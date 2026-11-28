-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,here,Cache)
    local root=here..'/../orbit.koplugin/'
    test('local completion: durable native revision replay and Undo use only Library commands',function()
        local saved,events={},{}
        local e=setmetatable({Cache=Cache,os={time=function() return 1800000000 end},now_s=function() return 1800000000 end,log=function() end},{__index=_G})
        e.LibraryAdapter={command=function(op,args,done,policy)
            eq(policy.kind,'device');events[#events+1]={op=op,args=Cache.copy(args)};done({revision=args.revision or 0});return true
        end,reset=function() end}
        setfenv(assert(loadfile(root..'logic/budgets.lua')),e)()
        setfenv(assert(loadfile(root..'ko/library.lua')),e)()
        local ui={doc_settings={readSetting=function(_,key) return saved[key] end,saveSetting=function(_,key,value) saved[key]=value end}}
        local status='complete'
        e.Library.nativeReader=function() return {digest=string.rep('a',32),summary={status=status}} end
        e.Library.localCompletion(ui,true);eq(#events,0)
        e.Library.localCompletion(ui);eq(#events,1);eq(events[1].op,'reading.local.event');ok(events[1].args.complete)
        local revision=events[1].args.revision
        e.Library.prepareLocalCompletion(ui);eq(#events,2);eq(events[2].args.revision,revision)
        status='reading';e.Library.localCompletion(ui);eq(events[3].args.revision,revision+1);eq(events[3].args.complete,false)
        saved.booksync_local_completion=nil
        e.Library.nativeReader=function() return {digest=string.rep('a',32),summary={status='complete',modified='2026-11-27',note=string.rep('x',20000)}} end
        e.Library.prepareLocalCompletion(ui)
        eq(events[4].op,'reading.local.prepare');eq(events[4].args.summary.modified,'2026-11-27')
        ok(#Cache.encode(events[4].args)<8192,'large native notes must not exhaust the command budget')
    end)
    test('local completion settings: one materialized local row within settings batch',function()
        local e=setmetatable({Cache=Cache,now_s=function() return 0 end,log=function() end},{__index=_G})
        local calls=0
        e.LibraryAdapter={read=function(request) local args=Cache.decode(request);eq(args.op,'reading.local');eq(args.limit,1);return {target=12,books_this_year=3},128 end,
            request=function(batch) eq(#batch,1);calls=calls+1;return true end}
        setfenv(assert(loadfile(root..'logic/budgets.lua')),e)()
        setfenv(assert(loadfile(root..'ko/library.lua')),e)()
        local p=e.Library.paint('settings-reading-statistics');eq(p:localReading().target,12)
        local m=p:flush();eq(calls,1);eq(m.rows,1);eq(m.bytes,128);eq(m.spawns,0);eq(m.network,0)
    end)
    test('local goal: late results cannot redraw a departed Settings form',function()
        local top,form,pending,paints
        paints=0
        local view={alive=true,dialog={},paint=function() paints=paints+1 end}
        local e=setmetatable({Library={},SettingsView={},UIManager={}},{__index=_G})
        e.currentTarget=12
        e.Library.paint=function() return {localReading=function() return {year=2026,target=e.currentTarget,goal_label='Off'} end,flush=function() end} end
        e.Library.localReadingGoal=function(_,done) pending=done end
        e.SettingsView.open=function(_,make) view.make=make;top=view.dialog;return view end
        e.UIManager.setDirty=function() e.dirty=(e.dirty or 0)+1 end
        e.UIManager.getTopmostVisibleWidget=function() return top end
        e.UIManager.show=function(_,d) top=d;form=d end
        e.UIManager.close=function(_,d) if top==d then top=view.dialog end end
        e.SettingsPage={new=function(o)
            o.controls={}
            local K={px=function(n) return n end,label=function() return {setText=function() end} end,button=function(b) return b end}
            o.content(K,{},702,0,function(b,_,_,id) o.controls[id]=b end)
            return o
        end}
        e.require=function(name)
            eq(name,'ui/widget/inputdialog')
            return {new=function(_,o) o.getInputText=function() return '12' end;o.onShowKeyboard=function() end;return o end}
        end
        setfenv(assert(loadfile(root..'ko/local_reading_settings.lua')),e)()
        e.LocalReadingSettings.open();view.make()[1].callback();eq(form.controls["goal-number"].text,"12");form.controls["goal-save"].callback()
        eq(top,view.dialog)
        local reader={};top=reader
        pending({goal_label='2026 · 12 books · This reader only',target=12})
        eq(top,reader);eq(paints,0)
        top=view.dialog;view.make()[1].callback();form.controls["goal-off"].callback()
        e.currentTarget=nil
        pending({goal_label='Off · This reader only'})
        eq(paints,1)
        view.make()[1].callback();local editor=form;form.controls["goal-save"].callback()
        eq(top,editor);eq(e.dirty,1);eq(paints,1)
    end)

end
