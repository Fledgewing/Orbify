-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Bounded geometry only. Companion owns dates, maxima, totals and provenance.
ReadingStatsPlan = {}
local titles = {['year-in-reading']='Year in reading', ['this-week']='This week',
    ['when-you-read']='When you read', ['reading-records']='Reading records'}
local metricTitles={today="Today",["reading-streak"]="Reading streak",["reading-goal"]="Reading goal",["pages-read"]="Pages read",["monthly-reading"]="Monthly reading"}
local function metricPlan(id,data,w,h,rows,headerTop)
    local p={title=metricTitles[id],rects={},labels={},icons={},dots={}}
    local m=data and data.metrics and data.metrics[id]
    if not m then p.message="Loading reading statistics";return p end
    p.source=m.source=="all your devices" and "All your devices" or m.source=="this reader" and "This reader only" or nil
    p.sourceInline=false
    if m.state~="ready" then p.message=m.reason or "Reading statistics unavailable";return p end
    local top=math.max(headerTop or 0,p.source and 48 or 30)
    local function label(x,y,text,size,bold,width)
        if text~=nil then p.labels[#p.labels+1]={x=x,y=y,text=tostring(text),size=size,bold=bold,width=width} end
    end
    local function rect(x,y,rw,rh,level,outline) p.rects[#p.rects+1]={x=x,y=y,w=rw,h=rh,level=level,outline=outline} end
    if id=="today" then
        label(8,top,m.value,30,true);label(8,top+44,"Reading today",12)
        label(8,h-20,m.separate,10)
    elseif id=="reading-streak" then
        label(8,top,m.value,30,true);label(8,top+38,m.best,12)
        if m.days then
            assert(m.days[7]~=nil and m.days[8]==nil)
            local gap=6;local width=math.max(1,(w-16-6*gap)/7)
            for i=1,7 do rect(8+(i-1)*(width+gap),top+62,width,10,m.days[i],true) end
            label(8,h-20,m.days_source,10)
        else label(8,h-20,"Seven-day history unavailable",10) end
    elseif id=="reading-goal" then
        label(8,top,m.value,20,true)
        if m.fraction then
            rect(8,top+34,w-16,6,0,true);rect(8,top+34,(w-16)*m.fraction,6,4)
        end
        label(8,top+50,m.pace,12);label(8,top+72,m.status,12)
    elseif id=="pages-read" then
        label(8,top,m.today,22,true,w/2-16);label(w/2,top,m.lifetime,22,true,w/2-16)
        label(8,top+30,"today",12);label(w/2,top+30,"all time",12)
        label(8,h-20,m.definition,11)
    elseif id=="monthly-reading" then
        assert(m.levels[12]~=nil and m.levels[13]==nil and m.labels[12]~=nil and m.labels[13]==nil)
        label(8,top,m.total,24,true,w/2-16);label(w/2,top+8,m.previous,11,false,w/2-8)
        local bottom=h-32;local height=math.max(1,bottom-top-36);local width=(w-16)/12
        for i=1,12 do
            assert(m.levels[i]>=0 and m.levels[i]<=1)
            local bar=height*m.levels[i]
            rect(8+(i-1)*width,bottom-bar,width-4,bar,i==12 and 4 or 2)
            label(8+(i-1)*width,bottom+3,m.labels[i],9,false,width-2)
        end
        rect(8,bottom,w-16,1,4);label(8,h-13,m.period,9)
    end
    return p
end
function ReadingStatsPlan.build(id, data, w, h, rows, headerTop, measure)
    if metricTitles[id] then return metricPlan(id,data,w,h,rows,headerTop) end
    assert(titles[id] and w >= 64 and h >= 64)
    measure=measure or function(text,size,bold,width) return {w=math.min(width or w-32,#tostring(text or '')*size*.6),h=size} end
    local function textHeight(text,size,bold,width) return measure(tostring(text or ''),size,bold,width).h end
    local p = {title=titles[id], rects={}, labels={},icons={},dots={}}
    local function rect(x,y,rw,rh,level,outline)
        p.rects[#p.rects+1]={x=x,y=y,w=rw,h=rh,level=level,outline=outline}
    end
    local function label(x,y,text,size,bold,width)
        if text ~= nil then p.labels[#p.labels+1]={x=x,y=y,text=tostring(text),size=size,bold=bold,width=width} end
    end
    local sources=data and data.sources or {}
    local source_field=({['year-in-reading']='days',['this-week']='days',
        ['when-you-read']='hours',['reading-records']='records'})[id]
    if sources[source_field] == 'this reader' then
        local r=data.records or {}
        local mixedYear=id=='year-in-reading' and (r.books_this_year~=nil and sources.finished=='all your devices'
            or r.best_streak~=nil and sources.streak=='all your devices')
        p.source=id=='reading-records' and 'Pages · this reader' or mixedYear and 'Days · this reader' or 'This reader only'
    end
    local states={empty='No reading recorded',error='Reading statistics unavailable',
        ['not-saved']='Enable KOReader statistics',['offline-without-data']='Not saved yet',loading='Loading reading statistics'}
    if not data or (data.state ~= 'ready' and data.state ~= 'offline-with-data') then
        p.message=data and states[data.state] or 'Loading reading statistics'
        return p
    end
    local d=data.display or {}
    p.sourceInline=p.source and ((headerTop and headerTop<48) or rows==1 and w>=300)
    local top=math.max(headerTop or 0,p.source and not p.sourceInline and 48 or 30)
    if id == 'year-in-reading' and not data.year then
        p.message='Reading days unavailable'; return p
    elseif id == 'when-you-read' and data.hours_available == false then
        p.message='Enable KOReader statistics'; return p
    elseif id == 'this-week' and not data.week then
        p.message='Reading days unavailable'; return p
    end
    if id == 'year-in-reading' then
        assert(data.year.intensity[365] ~= nil and data.year.intensity[366] == nil)
        local r=data.records or {}
        local summaryBottom=top
        local function stat(x,value,caption,width)
            label(x,top,value,30,true,width)
            local cy=top+textHeight(value,30,true,width)+4
            label(x,cy,caption,12,false,width)
            summaryBottom=math.max(summaryBottom,cy+textHeight(caption,12,false,width))
        end
        local compact=rows==2
        if compact then
            local text=tostring(data.year.days_read)..' days read'
            label(16,top,text,16,true);summaryBottom=top+textHeight(text,16,true)
        else
            stat(16,data.year.days_read,'days read',w*.15-8)
            if r.books_this_year~=nil then stat(16+w*.15,r.books_this_year,'books finished'..(p.source=='Days · this reader' and sources.finished=='this reader' and ' · local' or ''),w*.17-8) end
            if r.best_streak~=nil then stat(16+w*.32,r.best_streak,'longest streak'..(p.source=='Days · this reader' and sources.streak=='this reader' and ' · local' or ''),w*.3-8) end
        end
        local offset=data.year.weekday or 0
        local columns=math.ceil((365+offset)/7)
        local summary=summaryBottom-top+26
        local size=math.max(1,math.floor(math.min((w-16)/columns,(h-top-summary-36)/7)))
        local left=math.floor((w-columns*size)/2)
        local y0=math.max(top+summary,math.floor((top+summary+h-36-7*size)/2))
        for _,m in ipairs(d.months or {}) do
            label(left+math.floor((m.day+offset)/7)*size,y0-16,m.label,10)
        end
        for i=1,365 do
            local level=data.year.intensity[i]; assert(level>=0 and level<=4)
            rect(left+math.floor((i-1+offset)/7)*size,y0+((i-1+offset)%7)*size,
                math.max(1,size-2),math.max(1,size-2),level,i==365)
        end
        local x=math.max(8,w-238)
        local legendY=h-8-textHeight('Less',11)
        label(x,legendY,'Less',11)
        for level=0,4 do rect(x+30+level*14,legendY+2,10,10,level) end
        label(x+104,legendY,'More',11)
        rect(x+142,legendY+2,10,10,2,true); label(x+158,legendY,'Today',11)
    elseif id == 'this-week' then
        assert(data.week.levels[7] ~= nil and data.week.levels[8] == nil)
        local short=rows==1
        label(math.max(w/2,w-100),12,d.week_total or '—',14,true,92)
        if rows ~= 1 and d.best_day then label(16,top,(d.week_comparison and d.week_comparison..' · best day ' or 'Best day ')..d.best_day,12) end
        local separate=d.local_today
        local bottom=h-(separate and textHeight(separate,11)+textHeight('M',11)+20 or short and 8 or textHeight('M',11)+12)
        local chartTop=short and 30 or top+textHeight(d.week_comparison or 'Best day',12)+28
        local height=math.max(1,bottom-chartTop-(short and 0 or 18))
        local width=(w-16)/7
        for i=1,7 do
            local bh=height*data.week.levels[i]
            local bw=math.min(26,width-6); local x=8+(i-.5)*width-bw/2
            rect(x,bottom-bh,bw,bh,i==d.today_index and 4 or 2)
            if rows ~= 1 then
                label(x,bottom+4,({'M','T','W','T','F','S','S'})[i],11,i==d.today_index,width)
                if i==d.best_index then label(math.max(8,x-10),bottom-bh-textHeight(d.best_duration,10,true)-4,d.best_duration,10,true) end
            end
        end
        rect(8,bottom,w-16,1,4)
        if separate then label(8,h-18,separate,11) end
    elseif id == 'when-you-read' then
        if rows>1 then p.icons[#p.icons+1]={name='sunmoon',x=w-32,y=14,w=16} end
        assert(data.hour_levels[24] ~= nil and data.hour_levels[25] == nil and data.hour_intensity[24] ~= nil and data.hour_intensity[25] == nil)
        local strip=rows==1
        local summaryX,summaryY=16,top
        local summaryBottom=top
        if not strip then
            label(16,top,d.period,14,true)
            local period=measure(tostring(d.period or ''),14,true,w-32)
            summaryX=16+period.w+6
            if w<500 or w-summaryX-16<100 then summaryX,summaryY=16,top+period.h+4 end
            summaryBottom=math.max(top+period.h,summaryY+textHeight('Most at',12))
        end
        local peak=d.peak or (data.peak_hour and (data.peak_hour..':00'))
        if not strip or h-top>=textHeight('Most at',12)+22+textHeight('00',10)+12 then
            label(summaryX,summaryY,peak and ('Most at '..peak..(data.after_18_percent and ' · '..data.after_18_percent..'% after 18:00' or '')) or 'No reading recorded',12,false,w-summaryX-16)
        end
        local bottom=h-8-textHeight('00',10)
        local height=math.max(1,bottom-(strip and top or summaryBottom+textHeight(peak or '',11,true)+30))
        local width=(w-32)/24
        for i=1,24 do
            local bh=strip and math.min(22,height) or height*data.hour_levels[i]
            rect(16+(i-1)*width,bottom-bh,math.max(1,width-1),bh,
                strip and data.hour_intensity[i] or (i-1==data.peak_hour and 4 or 2),strip and i-1==data.peak_hour)
        end
        if not strip then
            rect(16,bottom,w-32,1,4)
            if data.peak_hour then
                local x=16+(data.peak_hour+.5)*width
                label(math.min(w-48,math.max(8,x-16)),bottom-height-textHeight(peak,11,true)-8,peak,11,true)
                rect(x-2,bottom-height-7,4,5,4)
            end
        end
        for i=0,3 do label(16+i*6*width,bottom+4,string.format('%02d',i*6),10) end
    else
        local r=data.records or {}
        local allLocal=true
        for _,field in ipairs({'records','longest_session_seconds','best_day_pages','finished','streak'}) do if sources[field] and sources[field]~='this reader' then allLocal=false end end
        if allLocal and sources.records=='this reader' then p.source='This reader only' end
        local function caption(text,field)
            return text..(not allLocal and sources[field]=='this reader' and ' · local' or '')
        end
        -- Measure value/caption pairs as a unit. The first row wins; the second
        -- row and running-streak footer are optional, never squeezed into its space.
        local function height(text,size,bold,width)
            return measure(tostring(text or '—'),size,bold,width).h
        end
        local short=rows==1
        local available=data.records_available~=false and r.recorded_pages~=nil
        local left,pad=16,16
        local cw=(w-2*pad-12)/(short and 4 or 2)
        local value=available and (d.pages or r.recorded_pages) or '—'
        local captionText=available and 'recorded pages, all time' or 'Local records unavailable'
        local heroSize=short and 24 or h<220 and 30 or 40
        local heroWidth=short and cw-8 or w-2*pad
        label(left,top,value,heroSize,true,heroWidth)
        local heroBottom=top+height(value,heroSize,true,heroWidth)
        label(left,heroBottom+4,captionText,12,false,heroWidth)
        local y=short and top or heroBottom+4+height(captionText,12,false,heroWidth)+16
        local sx=short and left+cw or left
        local valueSize=20
        local function metricRow(items,rowY)
            local valueH,captionH=0,0
            for _,v in ipairs(items) do
                valueH=math.max(valueH,height(v[2],valueSize,true,cw-8))
                captionH=math.max(captionH,height(v[3],11,false,cw-8))
            end
            local bottom=rowY+valueH+4+captionH
            if bottom>h-pad then return nil end
            for _,v in ipairs(items) do
                label(v[1],rowY,v[2] or '—',valueSize,true,cw-8)
                label(v[1],rowY+valueH+4,v[3],11,false,cw-8)
            end
            return bottom
        end
        local first={{sx,d.longest,caption(r.longest_session_period=='week' and 'longest · this week' or 'longest session','longest_session_seconds')},
            {sx+cw,r.best_day_pages and (r.best_day_pages..' pp'),caption('best day'..(d.record_day and ' · '..d.record_day or ''),'best_day_pages')}}
        if short then first[#first+1]={sx+2*cw,r.books_this_year,caption('books this year','finished')} end
        local bottom=metricRow(first,y)
        if bottom and not short then
            rect(left,y-12,w-2*pad,1,1)
            local secondY=bottom+10
            bottom=metricRow({{sx,r.books_this_year,caption('books this year','finished')},
                {sx+cw,r.streak and (r.streak..' days'),caption('streak · best '..tostring(r.best_streak or '—'),'streak')}},secondY) or bottom
            if r.streak~=nil and bottom+18<=h-pad then
                for i=1,7 do p.dots[#p.dots+1]={x=sx+cw+(i-1)*13,y=bottom+4,d=8,level=i<=r.streak and 4 or 1} end
                bottom=bottom+18
            end
            if rows>=3 and r.streak~=nil then
                local footer='Reading '..r.streak..' days running'
                local fh=height(footer,12,true,w-2*pad)
                if bottom+4+fh<=h-pad then
                    label(left+22,h-pad-fh,footer,12,true,w-2*pad-22)
                    p.icons[#p.icons+1]={name='flame',x=left,y=h-pad-fh,w=16}
                end
            end
        end
    end
    return p
end
