-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Snapshot-only UI. Home owns widget reads; this user-opened screen owns one bounded read.
BatteryUI = {}
function BatteryUI.glyph(canvas,fraction,x,y,w,h)
    local u=HomeWidgets.ui()
    local glyph=u.Progress:new{width=w,height=h,percentage=fraction,radius=0,margin_h=0,margin_v=0,
        fillcolor=u.BB.COLOR_BLACK,bgcolor=u.BB.COLOR_WHITE}
    local nativePaint=glyph.paintTo
    function glyph:paintTo(bb,px,py)
        if not bb.paintBorder or w>h*4 then return nativePaint(self,bb,px,py) end
        local border=math.max(1,math.floor(h/12))
        local tip=math.max(2,math.floor(w/12))
        local body=w-tip-border
        bb:paintRect(px,py,w,h,u.BB.COLOR_WHITE)
        bb:paintBorder(px,py,body,h,border,u.BB.COLOR_BLACK,border*2,true)
        bb:paintRect(px+body,py+math.floor(h*.3),tip,math.max(1,math.floor(h*.4)),u.BB.COLOR_BLACK)
        local inset=border*2
        bb:paintRect(px+inset,py+inset,math.max(0,math.floor((body-inset*2)*math.max(0,math.min(1,fraction)))),
            math.max(0,h-inset*2),u.BB.COLOR_BLACK)
    end
    HomeWidgets.put(canvas,glyph,x,y)
