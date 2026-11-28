-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Native reader adapter behind Library. No server contract is involved in local styles.
-- KOReader 9192014d: readerfont.lua:163-179,212-226,269-275;
-- readertypeset.lua:73-75,541-557; creoptions.lua:581-592 (gamma lookup).
local gamma = {.3,.35,.4,.45,.5,.55,.6,.65,.7,.75,.8,.85,.9,.95,.98,1,1.02,1.05,1.1,1.15,1.2,1.25,1.3,1.35,1.4,1.45,
    1.5,1.6,1.7,1.8,1.9,2,2.1,2.2,2.3,2.4,2.5,2.6,2.7,2.8,2.9,3,3.5,4,4.5,5,5.5,6,7,8,9,10,11,12,13,14,15}
local function span(id) return Budgets.span("library.reading-style." .. id, now_s, log) end
local function scale(n) return require("device").screen:scaleBySize(n) end
local function nearestGamma(value)
    local best=1
    for i,v in ipairs(gamma) do if math.abs(v-value)<math.abs(gamma[best]-value) then best=i end end
    return best-1
end
function Library.readingCustom(screen)
    local finish=span("read")
    local b=Budgets.get("screens",screen or "settings-reading")
    assert(Budgets.check(b,{rows=1,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}))
    local record=ReadingStyle.record(S.custom_reading)
    finish(); return record
end
function Library.readingChoices(ui)
    if not ui then return {} end
    if not ui.booksync_reading_choices then
        ui.booksync_reading_choices = ui.doc_settings and ui.doc_settings:readSetting("booksync_reading_choices") or {}
    end
    return ui.booksync_reading_choices
end
function Library.readingSupported(ui)
    return ui and ui.rolling and ui.font and ui.typeset and ui.document and ui.document.setFontFace ~= nil
end
function Library.readingFace(index, copied)
    local f=ReadingStyle.fonts[index]
    local cre=require("document/credocument"):engineInit()
    local face=copied or f.face
    local path, faceindex=cre.getFontFaceFilenameAndFaceIndex(face)
    if not path then face=f.fallback; path,faceindex=cre.getFontFaceFilenameAndFaceIndex(face) end
    return face, path or f.file, faceindex
end
function Library.readingApply(ui,key,choice,deferUpdate,screen)
    local finish=span("apply")
    if not Library.readingSupported(ui) then finish(); return false end
    local custom=Library.readingCustom(screen or "reader-top-panel")
    local value
    if choice=="custom" then value=custom[key] else value=ReadingStyle.presets[key][choice][2] end
    local config=ui.font.configurable
    if key=="font" then
        local face
        if choice=="custom" then face=Library.readingFace(custom.fontIndex,custom.face)
        elseif value then face=Library.readingFace(value)
        else face=ui.document.default_font end
        ui.font.font_face=face; ui.document:setFontFace(face)
        config.font_base_weight=choice=="custom" and custom.weight or 0
        ui.document:setFontBaseWeight(config.font_base_weight)
        -- Book's own permits embedded fonts; the other choices use the selected face.
        ui.typeset.configurable.embedded_fonts=choice==1 and 1 or 0
        ui.document:setEmbeddedFonts(ui.typeset.configurable.embedded_fonts)
    elseif key=="margins" then
        local m=ui.typeset.unscaled_margins
        -- scaleBySize rounds up (koreader-base ffi/framebuffer.lua:414).
        -- Calibrate at a large size so a fractional screen scale is not rounded
        -- to the next whole factor, then guard floating-point ceil overshoot.
        local unscaled=value/(scale(10000)/10000)
        if scale(unscaled)>value then unscaled=unscaled-0.000001 end
        ui.typeset.configurable.h_page_margins={unscaled,unscaled}
        ui.typeset.unscaled_margins={unscaled,m[2],unscaled,m[4]}
        ui.typeset:onSetPageMargins(ui.typeset.unscaled_margins)
    elseif key=="spacing" then
        config.line_spacing=math.floor(value*100+.5)
        ui.document:setInterlineSpacePercent(config.line_spacing)
    elseif key=="contrast" then
        config.font_gamma=nearestGamma(1+value)
        ui.document:setGammaIndex(config.font_gamma)
    end
    local selected=Library.readingChoices(ui); selected[key]=choice
    if ui.doc_settings then ui.doc_settings:saveSetting("booksync_reading_choices",selected) end
    if not deferUpdate and key~="margins" then ui:handleEvent(require("ui/event"):new(key=="contrast" and "RedrawCurrentView" or "UpdatePos")) end
    finish(); return true
