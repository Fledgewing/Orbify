-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Reader hooks only. Catalog decisions, outboxes and downloads belong to the companion.
FinishUI={session={},jobs={},intent={},page_digests=setmetatable({}, {__mode="k"})}
local function book(ui) return Library.nativeReader and Library.nativeReader(ui) end
local function dispatch(action,b,extra,done)
    local args={path=b and b.file,document=b and b.digest,key=b and type(b.key)=="string" and b.key}
    for k,v in pairs(extra or {}) do args[k]=v end
    return Library.catalogAction(action,args,done or function() end)
end
function FinishUI.onMarked(ui)
    Library.localCompletion(ui,FinishUI.automatic)
    local b=book(ui);if not b then return end
    FinishUI.intent[b.digest]=(FinishUI.intent[b.digest] or 0)+1
    local complete=b.summary.status=="complete"
    FinishUI.jobs[b.digest]=complete and {final_pos={percentage=b.percentage}} or nil
    FinishUI.session[b.digest]={forward=0,released=not complete}
    dispatch("finish.mark",b,{complete=complete,percentage=b.percentage})
    if Library.noteReaderMark then Library.noteReaderMark(b) end
end
function FinishUI.onLeave(ui)
    local b=book(ui);if not b then return end
    if Library.noteReaderLeave then Library.noteReaderLeave(b) end
    if b.summary.status=="complete" or FinishUI.jobs[b.digest] or FinishUI.sheet then dispatch("finish.leave",b) end
end
function FinishUI.leaveForHome(ui)
    local had=FinishUI.sheet~=nil;FinishUI.closeSheet()
    ui=ui or liveUI()
    FinishUI.onLeave(ui)
    local b=book(ui)
    if b and FinishUI.jobs[b.digest] and not FinishUI.sending then
        FinishUI.sending=true
        -- Home paints first; native writer/network setup never runs on its render path.
        UIManager:nextTick(function() Library.finishCurrent(function() FinishUI.sending=nil end) end)
    end
    return had
end
function FinishUI.onPage(ui,page)
    local b=FinishUI.page_digests[ui]
    if not b or not ui.document or b.file~=ui.document.file then return end
    local s=FinishUI.session[b.digest] or {forward=0};FinishUI.session[b.digest]=s
    if s.last and page>s.last then s.forward=s.forward+1 end;s.last=page
end
function FinishUI.model(b)
    local paint=Library.paint("end-of-book")
    local m=paint:widget("end-of-book"):read("reader.finish",{path=b.file,document=b.digest,rating=b.summary.rating,limit=3})
    m=Layout.copy(m or {})
    local current=paint:reader(b.file)
    m.book=current.items and current.items[1] or {}
    m.stats=m.book.stats
    m.pending=m.pending or current.pending
    if m.next and m.next.local_path and not m.next.book then
        local nextBook=paint:reader(m.next.local_path)
        m.next.book=nextBook.items and nextBook.items[1]
        m.pending=m.pending or nextBook.pending
    end
    paint:flush()
    if m.title then return m end
    return {pending=m.pending,book=m.book,title=b.file:match("([^/]+)$"),status=b.summary.status=="complete" and "✓ Marked as finished" or "Not marked as finished",undo=b.summary.status=="complete",can_mark=b.summary.status~="complete",stars=b.summary.rating}
end
function FinishUI.showSheet(ui,b)
    FinishUI.closeSheet();FinishUI.card_state=nil
    FinishUI.sheet=EndSheet:new{ui=ui,book=b,model=FinishUI.model(b)}
    UIManager:show(FinishUI.sheet) -- gate: exception (the reader reached the end)
    FinishUI.pollSheet(FinishUI.sheet)
end
function FinishUI.pollSheet(sheet)
    if FinishUI.sheet_retry then UIManager:unschedule(FinishUI.sheet_retry);FinishUI.sheet_retry=nil end
    if not (sheet.model and sheet.model.pending) or (sheet.pending_attempts or 0)>=20 then return end
    sheet.pending_attempts=(sheet.pending_attempts or 0)+1
    FinishUI.sheet_retry=function()
        FinishUI.sheet_retry=nil
        if FinishUI.sheet==sheet and UIManager:getTopmostVisibleWidget()==sheet then FinishUI.refreshSheet(sheet.ui,sheet.book) end
    end
    UIManager:scheduleIn(.5,FinishUI.sheet_retry)
end
function FinishUI.refreshSheet(ui,b)
    if FinishUI.sheet and FinishUI.sheet.ui==ui and FinishUI.sheet.book==b then
        FinishUI.sheet:update(FinishUI.model(b),FinishUI.card_state)
        FinishUI.pollSheet(FinishUI.sheet)
    end
end
function FinishUI.closeSheet()
    if FinishUI.sheet_retry then UIManager:unschedule(FinishUI.sheet_retry);FinishUI.sheet_retry=nil end
    local s=FinishUI.sheet;FinishUI.sheet=nil;if s then UIManager:close(s) end
