-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Explicit Home action. Editor draws geometry only; no widget queries or catalog work.
HomeEditor = {}
function HomeEditor.load() return Library.layout.load() end
function HomeEditor.save(document) return Library.layout.save(document) end
function HomeEditor.available(caps)
    local out={}
    for id,contract in pairs(HomeHost.installed()) do
        local size=contract.sizes["android-tablet"][1]
        local d=Layout.default()
        d.pages={{id="picker",tab="Home",placements={{instance="picker",widget=id,version=contract.version,
            x=0,y=0,w=size[1],h=size[2],settings={}}}}}
        d.overrides["android-tablet"]={}
        if #HomeHostPlan.resolve(d,{[id]=contract},caps).pages[1].placements>0 then out[#out+1]=id end
    end
    table.sort(out)
    return out
end
-- Preview only the host's bounded immutable snapshots; the editor never queries data.
function HomeEditor.title(p)
    local title=(p.settings or {}).title
    if type(title)~="string" or #title>80 then title=(WidgetRegistry[p.widget] or {}).name or p.widget end
    return title
end
function HomeEditor.previewKey(p)
    local s=p.settings or {}
    return UIUtil.encode({widget=p.widget,source=s.source or s.src,query=s.query or {},sort=s.sort or 0,offset=s.offset or 0,exclude_current=s.exclude_current})
end
function HomeEditor.preview(host,p,rect,scale)
    local key=HomeEditor.previewKey(p)
    local cached=(host.presentation or {})[p.instance]
    if cached and HomeEditor.previewKey(cached.p)~=key then cached=nil end
    if not cached then
        for _,entry in pairs(host.presentation or {}) do
            if HomeEditor.previewKey(entry.p)==key then cached=entry;break end
        end
    end
    local snapshot=cached and cached.snapshot
    if not snapshot and p.widget=="booklist" and (p.settings or {}).src=="device" then
        local items={};local seen={}
        for _,entry in pairs(host.presentation or {}) do
            for i=1,entry.snapshot.count or 0 do
                local row=entry.snapshot.items[i]
                if row.local_path and not seen[row.key] and #items<3 then items[#items+1]=row;seen[row.key]=true end
            end
        end
        if #items>0 then snapshot={state="ready",items=items,count=#items,total=host.library_on_device,bytes=0} end
    end
    snapshot=snapshot or {state="empty",items={},count=0,bytes=0}
    local oldPreview,oldScale=HomeWidgets.preview,HomeWidgets.kitScale
    HomeWidgets.preview,HomeWidgets.kitScale=true,scale
    local render=HomeWidgets.renderers[p.widget] or HomeWidgets.card
    local ok,widget=pcall(render,p,snapshot,function() end,rect)
    HomeWidgets.preview,HomeWidgets.kitScale=oldPreview,oldScale
    if ok then return widget end
    local K=BookSyncUI.new(scale)
    return K.card{w=rect.w,h=rect.h,title=HomeEditor.title(p)}
