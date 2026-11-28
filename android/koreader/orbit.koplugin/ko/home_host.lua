-- SPDX-License-Identifier: AGPL-3.0-or-later
-- One screen owner; widgets receive only an immutable snapshot and a dispatch handle.
DownloadUI={intents={},preparing={}}
function DownloadUI.update(origin)
    if HomeHost.active==origin and topWidget()==origin and not reading() then origin:invalidate() end
end
function DownloadUI.watch(origin,row,wanted,open)
    local job=Library.downloadState(row.key)
    if not job or not job.id then return end
    local intent={id=job.id,open=open};DownloadUI.intents[row.key]=intent
    local function poll()
        if DownloadUI.intents[row.key]~=intent then return end
        if not wanted() then intent.open=false;DownloadUI.intents[row.key]=nil;return end
        Library.downloadControl(row,"status",function(result)
            if DownloadUI.intents[row.key]~=intent then return end
            if not wanted() then intent.open=false;DownloadUI.intents[row.key]=nil;return end
            DownloadUI.update(origin)
            if result.state=="complete" then
                DownloadUI.intents[row.key]=nil
                if intent.open and result.local_path then
                    if HomeHost.active==origin then UIManager:close(origin)
                    elseif ReaderPanel.sheet==origin then ReaderPanel.close() end
                    Library.open({local_path=result.local_path})
                end
            elseif result.error or result.state=="canceled" or result.state=="paused" then
                DownloadUI.intents[row.key]=nil
            else UIManager:scheduleIn(1,poll) end
        end)
    end
    UIManager:nextTick(poll)
end
function DownloadUI.cancel(origin,row)
    local intent=DownloadUI.intents[row.key]
    if intent then intent.open=false;DownloadUI.intents[row.key]=nil end
    Library.downloadControl(row,"cancel",function(result)
        DownloadUI.update(origin)
        if result.state=="canceling" then DownloadUI.watch(origin,row,function()
            return topWidget()==origin and (HomeHost.active==origin or ReaderPanel.sheet==origin)
        end,false) end
    end)
end
function DownloadUI.info(origin,row,wanted)
    local paint=Budgets.span("download-job.paint",now_s,log)
    local job=Library.downloadState(row.key) or {}
    local dialog
    local state=job.state
    local resume=state=="error" or state=="paused" or state=="canceled"
    dialog=require("ui/widget/buttondialog"):new{title=(row.title or "Book").."\n"..(job.progress_text or job.error or "Preparing download"),buttons={{{
        text=resume and "Resume" or "Cancel",callback=function()
            UIManager:close(dialog)
            if resume then Library.downloadControl(row,"resume",function() DownloadUI.watch(origin,row,wanted,false) end)
            else DownloadUI.cancel(origin,row) end
        end},{text="Back",callback=function() UIManager:close(dialog);DownloadUI.watch(origin,row,wanted,false) end}}}}
    UIManager:show(dialog) -- gate: user action (download information)
    paint()
