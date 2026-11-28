-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Settings and reader panel share the same editor and Library's device-local style API.
CustomReading = {}
local C=CustomReading
local Editor=EndSheet:extend{name="booksync_custom_reading",min_button=50}
function Editor:rows() return self.display_rows end
function Editor:init()
    EndSheet.init(self)
    -- M8C touch targets also accept keyboard Back and the initially focused + action.
    self.focus_action="+"
    self.key_events={Close={{"Back"}},StepMore={{"Right"}},StepLess={{"Left"}},Select={{"Press"}}}
end
function Editor:onStepMore() self.focus_action="+"; return self:onSelect() end
function Editor:onStepLess() self.focus_action="−"; return self:onSelect() end
function Editor:onSelect()
    Library.readingSave(ReadingStyle.step(Library.readingCustom("reading-custom-" .. self.key),self.key,self.focus_action=="−" and -1 or 1),self.ui,"reading-custom-" .. self.key)
    self:refresh(); return true
end
function Editor:onClose() C.close(); return true end
function Editor:onTapAnywhere() return false end
function C.close()
    local e=C.editor; if not e then return end
    C.editor=nil; UIManager:close(e)
    if e.return_to then e.return_to() end
end
function Editor:rowWidget(block,w,h,mt)
    local r=block.row
    if block.kind=="footer" then
        local cells={}
        for _,cell in ipairs(block.items) do cells[#cells+1]={text=cell.text,callback=cell.action,height=mt.button,text_font_size=18} end
        return require("ui/widget/buttontable"):new{width=w,buttons={cells},zero_sep=true}
    elseif r and r.fontIndex then
        local _,path=Library.readingFace(r.fontIndex,r.face)
        return require("ui/widget/button"):new{text=r.text,callback=r.action,width=w,height=math.max(50,h),
            text_font_face=path,text_font_size=20}
    elseif r and r.preview then
        local s=Library.readingCustom("reading-custom-" .. self.key)
        local Font=require("ui/font")
        local _,path,index=Library.readingFace(s.fontIndex,s.face)
        local gutter=self.key=="margins" and math.floor(s.margins*w/require("device").screen:getWidth()) or 12
        local BB=require("ffi/blitbuffer")
        local face=Font:getFace(path,Device.screen:getWidth()/702*16*1000/Device.screen:scaleBySize(1000),index)
        local delta=self.key=="font" and s.weight or self.key=="contrast" and s.contrast*3 or 0
        -- A private face keeps the cached UI font unchanged. Give each positive step a
        -- distinct synthesis strength, and negative steps a lighter preview ink.
        if delta>0 and face.ftsize and face.ftsize.getEmboldenHalfStrength then
            local copy={}; for k,v in pairs(face) do copy[k]=v end
            face=setmetatable(copy,getmetatable(face))
            face.hash=tostring(face.hash) .. "-booksync-" .. delta
            face.is_real_bold=false
            face.embolden_half_strength=face.ftsize:getEmboldenHalfStrength(3/8*delta)
            local fallback=face.getFallbackFont
            face.getFallbackFont=function(num)
                if not num or num==0 then return face end
                return fallback and fallback(num)
            end
        end
        local ink=delta<0 and BB.Color8 and BB.Color8(math.floor(math.min(200,-delta*60))) or BB.COLOR_BLACK
        local scale=Device.screen:getWidth()/702
        local border,padding=math.max(1,math.floor(scale)),math.floor(8*scale)
        local preview=require("ui/widget/textboxwidget"):new{
            text="She sat down on the iron bench with the book open on her knees. There were things she knew and things she did not.",
            face=face,_face_adjusted=true,width=math.max(1,w-2*gutter-2*border-2*padding),
            line_height=self.key=="spacing" and s.spacing-1 or .35,
            bold=false,fgcolor=ink}
        return require("ui/widget/container/framecontainer"):new{width=w,height=math.floor(68*scale),radius=math.floor(10*scale),bordersize=border,margin=0,padding=0,padding_left=gutter,padding_right=gutter,
            background=self.key=="margins" and BB.COLOR_LIGHT_GRAY or BB.COLOR_WHITE,
            require("ui/widget/container/framecontainer"):new{bordersize=0,margin=0,padding=padding,background=BB.COLOR_WHITE,preview}}
    end
    return EndSheet.rowWidget(self,block,w,h,mt)
end
function Editor:build()
    local finish=Budgets.span("reading-custom-" .. self.key .. ".paint",now_s,log)
    local record=Library.readingCustom("reading-custom-" .. self.key)
    local rows={{kind="title",text="Custom " .. ReadingStyle.names[self.key]:lower()},
        {kind="notice",text="Changes apply straight away."}}
    if self.key=="font" then
        if record.face then
            rows[#rows+1]={kind="button",fontIndex=record.fontIndex,face=record.face,
                text="● " .. record.face .. " (copied)",action=function() end}
        end
        for i,f in ipairs(ReadingStyle.fonts) do
            rows[#rows+1]={kind="button",fontIndex=i,text=(record.fontIndex==i and not record.face and "● " or "○ ") .. f.name,
                action=function() local s=Library.readingCustom("reading-custom-" .. self.key); s.fontIndex=i; s.face=nil; Library.readingSave(s,self.ui,"reading-custom-" .. self.key); self:refresh() end}
        end
    end
    local function step(d) Library.readingSave(ReadingStyle.step(Library.readingCustom("reading-custom-" .. self.key),self.key,d),self.ui,"reading-custom-" .. self.key); self:refresh() end
    rows[#rows+1]={kind="footer",text="−",action=function() step(-1) end}
    rows[#rows+1]={kind="footer",text=self.key=="font" and string.format("Weight %+d",record.weight) or ReadingStyle.label(record,self.key),action=function() end}
    rows[#rows+1]={kind="footer",text="+",action=function() step(1) end}
    rows[#rows+1]={kind="label",preview=true,text="Live preview"}
    rows[#rows+1]={kind="button",text="Done",action=function() C.close() end}
    self.display_rows=rows
    local b=Budgets.get("screens","reading-custom-" .. self.key)
    assert(#rows<=b.rows,"Custom editor row budget exceeded")
    assert(Budgets.check(b,{rows=#rows,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}))
    local K=BookSyncUI.new();local p=K.px
    local choices={}
    for _,r in ipairs(rows) do if r.fontIndex then
        local selected=r.text:find("^● ")~=nil
        choices[#choices+1]={text=r.text:gsub("^● ",""):gsub("^○ ",""),radio=selected,bold=selected,callback=r.action,h=p(52),size="body",rule=true,serif=r.fontIndex~=4}
    end end
    self[1]=SettingsPage.new{title=rows[1].text,subtitle="Used when you pick Custom in the reading panel. Changes apply straight away.",
        modal=true,startY=p(76),w=p(self.key=="margins" and 640 or 598),h=p(self.key=="font" and (#choices*52+312) or 306),rows=choices,onBack=function() C.close() end,
        content=function(_,c,w,y,put)
            local stepY=y+p(12)
            K.label(c,self.key=="font" and "Weight" or ({spacing="Line height",contrast="Ink strength",margins="Side margins"})[self.key],p(24),stepY+p(13),p(240),"body",{bold=true})
            put(K.button{text="−",w=p(52),variant="outline",callback=function() step(-1) end},w-p(270),stepY,"less")
            K.label(c,self.key=="font" and string.format("Weight %+d",record.weight) or ReadingStyle.label(record,self.key),w-p(203),stepY+p(12),p(135),"body",{bold=true})
            put(K.button{text="+",w=p(52),variant="outline",callback=function() step(1) end},w-p(76),stepY,"more")
            local preview=self:rowWidget({row={preview=true}},w-p(48),p(90),self.metrics)
            put(preview,p(24),stepY+p(64),"preview")
            put(K.button{text="Done",w=p(84),variant=self.key=="margins" and "outline" or nil,callback=function() C.close() end},p(24),stepY+p(145),"done")
        end}
    finish()
end
function Editor:refresh()
    local previous=self[1]
    self:build()
    if previous and previous.free then previous:free() end
    UIManager:setDirty(self,"ui")
end
function C.open(key,ui,return_to)
    assert(ReadingStyle.names[key],"Unknown Custom editor")
    C.editor=Editor:new{key=key,ui=ui,return_to=return_to}
    UIManager:show(C.editor) -- gate: user action (Custom reading editor)
end
function C.copy(ui,menu)
    local finish=Budgets.span("reading-copy.paint",now_s,log)
    local previous=Library.readingCopy(ui)
    local function refresh()
        if menu and menu.updateItems then menu:updateItems(menu.page,"booksync-reading-copy") end
    end
    refresh()
    if C.copy_toast then UIManager:close(C.copy_toast) end
    local dialog
    local function close()
        if C.copy_toast~=dialog then return end
        C.copy_toast=nil; UIManager:close(dialog)
    end
    dialog=require("ui/widget/buttondialog"):new{title="Copied once from KOReader into Custom",
        modal=false,width_factor=.8,
        buttons={{{text="Undo",height=50,callback=function()
            if C.copy_toast~=dialog then return end
            Library.readingSave(previous,ui); close(); refresh()
        end}, {text="Done",height=50,callback=close}}},tap_close_callback=function() C.copy_toast=nil end}
    C.copy_toast=dialog
    assert(Budgets.check(Budgets.get("screens","reading-copy"),{rows=3,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}))
    UIManager:show(dialog) -- gate: user action (one-time style copy with Undo)
    UIManager:scheduleIn(6,close) -- dismiss only; never opens or returns to a surface
    finish()
end
function C.settingsRows(ui)
    local rows={}
    for _,key in ipairs(ReadingStyle.keys) do
        local choices={}
        -- Pair choices stay in the already-open Settings submenu.
        for a=1,(key=="font" and 1 or #ReadingStyle.presets[key]-1) do for b=a+1,#ReadingStyle.presets[key] do
            local selected={a,b}
            choices[#choices+1]={text=ReadingStyle.presets[key][a][1] .. " / " .. ReadingStyle.presets[key][b][1],radio=true,
                checked_func=function() local p=ReadingStyle.pair(key,Library.settings.read("reading_pairs")); return p[1]==a and p[2]==b end,
                callback=function() Library.settings.writePair(key,selected) end}
        end end
        rows[#rows+1]={text_func=function()
            local p=ReadingStyle.pair(key,Library.settings.read("reading_pairs"))
            return (key=="margins" and "Margin" or ReadingStyle.names[key]) .. " choices: " .. (key=="font" and ReadingStyle.presets[key][p[2]][1] or ReadingStyle.presets[key][p[1]][1] .. " and " .. ReadingStyle.presets[key][p[2]][1])
        end,sub=key=="font" and "The panel shows Book’s own · Literary · Custom" or nil,sub_item_table=choices}
        rows[#rows+1]={menu_item_id="booksync-custom-" .. key,text_func=function() return "Custom " .. ReadingStyle.names[key]:lower() .. ": " .. ReadingStyle.label(Library.readingCustom(),key) end,
            sub=key=="font" and "Pick the font and its weight" or nil,callback=function(menu)
                C.open(key,ui,function()
                    -- Keep the originating menu and its selected row alive under the editor.
                    if menu and menu.updateItems then menu:updateItems(menu.page,"booksync-custom-" .. key) end
                end)
            end,keep_menu_open=true}
    end
    rows[#rows+1]={menu_item_id="booksync-reading-copy",text="Use KOReader's current values",help_text="Copies once into Custom. Later changes there don't follow.",
        callback=function(menu) C.copy(ui,menu) end,keep_menu_open=true}
    return rows
end
function C.panelRows(ui,refresh,screen)
    screen=screen or "reader-bottom-panel"
    if not Library.readingSupported(ui) then return {} end
    local rows={}
    local selected=Library.readingChoices(ui)
    for _,key in ipairs(ReadingStyle.keys) do
        local pair=ReadingStyle.pair(key,Library.settings.read("reading_pairs"))
        local cells={}
        for _,choice in ipairs({pair[1],pair[2],"custom"}) do
            local custom=choice=="custom"
            local label=custom and ("Custom · " .. ReadingStyle.label(Library.readingCustom(screen),key)) or ReadingStyle.presets[key][choice][1]
            local prefix=selected[key]==choice and "✓ " or ""
            local suffix=custom and selected[key]==choice and " ✎" or ""
            cells[#cells+1]={text=prefix .. ReadingStyle.names[key] .. "\n" .. label .. suffix,
                display_text=prefix .. label .. suffix,
                callback=function()
                    if ReadingStyle.tap(selected[key],choice)=="edit" then C.open(key,ui,refresh)
                    else Library.readingApply(ui,key,choice,nil,screen); refresh() end
                end}
        end
        rows[#rows+1]={kind="reading-choices",group_label=ReadingStyle.names[key],key=key,choices=cells}
    end
    return rows
end
