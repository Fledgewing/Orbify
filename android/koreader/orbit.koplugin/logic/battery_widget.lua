-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Presentation selection only; all values and evidence labels are companion-owned.
BatteryWidgetPlan = {tabs={"Overview","Rates","Daily","Charges"}}
function BatteryWidgetPlan.display(data)
    if data and (data.error or data.pending or data.state=="error") then
        local message=(data.error or data.state=="error") and "Battery unavailable · try again" or "Loading battery…"
        return {level="—",estimate=message,narrow_estimate=message,page_estimate=message,
            reading="reading non-stop · —",standby="standby only · —"}
    end
    return data and data.display or {level="—",estimate="Learning · needs measured use",
        narrow_estimate="Learning · usual use",page_estimate="Learning · estimate available after measured use",
        reading="— Needs measured reading",standby="— Needs measured standby"}
end
-- Short presentation-only forms; unknown estimates stay unknown.
function BatteryWidgetPlan.compact(value,kind,narrow)
    value=tostring(value or "—")
    if value:find("Learning",1,true) then return narrow and "Learning usage" or "Learning your usage" end
    if value:lower():find("measured",1,true) or value:find("Needs 24",1,true) or ((kind=="reading_rate" or kind=="standby_rate") and value:find("—",1,true)) then
        return ({reading="Reading —",standby="Standby —",reading_rate="Reading · —",standby_rate="Standby · —",used_week="—"})[kind] or "—"
    end
    if value:find("No charges",1,true) then return "No charges yet" end
    return value
end
function BatteryWidgetPlan.widget(data,w,h)
    local d=BatteryWidgetPlan.display(data)
    local compact=BatteryWidgetPlan.compact
    local lines={compact(w == 1 and d.narrow_estimate or d.estimate,"estimate",w==1),compact(d.reading,"reading",w==1),compact(d.standby,"standby",w==1)}
    if w>1 and h>1 then
        lines[#lines+1]=d.reading_rate or "— Needs measured reading"
        lines[#lines+1]=d.standby_rate or "— Needs measured standby"
        lines[#lines+1]=d.used_week or "— Needs measured daily use"
        if h>=3 or w>=4 then
            lines[#lines+1]="Per 100 pages · — Needs tracked page measurements"
            lines[#lines+1]=d.charging_rate or "— Needs measured charging"
        end
        lines[#lines+1]=d.last_charge or "— No charges recorded"
    end
    return {level=d.level or "—",lines=lines,level_fraction=data and data.level and data.level/100 or 0}
end
function BatteryWidgetPlan.page(data,tab,page)
    local d=BatteryWidgetPlan.display(data)
    local key=({"overview","rates","daily","charges"})[tab] or "overview"
    local count=math.min(d[key.."_count"] or 0,key == "daily" and 14 or key == "charges" and 5 or 9)
    local rows={}
    local first=key == "daily" and page == 2 and 8 or 1
    local last=key == "daily" and math.min(count,first+6) or count
    for i=first,last do rows[#rows+1]=d[key][i] end
    if #rows==0 then rows[1]=key == "charges" and "— No charges recorded" or "— Needs measured use" end
    return {level=d.level or "—",estimate=d.page_estimate,rows=rows,daily=key == "daily",pages=key == "daily" and 2 or 1}
end
