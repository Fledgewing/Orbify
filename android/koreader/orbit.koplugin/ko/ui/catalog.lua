-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Cover-led catalog surfaces. The host owns navigation and the companion owns all reads.
CatalogUI = {}
function CatalogUI.kit()
    local K=BookSyncUI.new();local p=K.px
    function K.separator(c,x,y,w,heavy)
        K.put(c,require("ui/widget/linewidget"):new{dimen=require("ui/geometry"):new{w=w,h=p(heavy and 1.5 or 1)},background=heavy and K.black or K.light},x,y)
    end
    function K.action(c,text,icon,x,y,w,h,callback,enabled,border)
        local area=K.canvas(w,h)
        if icon then
            local glyph
            local iconSize=math.min(p(24),math.floor(math.min(w,h)*.55))
            if icon=="filter" or icon=="download" or icon=="cloud" or icon=="star" or icon=="star-filled" or icon=="person" or icon=="chevL" or icon:find("disabled-",1,true) then
                glyph=require("ui/widget/imagewidget"):new{file=SOURCE_DIR.."/ko/ui/catalog-icons/"..icon..".svg",width=iconSize,height=iconSize,is_icon=true,alpha=true}
            else glyph=K.icon{name=icon,w=iconSize} end
            K.put(area,glyph,(w-iconSize)/2,(h-iconSize)/2)
        else
            local t=K.text{text=text,w=w-p(8),size="small",bold=true,muted=enabled==false}
            K.put(area,t,(w-t:getSize().w)/2,(h-t:getSize().h)/2)
        end
        local frame=border and K.frame(area,{w=w,h=h,border=p(1),radius=h/2,color=enabled==false and K.light or K.black}) or area
        local hit=K.hit(frame,{text=text,w=w,h=h,callback=callback,enabled=enabled});K.put(c,hit,x,y);return hit
    end
    function K.header(c,o)
        local backContent=K.canvas(p(74),p(52))
        K.action(backContent,"Back icon","chevL",0,0,p(22),p(52))
        K.label(backContent,(o.backText or "‹ Home"):gsub("‹ ",""),p(24),p(15),p(58),"small",{bold=true})
        local back=K.hit(backContent,{text=o.backText or "‹ Home",w=p(74),h=p(52),callback=o.back})
        K.put(c,back,p(20),p(6))
        K.label(c,o.title,p(110),p(o.subtitle and 9 or 18),o.w-p(240),"medium",{bold=true})
        if o.subtitle then K.label(c,o.subtitle,p(110),p(35),o.w-p(240),"caption",{muted=true}) end
        if o.filter then K.action(c,"Filter","filter",o.w-p(126),p(6),p(52),p(52),o.filter,nil,o.filterActive) end
        if o.search then K.action(c,"Search","search",o.w-p(72),p(6),p(52),p(52),o.search) end
        K.separator(c,0,p(63),o.w,true)
        return back
    end
    function K.pager(c,o)
        local y=o.h-p(66);local mid=o.w/2
        K.action(c,"Previous",o.offset>0 and "chevL" or "disabled-chevL",mid-p(101),y,p(52),p(52),o.previous,o.offset>0,true)
        local pages=o.total and math.max(1,math.ceil(o.total/o.limit))
        local page=o.page or math.floor(o.offset/o.limit)+1
        local t=K.text{text="Page "..page..(pages and " of "..pages or ""),w=p(92),size="caption",bold=true}
        K.put(c,t,mid-t:getSize().w/2,y+p(17))
        K.action(c,"Next",o.forwardEnabled and "chevR" or "disabled-chevR",mid+p(49),y,p(52),p(52),o.next,o.forwardEnabled,true)
    end
    function K.jacket(o)
        local cover=K.cover(o);local draw=cover.paintTo
        function cover:paintTo(bb,x,y)
            draw(self,bb,x,y)
            local w,h=o.w,o.h or math.floor(o.w/K.tokens.coverRatio);local radius=p(3)
            -- The bitmap fills the kit frame. Clear only the tiny outer corner
            -- pixels, then redraw its outline so saved covers retain rounded edges.
            for dy=0,radius-1 do
                local distance=radius-dy-.5
                local inset=math.max(0,math.ceil(radius-math.sqrt(math.max(0,radius*radius-distance*distance))-.5))
                if inset>0 then
                    bb:paintRect(x,y+dy,inset,1,K.white);bb:paintRect(x+w-inset,y+dy,inset,1,K.white)
                    bb:paintRect(x,y+h-dy-1,inset,1,K.white);bb:paintRect(x+w-inset,y+h-dy-1,inset,1,K.white)
                end
            end
            bb:paintBorder(x,y,w,h,p(1),K.black,radius)
        end
        return cover
    end
    function K.bookRow(c,b,x,y,w,h,open,more)
        local row=K.canvas(w-p(42),h)
        K.put(row,K.jacket{file=b.cover_path,title=b.title,author=b.authors and b.authors[1],w=p(52),h=p(78)},0,p(6))
        local nx=b.number and p(70) or p(78)
        if b.number then K.label(row,b.number,nx,p(33),p(28),"small",{bold=true}) end
        local tx=b.number and p(98) or p(78)
        K.label(row,b.title or "Untitled",tx,p(22),w-tx-p(42),"body",{bold=true})
        local sub=b.status_text or (b.authors and table.concat(b.authors,", ")) or ""
        if b.dot=="reading" and tonumber(b.progress) then
            K.put(row,K.progress{w=p(70),value=b.progress/100},tx,p(65))
            K.label(row,tostring(math.floor(b.progress)).."% · reading",tx+p(76),p(56),w-tx-p(120),"caption",{bold=true})
        else
            local statusX=tx
            if b.dot=="read" then
                K.put(row,K.icon{name="check",w=p(13)},tx,p(58));statusX=tx+p(20)
            elseif b.on_device==false then
                K.action(row,"On server","cloud",tx-p(3),p(51),p(20),p(24));statusX=tx+p(20)
            end
            K.label(row,sub,statusX,p(56),w-statusX-p(42),"caption",{muted=b.dot~="read",bold=b.dot=="read"})
        end
        if b.on_device==false then K.action(row,"Download badge","download",p(39),p(67),p(20),p(20),nil,true,true) end
        K.put(c,K.hit(row,{text=b.title,w=w-p(42),h=h,callback=open}),x,y)
        K.action(c,"More","more",x+w-p(42),y+p(20),p(42),p(52),more or open)
        K.separator(c,x,y+h,w)
    end
    return K
