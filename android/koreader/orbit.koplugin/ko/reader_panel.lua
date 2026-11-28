-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Opt-in owned reader sheets; all data and native actions stay behind Library.
ReaderPanel = {}
local ReaderSheet = EndSheet:extend{ name="booksync_reader_panel", is_always_active=true, min_button=50, alpha=.6 }

function ReaderSheet:init()
    EndSheet.init(self)
    self.key_events={Close={{"Back"}},Select={{"Press"}},StepMore={{"Right"}},StepLess={{"Left"}}}
end
function ReaderSheet:focusStep(delta)
    local controls=self.focus_controls or {}
    if #controls==0 then return false end
    local old=controls[self.focus_index or 1]
    if old and old.onUnfocus then old:onUnfocus() end
    self.focus_index=((self.focus_index or 1)-1+delta)%#controls+1
    self.keyboard_focus=true
    local current=controls[self.focus_index]
    if current.onFocus then current:onFocus() end
    UIManager:setDirty(self,"ui")
    return true
end
function ReaderSheet:onSelect()
    local current=(self.focus_controls or {})[self.focus_index or 1]
    if current and current.callback then current.callback(); return true end
    return false
end
function ReaderSheet:onStepMore()
    if self.scrub_focus then Library.readerAction(self.ui,"next-chapter"); ReaderPanel.show(self.ui,self.screen,nil,self); return true end
    return self:focusStep(1)
end
function ReaderSheet:onStepLess()
    if self.scrub_focus then Library.readerAction(self.ui,"previous-chapter"); ReaderPanel.show(self.ui,self.screen,nil,self); return true end
    return self:focusStep(-1)
