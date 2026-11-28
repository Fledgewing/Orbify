-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Deliberate UI-facing services. Backends retain their existing behavior and ownership.
-- Immediate foreground handoff; the five-minute measurement timer is not a UI gate.
function Library.readingVisibilityChanged(reason)
    local ui=liveUI()
    return Companion.send(Companion.ACTION.STATS,{reason=reason,
        visibility_only="1",open=ui and ui.document and "1" or "0",reading=reading() and "1" or "0"})
end
function Library.homeVisibilityChanged(visible) return Library.readingVisibilityChanged(visible and "home" or "home-close") end
Library.settings={}
function Library.settings.read(key)
    -- Borrowed immutable values preserve layout array metadata; edits use complete settings intents.
    if key then return S[key] end
    local values={}
    for _,name in ipairs(SettingsUI.modeKeys) do values[name]=S[name] end
    return values
end
function Library.settings.write(key,value)
    S[key]=Cache.copy(value); saveSettings(); return value
end
function Library.settings.writePair(key,value)
    S.reading_pairs=S.reading_pairs or {}; S.reading_pairs[key]=value; saveSettings()
end
function Library.settings.schema() return SCHEMA end
function Library.settings.toWire(d,value) return SettingsSync.toWire(d,value) end
function Library.settings.fromWire(d,value) return SettingsSync.fromWire(d,value) end
function Library.settings.set(key,value,why) return Shared.set(key,value,why or "settings") end
function Library.settings.preset(values)
    return Shared.setMany(SettingsUI.modeKeys,values,"mode")
end
function Library.settings.mode() return Shared.mode() end
function Library.settings.refresh(why) return Shared.refresh(why) end
function Library.settings.setupNeededText() return Shared.setupNeededText() end
function Library.settings.status(key) return Shared[key] end
Library.companion={}
function Library.companion.addon() return Companion.mode=="addon" end
function Library.companion.has(cap) return Companion.has(cap) end
function Library.companion.status() return Companion.state() end
function Library.companion.disabledText() return Companion.disabledText() end
function Library.companion.workerProblem(why) return Companion.workerProblem(why) end
function Library.companion.installed() return Companion.installed() end
function Library.companion.openStatus() return CompanionActivities.openStatus() end
function Library.companion.openHelpers()
    return Jni.startActivity{action=Companion.ACTION.SHOW_STATUS,package=Companion.PACKAGE, -- gate: user action (helper settings)
        flags=0x20000000,extras={booksync_page="helpers"}}
end
function Library.companion.openHome() return CompanionActivities.openHome() end
function Library.companion.openApps() return CompanionActivities.openApps() end
function Library.companion.openPin()
    return Jni.startActivity{action=Companion.ACTION.SHOW_PIN,package=Companion.PACKAGE} -- gate: user action (menu)
end
function Library.companion.openSetup()
    local ok=Jni.startActivity{action=Companion.ACTION.SHOW_SETUP,package=Companion.PACKAGE} -- gate: user action (setup box button)
    if not ok then ok=Jni.startActivity{action=Companion.ACTION.SHOW_STATUS,package=Companion.PACKAGE} end -- gate: user action (setup box button)
    return ok
end
function Library.companion.setupLater() return Companion.send(Companion.ACTION.SETUP_LATER,{}) end
Library.launch={}
function Library.launch.intake(source)
    local cmd = Jni.takeIntentExtra(Companion.EXTRA_COMMAND)
    if not cmd or cmd == "" then return nil end
    local from = Jni.takeIntentExtra(Companion.EXTRA_FROM)
    local held = Jni.takeIntentExtra(Companion.EXTRA_ROTATION)
    if not Companion.confirmCommand(cmd) then
        log("command ignored:", cmd, "(" .. source .. "): not sent by Orbit Companion")
        return nil
    end
    log("command from companion:", cmd, "(" .. source .. ")", from and ("from " .. tostring(from)) or "",
        held and ("held " .. tostring(held)) or "")
    return cmd,from,held
end
function Library.launch.patchVersion() return patchFileVersion() end
function Library.launch.restart(reader,source,quitOnly) return reader:restartForCompanion(source,quitOnly) end
function Library.launch.reopen(reader,source) return reader:reopenAfterRestart(source) end
Library.layout={}
function Library.layout.codec()
    local json=require("dkjson")
    local null=setmetatable({}, {__jsontype="null",__tojson=function() return "null" end})
    return {encode=json.encode,decode=function(raw)
        local value,pos,err=json.decode(raw,1,null)
        assert(not err and not raw:sub(pos):find("%S"),err or "trailing JSON")
        return value
    end}
end
function Library.layout.path() return Store.dir().."/home-layout.json" end
function Library.layout.load()
    if Library.layout.loaded then return end
    Library.layout.loaded=true
    local path=Library.layout.path()
    if not Store.readFile(path,1) and not Store.readFile(path..".bak",1) then return end
    local document,notice=LayoutStore.load(path,Store,Library.layout.codec())
    -- Retain the host's existing in-memory layout when no file has been saved yet.
    if Store.readFile(Library.layout.path(),1) or Store.readFile(Library.layout.path()..".bak",1) then S.home_layout=document end
    Library.layout.notice=notice
end
function Library.layout.save(document)
    local ok,err=LayoutStore.save(Library.layout.path(),document,Store,Library.layout.codec())
    if ok then S.home_layout=document end
    return ok,err
