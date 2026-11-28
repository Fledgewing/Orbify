-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Thin 0.12 UI boundary. One host-owned context per paint; finish with :flush().
-- Neutral companion transport. Only lifecycle calls import the opaque owner; paints never
-- inspect a server plugin, credentials or protocol records. Tests may inject this interface.
if not rawget(getfenv(1),"LibraryAdapter") then
LibraryAdapter={sent={},order={},ready={}}
LibraryAdapter.LOCAL_OWNER="device-local"
function LibraryAdapter.owner() return LibraryAdapter.managed_owner or LibraryAdapter.LOCAL_OWNER end
function LibraryAdapter.read(request,op,maxBytes,screen)
    maxBytes=math.min(maxBytes or Budgets.MAX_SNAPSHOT,Budgets.MAX_SNAPSHOT)
    if op=="settings.recommendations" and LibraryAdapter.recommendations then
        local bytes=#Cache.encode(LibraryAdapter.recommendations)
        if bytes>maxBytes then return nil end
        return LibraryAdapter.recommendations,bytes
    end
    if op=="account.state" and LibraryAdapter.account_snapshot then
        if LibraryAdapter.account_bytes>maxBytes then return nil end
        return LibraryAdapter.account_snapshot, LibraryAdapter.account_bytes
    end
    local owner = LibraryAdapter.owner()
    if not owner then
        if op=="capabilities" and LibraryAdapter.account_snapshot then
            local result={account=LibraryAdapter.account_snapshot}
            local bytes=#Cache.encode(result)
            if bytes>maxBytes then return nil end
            return result,bytes
        end
        return nil
    end
    -- Explicit reader surfaces may read one bounded local snapshot while the book
    -- stays foreground. Background reads retain Store's memo-only reading rule.
    local user_surface=screen=="reader-top-panel" or screen=="reader-bottom-panel" or screen=="book-info" or screen=="details" or screen=="end-of-book" or screen=="settings-reading-statistics"
    local result, bytes = Store.library(owner, request, maxBytes, user_surface)
    local decodedBytes=bytes or 0
    if type(result)~="table" then result=nil end
    if op=="capabilities" and LibraryAdapter.account_snapshot then
        local merged={}
        for k,v in pairs(result or {}) do merged[k]=v end
        merged.account=LibraryAdapter.account_snapshot
        bytes=math.max(decodedBytes,#Cache.encode(merged))
        if bytes>maxBytes then return nil,decodedBytes end
        result=merged
    end
    LibraryAdapter.ready[owner .. request] = result ~= nil
    return result, bytes
end
function LibraryAdapter.request(requests)
    local owner = LibraryAdapter.owner()
    local problem=Companion.workerProblem()
    if not owner or problem then
        if manual and not reading() then
            UIManager:show(require("ui/widget/infomessage"):new{text=problem or _("Connect to the server and sign in to refresh the catalog.")}) -- gate: user action (explicit refresh)
        end
        return false
    end
    -- Coalesce repeat paints; misses retry sooner than already materialized windows.
    local due, now = {}, now_s()
    for _, request in ipairs(requests) do
        local key = owner .. request
        local last = LibraryAdapter.sent[key]
        if not last or now-last >= (request:find("catalog.state",1,true) and 3 or LibraryAdapter.ready[key] and 30 or 2) then
            table.insert(due, request)
            if not last then
                table.insert(LibraryAdapter.order, key)
                if #LibraryAdapter.order > 64 then
                    local old = table.remove(LibraryAdapter.order, 1)
                    LibraryAdapter.sent[old], LibraryAdapter.ready[old] = nil, nil
                end
            end
            LibraryAdapter.sent[key] = now
        end
    end
    if #due == 0 then return false end
    local batch = Cache.encode(due)
    assert(#batch <= 131072, "Library batch byte budget exceeded")
    Companion.send(Companion.ACTION.PATCH, {library_batch=batch, owner=owner})
    return true
end

function LibraryAdapter.fullRefresh() return Library.refreshCatalog("full",true) end
function LibraryAdapter.syncNow(reader) return reader:onOrbitSyncAndSleep(true) end
function LibraryAdapter.syncCurrent(done)
    return ReadingSync.run("manual",function(ok,why) done(ok,why or (ok and "Synced" or "Saved · delivery pending")) end)
end
-- A successful transport drain may retain closed-sidecar applications. Those do not
-- delay the finish; transport errors do. SyncOwner remains the sole position writer.
function LibraryAdapter.finishCurrent(done)
    local owner,epoch=LibraryAdapter.owner(),LibraryAdapter.owner_epoch
    return ReadingSync.run("manual",function(ok,why)
        if owner~=LibraryAdapter.owner() or epoch~=LibraryAdapter.owner_epoch then return done(false,"canceled") end
        if why then return done(false,why) end
        return Library.catalogAction("finish.drain",{manual=true},function(result) done(not result.error,result.error) end)
    end)
end
-- KOReader already computes this on page/position updates, even with its footer hidden.
-- No document scan, sidecar read or second progress writer on a panel paint.
function LibraryAdapter.readerPosition(path)
    local ui = liveUI()
    if not (ui and ui.document and ui.document.file == path) then return nil end
    local footer = ui.view and ui.view.footer
    local fraction = footer and footer.percent_finished
    if type(fraction) == "number" and fraction == fraction and fraction >= 0 and fraction <= 1 then
        return fraction
    end
end

function LibraryAdapter.watch(enabled)
    LibraryAdapter.watching = enabled
    if enabled then LibraryAdapter.reset(); Library.watchEvents() end
end
function LibraryAdapter.changed(ev)
    if ev.owner and ev.owner ~= LibraryAdapter.owner() then return end
    if ev.kind ~= "library" then LibraryAdapter.reset() end
    Library.changed(ev)
end

function LibraryAdapter.reset() LibraryAdapter.sent, LibraryAdapter.ready, LibraryAdapter.order = {}, {}, {} end

function LibraryAdapter.openAccount()
    if Companion.workerProblem() then return false end
    local result=Jni.call(Companion.AUTHORITY,Companion.PACKAGE..".call.ACCOUNT_OPEN",{})
    return result and result.ok=="1"
end
-- Current-state reloads share one ordered lifecycle chain. A newer reload retires the
-- older retry, but inherits its waiters; stored command replies never publish identity.
function LibraryAdapter.accountReturned(attempt,epoch,done)
    if not epoch then
        LibraryAdapter.account_epoch=(LibraryAdapter.account_epoch or 0)+1
        epoch=LibraryAdapter.account_epoch
        if LibraryAdapter.account_retry then UIManager:unschedule(LibraryAdapter.account_retry) end
        LibraryAdapter.account_retry=nil
    end
    LibraryAdapter.account_waiters=LibraryAdapter.account_waiters or {}
    if done then table.insert(LibraryAdapter.account_waiters,done) end
    if epoch~=LibraryAdapter.account_epoch then return false end
    local result
    if not Companion.workerProblem() then
        result=Jni.call(Companion.AUTHORITY,Companion.PACKAGE .. ".call.SERVER_STATE",{reload=attempt==nil and "1" or "0"})
    end
    if result and result.pending=="1" and (attempt or 0)<3 then
        LibraryAdapter.account_retry=function() LibraryAdapter.accountReturned((attempt or 0)+1,epoch) end
        UIManager:scheduleIn(1,LibraryAdapter.account_retry)
        return false
    end
    LibraryAdapter.account_retry=nil
    local changed=false
    local body=result and result.ok=="1" and result.pending~="1" and result.body
    local state=type(body)=="string" and #body<=Budgets.MAX_SNAPSHOT and Cache.decode(body) or nil
    if type(state)=="table" then
        LibraryAdapter.account_snapshot,LibraryAdapter.account_bytes=state,#body
    end
    if type(state)=="table" then
        changed=LibraryAdapter.managed_owner~=result.owner
        LibraryAdapter.managed_owner=result.owner
        if changed then
            LibraryAdapter.owner_epoch=(LibraryAdapter.owner_epoch or 0)+1
            LibraryAdapter.reset()
        end
    end
    local waiters=LibraryAdapter.account_waiters
    LibraryAdapter.account_waiters={}
    for _,waiter in ipairs(waiters) do waiter(type(state)=="table" and state or nil) end
    if type(state)=="table" then Library.changed({kind="account"}) end
    return changed
end

-- One-shot delivery ticket. Retirement drops presentation and polling, never the
-- companion's durable job. Named policies belong here, never in UI code.
function LibraryAdapter.command(op,args,callback,policy)
    policy=policy or {kind="owner"}
    local owner,epoch=LibraryAdapter.owner(),LibraryAdapter.owner_epoch
    local live=true
    local poll
    local function retire()
        if not live then return end
        live=false
        if poll then UIManager:unschedule(poll) end
        callback=nil;policy=nil;poll=nil
    end
    local function settle(result)
        if not live then return end
        local done=callback
        retire()
        if done then done(result) end
    end
    local function wanted()
        if not live then return false end
        if policy.kind=="owner" and (owner~=LibraryAdapter.owner() or epoch~=LibraryAdapter.owner_epoch) then
            settle({error="canceled"});return false
        end
        if policy.wanted and not policy.wanted() then settle({error="canceled"});return false end
        return true
    end
    if Companion.workerProblem() then settle({error="unavailable"});return false,retire end
    local encoded=Cache.encode(args or {})
    assert(#encoded<=Budgets.MAX_REQUEST,"Server command exceeds budget")
    local sent=Jni.call(Companion.AUTHORITY,Companion.PACKAGE .. ".call.SERVER_COMMAND",{op=op,args=encoded})
    if not sent or sent.ok~="1" or not sent.id then settle({error="unavailable"});return false,retire end
    local id,deadline=sent.id,now_s()+120
    poll=function()
        if not wanted() then return end
        local result=Jni.call(Companion.AUTHORITY,Companion.PACKAGE .. ".call.SERVER_RESULT",{id=id})
        local body=result and result.body
        if type(body)~="string" or #body>(policy.maxBytes or Budgets.MAX_SNAPSHOT) then settle({error="unavailable"});return end
        local decoded=Cache.decode(body)
        if type(decoded)~="table" then settle({error="invalid"});return end
        -- 120 seconds bounds pending waits. An overdue ready reply still counts
        -- while its ticket is live; completion after a settled timeout is ignored.
        if not decoded.pending then
            if policy.kind=="account" then
                decoded.state=nil -- Historical command snapshots never publish account state.
                LibraryAdapter.accountReturned(nil,nil,function(state)
                    if not live then return end
                    decoded.state=state
                    if not state and not decoded.error then decoded.error="unavailable" end
                    if wanted() then settle(decoded) end
                end)
            else settle(decoded) end
            return
        end
        if now_s()>=deadline then settle({error="unavailable"});return end
        UIManager:scheduleIn(.2,poll)
    end
    UIManager:scheduleIn(.2,poll)
    return true,retire
end

end

Library = rawget(getfenv(1),"Library") or {}
if Library.bindLifecycle then Library.bindLifecycle() end
-- Explicit user command; the existing adapter/worker owns the full-refresh job.
local function command(id, run)
    local finish = Budgets.span("library." .. id .. ".enqueue", now_s, log)
    local accepted,retire = run()
    finish()
    return accepted,retire
end
-- Device effects outlive their initiating page. Retiring this presentation drops
-- its callback while the device-lifetime ticket still adopts the durable result.
local function deviceCommand(op,args,effect,done,maxBytes)
    local accepted=LibraryAdapter.command(op,args,function(result)
        effect(result)
        local callback=done;done=nil
        if callback then callback(result) end
    end,{kind="device",maxBytes=maxBytes})
    return accepted,function() done=nil end
end
function Library.fullRefresh() return command("full-refresh", LibraryAdapter.fullRefresh) end
function Library.syncNow(reader) return command("sync-now", function() return LibraryAdapter.syncNow(reader) end) end
local function counts()
    return {rows=0,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}
end
function Library.paint(screen)
    local budget = Budgets.get("screens", screen)
    return setmetatable({screen=screen,budget=budget, screen_budget=budget, usage=counts(), widgets={}, pending={}, seen={},
        metrics=counts(), finish=Budgets.span(screen .. ".paint", now_s, log)}, {__index=Library})
end
function Library:widget(name, instance)
    local budget = Budgets.get("widgets", name)
    local key = name .. ":" .. tostring(instance or name)
    assert(#key <= 256, "Widget instance key exceeds budget")
    if not self.widgets[key] then self.widgets[key] = counts() end
    return setmetatable({screen=self.screen,budget=budget, screen_budget=self.screen_budget, usage=self.widgets[key], widgets=self.widgets,
        is_widget=true, pending=self.pending, seen=self.seen, metrics=self.metrics}, {__index=Library})
end
function Library:read(op, args)
    assert(not self.metrics.flushed, "Library paint already flushed")
    local rows, bytes = 0, 0
    local finish = Budgets.span("library." .. op, now_s, function(line) log(line, "rows", rows, "bytes", bytes) end)
    local function read()
    args = args or {}
    args.op = op
    -- A ready pre-upgrade view has no root counts/extended source vocabulary.
    -- A new cache identity materializes the changed neutral shape immediately.
    if (op=="window" or op=="counts" or op=="facets" or op=="groups") and args.source=="unopened" then local ui=liveUI();args.exclude_path=ui and ui.document and ui.document.file end
    if op=="reader" or op=="reader.controls" then args.projection=2 elseif op=="library.summary" then args.projection=2 elseif op=="sources" then args.projection=6 end
    local remainingRows=math.min(self.budget.rows-self.usage.rows,self.screen_budget.rows-self.metrics.rows)
    local remainingBytes=math.min(self.budget.bytes-self.usage.bytes,self.screen_budget.bytes-self.metrics.bytes)
    assert(remainingRows>=1 and remainingBytes>=1,"Library caller budget exhausted")
    args.limit = math.max(1, math.min(remainingRows, Budgets.MAX_ROWS, Budgets.libraryWindow.rows,
        math.floor(tonumber(args.limit) or self.budget.rows)))
    args.bytes = math.min(remainingBytes, Budgets.libraryWindow.bytes, Budgets.MAX_SNAPSHOT)
    local request = Cache.encode(args)
    assert(#request <= Budgets.MAX_REQUEST, "Library request exceeds budget")
    assert(self.metrics.bytes + args.bytes <= self.screen_budget.bytes, "Library page byte budget exhausted")
    assert(self.metrics.rows + args.limit <= self.screen_budget.rows, "Library page row budget exhausted")
    assert(self.seen[request] or #self.pending < Budgets.MAX_BATCH, "Library paint request budget exceeded")
    local result, decoded = LibraryAdapter.read(request,op,args.bytes,self.screen)
    if type(result)~="table" then result=nil end
    local function charge(n, size)
        local call = counts(); call.rows, call.bytes, call.snapshotBytes = n, size, size
        assert(Budgets.check(Budgets.libraryWindow, call))
        local usage = counts()
        usage.rows, usage.bytes = self.usage.rows + n, self.usage.bytes + size
        usage.snapshotBytes = self.is_widget and usage.bytes or math.max(self.usage.snapshotBytes, size)
        assert(Budgets.check(self.budget, usage))
        for k,v in pairs(usage) do self.usage[k]=v end
        self.metrics.rows, self.metrics.bytes = self.metrics.rows + n, self.metrics.bytes + size
        self.metrics.snapshotBytes = math.max(self.metrics.snapshotBytes, self.usage.snapshotBytes)
        assert(Budgets.check(self.screen_budget, self.metrics))
    end
    -- Decoding work is charged before interpreting even malformed result metadata.
    bytes=decoded or 0
    assert(bytes<=args.bytes,"Library call budget exceeded")
    if bytes>0 then charge(0,bytes) end
    if result and result.items and Library.unavailablePaths then
        local decorated
        for i,row in ipairs(result.items) do
            local untilAt=type(row)=="table" and row.local_path and Library.unavailablePaths[row.local_path]
            if untilAt and untilAt>now_s() then
                if not decorated then decorated=Cache.copy(result) end
                decorated.items[i].local_path=nil
            end
        end
        if decorated then result=decorated end
    end
    if result and result.items and Library.downloadJobs then
        local decorated
        for i,row in ipairs(result.items) do
            local job=type(row)=="table" and not row.local_path and Library.downloadJobs[row.key]
            if job then
                local overlay={id=job.id,state=job.state,progress_text=job.progress_text or job.error}
                local size=#UIUtil.encode(overlay)+32
                local available=math.min(self.budget.bytes-self.usage.bytes,self.screen_budget.bytes-self.metrics.bytes)
                if size<=available then
                    if not decorated then decorated=Cache.copy(result) end
                    decorated.items[i].transfer=overlay;charge(0,size)
                end
            end
        end
        if decorated then result=decorated end
    end
    if result then
        rows=result.row_count or (result.items and #result.items or 1)
        assert(type(rows)=="number" and rows>=0 and rows==math.floor(rows) and rows<=args.limit,"Library call budget exceeded")
        charge(rows,0)
    end
    if not self.seen[request] then
        assert(#self.pending < Budgets.MAX_BATCH, "Library paint request budget exceeded")
        self.seen[request] = true
        table.insert(self.pending, request)
    end
    return result or {items={}, freshness={saved=false}, pending=true}
    end
    local ok,result=pcall(read)
    finish()
    if not ok then error(result,0) end
    return result
end
function Library:accountState() return self:read("account.state", {limit=1}) end
function Library:summary() return self:read("library.summary", {limit=1}) end
function Library:modeEstimates() return self:read("mode-estimates", {limit=3}) end
function Library:battery() return self:read("battery", {limit=1}) end
function Library:readingStats() return self:read("reading.stats", {limit=1}) end
function Library:clock(twelve) return self:read("device.clock", {limit=1,twelve_hour=twelve==true}) end
function Library:capabilities() return self:read("capabilities") end
function Library:window(source, query, offset, limit)
    return self:read("window", {source=source or "library/all", query=query or {}, offset=offset or 0, limit=limit})
end
function Library:book(key) return self:read("book", {key=key, limit=1}) end
function Library:cover(key) return self:read("cover", {key=key, limit=1}) end
function Library:counts(source, query) return self:read("counts", {source=source or "library/all", query=query or {}}) end
-- Reader identity stays opaque to the UI; the worker joins the local file ledger.
function Library:reader(path)
    local position = LibraryAdapter.readerPosition and LibraryAdapter.readerPosition(path)
    return self:read("reader", {path=path, native_progress=position, limit=1})
end
-- An explicit user action, never invoked by paint/read.
function Library.syncCurrent(done)
    local finish = Budgets.span("library.progress.sync", now_s, log)
    local result = LibraryAdapter.syncCurrent(done)
    finish()
    return result
end
function Library:facets(source, query, field, offset, limit, exclude_current)
    return self:read("facets", {source=source or "library/all", query=query or {}, field=field, offset=offset or 0, limit=limit, exclude_current=exclude_current})
end
function Library:progress(key) return self:read("progress", {key=key, limit=1}) end
function Library:status(key) return self:read("status", {key=key, limit=1}) end
function Library:job(key) return self:read("job", {key=key, limit=1}) end
function Library:flush(local_only)
    assert(not self.is_widget and not self.metrics.flushed, "Library host paint already flushed or missing")
    self.metrics.flushed = true
    if not local_only and #self.pending > 0 and LibraryAdapter.request(self.pending) then self.metrics.roundTrips = 1 end
    assert(Budgets.check(self.screen_budget, self.metrics))
    self.finish()
    self.pending = {}
    return self.metrics
end

-- Owned read-model notifications. The adapter uses the existing companion event poll.
function Library:lists(limit) return self:read("lists", {limit=limit}) end
function Library.subscribe(callback)
    Library.listener = callback
    LibraryAdapter.watch(true)
    return function()
        if Library.listener == callback then Library.listener=nil; LibraryAdapter.watch(false) end
    end
end
-- Modal consumers observe the same neutral updates without taking the host's slot.
-- A forgotten modal cannot keep itself alive through this weak observer registry.
Library.observers=setmetatable({},{__mode="k"})
function Library.observe(callback)
    Library.observers[callback]=true;Library.watchEvents()
    return function() Library.observers[callback]=nil end
end
function Library.changed(event)
    local settings=SettingsView and SettingsView.active
    if settings and settings.alive and settings.screen=="settings-reading-statistics" and UIManager:getTopmostVisibleWidget()==settings.dialog then settings:paint() end
    if FinishUI and FinishUI.sheet and event.kind=="library" then
        local sheet=FinishUI.sheet;FinishUI.refreshSheet(sheet.ui,sheet.book)
    end
    if Library.listener then Library.listener(event) end
    for callback in pairs(Library.observers) do callback(event) end
end
Library.unavailablePaths={}
Library.unavailableOrder={}
function Library.open(row)
    if type(row.local_path) ~= "string" then return false end
    if not Store.fileExists(row.local_path) then
        if not Library.unavailablePaths[row.local_path] then
            Library.unavailableOrder[#Library.unavailableOrder+1]=row.local_path
            if #Library.unavailableOrder>32 then Library.unavailablePaths[table.remove(Library.unavailableOrder,1)]=nil end
        end
        Library.unavailablePaths[row.local_path]=now_s()+30
        Library.storageCommand("storage.refresh",{},function() LibraryAdapter.reset();Library.changed({kind="library_source",owner=LibraryAdapter.owner()}) end)
        return false,"missing"
    end
    require("apps/reader/readerui"):showReader(row.local_path)
    return true
end

function Library.retry() LibraryAdapter.reset() end

-- Explicit account commands; transport and connector compatibility stay behind the adapter.
function Library.openAccount() return LibraryAdapter.openAccount() end
function Library.accountReturned() return LibraryAdapter.accountReturned() end

function Library.syncPosition(document, update, callback)
    local args={document=document}
    if update then args.percentage,args.position=update.percentage,update.position end
    return LibraryAdapter.command(update and "sync.write" or "sync.read",args,callback)
end
function Library.catalogPage(page,limit,callback)
    return LibraryAdapter.command("catalog.window",{page=page,limit=math.min(limit or 24,Budgets.MAX_ROWS)},callback)
end
function Library.download(key,destination,callback)
    return LibraryAdapter.command("downloads.start",{key=key,destination=destination},callback)
end

-- Explicit account actions only; credentials are dispatched and immediately released.
function Library.accountCommand(op,args,done)
    return command(op,function() return LibraryAdapter.command(op,args,done,{kind="account"}) end)
end

-- Paged source names/counts, never a catalog delivered to the editor.
function Library:sources(category, offset, limit, caps)
    return self:read("sources", {category=category,offset=offset or 0,limit=limit or 6,
        allow_lists=not (caps and caps.lists and caps.lists.read==false),allow_collections=not (caps and caps.collections==false),
        allow_wtr=not (caps and caps.wantToRead==false),allow_device=not (caps and caps.onDevice==false)})
end

-- Position sync owns one local row and a bounded pure preview; all writes remain worker commands.
function Library.nativeReaderPosition(path) return LibraryAdapter.readerPosition(path) end
function Library.idle() if LibraryAdapter.idle then return LibraryAdapter.idle() end end
function Library.networkRestored() if LibraryAdapter.networkRestored then return LibraryAdapter.networkRestored() end end
-- Consent may outlive a run's caller, while its durable commands remain device-lived.
-- Keep account identity/epoch checks behind Library, shared across that run's replies.
function Library.positionDelivery()
    local owner,epoch=LibraryAdapter.owner(),LibraryAdapter.owner_epoch
    local live=true
    return function()
        live=live and owner==LibraryAdapter.owner() and epoch==LibraryAdapter.owner_epoch
        return live
    end
end
function Library.positionCommand(op,args,done)
    return command(op,function() return LibraryAdapter.command(op,args,done or function() end,{kind="device"}) end)
end
function Library.positionCached(path)
    local finish=Budgets.span("library.position.cached",now_s,log)
    local b=Budgets.get("screens","position-consent")
    local root=require("datastorage"):getSettingsDir() .. "/orbit-cache"
    local body=Store.readFile(root .. "/position/" .. require("ffi/sha2").md5(path) .. ".lua",b.bytes+1)
    local value=type(body)=="string" and #body<=16384 and Cache.decode(body) or nil
    finish()
    return type(value)=="table" and value.path==path and value or nil
end
function Library.positionPreview(args)
    local finish=Budgets.span("library.position.preview",now_s,log)
    local encoded=Cache.encode(args); assert(#encoded<=Budgets.MAX_REQUEST,"Position preview exceeds budget")
    local result=Jni.call(Companion.AUTHORITY,Companion.PACKAGE .. ".call.SYNC_PREVIEW",{args=encoded})
    local body=result and result.body
    local value=type(body)=="string" and #body<=16384 and Cache.decode(body) or nil
    finish()
    return value
end

-- Neutral lifecycle hooks shared with the independently migrating catalog/finish adapter.
function Library.backgroundCommand(op,...)
    local args={...}
    return command(op,function() return LibraryAdapter.backgroundCommand(op,unpack(args)) end)
end
function Library.backgroundBusy()
    local finish=Budgets.span("library.background.busy",now_s,log)
    local busy=LibraryAdapter.backgroundBusy and LibraryAdapter.backgroundBusy()
    finish(); return busy
end

local function storagePath()
    local ui=liveUI and liveUI()
    return ui and ui.document and ui.document.file or nil
end
function Library.downloadRoot()
    return G_reader_settings:readSetting("download_dir") or G_reader_settings:readSetting("home_dir") or Device.home_dir or G_reader_settings:readSetting("lastdir")
end
function Library:storage() return self:read("storage.summary",{limit=1,exclude_path=storagePath(),current_folder=Library.downloadRoot()}) end
function Library:collections(offset,limit) return self:read("collections",{offset=offset or 0,limit=limit or 6}) end
function Library.storageCommand(op,args,done)
    args.exclude_path=storagePath(); args.owner=LibraryAdapter.owner()
    return command(op,function() return deviceCommand(op,args,function(result)
        if op=="storage.folder" and result and not result.error and result.download_path then
            G_reader_settings:saveSetting("download_dir",result.download_path)
        end
    end,done) end)
end

-- Companion-materialized Series and grouped catalog windows, including preview row charges.
function Library:series(key, offset, limit)
    return self:read("series", {key=key,offset=offset or 0,limit=limit or 12})
end
function Library:groups(source, query, offset, limit, exclude_current, preview, group_limit)
    return self:read("groups", {source=source,query=query,offset=offset or 0,limit=limit or 8,exclude_current=exclude_current,preview=preview,group_limit=group_limit})

end

-- Settings projections reuse the companion's sleep choices and device settings owners.
function Library.refreshDevice(attempt)
    local finish=Budgets.span("library.settings-device.refresh",now_s,log)
    local result=Jni.call(Companion.AUTHORITY,Companion.PACKAGE..".call.DEVICE_SETTINGS",{})
    local body=result and result.ok=="1" and result.body
    Library.device_snapshot=type(body)=="string" and #body<=16384 and Cache.decode(body) or nil
    assert(Budgets.check(Budgets.get("screens","settings-device"),{rows=1,bytes=type(body)=="string" and #body or 0,
        spawns=0,roundTrips=1,network=0,snapshotBytes=type(body)=="string" and #body or 0}))
    if Library.device_snapshot and Library.device_snapshot.pending and (attempt or 0)<3 then
        UIManager:scheduleIn(.5,function() Library.refreshDevice((attempt or 0)+1) end)
    end
    finish()
end
function Library:deviceSettings()
    local finish=Budgets.span("library.settings-device",now_s,log)
    local device=Library.device_snapshot or {reader="Not available",sleep_label="Not available",unavailable=true}
    self.usage.rows=self.usage.rows+1; self.metrics.rows=self.metrics.rows+1
    assert(Budgets.check(self.budget,self.usage))
    assert(Budgets.check(self.screen_budget,self.metrics))
    finish(); return device
end
function Library:sleepChoices(category, offset)
    return self:read("sleep.choices", {category=category,offset=offset or 0,limit=6})
end
function Library.sleepAfter(ms, done)
    return command("device.sleep",function() return deviceCommand("device.sleep",{ms=ms},function(result)
        if result.device then Library.device_snapshot=result.device end
    end,done) end)
end

-- Explicit background acquisition; paints consume local references from their snapshots.
function Library.acquireCover(key,done,wanted)
    return command("covers.acquire",function()
        return LibraryAdapter.command("covers.acquire",{key=key,owner=LibraryAdapter.owner()},function(result)
            if result.local_path then LibraryAdapter.reset(); Library.changed({kind="cover",owner=LibraryAdapter.owner()}) end
            if done then done(result) end
        end,{kind="owner",wanted=wanted})
    end)
end

-- Adapter capabilities determine the overflow model, never server names in a widget.
function Library.cardActions(row,caps)
    caps=caps or {}
    local items={{id="details",label="Details",enabled=row.key~=nil and row.detail_available~=false},
        {id=row.local_path and "book" or "download",label=row.local_path and "Open" or "Download",enabled=row.local_path~=nil or caps.download==true}}
    if row.series_key and not (caps.series and caps.series.read==false) then
        items[#items+1]={id="series",label="View series",enabled=true}
    end
    -- Status intents are capability-gated and checkpointed by the sole sync writer.
    items[#items+1]={id="status",label=row.status=="finished" and "Mark unread" or "Mark read",enabled=(caps.status and caps.status.write)==true and row.status~="unknown" and row.status_write~=false}
    if row.local_path then items[#items+1]={id="remove",label="Remove download",enabled=caps.removeDownload==true and row.can_remove~=false} end
    assert(#items<=Budgets.get("screens","book-actions").rows,"Card action row budget exceeded")
    return items
end

Library.cardStatusEpoch={}
Library.cardNativeContexts={}
function Library.cardStatusLeave(result)
    local context=Library.cardNativeContexts[result.token]
    Library.cardNativeContexts[result.token]=nil
    return Library.catalogAction("status.leave",{token=result.token},function(reply)
        local ui=liveUI and liveUI()
        if not reply.error and reply.native_token and context and (FinishUI.intent[context.digest] or 0)==context.epoch and ui and ui.document and ui.document.file==reply.path and ui.doc_settings then
            ui.doc_settings:saveSetting("booksync_status_token",reply.native_token)
        end
        if not reading() and NetworkMgr:isConnected() then Library.catalogAction("finish.drain",{manual=false},function() end) end
    end)
end
function Library.cardStatus(row,undo,done)
    local key=row.key
    if undo then Library.cardNativeContexts[undo]=nil end
    Library.cardStatusSequence=(Library.cardStatusSequence or 0)+1
    local epoch=Library.cardStatusSequence;Library.cardStatusEpoch[key]=epoch
    local ui=liveUI and liveUI()
    local current=ui and ui.document and ui.document.file==row.local_path and ui.doc_settings
    local before=current and Cache.copy(ui.doc_settings:readSetting("summary") or {}) or nil
    local digest=current and ui.doc_settings:readSetting("partial_md5_checksum")
    local nativeEpoch=digest and FinishUI.intent[digest] or 0
    local args={key=key,status=row.status=="finished" and "unread" or "finished",before_status=row.status,token=undo,
        native_token=current and ui.doc_settings:readSetting("booksync_status_token"),
        native_capture=current and ReadingSync.capture(ui,"manual"),before_native=before and {status=before.status,modified=before.modified}}
    return Library.catalogAction(undo and "status.undo" or "status.mark",args,function(result)
        if Library.cardStatusEpoch[key]~=epoch then
            if not undo and result.token then Library.cardStatusLeave(result) end
            return
        end
        Library.cardStatusEpoch[key]=nil
        local bytes=#UIUtil.encode(result or {})
        assert(Budgets.check(Budgets.get("screens","book-status"),{rows=1,bytes=bytes,snapshotBytes=bytes,network=0,spawns=0,roundTrips=1}))
        if not result.error and current and ui.document and ui.document.file==row.local_path and (FinishUI.intent[digest] or 0)==nativeEpoch then
            local summary=Cache.copy(ui.doc_settings:readSetting("summary") or {})
            local desired=result.native_summary or {}
            summary.status,summary.modified=desired.status,desired.modified
            ui.doc_settings:saveSetting("summary",summary)
            ui.doc_settings:saveSetting("booksync_status_token",result.native_token or result.token)
            Library.cardNativeContexts[result.token]={digest=digest,epoch=nativeEpoch}
            -- Same in-memory cache update as native ReaderStatus.markBook (pinned readerstatus.lua:216).
            require("ui/widget/booklist").setBookInfoCacheProperty(ui.document.file,"status",summary.status)
        end
        local held=done and done(result)
        if not result.error and result.token and (undo or held~=true) then Library.cardStatusLeave(result) end
    end)
end

function Library.cardRemoval(row,token,done)
    return Library.storageCommand(token and "storage.remove" or "storage.remove.preview",
        {path=row.local_path,token=token},function(result)
            local bytes=#UIUtil.encode(result or {})
            assert(Budgets.check(Budgets.get("screens","book-removal"),{rows=1,bytes=bytes,snapshotBytes=bytes,network=0,spawns=0,roundTrips=1}))
            if done then done(result) end
        end)
end

-- Transfer control is companion-owned; renderers read only this bounded in-memory overlay.
Library.downloadJobs={}
Library.downloadOrder={}
function Library.downloadState(key) return Library.downloadJobs[key] end
function Library.rememberDownload(key,result)
    local previous=Library.downloadJobs[key]
    if previous and previous.id==result.id and (tonumber(previous.sequence) or 0)>(tonumber(result.sequence) or 0) then return previous end
    if result.state=="complete" and result.local_path then Library.unavailablePaths[result.local_path]=nil end
    if not Library.downloadJobs[key] then
        Library.downloadOrder[#Library.downloadOrder+1]=key
        if #Library.downloadOrder>32 then Library.downloadJobs[table.remove(Library.downloadOrder,1)]=nil end
    end
    Library.downloadJobs[key]=result
    return result
end
local function transferResult(result,kind)
    local bytes=#UIUtil.encode(result or {})
    local rows=result.row_count or (result.items and #result.items) or 1
    assert(Budgets.check(Budgets.get("screens",kind),{rows=rows,bytes=bytes,snapshotBytes=bytes,network=0,spawns=0,roundTrips=1}))
    return result
end
function Library.downloadPrepare(row,done)
    return Library.catalogAction("download.prepare",{key=row.key,root=Library.downloadRoot()},function(result) done(transferResult(result,"download-options")) end)
end
function Library.downloadStart(row,choice,done)
    return Library.catalogAction("download.start",{key=row.key,file_reference=choice.file_reference,variant=choice.variant,destination=choice.destination},function(result)
        Library.rememberDownload(row.key,transferResult(result,"download-job"));done(result)
    end)
end
function Library.downloadControl(row,action,done)
    local job=Library.downloadState(row.key)
    if not job or not job.id then return false end
    return Library.catalogAction("download."..action,{id=job.id},function(result)
        local current=Library.downloadState(row.key)
        if not current or current.id~=job.id then if done then done({error="canceled"}) end;return end
                if result.error and not result.id then
            local failed=Cache.copy(current);failed.error=result.error;failed.state="error";failed.progress_text="Status unavailable · Try again";result=failed
        end
        local adopted=Library.rememberDownload(row.key,transferResult(result,"download-job"));if done then done(adopted) end
    end)
end
-- Series commands return one bounded neutral snapshot. No catalog traversal in Lua.
function Library.seriesCommand(action,args,done)
    return Library.catalogAction("series."..action,args,function(result)
        transferResult(result,"series-downloads")
        for _,row in ipairs(result.items or {}) do
            if row.id and row.key and row.state then Library.rememberDownload(row.key,row) end
        end
        if done then done(result) end
    end)
end
function Library.seriesFile(row,root,done)
    return Library.catalogAction("download.prepare",{key=row.key,root=root},function(result) done(transferResult(result,"download-options")) end)
end
function Library.downloadConnect(done)
    return Net.up(Library.controller(),{reason="manual",cap=20},function(ready) done(ready) end)
end
-- Kept for existing caller compatibility; new UI uses the job controls above.
function Library.downloadCard(row,done) return Library.catalogAction("finish.download",{key=row.key},done) end

-- Card cover preparation runs after the first paint. The interface owns cache misses,
-- account/generation cancellation and retries; widgets see only a bounded local path.
Library.cardCoverJobs={head=1,tail=0,active=0}
function Library.drainCardCovers()
    local queue=Library.cardCoverJobs
    queue.scheduled=nil
    local finish=Budgets.span("library.card-covers",now_s,log)
    for _,job in ipairs(Cache.takeWindow(queue,Budgets.CARD_COVER_BATCH)) do
        local ok,err=pcall(job)
        if not ok then log("library.card-covers failed",tostring(err)) end
    end
    finish()
    if Library.cardCoverJobs==queue and queue.head<=queue.tail and not queue.scheduled then
        queue.scheduled=true; UIManager:nextTick(Library.drainCardCovers)
    end
end
function Library.deferCardCover(task)
    local queue=Library.cardCoverJobs
    local live=true
    queue.active=queue.active+1
    queue.tail=queue.tail+1
    queue[queue.tail]=function()
        if not live then return end
        live=false; queue.active=queue.active-1
        task()
    end
    if not queue.scheduled then
        queue.scheduled=true; UIManager:nextTick(Library.drainCardCovers)
    end
    return function()
        if not live then return end
        live=false; queue.active=queue.active-1
        if queue.active==0 and Library.cardCoverJobs==queue then
            UIManager:unschedule(Library.drainCardCovers)
            Library.cardCoverJobs={head=1,tail=0,active=0}
        end
    end
end
function Library.prepareCardCover(row,done,visible)
    local owner=LibraryAdapter.owner()
    local canceled=false
    local retire,cancelDelivery
    local function valid() return not canceled and owner==LibraryAdapter.owner() and not reading() and (not visible or visible()) end
    local function deliver(path)
        if not valid() or type(path)~="string" then return end
        local attr=require("lfs").attributes(path)
        if attr and attr.mode=="file" and attr.size<=Budgets.CARD_COVER_BYTES then done(path); return true end
    end
    local task=function()
        if not valid() then return end
        if row.cover_path and deliver(row.cover_path) then return end
        if not row.key then return end
        local key="card-cover:"..owner..row.key
        local last=LibraryAdapter.sent[key]
        if last and now_s()-last<30 then return end
        LibraryAdapter.sent[key]=now_s()
        table.insert(LibraryAdapter.order,key)
        if #LibraryAdapter.order>64 then LibraryAdapter.sent[table.remove(LibraryAdapter.order,1)]=nil end
        local accepted
        accepted,retire=Library.acquireCover(row.key,function(result)
            if valid() then cancelDelivery=Library.deferCardCover(function() deliver(result.local_path) end) end
        end,valid)
    end
    local cancelTask=Library.deferCardCover(task)
    return function()
        canceled=true; cancelTask()
        if cancelDelivery then cancelDelivery();cancelDelivery=nil end
        if retire then retire();retire=nil end
    end
end

-- Cover lookup never schedules work on a paint. The thumbnail host explicitly acquires misses
-- after paint; the companion publishes the exact one-row reference on its existing writer.
function Library.cachedCover(reference)
    local paint=Library.paint("cover-cache")
    local result=paint:read("cover.reference",{reference=reference,limit=1})
    paint:flush(true)
    local path=result.local_path
    return type(path)=="string" and Store.readFile(path,1) and path or nil
end
function Library.acquireCoverReference(reference,refresh,done)
    local owner=LibraryAdapter.owner()
    return command("covers.acquire",function()
        return LibraryAdapter.command("covers.acquire",{reference=reference,refresh=refresh==true,owner=owner},function(result)
            if result.local_path then LibraryAdapter.reset(); Library.changed({kind="cover",owner=LibraryAdapter.owner()}) end
            if done then done(result) end
        end)
    end)
end

-- One shared durable event reader, retained across catalog and sync cutovers. Acknowledgement
-- follows dispatch, and an unchanged durable batch never creates a second timer chain.
Library.events={}
function Library.watchEvents()
    if Library.events.watching then return end
    Library.events.watching=true
    UIManager:scheduleIn(.5,Library.pollEvents)
end
function Library.pollEvents()
    local state=Library.events
    UIManager:unschedule(Library.pollEvents)
    UIManager:scheduleIn(.5,Library.pollEvents)
    if Companion.workerProblem() or reading() then return end
    if Library.compatTick then Library.compatTick(now_s()) end
    local encoded=Store.readFile(Store.dir().."/events-batch.lua",65537)
    if not encoded or #encoded>65536 then return end
    local batch=Cache.decode(encoded)
    if type(batch)~="table" or not batch.id then return end
    if batch.id~=state.ack then
        state.ack,state.sent_at=batch.id,nil
        local applied,err=pcall(Library.applyEvents,batch.events or {})
        if not applied then state.ack=nil;log("library events: dispatch deferred",tostring(err));return end
    end
    if not state.sent_at or now_s()-state.sent_at>=10 then
        state.sent_at=now_s()
        Companion.send(Companion.ACTION.PATCH,{reason="events",drain_events="1",events_ack=batch.id})
    end
end
function Library.applyEvents(events)
    for _,event in ipairs(events) do
        if type(event)=="table" then
            -- Durable account completion reconciles even after its form ticket retired.
            if event.kind=="account" then Library.accountReturned() end
            if event.kind=="library" or event.kind=="library_source" or event.kind=="account" or event.kind=="checked" or event.kind=="copies" then
                LibraryAdapter.changed(event)
            end
            if Library.compatEvent then Library.compatEvent(event) end
        end
    end
end
function Library:catalogState() return self:read("catalog.state",{limit=1}) end
function Library.catalogSnapshot()
    local paint=Library.paint("catalog-refresh")
    local result=paint:catalogState(); paint:flush(true)
    return result
end
function Library.refreshCatalog(action,manual)
    local owner=LibraryAdapter.owner()
    local catalog=(LibraryAdapter.account_snapshot or {}).catalog or {}
    if not manual and catalog.canRefresh~=true then return false end
    local problem=Companion.workerProblem()
    if not owner or problem then
        if manual and not reading() then
            UIManager:show(require("ui/widget/infomessage"):new{text=problem or _("Connect to the server and sign in to refresh the catalog.")}) -- gate: user action (explicit refresh)
        end
        return false
    end
    local generation={}
    if Library.catalog_active and Library.catalog_owner==owner and (not manual or Library.catalog_requested=="full" and (action=="full" or action=="refresh")) then
        if manual and Badge.running then Badge.expand() end
        return true
    end
    if Library.catalog_retire then Library.catalog_retire() end
    Library.catalog_owner=owner
    Library.catalog_requested=action
    Library.catalog_generation=generation
    Library.catalog_active=true
    Wifi.acquire("mirror")
    local finished=false
    local retireCommand,statusPoll
    local deadline=now_s()+120
    local function finish()
        if finished then return end
        finished=true
        if retireCommand then retireCommand() end
        if statusPoll then UIManager:unschedule(statusPoll) end
        if Library.catalog_generation==generation then
            Library.catalog_active=nil
            Library.catalog_retire=nil
        end
        Wifi.release("mirror")
    end
    Library.catalog_retire=finish
    local function accept(result)
        if finished or Library.catalog_generation~=generation then return end
        if LibraryAdapter.owner()~=owner or result.error then finish(); return end
        Library.catalog_status=result
        if manual and action=="full" and Library.catalogStarted then Library.catalogStarted() end
        if manual and action=="full" and not Badge.running and not reading() then Badge.start(true,result) end
        local function poll()
            if finished or Library.catalog_generation~=generation then return end
            if LibraryAdapter.owner()~=owner then finish(); return end
            local status=Library.catalogSnapshot()
            if now_s()>=deadline and (status.pending or result.run and status.run~=result.run) then
                finish()
                if Badge.running and not reading() then Badge.finish(_("Paused · it goes on when the server answers")) end
                return
            end
            if not status.pending and (not result.run or status.run==result.run) then
                Library.catalog_status=status
                if Badge.running and not reading() then Badge.update(status) end
                local stale=status.beat and Store.now()-status.beat>=90
                if status.running~=true or stale then
                    finish()
                    if Badge.running and not reading() then Badge.finish((stale or status.why and status.why~="finished") and _("Paused · it goes on when the server answers") or nil,status) end
                    LibraryAdapter.reset()
                    Library.changed({kind="catalog",owner=owner})
                    if Library.catalogFinished then Library.catalogFinished(status) end
                    return
                end
            end
            UIManager:scheduleIn(3,poll)
        end
        statusPoll=poll
        UIManager:scheduleIn(3,poll)
    end
    local started
    started,retireCommand=command("catalog.control",function()
        return LibraryAdapter.command("catalog.control",{owner=owner,action=action,manual=manual==true},accept)
    end)
    if not started then finish() end
    return started
end

if OrbitAndroid then
    local init=OrbitAndroid.init
    function OrbitAndroid:init(...)
        local result=init(self,...)
        if Library.connectorReady then Library.connectorReady() end
        Library.accountReturned()
        Library.catalogAction("initialize",{},function() end)
        Library.watchEvents()
        return result
    end
end

function Library.catalogAction(action,args,done)
    args=args or {};args.action=action;args.owner=LibraryAdapter.owner();args.open_path=storagePath()
    if not args.owner then if done then done({error="unavailable"}) end;return false end
    return command(action,function() return LibraryAdapter.command("catalog.action",args,done or function() end) end)
end
function Library.recommendations(args,done)
    return command("recommendations",function() return LibraryAdapter.command("settings.recommendations",args,function(result)
        if not result.error and not args.definitions then LibraryAdapter.recommendations=result end
        done(result)
    end,{kind="device"}) end)
end
function Library.endAction(name,...) return FinishUI.actions[name](...) end
function Library.openGrouped(title,source,query)
    if HomeHost.show() and HomeHost.active then HomeHost.active:showList(title,source,query) end
end
function Library.copiesTick(why)
    if S.keep_copies_current==false or reading() or Library.copies_pending then return end
    if Library.copies_at and now_s()-Library.copies_at<600 and why~="full refresh" then return end
    Library.copies_at=now_s();Library.copies_pending=true
    local ui=liveUI()
    return Library.catalogAction("copies.check",{enabled=true,open_path=ui and ui.document and ui.document.file},function()
        Library.copies_pending=nil
    end)
end

function Library.cachedAccountState() return LibraryAdapter.account_snapshot or {} end

-- Finish follows the existing sole position writer and its outbox; no replacement writer.
function Library.finishCurrent(done)
    if not LibraryAdapter.finishCurrent then done(false,"Sync unavailable");return false end
    return command("finish-current",function() return LibraryAdapter.finishCurrent(done) end)
end

-- Native catalog compatibility uses neutral references and companion-owned transfer only.
function Library.catalogDownload(reference,destination,file_reference,done)
    return Library.catalogAction("finish.download",{reference=reference,destination=destination,file_reference=file_reference},done)
end

-- Local reader/settings bindings; protocol objects never enter the plugin.
function Library.nativeReader(ui)
    if not (ui and ui.document and ui.doc_settings) then return end
    local digest=ui.doc_settings:readSetting("partial_md5_checksum")
    if type(digest)~="string" then return end
    local prepared=FinishUI.reader_key
    if not prepared or prepared.path~=ui.document.file or prepared.document~=digest or prepared.owner~=LibraryAdapter.owner() then prepared=nil end
    return {digest=digest,file=ui.document.file,key=prepared and prepared.key,book_id=prepared and prepared.reference,
        percentage=LibraryAdapter.readerPosition(ui.document.file),summary=ui.doc_settings:readSetting("summary") or {},doc_settings=ui.doc_settings}
end
local function connectorSettings()
    local key=NativeRetirement and NativeRetirement.plan and NativeRetirement.plan.settings_key
    return key and G_reader_settings:readSetting(key)
end
local function preferenceSource(settings,key)
    local rule=NativeRetirement and NativeRetirement.plan and NativeRetirement.plan.preference_overlay
    local record=rule and S[rule.record]
    if type(record)=="table" and next(record) and type(rule.guard)=="table" and type(rule.keys)=="table" then
        local n=0
        for name,value in pairs(rule.guard) do
            n=n+1;if n>8 or settings[name]~=value then return settings,false end
        end
        for i,name in ipairs(rule.keys) do if i>8 then break end;if name==key then return record,true end end
    end
    return settings,false
end
function Library.observeSetting(item)
    local settings=connectorSettings();local defaults=NativeRetirement and NativeRetirement.defaults
    if type(settings)~="table" or type(defaults)~="table" then return {available=false,reason="Connector defaults unavailable"} end
    local source=preferenceSource(settings,item.key)
    return {available=true,current=source[item.key],default=defaults[item.key]}
end
function Library.writeSetting(item,value)
    local settings=connectorSettings();if type(settings)~="table" then return false end
    local source,overlay=preferenceSource(settings,item.key)
    source[item.key]=value
    if overlay then saveSettings() else G_reader_settings:flush() end
    return true
end
function Library.sleepRefresh(extras)
    Companion.send(Companion.ACTION.SLEEP_REFRESH,extras);Library.watchEvents()
end
function Library.localBookReference(path)
    local row=FinishUI and FinishUI.reader_key
    return row and row.owner==LibraryAdapter.owner() and row.path==path and row.reference or nil
end
function Library.storageRecount(why)
    Companion.send(Companion.ACTION.STORAGE,{reason=tostring(why),limit=tostring((tonumber(S.storage_limit_mb) or 512)*1048576),mirror_covers=S.mirror_covers and "1" or "0"})
    Library.watchEvents()
end
LibraryAdapter.idle=function()
    Library.copiesTick("book closed")
    if FinishUI and not reading() and not FinishUI.sending then
        FinishUI.sending=true;Library.finishCurrent(function() FinishUI.sending=nil end)
    end
end
LibraryAdapter.networkRestored=function() return Library.refreshCatalog("resume",false) end
LibraryAdapter.backgroundBusy=function() return Library.catalog_active and "saving the catalog for offline" or nil end
LibraryAdapter.backgroundCommand=function(op,...)
    local hooks={ ["views.install"]=function() end,["cache.resume"]=LibraryAdapter.networkRestored,
        ["storage.recount"]=Library.storageRecount,["covers.refresh"]=function() return Library.refreshCatalog("covers",false) end,
        ["preferences.report"]=function(...) return Recommendations.report(...) end,["preferences.apply"]=function(...) return Recommendations.applyChoices(...) end,
        ["capabilities.lost"]=function() return Recommendations.pass("caps lost",nil,true) end,["capabilities.gained"]=function() return Recommendations.pass("capabilities gained") end }
    return assert(hooks[op],"Unknown lifecycle operation")(...)
end
Library.connectorReady=function() Library.watchEvents() end
Library.compatTick=Library.compatTick or function(t) if Sleep and Sleep.waited then Sleep.waited(t) end end
Library.catalogFinished=Library.catalogFinished or function() Library.copiesTick("catalog refresh") end
Library.compatEvent=function(ev)
    if ev.kind=="sleep_pool" and Sleep then Sleep.landed(ev)
    elseif ev.kind=="native_footer_repair" and type(ev.token)=="string" and S.native_footer_repair~=ev.token then
        local before=tonumber(ev.before);local after=tonumber(ev.after)
        if (before or ev.before=="nil") and (after or ev.after=="nil") then
            if G_reader_settings:readSetting("reader_footer_mode")==before then G_reader_settings:saveSetting("reader_footer_mode",after) end
            S.native_footer_repair=ev.token;saveSettings()
        end
    elseif (ev.kind=="copy.identity" or ev.kind=="finish.applied" or ev.kind=="download.saved") and ev.owner==LibraryAdapter.owner() then
        if ev.kind=="copy.identity" then
            -- The companion already repaired sidecars/statistics and its owned file ledger.
            Library.catalogAction("copies.ack",{token=ev.token})
        elseif ev.kind=="finish.applied" then
            local epoch=FinishUI.intent[ev.document] or 0
            Library.catalogAction("finish.validate",{document=ev.document,token=ev.token},function(result)
                if result.apply and ev.owner==LibraryAdapter.owner() and epoch==(FinishUI.intent[ev.document] or 0) then
                    FinishUI.jobs[ev.document]=nil
                    local ui=liveUI and liveUI()
                    if ev.native_summary and ev.native_token and ui and ui.document and ui.document.file==ev.path and ui.doc_settings then
                        local summary=Cache.copy(ui.doc_settings:readSetting("summary") or {})
                        summary.status,summary.modified=ev.native_summary.status,ev.native_summary.modified
                        ui.doc_settings:saveSetting("summary",summary)
                        ui.doc_settings:saveSetting("booksync_status_token",ev.native_token)
                        require("ui/widget/booklist").setBookInfoCacheProperty(ev.path,"status",summary.status)
                    end
                    Library.catalogAction("finish.ack",{document=ev.document,token=ev.token})
                end
            end)
        elseif ev.kind=="download.saved" and ev.deferred then Gate.show("downloaded book",function()
            UIManager:show(InfoMessage:new{text="Downloaded: "..tostring(ev.title or "Book"),timeout=3}) -- gate: Gate.show
        end) end
    end
end

-- Persist native intent before dispatch; retries after restart carry the same revision.
function Library.localCompletion(ui, automatic)
    if automatic then return end
    local b=Library.nativeReader(ui); if not b then return end
    local previous=ui.doc_settings:readSetting("booksync_local_completion") or {}
    local revision=math.max(tonumber(previous.revision) or 0,tonumber(ui.doc_settings:readSetting("booksync_local_completion_revision")) or 0,math.floor(os.time()*1000000+(now_s()%1)*1000000))+1
    local event={document=b.digest,revision=revision,token=b.digest..":"..string.format("%.0f",revision),
        complete=b.summary.status=="complete",at=os.time()}
    ui.doc_settings:saveSetting("booksync_local_completion",event)
    Library.sendLocalCompletion(event,ui.doc_settings)
end
function Library.sendLocalCompletion(event,settings)
    return deviceCommand("reading.local.event",event,function(result)
        if settings and result.revision then settings:saveSetting("booksync_local_completion_revision",result.revision) end
        Library.retry()
    end)
end
function Library.prepareLocalCompletion(ui)
    local b=Library.nativeReader(ui); if not b then return end
    local event=ui.doc_settings:readSetting("booksync_local_completion")
    if type(event)=="table" then Library.sendLocalCompletion(event,ui.doc_settings)
    else deviceCommand("reading.local.prepare",{document=b.digest,summary={status=b.summary.status,modified=b.summary.modified}},function(result)
        if result.revision then ui.doc_settings:saveSetting("booksync_local_completion_revision",result.revision) end
        Library.retry()
    end) end
end
function Library:localReading() return self:read("reading.local",{limit=1}) end
function Library.localReadingGoal(target,done)
    return deviceCommand("reading.local.goal",{target=target},function() Library.retry() end,done)
end

Library.companion=Library.companion or {}
function Library.companion.command(args,done)
    if args.action~="set" then
        if not ({permission=true,protected=true,setup=true,recovery=true})[args.action] then done({error="invalid"});return false end
        if Companion.workerProblem() then done({error="unavailable"});return false end
        local ok=Jni.startActivity{action=Companion.ACTION.READER_ACTION,package=Companion.PACKAGE, -- gate: user action (explicit system/security or recovery button)
            extras={booksync_action=args.action}}
        done(ok and {ok=true} or {error="unavailable"})
        return ok
    end
    return LibraryAdapter.command("reader.companion",args,function(result)
        if not result.error then Shared.refresh("reader-helper") end
        done(result)
    end,{kind="device"})
end

-- The reminder service uses this fixed device-local port; no arbitrary adapter operation.
function Library.remindersCommand(op,args,done)
    assert(({draft=true,list=true,retry=true,runtime=true,add=true,edit=true,setEnabled=true,delete=true,claimDue=true,respond=true,sleep=true})[op],"Unknown reminder operation")
    return command("reminders."..op,function()
        return deviceCommand("reminders."..op,args,function() end,done,(op=="draft" or op=="claimDue") and 1024 or 8192)
    end)
end
