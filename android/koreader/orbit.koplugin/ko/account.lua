-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Owned account pages and forms use the kit, native keyboard and bounded Library worker port.
AccountView = {}
function AccountView.read(paint)
    local own=not paint
    paint=paint or Library.paint("account")
    local a=paint:accountState()
    if own then paint:flush() end
    return a
end
function AccountView.open(kind)
    Library.accountReturned()
    if AccountView.active then AccountView.active:close() end
    local v=setmetatable({alive=true,state=AccountView.read(),page="summary",focus=kind or "account"},{__index=AccountView})
    AccountView.active=v
    v:paint();if kind then v:form(kind) end
    return v
end
function AccountView:close()
    self.alive=false; self:retireCommand(); self.password=nil
    if self.dialog then UIManager:close(self.dialog); self.dialog=nil end
    if self.backdrop then UIManager:close(self.backdrop);self.backdrop=nil end
    if AccountView.active==self then AccountView.active=nil end
    Library.changed({kind="account"})
    local settings=SettingsView and SettingsView.active
    if settings and settings.alive and UIManager:getTopmostVisibleWidget()==settings.dialog then settings:paint() end
end
function AccountView:form(kind)
    self.kind=kind; self.page="form"; self.error=nil
    local l=kind=="account" and self.state or AccountPlan.login(self.state,kind)
    self.server,self.username,self.password=l.server or "",l.username or "",nil
    self.focus="server"; self:paint()
end
function AccountView:retireCommand()
    if self.pending_cancel then self.pending_cancel();self.pending_cancel=nil end
end
function AccountView:back()
    self:retireCommand(); self.busy=false; self.password=nil; self.error=nil
    if self.page=="summary" then self:close(); return end
    if self.page=="signout" then self.focus="signout"

    else self.focus=self.kind or "account" end
    self.page="summary"; self:paint()
end
function AccountView:command(op,args)
    if self.busy then return end
    self:retireCommand()
    self.busy=true; self.error=nil
    local before=self.state
    self.password=nil
    self:paint()
    local accepted,retire=Library.accountCommand(op,args,function(result)
        if not self.alive then return end
        self.busy=false
        if result.error then
            self.error=AccountPlan.error(result.error); self.focus=self.error[3]
            if UIManager:getTopmostVisibleWidget()==self.dialog then self:paint() end
            return
        end
        self.state=result.state or self.state
        Library.retry()
        if op=="account.signIn" then
            self.result,self.returnFocus=AccountPlan.result(before,self.state); self.page="result"; self.focus="done"
        else self.page="summary"; self.focus=op=="account.signOut" and "account" or self.kind end
        -- Completion may update only the still-visible, explicitly opened form.
        if UIManager:getTopmostVisibleWidget()==self.dialog then self:paint() end
    end)
    self.pending_cancel=retire
    args.password=nil
end
function AccountView:edit(field)
    if self.busy then return end
    local dialog
    local function clear() dialog:setInputText(""); dialog.input=""; UIManager:close(dialog) end
    dialog=require("ui/widget/inputdialog"):new{title=({server="Server",username="User name",password="Password"})[field],
        input=field=="password" and "" or self[field],text_type=field=="password" and "password" or nil,
        buttons={{{text="Cancel",callback=clear},{text="Use",callback=function()
            local value=dialog:getInputText()
            local max=field=="server" and 2048 or field=="username" and 100 or 1024
            if #value<=max then self[field]=value; self.error=nil
            else self.error={"That entry is too long","Shorten it and try again.",field} end
            clear(); self.focus=field; self:paint()
        end}}}}
    UIManager:show(dialog) -- gate: user action (account keyboard)
    dialog:onShowKeyboard()
