-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E)
    local function load(plan,late,constructor)
        local invoked=0
        local function old() invoked=invoked+1 end
        local sandbox=setmetatable({f=old},{__call=function(self,...) return self.f(...) end})
        local inherited={_init=old,onResume=sandbox,onCloseDocument=sandbox,stopPlugin=old}
        inherited.__index=inherited
        local legacy=setmetatable({new=old,name="retired-fixture",init=old,onStart=old,onReaderReady=sandbox,onSuspend=sandbox,onCloseWidget=sandbox,download=old,default_settings={sync_forward=1}},inherited)
        local client={request=old,download=old}
        local loader={enabled_plugins={legacy},loaded_plugins=late and {[legacy.name]=legacy} or {},createPluginInstance=constructor and function(_,p) local instance=p:new({ui="fixture-ui"});instance:_init();instance:init();instance:onStart();return instance end or nil}
        local env=setmetatable({Library={bootstrap=function() return plan and {ok="1",body="fixture"} or {ok="0"} end},
            Cache={decode=function() return plan end},HomePlan={},PluginLoader=loader,package={loaded={fixture_client=client}}},{__index=_G})
        local chunk=assert(loadfile(E.SOURCE_DIR.."/ko/retirement.lua"));setfenv(chunk,env);chunk()
        return env,legacy,client,loader,function() return invoked end
    end
    test("retirement: a neutral descriptor disables complete classes before any constructor",function()
        local e,p,client,loader,count=load({plugins={"retired-fixture"},modules={"fixture_client"},settings_key="fixture"},false,true)
        ok(e.SyncRetirement.safe);local instance=loader:createPluginInstance(p);eq(instance.ui,"fixture-ui");instance:onReaderReady();instance:onCloseDocument();p:onReaderReady();p:onResume();p:onSuspend();p:onCloseDocument();p:onCloseWidget();p:stopPlugin();p:download();client:request();client:download();eq(count(),0)
        eq(e.NativeRetirement.defaults.sync_forward,1)
    end)
    test("retirement: missing, late and unknown startup seams never activate the owned writer",function()
        eq(load(nil,false,true).SyncRetirement.safe,false)
        eq(load({plugins={"retired-fixture"},modules={"fixture_client"}},true,true).SyncRetirement.safe,false)
        eq(load({plugins={"retired-fixture"},modules={}},false,false).SyncRetirement.safe,false)
    end)
    test("retirement: malformed descriptor does not claim safety",function()
        eq(load({plugins="invalid",modules={}},false,true).SyncRetirement.safe,false)
    end)
    test("library bootstrap: one local row has a deterministic byte and round-trip budget",function()
        local b=E.Budgets.libraryBootstrap
        ok(E.Budgets.check(b,{rows=1,bytes=100,spawns=0,network=0,roundTrips=1,snapshotBytes=100}))
        ok(not E.Budgets.check(b,{rows=1,bytes=16385,spawns=0,network=0,roundTrips=1,snapshotBytes=16385}))
        eq(b.network,0);eq(b.spawns,0)
    end)
    test("library bootstrap: untrusted companion sends nothing and oversized metadata fails closed",function()
        local calls=0
        local env=setmetatable({Budgets=E.Budgets,now_s=function() return 1 end,log=function() end,
            Companion={state=function() return "untrusted" end,LIBRARY_BOOTSTRAP="bootstrap",AUTHORITY="fixture"},
            Jni={call=function() calls=calls+1;return {ok="1",body=string.rep("x",16385)} end}},{__index=_G})
        setfenv(assert(loadfile(E.SOURCE_DIR.."/ko/library_bootstrap.lua")),env)()
        eq(env.Library.bootstrap().ok,"0");eq(calls,0)
        env.Companion.state=function() return "ok" end
        eq(env.Library.bootstrap().why,"budget");eq(calls,1)
    end)

end
