-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,Widget)
    local function withUI(fn)
        local oldScale=E.Device.screen.scaleBySize
        E.Device.screen.scaleBySize=function(_,n) return n end
        local oldRequire,oldRead,oldRequest,oldRefresh=E.require,E.LibraryAdapter.read,E.LibraryAdapter.request,E.Shared.refresh
        local dialogClass=Widget:extend{moveFocusTo=function(self,x,y) self.focus={x,y} end,getButtonById=function() end}
        E.require=function(name)
            if name=="ui/widget/buttondialog" then return dialogClass end
            return oldRequire(name)
        end
        local success,err=pcall(fn)
        if E.SettingsView.active then E.SettingsView.active:close() end
        E.require,E.LibraryAdapter.read,E.LibraryAdapter.request=oldRequire,oldRead,oldRequest
        E.Device.screen.scaleBySize=oldScale
        E.Shared.refresh=oldRefresh
        ok(success,err)
    end
    local function button(view,id)
        for _,line in ipairs(view.dialog.buttons) do for _,b in ipairs(line) do if b.id==id then return b end end end
    end
    test("Settings presentation: Mode card cycles all presets, Custom and PIN keeps it read only",function()
        withUI(function()
            local saved={}; for _,key in ipairs(E.SettingsUI.modeKeys) do saved[key]=E.S[key] end
            local has=E.Companion.has; E.Companion.has=function() return true end
            local m=setmetatable({},{__index=E.OrbitAndroid})
            local group
            for _,g in ipairs(m:menuItems()) do if g.settings_group=="sync" then group=g end end
            local v=E.SettingsView.open(group.text,group.sub_item_table_func,"settings-sync")
            for i=1,3 do
                local b=button(v,"mode-card"); ok(b); ok(b.height>=50); b.callback()
                ok(E.SettingsUI.mode(E.S)~="custom")
            end
            E.Shared.set("wifi_idle_min",10)
            v:paint()
            local rows=group.sub_item_table_func()
            ok(rows[2].card_text():find("Your own settings",1,true))
            ok(rows[2].card_text():find("Battery depends on your mix",1,true))
            eq(rows[3].text,"Back to Balanced")
            local locked=m.readOnly(rows)
            eq(locked[2].card_action,nil,"card cannot bypass PIN")
            for _,choice in ipairs(locked[2].sub_item_table) do eq(choice.enabled_func(),false) end
            local unavailable=E.Companion.has; E.Companion.has=function() return false end
            rows[2].card_action(); eq(E.SettingsUI.mode(E.S),"custom","missing Wi-Fi capability cannot apply mode")
            E.Companion.has=unavailable
            for _,key in ipairs(E.SettingsUI.modeKeys) do E.Shared.set(key,saved[key]) end
            E.Companion.has=has
        end)
    end)
    test("Settings presentation: Home order, Back restores page and focus; every target is at least 50 px",function()
        withUI(function()
            local m=setmetatable({},{__index=E.OrbitAndroid})
            local group
            for _,g in ipairs(m:menuItems()) do if g.settings_group=="home" then group=g end end
            local rows=group.sub_item_table_func()
            eq(rows[1].text,"Edit layout"); eq(rows[2].text,"Reset layout")
            eq(#rows,4); eq(rows[3].text,"Page names"); ok(rows[4].text_func():find("Home button",1,true))
            local v=E.SettingsView.open(group.text,group.sub_item_table_func,"settings-home")
            button(v,"setting-4").callback()
            eq(#v.stack,1)
            button(v,"back").callback()
            eq(#v.stack,0); eq(v.dialog.focus[2],4)
            for _,line in ipairs(v.dialog.buttons) do for _,b in ipairs(line) do ok(b.height>=50) end end
            local child=E.SettingsView.open("Nested choices",function() return {{text="Choice"}} end,"settings-home")
            local previous=v.dialog
            child:back()
            eq(E.SettingsView.active,v); ok(v.dialog~=previous,"return refreshes checked shared values")
            eq(v.dialog.focus[2],4,"nested return retains parent focus")
            v.dialog:onClose(); eq(v.alive,false)
        end)
    end)
    test("Settings sleep choices: bounded counts, multi-select, categories, loading, error, empty and missing",function()
        withUI(function()
            local state="ready"
            local seen={}
            E.LibraryAdapter.read=function(encoded)
                local a=E.Cache.decode(encoded); eq(a.op,"sleep.choices"); eq(a.limit,6); eq(a.bytes,16384)
                seen[#seen+1]=a
                if state=="loading" then return nil end
                if state=="error" then return {items={},error="unavailable"},80 end
                if state=="empty" then return {items={},total=0,freshness={saved=true}},80 end
                if state=="missing" then return {items={},freshness={saved=false}},80 end
                return {items={{id="scope:42",title="Quiet books",count=7}},total=7,next=a.offset==0 and 6 or nil,freshness={saved=true}},160
            end
            E.LibraryAdapter.request=function(batch) eq(#batch,1); return true end
            local old=E.S.sleep_from
            local v=E.SettingsView.sleepChoices("sleep_from")
            ok(button(v,"setting-2").text:find("7 books",1,true))
            button(v,"setting-2").callback(); ok(E.S.sleep_from:find("scope:42",1,true))
            button(v,"setting-3").callback(); eq(seen[#seen].offset,6)
            button(v,"setting-1").callback(); eq(seen[#seen].category,"collections"); eq(seen[#seen].offset,0)
            for _,s in ipairs({"loading","error","empty","missing"}) do
                state=s; v:paint()
                local text=button(v,"setting-2").text
                ok(text:find(({loading="Loading",error="unavailable",empty="No choices",missing="not saved"})[s],1,true),text)
            end
            E.Shared.set("sleep_from",old)
            v:close(); ok(not v.retry,"close cancels pending repaints")
        end)
    end)
    test("Settings device command: failure and permission stay visible; closed or covered initiators never redraw",function()
        withUI(function()
            local v=E.SettingsView.open("Power",function() return {{text="Sleep after: 10 min idle"}} end,"settings-sync")
            v:deviceResult({error="permission"}); ok(v.notice:find("Allow",1,true))
            v:deviceResult({error="unavailable"}); ok(v.notice:find("unavailable",1,true))
            v:deviceResult({device={}}); eq(v.notice,nil)
            local before=v.dialog
            local cover=Widget:new{}; E.UIManager:show(cover)
            v:deviceResult({error="permission"}); eq(v.dialog,before)
            E.UIManager:close(cover); v:close()
            v:deviceResult({error="permission"}); eq(v.dialog,nil)
        end)
    end)
    test("Settings Updates and About: installed channel is independent of selected channel, credits stay reachable",function()
        local m=setmetatable({},{__index=E.OrbitAndroid})
        local groups={}
        for _,g in ipairs(m:menuItems()) do groups[g.settings_group]=g end
        local updates=groups.updates.sub_item_table_func()
        ok(updates[1].text:find("Installed:",1,true)); ok(updates[2].text_func():find("Update channel:",1,true))
        eq(updates[3].text,"Check now"); eq(updates[4].text,"What's new")
        local before=updates[1].text; local old=E.S.update_channel
        updates[2].sub_item_table[3].callback(); eq(groups.updates.sub_item_table_func()[1].text,before)
        E.Shared.set("update_channel",old)
        local about=groups.about.sub_item_table_func()
        ok(about[1].text:find("Version:",1,true)); ok(about[2].text:find("This reader:",1,true)); eq(about[3].text,"About")
    end)
    test("Settings owned navigation: replaced pages retire; a locked direct account route stays read only",function()
        withUI(function()
            local owner=setmetatable({},{__index=E.OrbitAndroid})
            local pin=E.Shared.pin_locked
            E.Shared.refresh=function() end
            E.Shared.pin_locked=false
            local first=owner:showSettings("home")
            local second=owner:showSettings("reading")
            eq(first.alive,false);eq(first.dialog,nil);eq(second.parent,nil)
            E.Shared.pin_locked=true
            local account=owner:showSettings("account")
            eq(second.alive,false);eq(account.screen,"settings-account")
            for _,row in ipairs(account.make()) do
                if row.callback then ok(row.enabled_func and not row.enabled_func(),"account actions respect PIN") end
            end
            account.onBack=nil;account:close();E.Shared.pin_locked=pin
        end)
    end)

    test("Settings setup: pending setup is an owned row and delayed prompts stay quiet",function()
        withUI(function()
            local owner=setmetatable({},{__index=E.OrbitAndroid})
            local previous=E.Shared.setup_needed
            E.Shared.refresh=function() end;E.Shared.setup_needed=9
            local old=Widget:new{ok_text="Fix now"};E.OrbitAndroid.setup_dialog=old;E.UIManager:show(old)
            local v=owner:showSettings()
            eq(E.OrbitAndroid.setup_dialog,nil);eq(v.make()[1].text,"Companion setup");eq(v.make()[1].detail,"9 steps")
            local count=#W.shown
            owner:maybeSetupPrompt("start");owner:maybeSetupPrompt("resume")
            eq(#W.shown,count);eq(W.shown[#W.shown],v.dialog)
            E.Shared.setup_needed=previous
        end)
    end)

end
