-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Immutable Library values and explicit intents only. No scheduling or storage in UI.
RemindersUI={}
local function copy(row)
    local draft={}
    for _,key in ipairs({"kind","id","revision","enabled","minuteOfDay","days","message","intervalMinutes","title","detail","editable","sourceLabel"}) do draft[key]=row[key] end
    return draft
end
local function visible(view)
    return view and view.alive and UIManager:getTopmostVisibleWidget()==view.dialog
end
-- Reminder mockups use the approved 480-unit viewport; the shared kit owns
-- type, native font scaling, hit targets, borders and pill actions.
function RemindersUI.page(view,items,buttons,nav,pageSize)
    local K=BookSyncUI.new(Device.screen:getWidth()/480);local p=K.px
    local sw,sh=Device.screen:getWidth(),Device.screen:getHeight()
    local c=K.canvas(sw,sh);local widgets={}
    local function put(widget,x,y,id) K.put(c,widget,x,y);if id then widgets[id]=widget end end
    local function label(text,x,y,w,size,opts) return K.label(c,text,p(x),p(y),p(w),size,opts) end
    local function rule(y) put(K.frame(K.canvas(sw-p(36),p(1)),{w=sw-p(36),h=p(1),background=K.light}),p(18),y) end
    put(K.button{text="‹ Back",w=p(84),h=p(40),size=14,variant="outline",callback=function() view:back() end},p(16),p(10),"back")
    label("BookSync",116,10,340,18,{bold=true});label("Reader settings",116,33,340,12)
    put(K.frame(K.canvas(sw,p(1)),{w=sw,h=p(1),ink=true}),0,p(60));label(view.title,18,94,444,28,{serif=true,bold=true})
    local function paragraph(parent,text,x,y,w,size)
        local sample=K.text{text="",w=w,size=size}
        local block=require("ui/widget/textboxwidget"):new{text=text,width=w,face=sample.face}
        K.put(parent,block,x,y);sample:free();return block:getSize().h
    end
    local y=p(148)
    if view.notice then
        y=p(137)+paragraph(c,view.notice,p(18),p(137),p(444),14)+p(12)
    end
    local actions={}
    for j,line in ipairs(buttons) do
        if line~=nav then
            local row=items[view.offset+j];local b=line[1]
            if row.action then actions[#actions+1]={row=row,button=b}
            else
                local h=p(row.height or (row.note_func and 71 or 65))
                local rc=K.canvas(p(444),h)
                local title=row.kitText or row.text or ""
                local note=row.note_func and row.note_func() or row.kitSub
                local detail=row.kitDetail
                if row.checked_func then detail=row.checked_func() and "●" or "○" end
                local textHeight=paragraph(rc,title,p(9),p(note and 12 or 22),p(detail and 290 or 420),17)
                if note then textHeight=textHeight+p(8)+paragraph(rc,note,p(9),p(39),p(411),14) end
                h=math.max(h,textHeight+p(28));rc.dimen.h=h
                if detail then
                    local t=K.text{text=detail..(b.enabled and row.callback and not row.noChevron and " · ›" or ""),w=p(150),size=16}
                    K.put(rc,t,p(435)-t:getSize().w,p(23))
                end
                local hit=K.hit(rc,{w=p(444),h=h,text=b.text,callback=b.callback,enabled=b.enabled})
                put(hit,p(18),y,b.id);y=y+h;rule(y)
            end
        end
    end
    if view.reminderMeta then
        local info=view.reminderMeta()
        if info then y=y+p(10)+paragraph(c,info,p(18),y+p(10),p(444),14)+p(10) end
    end
    for _,action in ipairs(actions) do
        y=y+p(14);local row,b=action.row,action.button
        put(K.button{text=row.kitText or b.text,w=p(444),h=p(51),size=17,variant=row.primary and "solid" or "outline",enabled=b.enabled,callback=b.callback},p(18),y,b.id)
        y=y+p(51)
    end
    if #items>pageSize then
        local py=math.max(y+p(16),sh-p(118))
        put(K.button{text="‹",w=p(52),variant="outline",callback=nav[2].callback,enabled=nav[2].enabled},p(130),py,"previous")
        K.label(c,string.format("%d / %d",math.floor(view.offset/pageSize)+1,math.ceil(#items/pageSize)),p(212),py+p(14),p(80),14)
        put(K.button{text="›",w=p(52),variant="outline",callback=nav[4].callback,enabled=nav[4].enabled},p(298),py,"next")
    end
    put(K.frame(K.canvas(sw,p(1)),{w=sw,h=p(1),ink=true}),0,sh-p(49));K.label(c,"Tap a choice",p(16),sh-p(33),p(300),12)
    local Input=require("ui/widget/container/inputcontainer"):extend{name="booksync_reminders",covers_fullscreen=true}
    function Input:onClose() view:back();return true end
    function Input:getButtonById(id) return widgets[id] end
    function Input:moveFocusTo(x,y) self.focus={x,y} end
    return Input:new{title=view.title,dimen=require("ui/geometry"):new{w=sw,h=sh},key_events={Close={{"Back"}}},K.frame(c,{w=sw,h=sh})}
end

-- A single claimed occurrence, drawn over the untouched native page/Home.
function RemindersUI.sheet(o)
    local sw,sh=Device.screen:getWidth(),Device.screen:getHeight()
    local K=BookSyncUI.new(sw/480);local p=K.px
    local w=p(444);local c=K.canvas(w,sh);local widgets={}
    local y=p(24)
    K.label(c,o.managed and "MANAGED BY "..o.managed or "ON THIS DEVICE",p(24),y,w-p(48),12,{bold=true});y=y+p(25)
    K.label(c,o.interval and "Rest your eyes." or "Reminder",p(24),y,w-p(48),28,{serif=true,bold=true});y=y+p(44)
    local sample=K.text{text="",w=w-p(48),size=22}
    local text=require("ui/widget/textboxwidget"):new{text=o.message,width=w-p(48),face=sample.face}
    K.put(c,text,p(24),y);y=y+text:getSize().h+p(12);sample:free()
    for _,note in ipairs(o.notes) do
        K.label(c,note,p(24),y,w-p(48),14);y=y+p(27)
    end
    for i,action in ipairs(o.buttons) do
        local b=action[1];y=y+p(14)
        local widget=K.button{text=b.text,w=w-p(48),h=p(51),size=17,variant=i==1 and "solid" or "outline",enabled=b.enabled,callback=b.callback}
        K.put(c,widget,p(24),y);widgets[i]=widget;y=y+p(51)
    end
    local h=y+p(24);local fitted=K.canvas(w,h)
    for _,child in ipairs(c) do fitted[#fitted+1]=child end
    local overlay=K.canvas(sw,sh)
    K.put(overlay,K.frame(K.canvas(w+p(14),h+p(14)),{w=w+p(14),h=h+p(14),radius=p(20)}),p(11),math.min(p(220),sh-h-p(24))-p(7))
    K.put(overlay,K.frame(fitted,{w=w,h=h,radius=p(16),border=p(2)}),p(18),math.min(p(220),sh-h-p(24)))
    local Input=require("ui/widget/container/inputcontainer"):extend{name="booksync_reminder_sheet",modal=true,stop_events_propagation=true}
    function Input:moveFocusTo(_,index)
        self.focus={1,index}
        for i,widget in ipairs(widgets) do
            local frame=widget[1];local border=p(i==index and 3 or 1.5)
            frame.bordersize=border;frame.padding=-border
        end
        UIManager:setDirty(self,"ui")
    end
    function Input:getButtonById(id)
        for i,line in ipairs(o.buttons) do if line[1].text==id then return widgets[i] end end
    end
    function Input:onTapClose() o.dismiss();return true end
    function Input:onClose() o.dismiss();return true end
    function Input:onSwipe() o.dismiss();return true end
    function Input:onPan() return true end
    return Input:new{dimen=require("ui/geometry"):new{w=sw,h=sh},buttons=o.buttons,ges_events={TapClose={require("ui/gesturerange"):new{ges="tap",range=require("ui/geometry"):new{w=sw,h=sh}}}},overlay}
end

function RemindersUI.open()
    local saved={items={},pending=true}
    local view
    local function reload(retry)
        Library.reminders.list(function(result)
            saved=result
            if visible(view) then view:paint() end
        end,retry)
    end
    local function editor(row,isNew)
        local draft=copy(row)
        local form,saveIntent,deleteIntent
        local saving,retrySave=false,false
        local function preview(nextDraft,inputTime,done)
            Library.reminders.draft(nextDraft,function(result)
                if result.error then form.notice="Check the time, days and message."
                else
                    for key,value in pairs(result) do draft[key]=value end
                    form.notice=nil
                    if done then done() end
                end
                if visible(form) then form:paint() end
            end,inputTime)
        end
        local function input(title,value,callback)
            local dialog
            dialog=require("ui/widget/inputdialog"):new{title=title,input=value or "",buttons={{{text="Cancel",callback=function() UIManager:close(dialog) end},
                {text="Done",callback=function() local text=dialog:getInputText();UIManager:close(dialog);callback(text) end}}}}
            UIManager:show(dialog) -- gate: user action (reminder draft field)
            dialog:onShowKeyboard()
        end
        local function days()
            local mask=draft.days
            local names={"Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"}
            form:push("Days",function()
                local out={}
                for _,item in ipairs({{127,"Every day"},{31,"Weekdays"},{96,"Weekends"}}) do
                    out[#out+1]={text=item[2],checked_func=function() return mask==item[1] end,callback=function()
                        mask=item[1];local nextDraft=copy(draft);nextDraft.days=mask;preview(nextDraft,nil,function() form:back() end)
                    end}
                end
                out[#out+1]={text="Custom days",callback=function()
                    form:push("Custom days",function()
                        local choices={}
                        for i,name in ipairs(names) do
                            local bit=2^(i-1)
                            choices[#choices+1]={text=name,checked_func=function() return math.floor(mask/bit)%2==1 end,callback=function()
                                mask=mask+(math.floor(mask/bit)%2==1 and -bit or bit)
                            end}
                        end
                        choices[#choices+1]={text="Done",enabled=mask>0,callback=function()
                            local nextDraft=copy(draft);nextDraft.days=mask
                            preview(nextDraft,nil,function() form:back();form:back() end)
                        end}
                        return choices
                    end)
                end}
                return out
            end)
        end
        local function save()
            local args={}
            for _,key in ipairs({"kind","id","revision","enabled","minuteOfDay","days","message","intervalMinutes"}) do args[key]=draft[key] end
            if saving then return end
            saveIntent=saveIntent or args
            saving=true;form.notice="Saving…";form:paint()
            Library.reminders.mutate(isNew and "add" or "edit",saveIntent,function(result)
                saving=false
                if result.error then
                    retrySave=true
                    form.notice="Could not save reminder. Try again."
                    if visible(form) then form:paint() end
                else saved=result;if form.alive then form:close() end end
            end)
        end
        form=SettingsView.open(isNew and "Add bedtime reminder" or draft.kind=="interval" and "Rest your eyes" or draft.editable==false and "Reminder" or "Edit reminder",function()
            if draft.editable==false then return {{text="Managed by "..(draft.sourceLabel or "source"),enabled=false},{text=draft.title or "Reminder",enabled=false},{text=draft.message or draft.detail,enabled=false}} end
            local rows={{text=draft.enabled and "On" or "Off",kitText="Reminder",kitDetail=draft.enabled and "On" or "Off",noChevron=true,callback=function() draft.enabled=not draft.enabled end}}
            if draft.kind=="interval" then
                rows[#rows+1]={text="Interval · "..(draft.detail or "Every 20 minutes of reading"),kitText="Interval",kitDetail=tostring(draft.intervalMinutes or 20).." minutes",callback=function()
                    form:push("Interval",function()
                        local choices={}
                        for _,n in ipairs({20,30,45,60}) do choices[#choices+1]={text=n.." minutes",checked_func=function() return draft.intervalMinutes==n end,callback=function()
                            local nextDraft=copy(draft);nextDraft.intervalMinutes=n;preview(nextDraft,nil,function() form:back() end)
                        end} end
                        return choices
                    end)
                end}
            else
                rows[#rows+1]={text="Time · "..(draft.title or "21:00"),kitText="Time",kitDetail=draft.title or "21:00",callback=function()
                    input("Time",draft.title,function(text) preview(draft,text) end)
                end}
                rows[#rows+1]={text="Days · "..(draft.detail or "Every day"),kitText="Days",kitDetail=draft.detail or "Every day",callback=days}
                rows[#rows+1]={text="Message · "..(draft.message and draft.message~="" and draft.message or "Time to stop reading"),kitText="Message",kitSub=draft.message and draft.message~="" and draft.message or "Time to stop reading",height=71,multiline=true,callback=function()
                    input("Message · up to 60 characters",draft.message,function(text)
                        local nextDraft=copy(draft);nextDraft.message=text;preview(nextDraft)
                    end)
                end}
            end
            for _,r in ipairs(rows) do r.enabled=not saving and not retrySave end
            rows[#rows+1]={text="Save",kitText="Save reminder",action=true,primary=true,enabled=not saving,callback=save}
            if not isNew and draft.kind=="time" then rows[#rows+1]={text="Delete",kitText="Delete reminder",action=true,callback=function()
                local confirm
                confirm=require("ui/widget/buttondialog"):new{title="Delete reminder?",buttons={{{text="Cancel",callback=function() UIManager:close(confirm) end}},
                    {{text="Delete",callback=function()
                        UIManager:close(confirm)
                        deleteIntent=deleteIntent or {id=draft.id,revision=draft.revision}
                        Library.reminders.mutate("delete",deleteIntent,function(result)
                            if result.error then form.notice="Could not save reminder. Try again.";if visible(form) then form:paint() end
                            else saved=result;if form.alive then form:close() end end
                        end)
                    end}}}}
                confirm:moveFocusTo(1,1)
                UIManager:show(confirm) -- gate: user action (reminder delete confirmation; Cancel focused)
            end} end
            return rows
        end,"reminders-editor")
        form.reminderMeta=function() if draft.kind=="interval" and form.title=="Rest your eyes" then return "Counts reading time only. A break of 5 minutes resets the count." end end
        form:paint()
        return form
    end
    view=SettingsView.open("Reminders",function()
        if saved.pending then return {{text="Loading reminders…",enabled=false}} end
        if saved.error then return {{text=saved.problem or "Reminders could not be loaded",enabled=false},{text="Retry",callback=function() reload(true) end}} end
        local rows={}
        if saved.notice then rows[#rows+1]={text=saved.notice,enabled=false} end
        if saved.clockStatus=="unknown" then rows[#rows+1]={text="Reminders need the time. Connect to Wi-Fi once to set the clock.",enabled=false,height=96} end
        for _,row in ipairs(saved.items or {}) do
            rows[#rows+1]={text=(row.title or "Reminder").." — "..(row.enabled and "On" or "Off"),kitText=row.title or "Reminder",kitDetail=row.enabled and "On" or "Off",
                note_func=function() return row.kind=="interval" and (saved.clockStatus=="unknown" and "Uses reading time; no clock needed" or row.detail) or (row.detail or "").." · "..(row.message and row.message~="" and row.message or "Time to stop reading") end,callback=function() editor(row,false) end}
        end
        if saved.timeCount==0 then rows[#rows+1]={text="No bedtime reminders",enabled=false} end
        local full=(saved.timeCount or 0)>=8
        rows[#rows+1]={text=full and "8 bedtime reminders — limit reached" or "Add bedtime reminder",kitText=full and "8 bedtime reminders — limit reached" or "Add reminder",action=true,enabled=not full,callback=function()
            Library.reminders.draft({kind="time",enabled=true,minuteOfDay=1260,days=127,message=""},function(result)
                if result.error then view.notice="Could not save reminder. Try again.";if visible(view) then view:paint() end
                elseif visible(view) then editor(result,true) end
            end)
        end}
        return rows
    end,"reminders-list")
    view.reminderMeta=function() if not saved.pending and not saved.error then return tostring(saved.timeCount or 0).." bedtime reminders · On this device" end end
    reload();return view
end
function RemindersUI.closeSheet()
    local entry=RemindersUI.current
    if not entry then return end
    RemindersUI.current=nil;entry.alive=false
    Library.reminders.detach(entry.value)
    UIManager:close(entry.dialog)
end
function RemindersUI.due(value)
    if RemindersUI.current then return end
    local entry={value=value,alive=true,focus=1}
    local interval=value.kind=="interval"
    local actions=interval and {{"Done","done"},{"Turn off","turnOff"}} or {{"Got it","gotIt"},{"10 more minutes","snooze10"},{"Sleep","sleep"}}
    local function respond(action)
        if not entry.alive or entry.busy then return end
        entry.busy=true
        Library.reminders.respond(value,action,function(result)
            entry.busy=false
            if not entry.alive or RemindersUI.current~=entry then return end
            if result.error or result.accepted==false and not result.stale then
                entry.error=action=="turnOff" and "Could not turn off reminder. Try again." or action=="sleep" and "Could not sleep. Keep reading or try again." or "Could not save reminder. Try again."
                entry.focus=1;entry:paint()
            else RemindersUI.closeSheet();Library.reminders.dismissed() end
        end)
    end
    local function input(action)
        if action=="dismiss" then respond(interval and "done" or "gotIt")
        elseif action=="select" then
            local a=actions[entry.focus][2]
            if a~="sleep" or value.sleepAvailable then respond(a) end
        else
            entry.focus=math.max(1,math.min(#actions,entry.focus+(action=="up" and -1 or 1)))
            entry.dialog:moveFocusTo(1,entry.focus)
        end
    end
    function entry:paint()
        local finish=Budgets.span("reminders-sheet.draw",now_s,log)
        local buttons={}
        for _,action in ipairs(actions) do
            buttons[#buttons+1]={{text=action[1],enabled=not (action[2]=="sleep" and not value.sleepAvailable or action[2]=="turnOff" and value.editable==false),
                callback=function() if Library.reminders.actionAllowed() then respond(action[2]) end end}}
        end
        local notes={}
        if value.dueLabel then notes[#notes+1]=value.dueLabel end
        if not interval and not value.sleepAvailable then notes[#notes+1]="Sleep unavailable" end
        if self.error then notes[#notes+1]=self.error end
        local message=interval and "Look at something far away for 20 seconds." or value.message
        local dialog=RemindersUI.sheet{interval=interval,message=message,managed=value.editable==false and (value.sourceLabel or "source") or nil,
            notes=notes,buttons=buttons,dismiss=function() input("dismiss") end}
        dialog.onClose=function() input("dismiss");return true end
        dialog.onSwipe=function() input("dismiss");return true end
        dialog.onPan=function() return true end
        -- Native gestures and Back/page turns always consume the input.
        if Device:isTouchDevice() then
            dialog.ges_events.ReminderSwipe={require("ui/gesturerange"):new{ges="swipe",range=require("ui/geometry"):new{x=0,y=0,w=Device.screen:getWidth(),h=Device.screen:getHeight()}}}
            dialog.onReminderSwipe=dialog.onSwipe
        end
        dialog:moveFocusTo(1,self.focus)
        if self.dialog then UIManager:close(self.dialog) end
        self.dialog=dialog
        if Library.reminders.attach(value,dialog,input) then
            Gate.reminder(value,function() UIManager:show(dialog) end) -- gate: claimed reminder only
        end
        finish()
    end
    RemindersUI.current=entry;entry:paint()
    if not entry.dialog or not Library.reminders.canDraw(value) then RemindersUI.closeSheet() end
end
Library.reminders.subscribe(function(kind,value)
    if kind=="due" then RemindersUI.due(value)
    elseif kind=="retired" and RemindersUI.current and RemindersUI.current.value==value then RemindersUI.closeSheet() end
end)
