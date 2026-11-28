-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Bounded Settings presentation. Library owns dates, count, validation and persistence.
LocalReadingSettings={}
function LocalReadingSettings.open()
    local view,saved
    local function apply(result)
        if not result.error then saved=result end
        -- The mutation outlives its form; presentation never outlives visibility.
        if not view.alive or UIManager:getTopmostVisibleWidget()~=view.dialog then return end
        view.notice=result.error=="invalid" and "Enter a number from 1 to 999."
            or result.error and "Not available · try again" or nil
        view:paint()
    end
    local function edit(snapshot)
        local paint=Library.paint("settings-reading-statistics")
        local current=paint:localReading();paint:flush()
        if not current.pending and not current.error then snapshot=current end
        local value=snapshot.target and tostring(snapshot.target) or ""
        local goal
        local function close() if goal then UIManager:close(goal);goal=nil end end
        local function paint()
            close()
            goal=SettingsPage.new{title="Local reading goal",subtitle="This reader only",rows={},onBack=close,
                content=function(K,c,w,y,put)
                    local p=K.px
                    local errorLabel=K.label(c,"",p(30),p(450),w-p(60),"small")
                    K.label(c,tostring(snapshot.year or ""),p(30),p(100),w-p(60),"number",{serif=true,bold=true})
                    K.label(c,"Books to finish on this reader",p(30),p(178),w-p(60),"title")
                    put(K.button{text=value,w=p(133),h=p(84),radius=0,size=20,bold=false,variant="outline",callback=function()
                        local input
                        input=require("ui/widget/inputdialog"):new{title="Books to finish",input=value,input_type="number",buttons={{{text="Cancel",callback=function() UIManager:close(input) end},
                            {text="Use",callback=function() value=input:getInputText();UIManager:close(input);paint() end}}}}
                        UIManager:show(input) -- gate: user action (goal keyboard)
                        input:onShowKeyboard()
                    end},p(30),p(225),"goal-number")
                    K.label(c,"1–999 books. This reader only. Your account goal stays separate.",p(30),p(316),w-p(60),"body")
                    put(K.button{text="Off",w=p(95),h=p(84),radius=0,variant="outline",callback=function() close();Library.localReadingGoal(nil,apply) end},p(30),p(380),"goal-off")
                    put(K.button{text="Save",w=p(115),h=p(84),radius=0,variant="outline",callback=function()
                        local n=tonumber(value)
                        if not n or n<1 or n>999 or n~=math.floor(n) then
                            errorLabel:setText("Enter a number from 1 to 999.");UIManager:setDirty(goal,"ui");return
                        end
                        close();Library.localReadingGoal(value,apply)
                    end},p(142),p(380),"goal-save")
                end}
            UIManager:show(goal) -- gate: user action (local reading goal editor)
        end
        paint()
    end
    view=SettingsView.open("Reading statistics",function()
        local p=Library.paint("settings-reading-statistics")
        local r=p:localReading();p:flush()
        if saved then r=saved end
        return {{text="Local reading goal",note_func=function() return r.goal_label or "Loading…" end,pending=r.pending,
            enabled=not r.pending and not r.error,callback=function() edit(r) end},
            {text="Finished this year",note_func=function() return r.count_label or "Not available" end,enabled=false},
            {text="Only books explicitly marked finished count.\nAccount totals remain separate when overlap is unknown.",enabled=false,height=96}}
    end,"settings-reading-statistics")
    return view
end
