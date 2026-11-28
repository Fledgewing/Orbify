#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native reader-only menus/navigation; every command targets a verified emulator."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import time
sys.dont_write_bytecode=True
from run import Emulator

def review(device,out):
    out.mkdir(parents=True,exist_ok=True)
    device.wait_companion()
    def wait(code):
        deadline=time.monotonic()+30
        while device.command(code)!="ready":
            if time.monotonic()>deadline: raise TimeoutError("native reader navigation did not complete")
            time.sleep(.2)
    def input_action(value,row,column):
        return ('local input=assert(ReaderPanel.sheet);'
                'if input.search_input then input.search_input:setText('+json.dumps(value,ensure_ascii=False)+');input.search_submit() '
                'else input.go_value='+json.dumps(value)+';input.go_percent='+('true' if column==2 else 'false')+';input.go_submit() end;return true')

    try:
        device.command('Library.companion.setupLater();ReaderPanel.close();Library._navReview={enabled=Library.readerMenusEnabled()};Library.open({local_path="/storage/emulated/0/Books/001 Seedfall.epub"});return true')
        wait('local ui=require("apps/reader/readerui").instance;return ui and ui.document and ui.document.file:find("001 Seedfall",1,true) and "ready" or "pending"')
        device.command('local t=Library._navReview;local ui=require("apps/reader/readerui").instance;t.ui=ui;t.tap=rawget(ui.menu,"onTapShowMenu");t.page=ui.document:getCurrentPage();t.pointer=ui.document:getXPointer();Library.setReaderMenus(ui,true);assert(ui.booksync_reader_menu_hooks and #ui.booksync_reader_menu_hooks.hooks>=4);ui.menu:onTapShowMenu();assert(ReaderPanel.sheet.screen=="reader-top-panel");return true')
        device.shot(out/"owned-tap-menu.png")
        device.command('ReaderPanel.close();local t=Library._navReview;assert(t.ui.document:getXPointer()==t.pointer);t.ui.config:onTapShowConfigMenu();assert(ReaderPanel.sheet.screen=="reader-bottom-panel");ReaderPanel.close();assert(t.ui.document:getXPointer()==t.pointer);return true')
        device.command('local t=Library._navReview;t.ui.menu:registerToMainMenu({addToMainMenu=function(_,items) items.booksync_e2e_plugin={text="Synthetic plugin action",callback=function() t.plugin=true end} end});t.ui.menu.tab_item_table=nil;t.ui.menu:onShowMenu(nil,true);assert(not ReaderPanel.sheet);assert(t.ui.menu.menu_items.booksync_e2e_plugin);t.ui.menu.menu_items.booksync_e2e_plugin.callback();assert(t.plugin);t.ui.menu:onCloseReaderMenu();ReaderPanel.stockMenu(t.ui.menu);return true')
        device.shot(out/"native-plugin-escape.png")
        device.command('local t=Library._navReview;t.ui.menu:onCloseReaderMenu();local ours=t.ui.menu.onTapShowMenu;local foreign=function() t.gesture=true;return true end;t.ui.menu.onTapShowMenu=foreign;t.ui.menu:onTapShowMenu();assert(t.gesture and not ReaderPanel.sheet);Library.setReaderMenus(t.ui,false);assert(t.ui.menu.onTapShowMenu==foreign);rawset(t.ui.menu,"onTapShowMenu",t.tap);Library.setReaderMenus(t.ui,true);return true')
        # Native TOC loading is explicitly invoked once. Owned paint thereafter
        # consumes only the native cached table and never calls fillToc itself.
        device.command('local ui=Library._navReview.ui;ui.toc:onShowToc();ui.toc.toc_menu.close_callback();ReaderPanel.navigation(ui,"contents");assert(ReaderPanel.sheet.screen=="reader-navigation");return true')
        device.shot(out/"contents.png")
        device.command('local ui=Library._navReview.ui;assert(#ui.toc.toc==5);local model=Library.readerWindow(ui,"contents",0,8);local expected=ui.toc.toc[2].xpointer;assert(Library.readerNavigate(ui,model.token,2));ReaderPanel.close();assert(ui.document:getPageFromXPointer(ui.document:getXPointer())==ui.document:getPageFromXPointer(expected));return true')
        device.command('local ui=Library._navReview.ui;ReaderPanel.goDialog(ui);return true')
        device.command(input_action("100",1,2))
        device.command('local ui=Library._navReview.ui;assert(ui.document:getCurrentPage()==ui.document:getPageCount());ReaderPanel.goDialog(ui);return true')
        device.command(input_action("1",1,1))
        device.command('local ui=Library._navReview.ui;assert(ui.document:getCurrentPage()==1);Library._navReview.bookmarked=ui.view.dogear_visible;if not Library._navReview.bookmarked then Library.readerAction(ui,"bookmark") end;ReaderPanel.navigation(ui,"annotations");assert(ReaderPanel.sheet.screen=="reader-navigation");return true')
        device.shot(out/"saved-items.png")
        device.command('ReaderPanel.close();local ui=Library._navReview.ui;if not Library._navReview.bookmarked then Library.readerAction(ui,"bookmark") end;ReaderPanel.searchDialog(ui);return true')
        device.command(input_action("orchard",1,1))
        wait('return ReaderPanel.sheet and ReaderPanel.sheet.screen=="reader-navigation" and Library._navReview.ui.booksync_search and #Library._navReview.ui.booksync_search.results>0 and "ready" or "pending"')
        device.shot(out/"search-results.png")
        device.command('local ui=Library._navReview.ui;local result=Library.readerWindow(ui,"search",0,8);assert(result.total>0 and result.total<=128);assert(Library.readerNavigate(ui,result.token,1));ReaderPanel.close();ReaderPanel.searchDialog(ui);return true')
        device.command(input_action("zzzz-no-native-match-zzzz",1,1))
        wait('return ReaderPanel.sheet and Library._navReview.ui.booksync_search.query=="zzzz-no-native-match-zzzz" and #Library._navReview.ui.booksync_search.results==0 and "ready" or "pending"')
        device.shot(out/"no-matches.png")
        device.command('ReaderPanel.close();local t=Library._navReview;Library.setReaderMenus(t.ui,false);t.ui.menu:onTapShowMenu();assert(not ReaderPanel.sheet and t.ui.menu.menu_container);t.ui.menu:onCloseReaderMenu();Library.setReaderMenus(t.ui,true);return true')
        device.command('local ui=Library._navReview.ui;local screen=require("device").screen;Library._navReview.rotation=screen:getRotationMode();ui:handleEvent(require("ui/event"):new("SetRotationMode",1));return true')
        device.command('local ui=Library._navReview.ui;local before=ui.document:getXPointer();ReaderPanel.navigation(ui,"contents");assert(ReaderPanel.sheet.plan.h<=ReaderPanel.sheet.screen_h);ReaderPanel.close();assert(ui.document:getXPointer()==before);return true')
        device.shot(out/"landscape-navigation.png")
        device.command('local t=Library._navReview;t.ui:handleEvent(require("ui/event"):new("SetRotationMode",t.rotation));return true')
        root=Path(__file__).resolve().parents[3]
        spec=importlib.util.spec_from_file_location("navigation_kit",root/"tools/e2e/kit.py")
        kit=importlib.util.module_from_spec(spec);sys.modules[spec.name]=kit;spec.loader.exec_module(kit)
        library=json.loads((root/"shared/fixtures/e2e/library.json").read_text())
        library.update(chapters=20,paragraphs_per_chapter=400)
        book={"title":"Navigation long","author":"Fixture","series":None,"index":None,"cover":False,"number":1000,"uuid":"urn:uuid:00000000-0000-4000-8000-000000000000"}
        long_book=out/"navigation-long.epub";long_book.write_bytes(kit.epub_bytes(book,library))
        device.shell("mkdir","-p","/sdcard/BookSync/E2E")
        device.push(long_book,"/sdcard/BookSync/E2E/navigation-long.epub")
        device.command('Library.open({local_path="/storage/emulated/0/BookSync/E2E/navigation-long.epub"});return true')
        wait('local ui=require("apps/reader/readerui").instance;return ui and ui.document and ui.document.file:find("navigation-long.epub",1,true) and "ready" or "pending"')
        device.command('local t=Library._navReview;t.ui=require("apps/reader/readerui").instance;t.long_returned=false;t.long_done=nil;t.pulse=false;local info=require("ui/widget/infomessage"):new{text="Searching… (tap to cancel)"};UI:show(info);assert(Library.readerSearch(t.ui,"long-query-with-no-match",info,function(done) assert(t.long_returned,"search blocked the caller");t.long_done=done;info.dismiss_callback=nil;UI:close(info) end));t.long_returned=true;UI:scheduleIn(0,function() t.pulse=true end);return true')
        wait('local t=Library._navReview;return t.pulse and t.long_done~=nil and "ready" or "pending"')
        device.command('assert(Library._navReview.long_done);ReaderPanel.searchDialog(Library._navReview.ui);return true')
        cancel=input_action("another-long-query-with-no-match",1,1).replace(';return true',';local info=UI:getTopmostVisibleWidget();assert(info.text=="Searching… (tap to cancel)");UI:close(info);assert(not ReaderPanel.sheet);return true')
        device.command(cancel)
        device.shot(out/"long-search-canceled.png")
        print("13 native reader navigation checks passed (tap panels, position, plugin escape, gesture ownership, Contents, page/percent, bookmarks, search, no matches, disable, landscape, long EPUB async search, cancel)",flush=True)
    except Exception:
        device.shot(out/"failure.png");raise
    finally:
        device.command('ReaderPanel.close();local t=Library._navReview;local ui=require("apps/reader/readerui").instance;if t then if t.rotation then ui:handleEvent(require("ui/event"):new("SetRotationMode",t.rotation)) end;Library.setReaderMenus(ui,t.enabled) end;Library._navReview=nil;return true')
        device.shell("am","force-stop","org.koreader.launcher")
        device.shell("am","start","-n","org.koreader.launcher/.MainActivity")

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--serial",required=True);p.add_argument("--out",type=Path,required=True)
    a=p.parse_args();review(Emulator(a.serial),a.out)
