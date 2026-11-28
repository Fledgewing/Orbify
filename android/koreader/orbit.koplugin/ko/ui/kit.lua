-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Owned presentation primitives. No data access, timers, focus changes or UIManager.
-- Dimensions are native pixels; tokens are prototype CSS units, scaled once by px().
BookSyncUI = {}
function BookSyncUI.new(scale)
    local K={scale=scale or Device.screen:getWidth()/702}
    local BB=require("ffi/blitbuffer")
    local Font=require("ui/font")
    local Text=require("ui/widget/textwidget")
    local Frame=require("ui/widget/container/framecontainer")
    local Overlap=require("ui/widget/overlapgroup")
    local Input=require("ui/widget/container/inputcontainer")
    local Geom=require("ui/geometry")
    local Gesture=require("ui/gesturerange")
    K.tokens={type={caption=12,small=14,body=16,medium=19,title=25,heading=31,number=40},
        space={xs=4,sm=8,gap=12,pad=16,edge=20},line={hair=1,control=1.5,card=1,focus=3},
        radius={cover=3,small=10,card=16,sheet=20},tap=52,coverRatio=2/3,
        face={display="NotoSerif-Regular.ttf",ui="NotoSans-Regular.ttf"}}
    K.icons={chevR=true,search=true,home=true,play=true,more=true,check=true,sync=true,feather=true,sparkle=true,calendar=true,stack=true,clock=true,books=true,toc=true,bookmark=true,goto=true,info=true,kmenu=true,plus=true,minus=true,x=true,edit=true,trash=true,resize=true,arrowL=true,arrowR=true,arrowU=true,arrowD=true}
    K.black,K.white,K.gray,K.light=BB.COLOR_BLACK,BB.COLOR_WHITE,BB.Color8(0x55),BB.Color8(0xcf)
    K.tile,K.rule=BB.Color8(0xec),BB.Color8(0x8c)
    function K.px(n) return math.floor(n*K.scale+.5) end
    function K.canvas(w,h) return Overlap:new{dimen=Geom:new{w=w,h=h},allow_mirroring=false} end
    function K.put(c,child,x,y) child.overlap_offset={math.floor(x),math.floor(y)};c[#c+1]=child;return child end
    function K.text(o)
        local size=type(o.size)=="number" and o.size or K.tokens.type[o.size or "body"]
        -- Font:getFace scales point sizes by DPI; our layout is already in pixels.
        local face=Font:getFace(K.tokens.face[o.serif and "display" or "ui"],K.px(size)*1000/Device.screen:scaleBySize(1000))
        return Text:new{text=tostring(o.text or ""),face=face,max_width=math.max(1,o.w),
            fgcolor=o.ink and K.white or o.muted and K.gray or K.black,bold=o.bold or false}
    end
    function K.label(c,text,x,y,w,size,opts)
        opts=opts or {};opts.text,opts.w,opts.size=text,w,size
        return K.put(c,K.text(opts),x,y)
    end
    function K.frame(c,o)
        local b=o.border or 0
        return Frame:new{padding=-b,margin=0,bordersize=b,radius=o.radius or 0,
            background=not o.transparent and (o.background or (o.ink and K.black or K.white)) or nil,color=o.color or K.black,
            width=o.w,height=o.h,c}
    end
    -- InputContainer supplies real hit testing and propagates child input. The callback
    -- is also exposed for keyboard adapters and the native acceptance driver.
    function K.hit(c,o)
        local Hit=Input:extend{}
        function Hit:onKitTap() if self.enabled~=false and self.callback then self.callback();return true end end
        local range=Geom:new{x=0,y=0,w=o.w,h=o.h}
        return Hit:new{dimen=range,width=o.w,height=o.h,text=o.text,
            callback=o.callback,enabled=o.enabled~=false,
            ges_events={KitTap={Gesture:new{ges="tap",range=range}}},c}
    end
    function K.button(o)
        local w,h=o.w,o.h or K.px(K.tokens.tap)
        local c=K.canvas(w,h)
        local inverted=o.variant=="inverted"
        local ink=o.ink or (o.variant~="outline" and o.variant~="ghost" and not inverted and o.enabled~=false)
        local iconW=o.icon and K.px(o.iconSize or 18) or 0;local gap=o.icon and K.px(9) or 0
        local endW=o.trailingIcon and K.px(16) or 0;local endGap=o.trailingIcon and K.px(4) or 0
        local count=o.count~=nil and (o.countText or K.formatCount(o.count)..(o.countSuffix or "")) or nil
        local detail=count and K.text{text=count,w=w-K.px(32),size=o.size or "body",muted=true} or nil
        local detailW=detail and detail:getSize().w+K.px(9) or 0
        local t=K.text{text=o.text,w=w-K.px(32)-iconW-gap-detailW-endW-endGap,size=o.size or "body",bold=o.bold~=false,ink=ink,muted=o.enabled==false}
        local left=o.align=="left" and K.px(13) or math.max(K.px(8),(w-t:getSize().w-iconW-gap-detailW-endW-endGap)/2)
        if o.icon then K.put(c,K.icon{name=o.icon,w=iconW,ink=ink},left,(h-iconW)/2) end
        K.put(c,t,left+iconW+gap,(h-t:getSize().h)/2)
        if detail then K.put(c,detail,left+iconW+gap+t:getSize().w+K.px(9),(h-detail:getSize().h)/2) end
        if o.trailingIcon then K.put(c,K.icon{name=o.trailingIcon,w=endW,ink=ink},left+iconW+gap+t:getSize().w+detailW+endGap,(h-endW)/2) end
        return K.hit(K.frame(c,{w=w,h=h,radius=o.radius or math.floor(h/2),border=o.variant=="ghost" and 0 or K.px(1.5),
            color=inverted and K.white or nil,ink=ink,transparent=o.variant=="ghost"}),
            {w=w,h=h,text=o.text,callback=o.callback,enabled=o.enabled})
    end
    function K.formatCount(n)
        local value=tostring(n);local changed
        repeat value,changed=value:gsub("^(%-?%d+)(%d%d%d)","%1,%2") until changed==0
        return value
    end
    -- Additive factory: the count remains a separately styled UI label.
    function K.search(o)
        local options={};for k,v in pairs(o) do options[k]=v end
        options.text=options.text or "Search";options.icon="search";options.iconSize=20
        options.variant="outline";options.align="left";options.bold=true;options.size="small"
        options.countSuffix=options.countSuffix or " books"
        return K.button(options)
    end
    function K.icon(o)
        if K.icons[o.name] then
            return require("ui/widget/imagewidget"):new{file=SOURCE_DIR.."/ko/ui/icons/"..o.name..".svg",width=o.w,height=o.h or o.w,is_icon=true,alpha=not o.ink,invert=o.ink}
        end
        return require("ui/widget/iconwidget"):new{icon=o.name or "book.opened",width=o.w,height=o.h or o.w,alpha=not o.ink,invert=o.ink}
    end
    function K.iconTile(o)
        local h=o.h or K.px(100);local c=K.canvas(o.w,h);local d=K.px(52)
        local circle=K.canvas(d,d);K.put(circle,K.icon{name=o.icon,w=K.px(26)},K.px(13),K.px(13))
        K.put(c,K.frame(circle,{w=d,h=d,radius=d/2,border=K.px(1.5)}),(o.w-d)/2,0)
        local t=K.text{text=o.text,w=o.w,size="small",bold=true}
        K.put(c,t,(o.w-t:getSize().w)/2,d+K.px(8))
        return K.hit(c,{w=o.w,h=h,text=o.text,callback=o.callback,enabled=o.enabled})
    end
    function K.card(o)
        local c=K.canvas(o.w,o.h);local pad=K.px(16)
        if o.title then K.label(c,o.title,pad,pad,o.w-2*pad-(o.all and K.px(90) or 0),"small",{bold=true,ink=o.ink}) end
        if o.all then K.put(c,K.button{text="All"..(o.count~=nil and " "..tostring(o.count) or ""),trailingIcon="chevR",w=K.px(90),h=K.px(52),variant="ghost",size="small",ink=o.ink,callback=o.all},o.w-pad-K.px(90),0) end
        local frame=K.frame(c,{w=o.w,h=o.h,radius=K.px(16),border=K.px(1),ink=o.ink,color=o.ink and K.black or K.rule})
        frame.content=c;return frame
    end
    function K.cover(o)
        local w=o.w;local h=o.h or math.floor(w/K.tokens.coverRatio)
        local c=K.canvas(w,h)
        if o.file then
            K.put(c,require("ui/widget/imagewidget"):new{file=o.file,width=w,height=h,scale_factor=0},0,0)
        else
            K.label(c,o.title or "Untitled",K.px(8),math.floor(h*.28),w-K.px(16),"small",{serif=true,bold=true})
            K.label(c,o.author or "BookSync",K.px(8),h-K.px(30),w-K.px(16),"caption",{muted=true})
        end
        return K.frame(c,{w=w,h=h,radius=K.px(3),border=K.px(1)})
    end
    function K.progress(o)
        local value=tonumber(o.value) or 0;if value~=value then value=0 end
        local w,h=o.w,o.h or K.px(5)
        local Progress=require("ui/widget/progresswidget"):extend{}
        local widget=Progress:new{width=w,height=h,percentage=math.max(0,math.min(1,value)),dimen=Geom:new{w=w,h=h}}
        function widget:paintTo(bb,x,y)
            local edge=math.min(K.px(1),math.floor(h/3))
            local track=o.ink and K.rule or K.white;local fill=o.ink and K.white or K.black
            bb:paintRoundedRect(x,y,w,h,fill,h/2)
            local iw,ih=w-2*edge,h-2*edge;local radius=ih/2
            if iw<=0 or ih<=0 then return end
            bb:paintRoundedRect(x+edge,y+edge,iw,ih,track,radius)
            -- Fill is clipped to the rounded inner track, including at 0 and 100%.
            local endX=math.floor(iw*self.percentage)
            for dy=0,ih-1 do
                local distance=math.abs(dy+.5-radius)
                local inset=math.max(0,math.ceil(radius-math.sqrt(math.max(0,radius*radius-distance*distance))-.5))
                local width=math.min(endX,iw-inset)-inset
                if width>0 then bb:paintRect(x+edge+inset,y+edge+dy,width,1,fill) end
            end
        end
        return widget
    end
    function K.segments(o)
        local h=o.h or K.px(52);local c=K.canvas(o.w,h);local gap=K.px(4);local n=#o.items
        for i,item in ipairs(o.items) do
            local x=math.floor((i-1)*o.w/n);local width=math.floor(i*o.w/n)-x
            K.put(c,K.button{text=item,w=width-gap,h=h-gap,radius=K.px(8),variant=i==o.selected and "solid" or "ghost",size="small",
                callback=function() if o.onChange then o.onChange(i) end end},x+gap/2,gap/2)
        end
        return K.frame(c,{w=o.w,h=h,radius=K.px(10),border=K.px(1.5)})
    end
    function K.toggle(o)
        local w,h=o.w or K.px(56),o.h or K.px(32);local c=K.canvas(w,h)
        local d=h-K.px(8);local knob=K.frame(K.canvas(d,d),{w=d,h=d,radius=d/2,ink=not o.value})
        K.put(c,knob,o.value and w-d-K.px(4) or K.px(4),K.px(4))
        return K.hit(K.frame(c,{w=w,h=h,radius=h/2,border=K.px(1.5),ink=o.value}),
            {w=w,h=h,text=o.text,callback=function() if o.onChange then o.onChange(not o.value) end end,enabled=o.enabled})
    end
    function K.slider(o)
        local h=K.px(52);local c=K.canvas(o.w,h);local d=K.px(24)
        local value=tonumber(o.value) or 0;if value~=value then value=0 end;value=math.max(0,math.min(1,value))
        K.put(c,K.progress{w=o.w,h=K.px(4),value=value},0,(h-K.px(4))/2)
        K.put(c,K.frame(K.canvas(d,d),{w=d,h=d,radius=d/2,border=K.px(1.5)}),(o.w-d)*value,(h-d)/2)
        local hit=K.hit(c,{w=o.w,h=h,text=o.text,enabled=o.enabled})
        function hit:onKitTap(_,ges)
            if self.enabled==false or not ges or not ges.pos then return end
            local v=math.max(0,math.min(1,(ges.pos.x-self.dimen.x)/o.w))
            if o.onChange then o.onChange(v) end;return true
        end
        return hit
    end
    function K.row(o)
        local h=o.h or K.px(64);local c=K.canvas(o.w,h);local x=0
        if o.icon then
            local d=K.px(32);local well=K.canvas(d,d)
            K.put(well,K.icon{name=o.icon,w=K.px(18)},K.px(7),K.px(7))
            K.put(c,K.frame(well,{w=d,h=d,radius=K.px(9),background=K.tile}),0,(h-d)/2)
            x=d+K.px(11)
        end
        local text=K.text{text=o.text,w=o.w-x-K.px(78),size="small",bold=true}
        K.put(c,text,x,o.sub and (h-K.px(42))/2 or (h-text:getSize().h)/2)
        if o.sub then K.label(c,o.sub,x,(h+K.px(4))/2,o.w-x-K.px(78),"caption",{muted=true}) end
        local detail=o.count~=nil and K.formatCount(o.count) or o.detail and tostring(o.detail):gsub("%s*›$","")
        if detail then
            local count=K.text{text=detail,w=K.px(60),size="small",bold=true}
            K.put(c,count,o.w-K.px(28)-count:getSize().w,(h-count:getSize().h)/2)
        end
        K.put(c,K.icon{name="chevR",w=K.px(16)},o.w-K.px(16),(h-K.px(16))/2)
        return K.hit(c,{w=o.w,h=h,text=o.text,callback=o.callback,enabled=o.enabled})
    end
    return K
end
