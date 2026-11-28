-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,here)
    local e=setmetatable({},{__index=_G}); setfenv(assert(loadfile(here..'/../orbit.koplugin/logic/battery_widget.lua')),e)()
    test('battery: learning never invents an estimate, ready labels retain usual-use context',function()
        local p=e.BatteryWidgetPlan
        for _,size in ipairs({{2,2},{1,2},{2,1},{4,3},{2,3},{4,2}}) do
            local learning=p.widget(nil,size[1],size[2])
            ok(learning.lines[1]:find('Learning',1,true)); eq(learning.level,'—')
            local ready=p.widget({level=78,display={level='78%',estimate='≈ 2 d 6 h at your usual use',
                narrow_estimate='≈ 2 d 6 h · usual use',reading='19 h reading non-stop',standby='5 d standby only'}},size[1],size[2])
            ok(ready.lines[1]:find(size[1]==1 and '· usual use' or 'at your usual use',1,true))
            eq(ready.level_fraction,.78); eq(ready.lines[2],'19 h reading non-stop')
        end
    end)
    test('battery: empty widget copy is short and keeps missing evidence explicit',function()
        local p=e.BatteryWidgetPlan
        eq(p.widget(nil,2,2).lines[1],'Learning your usage')
        eq(p.widget(nil,1,2).lines[1],'Learning usage')
        eq(p.compact('Reading · — No measured use','reading_rate'),'Reading · —')
        eq(p.compact('— Needs measured use standby only','standby'),'Standby —')
        eq(p.compact('— No charges recorded','last_charge'),'No charges yet')
    end)
    test('battery: failed and pending reads are distinct from learning evidence',function()
        eq(e.BatteryWidgetPlan.widget({error='budget'},2,2).lines[1],'Battery unavailable · try again')
        eq(e.BatteryWidgetPlan.widget({pending=true},1,2).lines[1],'Loading battery…')
        eq(e.BatteryWidgetPlan.page({error='unavailable'},1,1).estimate,'Battery unavailable · try again')
        eq(e.BatteryWidgetPlan.page({pending=true},1,1).estimate,'Loading battery…')
    end)
    test('battery: clock corrections and unavailable measurements are never filled from UI time',function()
        local d={level='—',page_estimate='Learning · estimate available after measured use',
            overview={'Your usual use: — Needs 24 h of observed use'},overview_count=1,
            charges={'Earlier recorded charge · clock boundary'},charges_count=1}
        local p=e.BatteryWidgetPlan.page({display=d},1,1)
        eq(p.level,'—'); eq(p.rows[1],d.overview[1])
        eq(e.BatteryWidgetPlan.page({display=d},4,1).rows[1],d.charges[1])
        eq(e.BatteryWidgetPlan.page(nil,4,1).rows[1],'— No charges recorded')
    end)
    test('battery: daily pagination selects at most seven immutable ready-to-draw rows',function()
        local d={daily={},daily_count=14}
        for i=1,14 do d.daily[i]={text='Day '..i,fraction=.1} end
        local a=e.BatteryWidgetPlan.page({display=d},3,1)
        local b=e.BatteryWidgetPlan.page({display=d},3,2)
        eq(#a.rows,7); eq(#b.rows,7); eq(b.rows[1].text,'Day 8')
        eq(d.daily_count,14)
    end)
end