end
function CatalogUI.install(host,K,c,metrics)
    local old=host[1];host[1]=K.frame(c,{w=host.dimen.w,h=host.dimen.h})
    host.metrics=metrics;host.changed_rects={{x=0,y=0,w=host.dimen.w,h=host.dimen.h}}
    if old then old:free() end
end
function CatalogUI.refresh(host,pending)
    if pending and (host.catalogRetries or 0)<20 then
        host.catalogRetries=(host.catalogRetries or 0)+1
        host.widgetRefresh=function()
            host.widgetRefresh=nil
            if HomeHost.active==host and UIManager:getTopmostVisibleWidget()==host and not reading() then host:rebuild();UIManager:setDirty(host,"ui") end
        end
        UIManager:scheduleIn(.5,host.widgetRefresh)
    elseif not pending then host.catalogRetries=nil end
end
function CatalogUI.library(host)
    local K=CatalogUI.kit();local p=K.px;local w,h=host.dimen.w,host.dimen.h
    local settings=host.list_layout.pages[1].placements[1].settings
    local columns=5;local gap=p(15);local edge=p(24);local cw=math.floor((w-2*edge-4*gap)/5)
    local ch=math.floor(cw*1.5);local rowh=ch+p(48)
    local rows=math.max(1,math.floor((h-p(180))/rowh));local limit=math.min(24,rows*columns)
    local paint=Library.paint(host.filter.model.source=="search" and "search" or "library")
    host.caps=paint:capabilities()
    local result=paint:read("window",{source=settings.source,query=settings.query,offset=settings.offset,limit=limit,exclude_current=settings.exclude_current})
    host.list_result,host.list_limit=result,limit
    local c=K.canvas(w,h);local f=host.filter:header(result.total)
    K.header(c,{w=w,title=host.list_title,subtitle=f.subtitle,back=function() host:onClose() end,
        filter=f.callback,filterActive=f.active,search=function() host:search() end})
    local state,label=SeriesPlan.state(result);host.catalog_state=state
    if label then K.label(c,label,edge,p(68),w-2*edge,"caption",{muted=true}) end
    for i,b in ipairs(result.items or {}) do
        local x=edge+((i-1)%columns)*(cw+gap);local y=p(89)+math.floor((i-1)/columns)*rowh
        local tile=K.canvas(cw,rowh)
        K.put(tile,K.jacket{file=b.cover_path,title=b.title,author=b.authors and b.authors[1],w=cw,h=ch},0,0)
        K.label(tile,b.title or "Untitled",0,ch+p(4),cw,"caption",{bold=true})
        K.label(tile,b.authors and table.concat(b.authors,", ") or "",0,ch+p(21),cw,"caption",{muted=true})
        K.put(c,K.hit(tile,{text=b.title,w=cw,h=rowh,callback=function() host:dispatch("book",b) end}),x,y)
        if not b.local_path then K.action(c,"Download","download",x+cw-p(24),y+ch-p(24),p(30),p(30),function() host:dispatch("book",b) end,true,true) end
    end
    if state=="error" or state=="offline-without-data" then
        K.put(c,K.button{text="Retry",w=p(130),callback=function() Library.retry();host:rebuild();UIManager:setDirty(host,"ui") end},edge,p(120))
    end
    K.pager(c,{w=w,h=h,offset=settings.offset or 0,limit=limit,total=result.total,forwardEnabled=result.next~=nil,
        previous=function() host:listPage(-1) end,next=function() host:listPage(1) end})
    CatalogUI.install(host,K,c,paint:flush());CatalogUI.refresh(host,result.pending)