end
function DownloadUI.start(origin,row,wanted)
    local existing=Library.downloadState(row.key)
    if existing and existing.id and existing.state~="complete" then return DownloadUI.info(origin,row,wanted) end
    if DownloadUI.preparing[row.key] then return end
    DownloadUI.preparing[row.key]=true
    local function prepare()
        Library.downloadPrepare(row,function(result)
            if not wanted() then DownloadUI.preparing[row.key]=nil;return end
            local options=result.items or {}
            if result.error or #options==0 then
                DownloadUI.preparing[row.key]=nil
                Library.rememberDownload(row.key,{state="error",error=result.error or "unsupported",progress_text="No supported file available"})
                DownloadUI.update(origin);return
            end
            local paint=Budgets.span("download-options.paint",now_s,log)
            local buttons,dialog={}
            for _,choice in ipairs(options) do
                local selected=choice
                buttons[#buttons+1]={{text=(choice.label or "File").." · "..(choice.bytes and tostring(choice.bytes).." bytes" or "size unknown"),callback=function()
                    DownloadUI.preparing[row.key]=nil;UIManager:close(dialog)
                    Library.downloadStart(row,selected,function(started)
                        if not wanted() then return end
                        DownloadUI.update(origin);DownloadUI.watch(origin,row,wanted,true)
                    end)
                end}}
            end
            buttons[#buttons+1]={{text="Cancel",callback=function() DownloadUI.preparing[row.key]=nil;UIManager:close(dialog) end}}
            dialog=require("ui/widget/buttondialog"):new{title="Download · "..(row.title or "Book").."\n"..(options[1].destination_label or options[1].destination or ""),buttons=buttons}
            dialog.tap_close_callback=function() DownloadUI.preparing[row.key]=nil end
            UIManager:show(dialog) -- gate: user action (download format and destination)
            paint()
        end)
    end
    if NetworkMgr:isConnected() then prepare() else
        local dialog
        dialog=require("ui/widget/buttondialog"):new{title="Not downloaded — connect to get it",buttons={{{text="Connect and download",callback=function()
            UIManager:close(dialog);Library.downloadConnect(function(ready)
                if not wanted() then DownloadUI.preparing[row.key]=nil;return end
                if ready then prepare() else DownloadUI.preparing[row.key]=nil;Library.rememberDownload(row.key,{state="error",error="offline",progress_text="Could not connect · Try again"});DownloadUI.update(origin) end
            end)
        end},{text="Cancel",callback=function() DownloadUI.preparing[row.key]=nil;UIManager:close(dialog) end}}}}
        dialog.tap_close_callback=function() DownloadUI.preparing[row.key]=nil end
        UIManager:show(dialog) -- gate: user action (offline download confirmation)
    end
end

HomeHost = {}
-- Reuse the central visible stack: owned dialogs remain above Home, and a reader
-- placed above Home restores the reading gate. No separate dialog-specific gate.
function HomeHost.foreground()
    if not HomeHost.active then return false end
    local reader=liveUI()
    for _,widget in ipairs(visibleStack()) do
        if reader and widget==reader then return false end
        if widget==HomeHost.active then return true end
    end
    return false
end
function HomeHost.document()
    -- Layout editor publishes the same validated layout-as-data in reader settings.
    HomeEditor.load()
    local d=Library.settings.read("home_layout")
    if d and Layout.validate(d) then return d end
    return Layout.default()
end
function HomeHost.installed()
    local registry={}
    for id in pairs(HomeWidgets.renderers) do registry[id]=WidgetRegistry[id] end
    return registry
