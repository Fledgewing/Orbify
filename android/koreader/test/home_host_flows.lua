-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,Widget)
    local function find(node,key,value)
        if type(node)~="table" then return end
        if node[key]==value then return node end
        for _,child in ipairs(node) do local match=find(child,key,value);if match then return match end end
    end
    local function withHost(fn)
        local saved={adapter=E.LibraryAdapter,ui=E.HomeWidgets._ui,layout=E.S.home_layout,screen=E.S.home_screen,
            width=E.Device.screen.getWidth,problem=E.Companion.workerProblem,scale=E.Device.screen.scaleBySize,height=E.Device.screen.getHeight,shown=W.shown,free=Widget.free,paint=Widget.paintTo,require=E.require,codec=E.Library.layout.codec,news=E.S.news_012_pending,path=E.Library.layout.path,loaded=E.Library.layout.loaded,save=E.HomeEditor.save,liveUI=E.liveUI,pin=E.Shared.pin_locked,refresh=E.Shared.refresh,wifiState=E.Wifi.state,eobSheet=E.FinishUI.sheet,open=E.Library.open,panel=E.ReaderPanel,readFile=E.Store.readFile,writeFile=E.Store.writeFile}
        local batches,reads={},{}
        E.Device.screen.getWidth=function() return 702 end
        E.Device.screen.scaleBySize=function(_,n) return n end
        E.Companion.workerProblem=function() end
        Widget.free=function() end
        local U={Font={getFace=function() return {} end},BB={Color8=function(n) return n end,COLOR_BLACK=0,COLOR_WHITE=1,COLOR_DARK_GRAY=.3,COLOR_GRAY=.5,COLOR_LIGHT_GRAY=.8}}
        for _,k in ipairs({"Overlap","Frame","Text","Button","Progress"}) do U[k]=Widget:extend{} end
        U.Text.getSize=function(self) return {w=self.max_width or 0,h=20} end
        Widget.paintTo=function(self,bb,x,y)
            for _,child in ipairs(self) do if child.paintTo then child:paintTo(bb,x,y) end end
        end
        E.require=function(name)
            if name=="ui/font" then return U.Font end
            if name=="ui/widget/container/framecontainer" then return U.Frame end
            if name=="ui/widget/overlapgroup" then return U.Overlap end
            if name=="ui/widget/progresswidget" then return U.Progress end
            if name=="ui/widget/textwidget" then return U.Text end
            if name=="ffi/blitbuffer" then return U.BB end
            if name=="ui/size" then return {padding={buttontable=0}} end
            if name=="ui/widget/touchmenu" then return Widget:extend{} end
            if name=="ui/widget/buttondialog" then
                return Widget:extend{moveFocusTo=function(self,x,y) self.focus={x,y} end,getButtonById=function() end,
                    -- Pinned ButtonDialog:onClose uses tap_close_callback, not dismiss_callback.
                    onClose=function(self)
                        if self.tap_close_callback then self.tap_close_callback() end
                        E.UIManager:close(self)
                        return true
                    end}
            end
            if name=="ui/widget/inputdialog" then
                return Widget:extend{getInputText=function() return "Moon" end,onShowKeyboard=function() end}
            end
            return require(name)
        end
        E.HomeWidgets._ui=U
        E.LibraryAdapter={owner=function() return "fixture" end,watch=function() end,reset=function() end,read=function(raw)
            local a=E.Cache.decode(raw); reads[#reads+1]=a
            if a.op == "capabilities" then return {lists={read=true},collections=true},80 end
            if a.op == "library.summary" then return {total=7,on_device=2,freshness={saved=true}},100 end
            if a.op == "battery" then return {level=78,hours_usual_use=54,screen_on={pct_per_hour=4.1},
                standby={pct_per_hour=.6},recent_charges={{from_pct=12,to_pct=100}},freshness={saved=true},
                display={level="78%",estimate="≈ 2 d 6 h at your usual use",narrow_estimate="≈ 2 d 6 h · usual use",
                    reading="12 h reading non-stop",standby="10 d standby only"}},500 end
            if a.op == "reading.stats" then
                local d={state="ready",year={intensity={},days_read=1,start="2026-01-01"},
                    week={seconds={0,0,0,0,0,0,60},levels={0,0,0,0,0,0,1},total_seconds=60},
                    hour_levels={},hour_intensity={},peak_hour=22,after_18_percent=100,
                    records={recorded_pages=3,longest_session_seconds=60,streak=1,best_streak=1},
                    sources={days="server",hours="this reader",records="this reader",streak="server"},local_today_seconds=60}
                for i=1,365 do d.year.intensity[i]=0 end
                for i=1,24 do d.hour_levels[i]=0; d.hour_intensity[i]=0 end
                return d,#E.Cache.encode(d)
            end
            if a.op == "counts" then return {total=2,freshness={saved=true}},80 end
            if a.op == "facets" then return {items=a.field and {{value="unread",label="Unread",count=2}} or {},total=2,freshness={saved=true}},150 end
            if a.op == "lists" then return {items={{key="opaque-list",title="Favourites",count=3}},freshness={saved=true}},150 end
            return {items={{key="opaque-book",title="The Moon",authors={"A"},progress=25,local_path="/fixture/book.epub"}},freshness={saved=true}},200
        end,request=function(batch) batches[#batches+1]=batch; return true end}
        local records,files={},{}; local seq=0
        E.Library.layout.loaded=true
        E.Library.layout.path=function() return "home-layout-fixture" end
        E.Library.layout.codec=function() return {encode=function(d)
            seq=seq+1; records[tostring(seq)]=E.Layout.copy(d); return tostring(seq)
        end,decode=function(raw) return E.Layout.copy(records[raw]) end} end
        E.Store.readFile=function(path) return files[path] end
        E.Store.writeFile=function(path,raw) files[path]=raw; return true end
        W.shown={};E.S.news_012_pending=false
        local success,err=pcall(fn,batches,reads,U)
        if E.HomeHost.active then E.HomeHost.active:onCloseWidget() end
        E.LibraryAdapter,E.HomeWidgets._ui,E.S.home_layout,E.S.home_screen=saved.adapter,saved.ui,saved.layout,saved.screen
        E.Device.screen.scaleBySize,W.shown,Widget.free,Widget.paintTo,E.require=saved.scale,saved.shown,saved.free,saved.paint,saved.require
        E.Library.layout.codec,E.Library.layout.path,E.Library.layout.loaded=saved.codec,saved.path,saved.loaded
        E.Library.open,E.ReaderPanel=saved.open,saved.panel
        E.HomeEditor.save=saved.save;E.S.news_012_pending=saved.news
        E.liveUI,E.Wifi.state,E.FinishUI.sheet=saved.liveUI,saved.wifiState,saved.eobSheet
        E.Shared.pin_locked,E.Shared.refresh=saved.pin,saved.refresh
        E.Store.readFile,E.Store.writeFile=saved.readFile,saved.writeFile
        E.Companion.workerProblem=saved.problem
        E.Device.screen.getHeight=saved.height;E.Device.screen.getWidth=saved.width
        ok(success,err)
    end
    test("owned card status: Undo and dismiss release one intent and stale replies never show",function() withHost(function()
        local status,leave=E.Library.cardStatus,E.Library.cardStatusLeave
        local pending,released,undo
        E.Library.cardStatus=function(_,token,done) if token then undo=token;done({ok=true}) else pending=done end end
        E.Library.cardStatusLeave=function(result) released=(released or 0)+1;eq(result.token,"saved") end
        local success,err=pcall(function()
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            h:dispatch("status",{key="book"});eq(W.shown[#W.shown],h)
            eq(pending({token="saved"}),true)
            local dialog=W.shown[#W.shown];eq(dialog.buttons[1][1].text,"Undo")
            dialog.buttons[1][2].callback();dialog:onCloseWidget();eq(released,1,"Done/close share one release")
            W.shown={h};h:dispatch("status",{key="book"});pending({token="saved"})
            dialog=W.shown[#W.shown];dialog.buttons[1][1].callback();eq(undo,"saved");eq(released,1,"Undo replaces the held intent")
            W.shown={h};h:dispatch("status",{key="book"});E.HomeHost.active=nil
            eq(pending({token="saved"}),nil);eq(W.shown[#W.shown],h,"departed screen receives no dialog")
        end)
        E.Library.cardStatus,E.Library.cardStatusLeave=status,leave
        ok(success,err)
    end) end)
    test("owned card removal: preview before confirm and stale completion never redraws",function() withHost(function()
        local removal,req=E.Library.cardRemoval,E.require
        local pending,token
        E.require=function(name) if name=="ui/widget/confirmbox" then return Widget:extend{} end;return req(name) end
        E.Library.cardRemoval=function(_,t,done) token=t;pending=done end
        local success,err=pcall(function()
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            h:dispatch("remove",{key="book",title="A book",local_path="/fixture/book.epub"});eq(token,nil)
            pending({token="exact-file",detail="Annotations stay"})
            local dialog=W.shown[#W.shown];eq(dialog.ok_text,"Remove")
            W.shown={h};dialog.ok_callback();eq(token,"exact-file")
            E.HomeHost.active=nil;pending({ok=true});eq(W.shown[#W.shown],h)
        end)
        E.Library.cardRemoval,E.require=removal,req
        ok(success,err)
    end) end)
    test("owned Home: the default repeated Home returns to the open book",function() withHost(function()
        E.S.home_screen="booksync"
        local ui={document={file="/fixture/current.epub"}};E.liveUI=function() return ui end
        local controller=setmetatable({ui=ui,openCompanionHome=function() error("default Home opened the companion") end},{__index=E.OrbitAndroid})
        controller:smartHome("command",nil,"smart");local host=E.HomeHost.active
        eq(W.shown[#W.shown],host)
        controller:smartHome("command",nil,"smart")
        for _,w in ipairs(W.shown) do ok(w~=host,"Home closed back to the current book") end
        eq(ui.document.file,"/fixture/current.epub");eq(E.reading(),true)
    end) end)
    test("owned Home: legacy choice cycles Home, companion and the current book",function() withHost(function()
        E.S.home_screen="server-home"
        local ui={document={file="/fixture/current.epub"}}
        E.liveUI=function() return ui end
        local opened=0
        local controller=setmetatable({ui=ui,openCompanionHome=function() opened=opened+1;return true end},{__index=E.OrbitAndroid})
        ok(controller:smartHome("command",nil,"smart"));local host=E.HomeHost.active
        ok(host);eq(E.reading(),false)
        ok(controller:smartHome("command",nil,"smart"));eq(opened,1)
        ok(controller:smartHome("command","other_app","smart"));eq(W.shown[#W.shown],nil)
        eq(ui.document.file,"/fixture/current.epub");eq(E.reading(),true)
    end) end)
    test("owned Home: list and Series return through the owned host with no native catalog",function() withHost(function()
        local ui={document={file="/fixture/current.epub"}};E.liveUI=function() return ui end
        local controller=setmetatable({ui=ui},{__index=E.OrbitAndroid})
        controller:onOrbitGoHome();local host=E.HomeHost.active
        host:showList("All books","all",{});ok(host.list_layout)
        controller:smartHome("command",nil,"smart");eq(host.list_layout,nil)
        eq(E.HomeHost.active,host);eq(ui.document.file,"/fixture/current.epub")
    end) end)
    test('Home cold snapshot: bounded visible retries recover a missed ready notification',function()
        withHost(function(batches)
            local read=E.LibraryAdapter.read;local ready=false
            E.LibraryAdapter.read=function(raw,...)
                local a=E.Cache.decode(raw)
                if a.op=='window' and a.source=='unopened' then
                    if not ready then return nil end
                    return {items={},total=0,freshness={saved=true}},80
                end
                return read(raw,...)
            end
            E.S.home_layout=E.Layout.default();E.S.home_layout.pages={{id='cold',tab='Home',name='Cold',placements={{instance='cold',widget='booklist',version=1,x=0,y=0,w=2,h=3,settings=E.BookList.preset('unopened')}}}}
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            ok(h.widgetRefresh,'a cold miss must have a bounded local retry')
            local before=#batches;W.shown={};h.widgetRefresh();eq(#batches,before)
            W.shown={h};ready=true;h.widgetRefresh();ok(h.redraw);h.redraw()
            eq(E.Cache.decode(h.signatures.cold).total,0);eq(h.widgetRefresh,nil)
            h:onCloseWidget();ready=false
            h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            for i=1,20 do if h.widgetRefresh then h.widgetRefresh();if h.redraw then h.redraw() end end end
            eq(h.widgetRefresh,nil,'a missing worker cannot create an unbounded retry loop')
            h:dispatch('retry');ok(h.widgetRefresh,'explicit Retry starts a fresh bounded attempt')
            h:onCloseWidget();E.LibraryAdapter.read=read
        end)
    end)
    test('Home visibility: immediate gate reports survive zero measurement counts and restore reading',function()
        withHost(function()
            local send,foreground=E.Companion.send,E.Library.isForeground
            local reports={}
            E.liveUI=function() return {document={file='/fixture/book.epub'}} end
            E.Library.isForeground=function() return true end
            E.Companion.send=function(action,extras) if action==E.Companion.ACTION.STATS then reports[#reports+1]=extras end;return true end
            local worked,why=pcall(function()
                E.HomeHost.show();eq(#reports,1);eq(reports[1].reading,'0');eq(reports[1].open,'1');eq(reports[1].visibility_only,'1')
                local h=E.HomeHost.active;h:onClose();h:onCloseWidget()
                eq(#reports,2);eq(reports[2].reading,'1');eq(reports[2].reason,'home-close')
                h:onCloseWidget();eq(#reports,2)
            end)
            E.Companion.send=send;E.Library.isForeground=foreground
            if not worked then error(why,0) end
        end)
    end)
    dofile((arg[0]:match("^(.*)/") or ".").."/series_flows.lua")(test,eq,ok,E,W,withHost)
    dofile((arg[0]:match("^(.*)/") or ".").."/booklist_flows.lua")(test,eq,ok,E,W,Widget,withHost)
    dofile((arg[0]:match("^(.*)/") or ".").."/home_editor_flows.lua")(test,eq,ok,E,W,Widget,withHost)
    dofile((arg[0]:match("^(.*)/") or ".").."/battery_flows.lua")(test,eq,ok,E,W,withHost)
    dofile((arg[0]:match("^(.*)/") or ".").."/local_widget_flows.lua")(test,eq,ok,E,W,withHost)
    test("First run: upgrade news appears once on Home, with a static budget",function()
        withHost(function(batches)
            local pending=E.S.news_012_pending
            local saved=E.saveSettings
            local saves=0
            E.saveSettings=function() saves=saves+1 end
            E.S.news_012_pending=true
            ok(E.HomeHost.show())
            local dialog=W.shown[#W.shown]
            eq(dialog.title,"What's new in 0.12"); eq(#dialog.buttons,5)
            ok(dialog.buttons[5][1].height>=50,"upgrade acknowledgement meets the touch minimum")
            eq(#batches,1,"news adds no read-model batch")
            dialog.buttons[5][1].callback()
            eq(E.S.news_012_pending,false); eq(saves,1)
            ok(E.HomeHost.show())
            eq(W.shown[#W.shown],E.HomeHost.active,"already seen")
            E.S.news_012_pending=true
            local dismissed=E.HomeHost.whatsNew()
            eq(dismissed.dismiss_callback,nil,"ButtonDialog does not support InfoMessage's dismissal hook")
            dismissed:onClose() -- native Back and outside taps take this same path
            eq(E.S.news_012_pending,false); eq(saves,2)
            E.S.news_012_pending=false
            ok(E.HomeHost.show())
            eq(W.shown[#W.shown],E.HomeHost.active,"fresh install has no news")
            E.saveSettings=saved; E.S.news_012_pending=pending
            eq(E.Budgets.screens["whats-new"].roundTrips,0)
        end)
    end)
    test("First run: empty reading and shelves give guidance without a dead Retry",function()
        withHost(function()
            for _,widget in ipairs({"continue-reading","booklist","lists"}) do
                local p={widget=widget,settings={title="Want to read"}}
                local card=E.HomeWidgets.card(p,E.HomeHostPlan.snapshot({items={},freshness={saved=true}}),function() error("no action") end,{w=400,h=300})[1]
                local guidance=false
                for _,child in ipairs(card) do
                    ok(child.text~="Retry")
                    if child.text==(widget=="continue-reading" and "Open a book to start reading" or widget=="lists" and "No lists yet" or "No books here yet") then guidance=true end
                end
                ok(guidance)
            end
        end)
    end)
    test("First run: missing catalog uses actionable signed-out cards, cached rows survive",function()
        withHost(function()
            local a={signedIn=false,opds={available=false}}
            local missing=E.HomeHostPlan.snapshot({items={},pending=true},a)
            eq(missing.state,"error"); eq(missing.setup,true)
            local declared=false
            for _,state in ipairs(E.WidgetRegistry.booklist.states) do if state==missing.state then declared=true end end
            ok(declared,"setup cards retain the declared widget state contract")
            local action
            local card=E.HomeWidgets.card({widget="booklist",settings={}},missing,function(id) action=id end,{w=400,h=300})[1]
            eq(card[#card].text,"Sign in"); card[#card].callback(); eq(action,"setup")
            local cached=E.HomeHostPlan.snapshot({items={{key="b"}},freshness={saved=true}},a)
            eq(cached.state,"ready")
            a.opds.available=true
            eq(E.HomeHostPlan.snapshot({items={},pending=true},a).state,"loading","own catalog login needs no account")
            a.opds.available=false; a.sync={available=true}
            eq(E.HomeHostPlan.snapshot({items={},pending=true},a).state,"loading","own sync login can still materialize local windows")
            a.signedIn=true; a.sync.available=false
            eq(E.HomeHostPlan.snapshot({items={},pending=true},a).state,"loading","signed in projection can complete")
        end)
    end)
    dofile((arg[0]:match("^(.*)/") or ".").."/storage_flows.lua")(test,eq,ok,E,W,withHost)
    test("Home host: paint batches only installed visible widgets and page swipe",function()
        withHost(function(batches,reads)
            E.S.home_layout=E.Layout.default()
            table.insert(E.S.home_layout.pages,2,{id="second",tab="Home",name="More books",placements={{instance="more",widget="booklist",version=1,x=0,y=0,w=4,h=2,settings={src="wtr"}}}})
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            eq(#batches,1); eq(#batches[1],8) -- capabilities + six placements + local storage
            eq(h.metrics.spawns,0); eq(h.metrics.network,0); eq(h.metrics.roundTrips,1)
            eq(h.metrics.rows,8); ok(h.metrics.bytes<=E.Budgets.screens.home.bytes)
            eq(h.index,1)
            h:onHomeSwipe(nil,{direction="west"}); eq(h.index,2)
            eq(#batches,2); eq(#batches[2],2,"future-only page is skipped; second Shelf still reads")
            h:onHomeSwipe(nil,{direction="east"}); eq(h.index,1)
            h:onPrevious(); eq(h.index,1)
            h:onClose(); h:onCloseWidget(); eq(E.Library.listener,nil)
        end)
    end)
    test("Home design: page title, menu settings and Back restore the originating page",function()
        withHost(function()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:turn(2); local index=h.index
            eq(find(h,"text","Stats").text,"Stats")
            ok(find(h,"text","Stats").max_width<=h.dimen.w-220,"page title leaves room for Search and menu")
            h:showList("Want to read","want-to-read")
            h:onClose(); eq(h.index,index); eq(find(h,"text","Stats").text,"Stats")
            local old=E.state.module
            local opened=0
            E.state.module={showSettings=function() opened=opened+1 end}
            local success,err=pcall(function()
                h:menu(); local menu=W.shown[#W.shown]
                eq(menu.buttons[1][1].text,"Browse library")
                eq(menu.buttons[3][1].text,"BookSync settings")
                menu.buttons[3][1].callback(); eq(opened,1); eq(W.shown[#W.shown],h)
            end)
            E.state.module=old
            ok(success,err)
        end)
    end)
    test("Home design: all installed widget sizes keep touch controls at least 50 logical pixels",function()
        withHost(function()
            local data={items={{key="a",title="The Moon",authors={"A"},progress=25,local_path="book.epub"},
                {key="b",title="Glasswater",progress=62},{key="c",title="Lantern"},{key="d",title="Sea"}},freshness={saved=true}}
            local function controls(node,ox,oy,bounds,found)
                ox,oy=ox or 0,oy or 0
                local at=node.overlap_offset or {0,0}; ox,oy=ox+at[1],oy+at[2]
                if node.callback and node.width and node.height then
                    ok(node.width>=50 and node.height>=50,"small target: "..tostring(node.text).." "..node.width.."×"..node.height)
                    ok(ox>=0 and oy>=0 and ox+node.width<=bounds.w and oy+node.height<=bounds.h,
                        "target outside card: "..tostring(node.text))
                    for _,r in ipairs(found) do
                        ok(not (ox<r.x+r.w and r.x<ox+node.width and oy<r.y+r.h and r.y<oy+node.height),
                            "overlapping targets: "..tostring(node.text).." / "..r.text)
                    end
                    found[#found+1]={x=ox,y=oy,w=node.width,h=node.height,text=node.text}
                end
                for _,child in ipairs(node) do controls(child,ox,oy,bounds,found) end
            end
            for _,id in ipairs({"continue-reading","booklist","lists","library","battery"}) do
                for _,size in ipairs(E.WidgetRegistry[id].sizes["android-tablet"]) do
                    local rect=E.HomeHostPlan.rect({x=0,y=0,w=size[1],h=size[2]},{cols=4,rows=8},678,764,12)
                    local p={widget=id,w=size[1],h=size[2],settings={style=1}}
                    for _,state in ipairs({"ready","empty","loading","error","offline-without-data","offline-with-data","setup"}) do
                        local snap=E.HomeHostPlan.snapshot(data)
                        if id=="library" then snap=E.HomeHostPlan.snapshot({total=7,on_device=2,freshness={saved=true}}) end
                        if id=="battery" then snap=E.HomeHostPlan.snapshot({level=78,display={level="78%"},freshness={saved=true}}) end
                        local plain={state=state=="setup" and "error" or state,setup=state=="setup",items=snap.items,count=snap.count,data=snap.data,bytes=snap.bytes}
                        local card=E.HomeWidgets.renderers[id](p,plain,function() end,rect)
                        controls(card,0,0,{w=rect.w,h=rect.h},{})
                        if id=="continue-reading" and (state=="ready" or state=="offline-with-data") then
                            local percent=false
                            for _,child in ipairs(card[1]) do if child.text=="25%" then percent=true end end
                            ok(percent,"every hero size retains the percentage label")
                        end
                        if id=="booklist" then
                            p.settings.style=0
                            controls(E.HomeWidgets.renderers[id](p,plain,function() end,rect),0,0,{w=rect.w,h=rect.h},{})
                            p.settings.style=1
                        end
                    end
                end
            end
        end)
    end)
    test("Home Settings: owned root preserves the current PIN policy",function()
        withHost(function()
            local owner=setmetatable({}, {__index=E.OrbitAndroid})
            local normal,locked=0,0
            owner.menuItems=function() normal=normal+1; return {{text="Book info"},{text="Your server",settings_group="account"}} end
            owner.lockedMenuItems=function(_,items) locked=locked+1; eq(#items,1); eq(items[1].settings_group,"account"); return {{text="Locked"}} end
            E.Shared.refresh=function() end
            E.Shared.pin_locked=false
            local menu=owner:showSettings()
            eq(menu.make()[1].text,"Your server"); eq(#menu.make(),1); eq(normal,1); eq(locked,0)
            E.Shared.pin_locked=true
            menu=owner:showSettings()
            eq(menu.make()[1].text,"Locked"); eq(normal,2); eq(locked,1)
        end)
    end)
    test("Home design: wide cover shelves read columns rather than a text-row limit",function()
        withHost(function(_,reads)
            local layout=E.Layout.default()
            layout.pages={{id="shelf",tab="Home",placements={{instance="wide",widget="booklist",version=1,
                x=0,y=0,w=4,h=2,settings={title="Recently added",src="recent",style=0}}}}}
            E.S.home_layout=layout
            E.Device.screen.getHeight=function() return 1200 end
            local h=E.HomeHost.create(); E.HomeHost.active=h
            eq(reads[#reads].op,"window"); eq(reads[#reads].limit,4)
            eq(h.metrics.roundTrips,1); eq(h.metrics.spawns,0); eq(h.metrics.network,0)
            E.Device.screen.getHeight=function() return 800 end
            h.dimen.h=800;h:rebuild()
            eq(reads[#reads].limit,1,"short shelf requests only its visible compact row")
        end)
    end)
    test("Home card rows: paging consumes exactly the visible books",function()
        withHost(function()
            E.Device.screen.getHeight=function() return 936 end -- Match the 702-unit M8C reference viewport.
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local args=E.Cache.decode(raw)
                if args.op~="window" then return read(raw) end
                local items={}
                for n=args.offset+1,args.offset+args.limit do
                    items[#items+1]={key="book-"..n,title="Book "..n,progress=25}
                end
                local result={items=items,next=args.offset+args.limit,total=20,freshness={saved=true}}
                return result,#E.Cache.encode(result)
            end
            local h=E.HomeHost.create();E.HomeHost.active=h
            h:showList("Library","library/all")
            eq(h.list_limit,15);eq(#h.list_result.items,15)
            eq(h.list_result.items[1].title,"Book 1");eq(h.list_result.items[15].title,"Book 15")
            h:listPage(1)
            eq(h.list_result.items[1].title,"Book 16");eq(h.list_result.items[15].title,"Book 30")
            h:listPage(-1);eq(h.list_result.items[1].title,"Book 1")
        end)
    end)
    test("Home host: immutable snapshots isolate query and renderer errors",function()
        withHost(function(batches,reads,U)
            local render=E.HomeWidgets.renderers.booklist
            local errors=0
            E.HomeWidgets.renderers.booklist=function(p,snapshot)
                eq(pcall(function() snapshot.items[1].title="changed" end),false)
                errors=errors+1; error("broken renderer")
            end
            local success,err=pcall(function()
                local h=E.HomeHost.create(); E.HomeHost.active=h
                ok(errors>0); eq(h.metrics.roundTrips,1); eq(#batches,1)
                -- Query budget errors produce cards and do not poison the host flush.
                local read=E.LibraryAdapter.read
                E.LibraryAdapter.read=function(raw)
                    if E.Cache.decode(raw).op=="window" then error("unavailable read") end
                    return read(raw)
                end
                h:rebuild(); eq(h.metrics.rows,4); eq(#batches,2)
            end)
            E.HomeWidgets.renderers.booklist=render
            ok(success,err)
        end)
    end)
    test("Home host: deferred drawing errors and malformed settings stay inside cards",function()
        withHost(function()
            E.S.home_layout=E.Layout.default()
            E.S.home_layout.pages[1].placements[2].settings.limit="invalid"
            local old=E.HomeWidgets.renderers["continue-reading"]
            E.HomeWidgets.renderers["continue-reading"]=function()
                return {paintTo=function() error("deferred render error") end,free=function() end}
            end
            local success,err=pcall(function()
                local h=E.HomeHost.create(); E.HomeHost.active=h
                local canvas=h[1][1]
                local boundary=find(canvas,"instance","resume")
                local failed=boundary[1]
                local Frame=E.HomeWidgets.ui().Frame
                Frame.paintTo=function() end
                boundary:paintTo({},0,0)
                ok(boundary[1] ~= failed,"replaced only the broken card")
                ok(h.metrics.rows>=2,"siblings still have data")
                Frame.paintTo=nil
            end)
            E.HomeWidgets.renderers["continue-reading"]=old
            ok(success,err)
        end)
    end)
    test("Home host: read-model invalidation redraws only an already visible Home",function()
        withHost(function(batches)
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            E.Library.changed({kind="library"}); E.Library.changed({kind="library"})
            local callback=h.redraw; ok(callback); callback(); eq(#batches,2)
            W.shown={}; E.Library.changed({kind="library"}); h.redraw(); eq(#batches,2)
            h:onCloseWidget(); eq(E.Library.listener,nil)
        end)
    end)
    test("Home wiring: both approved default pages draw and Stats shares one bounded row",function()
        withHost(function(batches,reads)
            E.S.home_layout=nil
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local rectangles=0
            local bb={paintRect=function(_,x,y,w,h,color) ok(w>=0 and h>=0); ok(color~=nil); rectangles=rectangles+1 end}
            for page=1,2 do
                eq(h.index,page)
                h[1]:paintTo(bb,0,0)
                ok(E.Budgets.check(E.Budgets.screens.home,h.metrics))
                eq(h.metrics.spawns,0); eq(h.metrics.network,0); eq(h.metrics.roundTrips,1)
                if page<2 then h:onNext() end
            end
            local stats=0
            for _,a in ipairs(reads) do if a.op=="reading.stats" then stats=stats+1 end end
            eq(stats,1); eq(#batches,2)
            ok(rectangles>=400,"real Year, weekly and hourly renderers painted")
        end)
    end)
    test("Home metrics: separate approved cards share one bounded worker snapshot",function()
        withHost(function(batches,reads)
            E.S.home_layout=E.Layout.default()
            local placements={}
            for i,id in ipairs({'today','reading-streak','reading-goal','pages-read'}) do
                placements[i]={instance='metric-'..i,widget=id,version=1,x=((i-1)%2)*2,y=math.floor((i-1)/2)*2,w=2,h=2,settings={}}
            end
            placements[5]={instance='monthly',widget='monthly-reading',version=1,x=0,y=4,w=4,h=2,settings={}}
            placements[6]={instance='year',widget='year-in-reading',version=1,x=0,y=6,w=4,h=2,settings={}}
            E.S.home_layout.pages={E.S.home_layout.pages[1]}
            E.S.home_layout.pages[1].placements=placements
            assert(E.Layout.validate(E.S.home_layout))
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            local count,old=0,0
            for _,request in ipairs(reads) do if request.op=='reading.metrics' then count=count+1;eq(request.limit,1) elseif request.op=='reading.stats' then old=old+1 end end
            eq(count,1);eq(old,1);eq(#batches,1);eq(h.metrics.roundTrips,1)
            eq(h.metrics.spawns,0);eq(h.metrics.network,0)
            ok(E.Budgets.check(E.Budgets.screens.home,h.metrics))
        end)
    end)
    test("Home wiring: measured Battery paints its true level in the shared batch",function()
        withHost(function(batches,reads)
            E.S.home_layout=nil
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:onNext(); h:onNext()
            local card=find(h,"instance","battery")[1][1]
            ok(find(card,"text","78%"))
            ok(find(card,"text","≈ 2 d 6 h at your usual use"))
            ok(find(card,"percentage",.78))
            local count=0
            for _,a in ipairs(reads) do if a.op=="battery" then count=count+1 end end
            eq(count,1); eq(h.metrics.roundTrips,1); eq(h.metrics.spawns,0); eq(h.metrics.network,0)
        end)
    end)
    test("Home wiring: Battery compact and large cards keep progress in bounds",function()
        withHost(function()
            local snapshot=E.HomeHostPlan.snapshot({level=78,hours_usual_use=54,freshness={saved=true}})
            for _,case in ipairs({{w=280,h=69,cols=2,rows=1},{w=130,h=149,cols=1,rows=2},{w=580,h=230,cols=4,rows=2}}) do
                local rect=case
                local card=E.HomeWidgets.renderers.battery({w=case.cols,h=case.rows},snapshot,function() end,rect)[1]
                for _,child in ipairs(card) do
                    if child.percentage then
                        eq(child.percentage,.78)
                        ok(child.overlap_offset[1]+child.width<=card.dimen.w)
                        ok(child.overlap_offset[2]+child.height<=card.dimen.h)
                    end
                end

            end
        end)
    end)
    test("Home wiring: configured Library tile exposes bounded device and group links",function()
        withHost(function()
            E.S.home_layout=E.Layout.default()
            E.S.home_layout.pages[2].placements={{instance="summary",widget="library",version=1,x=0,y=0,w=2,h=2,settings={}}}
            local oldHeight=E.Device.screen.getHeight
            E.Device.screen.getHeight=function() return 1600 end
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            E.Device.screen.getHeight=oldHeight
            h:onNext()
            local tile=find(h,"instance","summary")[1][1]
            local links={}; for _,child in ipairs(tile) do if child.callback then links[child.text]=child end end
            ok(links["2 on device ›"]); ok(links["Authors ›"]); ok(links["Series ›"]); ok(links["Collections ›"])
            for _,child in ipairs(tile) do if child.height then
                ok(child.overlap_offset[2]+child.height<=tile.dimen.h)
            end end
            links["Series ›"].callback()
            eq(h.filter.model.source,"library/all"); eq(h.filter.model.query.group,"series")
        end)
    end)
    test("Home wiring: list and search filter buttons save a reusable tile",function()
        withHost(function(batches,reads)
            E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:dispatch("all",nil,E.S.home_layout.pages[1].placements[5])
            eq(h.filter.model.source,"recently-added")
            h.filter:header(h.list_result.total).callback()
            local filter=h.filter
            ok(filter.alive)
            filter.dialog.buttons[1][1].callback() -- Show picker
            eq(filter.model.pick,"show")
            filter.dialog.buttons[1][1].callback() -- Unread
            eq(filter.model.query.show,"unread")
            filter.dialog.buttons[11][1].callback() -- Save footer after nine rows + divider
            eq(filter.alive,false)
            local found
            for _,page in ipairs(E.S.home_layout.pages) do for _,p in ipairs(page.placements) do
                if p.settings.src=="custom" then found=p end
            end end
            ok(found); eq(found.settings.source,"recently-added"); eq(found.settings.query.show,"unread")
            E.S.home_layout=nil; E.Library.layout.loaded=false
            local reloaded=E.HomeHost.document()
            local restored
            for _,page in ipairs(reloaded.pages) do for _,p in ipairs(page.placements) do
                if p.instance==found.instance then restored=p end
            end end
            ok(restored); eq(restored.settings.query.show,"unread")
            local toast=W.shown[#W.shown]
            toast.buttons[1][1].callback()
            eq(h.list_layout,nil)
            h:dispatch("all",nil,found)
            eq(h.filter.model.query.show,"unread")
            eq(h.filter.model.source,"recently-added")
            ok(E.Budgets.check(E.Budgets.screens.library,h.metrics))
            h:search()
            local input=W.shown[#W.shown]; input.buttons[1][2].callback()
            eq(h.filter.model.source,"search"); eq(h.filter.model.query.q,"Moon")
            eq(h.filter.model.query.sort,"match")
            ok(h.filter:header(h.list_result.total).callback)
        end)
    end)
    test("Home wiring: filter dialogs over Home keep cached reads available above an open book",function()
        withHost(function()
            local h=E.HomeHost.create(); E.HomeHost.active=h
            local reader={document={}}
            E.liveUI=function() return reader end
            E.Wifi.state=function() return {foreground=true} end
            E.FinishUI.sheet=nil
            W.shown={reader,h}
            eq(E.reading(),false)
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                eq(E.reading(),false,"owned Home dialog is browsing, not foreground reading")
                return read(raw)
            end
            h:showList("Library","library/all")
            h.filter:show()
            eq(E.reading(),false,"filter sheet above Home")
            h.filter.dialog.buttons[1][1].callback()
            eq(h.filter.model.pick,"show"); eq(h.filter.total,2)
            eq(E.reading(),false,"picker above Home")
            h.filter.dialog.buttons[1][1].callback()
            eq(h.filter.model.query.show,"unread")
            W.shown={h,reader}
            eq(E.reading(),true,"reader placed above Home remains protected")
            W.shown={reader}
            eq(E.reading(),true,"stale active Home cannot open the gate")
            local filter=h.filter
            h:onCloseWidget()
            eq(filter.alive,false); eq(filter.dialog,nil); eq(filter.retry,nil)
        end)
    end)
    test("Home wiring: nonlocal Details retain Home above the open book",function()
        withHost(function()
            local h=E.HomeHost.create(); E.HomeHost.active=h
            local reader={document={}}
            E.liveUI=function() return reader end
            E.Wifi.state=function() return {foreground=true} end
            E.FinishUI.sheet=nil
            W.shown={reader,h}
            E.Library.open=function() return false end
            E.ReaderPanel={details=function(key)
                eq(key,"opaque-book"); eq(E.reading(),false)
                W.shown[#W.shown+1]={name="booksync_details"}
                return true
            end}
            h:dispatch("book",{key="opaque-book"})
            eq(W.shown[2],h,"Details Back returns to Home")
            eq(E.reading(),false)
            table.remove(W.shown)
            h:onClose(); h:onCloseWidget()
            eq(E.reading(),true,"closing Home restores foreground reading")
            local resumed=E.HomeHost.create(); E.HomeHost.active=resumed; W.shown={reader,resumed}
            E.Library.open=function() return true end
            E.ReaderPanel={details=function() error("local Resume must not open Details") end}
            resumed:dispatch("book",{key="local-book",local_path="/fixture/book.epub"})
            eq(W.shown[#W.shown],reader)
            eq(E.reading(),true,"local Resume closes Home")
        end)
    end)
    test("Home wiring: failed filter save preserves the published layout",function()
        withHost(function()
            E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local published=E.S.home_layout
            E.HomeEditor.save=function() return nil,"layout write failed" end
            eq(h:saveFilter({base_source="search",query={q="Moon"}}),false)
            eq(E.S.home_layout,published)
            eq(W.shown[#W.shown].text,"layout write failed")
        end)
    end)
    test("Home wiring: bounded list paging returns to the prior full window",function()
        withHost(function()
            local adapterRead=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local a=E.Cache.decode(raw)
                if a.op~="window" then return adapterRead(raw) end
                local rows={}
                local limit=a.limit
                for i=1,math.min(limit,limit+1-a.offset) do rows[i]={key="book-"..(a.offset+i),title="Book"} end
                return {items=rows,total=limit+1,next=a.offset==0 and limit or nil,freshness={saved=true}},400
            end
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:showList("Library","library/all")
            local settings=h.list_layout.pages[1].placements[1].settings
            local n=h.list_limit
            eq(#h.list_result.items,n)
            h:onNext(); eq(settings.offset,n); eq(#h.list_result.items,1)
            h:onPrevious(); eq(settings.offset,0); eq(#h.list_result.items,n)
            local snapshot=E.HomeHostPlan.snapshot({items={{title=string.rep("x",16384)}},freshness={saved=true}})
            eq(snapshot.state,"error"); eq(snapshot.count,0)
        end)
    end)
    test("Home wiring: full pages grow a named page without changing the original",function()
        local d=E.Layout.default()
        d.pages={{id="full",tab="Home",placements={{instance="fill",widget="future",version=1,x=0,y=0,w=4,h=8,settings={}}}}}
        local out,page=E.HomeHostPlan.saveFilter(d,{base_source={kind="list",key="opaque"},query={q="Moon"}},"Short books")
        ok(out); eq(#d.pages,1); eq(#out.pages,2); eq(out.pages[2].name,"Short books")
        eq(out.pages[2].id,page); eq(out.pages[2].placements[1].settings.source.key,"opaque")
        ok(E.Layout.validate(out))
    end)
    test("Home host: grid projection, immutable contract and strict budgets",function()
        local p={x=2,y=3,w=2,h=3}
        local r=E.HomeHostPlan.rect(p,{cols=4,rows=8},580,680,12)
        ok(r.x>0 and r.y>0 and r.x+r.w<=580 and r.y+r.h<=680)
        local b=E.Budgets.widgets.lists
        for _,field in ipairs({"rows","bytes","spawns","roundTrips","network","snapshotBytes"}) do
            local counts={rows=0,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}
            counts[field]=b[field]+1; eq(E.Budgets.check(b,counts),nil,field)
        end
        eq(E.HomeHostPlan.need({widget="booklist",settings={src="wtr"}}).source,"want-to-read")
        eq(E.HomeHostPlan.need({widget="booklist",settings={src="recent"}}).source,"recently-added")
        local also=E.HomeHostPlan.need({widget="booklist",settings={src="reading",sort=3}})
        eq(also.offset,0); eq(also.exclude_current,true); eq(also.query.sort,"last"); eq(also.query.dir,"desc")
        eq(E.HomeHostPlan.snapshot({items={},freshness={saved=true}}).state,"empty")
        eq(E.HomeHostPlan.snapshot({items={},pending=true}).state,"loading")
        eq(E.HomeHostPlan.snapshot({items={}}).state,"offline-without-data")
        eq(E.HomeHostPlan.snapshot({items={{key="b"}},freshness={saved=true,offline=true}}).state,"offline-with-data")
        local registry=E.HomeHost.installed()
        eq(#E.HomeHostPlan.resolve(E.Layout.default(),registry,{}).pages,2)
        local projected=E.HomeHostPlan.resolve(E.Layout.default(),registry,{wantToRead=false,lists={read=false},battery=false})
        for _,p in ipairs(projected.pages[1].placements) do ok(p.widget ~= "lists" and p.instance ~= "want") end
    end)
    test("Home host: server-only book cards open the owned Details surface",function()
        withHost(function()
            local open,panel=E.Library.open,E.ReaderPanel
            local target
            local success,err=pcall(function()
                E.Library.open=function() return false end
                E.ReaderPanel={details=function(key) target=key; return true end}
                local h=E.HomeHost.create(); E.HomeHost.active=h
                h:dispatch("book",{key="opaque-book"})
                eq(target,"opaque-book")
            end)
            E.Library.open,E.ReaderPanel=open,panel
            ok(success,err)
        end)
    end)

    test("Settings labels: multi-line choices retain a title and explanatory row",function()
        withHost(function()
            local view=E.SettingsView.open("Channel",function() return {{id="channel",text="Stable\nTested releases only",height=96}} end,"settings-updates")
            local row=view.dialog:getButtonById("channel")
            eq(row.text,"Stable")
            view:close()
        end)
    end)
    test("Home host: a covered event redraws after reveal without reading on paint",function()
        withHost(function()
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            local nextTick=E.UIManager.nextTick
            local pending,calls=nil,0
            local rebuild=h.rebuild
            h.rebuild=function(self) calls=calls+1;return rebuild(self) end
            E.UIManager.nextTick=function(_,fn) pending=fn end
            local success,err=pcall(function()
                W.shown={h,{name="dialog"}}
                h:invalidate();pending();eq(calls,0);eq(h.invalid,true)
                pending=nil;W.shown={h}
                h:paintTo({paintRect=function() end},0,0)
                eq(calls,0,"paint only schedules the redraw")
                ok(pending,"revealing Home resumes its pending invalidation")
                pending();eq(calls,1);eq(h.invalid,nil)
            end)
            E.UIManager.nextTick=nextTick
            ok(success,err)
        end)
    end)
    test("Home cards: hero cover clears its measured heading",function()
        withHost(function(_,_,U)
            U.Text.getSize=function() return {w=100,h=60} end
            local cover=E.HomeWidgets.cover
            local y,height,right
            E.HomeWidgets.cover=function(_,_,x,top,w,h) y,height,right=top,h,x+w end
            local snapshot=E.HomeHostPlan.snapshot({items={{key="fixture",title="Fixture"}},freshness={saved=true}})
            local card=E.HomeWidgets.card({widget="continue-reading",w=4,h=2,settings={}},snapshot,function() end,{w=600,h=280})
            E.HomeWidgets.cover=cover
            ok(y>=14,"cover keeps its top inset")
            ok(find(card,"text","Fixture").overlap_offset[1]>right,"title and cover occupy separate columns")
            ok(y+height<=278-14,"cover stays within the tile")
        end)
    end)
    test("Home cards: projected labels, overflow routes and deferred cover lifetime",function()
        withHost(function(_,_,U)
            local b={key="opaque",title="The Moon",authors={"A"},progress=25,local_path="book.epub",series_key="series-key",
                series_line="Moon · Book 2",time_left="50 m left",finish_forecast="Done by Tuesday"}
            b.added_label="Yesterday";eq(E.HomeWidgets.caption({cap=1},b),"Yesterday","worker-provided date caption")
            local snap=E.HomeHostPlan.snapshot({items={b},freshness={saved=true}})
            local actions={}
            local card=E.HomeWidgets.card({widget="continue-reading",w=4,h=4,settings={}},snap,
                function(action) actions[#actions+1]=action end,{w=678,h=374})
            local labels={}
            for _,child in ipairs(card[1]) do
                if child.text then labels[child.text]=true end
                if child.text=="⋯" then child.callback() end
            end
            for _,label in ipairs({b.series_line,b.time_left,b.finish_forecast}) do ok(labels[label],label) end
            eq(actions[1],"more")
            local unknown=E.HomeHostPlan.snapshot({items={{key="unknown",title="No locator"}},freshness={saved=true}})
            local missing=E.HomeWidgets.card({widget="continue-reading",w=4,h=2,settings={}},unknown,function() end,{w=678,h=178})
            local unknownLabel=false
            for _,child in ipairs(missing[1]) do
                ok(child.text~="0%","missing position never becomes zero progress")
                if child.text=="—" then unknownLabel=true end
            end
            ok(unknownLabel)
            local dense=E.HomeWidgets.card({widget="booklist",w=4,h=2,settings={style=1,cap=3}},snap,function() end,{w=678,h=156})
            local caption=false
            for _,child in ipairs(dense[1]) do if child.text=="25% · 50 m left · A" then caption=true end end
            ok(caption,"compact rows retain the configured caption alongside pace")
            for _,height in ipairs({178,374}) do
                local c=E.HomeWidgets.card({widget="continue-reading",w=4,h=4,settings={}},snap,function() end,{w=678,h=height})
                local percent,left,bar
                for _,child in ipairs(c[1]) do
                    if child.text=="25%" then percent=child end
                    if child.text==b.time_left then left=child end
                    if child.percentage then bar=child end
                end
                ok(left.overlap_offset[1]>=percent.overlap_offset[1]+percent.max_width,"pace and percentage occupy separate columns")
                ok(left.overlap_offset[2]+16<=bar.overlap_offset[2],"pace text clears the progress bar")
            end
            local h=E.HomeHost.create(); E.HomeHost.active=h
            h:dispatch("more",b)
            local dialog=W.shown[#W.shown]
            eq(dialog.buttons[1][1].text,"Details"); eq(dialog.buttons[2][1].text,"Open")
            dialog.buttons[3][1].callback(); eq(h.series_key,"series-key")
            eq(dialog.buttons[4][1].enabled,false,"no alternate status sync writer")
            eq(dialog.buttons[5][1].enabled,false,"no unsafe file delete fallback")
            W.shown={h}
            local prepare,dirty=E.Library.prepareCardCover,E.UIManager.setDirty
            local dirtied
            E.UIManager.setDirty=function(_,window) dirtied=window end
            local calls,canceled,deliver=0,0
            E.Library.prepareCardCover=function(row,done)
                eq(row,b); calls=calls+1; deliver=done
                return function() canceled=canceled+1 end
            end
            local success,err=pcall(function()
                local c=E.HomeWidgets.canvas(80,120)
                local taps=0
                local tap=E.HomeWidgets.coverTap(c,function() taps=taps+1 end,10,20,80,100)
                tap:paintTo({},110,220)
                eq(tap.dimen.x,110);eq(tap.dimen.y,220)
                eq(tap.ges_events.TapCardCover[1].range,tap.dimen)
                ok(tap:onTapCardCover());eq(taps,1,"transparent cover input keeps a live native hit region")
                local cover=E.HomeWidgets.cover(c,b,0,0,80,120)
                eq(calls,0,"construction never decodes or acquires")
                cover:paintTo({},0,0); cover:paintTo({},0,0); eq(calls,1)
                cover:onCloseWidget(); cover:free(); eq(canceled,1,"native close cancels exactly once")
                deliver("/unused-after-free"); eq(calls,1,"late delivery ignored")
                local nativeRequire=E.require
                local decoded=0
                E.require=function(name)
                    if name=="ui/widget/imagewidget" then return U.Frame:extend{_render=function() decoded=decoded+1 end} end
                    return nativeRequire(name)
                end
                local imageCover=E.HomeWidgets.cover(c,b,0,0,80,120)
                imageCover:paintTo({},0,0); eq(decoded,0)
                local replacement={}
                E.HomeHost.active=replacement;W.shown={replacement}
                deliver("/other-home.jpg");eq(decoded,0,"another Home cannot receive this delivery")
                E.HomeHost.active=h;W.shown={h}
                deliver("/saved-cover.jpg"); eq(decoded,1)
                eq(dirtied,h,"prepared cover flags its initiating window for paint")
                ok(imageCover[1]._render,"placeholder replaced by prepared bitmap")
                imageCover:free()
                E.require=nativeRequire
            end)
            E.HomeHost.active=h;W.shown={h}
            E.Library.prepareCardCover,E.UIManager.setDirty=prepare,dirty
            ok(success,err)
        end)
    end)

    test("Home card covers: off-paint, bounded, coalesced and owner/cancel safe",function()
        withHost(function()
            local originalRequire,acquire=E.require,E.Library.acquireCover
            local savedCoverJobs=E.Library.cardCoverJobs
            E.Library.cardCoverJobs={head=1,tail=0,active=0}
            local owner,size="fixture",100
            local paths,requests,callback={},0
            E.LibraryAdapter.owner=function() return owner end
            E.LibraryAdapter.sent,E.LibraryAdapter.order={},{}
            E.require=function(name)
                if name=="lfs" then return {attributes=function() return {mode="file",size=size} end} end
                return originalRequire(name)
            end
            E.Library.acquireCover=function(key,done) requests=requests+1; callback=done end
            local function schedule(row)
                local cancel=E.Library.prepareCardCover(row,function(path) paths[#paths+1]=path end,function() return true end)
                return cancel,W.queue[#W.queue].fn
            end
            local success,err=pcall(function()
                local cancel,task=schedule({cover_path="saved.jpg"})
                eq(#paths,0);eq(requests,0,"paint schedules no command")
                task();cancel();eq(paths[1],"saved.jpg")
                size=E.Budgets.CARD_COVER_BYTES+1
                cancel,task=schedule({cover_path="oversized.jpg"});task();cancel();eq(#paths,1)
                size=100
                cancel,task=schedule({cover_path="canceled.jpg"});cancel();task();eq(#paths,1)
                cancel,task=schedule({key="remote"});task();cancel();eq(requests,1)
                local cancelAgain,again=schedule({key="remote"});again();cancelAgain();eq(requests,1,"misses coalesce")
                local cancelLate,late=schedule({key="other"});late();eq(requests,2)
                owner="replacement";callback({local_path="wrong-owner.jpg"});cancelLate();eq(#paths,1)
            end)
            E.Library.cardCoverJobs=savedCoverJobs
            E.require,E.Library.acquireCover=originalRequire,acquire
            ok(success,err)
        end)
    end)

    test("transfer controls: out-of-order same-job replies adopt only the latest sequence",function() withHost(function()
        local jobs,order,command=E.Library.downloadJobs,E.Library.downloadOrder,E.LibraryAdapter.command
        E.Library.downloadJobs={};E.Library.downloadOrder={}
        local callbacks={};local reply
        E.LibraryAdapter.command=function(_,_,done) callbacks[#callbacks+1]=done;return true end
        local success,err=pcall(function()
            E.Library.rememberDownload("book",{id="same-job",state="canceled",sequence=2})
            E.Library.downloadControl({key="book"},"status",function(result) reply=result end)
            E.Library.downloadControl({key="book"},"resume",function() end)
            callbacks[2]({id="same-job",state="queued",sequence=3,row_count=1})
            callbacks[1]({id="same-job",state="canceled",sequence=2,row_count=1})
            eq(reply.state,"queued");eq(reply.sequence,3)
            eq(E.Library.downloadState("book").state,"queued")
        end)
        E.Library.downloadJobs,E.Library.downloadOrder,E.LibraryAdapter.command=jobs,order,command
        ok(success,err)
    end) end)

    test("transfer snapshots: late canceled reply cannot replace a newer Resume",function() withHost(function()
        local saved,order=E.Library.downloadJobs,E.Library.downloadOrder
        E.Library.downloadJobs={};E.Library.downloadOrder={}
        E.Library.rememberDownload("book",{id="same-job",state="canceled",sequence=2})
        E.Library.rememberDownload("book",{id="same-job",state="queued",sequence=3})
        local adopted=E.Library.rememberDownload("book",{id="same-job",state="canceled",sequence=2})
        eq(adopted.state,"queued");eq(E.Library.downloadState("book").sequence,3)
        E.Library.rememberDownload("book",{id="same-job",state="complete",sequence=5})
        adopted=E.Library.rememberDownload("book",{id="same-job",state="running",sequence=4})
        eq(adopted.state,"complete")
        E.Library.downloadJobs,E.Library.downloadOrder=saved,order
    end) end)

    test("Home open: missing local file clears availability without starting a transfer",function() withHost(function()
        local exists,storage,req=E.Store.fileExists,E.Library.storageCommand,E.require
        local paths,order=E.Library.unavailablePaths,E.Library.unavailableOrder
        E.Library.unavailablePaths={};E.Library.unavailableOrder={}
        local opened,refreshed=0,0
        E.Store.fileExists=function() return false end
        E.Library.storageCommand=function(op,_,done) eq(op,"storage.refresh");refreshed=refreshed+1;done({ok=true}) end
        E.require=function(name)
            if name=="apps/reader/readerui" then return {showReader=function(_,path) eq(path,"/fixture/book.epub");opened=opened+1 end} end
            return req(name)
        end
        local success,err=pcall(function()
            local did,why=E.Library.open({local_path="/fixture/book.epub"})
            eq(did,false);eq(why,"missing");eq(opened,0);eq(refreshed,1)
            local paint=E.Library.paint("home");local result=paint:widget("booklist"):window("library/all",{},0,1)
            eq(result.items[1].local_path,nil,"known missing path is not offered as local")
            E.Store.fileExists=function() return true end
            ok(E.Library.open({local_path="/fixture/book.epub"}));eq(opened,1)
        end)
        E.Store.fileExists,E.Library.storageCommand,E.require=exists,storage,req
        E.Library.unavailablePaths,E.Library.unavailableOrder=paths,order
        ok(success,err)
    end) end)

    test("Home card download: explicit format, bounded progress, cancellation and no late focus",function()
        withHost(function()
            local prepare,start,control,open=E.Library.downloadPrepare,E.Library.downloadStart,E.Library.downloadControl,E.Library.open
            local connected=E.NetworkMgr.isConnected
            E.NetworkMgr.isConnected=function() return true end
            local calls,opened,deliver=0,0
            E.Library.downloadPrepare=function(_,done) calls=calls+1;deliver=done end
            E.Library.downloadStart=function(row,choice,done)
                eq(choice.file_reference,7);E.Library.rememberDownload(row.key,{id="job",state="running"});done({id="job",state="running"})
            end
            E.Library.downloadControl=function(_,action,done)
                if action=="status" then deliver=done elseif action=="cancel" then done({state="canceled"}) end
            end
            E.Library.open=function() opened=opened+1;return true end
            local success,err=pcall(function()
                local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
                h:dispatch("download",{key="remote"});h:dispatch("download",{key="remote"});eq(calls,1)
                deliver({items={{file_reference=7,label="EPUB",destination="/fixture/book.epub"}}})
                local chooser=W.shown[#W.shown];eq(chooser.buttons[1][1].text,"EPUB · size unknown")
                chooser.buttons[1][1].callback()
                local poll=W.queue[#W.queue].fn;poll()
                h:dispatch("download-cancel",{key="remote"})
                deliver({state="complete",local_path="saved.epub"});eq(opened,0,"Cancel revokes completion focus")
                E.Library.rememberDownload("remote",{id="next-job",state="running"})
                E.DownloadUI.watch(h,{key="remote"},function() return E.HomeHost.active==h end,true)
                poll=W.queue[#W.queue].fn;poll();E.HomeHost.active=nil
                deliver({state="complete",local_path="saved.epub"});eq(opened,0,"departure revokes completion focus")
                E.HomeHost.active=h;W.shown={h}
                E.Library.rememberDownload("remote",{id="final-job",state="running"})
                E.DownloadUI.watch(h,{key="remote"},function() return E.HomeHost.active==h end,true)
                poll=W.queue[#W.queue].fn;poll()
                deliver({state="complete",local_path="saved.epub"});eq(opened,1,"visible originating screen may open once")
                deliver({state="complete",local_path="saved.epub"});eq(opened,1,"terminal event cannot reopen it")
            end)
            E.Library.downloadPrepare,E.Library.downloadStart,E.Library.downloadControl,E.Library.open=prepare,start,control,open
            E.NetworkMgr.isConnected=connected;E.Library.downloadJobs={};E.Library.downloadOrder={};E.DownloadUI.preparing={};E.DownloadUI.intents={}
            ok(success,err)
        end)
    end)

    test("Home host: account setup actions use the right form and invalidate the subtitle region",function()
        withHost(function()
            local read,open=E.LibraryAdapter.read,E.AccountView.open
            local state={signedIn=false,sync={available=false},opds={available=false}}
            local kind
            E.AccountView.open=function(k) kind=k or "summary" end
            E.LibraryAdapter.read=function(raw)
                if E.Cache.decode(raw).op=="capabilities" then return {account=state},256 end
                return read(raw)
            end
            local success,err=pcall(function()
                local h=E.HomeHost.create(); E.HomeHost.active=h
                local canvas=h[1][1]
                local setup=find(canvas,"text","Not signed in · Sign in");eq(setup.text,"Not signed in · Sign in"); setup.callback(); eq(kind,"summary")
                for _,control in ipairs(canvas) do if control.text=="Search" then
                    ok(setup.overlap_offset[1]+setup.width<=control.overlap_offset[1],"setup subtitle does not overlap Search")
                end end
                state={signedIn=true,sync={available=false},opds={available=false}}
                h:rebuild(); canvas=h[1][1]
                local setup=find(canvas,"text","No sync login · Set up");eq(setup.text,"No sync login · Set up"); setup.callback(); eq(kind,"sync")
                eq(h.changed_rects[1].y,0); ok(h.changed_rects[1].h>0)
                h:dispatch("book",{key="remote-only"})
                eq(h.download_prompt.title,"No OPDS login, so it can't download")
                h.download_prompt.buttons[1][2].callback(); eq(kind,"opds")
                state={signedIn=true,sync={available=true},opds={available=true}}
                h:rebuild()
                eq(h.account_status,nil)
                ok(h.changed_rects[1].h>=76 and h.changed_rects[1].h<h.dimen.h,"removing setup action invalidates its header region")
            end)
            E.LibraryAdapter.read,E.AccountView.open=read,open
            ok(success,err)
        end)
    end)

    test("Clock: installed snapshot renderer, states, battery tap, Back and host refresh",function()
        withHost(function(batches,reads)
            local data={state="ready",time="21:42",weekday="Tuesday",date="25 November",battery="▭ 78% ›",
                days={{label="M",date="24"},{label="T",date="25",today=true}},freshness={saved=true}}
            local calls=0
            for _,size in ipairs(E.WidgetRegistry.clock.sizes["android-tablet"]) do
                local rect=E.HomeHostPlan.rect({x=0,y=0,w=size[1],h=size[2]},{cols=4,rows=8},678,764,12)
                for _,state in ipairs({"ready","loading","error","not-saved","empty","offline-without-data","offline-with-data"}) do
                    data.state=(state=="offline-with-data" and "ready" or state)
                    local snapshot=E.HomeHostPlan.snapshot(data)
                    local card=E.ClockWidgets.render({w=size[1],h=size[2]},snapshot,function(action) eq(action,"battery"); calls=calls+1 end,rect)
                    local time,battery,message=false,false,false
                    for _,control in ipairs(card[1]) do
                        if control.text=="21:42" then time=true end
                        if control.callback then
                            ok(control.width>=50 and control.height>=50)
                            ok(control.overlap_offset[2]+control.height<=rect.h)
                            control.callback(); battery=true
                        end
                        if control.text=="Loading clock" or control.text=="Time unavailable" or control.text=="Clock unavailable" then message=true end
                    end
                    if data.state=="ready" then ok(time and battery) else ok(message and not time and not battery) end
                end
            end
            eq(calls,6)
            data.state="ready"
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local args=E.Cache.decode(raw)
                if args.op=="device.clock" then return data,#E.Cache.encode(data) end
                return read(raw)
            end
            local success,err=pcall(function()
                local doc=E.Layout.default()
                doc.pages={{id="clock",tab="Home",name="Clock",placements={{instance="clock",widget="clock",version=1,x=0,y=0,w=2,h=2,settings={}}}}}
                E.S.home_layout=doc
                local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
                ok(h.widgetRefresh); eq(#batches,1); eq(h.metrics.roundTrips,1)
                local refresh=h.widgetRefresh
                refresh(); ok(h.redraw); h.redraw(); eq(#batches,2)
                -- Cover Home after the timer queues its redraw, then return with Back.
                h.widgetRefresh(); ok(h.redraw); W.shown={}; h.redraw(); eq(#batches,2)
                ok(h.widgetRefresh,"a suppressed redraw retains the host heartbeat")
                W.shown={h}; h.widgetRefresh(); ok(h.redraw); h.redraw(); eq(#batches,3)
                W.shown={}; local count=#batches; h.widgetRefresh(); eq(#batches,count)
                ok(not h.redraw,"hidden Home never paints")
                h:onClose(); h:onCloseWidget(); eq(h.widgetRefresh,nil)
            end)
            E.LibraryAdapter.read=read
            ok(success,err)
        end)
    end)

end