end
function CatalogUI.storage(page)
    local K=CatalogUI.kit();local p=K.px;local w,h=page.dimen.w,page.dimen.h
    local c=K.canvas(w,h);local edge=p(24);local data=page.data or {};local plan=StoragePlan.page(data)
    page.controls={}
    local back=K.header(c,{w=w,title="Storage",subtitle="This device · "..(plan.caption or plan.message or "Space unavailable"),back=function() page:onClose() end})
    local free=data.free_label or "—"
    local t=K.text{text=free,w=w-p(220),size=40,bold=true}
    K.put(c,t,edge,p(78))
    K.label(c,(plan.caption or ""):match("free of .+") or plan.message or "Space unavailable",edge+t:getSize().w+p(10),p(108),w-edge-t:getSize().w-p(34),"body",{bold=true})
    StorageUI.bar(c,plan.parts,edge,p(147),w-2*edge,p(30))
    local y=p(185)
    for i,part in ipairs(plan.parts) do
        StorageUI.bar(c,{{fraction=1,pattern=part.pattern}},edge,y+p(12),p(22),p(22))
        K.label(c,part.label,edge+p(34),y+p(6),w-p(220),"small",{bold=true})
        local sub=i==1 and (tostring(data.on_device or "—").." books") or i==2 and "Covers and details saved for offline browsing" or i==3 and "Not managed by BookSync" or ""
        K.label(c,sub,edge+p(34),y+p(25),w-p(220),"caption")
        local value=K.text{text=part.display or "—",w=p(120),size="small",bold=true}
        K.put(c,value,w-edge-value:getSize().w,y+p(16));K.separator(c,edge,y+p(49),w-2*edge)
        y=y+p(50)
    end
    if plan.warning then K.label(c,plan.warning,edge,y+p(6),w-2*edge,"caption",{bold=true});y=y+p(44) end
    if plan.message then K.label(c,plan.message,edge,y+p(6),w-2*edge,"small");y=y+p(30) end
    K.label(c,"FREE UP SPACE",edge,y+p(20),w-2*edge,"caption",{bold=true});y=y+p(44)
    local function action(label,sub,icon,callback)
        -- Storage's older saved projections encode the separator as a Latin-1 byte.
        sub=type(sub)=="string" and sub:gsub("\194?\183","·") or sub
        local area=K.canvas(w-2*edge,p(64))
        K.put(area,K.icon{name=icon,w=p(24)},0,p(20))
        K.label(area,label,p(36),p(10),w-2*edge-p(66),"body",{bold=true})
        K.label(area,sub or "",p(36),p(34),w-2*edge-p(66),"caption")
        K.label(area,"›",w-2*edge-p(18),p(20),p(18),"body")
        local control=K.hit(area,{text=label..(sub and "\n"..sub or ""),w=w-2*edge,h=p(64),callback=function() if not page.busy then callback() end end,enabled=not page.busy})
        K.put(c,control,edge,y);page.controls[#page.controls+1]=control
        K.separator(c,edge,y+p(63),w-2*edge);y=y+p(64)
    end
    for _,a in ipairs(plan.actions) do
        action(a.label,a.detail,a.id=="old" and "clock" or a.id=="finished" and "trash" or "books",function() page.confirm=a;page:confirmation() end)
    end
    action("Catalog cache limit","Covers and details for browsing offline","stack",function() StorageUI.cacheLimit() end)
    if data.pending or data.error then action("Retry",plan.message,"sync",function() Library.retry();page:rebuild() end) end
    back.text="Back";page.controls[#page.controls+1]=back
    CatalogUI.install(page,K,c,page.metrics)
end
function CatalogUI.readingPace(stats)
    stats=stats or {}
    local seconds,pages=tonumber(stats.reading_seconds),tonumber(stats.pages_read)
    if stats.available==false or not seconds or seconds<=0 or not pages or pages<=0 then return "—" end
    return tostring(math.floor(pages*3600/seconds)).." pp/h"
end
function CatalogUI.finish(sheet)
    local K=CatalogUI.kit();local p=K.px;local m=sheet.model or {}
    local w,h=sheet.screen_w,sheet.screen_h
    local rows=sheet:rows();local actions={};local cards={};local notices={}
    for _,r in ipairs(rows) do
        if r.kind=="card" then cards[#cards+1]=r
        elseif r.kind=="notice" or r.kind=="button" then
            if r.text~="View series" then notices[#notices+1]=r end
        else actions[r.kind]=actions[r.kind] or r end
    end
    -- Optional cards grow the sheet upward; keep the footer on screen at every state.
    local sh=math.min(h-p(44),p(610+math.max(0,#cards-1)*132+#notices*32+(m.next and not m.next.book_id and 42 or 0)))
    local sw=w-p(24);local inner=sw-p(48);local c=K.canvas(sw,sh)
    local function action(name,...)
        Library.endAction(name,sheet.ui,sheet.book,...)
    end
    local b=m.book or sheet.book or {}
    K.put(c,K.jacket{file=b.cover_path,title=m.title,author=m.author,w=p(98),h=p(147)},p(24),p(22))
    if actions.author and actions.author.action then
        local byline=K.canvas(sw-p(164),p(42))
        K.label(byline,actions.author.text,0,p(5),sw-p(164),"caption",{muted=true})
        K.put(c,K.hit(byline,{text=actions.author.text,w=sw-p(164),h=p(42),callback=actions.author.action}),p(140),p(22))
    end
    local displayFace=K.tokens.face.display
    K.tokens.face.display="NotoSerif-Italic.ttf"
    K.label(c,"The End",p(140),p(76),sw-p(164),36,{serif=true})
    K.tokens.face.display=displayFace
    local prefix=K.text{text=m.undo and "You finished " or "At the end of ",w=sw-p(164),size="body"}
    K.put(c,prefix,p(140),p(128))
    K.label(c,m.title or "your book",p(140)+prefix:getSize().w,p(128),sw-p(164)-prefix:getSize().w,"body",{bold=true})
    K.label(c,m.status or "Finish status not saved yet",p(140),p(154),sw-p(256),"caption",{muted=true})
    if actions.status and actions.status.action then
        K.put(c,K.button{text=actions.status.label,w=p(m.undo and 104 or 160),h=p(36),variant="ghost",size="caption",callback=actions.status.action},sw-p(m.undo and 128 or 184),p(150))
    end
    K.separator(c,p(24),p(185),inner)
    local stats=m.stats or {};local seconds=tonumber(stats.reading_seconds)
    local metrics={{stats.days_start_to_finish and tostring(stats.days_start_to_finish).." days" or "—","start to finish"},
        {seconds and string.format("%d h %02d m",math.floor(seconds/3600),math.floor(seconds%3600/60)) or "—","reading time"},
        {stats.pages_read and tostring(stats.pages_read) or "—","pages"},
        {CatalogUI.readingPace(stats),"reading pace"}}
    for i,v in ipairs(metrics) do
        local cell=math.floor(inner/4);local x=p(24)+(i-1)*cell
        local value=K.text{text=v[1],w=cell,size=24,bold=true}
        K.put(c,value,x+(cell-value:getSize().w)/2,p(197))
        local label=K.text{text=v[2],w=cell,size="caption",muted=true}
        K.put(c,label,x+(cell-label:getSize().w)/2,p(231))
    end
    K.separator(c,p(24),p(257),inner)
    K.label(c,"How was it?",p(24),p(282),p(200),"small",{bold=true})
    for n=1,5 do
        local x=sw-p(280)+(n-1)*p(52)
        K.action(c,"Rate "..n,m.stars and n<=m.stars and "star-filled" or "star",x,p(274),p(48),p(48),function() action("star",n) end)
    end
    local y=p(342)
    if m.next and not m.next.book_id then
        K.label(c,m.next.line or "",p(24),y,inner,"small",{bold=true})
        y=y+p(42)
    end
    for _,r in ipairs(cards) do
        local card={content=K.canvas(inner,p(122))}
        K.put(card.content,K.jacket{file=r.book and r.book.cover_path,title=r.text,w=p(66),h=p(98)},p(12),p(12))
        K.label(card.content,cards[1]==r and m.next and m.next.line or m.suggestion and m.suggestion.line or "Read next",p(90),p(24),inner-p(104),"caption",{bold=true,muted=true})
        K.label(card.content,r.text,p(90),p(49),inner-p(310),"medium",{serif=true,bold=true})
        if r.sub then K.label(card.content,r.sub,p(90),p(80),inner-p(310),"caption",{muted=true}) end
        K.put(card.content,K.button{text=r.label~="" and (r.label=="Open" and "Open" or "Download & start") or "Downloading…",w=p(204),icon=r.label~="Open" and r.label~="" and "arrowD" or nil,enabled=r.label~="",callback=r.action},inner-p(216),p(35))
        K.put(c,K.frame(card.content,{w=inner,h=p(122),border=p(1),radius=p(16)}),p(24),y);y=y+p(132)
    end
    for _,r in ipairs(notices) do
        if r.action then
            K.put(c,K.button{text=r.text,w=inner,h=p(30),variant="ghost",size="caption",callback=r.action},p(24),y)
        else K.label(c,r.text,p(24),y,inner,"caption") end
        y=y+p(32)
    end
    -- Series and Review remain direct actions, with no invented Want-to-read capability.
    if m.series_key then K.put(c,K.button{text="View series",w=p(150),h=p(34),variant="ghost",size="caption",callback=function() action("series",m.series_key) end},p(24),sh-p(110)) end
    K.put(c,K.button{text="Review ›",w=p(120),h=p(34),variant="ghost",size="caption",callback=function() action("review") end},sw-p(144),sh-p(110))
    K.put(c,K.button{text="Home",icon="home",w=inner/2-p(8),variant="outline",callback=function() action("home") end},p(24),sh-p(72))
    K.put(c,K.button{text="Back to book",w=inner/2-p(8),variant="ghost",callback=function() Library.endAction("back") end},p(24)+inner/2+p(8),sh-p(72))
    local frame=K.frame(c,{w=sw,h=sh,border=p(2),radius=p(20)})
    local full=K.canvas(w,h);K.put(full,frame,p(12),h-sh-p(10))
    local old=sheet[1];sheet[1]=full;sheet.frame=frame;sheet.sheet_h=sh+p(10)
    if old then old:free() end
end