end

Library.resources={}
function Library.resources.about()
    local credits
    for _i, path in ipairs({ SOURCE_DIR .. "/about_credits.json", SOURCE_DIR .. "/../../../shared/about/credits.json" }) do
        local f = io.open(path, "rb")
        if f then
            local text = f:read("*a")
            f:close()
            credits = SettingsSync.decodeJson(text)
            if credits then break end
        end
    end
    assert(credits, "BookSync: shared About credits missing")
    return credits
end
function Library.resources.battery()
    local s={}
    for _, path in ipairs({ SOURCE_DIR .. "/battery.json", SOURCE_DIR .. "/../../../shared/ui/battery.json" }) do
        local file = io.open(path, "rb")
        if file then s.battery_program = SettingsSync.decodeJson(file:read("*a")); file:close(); break end
    end
    assert(s.battery_program, "BookSync battery drawing program missing")
    return s.battery_program
end
Library.report={}
function Library.report.send(why,snapshot)
    Companion.send(Companion.ACTION.REPORT,{reason=why,signed_in=Library.cachedAccountState().signedIn and "1" or "0",recommended=snapshot.report or "none",conflicts=tostring(snapshot.conflicts or 0)})
end
-- Expose only these service methods, never backend state or arbitrary transport commands.
Library.sleep={}
function Library.sleep.settings(...) return Sleep.settings(...) end
function Library.sleep.available(...) return Sleep.available(...) end
function Library.sleep.on(...) return Sleep.on(...) end
function Library.sleep.set(...) return Sleep.set(...) end
function Library.sleep.changed(...) return Sleep.changed(...) end
function Library.sleep.notify(...) return Sleep.notify(...) end
function Library.sleep.woke(...) return Sleep.woke(...) end
function Library.sleep.load(...) return Sleep.load(...) end
function Library.sleep.bookId(...) return Sleep.bookId(...) end
function Library.sleep.writeCurrent(...) return Sleep.writeCurrent(...) end
function Library.sleep.kick(...) return Sleep.kick(...) end
function Library.sleep.refresh(...) return Sleep.refresh(...) end
function Library.sleep.saveScopes(...) return Sleep.saveScopes(...) end
function Library.sleep.scopes(...) return Sleep.scopes(...) end
function Library.sleep.refreshScopes(...) return Sleep.refreshScopes(...) end
function Library.sleep.tags(...) return Sleep.tags(...) end
function Library.sleep.ruleLabel(...) return Sleep.ruleLabel(...) end
function Library.sleep.fromLabel(...) return Sleep.fromLabel(...) end
function Library.sleep.preview(...) return Sleep.preview(...) end
function Library.sleep.openCompanion(...) return Sleep.openCompanion(...) end
Library.preferences={}
function Library.preferences.pass(...) return Recommendations.pass(...) end
function Library.preferences.takeLine()
    if not Recommendations.line_pending then return nil end
    Recommendations.line_pending=false
    return Recommendations.snapshot.line
end
function Library.preferences.menuLine()
    return Recommendations.reviewed and Recommendations.snapshot.seen_line or Recommendations.snapshot.line
end
function Library.preferences.subscribe(fn) Recommendations.onSnapshot=fn end
function Library.preferences.choose(snapshot,id,what)
    if what=="mine" then
        for _,item in ipairs(snapshot.items or {}) do
            if (id==item.id or id=="all") and item.state=="conflict" and item.needs_wifi then
                Library.preferences.keepWifi()
            end
        end
    end
    return Recommendations.pass("review",{[id]=what},false)
end
function Library.preferences.keepWifi() return Library.settings.write("wifi_via_companion",false) end
function Library.preferences.seen()
    Recommendations.reviewed=true; Recommendations.line_pending=false
    if S.recommended then S.recommended.unseen=0; saveSettings() end
end

function Library.isForeground()
    local resumed=Jni.isResumed and Jni.isResumed()
    if type(resumed)=="boolean" then return resumed end
    return not (Wifi and Wifi.state and Wifi.state().foreground==false)
end
function Library.checkUpdate(why) return Updater.check(why) end
function Library.updateStatus(text) return setUpdateStatus(text) end
function Library.positionEnabled() return ReadingSync.on() end
function Library.readFromHere(why) return ReadingSync.readFromHere(why) end

function Library.launch.finishPendingHome()
    if not state.pending_home then return false end
    state.pending_home=nil; return true
end
function Library.syncAndSleep(reader,stayAwake) return reader:onOrbitSyncAndSleep(stayAwake) end
function Library.wake(reader,reason) return reader:wakeFlow(reason) end
function Library.actions() return (NativeRetirement.plan or {}).actions or {} end

function Library.controller() return state.module end
function Library.launch.startRotation() return rawget(_G,"ORBIT_START_ROTATION") end

function Library.settings.wifiLabel() return WifiPlan.modeLabel(Shared.mode()) end
function Library.setupPrompt(why,where)
    if not Companion.has("setup") then return nil end
    local prompt=Shared.setup_prompt
    local show,reason=SetupPrompt.decide(prompt,where,S.setup_prompt_shown)
    if prompt then log("setup box ("..why.."):",show and ("showing in "..where) or ("not now, "..reason)) end
    if not show then return nil end
    S.setup_prompt_shown=prompt.key
    saveSettings()
    return SetupPrompt.text(prompt)
end
