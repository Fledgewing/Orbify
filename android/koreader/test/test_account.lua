-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,here)
    local root=here .. "/../orbit.koplugin/"
    local e=setmetatable({},{__index=_G})
    for _,path in ipairs({"logic/account.lua","logic/budgets.lua"}) do setfenv(assert(loadfile(root .. path)),e)() end
    local P=e.AccountPlan
    local function login(origin) return {set=origin~=nil,available=origin~=nil,origin=origin} end
    test("account: sign-out names exactly what stops for account-only, own sync and mixed logins",function()
        local a={signedIn=true,sync=login("account"),opds=login("account")}
        local t=P.signout(a); ok(t:find("Sync stops",1,true)); ok(t:find("Browsing and downloading",1,true)); ok(not t:find("own sync",1,true))
        a.sync=login("user"); t=P.signout(a); ok(not t:find("Sync stops",1,true)); ok(t:find("sync keeps working",1,true))
        a.sync=login("account"); a.opds=login("user"); t=P.signout(a); ok(t:find("Sync stops",1,true)); ok(t:find("still download",1,true)); ok(not t:find("Browsing and downloading",1,true))
    end)
    test("account: kept login and result focus follow the first changed login",function()
        local rows,f=P.result({sync=login("user")},{sync=login("user"),opds={set=true,outcome="created"}})
        eq(f,"opds"); ok(rows[1]:find("Kept: the one you set",1,true)); ok(rows[1]:find("Replace",1,true)); eq(rows[2],"OPDS login: Created")
        rows,f=P.result({}, {sync=login("user"),opds={set=true,outcome="created"}})
        eq(f,"opds"); ok(rows[1]:find("Kept: the one you set",1,true),"worker provenance is authoritative even after a cold initial read")
        rows,f=P.result({}, {sync={set=true,outcome="found"},opds=login("account")}); eq(f,"sync"); eq(rows[1],"Sync login: Found")
        rows,f=P.result({sync=login("user"),opds=login("user")},{sync=login("user"),opds=login("user")}); eq(f,"account")
        rows,f=P.result({sync=login("account"),opds=login("account")},{sync=login("account"),opds=login("account")}); eq(f,"account"); eq(rows[1],"Sync login: Found")
    end)
    test("account: surface states and all errors stay neutral",function()
        eq(P.sync({signedIn=false},true),"Not signed in · Sign in")
        eq(P.sync({signedIn=true},true),"No sync login · Set up")
        eq(P.sync({sync=login("user")}),nil)
        for _,id in ipairs({"unauthorized","unavailable","too-old","two-step"}) do ok(P.error(id)[1]); ok(P.error(id)[3]) end
        for _,id in ipairs({"summary","form","signout","remove","result"}) do eq(e.Budgets.get("screens","account-" .. id).spawns,0) end
    end)
    -- Run the actual view/controller with stand-ins for native widgets and the worker.
    local shown,completion,current,commands={},nil,nil,{}
    local nativeRequire=require
    e.require=function(name)
        if name=="ui/widget/buttondialog" then return {new=function(_,args)
            args.moveFocusTo=function(self,x,y) self.focus=y end
            return args
        end} end
        if name=="ui/widget/inputdialog" then return {new=function(_,args)
            args.onShowKeyboard=function() end
            args.getInputText=function() return "typed-secret" end
            args.setInputText=function(self,s) self.cleared=s end
            return args
        end} end
        return nativeRequire(name)
    end
    e.SettingsPage={new=function(o) o.onClose=o.onBack;return o end}
    e.Device={screen={getWidth=function() return 700 end,scaleBySize=function(_,n) return n end}}
    e.now_s=function() return 1 end; e.log=function() end
    e.UIManager={show=function(_,d) current=d; shown[#shown+1]=d end,close=function(_,d) if current==d then current=nil end end,
        getTopmostVisibleWidget=function() return current end,scheduleIn=function() end}
    e.Library={paint=function() return {accountState=function() return {signedIn=true,sync=login("user"),opds=login("account")} end,flush=function() end} end,
        accountReturned=function() end,retry=function() end,changed=function() end,accountCommand=function(op,args,done)
            commands[#commands+1]={op=op,kind=args.kind,password=args.password}; completion=done
        end}
    setfenv(assert(loadfile(root .. "ko/account.lua")),e)()
    local function tap(v,id)
        for _,line in ipairs(v.dialog.buttons) do for _,b in ipairs(line) do if b.id==id then return b.callback() end end end
        error("missing action " .. id)
    end
    local function focused(v) return v.dialog.buttons[v.dialog.focus][1].id end
    test("account flows: Remove asks with Keep focused; Back, Save and Replace return to login",function()
        local v=e.AccountView.open("sync"); tap(v,"remove"); eq(v.page,"remove"); eq(focused(v),"keep")
        tap(v,"keep"); eq(v.page,"summary"); eq(focused(v),"sync")
        v:form("sync"); tap(v,"remove"); v:back(); eq(v.page,"summary"); eq(focused(v),"sync")
        v:form("sync"); tap(v,"replace"); eq(commands[#commands].op,"login.replace"); completion({state={signedIn=true,sync=login("account"),opds=login("account")}})
        eq(v.page,"summary"); eq(focused(v),"sync")
        v:form("opds"); tap(v,"remove"); tap(v,"confirm"); eq(commands[#commands].op,"login.remove")
        completion({state={signedIn=true}}); eq(focused(v),"opds")
        v:form("sync"); v.server="https://library.invalid"; v.username="fixture"; v.password="transient"
        v:paint(); tap(v,"save"); eq(v.password,nil); eq(commands[#commands].op,"login.save")
        completion({state={sync=login("user")}}); eq(focused(v),"sync"); v:close()
    end)
    test("account flows: every error clears secrets and focuses its recovery",function()
        for _,code in ipairs({"unauthorized","unavailable","too-old","two-step"}) do
            local v=e.AccountView.open("account"); v:command("account.signIn",{password="temporary"})
            eq(v.password,nil); completion({error=code}); eq(v.error,P.error(code)); eq(focused(v),P.error(code)[3]); v:close()
        end
    end)
    test("account flows: sign-out and result Done restore exact focus; closed form never reopens",function()
        local v=e.AccountView.open(); tap(v,"signout"); eq(focused(v),"keep"); tap(v,"keep"); eq(focused(v),"signout")
        tap(v,"signout"); v:back(); eq(focused(v),"signout")
        tap(v,"signout"); tap(v,"confirm"); completion({state={signedIn=false,sync=login("user")}}); eq(focused(v),"account")
        v:form("account"); v:command("account.signIn",{}); completion({state={signedIn=true,sync=login("user"),opds={set=true,outcome="created"}}})
        eq(v.page,"result"); tap(v,"done"); eq(focused(v),"opds")
        v:form("account"); v:command("account.signIn",{}); local done=completion; v:close(); local count=#shown; done({state={signedIn=true}}); eq(#shown,count)
    end)
    test("account flows: native password field is masked, cleared and never included in a paint",function()
        local v=e.AccountView.open("sync"); v:edit("password")
        local keyboard=current
        eq(keyboard.text_type,"password"); keyboard.buttons[1][2].callback()
        eq(keyboard.cleared,""); eq(keyboard.input,""); eq(v.password,"typed-secret")
        for _,line in ipairs(v.dialog.buttons) do for _,b in ipairs(line) do ok(not b.text:find("typed-secret",1,true)) end end
        v:back(); eq(v.password,nil); eq(focused(v),"sync"); v:close()
    end)
    test("account UI: only the neutral library port owns commands and state",function()
        local f=assert(io.open(root .. "ko/account.lua","rb")); local text=f:read("*a"); f:close()
        for _,forbidden in ipairs({"Jni.","Companion.","/auth/","/opds/","bookorbit","BookOrbit","saveSettings","io.open","os.execute","io.popen"}) do
            ok(not text:find(forbidden,1,true),forbidden)
        end
    end)

    test("account flows: hidden error results cannot repaint over reading; Close invalidates Home",function()
        local v=e.AccountView.open("account"); v:command("account.signIn",{}); current={name="reader"}
        local count=#shown; completion({error="unauthorized"}); eq(#shown,count)
        local invalidations=0; e.Library.changed=function(ev) eq(ev.kind,"account"); invalidations=invalidations+1 end
        v:close(); eq(invalidations,1); e.Library.changed=function() end
    end)

    test("account summary: signed-out guidance and signed-in ordered value rows",function()
        local v=e.AccountView.open()
        v.state={signedIn=false};v:paint()
        eq(#v.dialog.rows,2);eq(v.dialog.rows[1].text,"Sign in to your server")
        ok(v.dialog.rows[1].sub);eq(v.dialog.rows[2].text,"Until you sign in")
        v.state={signedIn=true,username="reader",server="https://fixture.example.test",sync=login("account"),opds=login("account")};v:paint()
        local names={"Signed in as","Your server","Connection","What BookSync set up","Sign in again…","Sign out","LOGINS","Sync login","OPDS login"}
        eq(#v.dialog.rows,#names)
        for i,name in ipairs(names) do eq(v.dialog.rows[i].text,name) end
        ok(v.dialog.rows[5].sub);ok(v.dialog.rows[6].sub);ok(v.dialog.rows[7].section)
        eq(v.dialog.rows[8].detail,"Set up by your account");ok(v.dialog.rows[8].callback)
        v.result={"Sync login: Found","OPDS login: Created"};v.page="result";v:paint()
        eq(v.dialog.fitContent,true);eq(v.dialog.h,nil)
        v.state={signedIn=false,sync={},opds={}};v.page="summary";v:paint()
        eq(#v.dialog.rows,2);eq(v.dialog.rows[1].text,"Sign in to your server");eq(v.dialog.rows[2].text,"Until you sign in")
        v:close()
    end)

end
