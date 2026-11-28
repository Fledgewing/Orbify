-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Presentation only: owned settings rows, header and modal surface over the shared kit.
SettingsPage={}
function SettingsPage.new(o)
    local K=BookSyncUI.new(); local p=K.px
    local sw,sh=Device.screen:getWidth(),Device.screen:getHeight()
    local w=o.w or (o.modal and math.min(sw-p(104),p(598)) or sw)
    local h=o.h or sh
    local c=K.canvas(w,h)
    local edge=o.modal and p(24) or p(25)
    local widgets={}
    local function put(widget,x,y,id)
        K.put(c,widget,x,y)
        if id then widgets[id]=widget end
        return widget
    end
    local function icon(name,size)
        if name:match("^settings%-") then return require("ui/widget/imagewidget"):new{file=SOURCE_DIR.."/ko/ui/icons/"..name..".svg",width=size,height=size,is_icon=true,alpha=true} end
        return K.icon{name=name,w=size}
    end
    local function rule(y)
        local line=K.frame(K.canvas(w-2*edge,p(1)),{w=w-2*edge,h=p(1)})
        line.background=K.light;put(line,edge,y)
    end
    if o.modal then
        K.label(c,o.title,edge,p(20),w-2*edge,20,{serif=true,bold=true})
        if o.subtitle then K.label(c,o.subtitle,edge,p(52),w-2*edge,"caption") end
    else
        local back=K.canvas(p(88),p(58))
        K.put(back,icon("settings-chevL",p(18)),p(9),p(20))
        K.label(back,o.backText or "Back",p(30),p(18),p(58),"small",{bold=true})
        put(K.hit(back,{w=p(88),h=p(58),text=o.backText or "Back",callback=o.onBack}),p(15),p(3),"back")
        K.label(c,o.title,p(103),p(9),w-p(125),"medium",{bold=true})
        K.label(c,o.subtitle or "BookSync settings",p(103),p(35),w-p(125),"caption",{muted=true})
        put(K.frame(K.canvas(w,p(1)),{w=w,h=p(1),ink=true}),0,p(63))
    end
    local y=o.startY or p(o.modal and 92 or o.root and 63 or 67)
    if o.intro then
        local sample=K.text{text="",w=w-2*edge,size="body"}
        local paragraph=require("ui/widget/textboxwidget"):new{text=o.intro,width=w-2*edge,face=sample.face}
        put(paragraph,edge,y)
        y=y+paragraph:getSize().h+p(24)
        sample:free()
    end
    for i,row in ipairs(o.rows or {}) do
        local rh=row.h or p(o.root and 105 or 73)
        local rc=K.canvas(w-2*edge,rh)
        local rw=w-2*edge
        local x=0
        if row.icon then
            local tile=K.canvas(p(40),p(40))
            local image=icon(row.icon,p(23));image.alpha=true
            K.put(tile,image,p(8),p(8))
            local well=K.frame(tile,{w=p(40),h=p(40),radius=p(11)})
            well.background=require("ffi/blitbuffer").Color8 and require("ffi/blitbuffer").Color8(236) or K.light;K.put(rc,well,0,(rh-p(40))/2)
            x=p(54)
        end
        if row.radio~=nil then
            local circle=K.canvas(p(22),p(22))
            if row.radio then K.put(circle,K.frame(K.canvas(p(10),p(10)),{w=p(10),h=p(10),radius=p(5),ink=true}),p(6),p(6)) end
            K.put(rc,K.frame(circle,{w=p(22),h=p(22),radius=p(11),border=p(2),transparent=true}),0,(rh-p(22))/2)
            x=p(34)
        end
        local detail=row.detail
        local dw=p(25)
        if detail then
            local measure=K.text{text=detail,w=rw*.48,size="small",bold=row.callback~=nil and not row.keyboard}
            dw=math.min(rw*.48,measure:getSize().w+p(8))
            if measure.free then measure:free() end
        end
        local labelY=row.sub and (rh-p(42))/2 or (rh-p(23))/2
        if row.card then labelY=p(15) end
        K.label(rc,row.text,x,labelY,rw-x-dw-p(row.callback and detail and 43 or 18),row.size or (row.section and "caption" or o.root and "body" or "small"),{bold=row.bold~=false,serif=row.serif,muted=row.enabled==false})
        if row.card then
            local lines={};for line in (row.sub or ""):gmatch("[^\n]+") do lines[#lines+1]=line end
            K.put(rc,K.segments{w=rw-p(24),items={"Battery saver","Balanced","Always current"},selected=({["Battery saver"]=1,Balanced=2,["Always up to date"]=3})[lines[1]],onChange=row.cardChange},p(12),p(42))
            for j=2,math.min(#lines,3) do K.label(rc,lines[j],p(12),p(102+(j-2)*24),rw-p(24),"caption",{muted=true}) end
        elseif row.sub then K.label(rc,row.sub,x,labelY+p(23),rw-x-p(12),"caption",{muted=not o.root}) end
        if row.toggle~=nil then
            K.put(rc,K.toggle{value=row.toggle,enabled=row.enabled,onChange=function() if row.callback then row.callback() end end},rw-p(56),(rh-p(32))/2)
        elseif detail then
            local inset=(row.keyboard or row.callback) and p(25) or 0
            K.label(rc,detail,rw-dw-inset,(rh-p(23))/2,dw,"small",{bold=row.callback~=nil and not row.keyboard,muted=row.enabled==false})
            if row.keyboard then K.put(rc,icon("settings-keyboard",p(17)),rw-p(17),(rh-p(17))/2)
            elseif row.callback then K.put(rc,icon("settings-chevR",p(17)),rw-p(17),(rh-p(17))/2) end
        elseif row.callback and row.radio==nil and not row.card then K.put(rc,icon("settings-chevR",p(17)),rw-p(20),(rh-p(17))/2) end
        if row.card then rc=K.frame(rc,{w=rw,h=rh,radius=p(16),border=p(1),color=K.light}) end
        local hit=K.hit(rc,{w=rw,h=rh,text=row.text,callback=row.callback,enabled=row.enabled})
        hit.callback=row.callback;hit.enabled=row.enabled~=false
        put(hit,edge,y,row.id or tostring(i))
        if row.rule~=false then rule(y+rh) end
        y=y+rh
    end
    local contentEnd=o.content and o.content(K,c,w,y,put)
    if o.fitContent then
        h=math.min(sh,(contentEnd or y)+p(24))
        -- OverlapGroup caches its size at init. Build a canvas at the measured height
        -- so Center/BottomContainer sees the same bounds that the frame paints.
        local fitted=K.canvas(w,h)
        for _,child in ipairs(c) do fitted[#fitted+1]=child end
        c=fitted
    end
    local Input=require("ui/widget/container/inputcontainer"):extend{name="booksync_settings_page",covers_fullscreen=not o.modal,modal=o.modal}
    function Input:onClose() if o.onBack then o.onBack() end;return true end
    function Input:getButtonById(id) return widgets[id] end
    function Input:moveFocusTo(x,y) self.focus={x,y} end
    function Input:closeMenu() if o.onBack then o.onBack() end end
    local frame=K.frame(c,{w=w,h=h,radius=o.modal and p(18) or 0,border=o.modal and p(2) or 0})
    if o.modal then
        local Container
        if o.bottom then Container=require("ui/widget/container/bottomcontainer") else Container=require("ui/widget/container/centercontainer") end
        frame=Container:new{dimen=require("ui/geometry"):new{w=sw,h=sh},frame}
        local overlay=K.canvas(sw,sh)
        local white=K.frame(K.canvas(sw,sh),{w=sw,h=sh})
        K.put(overlay,require("ui/widget/container/alphacontainer"):new{alpha=.62,white},0,0)
        K.put(overlay,frame,0,0);frame=overlay
    end
    return Input:new{title=o.title,dimen=require("ui/geometry"):new{w=sw,h=sh},key_events={Close={{"Back"}}},frame}
end