end
function HomeHost.create()
    local Input=require("ui/widget/container/inputcontainer")
    local Geom=require("ui/geometry")
    local GestureRange=require("ui/gesturerange")
    local Host=Input:extend{name="booksync_home",covers_fullscreen=true}
    function Host:init()
        self.index=1
        self.dimen=Geom:new{w=Device.screen:getWidth(),h=Device.screen:getHeight()}
        self.ges_events={HomeSwipe={GestureRange:new{ges="swipe",range=self.dimen}}}
        self.key_events={Close={{"Back"}},Next={{"PgFwd"}},Previous={{"PgBack"}}}
        self.unsubscribe=Library.subscribe(function(ev) self:invalidate(ev) end)
        self:rebuild()
    end
    function Host:rebuild()
        if self.widgetRefresh then UIManager:unschedule(self.widgetRefresh); self.widgetRefresh=nil end
        if self.series_key then return SeriesUI.paint(self) end
        if self.list_layout and self.filter.model.query.group~="none" and self.filter.model.query.group~=nil then return SeriesUI.groups(self) end
        if self.list_layout then return CatalogUI.library(self) end
        local refreshDelay,pendingSnapshot
        local paint=Library.paint("home")
        local ready,caps=pcall(paint.capabilities,paint)
        caps=ready and caps or {}
        self.caps=caps
        local account=caps.account or {}
        self.account=account
        local previous=self.signatures or {}
        self.signatures,self.changed_rects={},{}
        self.presentation=self.presentation or {}
        local registry=HomeHost.installed()
        if type(caps.lists) == "table" and not caps.lists.read then registry.lists=nil end
        local resolved=assert(HomeHostPlan.resolve(HomeHost.document(),registry,caps))
        self.index=HomeHostPlan.page(self.index,0,#resolved.pages)
        local page=resolved.pages[self.index]
        local K=HomeWidgets.kit();local px=K.px
        local scale=px
        local gap=scale(12)
        local inset=px(18)
        local top=px(76)
        local bottom=px(58)
        local w,h=self.dimen.w,self.dimen.h
        local canvas=HomeWidgets.canvas(w,h)
        local sharedStats={}
        for _,p in ipairs(page.placements) do
            local rect=HomeHostPlan.rect(p,resolved.grid,w-2*inset,h-top-bottom,gap)
            rect.x,rect.y=rect.x+inset,rect.y+top
            local context=paint:widget(p.widget,p.instance)
            local ok,result=pcall(function()
                local need=(HomeWidgets.needs[p.widget] or HomeHostPlan.need)(p)
                if p.widget == "lists" or p.widget == "booklist" then
                    local geometry=HomeHostPlan.cardGeometry(p,rect,scale)
                    need.limit=math.min(need.limit,math.max(1,geometry.capacity))
                end
                if HomeWidgets.stats[p.widget] then
                    if not sharedStats[need.op] then sharedStats[need.op]=context:read(need.op,need) end
                    return sharedStats[need.op]
                end
                local data=context:read(need.op,need)
                if p.widget=="library" then
                    local merged={}; for k,v in pairs(data) do merged[k]=v end
                    -- This widget owns a summary record, including when the catalog is unsaved.
                    merged.items=nil
                    self.library_total=merged.total;self.library_on_device=merged.on_device
                    merged.storage=context:storage()
                    merged.collections_available=caps.collections==true
                    return merged
                end
                return data
            end)
            result=ok and result or {error="Unavailable"}
            if result.pending then pendingSnapshot=true end
            local signature=UIUtil.encode(result)
            self.signatures[p.instance]=signature
            if previous[p.instance] ~= signature then self.changed_rects[#self.changed_rects+1]=rect end
            local snapshotAccount=caps.account
            if WidgetRegistry[p.widget].localOnly or (p.settings or {}).src=="unopened" or (p.settings or {}).source=="unopened" then snapshotAccount=nil end
            local snapshot=HomeHostPlan.snapshot(result,snapshotAccount)
            self.presentation[p.instance]={p=p,snapshot=snapshot}
            local interval=WidgetRegistry[p.widget].refreshSeconds
            if interval then refreshDelay=math.min(refreshDelay or interval,interval) end
            local dispatch=function(action,row) self:dispatch(action,row,p) end
            local rendered,card=pcall(HomeWidgets.renderers[p.widget],HomeHostPlan.immutable(p),snapshot,dispatch,rect)
            if not rendered then card=HomeWidgets.card(p,HomeHostPlan.snapshot({error="Render failed"}),dispatch,rect) end
            -- Catch deferred KOReader painting too, not only widget construction.
            local Boundary=WidgetContainer:extend{}
            local boundary=Boundary:new{instance=p.instance,card}
            function boundary:paintTo(bb,x,y)
                local done=Budgets.span("widget."..p.widget,now_s,log)
                local painted=pcall(self[1].paintTo,self[1],bb,x,y)
                if not painted then
                    self[1]:free()
                    self[1]=HomeWidgets.card(p,HomeHostPlan.snapshot({error="Render failed"}),dispatch,rect)
                    self[1]:paintTo(bb,x,y)
                end
                done()
            end
            HomeWidgets.put(canvas,boundary,rect.x,rect.y)
        end
        do
            local title=page.name or page.tab or "Home"
            K.label(canvas,title,px(20),px(8),w-px(300),"title",{bold=true})
            local accountStatus,kind=AccountPlan.sync(account,true)
            self.account_status=accountStatus
            local last=Library.settings.read("last_sleep_sync") or {}
            local freshness=HomeHostPlan.syncFreshness(last,os.time(),accountStatus)
            local sync=K.canvas(w-px(350),px(30))
            K.label(sync,freshness,0,0,w-px(350),"caption",{muted=true})
            K.put(canvas,K.hit(sync,{w=w-px(350),h=px(30),text=freshness,
                callback=function() if accountStatus then AccountView.open(kind=="sync" and "sync" or nil) else Library.localWidgetAction("control-sync") end end}),px(20),px(46))
            local signature=freshness..tostring(self.library_total)..title
            if self.header_signature~=signature then self.changed_rects[#self.changed_rects+1]={x=0,y=0,w=w,h=top};self.header_signature=signature end
            K.put(canvas,K.search{count=self.library_total,w=px(194),callback=function() self:search() end},w-px(274),px(12))
            local more=K.canvas(px(52),px(52));K.put(more,K.icon{name="more",w=px(22)},px(15),px(15))
            K.put(canvas,K.hit(K.frame(more,{w=px(52),h=px(52),radius=px(26),border=px(1.5)}),
                {text="⋯",w=px(52),h=px(52),callback=function() self:menu() end}),w-px(70),px(12))
            local total=#resolved.pages;local cell=px(80);local left=(w-total*cell-px(104))/2
            local function arrow(x,delta,enabled)
                local c=K.canvas(px(52),px(52));local icon=K.icon{name="chevR",w=px(18)}
                if delta<0 then icon.rotation_angle=180 end;icon.dim=not enabled
                K.put(c,icon,px(17),px(17))
                K.put(canvas,K.hit(c,{text=delta<0 and "‹" or "›",w=px(52),h=px(52),enabled=enabled,callback=function() self:turn(delta) end}),x,h-bottom)
            end
            arrow(left,-1,self.index>1)
            for i,pg in ipairs(resolved.pages) do
                local index=i;local active=i==self.index;local c=K.canvas(cell,px(52))
                local label=K.text{text=pg.name or pg.tab,w=cell-px(30),size="caption",bold=active,muted=not active}
                local x=(cell-px(15)-label:getSize().w)/2
                K.put(c,K.frame(K.canvas(px(8),px(8)),{w=px(8),h=px(8),radius=px(4),border=px(1.5),ink=active}),x,px(22))
                K.put(c,label,x+px(15),(px(52)-label:getSize().h)/2)
                K.put(canvas,K.hit(c,{text=pg.name or pg.tab,w=cell,h=px(52),callback=function() self:turn(index-self.index) end}),left+px(52)+(i-1)*cell,h-bottom)
            end
            arrow(left+px(52)+total*cell,1,self.index<total)
        end
        self.metrics=paint:flush()
        -- A ready event can race a busy read or the first cold request. Recover
        -- locally while visible, without an unbounded missing-worker loop.
        if pendingSnapshot then
            self.pendingRetries=(self.pendingRetries or 0)+1
            if self.pendingRetries<=20 then refreshDelay=math.min(refreshDelay or 1,1) end
        else self.pendingRetries=nil end
        if refreshDelay then
            self.widgetRefresh=function()
                if HomeHost.active~=self then self.widgetRefresh=nil; return end
                -- Keep the heartbeat until rebuild replaces it: a panel may cover Home
                -- between this check and the queued redraw. Back must still refresh Clock.
                UIManager:scheduleIn(refreshDelay,self.widgetRefresh)
                if HomeHost.foreground() and topWidget()==self and not reading() then self:invalidate() end
            end
            UIManager:scheduleIn(refreshDelay,self.widgetRefresh)
        end
        local old=self[1]
        self[1]=HomeWidgets.ui().Frame:new{padding=0,margin=0,bordersize=0,background=HomeWidgets.ui().BB.COLOR_WHITE,canvas}
        if old then old:free() end
    end
    function Host:menu()
        local menu
        menu=require("ui/widget/buttondialog"):new{title=_("Home"),buttons={
            {{text=_("Browse library"),callback=function() UIManager:close(menu);self:dispatch("browse") end}},
            {{text=_("Edit Home"),callback=function() UIManager:close(menu); HomeEditor.show(self) end}},
            {{text=_("BookSync settings"),callback=function()
                UIManager:close(menu)
                assert(Library.controller(),"BookSync module unavailable"):showSettings()
            end}},
            {{text=_("Cancel"),callback=function() UIManager:close(menu) end}},
        }}
        UIManager:show(menu) -- gate: user action (Home menu)
    end
    function Host:turn(delta)
        if self.series_key then return SeriesUI.page(self,delta) end
        if self.list_layout then return self:listPage(delta) end
        local resolved=HomeHostPlan.resolve((self.list_layout or HomeHost.document()),HomeHost.installed(),self.caps)
        local index=HomeHostPlan.page(self.index,delta,#resolved.pages)
        if index ~= self.index then self.pendingRetries=nil; self.index=index; self:rebuild(); UIManager:setDirty(self,"ui") end
        return true
    end
    function Host:onHomeSwipe(_,ges)
        if ges.direction == "west" then return self:turn(1) end
        if ges.direction == "east" then return self:turn(-1) end
    end
    function Host:onNext() return self:turn(1) end
    function Host:onPrevious() return self:turn(-1) end
    function Host:invalidate()
        self.invalid=true
        if self.redraw then return end
        self.redraw=function()
            self.redraw=nil
            -- Never show/focus Home on an event; only update an already visible Home.
            if HomeHost.active == self and topWidget() == self and not reading() then
                self.invalid=nil; self:rebuild()
                for _,r in ipairs(self.changed_rects) do UIManager:setDirty(self,"ui",Geom:new(r)) end
            end
        end
        UIManager:nextTick(self.redraw)
    end
    function Host:paintTo(bb,x,y)
        -- An event received behind a dialog stays pending. Revealing Home must
        -- enqueue its existing bounded redraw instead of retaining a cold placeholder.
        -- Keep all reads and rebuilding off the paint stack.
        if self.invalid and HomeHost.active==self and topWidget()==self and not reading() then self:invalidate() end
        return Input.paintTo(self,bb,x,y)
    end
    function Host:dispatch(action,row,p)
        if action == "setup" then AccountView.open()
        elseif action == "retry" then self.pendingRetries=nil; Library.retry(); self:rebuild(); UIManager:setDirty(self,"ui")
        elseif action=="control-rotate" then
            UIManager:close(self);Library.localWidgetAction(action,row);return true
        elseif action=="dust-another" or action:match("^control%-") or action == "discover-another" or action == "word-lookup" or action == "light-down" or action == "light-up" then
            Library.localWidgetAction(action,row)
            if action~="word-lookup" then self:rebuild(); UIManager:setDirty(self,"ui") end
        elseif action == "battery" then BatteryUI.show()
        elseif action == "storage" then StorageUI.show()
        elseif action == "browse" then StorageUI.show("browse",function(row)
            if row.root=="authors" or row.root=="series" then self:showList(row.title,"all",{group=row.root=="authors" and "author" or "series"})
            elseif row.root=="all" or row.root=="reading" or row.root=="recently-added" or row.root=="on-device" then self:showList(row.title,row.root)
            else self:dispatch(row.root) end
        end,nil,self.caps)
        elseif action == "libraries" or action == "lists" then StorageUI.show(action,function(row) self:showList(row.title,BookList.source({src=row.src})) end)
        elseif action == "collections" then StorageUI.show("collections",function(row)
            self:showList(row.title,{kind="collection",key=row.key})
        end)
        elseif action == "more" then
            local done=Budgets.span("book-actions.paint",now_s,log)
            local dialog
            local buttons={}
            for _i,item in ipairs(Library.cardActions(row,self.caps)) do
                local choice=item
                buttons[#buttons+1]={{text=_(choice.label),height=Device.screen:scaleBySize(50),enabled=choice.enabled,callback=function()
                    UIManager:close(dialog)
                    self:dispatch(choice.id,row,p)
                end}}
            end
            dialog=require("ui/widget/buttondialog"):new{title=row.title or _("Book"),buttons=buttons}
            UIManager:show(dialog) -- gate: user action (card overflow)
            done()
        elseif action == "status" then
            Library.cardStatus(row,nil,function(result)
                if HomeHost.active~=self or topWidget()~=self or reading() then return end
                self:rebuild();UIManager:setDirty(self,"ui")
                if result.error then
                    UIManager:show(InfoMessage:new{text="Reading status could not be saved. Try again.",timeout=3}) -- gate: user action (status result)
                    return
                end
                local paint=Budgets.span("book-status.paint",now_s,log)
                local dialog
                local released=false
                local function release()
                    if released then return end
                    released=true;Library.cardStatusLeave(result)
                end
                dialog=require("ui/widget/buttondialog"):new{title="Saved on this reader · delivery pending",buttons={{{text="Undo",callback=function()
                    released=true;UIManager:close(dialog)
                    Library.cardStatus(row,result.token,function(reply)
                        if HomeHost.active==self and topWidget()==self and not reading() then
                            self:rebuild();UIManager:setDirty(self,"ui")
                            if reply.error then UIManager:show(InfoMessage:new{text="Status changed. Review the book before trying Undo again.",timeout=3}) end -- gate: user action (Undo result)
                        end
                    end)
                end},{text="Done",callback=function() release();UIManager:close(dialog) end}}}}
                local close=dialog.onCloseWidget
                dialog.onCloseWidget=function(self,...)
                    release();if close then return close(self,...) end
                end
                dialog.tap_close_callback=release
                UIManager:show(dialog) -- gate: user action (status Undo)
                paint();return true
            end)
        elseif action == "remove" then
            Library.cardRemoval(row,nil,function(result)
                if HomeHost.active~=self or topWidget()~=self or reading() then return end
                if result.error or not result.token then
                    UIManager:show(InfoMessage:new{text="Download cannot be removed while open or unavailable.",timeout=3}) -- gate: user action (remove preview result)
                    return
                end
                local paint=Budgets.span("book-removal.paint",now_s,log)
                local dialog
                dialog=require("ui/widget/confirmbox"):new{text="Remove download?\n"..(row.title or "Book").."\n"..result.detail,
                    ok_text="Remove",ok_callback=function()
                        Library.cardRemoval(row,result.token,function(reply)
                            if HomeHost.active~=self or topWidget()~=self or reading() then return end
                            if reply.error then
                                UIManager:show(InfoMessage:new{text="Download changed or cannot be removed. Review it and try again.",timeout=3}) -- gate: user action (remove command result)
                            else self:rebuild();UIManager:setDirty(self,"ui") end
                        end)
                    end}
                UIManager:show(dialog) -- gate: user action (remove download confirmation)
                paint()
            end)
        elseif action == "download" then
            DownloadUI.start(self,row,function() return HomeHost.active==self and topWidget()==self and not reading() end)
        elseif action == "download-cancel" then DownloadUI.cancel(self,row)
        elseif action == "details" then ReaderPanel.details(row.key)
        elseif action == "series" then self:showSeries(row.series_key)
        elseif action == "book" then
            if self.caps.account and not row.local_path and not AccountPlan.login(self.account or {},"opds").available then
                local prompt=require("ui/widget/buttondialog"):new{title="No OPDS login, so it can't download",buttons={{{text="Keep browsing",callback=function() UIManager:close(self.download_prompt) end},{text="Set up",callback=function() UIManager:close(self.download_prompt); AccountView.open("opds") end}}}}
                self.download_prompt=prompt
                UIManager:show(prompt) -- gate: user action (server-only book)
                return
            end
            if not row.local_path and self.caps.download==true then return self:dispatch("download",row) end
            local opened,why=Library.open(row)
            if opened then
                if HomeHost.active==self then UIManager:close(self) end
            elseif why=="missing" then self:rebuild();UIManager:setDirty(self,"ui")
            elseif not (ReaderPanel and row.key and ReaderPanel.details(row.key)) then
                UIManager:show(TextViewer:new{title=row.title or _("Book details"),text=_("This book is not saved on this reader.")}) -- gate: user action (widget book)
            end
        elseif action == "list" then self:showList(row.title,{kind="list",key=row.key})
        elseif action == "all" or action == "device" or action == "group" then
            local need=HomeHostPlan.need(p)
            self:showList((p.settings or {}).title or (action=="device" and "On device" or "Library"),
                action=="device" and "on-device" or p.widget=="library" and "library/all" or need.source,
                action=="group" and {group=row.group} or need.query,need.exclude_current)
        end
    end
    function Host:showSeries(key,onBack)
        if self.series_key then return end
        self.series_key,self.series_offset,self.series_return=key,0,onBack
        self:rebuild(); UIManager:setDirty(self,"ui")
    end
    function Host:showList(title,source,query,exclude_current)
        self.pendingRetries=nil
        if self.series_key or self.list_layout then
            self.catalog_history=self.catalog_history or {}
            self.catalog_history[#self.catalog_history+1]={series_key=self.series_key,series_offset=self.series_offset,
                list_layout=self.list_layout,list_title=self.list_title,filter=self.filter,index=self.index,group_offsets=self.group_offsets,series_return=self.series_return}
        end
        self.series_key=nil; self.series_return=nil; self.group_offsets={}
        if not self.list_layout then self.home_index=self.index end
        self.list_title=title or "Library"
        self.list_layout=Layout.default()
        self.list_layout.grids["android-tablet"].rows=3
        self.list_layout.pages={{id="list",tab="Library",name=self.list_title,placements={{instance="list-books",widget="booklist",version=1,
            x=0,y=0,w=4,h=3,settings={title=self.list_title,source=source,query=query or {},exclude_current=exclude_current,offset=0,limit=8,style=1}}}}}
        local settings=self.list_layout.pages[1].placements[1].settings
        self.filter=FilterView.new{title=self.list_title,source=source,query=query,exclude_current=exclude_current,
            onChange=function(q) settings.query=q; settings.offset=0; self.group_offsets={}; self:rebuild(); UIManager:setDirty(self,"ui") end,
            onApply=function(q) settings.query=q; settings.offset=0; self.group_offsets={}; self:rebuild(); UIManager:setDirty(self,"ui") end,
            onSave=function(saved) self:saveFilter(saved) end}
        self.index=1; self:rebuild(); UIManager:setDirty(self,"ui")
    end
    function Host:listPage(delta)
        if self.filter.model.query.group and self.filter.model.query.group~="none" then return SeriesUI.groupPage(self,delta) end
        local settings=self.list_layout.pages[1].placements[1].settings
        local result=self.list_result or {}
        if delta>0 and not result.next then return true end
        settings.offset=delta>0 and result.next or math.max(0,settings.offset-(self.list_limit or 8))
        self:rebuild(); UIManager:setDirty(self,"ui"); return true
    end
    function Host:search()
        local dialog
        dialog=require("ui/widget/inputdialog"):new{title=_("Search library"),input="",buttons={{
            {text=_("Cancel"),callback=function() UIManager:close(dialog) end},
            {text=_("Search"),callback=function()
                local q=dialog:getInputText()
                UIManager:close(dialog)
                self:showList(_("Search"),"search",{q=q,sort="match"})
            end}}}}
        UIManager:show(dialog) -- gate: user action (owned Home search)
        dialog:onShowKeyboard()
    end
    function Host:saveFilter(saved)
        local document,page=HomeHostPlan.saveFilter(HomeHost.document(),saved,self.list_title)
        if not document then
            UIManager:show(InfoMessage:new{text=_("No room on Home")}) -- gate: user action (save filter)
            return false
        end
        local saved,err=HomeEditor.save(document)
        if not saved then
            UIManager:show(InfoMessage:new{text=err or _("Could not save Home")}) -- gate: user action (save filter)
            return false
        end
        -- gate: user action (save filter)
        UIManager:show(require("ui/widget/buttondialog"):new{title=_("Book list saved on Home").." · "..(function() for _,pg in ipairs(document.pages) do if pg.id==page then return pg.name or pg.tab end end return "Home" end)(),buttons={{{text=_("Go to Home"),callback=function()
            -- Close this toast before rebuilding the initiating host.
            local toast=topWidget(); UIManager:close(toast)
            self.list_layout=nil; self.list_title=nil; self.filter=nil
            local visible=HomeHostPlan.resolve(document,HomeHost.installed(),self.caps)
            for i,p in ipairs(visible.pages) do if p.id==page then self.index=i end end
            self:rebuild(); UIManager:setDirty(self,"ui")
        end}}}}) -- gate: user action (save filter)
        return true
    end
    function Host:onClose()
        if self.series_key then
            local back=self.series_return
            self.series_key=nil; self.series_return=nil
            if back then back(); return true end
            self:rebuild(); UIManager:setDirty(self,"ui"); return true
        end
        if self.catalog_history and #self.catalog_history>0 then
            if self.filter then self.filter:close(false) end
            local previous=table.remove(self.catalog_history)
            self.series_key,self.series_offset=previous.series_key,previous.series_offset
            self.list_layout,self.list_title,self.filter,self.index=previous.list_layout,previous.list_title,previous.filter,previous.index
            self.group_offsets=previous.group_offsets; self.series_return=previous.series_return
            self:rebuild(); UIManager:setDirty(self,"ui"); return true
        end
        if self.list_layout then
            self.list_layout=nil; self.list_title=nil; self.filter=nil; self.index=self.home_index or 1; self.home_index=nil; self:rebuild(); UIManager:setDirty(self,"ui"); return true
        end
        UIManager:close(self)
        return true
    end
    function Host:onCloseWidget()
        if self.widgetRefresh then UIManager:unschedule(self.widgetRefresh); self.widgetRefresh=nil end
        for _,entry in ipairs(self.catalog_history or {}) do if entry.filter then entry.filter:close(false) end end
        self.catalog_history=nil
        if self.filter then self.filter:close(false); self.filter=nil end
        if self.unsubscribe then self.unsubscribe(); self.unsubscribe=nil end
        if self.redraw then UIManager:unschedule(self.redraw); self.redraw=nil end
        if HomeHost.active == self then HomeHost.active=nil;Library.homeVisibilityChanged(false) end
    end
    return Host:new{}
end
function HomeHost.show()
    local problem=Library.companion.workerProblem(_("for BookSync Home"))
    if problem then
        UIManager:show(InfoMessage:new{text=problem}) -- gate: user action (Home)
        return false
    end
    if FinishUI then FinishUI.leaveForHome(liveUI()) end
    if HomeHost.active then UIManager:close(HomeHost.active) end
    -- The explicit Home action is leaving the reading foreground. Permit its bounded
    -- cached reads during construction, before UIManager has pushed the new screen.
    HomeHost.opening=true
    local ok,host=pcall(HomeHost.create)
    HomeHost.opening=nil
    if not ok then error(host) end
    HomeHost.active=host
    UIManager:show(host) -- gate: user action (Home command or menu)
    Library.homeVisibilityChanged(true)
    if Library.settings.read("news_012_pending") then HomeHost.whatsNew() end
    return true
end

-- Only opened after the explicit Home action has left the reading foreground.
function HomeHost.whatsNew()
    local finish=Budgets.span("whats-new.paint",now_s,log)
    local budget=Budgets.get("screens","whats-new")
    local dialog
    local function acknowledge()
        if not Library.settings.read("news_012_pending") then return end
        Library.settings.write("news_012_pending",false)
        G_reader_settings:flush()
    end
    dialog=require("ui/widget/buttondialog"):new{
        title=_("What's new in 0.12"),
        buttons={
            {{text=_("Home is a widget grid you can edit"),enabled=false}},
            {{text=_("Lists (your saved filters) on Home"),enabled=false}},
            {{text=_("BookSync settings on the reader"),enabled=false}},
            {{text=_("Battery: time left at your usual use"),enabled=false}},
            {{text=_("Done"),height=Device.screen:scaleBySize(50),callback=function() acknowledge(); UIManager:close(dialog) end}},
        },
        tap_close_callback=acknowledge,
    }
    assert(Budgets.check(budget,{rows=#dialog.buttons,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}))
    UIManager:show(dialog) -- gate: explicit Home action, above the Home host
    finish()
    return dialog
end
