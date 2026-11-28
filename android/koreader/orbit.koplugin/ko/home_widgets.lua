-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Original KOReader renderers. Only the host owns queries and invalidation.
HomeWidgets = {renderers={},needs={}}
function HomeWidgets.register(id, renderer, need)
    assert(WidgetRegistry[id] and Budgets.widgets[id], "Widget contract/budget required")
    HomeWidgets.renderers[id]=renderer
    HomeWidgets.needs[id]=need
end
function HomeWidgets.ui()
    if HomeWidgets._ui then return HomeWidgets._ui end
    local u={Overlap=require("ui/widget/overlapgroup"),Frame=require("ui/widget/container/framecontainer"),
        Text=require("ui/widget/textwidget"),Button=require("ui/widget/button"),Progress=require("ui/widget/progresswidget")}
    u.Font=require("ui/font"); u.BB=require("ffi/blitbuffer")
    HomeWidgets._ui=u; return u
end
function HomeWidgets.kit()
    local K=BookSyncUI.new(HomeWidgets.kitScale)
    K.icons.filter=true;K.icons.clouddl=true -- Home's list/selection decoration extends the owned icon set.
    return K
end
function HomeWidgets.canvas(w,h)
    return HomeWidgets.ui().Overlap:new{dimen={w=w,h=h},allow_mirroring=false}
