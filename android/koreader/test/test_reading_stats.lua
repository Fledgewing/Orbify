return function(test,eq,ok,here,Cache)
    local e=setmetatable({SOURCE_DIR='.',Cache=Cache,now_s=function() return 0 end,log=function() end},{__index=_G})
    local root=here..'/../orbit.koplugin/'
    for _,p in ipairs({'logic/ui_util.lua','logic/budgets.lua','logic/widget_registry.lua','logic/reading_stats.lua','logic/reader_panel.lua','ko/reading_stats.lua'}) do
        setfenv(assert(loadfile(root..p)),e)()
    end
    test('clock: library operation inherits one row and batches the host request',function()
        local env=setmetatable({Cache=Cache,now_s=function() return 0 end,log=function() end},{__index=_G})
        local calls,batches=0,0
        env.LibraryAdapter={read=function(request)
            local args=Cache.decode(request); eq(args.op,'device.clock'); eq(args.limit,1); eq(args.twelve_hour,true)
            calls=calls+1; return {state='ready',time='9:42 PM'},128
        end,request=function(batch) eq(#batch,1); batches=batches+1; return true end}
        setfenv(assert(loadfile(root..'logic/budgets.lua')),env)()
        setfenv(assert(loadfile(root..'ko/library.lua')),env)()
        local host=env.Library.paint('home')
        eq(host:widget('clock'):clock(true).time,'9:42 PM'); eq(calls,1); eq(batches,0)
        local usage=host:flush(); eq(usage.rows,1); eq(usage.bytes,128)
        eq(usage.spawns,0); eq(usage.network,0); eq(usage.roundTrips,1); eq(batches,1)
    end)
    local data={state='ready',year={intensity={},days_read=7,start='2025-11-26'},
        week={seconds={1,2,3,4,5,6,7},levels={.1,.2,.3,.4,.5,.6,1},total_seconds=28},
        hour_levels={},hour_intensity={},peak_hour=19,after_18_percent=71,
        records={recorded_pages=8,longest_session_seconds=600,best_day_pages=4,streak=3,best_streak=4},
        display={week_total='2 h 10 m',today_index=3,best_index=7,best_day='Sunday',best_duration='10 m',
            period='Evenings',peak='19:00',longest='10 m',months={{day=0,label='Nov'},{day=6,label='Dec'}}}}
    for i=1,365 do data.year.intensity[i]=i%5 end
    for i=1,24 do data.hour_levels[i]=i/24; data.hour_intensity[i]=i%5 end
    test('stats: standalone registry widgets paint bounded snapshots and release text',function()
        local frees, paints, logs, textAlloc = 0, 0, 0, 0
        local positions={}
        local function class()
            local c={}
            function c:new(o) if o and o.text then textAlloc=textAlloc+1 end;return setmetatable(o or {},{__index=self}) end
            function c:getSize() return self.dimen or {w=100,h=self.bold and 28 or 18} end
            function c:paintTo(_,x,y) paints=paints+1;if self.text then positions[self.text]={x=x,y=y} end end
            function c:free() if self.text then frees=frees+1 end end
            return c
        end
        local colors={COLOR_WHITE=0,COLOR_LIGHT_GRAY=1,COLOR_GRAY=2,COLOR_DARK_GRAY=3,COLOR_BLACK=4}
        local modules={['ui/widget/widget']=class(),['ui/geometry']=class(),
            ['ui/font']={getFace=function() return {} end},['ui/widget/textwidget']=class(),['ui/widget/imagewidget']=class(),['ffi/blitbuffer']=colors}
        e.require=function(name) return assert(modules[name],name) end
        e.log=function() logs=logs+1 end
        local rects=0
        local bb={paintBorder=function() end,paintRoundedRect=function() end,paintRect=function(_,x,y,w,h,color)
            ok(w>=0 and h>=0 and x>=10 and y>=10 and x+w<=610 and y+h<=310)
            ok(color~=nil); rects=rects+1
        end}
        for _,id in ipairs({'year-in-reading','this-week','when-you-read','reading-records'}) do
            local w=e.WidgetRegistry[id].renderers['android-tablet'](data,{w=600,h=300,rows=2})
            eq(w:getSize().w,600); w:paintTo(bb,10,10); w:free()
        end
        ok(rects>=400); ok(paints>4); eq(frees,textAlloc); eq(logs,8)
        local sourced={state='not-saved',sources={hours='this reader'}}
        local w=e.ReadingStatsWidgets.render('when-you-read',sourced,{w=600,h=300,rows=2})
        w:paintTo(bb,10,10);w:free()
        ok(positions['This reader only'].x>=positions['When you read'].x+100+12,'inline source clears the measured title')
        ok(positions['Enable KOReader statistics'].y>=positions['When you read'].y+28+4,'empty message clears the measured header')
    end)
    test('stats and battery: every registered size paints disjoint measured text within the card',function()
        local boxes,scale={},1
        local function class()
            local c={}
            function c:new(o) return setmetatable(o or {},{__index=self}) end
            function c:getSize()
                if self.dimen then return self.dimen end
                if self.width then return {w=self.width,h=self.height} end
                local size=(self.face and self.face.size or 14)*scale
                return {w=math.min(self.max_width or math.huge,#(self.text or '')*size*.62),h=math.ceil(size*1.45)}
            end
            function c:paintTo(bb,x,y)
                if self.text then
                    local b=self:getSize()
                    if self.width then
                        local th=math.ceil((self.text_font_size or 14)*scale*1.45)
                        y=y+(self.height-th)/2
                        b={w=math.min(self.width,#self.text*(self.text_font_size or 14)*scale*.62),h=th}
                    end
                    boxes[#boxes+1]={x=x,y=y,w=b.w,h=b.h,text=self.text}
                end
                for _,child in ipairs(self) do
                    local o=child.overlap_offset or {0,0};child:paintTo(bb,x+o[1],y+o[2])
                end
            end
            function c:free() end
            return c
        end
        local colors={COLOR_WHITE=0,COLOR_LIGHT_GRAY=1,COLOR_GRAY=2,COLOR_DARK_GRAY=3,COLOR_BLACK=4}
        local U={Font={getFace=function(_,name,size) return {size=size,name=name} end},BB=colors}
        for _,k in ipairs({'Text','Button','Frame','Progress','Overlap'}) do U[k]=class() end
        local modules={['ui/widget/widget']=class(),['ui/geometry']=class(),
            ['ui/font']=U.Font,['ui/widget/textwidget']=U.Text,['ui/widget/imagewidget']=class(),['ffi/blitbuffer']=colors}
        local env=setmetatable({now_s=function() return 0 end,log=function() end,
            Device={screen={scaleBySize=function(_,n) return n*scale end}},
            require=function(name) return assert(modules[name],name) end},{__index=e})
        for _,file in ipairs({'ko/home_widgets.lua','logic/battery_widget.lua','ko/battery.lua','ko/reading_stats.lua'}) do
            setfenv(assert(loadfile(root..file)),env)()
        end
        env.HomeWidgets._ui=U
        local bb={paintBorder=function() end,paintRoundedRect=function() end,paintRect=function() end}
        local ready={}
        for k,v in pairs(data) do ready[k]=v end
        ready.metrics={today={state='ready',value='1 h 20 m',separate='10 m · this reader, separate'},
            ['reading-streak']={state='ready',value='7 days',best='Longest: 12 days',days={0,4,4,0,4,4,4},days_source='Last seven days · this reader'},
            ['reading-goal']={state='ready',value='8 / 24 books · 2026',fraction=1/3,pace='Need 0.5 books / week',status='On pace'},
            ['pages-read']={state='ready',today='17',lifetime='2,345',definition='Timed page visits'},
            ['monthly-reading']={state='ready',levels={0,.1,.2,.3,.4,.5,.6,.7,.8,.9,1,.5},labels={'D','J','F','M','A','M','J','J','A','S','O','N'},total='20 h 10 m',previous='Previous month: 2 h 10 m',period='Dec 2025 – Nov 2026'}}
        local battery={state='ready',data={level=78,display={level='78%',estimate='≈ 2 d 6 h at your usual use',
            narrow_estimate='≈ 2 d 6 h · usual use',reading='19 h reading non-stop',standby='5 d 22 h standby only',
            reading_rate='Reading · 4.1 ± 0.3 %/h',standby_rate='Standby · 0.6 %/h',used_week='76% used this week',
            last_charge='Last charge · Sun 21:10 · 12% → 100%'}}}
        for _,factor in ipairs({1,1.25,2}) do
            scale=factor
            for _,id in ipairs({'year-in-reading','this-week','when-you-read','reading-records','today','reading-streak','reading-goal','pages-read','monthly-reading','battery'}) do
                for _,size in ipairs(e.WidgetRegistry[id].sizes['android-tablet']) do
                    local w=(math.floor(size[1]*690/4)-12)*scale
                    local h=(math.floor(size[2]*776/8)-12)*scale
                    for _,state in ipairs({'ready','loading','error','not-saved'}) do
                        boxes={}
                        local snapshot=ready
                        if state~='ready' then snapshot={state=state,sources={records='this reader',hours='this reader'}} end
                        local widget
                        if id=='battery' then
                            widget=env.BatteryUI.widget({w=size[1],h=size[2]},state=='ready' and battery or {state=state},function() end,{w=w,h=h})
                        else widget=env.ReadingStatsWidgets.render(id,snapshot,{w=w,h=h,rows=size[2]}) end
                        widget:paintTo(bb,0,0);widget:free()
                        ok(#boxes>0,id..' has visible text')
                        for i,b in ipairs(boxes) do
                            ok(b.x>=0 and b.y>=0 and b.x+b.w<=w and b.y+b.h<=h,id..' out of card: '..b.text)
                            for j=1,i-1 do local a=boxes[j]
                                ok(b.x>=a.x+a.w or a.x>=b.x+b.w or b.y>=a.y+a.h or a.y>=b.y+b.h,
                                    id..' overlapping: '..a.text..' / '..b.text)
                            end
                        end
                    end
                end
            end
        end
    end)
    test('stats: hourly chart uses independent rectangular bars and records include owned icons',function()
        local levels=data.hour_levels;data.hour_levels={}
        for i=1,24 do data.hour_levels[i]=i%2==0 and .8 or .1 end
        local chart=e.ReadingStatsPlan.build('when-you-read',data,330,192,2)
        for i=2,24 do eq(chart.rects[i].h/chart.rects[1].h,i%2==0 and 8 or 1) end
        ok(chart.rects[1].x+chart.rects[1].w<chart.rects[2].x,'hour bars retain a gap')
        data.hour_levels=levels
        local records=e.ReadingStatsPlan.build('reading-records',data,330,292,3)
        eq(#records.dots,7);eq(records.icons[1].name,'flame')
    end)
    test('stats: measured plans, hour bars and short strip, immutable snapshot',function()
        local before=Cache.encode(data)
        for id,n in pairs({['year-in-reading']=371,['this-week']=8,['when-you-read']=26,['reading-records']=1}) do
            local p=e.ReadingStatsPlan.build(id,data,600,300,2)
            eq(#p.rects,n); ok(e.WidgetRegistry[id].renderers['android-tablet'])
            ok(e.Budgets.get('widgets',id))
            for _,r in ipairs(p.rects) do ok(r.x>=0 and r.y>=0 and r.x+r.w<=600 and r.y+r.h<=300) end
        end
        for _,id in ipairs({'year-in-reading','this-week','when-you-read','reading-records'}) do
            for _,size in ipairs(e.WidgetRegistry[id].sizes['android-tablet']) do
                local w=math.floor(size[1]*690/4)-12
                local h=math.floor(size[2]*776/8)-12
                local plan=e.ReadingStatsPlan.build(id,data,w,h,size[2])
                for _,r in ipairs(plan.rects) do ok(r.x>=0 and r.y>=0 and r.x+r.w<=w and r.y+r.h<=h,id) end
                for _,t in ipairs(plan.labels) do ok(t.x>=0 and t.y>=0 and t.y+(t.size or 12)<=h,id..' clipped '..t.text) end
            end
        end
        local p=e.ReadingStatsPlan.build('when-you-read',data,600,140,1)
        eq(p.rects[1].h,p.rects[24].h)
        local strip=e.ReadingStatsPlan.build('when-you-read',data,333,85,1)
        eq(strip.rects[1].h,22)
        local week=e.ReadingStatsPlan.build('this-week',data,333,85,1)
        ok(week.rects[7].h>=40,'compact week retains a visible chart')
        eq(Cache.encode(data),before)
        eq(e.ReadingStatsPlan.build('this-week',{state='empty'},300,200,2).message,'No reading recorded')
        local b=e.Budgets.widgets['year-in-reading']
        eq(e.Budgets.check(b,{rows=1,bytes=16385,snapshotBytes=16385,spawns=0,network=0,roundTrips=0}),nil)
        eq(pcall(e.ReadingStatsWidgets.render,'this-week',{padding=string.rep('x',17000)},{w=400,h=300,rows=2}),false)
    end)
    local function has(plan,text)
        for _,v in ipairs(plan.labels) do if v.text:find(text,1,true) then return true end end
        return false
    end
    test('stats: companion display, calendar legend, today, peak and record hierarchy',function()
        local week=e.ReadingStatsPlan.build('this-week',data,330,280,3)
        eq(week.rects[3].level,4); eq(week.rects[7].level,2)
        ok(has(week,'Best day Sunday')); ok(has(week,'2 h 10 m'))
        local year=e.ReadingStatsPlan.build('year-in-reading',data,680,280,3)
        ok(year.rects[365].outline); ok(has(year,'Today')); ok(has(year,'Less')); ok(has(year,'More')); ok(has(year,'Dec'))
        local peak=e.ReadingStatsPlan.build('when-you-read',data,330,180,2)
        ok(has(peak,'Evenings')); ok(has(peak,'19:00'))
        local strip=e.ReadingStatsPlan.build('when-you-read',data,680,85,1)
        ok(strip.rects[20].outline); eq(strip.rects[1].h,strip.rects[24].h)
        local records=e.ReadingStatsPlan.build('reading-records',data,330,280,3)
        eq(records.labels[1].size,40); ok(has(records,'recorded pages, all time')); ok(has(records,'best day')); ok(has(records,'Reading 3 days running'))
    end)
    test('stats: per-field provenance never labels remote sessions as local',function()
        data.sources={days='all your devices',hours='this reader',records='this reader',
            longest_session_seconds='all your devices',best_day_pages='this reader',streak='all your devices'}
        data.local_today_seconds=600; data.display.local_today='10 m today · this reader (separate)'
        eq(e.ReadingStatsPlan.build('year-in-reading',data,600,300,2).source,nil)
        data.sources.days='this reader'
        eq(e.ReadingStatsPlan.build('year-in-reading',data,600,300,2).source,'Days · this reader')
        data.sources.streak='this reader'
        eq(e.ReadingStatsPlan.build('year-in-reading',data,600,300,2).source,'This reader only')
        data.sources.days='all your devices'; data.sources.streak='all your devices'
        local week=e.ReadingStatsPlan.build('this-week',data,600,300,2)
        eq(week.source,nil); ok(has(week,'10 m today · this reader (separate)'))
        eq(e.ReadingStatsPlan.build('when-you-read',data,600,300,2).source,'This reader only')
        local records=e.ReadingStatsPlan.build('reading-records',data,600,300,2)
        eq(records.source,'Pages · this reader')
        ok(has(records,'best day · local')); ok(not has(records,'longest session · this reader'))
        data.sources.streak='this reader'
        ok(has(e.ReadingStatsPlan.build('reading-records',data,600,300,2),'streak · best 4 · local'))
        data.hours_available=false
        eq(e.ReadingStatsPlan.build('when-you-read',data,600,300,2).message,'Enable KOReader statistics')
        data.records_available=false; data.records.books_this_year=17
        local only=e.ReadingStatsPlan.build('reading-records',data,600,300,2)
        ok(has(only,'Local records unavailable')); ok(has(only,'17'))
        data.year=nil
        eq(e.ReadingStatsPlan.build('year-in-reading',data,600,300,2).message,'Reading days unavailable')
    end)
    test('stats: every read state has explicit copy and no invented values',function()
        for _,id in ipairs({'year-in-reading','this-week','when-you-read','reading-records'}) do
            for _,state in ipairs({'empty','error','not-saved','offline-without-data','loading'}) do
                local plan=e.ReadingStatsPlan.build(id,{state=state},330,180,2)
                ok(plan.message); eq(#plan.rects,0); eq(#plan.labels,0)
            end
        end
    end)

    test('retained metrics: compact cards preserve independent provenance and bounded geometry',function()
        local metrics={today={state='ready',source='all your devices',value='1 h 20 m',separate='10 m · this reader, separate'},
            ['reading-streak']={state='ready',source='all your devices',value='7 days',best='Longest: 12 days',days={0,4,4,0,4,4,4},days_source='Last seven days · this reader'},
            ['reading-goal']={state='ready',source='all your devices',value='8 / 24 books · 2026',fraction=1/3,pace='Need 0.5 books / week',status='On pace'},
            ['pages-read']={state='ready',source='this reader',today='17',lifetime='2,345',definition='Timed page visits'},
            ['monthly-reading']={state='ready',source='all your devices',levels={0,.1,.2,.3,.4,.5,.6,.7,.8,.9,1,.5},labels={'D','J','F','M','A','M','J','J','A','S','O','N'},total='20 h 10 m',previous='Previous month: 2 h 10 m',period='Dec 2025 – Nov 2026'}}
        local snapshot={state='ready',metrics=metrics};local before=Cache.encode(snapshot)
        for id in pairs(metrics) do
            local spec=e.WidgetRegistry[id];ok(spec.renderers['android-tablet']);eq(spec.dataNeeds[1].source,'reading.metrics')
            eq(e.Budgets.get('widgets',id).rows,1)
            for _,size in ipairs(spec.sizes['android-tablet']) do
                local w=math.floor(size[1]*690/4)-12;local h=math.floor(size[2]*776/8)-12
                local plan=e.ReadingStatsPlan.build(id,snapshot,w,h,size[2],56)
                for _,r in ipairs(plan.rects) do ok(r.w>=0 and r.h>=0 and r.x>=0 and r.y>=0 and r.x+r.w<=w and r.y+r.h<=h,id) end
                for _,t in ipairs(plan.labels) do ok(t.y>=0 and t.y+t.size<=h,id..' clipped '..t.text) end
            end
        end
        local today=e.ReadingStatsPlan.build('today',snapshot,333,182,2)
        eq(today.source,'All your devices');ok(has(today,'this reader, separate'))
        local streak=e.ReadingStatsPlan.build('reading-streak',snapshot,333,182,2)
        eq(#streak.rects,7);ok(has(streak,'Last seven days · this reader'))
        local pages=e.ReadingStatsPlan.build('pages-read',snapshot,333,182,2)
        eq(pages.source,'This reader only');ok(has(pages,'Timed page visits'))
        local monthly=e.ReadingStatsPlan.build('monthly-reading',snapshot,574,156,2,60)
        eq(#monthly.rects,13);ok(monthly.rects[11].h>=20,'two-row monthly retains a visible chart below measured header')
        local compact=e.ReadingStatsPlan.build('reading-streak',snapshot,282,156,2,60)
        ok(compact.rects[1].y+compact.rects[1].h<=136,'seven-day strip clears its footer')
        -- Home wraps each nested value; the proxy arrays deliberately have length zero.
        local function freeze(v) if type(v)~='table' then return v end;local values={};for k,x in pairs(v) do values[k]=freeze(x) end;return setmetatable({}, {__index=values}) end
        local frozen=freeze(snapshot)
        eq(#frozen.metrics['reading-streak'].days,0)
        eq(#e.ReadingStatsPlan.build('reading-streak',frozen,333,182,2).rects,7)
        eq(#e.ReadingStatsPlan.build('monthly-reading',frozen,678,182,2).rects,13)
        eq(Cache.encode(snapshot),before)
    end)
    test('retained metrics: unknown counts and goals never become zero progress',function()
        local snapshot={metrics={['reading-goal']={state='ready',source='all your devices',value='Target 24 · 2026',status='Completion count unavailable'},today={state='unavailable',reason='Reading time unavailable'}}}
        local goal=e.ReadingStatsPlan.build('reading-goal',snapshot,333,182,2)
        eq(#goal.rects,0);ok(has(goal,'Completion count unavailable'))
        eq(e.ReadingStatsPlan.build('today',snapshot,333,182,2).message,'Reading time unavailable')
        for _,id in ipairs({'today','reading-streak','reading-goal','pages-read','monthly-reading'}) do
            local plan=e.ReadingStatsPlan.build(id,nil,333,182,2);eq(#plan.rects,0);ok(plan.message)
        end
    end)

    -- Battery presentation regressions live in test_battery.lua after the F12-O display projection.
    test('reader duration helper: measured and unavailable values',function()
        eq(e.ReaderPanelPlan.duration(.5,true),'30 min')
        eq(e.ReaderPanelPlan.duration(54),'2 d 6 h')
        eq(e.ReaderPanelPlan.duration(-1),nil); eq(e.ReaderPanelPlan.duration(math.huge),nil)
    end)
end
