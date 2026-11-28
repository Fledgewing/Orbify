#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Android emulator-only native KOReader review driver. No unqualified adb calls."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import zipfile
import uuid

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = "net.fledgewing.orbitcompanion"

class Emulator:
    def __init__(self, serial):
        if not re.fullmatch(r"emulator-\d+", serial):
            raise ValueError("an explicit emulator-N serial is required")
        self.serial=serial
        if self.adb("shell", "getprop", "ro.kernel.qemu").strip() != b"1":
            raise ValueError("target does not identify itself as an emulator")
    def adb(self,*args):
        return subprocess.check_output(["adb","-s",self.serial,*map(str,args)],stderr=subprocess.PIPE,timeout=60)
    def shell(self,*args):
        return self.adb("shell",*args).decode().strip()
    def push(self,path,destination):
        self.adb("push",path,destination)
    def wait_driver(self,timeout=20):
        # Reader -> FileManager retires one plugin instance before loading the
        # next. Wait for that lifecycle boundary without replaying any UI action.
        deadline=time.monotonic()+timeout
        while True:
            try:
                self.command('return true')
                return
            except RuntimeError as error:
                if not str(error).endswith('plugin not loaded'):raise
                if time.monotonic()>=deadline:raise TimeoutError('plugin did not load after native navigation') from error
                time.sleep(.2)

    def wait_companion(self,timeout=20):
        deadline=time.monotonic()+timeout
        while self.command('return Companion.workerProblem()==nil and "ready" or "pending"')!="ready":
            if time.monotonic()>=deadline: raise TimeoutError("matching companion status was not published")
            time.sleep(.2)
    def wait_projection(self,timeout=20):
        # Wait for the visible screen, including Home's materialized widget rows.
        # Advancing while those rows are Loading queues unrelated cold work ahead
        # of the next screen and makes screenshots claim readiness too early.
        code=('local h=HomeHost.active;local front=top();local pending=AccountView.active and AccountView.active.busy;'
              'if h and front==h then if h.series_key then pending=pending or h.series_result and h.series_result.pending;'
              'elseif h.list_layout then pending=pending or h.list_result and h.list_result.pending;'
              'else for _,raw in pairs(h.signatures or {}) do local r=Cache.decode(raw);if type(r)=="table" and r.pending then pending=true end end end end;'
              'return pending and "pending" or "ready"')
        deadline=time.monotonic()+timeout
        while self.command(code)!="ready":
            if time.monotonic()>deadline:raise TimeoutError("Visible screen projection did not publish")
            time.sleep(.2)

    def dismiss_color_notice(self):
        # KOReader's one-time native color notice can cover a fresh profile's Home.
        # Dismiss only that exact notice, never an arbitrary dialog or reader sheet.
        return self.command('local w=top();if w and type(w.text)=="string" and w.text:find("Documents will be rendered in color on this device.",1,true)==1 then UI:close(w);return "dismissed" end;return "absent"')

    def command(self,code,timeout=20):
        request_id=uuid.uuid4().hex
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"command.lua";path.write_text("-- booksync-request:"+request_id+"\n"+code)
            self.push(path,"/sdcard/koreader/e2e-pending.lua")
            self.shell("mv","/sdcard/koreader/e2e-pending.lua","/sdcard/koreader/e2e-command.lua")
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            try: result=self.shell("cat","/sdcard/koreader/e2e-result")
            except subprocess.CalledProcessError: result=""
            if result.startswith("FAIL "+request_id+"\n"):
                raise RuntimeError(result.split("\n",1)[1])
            if result.startswith("OK "+request_id+"\n"):
                return result.split("\n",1)[1]
            time.sleep(.2)
        raise TimeoutError("KOReader test driver did not respond")
    def shot(self,path):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(self.adb("exec-out","screencap","-p"))

