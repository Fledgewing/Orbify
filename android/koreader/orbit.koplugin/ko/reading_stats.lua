-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Host supplies one immutable reading.stats snapshot, placement pixels and grid height.
-- No reads, timers or dispatch: the library/host owns batching and invalidation.
ReadingStatsWidgets = {}
function ReadingStatsWidgets.render(id, snapshot, placement)
    local finish=Budgets.span(id..'.render',now_s,log)
    local budget=Budgets.get('widgets',id)
    local bytes=placement.snapshotBytes or #UIUtil.encode(snapshot or {})
    assert(Budgets.check(budget,{rows=1,bytes=bytes,snapshotBytes=bytes,spawns=0,network=0,roundTrips=0}))
    local nativeScale=Device and Device.screen:scaleBySize(100)/100 or 1
    -- The approved M8C canvas is 702 CSS pixels wide. KOReader's DPI scale
    -- differs from that design unit; convert faces once, without fitting fonts down.
    local scale=Device and Device.screen.getWidth and math.min(nativeScale,math.max(1,Device.screen:getWidth()/702)) or nativeScale
    local width,height=placement.w/scale,placement.h/scale
    local Widget = require('ui/widget/widget')
    local Geom = require('ui/geometry')
    local Font = require('ui/font')
    local Text = require('ui/widget/textwidget')
    local BB = require('ffi/blitbuffer')
    local widget=Widget:new{dimen=Geom:new{w=placement.w,h=placement.h}}
    local texts={}
    local function native(value,bold,size,maxWidth)
        return Text:new{text=tostring(value),face=Font:getFace('NotoSans-Regular.ttf',size*scale/nativeScale),
            bold=bold,fgcolor=bold and BB.COLOR_BLACK or (BB.COLOR_GRAY_5 or BB.COLOR_DARK_GRAY),padding=0,max_width=nil}
    end
    local function measure(value,size,bold,maxWidth)
        local t=native(value,bold,size,maxWidth or width-32)
        local bounds=t:getSize()
        local result={w=bounds.w/scale,h=bounds.h/scale}
        t:free()
        return result
    end
    local function text(x,y,value,bold,size,maxWidth)
        local t=native(value,bold,size or 12,math.min(maxWidth or width-32,width-x-8))
        local bounds=t:getSize()
        local box={x=math.floor(x*scale),y=math.floor(y*scale),w=bounds.w,h=bounds.h,widget=t}
        local fits=bounds.w<=math.max(1,(maxWidth or width-x-8)*scale) and box.x>=0 and box.y>=0 and box.x+box.w<=placement.w-4*scale and box.y+box.h<=placement.h-4*scale
        for _,other in ipairs(texts) do
            if box.x<other.x+other.w+2*scale and other.x<box.x+box.w+2*scale
                and box.y<other.y+other.h+2*scale and other.y<box.y+box.h+2*scale then fits=false end
        end
        if not fits then t:free();return nil end
        texts[#texts+1]=box
        return box
    end
    -- Keep the native measured bounds all the way through painting. Optional
    -- labels are omitted when their column or remaining height cannot hold them.
    local plan=ReadingStatsPlan.build(id,snapshot,width,height,placement.rows)
    local title=text(16,12,plan.title,true,14)
    local headerBottom=title and (title.y+title.h)/scale or 12
    if plan.source then
        local source
        local inlineX=title and (title.x+title.w)/scale+12 or width
        if width-inlineX-16>=measure(plan.source,11,false,width).w then
            source=text(inlineX,12,plan.source,false,11,width-inlineX-16)
        else source=text(16,headerBottom+4,plan.source,false,11) end
        if source then headerBottom=math.max(headerBottom,(source.y+source.h)/scale) end
    end
    plan=ReadingStatsPlan.build(id,snapshot,width,height,placement.rows,headerBottom+12,measure)
    if plan.message then text(16,headerBottom+12,plan.message,false,12) end
    for _,v in ipairs(plan.labels) do text(v.x,v.y,v.text,v.bold,v.size,v.width) end
    widget.stats_texts=texts
    widget.stats_plan=plan
    local icons={}
    for _,v in ipairs(plan.icons or {}) do
        icons[#icons+1]={x=v.x*scale,y=v.y*scale,widget=require('ui/widget/imagewidget'):new{file=SOURCE_DIR..'/ko/ui/icons/'..v.name..'.svg',width=v.w*scale,height=v.w*scale,is_icon=true,alpha=true}}
    end
    local colors={BB.COLOR_WHITE,BB.COLOR_LIGHT_GRAY,BB.COLOR_GRAY,BB.COLOR_DARK_GRAY,BB.COLOR_BLACK}
    function widget:paintTo(bb,x,y)
        local done=Budgets.span(id..'.paint',now_s,log)
        bb:paintRect(x,y,self.dimen.w,self.dimen.h,BB.COLOR_WHITE)
        if bb.paintBorder then bb:paintBorder(x,y,self.dimen.w,self.dimen.h,math.max(1,math.floor(scale)),BB.COLOR_DARK_GRAY,math.floor(16*scale),true) end
        for _,r in ipairs(plan.rects) do
            bb:paintRect(x+math.floor(r.x*scale),y+math.floor(r.y*scale),math.max(0,math.min(math.floor(r.w*scale),placement.w-math.floor(r.x*scale))),math.max(0,math.min(math.floor(r.h*scale),placement.h-math.floor(r.y*scale))),colors[r.level+1])
            if r.outline or r.level==0 and r.w>=1 and r.h>=1 then
                local color=r.outline and BB.COLOR_BLACK or BB.COLOR_LIGHT_GRAY
                local rx,ry,rw,rh=x+math.floor(r.x*scale),y+math.floor(r.y*scale),math.max(1,math.floor(r.w*scale)),math.max(1,math.floor(r.h*scale))
                bb:paintRect(rx,ry,rw,1,color); bb:paintRect(rx,ry+rh-1,rw,1,color)
                bb:paintRect(rx,ry,1,rh,color); bb:paintRect(rx+rw-1,ry,1,rh,color)
            end
        end
        for _,v in ipairs(plan.dots or {}) do
            bb:paintRoundedRect(x+v.x*scale,y+v.y*scale,v.d*scale,v.d*scale,colors[v.level+1],v.d*scale/2)
        end
        for _,v in ipairs(icons) do v.widget:paintTo(bb,x+v.x,y+v.y) end
        for _,t in ipairs(texts) do t.widget:paintTo(bb,x+math.floor(t.x),y+math.floor(t.y)) end
        done()
    end
    function widget:free() for _,t in ipairs(texts) do t.widget:free() end;for _,v in ipairs(icons) do v.widget:free() end end
    finish()
    return widget
end
for _,id in ipairs({'year-in-reading','this-week','when-you-read','reading-records','today','reading-streak','reading-goal','pages-read','monthly-reading'}) do
    local name=id
    WidgetRegistry[name].renderers=WidgetRegistry[name].renderers or {}
    WidgetRegistry[name].renderers['android-tablet']=function(snapshot,placement)
        return ReadingStatsWidgets.render(name,snapshot,placement)
    end
end
