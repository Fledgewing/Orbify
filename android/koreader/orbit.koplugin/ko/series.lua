-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Series and grouped lists belong to the existing Home host, not a second screen stack.
SeriesUI = {}
function SeriesUI.paint(host)
    local K=CatalogUI.kit();local p=K.px
    local w,h=host.dimen.w,host.dimen.h
    local top,bottom,row=p(365),p(68),p(92)
    local count=math.max(1,math.min(8,math.floor((h-top-bottom)/row)))
    local paint=Library.paint("series")
    host.caps=paint:capabilities()
    local result
    if host.caps.series and host.caps.series.read==false then result={error="unsupported"}
    else result=paint:series(host.series_key,host.series_offset,count+4) end
    host.series_result,host.series_limit=result,count
    local c=K.canvas(w,h);local edge=p(24)
    K.header(c,{w=w,title="Series",backText="‹ Back",back=function() host:onClose() end,search=function() host:search() end})
    local state,label=SeriesPlan.state(result);host.catalog_state=state
    if state=="ready" or state=="offline-with-data" then
        if label then K.label(c,label,p(110),p(42),w-p(240),"caption",{muted=true}) end
        K.label(c,result.title or "Series",edge,p(78),w-2*edge,28,{serif=true,bold=true})
        K.label(c,result.subtitle or "",edge,p(120),w-2*edge,"small",{muted=true})
        local dots=result.dots or {};local n=math.min(#dots,24)
        for i=1,n do
            local width=math.floor((w-2*edge-p(6)*(n-1))/n)
            K.put(c,K.frame(K.progress{w=width,h=p(8),value=SeriesPlan.dot(dots[i])},{w=width,h=p(8),border=p(1),radius=p(4)}),edge+(i-1)*(width+p(6)),p(151))
        end
        if result.dot_caption then K.label(c,result.dot_caption,edge,p(160),w-2*edge,"caption",{muted=true}) end
        local nextBooks=result.next_books or {};local enabled=host.caps.series and host.caps.series.downloadNext==true and not result.membership_incomplete
        local cardHeight=#nextBooks>0 and 178 or 76
        top=p(177+cardHeight+10)
        host.series_card_height=p(cardHeight)
        local card={content=K.canvas(w-2*edge,p(cardHeight))}
        K.label(card.content,#nextBooks>0 and "Download the next "..#nextBooks or "Series on this device",p(17),p(20),p(360),"body",{bold=true})
        K.label(card.content,result.membership_incomplete and "Saved membership incomplete" or #nextBooks>0 and "Keeps the series ready offline" or result.earlier_pending and "Earlier unread books available" or result.remaining_saved and "Every remaining book is on this device" or result.local_known and "No remaining books" or "Device state not saved",p(17),p(45),w-2*edge-p(34),"caption",{muted=true})
        K.put(card.content,K.button{text=#nextBooks>0 and "Download next "..#nextBooks or "Series downloads…",w=p(204),icon=#nextBooks>0 and "arrowD" or nil,enabled=enabled,
            callback=function() SeriesUI.download(host) end},w-2*edge-p(221),p(16))
        for i,b in ipairs(nextBooks) do
            K.action(card.content,tostring(b.number or i),nil,p(17),p(80+(i-1)*30),p(24),p(24),nil,true,true)
            K.label(card.content,b.title or "Untitled",p(51),p(80+(i-1)*30),w-2*edge-p(85),"small",{bold=true})
        end
        K.put(c,K.frame(card.content,{w=w-2*edge,h=p(cardHeight),border=p(2),radius=p(16)}),edge,p(177))
        for i,b in ipairs(result.items or {}) do
            K.bookRow(c,b,edge,top+(i-1)*row,w-2*edge,row,function() host:dispatch("book",b) end,function() host:dispatch("more",b) end)
        end
    else
        K.label(c,label or "No books",edge,p(90),w-2*edge,"body")
        if result.error or state=="offline-without-data" then K.put(c,K.button{text="Retry",w=p(130),callback=function() Library.retry();host:rebuild();UIManager:setDirty(host,"ui") end},edge,p(140)) end
    end
    if result.next or (result.offset or 0)>0 then
        K.pager(c,{w=w,h=h,offset=host.series_offset or 0,limit=count,total=result.total,forwardEnabled=result.next~=nil,
            previous=function() SeriesUI.page(host,-1) end,next=function() SeriesUI.page(host,1) end})
    end
    CatalogUI.install(host,K,c,paint:flush());CatalogUI.refresh(host,result.pending)
end
function SeriesUI.page(host,delta)
    local result=host.series_result or {}
    if delta>0 and not result.next then return true end
    host.series_offset=delta>0 and result.next or math.max(0,host.series_offset-(host.series_limit or 1))
    host:rebuild(); UIManager:setDirty(host,"ui"); return true
end
function SeriesUI.groups(host)
    local K=CatalogUI.kit();local p=K.px;local w,h=host.dimen.w,host.dimen.h
    local paint=Library.paint(host.filter.model.source=="search" and "search" or "library")
    host.caps=paint:capabilities()
    local settings=host.list_layout.pages[1].placements[1].settings
    local count=math.max(1,math.min(4,math.floor((h-p(220))/p(154))))
    local covers=math.max(1,math.min(9,math.floor((w-p(48))/p(72))))
    local result=paint:groups(settings.source,settings.query,settings.offset,24,settings.exclude_current,covers,count)
    host.list_result,host.list_limit=result,#(result.items or {})
    local c=K.canvas(w,h);local edge=p(24);local f=host.filter:header(result.total)
    K.header(c,{w=w,title=host.list_title,subtitle=f.subtitle,back=function() host:onClose() end,search=function() host:search() end,filter=f.callback,filterActive=f.active})
    local x=edge
    for _,chip in ipairs(f.chips) do
        local width=K.text{text=chip.label,w=w-2*edge,size="small",bold=true}:getSize().w+p(52)
        if x+width>w-edge then break end
        K.put(c,K.button{text=chip.label,trailingIcon="x",w=width,size="small",variant="outline",callback=chip.callback},x,p(74));x=x+width+p(10)
    end
    local state,label=SeriesPlan.state(result);host.catalog_state=state
    if label then K.label(c,label,edge,p(131),w-2*edge,"caption") end
    for i,row in ipairs(result.items or {}) do
        local y=p(150)+(i-1)*p(154)
        local go=function()
            if row.series_key then host:showSeries(row.series_key)
            else host:showList(row.title,settings.source,SeriesPlan.groupQuery(settings.query,row),settings.exclude_current) end
        end
        local heading=K.canvas(w-2*edge,p(38))
        K.action(heading,"Group",row.field=="author" and "person" or "stack",0,0,p(18),p(32))
        K.label(heading,row.title or "",p(28),p(5),w-p(310),"body",{bold=true})
        local detail=K.text{text=(row.count_text or "")..((row.series_key or row.partial) and "  ›" or ""),w=p(144),size="caption",bold=true}
        K.put(heading,detail,w-2*edge-detail:getSize().w,p(9))
        K.put(c,K.hit(heading,{text=row.title,w=w-2*edge,h=p(38),callback=(row.series_key or row.partial) and go or nil}),edge,y)
        for j,b in ipairs(row.books or {}) do
            local bx=edge+(j-1)*p(72)
            K.put(c,K.hit(K.jacket{file=b.cover_path,title=b.title,author=b.authors and b.authors[1],w=p(63),h=p(94)},
                {text=b.title,w=p(63),h=p(94),callback=function() host:dispatch("book",b) end}),bx,y+p(39))
        end
        local dots=row.dots or {};local n=math.min(5,#dots)
        for j=1,n do K.put(c,K.frame(K.progress{w=p(18),h=p(7),value=SeriesPlan.dot(dots[j])},{w=p(18),h=p(7),border=p(1),radius=p(3)}),w-p(216)+(j-1)*p(22),y+p(15)) end
        K.separator(c,edge,y+p(143),w-2*edge)
    end
    K.pager(c,{w=w,h=h,offset=settings.offset or 0,limit=count,page=1+#(host.group_offsets or {}),forwardEnabled=result.next~=nil,
        previous=function() host:listPage(-1) end,next=function() host:listPage(1) end})
    CatalogUI.install(host,K,c,paint:flush());CatalogUI.refresh(host,result.pending)
end
-- Group pages consume variable numbers of preview rows; retain actual cursors for Back.
function SeriesUI.groupPage(host,delta)
    local settings=host.list_layout.pages[1].placements[1].settings
    local result=host.list_result or {}
    host.group_offsets=host.group_offsets or {}
    if delta>0 then
        if not result.next then return true end
        host.group_offsets[#host.group_offsets+1]=settings.offset
        settings.offset=result.next
    else
        settings.offset=table.remove(host.group_offsets) or 0
    end
    host:rebuild(); UIManager:setDirty(host,"ui"); return true
end
-- Public entry for Details/Book info and the later end sheet, with no end transport dependency.
function SeriesUI.show(key,onBack)
    if not key then return false end
    local wasHome=HomeHost.foreground()
    if not wasHome and not HomeHost.show() then return false end
    local host=HomeHost.active
    host:showSeries(key,function()
        if not wasHome then UIManager:close(host)
        else host:rebuild(); UIManager:setDirty(host,"ui") end
        if onBack then onBack() end
    end)
    return true
end

-- Every dialog below follows an explicit Series download action. Async callbacks
-- retain the originating host and never open a book or resurrect a departed sheet.
function SeriesUI.download(host)
    local seriesKey=host.series_key
    local function wanted() return HomeHost.active==host and host.series_key==seriesKey and not reading() end
    local function visible(dialog) return wanted() and UIManager:getTopmostVisibleWidget()==dialog end
    local function show(title,buttons)
        assert(#buttons+1<=Budgets.get("screens","series-downloads").displayRows,"Series display row budget exceeded")
        local finish=Budgets.span("series-downloads.paint",now_s,log)
        local dialog=require("ui/widget/buttondialog"):new{title=title,buttons=buttons}
        UIManager:show(dialog) -- gate: user action (approved Series preview and queue)
        finish();return dialog
    end
    local function notice(text)
        local dialog
        dialog=show(text,{{{text="Back",callback=function() UIManager:close(dialog) end}}})
    end
    local function monitor(result)
        if not wanted() then return end
        if result.error or not result.id then notice("Series downloads unavailable · Try again");return end
        local dialog,closed,pending=nil,false,false
        local function paint(value)
            local buttons={}
            for _,row in ipairs(value.items or {}) do
                local item=row
                buttons[#buttons+1]={{text=(item.title or "Book").." · "..(item.progress_text or item.state or "")..(item.state~="complete" and item.id and " · Cancel" or ""),enabled=item.id~=nil and item.state~="complete" and item.state~="canceled",callback=function()
                    pending=true
                    Library.catalogAction("download.cancel",{id=item.id},function()
                        Library.seriesCommand("status",{id=value.id},function(nextValue) pending=false;if visible(dialog) then UIManager:close(dialog);closed=true;monitor(nextValue) end end)
                    end)
                end}}
            end
            if value.state=="paused" then buttons[#buttons+1]={{text=NetworkMgr:isConnected() and "Resume remaining" or "Connect and resume remaining",callback=function()
                if pending then return end
                pending=true
                local function resume(ready)
                    if not visible(dialog) then return end
                    if not ready then pending=false;return end
                    Library.seriesCommand("resume",{id=value.id},function(nextValue) pending=false;if visible(dialog) then UIManager:close(dialog);closed=true;monitor(nextValue) end end)
                end
                if NetworkMgr:isConnected() then resume(true) else Library.downloadConnect(resume) end
            end}} end
            if value.state~="complete" then buttons[#buttons+1]={{text="Cancel remaining",callback=function()
                pending=true;Library.seriesCommand("cancel",{id=value.id},function(nextValue) pending=false;if visible(dialog) then UIManager:close(dialog);closed=true;monitor(nextValue) end end)
            end}} end
            buttons[#buttons+1]={{text="Back",callback=function() closed=true;UIManager:close(dialog);DownloadUI.update(host) end}}
            dialog=show(value.summary or "Series downloads",buttons)
            dialog.tap_close_callback=function() closed=true end
        end
        paint(result)
        local function poll()
            if closed or not visible(dialog) or result.state=="complete" then return end
            if pending then UIManager:scheduleIn(1,poll);return end
            pending=true
            Library.seriesCommand("status",{id=result.id},function(value)
                pending=false
                if closed or not visible(dialog) then return end
                if not value.error and (tonumber(value.sequence) or 0)>=(tonumber(result.sequence) or 0) then
                    if UIUtil.encode(value)~=UIUtil.encode(result) then UIManager:close(dialog);result=value;paint(value) end
                end
                UIManager:scheduleIn(1,poll)
            end)
        end
        UIManager:scheduleIn(1,poll)
    end
    local params={key=host.series_key,count=3,root=Library.downloadRoot()}
    local function arguments()
        local result={};for key,value in pairs(params) do result[key]=value end;return result
    end
    local preview
    local function resolve(plan)
        local choices,labels={},{}
        local function file(index)
            if not wanted() then return end
            local row=(plan.items or {})[index]
            if not row then
                local buttons={}
                for _,line in ipairs(labels) do if line~="" then buttons[#buttons+1]={{text=line,enabled=false}} end end
                local dialog
                buttons[#buttons+1]={{text="Start downloads",callback=function()
                    UIManager:close(dialog)
                    local args=arguments();args.token=plan.token;args.choices=choices
                    Library.seriesCommand("start",args,function(value) if wanted() and UIManager:getTopmostVisibleWidget()==host then monitor(value) end end)
                end},{text="Back",callback=function() UIManager:close(dialog);preview() end}}
                dialog=show("Download "..#plan.items.." books?",buttons)
                return
            end
            Library.seriesFile(row,params.root,function(options)
                if not wanted() or UIManager:getTopmostVisibleWidget()~=host then return end
                if options.error then notice((row.title or "Book").." · File choices unavailable · Try again");return end
                if #(options.items or {})==0 then
                    labels[#labels+1]=(row.title or "Book").." · No supported file · will fail"
                    file(index+1);return
                end
                local function selected(choice)
                    choices[row.key]={file_reference=choice.file_reference,variant=choice.variant}
                    labels[#labels+1]=(row.title or "Book").." · "..(choice.label or "File").." · "..(choice.bytes and tostring(choice.bytes).." bytes" or "size unknown")
                    params.root=params.root or options.root or Library.downloadRoot()
                    if index==1 then labels[#labels+1]=options.items[1].destination_label or "" end
                    file(index+1)
                end
                if #options.items==1 then selected(options.items[1]);return end
                local buttons,dialog={}
                for _,choice in ipairs(options.items) do
                    local item=choice
                    buttons[#buttons+1]={{text=(item.label or "File").." · "..(item.bytes and tostring(item.bytes).." bytes" or "size unknown"),callback=function() UIManager:close(dialog);selected(item) end}}
                end
                buttons[#buttons+1]={{text="Cancel",callback=function() UIManager:close(dialog) end}}
                dialog=show("Choose file · "..(row.title or "Book"),buttons)
            end)
        end
        file(1)
    end
    preview=function()
        Library.seriesCommand("preview",arguments(),function(plan)
            if not wanted() or UIManager:getTopmostVisibleWidget()~=host then return end
            if plan.error then notice(plan.error=="incomplete" and "Saved membership incomplete · Refresh the catalog before downloading" or "Series preview unavailable");return end
            if #(plan.items or {})==0 and not plan.earlier_key then notice("No eligible books after this position. Nothing will wrap to the beginning.");return end
            local title="Download next "..params.count.." · "..#plan.items.." available"
            local buttons={}
            for _,row in ipairs(plan.items) do buttons[#buttons+1]={{text=(row.number and tostring(row.number).." · " or "")..(row.title or "Book").." · "..(row.bytes and tostring(row.bytes).." bytes" or "size unknown"),enabled=false}} end
            local dialog
            buttons[#buttons+1]={{text=NetworkMgr:isConnected() and "Review files" or "Connect and download "..#plan.items,enabled=#plan.items>0,callback=function()
                UIManager:close(dialog)
                if NetworkMgr:isConnected() then resolve(plan) else Library.downloadConnect(function(ready)
                    if wanted() and UIManager:getTopmostVisibleWidget()==host then if ready then resolve(plan) else notice("Could not connect · Try again") end end
                end) end
            end}}
            buttons[#buttons+1]={{text="Change number (1–10)",callback=function()
                UIManager:close(dialog)
                local input
                input=require("ui/widget/inputdialog"):new{title="Download how many? (1–10)",input=tostring(params.count),input_type="number",buttons={{{text="Cancel",callback=function() UIManager:close(input) end},{text="Review",callback=function()
                    local n=tonumber(input:getInputText())
                    if n and n==math.floor(n) and n>=1 and n<=10 then params.count=n;UIManager:close(input);preview() end
                end}}}}
                UIManager:show(input) -- gate: user action (approved Series count editor)
                input:onShowKeyboard()
            end}}
            if plan.earlier_key then buttons[#buttons+1]={{text="Start at earlier gap · "..(plan.earlier_title or "Book"),callback=function() params.start_key=plan.earlier_key;UIManager:close(dialog);preview() end}} end
            buttons[#buttons+1]={{text="Cancel",callback=function() UIManager:close(dialog) end}}
            dialog=show(title,buttons)
        end)
    end
    Library.seriesCommand("find",{key=host.series_key},function(result)
        if not wanted() or UIManager:getTopmostVisibleWidget()~=host then return end
        if result.id and result.state~="complete" then monitor(result) else preview() end
    end)
end