def setup(device, apk, koreader, apksigner):
    # Reuse package.sh's version stamp, schema, credits and battery assets. This is the
    # debug counterpart of sideload-android.sh's APK install + whole plugin replacement.
    cert=subprocess.check_output([str(apksigner),"verify","--print-certs",str(apk)],text=True)
    digest=re.search(r"certificate SHA-256 digest: ([a-fA-F0-9]{64})",cert).group(1).upper()
    pin=":".join(digest[i:i+2] for i in range(0,64,2))
    device.adb("install","-r",koreader);device.adb("install","-r","-t",apk)
    device.shell("appops","set","org.koreader.launcher","MANAGE_EXTERNAL_STORAGE","allow")
    for permission in ("READ_EXTERNAL_STORAGE","WRITE_EXTERNAL_STORAGE"):
        device.shell("pm","grant",PACKAGE,"android.permission."+permission)
    # A fresh APK has not run its first-launch initialization/status publication yet.
    device.shell("am","start","-W","-n",PACKAGE+"/.LauncherActivity")
    device.shell("am","force-stop","org.koreader.launcher")
    with tempfile.TemporaryDirectory() as directory:
        work=Path(directory)
        subprocess.run(["bash",str(ROOT/"android/koreader/package.sh"),"shared",str(work/"plugin.zip")],check=True,capture_output=True)
        with zipfile.ZipFile(work/"plugin.zip") as archive: archive.extractall(work)
        policy=work/"orbit.koplugin/ko/companion.lua"
        source=policy.read_text()
        source,count=re.subn(r'\["(?:[0-9A-F]{2}:){31}[0-9A-F]{2}"\] = true',f'["{pin}"] = true',source)
        if count != 1: raise ValueError("expected one release signer in staged test copy")
        policy.write_text(source)
        # The deterministic fixture clock must be shared by both halves of a grant.
        # Inject only into the staged emulator plugin; paint reads a memo, never a file.
        reminders=work/"orbit.koplugin/ko/library_reminders.lua"
        text=reminders.read_text()
        text=text.replace("return (time.boottime and time.to_s(time.boottime()) or now_s())*1000", "return R.clockMemo or (time.boottime and time.to_s(time.boottime()) or now_s())*1000")
        text=text.replace('return Library.remindersCommand(op,args or {},done or function() end)', 'return Library.remindersCommand(op,args or {},function(result) R.clockMemo=result.clockElapsed or R.clockMemo;if done then done(result) end end)')
        reminders.write_text(text)
        device.shell("mkdir","-p","/sdcard/koreader/plugins","/sdcard/koreader/patches","/sdcard/Books")
        device.shell("rm","-rf","/sdcard/koreader/plugins/orbit.koplugin")
        device.push(work/"orbit.koplugin","/sdcard/koreader/plugins/")
        spec=importlib.util.spec_from_file_location("kit",ROOT/"tools/e2e/kit.py")
        kit=importlib.util.module_from_spec(spec);sys.modules[spec.name]=kit;spec.loader.exec_module(kit)
        books=kit.generate(work/"Books")
        for i,book in enumerate(books):
            path=work/"Books"/book["file"]
            sidecar=path.with_suffix(".sdr");sidecar.mkdir()
            # Only synthetic sidecars: enables realistic saved/offline projections before
            # each book is opened. Same EPUB generator as the emulated server kit.
            props={"title":book["title"],"authors":book["author"],"series":book["series"],"series_index":book["index"]}
            fields=",".join(f'[{json.dumps(k)}]={json.dumps(v)}' for k,v in props.items() if v is not None)
            (sidecar/"metadata.epub.lua").write_text('return {["doc_props"]={'+fields+'},["percent_finished"]='+str(.2 if i<2 else 0)+',["summary"]={["status"]="'+('reading' if i<2 else 'new')+'"}}')
        device.push(work/"Books","/sdcard/")
    device.push(Path(__file__).with_name("driver.lua"),"/sdcard/koreader/patches/2-booksync-e2e.lua")
    device.shell("settings","put","secure","immersive_mode_confirmations","confirmed")
    device.shell("am","start","-n","org.koreader.launcher/.MainActivity")

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial",required=True)
    commands=parser.add_subparsers(dest="action",required=True)
    install=commands.add_parser("setup")
    for name in ("apk","koreader","apksigner"): install.add_argument("--"+name,type=Path,required=True)
    call=commands.add_parser("command");call.add_argument("code")
    shot=commands.add_parser("shot");shot.add_argument("path",type=Path)
    args=parser.parse_args();device=Emulator(args.serial)
    if args.action=="setup": setup(device,args.apk,args.koreader,args.apksigner)
    elif args.action=="command": print(device.command(args.code))
    else: device.shot(args.path)

if __name__=="__main__": main()
