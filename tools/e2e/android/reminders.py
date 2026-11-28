#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native reminder settings, claims and input on a verified disposable emulator.

Uses the production Library/service/store with clocks injected only by build.py.
No shipping test command, live server, physical reader or real-time twenty-minute wait.
"""
import argparse
from datetime import datetime
from zoneinfo import ZoneInfo
import json
from pathlib import Path
import sys
import tempfile
import time
sys.dont_write_bytecode=True
from run import Emulator


def review(device,out):
    out.mkdir(parents=True,exist_ok=True)
    device.shell("settings","put","system","time_12_24","24")
    checks=[]
    zone=ZoneInfo(device.shell("getprop","persist.sys.timezone") or "UTC")
    wall=int(datetime(2026,11,27,20,0,tzinfo=zone).timestamp()*1000)
    def local_minute():
        now=datetime.fromtimestamp(wall/1000,zone)
        return now.hour*60+now.minute
    elapsed=int(float(device.shell('cat','/proc/uptime').split()[0])*1000)
    fail=0
    def clock(ms=0):
        nonlocal wall,elapsed
        wall+=ms;elapsed+=ms
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'clock';p.write_text(f'{wall} {elapsed} {fail}')
            device.push(p,'/sdcard/koreader/settings/e2e-reminder-clock.new')
            device.shell('mv','/sdcard/koreader/settings/e2e-reminder-clock.new','/sdcard/koreader/settings/e2e-reminder-clock')
    def wait(code):
        deadline=time.monotonic()+30
        while device.command(code)!='ready':
            if time.monotonic()>deadline:raise TimeoutError(code)
            time.sleep(.1)
    def check(name,code='return true'):
        device.command(code)
        device.command('UI:forceRePaint();return true')
        time.sleep(.2)
        device.shot(out/(name+'.png'))
        checks.append(name)
        (out/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    def invoke(op,args=None):
        args=args or '{}'
        device.command('local args='+args+';Library._reminderResult=nil;Library.remindersCommand('+json.dumps(op)+',args,function(r) Library._reminderResult=r end);return true')
        wait('return Library._reminderResult and "ready" or "pending"')
        device.command('assert(not Library._reminderResult.error,Library._reminderResult.error);return true')
    def tick():
        device.command('Library.reminders.activity();Library.reminders.tick();return true')
        wait('return not Library.reminders.busy and "ready" or "pending"')
    def no_sheet():device.command('assert(not RemindersUI.current);return true')
    def sheet(kind):wait('return RemindersUI.current and RemindersUI.current.value.kind=='+json.dumps(kind)+' and "ready" or "pending"')
    def key(name):device.shell('input','keyevent',name)
    def tap_action(text):
        point=device.command('local b=assert(RemindersUI.current.dialog:getButtonById('+json.dumps(text)+'));return math.floor(b.dimen.x+b.dimen.w/2)..","..math.floor(b.dimen.y+b.dimen.h/2)')
        x,y=point.split(',');device.shell('input','tap',x,y)
    def dismissed():wait('return not RemindersUI.current and "ready" or "pending"')
    def row(index):
        device.command('local v=SettingsView.active;local n=v.screen=="reminders-list" and 4 or 8;local i='+str(index)+';v.offset=math.floor((i-1)/n)*n;v:paint();v.dialog.buttons[(i-1)%n+1][1].callback();return true')
    def close_settings():
        device.command('while SettingsView.active do SettingsView.active:close() end;return true')
    def time_row(minute):
        invoke('list')
        invoke('add','{kind="time",enabled=true,minuteOfDay='+str(minute)+',days=127,message="",mutation="a:"..string.format("%.0f",Library._reminderResult.revision)..":e2e-'+str(wall)+'"}')
    def clear_times():
        invoke('list')
        device.command('Library._reminderRows=Library._reminderResult.items;return true')
        count=int(device.command('return #Library._reminderRows'))
        for i in range(1,count+1):
            is_time=device.command('return Library._reminderRows['+str(i)+'].kind=="time"')=='true'
            if is_time:
                invoke('delete','{id=Library._reminderRows['+str(i)+'].id,revision=Library._reminderRows['+str(i)+'].revision,mutation="remove-'+str(wall)+'-'+str(i)+'"}')
    def interval(enabled):
        invoke('list')
        device.command('for _,r in ipairs(Library._reminderResult.items) do if r.kind=="interval" then Library._eye=r end end;return true')
        invoke('edit','{id=Library._eye.id,revision=Library._eye.revision,kind="interval",enabled='+str(enabled).lower()+',intervalMinutes=20,mutation="eye-'+str(wall)+'"}')
    def read(minutes):
        for _ in range(minutes):clock(60000);tick()
    clock()
    device.shell('settings','put','system','time_12_24','24')
    # Restart both processes so the disposable injected clock owns the whole runtime.
    device.shell('am','force-stop','net.fledgewing.orbitcompanion')
    device.shell('am','start','-n','net.fledgewing.orbitcompanion/.LauncherActivity')
    device.shell('am','force-stop','org.koreader.launcher')
    device.shell('am','start','-n','org.koreader.launcher/.MainActivity')
    device.wait_companion()
    device.command('Library.companion.setupLater();local w=top();if w and type(w.text)=="string" and w.text:find("BookSync Companion needs",1,true) then click("Later") end;return true')
    device.command('local t=top();if t and t.text then UI:close(t) end;while SettingsView.active do SettingsView.active:close() end;local ui=require("apps/reader/readerui").instance;if ui then ui:onClose() end;HomeHost.show();return true')
    clear_times()
    # Actual Settings drafts: changing a field never writes until Save.
    device.command('RemindersUI.open();return true')
    wait('return SettingsView.active and SettingsView.active.make()[1].text:find("Rest your eyes",1,true) and "ready" or "pending"')
    check('empty-and-eye-off')
    row(1);row(1);row(2);row(2)
    wait('return SettingsView.active.title=="Rest your eyes" and "ready" or "pending"')
    check('interval-30-draft','local v=SettingsView.active;local save=v.dialog:getButtonById("setting-3");assert(save and save.dimen.y+save.dimen.h<=Device.screen:getHeight());assert(not v.dialog:getButtonById("next"));return true')
    row(3)
    wait('return SettingsView.active.title=="Reminders" and "ready" or "pending"')
    invoke('list');device.command('for _,r in ipairs(Library._reminderResult.items) do if r.kind=="interval" then assert(r.enabled and r.intervalMinutes==30) end end;return true')
    row(1);row(1);device.command('SettingsView.active:back();return true')
    invoke('list');device.command('for _,r in ipairs(Library._reminderResult.items) do if r.kind=="interval" then assert(r.enabled) end end;return true')
    check('back-discards-eye-draft')
    close_settings();clock(1);interval(False)
    device.command('RemindersUI.open();return true')
    wait('return #SettingsView.active.make()==3 and "ready" or "pending"')
    row(3)
    wait('return SettingsView.active.title=="Add bedtime reminder" and "ready" or "pending"')
    row(2)
    check('time-keyboard-docked','local input=RemindersUI.timeDialog;assert(input and input.keypad_y+input.keypad_h==Device.screen:getHeight());for _,key in ipairs({"2","0","0","1"}) do input:getButtonById("key-"..key).callback() end;assert(input:getInputText()=="20:01");input:submit();return true')
    wait('return SettingsView.active.make()[2].text:find("20:01",1,true) and "ready" or "pending"')
    row(4)
    check('message-keyboard-docked','local input;for _,w in ipairs(UI._window_stack) do if w.widget.setInputText then input=w.widget end end;assert(input);local d=input._input_widget:getKeyboardDimen();assert(d.y+d.h==Device.screen:getHeight());input:setInputText("Time for a break");input.buttons[1][2].callback();return true')
    wait('return SettingsView.active.make()[4].text:find("Time for a break",1,true) and "ready" or "pending"')
    fail=1;clock();row(5)
    wait('return SettingsView.active.notice=="Could not save reminder. Try again." and "ready" or "pending"')
    check('save-failure-retains-draft')
    fail=0;clock();row(5)
    wait('return SettingsView.active.title=="Reminders" and "ready" or "pending"')
    check('bedtime-saved')
    close_settings();tick();clock(60000);tick();sheet('time')
    check('bedtime-over-home','assert(RemindersUI.current.focus==1);assert(not RemindersUI.current.value.sleepAvailable);return true')
    key('KEYCODE_DPAD_RIGHT');dismissed()
    check('page-key-dismisses-home')
    clear_times();clock(1)
    # Native page remains unchanged by dismissal; next fresh page key can turn it.
    device.command('Library.settings.write("sync_on_wake",false);Library.settings.write("sync_on_sleep",false);Library.open({local_path="/storage/emulated/0/Books/002 The Pruning.epub"});return true')
    wait('local ui=require("apps/reader/readerui").instance;return ui and ui.document and "ready" or "pending"')
    time_row(1202);tick();clock(60000);tick();sheet('time')
    check('bedtime-over-page','Library._reminderPage=require("apps/reader/readerui").instance.document:getCurrentPage();return true')
    key('KEYCODE_DPAD_RIGHT');dismissed()
    check('page-key-no-fallthrough','assert(require("apps/reader/readerui").instance.document:getCurrentPage()==Library._reminderPage);return true')
    key('KEYCODE_DPAD_RIGHT')
    wait('return require("apps/reader/readerui").instance.document:getCurrentPage()~=Library._reminderPage and "ready" or "pending"')
    clear_times();clock(1);time_row(1203);tick();clock(60000);tick();sheet('time')
    for n in range(2):
        if n==0:tap_action('10 more minutes')
        else:key('KEYCODE_DPAD_DOWN');key('KEYCODE_ENTER')
        dismissed()
        clock(600000);tick();sheet('time');check('snooze-'+str(n+1))
    key('KEYCODE_BACK');dismissed();clear_times();clock(1)
    # Missed eligibility at the inclusive boundary, without waking or navigating.
    clock((-wall)%60000);minute=(local_minute()+1)%1440;time_row(minute)
    device.command('Library.reminders.asleep=true;Library.reminders.tick();return true')
    wait('return not Library.reminders.busy and "ready" or "pending"')
    clock(61*60000)
    device.command('Library.reminders.asleep=false;return true');tick();sheet('time')
    check('missed-60-minutes','assert(RemindersUI.current.value.dueLabel);return true')
    key('KEYCODE_BACK');dismissed();clear_times();clock(1)
    minute=(local_minute()+1)%1440;time_row(minute)
    device.command('Library.reminders.asleep=true;Library.reminders.tick();return true')
    wait('return not Library.reminders.busy and "ready" or "pending"')
    clock(61*60000+1000);device.command('Library.reminders.asleep=false;return true');tick();no_sheet()
    check('missed-expired-silent');clear_times();clock(1)
    interval(True);tick();read(19);no_sheet();read(1);sheet('interval')
    check('eye-rest-static-page','assert(RemindersUI.current.focus==1);assert(RemindersUI.current.value.message=="Rest your eyes. Look at something far away for 20 seconds.");return true')
    tap_action('Done');dismissed();check('eye-rest-touch-done');clock(1);tick();no_sheet()
    # Five minutes outside reading resets nineteen minutes, before resumed input.
    read(19);device.command('RemindersUI.open();return true');tick();clock(300000);tick();close_settings();tick();read(1);no_sheet()
    check('five-minute-break-reset')
    interval(True);tick()
    minute=(local_minute()+20)%1440;time_row(minute);read(20);sheet('time')
    check('bedtime-wins-same-threshold');key('KEYCODE_BACK');dismissed();tick();no_sheet()
    read(20);sheet('interval');fail=1;clock()
    key('KEYCODE_DPAD_DOWN');key('KEYCODE_ENTER')
    wait('return RemindersUI.current and RemindersUI.current.error=="Could not turn off reminder. Try again." and "ready" or "pending"')
    check('turn-off-failure-stays-enabled','assert(RemindersUI.current.focus==1);return true')
    fail=0;clock();key('KEYCODE_DPAD_DOWN');key('KEYCODE_ENTER');dismissed()
    invoke('list');device.command('for _,r in ipairs(Library._reminderResult.items) do if r.kind=="interval" then assert(not r.enabled) end end;return true')
    check('turn-off-durable')
    clear_times();clock(1)
    device.command('local ui=require("apps/reader/readerui").instance;ui:onClose();HomeHost.show();return true')
    # Account-independent storage and restart retain settings without replaying claims.
    device.shell('am','force-stop','org.koreader.launcher');device.shell('am','start','-n','org.koreader.launcher/.MainActivity');device.wait_companion()
    invoke('list');device.command('assert(#Library._reminderResult.items==1 and not Library._reminderResult.items[1].enabled);return true')
    check('restart-retains-local-settings')
    print(str(len(checks))+' native reminder checks passed',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();review(Emulator(a.serial),a.out)
