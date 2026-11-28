-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,Widget,withHost)
    local function press(view,text)
        for _,line in ipairs(view.dialog.buttons) do for _,b in ipairs(line) do
            if b.text==text then return b.callback() end
        end end
        error("missing row "..text)
    end
    local function sources(reads)
        local fallback=E.LibraryAdapter.read
        E.LibraryAdapter.read=function(raw)
            local a=E.Cache.decode(raw)
            if a.op~="sources" then return fallback(raw) end
            if reads then reads[#reads+1]=a end
            local rows={}
            if a.category=="builtin" then
                for _,src in ipairs({"custom","recent","wtr","reading","finished","device"}) do
                    rows[#rows+1]={src=src,title=E.BookList.names[src],count=7}
                end
            else
                local kind=({lists="list",series="series",authors="author",collections="collection",libraries="library"})[a.category]
                for i=a.offset+1,math.min(a.offset+a.limit,13) do rows[#rows+1]={src=kind..":key-"..i,title=kind.." "..i,count=i} end
            end
            return {items=rows,total=a.category=="builtin" and 6 or 13,next=a.category~="builtin" and a.offset<12 and a.offset+6 or nil,freshness={saved=true}},900
        end
    end
    test("Book list sources: late Library events refresh a visible picker without replacing Home",function()
        withHost(function()
            local read=E.LibraryAdapter.read;local ready=false
            E.LibraryAdapter.read=function(raw,...)
                if E.Cache.decode(raw).op=='sources' then
                    if not ready then return nil end
                    return {items={{src='year:2025',title='Finished in 2025',count=100}},total=1,freshness={saved=true}},200
                end
                return read(raw,...)
            end
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h};local listener=E.Library.listener
            local view=E.BookListConfig.new{cfg=E.BookList.preset('year'),origin=h,caps=h.caps,onDone=function() return true end}
            view.sources=true
            local active=E.Library.catalog_active;E.Library.catalog_active=true
            local opened,openErr=pcall(view.paint,view);E.Library.catalog_active=active;ok(opened,openErr)
            eq(W.shown[#W.shown],view.dialog,'explicit editor controls stay available during catalog refresh')
            if view.retry then E.UIManager:unschedule(view.retry);view.retry=nil end
            ready=true;E.Library.changed({kind='library'})
            ok(view.eventPaint,'late ready events must survive the bounded polling window')
            eq(E.Library.listener,listener)
            local refresh=view.eventPaint;W.shown={};refresh();eq(view.eventPaint,refresh)
            W.shown={view.dialog};E.Gate.background(refresh);eq(view.eventPaint,nil)
            eq(W.shown[#W.shown],view.dialog,'a background reply must replace the visible owned dialog')
            local reading=E.reading;E.reading=function() return true end
            local shown=false
            local safe,err=pcall(function() E.Gate.background(function() E.Gate.show('owned reading guard',function() shown=true end,nil,view.dialog) end) end)
            E.reading=reading;ok(safe,err);eq(shown,false,'an owned modal never bypasses the reading gate')
            press(view,'○ Finished in 2025 · 100');eq(view.cfg.src,'year:2025')
            view:close();E.Library.changed({kind='library'});eq(view.eventPaint,nil)
            E.LibraryAdapter.read=read
        end)
    end)
    test("Book list year: native request and immutable context retain saved-selection semantics",function()
        local cfg=E.BookList.choose(E.BookList.preset('year'),{src='year:2025',title='Finished in 2025',default_sort=0})
        local need=E.HomeHostPlan.need({widget='booklist',settings=cfg})
        eq(need.source.kind,'finished-year');eq(need.source.key,'2025');eq(need.query.sort,nil)
        local snap=E.HomeHostPlan.snapshot({items={{title='Saved'}},total=1,context={title='2025 · 100 total',coverage='Saved selection'},freshness={saved=true}})
        eq(snap.context.title,'2025 · 100 total');eq(pcall(function() snap.context.title='bad' end),false)
    end)
    test("Up next: See all and filter preserve the saved-selection context",function()
        withHost(function()
            E.S.home_layout=E.Layout.default();E.S.home_layout.pages={{id='next',tab='Home',name='Up next',placements={{instance='next',widget='booklist',version=1,x=0,y=0,w=4,h=3,settings=E.BookList.preset('upnext')}}}}
            local host=E.HomeHost.create();E.HomeHost.active=host;W.shown={host}
            host:dispatch('all',nil,{widget='booklist',settings=E.BookList.preset('upnext')})
            eq(host.filter.model.source,'series-next');eq(host.filter.model.query.sort,'order')
            local snapshot=E.HomeHostPlan.snapshot({items={{title='Next'}},total=1,context={coverage='Saved selection'},freshness={saved=true}})
            eq(snapshot.context.coverage,'Saved selection')
        end)
    end)
    test("Book list editor: every source, paged counted windows and filter return",function()
        withHost(function(batches,reads)
            sources(reads)
            E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local e=E.HomeEditor.show(h); e.model.selected="also"
            local cfg=e:configure()
            local old=e.model.document
            for _,src in ipairs({"recent","wtr","reading","finished","device"}) do
                press(cfg,"Source: "..E.BookList.name(cfg.cfg).." ›")
                eq(#cfg.dialog.buttons,10); eq(cfg.metrics.rows,6); eq(cfg.metrics.roundTrips,1)
                press(cfg,"○ "..E.BookList.names[src].." · 7")
                eq(cfg.cfg.src,src); eq(e.model.document,old)
            end
            press(cfg,"Source: On this device ›")
            press(cfg,"○ Custom filter · 7")
            ok(cfg.filter); eq(cfg.dialog,nil)
            local filter=cfg.filter
            filter.model.query.show="unread"; filter:back()
            eq(cfg.cfg.query.show,"unread"); eq(cfg.cfg.title,"Custom filter"); eq(cfg.filter,nil)
            for _,cat in ipairs({{"lists","Your lists","list"},{"series","Series","series"},{"authors","Authors","author"},{"collections","Collections","collection"},{"libraries","Libraries","library"}}) do
                press(cfg,"Source: "..E.BookList.name(cfg.cfg).." ›")
                if cfg.category~=cat[1] then press(cfg,cat[2]) end; eq(cfg.category,cat[1])
                press(cfg,"›"); eq(cfg.offset,6); eq(reads[#reads].offset,6); eq(reads[#reads].limit,6)
                press(cfg,"›"); eq(cfg.offset,12); eq(#cfg.dialog.buttons,5)
                press(cfg,"‹"); eq(cfg.offset,6)
                press(cfg,"○ "..cat[3].." 7 · 7"); eq(cfg.cfg.src,cat[3]..":key-7")
                eq(E.HomeHostPlan.need({widget="booklist",settings=cfg.cfg}).source.kind,cat[3])
            end
            press(cfg,"Caption: Progress"); eq(cfg.cfg.cap,3)
            press(cfg,"Done"); eq(cfg.alive,false)
            eq(e.model:page().placements[2].settings.src,"library:key-7")
            eq(E.S.home_layout.pages[1].placements[2].settings.src,"reading","unpublished until editor Done")
        end)
    end)
    test("Book list Pick back up: source order, hero exclusion and See all retain the owned context",function()
        withHost(function(_,reads)
            local cfg=E.BookList.choose(E.BookList.preset('also'),{src='pickup',title='Pick back up',default_sort=0})
            local p={widget='booklist',settings=cfg,w=4,h=2}
            local need=E.HomeHostPlan.need(p);eq(need.source,'pick-back-up');eq(need.exclude_current,true);eq(need.query.sort,nil)
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            h:dispatch('all',nil,p)
            eq(h.filter.model.source,'pick-back-up');eq(h.filter.exclude_current,true)
            eq(reads[#reads].source,'pick-back-up');eq(reads[#reads].exclude_current,true)
            h:onClose()
        end)
    end)
    test("Book list Reading now keeps list, filter counts and saved context consistent",function()
        withHost(function(batches,reads)
            E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local p=E.Layout.default().pages[1].placements[2]
            h:dispatch("all",nil,p)
            eq(h.list_layout.pages[1].placements[1].settings.exclude_current,true)
            eq(h.filter.exclude_current,true)
            h.filter:show()
            eq(reads[#reads].op,"counts"); eq(reads[#reads].exclude_current,true)
            local out,page=E.HomeHostPlan.saveFilter(E.S.home_layout,{base_source="reading",query={},exclude_current=true})
            for _,pg in ipairs(out.pages) do if pg.id==page then
                eq(pg.placements[#pg.placements].settings.exclude_current,true)
            end end
            h.filter:close(false)
        end)
    end)
    test("Book list Classic: More, title suggestions, focused source, Back and Cancel",function()
        withHost(function()
            sources(); E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local e=E.HomeEditor.show(h); e.model.selected="also"
            local original=e.model.document
            local cfg=e:onMore(); eq(cfg.classic,true); eq(cfg.dialog.focus[2],1)
            press(cfg,"Title: Also reading"); eq(cfg.cfg.title,"Reading now")
            press(cfg,"Source: Reading now ›"); eq(cfg.dialog.focus[2],7,"current source receives focus after category rows")
            cfg.dialog:onClose(); eq(cfg.sources,nil); ok(cfg.alive)
            press(cfg,"Cancel"); eq(cfg.alive,false); eq(e.model.document,original)
            cfg=e:onMore(); cfg.dialog:onClose(); eq(cfg.alive,false); eq(e.model.document,original)
        end)
    end)
    test("Book list filter save inside editor keeps selection and commits on editor Done",function()
        withHost(function()
            sources(); E.S.home_layout=E.Layout.default()
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local e=E.HomeEditor.show(h); e.model.selected="also"
            local cfg=e:configure(); cfg:choose({src="custom",title="Custom filter"})
            local filter=cfg.filter
            filter.model.query.show="unread"
            local original=e.model.document
            local originalIndex=e.model.index
            local save
            for _,line in ipairs(filter.dialog.buttons) do for _,b in ipairs(line) do if b.text=="+ Save as a Book list on Home" then save=b.callback end end end
            ok(save); save()
            eq(e.model.index,originalIndex); eq(e.model.selected,"also")
            eq(#e.model.document.pages,#original.pages+1); eq(e.model.document.pages[2],original.pages[2]); eq(#e.model.document.pages[3].placements,1); ok(cfg.notice:find("Custom filter",1,true))
            eq(E.S.home_layout,original); eq(cfg.cfg.query.show,"unread")
            press(cfg,"Done"); eq(cfg.alive,false); ok(e:done())
            eq(#E.S.home_layout.pages[3].placements,1)
            eq(E.S.home_layout.pages[1].placements[2].settings.src,"custom")
        end)
    end)
    test("Book list save: Go to Home resolves the destination past hidden future pages",function()
        withHost(function()
            local d=E.Layout.default()
            d.pages={
                {id="hidden",tab="Home",name="Future",placements={{instance="future",widget="future",version=1,x=0,y=0,w=4,h=8,settings={}}}},
                {id="target",tab="Home",name="My shelves",placements=setmetatable({},{__jsontype="array"})},
                d.pages[1],
            }
            E.S.home_layout=d
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:showList("Saved filter","library/all")
            ok(h:saveFilter({base_source="library/all",query={show="unread"}}))
            local toast=W.shown[#W.shown]
            ok(toast.title:find("My shelves",1,true))
            toast.buttons[1][1].callback()
            eq(h.list_layout,nil); eq(h.index,1)
            local resolved=E.HomeHostPlan.resolve(E.S.home_layout,E.HomeHost.installed(),h.caps)
            eq(resolved.pages[h.index].id,"target")
        end)
    end)
    test("Book list save: first fitting space, full-page naming, errors and captions",function()
        withHost(function()
            local d=E.Layout.default()
            d.pages={{id="one",tab="Home",name="First",placements={{instance="fill",widget="future",version=1,x=0,y=0,w=4,h=6,settings={}}}},
                {id="two",tab="Home",name="Second",placements=setmetatable({},{__jsontype="array"})}}
            local saved={base_source="library/all",query={show="unread"}}
            local out,page=E.HomeHostPlan.saveFilter(d,saved,"Custom filter")
            eq(page,"one"); eq(out.pages[1].placements[2].y,6); eq(#d.pages[1].placements,1)
            local p=out.pages[1].placements[2]; ok(E.BookList.valid(p.settings)); eq(p.widget,"booklist")
            eq(p.settings.query.show,"unread"); saved.query.show="finished"; eq(p.settings.query.show,"unread")
            E.S.home_layout=d
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:showList("Short books","library/all")
            local success=h:saveFilter(saved); ok(success,W.shown[#W.shown].text); ok(W.shown[#W.shown].title:find("First",1,true),W.shown[#W.shown].title)
            eq(E.HomeWidgets.caption({cap=0},{authors={"A"}}),"")
            eq(E.HomeWidgets.caption({cap=1},{added="2026-11-26T12:00:00"}),"2026-11-26")
            eq(E.HomeWidgets.caption({cap=2},{progress=42}),"42%")
            eq(E.HomeWidgets.caption({cap=3},{authors={"A"}}),"A")
        end)
    end)
end
