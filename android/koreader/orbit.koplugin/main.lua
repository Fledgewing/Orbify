-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).
--[[--
Orbit: a KOReader plugin for Android e-readers (generic Android; vendor quirks live in VENDORS,
ko/jni.lua). It was the user patch 2-orbit-android.lua up to BookSync 0.7.x and behaves the same.

BookSync's companion owns sync transport, durable lifecycle replay and position decisions.
The reader captures small native locators/geometry and displays explicit consent. The
migration gate disables the retired sync client before any plugin instances start.
KOReader's own built-in sync remains independent.

Layout (docs/design/orbit-plugin.md): FILES below, loaded in that order into one environment
shared by the plugin's files, so each file's top-level names are visible to the others, as
they were in the single patch file. logic/ is pure (no KOReader modules, unit-tested by
android/koreader/test/); ko/ is the KOReader side.

Companion interface: android/docs/INTERFACE.md. Logs: `adb logcat | grep OrbitAndroid`.
]]

-- Stamped by the release workflow (.github/workflows/release.yml) from the tag; a copy from the
-- repo says 0.0.0-dev, which any release replaces. Kept near the top: the restart check and the
-- companion read it from this file's head.
local PATCH_VERSION = "0.0.0-dev"

local LOGIC = {
    "logic/ui_util.lua", "logic/schedule.lua", "logic/plan.lua", "logic/update.lua", "logic/wifi_plan.lua",
    "logic/home_plan.lua", "logic/native.lua", "logic/stats.lua", "logic/clicks.lua",
    "logic/prompts.lua", "logic/sheet_layout.lua", "logic/cache.lua", "logic/caps.lua", "logic/copies.lua", "logic/sleep_pool.lua", "logic/settings_sync.lua",
    "logic/orbismart.lua", "logic/status_layout.lua",
    "logic/reading_style.lua", "logic/account.lua", "logic/settings_ui.lua", "logic/reader_panel.lua", "logic/budgets.lua", "logic/widget_registry.lua", "logic/layout.lua", "logic/filter_sheet.lua", "logic/reading_stats.lua", "logic/local_widgets.lua", "logic/storage.lua", "logic/battery_widget.lua", "logic/home_host.lua", "logic/home_editor.lua", "logic/booklist.lua", "logic/series.lua",
}
local KO = {
    "ko/base.lua", "ko/ui/kit.lua", "ko/ui/catalog.lua", "ko/ui/settings_page.lua", "ko/ui/gallery.lua", "ko/service_notices.lua", "ko/jni.lua", "ko/companion.lua", "ko/library_bootstrap.lua", "ko/layout_store.lua", "ko/library_services.lua", "ko/retirement.lua", "ko/settings.lua", "ko/shared.lua",
    "ko/net.lua", "ko/wifi.lua", "ko/updater.lua",
    "ko/background.lua", "ko/runtime.lua", "ko/clicks_channel.lua", "ko/keys.lua",
    "ko/library_lifecycle.lua", "ko/module.lua", "ko/start.lua", "ko/home_lifecycle.lua", "ko/home.lua", "ko/sleep.lua", "ko/reading_sync.lua",
    "ko/library_diagnostics.lua", "ko/test_sync_path.lua", "ko/companion_activities.lua", "ko/companion_ui.lua", "ko/recommendations_backend.lua", "ko/recommendations.lua", "ko/menu.lua",
    "ko/wifi_backend.lua", "ko/endsheet.lua", "ko/finish.lua",
    "ko/db.lua", "ko/store.lua", "ko/badge.lua", "ko/sleep_backend.lua", "ko/sleepscreen.lua",
    "ko/sqlite_stress.lua", "ko/library.lua", "ko/position_prompt.lua", "ko/position_sync.lua", "ko/covers.lua", "ko/account.lua", "ko/reader_companion_service.lua", "ko/reader_companion.lua", "ko/reading_style.lua", "ko/custom_reading.lua", "ko/reader_panel.lua", "ko/filter_sheet.lua", "ko/reading_stats.lua", "ko/home_widgets.lua", "ko/storage.lua", "ko/clock.lua", "ko/library_local_widgets.lua", "ko/local_widgets.lua", "ko/battery.lua", "ko/home_host.lua", "ko/series.lua", "ko/home_editor.lua", "ko/booklist_config.lua", "ko/settings_view.lua", "ko/local_reading_settings.lua",
    "ko/library_reminders.lua", "ko/reminders.lua", "ko/status_layout.lua", "ko/notices.lua", "ko/main_loop.lua",
}

