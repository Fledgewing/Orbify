-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).
-- Part of orbit.koplugin: loaded by main.lua into the plugin's shared environment, in the
-- order main.lua lists (docs/design/orbit-plugin.md "Module layout").

-- "Go home" from the companion launcher
---------------------------------------------------------------------------------------------

function OrbitAndroid:checkCommand(source)
    local cmd, from, held = Library.launch.intake(source)
    if not cmd then return false end
    if cmd == "home" or cmd == "home_smart" then
        self:smartHome(source, from or nil, cmd == "home" and HomePlan.SERVER_HOME or "smart", held or nil)
        return true
    end
    if cmd == "restart" then
        Library.launch.restart(self,source)
        return true
    end
    if cmd == "reopen_book" then
        Library.launch.reopen(self,source)
        return true
    end
    -- recommended settings' review page.
    if cmd == "signin" then
        UIManager:scheduleIn(0.5, function() self:openSignIn(source) end)
        return true
    end
    if cmd == "recommended" then
        UIManager:scheduleIn(0.5, function() self:showRecommended("companion") end)
        return true
    end
    -- The companion's Settings buttons (docs/design/companion-settings.md §3.2, A2, A4, A5): the work
    -- happens here in KOReader, which the command brought to the front.
    if cmd == "full_refresh" then
        UIManager:scheduleIn(0.5, function() Library.fullRefresh() end)
        return true
    end
    if cmd == "sync_sleep" then
        UIManager:scheduleIn(0.5, function() Library.syncAndSleep(self) end)
        return true
    end
    if cmd == "test_sync_path" then
        UIManager:scheduleIn(0.5, function() self:testSyncPath() end)
        return true
    end
    log("unknown command ignored:", cmd)
    return false
end

function OrbitAndroid:openSignIn(source)
    return AccountView.open("account")
end

