-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Snapshot-only storage owner. Reuses the Home canvas, native buttons and Library batch.
StorageUI = {}
function StorageUI.bar(canvas,parts,x,y,w,h)
    if not parts or not parts[1] then return end
    local Widget=require("ui/widget/widget")
    local Geom=require("ui/geometry")
    local bar=Widget:new{dimen=Geom:new{w=w,h=h}}
    function bar:paintTo(bb,px,py)
        local u=HomeWidgets.ui(); local offset=0
        bb:paintRect(px,py,w,h,u.BB.COLOR_WHITE)
        -- Home snapshots are immutable proxies: LuaJIT ipairs does not read __index.
        for i=1,4 do
            local part=parts and parts[i]
            if not part then break end
            local width=math.min(w-offset,math.max(0,math.floor(w*(part.fraction or 0))))
            if part.pattern=="solid" then bb:paintRect(px+offset,py,width,h,u.BB.COLOR_BLACK)
            elseif part.pattern=="hatch" then
                for dy=0,h-1 do
                    for dx=-8,width-1,8 do
                        local left=math.max(0,dx+dy%8);local right=math.min(width,dx+dy%8+3)
                        if right>left then bb:paintRect(px+offset+left,py+dy,right-left,1,u.BB.COLOR_BLACK) end
                    end
                end
            elseif part.pattern=="dots" then
                for dx=0,width-1,4 do
                    for dy=0,h-1,4 do bb:paintRect(px+offset+dx,py+dy,1,math.min(2,h-dy),u.BB.COLOR_BLACK) end
                end
            end
            offset=offset+width
        end
        local radius=math.min(math.floor(h/2),Device.screen:scaleBySize(4))
        for dy=0,radius-1 do
            local distance=radius-dy-.5
            local inset=math.max(0,math.ceil(radius-math.sqrt(math.max(0,radius*radius-distance*distance))-.5))
            if inset>0 then
                bb:paintRect(px,py+dy,inset,1,u.BB.COLOR_WHITE)
                bb:paintRect(px+w-inset,py+dy,inset,1,u.BB.COLOR_WHITE)
                bb:paintRect(px,py+h-dy-1,inset,1,u.BB.COLOR_WHITE)
                bb:paintRect(px+w-inset,py+h-dy-1,inset,1,u.BB.COLOR_WHITE)
            end
        end
        bb:paintBorder(px,py,w,h,math.max(1,Device.screen:scaleBySize(1)),u.BB.COLOR_BLACK,radius)

    end
    HomeWidgets.put(canvas,bar,x,y)