end
function HomeWidgets.put(canvas, child, x,y)
    child.overlap_offset={x,y}; canvas[#canvas+1]=child; return child
end
function HomeWidgets.text(canvas, text, x,y,w,size,ink,bold)
    local u=HomeWidgets.ui()
    return HomeWidgets.put(canvas,u.Text:new{text=tostring(text or ""),face=u.Font:getFace(bold and "tfont" or "cfont",size),
        max_width=w,fgcolor=ink and u.BB.COLOR_WHITE or u.BB.COLOR_BLACK},x,y)
end
function HomeWidgets.button(canvas,text,x,y,w,h,callback,enabled)
    return HomeWidgets.put(canvas,HomeWidgets.ui().Button:new{text=text,width=w,height=h,padding=0,bordersize=0,
        text_font_size=16,avoid_text_truncation=false,callback=callback,enabled=enabled~=false},x,y)
end
-- First paint is a placeholder. Native bitmap decoding is deferred and its resource
-- belongs to this node: freeing/rebuilding the host cancels late delivery.
function HomeWidgets.cover(canvas,book,x,y,w,h,ink)
    local u=HomeWidgets.ui()
    if HomeWidgets.preview then
        local K=HomeWidgets.kit()
        local child=book.cover_path and require("ui/widget/imagewidget"):new{file=book.cover_path,width=w,height=h,scale_factor=0}
            or K.cover{w=w,h=h,title=book.title,author=book.authors and book.authors[1]}
        return HomeWidgets.put(canvas,u.Frame:new{padding=0,margin=0,bordersize=ink and K.px(2) or 1,color=ink and u.BB.COLOR_WHITE or u.BB.COLOR_BLACK,radius=K.px(3),child},x,y)
    end
    local placeholder=BookSyncUI.new().cover{w=w,h=h,title=book.title,author=book.authors and book.authors[1]}
    local node=u.Frame:new{coverExpected=type(book.cover_path)=="string",padding=0,margin=0,bordersize=ink and HomeWidgets.kit().px(2) or 1,color=ink and u.BB.COLOR_WHITE or u.BB.COLOR_BLACK,radius=HomeWidgets.kit().px(3),placeholder}
    local basePaint,baseFree=node.paintTo,node.free
    function node:paintTo(bb,px,py)
        if not self.started then
            self.started=true
            local host=HomeHost.active
            self.cancel=Library.prepareCardCover(book,function(path)
                if self.released or HomeHost.active~=host or UIManager:getTopmostVisibleWidget()~=host then return end
                local finish=Budgets.span("card.cover.decode",now_s,log)
                local image
                local ok=pcall(function()
                    image=require("ui/widget/imagewidget"):new{file=path,width=w,height=h,scale_factor=0}
                    image:_render()
                end)
                if ok then
                    self[1]:free(); self[1]=image;self.coverReady=true
                    UIManager:setDirty(host,"ui",self.dimen)
                elseif image then image:free() end
                finish()
            end,function() return not self.released and host and HomeHost.active==host and UIManager:getTopmostVisibleWidget()==host end)
        end
        return basePaint(self,bb,px,py)
    end
    function node:free()
        if self.released then return end
        self.released=true
        if self.cancel then self.cancel(); self.cancel=nil end
        if baseFree then baseFree(self) end
    end
    function node:onCloseWidget() self:free() end
    return HomeWidgets.put(canvas,node,x,y)
end
-- Transparent input surface: keep gesture coordinates without painting over a cover.
function HomeWidgets.coverTap(canvas,callback,x,y,w,h)
    local range=require("ui/geometry"):new{x=0,y=0,w=w,h=h}
    local Tap=require("ui/widget/container/inputcontainer"):extend{}
    function Tap:paintTo(_bb,px,py) self.dimen.x,self.dimen.y=px,py end
    function Tap:onTapCardCover() self.callback(); return true end
    return HomeWidgets.put(canvas,Tap:new{dimen=range,width=w,height=h,text=_("Book"),callback=callback,
        ges_events={TapCardCover={require("ui/gesturerange"):new{ges="tap",range=range}}}},x,y)
end
function HomeWidgets.more(canvas,b,dispatch,x,y,w,h)
    local job=not b.local_path and b.transfer
    local active=job and job.id and (job.state=="running" or job.state=="queued" or job.state=="canceling")
    HomeWidgets.button(canvas,active and "Cancel" or "⋯",x,y,w,h,function() dispatch(active and "download-cancel" or "more",b) end)
end
function HomeWidgets.caption(settings, book)
    local job=not book.local_path and book.transfer
    if job then return job.progress_text or job.error or job.state or "" end
    local cap=settings.cap or 0
    if cap==1 then return book.added_label or (book.added and tostring(book.added):sub(1,10)) or "—" end
    if type(book.status_note)=="string" then return book.status_note end
    if cap==2 then return book.status=="finished" and _("Finished") or book.progress and string.format("%d%%",book.progress) or _("Not started") end
    if cap==3 then return book.authors and book.authors[1] or "" end
    return ""
end
function HomeWidgets.classicCard(p, snapshot, dispatch, rect)
    local u=HomeWidgets.ui(); local scale=function(n) return Device.screen:scaleBySize(n) end
    local geometry=HomeHostPlan.cardGeometry(p,rect,scale)
    local w,h,compact,pad=geometry.w,geometry.h,geometry.compact,geometry.pad
    local canvas=HomeWidgets.canvas(w,h)
    local ready=snapshot.state == "ready" or snapshot.state == "offline-with-data"
    local hero=p.widget == "continue-reading" and ready
    local heading
    local title=type((p.settings or {}).title) == "string" and p.settings.title or (p.widget == "continue-reading" and "Continue reading" or p.widget == "lists" and "Lists" or "Shelf")
    if snapshot.context and snapshot.context.title then title=snapshot.context.title end
    if compact then
        -- One horizontal band keeps both actions large in a one-row tile.
        HomeWidgets.button(canvas,_(title).." ›",pad,math.floor((h-scale(50))/2),math.floor((w-3*pad)/2),scale(50),function() dispatch("all") end)
    elseif hero or p.widget == "lists" then heading=HomeWidgets.text(canvas,_(title),pad,pad,w-2*pad-(hero and scale(50) or 0),18,hero,true)
    else HomeWidgets.button(canvas,_(title).."  ›",pad,pad,w-2*pad,scale(52),function() dispatch("all") end) end
    if not compact and snapshot.context and snapshot.context.coverage then HomeWidgets.text(canvas,snapshot.context.coverage,pad,pad+scale(40),w-2*pad,10) end
    if not ready then
        local labels={loading="Loading…",empty=p.widget == "continue-reading" and "Open a book to start reading" or p.widget == "lists" and "No lists yet" or "No books here yet",["offline-without-data"]="Not saved yet",error="Couldn't load this widget"}
        if not compact then HomeWidgets.text(canvas,_(snapshot.setup and "Sign in to load your library" or labels[snapshot.state] or "Unavailable"),pad,pad+scale(58),w-2*pad,16) end
        local rx=compact and math.floor((w+pad)/2) or pad
        local rw=compact and math.floor((w-3*pad)/2) or w-2*pad
        local ry=compact and math.floor((h-scale(50))/2) or h-pad-scale(50)
        if snapshot.setup then
            HomeWidgets.button(canvas,_("Sign in"),rx,ry,rw,scale(50),function() dispatch("setup") end)
        elseif snapshot.state ~= "empty" then
            HomeWidgets.button(canvas,_(compact and (labels[snapshot.state] or "Unavailable") or "Retry"),rx,ry,rw,scale(50),function() dispatch("retry") end)
        elseif compact then
            HomeWidgets.text(canvas,_(p.widget == "lists" and "No lists yet" or "No books yet"),rx,math.floor((h-scale(20))/2),rw,16)
        end
    elseif compact then
        local b=snapshot.items[1]
        local more=p.widget~="lists" and scale(50) or 0
        HomeWidgets.button(canvas,b.title or _("Untitled"),math.floor((w+pad)/2),math.floor((h-scale(50))/2),math.floor((w-3*pad)/2)-more,scale(50),function() dispatch(p.widget == "lists" and "list" or "book",b) end)
        if more>0 then HomeWidgets.more(canvas,b,dispatch,w-pad-more,math.floor((h-scale(50))/2),more,scale(50)) end
    elseif hero then
        local b=snapshot.items[1]; local coverW=math.min(scale(110),math.floor(w*.23))
        local tx=pad+coverW+scale(18); local tw=w-tx-pad
        local coverH=math.min(h-2*pad-scale(32),math.floor(coverW*1.5))
        local coverY=math.max(math.floor((h-coverH)/2),pad+heading:getSize().h+scale(4))
        coverH=math.max(1,math.min(coverH,h-pad-coverY))
        HomeWidgets.cover(canvas,b,pad,coverY,coverW,coverH,true)
        HomeWidgets.more(canvas,b,dispatch,w-pad-scale(50),0,scale(50),scale(50))
        local short=h<scale(220)
        HomeWidgets.text(canvas,b.title or _("Untitled"),tx,pad+scale(35),tw,short and 18 or 25,true,true)
        if not short then HomeWidgets.text(canvas,b.authors and b.authors[1] or "",tx,pad+scale(73),tw,16,true) end
        if h>=scale(290) and b.series_line then HomeWidgets.text(canvas,b.series_line,tx,pad+scale(98),tw,14,true) end
        local percentW=scale(short and 48 or 70)
        HomeWidgets.text(canvas,b.time_left or _("Not enough reading yet"),tx+percentW,h-scale(short and 102 or 121),tw-percentW,12,true)
        if h>=scale(290) then HomeWidgets.text(canvas,b.finish_forecast or _("Finish date unavailable"),tx,h-scale(146),tw,13,true) end
        local pct=tonumber(b.progress)
        pct=pct and pct==pct and math.max(0,math.min(100,pct)) or nil
        HomeWidgets.text(canvas,pct and string.format("%d%%",pct) or _("—"),tx,h-scale(short and 105 or 128),percentW,short and 16 or 26,true,true)
        HomeWidgets.put(canvas,u.Progress:new{width=tw,height=scale(9),percentage=(pct or 0)/100,radius=0,margin_h=0,margin_v=0,
            bordercolor=u.BB.COLOR_WHITE,bgcolor=u.BB.COLOR_DARK_GRAY,fillcolor=u.BB.COLOR_WHITE},tx,h-scale(78))
        HomeWidgets.button(canvas,b.local_path and _("Resume") or _("Download"),tx,h-pad-scale(50),tw,scale(50),function() dispatch("book",b) end)
    elseif geometry.shelf then
        local count=math.min(snapshot.count,geometry.capacity)
        local cw=math.floor((w-2*pad)/math.max(1,count))
        local rich=h>=scale(260)
        local coverH=math.max(scale(30),h-2*pad-scale(rich and 144 or 112))
        for i=1,count do
            local b=snapshot.items[i]; local x=pad+(i-1)*cw
            local bw=cw-scale(8)
            HomeWidgets.cover(canvas,b,x,pad+scale(56),bw,coverH)
            HomeWidgets.coverTap(canvas,function() dispatch("book",b) end,x,pad+scale(56),bw,math.max(scale(50),coverH))
            HomeWidgets.more(canvas,b,dispatch,x+math.max(0,bw-scale(50)),h-pad-scale(50),scale(50),scale(50))
            HomeWidgets.text(canvas,b.title or _("Untitled"),x,h-pad-scale(rich and 74 or 30),math.max(1,cw-scale(60)),14,false,true)
            HomeWidgets.text(canvas,HomeWidgets.caption(p.settings,b),x,h-pad-scale(rich and 56 or 12),math.max(1,cw-scale(60)),11)
            if rich then
                HomeWidgets.text(canvas,b.time_left or _("Not enough reading yet"),x,h-pad-scale(38),math.max(1,cw-scale(60)),11)
                HomeWidgets.text(canvas,b.finish_forecast or _("Finish date unavailable"),x,h-pad-scale(20),math.max(1,cw-scale(60)),11)
            end
        end
    else
        local rowH=geometry.rowH; local count=math.min(snapshot.count,geometry.capacity)
        local dense=rowH<scale(96)
        for i=1,count do
            local b=snapshot.items[i]
            local label=b.title or b.name or _("Untitled")
            if b.group and b.group ~= "" then label=b.group.." · "..label end
            if p.widget == "lists" and b.count ~= nil then label=label.."  ·  "..tostring(b.count) end
            local y=pad+scale(52)+(i-1)*rowH
            local progress=p.widget == "booklist" and tonumber(b.progress)
            if progress then label=label.."  ·  "..string.format("%d%%",math.max(0,math.min(100,progress))) end
            local caption=p.widget=="booklist" and HomeWidgets.caption(p.settings,b) or ""
            if caption~="" and (p.settings.cap~=2 or not progress) then label=label.." · "..caption end
            local books=p.widget=="booklist"
            local bx=books and pad+scale(42) or pad
            if books then HomeWidgets.cover(canvas,b,pad,y+scale(4),scale(34),math.min(scale(51),rowH-scale(8))) end
            HomeWidgets.button(canvas,books and "" or label,bx,y,w-pad-bx-(books and scale(50) or 0),rowH,function()
                dispatch(p.widget == "lists" and "list" or "book",b)
            end)
            if books then
                HomeWidgets.text(canvas,b.title or _("Untitled"),bx,y+scale(4),w-bx-pad-scale(50),14,false,true)
                if not dense then HomeWidgets.text(canvas,caption~="" and caption or b.series_line or (b.authors and b.authors[1]) or "",bx,y+scale(25),w-bx-pad-scale(50),11) end
                local pace=(progress and string.format("%d%% · ",progress) or "")..(b.time_left or _("Not enough reading yet"))
                if dense and caption~="" and not (p.settings.cap==2 and progress and b.status~="finished") then pace=pace.." · "..caption end
                HomeWidgets.text(canvas,pace,bx,y+scale(dense and 25 or 44),w-bx-pad-scale(50),11)
                if not dense then HomeWidgets.text(canvas,b.finish_forecast or _("Finish date unavailable"),bx,y+scale(63),w-bx-pad-scale(50),11) end
                HomeWidgets.more(canvas,b,dispatch,w-pad-scale(50),y,scale(50),rowH)
            end
            if progress then HomeWidgets.put(canvas,u.Progress:new{width=w-2*pad,height=scale(3),radius=0,margin_h=0,margin_v=0,
                percentage=math.max(0,math.min(100,progress))/100},pad,y+rowH-scale(3)) end
        end
    end
    return u.Frame:new{padding=0,margin=0,bordersize=1,radius=scale(10),background=hero and u.BB.COLOR_BLACK or u.BB.COLOR_WHITE,canvas}
end
-- Approved Home presentation; catalogue lists retain their independent renderer.
function HomeWidgets.card(p,snapshot,dispatch,rect)
    if p.instance=="list-books" or rect.h<HomeWidgets.kit().px(132) then return HomeWidgets.classicCard(p,snapshot,dispatch,rect) end
    local K=HomeWidgets.kit();local px=K.px
    local w,h=rect.w,rect.h;local pad=px(16);local settings=p.settings or {}
    local hero=p.widget=="continue-reading"
    local ready=snapshot.state=="ready" or snapshot.state=="offline-with-data"
    local title=type(settings.title)=="string" and #settings.title<=80 and settings.title or (hero and "Continue reading" or p.widget=="lists" and "Lists" or "Shelf")
    local card=K.card{w=w,h=h,title=not hero and title or nil,ink=hero,
        count=snapshot.total,all=not hero and function() dispatch("all") end or nil}
    local c=card.content
    if not ready then
        if hero then K.label(c,title,pad,pad,w-2*pad,"small",{bold=true,ink=true}) end
        local labels={loading="Loading…",empty=hero and "Open a book to start reading" or p.widget=="lists" and "No lists yet" or "No books here yet",
            ["offline-without-data"]="Not saved yet",error="Couldn't load this widget"}
        K.label(c,snapshot.setup and "Sign in to load your library" or labels[snapshot.state] or "Unavailable",pad,px(58),w-2*pad,"body",{ink=hero})
        if snapshot.state~="empty" then K.put(c,K.button{text=snapshot.setup and "Sign in" or "Retry",w=math.min(w-2*pad,px(160)),
            variant="outline",callback=function() dispatch(snapshot.setup and "setup" or "retry") end},pad,h-pad-px(52)) end
        return card
    end
    local function cover(b,x,y,cw,ch)
        HomeWidgets.cover(c,b,x,y,cw,ch,hero)
        HomeWidgets.coverTap(c,function() dispatch("book",b) end,x,not hero and math.max(y,px(52)) or y,cw,ch)
        if not hero and not b.local_path then
            local badge=K.canvas(px(20),px(20));K.put(badge,K.icon{name="clouddl",w=px(14)},px(3),px(3))
            K.put(c,K.frame(badge,{w=px(20),h=px(20),radius=px(10),border=px(1.5)}),x+cw-px(10),y+ch-px(10))
        end
    end
    if hero and h<px(250) then
        local b=snapshot.items[1];local ch=h-2*pad;local cw=math.min(math.floor(ch*2/3),math.floor(w*.36))
        ch=math.floor(cw*1.5);local x=pad+cw+px(14);local tw=w-x-pad
        cover(b,pad,math.floor((h-ch)/2),cw,ch)
        K.label(c,b.title or "Untitled",x,pad,tw-px(42),w<px(420) and 20 or 24,{serif=true,bold=true,ink=true})
        if w>=px(420) then K.label(c,b.authors and b.authors[1] or "",x,pad+px(30),tw,"small",{ink=true}) end
        K.put(c,K.button{text="⋯",w=px(52),h=px(52),variant="ghost",ink=true,callback=function() dispatch("more",b) end},w-pad-px(52),0)
        local pct=tonumber(b.progress);pct=pct and pct==pct and math.max(0,math.min(100,pct)) or nil
        K.label(c,pct and string.format("%d%%",pct) or "—",x,h-pad-px(98),px(60),"caption",{bold=true,ink=true})
        K.label(c,b.time_left or "Not enough reading yet",x+px(66),h-pad-px(98),tw-px(66),"caption",{ink=true})
        K.put(c,K.progress{w=tw,h=px(8),value=(pct or 0)/100,ink=true},x,h-pad-px(66))
        K.put(c,K.button{text=b.local_path and "Resume" or "Download",icon=b.local_path and "play" or nil,w=math.min(px(132),tw),variant="inverted",callback=function() dispatch("book",b) end},x,h-pad-px(52))
    elseif hero then
        local b=snapshot.items[1];local ch=h-2*pad;local cw=math.floor(ch*2/3)
        if w<px(420) then cw=math.min(cw,math.floor(w*.33));ch=math.floor(cw*1.5) end
        local x=pad+cw+px(22);local tw=w-x-pad
        cover(b,pad,pad,cw,ch)
        local capX=x
        for letter in ("CONTINUE READING"):gmatch(".") do
            local glyph=K.text{text=letter,w=tw,size="caption",bold=true,ink=true};glyph.fgcolor=K.light
            if capX+glyph:getSize().w>x+tw-px(42) then glyph:free();break end
            K.put(c,glyph,capX,pad);capX=capX+glyph:getSize().w+px(1)
        end
        K.put(c,K.button{text="⋯",w=px(52),h=px(52),variant="ghost",ink=true,callback=function() dispatch("more",b) end},w-pad-px(44),0)
        K.label(c,b.title or "Untitled",x,pad+px(22),tw,"heading",{serif=true,bold=true,ink=true})
        K.label(c,b.authors and b.authors[1] or "",x,pad+px(64),tw,"body",{ink=true}).fgcolor=K.light
        if h>px(230) then K.label(c,b.series_line or "",x,pad+px(87),tw,"caption",{ink=true}).fgcolor=K.rule end
        local pct=tonumber(b.progress);if pct and pct~=pct then pct=nil end
        pct=pct and math.max(0,math.min(100,pct)) or nil
        local base=h-pad-px(134)
        local metric=K.canvas(px(120),px(52));metric.text=pct and string.format("%d%%",pct) or "—";metric.max_width=px(120)
        local digits=K.label(metric,pct and string.format("%d",pct) or "—",0,0,px(120),"number",{bold=true,ink=true})
        if pct then K.label(metric,"%",digits:getSize().w,px(16),px(44),22,{bold=true,ink=true}) end
        K.put(c,metric,x,base)
        local time=K.text{text=b.time_left or "Not enough reading yet",w=tw-px(130),size="body",ink=true}
        K.put(c,time,w-pad-time:getSize().w,base+px(22))
        K.put(c,K.progress{w=tw,h=px(11),value=(pct or 0)/100,ink=true},x,h-pad-px(74))
        local bw=math.min(px(132),tw)
        K.put(c,K.button{text=b.local_path and "Resume" or "Download",icon=b.local_path and "play" or nil,w=bw,variant="inverted",callback=function() dispatch("book",b) end},x,h-pad-px(52))
        if tw>px(260) then
            local text=b.finish_forecast or "Finish date unavailable";local prefix,day=text:match("^(Done by )(.*)$")
            local forecast=K.canvas(tw-bw-px(18),px(52));forecast.text=text
            K.put(forecast,K.icon{name="clock",w=px(16),ink=true},0,px(2))
            local label=K.label(forecast,prefix or text,px(22),0,tw-bw-px(40),"small",{ink=true});label.fgcolor=K.light
            if day then K.label(forecast,day,px(22)+label:getSize().w,0,tw-bw-px(40)-label:getSize().w,"small",{bold=true,ink=true}) end
            K.put(c,forecast,x+bw+px(18),h-pad-px(36))
        end
    elseif p.widget=="lists" then
        local rowH=math.max(px(52),math.floor((h-pad-px(40))/4))
        local count=math.min(snapshot.count,math.floor((h-pad-px(40))/rowH))
        local icons={"feather","sparkle","calendar","stack"}
        for i=1,count do
            local b=snapshot.items[i];local y=px(42)+(i-1)*rowH
            local row=K.row{text=b.title or b.name or "List",detail=b.count and tostring(b.count).."  ›" or "›",icon=icons[(i-1)%4+1],w=w-2*pad,h=rowH,callback=nil}
            K.put(c,row,pad,y)
            K.put(c,K.hit(K.canvas(w-2*pad,rowH),{w=w-2*pad,h=rowH,text=b.title,callback=function() dispatch("list",b) end}),pad,y+px(10))
            if i<count then K.put(c,K.frame(K.canvas(w-2*pad,px(1)),{w=w-2*pad,h=px(1),background=K.light}),pad,y+rowH-px(4)) end
        end
    elseif (settings.style or 0)==0 and h>=px(160) then
        local count=math.min(snapshot.count,p.w>=4 and 6 or 3)
        local cell=(w-2*pad)/math.max(count,1)
        local ch=math.min(h-pad-px(settings.cap==1 and 62 or 44),math.floor((cell-px(12))*1.5))
        local cw=math.floor(ch*2/3)
        for i=1,count do
            local b=snapshot.items[i];local x=pad+(i-1)*cell
            cover(b,x,px(48),cw,ch)
            if settings.cap==1 then K.label(c,HomeWidgets.caption(settings,b),x,px(48)+ch+px(5),cell-px(8),"caption",{bold=true}) end
        end
    else
        local rowH=math.max(px(60),math.min(px(68),math.floor((h-pad-px(42))/math.max(1,math.min(snapshot.count,2)))))
        local count=math.min(snapshot.count,math.floor((h-pad-px(42))/rowH))
        for i=1,count do
            local b=snapshot.items[i];local y=px(42)+(i-1)*rowH;local cw=px(42);local ch=px(63)
            HomeWidgets.cover(c,b,pad,y,cw,ch)
            K.put(c,K.hit(K.canvas(w-2*pad-px(52),rowH),{w=w-2*pad-px(52),h=rowH,text=b.title,callback=function() dispatch("book",b) end}),pad,y+px(10))
            local x=pad+cw+px(14);local tw=w-x-pad-px(52)
            K.label(c,b.title or "Untitled",x,y,tw,"small",{bold=true})
            local pct=tonumber(b.progress);pct=pct and pct==pct and math.max(0,math.min(100,pct)) or nil
            K.put(c,K.progress{w=px(70),value=(pct or 0)/100},x,y+px(32))
            K.label(c,pct and string.format("%d%%",pct) or "—",x+px(78),y+px(26),tw-px(78),"caption",{bold=true})
            local caption=b.last_read_label or HomeHostPlan.readAge(b.last_read,os.time())
            if settings.cap~=nil and settings.cap~=2 and h<px(190) then caption=(pct and string.format("%d%% · ",pct) or "")..(b.time_left or "Not enough reading yet").." · "..HomeWidgets.caption(settings,b) end
            K.label(c,caption,x,y+px(46),tw,"caption",{muted=true})
            K.put(c,K.icon{name="chevR",w=px(16)},w-pad-px(16),y+(rowH-px(16))/2)
            K.put(c,K.hit(K.canvas(px(52),rowH),{w=px(52),h=rowH,text="›",callback=function() dispatch("more",b) end}),w-pad-px(52),y+px(10))
        end
    end
    return card
end

function HomeWidgets.libraryCard(p,snapshot,dispatch,rect)
    local K=HomeWidgets.kit();local px=K.px;local w,h=rect.w,rect.h
    if p.w<2 or p.h~=1 or h<px(70) then return StorageUI.widget(p,snapshot,dispatch,rect) end
    local card=K.card{w=w,h=h};local c=card.content;local pad=px(16)
    local d=snapshot.data or {};local st=d.storage or {};local half=(w-3*pad)/2
    local total=d.freshness and d.freshness.saved and tostring(d.total or 0) or "—"
    K.label(c,total,pad,pad,half,"heading",{bold=true})
    K.label(c,"books in your library",pad,h-pad-px(20),half,"caption",{muted=true})
    K.put(c,K.hit(K.canvas(half,h),{w=half,h=h,text="All books",callback=function() dispatch("all") end}),pad,0)
    local x=half+2*pad
    K.label(c,tostring(st.on_device or d.on_device or "—"),x,pad,half,"medium",{bold=true})
    K.label(c,"on device",x+px(44),pad+px(6),half-px(44),"caption",{muted=true})
    StorageUI.bar(c,st.parts,x,h-pad-px(28),half,px(6))
    K.label(c,st.widget_label or "Space unavailable",x,h-pad-px(20),half,"caption")
    K.put(c,K.hit(K.canvas(half,h),{w=half,h=h,text="Storage",callback=function() dispatch("storage") end}),x,0)
    return card
end
for _,id in ipairs({"continue-reading","booklist","lists"}) do HomeWidgets.register(id,HomeWidgets.card) end

-- Register the existing stats renderer against the host snapshot contract. The host
-- reads one materialized reading.stats row for all Stats cards in a paint.
HomeWidgets.stats={}
for _,id in ipairs({"year-in-reading","this-week","when-you-read","reading-records","today","reading-streak","reading-goal","pages-read","monthly-reading"}) do
    local name=id
    HomeWidgets.stats[name]=true
    HomeWidgets.register(name,function(p,snapshot,dispatch,rect)
        return ReadingStatsWidgets.render(name,snapshot.data,{w=rect.w-2,h=rect.h-2,rows=p.h,snapshotBytes=snapshot.bytes})
    end,function() return {op=WidgetRegistry[name].dataNeeds[1].source=="reading.metrics" and "reading.metrics" or "reading.stats",limit=1} end)
end
HomeWidgets.register("library",function(p,snapshot,dispatch,rect)
    return HomeWidgets.libraryCard(p,snapshot,dispatch,rect)
end,function() return {op="library.summary",limit=1} end)
-- F12-O extends the existing Battery registration with the snapshot-only page renderer.
HomeWidgets.register("battery",function(p,snapshot,dispatch,rect)
    assert(Budgets.check(Budgets.get("widgets","battery"),{rows=1,bytes=snapshot.bytes,
        snapshotBytes=snapshot.bytes,spawns=0,network=0,roundTrips=0}))
    return BatteryUI.widget(p,snapshot,dispatch,rect)
end,function() return {op="battery",limit=1} end)

-- The forecast stays a distinct read-only card; pace/date formatting is worker-owned.
HomeWidgets.register("finish-forecast",function(p,snapshot,dispatch,rect)
    local finish=Budgets.span("finish-forecast.paint",now_s,log)
    assert(Budgets.check(Budgets.get("widgets","finish-forecast"),{rows=1,bytes=snapshot.bytes,snapshotBytes=snapshot.bytes,spawns=0,network=0,roundTrips=0}))
    local scale=function(n) return Device.screen:scaleBySize(n) end
    local w,h=rect.w-2,rect.h-2;local c=HomeWidgets.canvas(w,h);local pad=scale(10)
    HomeWidgets.text(c,"Finish forecast",pad,pad,w-2*pad,18,false,true)
    local b=snapshot.items and snapshot.items[1]
    if b then
        HomeWidgets.text(c,b.title or "Current book",pad,pad+scale(34),w-2*pad,18,false,true)
        HomeWidgets.text(c,b.time_left or "Not enough reading yet",pad,pad+scale(64),w-2*pad,20)
        HomeWidgets.text(c,b.finish_forecast or "Finish date unavailable",pad,pad+scale(98),w-2*pad,14)
        if b.forecast_source then HomeWidgets.text(c,"Measured pace · this reader",pad,h-pad-scale(16),w-2*pad,11) end
    else HomeWidgets.text(c,snapshot.state=="loading" and "Loading…" or "Open a book to see its forecast",pad,pad+scale(42),w-2*pad,14) end
    finish();return c
end,function() return {op="window",source="reading",query={sort="last",dir="desc"},offset=0,limit=1} end)
