-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Display only: already joined, bounded library rows. No catalog or statistics work here.
ReaderPanelPlan = {}
-- Scalar display conversion only; all battery predictions are companion-owned.
function ReaderPanelPlan.duration(value, minutes)
    local hours=tonumber(value)
    if not hours or hours~=hours or hours<0 or hours==math.huge then return nil end
    if minutes and hours<1 then return math.floor(hours*60).." min" end
    local whole=math.floor(hours)
    local days,rest=math.floor(whole/24),whole%24
    return days>0 and (days.." d "..rest.." h") or (rest.." h")
end
function ReaderPanelPlan.model(result, battery, native)
    native=native or {}
    local b = result.items and result.items[1] or {}
    local pct = tonumber(b.progress)
    if pct and (pct ~= pct or pct == math.huge or pct == -math.huge) then pct = nil end
    if pct then pct = math.max(0, math.min(100, pct)) end
    local stats = b.stats or {}
    local battery_text=battery and battery.display and battery.display.page_estimate
        or "Battery estimate not available yet"
    local series=b.series_line
    if not series then
        local name=type(b.series)=="table" and b.series[1] or b.series
        if type(name)=="string" then
            series=b.series_position and ("Book "..b.series_position..(b.series_total and " of "..b.series_total or "").." · "..name) or name
        end
    end
    return { key=b.key, time_left=b.time_left, chapter_time_left=b.chapter_time_left, cover_path=b.cover_path, description=native.description or b.description, series_line=series,
        total_pages=native.total_pages or b.total_pages, started=b.started or (stats.started_days and (stats.started_days.." days ago")), stats=stats, title=b.title or "Book info not saved yet",
        author=table.concat(b.authors or {}, ", "), progress=pct and pct/100,
        progress_text=pct and (string.format("%d%% read", math.floor(pct+0.5))) or "Progress not saved yet",
        battery=battery_text, battery_short=ReaderPanelPlan.batteryLabel(battery_text),
        days=stats.days_start_to_finish and (tostring(stats.days_start_to_finish) .. " days start to finish") or "Days start to finish: not saved yet",
        time=stats.reading_seconds and ReaderPanelPlan.readTime(stats.reading_seconds) or "Reading time: not saved yet",
        pages=stats.pages_read and (tostring(stats.pages_read) .. " pages read") or "Pages read: not saved yet" }
end

-- Quick-size steps wrap through the approved M8C choices, including a native size
-- outside the preset list. No style/catalog work occurs in this projection.
local FONT_SIZES={16,18,20,22,24,27}
function ReaderPanelPlan.sizeIndex(current)
    local index=1
    for i,value in ipairs(FONT_SIZES) do if math.abs(value-current)<math.abs(FONT_SIZES[index]-current) then index=i end end
    return index
end
function ReaderPanelPlan.fontSize(current,delta)
    return FONT_SIZES[(ReaderPanelPlan.sizeIndex(current)-1+delta)%#FONT_SIZES+1]
end
function ReaderPanelPlan.sizeDots(current)
    local selected=ReaderPanelPlan.sizeIndex(current)
    local dots={}
    for i=1,#FONT_SIZES do dots[i]=i<=selected and "●" or "○" end
    return table.concat(dots)
end

-- Number entry is bounded before parsing; invalid keys and oversized values never
-- escape into the document engine. Range validation remains Library.readerGo's.
function ReaderPanelPlan.keypad(value,key)
    value=tostring(value or "")
    if key=="back" then return value:sub(1,-2) end
    if type(key)~="string" or not key:match("^%d$") or #value>=6 then return value end
    return (value=="0" and "" or value)..key
end
function ReaderPanelPlan.segment(cell)
    local text=cell.display_text or cell.text or ""
    local selected=text:sub(1,#"✓ ")=="✓ "
    text=text:gsub("^✓ ",""):gsub(" ✎$","")
    local name,detail=text:match("^(Custom) · (.*)$")
    return name or text,detail,selected
end

function ReaderPanelPlan.readTime(seconds)
    local minutes=math.floor(seconds/60)
    return minutes>=60 and string.format("%d h %02d m",math.floor(minutes/60),minutes%60) or minutes.." min reading time"
end
function ReaderPanelPlan.batteryLabel(text)
    if text:lower():find("learning",1,true) or text:find("estimate available",1,true) then return "Learning your usage" end
    if text:find("not available",1,true) then return "Estimate unavailable" end
    text=text:gsub(" at your usual use","")
    return #text<=32 and text or "Battery estimate available"
end
function ReaderPanelPlan.searchPattern(query,whole)
    if not whole then return query end
    return "\\b"..query:gsub("[\\%^%$%.%|%?%*%+%(%)%[%]%{%}]",function(c) return "\\"..c end).."\\b"
end
