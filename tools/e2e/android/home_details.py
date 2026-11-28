#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native V1 review details: compact local series and unavailable finish pace."""
import argparse
import json
from pathlib import Path
import sys
import time
sys.dont_write_bytecode=True
from run import Emulator


def review(d,out):
    out.mkdir(parents=True,exist_ok=True);d.wait_companion()
    d.command('SeriesUI.show("The Glass Orchard");return true');d.wait_projection()
    d.command('local h=HomeHost.active;assert(#h.series_result.next_books==0);assert(h.series_card_height==152);local found;local function visit(w) if type(w)~="table" then return end;if w.text=="Series on this device" then found=w end;for _,v in ipairs(w) do visit(v) end end;visit(h);assert(found);return true')
    d.command('UI:forceRePaint();return true');time.sleep(.5);d.shot(out/'series-local.png')
    d.command('Library.open({local_path="/storage/emulated/0/Books/001 Seedfall.epub"});return true')
    deadline=time.monotonic()+30
    while d.command('local ui=require("apps/reader/readerui").instance;return ui and ui.document and "ready" or "pending"')!='ready':
        if time.monotonic()>deadline:raise TimeoutError('synthetic book did not open')
        time.sleep(.2)
    d.command('local ui=require("apps/reader/readerui").instance;(ui.paging or ui.rolling):onGotoPage(ui.document:getPageCount());FinishUI.showSheet(ui,Library.nativeReader(ui));return true')
    deadline=time.monotonic()+30
    while d.command('local m=FinishUI.sheet.model;return not m.pending and m.book and m.book.cover_path and (not m.next or not m.next.local_path or m.next.book and m.next.book.cover_path) and "ready" or "pending"')!='ready':
        if time.monotonic()>deadline:raise TimeoutError('finish covers not ready')
        time.sleep(.2)
    d.command('UI:forceRePaint();return true');time.sleep(.5);d.shot(out/'end-of-book.png')
    d.command('local s=FinishUI.sheet;s.model.stats={available=false};s:build();local count=0;local function visit(w) if type(w)~="table" then return end;assert(w.text~="0 pp/h");if w.text=="—" then count=count+1 end;for _,v in ipairs(w) do visit(v) end end;visit(s);assert(count>=4);assert(CatalogUI.readingPace{available=false,pages_read=0,reading_seconds=3600}=="—");return true')
    d.command('UI:forceRePaint();return true');time.sleep(.5);d.shot(out/'end-empty.png')
    d.command('FinishUI.closeSheet();local ui=require("apps/reader/readerui").instance;if ui then ui:onClose() end;HomeHost.show();return true')
    (out/'details-tests.json').write_text(json.dumps({'assertions':['local series compact card','finish unavailable pace is a dash','zero measured pages never show 0 pp/h'],'screens':['series-local','end-of-book','end-empty']},indent=2)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();review(Emulator(a.serial),a.out)