end
function Library.readingSave(record,ui,screen)
    local finish=span("save")
    local old=Library.readingCustom(screen)
    S.custom_reading=ReadingStyle.record(record); saveSettings()
    local changed,marginApplied,layoutChanged=false,false,false
    for _,key in ipairs({"font","spacing","contrast","margins"}) do
        local different=key=="font" and (old.fontIndex~=S.custom_reading.fontIndex or old.face~=S.custom_reading.face or old.weight~=S.custom_reading.weight)
            or key~="font" and old[key]~=S.custom_reading[key]
        if different and Library.readingChoices(ui)[key]=="custom" then
            local applied=Library.readingApply(ui,key,"custom",true,screen)
            changed=applied or changed
            layoutChanged=layoutChanged or (applied and key~="contrast")
            marginApplied=marginApplied or (key=="margins" and applied)
        end
    end
    if changed and not marginApplied then ui:handleEvent(require("ui/event"):new(layoutChanged and "UpdatePos" or "RedrawCurrentView")) end
    finish()
end
function Library.readingCopy(ui)
    local finish=span("copy")
    local f=Library.readingSupported(ui) and ui.font or nil
    local function value(key, default) return f and f.configurable[key] or G_reader_settings:readSetting("copt_" .. key) or default end
    local margins=f and ui.typeset.unscaled_margins or {20,0,20,0}
    if not f then
        local pair=G_reader_settings:readSetting("copt_h_page_margins")
        if type(pair)=="table" then margins={pair[1],0,pair[2],0} end
    end
    local face=f and f.font_face or G_reader_settings:readSetting("cre_font")
    local fontIndex=1
    for i,font in ipairs(ReadingStyle.fonts) do
        if face==font.face then fontIndex=i; face=nil; break end
    end
    local record={fontIndex=fontIndex,face=face,
        weight=value("font_base_weight",0),margins=scale(margins[1]),spacing=value("line_spacing",100)/100,
        contrast=(gamma[value("font_gamma",15)+1] or 1)-1}
    local copied,previous=ReadingStyle.copy(Library.readingCustom(),record)
    Library.readingSave(copied,ui); finish(); return previous
end

-- A book remembers which choices it uses; newly edited device-local Custom values take
-- effect when that book next opens. Restore silently, without opening a surface.
function Library.readingRestore(ui)
    if not Library.readingSupported(ui) then return end
    local applied,marginApplied,layoutChanged=false,false,false
    for _,key in ipairs({"font","spacing","contrast","margins"}) do
        if Library.readingChoices(ui)[key]=="custom" then
            applied=Library.readingApply(ui,key,"custom",true,"reader-top-panel") or applied
            layoutChanged=layoutChanged or key~="contrast"
            marginApplied=marginApplied or key=="margins"
        end
    end
    if applied and not marginApplied then ui:handleEvent(require("ui/event"):new(layoutChanged and "UpdatePos" or "RedrawCurrentView")) end
end
local baseReady=OrbitAndroid.onReaderReady
if baseReady then
    function OrbitAndroid:onReaderReady(...)
        local result=baseReady(self,...)
        Library.readingRestore(self.ui)
        return result
    end
end

