-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Reader compositions over the shared kit. Callers own data, navigation and gates.
local Surface={}
function Surface.build(sheet)
    local K=BookSyncUI.new();local p=K.px
    local w,h=sheet.screen_w,sheet.screen_h
    local width=w-p(24)
    local logicalH=h/K.scale
    local top=sheet.screen=="reader-top-panel"
    local bottom=sheet.screen=="reader-bottom-panel"
    local gotoPage=sheet.screen=="reader-goto"
    local search=sheet.navigation_kind=="search"
    local input=sheet.screen=="reader-search"
    local height=p(top and 226 or bottom and 562 or gotoPage and 540 or math.min(748,logicalH-24))
    local c=K.canvas(width,height)
    local rows=sheet.display_rows or {}
    local function track(widget)
        sheet:touchControl(widget,widget.callback)
        return widget
    end
    local function segments(options)
        local widget=K.segments(options)
        for _,control in ipairs(widget[1]) do if control.callback then track(control) end end
        return widget
    end
    local function put(widget,x,y) return K.put(c,widget,p(x),p(y)) end
    local function label(text,x,y,ww,size,opts) return K.label(c,text,p(x),p(y),p(ww),size,opts) end
    local function rule(y,x,ww)
        local line=K.frame(K.canvas(p(ww or 654),p(1)),{w=p(ww or 654),h=p(1)})
        line.background=K.light;put(line,x or 12,y)
    end
    local function button(text,x,y,ww,callback,opts)
        opts=opts or {}
        if opts.enabled==false and opts.icon then text=opts.icon=="arrowL" and "‹" or "›";opts.icon=nil;opts.size=28 end
        opts.text=text;opts.w=p(ww);opts.callback=callback
        opts.h=p(opts.h or 52);opts.variant=opts.variant or "outline"
        local widget
        if opts.icon and text~="" or opts.variant=="ghost" and text~="" then
            local width,height=opts.w,opts.h;local content=K.canvas(width,height)
            local ink=opts.variant~="outline" and opts.variant~="ghost"
            local iconWidth=opts.icon and p(18) or 0;local gap=opts.icon and p(9) or 0
            local t=K.text{text=text,w=width-p(16)-iconWidth-gap,size=opts.size or "body",bold=true,ink=ink}
            local left=math.max(p(8),(width-t:getSize().w-iconWidth-gap)/2)
            if opts.icon then K.put(content,K.icon{name=opts.icon,w=iconWidth,ink=ink},left,(height-iconWidth)/2) end
            K.put(content,t,left+iconWidth+gap,(height-t:getSize().h)/2)
            widget=K.hit(K.frame(content,{w=width,h=height,radius=opts.radius or height/2,
                border=opts.variant=="ghost" and 0 or p(1),ink=ink,transparent=opts.variant=="ghost"}),
                {w=width,h=height,text=text,callback=callback,enabled=opts.enabled})
        else widget=K.button(opts) end
        if opts.enabled==false then widget[1].color=K.light end
        return put(track(widget),x,y)
    end
    local function circle(icon,text,x,y,callback,ink)
        local d=p(52);local tile=K.canvas(d,d)
        local glyph=K.icon{name=icon,w=p(25),ink=ink}
        if text=="Bookmarks" then
            glyph=K.canvas(p(25),p(25))
            for line=1,3 do K.put(glyph,K.frame(K.canvas(p(11),p(2)),{w=p(11),h=p(2),ink=true}),p(1),p(3+line*6)) end
            K.put(glyph,K.icon{name="bookmark",w=p(14)},p(13),p(3))
        end
        K.put(tile,glyph,p(13.5),p(13.5))
        if text=="Add bookmark" or text=="Remove bookmark" then
            K.put(tile,K.icon{name=text=="Add bookmark" and "plus" or "minus",w=p(8),ink=ink},p(22),p(19))
        end
        return put(track(K.hit(K.frame(tile,{w=d,h=d,radius=d/2,border=p(1),ink=ink}),
            {w=d,h=d,text=text,callback=callback})),x,y)
    end
    local function readingSlider(options)
        local slider=K.slider(options)
        slider.callback=function() if options.onChange then options.onChange(math.min(1,(options.value or 0)+.1)) end end
        local paint=slider.paintTo
        function slider:paintTo(bb,x,y)
            paint(self,bb,x,y)
            local value=math.max(0,math.min(1,options.value or 0));local d=p(26);local cy=p(26)
            bb:paintRect(x,y,options.w,p(52),K.white)
            bb:paintRoundedRect(x,y+cy-p(2),options.w,p(4),K.light,p(2))
            if value>0 then bb:paintRoundedRect(x,y+cy-p(2),math.max(p(4),math.floor(options.w*value)),p(4),K.black,p(2)) end
            local xx=x+math.floor((options.w-d)*value)
            bb:paintRoundedRect(xx,y+cy-d/2,d,d,K.black,d/2)
            bb:paintRoundedRect(xx+p(1.5),y+cy-d/2+p(1.5),d-2*p(1.5),d-2*p(1.5),K.white,(d-2*p(1.5))/2)
            bb:paintRoundedRect(xx+p(4),y+cy-d/2+p(4),d-2*p(4),d-2*p(4),K.black,(d-2*p(4))/2)
        end
        return slider
    end
    local function multiline(text,x,y,ww,size,opts)
        opts=opts or {}
        local face=K.text{text="",w=p(ww),size=size,serif=opts.serif}.face
        local tb=require("ui/widget/textboxwidget"):new{text=tostring(text or ""),width=p(ww),face=face,
            height=opts.height and p(opts.height),height_adjust=true,height_overflow_show_ellipsis=true,
            fgcolor=opts.ink and K.white or opts.muted and K.gray or K.black,bold=opts.bold or false}
        return put(tb,x,y)
    end
    local function find(text)
        for _,r in ipairs(rows) do
            if r.text==text then return r.action,r end
            for _,cell in ipairs(r.choices or {}) do if cell.text==text then return cell.callback,cell end end
        end
    end
    local function close() ReaderPanel.close() end
    local function header(title,sub)
        label(title,22,20,570,"medium",{bold=true})
        if sub then label(sub,22,47,580,"caption",{muted=true}) end
        button("",612,14,52,close,{icon="x",variant="ghost"})
        rule(78,0,678)
    end
    local function pages(y)
        local row
        for _,r in ipairs(rows) do if r.kind=="navigation-pages" then row=r end end
        if not row then return end
        rule(y,0,678)
        local result=sheet.navigation
        local count=math.max(1,math.ceil(result.total/row.limit))
        local current=math.floor((result.offset or 0)/row.limit)+1
        button("",22,y+8,52,row.previous,{icon="arrowL",enabled=row.previous~=nil})
        label("Page "..current.." of "..count,280,y+25,200,"caption",{bold=true})
        button("",604,y+8,52,row.next,{icon="arrowR",enabled=row.next~=nil})
    end
    local function nativeOptions()
        for _,r in ipairs(rows) do
            if r.kind=="button" then button("",552,14,52,r.action,{icon="more",variant="ghost"});return end
        end
    end
    if top then
        local r=rows[1]
        button("Home",18,15,92,r.choices[1].callback,{icon="home",size="small"})
        local title=K.text{text=r.text,w=p(348),size=19,serif=true,bold=true}
        put(title,math.max(118,(596-title:getSize().w/K.scale)/2),21)
        local author=K.text{text=r.author,w=p(350),size="caption",muted=true}
        put(author,math.max(118,(596-author:getSize().w/K.scale)/2),46)
        local x=486
        for i=2,#r.choices do local cell=r.choices[i];circle(cell.icon,cell.text,x,15,cell.callback,cell.marked);x=x+62 end
        rule(81)
        for i,cell in ipairs(rows[2].choices) do
            local xx=16+(i-1)*105
            circle(cell.icon,cell.text,xx+(i==6 and 37 or 26.5),98,cell.callback,i==6)
            local text=K.text{text=cell.text,w=p(i==6 and 128 or 105),size="caption",bold=true}
            put(text,i==6 and xx+16 or xx+(105-text:getSize().w/K.scale)/2,158)
        end
        local divider=K.frame(K.canvas(p(1),p(78)),{w=p(1),h=p(78),background=K.light});put(divider,544,96)
        local summary=rows[3].text
        local native=sheet.native or {}
        summary=summary:gsub(" read$","").." · "..(native.time_left or sheet.model.time_left or "Time left unknown")
        local summaryText=K.text{text=summary,w=p(345),size="caption",muted=true}
        put(summaryText,math.max(18,362-summaryText:getSize().w/K.scale),190)
        local battery=find(sheet.model.battery)
        local strip=K.canvas(p(294),p(38))
        local symbol=K.canvas(p(16),p(10));K.put(symbol,K.frame(K.canvas(p(8),p(4)),{w=p(8),h=p(4),ink=true}),p(3),p(3))
        K.put(strip,K.frame(symbol,{w=p(16),h=p(10),border=p(1.5),radius=p(2)}),p(4),p(14))
        K.put(strip,K.frame(K.canvas(p(2),p(4)),{w=p(2),h=p(4),ink=true}),p(21),p(17))
        K.label(strip,sheet.model.battery_short or sheet.model.battery,p(29),p(10),p(260),"caption",{bold=true})
        put(track(K.hit(strip,{w=p(294),h=p(38),text=sheet.model.battery,callback=battery})),366,181)
        -- Keep hardware-key shortcuts without adding unapproved rows to the card.
        track{ text="Reading settings",callback=function() ReaderPanel.show(sheet.ui,"reader-bottom-panel") end }
        track{ text="Back to book",callback=close }
    elseif bottom then
        local native=sheet.native or {}
        local pos,scrub,grids,lights,actions
        grids={}
        for _,r in ipairs(rows) do
            if r.kind=="reader-position" then pos=r elseif r.kind=="scrubber" then scrub=r
            elseif r.kind=="reader-grid" then grids[#grids+1]=r
            elseif r.kind=="reader-lights" then lights=r elseif r.kind=="reader-actions" then actions=r end
        end
        label(pos.text,18,11,470,"small",{bold=true})
        local position=K.text{text=pos.position,w=p(210),size="caption",bold=true}
        put(position,660-position:getSize().w/K.scale,11)
        local previous=button("",14,37,52,scrub.previous,{icon="chevron.first",variant="ghost"})
        previous.icon="chevron.first"
        local slider=readingSlider{w=p(516),value=scrub.value,text="Chapter position",onChange=function(v) scrub.seek(v*100) end}
        local stock=slider.paintTo
        function slider:paintTo(bb,x,y)
            stock(self,bb,x,y)
            for _,v in ipairs(scrub.chapters or {}) do
                bb:paintRect(x+math.floor(v*p(516)),y+p(20),p(1.5),p(12),v<=(scrub.value or 0) and K.black or K.gray)
            end
            for _,v in ipairs(scrub.bookmarks or {}) do bb:paintRect(x+math.floor(v*p(516)),y+p(5),p(4),p(8),K.black) end
        end
        slider.callback=function() sheet.scrub_focus=not sheet.scrub_focus;sheet.keyboard_focus=true;sheet:build();UIManager:setDirty(sheet,"ui") end
        put(track(slider),80,38)
        if not sheet.focus_index then sheet.focus_index=2 end
        button("",610,37,52,scrub.next,{icon="chevron.last",variant="ghost"})
        label(sheet.scrub_focus and "Prev/Next: chapter · Select/Back: done" or native.chapter_time_left or sheet.model.chapter_time_left or "Chapter time unknown",72,87,300,"caption",{muted=true})
        label(native.time_left or sheet.model.time_left or "Book time unknown",494,87,170,"caption",{muted=true})
        rule(121,16,646)
        local function group(r,x,y)
            local groupWidth=308
            local heading=(r.group_label or ""):match("^[^·]+") or ""
            label(heading:upper(),x,y,groupWidth,"caption",{bold=true,muted=true})
            if heading:find("Size",1,true) then
                local size=r.group_label:match("· (.*)") or ""
                local value=K.text{text=size:upper(),w=p(110),size="caption",bold=true,muted=true}
                put(value,x+groupWidth-value:getSize().w/K.scale,y)
                local box=K.canvas(p(groupWidth),p(54))
                K.put(box,K.text{text="A",w=p(30),size=14,serif=true,bold=true},p(20),p(17))
                local selected=ReaderPanelPlan.sizeIndex(tonumber(r.group_label:match("· (%d+)")) or 18)
                for i=1,6 do
                    local d=p(i==selected and 10 or 6);local dot=K.frame(K.canvas(d,d),{w=d,h=d,radius=d/2,background=i<=selected and K.black or K.light})
                    K.put(box,dot,p(124+(i-1)*10)-d/2,p(29)-d/2)
                end
                K.put(box,K.text{text="A",w=p(36),size=25,serif=true,bold=true},p(270),p(12))
                put(K.frame(box,{w=p(groupWidth),h=p(54),radius=p(12),border=p(1)}),x,y+27)
                for i,index in ipairs({1,3}) do
                    local hit=K.hit(K.canvas(p(150),p(54)),{w=p(150),h=p(54),text=r.choices[index].text,callback=r.choices[index].callback})
                    put(track(hit),x+(i-1)*158,y+27)
                end
            elseif heading=="Status bar" then
                for i,cell in ipairs(r.choices) do
                    local xx=x+(i-1)*158
                    put(track(K.toggle{text=cell.text,w=p(46),h=p(27),value=r.values[i],onChange=cell.callback}),xx+4,y+39)
                    label(i==1 and "Bottom bar" or "Clock",xx+59,y+43,100,"small")
                end
            else
                local selected=0;local names={}
                for i,cell in ipairs(r.choices) do
                    local name,detail,active=ReaderPanelPlan.segment(cell)
                    names[i]=name..(detail and "\n"..detail or "")
                    if active then selected=i end
                end
                if r.key=="font" and names[selected] then
                    local value=K.text{text=names[selected]:gsub("\n.*$",""),w=p(160),size="caption",muted=true,bold=true}
                    put(value,x+groupWidth-value:getSize().w/K.scale,y)
                end
                -- Segment shape and selection are shared with Home; specimens and
                -- custom values sit inside their own bounded segment content.
                local box=K.canvas(p(groupWidth),p(54))
                for i,cell in ipairs(r.choices) do
                    local cw=groupWidth/#r.choices;local name,detail=ReaderPanelPlan.segment(cell)
                    local face=r.key=="font"
                    local sub=K.canvas(p(cw),p(54))
                    if face then
                        local specimen=K.text{text="Aa",w=p(cw),size=19,serif=true,ink=i==selected}
                        K.put(sub,specimen,(p(cw)-specimen:getSize().w)/2,p(8))
                    end
                    local text=K.text{text=name,w=p(cw-8),size=face and 10 or 14,bold=true,ink=i==selected}
                    local textX=(p(cw)-text:getSize().w)/2
                    if not detail and (r.key=="margins" or r.key=="spacing") then
                        local iw=p(18);local gap=p(8);local left=(p(cw)-text:getSize().w-iw-gap)/2
                        local icon=K.canvas(iw,iw);local color=i==selected and K.white or K.black
                        if r.key=="margins" then
                            for line=1,3 do K.put(icon,K.frame(K.canvas(p(i==1 and 5 or 10),p(1.5)),{w=p(i==1 and 5 or 10),h=p(1.5),background=color}),p(i==1 and 6 or 4),p(4+line*3)) end
                            icon=K.frame(icon,{w=iw,h=iw,radius=p(2),border=p(1.5),transparent=true,color=color})
                        else
                            for line=1,3 do K.put(icon,K.frame(K.canvas(p(14),p(1.5)),{w=p(14),h=p(1.5),background=color}),p(2),p(3+line*5)) end
                        end
                        K.put(sub,icon,left,p(18));textX=left+iw+gap
                    end
                    K.put(sub,text,textX,p(face and 31 or detail and 10 or 18))
                    if detail and not face then
                        local value=K.text{text=detail,w=p(cw-8),size=10,bold=true,ink=i==selected}
                        local editable=i==selected
                        local left=(p(cw)-value:getSize().w-(editable and p(12) or 0))/2
                        K.put(sub,value,left,p(31))
                        if editable then K.put(sub,K.icon{name="edit",w=p(9),ink=true},left+value:getSize().w+p(3),p(33)) end
                    end
                    local active=i==selected
                    if active and (i==1 or i==#r.choices) then
                        K.put(sub,K.frame(K.canvas(p(12),p(54)),{w=p(12),h=p(54),ink=true}),i==1 and p(cw-12) or 0,0)
                    end
                    local widget=K.hit(K.frame(sub,{w=p(cw),h=p(54),ink=active,transparent=not active,
                        radius=p(active and (i==1 or i==#r.choices) and 12 or 0)}),
                        {w=p(cw),h=p(54),text=cell.text,callback=cell.callback})
                    K.put(box,track(widget),p((i-1)*cw),0)
                end
                for i=2,#r.choices do
                    K.put(box,K.frame(K.canvas(p(1),p(54)),{w=p(1),h=p(54),ink=true}),p((i-1)*groupWidth/#r.choices),0)
                end
                put(K.frame(box,{w=p(groupWidth),h=p(54),radius=p(12),border=p(1)}),x,y+27)
            end
        end
        for index,r in ipairs(grids) do for i,g in ipairs(r.groups) do group(g,i==1 and 18 or 350,132+(index-1)*92) end end
        if #grids==0 then
            for _,r in ipairs(rows) do if r.group_label=="Status bar" then group(r,18,140) end end
            label("This document uses KOReader's native style settings",18,246,620,"small",{muted=true})
        end
        label("FRONT LIGHT & WARMTH",18,409,500,"caption",{bold=true,muted=true})
        if lights then
            for i,r in ipairs(lights.controls) do
                local x=i==1 and 18 or 350
                label(r.name=="warmth" and "☾" or "☼",x,452,36,24)
                put(track(readingSlider{w=p(218),value=r.value/100,text=r.text,onChange=function(v) r.set(math.floor(v*100+.5)) end}),x+42,435)
                label(r.value,x+286,452,32,"small",{bold=true})
            end
        else label("Controlled by your reader's system light settings",18,452,620,"small",{muted=true}) end
        rule(501,16,646)
        button("More reading settings…",18,506,252,actions.choices[1].callback,{icon="kmenu",variant="ghost",size="small",h=46})
        label("KOReader's style menu",276,522,216,"small")
        button("Edit presets",575,506,94,actions.choices[2].callback,{variant="ghost",size=13,h=46})
        put(K.frame(K.canvas(p(77),p(1)),{w=p(77),h=p(1),ink=true}),583,536)
    elseif gotoPage then
        header("Go to",sheet.go_error or (sheet.go_percent and "Percent 0 to 100" or "Page 1 to "..tostring(sheet.go_total or "—")))
        button("",552,14,52,function() close();Library.readerNativeAction(sheet.ui,"goto") end,{icon="more",variant="ghost"})
        put(segments{w=p(360),h=p(54),items={"Page","% Percent"},selected=sheet.go_percent and 2 or 1,onChange=function(i)
            sheet.go_percent=i==2;sheet.go_value="";sheet.go_error=nil;sheet:build();UIManager:setDirty(sheet,"ui")
        end},159,94)
        local value=K.text{text=sheet.go_value=="" and "—" or sheet.go_value,w=p(300),size=56,bold=true}
        put(value,(678-value:getSize().w/K.scale)/2,164)
        label(sheet.go_percent and "%" or "/ "..tostring(sheet.go_total or "—"),388,202,140,"medium",{muted=true})
        rule(240,248,132)
        for index,key in ipairs({"1","2","3","4","5","6","7","8","9","←","0","Go"}) do
            local x=105+((index-1)%3)*160;local y=254+math.floor((index-1)/3)*68
            local callback=key=="Go" and sheet.go_submit or function() sheet.go_edit(key=="←" and "back" or key) end
            button(key,x,y,150,callback,{h=58,size=key=="Go" and 16 or 28,radius=p(8),variant=key=="Go" and "solid" or "outline"})
        end
    elseif input then
        header("Search in this book","Enter a word or phrase")
        button("",552,14,52,function() close();Library.readerNativeAction(sheet.ui,"search") end,{icon="more",variant="ghost"})
        local field=K.canvas(p(634),p(52))
        K.put(field,K.icon{name="search",w=p(24)},p(14),p(14))
        sheet.search_input=require("ui/widget/inputtext"):new{text=sheet.search_query or "",hint="Search this book…",width=p(410),height=p(40),
            padding=0,margin=0,bordersize=0,face=K.text{text="",size="body",w=p(410)}.face,parent=sheet,enter_callback=sheet.search_submit}
        K.put(field,sheet.search_input,p(54),p(7))
        local option=K.canvas(p(140),p(52))
        K.label(option,sheet.search_whole and "Whole words" or "Any text",p(8),p(16),p(128),"caption",{muted=true})
        K.put(field,track(K.hit(option,{w=p(140),h=p(52),text="Whole words",callback=function()
            sheet.search_whole=not sheet.search_whole
            sheet.search_query=sheet.search_input:getText();sheet.search_input:onCloseKeyboard()
            sheet:build();sheet.search_input:onShowKeyboard();UIManager:setDirty(sheet,"ui")
        end})),p(486),0)
        put(K.frame(field,{w=p(634),h=p(52),border=p(2),radius=p(12)}),22,94)
        button("Search",22,162,156,sheet.search_submit,{icon="search",variant="solid"})
    elseif sheet.navigation then
        local result=sheet.navigation;local kind=sheet.navigation_kind
        local summary=rows[2].text
        if kind=="contents" and result.current then summary=result.total.." chapters · you're in chapter "..result.current end
        if search and result.query then summary=(result.capped and "First 128" or result.total)..' matches for “'..result.query..'”' end
        header(rows[1].text,summary)
        local y=92
        if search then
            local field=K.canvas(p(634),p(52))
            K.put(field,K.icon{name="search",w=p(22)},p(14),p(15))
            K.label(field,result.query or "Search this book…",p(40),p(15),p(430),"body",{bold=true})
            put(K.frame(field,{w=p(634),h=p(52),radius=p(12),border=p(2)}),22,94)
            put(track(K.hit(K.canvas(p(480),p(52)),
                {w=p(480),h=p(52),text="Search this book",callback=function() ReaderPanel.searchDialog(sheet.ui) end})),22,94)
            local option=K.canvas(p(140),p(52))
            K.label(option,result.whole_words and "Whole words" or "Any text",p(8),p(16),p(128),"caption",{muted=true})
            put(track(K.hit(option,{w=p(140),h=p(52),text="Whole words",callback=function()
                ReaderPanel.search(sheet.ui,result.query or "",not result.whole_words)
            end})),508,94)
            y=164
        elseif kind=="annotations" then
            put(segments{w=p(634),h=p(54),items={"Highlights","Bookmarks","Notes"},selected=sheet.annotation_tab=="Highlights" and 1 or sheet.annotation_tab=="Bookmarks" and 2 or 3,
                onChange=function(i) ReaderPanel.navigation(sheet.ui,kind,result.offset,({"Highlights","Bookmarks","Notes"})[i]) end},22,94)
            y=168
        end
        local count=0
        for _,r in ipairs(rows) do if r.kind=="navigation-item" then
            local item=r.item
            local visible=kind~="annotations" or sheet.annotation_tab=="Bookmarks" and item.annotation_kind=="bookmark"
                or sheet.annotation_tab=="Highlights" and item.annotation_kind=="highlight" or sheet.annotation_tab=="Notes" and item.note and item.note~=""
            if visible then
                count=count+1
                if kind=="contents" then
                    local active=item.current;local row=K.canvas(p(658),p(52))
                    if not active then K.put(row,K.frame(K.canvas(p(658),p(26)),{w=p(658),h=p(26)}),0,0) end
                    K.label(row,item.index,p(12),p(17),p(35),"small",{bold=true,ink=active,muted=item.finished})
                    K.label(row,item.title,p(50+item.depth*12),p(17),p(active and 450 or 520),"body",{bold=active,ink=active,muted=item.finished})
                    if active then
                        local badge=K.canvas(p(84),p(22));K.label(badge,"You're here",p(8),p(3),p(76),"caption",{bold=true,ink=true})
                        K.put(row,K.frame(badge,{w=p(84),h=p(22),radius=p(11),border=p(1),ink=true,color=K.white}),p(514),p(15))
                    elseif item.finished then K.label(row,"✓",p(582),p(17),p(22),"small",{muted=true}) end
                    K.label(row,item.location,p(622),p(17),p(36),"small",{ink=active,muted=not active})
                    put(track(K.hit(K.frame(row,{w=p(658),h=p(52),radius=p(12),border=not active and p(.5) or 0,color=K.light,ink=active}),{w=p(658),h=p(52),text=item.title,callback=r.action})),10,y)
                    y=y+52
                else
                    local quote=item.quote or item.title
                    local TB=require("ui/widget/textboxwidget")
                    if search and item.match and TB.PTF_HEADER then
                        local function plain(value) return (value or ""):gsub("[\239][\191][\177-\179]","") end
                        quote=TB.PTF_HEADER.."…"..plain(item.before).." "..TB.PTF_BOLD_START..plain(item.match)..TB.PTF_BOLD_END.." "..plain(item.after).."…"
                    end
                    local face=K.text{text="",w=p(610),size=16,serif=true}.face
                    local quoteWidget=TB:new{text=quote,width=p(610),height=p(51),height_adjust=true,
                        height_overflow_show_ellipsis=true,face=face}
                    local quoteH=math.ceil(quoteWidget:getSize().h/K.scale)
                    local hasNote=item.note and item.note~=""
                    local noteH=hasNote and 26 or 0
                    local rh=quoteH+noteH+32
                    local block=K.canvas(p(634),p(rh))
                    K.put(block,quoteWidget,p(kind=="annotations" and 14 or 0),0)
                    if kind=="annotations" then K.put(block,K.frame(K.canvas(p(3),p(quoteH)),{w=p(3),h=p(quoteH),ink=true}),0,0) end
                    if hasNote then
                        K.put(block,K.icon{name="edit",w=p(12)},p(14),p(quoteH+6))
                        K.label(block,item.note,p(35),p(quoteH+4),p(580),"small",{bold=true})
                    end
                    K.label(block,(item.chapter and item.chapter~="" and item.chapter.." · " or "")..(item.location~="" and "p. "..item.location or "Position saved"),p(kind=="annotations" and 14 or 0),p(quoteH+noteH+8),p(600),"caption",{muted=true})
                    put(track(K.hit(block,{w=p(634),h=p(rh),text=item.title,callback=r.action})),22,y)
                    rule(y+rh-4,22,634);y=y+rh+10
                end
            end
        end end
        if count==0 then
            label(result.unavailable and "Open native options to load this book's data" or search and "No matches" or "No "..(sheet.annotation_tab or "chapters"):lower()..((result.next or (result.offset or 0)>0) and " on this page" or ""),22,y+24,620,"medium",{bold=true})
            if search then label("Try another word or phrase.",22,y+62,620,"small",{muted=true}) end
        end
        nativeOptions()
        pages(height/K.scale-64)
    else
        local m=sheet.model
        header(sheet.screen=="details" and "Full details" or "Book info")
        put(K.cover{w=p(132),h=p(198),title=m.title,author=m.author,file=m.cover_path},22,96)
        label(m.title,170,96,480,"title",{serif=true,bold=true})
        label(m.author,170,133,480,"body")
        if m.series_line then
            local link=K.canvas(p(480),p(36));local text=K.text{text=m.series_line,w=p(448),size="small",bold=true}
            K.put(link,K.icon{name="stack",w=p(16)},0,p(8));K.put(link,text,p(22),p(5))
            K.put(link,K.frame(K.canvas(text:getSize().w,p(1)),{w=text:getSize().w,h=p(1),ink=true}),p(22),p(27))
            put(track(K.hit(link,{w=p(480),h=p(36),text=m.series_line,callback=find("View series")})),170,161)
        end
        local stats={{"PAGES",m.total_pages},{"READ",m.progress_text},{"STARTED",m.started},{"TIME READ",m.time}}
        for i,pair in ipairs(stats) do
            local x=170+((i-1)%2)*250;local y=198+math.floor((i-1)/2)*44
            local value=tostring(pair[2] or "Not saved yet")
            if value:find("not saved yet",1,true) then value="Not saved yet" end
            label(pair[1],x,y,225,"caption",{bold=true,muted=true});label(value,x,y+17,225,"small",{bold=true})
        end
        multiline(m.description or "Description not saved yet",22,314,634,16,{serif=true,height=126})
        local details=find("Details");local series=find("View series")
        if details then button("Full details",22,448,134,details,{icon="info",size="small"}) end
        if series then button("View series",166,448,138,series,{icon="stack",size="small"}) end
        local open=find("Open") or find("Download") or find("Set up downloads")
        if open then button(find("Open") and "Open" or "Download",22,516,160,open) end
    end
    sheet.sheet_h=height
    sheet.sheet_y=top and p(10) or h-height-p(10)
    sheet.sheet_x=p(12)
    sheet.plan={h=sheet.sheet_h,inner=width,items={}}
    sheet.too_small=height>h-p(12) or (not top and not bottom and logicalH<300)
    sheet.frame=K.frame(c,{w=width,h=height,radius=p(20),border=p(2)})
    local full=K.canvas(w,h)
    if sheet.backdrop and sheet.backdrop.onCloseWidget then sheet.backdrop:onCloseWidget() end
    sheet.backdrop=require("ui/widget/container/alphacontainer"):new{alpha=sheet.alpha,K.frame(K.canvas(w,h),{w=w,h=h})}
    K.put(full,sheet.backdrop,0,0)
    K.put(full,sheet.frame,sheet.sheet_x,sheet.sheet_y)
    sheet[1]=full
end
return Surface
