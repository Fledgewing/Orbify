#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native catalog/finish regression and M8C visual proof, on a dedicated emulator.

Run setup and seed saved covers first. All main captures use the fixture companion.
The extra remote-series specimen changes only a bounded adapter response, making
unavailable remote states reviewable without HTTP, device access or another renderer.
"""
import argparse
import json
from pathlib import Path
import sys
import time
sys.dont_write_bytecode = True
from run import Emulator


def review(d, out):
    out.mkdir(parents=True, exist_ok=True)
    d.wait_companion()
    d.dismiss_color_notice()
    d.shell("svc", "wifi", "disable")
    d.shell("svc", "data", "disable")
    d.shell("am", "start", "-n", "org.koreader.launcher/.MainActivity")
    d.command('Library.companion.setupLater();AccountView.open();AccountView.active:command("account.signIn",{server="https://fixture.example.test",username="reader",password="fixture"});return true')
    d.wait_projection()
    d.command('assert(AccountView.active.state.signedIn);AccountView.active:close();return true')
    evidence = []

    def step(name, code, ready=None):
        d.command(code)
        d.wait_projection()
        if ready:
            deadline = time.monotonic() + 20
            while d.command(ready) != "ready":
                if time.monotonic() > deadline:
                    raise TimeoutError(name + " projection did not publish")
                time.sleep(.2)
        time.sleep(.3)
        d.shot(out / (name + ".png"))
        evidence.append(name)
        (out / "catalog-ui.json").write_text(json.dumps(evidence, indent=2) + "\n")

    step("library", 'HomeHost.show();HomeHost.active:showList("Library","all",{sort="title"});return true')
    d.command('local h=HomeHost.active;assert(h.list_limit==15);assert(#h.list_result.items==15);assert(h.list_result.total==59);assert(h.metrics.roundTrips<=1);return true')
    first = d.command('return HomeHost.active.list_result.items[1].key')
    step("library-page-2", 'HomeHost.active:listPage(1);return true')
    d.command('local h=HomeHost.active;assert(h.list_layout.pages[1].placements[1].settings.offset==15);return true')
    d.command('HomeHost.active:listPage(-1);return true')
    d.wait_projection()
    assert d.command('return HomeHost.active.list_result.items[1].key') == first
    step("filter", 'HomeHost.active.filter:show();return true',
         'return HomeHost.active.filter.total~=nil and "ready" or "pending"')
    step("filter-show", 'click("Show");return true',
         'local f=HomeHost.active.filter;return f.model.pick=="show" and not f:read().pending and "ready" or "pending"')
    d.command('local f=HomeHost.active.filter;local r=f:read();for _,o in ipairs(r.items) do if o.value=="unread" then f.model:choose("show",o);f.model.pick=nil;f:changed();return true end end;error("unread facet missing")')
    step("filter-selected", 'return true',
         'return HomeHost.active.filter.total~=nil and "ready" or "pending"')
    step("filter-sort", 'click("Group & sort");return true')
    d.command('local f=HomeHost.active.filter;f:back();f:close(true);return true')
    d.wait_projection()
    d.command('assert(HomeHost.active.filter.model.query.show=="unread");return true')
    step("library-by-author", 'HomeHost.active:showList("Library","all",{group="author"});return true')
    step("library-by-series", 'HomeHost.active:showList("Library","all",{group="series"});return true')
    d.command('local h=HomeHost.active;assert(h.list_result.items[1].books[1].cover_path);assert(h.metrics.rows<=32);return true')
    step("series", 'SeriesUI.show("The Glass Orchard");return true')
    d.command('assert(#HomeHost.active.series_result.items==5);assert(HomeHost.active.caps.series.downloadNext);return true')
    # A bounded saved response specimen proves the remote next-three state and its
    # real callback. Production selection and membership remain companion-owned.
    step("series-next-three", '''local h=HomeHost.active;local value=Layout.copy(h.series_result)
value.items[1].dot="read";value.items[1].status_text="Read · ★★★★★"
value.items[2].dot="reading";value.items[2].progress=62
value.dots={"read","reading","unread","unread","unread"};value.next_books={}
for i=3,5 do local b=value.items[i];b.local_path=nil;b.on_device=false;b.dot="unread";b.status_text="On server";value.next_books[#value.next_books+1]=Layout.copy(b) end
value.subtitle="Ada Quill · 5 books · 1 read, 1 reading";value.row_count=9
local read=LibraryAdapter.read;LibraryAdapter.read=function(raw) local a=Cache.decode(raw);if a.op=="series" then return value,#UIUtil.encode(value) end;return read(raw) end
local worked,why=pcall(function() h:rebuild();UI:setDirty(h,"ui") end);if not worked then LibraryAdapter.read=read;error(why) end;h.v3_review_read=read
local download=SeriesUI.download;local called=0;SeriesUI.download=function(host) assert(host==h);called=called+1 end
click("Download next 3");SeriesUI.download=download;assert(called==1);return true''')
    d.command('local h=HomeHost.active;LibraryAdapter.read=h.v3_review_read;h.v3_review_read=nil;return true')
    step("storage", 'StorageUI.show();return true',
         'return StorageUI.active.data.pending and "pending" or "ready"')
    d.command('assert(StorageUI.active.metrics.rows==1);StorageUI.active:onClose();return true')
    d.command('Library.open({local_path="/storage/emulated/0/Books/001 Seedfall.epub"});return true')
    deadline=time.monotonic()+20
    while d.command('local ui=require("apps/reader/readerui").instance;return ui and ui.document and "ready" or "pending"')!="ready":
        if time.monotonic()>deadline: raise TimeoutError("synthetic book did not open")
        time.sleep(.2)
    step("end-of-book", '''local ui=require("apps/reader/readerui").instance;
(ui.paging or ui.rolling):onGotoPage(ui.document:getPageCount());local b=Library.nativeReader(ui)
if b.summary.rating then FinishUI.actions.star(ui,b,b.summary.rating) end
FinishUI.showSheet(ui,Library.nativeReader(ui));return true''',
         'local m=FinishUI.sheet.model;return not m.pending and m.book and m.book.cover_path and (not m.next or not m.next.local_path or m.next.book and m.next.book.cover_path) and "ready" or "pending"')
    d.command('local s=FinishUI.sheet;assert(s.model.book.cover_path);assert(s.model.next.book.cover_path);assert(s.sheet_h<s.screen_h);return true')
    step("end-rated", 'click("Rate 4");return true',
         'local m=FinishUI.sheet.model;return not m.pending and m.book and m.book.cover_path and (not m.next or not m.next.local_path or m.next.book and m.next.book.cover_path) and "ready" or "pending"')
    # Fixture server may reject rating writes; native local rating remains authoritative.
    d.command('local s=FinishUI.sheet;assert(s.ui.doc_settings:readSetting("summary").rating==4);return true')
    # Taps outside close the actual EndSheet; its parent Reader/Custom layouts stay separate.
    d.command('local s=FinishUI.sheet;s:onTapAnywhere(nil,{pos={y=0}});assert(not FinishUI.sheet);assert(not FinishUI.sheet_retry);return true')
    step("end-reopened", 'local ui=require("apps/reader/readerui").instance;FinishUI.showSheet(ui,Library.nativeReader(ui));return true',
         'local m=FinishUI.sheet.model;return not m.pending and m.book and m.book.cover_path and (not m.next or not m.next.local_path or m.next.book and m.next.book.cover_path) and "ready" or "pending"')
    d.command('FinishUI.closeSheet();return true')
    return evidence


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--serial", required=True)
    p.add_argument("--out", required=True, type=Path)
    a = p.parse_args()
    review(Emulator(a.serial), a.out)