end
function BatteryUI.widget(p,snapshot,dispatch,rect)
    local finish=Budgets.span("battery.widget",now_s,log)
    local data=snapshot.data
    if snapshot.state=="loading" then data={pending=true}
    elseif snapshot.state=="error" then data={error=snapshot.error or "Unavailable"} end
    local plan=BatteryWidgetPlan.widget(data,p.w,p.h)
    local nativeScale=Device.screen:scaleBySize(100)/100
    local scale=Device.screen.getWidth and math.min(nativeScale,math.max(1,Device.screen:getWidth()/702)) or nativeScale
    local s=function(n) return n*scale end
    local faceSize=function(n) return n*scale/nativeScale end
    local w,h=rect.w-2,rect.h-2
    local c=HomeWidgets.canvas(w,h)
    local u=HomeWidgets.ui()
    local boxes={}
    local function text(value,x,y,width,size,bold)
        local t=u.Text:new{text=tostring(value or "—"),face=u.Font:getFace("NotoSans-Regular.ttf",faceSize(size)),
            bold=bold,fgcolor=bold and u.BB.COLOR_BLACK or (u.BB.COLOR_GRAY_5 or u.BB.COLOR_DARK_GRAY),padding=0,max_width=nil}
        local bounds=t:getSize()
        local box={x=x,y=y,w=bounds.w,h=bounds.h,widget=t}
        local fits=bounds.w<=math.max(1,width) and x>=0 and y>=0 and x+bounds.w<=w-s(8) and y+bounds.h<=h-s(8)
        for _,other in ipairs(boxes) do
            if x<other.x+other.w+s(2) and other.x<x+bounds.w+s(2)
                and y<other.y+other.h+s(2) and other.y<y+bounds.h+s(2) then fits=false end
        end
        if not fits then t:free();return nil end
        boxes[#boxes+1]=box
        HomeWidgets.put(c,t,x,y)
        return y+bounds.h
    end
    local narrow=p.w==1
    local short=p.h==1
    -- Title remains the navigation target. Its measured bounds reserve the header;
    -- every other line keeps its type size and is admitted in priority order.
    local title=u.Button:new{text="Battery ›",width=w-s(32),height=s(50),padding=0,bordersize=0,
        text_font_size=faceSize(14),text_font_face="tfont",align="left",avoid_text_truncation=false,callback=function() dispatch("battery") end}
    HomeWidgets.put(c,title,s(16),s(2))
    local titleProbe=u.Text:new{text="Battery ›",face=u.Font:getFace("tfont",faceSize(14)),max_width=w-s(16)}
    local titleHeight=titleProbe:getSize().h
    titleProbe:free()
    local header=s(2)+(s(50)+titleHeight)/2+s(4)
    local splitX=math.floor(w*.37)
    local levelX=s(52)
    local levelProbe=u.Text:new{padding=0,text=plan.level,face=u.Font:getFace("tfont",faceSize(short and 20 or 28))}
    local levelWidth=levelProbe:getSize().w
    levelProbe:free()
    splitX=math.max(splitX,levelX+levelWidth+s(12))
    local levelY=header
    local levelBottom=text(plan.level,levelX,levelY,levelWidth,short and 20 or 28,true) or header
    BatteryUI.glyph(c,plan.level_fraction,s(12),levelY+math.max(0,(levelBottom-levelY-s(16))/2),s(32),s(16))
    local x=narrow and s(12) or splitX
    local y=narrow and levelBottom+s(12) or header
    local contentBottom=levelBottom
    -- Only the three primary estimates belong beside the charge level. Measured
    -- rows below them get rates/history if space remains; no 8-point fallback.
    for i=1,math.min(3,#plan.lines) do
        local bottom=text(plan.lines[i],x,y,w-x-s(12),i==1 and 13 or 12,i==1)
        if bottom then y=bottom+s(4);contentBottom=math.max(contentBottom,bottom) end
    end
    y=contentBottom+s(10)
    if not narrow and not short then
        local d=BatteryWidgetPlan.display(data)
        local rates={BatteryWidgetPlan.compact(d.reading_rate,"reading_rate"),BatteryWidgetPlan.compact(d.standby_rate,"standby_rate"),BatteryWidgetPlan.compact(d.used_week,"used_week")}
        local cw=(w-s(24))/3
        local bottom=y
        for i=1,3 do
            if rates[i] then
                -- These are companion-formatted display strings, only split into
                -- typographic runs here; no battery estimate/rate is calculated.
                local caption,value=rates[i]:match("^(.-) · (.+)$")
                if i==3 then value=rates[i]:match("^(.-) used this week$") or rates[i];caption="used this week" end
                if value then
                    local last=text(value,s(12)+(i-1)*cw,y,cw-s(8),p.w>=4 and 19 or 16,true)
                    if last then
                        last=text(caption,s(12)+(i-1)*cw,last+s(3),cw-s(8),12,false) or last
                        bottom=math.max(bottom,last)
                    end
                else
                    local last=text(rates[i],s(12)+(i-1)*cw,y,cw-s(8),12,false)
                    bottom=math.max(bottom,last or y)
                end
            end
        end
        y=bottom+s(8)
        if d.last_charge then
            local value=BatteryWidgetPlan.compact(d.last_charge,"last_charge")
            local last=text(value,s(34),y,w-s(46),11,false)
            if last then HomeWidgets.put(c,require("ui/widget/imagewidget"):new{file=SOURCE_DIR.."/ko/ui/icons/charge.svg",width=s(18),height=s(18),is_icon=true,alpha=true},s(12),y) end
        end
    end
    finish()
    local frame=u.Frame:new{padding=0,margin=0,bordersize=1,radius=s(16),color=u.BB.COLOR_DARK_GRAY,c};frame.stats_texts=boxes;return frame
end
function BatteryUI.create()
    local Input=require("ui/widget/container/inputcontainer")
    local Geom=require("ui/geometry")
    local Page=Input:extend{name="booksync_battery",covers_fullscreen=true}
    function Page:init()
        self.tab,self.page=1,1
        self.dimen=Geom:new{w=Device.screen:getWidth(),h=Device.screen:getHeight()}
        self.key_events={Close={{"Back"}}}
        self:rebuild()
    end
    function Page:rebuild()
        local finish=Budgets.span("battery.render",now_s,log)
        if self.refresh then UIManager:unschedule(self.refresh); self.refresh=nil end
        local paint=Library.paint("battery")
        local result=paint:battery()
        self.metrics=paint:flush()
        local plan=BatteryWidgetPlan.page(result,self.tab,self.page)
        local s=function(n) return Device.screen:scaleBySize(n) end
        local w,h=self.dimen.w,self.dimen.h
        local c=HomeWidgets.canvas(w,h)
        HomeWidgets.text(c,"Battery · "..plan.level,s(16),s(12),w-s(180),24,false,true)
        BatteryUI.glyph(c,(result.level or 0)/100,w-s(164),s(22),s(44),s(18))
        HomeWidgets.button(c,"Close",w-s(100),s(8),s(90),s(50),function() self:onClose() end)
        HomeWidgets.text(c,plan.estimate,s(16),s(52),w-s(32),16,false,true)
        for i,title in ipairs(BatteryWidgetPlan.tabs) do
            HomeWidgets.button(c,(self.tab==i and "• " or "")..title,(i-1)*w/4,s(84),w/4,s(50),function()
                self.tab,self.page=i,1; self:rebuild(); UIManager:setDirty(self,"ui")
            end)
        end
        local step=math.min(s(58),math.floor((h-s(200))/math.max(1,#plan.rows)))
        for i,row in ipairs(plan.rows) do
            local y=s(140)+(i-1)*step
            HomeWidgets.put(c,require("ui/widget/textboxwidget"):new{
                text=type(row)=="table" and row.text or row,width=w-s(32),
                face=HomeWidgets.ui().Font:getFace("cfont",14)},s(16),y)
            if type(row)=="table" then BatteryUI.glyph(c,row.fraction,s(16),y+step-s(12),w-s(32),s(6)) end
        end
        if plan.pages>1 then
            HomeWidgets.button(c,"‹",s(16),h-s(52),s(80),s(50),function() self:turn(1) end)
            HomeWidgets.button(c,"›",w-s(96),h-s(52),s(80),s(50),function() self:turn(2) end)
            HomeWidgets.text(c,self.page.." / 2",w/2-s(20),h-s(42),s(80),16)
        end
        local old=self[1]
        self[1]=HomeWidgets.ui().Frame:new{padding=0,margin=0,bordersize=0,background=HomeWidgets.ui().BB.COLOR_WHITE,c}
        if old then old:free() end
        finish()
        -- Cold data may arrive after the page opens. Never reopen or steal reading focus.
        if result.pending and (self.attempts or 0)<5 then
            self.attempts=(self.attempts or 0)+1
            self.refresh=function()
                self.refresh=nil
                if UIManager:getTopmostVisibleWidget()==self then self:rebuild(); UIManager:setDirty(self,"ui") end
            end
            UIManager:scheduleIn(0.5,self.refresh)
        end
    end
    function Page:turn(page) self.page=page; self:rebuild(); UIManager:setDirty(self,"ui") end
    function Page:onCloseWidget()
        if BatteryUI.active==self then BatteryUI.active=nil end
        if self.refresh then UIManager:unschedule(self.refresh); self.refresh=nil end
    end
    function Page:onClose() self:onCloseWidget(); UIManager:close(self); return true end
    return Page:new{}
end
function BatteryUI.show()
    local problem=Library.companion.workerProblem(_("for Battery"))
    if problem then
        UIManager:show(InfoMessage:new{text=problem}) -- gate: user action (Battery)
        return false
    end
    if BatteryUI.active then UIManager:close(BatteryUI.active) end
    BatteryUI.opening=true
    local ok,page=pcall(BatteryUI.create)
    BatteryUI.opening=nil
    if not ok then error(page) end
    BatteryUI.active=page
    UIManager:show(page) -- gate: user action (Battery widget or Settings)
    return page
end
