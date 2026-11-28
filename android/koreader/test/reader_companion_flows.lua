-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(here,test,eq,ok)
    local root=here.."/../orbit.koplugin/"
    local function world()
        local e=setmetatable({Library={companion={}},OrbitAndroid={},Device={screen={}},
            Companion={PACKAGE="fixture",AUTHORITY="fixture",workerProblem=function() end},
            Jni={},Cache={},now_s=function() return 1 end,log=function() end,PATCH_VERSION="fixture"},{__index=_G})
        e.current={document={file="book.epub"}}
        e.liveUI=function() return e.current end
        e.Jni.isInteractive=function() return true end
        e.Library.isForeground=function() return true end
        e.snapshot={mode="add-on",sync="Last sync: unknown",setup="Setup: unknown",updates="Updates: unknown",
            helpers={{id="wifi",label="Wi-Fi switching",on=false,mutable=true,detail="Connect when asked"},
                {id="sleep",label="Sleep sync",on=false,mutable=true,detail="Save before sleep"},
                {id="screen",label="Screen off",on=false,mutable=true,permission=false,detail="Android permission needed"}}}
        e.raw="snapshot";e.reads=0;e.decoded=0
        e.Jni.call=function() e.reads=e.reads+1;return {ok="1",body=e.raw} end
        e.Cache.decode=function() e.decoded=e.decoded+1;return e.snapshot end
        e.Library.companion.command=function(args,done) e.command=args;e.done=done;return true,function() e.retired=true end end
        local manager={shown=0,top={id="original-menu"},scheduled={}}
        function manager:show(dialog) self.top=dialog;self.shown=self.shown+1 end
        function manager:close(dialog) if self.top==dialog then self.top=self.base end end
        manager.base=manager.top
        function manager:getTopmostVisibleWidget() return self.top end
        function manager:scheduleIn(_,fn) table.insert(self.scheduled,fn) end
        e.UIManager=manager
        function e.Device.screen:getWidth() return 1200 end
        function e.Device.screen:getHeight() return 1600 end
        function e.Device.screen:scaleBySize(v) return v end
        e.SettingsPage={new=function(o) o.onClose=o.onBack;return o end}
        e.require=function(name)
            eq(name,"ui/widget/buttondialog")
            return {new=function(_,value) value.moveFocusTo=function(self,_,row) self.focus=row end;return value end}
        end
        e.OrbitAndroid.onResume=function() end;e.OrbitAndroid.onSuspend=function() end
        for _,name in ipairs({"logic/budgets.lua","ko/reader_companion_service.lua","ko/reader_companion.lua"}) do
            setfenv(assert(loadfile(root..name)),e)()
        end
        return e,e.ReaderCompanionView,manager
    end
    test("reader companion: one bounded local snapshot and four status action rows",function()
        local e,V,m=world();local v=V.open("status")
        eq(e.reads,1);eq(e.decoded,1);eq(#v.dialog.buttons,7);eq(m.shown,1)
        eq(v.dialog.buttons[1][1].id,"setup");eq(v.dialog.buttons[4][1].id,"updates")
        v:close();eq(V.active,nil);eq(m.top,m.base)
    end)
    test("reader companion: missing/version worker uses existing problem without snapshot call",function()
        for _,message in ipairs({"BookSync Companion needed","Update BookSync Companion"}) do
            local e,V=world();e.Companion.workerProblem=function() return message end
            local v=V.open();eq(e.reads,0);eq(e.decoded,0);ok(v.dialog.intro:find(message,1,true))
        end
    end)
    test("reader companion: oversized and excess-row replies are unavailable before presentation",function()
        local e,V=world();e.raw=string.rep("x",16385)
        local v=V.open();eq(e.decoded,0);ok(v.snapshot.unavailable)
        e.raw="snapshot";table.insert(e.snapshot.helpers,{id="excess"});v:paint();ok(v.snapshot.unavailable)
    end)
    test("reader companion: permission Later stays inline and never sets a helper",function()
        local e,V,m=world();local v=V.open("helpers")
        v:toggle(e.snapshot.helpers[3]);eq(v.page,"permission");eq(e.command,nil)
        v.dialog.buttons[2][1].callback();eq(v.page,"helpers");eq(e.command,nil);eq(e.snapshot.helpers[3].on,false)
    end)
    test("reader companion: explicit system return observes permission without enabling helper",function()
        local e,V,m=world();local v=V.open("helpers");v.page="permission";v:paint()
        v:external("permission");eq(m.top,m.base);eq(e.command.action,"permission")
        e.OrbitAndroid:onSuspend();e.snapshot.helpers[3].permission=true;e.done({ok=true})
        e.OrbitAndroid:onResume();m.scheduled[1]()
        eq(v.page,"helpers");ok(v.dialog);eq(v.snapshot.helpers[3].permission,true);eq(v.snapshot.helpers[3].on,false)
        eq(e.command.action,"permission","grant never issues set")
    end)
    test("reader companion: denied/revoked permission stays visible as missing on return",function()
        for _,granted in ipairs({false,true}) do
            local e,V,m=world();e.snapshot.helpers[3].permission=granted
            local v=V.open("helpers");v:external("permission");e.OrbitAndroid:onSuspend()
            e.snapshot.helpers[3].permission=false;e.done({ok=true});V.resume()
            eq(v.snapshot.helpers[3].permission,false);eq(v.snapshot.helpers[3].on,false)
        end
    end)
    test("reader companion: return restores the initiating status control focus",function()
        local e,V,m=world();local v=V.open("status")
        v.dialog.buttons[4][1].callback();eq(e.command.action,"recovery")
        e.OrbitAndroid:onSuspend();e.done({ok=true});V.resume()
        eq(v.page,"status");eq(v.focus,"updates");eq(v.dialog.focus,4)
    end)
    test("reader companion: background permission changes and unrelated resumes never show sheets",function()
        local e,V,m=world();e.snapshot.helpers[3].permission=true
        e.OrbitAndroid:onResume();m.scheduled[1]();eq(m.shown,0)
        local v=V.open();local count=m.shown
        e.OrbitAndroid:onSuspend();e.OrbitAndroid:onResume();m.scheduled[2]();eq(m.shown,count)
        v:close();V.resume();eq(m.shown,count)
    end)
    test("reader companion: another book or changed underlying menu discards return",function()
        for _,change in ipairs({"book","menu","session"}) do
            local e,V,m=world();local v=V.open("helpers");v:external("permission");e.OrbitAndroid:onSuspend()
            if change=="book" then e.current.document={file="other.epub"}
            elseif change=="menu" then m.top={id="another-menu"}
            else e.OrbitAndroid:onReaderReady() end
            local count=m.shown;V.resume();eq(m.shown,count);eq(V.active,nil)
        end
    end)
    test("reader companion: protected changes request existing parent surface with no inline PIN",function()
        local e,V,m=world();e.snapshot.protected=true
        local v=V.open("helpers");v:toggle(e.snapshot.helpers[1])
        eq(e.command.action,"protected");eq(e.command.on,nil);eq(v.dialog,nil);eq(e.snapshot.helpers[1].on,false)
    end)
    test("reader companion: late helper completion after departure cannot repaint",function()
        local e,V,m=world();local v=V.open("helpers");v:toggle(e.snapshot.helpers[1]);eq(e.command.action,"set")
        m.top={id="another-menu"};local count=m.shown;e.done({ok=true});eq(m.shown,count)
        v:close();e.done({error="protected"});eq(m.shown,count)
    end)
    test("reader companion: helper completion in another app cannot show a sheet",function()
        local e,V,m=world();local v=V.open("helpers");v:toggle(e.snapshot.helpers[1])
        e.Library.isForeground=function() return false end
        local count=m.shown;e.done({ok=true});eq(m.shown,count)
    end)
    test("reader companion: navigation is a two-button footer and helper states are values",function()
        local e,V=world()
        for _,page in ipairs({"status","helpers"}) do
            local v=V.open(page);local footer={}
            for _,r in ipairs(v.dialog.rows) do
                ok(r.id~="back" and r.id~="close" and r.id~="protected" and r.id~="recovery")
                if r.id=="wifi" or r.id=="sleep" or r.id=="screen" then eq(r.detail,"Off") end
            end
            local K={px=function(n) return n end,button=function(o) return o end}
            eq(v.dialog.content(K,{},1200,100,function(b,_,_,id) footer[#footer+1]=id end),172)
            eq(#footer,2);eq(footer[1],"protected");eq(footer[2],"back");ok(v.dialog.fitContent)
            v:close()
        end
    end)

end
