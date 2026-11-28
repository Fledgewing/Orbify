#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Capture the final build in both account states on an explicitly selected M8C emulator.

Run setup, home.py, home_stats.py and reader_panels.py first. This tool uses their
synthetic books/statistics, the compiled ServerAdapter and actual native callbacks.
Approval crops are supplied separately; screenshots always come from this run.
"""
import argparse
import html
import json
from pathlib import Path
import re
import sys
import tempfile
import struct
from datetime import datetime
from zoneinfo import ZoneInfo
import time
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont
sys.dont_write_bytecode = True
from run import Emulator, ROOT, PACKAGE


CLEAN = '''ReaderPanel.close();FinishUI.closeSheet();if AccountView.active then AccountView.active:close() end;
if ReaderCompanionView.active then ReaderCompanionView.active:close() end;
while SettingsView.active do local v=SettingsView.active;v.onBack=nil;v:close() end;'''
BOOK = '/storage/emulated/0/Books/060 The Lantern Room.epub'
REFERENCES = {
    'home-1':'m8c-home-1.webp', 'home-2':'m8c-home-2.webp', 'editor':'m8c-edit.webp', 'picker':'m8c-picker.webp',
    'reader-top':'m8c-reader-top.webp', 'reader-bottom':'m8c-r10-1-panel-custom.webp',
    'contents':'m8c-sheet-toc.webp', 'bookmarks':'m8c-sheet-marks.webp', 'search':'m8c-sheet-search.webp',
    'goto':'m8c-sheet-goto.webp', 'book-info':'m8c-sheet-info.webp',
    'library':'m8c-list.webp', 'filter':'m8c-filter-sheet.webp', 'series':'m8c-series.webp',
    'storage':'m8c-storage.webp', 'end-of-book':'m8c-end.webp',
    'settings-root':'m8c-settings.webp', 'settings-library':'m8c-settings-library.webp',
    'settings-reading':'m8c-r10-3-settings-reading.webp', 'settings-about':'m8c-settings-about.webp',
    'account':'m8c-settings-signin.webp', 'signin':'m8c-signin-form.webp',
}
REMINDERS = {
    'reminders':'rem-Saved_reminders_On_and_Off-and.png',
    'reminder-editor':'rem-Edit_reminder-and.png',
    'rest-eyes-settings':'rem-Rest_your_eyes_Settings-and.png',
    'rest-eyes-interval':'rem-Eye_rest_interval_picker-and.png',
    'reminder-sheet':'rem-Reminder_over_the_page-and.png',
    'rest-eyes-sheet':'rem-Rest_your_eyes_over_the_page-and.png',
    'missed-reminder':'rem-Missed_reminder-and.png',
}
NATIVE_REFS = {'companion-status':'launcher.png', 'checklist':'checklist-0.png',
               'companion-settings':'settings.webp', 'companion-reading':'settings-reading.webp',
               'crash-summary':'crash-1.png', 'goal':'goal-0.png', 'goal-editor':'goal-1.png',
               'reader-companion-status':'reader-0.png', 'reader-companion-helpers':'reader-1.png'}


def wait(d, code, timeout=30):
    deadline = time.monotonic()+timeout
    while d.command(code) != 'ready':
        if time.monotonic() > deadline: raise TimeoutError(code)
        time.sleep(.2)


def nodes(d):
    d.shell('uiautomator','dump','/sdcard/booksync-final-ui.xml')
    return list(ET.fromstring(d.shell('cat','/sdcard/booksync-final-ui.xml')).iter('node'))


def native_tap(d, text, prefix=False):
    for _ in range(6):
        for n in nodes(d):
            label=n.get('text','')
            if (label.startswith(text) if prefix else label==text):
                x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
                if y2>y1 and 0<=y1<1800:
                    d.shell('input','tap',(x1+x2)//2,(y1+y2)//2);time.sleep(.3);return
        d.shell('input','swipe',700,1550,700,450,250)
    raise AssertionError('native control missing: '+text)


def capture(d,out,state,tail_only=False):
    folder=out/state;folder.mkdir(parents=True,exist_ok=True)
    d.shell('am','start','-n','org.koreader.launcher/.MainActivity');d.wait_driver();d.wait_companion()
    receipt=json.loads((folder/'screens.json').read_text()) if tail_only else []
    def shot(name,code=None,ready=None):
        if code: d.command(code+';return true')
        if ready: wait(d,ready)
        d.wait_projection();d.command('assert(Library.isForeground());UI:forceRePaint();return true');time.sleep(.3)
        d.shot(folder/(name+'.png'))
        if name not in receipt:receipt.append(name)
        assert Image.open(folder/(name+'.png')).size==(1404,1872)
        (folder/'screens.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(state+'/'+name,flush=True)
    def native_shot(name):
        time.sleep(.3)
        if deny_fixture_notification_prompt(d):time.sleep(.3)
        d.shot(folder/(name+'.png'))
        if name not in receipt:receipt.append(name)
        (folder/'screens.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(state+'/'+name,flush=True)
    if tail_only:
        d.command(CLEAN+'HomeHost.show();return true')
        capture_tail(d,out,state,shot,native_shot)
        return receipt
    def home():
        d.command(CLEAN+'local w=top();if w and type(w.text)=="string" and w.text:find("BookSync Companion needs",1,true) then click("Later") end;HomeHost.show();return true')
        d.wait_projection()
    d.command(CLEAN+'Library.open({local_path='+json.dumps(BOOK)+'});return true')
    wait(d,'return inBook() and liveUI().document.file=='+json.dumps(BOOK)+' and "ready" or "pending"')
    home()
    op='account.signIn' if state=='signed-in' else 'account.signOut'
    args='{server="https://fixture.example.test",username="reader",password="fixture"}' if state=='signed-in' else '{}'
    d.command('AccountView.open();AccountView.active:command('+json.dumps(op)+','+args+');return true')
    wait(d,'return AccountView.active.busy and "pending" or "ready"')
    d.command('assert(AccountView.active.state.signedIn=='+str(state=='signed-in').lower()+');AccountView.active:close();Library.companion.setupLater();Library.retry();return true')
    home()
    shot('home-1',ready='return HomeHost.active.library_total and "ready" or "pending"')
    shot('home-2','HomeHost.active:turn(1)')
    shot('editor','HomeHost.active:turn(-1);HomeEditor.show(HomeHost.active);local e=top();e.model.selected="resume";e:rebuild()')
    shot('picker','top():pick()')
    d.command('click("Close");click("Done");return true')
    shot('library','HomeHost.show();HomeHost.active:showList("Library","all",{sort="title"})')
    shot('filter','HomeHost.active.filter:show()', 'return HomeHost.active.filter.total~=nil and "ready" or "pending"')
    d.command('HomeHost.active.filter:close(true);return true')
    shot('series','SeriesUI.show("The Glass Orchard")')
    shot('storage','StorageUI.show()', 'return StorageUI.active.data.pending and "pending" or "ready"')
    d.command('StorageUI.active:onClose();Library.settings.write("sync_on_wake",false);Library.settings.write("sync_on_sleep",false);Library.open({local_path='+json.dumps(BOOK)+'});return true')
    wait(d,'return liveUI() and liveUI().document and liveUI().document.file=='+json.dumps(BOOK)+' and "ready" or "pending"')
    d.command('if PositionPrompt.current then click("No") end;return true')
    shot('reader-top','ReaderPanel.show(liveUI(),"reader-top-panel")')
    shot('reader-bottom','ReaderPanel.show(liveUI(),"reader-bottom-panel")')
    for name,kind in [('contents','contents'),('bookmarks','annotations')]:
        shot(name,'ReaderPanel.close();ReaderPanel.navigation(liveUI(),'+json.dumps(kind)+')')
    shot('goto','ReaderPanel.close();ReaderPanel.goDialog(liveUI())')
    shot('book-info','ReaderPanel.close();ReaderPanel.show(liveUI(),"book-info")')
    shot('search','ReaderPanel.close();ReaderPanel.search(liveUI(),"lantern",true)',
         'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.total~=nil and "ready" or "pending"')
    shot('end-of-book','ReaderPanel.close();FinishUI.showSheet(liveUI(),Library.nativeReader(liveUI()))',
         'local s=FinishUI.sheet;return s and s.model and not s.model.pending and "ready" or "pending"')
    d.command('FinishUI.closeSheet();return true')
    shot('reader-companion-status','ReaderCompanionView.open("status")')
    shot('reader-companion-helpers','ReaderCompanionView.active.page="helpers";ReaderCompanionView.active:paint()')
    home()
    for section in ('root','sync','library','reading','home','sleep','updates','about'):
        shot('settings-'+section,'plugin:showSettings('+('' if section=='root' else json.dumps(section))+')')
        page=2
        while d.command('local b=SettingsView.active.dialog:getButtonById("next");return b and b.enabled and "more" or "done"')=='more':
            shot('settings-'+section+'-'+str(page),'SettingsView.active.dialog:getButtonById("next"):onKitTap()');page+=1
        d.command(CLEAN+'return true')
    shot('account','AccountView.open()')
    shot('signin','AccountView.active:form("account")')
    d.command(CLEAN+'return true')
    shot('goal','LocalReadingSettings.open()', 'return SettingsView.active.make()[1].pending and "pending" or "ready"')
    shot('goal-editor','SettingsView.active.dialog:getButtonById("setting-1"):onKitTap()')
    d.command('top():onClose();'+CLEAN+'return true')
    capture_tail(d,out,state,shot,native_shot)
    return receipt


def capture_tail(d,out,state,shot,native_shot):
    # Real interface mutations, isolated local schedules; no supplied display models.
    def invoke(op,args='{}'):
        d.command('local args='+args+';Library._galleryReminder=nil;Library.remindersCommand('+json.dumps(op)+',args,function(r) Library._galleryReminder=r end);return true')
        wait(d,'return Library._galleryReminder and "ready" or "pending"')
        d.command('assert(not Library._galleryReminder.error);return true')
    invoke('list')
    d.command('Library._galleryRows=Library._galleryReminder.items;return true')
    count=int(d.command('return #Library._galleryRows'))
    for i in range(1,count+1):
        if d.command('return Library._galleryRows['+str(i)+'].kind=="time"')=='true':
            invoke('delete','{id=Library._galleryRows['+str(i)+'].id,revision=Library._galleryRows['+str(i)+'].revision,mutation="gallery-delete-'+state+'-'+str(i)+'"}')
    for i,minute in enumerate((1260,1290)):
        invoke('list')
        invoke('add','{kind="time",enabled='+str(i==0).lower()+',minuteOfDay='+str(minute)+',days='+str(127 if i==0 else 96)+',message='+json.dumps('' if i==0 else 'One last chapter')+',mutation="a:"..string.format("%.0f",Library._galleryReminder.revision)..":gallery-'+state+'-'+str(i)+'"}')
    d.shell('settings','put','system','time_12_24','12')
    shot('reminders','RemindersUI.open()', 'return not SettingsView.active.make()[1].pending and #SettingsView.active.make()>=4 and "ready" or "pending"')
    shot('reminder-editor','SettingsView.active.dialog.buttons[2][1].callback()')
    d.command('SettingsView.active:close();return true')
    shot('rest-eyes-settings','SettingsView.active.dialog.buttons[1][1].callback()')
    shot('rest-eyes-interval','SettingsView.active.dialog.buttons[2][1].callback()')
    d.command(CLEAN+'return true')
    capture_native_tail(d,native_shot)


def capture_native_tail(d,native_shot):
    # Same MAIN/LAUNCHER intent used by Android's app icon, separate from HOME.
    d.shell('am','start','-W','-f','0x14000000','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','-n',PACKAGE+'/.StatusActivity')
    native_shot('companion-status')
    native_tap(d,'Setup:',prefix=True);native_shot('checklist')
    d.shell('input','keyevent','KEYCODE_BACK')
    d.shell('am','start','-W','-f','0x14000000','-n',PACKAGE+'/.StatusActivity')
    native_tap(d,'Settings');native_shot('companion-settings')
    native_tap(d,'Reading and Home');native_tap(d,'Reminders');native_shot('companion-reading')
    d.shell('am','start','-W','-f','0x18000000','-n',PACKAGE+'/.CrashFixtureActivity')
    for _ in range(10):
        controls={n.get('text'):n for n in nodes(d)}
        def whole(label):
            n=controls.get(label)
            if n is None:return False
            _,y1,_,y2=map(int,re.findall(r'\d+',n.get('bounds')))
            return y2-y1>=140 and y2<=1758
        if whole('Copy for support') and whole('Clear crash summaries'):break
        d.shell('input','swipe',700,1550,700,950,250)
    else:raise AssertionError('crash summary actions did not fit in the native viewport')
    native_shot('crash-summary')
    d.shell('am','start','-n','org.koreader.launcher/.MainActivity');d.wait_driver();d.wait_companion()


def due_captures(d,folder):
    """Three real claimed occurrences per account state, after full policy acceptance."""
    zone=ZoneInfo(d.shell('getprop','persist.sys.timezone') or 'UTC')
    wall=int(datetime(2026,11,27,20,0,tzinfo=zone).timestamp()*1000)
    elapsed=int(float(d.shell('cat','/proc/uptime').split()[0])*1000)
    def clock(ms=0):
        nonlocal wall,elapsed
        wall+=ms;elapsed+=ms
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp)/'clock';f.write_text(f'{wall} {elapsed} 0')
            d.push(f,'/sdcard/koreader/settings/e2e-reminder-clock.new')
            d.shell('mv','/sdcard/koreader/settings/e2e-reminder-clock.new','/sdcard/koreader/settings/e2e-reminder-clock')
    def invoke(op,args='{}'):
        d.command('local args='+args+';Library._dueResult=nil;Library.remindersCommand('+json.dumps(op)+',args,function(r) Library._dueResult=r end);return true')
        wait(d,'return Library._dueResult and "ready" or "pending"')
        d.command('assert(not Library._dueResult.error);return true')
    def clear():
        invoke('list');d.command('Library._dueRows=Library._dueResult.items;return true')
        for i in range(1,int(d.command('return #Library._dueRows'))+1):
            if d.command('return Library._dueRows['+str(i)+'].kind=="time"')=='true':
                invoke('delete','{id=Library._dueRows['+str(i)+'].id,revision=Library._dueRows['+str(i)+'].revision,mutation="due-delete-'+str(wall)+'-'+str(i)+'"}')
    def interval(on):
        invoke('list');d.command('for _,r in ipairs(Library._dueResult.items) do if r.kind=="interval" then Library._dueEye=r end end;return true')
        invoke('edit','{id=Library._dueEye.id,revision=Library._dueEye.revision,kind="interval",enabled='+str(on).lower()+',intervalMinutes=20,mutation="due-eye-'+str(wall)+'-'+str(on)+'"}')
    def tick():
        d.command('Library.reminders.activity();Library.reminders.tick();return true')
        wait(d,'return not Library.reminders.busy and "ready" or "pending"')
    def add():
        invoke('list');minute=datetime.fromtimestamp(wall/1000,zone)
        minute=(minute.hour*60+minute.minute+1)%1440
        invoke('add','{kind="time",enabled=true,minuteOfDay='+str(minute)+',days=127,message="",mutation="a:"..string.format("%.0f",Library._dueResult.revision)..":due-'+str(wall)+'"}')
    def sheet(kind,name):
        wait(d,'return RemindersUI.current and RemindersUI.current.value.kind=='+json.dumps(kind)+' and "ready" or "pending"')
        d.command('UI:forceRePaint();return true');time.sleep(.2);d.shot(folder/(name+'.png'));print(folder.name+'/'+name,flush=True)
        d.shell('input','keyevent','KEYCODE_BACK')
        wait(d,'return not RemindersUI.current and "ready" or "pending"')
    d.command(CLEAN+'return true');clock()
    for pkg in ('org.koreader.launcher',PACKAGE):d.shell('am','force-stop',pkg)
    d.shell('am','start','-n',PACKAGE+'/.LauncherActivity');d.shell('am','start','-n','org.koreader.launcher/.MainActivity');d.wait_driver();d.wait_companion()
    d.command('Library.companion.setupLater();local w=top();if w and type(w.text)=="string" and w.text:find("BookSync Companion needs",1,true) then click("Later") end;return true')
    clear();interval(False)
    d.command('Library.open({local_path='+json.dumps(BOOK)+'});return true')
    wait(d,'return inBook() and "ready" or "pending"')
    add();tick();clock(60000);tick();sheet('time','reminder-sheet');clear();clock(1)
    clock((-wall)%60000)  # The inclusive missed boundary starts at an exact minute.
    add();d.command('Library.reminders.asleep=true;return true');tick();clock(61*60000)
    d.command('Library.reminders.asleep=false;return true');tick();sheet('time','missed-reminder');clear();clock(1)
    interval(True);tick()
    for _ in range(20):clock(60000);tick()
    sheet('interval','rest-eyes-sheet');clock(1);interval(False)
    (folder/'due-checks.json').write_text(json.dumps({'claimed_sheets':3,'fake_clocks':'disposable APK only','account_state_unchanged':True},indent=2)+'\n')


def seed_diagnostic(d):
    d.shell('am','start','-W','-f','0x18000000','-n',PACKAGE+'/.CrashFixtureActivity','--ez','reset','true')
    d.shell('run-as',PACKAGE,'rm','-f','no_backup/companion-crashes.bin')
    d.shell('am','start','-n','org.koreader.launcher/.MainActivity')
    for count in (1,2):
        d.shell('am','broadcast','--include-stopped-packages','-n',PACKAGE+'/.CrashFixtureReceiver')
        deadline=time.monotonic()+30
        while True:
            try:
                raw=d.adb('exec-out','run-as',PACKAGE,'cat','no_backup/companion-crashes.bin')
                if struct.unpack('>i',raw[-4:])[0]==count:break
            except Exception:pass
            if time.monotonic()>deadline:raise TimeoutError('synthetic diagnostic not saved')
            time.sleep(.2)


def deny_fixture_notification_prompt(d):
    ns=nodes(d)
    if not any('BookSync Companion' in n.get('text','') and 'notifications' in n.get('text','') for n in ns):return False
    deny=next((n for n in ns if n.get('resource-id','').endswith('/permission_deny_button')),None)
    assert deny is not None,'expected Android notification permission deny button'
    x1,y1,x2,y2=map(int,re.findall(r'\d+',deny.get('bounds')))
    d.shell('input','tap',(x1+x2)//2,(y1+y2)//2)
    return True


def launcher_icon(d,out):
    choices=d.shell('cmd','package','query-activities','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')
    launchers=[line.strip() for line in choices.splitlines() if '/' in line and ('nexuslauncher/' in line or 'launcher3/' in line)]
    assert launchers,'the disposable image needs its stock launcher for the icon test'
    d.shell('am','start','-W','-n',launchers[0]);time.sleep(.7)
    d.shell('input','swipe',700,1700,700,500,350)
    for _ in range(6):
        icon=next((n for n in nodes(d) if any(n.get(k,'').startswith('BookSync') for k in ('text','content-desc')) and n.get('bounds')!='[0,0][0,0]'),None)
        if icon is not None:
            x1,y1,x2,y2=map(int,re.findall(r'\d+',icon.get('bounds')))
            d.shell('input','tap',(x1+x2)//2,(y1+y2)//2);break
        d.shell('input','swipe',700,1500,700,500,250)
    else:raise AssertionError('BookSync launcher icon not found in the app drawer')
    deadline=time.monotonic()+15
    while True:
        resumed=d.shell('dumpsys','activity','activities')
        if 'GrantPermissionsActivity' in resumed and deny_fixture_notification_prompt(d):continue
        if any(PACKAGE in line for line in resumed.splitlines() if 'ResumedActivity' in line):break
        if time.monotonic()>deadline:raise AssertionError('launcher icon did not open the companion')
        time.sleep(.2)
    # ResumedActivity precedes the launch animation's visible surface.
    deadline=time.monotonic()+15
    while not any(n.get('package')==PACKAGE and n.get('text') for n in nodes(d)):
        if time.monotonic()>deadline:raise AssertionError('companion UI did not become visible after icon tap')
        time.sleep(.2)
    d.shot(out/'launcher-icon-path.png')


def user_path(d,out):
    """Real Android HOME, app-drawer icon, touch top, close and HOME ten times."""
    log=out/'user-path-logcat.txt'
    d.shell('cmd','package','set-home-activity',PACKAGE+'/.HomeActivity')
    d.shell('am','start','-n','org.koreader.launcher/.MainActivity')
    d.command(CLEAN+'HomeHost.show();AccountView.open();AccountView.active:command("account.signOut",{});return true')
    wait(d,'return AccountView.active.busy and "pending" or "ready"')
    d.command('AccountView.active:close();HomeHost.active:dispatch("book",{local_path='+json.dumps(BOOK)+'});return true')
    wait(d,'return inBook() and not HomeHost.foreground() and "ready" or "pending"')
    d.adb('logcat','-c')
    events=[]
    try:
        d.shell('input','keyevent','KEYCODE_HOME');time.sleep(1)
        wait(d,'return HomeHost.foreground() and "ready" or "pending"')
        d.shot(out/'home-signed-out-path.png');events.append('Signed-out Android HOME lands on BookSync Home')
        launcher_icon(d,out);events.append('Actual app-drawer icon tap opens the companion')
        d.shell('am','start','-n','org.koreader.launcher/.MainActivity');d.wait_driver()
        d.command(CLEAN+'HomeHost.show();return true')
        wait(d,'return HomeHost.foreground() and "ready" or "pending"')
        for i in range(10):
            d.command('HomeHost.active:dispatch("book",{local_path='+json.dumps(BOOK)+'});return true')
            wait(d,'return inBook() and not HomeHost.foreground() and "ready" or "pending"')
            # Opening a book briefly inhibits native input while the first page paints.
            # Observe that boundary before sending the one real tap; never replay it.
            time.sleep(.5)
            wait(d,'return not require("device").input._abs_ev_handler and "ready" or "pending"')
            d.shell('input','tap',700,60)
            wait(d,'return ReaderPanel.sheet and ReaderPanel.sheet.screen=="reader-top-panel" and "ready" or "pending"')
            d.shell('input','keyevent','KEYCODE_BACK')
            wait(d,'return not ReaderPanel.sheet and "ready" or "pending"')
            time.sleep(2.1)
            d.shell('input','keyevent','KEYCODE_HOME')
            wait(d,'return HomeHost.foreground() and "ready" or "pending"')
            events.append('Open → tap top → close panel → HOME '+str(i+1))
            print(events[-1],flush=True)
        events.append('10/10 cycles completed')
    finally:
        log.write_bytes(d.adb('logcat','-d','-v','threadtime'))
        (out/'user-path.json').write_text(json.dumps(events,indent=2)+'\n')
    data=log.read_text(errors='replace')
    assert 'FATAL EXCEPTION' not in data
    assert 'Fatal signal' not in data
    assert 'force quit' not in data.lower()


def gallery(out,reminder_crops,approved_crops):
    pairs=out/'pairs';pairs.mkdir(exist_ok=True)
    stamp=json.loads((ROOT/'shared/version.json').read_text())['version']
    refs=ROOT/'docs/design/booksync-home/shots'
    sections=[];manifest=[]
    for state in ('signed-out','signed-in'):
        for actual in sorted((out/state).glob('*.png')):
            name=actual.stem;note=''
            if name in REMINDERS:
                reference=reminder_crops/REMINDERS[name]
                approved=Image.open(reference).convert('RGB').crop((12,15,319,527))
                note='Approved 480×800 reminder viewport adapted to the wider M8C panel; fonts use bundled Noto and native rasterization. Due sheet preserves the real book. Sleep remains unavailable unless Android grants screen-off permission.'
            else:
                key=name
                reference=approved_crops/NATIVE_REFS[key] if key in NATIVE_REFS else refs/(('m8c-server-signed-in.webp' if state=='signed-in' else 'm8c-server-signed-out.webp') if key=='account' else REFERENCES.get(key,'m8c-settings.webp'))
                approved=Image.open(reference).convert('RGB')
                if name.startswith('settings-') and name not in REFERENCES:note='Parent Settings reference: no dedicated approved crop exists for this section.'
                if key in NATIVE_REFS:note='Native companion uses shared sans roles and Android system chrome. Long content scrolls. The approved reference supplies the visual family; synthetic setup/crash/account values differ.'
            native=Image.open(actual).convert('RGB')
            assert native.size==(1404,1872),(actual,native.size)
            # Normalize the approval to the capture width for legible side-by-side review;
            # original emulator PNGs remain linked and are never resampled or retouched.
            approved=approved.resize((1404,round(approved.height*1404/approved.width)),Image.Resampling.LANCZOS)
            pair=Image.new('RGB',(2832,max(approved.height,native.height)+48),'white')
            draw=ImageDraw.Draw(pair);font=ImageFont.load_default(size=24);draw.text((12,10),'APPROVED MOCKUP',fill='black',font=font);draw.text((1440,10),'NATIVE M8C · '+state,fill='black',font=font)
            pair.paste(approved,(0,48));pair.paste(native,(1428,48))
            target=pairs/(state+'-'+name+'.webp');pair.save(target,quality=82)
            sections.append(f'<article id="{state}-{name}"><h2>{state} · {name}</h2><p>{html.escape(note)}</p><a href="pairs/{target.name}"><img loading="lazy" src="pairs/{target.name}"></a><p><a href="{state}/{actual.name}">Original 1404×1872 capture</a></p></article>')
            manifest.append(dict(state=state,screen=name,pair=str(target.relative_to(out)),reference=reference.name,note=note))
    (out/'gallery.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (out/'index.html').write_text('''<!doctype html><meta charset="utf-8"><title>F1 · BookSync 0.12.1 final build</title>
<style>body{max-width:1800px;margin:24px auto;font:18px/1.5 system-ui;background:#eee;color:#111}article{background:white;padding:20px;margin:24px 0}img{width:100%;height:auto}a{color:inherit}</style>
<h1>F1 · BookSync 0.12.1 final build</h1><p>Approved mockup left, actual native emulator right. 1404×1872 at 300 dpi; isolated AVD, compiled fake ServerAdapter, synthetic covered library and real statistics DB. Both account states were captured on this build.</p>
<p>The source build label is __STAMP__, from the branch’s unchanged shared/version.json. This gallery reviews the 0.12.1 development feature set; release versioning is left to the maintainer.</p>
<p>Remaining differences: bundled Noto versus proprietary mockup fonts; native font/SVG hinting; synthetic books, pagination, data and covers; Android system chrome and keyboard. Battery has no physical measurements. Reminder approval has a taller 480×800 aspect ratio: fit follows M8C width and preserves full actions. Missing section-specific approval crops use the parent Settings reference, labelled below.</p>
<p><a href="user-path.json">HOME/icon/10-cycle assertions</a> · <a href="user-path-logcat.txt">Full path logcat</a> · <a href="gallery.json">Screen manifest</a></p>'''.replace('__STAMP__',html.escape(stamp))+''.join(sections))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--reminder-crops',type=Path,required=True);p.add_argument('--approved-crops',type=Path,required=True)
    p.add_argument('--gallery-only',action='store_true')
    p.add_argument('--resume-tail',choices=['signed-out','signed-in'])
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    if not a.gallery_only:
        d=Emulator(a.serial)
        assert d.shell('wm','size').splitlines()[-1].endswith('1404x1872')
        assert d.shell('wm','density').splitlines()[-1].endswith(': 300')
        if not a.resume_tail:seed_diagnostic(d)
        states=['signed-in'] if a.resume_tail=='signed-in' else ['signed-out','signed-in']
        for state in states:
            capture(d,a.out,state,tail_only=state==a.resume_tail)
            due_captures(d,a.out/state)
        user_path(d,a.out)
    gallery(a.out,a.reminder_crops,a.approved_crops)