end
FinishUI.actions={}
function FinishUI.actions.undo(ui,b) ui.status:markBook(false);FinishUI.refreshSheet(ui,b) end
function FinishUI.actions.mark(ui,b) ui.status:markBook(true);FinishUI.refreshSheet(ui,b) end
function FinishUI.actions.star(ui,b,n)
    local summary=b.doc_settings:readSetting("summary") or {}
    summary.rating=summary.rating~=n and n or nil;b.summary=summary;b.doc_settings:saveSetting("summary",summary)
    dispatch("finish.rate",b,{rating=summary.rating},function() FinishUI.refreshSheet(ui,b) end)
end
function FinishUI.actions.review(ui) FinishUI.closeSheet();if ui.status then ui.status:onShowBookStatus() end end
function FinishUI.actions.author(ui,b,name)
    FinishUI.closeSheet();Library.openGrouped(name,{kind="author",key=name},{group="series"})
end
function FinishUI.actions.series(ui,b,key)
    if not key then return false end
    local document=ui and ui.document
    FinishUI.closeSheet()
    local function restore()
        if ui and ui.document==document and not FinishUI.sheet then FinishUI.showSheet(ui,b) end
    end
    local opened=SeriesUI.show(key,restore)
    if not opened then restore() end
    return opened
end
function FinishUI.actions.back() FinishUI.closeSheet() end
function FinishUI.actions.home(ui) FinishUI.leaveForHome(ui);if Library.controller() then Library.controller():onOrbitGoHome() end end
function FinishUI.actions.book(ui,b,key,title,local_path)
    local sheet=FinishUI.sheet
    FinishUI.onLeave(ui)
    if local_path then FinishUI.closeSheet();return Library.open({local_path=local_path}) end
    FinishUI.card_state={book_id=key,text="Connecting…"};FinishUI.refreshSheet(ui,b)
    -- The existing sole position/lifecycle writer drains before the companion sends the finish.
    -- Downloads follow its completion; no new writer or transport is installed here.
    Library.finishCurrent(function(ok)
        if FinishUI.sheet~=sheet or not sheet then return end
        if not ok then FinishUI.card_state={book_id=key,failure="failed"};FinishUI.refreshSheet(ui,b);return end
        dispatch("finish.download",b,{key=key},function(result)
            if FinishUI.sheet~=sheet then return end
            if result.error=="canceled" then FinishUI.card_state=nil;return end
            if result.error then
                FinishUI.card_state={book_id=key,failure="failed"};FinishUI.refreshSheet(ui,b)
            elseif result.local_path then
                FinishUI.closeSheet();Library.open(result)
            end
        end)
    end)
end
FinishUI.actions.retry=FinishUI.actions.book
function FinishUI.actions.later(ui,b,key) dispatch("finish.download",b,{key=key,later=true});FinishUI.closeSheet() end
function FinishUI.drain(p,manual,done)
    if reading() then if done then done() end;return end
    Library.catalogAction("finish.drain",{manual=manual==true},function() if done then done() end end)
end
function FinishUI.installPluginHooks(p) if Library.installFinishHooks then return Library.installFinishHooks(p) end end
-- Native events are small, already-loaded records. No catalog work on a page turn.
local ok,ReaderStatus=pcall(require,"apps/reader/modules/readerstatus")
if ok and type(ReaderStatus)=="table" and type(ReaderStatus.markBook)=="function" and type(ReaderStatus.onEndOfBook)=="function" then
    wrap(ReaderStatus,"markBook",function(stock) return function(self,...)
        local r=stock(self,...);FinishUI.onMarked(self.ui);return r
    end end,"finish")
    wrap(ReaderStatus,"onEndOfBook",function(stock) return function(self,...)
        local b=book(self.ui)
        if Library.settings.read("eob_sheet")==false or not b or not b.key then
            local previous=FinishUI.automatic;FinishUI.automatic=true
            local ok,result=pcall(stock,self,...);FinishUI.automatic=previous
            if not ok then error(result,0) end
            return result
        end
        if b.summary.status~="complete" and Library.settings.read("eob_auto")~=false then FinishUI.automatic=true;self:markBook(true);FinishUI.automatic=nil;b=book(self.ui) end
        FinishUI.showSheet(self.ui,b);return true
    end end,"finish")
end
for _,name in ipairs({"onCloseWidget","onSuspend","onReaderReady","onPageUpdate"}) do
    local stock=OrbitAndroid[name]
    OrbitAndroid[name]=function(self,...)
        if name=="onCloseWidget" or name=="onSuspend" then FinishUI.onLeave(self.ui) end
        if name=="onCloseWidget" then FinishUI.closeSheet() end
        if name=="onReaderReady" then
            Library.prepareLocalCompletion(self.ui)
            local b=book(self.ui)
            FinishUI.reader_key=nil
            if b then
                FinishUI.page_digests[self.ui]={file=b.file,digest=b.digest}
                local ui=self.ui
                dispatch("finish.prepare",b,{local_only=true},function(result)
                    if self.ui==ui and ui.document and ui.document.file==b.file and not result.error then FinishUI.reader_key=result end
                end)
            end
        elseif name=="onPageUpdate" then FinishUI.onPage(self.ui,...) end
        return stock(self,...)
    end
end
