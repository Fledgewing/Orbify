-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).
-- Part of orbit.koplugin: loaded by main.lua into the plugin's shared environment, in the
-- order main.lua lists (docs/design/orbit-plugin.md "Module layout").

-- Menu (mockup screen 6): Tools › BookSync
---------------------------------------------------------------------------------------------

function toggle(key, text, help)
    return {
        text = text,
        help_text = help,
        checked_func = function() return Library.settings.read(key) == true end,
        callback = function()
            -- A shared setting goes to the companion with its time (docs/design/companion-settings.md §4).
            if Library.settings.schema().byKey[key] then return Library.settings.set(key, not Library.settings.read(key)) end
            Library.settings.write(key, not Library.settings.read(key))
            log("setting", key, "=", tostring(Library.settings.read(key)))
        end,
    }
end

-- A shared key's toggle with the companion's words: the schema's label, its line as help
-- (docs/design/companion-settings.md §5.7).
function stoggle(key)
    local d = Library.settings.schema().byKey[key]
    if not d then return toggle(key, key) end
    return toggle(key, _(d.label), _(d.line) .. (d.applies == "restart" and (" " .. _("Applies when KOReader restarts.")) or ""))
end

local function label(key, fallback)
    local d = Library.settings.schema().byKey[key]
    return d and _(d.label) or fallback
end

local function sectionTitle(id, fallback)
    for _i, sec in ipairs(Library.settings.schema().sections or {}) do if sec.id == id then return _(sec.title) end end
    return fallback
end

-- Drops the false placeholders a conditional row leaves.
local function compact(items)
    local out = {}
    for i = 1, table.maxn(items) do if items[i] then table.insert(out, items[i]) end end
    return out
end

-- Tiny bundled notice, loaded only for this explicit menu action.
function OrbitAndroid:showAbout()
    local credits = Library.resources.about()
    local lines = { "BookSync " .. PATCH_VERSION }
    for i, text in ipairs(credits.paragraphs) do
        table.insert(lines, text)
        if i == 2 then table.insert(lines, credits.url) end
    end
    UIManager:show(TextViewer:new{ title = _("About BookSync"), text = table.concat(lines, "\n\n") }) -- gate: user action (About menu)
end

function OrbitAndroid:statusText()
    local parts = {}
    local cstate = Library.companion.status()
    if cstate == "ok" then
        table.insert(parts, _("companion installed"))
    elseif cstate == "frozen" then
        table.insert(parts, Library.companion.disabledText())
    else
        table.insert(parts, _("no companion"))
    end
    table.insert(parts, _("Wi-Fi: ") .. _(Library.settings.wifiLabel()))
    local last = Library.settings.read("last_sleep_sync")
    if last then
        table.insert(parts, string.format("%s %s %s", _("last sleep sync"), last.ok and fmt(last.seconds) or _("failed"),
            os.date("%H:%M", last.at)))
    end
    local need = Library.settings.setupNeededText()
    if need then table.insert(parts, need) end
    local update=Library.settings.status("app_update")
    if update then table.insert(parts,update) end
    return _("Status: ") .. table.concat(parts, " · ")
end

function OrbitAndroid:updateStatusText()
    local st = Library.settings.read("patch_update_status")
    local head = string.format(_("Patch %s"), PATCH_VERSION)
    if not st then return head .. " · " .. _("not checked yet") end
    return string.format("%s · %s (%s)", head, st.text, os.date("%m-%d %H:%M", st.at))
end

-- By hand: Orbit Companion checks (it brings Wi-Fi up for a check by hand) and installs the update.
function OrbitAndroid:showWhatsNew()
    SettingsView.open("What's new in 0.12",function() return {
        {text="Home is a widget grid you can edit",enabled=false},
        {text="Lists (your saved filters) on Home",enabled=false},
        {text="BookSync settings on the reader",enabled=false},
        {text="Battery widget with time left at your usual use",enabled=false},
    } end,"settings-updates")
end

function OrbitAndroid:checkPatchUpdate()
    UIManager:show(InfoMessage:new{ text = Library.checkUpdate("menu"), timeout = 6 }) -- gate: user action (menu Update)
end