end
function AccountView:paint()
    if not self.alive then return end
    if self.page=="summary" and self.state.pending then self.state=AccountView.read() end
    local finish=Budgets.span("account." .. self.page .. ".paint",now_s,log)
    Budgets.get("screens","account-" .. self.page)
    local buttons={}
    local focus=1
    local function row(id,text,action,enabled,options)
        buttons[#buttons+1]={{id=id,text=text,align="left",enabled=enabled~=false,callback=action or function() end}}
        for k,v in pairs(options or {}) do buttons[#buttons][1][k]=v end
        if id==self.focus then focus=#buttons end
    end
    local a=self.state
    local title="Your server"
    if self.page=="summary" then
        if a.signedIn then
            row("identity","Signed in as",nil,false,{info=true,detail=a.username or "your account"})
            row("address","Your server",nil,false,{info=true,detail=a.server or "Not saved"})
            row("connection","Connection",nil,false,{info=true,detail=a.connected==true and "Connected" or "Signed in"})
            row("configured","What BookSync set up",nil,false,{info=true,sub="Sync: "..AccountPlan.status(AccountPlan.login(a,"sync")).." · OPDS: "..AccountPlan.status(AccountPlan.login(a,"opds"))})
            row("account","Sign in again…",function() self:form("account") end,true,{sub="If your password changed or sync says you are signed out"})
            row("signout","Sign out",function() self.page="signout"; self.focus="keep"; self:paint() end,true,{sub="Asks first. Keeps your downloaded books and progress"})
        else
            row("account","Sign in to your server",function() self:form("account") end,true,{sub="Once, with your server account. BookSync then sets up sync and OPDS for you"})
            row("until","Until you sign in",nil,false,{info=true,sub=AccountPlan.login(a,"sync").available and "Stats come from this reader only. Your own sync login still works." or "Stats come from this reader only, and your place doesn’t sync"})
        end
        if a.signedIn or AccountPlan.login(a,"sync").set or AccountPlan.login(a,"opds").set then
            row("logins","LOGINS",nil,false,{info=true,section=true})
            for _,k in ipairs({"sync","opds"}) do
                if a.signedIn or AccountPlan.login(a,k).set then
                    row(k,AccountPlan.names[k],function() self:form(k) end,true,{detail=AccountPlan.status(AccountPlan.login(a,k))})
                end
            end
        end
    elseif self.page=="signout" or self.page=="remove" then
        local out=self.page=="signout"
        title=out and "Sign out of your server?\n" .. AccountPlan.signout(a) or
            "Remove the " .. AccountPlan.names[self.kind] .. "?\n" .. (self.kind=="sync" and "This reader stops syncing your place until a sync login is set again." or
            "This reader can't browse or download from your server until an OPDS login is set again. Downloaded books stay.") .. " Nothing changes on your server."
        row("keep",out and "Stay signed in" or "Keep it",function() self:back() end)
        row("confirm",out and "Sign out" or "Remove",function() self:command(out and "account.signOut" or "login.remove",{kind=self.kind}) end,not self.busy)
    elseif self.page=="result" then
        title="Signed in as " .. (a.username or "your account") .. "\n" .. table.concat(self.result,"\n")
        row("done","Done",function() self.page="summary"; self.focus=self.returnFocus; self:paint() end)
    else
        title=self.kind=="account" and "Sign in to your server" or AccountPlan.names[self.kind] .. " · " .. AccountPlan.status(AccountPlan.login(a,self.kind)) .. "\n" ..
            (self.kind=="sync" and "The sync login KOReader uses to send your place between devices." or "For catalog browsing and downloads.") .. " It works with or without your server account."
        title=title .. "\nEach row opens the keyboard."
        for _,f in ipairs({"server","username","password"}) do
            local label=({server="Server",username="User name",password="Password"})[f]
            local value=self[f]
            if f=="password" then value=value and value~="" and "••••••" or "Enter password"
            elseif value=="" then value=f=="server" and "Your server address" or "Your user name" end
            row(f,label .. ": " .. value,function() self:edit(f) end,not self.busy)
        end
        if self.kind~="account" and not self.busy then
            local l=AccountPlan.login(a,self.kind)
            if a.signedIn and l.origin=="user" then row("replace","Replace with the account's",function() self:command("login.replace",{kind=self.kind}) end) end
            if l.set then row("remove","Remove " .. AccountPlan.names[self.kind] .. "…",function() self.page="remove"; self.focus="keep"; self:paint() end) end
        end
        row("cancel","Cancel",function() self:back() end)
        row("save",self.busy and "Signing in…" or self.kind=="account" and "Sign in" or "Save",function()
            self:command(self.kind=="account" and "account.signIn" or "login.save",{kind=self.kind,server=self.server,username=self.username,password=self.password})
        end,not self.busy and self.server~="" and self.username~="" and self.password~=nil and self.password~="")
    end
    if self.error then
        title=title .. "\n" .. self.error[1] .. "\n" .. self.error[2]
        if self.error[3]=="phone" then row("phone","Phone setup · on the X4 build",function() end) end
    end
    assert(#buttons<=Budgets.get("screens","account-" .. self.page).displayRows,"Account display row budget exceeded")
    local display={}
    for _,line in ipairs(buttons) do
        local b=line[1]
        local head,sub=b.text:match("^(.-) · (.*)$")
        local name,value=b.text:match("^(.-): (.+)$")
        display[#display+1]={id=b.id,text=name or head or b.text,sub=b.sub or sub,detail=b.detail or value,section=b.section,keyboard=self.page=="form" and (b.id=="server" or b.id=="username" or b.id=="password"),callback=b.enabled and b.callback or nil,enabled=b.enabled}
    end
    for i,line in ipairs(buttons) do
        local b=line[1]
        if b.info then display[i].callback=nil;display[i].enabled=true end
        if b.section then display[i].h=Device.screen:getWidth()/702*36 end
    end
    local modal=self.page~="summary"
    local heading,subtitle=title:match("^([^\n]+)\n(.*)$")
    if self.page=="summary" then heading="Your server" end
    local actions={}
    if modal then
        local keep={}
        for _,r in ipairs(display) do
            if r.id=="cancel" or r.id=="save" or r.id=="done" or r.id=="keep" or r.id=="confirm" then actions[#actions+1]=r
            else keep[#keep+1]=r end
        end
        display=keep
        for _,r in ipairs(display) do r.h=Device.screen:getWidth()/702*52 end
    end
    local scale=Device.screen:getWidth()/702
    local dialog=SettingsPage.new{title=heading or title,subtitle=modal and self.page=="form" and (self.kind=="account" and "Use your server account, once. BookSync then sets up sync and OPDS for you." or subtitle) or (not modal and "BookSync settings" or nil),
        modal=modal,fitContent=self.page=="result",startY=self.page=="form" and scale*86 or self.page=="result" and scale*64 or nil,w=modal and scale*580 or nil,intro=modal and self.page~="form" and subtitle or nil,h=modal and self.page~="result" and scale*(#display*52+194+(self.page~="form" and 170 or 0)+(self.error and 35 or 0)) or nil,rows=display,onBack=function() self:back() end,
        content=function(K,c,w,y,put)
            if modal then
                local p=K.px
                if self.page=="form" then
                    K.label(c,self.error and self.error[1] or "Each row opens KOReader's keyboard.",p(24),y+p(7),w-p(48),"caption",{bold=self.error~=nil,muted=not self.error})
                    if self.error then K.label(c,self.error[2],p(24),y+p(28),w-p(48),"caption") end
                end
                local aw=(w-p(48)-p(12)*(#actions-1)) / math.max(1,#actions)
                for i,r in ipairs(actions) do
                    local button=K.button{text=r.text,w=aw,h=p(52),enabled=r.enabled,variant=i==#actions and "solid" or "outline",callback=r.callback}
                    if r.enabled==false then button[1].background=K.tile;button[1].color=K.rule end
                    put(button,p(24)+(i-1)*(aw+p(12)),y+p(self.error and 65 or 30),r.id)
                end
                return y+p(self.error and 65 or 30)+p(52)
            end
        end}
    dialog.buttons=buttons
    dialog.focus=focus
    if modal and self.drawnPage=="summary" then self.backdrop=self.dialog
    elseif self.dialog then UIManager:close(self.dialog) end
    if not modal and self.backdrop then UIManager:close(self.backdrop);self.backdrop=nil end
    self.drawnPage=self.page
    self.dialog=dialog
    UIManager:show(dialog) -- gate: user action (account form; completion requires visible initiating form)
    if self.state.pending and (self.attempt or 0)<6 then
        self.attempt=(self.attempt or 0)+1
        UIManager:scheduleIn(0.5,function()
            if self.alive and self.page=="summary" and UIManager:getTopmostVisibleWidget()==self.dialog then self:paint() end
        end)
    end
    finish()
end
function AccountView.syncAction(a)
    local text,kind,note=AccountPlan.sync(a)
    return text, function() AccountView.open(kind) end, note
end