end
function StorageUI.widget(p,snapshot,dispatch,rect)
    local finish=Budgets.span("library.storage.widget",now_s,log)
    local s=function(n) return Device.screen:scaleBySize(n) end
    local w,h=rect.w-2,rect.h-2
    local c=HomeWidgets.canvas(w,h)
    local d=snapshot.data or {}; local st=d.storage or {}
    local total=d.freshness and d.freshness.saved and tostring(d.total or 0) or "—"
    local short=p.h==1; local tiny=p.w==1
    local pad=s(8); local half=math.floor((w-3*pad)/2)
    local label=st.widget_label or (st.pending and "Loading storage…" or "Space unavailable")
    if short then
        -- A grid row can be shorter than 68 scaled pixels on a portrait tablet.
        -- Keep the two actions in one band and anchor the measured caption to the
        -- actual tile bottom; the tall tile's fixed offsets would paint outside it.
        local x=tiny and pad or 2*pad+half
        local width=tiny and w-2*pad or half
        HomeWidgets.button(c,(tiny and "Library · " or "")..total.." books ›",pad,0,tiny and width or half,s(50),function() dispatch("all") end)
        if not tiny then
            HomeWidgets.button(c,(st.on_device~=nil and tostring(st.on_device) or d.on_device~=nil and tostring(d.on_device) or "—").." on device ›",
                x,0,width,s(50),function() dispatch("storage") end)
        end
        local caption=HomeWidgets.text(c,label,x,0,width,11)
        caption.padding=0
        local y=h-caption:getSize().h
        caption.overlap_offset[2]=math.max(0,y)
        local barHeight=math.min(s(3),y-s(50))
        if barHeight>0 then StorageUI.bar(c,st.parts,x,y-barHeight,width,barHeight) end
    elseif tiny then
        HomeWidgets.button(c,"Library · "..total.." ›",pad,0,w-2*pad,s(50),function() dispatch("all") end)
        HomeWidgets.text(c,label,pad,s(54),w-2*pad,11)
    else
        local y=short and math.max(0,math.floor((h-s(68))/2)) or s(8)
        HomeWidgets.button(c,"",pad,y,half,s(50),function() dispatch("all") end)
        HomeWidgets.text(c,total,pad,y,half,26,false,true)
        HomeWidgets.text(c,"books in your library",pad,y+s(32),half,12)
        HomeWidgets.button(c,(st.on_device~=nil and tostring(st.on_device) or d.on_device~=nil and tostring(d.on_device) or "—").." on device ›",
            2*pad+half,y,half,s(50),function() dispatch("storage") end)
        StorageUI.bar(c,st.parts,2*pad+half,y+s(50),half,s(6))
        HomeWidgets.text(c,label,2*pad+half,y+s(60),half,11)
        if not short then
            local links={{"Browse library","browse"},{"Authors","group",{group="author"}},{"Series","group",{group="series"}},{"Collections","collections"}}
            if not d.collections_available then table.remove(links,4) end
            local count=math.min(#links,math.max(0,math.floor((h-s(92)-pad)/s(50))))
            local start=h-count*s(50)-pad
            for i,link in ipairs(links) do
                if i>count then break end
                HomeWidgets.button(c,link[1].." ›",pad,start+(i-1)*s(50),w-2*pad,s(50),function() dispatch(link[2],link[3]) end)
            end
        end
    end
    finish()
    return HomeWidgets.ui().Frame:new{padding=0,margin=0,bordersize=1,c}
end
function StorageUI.create(mode,onCollection,onReturn,caps)
    local Input=require("ui/widget/container/inputcontainer")
    local Geom=require("ui/geometry")
    local Page=Input:extend{name="booksync_storage",covers_fullscreen=true}
    function Page:init()
        self.mode=mode or "storage"; self.offset=0; self.focus=1;self.caps=caps or {}
        self.dimen=Geom:new{w=Device.screen:getWidth(),h=Device.screen:getHeight()}
        self.key_events={Close={{"Back"}},Next={{"Down"}},Previous={{"Up"}},Select={{"Press"}}}
        self:rebuild()
    end
    function Page:visible() return not self.closed and UIManager:getTopmostVisibleWidget()==self end
    function Page:rebuild()
        if self.refresh then UIManager:unschedule(self.refresh); self.refresh=nil end
        local sourceMode=self.mode=="libraries" or self.mode=="lists"
        local paint=Library.paint(sourceMode and "booklist-sources" or self.mode=="collections" and "collections" or self.mode=="folder" and "storage-folder" or "storage")
        self.data=sourceMode and paint:sources(self.mode,self.offset,6) or self.mode=="browse" and paint:summary() or self.mode=="collections" and paint:collections(self.offset,6) or paint:storage()
        self.metrics=paint:flush()
        self:draw()
        if self.data.pending and (self.attempts or 0)<6 then
            self.attempts=(self.attempts or 0)+1
            self.refresh=function() self.refresh=nil; if self:visible() then self:rebuild(); UIManager:setDirty(self,"ui") end end
            UIManager:scheduleIn(.5,self.refresh)
        end
    end
    function Page:draw()
        if self.mode=="storage" then return CatalogUI.storage(self) end
        local finish=Budgets.span("storage."..self.mode..".render",now_s,log)
        local s=function(n) return Device.screen:scaleBySize(n) end
        local w,h=self.dimen.w,self.dimen.h; local c=HomeWidgets.canvas(w,h)
        self.controls={}
        local function button(label,y,callback,allowBusy)
            local b=HomeWidgets.button(c,label,s(16),y,w-s(32),s(54),function()
                if not self.busy or allowBusy then callback() end
            end,allowBusy or not self.busy)
            self.controls[#self.controls+1]=b
            return b
        end
        HomeWidgets.text(c,self.mode=="browse" and "Library" or self.mode=="libraries" and "Libraries" or self.mode=="lists" and "Your lists" or self.mode=="collections" and "Collections" or self.mode=="folder" and "Download folder" or "Storage",s(16),s(12),w-s(32),24,false,true)
        if self.busy then HomeWidgets.text(c,"Working…",w-s(150),s(18),s(134),16) end
        local y=s(62)
        if self.mode=="browse" then
            local counts=self.data.browse or {}
            HomeWidgets.text(c,self.data.coverage or "Catalog indexes not saved yet",s(16),y,w-s(32),14);y=y+s(32)
            local roots={{"All books","all",self.data.total},{"In progress","reading",self.data.in_progress},
                {"Recently added","recently-added",self.data.total},{"On this device","on-device",self.data.on_device},
                {"Libraries","libraries",counts.libraries},{"Authors","authors",counts.authors},{"Series","series",counts.series},
                {"Collections","collections",counts.collections},{"Your lists","lists",counts.lists}}
            for _,root in ipairs(roots) do
                if not (root[2]=="libraries" and self.caps.libraries==false or root[2]=="collections" and self.caps.collections==false or root[2]=="lists" and self.caps.lists and self.caps.lists.read==false) then
                button(root[1].." · "..tostring(root[3] or "—").." ›",y,function() self:onClose();if onCollection then onCollection({root=root[2],title=root[1]}) end end);y=y+s(56)
                end
            end
            if self.data.pending or self.data.error then button("Retry",y,function() Library.retry();self:rebuild() end);y=y+s(56) end
        elseif self.mode=="libraries" or self.mode=="lists" then
            if self.data.pending or self.data.error or #(self.data.items or {})==0 then
                button(self.data.pending and "Loading…" or self.data.error and "Couldn't load sources · Retry" or not (self.data.freshness and self.data.freshness.saved) and "Not saved yet" or "No sources",y,function() Library.retry();self:rebuild() end);y=y+s(56)
            end
            for _,row in ipairs(self.data.items or {}) do
                button(row.title.." · "..tostring(row.count or "—").." ›",y,function() self:onClose();if onCollection then onCollection(row) end end);y=y+s(56)
            end
            if self.offset>0 then button("Previous",y,function() self.offset=math.max(0,self.offset-6);self:rebuild() end);y=y+s(56) end
            if self.data.next then button("Next",y,function() self.offset=self.data.next;self:rebuild() end);y=y+s(56) end
        elseif self.mode=="collections" then
            if self.data.pending or self.data.error or #(self.data.items or {})==0 then
                button(self.data.pending and "Loading…" or self.data.error and "Couldn't load collections · Retry" or not (self.data.freshness and self.data.freshness.saved) and "Not saved yet" or "No collections",y,function() Library.retry(); self:rebuild() end)
            end
            for _,row in ipairs(self.data.items or {}) do
                button(row.title.." · "..tostring(row.count or "—").." ›",y,function() self:onClose(); if onCollection then onCollection(row) end end); y=y+s(56)
            end
            if self.offset>0 then button("Previous",y,function() self.offset=math.max(0,self.offset-6); self:rebuild() end); y=y+s(56) end
            if self.data.next then button("Next",y,function() self.offset=self.data.next; self:rebuild() end); y=y+s(56) end
        elseif self.mode=="folder" then
            for _,row in ipairs(self.data.folders or {}) do
                button((self.data.folder==row.id and "• " or "")..row.label,y,function() self:run("storage.folder",{folder=row.id},true) end); y=y+s(56)
            end
            if self.data.pending then HomeWidgets.text(c,"Loading…",s(16),y,w-s(32),16) end
            if self.data.error then button("Folder unavailable · Retry",y,function() Library.retry(); self:rebuild() end); y=y+s(56) end
        else
            local plan=StoragePlan.page(self.data)
            HomeWidgets.text(c,plan.caption or plan.message,s(16),y,w-s(32),18,false,true); y=y+s(32)
            StorageUI.bar(c,plan.parts,s(16),y,w-s(32),s(24)); y=y+s(32)
            for _,part in ipairs(plan.parts) do
                HomeWidgets.text(c,part.label.." · "..part.display,s(16),y,w-s(32),16); y=y+s(28)
            end
            if plan.warning then
                HomeWidgets.put(c,require("ui/widget/textboxwidget"):new{text=plan.warning,width=w-s(32),face=HomeWidgets.ui().Font:getFace("cfont",14)},s(16),y)
                y=y+s(80)
            end
            if plan.message and plan.caption then HomeWidgets.text(c,plan.message,s(16),y,w-s(32),14); y=y+s(30) end
            for _,action in ipairs(plan.actions) do
                button(action.label.."\n"..action.detail,y,function() self.confirm=action; self:confirmation() end); y=y+s(58)
            end
            if self.data.pending or self.data.error then button("Retry",y,function() Library.retry(); self:rebuild() end); y=y+s(56) end
            button("Catalog cache limit ›",y,function() StorageUI.cacheLimit() end); y=y+s(56)
        end
        button("Back",math.min(y+s(8),h-s(62)),function() self:onClose() end,true)
        local old=self[1]; self[1]=HomeWidgets.ui().Frame:new{padding=0,margin=0,bordersize=0,background=HomeWidgets.ui().BB.COLOR_WHITE,c}
        if old then old:free() end
        self.focus=math.min(self.focus,#self.controls)
        finish()
    end
    function Page:confirmation()
        if self.busy then return end
        local finish=Budgets.span("storage.confirm.paint",now_s,log)
        Budgets.get("screens","storage-confirm")
        local title,body=StoragePlan.confirm(self.confirm)
        local dialog
        dialog=require("ui/widget/buttondialog"):new{title=title.."\n"..body,buttons={{{text="Cancel",height=Device.screen:scaleBySize(50),callback=function() UIManager:close(dialog) end},
            {text=self.confirm.id=="covers" and "Clear" or "Remove",height=Device.screen:scaleBySize(50),callback=function()
                UIManager:close(dialog); self:run("storage.free",{action=self.confirm.id,token=self.confirm.token})
            end}}}}
        dialog:moveFocusTo(1,1)
        UIManager:show(dialog) -- gate: user action (Storage removal confirmation)
        finish()
    end
    function Page:run(op,args,folder)
        if self.busy then return end
        self.busy=true; self:draw(); UIManager:setDirty(self,"ui")
        local accepted,retire=Library.storageCommand(op,args,function(result)
            if self.closed then return end
            self.busy=false
            result=result or {error="Storage unavailable"}
            if self:visible() then
                self.data=result
                if folder and not self.data.error then self:onClose() else self:draw(); UIManager:setDirty(self,"ui") end
            else self.pending_result=result end
            Library.retry(); Library.changed({kind="storage"})
        end)
        self.pending_cancel=retire
    end
    function Page:moveFocus(delta)
        local old=self.controls[self.focus]
        if old.onUnfocus then old:onUnfocus() end
        for _=1,#self.controls do
            self.focus=(self.focus-1+delta)%#self.controls+1
            if self.controls[self.focus].enabled~=false then break end
        end
        if self.controls[self.focus].onFocus then self.controls[self.focus]:onFocus() end
        UIManager:setDirty(self,"ui")
        return true
    end
    function Page:paintTo(bb,x,y)
        local finish=Budgets.span("storage.screen.paint",now_s,log)
        -- A user popup may cover the initiating page. Adopt its completed local result
        -- only when the page is visible again; never reopen a closed page or read here.
        if self.pending_result and self:visible() then
            self.data=self.pending_result; self.pending_result=nil; self:draw()
        end
        Input.paintTo(self,bb,x,y)
        finish()
    end
    function Page:onNext() return self:moveFocus(1) end
    function Page:onPrevious() return self:moveFocus(-1) end
    function Page:onSelect() self.controls[self.focus].callback(); return true end
    function Page:onCloseWidget()
        self.closed=true
        if self.pending_cancel then self.pending_cancel();self.pending_cancel=nil end
        if self.refresh then UIManager:unschedule(self.refresh); self.refresh=nil end
        if StorageUI.active==self then StorageUI.active=nil end
    end
    function Page:onClose() if self.closed then return true end; self:onCloseWidget(); UIManager:close(self); Library.changed({kind="storage"}); if onReturn then onReturn() end; return true end
    return Page:new{}
end
function StorageUI.show(mode,onCollection,onReturn,caps)
    local problem=Library.companion.workerProblem("for Storage")
    if problem then UIManager:show(InfoMessage:new{text=problem}); return false end -- gate: user action (Storage)
    StorageUI.opening=true
    local ok,page=pcall(StorageUI.create,mode,onCollection,onReturn,caps)
    StorageUI.opening=nil
    if not ok then error(page) end
    StorageUI.active=page
    UIManager:show(page) -- gate: user action (Storage, Collections or Download folder)
    return page
end
function StorageUI.cacheLimit()
    local finish=Budgets.span("storage.cache-limit.paint",now_s,log)
    local budget=Budgets.get("screens","settings-library")
    local row=OrbitAndroid:settingRow("storage_limit_mb")
    local dialog
    local buttons={}
    for _,choice in ipairs(row.sub_item_table or {}) do
        buttons[#buttons+1]={{text=choice.text,height=Device.screen:scaleBySize(50),callback=function()
            UIManager:close(dialog); choice.callback()
        end}}
    end
    buttons[#buttons+1]={{text="Back",height=Device.screen:scaleBySize(50),callback=function() UIManager:close(dialog) end}}
    assert(#buttons<=budget.rows,"Cache limit row budget exceeded")
    dialog=require("ui/widget/buttondialog"):new{title="Catalog cache limit",buttons=buttons}
    UIManager:show(dialog) -- gate: user action (Storage cache limit)
    finish()
end