-- Native reader controls stay behind Library, like the existing style adapter above.
-- Only bounded, already-loaded native state is copied; no TOC load or sidecar read.
function Library.readerInput(ui,summaryOnly)
    local finish=span("controls-input")
    local view=ui.view or {}
    local total=ui.document.info and ui.document.info.number_of_pages
    local page=view.state and view.state.page or ui.rolling and ui.rolling.current_page
    local input={page=page,total=total,marked=view.dogear_visible==true,chapters={},bookmarks={}}
    -- Keep the reader's current dogear visible even when a long annotation list
    -- needs sampling. It is already a cached scalar, with no anchor lookup.
    if input.marked and type(page)=="number" then input.bookmarks[1]=page end
    local toc=ui.toc and ui.toc.toc or {}
    input.chapter_total=#toc
    -- Cached TOC is ordered by native page. A bounded binary lookup identifies
    -- the current chapter without a full-table walk, even for very large books.
    local low,high,index=1,#toc,0
    for _=1,Budgets.readerControls.tocComparisons do
        if low>high or type(page)~="number" then break end
        local middle=math.floor((low+high)/2)
        local at=toc[middle].page
        if type(at)~="number" then break end
        if at<=page then index=middle; low=middle+1 else high=middle-1 end
    end
    if index>0 then
        input.chapter_index=index
        input.chapter_title=type(toc[index].title)=="string" and toc[index].title:sub(1,256) or nil
    end
    do
        input.path=type(ui.document.file)=="string" and ui.document.file:sub(1,4096) or nil
        input.md5=ui.doc_settings and ui.doc_settings:readSetting("partial_md5_checksum")
        input.toc_loaded=ui.toc and type(ui.toc.toc)=="table" or false
        input.chapter_exact=low>high and type(page)=="number"
        if input.chapter_exact then
            local nextEntry=toc[index+1]
            input.next_exists=nextEntry~=nil
            if nextEntry and type(nextEntry.page)=="number" and nextEntry.page>page then
                input.next_page=nextEntry.page
                input.next_title=type(nextEntry.title)=="string" and nextEntry.title:sub(1,256) or nil
            end
        end
    end
    if summaryOnly then finish();return input end
    local annotations=ui.annotation and ui.annotation.annotations or {}
    -- The companion owns marker projection. Copy at most 64 cached scalar entries
    -- per kind, sampled across long books rather than scanning the document.
    for i=1,math.min(Budgets.readerControls.markersPerKind,#toc) do
        local item=toc[math.floor((i-1)*#toc/math.min(Budgets.readerControls.markersPerKind,#toc))+1]
        input.chapters[i]=item.page
    end
    for i=1,math.min(Budgets.readerControls.markersPerKind,#annotations) do
        local item=annotations[math.floor((i-1)*#annotations/math.min(Budgets.readerControls.markersPerKind,#annotations))+1]
        if not item.drawer and #input.bookmarks<Budgets.readerControls.markersPerKind then
            local pageNumber=type(item.page)=="number" and item.page
                or ui.bookmark and ui.bookmark:getBookmarkPageNumber(item)
            if not input.marked or pageNumber~=page then input.bookmarks[#input.bookmarks+1]=pageNumber end
        end
    end
    finish(); return input
end
function Library.readerMetadata(ui)
    local props=ui.doc_props or {}
    local description=type(props.description)=="string" and props.description~="" and props.description:sub(1,4096) or nil
    return {total_pages=ui.document.info and ui.document.info.number_of_pages,description=description}
end
function Library:readerControls(ui)
    return self:read("reader.controls",{limit=1,native=Library.readerInput(ui)})
end
function Library.readerAction(ui,action,value)
    local finish=span(action)
    if not (ui and ui.document) then finish(); return false end
    local target,method
    if action=="native-menu" then
        finish(); return ReaderPanel.stockMenu(ui.menu)
    elseif action=="more-settings" then
        finish()
        if ReaderPanel.stockConfig and ui.config then return ReaderPanel.stockConfig(ui.config) end
        return ReaderPanel.stockMenu(ui.menu)
    elseif action=="contents" then finish();return ReaderPanel.navigation(ui,"contents")
    elseif action=="annotations" then finish();return ReaderPanel.navigation(ui,"annotations")
    elseif action=="bookmark" then target,method=ui.bookmark,"onToggleBookmark"
    elseif action=="goto" then finish();return ReaderPanel.goDialog(ui)
    elseif action=="search" then finish();return ReaderPanel.searchDialog(ui)
    elseif action=="previous-chapter" then target,method=ui.rolling or ui.paging,"onGotoPrevChapter"
    elseif action=="next-chapter" then target,method=ui.rolling or ui.paging,"onGotoNextChapter"
    elseif action=="seek" then target,method=ui.rolling or ui.paging,"onGotoPercentage"; value=math.max(0,math.min(100,value))
        if ui.rolling then method="onGotoPercent" else value=value/100 end
    elseif action=="size" then target,method=ui.font,"onSetFontSize"
    elseif (action=="status" or action=="clock") and ReadingStatus and ReadingStatus.session and ReadingStatus.session.ui==ui then
        local session=ReadingStatus.session
        if action=="status" then session.bottom_visible=not session.bottom_visible
        else session.top_visible=session.top_visible==false; session.geometry_key=nil end
        ReadingStatus.relayout(ui)
        UIManager:setDirty(ui,"ui")
        finish(); return true
    elseif action=="status" then
        local footer=ui.view and ui.view.footer
        if footer then
            footer:applyFooterMode(footer.mode==0 and footer.mode_list.page_progress or 0)
            G_reader_settings:saveSetting("reader_footer_mode",footer.mode)
            footer:onUpdateFooter(true)
        end
        finish(); return footer~=nil
    elseif action=="clock" and ui.rolling then
        local enabled=not ui.rolling.cre_top_bar_enabled
        ui.rolling:onSetStatusLine(enabled and 0 or 1)
        finish(); return true
    elseif action=="light" or action=="warmth" then
        local device=require("device")
        if device:hasFrontlight() and (action=="light" or device:hasNaturalLight()) then
            local power=device:getPowerDevice()
            if action=="light" then power:setIntensity(value) else power:setWarmth(value) end
            finish(); return true
        end
    end
    local result=target and target[method] and target[method](target,value)
    finish(); return result~=nil and result~=false
end
function Library.readerSettings(ui)
    local finish=span("controls-state")
    local device=require("device")
    local power=device.hasFrontlight and device:hasFrontlight() and device:getPowerDevice()
    local footer=ui.view and ui.view.footer
    local session=ReadingStatus and ReadingStatus.session
    local owned=session and session.ui==ui
    local result={size=ui.font and ui.font.configurable.font_size or 22,status=owned and session.bottom_visible or not owned and footer and footer.mode~=0,
        clock=owned and session.top_visible~=false or not owned and ui.rolling and ui.rolling.cre_top_bar_enabled,
        light=power and power:frontlightIntensity(),
        warmth=power and device:hasNaturalLight() and power:frontlightWarmth()}
    finish(); return result
end

-- Reader-instance seams only. Native builders, invisible menu search and saved
-- custom gesture dispatch stay untouched (KOReader 9192014d readermenu:478-524).
function Library.closeNativeReaderMenus(ui)
    local menu=ui and ui.menu
    local config=ui and ui.config
    if menu and menu.menu_container then
        if not menu.onCloseReaderMenu then return false end
        menu:onCloseReaderMenu()
    end
    if config and config.config_dialog then
        if not config.onCloseConfigMenu then return false end
        config:onCloseConfigMenu()
    end
    return true
end
function Library.readerMenusEnabled() return S.clean_menus==true end
function Library.readerHookOrigin(method)
    local fn=type(method)=="table" and method.f or method
    if type(fn)~="function" then return false end
    local source=debug.getinfo(fn,"S").source or ""
    return source:match("apps/reader/modules/readermenu%.lua$")~=nil or source:match("apps/reader/modules/readerconfig%.lua$")~=nil
end
local function ownsReaderHook(method,wrapper)
    return method==wrapper or type(method)=="table" and method.f==wrapper
end
function Library.restoreReaderMenus(ui)
    local state=ui and ui.booksync_reader_menu_hooks
    if not state then return end
    state.active=false
    for _,hook in ipairs(state.hooks) do
        if ownsReaderHook(hook.target[hook.name],hook.wrapper) then rawset(hook.target,hook.name,hook.raw) end
    end
    ui.booksync_reader_menu_hooks=nil
end
function Library.withNativeMenus(ui,work)
    local state=ui and ui.booksync_reader_menu_hooks
    local previous=state and state.bypass
    if state then state.bypass=true end
    local result=UIUtil.pack(pcall(work))
    if state then state.bypass=previous end
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
function Library.installReaderMenus(ui)
    if not (ui and ui.document) then return false end
    local previous=ui.booksync_reader_menu_hooks
    if not Library.readerMenusEnabled() then Library.restoreReaderMenus(ui);return false end
    if previous and previous.active and previous.menu==ui.menu and previous.config==ui.config then return #previous.hooks>0 end
    Library.restoreReaderMenus(ui)
    local state={active=true,menu=ui.menu,config=ui.config,hooks={}}
    ui.booksync_reader_menu_hooks=state
    local function hook(target,name,screen,accept)
        local original=target and target[name]
        if not original or not Library.readerHookOrigin(original) then return end
        local record={target=target,name=name,raw=rawget(target,name)}
        record.wrapper=function(self,...)
            -- Another plugin may wrap this method later. Its outer chain remains
            -- stock; disabling/closing never overwrites a wrapper we do not own.
            if not state.active or state.bypass or not ownsReaderHook(target[name],record.wrapper)
                or not Library.readerMenusEnabled() or self.ui~=ui or not ui.document or not accept(self,...) then
                return original(self,...)
            end
            return ReaderPanel.show(ui,screen)
        end
        rawset(target,name,record.wrapper);state.hooks[#state.hooks+1]=record
    end
    local function tap(self) return self.activation_menu~="swipe" end
    local function south(self,gesture) return self.activation_menu~="tap" and gesture and gesture.direction=="south" end
    local function north(self,gesture) return self.activation_menu~="tap" and gesture and gesture.direction=="north" end
    local function always() return true end
    hook(ui.menu,"onTapShowMenu","reader-top-panel",tap)
    hook(ui.menu,"onSwipeShowMenu","reader-top-panel",south)
    hook(ui.menu,"onPressMenu","reader-top-panel",always)
    hook(ui.menu,"onKeyPressShowMenu","reader-top-panel",always)
    hook(ui.config,"onTapShowConfigMenu","reader-bottom-panel",tap)
    hook(ui.config,"onSwipeShowConfigMenu","reader-bottom-panel",north)
    return #state.hooks>0
end
function Library.setReaderMenus(ui,enabled)
    S.clean_menus=enabled;saveSettings()
    if S.clean_menus==true then Library.installReaderMenus(ui) else Library.restoreReaderMenus(ui) end
end

-- Bounded windows over native state that the reader has already loaded. Opening a
-- list never loads a TOC, parses a sidecar, filters the full annotation table or
-- asks the document engine to search on the UI thread.
local function navigationText(value,maximum)
    local text=type(value)=="string" and value or tostring(value or "")
    local cut=math.min(#text,maximum)
    while cut>0 and text:byte(cut+1) and text:byte(cut+1)>=128 and text:byte(cut+1)<192 do cut=cut-1 end
    return (text:sub(1,cut):gsub("[%c]"," "))
end
local function navigationList(ui,kind)
    if kind=="contents" then return ui.toc and ui.toc.toc
    elseif kind=="annotations" then return ui.annotation and ui.annotation.annotations
    elseif kind=="search" then
        local search=ui.booksync_search
        if search and search.document==ui.document and search.file==ui.document.file then return search.results end
    end
end
function Library.readerWindow(ui,kind,offset,limit,current)
    local finish=span("navigation-window")
    local document=ui and ui.document
    local list=document and navigationList(ui,kind)
    if type(list)~="table" then finish();return {items={},unavailable=true,total=0} end
    limit=math.max(1,math.min(kind=="contents" and 11 or 8,math.floor(limit or 8)))
    offset=math.max(0,math.min(math.floor(offset or 0),math.max(0,#list-1)))
    local serial=(ui.booksync_navigation_serial or 0)+1;ui.booksync_navigation_serial=serial
    local session={document=document,file=document.file,list=list,kind=kind,serial=serial,refs={}}
    local rows={}
    for index=offset+1,math.min(#list,offset+limit) do
        local item=list[index]
        if type(item)=="table" then
            session.refs[#rows+1]={index=index,item=item}
            local title,location,depth
            local display={}
            if kind=="contents" then
                display.page=item.page
                title=item.title or "Chapter";depth=math.max(0,math.min(5,(tonumber(item.depth) or 1)-1))
                location=item.page
                if ui.annotation and ui.annotation.getPageRef then location=ui.annotation:getPageRef(item.xpointer or item.page,item.page) or location end
            elseif kind=="annotations" then
                title=(item.drawer and "Highlight · " or "Bookmark · ")..navigationText(item.text or item.notes or "Saved position",240)
                display.annotation_kind=item.drawer and "highlight" or "bookmark"
                display.quote=navigationText(item.text or "Saved position",360)
                display.note=navigationText(item.note,180)
                display.chapter=navigationText(item.chapter,120)
                location=ui.bookmark and ui.bookmark.getBookmarkPageString and ui.bookmark:getBookmarkPageString(item.page) or item.page
            else
                title=(item.prev_text or "").." "..(item.matched_text or "Match").." "..(item.next_text or "")
                local before=item.prev_text or ""
                local from=math.max(1,#before-27)
                while from<=#before and before:byte(from)>=128 and before:byte(from)<192 do from=from+1 end
                display.before=navigationText(before:sub(from),28)
                display.match=navigationText(item.matched_text or "Match",160)
                display.after=navigationText(item.next_text,28)
                display.chapter=item.chapter and "Chapter "..item.chapter or nil
                location=item.page or type(item.start)=="number" and item.start or nil
            end
            display.title=navigationText(title,240);display.location=navigationText(location,48);display.depth=depth or 0;display.index=index
            rows[#rows+1]=display
        end
    end
    ui.booksync_navigation=session
    local result={items=rows,total=#list,offset=offset,next=(offset+limit<#list) and offset+limit or nil,token=serial,
        whole_words=kind=="search" and ui.booksync_search.whole_words or false,capped=kind=="search" and ui.booksync_search.capped or false,
        query=kind=="search" and navigationText(ui.booksync_search.query,160) or nil,error=kind=="search" and ui.booksync_search.error or nil}
    if kind=="contents" and type(current)=="number" then
        result.current=current
        for _,row in ipairs(rows) do row.current=row.index==current;row.finished=row.index<current end
    end
    local bytes=#UIUtil.encode(result)
    assert(Budgets.check(Budgets.get("screens","reader-navigation"),{rows=#rows+1,bytes=bytes,snapshotBytes=bytes,network=0,spawns=0,roundTrips=0}))
    finish();return result
end
function Library.readerNavigate(ui,token,row)
    local session=ui and ui.booksync_navigation
    local saved=session and session.refs[row]
    if not (saved and session.serial==token and ui.document==session.document and ui.document.file==session.file
        and navigationList(ui,session.kind)==session.list and session.list[saved.index]==saved.item) then return false end
    local item=saved.item
    if not (ui.link and ui.link.addCurrentLocationToStack) then return false end
    if session.kind=="contents" then
        if not ui.handleEvent or not (type(item.xpointer)=="string" and item.xpointer~="" or type(item.page)=="number" and item.page>=1) then return false end
        ui.link:addCurrentLocationToStack()
        local Event=require("ui/event")
        if item.xpointer then ui:handleEvent(Event:new("GotoXPointer",item.xpointer,item.xpointer))
        elseif type(item.page)=="number" then ui:handleEvent(Event:new("GotoPage",item.page)) else return false end
    elseif session.kind=="annotations" then
        if not (ui.bookmark and ui.bookmark.gotoBookmark and (type(item.page)=="string" or type(item.page)=="number")) then return false end
        ui.link:addCurrentLocationToStack();ui.bookmark:gotoBookmark(item.page,item.pos0)
    elseif ui.rolling and ui.rolling.onGotoXPointer then
        ui.link:addCurrentLocationToStack();ui.rolling:onGotoXPointer(item.start,item.start)
        if item["end"] and ui.document.getTextFromXPointers then ui.document:getTextFromXPointers(item.start,item["end"],true) end
    elseif ui.link.onGotoLink and type(item.start)=="number" then
        ui.link:addCurrentLocationToStack();ui.link:onGotoLink({page=item.start-1},true)
        if ui.view and ui.view.highlight and ui.view.highlight.temp and ui.document.nativeToPageRectTransform then
            local boxes={}
            for i=1,math.min(64,#(item.boxes or {})) do boxes[i]=ui.document:nativeToPageRectTransform(item.start,item.boxes[i]) end
            ui.view.highlight.temp[item.start]=boxes
        end
    else return false end
    return true
end
function Library.readerGo(ui,text,percent)
    if not (ui and ui.document and ui.link and ui.link.addCurrentLocationToStack) then return false end
    text=tostring(text or ""):match("^%s*(.-)%s*$")
    if percent then
        local n=tonumber(text)
        if not n or n~=n or n<0 or n>100 then return false end
        if not ((ui.rolling and ui.rolling.onGotoPercent) or (ui.paging and ui.paging.onGotoPercentage)) then return false end
        ui.link:addCurrentLocationToStack();return Library.readerAction(ui,"seek",n)
    end
    local page
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local label=ui.pagemap:cleanPageLabel(text)
        local _,number=ui.pagemap:getPageLabelProps(label);page=number
    else
        page=tonumber(text)
        local total=ui.document.info and ui.document.info.number_of_pages
        if not page or page~=math.floor(page) or page<1 or not total or page>total or text:match("^[+-]") then return false end
    end
    if not page or not ui.handleEvent then return false end
    ui.link:addCurrentLocationToStack();ui:handleEvent(require("ui/event"):new("GotoPage",page));return true
end
function Library.readerSearch(ui,query,info,done,wholeWords)
    if not (ui and ui.document and ui.document.findAllText and type(query)=="string" and #query>0 and #query<=512) then return false end
    local document,file=ui.document,ui.document.file
    local epoch=(ui.booksync_search_epoch or 0)+1;ui.booksync_search_epoch=epoch
    local Trapper=require("ui/trapper")
    Trapper:wrap(function()
        local finish=span("search-worker")
        local completed,result=Trapper:dismissableRunInSubprocess(function()
            local regex=wholeWords==true and not ui.paging
            -- CRE accepts regular expressions; Kopt uses padded literal word boundaries.
            local pattern=ui.paging and wholeWords and (" "..query.." ") or ReaderPanelPlan.searchPattern(query,wholeWords)
            local ok,items=pcall(document.findAllText,document,pattern,true,8,129,regex,0x00FF)
            if not ok or items~=nil and type(items)~="table" then return {ok=false} end
            local rows={}
            for i=1,math.min(128,#(items or {})) do
                local item=items[i]
                if type(item)~="table" or not (type(item.start)=="number" or type(item.start)=="string" and #item.start<=4096)
                    or type(item["end"])=="string" and #item["end"]>4096 then return {ok=false} end
                local boxes={};for j=1,math.min(64,#(item.boxes or {})) do boxes[j]=item.boxes[j] end
                local page=type(item.start)=="number" and item.start or nil
                if not page and document.getPageFromXPointer then
                    local resolved,value=pcall(document.getPageFromXPointer,document,item.start)
                    if resolved and type(value)=="number" and value>=1 then page=value end
                end
                local chapter
                local toc=ui.toc and ui.toc.toc or {};local low,high=1,#toc
                for _=1,Budgets.readerControls.tocComparisons do
                    if low>high or not page then break end
                    local mid=math.floor((low+high)/2);local at=toc[mid].page
                    if type(at)~="number" then break end
                    if at<=page then chapter=mid;low=mid+1 else high=mid-1 end
                end
                rows[#rows+1]={chapter=chapter,start=item.start,["end"]=item["end"],boxes=boxes,page=page,
                    prev_text=navigationText(item.prev_text,160),matched_text=navigationText(item.matched_text,160),next_text=navigationText(item.next_text,160)}
            end
            local result={ok=true,items=rows,capped=#(items or {})>128}
            if #UIUtil.encode(result)>262144 then return {ok=false} end
            return result
        end,info)
        finish()
        if ui.document~=document or document.file~=file or ui.booksync_search_epoch~=epoch then done(false);return end
        if completed then
            ui.booksync_search={document=document,file=file,query=query,whole_words=wholeWords==true,capped=type(result)=="table" and result.capped==true,results=type(result)=="table" and type(result.items)=="table" and result.items or {},error=type(result)~="table" or result.ok~=true}
            done(true)
        else done(false) end
    end)
    return true
end
function Library.readerNativeAction(ui,kind)
    if not (ui and ui.document) then return false end
    local target,method
    if kind=="contents" then target,method=ui.toc,"onShowToc"
    elseif kind=="annotations" then target,method=ui.bookmark,"onShowBookmark"
    elseif kind=="goto" then target,method=ui["goto"],"onShowGotoDialog"
    elseif kind=="search" then target,method=ui.search,"onShowFulltextSearchInput" end
    if target and target[method] then return target[method](target) end
    return ReaderPanel.stockMenu(ui.menu)
end
