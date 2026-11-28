#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Opt-in Home/editor acceptance on a disposable M8C-sized Android emulator."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import textwrap
import time
from PIL import Image, ImageDraw, ImageFont
sys.dont_write_bytecode=True
from run import Emulator, ROOT


def seed(device):
    spec=importlib.util.spec_from_file_location("kit",ROOT/"tools/e2e/kit.py")
    kit=importlib.util.module_from_spec(spec);sys.modules[spec.name]=kit;spec.loader.exec_module(kit)
    with tempfile.TemporaryDirectory() as directory:
        folder=Path(directory)/"Books";books=kit.generate(folder)
        for i,book in enumerate(books):
            sidecar=(folder/book["file"]).with_suffix(".sdr");sidecar.mkdir(exist_ok=True)
            props={"title":book["title"],"authors":book["author"],"series":book["series"],"series_index":book["index"]}
            fields=",".join(f'[{json.dumps(k)}]={json.dumps(v)}' for k,v in props.items() if v is not None)
            progress=[.62,.38,.81][i] if i<3 else 0
            status="reading" if i<3 else "complete" if i%7==0 else "new"
            (sidecar/"metadata.epub.lua").write_text('return {["doc_props"]={'+fields+'},["percent_finished"]='+str(progress)+',["summary"]={["status"]="'+status+'"}}')
            os.utime(sidecar/"metadata.epub.lua",(time.time()-i*86400,time.time()-i*86400))
            def font(size):
                for path in ("/System/Library/Fonts/Supplemental/Georgia.ttf","/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"):
                    try:return ImageFont.truetype(path,size)
                    except OSError:pass
                return ImageFont.load_default(size=size)
            background=0 if i%3==0 else 221 if i%3==1 else 119
            ink=255 if i%3==0 else 0
            image=Image.new("L",(360,540),background);draw=ImageDraw.Draw(image)
            draw.rounded_rectangle((8,8,351,531),radius=4,outline=ink,width=2)
            if i%3==0:draw.arc((110,270,250,410),35,315,fill=ink,width=3)
            elif i%3==1:draw.polygon([(0,440),(90,300),(170,400),(230,250),(360,430),(360,540),(0,540)],fill=51)
            else:
                for offset in range(-540,360,22):draw.line((offset,0,offset+540,540),fill=221,width=9)
                draw.rectangle((20,90,340,230),fill=0);ink=255
            for j,line in enumerate(textwrap.wrap(book["title"],18)[:4]):draw.text((180,110+j*42),line,font=font(34),fill=ink,anchor="mt")
            draw.text((180,495),book["author"],font=font(16),fill=ink,anchor="mt")
            image.save(sidecar/"cover.png")
        (folder/".booksync-home-fixture").write_text("Synthetic Home fixture only\n")
        device.push(folder,"/sdcard/")


def review(device,out,seed_books=True):
    out.mkdir(parents=True,exist_ok=True)
    assert device.shell("wm","size").splitlines()[-1].endswith("1404x1872"), "configure the M8C resolution first"
    assert device.shell("wm","density").splitlines()[-1].endswith(": 300"), "configure 300 dpi first"
    if seed_books:seed(device)
    device.shell("settings","put","system","screen_off_timeout","2147483647")
    device.shell("svc","power","stayon","true")
    device.shell("input","keyevent","224")
    device.wait_companion();device.dismiss_color_notice()
    device.command('Library.companion.setupLater();Library.settings.write("news_012_pending",false);return true')
    device.command('AccountView.open();AccountView.active:command("account.signIn",{server="https://fixture.example.test",username="reader",password="fixture"});return true')
    deadline=time.monotonic()+20
    while device.command('return AccountView.active.state.signedIn and "ready" or "pending"')!="ready":
        if time.monotonic()>deadline:raise TimeoutError("fixture sign-in")
        time.sleep(.2)
    device.command('AccountView.active:close();assert(HomeEditor.save(Layout.default()));Library.settings.write("last_sleep_sync",{at=os.time()-720,ok=true});Library.retry();HomeHost.show();assert(HomeHost.document().pages[1].placements[2].h==2);return true')
    device.wait_projection()
    device.command("UI:forceRePaint();return true")
    deadline=time.monotonic()+20
    while device.command('local n=0;local function visit(w) if type(w)~="table" then return end;if w.coverExpected and not w.coverReady then n=n+1 end;for _,c in ipairs(w) do visit(c) end end;visit(HomeHost.active);return n')!="0":
        if time.monotonic()>deadline:raise TimeoutError("expected fixture covers did not paint")
        time.sleep(.2)
    device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"home-1.png")
    device.command('assert(HomeHost.active.library_total==59);HomeHost.active:turn(1);return true')
    device.wait_projection();device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"home-2.png")
    device.command('HomeHost.active:turn(-1);HomeEditor.show(HomeHost.active);local e=top();e.model.selected="resume";e:rebuild();return true')
    device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"editor.png")
    device.command('local e=top();local before=HomeHost.active.metrics.roundTrips;e:pick();assert(e.metrics.network==0 and e.metrics.roundTrips==0);assert(HomeHost.active.metrics.roundTrips==before);return true')
    device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"picker.png")
    # Exercise the model through the same callbacks as the native editor controls.
    device.command('click("Close");local e=top();e.model.selected="resume";e:rebuild();local revision=e.model.document.revision;click("↓");assert(e.model.document.revision==revision+1);click("↑");e.model.selected="resume";e:rebuild();click("Size");return true')
    device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"editor-sizes.png")
    device.command('local e=top();assert(e.model.selected=="resume");click("Done");assert(Layout.editorPage(HomeHost.document(),1).placements[1].h==2);return true')
    device.wait_projection();device.command("UI:forceRePaint();return true");time.sleep(.5);device.shot(out/"editor-saved.png")
    # Restore the default fixture layout after verifying persistence.
    device.command('assert(HomeEditor.save(Layout.default()));HomeHost.show();return true')
    device.wait_projection()
    device.command('local entry=assert(HomeHost.active.presentation.want);local saved=assert(entry.snapshot.items[1]);local row={key=saved.key,title=saved.title,authors=saved.authors,cover_path=assert(saved.cover_path)};local old=HomeWidgets.preview;HomeWidgets.preview=true;local ok,w=pcall(HomeWidgets.card,{widget="booklist",w=2,h=2,settings={title="Want to read",style=0}},{state="ready",items={row},count=1,total=1,bytes=0},function() end,{w=654,h=382});HomeWidgets.preview=old;assert(ok,w);local BB=require("ffi/blitbuffer");local bb=BB.new(670,398,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,8,8);bb:writeToFile("/sdcard/koreader/e2e-home-remote.png");bb:free();w:free();return true')
    device.adb("pull","/sdcard/koreader/e2e-home-remote.png",str(out/"remote-cover.png"))
    (out/"home-tests.json").write_text(json.dumps({"screens":["home-1","home-2","editor","picker","editor-sizes","editor-saved"],"render":"native KOReader","emulator":device.serial,"size":[1404,1872],"dpi":300,"server":"opt-in fake ServerAdapter","assertions":["59-book fixture","editor/picker zero queries","move revision","resize persisted","remote cover badge"]},indent=2)+"\n")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--serial",required=True);p.add_argument("--out",type=Path,required=True);p.add_argument("--skip-seed",action="store_true")
    a=p.parse_args();review(Emulator(a.serial),a.out,not a.skip_seed)