-- All values and choices come from the shared schema; wire IDs stay unchanged.
function OrbitAndroid:settingRow(key)
    local d = assert(Library.settings.schema().byKey[key], "Missing shared setting: " .. key)
    local function display(text)
        if key == "sync_mode" and text == "Custom" then return "KOReader decides" end
        return SettingsUI.words(text, key == "home_button" and Library.settings.read("home_screen") or nil)
    end
    local function set(value)
        Library.settings.set(key, value)
    end
    local row = { help_text = _(display(d.line or "")) }
    row.note_func=function()
        if key=="wifi_idle_min" and Library.settings.mode()~="jit" then return "Only used with Just in time Wi-Fi" end
        if key=="sleep_cap" and not Library.settings.read("sync_on_sleep") then return "Only used when syncing on sleep" end
        if key=="reading_schedule" and Library.settings.mode()=="off_reading" and Library.settings.read("reading_schedule")~="off" then
            return "Wi-Fi is off while reading; these syncs wait until you close the book."
        end
    end
    if d.type == "bool" then
        row.text = _(SettingsUI.labels[key] or display(d.label))
        row.checked_func = function() return Library.settings.read(key) == true end
        row.callback = function() set(not Library.settings.read(key)) end
    elseif d.type == "source" then
        row.text = _(SettingsUI.labels[key] or display(d.label))
        row.sub_item_table = {}
        for _i, choice in ipairs(d.values) do
            row.sub_item_table[#row.sub_item_table+1] = {text=_(choice.label),
                checked_func=function()
                    for _j, id in ipairs(SleepPool.sources(Library.settings.read(key))) do if id == choice.id then return true end end
                    return false
                end,
                callback=function() set(SleepPool.togglePick(Library.settings.read(key), choice.id)) end}
        end
        row.keep_choices=true
        row.sub_item_table[#row.sub_item_table+1] = {text=_("Choose saved lists…"), callback=function() SettingsView.sleepChoices(key) end}
    elseif d.type == "rules" then
        row.text_func = function() return _(d.label) .. ": " .. SettingsUI.value(d, Library.settings.read(key)) end
        row.keep_choices=true
        row.sub_item_table_func=function()
            local items={}
            for _,id in ipairs(SleepPool.decodeRules(Library.settings.read(key))) do
                items[#items+1]={text="Remove: "..id,callback=function() set(SettingsUI.toggleRule(Library.settings.read(key),id)) end}
            end
            items[#items+1]={text="Whole library",checked_func=function() return Library.settings.read(key) and Library.settings.read(key)[1]=="library" end,
                callback=function() set(SettingsUI.toggleRule(Library.settings.read(key),"library")) end}
            items[#items+1]={text="Browse lists, collections and tags…",callback=function() SettingsView.sleepChoices(key) end}
            items[#items+1]={text="Type a tag…",callback=function()
                local dialog
                dialog=require("ui/widget/inputdialog"):new{title="Never show a tag",input="",buttons={{
                    {text="Cancel",callback=function() UIManager:close(dialog) end},
                    {text="Add",callback=function()
                        local rule=SleepPool.parseRule("tag:"..dialog:getInputText())
                        UIManager:close(dialog)
                        if rule then set(SettingsUI.toggleRule(Library.settings.read(key),rule.key)) end
                    end}}}}
                UIManager:show(dialog) -- gate: user action (sleep exclusion tag)
                dialog:onShowKeyboard()
            end}
            return items
        end
    elseif d.type == "text" then
        row.text_func = function() return _(SettingsUI.labels[key] or display(d.label)) .. ": " .. SettingsUI.value(d, Library.settings.read(key)) end
        row.callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local dialog
            dialog = InputDialog:new{title=_(SettingsUI.labels[key] or display(d.label)), input=Library.settings.toWire(d, Library.settings.read(key)),
                buttons={{
                    {text=_("Cancel"), callback=function() UIManager:close(dialog) end},
                    {text=_("Save"), callback=function()
                        local value = Library.settings.fromWire(d, dialog:getInputText())
                        UIManager:close(dialog)
                        if value ~= nil then set(value) end
                    end},
                }}}
            UIManager:show(dialog) -- gate: user action (settings input)
            pcall(dialog.onShowKeyboard, dialog)
        end
    else
        row.text_func = function()
            return _(SettingsUI.labels[key] or display(d.label)) .. ": " .. _(display(SettingsUI.value(d, key == "wifi_mode" and Library.settings.mode() or Library.settings.read(key))))
        end
        row.sub_item_table = {}
        for _i, v in ipairs(d.values or {}) do
            local value = Library.settings.fromWire(d, v.id)
            table.insert(row.sub_item_table, {text=key=="update_channel" and SettingsUI.channelText(v.id,v.label,PATCH_VERSION) or _(display(v.label)),
                height=key=="update_channel" and 96 or nil,radio=true,
                checked_func=function() return Library.settings.toWire(d, Library.settings.read(key)) == tostring(v.id) end,
                callback=function() set(value) end})
        end
    end
    if key == "wifi_mode" or key == "wifi_idle_min" or key == "wifi_via_companion" then
        row.enabled_func = function() return Library.companion.has("wifi") end
        if not Library.companion.has("wifi") then
            row.help_text = row.help_text .. " " .. _("Wi-Fi switching is unavailable in this setup. Wi-Fi stays as you leave it.")
        end
    end
    return row
end

function OrbitAndroid:menuItems()
    local finish = Budgets.span("settings.paint", now_s, log)
    local function later(fn)
        return function(touchmenu)
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            UIManager:scheduleIn(0.2, fn)
        end
    end
    local function action(text, fn) return {text=_(text), callback=later(fn)} end
    local function rows(keys)
        local out = {}
        for _i, key in ipairs(keys) do out[#out+1] = self:settingRow(key) end
        return out
    end
    local function group(id, title, make)
        return {text=_(title), settings_group=id, sub_item_table_func=function()
            local span = Budgets.span("settings." .. id .. ".paint", now_s, log)
            local items = make()
            assert(#items <= Budgets.get("screens", "settings-" .. id).rows, "Settings row budget exceeded")
            span()
            return items
        end}
    end
    local items = {
        group("account", "Your server", function()
            local a=AccountView.read()
            local out={action(AccountPlan.summary(a),function() AccountView.open() end),
                action(a.signedIn and "Sign in again…" or "Sign in to your server",function() AccountView.open("account") end)}
            if a.signedIn then out[#out+1]=action("Sign out",function()
                local v=AccountView.open(); v.page="signout"; v.focus="keep"; v:paint()
            end) end
            out[#out+1]={text="Logins",enabled=false}
            for _,k in ipairs({"sync","opds"}) do
                out[#out+1]=action(AccountPlan.names[k] .. " · " .. AccountPlan.status(AccountPlan.login(a,k)),function() AccountView.open(k) end)
            end
            return out
        end),
        group("sync", "Sync, Wi-Fi & power", function()
            local paint = Library.paint("settings-sync")
            local estimates = paint:modeEstimates()
            local account = paint:accountState()
            local device = paint:deviceSettings()
            paint:flush()
            local modes = {}
            for _i, mode in ipairs(SettingsUI.modes) do
                modes[#modes+1] = {text=_(mode.label) .. " · " .. SettingsUI.estimate(estimates, mode.id), help_text=_(mode.help) .. (Library.companion.has("wifi") and "" or (" " .. _("Wi-Fi switching is unavailable in this setup."))), radio=true,
                    enabled_func=function() return Library.companion.has("wifi") end,
                    checked_func=function() return SettingsUI.mode(Library.settings.read(), Library.settings.mode()) == mode.id end,
                    callback=function()
                        if not Library.companion.has("wifi") then return end
                        Library.settings.preset(mode.values)
                    end}
            end
            local modeRow={text_func=function() return _("Mode") .. ": " .. _(SettingsUI.modeLabel(Library.settings.read(), Library.settings.mode())) end, sub_item_table=modes,
                card_text=function() return SettingsUI.modeCard(Library.settings.read(),Library.settings.mode(),estimates) end,pending=estimates.pending,
                card_action=function()
                    local current=SettingsUI.mode(Library.settings.read(),Library.settings.mode())
                    local nextMode=({saver=2,balanced=3,current=1,custom=1})[current]
                    modes[nextMode].callback()
                end}
            local out = {modeRow}
            if Library.companion.addon() then
                out[#out+1]=action("Reader Helpers",function() ReaderCompanionView.open("helpers") end)
            end
            local text,go,note=AccountView.syncAction(account)
            table.insert(out, 1, action(text or "Sync now", text and go or function() Library.syncNow(self) end))
            out[1].help_text=note
            if SettingsUI.mode(Library.settings.read(), Library.settings.mode()) == "custom" then
                local reset = action("Back to Balanced", modes[2].callback)
                reset.enabled_func = modes[2].enabled_func
                out[#out+1] = reset
            end
            out[#out+1]={text_func=function()
                local name=SettingsUI.modeLabel(Library.settings.read(),Library.settings.mode())
                return name=="Your own settings" and "Your settings" or "What "..name.." does"
            end,enabled=false,section=true}
            for _i,key in ipairs(SettingsUI.syncKeys) do
                if key=="sync_mode" then out[#out+1]={text="Reading position",enabled=false,section=true} end
                out[#out+1]=self:settingRow(key)
            end
            out[#out+1]={text="Power",enabled=false,section=true}
            local sleep={text="Sleep after: "..(device.sleep_label or "Loading…"),pending=device.pending,enabled=not device.unavailable,sub_item_table={}}
            for i,ms in ipairs(SettingsUI.sleepTimes) do
                sleep.sub_item_table[#sleep.sub_item_table+1]={text=i==5 and "Never" or tostring(ms/60000).." min idle",radio=true,
                    checked_func=function() return device.sleep_ms==ms end,
                    callback=function()
                        local owner=SettingsView.active
                        Library.sleepAfter(ms,function(result)
                            if owner then owner:deviceResult(result) end
                        end)
                    end}
            end
            sleep.help_text="The reader sleeps after this long untouched. Android may ask you to allow changing system settings; then choose again."
            out[#out+1]=sleep
            out[#out+1] = action("Battery ›", function() BatteryUI.show() end)
            out[#out+1] = action("Sync and sleep now", function() self:onOrbitSyncAndSleep() end)
            if Library.positionEnabled() and self.ui and self.ui.document then
                out[#out+1] = action("Read from here everywhere", function() Library.readFromHere("menu") end)
            end
            return out
        end),
        group("library", "Library & downloads", function()
            local paint=Library.paint("settings-library")
            local storage=paint:storage(); paint:flush()
            local function openStorage(mode)
                local parent=SettingsView.active
                StorageUI.show(mode,nil,function()
                    if parent and parent.alive and UIManager:getTopmostVisibleWidget()==parent.dialog then parent:paint()
                    else self:showSettings("library") end
                end)
            end
            local out = {action("Storage",function() openStorage() end),
                action("Download folder",function() openStorage("folder") end)}
            out[1].detail=storage.free_label and (storage.free_label.." free") or "Space unavailable"
            out[2].detail=storage.folder_label or "Not selected"
            for _,row in ipairs(rows({"keep_copies_current", "offline_cache", "mirror_covers"})) do out[#out+1]=row end
            out[#out+1] = action("Full refresh", function() Library.fullRefresh() end)
            return out
        end),
        group("reading", "Reading", function()
            local out = CustomReading.settingsRows(self.ui)
            out[#out+1]=action("Reading statistics",LocalReadingSettings.open)
            local reminders=action("Reminders",RemindersUI.open);reminders.read_only=true -- local route stays available without PIN
            out[#out+1]=reminders
            out[#out+1]={text="BookSync reading menus",checked_func=Library.readerMenusEnabled,callback=function()
                Library.setReaderMenus(self.ui,not Library.readerMenusEnabled())
            end}
            for _, row in ipairs(rows({"status_orbit_layout", "status_orbit_size", "local_first", "eob_sheet", "eob_auto"})) do out[#out+1] = row end
            return out
        end),
        group("home", "Home", function()
            local out = {}
            out[#out+1] = action("Edit layout", function() HomeEditor.open("edit") end)
            out[#out+1] = action("Reset layout", function() HomeEditor.open("reset") end)
            out[#out+1] = action("Page names", function() HomeEditor.open("rename") end)
            out[#out+1] = self:settingRow("home_button")
            return out
        end),
        group("sleep", "Sleep screen", function()
            -- Shared values plus explicit six-row companion choice windows.
            local keys = {}
            for _i, d in ipairs(Library.settings.schema().settings) do if d.section == "sleep" and not d.hidden then keys[#keys+1] = d.key end end
            local out = rows(keys)
            out[#out+1] = action("Choose lists…", function() SettingsView.sleepChoices("sleep_from") end)
            out[#out+1] = action("Never show…", function() SettingsView.sleepChoices("sleep_leave_out") end)
            return out
        end),
        group("updates", "Updates", function()
            local out = {{text="Installed: " .. SettingsUI.installed(PATCH_VERSION),enabled=false},self:settingRow("update_channel")}
            out[#out+1] = action("Check now", function() self:checkPatchUpdate() end)
            local news=action("What's new", function() self:showWhatsNew() end); news.read_only=true
            out[#out+1]=news
            out[#out+1] = self:settingRow("auto_update_patch")
            out[#out+1] = self:settingRow("key_log")
            return out
        end),
        group("about", "About & help", function()
            local paint=Library.paint("settings-about")
            local device=paint:deviceSettings(); paint:flush()
            return {
            {text="Version: " .. SettingsUI.installed(PATCH_VERSION),enabled=false},
            {text="This reader: " .. (device.reader or "Loading…"),enabled=false,pending=device.pending},
            (function() local row = action("About", function() self:showAbout() end); row.read_only=true; return row end)(),
            action("Help and guides", function() self:onOrbitOpenCompanion() end),
            action("Advanced: open companion app", Library.companion.openStatus),
        } end),
    }
    assert(#items <= Budgets.get("screens", "settings").rows, "Settings row budget exceeded")
    finish()
    return items
end

-- Settings PIN set and locked: the companion's keypad, then open the menu again.
function OrbitAndroid:showPinKeypad(why)
    local ok = Library.companion.openPin() -- gate: user action (menu)
    log("menu: locked by the Settings PIN; keypad (" .. why .. ")", ok and "started" or "FAILED")
    return ok
end

-- Locked by the companion's Settings PIN: the same menu, read-only (docs/design/companion-settings.md
-- §4.7). Submenus open, so every value can be seen; nothing that changes or does something is
-- enabled. The first row asks for the PIN.
function OrbitAndroid.readOnly(items)
    local out = {}
    for _i, it in ipairs(items) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        if not it.read_only then c.card_action=nil end
        if type(it.sub_item_table) == "table" then
            c.sub_item_table = OrbitAndroid.readOnly(it.sub_item_table)
        elseif it.sub_item_table_func then
            local f = it.sub_item_table_func
            c.sub_item_table_func = function(...) return OrbitAndroid.readOnly(f(...) or {}) end
        elseif not it.read_only then
            c.enabled_func = function() return false end
            c.callback = function() end
        end
        table.insert(out, c)
    end
    return out
end

function OrbitAndroid:lockedMenuItems(items)
    items = OrbitAndroid.readOnly(items or self:menuItems())
    table.insert(items, 1, { text = _("Locked by the Settings PIN. Enter it to change these…"), separator = true,
        callback = function(touchmenu)
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            self:showPinKeypad("tap")
        end })
    return items
end

function OrbitAndroid:settingsPresentation(items)
    local out={}
    for _,item in ipairs(items) do
        local row={}; for k,v in pairs(item) do row[k]=v end
        if ({sync=true,library=true,home=true,sleep=true,updates=true,about=true})[row.settings_group] then
            local make=row.sub_item_table_func
            row.sub_item_table_func=nil
            row.settings_rows=make
            if row.settings_group=="updates" or row.settings_group=="about" then
                row.text_func=function()
                    if row.settings_group=="updates" then
                        return row.text.." · "..SettingsUI.value(Library.settings.schema().byKey.update_channel,Library.settings.read("update_channel")).." channel · "..PATCH_VERSION
                    end
                    return row.text.." · "..SettingsUI.installed(PATCH_VERSION)
                end
            end
            row.callback=function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                SettingsView.open(row.text,make,"settings-"..row.settings_group,function() self:showSettings() end)
            end
        end
        out[#out+1]=row
    end
    return out
end

-- The owned Home and reader gear share the existing Settings rows and PIN policy.
function OrbitAndroid:showSettings(group)
    if OrbitAndroid.setup_dialog then UIManager:close(OrbitAndroid.setup_dialog);OrbitAndroid.setup_dialog=nil end
    Library.settings.refresh("menu")
    Library.refreshDevice()
    local items={}
    for _,row in ipairs(self:menuItems()) do
        if row.settings_group then items[#items+1]=row end
    end
    if group=="account" and not Library.settings.status("pin_locked") then return AccountView.open() end
    local previous=SettingsView.active
    while previous do
        local parent=previous.parent
        previous.onBack=nil;previous.parent=nil;previous:close()
        previous=parent
    end
    if group then
        for _,row in ipairs(items) do if row.settings_group==group then
            local make=row.sub_item_table_func
            return SettingsView.open(row.text,function()
                local rows=make()
                return Library.settings.status("pin_locked") and OrbitAndroid.readOnly(rows) or rows
            end,"settings-"..group,function() self:showSettings() end)
        end end
    end
    if Library.settings.status("pin_locked") then items=self:lockedMenuItems(items) end
    local icons={account="settings-user",sync="sync",library="settings-download",reading="settings-type",home="home",sleep="settings-moon",updates="arrowU",about="info"}
    local subtitles={account="Account and logins",sync=SettingsUI.modeLabel(Library.settings.read(),Library.settings.mode()),library="Storage and downloaded books",reading="Fonts, margins and reading controls",home="BookSync Home",sleep="Cover and sleep screen choices",updates=SettingsUI.installed(PATCH_VERSION),about="BookSync "..PATCH_VERSION}
    return SettingsView.open("BookSync settings",function()
        local paint=Library.paint("settings")
        local account,storage,battery=paint:accountState(),paint:storage(),paint:battery()
        paint:flush()
        subtitles.account=AccountPlan.summary(account)
        subtitles.library=storage.folder_label or "Choose a download folder"
        local fonts=ReadingStyle.pair("font",Library.settings.read("reading_pairs"))
        local margins=ReadingStyle.pair("margins",Library.settings.read("reading_pairs"))
        subtitles.reading=ReadingStyle.presets.font[fonts[2]][1].." · "..ReadingStyle.presets.margins[margins[1]][1]:lower().." and "..ReadingStyle.presets.margins[margins[2]][1]:lower().." margins"
        subtitles.sleep=SettingsUI.value(Library.settings.schema().byKey.sleep_mode,Library.settings.read("sleep_mode"))
        subtitles.updates=SettingsUI.value(Library.settings.schema().byKey.update_channel,Library.settings.read("update_channel")).." channel · "..PATCH_VERSION
        if battery.display and battery.display.level and battery.display.level:find("%d") then subtitles.sync=SettingsUI.modeLabel(Library.settings.read(),Library.settings.mode()).." · "..battery.display.level.." battery" end
        local rows={}
        local setup=tonumber(Library.settings.status("setup_needed")) or 0
        if setup>0 then rows[#rows+1]={text="Companion setup",sub="Finish configuring this reader",detail=tostring(setup).." steps",icon="info",callback=Library.companion.openSetup} end
        for _,item in ipairs(items) do
            local id=item.settings_group
            rows[#rows+1]={text=item.text,icon=icons[id],sub=subtitles[id],callback=id and function() self:showSettings(id) end or item.callback}
        end
        return rows
    end,"settings")
end

function OrbitAndroid:addToMainMenu(menu_items)
    local entry = { text = _("BookSync"), callback = function(menu)
        if menu and menu.closeMenu then menu:closeMenu() end
        self:showSettings()
    end }
    -- Its own top-level entry in Tools, the way plugins and user patches add menus: an item
    -- missing from the menu order goes to the menu its sorting_hint names
    -- (frontend/ui/menusorter.lua:162-189). Nothing is injected into the plugin's menu.
    entry.sorting_hint = "tools"
    menu_items.orbit_android = entry
end

---------------------------------------------------------------------------------------------
