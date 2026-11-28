-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Shared entry for owned lists, Search and Custom filter configuration. No catalog records.
FilterView = {}
function FilterView.new(context)
    context=context or {}
    local model=FilterSheet.new(context)
    return setmetatable({model=model,exclude_current=context.exclude_current,onApply=context.onApply,onChange=context.onChange,
        onSave=context.onSave,title=context.title or "Library",sorts=context.sorts or
            (model.defaults.sort=="match" and {"match","title","author","added","rating"} or
                model.defaults.sort=="series" and {"series","title","author","last","added","rating"} or {"order","title","author","last","added","rating"}),
        alive=false}, {__index=FilterView})
end
function FilterView:header(total)
    local p=self.model:presentation(total)
    for _,chip in ipairs(p.chips) do
        chip.callback=function() self.model:clear(chip.key,chip.value); self:changed() end
    end
    p.callback=function() self:show() end
    return p
end
function FilterView:changed()
    self.model.offset=0
    if self.onChange then self.onChange(Layout.copy(self.model.query)) end
    if self.alive then self:paint() end
end
function FilterView:close(apply)
    self.alive=false
    if self.retry then UIManager:unschedule(self.retry); self.retry=nil end
    if self.dialog then UIManager:close(self.dialog); self.dialog=nil end
    if apply and self.onApply then self.onApply(Layout.copy(self.model.query)) end
end
function FilterView:show()
    Gate.show("filter sheet", function()
        self.alive=true; self.model.pick=nil; self:paint()
    end) -- gate: Gate.show, explicit filter action
end
function FilterView:back()
    if self.model.pick then self.model.pick=nil; self.model.offset=0; self:paint()
    else self:close(true) end
end
-- One bounded cached read, followed by at most one worker batch. A miss never becomes zero.
function FilterView:read()
    local paint=Library.paint(self.model.pick and "filter-picker" or "filter")
    local result
    if self.model.pick and self.model.pick~="gs" then
        result=paint:facets(self.model.source,self.model.query,self.model.pick,self.model.offset,FilterSheet.PAGE_SIZE,self.exclude_current)
    else
        result=paint:read("counts",{source=self.model.source,query=self.model.query,limit=1,exclude_current=self.exclude_current})
    end
    paint:flush()
    return result
