-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(here, test, ok, eq, audit)
    local function world()
        local W = {shown={}, logs={}, trips=0, syncs=0, reads={}}
        local function class(base)
            local c=setmetatable({}, {__index=base})
            c.__index=c
            function c:extend(t) return setmetatable(t or {}, {__index=self, __call=self.new}) end
            function c:new(t) t=setmetatable(t or {}, {__index=self}); if t.buttons then t.buttons_layout=t.buttons end; if t.init then t:init() end; return t end
            return c
        end
        local Widget=class()
        function Widget:getSize() return {w=self.width or self.max_width or self.dimen and self.dimen.w or 20,h=self.height or self.dimen and self.dimen.h or 20} end
        function Widget:onShowKeyboard() end
        function Widget:getSize() return {w=self.width or self.dimen and self.dimen.w or math.min(self.max_width or 100,#(self.text or "")*7),h=self.height or self.dimen and self.dimen.h or 20} end
        function Widget:getText() return self.text or "" end
        function Widget:onCloseKeyboard() end
        function Widget:getInputText() return self.input or "" end
        W.face={hash="fixture",ftsize={getEmboldenHalfStrength=function(_,factor) return factor end}}
        local ui={document={file="/books/fixture.epub",info={number_of_pages=200}},view={state={page=124}},menu={}}
        local Menu={onShowMenu=function() W.stock=(W.stock or 0)+1; return "native" end,
            onTapShowMenu=function(_,...) W.stock_taps=(W.stock_taps or 0)+1;W.tap_args=W.E.UIUtil.pack(...);return "native-tap" end,
            onSwipeShowMenu=function() W.stock_swipes=(W.stock_swipes or 0)+1;return "native-swipe" end}
        local Config={onShowConfigMenu=function() W.stock_config=true end,
            onTapShowConfigMenu=function(self) return self:onShowConfigMenu() end,
            onSwipeShowConfigMenu=function(self) return self:onShowConfigMenu() end}
        ui.config=setmetatable({ui=ui},{__index=Config})
        ui.menu=setmetatable({ui=ui},{__index=Menu})
        W.book={items={{key="opaque",title="The Moon",authors={"A"},progress=62,
            stats={days_start_to_finish=3,reading_seconds=3660,pages_read=120}}}}
        W.controls={items={{progress=.62,chapter="Chapter 3 of 6",position="p. 124 of 200 · 62%",
            chapters={.1,.3,.6,.7,.8,.9},bookmarks={.2,.5},marked=false}}}
        W.caps={progress={syncCurrent=true}}
        W.battery={hours_usual_use=54,display={page_estimate="≈ 2 d 6 h left at your usual use"}}
        local E=setmetatable({now_s=function() return 1 end, log=function(s) W.logs[#W.logs+1]=s end,
            S={clean_menus=true}, G_reader_settings={readSetting=function() return nil end}, saveSettings=function() end,
            BatteryUI={show=function() W.battery_opened=true end},
            state={}, OrbitAndroid={menuItems=function() return {} end,onCloseWidget=function() end},
            LibraryAdapter={readerPosition=function() return W.native end,read=function(request)
                local a=W.E.Cache.decode(request); W.reads[#W.reads+1]=a.op
                if a.op=="reader" then W.native_input=a.native_progress end
                if W.oversize then return {items={{},{}}},100 end
                if W.missing then return nil end
                return a.op=="reader.controls" and W.controls or a.op=="capabilities" and W.caps or a.op=="battery" and W.battery or W.book,256
            end,request=function(batch) W.trips=W.trips+1; W.batch=batch; return true end,
                syncCurrent=function(done) W.syncs=W.syncs+1; W.done=done; return true end}}, {__index=_G})
        E.SOURCE_DIR=here.."/../orbit.koplugin"
        W.E=E
        E.UIManager={scheduleIn=function(_,_,fn) W.poll=fn end, show=function(_,s) W.shown[#W.shown+1]=s; W.top=s end,
            close=function(_,s)
                for i=#W.shown,1,-1 do if W.shown[i]==s then table.remove(W.shown,i); break end end
                W.top=W.shown[#W.shown]
            end,
            setDirty=function() W.dirty=(W.dirty or 0)+1 end,
            getTopmostVisibleWidget=function() return W.top end}
        E.wrap=function(t,k,f) t[k]=f(t[k]) end
        E.require=function(name)
            if name=="device" then return {hasFrontlight=function() return W.hardware end,hasNaturalLight=function() return W.warmth_supported end,
                getPowerDevice=function() return W.power end,screen={getWidth=function() return 600*(W.scale or 1) end,getHeight=function() return 800*(W.scale or 1) end,scaleBySize=function(_,n) return math.ceil(n*(W.scale or 1)) end}} end
            if name=="document/credocument" then return {engineInit=function() return {getFontFaceFilenameAndFaceIndex=function(face) return face .. ".ttf",0 end} end} end
            if name=="ui/event" then return {new=function(_,name,...) return {name=name,...} end} end
            if name=="apps/reader/modules/readermenu" then return Menu end
            if name=="apps/reader/modules/readerconfig" then return Config end
            if name=="ui/geometry" or name=="ui/gesturerange" then return {new=function(_,t) return t end} end
            if name=="ui/font" then return {getFace=function() return W.face end} end
            if name=="ffi/blitbuffer" then return {COLOR_BLACK=0,COLOR_WHITE=1,COLOR_LIGHT_GRAY=2,Color8=function(n) return n end} end
            if name:match("^ui/widget/") then return Widget end
            return require(name)
        end
        E.SOURCE_DIR=here.."/../orbit.koplugin"
        E.Device=E.require("device")
        local function load(name) local fn=assert(loadfile(here.."/../orbit.koplugin/"..name)); setfenv(fn,E); fn() end
        for _,name in ipairs({"logic/ui_util.lua","logic/cache.lua","logic/budgets.lua","logic/reading_style.lua","logic/settings_ui.lua","logic/sheet_layout.lua","logic/reader_panel.lua","ko/library.lua","ko/library_services.lua","ko/endsheet.lua","ko/reading_style.lua","ko/ui/kit.lua","ko/ui/settings_page.lua","ko/custom_reading.lua","ko/reader_panel.lua"}) do load(name) end
        if audit then
            local paint=E.Library.paint
            E.Library.paint=function(screen)
                local context=paint(screen)
                local flush=context.flush
                context.flush=function(self,...)
                    local counts=flush(self,...); audit("screen",screen,counts)
                    for key,usage in pairs(self.widgets) do audit("widget",key:match("^([^:]+)"),usage) end
                    return counts
                end
                return context
            end
        end
        W.nativeMenuClass=Menu
        E.Library.readerHookOrigin=function() return true end
        E.Library.installReaderMenus(ui)
        W.ui=ui
        return W,E
    end
    local function row(E,text)
        for _,r in ipairs(E.ReaderPanel.sheet:rows()) do if r.text==text or r.position==text then return r end end
        for _,r in ipairs(E.ReaderPanel.sheet:rows()) do
            for _,cell in ipairs(r.choices or {}) do
                if cell.text==text then return {text=cell.text,action=cell.callback} end
            end
        end
        error("missing reader row "..text)
    end
    test("reader hooks: instance lifetime, repeated install, disable and third-party chain",function()
        local W,E=world();local ui=W.ui
        local first=ui.menu.onTapShowMenu
        E.Library.installReaderMenus(ui);eq(first,ui.menu.onTapShowMenu)
        ok(W.nativeMenuClass.onTapShowMenu~=first,"native class is never patched")
        E.Library.setReaderMenus(ui,false);eq(rawget(ui.menu,"onTapShowMenu"),nil)
        eq(ui.menu:onTapShowMenu("gesture",nil,7),"native-tap")
        eq(W.tap_args.n,3);eq(W.tap_args[3],7)
        E.Library.setReaderMenus(ui,true)
        local owned=ui.menu.onTapShowMenu
        local external=function(self,...) W.other=(W.other or 0)+1;return owned(self,...) end
        ui.menu.onTapShowMenu=external
        eq(ui.menu:onTapShowMenu("custom"),"native-tap");eq(W.other,1)
        E.Library.restoreReaderMenus(ui);eq(ui.menu.onTapShowMenu,external)
        eq(ui.menu:onTapShowMenu("custom"),"native-tap");eq(W.other,2)
        eq(E.ReaderPanel.sheet,nil)
    end)
    test("reader hooks: combined stock path bypasses both owned entry points and preserves hidden build",function()
        local W,E=world();local ui=W.ui
        W.nativeMenuClass.onShowMenu=function(self,tab,hidden)
            W.hidden=hidden;W.tab=tab
            if not hidden then self.ui.config:onTapShowConfigMenu() end
            return "native-combined"
        end
        eq(E.ReaderPanel.stockMenu(ui.menu,"tools",true),"native-combined");eq(W.hidden,true);eq(W.tab,"tools")
        eq(E.ReaderPanel.stockMenu(ui.menu,"tools",false),"native-combined");eq(W.stock_config,true)
        eq(E.ReaderPanel.sheet,nil,"stock combined path never recursively opens an owned panel")
        local close=setmetatable({ui=ui},{__index=E.OrbitAndroid})
        close:onCloseDocument();eq(ui.booksync_reader_menu_hooks,nil)
        eq(rawget(ui.config,"onTapShowConfigMenu"),nil)
    end)
    test("reader panel: bounded cached data, plain bar and one companion batch",function()
        local W,E=world()
        W.native=0.73
        eq(W.ui.menu:onTapShowMenu(),true)
        eq(W.native_input,0.73,"cached native position goes through the library request")
        eq(W.trips,1); eq(#W.batch,4); eq(W.syncs,0)
        eq(table.concat(W.reads,","),"reader,battery,reader.controls,capabilities")
        ok(row(E,"≈ 2 d 6 h left at your usual use"))
        eq(E.ReaderPanel.sheet.metrics.button,50)
        local bars=0
        for _,r in ipairs(E.ReaderPanel.sheet:rows()) do
            if r.kind=="progress" then bars=bars+1; eq(r.value,0.62) end
        end
        eq(bars,1)
        local sheet=E.ReaderPanel.sheet
        eq(sheet.alpha,.6,"translucent sheets request an undimmed background repaint")
        eq(sheet.frame.radius,math.floor(20*600/702+.5))
        ok(#sheet.focus_controls>=10,"kit controls participate in focus traversal")
        ok(#W.logs>=5,"call, paint and draw timing spans")
        row(E,"Book info").action()
        ok(row(E,"3 days start to finish")); ok(row(E,"1 h 01 m")); ok(row(E,"120 pages read"))
        row(E,"Details").action(); eq(E.ReaderPanel.sheet.screen,"details"); eq(W.reads[#W.reads-1],"reader","in-book Details keeps the native reader context")
        row(E,"Back to book").action(); eq(E.ReaderPanel.sheet,nil); eq(W.ui.document.file,"/books/fixture.epub")
        E.ReaderPanel.details("opaque"); eq(W.reads[#W.reads-1],"book")
        row(E,"Back").action(); eq(E.ReaderPanel.sheet,nil)
    end)
    test("reader panel: battery link uses the companion label and opens Battery",function()
        local W,E=world()
        W.battery={hours_usual_use=999,display={page_estimate="≈ 1 d 7 h left at your usual use"}}
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        row(E,"≈ 1 d 7 h left at your usual use").action()
        eq(W.battery_opened,true); eq(W.trips,1,"link dispatch adds no render reads")
        eq(E.ReaderPanel.sheet.screen,"reader-top-panel","Battery returns to the user-opened panel")
        W.battery={hours_usual_use=999}
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        ok(row(E,"Battery estimate not available yet").action,"learning still opens Battery")
    end)
    test("reader panel: Settings closes the panel and dispatches to the shared Settings owner",function()
        local W,E=world()
        E.state.module={showSettings=function() W.settings_opened=true end}
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        row(E,"BookSync settings").action()
        eq(W.settings_opened,true); eq(E.ReaderPanel.sheet,nil)
    end)
    test("reader panel: capabilities, missing data and asynchronous Sync never reopen a dismissed panel",function()
        local W,E=world(); W.caps={}; W.battery={}
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        for _,r in ipairs(E.ReaderPanel.sheet:rows()) do ok(r.text~="Sync") end
        ok(row(E,"Battery estimate not available yet"))
        W.caps={progress={syncCurrent=true}}
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        local sync=row(E,"Sync"); sync.action()
        ok(W.logs[#W.logs]:find("library.progress.sync",1,true),"explicit Sync dispatch has a timing span")
        sync.action(); eq(W.syncs,1)
        eq(sync.text,"Syncing…")
        W.done(false,"Offline · will sync when connected")
        eq(sync.text,"Offline · will sync when connected")
        sync.action(); eq(W.syncs,2)
        E.ReaderPanel.close(); local shown=#W.shown; local dirty=W.dirty
        W.done(true,"Synced"); eq(#W.shown,shown); eq(W.dirty,dirty)
        W.missing=true; E.ReaderPanel.show(W.ui,"book-info")
        ok(row(E,"Progress not saved yet")); ok(row(E,"Reading time: not saved yet"))
        eq(E.ReaderPanel.sheet.model.progress,nil)
        local poll=W.poll; E.ReaderPanel.close(); shown=#W.shown
        poll(); eq(#W.shown,shown,"cold completion never reopens the book overlay")
        E.ReaderPanel.show(W.ui,"book-info"); local sheet=E.ReaderPanel.sheet
        W.missing=false; W.poll(); eq(E.ReaderPanel.sheet,sheet)
        ok(row(E,"1 h 01 m"),"cold projection updates the existing user-opened surface")
    end)
    test("reader panel: native escape, close lifecycle and enforced surface/widget budgets",function()
        local W,E=world()
        eq(W.ui.menu:onShowMenu(nil,true),"native")
        E.ReaderPanel.show(W.ui,"reader-top-panel")
        row(E,"KOReader menu").action(); eq(W.stock,2); eq(E.ReaderPanel.sheet,nil)
        E.ReaderPanel.show(W.ui,"reader-top-panel"); E.OrbitAndroid:onCloseWidget(); eq(E.ReaderPanel.sheet,nil)
        for _,s in ipairs({"reader-top-panel","book-info","details"}) do
            local b=E.Budgets.get("screens",s); eq(b.rows,s=="reader-top-panel" and 4 or 3); eq(b.bytes,(s=="reader-top-panel" and 4 or 3)*16384); eq(b.spawns,0); eq(b.network,0); eq(b.roundTrips,1)
        end
        eq(E.Budgets.get("widgets","reader-progress").snapshotBytes,16384)
        W.oversize=true
        eq(pcall(E.ReaderPanel.show,W.ui,"reader-top-panel"),false)
        local m=E.ReaderPanelPlan.model({items={{progress=200}}},{}); eq(m.progress,1)
        eq(E.ReaderPanelPlan.model({items={{progress=0/0}}},{}).progress,nil)
    end)
    test("reader controls: native menus dispatch after dismissal; top header and tiles keep approved order",function()
        local W,E=world()
        local function target(key,method)
            W.ui[key]={[method]=function()
                eq(E.ReaderPanel.sheet,nil,"native dialog owns the screen after dismissal")
                W.action=key
                return true
            end}
        end
        target("toc","onShowToc"); target("bookmark","onShowBookmark")
        target("search","onShowFulltextSearchInput"); target("goto","onShowGotoDialog")
        for _,pair in ipairs({{"Contents","toc"},{"Bookmarks","bookmark"},{"Search","search"},{"Go to","goto"}}) do
            W.ui.menu:onTapShowMenu()
            local rows=E.ReaderPanel.sheet:rows()
            eq(rows[1].kind,"reader-header"); eq(rows[1].choices[1].text,"Home"); eq(rows[1].choices[1].icon,"home"); eq(rows[1].choices[1].keep_label,true)
            eq(rows[1].choices[2].text,"Sync"); eq(rows[1].choices[3].text,"BookSync settings")
            eq(rows[1].choices[4].text,"Add bookmark")
            local names={}; for _,cell in ipairs(rows[2].choices) do names[#names+1]=cell.text end
            eq(table.concat(names,","),"Contents,Bookmarks,Search,Go to,Book info,KOReader menu")
            row(E,pair[1]).action()
            if pair[1]=="Contents" or pair[1]=="Bookmarks" then
                eq(E.ReaderPanel.sheet.screen,"reader-navigation")
                row(E,pair[1]=="Contents" and "Native Contents options…" or "Edit saved items in KOReader…").action()
            else
                local input=W.shown[#W.shown]
                eq(input.screen,pair[1]=="Search" and "reader-search" or "reader-goto")
                if pair[1]=="Search" then ok(input.is_always_active,"input remains interactive below the native keyboard") end
                E.ReaderPanel.close()
                E.Library.readerNativeAction(W.ui,pair[1]=="Search" and "search" or "goto")
            end
            eq(W.action,pair[2])
        end
        W.ui.menu:onSwipeShowMenu({direction="south"}); eq(E.ReaderPanel.sheet.screen,"reader-top-panel")
        W.ui.config:onTapShowConfigMenu(); eq(E.ReaderPanel.sheet.screen,"reader-bottom-panel")
        row(E,"More reading settings…").action(); eq(W.stock_config,true); eq(E.ReaderPanel.sheet,nil)
    end)
    test("reader bottom: separate anchor, bounded ticks, scrub touch, chapter keys and Back release",function()
        local W,E=world()
        local moves={}
        W.ui.rolling={onGotoPercent=function(_,value) moves[#moves+1]=value; return true end,
            onGotoNextChapter=function() W.next=true; return true end,
            onGotoPrevChapter=function() W.previous=true; return true end}
        E.ReaderPanel.show(W.ui,"reader-bottom-panel")
        local sheet=E.ReaderPanel.sheet
        eq(W.trips,1); eq(#W.batch,2)
        eq(sheet.focus_index,2,"scrubber starts between its chapter arrows")
        sheet:focusStep(-1); eq(sheet.focus_controls[sheet.focus_index].icon,"chevron.first")
        sheet:focusStep(1)
        local scrub
        for _,r in ipairs(sheet:rows()) do if r.kind=="scrubber" then scrub=r end end
        eq(#scrub.chapters,6); eq(#scrub.bookmarks,2); eq(scrub.value,.62)
        local area=sheet.focus_controls[2]
        area.dimen.x=10
        local width=math.floor(516*600/702+.5)
        area:onKitTap(nil,{pos={x=10+width/2}});eq(moves[1],50)
        area:onKitTap(nil,{pos={x=-20}});eq(moves[2],0)
        area:onKitTap(nil,{pos={x=999}});eq(moves[3],100)
        local trips=W.trips
        sheet:onSelect(); eq(sheet.scrub_focus,true)
        eq(W.trips,trips,"grab feedback is geometry-only, without a library read")
        ok(row(E,"Prev/Next: one chapter · Select or Back: done"))
        sheet:onStepMore(); eq(W.next,true); sheet:onStepLess(); eq(W.previous,true)
        trips=W.trips
        sheet:onClose(); eq(sheet.scrub_focus,false); eq(E.ReaderPanel.sheet,sheet)
        eq(W.trips,trips,"releasing the scrubber does not request a snapshot")
        for _,r in ipairs(sheet:rows()) do ok(r.text~="Prev/Next: one chapter · Select or Back: done") end
        sheet:onClose(); eq(E.ReaderPanel.sheet,nil)
        E.ReaderPanel.show(W.ui,"reader-bottom-panel"); sheet=E.ReaderPanel.sheet
        sheet:onSelect(); eq(sheet.scrub_focus,true)
        eq(sheet:onTapAnywhere(nil,{pos={y=0}}),true); eq(E.ReaderPanel.sheet,nil)
        E.ReaderPanel.show(W.ui,"reader-top-panel"); sheet=E.ReaderPanel.sheet
        eq(sheet:onTapAnywhere(nil,{pos={y=799}}),true); eq(E.ReaderPanel.sheet,nil)
        W.ui.rolling=nil; W.ui.paging={onGotoPercentage=function(_,value) W.fraction=value; return true end}
        E.Library.readerAction(W.ui,"seek",50); eq(W.fraction,.5,"paging expects a fraction; rolling expects percent")
    end)
    test("reader keyboard: every top action and footer participates in focus order",function()
        local W,E=world(); E.ReaderPanel.show(W.ui,"reader-top-panel")
        local sheet=E.ReaderPanel.sheet
        local names={}
        for i,widget in ipairs(sheet.focus_controls) do
            if widget.text then names[widget.text]=i end
        end
        ok(names["Home"]); ok(names["Reading settings"]); ok(names["Back to book"])
        sheet.focus_index=names["Reading settings"]; sheet:onSelect()
        eq(E.ReaderPanel.sheet.screen,"reader-bottom-panel")
        E.ReaderPanel.show(W.ui,"reader-top-panel"); sheet=E.ReaderPanel.sheet
        sheet.focus_index=#sheet.focus_controls; sheet:onStepMore(); eq(sheet.focus_index,1)
        sheet:onStepLess(); eq(sheet.focus_index,#sheet.focus_controls)
        sheet.focus_index=names["Back to book"]; sheet:onSelect(); eq(E.ReaderPanel.sheet,nil)
    end)
    test("reader controls: native inputs bounded, missing/pending snapshots and marked state",function()
        local W,E=world()
        W.ui.toc={toc={}}; W.ui.annotation={annotations={}}
        for i=1,10000 do W.ui.toc.toc[i]={page=i}; W.ui.annotation.annotations[i]={page=i} end
        local input=E.Library.readerInput(W.ui)
        eq(#input.chapters,64); eq(#input.bookmarks,64); eq(input.total,200); eq(input.page,124)
        W.ui.view.dogear_visible=true
        input=E.Library.readerInput(W.ui); eq(input.bookmarks[1],124); eq(#input.bookmarks,64)
        for _,annotation in ipairs(W.ui.annotation.annotations) do annotation.drawer="lighten" end
        input=E.Library.readerInput(W.ui); eq(#input.bookmarks,1); eq(input.bookmarks[1],124)
        W.controls={items={{marked=true}}}; E.ReaderPanel.show(W.ui,"reader-top-panel")
        ok(row(E,"Remove bookmark"))
        W.controls={items={},pending=true}; E.ReaderPanel.show(W.ui,"reader-bottom-panel")
        ok(row(E,"Position not available yet")); ok(row(E,"Chapters not available yet"))
        local poll=W.poll; E.ReaderPanel.close(); local before=#W.shown; poll(); eq(#W.shown,before)
        E.ReaderPanel.show(W.ui,"reader-bottom-panel"); local sheet=E.ReaderPanel.sheet
        W.controls={items={{position="p. 1 of 200 · 1%",chapter="Chapter 1 of 6"}}}; W.poll()
        eq(E.ReaderPanel.sheet,sheet); ok(row(E,"p. 1 of 200 · 1%"))
        local b=E.Budgets.get("screens","reader-bottom-panel")
        eq(b.rows,2); eq(b.bytes,32768); eq(b.spawns,0); eq(b.network,0); eq(b.roundTrips,1)
        eq(E.ReaderPanelPlan.fontSize(27,1),16); eq(E.ReaderPanelPlan.fontSize(16,-1),27)
        eq(E.ReaderPanelPlan.fontSize(23,1),24)
    end)
    test("next stop: cached binary summary skips annotation resolution and missing TOC is honest",function()
        local W,E=world()
        W.ui.document.file="/fixture/long.epub"
        W.ui.toc={toc={}}
        for i=1,10000 do W.ui.toc.toc[i]={page=i,title="Entry "..i} end
        W.ui.annotation={annotations=setmetatable({},{__index=function() error("must not read annotations") end})}
        W.ui.bookmark={getBookmarkPageNumber=function() error("must not resolve bookmarks") end}
        local input=E.Library.readerInput(W.ui,true)
        eq(input.page,124);eq(input.chapter_index,124);eq(input.chapter_total,10000)
        eq(input.next_page,125);eq(input.next_title,"Entry 125");eq(input.chapter_exact,true)
        eq(input.toc_loaded,true);eq(input.next_exists,true);eq(#input.chapters,0);eq(#input.bookmarks,0)
        W.ui.toc={}
        input=E.Library.readerInput(W.ui,true);eq(input.toc_loaded,false);eq(input.chapter_total,0)
        W.ui.toc={toc={{page="unresolved"}}}
        input=E.Library.readerInput(W.ui,true);eq(input.chapter_exact,false);eq(input.next_page,nil)
    end)
    test("reader controls: owned strip toggles use existing status session",function()
        local W,E=world()
        local session={ui=W.ui,bottom_visible=true}
        E.ReadingStatus={session=session,relayout=function(ui) eq(ui,W.ui); W.relayout=(W.relayout or 0)+1 end}
        E.Library.readerAction(W.ui,"clock"); eq(session.top_visible,false)
        E.Library.readerAction(W.ui,"status"); eq(session.bottom_visible,false)
        local values=E.Library.readerSettings(W.ui); eq(values.clock,false); eq(values.status,false)
        E.Library.readerAction(W.ui,"clock"); E.Library.readerAction(W.ui,"status")
        eq(session.top_visible,true); eq(session.bottom_visible,true); eq(W.relayout,4)
    end)
    test("reader Sync adapter: explicit sync uses the companion owner",function()
        local ui={document={file="fixture.epub"},view={footer={percent_finished=0.73}}}
        local called,reply,done,message
        local E={liveUI=function() return ui end,ReadingSync={run=function(moment,callback) called=moment; reply=callback; return true end}}
        setfenv(assert(loadfile(here.."/../orbit.koplugin/ko/library.lua")),setmetatable(E,{__index=_G}))()
        eq(E.LibraryAdapter.readerPosition("fixture.epub"),0.73)
        eq(E.LibraryAdapter.readerPosition("other.epub"),nil)
        ui.view.footer.percent_finished=0/0; eq(E.LibraryAdapter.readerPosition("fixture.epub"),nil)
        E.LibraryAdapter.syncCurrent(function(ok,text) done,message=ok,text end)
        eq(called,"manual"); reply(false,"Offline · saved"); eq(done,false); eq(message,"Offline · saved")
        E.LibraryAdapter.syncCurrent(function(ok,text) done,message=ok,text end)
        reply(true); eq(done,true); eq(message,"Synced")
    end)

    local function styleReader(W)
        local ui=W.ui
        ui.rolling={}; ui.font={font_face="Fixture Serif",configurable={font_base_weight=0,line_spacing=130,font_gamma=18}}
        ui.typeset={configurable={},unscaled_margins={40,20,40,30},onSetPageMargins=function(_,m) W.margins=m end}
        ui.doc_settings={readSetting=function() end,saveSetting=function(_,k,v) W.saved=W.saved or {}; W.saved[k]=v end}
        ui.handleEvent=function(_,event) W.event=event; W.events=(W.events or 0)+1 end
        for _,method in ipairs({"setFontFace","setFontBaseWeight","setEmbeddedFonts","setInterlineSpacePercent","setGammaIndex"}) do
            ui.document[method]=function(_,v) W[method]=v end
        end
        ui.document.default_font="Book Face"
        return ui
    end
    test("reader scaled geometry: header targets and panels fit M8C native scaling",function()
        for _,factor in ipairs({1,1.5,2.34}) do
            local W,E=world(); W.scale=factor; styleReader(W)
            E.AccountView={syncAction=function() return "Sign in to sync",function() end end}
            W.caps={account={signedIn=false}}
            E.ReaderPanel.show(W.ui,"reader-top-panel")
            local sheet=E.ReaderPanel.sheet
            local header=sheet:rows()[1]; local width=0
            for _,cell in ipairs(header.choices) do
                local target=cell.width or sheet.metrics.button
                ok(target>=math.ceil(50*factor)); width=width+target
            end
            ok(width<sheet.plan.inner,"header leaves room for title and author")
            ok(sheet.plan.h<=sheet.screen_h)
            E.ReaderPanel.show(W.ui,"reader-bottom-panel")
            sheet=E.ReaderPanel.sheet; ok(sheet.plan.h<=sheet.screen_h)
            for _,item in ipairs(sheet.plan.items) do
                if item.kind=="scrubber" or item.kind=="reader-actions" then ok(item.h>=math.ceil(50*factor)) end
            end
        end
    end)
    test("reader quick controls: hardware sliders, preset destination, size units and native bookmark",function()
        local W,E=world(); local ui=styleReader(W)
        W.hardware=true; W.warmth_supported=true
        W.power={frontlightIntensity=function() return 30 end,frontlightWarmth=function() return 40 end,
            setIntensity=function(_,n) W.light=n end,setWarmth=function(_,n) W.warmth=n end}
        local settings=E.Library.readerSettings(ui); eq(settings.light,30); eq(settings.warmth,40)
        E.ReaderPanel.show(ui,"reader-bottom-panel")
        local sheet=E.ReaderPanel.sheet
        local controls,headings={},{}
        for _,r in ipairs(sheet:rows()) do
            if r.kind=="reader-lights" then controls=r.controls end
            if r.kind=="reader-grid" then
                for _,group in ipairs(r.groups) do headings[#headings+1]=group.group_label end
                if r.groups[2].group_label:find("Size",1,true) then
                    local size=r.groups[2]; eq(size.choices[2].text,"●●●●○○"); eq(size.choices[2].enabled,false)
                end
            end
        end
        eq(table.concat(headings,","),"Font,Size · 22 pt,Margins,Line spacing,Contrast,Status bar")
        eq(#controls,2); controls[1].set(60); eq(W.light,60); controls[2].set(70); eq(W.warmth,70)
        E.state.module={showSettings=function(_,group) W.settings_group=group end}
        row(E,"Edit presets").action(); eq(W.settings_group,"reading"); eq(E.ReaderPanel.sheet,nil)
        ui.font.onSetFontSize=function(_,n) W.size=n; return true end
        E.Library.readerAction(ui,"size",24); eq(W.size,24)
        ui.bookmark={onToggleBookmark=function() W.marked=true; return true end}
        E.ReaderPanel.show(ui,"reader-top-panel"); row(E,"Add bookmark").action(); eq(W.marked,true)
        W.warmth_supported=false
        E.ReaderPanel.show(ui,"reader-bottom-panel")
        sheet=E.ReaderPanel.sheet
        for _,r in ipairs(sheet:rows()) do
            if r.kind=="reader-lights" then
                eq(#r.controls,1)
                local found=false
                for _,control in ipairs(sheet.focus_controls) do if control.text==r.controls[1].text then found=true end end
                ok(found,"supported hardware slider is a real kit control")
                for _,control in ipairs(sheet.focus_controls) do if control.text==r.controls[1].text then control.callback();break end end
                eq(W.light,40,"hardware Select adjusts the published light by ten percent")
            end
        end
        W.hardware=false
        E.ReaderPanel.show(ui,"reader-bottom-panel")
        for _,r in ipairs(E.ReaderPanel.sheet:rows()) do ok(r.kind~="reader-lights") end
    end)
    test("Custom panel: every Custom choice applies first, edits second and returns with panel open",function()
        local W,E=world(); local ui=styleReader(W)
        E.ReaderPanel.show(ui,"reader-bottom-panel")
        for _,key in ipairs(E.ReadingStyle.keys) do
            local function cell()
                for _,row in ipairs(E.ReaderPanel.sheet:rows()) do
                    for _,r in ipairs(row.groups or {}) do
                        if r.choices and r.choices[3] and r.choices[3].text:find(E.ReadingStyle.names[key] .. "\n",1,true) then return r.choices[3] end
                    end
                end
            end
            local old=E.ReaderPanel.sheet
            cell().callback(); eq(E.CustomReading.editor,nil); eq(E.Library.readingChoices(ui)[key],"custom")
            eq(E.ReaderPanel.sheet,old); ok(cell().text:find("✎",1,true))
            cell().callback(); local editor=E.CustomReading.editor; eq(editor.key,key); eq(editor.focus_action,"+")
            local b=E.Budgets.get("screens","reading-custom-"..key); eq(b.bytes,0); eq(b.roundTrips,0)
            local before=E.Library.readingCustom(); editor:onSelect()
            local field=key=="font" and "weight" or key
            ok(E.Library.readingCustom()[field]>before[field]); eq(E.ReaderPanel.sheet,old)
            editor:onClose(); eq(E.CustomReading.editor,nil); eq(E.ReaderPanel.sheet,old); eq(W.top,old)
        end
        eq(W.setInterlineSpacePercent,144,"selected Custom spacing updates the engine")
        ok(W.setFontFace); ok(W.setGammaIndex); ok(W.margins)
    end)
    test("Custom Settings: each row returns to its originating menu; font radio and one-time copy Undo",function()
        local W,E=world(); local ui=styleReader(W)
        local rows=E.CustomReading.settingsRows(ui)
        eq(#rows,9)
        local updates=0; local menu={updateItems=function() updates=updates+1 end}
        for i,key in ipairs(E.ReadingStyle.keys) do
            local r=rows[i*2]; ok(r.text_func():find("Custom " .. E.ReadingStyle.names[key]:lower(),1,true))
            r.callback(menu); local editor=E.CustomReading.editor; eq(editor.key,key)
            for _,er in ipairs(editor:rows()) do
                if er.fontIndex==4 then er.action(); eq(E.Library.readingCustom().fontIndex,4) end
                if er.text=="Done" then er.action() end
            end
            eq(E.CustomReading.editor,nil); eq(updates,i)
        end
        local previous=E.Library.readingCustom()
        rows[9].callback(); local toast=W.top
        eq(toast.title,"Copied once from KOReader into Custom")
        eq(E.Library.readingCustom().face,"Fixture Serif"); eq(E.Library.readingCustom().margins,40)
        ui.font.configurable.line_spacing=180; eq(E.Library.readingCustom().spacing,1.3,"copy never follows native edits")
        toast.buttons[1][1].callback()
        for k,v in pairs(previous) do eq(E.Library.readingCustom()[k],v,"Undo " .. k) end
        local all={}; for _,r in ipairs(rows) do all[#all+1]=r.text or r.text_func() end
        ok(not table.concat(all):find("From KOReader",1,true))
    end)
    test("Custom native adapter: preserves vertical margins, permits book fonts, isolates PDF and closed reader",function()
        local W,E=world(); local ui=styleReader(W)
        E.Library.readingApply(ui,"margins","custom"); eq(W.margins[1],46); eq(W.margins[2],20); eq(W.margins[4],30)
        E.Library.readingApply(ui,"font",1); eq(W.setFontFace,"Book Face"); eq(W.setEmbeddedFonts,1)
        E.Library.readingApply(ui,"font","custom"); eq(W.setEmbeddedFonts,0); eq(W.setFontBaseWeight,1)
        E.Library.readingApply(ui,"contrast","custom"); eq(W.setGammaIndex,20)
        ui.rolling=nil; eq(E.Library.readingApply(ui,"font","custom"),false)
        eq(#E.CustomReading.panelRows(ui,function() end),0)
        E.Library.readingSave({margins=80}); eq(E.Library.readingCustom().margins,80)
        ok(#W.logs>0)
    end)

    test("Custom styles: physical margins, changed-only apply, reopen and close lifecycle",function()
        local W,E=world(); local ui=styleReader(W); W.scale=2
        E.Library.readingApply(ui,"margins","custom"); eq(W.margins[1],23); eq(W.margins[3],23)
        E.Library.readingApply(ui,"spacing","custom")
        W.setInterlineSpacePercent=nil
        local s=E.Library.readingCustom(); s.contrast=.3
        E.Library.readingSave(s,ui,"reading-custom-contrast")
        eq(W.setInterlineSpacePercent,nil,"an unselected edit does not reapply selected styles")
        s.spacing=1.6; E.Library.readingSave(s,nil)
        eq(W.setInterlineSpacePercent,nil,"closed-book edit only saves the record")
        E.Library.readingRestore(ui); eq(W.setInterlineSpacePercent,160)
        E.ReaderPanel.show(ui,"reader-top-panel")
        E.CustomReading.open("spacing",ui,function() error("closed reader must not reopen a panel") end)
        E.OrbitAndroid:onCloseWidget(); eq(E.CustomReading.editor,nil); eq(E.ReaderPanel.sheet,nil)
        eq(pcall(E.Library.readingCustom,"missing-screen"),false)
        E.Budgets.screens["reading-custom-spacing"].rows=0
        eq(pcall(E.Library.readingCustom,"reading-custom-spacing"),false)
    end)

    test("Custom previews: distinct weight/contrast steps and bounded page-scale gutters",function()
        local W,E=world()
        local function preview(key,value)
            local s=E.Library.readingCustom(); s[key=="font" and "weight" or key]=value
            E.Library.readingSave(s,nil)
            E.CustomReading.open(key,nil)
            local editor=E.CustomReading.editor
            local frame=editor:rowWidget({row={preview=true}},500,100,editor.metrics)
            E.CustomReading.close()
            return frame[1][1],frame
        end
        local lighter=preview("contrast",-.5); local light=preview("contrast",-.4)
        ok(lighter.fgcolor>light.fgcolor)
        local dark=preview("contrast",.2); local darker=preview("contrast",.3)
        ok(darker.face.embolden_half_strength>dark.face.embolden_half_strength)
        local medium=preview("font",1); local heavy=preview("font",2)
        ok(heavy.face.embolden_half_strength>medium.face.embolden_half_strength)
        eq(heavy.face.getFallbackFont(0),heavy.face,"native shaped glyphs use the private preview strength")
        eq(W.face.hash,"fixture"); eq(W.face.embolden_half_strength,nil,"shared UI face stays immutable")
        local text,frame=preview("margins",60); eq(frame.padding_left,50); eq(frame.padding_right,50)
        eq(text.width+2*frame[1].padding+2*frame.bordersize+frame.padding_left+frame.padding_right,500,"preview paper and gutters fit the row")
    end)

    test("Custom margins: physical pixels roundtrip at fractional native screen scales",function()
        local W,E=world(); local ui=styleReader(W)
        for _,factor in ipairs({1.25,1.5,1.8,2.34}) do
            W.scale=factor
            for _,pixels in ipairs({10,46,80}) do
                local s=E.Library.readingCustom(); s.margins=pixels; E.Library.readingSave(s,nil)
                E.Library.readingApply(ui,"margins","custom")
                eq(math.ceil(ui.typeset.unscaled_margins[1]*factor),pixels,"native margin in physical pixels")
                E.Library.readingCopy(ui)
                eq(E.Library.readingCustom().margins,pixels,"one-time copy keeps the applied margin")
            end
        end
    end)

    test("Custom contrast: native redraw only; mixed layout changes update position once",function()
        local W,E=world(); local ui=styleReader(W)
        E.Library.readingApply(ui,"contrast","custom"); eq(W.event.name,"RedrawCurrentView")
        local n=W.events; local s=E.Library.readingCustom(); s.contrast=.3
        E.Library.readingSave(s,ui,"reading-custom-contrast")
        eq(W.event.name,"RedrawCurrentView"); eq(W.events,n+1)
        E.Library.readingRestore(ui); eq(W.event.name,"RedrawCurrentView")
        E.Library.readingApply(ui,"spacing","custom"); eq(W.event.name,"UpdatePos")
        n=W.events; s=E.Library.readingCustom(); s.spacing=1.6; s.contrast=.4
        E.Library.readingSave(s,ui,"reading-custom-spacing")
        eq(W.event.name,"UpdatePos"); eq(W.events,n+1,"one update for mixed changes")
    end)

    test("Custom font copy: matching preset is selected; an outside face remains a visible choice",function()
        local W,E=world(); local ui=styleReader(W)
        for index,font in ipairs(E.ReadingStyle.fonts) do
            ui.font.font_face=font.face
            E.Library.readingCopy(ui)
            local s=E.Library.readingCustom(); eq(s.fontIndex,index); eq(s.face,nil)
            E.CustomReading.open("font",ui)
            local selected=false
            for _,r in ipairs(E.CustomReading.editor:rows()) do
                if r.fontIndex==index and r.text:find("● ",1,true)==1 then selected=true end
            end
            ok(selected,"copied preset selected"); E.CustomReading.close()
        end
        ui.font.font_face="Fixture Serif"; local previous=E.Library.readingCopy(ui)
        E.CustomReading.open("font",ui)
        local rows=E.CustomReading.editor:rows(); eq(#rows,12,"copied face fits the editor budget")
        eq(rows[3].face,"Fixture Serif"); eq(rows[3].text,"● Fixture Serif (copied)")
        E.CustomReading.close(); E.Library.readingSave(previous,ui)
        eq(E.Library.readingCustom().face,nil); eq(E.Library.readingCustom().fontIndex,4,"Undo keeps the previous font index")
    end)

    test("reader navigation: cached slices preserve hierarchy and labels without scanning distant entries",function()
        local W,E=world();local ui=W.ui
        local inaccessible=setmetatable({}, {__index=function() error("read outside native window") end})
        local toc={};for i=1,10000 do toc[i]=inaccessible end
        for i=5001,5008 do toc[i]={title="Chapter "..i,depth=3,page=i,xpointer="xp"..i} end
        ui.toc={toc=toc,fillToc=function() error("must not load the document TOC") end}
        ui.annotation={getPageRef=function(_,xp,page) eq(xp,"xp"..page);return "["..page.."]2" end}
        local result=E.Library.readerWindow(ui,"contents",5000,8)
        eq(#result.items,8);eq(result.total,10000);eq(result.next,5008);eq(result.items[1].depth,2)
        eq(result.items[1].location,"[5001]2");ok(#E.UIUtil.encode(result)<16384)
        ui.toc.toc=nil;eq(E.Library.readerWindow(ui,"contents",0,8).unavailable,true)
    end)
    test("reader navigation: exact native locators and history reject stale rows or another book",function()
        local W,E=world();local ui=W.ui;local history=0
        ui.link={addCurrentLocationToStack=function() history=history+1 end}
        ui.handleEvent=function(_,event) W.event=event end
        ui.toc={toc={{title="Part",depth=1,xpointer="/body/part",page=20},{title="Chapter",depth=2,page=30}}}
        local view=E.Library.readerWindow(ui,"contents",0,8)
        ok(E.Library.readerNavigate(ui,view.token,1));eq(W.event.name,"GotoXPointer");eq(W.event[1],"/body/part");eq(history,1)
        ui.toc.toc[2]={title="Changed",page=40};ok(not E.Library.readerNavigate(ui,view.token,2));eq(history,1)
        local nextView=E.Library.readerWindow(ui,"contents",0,8)
        ok(not E.Library.readerNavigate(ui,view.token,1));ok(E.Library.readerNavigate(ui,nextView.token,2));eq(W.event[1],40)
        ui.document={file="another.epub"};ok(not E.Library.readerNavigate(ui,nextView.token,1));eq(history,2)
    end)
    test("reader saved items: bookmarks and highlights share a bounded native list and retain editing escape",function()
        local W,E=world();local ui=W.ui
        ui.annotation={annotations={{page="bookmark-xp",text="Saved page"},{page="highlight-xp",pos0="highlight-start",drawer="lighten",text="Passage",notes="Private note"}}}
        local history=0;ui.link={addCurrentLocationToStack=function() history=history+1 end}
        ui.bookmark={getBookmarkPageString=function(_,page) return page=="bookmark-xp" and "iv" or "[7]2" end,
            gotoBookmark=function(_,page,marker) W.destination={page,marker} end,
            onShowBookmark=function() W.editor=true end}
        local result=E.Library.readerWindow(ui,"annotations",0,8)
        eq(result.items[1].location,"iv");ok(result.items[1].title:find("Bookmark",1,true));ok(result.items[2].title:find("Highlight",1,true))
        ok(E.Library.readerNavigate(ui,result.token,2));eq(W.destination[1],"highlight-xp");eq(W.destination[2],"highlight-start");eq(history,1)
        E.ReaderPanel.navigation(ui,"annotations");row(E,"Edit saved items in KOReader…").action();ok(W.editor)
        eq(#ui.annotation.annotations,2);eq(ui.annotation.annotations[2].notes,"Private note")
    end)
    test("reader Go to: page bounds, printed labels and percent semantics retain history",function()
        local W,E=world();local ui=W.ui;local history=0
        ui.link={addCurrentLocationToStack=function() history=history+1 end};ui.handleEvent=function(_,event) W.event=event end
        for _,text in ipairs({"0","201","+2","-1","1.5","invalid"}) do ok(not E.Library.readerGo(ui,text,false)) end
        eq(history,0);ok(E.Library.readerGo(ui,"200",false));eq(W.event[1],200);eq(history,1)
        ui.rolling={onGotoPercent=function(_,n) W.percent=n;return true end}
        ok(E.Library.readerGo(ui,"0",true));eq(W.percent,0);ok(E.Library.readerGo(ui,"100",true));eq(W.percent,100)
        ok(not E.Library.readerGo(ui,"101",true));eq(history,3)
        ui.pagemap={wantsPageLabels=function() return true end,cleanPageLabel=function(_,s) return s:lower() end,getPageLabelProps=function(_,s) if s=="iv" then return "iv",4 end end}
        ok(E.Library.readerGo(ui,"IV",false));eq(W.event[1],4);eq(history,4)
    end)
    test("reader search: native subprocess cap, cancellation, errors and stale book guard",function()
        local W,E=world();local ui=W.ui;local original=E.require
        local pending,completed=true,true
        local trap={wrap=function(_,work) pending=work end,dismissableRunInSubprocess=function(_,work) return completed,completed and work() or nil end}
        E.require=function(name) if name=="ui/trapper" then return trap end;return original(name) end
        ui.document.findAllText=function(_,query,caseInsensitive,context,maximum,regex,flags)
            eq(query,"needle");eq(caseInsensitive,true);eq(context,8);eq(maximum,129);eq(regex,false);eq(flags,255)
            return {{start="match-xp",["end"]="match-end",matched_text="needle",prev_text="before",next_text="after"}}
        end
        local resolutions=0
        ui.document.getPageFromXPointer=function(_,xp) eq(xp,"match-xp");resolutions=resolutions+1;return 42 end
        local answer
        ok(E.Library.readerSearch(ui,"needle",{},function(okay) answer=okay end));eq(answer,nil);pending();eq(answer,true)
        local result=E.Library.readerWindow(ui,"search",0,8);eq(result.total,1);eq(result.query,"needle");eq(result.items[1].location,"42");eq(resolutions,1)
        local history=0;ui.link={addCurrentLocationToStack=function() history=history+1 end}
        ui.rolling={onGotoXPointer=function(_,xp,marker) eq(xp,"match-xp");eq(marker,xp) end}
        ui.document.getTextFromXPointers=function(_,a,b,mark) eq(a,"match-xp");eq(b,"match-end");eq(mark,true) end
        ok(E.Library.readerNavigate(ui,result.token,1));eq(history,1)
        completed=false;answer=nil;E.Library.readerSearch(ui,"needle",{},function(v) answer=v end);pending();eq(answer,false)
        completed=true;ui.document.findAllText=function() error("native failure") end
        E.Library.readerSearch(ui,"needle",{},function(v) answer=v end);pending();eq(answer,true);eq(E.Library.readerWindow(ui,"search",0,8).error,true)
        answer=nil;E.Library.readerSearch(ui,"needle",{},function(v) answer=v end);ui.document={file="new.epub"};pending();eq(answer,false)
    end)

    test("reader search: worker bounds retained matches, context and private result bytes",function()
        local W,E=world();local ui=W.ui;local original=E.require
        local trap={wrap=function(_,work) work() end,dismissableRunInSubprocess=function(_,work) return true,work() end}
        E.require=function(name) if name=="ui/trapper" then return trap end;return original(name) end
        ui.document.findAllText=function()
            local rows={};for i=1,300 do rows[i]={start="xp"..i,["end"]="end"..i,matched_text=string.rep("x",10000),prev_text=string.rep("y",10000)} end;return rows
        end
        E.Library.readerSearch(ui,"bounded",{},function(v) ok(v) end)
        eq(#ui.booksync_search.results,128);eq(#ui.booksync_search.results[1].matched_text,160)
        ok(#E.UIUtil.encode(ui.booksync_search.results)<262144)
        ui.document.findAllText=function() return {{start=string.rep("x",4097)}} end
        E.Library.readerSearch(ui,"bounded",{},function(v) ok(v) end);eq(ui.booksync_search.error,true)
    end)
    test("reader search: paged navigation keeps one history entry and bounded native highlights",function()
        local W,E=world();local ui=W.ui;local history,boxes=0,0
        ui.paging={};ui.view.highlight={temp={}}
        ui.link={addCurrentLocationToStack=function() history=history+1 end,onGotoLink=function(_,link,neglect) eq(link.page,2);eq(neglect,true) end}
        ui.document.nativeToPageRectTransform=function(_,page,box) eq(page,3);boxes=boxes+1;return box end
        local raw={};for i=1,100 do raw[i]={x=i,y=2,w=3,h=4} end
        ui.booksync_search={document=ui.document,file=ui.document.file,query="paged",results={{start=3,boxes=raw}}}
        local result=E.Library.readerWindow(ui,"search",0,8)
        ok(E.Library.readerNavigate(ui,result.token,1));eq(history,1);eq(boxes,64);eq(#ui.view.highlight.temp[3],64)
    end)

    test("reader panels: short native viewports retain the stock escape without clipping or crashing",function()
        local W,E=world();local original=E.require
        E.require=function(name)
            local result=original(name)
            if name=="device" then result.screen.getHeight=function() return 100 end end
            return result
        end
        E.ReaderPanel.show(W.ui,"reader-bottom-panel")
        eq(E.ReaderPanel.sheet,nil);ok(W.stock_config)
        W.ui.toc={toc={{page=1,title="Chapter"}},onShowToc=function() W.native_toc=true end}
        E.ReaderPanel.navigation(W.ui,"contents")
        eq(E.ReaderPanel.sheet,nil);ok(W.native_toc)
    end)

    test("reader navigation: display fields keep notes, quote context and exact token refs",function()
        local W,E=world();local ui=W.ui
        ui.annotation={annotations={{drawer="lighten",text="Quoted words",note="A saved note",page=12},{text="Saved position",page=13}}}
        local result=E.Library.readerWindow(ui,"annotations",0,11)
        eq(result.items[1].annotation_kind,"highlight");eq(result.items[1].quote,"Quoted words")
        eq(result.items[1].note,"A saved note");eq(result.items[2].annotation_kind,"bookmark")
        ui.toc={toc={{page=1,title="One"},{page=20,title="Two"},{page=40,title="Three"}}}
        result=E.Library.readerWindow(ui,"contents",0,11,2)
        eq(result.current,2);eq(result.items[1].finished,true);eq(result.items[2].current,true);eq(result.items[3].finished,false)
        ui.booksync_search={document=ui.document,file=ui.document.file,query="word",results={{prev_text="Before",matched_text="word",next_text="after"}}}
        result=E.Library.readerWindow(ui,"search",0,11)
        eq(result.items[1].before,"Before");eq(result.items[1].match,"word");eq(result.items[1].after,"after")
        ok(#E.UIUtil.encode(result)<16384)
    end)
    test("reader owned keypad: valid page/percent, bounded entry and document lifetime",function()
        local W,E=world();local ui=W.ui
        ui.link={addCurrentLocationToStack=function() W.history=(W.history or 0)+1 end}
        ui.handleEvent=function(_,event) W.event=event end
        ui.rolling={onGotoPercent=function(_,value) W.percent=value;return true end}
        E.ReaderPanel.goDialog(ui);local sheet=E.ReaderPanel.sheet
        sheet.go_edit("4");sheet.go_edit("2");eq(sheet.go_value,"42")
        sheet.go_submit();eq(W.event.name,"GotoPage");eq(W.event[1],42);eq(E.ReaderPanel.sheet,nil)
        E.ReaderPanel.goDialog(ui);sheet=E.ReaderPanel.sheet;sheet.go_value="201";sheet.go_submit()
        eq(E.ReaderPanel.sheet,sheet);ok(sheet.go_error);eq(W.history,1)
        sheet.go_percent=true;sheet.go_value="75";sheet.go_submit();eq(W.percent,75);eq(W.history,2)
        E.ReaderPanel.goDialog(ui);sheet=E.ReaderPanel.sheet;ui.document={file="other.epub"};sheet.go_submit()
        eq(E.ReaderPanel.sheet,nil);eq(W.history,2)
    end)
    test("reader bottom sheets: taps above navigation and keypad close without navigating",function()
        local W,E=world();local ui=W.ui
        ui.toc={toc={{page=1,title="One"}}}
        for _,open in ipairs({function() E.ReaderPanel.navigation(ui,"contents") end,function() E.ReaderPanel.goDialog(ui) end}) do
            open();local sheet=E.ReaderPanel.sheet
            ok(sheet.sheet_y>0);eq(sheet:onTapAnywhere(nil,{pos={x=300,y=sheet.sheet_y-1}}),true);eq(E.ReaderPanel.sheet,nil)
        end
    end)

    test("reader annotation display: worst-case escaped quotes remain inside the snapshot byte cap",function()
        local W,E=world();local ui=W.ui
        ui.annotation={annotations={}}
        for i=1,20 do ui.annotation.annotations[i]={page=i,drawer="lighten",text=string.rep('"',100000),note=string.rep('"',100000),chapter=string.rep('"',100000)} end
        local result=E.Library.readerWindow(ui,"annotations",0,100)
        eq(#result.items,8);eq(#result.items[1].quote,360);eq(#result.items[1].note,180);eq(#result.items[1].chapter,120)
        ok(#E.UIUtil.encode(result)<=16384,"quoted display fields fit their declared native snapshot cap")
    end)

    test("reader search revision: whole-word literal, exact cap and chapter are worker-owned",function()
        local W,E=world();local ui=W.ui;local original=E.require
        E.require=function(name)
            if name=="ui/trapper" then return {wrap=function(_,fn) fn() end,dismissableRunInSubprocess=function(_,fn) return true,fn() end} end
            return original(name)
        end
        ui.toc={toc={{page=1},{page=20},{page=40}}}
        ui.document.getPageFromXPointer=function() return 42 end
        local count=128
        ui.document.findAllText=function(_,query,case,context,limit,regex)
            eq(query,"\\ba\\+b\\b");eq(limit,129);eq(regex,true)
            local rows={};for i=1,count do rows[i]={start="xp",matched_text="a+b",prev_text="before",next_text="after"} end
            return rows
        end
        E.Library.readerSearch(ui,"a+b",{},function(done) ok(done) end,true)
        local result=E.Library.readerWindow(ui,"search",0,8)
        eq(result.total,128);eq(result.capped,false);eq(result.whole_words,true);eq(result.items[1].chapter,"Chapter 3")
        count=129;E.Library.readerSearch(ui,"a+b",{},function(done) ok(done) end,true)
        result=E.Library.readerWindow(ui,"search",0,8);eq(result.total,128);eq(result.capped,true)
        ui.paging={}
        ui.document.findAllText=function(_,query,case,context,limit,regex)
            eq(query," a+b ");eq(regex,false);return {}
        end
        E.Library.readerSearch(ui,"a+b",{},function(done) ok(done) end,true)
        ui.doc_props={description="Native EPUB description"}
        local m=E.Library.readerMetadata(ui);eq(m.total_pages,200);eq(m.description,"Native EPUB description")
    end)

end
