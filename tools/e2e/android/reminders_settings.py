#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Additional native reminder render/input states and explicit SLEEP_NOW, emulator only."""
import argparse
from datetime import datetime
from zoneinfo import ZoneInfo
import json
from pathlib import Path
import re
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
sys.dont_write_bytecode=True
from run import Emulator


def companion_information(device,out,checks):
    # Use the public launcher and normal Settings navigation; the section Activity
    # deliberately is not exported and must never be opened directly by adb.
    def node(text):
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            device.shell('uiautomator','dump','/sdcard/booksync-reminders-ui.xml')
            tree=ET.fromstring(device.shell('cat','/sdcard/booksync-reminders-ui.xml'))
            found=next((n for n in tree.iter('node') if n.get('text')==text),None)
            if found is not None and found.get('bounds')!='[0,0][0,0]':return found
            # Shared companion type keeps its floor; lower information rows scroll.
            device.shell('input','swipe','700','1550','700','450','250')
            time.sleep(.2)
        raise AssertionError('missing native companion text: '+text)
    def tap(text):
        bounds=node(text).get('bounds')
        x1,y1,x2,y2=map(int,re.findall(r'\d+',bounds))
        device.shell('input','tap',str((x1+x2)//2),str((y1+y2)//2))
    device.shell('am','start','-W','-f','0x14000000','-n','net.fledgewing.orbitcompanion/.LauncherActivity')
    tap('Settings');tap('Reading and Home')
    node('Reminders');node('Set reminders in BookSync reader settings')
    device.shot(out/'companion-information-row.png')
    if 'companion-information-row' not in checks:checks.append('companion-information-row')
    (out/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')


def review(device,out):
    out.mkdir(parents=True,exist_ok=True)
    checks=[]
    zone=ZoneInfo(device.shell('getprop','persist.sys.timezone') or 'UTC')
    wall,elapsed=map(int,device.shell('cat','/sdcard/koreader/settings/e2e-reminder-clock').split()[:2])
    def clock(ms=0,fail_sleep=0):
        nonlocal wall,elapsed
        wall+=ms;elapsed+=ms
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'clock';p.write_text(f'{wall} {elapsed} 0 {fail_sleep}')
            device.push(p,'/sdcard/koreader/settings/e2e-reminder-clock.new')
            device.shell('mv','/sdcard/koreader/settings/e2e-reminder-clock.new','/sdcard/koreader/settings/e2e-reminder-clock')
    def minute():
        d=datetime.fromtimestamp(wall/1000,zone);return d.hour*60+d.minute
    def wait(code):
        deadline=time.monotonic()+30
        while device.command(code)!='ready':
            if time.monotonic()>deadline:raise TimeoutError(code)
            time.sleep(.1)
    def check(name,code='return true'):
        device.command(code);device.shot(out/(name+'.png'));checks.append(name)
        (out/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    def invoke(op,args='{}'):
        device.command('local args='+args+';Library._extraReminder=nil;Library.remindersCommand('+json.dumps(op)+',args,function(r) Library._extraReminder=r end);return true')
        wait('return Library._extraReminder and "ready" or "pending"')
        device.command('assert(not Library._extraReminder.error,Library._extraReminder.error);return true')
    def row(i):
        device.command('local v=SettingsView.active;local n=v.screen=="reminders-list" and 4 or 8;local i='+str(i)+';v.offset=math.floor((i-1)/n)*n;v:paint();v.dialog.buttons[(i-1)%n+1][1].callback();return true')
    def close():device.command('while SettingsView.active do SettingsView.active:close() end;return true')
    def clear():
        invoke('list');device.command('Library._extraRows=Library._extraReminder.items;return true')
        n=int(device.command('return #Library._extraRows'))
        for i in range(1,n+1):
            if device.command('return Library._extraRows['+str(i)+'].kind=="time"')=='true':
                invoke('delete','{id=Library._extraRows['+str(i)+'].id,revision=Library._extraRows['+str(i)+'].revision,mutation="extra-delete-'+str(wall)+'-'+str(i)+'"}')
    def tick():
        device.command('Library.reminders.activity();Library.reminders.tick();return true')
        wait('return not Library.reminders.busy and "ready" or "pending"')
    def add(n):
        invoke('list')
        invoke('add','{kind="time",enabled=true,minuteOfDay='+str(n)+',days=127,message="WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",mutation="a:"..string.format("%.0f",Library._extraReminder.revision)..":extra-'+str(wall)+'-'+str(n)+'"}')
    device.wait_companion();clock();close();clear()
    for i in range(8):add((minute()+60+i)%1440)
    device.command('RemindersUI.open();return true')
    wait('return #SettingsView.active.make()==10 and "ready" or "pending"')
    check('full-list-four-row-pages','local v=SettingsView.active;local rows=v.make();assert(rows[10].text=="8 bedtime reminders — limit reached" and rows[10].enabled==false);assert(v.dialog.buttons[5][1].id=="back");return true')
    row(2)
    check('maximum-message-editor','assert(SettingsView.active.make()[4].text=="Message · "..string.rep("W",60));return true')
    row(6)
    check('delete-cancel-initial-focus','local d=top();assert(d.buttons[1][1].text=="Cancel");d.buttons[1][1].callback();return true')
    invoke('list');device.command('assert(Library._extraReminder.timeCount==8);return true')
    row(3);row(4);row(1);row(8)
    wait('return SettingsView.active.title=="Edit reminder" and "ready" or "pending"')
    check('custom-days-draft')
    row(5)
    wait('return SettingsView.active.title=="Reminders" and "ready" or "pending"')
    close();device.shell('settings','put','system','time_12_24','12')
    device.command('RemindersUI.open();return true')
    wait('return SettingsView.active.make()[2] and SettingsView.active.make()[2].text:find("M",1,true) and "ready" or "pending"')
    row(2);row(2)
    check('twelve-hour-time-input','assert(RemindersUI.timeDialog and RemindersUI.timeDialog:getInputText():find("M",1,true));return true')
    device.command('RemindersUI.timeDialog:onClose();return true')
    close();device.shell('settings','put','system','time_12_24','24')
    # Render-only future/error fakes remain behind the Library surface. No future provider
    # registers, no credentials exist, and service mutation rejection is covered on the JVM.
    device.command('Library._realReminderList=Library.reminders.list;Library.reminders.list=function(done) done({items={{kind="time",id="family:future",revision=1,source="family",sourceLabel="Family",editable=false,enabled=true,title="21:00",detail="Every day",message="Time to stop reading"}},timeCount=1,clockStatus="known"});return true end;RemindersUI.open();return true')
    row(1)
    check('future-read-only-details','local rows=SettingsView.active.make();assert(#rows==3 and rows[1].text=="Managed by Family");for _,r in ipairs(rows) do assert(r.enabled==false and not r.callback) end;return true')
    close()
    device.command('Library.reminders.list=function(done) done({error="storage"});return true end;RemindersUI.open();return true')
    check('unreadable-store-settings-only','assert(SettingsView.active.make()[1].text=="Reminders could not be loaded");return true');close()
    device.command('Library.reminders.list=function(done) done({items={{kind="interval",id="local:eye-rest",revision=1,enabled=false,editable=true,title="Rest your eyes",detail="Every 20 minutes of reading"}},timeCount=0,clockStatus="unknown",notice="Previous reminders recovered"});return true end;RemindersUI.open();return true')
    check('recovered-and-unknown-clock','local rows=SettingsView.active.make();assert(rows[1].text=="Previous reminders recovered");assert(rows[2].kitWarning=="Reminders need the time. Connect to Wi-Fi once to set the clock.");assert(rows[2].note_func()=="Uses reading time; no clock needed");return true');close()
    device.command('Library.reminders.list=Library._realReminderList;return true');clear()
    # This test-only APK permits removal of its synthetic device administrator afterwards.
    device.shell('dpm','set-active-admin','net.fledgewing.orbitcompanion/.AdminReceiver')
    try:
        device.command('Library.open({local_path="/storage/emulated/0/Books/002 The Pruning.epub"});return true')
        wait('local ui=require("apps/reader/readerui").instance;return ui and ui.document and "ready" or "pending"')
        clock((-wall)%60000);add((minute()+1)%1440);tick();clock(60000,1);tick()
        wait('return RemindersUI.current and "ready" or "pending"')
        check('sleep-available-explicit-only','assert(RemindersUI.current.focus==1 and RemindersUI.current.value.sleepAvailable);Library._sleepPage=require("apps/reader/readerui").instance.document:getCurrentPage();return true')
        for key in ('KEYCODE_DPAD_DOWN','KEYCODE_DPAD_DOWN','KEYCODE_ENTER'):device.shell('input','keyevent',key)
        wait('return RemindersUI.current and RemindersUI.current.error=="Could not sleep. Keep reading or try again." and "ready" or "pending"')
        check('sleep-failure-keeps-page','assert(RemindersUI.current.focus==1);assert(require("apps/reader/readerui").instance.document:getCurrentPage()==Library._sleepPage);return true')
        for key in ('KEYCODE_DPAD_DOWN','KEYCODE_ENTER'):device.shell('input','keyevent',key)
        wait('return not RemindersUI.current and "ready" or "pending"')
        clock(600000,1);tick()
        wait('return RemindersUI.current and "ready" or "pending"')
        check('sleep-failure-allows-snooze','assert(require("apps/reader/readerui").instance.document:getCurrentPage()==Library._sleepPage);return true')
        for key in ('KEYCODE_DPAD_DOWN','KEYCODE_DPAD_DOWN','KEYCODE_ENTER'):device.shell('input','keyevent',key)
        wait('return RemindersUI.current and RemindersUI.current.error=="Could not sleep. Keep reading or try again." and "ready" or "pending"')
        clock()
        for key in ('KEYCODE_DPAD_DOWN','KEYCODE_DPAD_DOWN','KEYCODE_ENTER'):device.shell('input','keyevent',key)
        deadline=time.monotonic()+30;power=''
        while time.monotonic()<deadline:
            state=re.search(r'mWakefulness=(\w+)',device.shell('dumpsys','power'))
            power=state.group(1) if state else ''
            if power in ('Asleep','Dozing'):break
            time.sleep(.1)
        if power not in ('Asleep','Dozing'):raise AssertionError('Explicit Sleep did not reach native lockNow')
        (out/'native-sleep.json').write_text(json.dumps({'wakefulness':power,'path':'existing SLEEP_NOW implementation','physical_device':False},indent=2)+'\n')
        device.shell('input','keyevent','KEYCODE_WAKEUP');device.shell('wm','dismiss-keyguard')
        device.shell('am','start','-n','org.koreader.launcher/.MainActivity');device.wait_companion()
        check('native-sleep-wake-restores-page','local ui=require("apps/reader/readerui").instance;assert(ui and ui.document and ui.document:getCurrentPage()==Library._sleepPage);assert(not RemindersUI.current);return true')
    finally:
        device.shell('dpm','remove-active-admin','net.fledgewing.orbitcompanion/.AdminReceiver')
    clear();companion_information(device,out,checks)
    print(str(len(checks))+' native reminder settings/sleep checks passed',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--companion-only',action='store_true',help='capture the public companion information route after the reader flow')
    a=p.parse_args();device=Emulator(a.serial)
    if a.companion_only:
        a.out.mkdir(parents=True,exist_ok=True)
        path=a.out/'checks.json';checks=json.loads(path.read_text()) if path.exists() else []
        companion_information(device,a.out,checks)
        print(str(len(checks))+' native reminder settings/sleep checks passed',flush=True)
    else:review(device,a.out)