-- This plugin's folder: PluginLoader dofile()s <folder>/main.lua (frontend/pluginloader.lua:244).
local DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/main%.lua$") or "."

local env = setmetatable({
    PATCH_VERSION = PATCH_VERSION,
    -- The folder the self-update replaces (ko/updater.lua); tests point it elsewhere.
    PLUGIN_DIR = rawget(_G, "ORBIT_ANDROID_PLUGIN_DIR") or DIR,
    -- The folder this code loads from (the shared settings schema sits beside it, ko/settings.lua).
    SOURCE_DIR = DIR,
}, { __index = _G })

local function load(files)
    for _i, name in ipairs(files) do
        local chunk, err = loadfile(DIR .. "/" .. name)
        if not chunk then error("orbit.koplugin: " .. tostring(err), 0) end
        setfenv(chunk, env)
        chunk()
        if env.INACTIVE then return false end
    end
    return true
end

load(LOGIC)

if rawget(_G, "ORBIT_ANDROID_TEST") then
    return { Schedule = env.Schedule, Plan = env.Plan, Update = env.Update, WifiPlan = env.WifiPlan,
        HomePlan = env.HomePlan, disabledText = env.disabledText, Compat = env.Compat, Stats = env.Stats,
        Clicks = env.Clicks, SetupPrompt = env.SetupPrompt, MenuLock = env.MenuLock,
        SeriesPlan = env.SeriesPlan, ReadingStyle = env.ReadingStyle, BookList = env.BookList, HomeEditorPlan = env.HomeEditorPlan, Layout = env.Layout, WidgetRegistry = env.WidgetRegistry, Budgets = env.Budgets, FilterSheet = env.FilterSheet, RestartPlan = env.RestartPlan, Cache = env.Cache, SheetLayout = env.SheetLayout, Caps = env.Caps, CopiesPlan = env.CopiesPlan, SleepPool = env.SleepPool, SettingsSync = env.SettingsSync, OrbiSmart = env.OrbiSmart, StatusLayout = env.StatusLayout, BatteryGlyph = env.BatteryGlyph, PATCH_VERSION = PATCH_VERSION }
end

-- The old user patch still loaded (koreader/patches/2-orbit-android.lua; it hooks PluginLoader at
-- startup, before any plugin loads): it runs, and this plugin stays out, so nothing is hooked
-- twice. The companion and tools/install-usb.sh delete the patch when they install the plugin.
local function oldPatch()
    local okp, PluginLoader = pcall(require, "pluginloader")
    if not okp or type(PluginLoader) ~= "table" then return nil end
    for _i, fn in ipairs({ PluginLoader.loadPlugins, PluginLoader.genPluginManagerSubItem }) do
        local info = type(fn) == "function" and debug.getinfo(fn, "S") or nil
        local src = info and info.source or ""
        if src:find("2-orbit-android.lua", 1, true) then return (src:gsub("^@", "")) end
    end
end

local patch = oldPatch()
if patch then
    local okl, logger = pcall(require, "logger")
    if okl and type(logger) == "table" and type(logger.warn) == "function" then logger.warn("OrbitAndroid: the old patch is loaded (" .. patch .. "); the Orbit plugin stays off") end
    return { disabled = true }
end

if not load(KO) then return { disabled = true } end

env.log("plugin", PATCH_VERSION, "loaded; companion", env.Companion.installed() and "installed" or "not installed",
    "| schedule", env.S.reading_schedule, "| sleep cap", env.S.sleep_cap .. "s")

return env.OrbitAndroid