end
function FilterView:paint(attempt)
    if not self.alive then return end
    local finish=Budgets.span("filter.draw",now_s,log)
    if self.retry then UIManager:unschedule(self.retry); self.retry=nil end
    local result=self:read()
    local saved=result.freshness and result.freshness.saved
    self.total=saved and result.total or nil
    local buttons={}
    local focus
    local function row(text, action, bold, id, detail, muted)
        local b={text=text,callback=action,font_bold=bold or false,align="left",id=id,detail=detail,muted=muted}
        buttons[#buttons+1]={b}; return b
    end
    local m=self.model
    if m.pick=="gs" then
        local function choices(field, values, title)
            for _,value in ipairs(values) do
                local text=title .. ": " .. (m.query[field]==value and "● " or "○ ") ..
                    (field=="group" and (value=="none" and "Not grouped" or "By " .. value) or value)
                row(text,function() m.query[field]=value; self:changed() end,m.query[field]==value)
            end
        end
        choices("group",{"none","author","series"},"Group")
        choices("sort",self.sorts,"Sort by")
        choices("dir",{"asc","desc"},"Order")
    elseif m.pick then
        for i,option in ipairs(result.items or {}) do
            local display=FilterSheet.option(option,FilterSheet.MULTI[m.pick])
            if option.selected and not focus then focus=i end
            row(display.text,function()
                m:choose(m.pick,option)
                if not FilterSheet.MULTI[m.pick] then m.pick=nil; m.offset=0 end
                self:changed()
            end,option.selected,"option-" .. i,nil,display.gray)
        end
        if not saved or result.error then row(result.error and "Filter unavailable" or "Counting…",function() self:paint() end) end
        if FilterSheet.MULTI[m.pick] then
            local n=#(m.query[m.pick] or {})
            row("Clear " .. n,function() m:clear(m.pick); self:changed() end)
        end
    else
        for _,r in ipairs(m:rows()) do
            local b=row(r.label,function()
                m.pick=r.key; m.offset=0; self:paint()
            end,r.changed,nil,(r.changed and "●  " or "")..r.value)
            if r.divider then table.insert(buttons,#buttons,{}) end -- thin divider, no heading
        end
        local b=row("+ Save as a Book list on Home",function()
            if self.onSave then
                local saved=self.onSave({source="custom-filter",base_source=Layout.copy(m.source),query=Layout.copy(m.query),exclude_current=self.exclude_current})
                if saved~=false then self:close(true) end
            end
        end)
        b.enabled=self.onSave~=nil
        buttons[#buttons+1]={{text="Reset",callback=function() m:reset(); self:changed() end},
            {text=self.total~=nil and ("Show " .. self.total .. " books") or "Counting…",callback=function() self:close(true) end}}
    end
    local nav={{text=m.pick and "‹ Filter" or "Close",callback=function() self:back() end}}
    if m.pick and m.pick~="gs" and ((result.option_total or 0)>FilterSheet.PAGE_SIZE or m.offset>0) then
        nav[#nav+1]={text="‹",enabled=m.offset>0,callback=function() m.offset=math.max(0,m.offset-FilterSheet.PAGE_SIZE); self:paint() end}
        nav[#nav+1]={text="Page " .. (math.floor(m.offset/FilterSheet.PAGE_SIZE)+1) .. " of " .. math.ceil((result.option_total or 0)/FilterSheet.PAGE_SIZE),enabled=false,callback=function() end}
        nav[#nav+1]={text="›",enabled=result.next~=nil,callback=function() m.offset=result.next or m.offset; self:paint() end}
    end
    buttons[#buttons+1]=nav
    local screen=require("device").screen
    local K=CatalogUI.kit();local p=K.px
    local w,h=screen:getWidth(),screen:getHeight()
    local sw,sh=w-p(64),h-p(76)
    local c=K.canvas(sw,sh)
    K.action(c,"Filter","filter",p(18),p(14),p(34),p(48),function() self:back() end)
    K.label(c,m.pick and (FilterSheet.LABELS[m.pick] or "Group & sort") or "Filter",p(54),p(17),sw-p(120),"medium",{bold=true})
    K.label(c,self.title,p(54),p(43),sw-p(120),"caption")
    K.action(c,"Close","x",sw-p(62),p(14),p(52),p(52),function() self:back() end)
    K.separator(c,0,p(76),sw)
    local body={}
    -- The last two root rows are Save and Reset/Apply; navigation lives in the header.
    for i,line in ipairs(buttons) do
        if #line>0 and i<#buttons and (m.pick or i<#buttons-2) then
            for _,b in ipairs(line) do body[#body+1]=b end
        end
    end
    local bodyH=sh-p(m.pick and 144 or 220)
    local rh=math.min(p(64),math.floor(bodyH/math.max(1,#body)))
    for i,b in ipairs(body) do
        local y=p(76)+(i-1)*rh
        if b.text=="Group & sort" then K.separator(c,p(22),y-p(8),sw-p(44),true) end
        local row=K.canvas(sw-p(44),rh)
        K.label(row,b.text,0,math.floor((rh-p(24))/2),b.detail and p(200) or sw-p(74),"body",{bold=b.font_bold or b.detail~=nil,muted=b.muted})
        if b.detail then
            local t=K.text{text=b.detail,w=sw-p(264),size="small",bold=b.font_bold}
            K.put(row,t,sw-p(74)-t:getSize().w,math.floor((rh-t:getSize().h)/2))
        end
        K.label(row,"›",sw-p(60),math.floor((rh-p(24))/2),p(18),"body")
        K.separator(row,0,rh-p(1),sw-p(44))
        K.put(c,K.hit(row,{text=b.text,w=sw-p(44),h=rh,callback=b.callback,enabled=b.enabled}),p(22),y)
    end
    if not m.pick then
        K.separator(c,0,sh-p(132),sw)
        local save=buttons[#buttons-2][1]
        K.put(c,K.button{text=save.text,w=sw-p(44),h=p(52),variant="ghost",enabled=save.enabled,callback=save.callback},p(22),sh-p(132))
        local actions=buttons[#buttons-1]
        K.put(c,K.button{text="Reset",w=p(80),variant="outline",callback=actions[1].callback},p(22),sh-p(66))
        K.put(c,K.button{text=actions[2].text,w=sw-p(134),callback=actions[2].callback},p(112),sh-p(66))
    else
        K.put(c,K.button{text="‹ Filter",w=p(130),variant="outline",callback=function() self:back() end},p(22),sh-p(66))
        if #nav>1 then
            K.action(c,"Previous","arrowL",sw-p(136),sh-p(66),p(52),p(52),nav[2].callback,nav[2].enabled,true)
            K.action(c,"Next","arrowR",sw-p(74),sh-p(66),p(52),p(52),nav[4].callback,nav[4].enabled,true)
        end
    end
    local full=K.canvas(w,h)
    K.put(full,K.frame(c,{w=sw,h=sh,border=p(2),radius=p(18)}),p(32),p(38))
    local Input=require("ui/widget/container/inputcontainer"):extend{name="booksync_filter"}
    local dialog=Input:new{dimen=require("ui/geometry"):new{w=w,h=h},full}
    dialog.buttons=buttons -- semantic actions also serve keyboard/test adapters
    dialog.onClose=function() self:back();return true end
    dialog.key_events={Close={{"Back"}}}
    if self.dialog then UIManager:close(self.dialog) end
    self.dialog=dialog
    Gate.show("filter paint",function()
        if self.alive and self.dialog==dialog then UIManager:show(dialog) end -- gate: Gate.show; visible initiating filter only
    end)
    if result.pending and (attempt or 0)<20 then
        self.retry=function()
            self.retry=nil
            if self.alive and not reading() then self:paint((attempt or 0)+1) end
        end
        UIManager:scheduleIn(0.5,self.retry)
    end
    finish()
end
