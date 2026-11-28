#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reader-inline status/helpers and explicit system return on a disposable emulator only."""
import argparse
import json
from pathlib import Path
import re
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
sys.dont_write_bytecode = True
from run import Emulator, PACKAGE


def review(device, out):
    out.mkdir(parents=True, exist_ok=True)
    pref="shared_prefs/orbit.xml"
    saved=device.shell("run-as",PACKAGE,"cat",pref)
    evidence=[]
    def check(name, code):
        result=device.command(code)
        device.shot(out/(name+".png"))
        evidence.append({"check":name,"result":result})
        (out/"reader-companion.json").write_text(json.dumps(evidence,indent=2)+"\n")
        print(name,flush=True)
    def wait(code, timeout=20):
        deadline=time.monotonic()+timeout
        while device.command(code)!="ready":
            if time.monotonic()>deadline: raise TimeoutError(code)
            time.sleep(.2)
    def configure(mode, protected=False):
        book=device.command('local ui=liveUI();return ui and ui.document and ui.document.file or ""')
        xml=ET.fromstring(saved)
        values={"orbit_mode":("string",mode),"setup_later_until":("long","9000000000000000"),
                "helper_wifi":("boolean","false"),"helper_sleep_sync":("boolean","false"),
                "helper_screen_off":("boolean","false"),"helper_pin":("boolean",str(protected).lower()),
                "pin_hash":("string","synthetic-test-lock" if protected else "")}
        for name,(kind,value) in values.items():
            for node in list(xml):
                if node.get("name")==name: xml.remove(node)
            node=ET.SubElement(xml,kind,{"name":name})
            if kind=="string": node.text=value
            else: node.set("value",value)
        store(ET.tostring(xml,encoding="unicode"))
        if book:
            # Android may kill provider clients when this test force-stops the companion.
            # A fixture-mode change starts a new reader lifetime. Actual permission return
            # tests below never reopen a book or restore a page to satisfy an assertion.
            device.command('Library.companion.setupLater();local w=top();if w and type(w.text)=="string" and w.text:find("setup steps",1,true) then click("Later") end;Library.open({local_path='+json.dumps(book)+'});return true')
            wait('return liveUI() and liveUI().document and liveUI().document.file=='+json.dumps(book)+' and "ready" or "pending"')
            wait('return not Net.inflight and not ReadingSync.busy and "ready" or "pending"')
            # Settle the fixture's independent remote-ahead consent before starting
            # the next return-ticket case; never do this during a permission return.
            device.command('if PositionPrompt.current then click("No") end;assert(not PositionPrompt.current);Library._readerCompanionReviewPage=liveUI().document:getCurrentPage();return true')
    def store(value):
        device.shell("am","force-stop",PACKAGE)
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/"orbit.xml";source.write_text(value)
            device.push(source,"/data/local/tmp/booksync-reader-companion-prefs.xml")
        device.shell("run-as",PACKAGE,"cp","/data/local/tmp/booksync-reader-companion-prefs.xml",pref)
        device.shell("am","start","-W","-n",PACKAGE+"/.StatusActivity")
        device.shell("am","start","-W","-n","org.koreader.launcher/.MainActivity")
        device.wait_companion()
    def callback(id):
        return 'local v=assert(ReaderCompanionView.active);for _,r in ipairs(v.dialog.buttons) do if r[1].id=="'+id+'" then assert(r[1].enabled~=false);r[1].callback();return true end end;error("missing control")'
    def helpers_ready():
        wait('local v=ReaderCompanionView.active;return v and v.dialog and not v.busy and v.page=="helpers" and "ready" or "pending"')
    try:
        device.wait_companion()
        device.command('if ReaderCompanionView.active then ReaderCompanionView.active:close() end;while SettingsView.active do local v=SettingsView.active;v.onBack=nil;v:close() end;local w=top();if w and type(w.text)=="string" and w.text:find("setup steps",1,true) then click("Later") end;Library.companion.setupLater();Library.open({local_path="/storage/emulated/0/Books/001 Seedfall.epub"});return true')
        wait('return liveUI() and liveUI().document and liveUI().document.file:find("Seedfall",1,true) and "ready" or "pending"')
        configure("full")
        # Position consent is an allowed reader action, separate from these sheets.
        # Settle it before recording the page that system-action return must preserve.
        wait('return not Net.inflight and not ReadingSync.busy and "ready" or "pending"')
        accepted=device.command('if PositionPrompt.current then Library._readerCompanionExpectedPage=Library.position.geometry({remote={percentage=0.5}},liveUI(),"reading").remote_page;click("Yes");return "accepted" end;return "none"')
        if accepted=="accepted":
            wait('return liveUI().document:getCurrentPage()==Library._readerCompanionExpectedPage and "ready" or "pending"')
        device.command('assert(not PositionPrompt.current);Library._readerCompanionExpectedPage=nil;Library._readerCompanionReviewPage=liveUI().document:getCurrentPage();return true')
        check("full-reader-status",'plugin:onOrbitOpenCompanion();local v=assert(ReaderCompanionView.active);assert(top()==v.dialog and v.page=="status");assert(#v.dialog.buttons<=9);return v.dialog.title')
        check("full-reader-helpers",callback("helpers")+'\n')
        device.command('local v=ReaderCompanionView.active;assert(v.snapshot.mode=="full");assert(v.snapshot.helpers[1].on and not v.snapshot.helpers[1].mutable);v:close();return true')
        configure("addon")
        check("addon-reader-helpers",'ReaderCompanionView.open("helpers");local v=ReaderCompanionView.active;assert(v.snapshot.mode=="add-on");assert(not v.snapshot.helpers[1].on and not v.snapshot.helpers[2].on);assert(not v.snapshot.helpers[3].mutable);return true')
        for helper,index in (("wifi",1),("sleep",2)):
            device.command(callback(helper));helpers_ready()
            check(helper+"-explicit-on",'assert(ReaderCompanionView.active.snapshot.helpers['+str(index)+'].on);return true')
            device.command(callback(helper));helpers_ready()
            check(helper+"-explicit-off",'assert(not ReaderCompanionView.active.snapshot.helpers['+str(index)+'].on);return true')
        check("permission-explanation",callback("review"))
        check("permission-later",callback("later"))
        device.command(callback("review"))
        device.command(callback("permission"))
        # Android's actual device-admin consent is visible only after the explicit button.
        deadline=time.monotonic()+20
        while "DeviceAdminAdd" not in device.shell("dumpsys","window"):
            if time.monotonic()>deadline: raise TimeoutError("Android permission activity did not open")
            time.sleep(.2)
        device.shot(out/"android-permission-explicit.png")
        device.shell("input","keyevent","4")
        helpers_ready()
        check("permission-denied-return",'local v=ReaderCompanionView.active;assert(not v.snapshot.helpers[3].permission and not v.snapshot.helpers[3].on);assert(v.context.document==liveUI().document);assert(liveUI().document:getCurrentPage()==Library._readerCompanionReviewPage);return true')
        # Request again and grant via Android's native consent button.
        device.command(callback("review"));device.command(callback("permission"))
        deadline=time.monotonic()+20
        while True:
            device.shell("uiautomator","dump","/sdcard/booksync-reader-permission.xml")
            tree=ET.fromstring(device.shell("cat","/sdcard/booksync-reader-permission.xml"))
            node=next((n for n in tree.iter("node") if "activate" in n.get("text","").lower() and "deactivate" not in n.get("text","").lower()),None)
            if node is not None: break
            if time.monotonic()>deadline: raise TimeoutError("Android Activate button missing")
            time.sleep(.2)
        x1,y1,x2,y2=map(int,re.findall(r"\d+",node.get("bounds")))
        device.shell("input","tap",str((x1+x2)//2),str((y1+y2)//2))
        helpers_ready()
        check("permission-granted-still-off",'local v=ReaderCompanionView.active;assert(v.snapshot.helpers[3].permission);assert(not v.snapshot.helpers[3].on and not v.snapshot.helpers[2].on);return true')
        device.command('ReaderCompanionView.active:close();return true')
        # Revocation changes observed state only; it must not create a new reader sheet.
        device.shell("am","start","-W","-n",r"com.android.settings/.Settings\$DeviceAdminSettingsActivity")
        def tap_native(fragment):
            deadline=time.monotonic()+20
            while True:
                device.shell("uiautomator","dump","/sdcard/booksync-reader-permission.xml")
                tree=ET.fromstring(device.shell("cat","/sdcard/booksync-reader-permission.xml"))
                node=next((n for n in tree.iter("node") if fragment.lower() in n.get("text","").lower()),None)
                if node is not None: break
                if time.monotonic()>deadline: raise TimeoutError("native control missing: "+fragment)
                time.sleep(.2)
            x1,y1,x2,y2=map(int,re.findall(r"\d+",node.get("bounds")))
            device.shell("input","tap",str((x1+x2)//2),str((y1+y2)//2))
        tap_native("BookSync Companion")
        tap_native("Deactivate")
        device.shell("am","start","-W","-n","org.koreader.launcher/.MainActivity")
        check("background-revocation-silent",'assert(not ReaderCompanionView.active);local s=Library.companion.snapshot();assert(not s.helpers[3].permission);assert(not ReaderCompanionView.active);return true')
        configure("addon",protected=True)
        device.command('ReaderCompanionView.open("helpers");local v=ReaderCompanionView.active;assert(v.snapshot.protected);return true')
        check("protected-departure",callback("wifi"))
        tap_native("Settings are locked")
        device.shot(out/"protected-native-parent-settings.png")
        device.shell("input","keyevent","4");helpers_ready()
        check("protected-return-context",'local v=ReaderCompanionView.active;assert(v.context.document==liveUI().document);assert(not v.snapshot.helpers[1].on);v:close();return true')
        configure("addon")
        # A changed book retires the return ticket even if it reuses the same ReaderUI.
        device.command('ReaderCompanionView.open("helpers");ReaderCompanionView.active:external("protected");return true')
        device.shell("am","start","-W","-n","org.koreader.launcher/.MainActivity")
        device.command('assert(Library.open({local_path="/storage/emulated/0/Books/002 The Pruning.epub"}));return true')
        wait('return liveUI() and liveUI().document and liveUI().document.file:find("Pruning",1,true) and "ready" or "pending"')
        check("another-book-drops-return",'assert(not ReaderCompanionView.active);return true')
        print(str(len(evidence))+" native reader companion checks passed",flush=True)
    except Exception:
        device.shot(out/"failure.png")
        raise
    finally:
        store(saved)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial",required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args();review(Emulator(args.serial),args.out)