end
function HomeEditor.choices(caps)
    local available=HomeEditor.available(caps);local installed={};for _,id in ipairs(available) do installed[id]=true end
    local out,used={},{}
    local function add(id)
        if installed[id] or BookList.presets[id] and installed.booklist then
            if id=="wtr" and caps.wantToRead==false or id=="ondevice" and caps.onDevice==false then return end
            out[#out+1]=id;used[id]=true
        end
    end
    for _,id in ipairs({"continue-reading","also","recent","wtr","ondevice","lists","library"}) do add(id) end
    for _,id in ipairs(available) do if not used[id] then add(id) end end
    for _,id in ipairs({"finished","pickup","year","upnext","unopened"}) do
        if not (id=="upnext" and caps.retainedSeriesNext==false or id=="year" and caps.retainedFinishedYears==false) then add(id) end
    end
    return out
end
function HomeEditor.create(host)
    local Input=require("ui/widget/container/inputcontainer")
    local Geom=require("ui/geometry")
    local Editor=Input:extend{name="booksync_home_editor",covers_fullscreen=true}
    function Editor:init()
        self.dimen=Geom:new{w=Device.screen:getWidth(),h=Device.screen:getHeight()}
        local document=HomeHost.document()
        local resolved=HomeHostPlan.resolve(document,HomeHost.installed(),host.caps)
        local id=resolved.pages[host.index].id
        local index=1; for i,p in ipairs(document.pages) do if p.id==id then index=i end end
        self.model=HomeEditorPlan.new(document,index)
        self.key_events={Close={{"Back"}},More={{"Menu"}}}
        self.message=Library.layout.notice
        self:rebuild()
    end
    function Editor:action(fn)
        local done=Budgets.span("editor.operation",now_s,log)
        local ok,err=fn()
        self.message=ok and nil or err
        self:rebuild(); UIManager:setDirty(self,"ui"); done()
        return ok,err
    end
    function Editor:rebuild()
        local done=Budgets.span(self.picker and "editor-picker.draw" or "editor.draw",now_s,log)
        local K=HomeWidgets.kit();local px=K.px;local m=self.model
        local w,h=self.dimen.w,self.dimen.h;local canvas=K.canvas(w,h)
        local pg=Layout.editorPage(m.document,m.index);local grid=m.document.grids["android-tablet"]
        local selected
        for _,p in ipairs(pg.placements) do if p.instance==m.selected then selected=p end end
        local name=selected and HomeEditor.title(selected) or (m:page().name or "Home")
        K.label(canvas,name,px(20),px(18),w-px(170),"body",{bold=true})
        K.label(canvas,selected and "Arrows below move it, past other widgets if needed" or "Tap a widget to edit · + adds one",px(20),px(44),w-px(170),"caption",{muted=true})
        local function button(text,x,y,width,fn,options)
            options=options or {};options.text,options.w,options.callback=options.label or (options.iconOnly and "" or text),width,fn
            options.h=options.h or px(52);options.variant=options.variant or "outline"
            local widget=K.button(options);widget.text=text;return K.put(canvas,widget,x,y)
        end
        if selected then button("Remove",w-px(132),px(12),px(52),function() self:action(function() return m:remove() end) end,{icon="trash",iconOnly=true,size="caption",radius=px(12)})
        else button("Add widget",w-px(160),px(12),px(84),function() self:pick() end,{size="caption"}) end
        button("Done",w-px(70),px(12),px(52),function() self:done() end,{variant="solid",icon="check",iconOnly=true,size="caption",radius=px(12)})
        local top,bottom,inset,gap=px(76),px(58),px(18),px(12)
        local occupied={};local count=0
        for _,p in ipairs(pg.placements) do
            if not p.hidden then
                count=count+1
                for y=p.y,p.y+p.h-1 do for x=p.x,p.x+p.w-1 do occupied[y*grid.cols+x]=true end end
                local rect=HomeHostPlan.rect(p,grid,w-2*inset,h-top-bottom,gap)
                local preview=HomeEditor.preview(host,p,rect,K.scale)
                if m.selected and m.selected~=p.instance then
                    local dim=K.frame(preview,{w=rect.w,h=rect.h});dim.dim=true;preview=dim
                end
                K.put(canvas,preview,rect.x+inset,rect.y+top)
                local instance=p.instance;local title=HomeEditor.title(p)
                -- An input-only overlay selects, so preview actions cannot open books.
                local cover=K.canvas(rect.w,rect.h)
                local Outline=require("ui/widget/widget"):extend{}
                local border=Outline:new{dimen=require("ui/geometry"):new{w=rect.w,h=rect.h}}
                function border:paintTo(bb,x,y)
                    local b,r=px(2),px(16)
                    bb:paintBorder(x,y,rect.w,rect.h,b,K.black,r)
                    if m.selected~=instance then
                        for dx=r,rect.w-r-px(6),px(12) do
                            bb:paintRect(x+dx,y,px(6),b,K.white);bb:paintRect(x+dx,y+rect.h-b,px(6),b,K.white)
                        end
                        for dy=r,rect.h-r-px(6),px(12) do
                            bb:paintRect(x,y+dy,b,px(6),K.white);bb:paintRect(x+rect.w-b,y+dy,b,px(6),K.white)
                        end
                    end
                end
                K.put(cover,border,0,0)
                K.put(canvas,K.hit(cover,{w=rect.w,h=rect.h,text=title.." · "..p.w.."×"..p.h,
                    callback=function() m.selected=instance;self:action(function() return true end) end}),rect.x+inset,rect.y+top)
                local tagW=math.min(rect.w-px(20),px(190));local tag=K.canvas(tagW,px(20))
                local icon=p.widget=="continue-reading" and "books" or p.widget=="lists" and "filter" or p.widget=="library" and "books" or "stack"
                K.put(tag,K.icon{name=icon,w=px(14)},px(7),px(3))
                local text=title.." · "..p.w.."×"..p.h;K.label(tag,text,px(26),0,tagW-px(32),"caption",{bold=true})
                local label=K.frame(tag,{w=tagW,h=px(20),radius=px(10),border=px(1)});label.text=text
                K.put(canvas,label,rect.x+inset+rect.w-tagW-px(12),rect.y+top+rect.h-px(10))
            end
        end
        for y=0,grid.rows-1 do for x=0,grid.cols-1 do if not occupied[y*grid.cols+x] then
            local sx,sy=x,y;local r=HomeHostPlan.rect({x=x,y=y,w=1,h=1},grid,w-2*inset,h-top-bottom,gap)
            local cell=K.canvas(r.w,r.h);K.put(cell,K.icon{name="plus",w=px(22)},(r.w-px(22))/2,(r.h-px(22))/2)
            local slot=K.frame(cell,{w=r.w,h=r.h,radius=px(16),border=px(1),color=K.rule})
            local basePaint=slot.paintTo
            function slot:paintTo(bb,x,y)
                basePaint(self,bb,x,y)
                for dx=px(16),r.w-px(16),px(2) do bb:paintRect(x+dx,y,px(1),px(1),K.white);bb:paintRect(x+dx,y+r.h-px(1),px(1),px(1),K.white) end
                for dy=px(16),r.h-px(16),px(2) do bb:paintRect(x,y+dy,px(1),px(1),K.white);bb:paintRect(x+r.w-px(1),y+dy,px(1),px(1),K.white) end
            end
            K.put(canvas,K.hit(slot,{text="+",w=r.w,h=r.h,callback=function() self:pick(sx,sy) end}),r.x+inset,r.y+top)
        end end end
        local footer=h-px(52)
        if selected then
            for i,move in ipairs({{"←",-1,0},{"↑",0,-1},{"↓",0,1},{"→",1,0}}) do
                local dx,dy=move[2],move[3]
                button(move[1],px((selected.widget=="booklist" and 20 or 136)+(i-1)*62),footer,px(52),function() self:action(function() return m:move(dx,dy) end) end)
            end
            button("Size",px(selected.widget=="booklist" and 284 or 405),footer,px(160),function() self:sizes() end,{label="Size "..selected.w.."×"..selected.h,trailingIcon="resize",size="small"})
            if selected.widget=="booklist" then button("Configure",w-px(128),footer,px(116),function() self:configure() end,{size="small"}) end
        else
            button("‹",px(20),footer,px(52),function() self:turn(-1) end)
            button("Rename",px(84),footer,px(92),function() self:rename() end,{size="small"})
            button("+ Page",px(188),footer,px(98),function() self:action(function() return m:pageAction("add") end) end,{size="small"})
            button("›",px(298),footer,px(52),function() self:turn(1) end)
            button("Pages",w-px(230),footer,px(100),function() self:pageMenu() end,{size="small"})
            button("Reset",w-px(118),footer,px(98),function() self:reset() end,{size="small"})
        end
        if self.message then K.label(canvas,self.message,px(20),h-px(82),w-px(40),"caption") end
        local pickerNodes=0
        if self.picker then
            local ids=HomeEditor.choices(host.caps or {});local per=5
            local pages=math.max(1,math.ceil(#ids/per));self.picker=math.min(self.picker,pages)
            local sx,sy=px(12),px(122);local sw,sh=w-px(24),h-px(132)
            local sheet=K.card{w=sw,h=sh};sheet.radius=px(20);sheet.bordersize=px(2);sheet.padding=-px(2);sheet.color=K.black
            local c=sheet.content;local pad=px(22)
            K.label(c,"Add a widget",pad,px(18),sw-px(100),"medium",{bold=true})
            K.label(c,"Goes in the first space it fits on page "..m.index,pad,px(48),sw-px(70),"caption",{muted=true})
            local close=K.canvas(px(52),px(52));K.put(close,K.icon{name="x",w=px(24)},px(14),px(14))
            K.put(c,K.hit(close,{text="Close",w=px(52),h=px(52),callback=function() self.picker=nil;self:action(function() return true end) end}),sw-px(66),px(14))
            K.label(c,"IN THIS RELEASE",pad,px(96),sw-2*pad,"caption",{bold=true,muted=true})
            local rowH=math.floor((sh-px(210))/per);count=0
            for i=(self.picker-1)*per+1,math.min(#ids,self.picker*per) do
                local id=ids[i];local preset=BookList.presets[id]
                local contract=preset and {name=preset.title,description="Book list preset",sizes=WidgetRegistry.booklist.sizes} or WidgetRegistry[id]
                local y=px(147)+(i-1)%per*rowH;count=count+1
                local title=contract.name;local settings=preset and Layout.copy(preset) or {}
                settings.src=preset and preset.src or nil;settings.title=title
                if id=="also" then settings.src="reading";settings.style=1 end
                local miniature={instance="picker-"..id,widget=preset and "booklist" or id,w=2,h=2,settings=settings}
                local previewW=px(150);local previewH=math.min(rowH-px(18),px(88))
                K.put(c,HomeEditor.preview(host,miniature,{w=previewW,h=previewH},K.scale*.45),pad,y)
                local tx=pad+previewW+px(14);local tw=sw-tx-px(112)
                local heading=K.label(c,title,tx,y-px(5),tw-px(64),"body",{bold=true})
                local badge=K.canvas(px(54),px(16));local tag=K.text{text="In 0.12",w=px(46),size=10,bold=true,ink=true};K.put(badge,tag,(px(54)-tag:getSize().w)/2,(px(16)-tag:getSize().h)/2)
                K.put(c,K.frame(badge,{w=px(54),h=px(16),radius=px(8),ink=true}),tx+heading:getSize().w+px(8),y-px(3))
                local descriptions={
                    ["continue-reading"]="Your current book, big: cover, progress, time left and when you'll finish.",
                    also="Book list preset: Reading now, rows with progress, without the book in Continue reading.",
                    recent="Book list preset: the newest books on your server, as a cover shelf captioned with the date added.",
                    wtr="Book list preset: books you marked to read next, as a cover shelf.",
                    ondevice="Book list preset: the books on this reader, last read first."}
                local face=K.text{text="",w=tw,size="caption"}.face
                K.put(c,require("ui/widget/textboxwidget"):new{text=descriptions[id] or contract.description or "Book list preset",width=tw,height=px(40),face=face,fgcolor=K.gray},tx,y+px(20))
                local sizes={};for _,size in ipairs(contract.sizes["android-tablet"]) do sizes[#sizes+1]=size[1].."×"..size[2] end
                K.label(c,"Sizes "..table.concat(sizes," · "),tx,y+px(51),tw,"caption",{bold=true})
                local add=K.canvas(px(76),px(52))
                K.put(add,K.icon{name="plus",w=px(18)},px(12),px(17))
                K.label(add,"Add",px(35),px(16),px(34),"small",{bold=true})
                K.put(c,K.hit(K.frame(add,{w=px(76),h=px(52),radius=px(12),border=px(1.5)}),{text="Add",w=px(76),h=px(52),callback=function()
                    self:action(function() local ok,err=m:add(preset and "booklist" or id,self.slotX,self.slotY,preset);if ok then self.picker=nil end;if ok and id=="booklist" then self:configure() end;return ok,err end)
                end}),sw-pad-px(76),y+px(12))
                K.put(c,K.frame(K.canvas(sw-2*pad,px(1)),{w=sw-2*pad,h=px(1),background=K.light}),pad,y+rowH-px(8))
            end
            K.put(c,K.button{text="‹",w=px(52),variant="outline",callback=function() self.picker=math.max(1,self.picker-1);self:action(function() return true end) end},pad,sh-px(64))
            K.label(c,"Page "..self.picker.." of "..pages,sw/2-px(50),sh-px(44),px(120),"caption",{bold=true})
            K.put(c,K.button{text="›",w=px(52),variant="outline",callback=function() self.picker=math.min(pages,self.picker+1);self:action(function() return true end) end},sw-pad-px(52),sh-px(64))
            local Scrim=require("ui/widget/widget"):extend{}
            local scrim=Scrim:new{dimen=require("ui/geometry"):new{w=w,h=h}}
            function scrim:paintTo(bb,x,y) bb:lightenRect(x,y,w,h) end
            local blocker=K.hit(scrim,{w=w,h=h,callback=function() self.picker=nil;self:action(function() return true end) end})
            function blocker:onKitTap(_,ges)
                if ges and ges.pos and ges.pos.x>=sx and ges.pos.x<=sx+sw and ges.pos.y>=sy and ges.pos.y<=sy+sh then return true end
                self.callback();return true
            end
            K.put(canvas,blocker,0,0)
            pickerNodes=#c
            K.put(canvas,sheet,sx,sy)
        end
        self.metrics={drawNodes=#canvas+pickerNodes,rows=count,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}
        assert(Budgets.check(Budgets.get("screens",self.picker and "editor-picker" or "editor"),self.metrics))
        local old=self[1];self[1]=K.frame(canvas,{w=w,h=h});if old then old:free() end
        done()
    end
    function Editor:pageMenu()
        local dialog
        dialog=require("ui/widget/buttondialog"):new{title="Home pages",buttons={
            {{text="Move ‹",callback=function() UIManager:close(dialog);self:reorder(-1) end},{text="Move ›",callback=function() UIManager:close(dialog);self:reorder(1) end}},
            {{text="Delete page",callback=function() UIManager:close(dialog);self:confirm("Delete this page and its widgets?",function() return self.model:pageAction("remove") end) end}},
            {{text="Close",callback=function() UIManager:close(dialog) end}}}}
        UIManager:show(dialog) -- gate: user action (editor page actions)
    end
    function Editor:paintTo(bb,x,y)
        local done=Budgets.span("editor.paint",now_s,log)
        Input.paintTo(self,bb,x,y); done()
    end
    function Editor:turn(delta)
        self.model.index=HomeHostPlan.page(self.model.index,delta,#self.model.document.pages)
        self.model.selected=nil; self:action(function() return true end)
    end
    function Editor:reorder(delta)
        self:action(function() return self.model:pageAction("reorder",self.model.index+delta) end)
    end
    function Editor:pick(x,y)
        self.picker=1; self.slotX,self.slotY=x,y; self:action(function() return true end)
    end
    function Editor:rename()
        local dialog
        dialog=require("ui/widget/inputdialog"):new{title=_("Rename page"),input=self.model:page().name or "",
            buttons={{{text=_("Cancel"),id="close",callback=function() UIManager:close(dialog) end},
                {text=_("Save"),is_enter_default=true,callback=function()
                    local value=dialog:getInputText():match("^%s*(.-)%s*$")
                    self:action(function() return self.model:pageAction("rename",value) end)
                    UIManager:close(dialog)
                end}}}}
        UIManager:show(dialog) -- gate: user action (editor rename)
        dialog:onShowKeyboard()
    end
    function Editor:configure(classic)
        local m=self.model
        for _i,p in ipairs(Layout.editorPage(m.document,m.index).placements) do
            if p.instance==m.selected and p.widget=="booklist" then
                self.config=BookListConfig.new{cfg=p.settings,caps=host.caps,origin=self,classic=classic or (Device.isTouchDevice and not Device:isTouchDevice()),
                    onDone=function(cfg) return self:action(function() return m:configure(cfg) end) end,
                    onSave=function(saved)
                        local d,page=HomeHostPlan.saveFilter(m.document,saved,"Custom filter")
                        if not d then
                            Gate.show("save Book list",function()
                                UIManager:show(InfoMessage:new{text=_("No room on Home")}) -- gate: Gate.show, explicit save
                            end)
                            return false
                        end
                        m.document=d
                        local name
                        for i,pg in ipairs(d.pages) do if pg.id==page then name=pg.name or pg.tab end end
                        self.config.notice="Book list added to "..(name or "Home").." · Done saves your Home"
                        self:action(function() return true end)
                        return true
                    end}
                self.config:paint(); return self.config
            end
        end
    end
    -- Classic More shares the selected widget's Configure path; no keyboard required.
    function Editor:onMore() return self:configure(true) end
    function Editor:sizes()
        local selected
        for _,p in ipairs(Layout.editorPage(self.model.document,self.model.index).placements) do if p.instance==self.model.selected then selected=p end end
        if not selected or not WidgetRegistry[selected.widget] then return end
        local sizes=WidgetRegistry[selected.widget].sizes["android-tablet"];local current=1
        for i,size in ipairs(sizes) do if selected.w==size[1] and selected.h==size[2] then current=i end end
        -- The approved toolbar cycles to the next legal span; it never evicts a neighbour.
        return self:action(function()
            local why="No other size fits here"
            for offset=1,#sizes-1 do
                local size=sizes[(current+offset-1)%#sizes+1]
                local ok,err=self.model:resize(size[1],size[2]);if ok then return true end;why=err or why
            end
            return false,why
        end)
    end
    function Editor:reset()
        self:confirm("Reset all Home pages to default?",function() return self.model:reset() end)
    end
    function Editor:confirm(text,fn)
        UIManager:show(ConfirmBox:new{text=_(text),ok_callback=function() self:action(fn) end}) -- gate: user action (editor destructive edit)
    end
    function Editor:done()
        local done=Budgets.span("editor.save",now_s,log)
        local ok,err=HomeEditor.save(self.model.document)
        done()
        if not ok then self.message=err; self:rebuild(); UIManager:setDirty(self,"ui"); return false end
        UIManager:close(self)
        host.index=1; host:rebuild(); UIManager:setDirty(host,"ui")
        return true
    end
    function Editor:onCloseWidget()
        if self.config then self.config:close(); self.config=nil end
    end
    function Editor:onClose()
        if self.picker then self.picker=nil; self:action(function() return true end); return true end
        if self.model.selected then self.model.selected=nil; self:action(function() return true end); return true end
        self:done(); return true
    end
    return Editor:new{}
end
function HomeEditor.show(host, action)
    local editor=HomeEditor.create(host)
    UIManager:show(editor) -- gate: user action (Home editor or Settings)
    if action == "rename" then editor:rename()
    elseif action == "reset" then editor:reset() end
    return editor
end
-- Settings uses the same host, draft and save boundary as Home's Edit button.
function HomeEditor.open(action)
    local host=HomeHost.active
    if not (host and topWidget()==host) then
        if not HomeHost.show() then return false end
        host=HomeHost.active
    end
    return HomeEditor.show(host, action)
end
