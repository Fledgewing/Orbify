-- Checks that every KOReader internal the Orbit plugin hooks or calls is still defined in a
-- KOReader checkout (and its koreader-base, for the ffi/ modules). Static: it looks for each
-- definition in the source, like plugin_compat.lua does for the BookOrbit plugin.
--   luajit koreader_compat.lua <koreader checkout> [<koreader-base checkout>]
-- Without a koreader-base checkout, the base checks are skipped and named.
-- Prints the KOReader version and any missing symbols; exits 1 when something is missing.
-- When the plugin starts using another KOReader symbol, add it here.
local root = arg[1] or error("usage: koreader_compat.lua <koreader dir> [<koreader-base dir>]")
local base = arg[2]

local function read(path)
    local h = io.open(path, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end
local function esc(s) return (s:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0")) end

-- Every .lua file under dir (for symbols KOReader defines in more than one place).
local function tree(dir)
    local out = {}
    local p = io.popen('find "' .. dir .. '" -name "*.lua" -type f 2>/dev/null')
    for f in p:lines() do table.insert(out, f) end
    p:close()
    return out
end

-- kind: "fn" a function (function X:name( / X.name = function / name = function), "field" an
-- assignment (name = / .name =), "text" a plain substring.
local function defined(text, name, kind)
    if kind == "text" then return text:find(name, 1, true) ~= nil end
    if kind == "fn" then
        return text:find("function%s+[%w_%.]+[:%.]" .. esc(name) .. "%s*%(") ~= nil
            or text:find("[%.%s{,]" .. esc(name) .. "%s*=%s*function") ~= nil
            -- a function another one stands for: isAndroid = yes, canRestart = no
            or text:find("[%.%s{,]" .. esc(name) .. "%s*=%s*[%w_%.]+%s*[,\n}]") ~= nil
    end
    return text:find("[%.%s{,]" .. esc(name) .. "%s*=") ~= nil
end

-- { file (relative to the checkout, "*" for anywhere under frontend/ and plugins/), symbols, base? }
-- Symbols: name (a function), or { name, kind }.
local F, T = "field", "text"
local NEEDS = {
    { "frontend/ui/widget/container/inputcontainer.lua", { {"stop_events_propagation", T} } },
    { "frontend/docsettings.lua", { {"function DocSettings:flush(data, no_custom_metadata)", T} } },
    { "frontend/apps/reader/modules/readerrolling.lua", { "onSaveSettings" } },
    { "frontend/apps/reader/modules/readerpaging.lua", { "onSaveSettings" } },
    { "frontend/ui/time.lua", { "boottime" } },
    { "frontend/ui/uimanager.lua", { "handleInputEvent" } },
    { "frontend/apps/reader/modules/readerpagemap.lua", { "wantsPageLabels", "cleanPageLabel", "getPageLabelProps" } },
    { "frontend/apps/reader/modules/readerlink.lua", { "addCurrentLocationToStack", "onGotoLink" } },
    { "frontend/apps/reader/modules/readerrolling.lua", { "onGotoXPointer" } },
    { "frontend/document/koptinterface.lua", { "nativeToPageRectTransform" } },

    { "frontend/device/android/device.lua", { {"home_dir", F}, {"android.isResumed()", T} } },
    -- Library's native reader-control adapter (pin documented in G-READER-NOTES.md).
    { "frontend/apps/reader/modules/readertoc.lua", { "onShowToc", {"toc", F} } },
    { "frontend/apps/reader/modules/readerannotation.lua", { {"annotations", F}, "getPageRef" } },
    { "frontend/apps/reader/modules/readerview.lua", { {"dogear_visible", F} } },
    { "frontend/apps/reader/modules/readerbookmark.lua", { "onShowBookmark", "onToggleBookmark", "getBookmarkPageNumber", "getBookmarkPageString", "gotoBookmark" } },
    { "frontend/apps/reader/modules/readergoto.lua", { "onShowGotoDialog" } },
    { "frontend/apps/reader/modules/readersearch.lua", { "onShowFulltextSearchInput" } },
    { "frontend/apps/reader/modules/readerconfig.lua", { "onShowConfigMenu", "onCloseConfigMenu", "onTapShowConfigMenu", "onSwipeShowConfigMenu" } },
    { "frontend/apps/reader/modules/readerrolling.lua", { "onGotoPercent", "onGotoNextChapter", "onGotoPrevChapter", "onSetStatusLine", {"current_page", F} } },
    { "frontend/apps/reader/modules/readerpaging.lua", { "onGotoPercentage", "onGotoNextChapter", "onGotoPrevChapter" } },
    { "frontend/apps/reader/modules/readerfont.lua", { "onSetFontSize" } },
    { "frontend/apps/reader/modules/readerfooter.lua", { "applyFooterMode", "onUpdateFooter" } },
    { "frontend/device/generic/device.lua", { "hasFrontlight", "hasNaturalLight", "getPowerDevice" } },
    { "frontend/apps/reader/modules/readerdictionary.lua", { "onLookupWord" } },
    { "frontend/device/generic/powerd.lua", { "frontlightIntensity", "frontlightWarmth", "setIntensity", "setWarmth" } },
    { "frontend/ui/widget/buttontable.lua", { {"buttons_layout", F} } },
    { "frontend/ui/widget/button.lua", { "onFocus", "onUnfocus" } },
    { "frontend/ui/widget/touchmenu.lua", { "init", {"tab_item_table", F} } },
    { "frontend/ui/widget/buttondialog.lua", { "getButtonById", "onClose", {"tap_close_callback", F} } },
    { "frontend/ui/widget/focusmanager.lua", { "moveFocusTo" } },
    { "frontend/ui/widget/infomessage.lua", { {"dismiss_callback", F} } },
    { "frontend/ui/trapper.lua", { "wrap", "info", "dismissableRunInSubprocess" } },
    { "frontend/ui/uimanager.lua", { "show", "close", "scheduleIn", "nextTick", "unschedule", "setDirty",
        "handleInput", "forceRePaint", "getElapsedTimeSinceBoot", "getTopmostVisibleWidget", "quit", "restartKOReader",
        "sendEvent", "broadcastEvent", "_repaint", { "_window_stack", F }, { "_refresh_stack", F },
        { "refresh_methods", T } } },
    { "*", { "isConnected", "isWifiOn", "turnOnWifi", "turnOffWifi", "beforeWifiAction",
        "turnOnWifiAndWaitForConnection", "scheduleConnectivityCheck" } },
    { "frontend/ui/network/manager.lua", { { "NetworkMgr", T } } },
    { "frontend/device/generic/device.lua", { "canRestart", "exit", "isAndroid", "isTouchDevice", { "screen", F }, { "input", F },
        { "closed_rotation_mode", T } } },
    -- The start patch (orbit.koplugin/patches/1-orbit-start-rotation.lua): early patches, then the
    -- settings, the Device, the late patches, the first file browser.
    { "frontend/userpatch.lua", { "applyPatches", { "early", F }, { "late", F } } },
    { "reader.lua", { { "userpatch.applyPatches(userpatch.early)", T }, { "userpatch.applyPatches(userpatch.late)", T },
        { "settings.reader.lua", T } } },
    { "frontend/device/input.lua", { "handleKeyBoardEv" } },
    { "frontend/device/devicelistener.lua", { "onToggleNightMode", "onIterateRotation" } },
    { "frontend/apps/reader/readerui.lua", { "init", "showReader", "registerModule", "onHome",
        { "instance", F }, { "registerModule(\"status\"", T }, { "registerModule(\"toc\"", T },
        { "registerModule(\"menu\"", T } } },
    -- Home keeps the held rotation (ko/home.lua keepHeldRotation, keepRotationOnFileBrowser).
    { "frontend/apps/filemanager/filemanager.lua", { { "instance", F }, "setRotationMode", "onSetRotationMode",
        { "lock_rotation", T } } },
    { "frontend/ui/widget/eventlistener.lua", { "handleEvent" } },
    { "frontend/apps/reader/modules/readermenu.lua", { "registerToMainMenu", "onCloseReaderMenu", "onShowMenu", "onTapShowMenu", "onSwipeShowMenu", "onPressMenu", "onKeyPressShowMenu",
        { "menu_container", F } } },
    { "frontend/ui/widget/progresswidget.lua", { {"percentage", F}, {"ticks", F}, {"bordersize", F}, {"margin_h", F}, {"margin_v", F}, {"radius", F} } },
    { "frontend/ui/widget/container/rightcontainer.lua", { {"RightContainer", T} } },
    { "frontend/ui/widget/container/topcontainer.lua", { {"TopContainer", T} } },
    { "frontend/apps/reader/modules/readerpaging.lua", { "getLastPercent", "getLastProgress" } },
    { "frontend/apps/reader/modules/readerrolling.lua", { "getLastPercent", "getLastProgress" } },
    { "frontend/apps/reader/modules/readertoc.lua", { "isChapterStart", "getPreviousChapter" } },
    { "frontend/ui/widget/booklist.lua", { "setBookInfoCacheProperty" } },
    { "frontend/apps/reader/modules/readerstatus.lua", { "onEndOfBook", "markBook", "onShowBookStatus",
        { "end_document_action", T } } },
    { "frontend/dispatcher.lua", { "registerAction" } },
    -- Plugin handlers are HandlerSandbox tables with __call (compat.lua Compat.callable).
    { "frontend/pluginloader.lua", { "loadPlugins", "genPluginManagerSubItem", "getPluginInstance", "createPluginInstance",
        { "HandlerSandbox", T }, { "__call", T } } },
    -- Recommended settings (ko/recommended.lua): the stock gesture defaults, Gestures.default_settings.
    { "plugins/gestures.koplugin/main.lua", { "onFlushSettings", { "data", F }, { "updated", F }, { "default_settings", F } } },
    { "plugins/gestures.koplugin/defaults.lua", { { "gesture_reader", F } } },
    { "frontend/docsettings.lua", { "open", { "LuaSettings:extend", T } } }, -- readSetting: LuaSettings'
    { "frontend/luasettings.lua", { "open", "readSetting", "saveSetting", "flush", "isTrue" } },
    { "datastorage.lua", { "getSettingsDir", "getDocSettingsHashDir" } },
    { "frontend/ui/event.lua", { "new" } },
    { "frontend/ui/time.lua", { "now", "to_s" } },
    { "frontend/ui/font.lua", { { "smallinfofont", F }, "getFace", { "xx_smallinfofont", F }, {"hash", F}, {"ftsize", F}, {"embolden_half_strength", F}, {"is_real_bold", F}, {"getFallbackFont", T} } },
    -- The Full refresh badge (ko/badge.lua): a toast (taps go on through it) that redraws only its rectangle.
    { "frontend/ui/uimanager.lua", { { "widget.toast", T } } },
    { "frontend/ui/size.lua", { { "padding", F }, { "radius", F }, { "line", F }, { "border", F } } },
    -- The end-of-book sheet's footer: one ButtonTable row without separators.
    { "frontend/ui/widget/buttontable.lua", { { "zero_sep", F }, { "sep_width", F } } },
    { "frontend/ui/geometry.lua", { "new", "contains" } },
    { "frontend/ui/gesturerange.lua", { { "GestureRange", T } } },
    { "frontend/socketutil.lua", { "set_timeout", "reset_timeout" } },
    { "frontend/logger.lua", { { "info", T }, { "warn", T } } },
    { "frontend/gettext.lua", { { "GetText", T } } },
    { "frontend/ui/widget/container/widgetcontainer.lua", { { "extend", T }, "paintTo", "free" } },
    { "frontend/ui/widget/container/inputcontainer.lua", { { "ges_events", T }, "paintTo" } },
    -- Owned Home and shared kit: native rounded frames, explicit font faces and icons.
    { "frontend/ui/widget/overlapgroup.lua", { "paintTo", {"overlap_offset", T}, {"allow_mirroring", F} } },
    { "frontend/ui/widget/progresswidget.lua", { "paintTo", {"percentage", F} } },
    { "frontend/ui/widget/button.lua", { "onFocus", "onUnfocus", {"height", F}, {"text_font_size", F}, {"avoid_text_truncation", F} } },
    { "frontend/ui/widget/container/framecontainer.lua", { {"radius", F}, {"background", F}, {"padding", F}, "getSize", "paintTo" } },
    { "frontend/ui/widget/iconwidget.lua", { {"icon", F} } },
    { "frontend/apps/reader/readerui.lua", { {"doc_props", T} } },
    -- V2 reader sheets: native input, dimmed book backdrop and contextual matches.
    { "frontend/ui/widget/container/alphacontainer.lua", { "paintTo", {"alpha", F} } },
    { "frontend/ui/widget/inputtext.lua", { "getText", "onShowKeyboard", "onCloseKeyboard", {"enter_callback", T}, {"parent", F} } },
    { "frontend/ui/widget/textboxwidget.lua", { {"PTF_HEADER", F}, {"PTF_BOLD_START", F}, {"PTF_BOLD_END", F}, {"height_overflow_show_ellipsis", F} } },
    -- Device-local Custom reading styles: quiet native setters and in-place Settings return.
    { "frontend/apps/reader/modules/readerfont.lua", { {"font_face", F}, {"font_base_weight", T}, {"line_spacing", T}, {"font_gamma", T} } },
    { "frontend/document/credocument.lua", { "setFontFace", "setFontBaseWeight", "setEmbeddedFonts", "setInterlineSpacePercent", "setGammaIndex", "engineInit" } },
    { "frontend/ui/widget/touchmenu.lua", { "updateItems", {"keep_menu_open", T} } },
    { "frontend/ui/widget/textboxwidget.lua", { {"line_height", F}, {"fgcolor", F}, {"face", F}, {"_face_adjusted", T} } },
    { "frontend/ui/widget/button.lua", { {"text_font_face", F} } },
    -- Reading strips: temporary effective margins and native hidden-footer release.
    { "frontend/apps/reader/modules/readerfooter.lua", { "getHeight", "onToggleFooterMode",
        { "reclaim_height", F }, { "pageno", F }, { "pages", F }, { "percent_finished", F } } },
    { "frontend/apps/reader/modules/readerview.lua", { "paintTo" } },
    { "frontend/apps/reader/modules/readertypeset.lua", { "onSetPageMargins", { "unscaled_margins", F } } },
    { "frontend/apps/reader/modules/readerrolling.lua", { "onUpdatePos", "onRedrawCurrentView", { "cre_top_bar_enabled", F } } },
    { "frontend/apps/reader/modules/readertoc.lua", { "getTocTitleByPage" } },
    { "frontend/document/document.lua", { "getPageCount" } },
    { "frontend/ui/widget/widget.lua", { "getSize" } },
    { "frontend/ui/widget/textwidget.lua", { "getSize", "paintTo", "free", "setText", "isTruncated" } },
    { "frontend/ui/widget/imagewidget.lua", { "_render", "paintTo", "free", {"rotation_angle", F} } },
    { "frontend/device/generic/device.lua", { "getPowerDevice" } },
    { "frontend/apps/reader/modules/readerdictionary.lua", { "onLookupWord" } },
    { "frontend/device/generic/powerd.lua", { "getCapacity", "isCharging" } },
    -- OrbiSmart (ko/orbismart.lua): places in this layout's pages, and the Yes / No popup (its
    -- Back / tap outside runs cancel_callback).
    { "frontend/document/credocument.lua", { "getPageCount", "getPageFromXPointer", "getCurrentPage", "setPageMargins", "findAllText", "getTextFromXPointers" } },
    { "frontend/apps/reader/modules/readerpaging.lua", { "onInitScrollPageStates" } },
    { "frontend/ui/widget/confirmbox.lua", { { "ok_text", F }, { "cancel_text", F }, { "cancel_callback", F },
        { "self.cancel_callback()", T } } },
    -- The sleep screen (ko/sleepscreen.lua): the open book's cover and title, and the text input.
    { "frontend/apps/filemanager/filemanagerbookinfo.lua", { "getCoverImage" } },
    { "frontend/apps/reader/readerui.lua", { { "doc_props", F } } },
    { "frontend/ui/widget/inputdialog.lua", { "getInputText", "setInputText", "onShowKeyboard" } },
}
-- Widgets the plugin builds with: each module must still exist.
for _, w in ipairs({ "infomessage", "textviewer", "confirmbox", "button", "container/bottomcontainer",
    "container/framecontainer", "horizontalgroup", "horizontalspan", "linewidget", "textboxwidget",
    "container/alphacontainer",
    "verticalgroup", "verticalspan", "buttontable", "textwidget", "imagewidget", "container/centercontainer",
    "container/leftcontainer", "menu", "buttondialog", "notification" }) do
    table.insert(NEEDS, { "frontend/ui/widget/" .. w .. ".lua", {} })
end
-- koreader-base (the base/ submodule): ffi modules the plugin requires.
local BASE = {
    { "ffi/freetype.lua", { "getEmboldenHalfStrength", "hasGlyph", "getInfo" } },
    { "cre.cpp", { {"getFontFaceFilenameAndFaceIndex", T} } },
    -- Home editor: dkjson preserves array/object tags and nulls for Layout.save/load.
    { "thirdparty/dkjson/CMakeLists.txt", { { "dkjson.lua", T } } },
    { "ffi/util.lua", { "runInSubProcess", "isSubProcessDone", "readAllFromFD", "writeToFD",
        "terminateSubProcess" } },
    { "ffi/input_android.lua", { { "waitForEvent", T } } },
    { "ffi/blitbuffer.lua", { { "COLOR_BLACK", F }, { "COLOR_WHITE", F }, { "COLOR_LIGHT_GRAY", F }, { "COLOR_GRAY", F }, { "COLOR_DARK_GRAY", F }, "paintRoundedRect", "paintBorder", "lightenRect", "paintRect", "writeToFile", "free", {"Color8", T} } },
    { "ffi/framebuffer_android.lua", { "getRotationMode", "setRotationMode", { "ASCREEN_ORIENTATION_", T } } },
    -- The offline cache's database (ko/db.lua; docs/design/sqlite-cache.md), as KOReader's statistics plugin uses it.
    { "thirdparty/lua-ljsqlite3/init.lua", { "open", "set_busy_timeout", "prepare", "exec", "rowexec", "step", "bind",
        "reset", "close", "_ncol", { "ro = sql.SQLITE_OPEN_READONLY", T } } },
}

local missing = {}
local function check(dir, list, label)
    local all
    for _, need in ipairs(list) do
        local file, syms = need[1], need[2]
        local text
        if file == "*" then
            if not all then
                local parts = {}
                for _, sub in ipairs({ "frontend", "plugins" }) do
                    for _, f in ipairs(tree(dir .. "/" .. sub)) do table.insert(parts, read(f) or "") end
                end
                all = table.concat(parts, "\n")
            end
            text = all
        else
            text = read(dir .. "/" .. file)
            if not text then table.insert(missing, label .. file .. " (file gone)") end
        end
        if text then
            for _, s in ipairs(syms) do
                local name, kind = s, "fn"
                if type(s) == "table" then name, kind = s[1], s[2] end
                if not defined(text, name, kind) then
                    table.insert(missing, label .. (file == "*" and "" or file .. ": ") .. name)
                end
            end
        end
    end
end

-- KOREADER_REF names what was checked (CI passes the tag); else the checkout's commit.
local function commit()
    local p = io.popen('git -C "' .. root .. '" rev-parse --short HEAD 2>/dev/null')
    local c = p:read("*l")
    p:close()
    return c
end
local version = os.getenv("KOREADER_REF") or commit() or "unknown"
check(root, NEEDS, "")
if base then check(base, BASE, "base ") end

table.sort(missing)
print("KOReader " .. tostring(version) .. (base and "" or " (koreader-base not given: ffi checks skipped)"))
if #missing == 0 then
    print("all hooked symbols present")
    os.exit(0)
end
print("missing: " .. table.concat(missing, ", "))
os.exit(1)
