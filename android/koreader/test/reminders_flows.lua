-- SPDX-License-Identifier: MIT
return function(test,eq,ok,E,W,UI,Reader,Files)
    local function world(fn)
        local R=E.Library.reminders
        local saved={reader=Reader.instance,fm=Files.instance,shown=W.shown,queue=W.queue,
            command=E.Library.remindersCommand,foreground=E.Library.isForeground,interactive=E.Jni.isInteractive,
            home=E.HomeHost.active,position=E.PositionPrompt.current,transition=R.transition,queued=R.queued,closed=R.closed}
        local ui={document={file="/fixture/reminders.epub"}}
        Reader.instance=ui;Files.instance=nil;W.shown={ui};W.queue={};E.HomeHost.active=nil;E.PositionPrompt.current=nil
        E.Library.isForeground=function() return true end;E.Jni.isInteractive=function() return true end
        R.sheet=nil;R.grant=nil;R.asleep=false;R.held={};R.busy=nil;R.again=nil;R.transition=nil;R.queued=nil;R.closed=nil
        local x={ui=ui,calls={}}
        E.Library.remindersCommand=function(op,args,done)
            table.insert(x.calls,{op=op,args=args});if op=="runtime" then x.owner=args.owner end
            done({due={}});return true
        end
        R.tick()
        x.value={grant="one-use",owner=x.owner,source="local",kind="time",sleepAvailable=true}
        R.grant=x.value
        fn(R,x)
        R.grant=nil;R.sheet=nil;R.input=nil;R.asleep=false;R.busy=nil;R.waiting=nil
        Reader.instance=saved.reader;Files.instance=saved.fm;W.shown=saved.shown;W.queue=saved.queue
        E.Library.remindersCommand=saved.command;E.Library.isForeground=saved.foreground;E.Jni.isInteractive=saved.interactive
        E.HomeHost.active=saved.home;E.PositionPrompt.current=saved.position
        R.transition=saved.transition;R.queued=saved.queued;R.closed=saved.closed
    end
    test("reminder time draft: noon midnight and 24-hour boundaries",function()
        eq(E.RemindersUI.timeDraft(0,true):text(),"12:00 AM")
        eq(E.RemindersUI.timeDraft(720,true):text(),"12:00 PM")
        eq(E.RemindersUI.timeDraft(1439,false):text(),"23:59")
        local m=E.RemindersUI.timeDraft(1260,true);m:key("period");eq(m:text(),"09:00 AM")
        m:select("hour");m:key("0");m:key("0");eq(m:text(),nil)
        m:select("hour");m:key("1");m:key("3");eq(m:text(),nil)
    end)
    test("reminder time draft: field replacement backspace and invalid minutes stay local",function()
        local m=E.RemindersUI.timeDraft(1260,false)
        m:key("2");m:key("0");eq(m.field,"minute");m:key("5");m:key("9");eq(m:text(),"20:59")
        m:key("backspace");eq(m:text(),"20:05");m:key("9");eq(m:text(),"20:59")
        m:select("minute");m:key("6");m:key("0");eq(m:text(),nil)
        m:key("backspace");m:key("1");eq(m:text(),nil)
        m:key("backspace");m:key("backspace");eq(m:text(),nil)
        m:key("x");eq(m.minute,"")
    end)
    test("reminder gate: only the current typed local grant can draw",function() world(function(R,x)
        local draws=0
        ok(E.Gate.reminder(x.value,function() draws=draws+1 end));eq(draws,1)
        eq(E.Gate.reminder({grant="one-use",owner=x.owner,source="local",kind="time"},function() draws=draws+1 end),false)
        x.value.source="family";eq(E.Gate.reminder(x.value,function() draws=draws+1 end),false);eq(draws,1)
    end) end)
    test("reminder gate: hidden sleeping and background always deny",function() world(function(R,x)
        E.Library.isForeground=function() return false end;eq(R.canDraw(x.value),false)
        E.Library.isForeground=function() return true end;E.Jni.isInteractive=function() return false end;eq(R.canDraw(x.value),false)
        E.Jni.isInteractive=function() return true end;R.asleep=true;eq(R.canDraw(x.value),false)
    end) end)
    test("reminder gate: position consent and other modals are never stacked",function() world(function(R,x)
        E.PositionPrompt.current={};eq(R.canDraw(x.value),false);E.PositionPrompt.current=nil
        W.shown[#W.shown+1]={};eq(R.canDraw(x.value),false)
    end) end)
    test("reminder gate: time may cover a native menu; interval requires page",function() world(function(R,x)
        x.ui.menu={menu_container={}};W.shown[#W.shown+1]=x.ui.menu.menu_container
        ok(R.canDraw(x.value));x.value.kind="interval";eq(R.canDraw(x.value),false)
    end) end)
    test("reminder gate: owner A to B to A never revives an old grant",function() world(function(R,x)
        Reader.instance={document={}};W.shown={Reader.instance};eq(R.canDraw(x.value),false)
        Reader.instance=x.ui;W.shown={x.ui};eq(R.canDraw(x.value),false)
    end) end)
    test("reminder owner: a new document on the same reader retires an old grant",function() world(function(R,x)
        local doc=x.ui.document;x.ui.document={};eq(R.canDraw(x.value),false)
        x.ui.document=doc;eq(R.canDraw(x.value),false)
    end) end)
    test("reminder lifecycle: coalescing preserves the first inactive frame",function() world(function(R,x)
        R.lifecycle();ok(R.transition.page);R.closed=x.ui;R.lifecycle();eq(R.transition.page,false)
        R.closed=nil;R.lifecycle();eq(R.transition.page,false)
    end) end)
    test("reminder input: held Select and repeats drain before fresh navigation",function() world(function(R,x)
        local actions={};R.held[1]=true;ok(R.attach(x.value,{},function(action) actions[#actions+1]=action end))
        local input={event_map={[1]="Enter",[2]="Down"}}
        for _,value in ipairs({2,0}) do ok(R.rawKey(input,{code=1,value=value})) end;eq(#actions,0)
        R.rawKey(input,{code=2,value=1});R.rawKey(input,{code=2,value=2});R.rawKey(input,{code=2,value=0});eq(actions[1],"down")
        R.rawKey(input,{code=1,value=1});R.rawKey(input,{code=1,value=0});eq(actions[2],"select")
    end) end)
    test("reminder input: every page key dismisses and consumes without focus traversal",function() world(function(R,x)
        local actions={};ok(R.attach(x.value,{},function(action) actions[#actions+1]=action end))
        for _,name in ipairs({"Left","Right","LPgFwd","RPgFwd","LPgBack","RPgBack","Back"}) do
            local input={event_map={[900]=name}}
            ok(R.rawKey(input,{code=900,value=1}));ok(R.rawKey(input,{code=900,value=0}));eq(actions[#actions],"dismiss")
        end
    end) end)
    test("reminder input: native page activity coalesces without IPC",function() world(function(R,x)
        local count=#x.calls;for _=1,10000 do R.activity() end;eq(#x.calls,count)
    end) end)
    test("reminder sleep: unavailable never requests permission or sends an intent",function() world(function(R,x)
        x.value.sleepAvailable=false;local result
        R.respond(x.value,"sleep",function(r) result=r end);eq(result.error,"unavailable");eq(#x.calls,1)
    end) end)
    test("reminder sleep: signed-out reader checkpoints native position without requiring an account",function() world(function(R,x)
        local saved=E.Library.cachedAccountState;E.Library.cachedAccountState=function() return {} end
        local sequence={};x.ui.handleEvent=function(_,ev) sequence[#sequence+1]="native-save" end
        x.ui.doc_settings={flush=function() sequence[#sequence+1]="metadata-flush";return "/fixture" end}
        E.Library.remindersCommand=function(op,args,done)
            sequence[#sequence+1]=op
            done(op=="respond" and {sleep=true,accepted=true} or {ok=true});return true
        end
        local result;R.respond(x.value,"sleep",function(r) result=r end)
        eq(table.concat(sequence,","),"respond,native-save,metadata-flush,sleep");ok(result.ok)
        E.Library.cachedAccountState=saved
    end) end)
    test("reminder sleep: snooze after failed Sleep reaches the service instead of closing silently",function() world(function(R,x)
        R.sleepAccepted=x.value
        local action,result
        E.Library.remindersCommand=function(op,args,done)
            eq(op,"respond");action=args.action;done({accepted=true});return true
        end
        R.respond(x.value,"snooze10",function(r) result=r end)
        eq(action,"snooze10");ok(result.accepted);eq(R.sleepAccepted,nil)
    end) end)
    test("reminder sleep: failed native position flush never dispatches Sleep",function() world(function(R,x)
        local saved=E.Library.cachedAccountState;E.Library.cachedAccountState=function() return {} end
        x.ui.handleEvent=function() end;x.ui.doc_settings={flush=function() return nil end}
        local operations={};E.Library.remindersCommand=function(op,args,done) operations[#operations+1]=op;done({sleep=true,accepted=true});return true end
        local result;R.respond(x.value,"sleep",function(r) result=r end)
        eq(result.error,"position");eq(table.concat(operations,","),"respond")
        E.Library.cachedAccountState=saved
    end) end)
    test("reminder modal: ordinary notices cannot piggyback on the authorized draw",function() world(function(R,x)
        local reading,catalog=E.reading,E.Library.catalog_active
        E.reading=function() return false end;E.Library.catalog_active=nil;R.sheet={}
        local draws=0;E.Gate.show("ordinary while reminder",function() draws=draws+1 end)
        eq(draws,0);ok(E.Gate.silent());R.sheet=nil
        E.reading=reading;E.Library.catalog_active=catalog
    end) end)
    test("reminder modal: position consent waits for fresh input after dismissal",function() world(function(R,x)
        local count=0;R.sheet={}
        ok(R.deferPosition(function() count=count+1 end));eq(count,0)
        R.sheet=nil;R.grant=nil;R.activity();eq(count,0)
        local pending=W.queue[#W.queue];ok(pending);pending.fn();eq(count,1)
    end) end)
    test("reminder settings: actual local menu route stays available behind the PIN",function() world(function(R,x)
        local original,allowed
        for _,group in ipairs(E.OrbitAndroid.menuItems(setmetatable({ui=x.ui},{__index=E.OrbitAndroid}))) do
            if group.settings_group=="reading" then
                local rows=group.sub_item_table_func()
                for _,row in ipairs(rows) do if row.text=="Reminders" then original=row end end
                local locked=E.OrbitAndroid.readOnly(rows)
                for _,row in ipairs(locked) do if row.text=="Reminders" then
                    allowed=true;ok(original);eq(row.callback,original.callback);ok(not row.enabled_func or row.enabled_func())
                end end
            end
        end
        ok(original and allowed,"Reminders is reachable in the actual locked Reading group")
    end) end)
    test("reminder draft: oversized input is rejected before encoding or IPC",function() world(function(R,x)
        local count=#x.calls;local result
        R.draft({kind="time",message=string.rep("x",241)},function(r) result=r end)
        eq(result.error,"invalid");eq(#x.calls,count)
    end) end)
    test("reminder retirement: detach makes all late responses stale",function() world(function(R,x)
        R.detach(x.value);local result
        R.respond(x.value,"sleep",function(r) result=r end);eq(result.stale,true);eq(#x.calls,1)
    end) end)
end