end
function ReaderSheet:control(widget,callback,scrubber)
    if widget.enabled==false then return widget end
    self.focus_controls[#self.focus_controls+1]=widget
    if callback then widget.callback=callback end
    if scrubber and not self.focus_index then self.focus_index=#self.focus_controls end
    return widget
end
function ReaderSheet:touchControl(area,callback)
    self:control(area,callback)
    area.onFocus=function(self) self.focused=true end
    area.onUnfocus=function(self) self.focused=false end
    local stock=area.paintTo
    function area:paintTo(bb,x,y)
        if stock then stock(self,bb,x,y) end
        if self.focused then
            local width,height=self.dimen.w,self.dimen.h
            local ink=require("ffi/blitbuffer").COLOR_BLACK
            bb:paintRect(x,y,width,2,ink); bb:paintRect(x,y+height-2,width,2,ink)
        end
    end
end
function ReaderSheet:rows()
    if not self.scrub_focus then return self.display_rows end
    local rows={}
    for _,row in ipairs(self.display_rows) do
        rows[#rows+1]=row
        if row.kind=="scrubber" then
            rows[#rows+1]={kind="label",text="Prev/Next: one chapter · Select or Back: done"}
        end
    end
    return rows
end
function ReaderSheet:onClose()
    if self.scrub_focus then
        self.scrub_focus=false; self:build(); UIManager:setDirty(self,"ui")
    else ReaderPanel.close() end
    return true
end
function ReaderSheet:onTapAnywhere(_arg,ges)
    if ges and ges.pos and (ges.pos.y<(self.sheet_y or 0)
        or ges.pos.y>(self.sheet_y or 0)+(self.sheet_h or 0)
        or ges.pos.x<self.sheet_x or ges.pos.x>self.screen_w-self.sheet_x) then
        ReaderPanel.close();return true
    end
    return false
end
function ReaderSheet:onCloseDialog() ReaderPanel.close() end
-- The catalog Details page belongs to the Home/detail slice. Keep its existing
-- EndSheet presentation while these reader-only surfaces adopt the kit.
function ReaderSheet:rowWidget(block,w,h,mt)
    local widget=EndSheet.rowWidget(self,block,w,h,mt)
    if block.kind=="button" then self:control(widget) end
    if block.kind=="footer" then
        for _,row in ipairs(widget.buttons_layout or {}) do for _,button in ipairs(row) do self:control(button) end end
    end
    return widget
end
local surface
function ReaderSheet:build()
    local finish=Budgets.span(self.screen..".draw",now_s,log)
    if not surface then
        surface=setfenv(assert(loadfile(SOURCE_DIR.."/ko/ui/reader_surface.lua")),getfenv(1))()
    end
    self.focus_controls={}
    if self.screen=="details" then
        EndSheet.build(self)
        self.sheet_h=self.plan.h;self.sheet_y=0;self.sheet_x=0
        self.too_small=self.plan.h>self.screen_h
        self.frame.height=self.sheet_h
        self[1]=require("ui/widget/container/topcontainer"):new{
            dimen=require("ui/geometry"):new{w=self.screen_w,h=self.screen_h},self.frame}
        finish();return
    end
    local previous=self[1]
    surface.build(self)
    if previous and previous.free then previous:free() end
    if self.keyboard_focus then
        local current=self.focus_controls[self.focus_index or 1]
        if current and current.onFocus then current:onFocus() end
    end
    finish()
end
function ReaderPanel.close()
    local sheet = ReaderPanel.sheet
    ReaderPanel.sheet = nil
    if sheet then
        if sheet.search_input then sheet.search_input:onCloseKeyboard() end
        UIManager:close(sheet)
    end
end
local function button(text, action) return {kind="button", text=text, action=action} end

function ReaderPanel.show(ui, screen, key, reuse, attempt)
    if not Library.closeNativeReaderMenus(ui) then return false end
    if not (ui and ui.document) and screen ~= "details" then return false end
    local paint = Library.paint(screen)
    local book = paint:widget("reader-progress")
    local result = key and book:book(key) or book:reader(ui.document.file)
    local battery = screen == "reader-top-panel" and paint:battery() or nil
    local bottom=screen=="reader-bottom-panel"
    local controls=(screen=="reader-top-panel" or bottom) and paint:widget("reader-controls"):readerControls(ui) or nil
    local native=controls and controls.items and controls.items[1] or {}
    local caps = not bottom and paint:read("capabilities", {limit=1}) or {}
    local account=caps.account or {}
    local m = ReaderPanelPlan.model(result, battery,ui and ui.document and Library.readerMetadata(ui))
    paint:flush()
    local rows = {
        {kind="title", text=m.title}, {kind="label", text=m.author},
        {kind="label", text=m.progress_text}, {kind="progress", value=m.progress},
    }
    local function back() ReaderPanel.close() end
    local function refresh() ReaderPanel.show(ui,screen,key,ReaderPanel.sheet) end
    local function action(name,value,stay)
        return function()
            if not stay then back() end
            Library.readerAction(ui,name,value)
            if stay and ReaderPanel.sheet then refresh() end
        end
    end
    if bottom then
        rows={
            {kind="reader-position",text=native.chapter_title or native.chapter or "Chapters not available yet",
                position=native.position or "Position not available yet"},
            {kind="scrubber",value=native.progress,chapters=native.chapters or {},bookmarks=native.bookmarks or {},
                previous=action("previous-chapter",nil,true),next=action("next-chapter",nil,true),
                seek=function(value) action("seek",value,true)() end},
        }
        local quick=CustomReading and CustomReading.panelRows(ui,refresh,screen) or {}
        local settings=Library.readerSettings(ui)
        local size={kind="reading-choices",group_label="Size · "..settings.size.." pt",choices={
            {text="A−",font_size=14,callback=action("size",ReaderPanelPlan.fontSize(settings.size,-1),true)},
            {text=ReaderPanelPlan.sizeDots(settings.size),font_size=12,enabled=false,callback=function() end},
            {text="A+",font_size=24,callback=action("size",ReaderPanelPlan.fontSize(settings.size,1),true)}}}
        local toggles={kind="reading-choices",group_label="Status bar",values={settings.status,settings.clock},choices={
            {text=(settings.status and "✓ " or "").."Bottom bar",callback=action("status",nil,true),height=50},
            {text=(settings.clock and "✓ " or "").."Clock",callback=action("clock",nil,true),height=50}}}
        if #quick>0 then
            table.insert(rows,{kind="reader-grid",groups={quick[1],size}})
            table.insert(rows,{kind="reader-grid",groups={quick[2],quick[3]}})
            table.insert(rows,{kind="reader-grid",groups={quick[4],toggles}})
        else
            table.insert(rows,toggles)
        end
        local lights={}
        for _,name in ipairs({"light","warmth"}) do
            if type(settings[name])=="number" then
                lights[#lights+1]={text=(name=="light" and "Light · " or "Warmth · ")..settings[name],value=settings[name],name=name,
                    set=function(value) action(name,value,true)() end}
            end
        end
        if #lights>0 then table.insert(rows,{kind="reader-lights",controls=lights}) end
        table.insert(rows,{kind="reader-actions",choices={
            {text="More reading settings…",callback=function() back(); Library.readerAction(ui,"more-settings") end},
            {text="Edit presets",callback=function() back(); if Library.controller() then Library.controller():showSettings("reading") end end}}})
    elseif screen == "reader-top-panel" then
        table.insert(rows, button(m.battery, function() BatteryUI.show() end))
        local text,go
        if caps.account then text,go=AccountView.syncAction(account) end
        if text then table.insert(rows,button(text,function() back(); go() end))
        elseif caps.progress and caps.progress.syncCurrent then
            local sync = button("Sync", function() end)
            local busy = false
            sync.action = function()
                if busy then return end
                busy = true
                local sheet = ReaderPanel.sheet
                sheet.syncing = true
                sync.text = "Syncing…"
                sheet:build(); UIManager:setDirty(sheet, "ui")
                Library.syncCurrent(function(_, message)
                    busy = false
                    sheet.syncing = false
                    -- Never reopen or repaint a dismissed panel over the reading page.
                    if ReaderPanel.sheet ~= sheet or UIManager:getTopmostVisibleWidget() ~= sheet then return end
                    sync.text = message
                    sheet:build(); UIManager:setDirty(sheet, "ui")
                end)
            end
            table.insert(rows, sync)
        end
        table.insert(rows, button("BookSync settings", function()
            back(); if Library.controller() then Library.controller():showSettings() end
        end))
        table.insert(rows, button("Book info", function() ReaderPanel.show(ui, "book-info") end))
        table.insert(rows, {kind="footer", text="Home", action=function()
            back(); if Library.controller() then Library.controller():onOrbitGoHome() end
        end})
        table.insert(rows, {kind="footer", text="KOReader menu", action=function()
            back(); Library.readerAction(ui,"native-menu")
        end})
        local home,settings,info,stock,sync
        for _,r in ipairs(rows) do
            if r.text=="Home" then home=r elseif r.text=="BookSync settings" then settings=r
            elseif r.text=="Book info" then info=r elseif r.text=="KOReader menu" then stock=r
            elseif r.kind=="button" and r.text~=m.battery then sync=r end
        end
        local function cell(r,icon) return {text=r.text,icon=icon,callback=r.action} end
        local header={cell(home,"home")}
        if sync then header[#header+1]=cell(sync,"sync") end
        header[#header+1]=cell(settings,"appbar.settings")
        header[#header+1]={text=native.marked and "Remove bookmark" or "Add bookmark",
            icon="bookmark",marked=native.marked,callback=action("bookmark",nil,true)}
        header[1].width=math.floor(1.6*require("device").screen:scaleBySize(50)); header[1].text="Home"; header[1].keep_label=true
        if sync and sync.text~="Sync" then header[2].width=math.floor(2.8*require("device").screen:scaleBySize(50)) end
        rows={
            {kind="reader-header",text=m.title,author=m.author,choices=header},
            {kind="reader-tiles",choices={
                {text="Contents",icon="toc",callback=action("contents")},
                {text="Bookmarks",icon="bookmark",callback=action("annotations")},
                {text="Search",icon="search",callback=action("search")},
                {text="Go to",icon="goto",callback=action("goto")},cell(info,"info"),cell(stock,"kmenu")}},
            {kind="label",text=(native.chapter or "Chapters not available yet").." · "..m.progress_text,summary=true},
            {kind="progress",value=m.progress},
            button(m.battery,function() BatteryUI.show() end),
            button("Reading settings",function() ReaderPanel.show(ui,"reader-bottom-panel") end),
        }
        -- Keep the mutable sync status row: the header uses its callback and status remains visible.
        if sync then sync.kind="label"; table.insert(rows,sync) end
    else
        local summary=result.items and result.items[1]
        if screen=="details" and summary then
            table.insert(rows,button(summary.local_path and "Open" or caps.download==true and "Download" or "Set up downloads",function()
                local origin=ReaderPanel.sheet
                if summary.local_path then back();Library.open(summary)
                elseif caps.download~=true then back();AccountView.open("opds")
                else DownloadUI.start(origin,summary,function() return ReaderPanel.sheet==origin and topWidget()==origin end) end
            end))
        end
        if summary and summary.series_key and not (caps.series and caps.series.read==false) then
            table.insert(rows, button("View series", function()
                local document=ui and ui.document
                back()
                SeriesUI.show(summary.series_key,function()
                    if not ui or ui.document==document then ReaderPanel.show(ui,screen,key) end
                end)
            end))
        end
        table.insert(rows, {kind="label", text=m.days})
        table.insert(rows, {kind="label", text=m.time})
        table.insert(rows, {kind="label", text=m.pages})
        if screen == "book-info" and m.key then
            table.insert(rows, button("Details", function() ReaderPanel.show(ui, "details") end))
        end
    end
    if not bottom then table.insert(rows, {kind="footer", text=ui and ui.document and "Back to book" or "Back", action=back}) end
    local sheet
    if reuse then
        sheet = reuse
        sheet.model, sheet.display_rows, sheet.native = m, rows, native
        sheet:build()
        if sheet.too_small then
            ReaderPanel.close()
            if bottom then return ReaderPanel.stockConfig(ui.config) else return ReaderPanel.stockMenu(ui.menu) end
        end
        UIManager:setDirty(sheet, "ui")
    else
        ReaderPanel.close()
        sheet = ReaderSheet:new{ui=ui, screen=screen, model=m, display_rows=rows, native=native}
        if sheet.too_small then
            if sheet.free then sheet:free() end
            if bottom then return ReaderPanel.stockConfig(ui.config) else return ReaderPanel.stockMenu(ui.menu) end
        end
        ReaderPanel.sheet = sheet
        UIManager:show(sheet) -- gate: user action (reader top panel, Book info or Details)
    end
    -- A cold projection completes quietly, only while the user-opened surface is still on top.
    if (result.pending or caps.pending or (controls and controls.pending) or (battery and battery.pending)) and (attempt or 0) < 5 then
        local document = ui and ui.document
        UIManager:scheduleIn(0.5, function()
            if ReaderPanel.sheet == sheet and not sheet.syncing and UIManager:getTopmostVisibleWidget() == sheet
                and (not ui or ui.document == document) then
                ReaderPanel.show(ui, screen, key, sheet, (attempt or 0)+1)
            end
        end)
    end
    return true
end
function ReaderPanel.details(key, ui) return ReaderPanel.show(ui, "details", key) end

-- Native builders remain live, including third-party items and invisible search.
function ReaderPanel.stockMenu(menu,...)
    if not (menu and menu.onShowMenu) then return false end
    local args=UIUtil.pack(...)
    return Library.withNativeMenus(menu.ui,function() return menu:onShowMenu(unpack(args,1,args.n)) end)
end
function ReaderPanel.stockConfig(config,...)
    if not (config and config.onShowConfigMenu) then return false end
    local args=UIUtil.pack(...)
    return Library.withNativeMenus(config.ui,function() return config:onShowConfigMenu(unpack(args,1,args.n)) end)
end
local nativeReady=OrbitAndroid.onReaderReady
function OrbitAndroid:onReaderReady(...)
    local result=nativeReady and nativeReady(self,...)
    Library.installReaderMenus(self.ui)
    return result
end
local nativeCloseDocument=OrbitAndroid.onCloseDocument
function OrbitAndroid:onCloseDocument(...)
    Library.restoreReaderMenus(self.ui)
    if nativeCloseDocument then return nativeCloseDocument(self,...) end
end
-- Also reachable from the plugin's existing Tools entry when a native menu is open.
local baseMenu = OrbitAndroid.menuItems
function OrbitAndroid:menuItems(...)
    local rows = baseMenu(self, ...)
    if self.ui and self.ui.document then
        table.insert(rows,1,{text="BookSync reading menu",callback=function() ReaderPanel.show(self.ui,"reader-top-panel") end})
        table.insert(rows, 2, {text="Book info", callback=function() ReaderPanel.show(self.ui, "book-info") end})
    end
    return rows
end
local baseClose = OrbitAndroid.onCloseWidget
function OrbitAndroid:onCloseWidget(...)
    Library.restoreReaderMenus(self.ui)
    if CustomReading and CustomReading.editor then
        CustomReading.editor.return_to=nil
        CustomReading.close()
    end
    if CustomReading and CustomReading.copy_toast then
        UIManager:close(CustomReading.copy_toast)
        CustomReading.copy_toast=nil
    end
    ReaderPanel.close()
    return baseClose(self, ...)
end

-- Reader-only kit compositions consume bounded cached windows. Native document
-- data and navigation stay behind Library; specialist editing remains reachable.
local function navigationButton(text,action)
    return {kind="button",text=text,action=action}
end
local function navigationLimit(kind)
    local h=require("device").screen:getHeight()/(require("device").screen:getWidth()/702)
    local usable=math.min(748,h-24)-64-(kind=="contents" and 92 or 168)
    return math.max(1,math.min(11,math.floor(usable/(kind=="contents" and 52 or kind=="annotations" and 122 or 100))))
end
function ReaderPanel.navigation(ui,kind,offset,tab)
    if not (ui and ui.document) or not Library.closeNativeReaderMenus(ui) then return false end
    local document=ui.document
    local limit=navigationLimit(kind)
    local current
    if kind=="contents" then
        current=Library.readerInput(ui,true).chapter_index
        if offset==nil and current then offset=math.floor((current-1)/limit)*limit end
    end
    local result=Library.readerWindow(ui,kind,offset or 0,limit,current)
    local rows={}
    local title=kind=="contents" and "Contents" or kind=="annotations" and "Bookmarks & highlights" or "Search in this book"
    rows[1]={kind="title",text=title}
    rows[2]={kind="label",text=result.error and "Search unavailable" or result.unavailable and "Native data not available here" or tostring(result.total)..(kind=="search" and " matches" or kind=="contents" and " chapters" or " saved items")}
    for index,item in ipairs(result.items or {}) do
        local row=index
        rows[#rows+1]={kind="navigation-item",item=item,action=function()
            if ui.document~=document then ReaderPanel.close();return end
            if Library.readerNavigate(ui,result.token,row) then ReaderPanel.close() else ReaderPanel.navigation(ui,kind,result.offset,tab) end
        end}
    end
    local function turn(delta)
        if ui.document==document then ReaderPanel.navigation(ui,kind,math.max(0,(result.offset or 0)+delta*limit),tab) end
    end
    rows[#rows+1]={kind="navigation-pages",previous=(result.offset or 0)>0 and function() turn(-1) end or nil,
        next=result.next and function() turn(1) end or nil,limit=limit}
    rows[#rows+1]=navigationButton(kind=="annotations" and "Edit saved items in KOReader…" or kind=="search" and "Native search options…" or "Native Contents options…",function()
        ReaderPanel.close();if ui.document==document then Library.readerNativeAction(ui,kind) end
    end)
    rows[#rows+1]={kind="footer",text="Back to book",action=ReaderPanel.close}
    ReaderPanel.close()
    local sheet=ReaderSheet:new{ui=ui,screen="reader-navigation",display_rows=rows,model={},navigation_kind=kind,
        navigation=result,annotation_tab=tab or "Highlights"}
    if sheet.too_small then
        if sheet.free then sheet:free() end
        return Library.readerNativeAction(ui,kind)
    end
    ReaderPanel.sheet=sheet
    UIManager:show(sheet) -- gate: user action (owned Contents, saved items or search results)
    return true
end
function ReaderPanel.goDialog(ui)
    if not (ui and ui.document) then return false end
    local document=ui.document
    local input=Library.readerInput(ui,true)
    local sheet
    local function edit(key)
        if sheet.go_replace and key~="back" then sheet.go_value="" end
        sheet.go_replace=false
        sheet.go_error=nil
        sheet.go_value=ReaderPanelPlan.keypad(sheet.go_value,key)
        sheet:build();UIManager:setDirty(sheet,"ui")
    end
    local function go()
        if ui.document~=document then ReaderPanel.close();return end
        if Library.readerGo(ui,sheet.go_value,sheet.go_percent) then ReaderPanel.close()
        else sheet.go_error="Enter a valid "..(sheet.go_percent and "percentage" or "page");sheet:build();UIManager:setDirty(sheet,"ui") end
    end
    ReaderPanel.close()
    sheet=ReaderSheet:new{ui=ui,screen="reader-goto",model={},display_rows={},
        go_value=tostring(input.page or ""),go_replace=true,go_total=input.total,go_edit=edit,go_submit=go}
    if sheet.too_small then
        if sheet.free then sheet:free() end
        return Library.readerNativeAction(ui,"goto")
    end
    ReaderPanel.sheet=sheet
    UIManager:show(sheet) -- gate: user action (owned Go to keypad)
    return true
end
function ReaderPanel.search(ui,query,wholeWords)
    if not (ui and ui.document) or #query==0 or #query>512 then return false end
    local document=ui.document
    ReaderPanel.close()
    local info=require("ui/widget/infomessage"):new{text="Searching… (tap to cancel)"}
    UIManager:show(info) -- gate: user action (native cancelable search worker)
    UIManager:forceRePaint()
    local accepted=Library.readerSearch(ui,query,info,function(completed)
        local visible=UIManager:getTopmostVisibleWidget()==info
        info.dismiss_callback=nil;UIManager:close(info)
        if completed and visible and ui.document==document then ReaderPanel.navigation(ui,"search") end
    end,wholeWords)
    if not accepted then UIManager:close(info);Library.readerNativeAction(ui,"search") end
    return accepted
end
function ReaderPanel.searchDialog(ui)
    if not (ui and ui.document) then return false end
    local document=ui.document
    local previous=Library.readerWindow(ui,"search",0,1)
    local dialog
    local function search()
        if ui.document~=document then ReaderPanel.close();return end
        ReaderPanel.search(ui,dialog.search_input:getText(),dialog.search_whole)
    end
    ReaderPanel.close()
    dialog=ReaderSheet:new{ui=ui,screen="reader-search",model={},display_rows={},search_submit=search,
        search_whole=previous.query==nil or previous.whole_words,search_query=previous.query}
    if dialog.too_small then
        if dialog.free then dialog:free() end
        return Library.readerNativeAction(ui,"search")
    end
    ReaderPanel.sheet=dialog
    UIManager:show(dialog) -- gate: user action (owned query sheet, native keyboard)
    dialog.search_input:onShowKeyboard()
    UIManager:setDirty(dialog,"ui")
    return true
end