-- topmost (the plugin's own test, main.lua:1384) and shows its dashboard context
-- (book details, lists, sheets over it) don't count.
-- The topmost screen: notes (KOReader's toasts, Orbit's own notes) float over it and never count.
function topWidget()
    local okw, stack = pcall(function() return UIManager._window_stack end)
    if okw and type(stack) == "table" and #stack > 0 then
        for i = #stack, 1, -1 do
            local w = stack[i] and stack[i].widget
            if w and not w.invisible and not w.toast and not w.orbit_note then return w end
        end
        return nil
    end
    local okt, top = pcall(function() return UIManager:getTopmostVisibleWidget() end)
    return okt and top or nil
end

-- Nothing interrupts reading (docs/design/reading-gate.md): while a book is open in front,
-- nothing from BookSync shows, restarts or takes focus. reading() is the one gate; every note and
-- message goes through Gate.show, which holds it until the next moment nobody is reading
-- and drops it when it has gone stale. Exceptions are only what the reader does in the book:
-- menus they open, the end-of-book sheet.
function reading()
    if StorageUI and (StorageUI.opening or StorageUI.active and topWidget() == StorageUI.active) then return false end
    if BatteryUI and (BatteryUI.opening or BatteryUI.active and topWidget() == BatteryUI.active) then return false end
    if HomeHost and (HomeHost.opening or HomeHost.foreground()) then return false end
    local ui = liveUI()
    if not (ui and ui.document) then return false end
    if not Library.isForeground() then return false end

    if ui.menu and ui.menu.menu_container then return false end -- a menu the reader opened
    if (FinishUI and FinishUI.sheet~=nil) then return false end                -- the reader reached the end
    return true
end

Gate = { queue = {}, MAX_AGE_S = 600 }

function Gate.refreshNotice(what)
    local full = Library.catalog_active
    log((full and "Full refresh" or "background") .. ": suppressed notice: " .. tostring(what))
    if full and Badge and Badge.notice then Badge.notice(what) end
end

-- what: for the log; fn: shows it; max_age_s: dropped after this long held.
function Gate.show(what, fn, max_age_s, visible_owner)
    -- Updating the user's already visible modal is not a background notice.
    -- Keep the one reading gate and verify ownership before replacing it.
    if visible_owner and topWidget()==visible_owner and not reading() then return fn() end
    if Gate.silent() then
        Gate.refreshNotice(what)
        return
    end
    if not reading() then
        log("notice: shown: " .. tostring(what))
        return fn()
    end
    log("notice: suppressed (held while reading): " .. tostring(what))
    for _, q in ipairs(Gate.queue) do
        if q.what == what then q.fn, q.at = fn, now_s(); return end -- the newest of the same kind
    end
    table.insert(Gate.queue, { what = what, fn = fn, at = now_s(), max_age = max_age_s or Gate.MAX_AGE_S })
end

function Gate.drain(why)
    if Gate.inBackground() and not (Library.catalog_active) then return end
    if Gate.silent() then
        for _, q in ipairs(Gate.queue) do Gate.refreshNotice(q.what) end
        Gate.queue = {}
        return
    end
    if #Gate.queue == 0 or reading() then return end
    local list = Gate.queue
    Gate.queue = {}
    for _, q in ipairs(list) do
        if now_s() - q.at <= q.max_age then
            log("gate: shown now (" .. tostring(why) .. "):", q.what)
            pcall(q.fn)
        else
            log("notice: suppressed (stale): " .. tostring(q.what))
        end
    end
end

function Gate.installToast()
    -- The final boundary also catches direct KOReader and Trapper messages.
    -- Dialogs (including position-sync choices) are unaffected.
    wrap(UIManager, "show", function(stock) return function(self, w, ...)
        local notice = w and (false or w.is_infomessage or w.orbit_note)
        local m = w and getmetatable(w)
        while m and not notice do
            notice = m == InfoMessage or m == package.loaded["ui/widget/notification"]
            m = getmetatable(m)
        end
        if notice then
            local text = w.text
            if not text and w.variants then
                local parts = {}
                for _, part in ipairs(w.variants[1] or {}) do parts[#parts + 1] = tostring(part.t or "") end
                text = table.concat(parts)
            end
            -- Invisible Trapper input traps have no message and must keep working.
            if text ~= nil then
                -- Zero-timeout opening messages keep UIManager alive until its
                -- next-tick ReaderUI constructor runs. Callback-bearing widgets
                -- also belong to a caller's control flow, not the notice queue.
                if not w.orbit_refresh_popup and w.timeout ~= 0 and not w.dismiss_callback
                    and not w.invisible and Gate.silent() then
                    Gate.refreshNotice("notice: " .. tostring(text)); return
                end
                log("notice: shown: " .. tostring(text))
            end
        end
        return stock(self, w, ...)
    end end, "refresh_notices")
    Gate.installCatalog()
    Gate.installTrapper()


end

-- A short note that never sits in the way: KOReader's Notification is a toast (it lets every
-- tap through and closes on the next event, notification.lua:63), so Home opening under it
-- still sees Home on top. Without it: an InfoMessage marked as a note. Held while reading.
function orbitNote(text, timeout, refresh_popup)
    local show = function()
        local okn, Notification = pcall(require, "ui/widget/notification")
        if okn and type(Notification) == "table" and type(Notification.new) == "function" then
            local okw, w = pcall(Notification.new, Notification, { text = text, timeout = timeout or 4 })
            if okw and w then w.orbit_note = true; w.orbit_refresh_popup = refresh_popup; UIManager:show(w); return w end -- gate: inside Gate.show
        end
        local w = InfoMessage:new{ text = text, timeout = timeout or 4 }
        w.orbit_note = true
        w.orbit_refresh_popup = refresh_popup
        UIManager:show(w) -- gate: inside Gate.show
        return w
    end
    if refresh_popup then return show() end
    return Gate.show("note: " .. tostring(text), show)
end

-- as toasts) and KOReader's widgets float over Home while the reader browses it (v0.11.1 on the
-- M8C held Full refresh's progress "while reading" with Home on screen). The pills alone, over
-- the book, don't count. Shared by reading() and the Wi-Fi plan's "browsing".
function visibleStack()
    local out = {}
    local okw, stack = pcall(function() return UIManager._window_stack end)
    if okw and type(stack) == "table" then
        for i = #stack, 1, -1 do
            local w = type(stack[i]) == "table" and stack[i].widget or nil
            if w ~= nil and not w.invisible then table.insert(out, w) end
        end
    else
        local top = topWidget()
        if top then out[1] = top end
    end
    return out
end

