-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,withHost)
    local function click(node,text)
        if node.text==text and node.callback then node.callback(); return true end
        for _,child in ipairs(node) do if type(child)=='table' and click(child,text) then return true end end
        return false
    end
    local function data()
        return {caption='1.2 GB free of 32 GB',widget_label='Low space · 1.2 GB free',on_device=2,
            warning='Low space: 1.2 GB free. Downloads still work.',parts={{label='Books',display='100 MB',fraction=.1,pattern='solid'},
            {label='Free',display='1.2 GB',fraction=.9,pattern='white'}},
            actions={{id='finished',label='Remove finished books from device',detail='Frees 10 MB · 1 book',token='preview'}},
            folders={{id='Books',label='/Books'},{id='BookSync',label='/BookSync'}},folder='Books',freshness={saved=true}}
    end
    test('library roots: saved counts, capabilities and named source selection stay behind Library',function()
        withHost(function(_,reads)
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local a=E.Cache.decode(raw)
                if a.op=='library.summary' then eq(a.projection,2);return {total=7,in_progress=2,browse={libraries=1,authors=3,series=2,collections=1,lists=1},coverage='Saved catalog indexes',freshness={saved=true}},300 end
                if a.op=='sources' then
                    reads[#reads+1]=a;eq(a.projection,6)
                    return {items={{src=a.category=='libraries' and 'library:opaque:7' or 'list:opaque:9',title='Named source',count=2}},total=1,freshness={saved=true}},180
                end
                return read(raw)
            end
            local h=E.HomeHost.create();E.HomeHost.active=h;W.shown={h}
            h:dispatch('browse');local page=E.StorageUI.active
            eq(page.metrics.rows,1);eq(page.metrics.roundTrips,1)
            ok(click(page,'Libraries · 1 ›'));eq(E.StorageUI.active.mode,'libraries')
            page=E.StorageUI.active;eq(reads[#reads].category,'libraries');eq(reads[#reads].limit,6)
            ok(click(page,'Named source · 2 ›'))
            eq(h.filter.model.source.kind,'library');eq(h.filter.model.source.key,'opaque:7')
            h:onClose();h:dispatch('browse');page=E.StorageUI.active
            ok(click(page,'Your lists · 1 ›'));page=E.StorageUI.active
            ok(click(page,'Named source · 2 ›'));eq(h.filter.model.source.kind,'list');eq(h.filter.model.source.key,'opaque:9')
        end)
    end)
    test('library roots: incomplete counts remain unknown and unsupported roots are hidden',function()
        withHost(function()
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                if E.Cache.decode(raw).op=='library.summary' then return {total=7,browse={complete=false},coverage='Catalog indexes updating',freshness={saved=true}},180 end
                return read(raw)
            end
            local page=E.StorageUI.show('browse',function() end,nil,{libraries=false,collections=false,lists={read=false}})
            local labels={};for _,control in ipairs(page.controls) do labels[control.text]=true;ok(control.overlap_offset[2]+control.height<=page.dimen.h) end
            ok(labels['Authors · — ›']);ok(labels['Series · — ›']);eq(labels['Collections · — ›'],nil);eq(labels['Libraries · — ›'],nil);eq(labels['Your lists · — ›'],nil)
            page:onClose()
        end)
    end)
    test('storage: one-row Library caption stays within a portrait tablet tile',function()
        withHost(function()
            local text=E.HomeWidgets.text
            local captions={}
            E.HomeWidgets.text=function(...)
                local node=text(...)
                node.getSize=function(self) return {w=200,h=30+2*(self.padding or 4)} end
                captions[#captions+1]=node
                return node
            end
            for _,factor in ipairs({1,2}) do
                E.Device.screen.scaleBySize=function(_,n) return n*factor end
                for _,columns in ipairs({1,2,4}) do
                    local tile=E.StorageUI.widget({w=columns,h=1},{data={total=59,freshness={saved=true},storage=data()}},function() end,{w=288*columns,h=136})
                    local caption=captions[#captions]
                    eq(caption.overlap_offset[2]+caption:getSize().h,134)
                    local canvas=tile[1]
                    eq(#canvas,columns==1 and 3 or 4,'compact tile keeps its patterned bar')
                    local actions=0
                    for _,node in ipairs(canvas) do if node.callback then actions=actions+1;ok(node.height>=50) end end
                    eq(actions,columns==1 and 1 or 2)
                end
            end
            E.HomeWidgets.text=text
        end)
    end)
    test('storage: patterned bar paints the bounded immutable Home snapshot',function()
        withHost(function()
            local empty=E.HomeWidgets.canvas(100,10)
            E.StorageUI.bar(empty,{},0,0,100,10); eq(#empty,0,"unknown capacity has no bar")
            local canvas=E.HomeWidgets.canvas(100,10)
            local parts=E.HomeHostPlan.immutable({{pattern='solid',fraction=.5},{pattern='hatch',fraction=.2},
                {pattern='dots',fraction=.1},{pattern='white',fraction=.2}})
            E.StorageUI.bar(canvas,parts,0,0,100,10)
            local rects={}
            local border
            canvas[1]:paintTo({paintRect=function(_,x,y,w,h,color) rects[#rects+1]={x=x,y=y,w=w,h=h,color=color} end,
                paintBorder=function(_,x,y,w,h,line,color,radius) border={w=w,h=h,line=line,radius=radius} end},0,0)
            eq(border.w,100);eq(border.h,10);eq(border.radius,4);eq(border.line,1)
            eq(rects[2].w,50); eq(rects[2].h,10); eq(rects[2].color,0)
            ok(#rects>8,'hatch and dots must be drawn from proxy rows')
            for _,r in ipairs(rects) do ok(r.x>=0 and r.y>=0 and r.x+r.w<=100 and r.y+r.h<=10) end
        end)
    end)
    test('storage: Home adds one bounded local row to the existing batch and has no paint IO',function()
        withHost(function(batches)
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw) if E.Cache.decode(raw).op=='storage.summary' then return data(),700 end; return read(raw) end
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local n=0; for _,raw in ipairs(batches[1]) do local a=E.Cache.decode(raw); if a.op=='storage.summary' then n=n+1; eq(a.limit,1) end end
            eq(n,1); eq(h.metrics.roundTrips,1); eq(h.metrics.spawns,0); eq(h.metrics.network,0)
            local page=E.StorageUI.show(); eq(page.name,'booksync_storage'); eq(page.metrics.rows,1)
            eq(page.metrics.roundTrips,1)
            local removed=0
            E.LibraryAdapter.command=function(op,args,done) eq(op,'storage.free'); eq(args.token,'preview'); removed=removed+1; local d=data(); d.actions={}; done(d) end
            ok(click(page,'Remove finished books from device\nFrees 10 MB · 1 book'))
            local dialog=W.shown[#W.shown]; eq(dialog.focus[2],1); eq(removed,0)
            eq(dialog.buttons[1][1].text,'Cancel'); ok(dialog.title:find('progress, highlights and notes are kept',1,true))
            dialog.buttons[1][1].callback(); eq(removed,0)
            ok(click(page,'Remove finished books from device\nFrees 10 MB · 1 book'))
            dialog=W.shown[#W.shown]; dialog.buttons[1][2].callback(); eq(removed,1); eq(#page.data.actions,0)
            for _,control in ipairs(page.controls) do ok(control.width>=E.CatalogUI.kit().px(52) and control.height>=E.CatalogUI.kit().px(52)); ok(control.overlap_offset[2]+control.height<=page.dimen.h) end
            page:onClose(); eq(E.StorageUI.active,nil)
        end)
    end)
    test('storage: known device figures paint even before the catalog is saved',function()
        withHost(function()
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local op=E.Cache.decode(raw).op
                if op=='library.summary' then return {items={},total=0,freshness={saved=false}},100 end
                if op=='storage.summary' then return data(),700 end
                return read(raw)
            end
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            local function hasText(node,label)
                if node.text==label then return true end
                for _,child in ipairs(node) do if type(child)=='table' and hasText(child,label) then return true end end
                return false
            end
            ok(hasText(h,'Low space · 1.2 GB free'),'known local capacity must not depend on a saved remote catalog')
            eq(h.metrics.roundTrips,1)
        end)
    end)
    test('storage: pending, unavailable, empty, low and cached offline states remain bounded',function()
        withHost(function()
            for _,state in ipairs({{pending=true},{error='unavailable'},{caption='Space unavailable',parts={},actions={}},data()}) do
                E.LibraryAdapter.read=function() return state,400 end
                local page=E.StorageUI.create(); E.StorageUI.active=page; W.shown={page}
                eq(page.metrics.rows,1); ok(page.metrics.bytes<=16384)
                for _,control in ipairs(page.controls) do ok(control.height>=E.CatalogUI.kit().px(52)) end
                page:onClose()
            end
            E.Companion.workerProblem=function() return 'Update BookSync Companion' end
            eq(E.StorageUI.show(),false)
        end)
    end)
    test('storage: folder selection dispatches once; late results cannot redraw a closed page',function()
        withHost(function()
            E.LibraryAdapter.read=function() return data(),700 end
            local callback,op,args
            E.LibraryAdapter.command=function(o,a,done) op,args,callback=o,a,done end
            local returned=0
            local page=E.StorageUI.show('folder',nil,function() returned=returned+1 end)
            page:onNext(); eq(page.focus,2); page:onPrevious(); eq(page.focus,1)
            ok(click(page,'/BookSync')); eq(op,'storage.folder'); eq(args.folder,'BookSync'); eq(page.busy,true)
            page:onClose(); eq(returned,1); local before=page[1]
            callback({folder='BookSync',freshness={saved=true}}); eq(page[1],before); eq(E.StorageUI.active,nil)
        end)
    end)
    test('storage: Settings rows inherit owned targets and Back preserves the initiating focus',function()
        withHost(function()
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw) if E.Cache.decode(raw).op=='storage.summary' then return data(),700 end; return read(raw) end
            local m=setmetatable({},{__index=E.OrbitAndroid})
            local group
            for _,row in ipairs(m:settingsPresentation(m:menuItems())) do if row.settings_group=='library' then group=row end end
            ok(group.callback); eq(group.sub_item_table_func,nil)
            group.callback()
            local view=E.SettingsView.active
            eq(view.screen,'settings-library'); eq(#view.make(),6)
            local rows=view.dialog.buttons
            ok(rows[1][1].text:find('Storage',1,true)); ok(rows[2][1].text:find('Download folder',1,true))
            for _,line in ipairs(rows) do for _,button in ipairs(line) do ok(button.height>=50) end end
            local manager=E.require("ui/uimanager")
            local schedule=manager.scheduleIn
            local pending
            manager.scheduleIn=function(_,_,fn) pending=fn end
            local success,err=pcall(rows[2][1].callback)
            manager.scheduleIn=schedule
            ok(success,err); ok(pending); pending()
            local page=E.StorageUI.active; ok(page); eq(page.mode,'folder')
            page:onClose(); eq(E.SettingsView.active,view); eq(view.focus,2)
            eq(W.shown[#W.shown],view.dialog)
            view.onBack=nil; view:close()
        end)
    end)
    test('storage: Catalog cache limit reaches every shared choice with a Back target',function()
        withHost(function()
            E.LibraryAdapter.read=function() return data(),700 end
            local page=E.StorageUI.show()
            ok(click(page,'Catalog cache limit\nCovers and details for browsing offline'))
            local dialog=W.shown[#W.shown]
            eq(dialog.title,'Catalog cache limit')
            eq(#dialog.buttons,#E.Cache.STORAGE_LIMITS_MB+1)
            for _,line in ipairs(dialog.buttons) do ok(line[1].height>=50); ok(line[1].callback) end
            dialog.buttons[#dialog.buttons][1].callback()
            eq(W.shown[#W.shown],page)
            page:onClose()
        end)
    end)
    test('storage: busy actions cannot open a second confirmation and hidden completion waits for visibility',function()
        withHost(function()
            local reads=0
            E.LibraryAdapter.read=function() reads=reads+1; return data(),700 end
            local done,calls
            E.LibraryAdapter.command=function(_,_,callback) calls=(calls or 0)+1; done=callback end
            local page=E.StorageUI.show()
            page:run('storage.free',{action='finished',token='preview'})
            eq(calls,1); eq(page.busy,true)
            local shown=#W.shown
            ok(click(page,'Remove finished books from device\nFrees 10 MB · 1 book'))
            ok(click(page,'Catalog cache limit\nCovers and details for browsing offline'))
            eq(#W.shown,shown); eq(calls,1)
            eq(page.controls[1].enabled,false); eq(page.controls[#page.controls].enabled,true)
            page:onNext(); eq(page.controls[page.focus].text,'Back')
            local popup={}; W.shown[#W.shown+1]=popup
            local old=page[1]; local result=data(); result.actions={}
            done(result); eq(page[1],old); eq(page.busy,false); ok(page.pending_result)
            table.remove(W.shown)
            page:paintTo({paintRect=function() end,paintBorder=function() end,paintRoundedRect=function() end},0,0)
            eq(page.pending_result,nil); eq(#page.data.actions,0); eq(reads,1,"deferred paint never reads again")
            page:onClose()
        end)
    end)
    test('collections: loading, error, unsaved and complete-empty remain distinct',function()
        withHost(function()
            for _,case in ipairs({{{pending=true},'Loading…'},{{error='offline'},"Couldn't load collections · Retry"},
                {{items={},freshness={saved=false}},'Not saved yet'},{{items={},freshness={saved=true}},'No collections'}}) do
                E.LibraryAdapter.read=function() return case[1],200 end
                local page=E.StorageUI.show('collections')
                eq(page.controls[1].text,case[2]); eq(page.metrics.roundTrips,1)
                page:onClose()
            end
        end)
    end)
    test('collections: bounded pages open opaque source and Back restores Home',function()
        withHost(function()
            local read=E.LibraryAdapter.read
            E.LibraryAdapter.read=function(raw)
                local a=E.Cache.decode(raw)
                if a.op=='collections' then eq(a.limit,6); return {items={{key='opaque',title='Saved collection',count=3}},next=a.offset==0 and 6 or nil,freshness={saved=true}},400 end
                return read(raw)
            end
            local h=E.HomeHost.create(); E.HomeHost.active=h; W.shown={h}
            h:dispatch('collections',nil,{})
            local page=W.shown[#W.shown]; eq(page.metrics.rows,1)
            ok(click(page,'Next')); eq(page.offset,6); ok(click(page,'Previous')); eq(page.offset,0)
            ok(click(page,'Saved collection · 3 ›')); eq(h.filter.model.source.kind,'collection'); eq(h.filter.model.source.key,'opaque')
            h:onClose(); eq(h.list_layout,nil)
        end)
    end)
end
