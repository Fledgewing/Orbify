-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,E,W,Widget,withHost)
    local function click(editor,text,nth)
        local match=0;local seen={}
        local function visit(node)
            if type(node)~="table" or seen[node] then return false end;seen[node]=true
            if node.text==text and node.callback then match=match+1;if match==(nth or 1) then node.callback();return true end end
            for _,child in ipairs(node) do if visit(child) then return true end end
            return node.buttons and visit(node.buttons) or false
        end
        if visit(editor) then return end
        if text=="Move ‹" or text=="Move ›" or text=="Delete page" then click(editor,"Pages");if visit(W.shown[#W.shown]) then return end end
        error("missing control: "..text)
    end
    local function editor()
        E.S.home_layout=E.Layout.default()
        local host=E.HomeHost.create()
        E.HomeHost.active=host; W.shown={host}
        E.HomeEditor.show(host)
        return W.shown[#W.shown],host
    end
    test("Home editor: a changed query never borrows an unrelated cached preview",function()
        withHost(function(_,reads)
            local e,host=editor();local p=E.Layout.editorPage(e.model.document,1).placements[2]
            p.settings.query={q="a different saved filter"}
            local render=E.HomeWidgets.renderers.booklist;local captured;local before=#reads
            E.HomeWidgets.renderers.booklist=function(_,snapshot) captured=snapshot;return Widget:new{} end
            local success,err=pcall(function()
                E.HomeEditor.preview(host,p,{w=300,h=200},1)
                eq(captured.state,"empty");eq(#reads,before,"preview remains query-free")
            end)
            E.HomeWidgets.renderers.booklist=render;ok(success,err)
        end)
    end)
    test("Home editor: Settings shortcuts reuse rename and reset confirmation",function()
        withHost(function()
            E.S.home_layout=E.Layout.default()
            table.insert(E.S.home_layout.pages,2,{id="settings-page",tab="Home",name="More",placements={{instance="settings-list",widget="booklist",version=1,x=0,y=0,w=4,h=2,settings={src="reading"}}}})
            local host=E.HomeHost.create(); E.HomeHost.active=host; W.shown={host}
            host.index=2
            local Input=require("ui/widget/inputdialog")
            local keyboard=Input.onShowKeyboard; Input.onShowKeyboard=function() end
            local editor=E.HomeEditor.open("rename")
            Input.onShowKeyboard=keyboard
            eq(editor.model.index,2,"keeps the visible Home page")
            local dialog=W.shown[#W.shown]; eq(dialog.title,"Rename page")
            dialog.buttons[1][1].callback(); eq(W.shown[#W.shown],editor)
            E.HomeEditor.show(host,"reset")
            ok(W.shown[#W.shown].text:find("Reset all Home pages",1,true))
        end)
    end)
    test("Home editor: select, band move, resize and remove use pure operations",function()
        withHost(function(batches,reads)
            local e=editor(); local m=e.model
            -- Equal-height collision band can trade without the third row below it.
            m.document=E.Layout.copy(m.document); m.document.pages[1].placements[3].h=2
            e:rebuild()
            local calls=#reads; local trips=#batches
            click(e,"Also reading · 2×2"); eq(m.selected,"also")
            local configure
            for _,control in ipairs(e[1][1]) do if control.text=="Configure" then configure=control end end
            ok(configure and configure.height>=50 and configure.width>=50,"Configure touch minimum")
            for _,control in ipairs(e[1][1]) do
                if control.callback and control~=configure and control.width then
                    local a,b=control.overlap_offset,configure.overlap_offset
                    ok(not (a[1]<b[1]+configure.width and b[1]<a[1]+control.width and a[2]<b[2]+configure.height and b[2]<a[2]+control.height),
                        "Configure overlaps "..control.text)
                end
            end
            local revision=m.document.revision
            click(e,"→"); eq(m.document.revision,revision+1)
            local p=E.Layout.editorPage(m.document,1)
            eq(p.placements[2].x,2); eq(p.placements[3].x,0)
            click(e,"Size");eq(E.Layout.editorPage(m.document,1).placements[2].h,3,"next fitting span")
            click(e,"Size") -- Skip blocked wide spans and cycle to 2×1.
            eq(E.Layout.editorPage(m.document,1).placements[2].w,2)
            eq(E.Layout.editorPage(m.document,1).placements[2].h,1)
            click(e,"Remove"); eq(#m:page().placements,5); eq(m.selected,nil)
            eq(#reads,calls); eq(#batches,trips)
            eq(e.metrics.bytes,0); eq(e.metrics.spawns,0); eq(e.metrics.network,0); eq(e.metrics.roundTrips,0)
        end)
    end)
    test("Home editor: picker copy, sizes, free slots and full page fallback",function()
        withHost(function()
            local e=editor(); local m=e.model
            e:pick(); eq(e.picker,1)
            local available=E.HomeEditor.available({catalog=false,lists={read=false}})
            for _,id in ipairs(available) do ok(id~="booklist" and id~="continue-reading" and id~="lists") end
            local described=0
            for _,id in ipairs(E.HomeEditor.available({})) do
                local c=E.WidgetRegistry[id]; ok(c.name and c.description); ok(#c.sizes["android-tablet"]>0); described=described+1
            end
            ok(described>=3)
            -- Default Home is full: all allowed spans are tried before a new page is added.
            local n=#m.document.pages
            local hero
            for i,id in ipairs(E.HomeEditor.choices({})) do if id=="continue-reading" then hero=i end end
            local per=5
            e.picker=math.floor((hero-1)/per)+1; e:rebuild()
            click(e,"Add",(hero-1)%per+1) -- Find across picker pages as the installed catalog grows.
            eq(#m.document.pages,n+1); eq(m:page().name,"Reading")
            eq(m.index,n+1); ok(m.selected)
            e.picker=nil; e:rebuild(); e:turn(-1); e:turn(1)
            click(e,"+" ); eq(e.picker,1); ok(e.slotX~=nil and e.slotY~=nil)
            e:onClose(); eq(e.picker,nil)
            ok(E.Layout.validate(m.document))
        end)
    end)
    test("Home editor: pages, keyboard rename, manual name retention, reset",function()
        withHost(function()
            local e=editor(); local m=e.model
            click(e,"+ Page"); eq(m.index,2); eq(m:page().name,"Page 3")
            local id=m:page().id
            local Input=require("ui/widget/inputdialog")
            local keyboard=Input.onShowKeyboard; Input.onShowKeyboard=function() end
            click(e,"Rename")
            Input.onShowKeyboard=keyboard
            local dialog=W.shown[#W.shown]
            -- Generic harness widgets preserve the keyboard API arguments; use a keyboard stand-in.
            eq(dialog.title,"Rename page")
            dialog.getInputText=function() return "  My shelves  " end
            dialog.buttons[1][2].callback(); eq(m:page().name,"My shelves"); eq(m:page().named,true)
            ok(m:add("booklist")); eq(m:page().name,"My shelves")
            click(e,"Move ›"); eq(m.index,3); eq(m:page().id,id)
            click(e,"Move ‹"); eq(m.index,2)
            click(e,"Delete page"); W.shown[#W.shown].ok_callback(); eq(#m.document.pages,2)
            click(e,"Reset"); W.shown[#W.shown].ok_callback(); eq(m.index,1); eq(m:page().name,"Home")
            eq(#m:page().placements,6)
            while #m.document.pages>1 do ok(m:pageAction("remove")) end; local before=m.document
            eq(m:pageAction("remove"),nil); eq(m.document,before)
        end)
    end)
    test("Home editor: move drawing bound ignores all other pages and rejects overruns",function()
        withHost(function(batches,reads)
            local e=editor(); local m=e.model
            -- If a move projects/validates another page, accessing it fails.
            m.document.pages[2]=setmetatable({}, {__index=function() error("unrelated page touched") end})
            m.document.pages[1].placements[2].settings.title=string.rep("x",100000)
            m.selected="also";e:rebuild()
            local calls=#reads
            click(e,"→"); eq(#reads,calls)
            ok(e.metrics.rows<=128); ok(e.metrics.drawNodes<=208)
            for _,control in ipairs(e[1][1]) do if control.text then ok(#control.text<=160,"bounded displayed labels") end end
            local b=E.Budgets.get("screens","editor")
            ok(E.Budgets.check(b,e.metrics)); eq(b.targetMs,100)
            if os.getenv("BOOKSYNC_PERF_REPORT") then
                print(string.format("PERF editor-move rows=%d nodes=%d bytes=%d trips=%d spawns=%d network=%d",e.metrics.rows,e.metrics.drawNodes,e.metrics.bytes,e.metrics.roundTrips,e.metrics.spawns,e.metrics.network))
            end
            for _,field in ipairs({"rows","bytes","spawns","roundTrips","network","snapshotBytes","drawNodes"}) do
                local bad=E.Layout.copy(e.metrics); bad[field]=b[field]+1
                eq(E.Budgets.check(b,bad),nil,field)
            end
            local before=m.document
            m.selected="resume"; click(e,"↑"); eq(m.document,before); ok(e.message:find("edge"))
        end)
    end)
    test("Home editor: failed atomic save retains published layout and recoverable backup",function()
        withHost(function()
            local e,host=editor(); local m=e.model
            local old=E.S.home_layout
            ok(m:pageAction("rename","Edited"))
            local originalSave=E.HomeEditor.save
            E.HomeEditor.save=function() return nil,"layout write failed" end
            eq(e:done(),false); eq(E.S.home_layout,old); eq(e.message,"layout write failed")
            E.HomeEditor.save=originalSave
            -- Exercise Layout.save via the host boundary, with a typed fixture codec and atomic in-memory writes.
            local codec,read,write,path=E.Library.layout.codec,E.Store.readFile,E.Store.writeFile,E.Library.layout.path
            local records,files={},{}; local seq=0; local fail
            E.Library.layout.codec=function() return {encode=function(d) seq=seq+1; records[tostring(seq)]=E.Layout.copy(d); return tostring(seq) end,
                decode=function(raw) return E.Layout.copy(records[raw]) end} end
            E.Library.layout.path=function() return "layout-fixture" end
            E.Store.readFile=function(p) return files[p] end
            E.Store.writeFile=function(p,raw) if p==fail then return false end; files[p]=raw; return true end
            local success,err=pcall(function()
                ok(E.HomeEditor.save(old)); local previous=files["layout-fixture"]
                fail="layout-fixture"; eq(E.HomeEditor.save(m.document),nil)
                eq(files["layout-fixture"],previous); eq(files["layout-fixture.bak"],previous); eq(E.S.home_layout,old)
                fail=nil; ok(e:done()); eq(E.S.home_layout.pages[1].name,"Edited")
                eq(records[files["layout-fixture.bak"]].pages[1].name,"Home")
            end)
            E.Library.layout.codec,E.Store.readFile,E.Store.writeFile,E.Library.layout.path=codec,read,write,path
            ok(success,err)
        end)
    end)
end
