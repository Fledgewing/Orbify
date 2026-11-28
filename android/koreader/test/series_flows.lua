-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,withHost)
    local function buttons(node,out)
        out=out or {}
        if node.callback then out[#out+1]=node end
        for _,child in ipairs(node) do buttons(child,out) end
        return out
    end
    local function tap(host,text)
        for _,button in ipairs(buttons(host)) do if button.text==text then return button.callback() end end
        error("missing control "..text)
    end
    local function text(host,wanted)
        local function find(node)
            if node.text==wanted then return true end
            for _,child in ipairs(node) do if find(child) then return true end end
        end
        return find(host)
    end
    local function fixtures(reads)
        local read=E.LibraryAdapter.read
        local groupValue
        local value={items={{key="one",title="Book one",number="1",authors={"Author"},status_text="Read · ★★★★",dot="read",local_path="fixture.epub"}},
            title="Orbit",subtitle="Author · 4 books · 1 read, 1 reading",dots={"read","reading","unread","unread"},
            next_books={{key="three",title="Book three",number=3}},row_count=3,total=4,next=1,freshness={saved=true}}
        E.LibraryAdapter.read=function(raw)
            local a=E.Cache.decode(raw)
            if a.op=="series" then reads[#reads+1]=a; return value,700 end
            if a.op=="groups" then
                if groupValue then reads[#reads+1]=a; return groupValue,700 end
                reads[#reads+1]=a
                return {items={{title="Orbit",series_key="opaque-series",count_text="All 4",partial=true,dots={"read","reading","unread","unread"},books=value.items},
                    {title="Not in a series",field="series",value="",count_text="All 17",partial=true,books=value.items}},
                    row_count=4,total=21,next=2,freshness={saved=true}},900
            end
            return read(raw)
        end
        return function(v) value=v end, function(v) groupValue=v end
    end
    test("Finish sheet opens saved Series from the reader and Back restores its sheet",function()
        withHost(function(batches,reads)
            fixtures(reads)
            local ui={document={file="finished.epub"}}
            local b={file="finished.epub",digest="finished-series",summary={status="complete"}}
            local model,action,native=E.FinishUI.model,E.Library.catalogAction,E.Library.nativeReader
            local nextTick,finish=E.UIManager.nextTick,E.Library.finishCurrent
            local jobs,sending=E.FinishUI.jobs[b.digest],E.FinishUI.sending
            local order,scheduled={},nil
            E.liveUI=function() return ui end
            E.HomeHost.active=nil; W.shown={ui}
            E.Library.nativeReader=function() return b end
            E.FinishUI.jobs[b.digest]={}; E.FinishUI.sending=nil
            E.FinishUI.model=function() return {title="Finished",status="Saved",series_key="opaque-series"} end
            E.Library.catalogAction=function(op) eq(op,"finish.leave");order[#order+1]=op end
            E.UIManager.nextTick=function(_,fn) scheduled=fn end
            E.Library.finishCurrent=function(done) order[#order+1]="existing-writer";done(true) end
            local success,why=pcall(function()
                E.FinishUI.showSheet(ui,b)
                tap(E.FinishUI.sheet,"View series")
                local h=E.HomeHost.active
                eq(E.FinishUI.sheet,nil);eq(h.series_key,"opaque-series")
                eq(reads[#reads].op,"series");eq(reads[#reads].key,"opaque-series")
                eq(h.metrics.network,0);eq(h.metrics.spawns,0);eq(h.metrics.roundTrips,1)
                eq(order[1],"finish.leave");eq(#order,1);ok(scheduled)
                scheduled();eq(order[2],"existing-writer")
                tap(h,"‹ Back")
                ok(E.FinishUI.sheet);eq(E.FinishUI.sheet.ui,ui);eq(E.FinishUI.sheet.book,b)
                eq(E.HomeHost.foreground(),false);eq(ui.document.file,"finished.epub")
            end)
            E.FinishUI.closeSheet()
            E.FinishUI.model,E.Library.catalogAction,E.Library.nativeReader=model,action,native
            E.UIManager.nextTick,E.Library.finishCurrent=nextTick,finish
            E.FinishUI.jobs[b.digest],E.FinishUI.sending=jobs,sending
            if not success then error(why) end
        end)
    end)
    test("Series flow: grouped Library/Search, reading order snapshots, Back and explicit entry",function()
        withHost(function(batches,reads)
            fixtures(reads)
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:turn(1); local home=h.index
            h:showList("Search","search",{q="calder",group="series",sort="match",where="on-device"})
            local settings=h.list_layout.pages[1].placements[1].settings
            eq(reads[#reads].op,"groups"); eq(reads[#reads].source,"search"); eq(reads[#reads].query.q,"calder")
            ok(h.metrics.rows<=E.Budgets.screens.search.rows); eq(h.metrics.roundTrips,1)
            eq(h.metrics.spawns,0); eq(h.metrics.network,0)
            tap(h,"Orbit")
            eq(h.series_key,"opaque-series"); eq(reads[#reads].op,"series"); eq(reads[#reads].key,"opaque-series")
            eq(h.metrics.rows,4,"nested previews are charged")
            ok(text(h,"Download the next 1")); ok(text(h,"Read · ★★★★"))
            tap(h,"Next"); eq(h.series_offset,1); eq(reads[#reads].offset,1)
            h:onPrevious(); eq(h.series_offset,0)
            tap(h,"‹ Back"); eq(h.series_key,nil); eq(settings.query.q,"calder"); eq(settings.query.where,"on-device")
            tap(h,"Not in a series")
            eq(h.filter.model.query.without_series,true); eq(h.filter.model.query.q,"calder")
            h:onClose(); eq(h.filter.model.query.group,"series"); eq(h.list_title,"Search")
            h:onClose(); eq(h.list_layout,nil); eq(h.index,home)
            ok(E.SeriesUI.show("from-end-sheet")); eq(h.series_key,"from-end-sheet")
            h:onClose(); eq(h.series_key,nil)
            local returned=0
            E.SeriesUI.show("callback",function() returned=returned+1 end)
            h:search(); W.shown[#W.shown].buttons[1][2].callback()
            h:onClose(); eq(h.series_key,"callback"); eq(returned,0)
            h:onClose(); eq(returned,1); eq(h.series_key,nil)
        end)
    end)
    test("Series flow: states, retry, local open, paging, search return and minimum targets",function()
        withHost(function(batches,reads)
            local set=fixtures(reads)
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:showSeries("opaque-series")
            for _,case in ipairs({
                {{error="missing"},"error","Couldn't load this page"},{{pending=true},"loading","Loading…"},
                {{items={},freshness={saved=false}},"offline-without-data","Not saved yet"},
                {{items={},freshness={saved=true}},"empty","No books"},
                {{items={{title="Book",key="a",status_text="On server"}},freshness={saved=true},offline=true},"offline-with-data","Offline · saved library"},
                {{items={{title="Book",key="a",status_text="On device",local_path="fixture.epub"}},remaining_saved=true,freshness={saved=true}},"ready","Every remaining book is on this device"},
            }) do
                set(case[1]); h:rebuild(); eq(h.catalog_state,case[2]); ok(text(h,case[3]))
                local found={}
                local function controls(node,x,y)
                    local at=node.overlap_offset or {0,0}; x,y=x+at[1],y+at[2]
                    if node.callback and node.width and node.height then
                        ok(node.width>=E.CatalogUI.kit().px(38) and node.height>=E.CatalogUI.kit().px(38))
                        ok(x>=0 and y>=0 and x+node.width<=h.dimen.w and y+node.height<=h.dimen.h)
                        for _,r in ipairs(found) do ok(not(x<r.x+r.w and r.x<x+node.width and y<r.y+r.h and r.y<y+node.height),"overlapping targets") end
                        found[#found+1]={x=x,y=y,w=node.width,h=node.height}
                    end
                    for _,child in ipairs(node) do controls(child,x,y) end
                end
                controls(h,0,0)
                if case[2]=="error" or case[2]=="offline-without-data" then
                    local n=0; local retry=E.Library.retry; E.Library.retry=function() n=n+1 end
                    tap(h,"Retry"); E.Library.retry=retry; eq(n,1)
                end
            end
            h:search(); local dialog=W.shown[#W.shown]; dialog.buttons[1][2].callback()
            eq(h.list_title,"Search"); eq(h.series_key,nil)
            h:onClose(); eq(h.series_key,"opaque-series")
            local opened
            E.Library.open=function(row) opened=row.local_path; return true end
            for _,b in ipairs(buttons(h)) do if b.text=="Book" then b.callback(); break end end
            eq(opened,"fixture.epub")
        end)
    end)
    test("Grouped rows: every state, partial/complete taps and bounded targets",function()
        withHost(function(batches,reads)
            local _,set=fixtures(reads)
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:showList("Library","library/all",{group="author"})
            for _,case in ipairs({
                {{error="unavailable"},"error"},{{pending=true},"loading"},
                {{items={},freshness={saved=false}},"offline-without-data"},
                {{items={},freshness={saved=true}},"empty"},
                {{items={{title="Author",count_text="1 book",field="author",value="Author",partial=false,books={{title="Book",key="one"}}}},freshness={saved=true},offline=true},"offline-with-data"},
                {{items={{title="Author",count_text="1 book",field="author",value="Author",partial=false,books={{title="Book",key="one"}}}},freshness={saved=true}},"ready"},
            }) do
                set(case[1]); h:rebuild(); eq(h.catalog_state,case[2])
                for _,b in ipairs(buttons(h)) do
                    if b.width and b.height then ok(b.width>=E.CatalogUI.kit().px(38) and b.height>=E.CatalogUI.kit().px(38)) end
                    ok(b.text~="Author · 1 book ›","complete authors have no link")
                end
                if case[2]=="ready" then ok(text(h,"Author"));ok(text(h,"1 book")) end
                eq(h.metrics.spawns,0); eq(h.metrics.network,0); eq(h.metrics.roundTrips,1)
            end
            local groups={}
            for i=1,E.SeriesPlan.geometry(h.dimen.w,h.dimen.h,function(n) return n end).groups do groups[i]={title="Author "..i,count_text="All 4",field="author",value="A"..i,partial=true,
                books={{key="a",title="A"},{key="b",title="B"},{key="c",title="C"}}} end
            set({items=groups,row_count=#groups*4,freshness={saved=true}}); h:rebuild()
            local found={}
            local function targets(node,x,y)
                local at=node.overlap_offset or {0,0}; x,y=x+at[1],y+at[2]
                if node.callback and node.width and node.height then
                    ok(node.width>=E.CatalogUI.kit().px(38) and node.height>=E.CatalogUI.kit().px(38))
                    ok(x>=0 and y>=0 and x+node.width<=h.dimen.w and y+node.height<=h.dimen.h)
                    for _,r in ipairs(found) do ok(not(x<r.x+r.w and r.x<x+node.width and y<r.y+r.h and r.y<y+node.height),"overlapping grouped targets") end
                    found[#found+1]={x=x,y=y,w=node.width,h=node.height}
                end
                for _,child in ipairs(node) do targets(child,x,y) end
            end
            targets(h,0,0)
            set({items=groups,row_count=#groups*4,next=2,freshness={saved=true}})
            h:rebuild(); h:listPage(1); eq(h.list_layout.pages[1].placements[1].settings.offset,2)
            set({items=groups,row_count=#groups*4,next=5,freshness={saved=true}})
            h:rebuild(); h:listPage(1); eq(h.list_layout.pages[1].placements[1].settings.offset,5)
            h:listPage(-1); eq(h.list_layout.pages[1].placements[1].settings.offset,2)
            h:listPage(-1); eq(h.list_layout.pages[1].placements[1].settings.offset,0)
            set({items=groups,row_count=25,freshness={saved=true}})
            ok(not pcall(function() h:rebuild() end),"nested row overrun must fail")
            set({items={{title="Orbit",series_key="series",count_text="1 book",partial=false,books={{title="Book",key="one"}},dots={"unread"}}},freshness={saved=true}})
            h:rebuild(); tap(h,"Orbit"); eq(h.series_key,"series")
        end)
    end)

    test("Series download preview requires explicit file review and never opens completed books",function()
        withHost(function(_,reads)
            fixtures(reads)
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h};h.series_key="opaque-series"
            local command,file,connected,root,schedule=E.Library.seriesCommand,E.Library.seriesFile,E.NetworkMgr.isConnected,E.Library.downloadRoot,E.UIManager.scheduleIn
            local calls={}
            local success,why=pcall(function()
                E.Library.downloadRoot=function() return "/Books" end
                E.NetworkMgr.isConnected=function() return true end
                E.UIManager.scheduleIn=function() end
                E.Library.seriesCommand=function(op,args,done)
                    calls[#calls+1]=op
                    if op=="find" then done({})
                    elseif op=="preview" then eq(args.count,3);done({items={{key="a",title="One"},{key="b",title="Two"}},token="exact"})
                    elseif op=="start" then
                        eq(args.token,"exact");eq(args.root,"/Books");eq(args.choices.a.file_reference,2);eq(args.choices.b.file_reference,2)
                        done({id="batch",state="complete",items={},summary="2 saved"})
                    else error(op) end
                end
                E.Library.seriesFile=function(_,root,done) eq(root,"/Books");done({items={{file_reference=1,label="EPUB"},{file_reference=2,label="PDF"}}}) end
                E.SeriesUI.download(h)
                eq(table.concat(calls,","),"find,preview")
                local function click(row,col) W.shown[#W.shown].buttons[row][col or 1].callback() end
                click(3);click(2);click(2)
                eq(W.shown[#W.shown].title:sub(1,17),"Download 2 books?")
                eq(table.concat(calls,","),"find,preview")
                click(3);eq(table.concat(calls,","),"find,preview,start");eq(W.shown[#W.shown].title,"2 saved")
            end)
            E.Library.seriesCommand,E.Library.seriesFile,E.NetworkMgr.isConnected,E.Library.downloadRoot,E.UIManager.scheduleIn=command,file,connected,root,schedule
            if not success then error(why) end
        end)
    end)
    test("Series download callbacks cannot reopen a departed series",function()
        withHost(function(_,reads)
            fixtures(reads)
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h};h.series_key="before"
            local command,root=E.Library.seriesCommand,E.Library.downloadRoot
            local pending
            E.Library.downloadRoot=function() return "/Books" end
            E.Library.seriesCommand=function(op,_,done) eq(op,"find");pending=done end
            E.SeriesUI.download(h);h.series_key="after"
            pending({});eq(#W.shown,1)
            E.Library.seriesCommand,E.Library.downloadRoot=command,root
        end)
    end)

end
