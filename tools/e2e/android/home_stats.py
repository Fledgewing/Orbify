#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native empty/50-day Stats acceptance, using an explicit synthetic KOReader DB."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
sys.dont_write_bytecode=True
from run import Emulator, PACKAGE


def install_statistics(d, source, empty=False):
    # Both processes are stopped before replacing this disposable emulator's DB;
    # no physical serial can pass Emulator's constructor.
    d.shell('am','force-stop','org.koreader.launcher')
    d.shell('am','force-stop',PACKAGE)
    with tempfile.TemporaryDirectory() as tmp:
        target=Path(tmp)/'statistics.sqlite3'
        with sqlite3.connect(source) as src, sqlite3.connect(target) as dst:
            src.backup(dst)
            dst.execute("PRAGMA journal_mode=DELETE")
            if empty:
                dst.execute('DELETE FROM page_stat_data');dst.execute('DELETE FROM book');dst.commit()
        src.close();dst.close()
        base='/sdcard/koreader/settings/statistics.sqlite3'
        d.shell('rm','-f',base+'-wal',base+'-shm')
        d.push(target,base)
    d.shell('am','start','-n',PACKAGE+'/.LauncherActivity')
    d.shell('am','start','-n','org.koreader.launcher/.MainActivity')
    d.wait_companion();d.dismiss_color_notice()
    d.command('Library.companion.setupLater();assert(HomeEditor.save(Layout.default()));Library.retry();HomeHost.show();HomeHost.active:turn(1);return true')
    d.wait_projection()


CHECK=r'''
local host=assert(HomeHost.active);local stats,metrics,battery
for _,v in pairs(host.presentation) do
    if v.p.widget=='year-in-reading' then stats=v.snapshot.data end
    if v.p.widget=='battery' then battery=v.snapshot end
end
assert(stats and stats.year and battery,'Stats/Battery projection not ready')
local p=Library.paint('home');metrics=p:widget('today'):read('reading.metrics',{limit=1});p:flush()
assert(metrics.metrics,'retained metrics not ready')
local BB=require('ffi/blitbuffer');local checked,texts=0,0
local ids={'year-in-reading','this-week','when-you-read','reading-records','today','reading-streak','reading-goal','pages-read','monthly-reading','battery'}
for _,id in ipairs(ids) do
    for _,span in ipairs(WidgetRegistry[id].sizes['android-tablet']) do
        -- Match the host's actual grid, including its inner card inset.
        local w=math.floor((1332-3*24)*span[1]/4+(span[1]-1)*24)-2
        local h=math.floor((1604-7*24)*span[2]/8+(span[2]-1)*24)-2
        local widget=id=='battery' and BatteryUI.widget({w=span[1],h=span[2]},battery,function() end,{w=w+2,h=h+2})
            or ReadingStatsWidgets.render(id,WidgetRegistry[id].dataNeeds[1].source=='reading.metrics' and metrics or stats,{w=w,h=h,rows=span[2]})
        local bb=BB.new(w+4,h+4,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);widget:paintTo(bb,1,1)
        assert(widget.stats_texts and #widget.stats_texts>0,id..' has no native text')
        for _,b in ipairs(widget.stats_texts) do
            local t=b.widget;assert(not t:isTruncated(),id..' truncated: '..t.text)
            assert(not t.text:find('…',1,true),id..' ellipsis: '..t.text);texts=texts+1
        end
        widget:free();bb:free();checked=checked+1
    end
end
-- The real page's boundary must not have hidden a renderer failure.
local function visit(w)
    if type(w)~='table' then return end
    assert(w.text~="Couldn't load this widget",'renderer fell back to an error card')
    for _,v in ipairs(w) do visit(v) end
end
visit(host)
return checked..' sizes; '..texts..' untruncated native labels; '..stats.year.days_read..' days'
'''


def review(d,out,source):
    out.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(source) as db:
        days=db.execute("SELECT COUNT(DISTINCT date(start_time,'unixepoch')) FROM page_stat").fetchone()[0]
    assert days==50, f'expected the 50-day synthetic DB, got {days}'
    receipt={'database_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'fixture_days':days,'native':{},'screens':[]}
    for empty in (True,False):
        state='empty' if empty else 'seeded'
        install_statistics(d,source,empty)
        deadline=time.monotonic()+30
        while True:
            try:
                result=d.command(CHECK)
                assert result.endswith('; 0 days') if empty else not result.endswith('; 0 days'),'statistics state not published'
                break
            except (RuntimeError,AssertionError):
                if time.monotonic()>deadline:raise
                time.sleep(.5);d.command('Library.retry();HomeHost.active:rebuild();return true');d.wait_projection()
        receipt['native'][state]=result
        d.command('Library.settings.write("last_sleep_sync",{at=os.time()-720,ok=true});HomeHost.active:rebuild();UI:forceRePaint();return true');time.sleep(.5)
        name='home-2-empty.png' if empty else 'home-2.png'
        d.shot(out/name);receipt['screens'].append(name)
        print(state+': '+result,flush=True)
    (out/'stats-tests.json').write_text(json.dumps(receipt,indent=2)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--statistics-db',type=Path,required=True)
    a=p.parse_args();review(Emulator(a.serial),a.out,a.statistics_db)