--   "main": the catalog (main.lua:1207-1229) is the topmost widget, in dashboard mode
--     showRecentSearches; detail_sheet/list_sheet live in that context, :2451-2462), or
--   nil: no catalog showing (none, or KOReader's file browser or a book over it).
-- Returns kind, the widgets over the catalog (topmost first), and a description for the log.
function keepHeldRotation(action, held, in_reader, source)
    if held == nil then return end
    -- KOReader's start already kept the held rotation (patches/1-orbit-start-rotation.lua).
    if source == "start" and Library.launch.startRotation() ~= nil then
        log("home: rotation kept from the start (" .. tostring(Library.launch.startRotation()) .. ")")
        return
    end
    local okc, current = pcall(function() return Device.screen:getRotationMode() end)
    local okl, locked = pcall(function() return G_reader_settings:isTrue("lock_rotation") end)
    local mode = HomePlan.rotation{
        action = action, held = held, in_reader = in_reader,
        current = okc and current or nil, locked = okl and locked or false,
    }
    if mode == nil then
        log("home: rotation stays", okc and tostring(current) or "?", "(held " .. tostring(held) .. ")")
        return
    end
    local okf, FM = pcall(require, "apps/filemanager/filemanager")
    local oks, err = pcall(function()
        if okf and type(FM) == "table" and FM.instance then FM.instance:onSetRotationMode(mode)
        else Device.screen:setRotationMode(mode) end
    end)
    log("home: rotation", tostring(current), "->", mode, "(held " .. held .. ")", oks and "" or tostring(err))
end

-- A book closing opens a new file browser, which turns the device to the file browser's rotation
-- start sets it before plugins load (reader.lua:291); the companion's ROTATION corrects that one.
function keepRotationOnFileBrowser(why)
    local okf, FM = pcall(require, "apps/filemanager/filemanager")
    if not okf or type(FM) ~= "table" or rawget(FM, "_orbit_keep_rotation") then return end
    if not Compat.callable(FM.setRotationMode) then
        log("compat: FileManager.setRotationMode missing; the file browser keeps its own rotation")
        return
    end
    FM._orbit_keep_rotation = true
    FM.setRotationMode = function()
        log("file browser: rotation stays", tostring(select(2, pcall(function() return Device.screen:getRotationMode() end))))
    end
    log("file browser: keeps the current rotation (" .. why .. ")")
end

-- Home (android/docs/INTERFACE.md "go home"): HomePlan decides. mode: "smart" (home_smart) or
-- HomePlan.SERVER_HOME (home).
function OrbitAndroid:smartHome(source,from_extra,mode,held)
    local host=HomeHost.active
    local ui=liveUI()
    -- Preserve the owned Home's established toggle and Back behavior.
    if Library.settings.read("home_screen")=="booksync" then
        if (mode==nil or mode=="smart") and host and topWidget()==host and ui and ui.document then return host:onClose() end
        return HomeHost.show()
    end
    -- The older Home choice retains its book -> Home -> companion cycle using owned UI.
    if host and HomeHost.foreground() then
        if from_extra=="other_app" then
            if ui and ui.document then UIManager:close(host);return true end
            return HomeHost.show()
        end
        if host.list_layout or host.series_key then return host:onClose() end
        return self:openCompanionHome()
    end
    if from_extra=="other_app" and ui and ui.document and (mode==nil or mode=="smart") then return true end
    return HomeHost.show()
end

-- :2521-2525). If anything is left over it, or the plugin lacks goDashboard: close the catalog
function OrbitAndroid:onOrbitGoHome() return HomeHost.show() end
function OrbitAndroid:finishHome()
    if Library.launch.finishPendingHome() then return HomeHost.show() end
end

function OrbitAndroid:whereNow()
    local ui = liveUI() or self.ui
    if HomeHost.foreground() then return HomePlan.SERVER_HOME end
    if ui and ui.document then return "reader" end
    return "browser"
end

-- The one-time "Setup needs you" box (SetupPrompt). where: given (the menu) or looked up.
function OrbitAndroid:maybeSetupPrompt(why, where)
    if (SettingsView and SettingsView.active and SettingsView.active.alive) or (AccountView and AccountView.active and AccountView.active.alive) or (ReaderCompanionView and ReaderCompanionView.active and ReaderCompanionView.active.alive) then return end
    pcall(self.maybeRecommendedLine, self, where)
    local text=Library.setupPrompt(why,where or self:whereNow())
    if not text then return end
    OrbitAndroid.setup_dialog=ConfirmBox:new{ -- gate: SetupPrompt.decide never shows it in a book
        text = _(text),
        ok_text = _("Fix now"),
        cancel_text = _("Later"),
        ok_callback = function()
            OrbitAndroid.setup_dialog=nil
            local ok = Library.companion.openSetup()
            log("setup box: Fix now", ok and "opened the companion" or "FAILED to open the companion")
        end,
        cancel_callback = function()
            OrbitAndroid.setup_dialog=nil
            -- The companion's own Later: quiet until an update or a step stops working.
            Library.companion.setupLater()
            log("setup box: Later")
        end,
    }
    UIManager:show(OrbitAndroid.setup_dialog) -- gate: explicit setup policy; never over owned settings
end

---------------------------------------------------------------------------------------------

function OrbitAndroid:showWakeBanner(res)
    local text = _("Can't reach library. Reading from this device's place.") .. "\n" .. (res.detail or "")
    local retry = function() Library.wake(self,"retry") end
    Gate.show("wake banner: " .. text, function()
        UIManager:show(InfoMessage:new{ text=text,timeout=6 }) -- gate: Gate.show
    end, 60)
end
