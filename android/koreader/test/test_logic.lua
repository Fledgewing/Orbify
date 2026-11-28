-- @fixture orbismart/cases.json
-- Pure-Lua tests for the patch's scheduling and decision logic.
-- Run from anywhere: luajit android/koreader/test/test_logic.lua  (or lua 5.1-5.4)
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
ORBIT_ANDROID_TEST = true
local M = dofile(here .. "/../orbit.koplugin/main.lua")
local Schedule, Plan, Update, WifiPlan, HomePlan = M.Schedule, M.Plan, M.Update, M.WifiPlan, M.HomePlan

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function ok(v, what) if not v then error(what or "expected true", 2) end end
local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

test("cache values retain their literal format", function()
    local bytes = {}
    for i=0,255 do bytes[#bytes+1]=string.char(i) end
    local input = {text=table.concat(bytes), array={true,false,1,-2,1.25}, [9]="number key"}
    local encoded=M.Cache.encode(input)
    local output=M.Cache.decode(encoded)
    eq(output.text,input.text); eq(output.array[2],false); eq(output[9],"number key")
    eq(M.Cache.decode('{name="fixture", nested={count=2}}').nested.count,2)
    eq(M.Cache.decode("{(function() return 1 end)()}"),nil)
    eq(M.Cache.decode("{[1+1]=2}"),nil)
    eq(M.Cache.decode("{[{}]=1}"),nil) -- unsupported key encoding
    eq(M.Cache.decode(string.rep("{",10000).."1"..string.rep("}",10000)),nil)
    eq(M.Cache.decode('{["x"]=1} trailing'),nil)
end)

test("0.12 first run: fresh install, additive upgrade and crash retry", function()
    local fresh={}
    ok(M.HomePlan.migrate012(fresh))
    eq(fresh.home_screen,"booksync"); eq(fresh.news_012_pending,false)
    eq(M.HomePlan.migrate012(fresh),false)
    local layout,logins,caches,outbox={pages={}}, {sync="fixture"}, {}, {{id=1}}
    local old={home_screen="server",sync_mode="custom",home_layout=layout,
        logins=logins,caches=caches,outbox=outbox,settings_at={sync_mode=125}}
    ok(M.HomePlan.migrate012(old))
    eq(old.home_screen,"booksync"); eq(old.news_012_pending,true)
    eq(old.sync_mode,"custom"); eq(old.settings_at.sync_mode,125)
    eq(old.home_layout,layout); eq(old.logins,logins); eq(old.caches,caches); eq(old.outbox,outbox)
    old.news_012_pending=false
    eq(M.HomePlan.migrate012(old),false); eq(old.news_012_pending,false)
    -- A process dying before the atomic settings flush leaves the old durable state.
    local beforeFlush={sync_mode="custom"}
    ok(M.HomePlan.migrate012(beforeFlush)); eq(beforeFlush.news_012_pending,true)
end)

-- Turns `n` pages, all in chapter `key` (nil: no table of contents).
local function turn(s, n, key, t)
    for _ = 1, n do Schedule.onPage(s, key, t) end
end

test("reading schedule request from the companion: valid, newer, applied once", function()
    eq(Schedule.request({ id = "pg50", at = 2000 }, 1000), "pg50")
    eq(select(2, Schedule.request({ id = "pg50", at = 2000 }, nil)), 2000)
    eq(Schedule.request({ id = "pg50", at = 2000 }, 2000), nil, "already applied")
    eq(Schedule.request({ id = "pg50", at = 1500 }, 2000), nil, "older")
    eq(Schedule.request({ id = "bogus", at = 3000 }, 0), nil, "unknown id")
    eq(Schedule.request(nil, 0), nil)
    eq(Schedule.request({ id = "off", at = "4000" }, 0), "off")
end)

test("off never fires", function()
    local s = Schedule.new("off", 0)
    turn(s, 500, 1, 0)
    eq(Schedule.isDue(s, 1e6), false)
end)

test("unknown id falls back to off", function()
    eq(Schedule.new("bogus", 0).kind, "off")
end)

test("every option parses", function()
    for _, o in ipairs(Schedule.OPTIONS) do
        local s = Schedule.new(o.id, 0)
        eq(s.id, o.id, "id")
        eq(s.n, o.n, "n for " .. o.id)
    end
    eq(#Schedule.OPTIONS, 10, "option count")
end)

for _, n in ipairs({ 10, 15, 30, 60 }) do
    test("minutes " .. n .. ": due only after the interval and with reading", function()
        local s = Schedule.new("min" .. n, 100)
        eq(Schedule.isDue(s, 100 + n * 60), false, "idle book")
        turn(s, 1, nil, 120)
        eq(Schedule.isDue(s, 100 + n * 60 - 1), false, "just before")
        eq(Schedule.isDue(s, 100 + n * 60), true, "at interval")
        Schedule.markSynced(s, 100 + n * 60)
        eq(Schedule.isDue(s, 100 + n * 60 * 3), false, "idle after sync")
    end)
end

for _, n in ipairs({ 25, 50, 100 }) do
    test("pages " .. n, function()
        local s = Schedule.new("pg" .. n, 0)
        turn(s, n - 1, 1, 0)
        eq(Schedule.isDue(s, 0), false, "one short")
        turn(s, 1, 1, 0)
        eq(Schedule.isDue(s, 0), true, "at n")
        Schedule.markSynced(s, 0)
        eq(Schedule.isDue(s, 0), false, "reset")
        turn(s, n, 1, 0)
        eq(Schedule.isDue(s, 0), true, "again")
    end)
end

test("every chapter: forward chapter change", function()
    local s = Schedule.new("ch1", 0)
    turn(s, 5, 1, 0)
    eq(Schedule.isDue(s, 0), false, "same chapter")
    turn(s, 1, 12, 0)
    eq(Schedule.isDue(s, 0), true, "next chapter")
    Schedule.markSynced(s, 0)
    turn(s, 3, 12, 0)
    eq(Schedule.isDue(s, 0), false, "still chapter 2")
end)

test("every chapter: going back does not count", function()
    local s = Schedule.new("ch1", 0)
    turn(s, 1, 30, 0)
    turn(s, 1, 12, 0)
    eq(Schedule.isDue(s, 0), false, "backwards")
    turn(s, 1, 30, 0)
    eq(Schedule.isDue(s, 0), true, "forward again")
end)

test("every 2 chapters", function()
    local s = Schedule.new("ch2", 0)
    turn(s, 1, 1, 0)
    turn(s, 1, 10, 0)
    eq(Schedule.isDue(s, 0), false, "one chapter")
    turn(s, 1, 20, 0)
    eq(Schedule.isDue(s, 0), true, "two chapters")
end)

test("first page seen does not count as a chapter change", function()
    local s = Schedule.new("ch1", 0)
    turn(s, 1, 40, 0)
    eq(Schedule.isDue(s, 0), false)
end)

test("chapters: book without a toc never fires", function()
    local s = Schedule.new("ch1", 0)
    turn(s, 300, nil, 0)
    eq(Schedule.isDue(s, 0), false)
end)

-- Plan.outboxVerdict
local function v(o)
    o.pending = o.pending or 0; o.elapsed = o.elapsed or 0; o.cap = o.cap or 20; o.since_nudge = o.since_nudge or 0
    return Plan.outboxVerdict(o)
end
test("outbox: empty and idle is done", function() eq(v{ pending = 0, busy = false }, "done") end)
test("outbox: empty but busy waits", function() eq(v{ pending = 0, busy = true }, "wait") end)
test("outbox: pending and busy waits", function() eq(v{ pending = 1, busy = true }, "wait") end)
test("outbox: idle with a new error fails", function() eq(v{ pending = 1, busy = false, new_error = true }, "failed") end)
test("outbox: idle with no error nudges after 2 s", function()
    eq(v{ pending = 1, busy = false, since_nudge = 1 }, "wait")
    eq(v{ pending = 1, busy = false, since_nudge = 2 }, "nudge")
end)
test("outbox: cap reached times out", function() eq(v{ pending = 1, busy = true, elapsed = 20 }, "timeout") end)
test("outbox: done beats the cap", function() eq(v{ pending = 0, busy = false, elapsed = 25 }, "done") end)

-- Plan.readingAction
local P = Plan.STRATEGY
test("reading: no remote position pushes", function() eq(Plan.readingAction{ has_remote = false }, "push") end)
test("reading: same place does nothing", function() eq(Plan.readingAction{ has_remote = true, same_place = true }, "none") end)
test("reading: device ahead pushes", function()
    eq(Plan.readingAction{ has_remote = true, remote_newer = false, forward = P.PROMPT }, "push")
end)
test("reading: server ahead + Silent pulls", function()
    eq(Plan.readingAction{ has_remote = true, remote_newer = true, forward = P.SILENT }, "pull")
end)
test("reading: server ahead + Ask never prompts mid-book", function()
    eq(Plan.readingAction{ has_remote = true, remote_newer = true, forward = P.PROMPT }, "none")
end)
test("reading: server ahead + Don't sync keeps both", function()
    eq(Plan.readingAction{ has_remote = true, remote_newer = true, forward = P.DISABLE }, "none")
end)

-- Update: version comparison
local cmp = Update.compare
test("version: parses tags, rejects junk", function()
    local v = Update.parseVersion("v1.2.3-rc.1")
    eq(v[1], 1); eq(v[2], 2); eq(v[3], 3); eq(v.pre, "rc.1")
    eq(Update.parseVersion("1.2.3+build.5").pre, nil)
    eq(Update.parseVersion("1.2"), nil)
    eq(Update.parseVersion("latest"), nil)
    eq(Update.parseVersion("1.2.3-"), nil)
    eq(Update.parseVersion(nil), nil)
end)
test("version: numeric, not text, order", function()
    eq(cmp("0.10.0", "0.9.9"), 1)
    eq(cmp("1.0.0", "0.99.99"), 1)
    eq(cmp("v0.1.0", "0.1.0"), 0)
    eq(cmp("0.1.0", "0.1.1"), -1)
end)
test("version: pre-releases sort before the release", function()
    eq(cmp("0.2.0-rc.1", "0.2.0"), -1)
    eq(cmp("0.2.0", "0.2.0-rc.1"), 1)
    eq(cmp("0.2.0-rc.2", "0.2.0-rc.1"), 1)
    eq(cmp("0.2.0-rc.10", "0.2.0-rc.9"), 1)
    eq(cmp("0.2.0-beta", "0.2.0-rc"), -1)
    eq(cmp("0.2.0-rc", "0.2.0-rc.1"), -1)
    eq(cmp("0.0.0-dev", "0.1.0"), -1)
end)
test("version: unparsable compares as nil", function() eq(cmp("x", "0.1.0"), nil) end)
test("version: preview, candidate, stable and an installed rc.17", function()
    local sequence = { "0.11.3-rc.17", "0.11.4-preview.1", "0.11.4-preview.2", "0.11.4-rc.1", "0.11.4" }
    for i = 2, #sequence do
        eq(cmp(sequence[i - 1], sequence[i]), -1)
        eq(cmp(sequence[i], sequence[i - 1]), 1)
    end
    eq(cmp("0.11.4-preview.10", "0.11.4-preview.2"), 1)
    eq(cmp("v0.11.4-preview.1", "0.11.3-rc.17"), 1)
end)

test("version: the repo copy is a dev version", function() eq(cmp(M.PATCH_VERSION, "0.0.1"), -1) end)

test("version: a test build sorts before the next release", function()
    local t = "0.11.3-0.test.42"
    eq(cmp("0.11.2", t), -1)
    eq(cmp("0.11.3", t), 1)
    eq(cmp("0.11.3-rc.1", t), 1)
    eq(cmp("0.11.3-alpha", t), 1)
    eq(Update.parseVersion("xteink-v1.6.1.101+bookorbit.8"), nil)
    eq(cmp("android-v0.7.0", "v0.7.0"), 0)
end)
local JSON = dofile(here .. "/json_mini.lua")

-- WifiPlan: restore previous state, idle timer, never off while busy
local function ctx(now, t) t = t or {}; t.now = now; if t.wifi_on == nil then t.wifi_on = true end; return t end
local function act(st, c) local a, why, force = WifiPlan.decide(st, c); return a, why, force end

test("wifi: a flow that turned Wi-Fi on puts it back off, in every mode", function()
    for _, mode in ipairs({ "always_on", "off_reading", "jit" }) do
        local st = WifiPlan.new(mode, 10, 0)
        WifiPlan.acquire(st, "wake", false, 0)
        eq(act(st, ctx(5)), nil, mode .. ": held")
        WifiPlan.release(st, "wake", 10)
        eq(act(st, ctx(11)), nil, mode .. ": grace")
        local a, why = act(st, ctx(13))
        eq(a, "off", mode .. ": restored")
        ok(why:find("restore", 1, true), "reason names the restore")
    end
end)

test("wifi: a flow that found Wi-Fi on leaves it on (always on, not in a book)", function()
    local st = WifiPlan.new("always_on", 2, 0)
    WifiPlan.acquire(st, "wake", true, 0)
    WifiPlan.release(st, "wake", 1)
    eq(act(st, ctx(1000)), nil)
end)

test("wifi: overlapping flows restore once, after the last", function()
    local st = WifiPlan.new("always_on", 2, 0)
    WifiPlan.acquire(st, "wake", false, 0)
    WifiPlan.acquire(st, "reading", true, 1) -- on by now, but the first lease decided
    WifiPlan.release(st, "wake", 2)
    eq(act(st, ctx(10)), nil, "reading still holds it")
    WifiPlan.release(st, "reading", 12)
    eq(act(st, ctx(16)), "off")
end)

test("wifi: never off while busy, a flow holds it, or another app is in front", function()
    local st = WifiPlan.new("jit", 1, 0)
    eq(act(st, ctx(100, { busy = true })), nil, "busy")
    st.foreground = false
    eq(act(st, ctx(100)), nil, "other app")
    eq(act(st, ctx(100, { screen_off = true })), "off", "screen off counts as ours")
    st.foreground = true
    WifiPlan.acquire(st, "test", true, 100)
    eq(act(st, ctx(1000)), nil, "lease")
end)

test("wifi: just in time turns off after the idle time, measured from the last activity", function()
    local st = WifiPlan.new("jit", 2, 0)
    eq(act(st, ctx(119)), nil, "not yet")
    WifiPlan.activity(st, 100)
    eq(act(st, ctx(219)), nil, "activity restarts the timer")
    local a, why = act(st, ctx(220))
    eq(a, "off"); ok(why:find("idle 2 min", 1, true), why)
    eq(act(st, ctx(220, { wifi_on = false })), nil, "already off")
end)

test("wifi: always on and off while reading have no idle timer", function()
    eq(act(WifiPlan.new("always_on", 1, 0), ctx(1e6)), nil)
    eq(act(WifiPlan.new("off_reading", 1, 0), ctx(1e6)), nil)
end)

test("wifi: just in time in a book turns off when the open-time pull is done", function()
    local st = WifiPlan.new("jit", 10, 0)
    WifiPlan.bookOpened(st, true)
    WifiPlan.acquire(st, "open", true, 0)
    eq(act(st, ctx(2)), nil, "pulling")
    WifiPlan.release(st, "open", 4)
    eq(act(st, ctx(7)), "off")
end)

test("wifi: off while reading turns Wi-Fi off at open and back on at close", function()
    local st = WifiPlan.new("off_reading", 2, 0)
    WifiPlan.bookOpened(st, true)
    WifiPlan.acquire(st, "open", true, 0)
    eq(act(st, ctx(1)), nil, "pull first")
    WifiPlan.release(st, "open", 2)
    local a, _why, force = act(st, ctx(5))
    eq(a, "off"); eq(force, true, "applies to Wi-Fi on by hand too")
    WifiPlan.wifiOff(st)
    eq(act(st, ctx(6, { wifi_on = false })), nil)
    eq(WifiPlan.bookClosed(st), "on", "restored")
    WifiPlan.bookOpened(st, false)
    eq(WifiPlan.bookClosed(st), nil, "was off: stays off")
end)

test("wifi: sleep sync hands the restore to the companion", function()
    local st = WifiPlan.new("always_on", 2, 0)
    WifiPlan.acquire(st, "sleep", false, 0)
    WifiPlan.release(st, "sleep", 5, true)
    eq(act(st, ctx(100)), nil)
end)

test("wifi: unknown mode falls back to just in time", function()
    eq(WifiPlan.new("bogus", 2, 0).mode, "jit")
    eq(WifiPlan.validMode("off_reading"), true)
end)

-- HomePlan: the Smart Home decision table
local H = HomePlan.decide
test("home: in a book, pressed in KOReader -> BookOrbit home", function()
    eq(H{ mode = "smart", in_reader = true, covered = false, from_other = false }, "dashboard")
end)
test("home: pressed on BookOrbit home -> the companion, in both modes", function()
    eq(H{ mode = "smart", on_dashboard = true, from_other = false }, "companion")
    eq(H{ mode = "bookorbit", on_dashboard = true, from_other = false }, "companion")
    eq(H{ mode = "smart", in_reader = true, covered = true, on_dashboard = true, from_other = false }, "companion",
        "dashboard over an open book")
end)
test("home: elsewhere with a book open -> the book", function()
    eq(H{ mode = "smart", in_reader = true, covered = false, from_other = true }, "book", "another app in front")
    eq(H{ mode = "smart", in_reader = true, covered = true, from_other = false }, "book", "KOReader's menu")
    eq(H{ mode = "smart", in_reader = true, covered = true, on_dashboard = true, from_other = true }, "book",
        "from the companion with BookOrbit home over the book: no loop")
end)
test("home: elsewhere with no book open -> BookOrbit home (history is not reopened)", function()
    eq(H{ mode = "smart", in_reader = false, from_other = false }, "dashboard", "file browser")
    eq(H{ mode = "smart", in_reader = false, from_other = true }, "dashboard", "another app")
    eq(H{ mode = "smart", in_reader = false, covered = true, from_other = false }, "dashboard", "other BookOrbit view")
    eq(H{ mode = "smart", on_dashboard = true, from_other = true }, "dashboard", "from the companion, no book")
end)
test("home: any BookOrbit screen but its main page -> the main page, in both modes", function()
    eq(H{ mode = "smart", in_reader = true, covered = true, library_sub = true, from_other = false }, "library_main")
    eq(H{ mode = "smart", in_reader = false, covered = true, library_sub = true, from_other = true }, "library_main")
    eq(H{ mode = "bookorbit", library_sub = true }, "library_main")
end)
test("home: a BookOrbit page past the first -> page 1 first (M8C 11-22)", function()
    eq(H{ mode = "smart", on_dashboard = true, page_above_1 = true, from_other = false }, "first_page", "dashboard page 2")
    eq(H{ mode = "bookorbit", on_dashboard = true, page_above_1 = true, from_other = false }, "first_page")
    eq(H{ mode = "smart", library_sub = true, page_above_1 = true, from_other = false }, "first_page", "a list's page 3")
    eq(H{ mode = "smart", on_dashboard = true, page_above_1 = false, from_other = false }, "companion", "page 1 leaves")
    eq(H{ mode = "smart", on_dashboard = true, page_above_1 = true, from_other = true }, "dashboard",
        "from another app: the usual rule")
end)

test("home: cold start after KOReader was killed with a book open -> that book", function()
    eq(H{ mode = "smart", in_reader = false, from_other = true, reopen = true }, "book")
end)
test("home: BookOrbit home mode -> BookOrbit home, except from the dashboard", function()
    eq(H{ mode = "bookorbit", in_reader = true, from_other = true }, "dashboard")
    eq(H{ mode = "bookorbit", in_reader = false, reopen = true }, "dashboard")
    eq(H{ mode = "bookorbit", on_dashboard = true, from_other = true }, "dashboard")
end)
test("wifi_on setting -> radio state", function()
    eq(Plan.wifiOnSetting(1), true); eq(Plan.wifiOnSetting(2), true)
    eq(Plan.wifiOnSetting(0), false); eq(Plan.wifiOnSetting(3), false)
    eq(Plan.wifiOnSetting(-1), nil)
end)
test("home: where Home came from", function()
    eq(HomePlan.cameFromOtherApp("other_app", 0.1), true)
    eq(HomePlan.cameFromOtherApp(nil, 0.8), false, "quick pause: pressed in KOReader")
    eq(HomePlan.cameFromOtherApp(nil, 40), true, "long pause: another app")
    eq(HomePlan.cameFromOtherApp(nil, nil), true, "fresh start")
    eq(HomePlan.cameFromOtherApp("koreader", 40), false)
end)

test("home: BookOrbit Home keeps the rotation the device is held in", function()
    local R = HomePlan.rotation
    -- The reported case: held upside down (left-handed) in another app; KOReader's file browser
    -- had forced upright; Home opens BookOrbit Home -> turn back to the held rotation.
    eq(R{ action = "dashboard", held = "reverse_portrait", current = 0 }, 2)
    eq(R{ action = "library_main", held = "landscape", current = 0 }, 1)
    eq(R{ action = "first_page", held = "reverse_landscape", current = 2 }, 3)
    eq(R{ action = "dashboard", held = "portrait", current = 2 }, 0, "held upright, KOReader upside down")
    eq(R{ action = "dashboard", held = "reverse_portrait", current = 2 }, nil, "already right")
    eq(R{ action = "book", held = "reverse_portrait", current = 0 }, nil, "a book applies its own rotation")
    eq(R{ action = "dashboard", held = "reverse_portrait", current = 0, in_reader = true }, nil,
        "over an open book: the book's rotation, never saved into it")
    eq(R{ action = "companion", held = "reverse_portrait", current = 0 }, nil, "the companion follows the system")
    eq(R{ action = "dashboard", held = "reverse_portrait", current = 0, locked = true }, nil, "Lock auto rotation")
    eq(R{ action = "dashboard", held = nil, current = 0 }, nil, "older companion: no extra")
    eq(R{ action = "dashboard", held = "sideways", current = 0 }, nil, "unknown value")
end)

-- The early user patch (patches/1-orbit-start-rotation.lua) with KOReader's start stubbed:
-- reader.lua runs it (:26-27), opens the settings (:39), inits the Device (:157), runs the late
-- patches (:190), then shows the file browser (:291).
local function startWithPatch(o)
    local names = { "android", "luasettings", "userpatch", "apps/filemanager/filemanager" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = package.loaded[n] end
    local r = { fm_turns = 0, applied = {} }
    package.loaded.android = { orientation = { get = function() return o.display end },
        hasNativeRotation = function() return o.native ~= false end }
    local LuaSettings = {}
    function LuaSettings:open(path)
        local data = { lock_rotation = o.locked, closed_rotation_mode = o.closed }
        return { path = path, data = data,
            isTrue = function(_, k) return data[k] == true end,
            saveSetting = function(_, k, v) data[k] = v end }
    end
    local userpatch = { early = "1", late = "2" }
    function userpatch.applyPatches(p) table.insert(r.applied, p) end
    local FM = {}
    function FM.setRotationMode() r.fm_turns = r.fm_turns + 1 end
    package.loaded.luasettings, package.loaded.userpatch = LuaSettings, userpatch
    package.loaded["apps/filemanager/filemanager"] = FM
    ORBIT_START_ROTATION = nil
    local okp, err = pcall(dofile, here .. "/../orbit.koplugin/patches/1-orbit-start-rotation.lua")
    if okp then
        r.settings = LuaSettings:open("/sdcard/koreader/settings.reader.lua")
        r.other = LuaSettings:open("/sdcard/koreader/settings/x.lua")
        userpatch.applyPatches(userpatch.late)
        FM:setRotationMode() -- the first showFiles
        FM:setRotationMode() -- a later file browser
    end
    r.start_rotation = ORBIT_START_ROTATION
    ORBIT_START_ROTATION = nil
    for _, n in ipairs(names) do package.loaded[n] = saved[n] end
    if not okp then error(err) end
    return r
end

test("start patch: KOReader starts in the held rotation, no turn", function()
    -- Held upside down; KOReader closed upright last time; the file browser's default is upright.
    local r = startWithPatch{ display = 2, closed = 0 }
    eq(r.settings.data.closed_rotation_mode, 2, "Device init keeps the held rotation")
    eq(r.other.data.closed_rotation_mode, 0, "only settings.reader.lua")
    eq(r.fm_turns, 1, "the first file browser skips its rotation; later ones are KOReader's again")
    eq(r.applied[1], "2", "the late patches still run")
    eq(r.start_rotation, 2, "the plugin is told")
end)

test("start patch: Lock auto rotation, or no native rotation: KOReader as it is", function()
    local r = startWithPatch{ display = 2, closed = 0, locked = true }
    eq(r.settings.data.closed_rotation_mode, 0)
    eq(r.fm_turns, 2)
    eq(r.start_rotation, nil)
    r = startWithPatch{ display = 2, closed = 0, native = false }
    eq(r.settings.data.closed_rotation_mode, 0, "the patch did nothing")
    eq(r.fm_turns, 2)
    eq(r.start_rotation, nil)
    r = startWithPatch{ display = 7, closed = 0 }
    eq(r.start_rotation, nil, "an unknown rotation")
end)

test("disabled text names the disabler at run time, or stays neutral", function()
    eq(M.disabledText("BookSync Companion", "Meebook Launcher", "Freeze management"),
        "BookSync Companion is disabled by Meebook Launcher: re-enable it in Meebook Launcher › Freeze management.")
    eq(M.disabledText("BookSync Companion", nil, nil), "BookSync Companion is disabled by the system: re-enable it in Settings › Apps.")
end)





local Stats = M.Stats

test("stats: content type from the file and the view", function()
    eq(Stats.contentOf("/b/x.epub"), "text")
    eq(Stats.contentOf("/b/X.FB2.ZIP"), "text")
    eq(Stats.contentOf("/b/manga.cbz", false), "comic")
    eq(Stats.contentOf("/b/manga.cbz", true), "webtoon", "a comic in continuous mode")
    eq(Stats.contentOf("/b/paper.pdf", true), "pdf", "a PDF in scroll mode stays pdf")
    eq(Stats.contentOf("/b/a.djvu"), "pdf")
    eq(Stats.contentOf("/b/odd.xyz", false, true), "pdf", "unknown, paged engine")
    eq(Stats.contentOf("/b/odd.xyz", false, false), "text", "unknown, flowing engine")
    eq(Stats.contentOf(nil), "none")
end)

test("stats: refreshes split into full and partial", function()
    local a = Stats.new(0)
    for _, m in ipairs({ "full", "flashui", "flashpartial", "partial", "ui", "fast", "a2", "[ui]", "[partial]" }) do
        Stats.refresh(a, m)
    end
    eq(a.full, 3, "full")
    eq(a.partial, 6, "partial")
end)

test("stats: batches every 5 minutes with a book open, never per page", function()
    local a = Stats.new(0)
    for _ = 1, 40 do Stats.page(a); Stats.refresh(a, "partial") end
    eq(Stats.isDue(a, 299, true), false, "not before 5 min")
    eq(Stats.isDue(a, 300, true), true, "due at 5 min")
    local b = Stats.take(a, 300, "text", true, { wifi_mode = "jit" })
    eq(b.pages, "40"); eq(b.partial, "40"); eq(b.full, "0")
    eq(b.period_s, "300"); eq(b.reading_min, "5.0"); eq(b.content, "text"); eq(b.open, "1")
    eq(b.seq, "1"); eq(b.wifi_mode, "jit")
    eq(a.pages, 0, "reset after a batch")
    eq(Stats.isDue(a, 500, true), false)
    eq(Stats.take(a, 600, "text", true).seq, "2", "sequence counts up")
end)

test("stats: nothing to send without a book and counts, or while paused", function()
    local a = Stats.new(0)
    eq(Stats.isDue(a, 1000, false), false, "file browser, nothing counted")
    eq(Stats.take(a, 1000, "none", false), nil)
    Stats.refresh(a, "ui")
    eq(Stats.isDue(a, 1400, false), true, "file browser refreshes still go out")
    eq(Stats.take(a, 1400, "none", false).reading_min, "0.0")
    a.at = nil
    Stats.page(a)
    eq(Stats.isDue(a, 9999, true), false, "paused by a suspend")
    eq(Stats.take(a, 9999, "text", false), nil)
end)

local Clicks = M.Clicks

test("clicks: the key map keeps known actions only, keyed by keycode", function()
    local m = Clicks.parse({ ["87"] = { press = "next", hold = "nuke" }, ["66"] = { press = "nothing" }, x = { press = "next" } })
    eq(m[87].press, "next")
    eq(m[87].hold, nil, "unknown action dropped")
    eq(m[66], nil, "nothing: not ours")
    eq(next(Clicks.parse(nil)), nil)
end)

test("clicks: plain press fires on key down, no delay", function()
    local st, a = {}, { press = "next" }
    eq(Clicks.down(st, 0, a), "press")
    eq(Clicks.down(st, 0.05, a), nil, "repeat while down")
    eq(Clicks.up(st, 0.1, a), nil)
    eq(Clicks.nextDue(st, a), nil)
end)

test("clicks: hold at 0.6 s while down, else a press on release", function()
    local st, a = {}, { press = "next", hold = "sync_sleep" }
    eq(Clicks.down(st, 10, a), nil)
    eq(Clicks.nextDue(st, a), 10.6)
    eq(Clicks.tick(st, 10.59, a), nil)
    eq(Clicks.tick(st, 10.6, a), "hold")
    eq(Clicks.up(st, 11, a), nil)
    eq(Clicks.down(st, 20, a), nil)
    eq(Clicks.up(st, 20.2, a), "press")
end)

test("clicks: double within 0.35 s, else the single after the window", function()
    local st, a = {}, { press = "light", double = "home" }
    Clicks.down(st, 0, a); eq(Clicks.up(st, 0.1, a), nil)
    eq(Clicks.down(st, 0.3, a), "double")
    eq(Clicks.up(st, 0.35, a), nil)
    eq(Clicks.tick(st, 5, a), nil)
    Clicks.down(st, 10, a); Clicks.up(st, 10.1, a)
    eq(Clicks.tick(st, 10.44, a), nil)
    eq(Clicks.tick(st, 10.45, a), "press")
end)

test("clicker: one path; the patch's own keys only when the service can't", function()
    eq(Clicks.ownPath(false, false), true)
    eq(Clicks.ownPath(true, false), true, "service off")
    eq(Clicks.ownPath(false, true), true, "no channel")
    eq(Clicks.ownPath(true, true), false, "service handles them: never two page turns")
    local k, v = Clicks.parseLine("CLICK next 3")
    eq(k, "click"); eq(v, "next")
    k, v = Clicks.parseLine("CLICK nuke 4")
    eq(k, "click"); eq(v, nil)
    k, v = Clicks.parseLine("SERVICE off")
    eq(k, "service"); eq(v, false)
    eq(Clicks.parseLine("HTTP/1.1 200 OK"), nil)
end)

-- SetupPrompt: the one-time setup box, never in a book
local SetupPrompt = M.SetupPrompt
test("setup box: only off a book, once per key, never when snoozed", function()
    local pr = { key = "clicker", rows = { "Clicker buttons (accessibility)" } }
    eq(SetupPrompt.decide(pr, "reader", nil), false, "never in a book")
    eq(SetupPrompt.decide(pr, "browser", nil), true)
    eq(SetupPrompt.decide(pr, "bookorbit", nil), true)
    eq(SetupPrompt.decide(pr, "menu", nil), true)
    eq(SetupPrompt.decide(pr, "browser", "clicker"), false, "already shown")
    eq(SetupPrompt.decide({ key = "clicker,keyboard" }, "browser", "clicker"), true, "a new row shows again")
    eq(SetupPrompt.decide(nil, "browser", nil), false, "snoozed or nothing: the companion sends none")
    eq(SetupPrompt.decide({ key = "" }, "browser", nil), false)
    eq(SetupPrompt.text(pr), "BookSync Companion needs 1 setup step: Clicker buttons (accessibility).")
    ok(SetupPrompt.text({ key = "a,b", rows = { "A", "B" } }):find("2 setup steps:\n• A\n• B", 1, true))
end)

test("menu lock: only on the companion's pin_locked = true; no answer stays usable", function()
    local L = M.MenuLock
    eq(L.locked({ pin_locked = true }), true, "locked")
    eq(L.locked({ pin_locked = false }), false, "unlocked")
    eq(L.locked({}), false, "older companion without the field")
    eq(L.locked(nil), false, "companion unreachable")
    eq(L.locked({ pin_locked = "true" }), false, "only a real boolean locks")
end)

test("restart plan: a newer file loads now, or after the book; one try per version", function()
    local R = M.RestartPlan
    eq(R.fileVersion('\n-- x\nlocal PATCH_VERSION = "0.5.0"\n'), "0.5.0")
    eq(R.fileVersion("-- no version"), nil)
    eq(R.decide(nil, "0.4.9", nil, false, "check"), "none", "no file")
    eq(R.decide("0.4.9", "0.4.9", nil, false, "check"), "none", "already running it")
    eq(R.decide("0.4.8", "0.4.9", nil, false, "check"), "none", "older file never restarts")
    eq(R.decide("0.5.0", "0.4.9", nil, false, "check"), "wait", "automatic, in front (no book, Home, a list): waits")
    eq(R.decide("0.5.0", "0.4.9", nil, true, "check"), "wait", "a book open: never interrupts reading")
    eq(R.decide("0.5.0", "0.4.9", nil, false, "close"), "wait", "a book closed: still in KOReader, waits")
    eq(R.decide("0.5.0", "0.4.9", nil, true, "background"), "quit", "another app in front: save and quit")
    eq(R.decide("0.5.0", "0.4.9", nil, true, "sleep"), "restart", "the device sleeping")
    eq(R.decide("0.5.0", "0.4.9", "0.5.0", false, "check"), "gave_up", "restarted for it and still old")
    eq(R.decide("0.5.1", "0.4.9", "0.5.0", false, "sleep"), "restart", "a newer file gets its own try")
    eq(R.decide("0.5.0", "0.5.0", "0.5.0", false, "check"), "done", "loaded after its restart")
    eq(R.decide("0.0.0-dev", "0.0.0-dev", nil, false, "check"), "none", "dev build")
    eq(R.decide("0.5.0", "0.4.9", nil, true, "manual"), "restart", "an update the reader asked for: at once, book or not")
    eq(R.decide("0.5.0", "0.4.9", nil, true, "check_asleep"), "wait", "screen off, nobody to relaunch: waits")
    eq(R.doneText("0.5.0"), "Updated to v0.5.0")
end)



---------------------------------------------------------------- end-of-book sheet layout
local SL = M.SheetLayout
-- KOReader's Screen:scaleBySize (koreader-base ffi/framebuffer.lua fb:scaleBySize, no DPI override).
local function scaler(w, h) return function(px) return math.ceil(px * (math.min(w, h) / 600)) end end
local function sheetRows(kind)
    local r = { { kind = "status", text = "✓ Marked as finished", label = "Undo" }, { kind = "title", text = "The Lighthouse Keepers" },
        { kind = "author", text = "by Mara Quill ›" }, { kind = "series", text = "Harbour Lights · Book 2 of 4" } }
    for n = 1, 5 do table.insert(r, { kind = "star", n = n }) end
    table.insert(r, { kind = "hint", text = "Tap a star · tap it again to clear" })
    table.insert(r, { kind = "review", text = "Review ›" })
    table.insert(r, { kind = "label", text = "Next in series · Book 3" })
    if kind == "failed" then
        table.insert(r, { kind = "notice", text = "Couldn't connect" })
        table.insert(r, { kind = "button", text = "Try again" })
        table.insert(r, { kind = "button", text = "Get it at the next sync" })
    else
        table.insert(r, { kind = "card", text = "The Storm Signal", sub = "Book 3 · on this reader" })
    end
    table.insert(r, { kind = "label", text = "Also by Mara Quill" })
    table.insert(r, { kind = "card", text = "Fog Days", sub = "on BookOrbit" })
    table.insert(r, { kind = "footer", text = "‹ Back to book" }); table.insert(r, { kind = "footer", text = "Home" })
    return r
end

test("end-of-book sheet: rows never overlap, widths are symmetric, rows fit their text (1404x1872 and others)", function()
    for _, screen in ipairs({ { 1404, 1872 }, { 1072, 1448 }, { 758, 1024 } }) do
        local w, h = screen[1], screen[2]
        local scale = scaler(w, h)
        local m = SL.metrics(w, scale)
        for _, variant in ipairs({ "ok", "failed" }) do
            local blocks = SL.blocks(sheetRows(variant))
            local plan = SL.plan(blocks, m)
            local where = w .. "x" .. h .. " " .. variant
            eq(plan.items[1].kind, "status", where)
            local stars, footer
            for i, it in ipairs(plan.items) do
                eq(it.x, m.pad, where .. " left pad " .. it.kind)
                eq(w - (it.x + it.w), m.pad, where .. " right pad " .. it.kind)
                if i > 1 then
                    local prev = plan.items[i - 1]
                    ok(it.y >= prev.y + prev.h + m.gap_small, where .. ": " .. it.kind .. " overlaps " .. prev.kind)
                end
                if it.kind == "stars" then stars = it end
                if it.kind == "footer" then footer = it end
            end
            ok(plan.h <= h * 0.9, where .. " fits: " .. plan.h)
            -- Each row is at least as tall as its text in KOReader's scaled font.
            local function line(size) return math.ceil(scale(size) * SL.LINE) end
            local F = SL.FONTS
            for _, it in ipairs(plan.items) do
                local need = ({ status = line(F.status), title = line(F.title), author = line(F.author), series = line(F.series),
                    label = line(F.label), hint = line(F.hint), stars = line(F.star), notice = line(F.notice),
                    card = line(F.card_title) + line(F.card_sub) })[it.kind]
                if need then ok(it.h >= need, where .. ": " .. it.kind .. " " .. it.h .. " < " .. need) end
            end
            -- Stars: five equal targets centred as a group; footer: equal halves.
            local cells = SL.centred(stars.w, 5, m.star * 2)
            eq(cells[1].x, stars.w - (cells[5].x + cells[5].w) + ((stars.w - cells[1].w * 5) % 2), where .. " stars centred")
            for _, c in ipairs(cells) do eq(c.w, cells[1].w); ok(c.w >= m.star, "star target") end
            ok(#footer.block.items == 2, "two footer buttons")
            local halves = SL.split(footer.w, 2)
            eq(halves[1].w, halves[2].w, "equal footer buttons")
            -- A widget that came out taller grows its row and pushes the rest down.
            m.measured = { [plan.items[2].block] = plan.items[2].h + 30 }
            local grown = SL.plan(blocks, m)
            eq(grown.items[3].y, plan.items[3].y + 30, where .. " a taller row pushes the next")
            m.measured = nil
        end
    end
end)

---------------------------------------------------------------- companion caps (addon-mode §6)
local Caps = M.Caps
test("caps: from the file only, the status only, both (the status wins), none", function()
    local file = { mode = "addon", caps = { "install", "setup", "stats", "relaunch" } }
    local status = { mode = "full", caps = { "install", "home", "wifi" } }
    local c, mode, src = Caps.resolve("ok", file, nil, nil)
    ok(c.install and not c.wifi and mode == "addon" and src == "file", "file")
    c, mode, src = Caps.resolve("ok", nil, status, nil)
    ok(c.home and c.wifi and mode == "full" and src == "status", "status")
    c, mode, src = Caps.resolve("ok", file, status, nil)
    ok(c.wifi and src == "status", "/status wins")
    c, mode, src = Caps.resolve("ok", nil, { version = "0.10.0" }, nil)
    ok(next(c) == nil and src == "none", "a status without caps offers nothing")
    c, mode, src = Caps.resolve("missing", file, nil, nil)
    ok(next(c) == nil and src == "none", "a leftover file is ignored")
    c, mode, src = Caps.resolve("frozen", file, status, nil)
    ok(next(c) == nil, "frozen: nothing")
    c, mode, src = Caps.resolve("ok", nil, nil, { mode = "addon", caps = { "install" } })
    ok(c.install and not c.wifi and src == "cache", "the caps seen last time")
    c, mode, src = Caps.resolve("ok", nil, nil, nil)
    ok(next(c) == nil and src == "none", "nothing known yet: nothing offered")
end)

test("caps: diff names what was lost and gained", function()
    local lost, gained = Caps.diff({ wifi = true, home = true, install = true }, { install = true, pin = true })
    eq(table.concat(lost, ","), "home,wifi"); eq(table.concat(gained, ","), "pin")
end)

test("copies: the replacement file, the decision, the sidecar folder, the queue (the lookup is CopiesLogic's)", function()
    local P = M.CopiesPlan
    local c = { { path = "/b/a.epub" }, { path = "/b/b.epub" } }
    local files = { { id = 9, role = "alternate" }, { id = 10, fileHash = "x" }, { id = 11, role = "primary" } }
    eq(P.pick(files, 10).id, 10, "the same library file")
    eq(P.pick(files, 99).id, 11, "else the primary")
    eq(P.decide("x", { fileHash = "x" }), "same")
    eq(P.decide("y", { fileHash = "x" }), "replace")
    eq(P.decide("y", { }), "unknown", "never replaced blind")
    eq(P.hashSidecar("/s/hashdocsettings", "b3fb8f4f"), "/s/hashdocsettings/b3/b3fb8f4f.sdr")
    local q = { { path = "/b/a.epub" } }
    eq(P.enqueue(q, c), 1, "a once")
    eq(#q, 2)
end)

---------------------------------------------------------------- sleep screen pool (lock-screen.md)
local SP = M.SleepPool
local function seq(list) local i = 0 return function(n) i = i % #list + 1; return math.min(n, list[i]) end end

test("sleep screen settings: off by default, bad values fall back, text cut at 60", function()
    local n = SP.normalize({})
    eq(n.sleep_mode, "off"); eq(n.sleep_from, "up_next"); eq(n.sleep_hours, 6); eq(n.sleep_style, "bar")
    eq(n.sleep_text_position, "right"); eq(n.sleep_battery_corner, "bottom_left"); eq(n.sleep_battery, false)
    n = SP.normalize({ sleep_mode = "bogus", sleep_hours = 5, sleep_from = "scope:x", sleep_style = "halo",
        sleep_text_position = "middle", sleep_battery_corner = "centre", sleep_battery = "1" })
    eq(n.sleep_mode, "off"); eq(n.sleep_hours, 6); eq(n.sleep_from, "up_next"); eq(n.sleep_style, "bar")
    eq(n.sleep_text_position, "right"); eq(n.sleep_battery_corner, "bottom_left"); eq(n.sleep_battery, true)
    eq(SP.normalize({ sleep_hours = "12" }).sleep_hours, 12)
    eq(SP.normalize({ sleep_from = "collection:4" }).sleep_from, "collection:4")
    local long = string.rep("é", 70)
    eq(#SP.cleanText(long), 120, "60 two-byte characters")
    eq(SP.cleanText("  Bedtime\n8 pm  "), "Bedtime 8 pm")
end)

test("sleep screen: the SETTINGS extras are strings, rules one per line", function()
    local x = SP.extras({ sleep_mode = "recommended", sleep_leave_out = { "tag:Age:18", "scope:3", "bogus", "scope:3" },
        sleep_battery = true, sleep_hours = 3 })
    eq(x.sleep_mode, "recommended"); eq(x.sleep_hours, "3"); eq(x.sleep_battery, "1")
    eq(x.sleep_leave_out, "tag:age:18\nscope:3")
    local back = SP.decodeRules(x.sleep_leave_out)
    eq(#back, 2); eq(back[1], "tag:age:18"); eq(back[2], "scope:3")
    eq(SP.parseRule("tag:   "), nil); eq(SP.parseRule("scope:0"), nil); eq(SP.parseRule("field:3"), nil)
    eq(SP.parseFrom("discover").type, "random"); eq(SP.parseFrom("up_next").type, "up-next-in-series")
end)

test("sleep screen: Pick from and Leave out as sets, Library (shared/fixtures/sleep/cases.json sources)", function()
    -- @fixture sleep/cases.json#sources
    local src = JSON.fixture(here, "sleep/cases.json").sources
    ok(#src.from >= 5 and #src.leave_out >= 3, "the shared cases")
    for _, c in ipairs(src.from) do eq(SP.normalizeFrom(c.wire), c.expect, c.name) end
    for _, c in ipairs(src.leave_out) do eq(SP.encodeRules(SP.decodeRules(c.wire)), c.expect, c.name) end
    eq(SP.normalize({ sleep_from = "discover\nscope:3" }).sleep_from, "discover\nscope:3")
    eq(SP.extras({ sleep_from = "library\nup_next" }).sleep_from, "library")
end)

test("sleep screen: text and battery never share a corner (L3b2)", function()
    eq(SP.batteryCorner("bottom_left", "bottom"), "top_left")
    eq(SP.batteryCorner("top_right", "top"), "bottom_right")
    eq(SP.batteryCorner("bottom_right", "right"), "bottom_left")
    eq(SP.batteryCorner("top_left", "left"), "top_right")
    eq(SP.batteryCorner("bottom_left", "right"), "bottom_left", "default: apart already")
    eq(SP.batteryCorner("top_left", "bottom"), "top_left")
end)

-- Which books count (R2), Leave out (X1-X7), the shuffle bag (R1b) and Every sleep's batch (R4b):
-- Orbit Companion's (SleepPoolTest.kt).
test("sleep screen: the pickers' section entries", function()
    local e = SP.entries({ items = { { id = "12", title = "Romance", count = 40 }, { id = "x", title = "bad" } } })
    eq(#e, 1); eq(e[1].id, 12); eq(e[1].count, 40)
end)

test("sleep screen: the JSON the companion reads (scopes.json, current.json) is valid", function()
    local doc = { v = 1, at = 1700000000000, items = { { id = 5, title = 'Quote " and \\ slash', file = "covers/5.jpg" } } }
    local back = JSON.decode(SP.json(doc))
    eq(back.v, 1); eq(back.at, 1700000000000)
    eq(back.items[1].id, 5); eq(back.items[1].title, 'Quote " and \\ slash'); eq(back.items[1].file, "covers/5.jpg")
    eq(SP.json({ items = {} }), '{"items":[]}')
end)

-- Nothing interrupts reading (docs/design/reading-gate.md): every place in the plugin that shows
-- something, takes focus or restarts says how the reading gate covers it ("-- gate: <why>" on its
-- line or the line before). A new path without it fails here.
test("reading gate: every show, toast, activity start and restart names its gate", function()
    local dir = here .. "/../orbit.koplugin/ko/"
    local pat = { "UIManager:show%(", "bookorbit_toast\"%)%.show", "bookorbit_toast\"%)%.error", "Toast%.show%(",
        "Toast%.error%(", "Jni%.startActivity{", "restartKOReader%(%)", "UIManager:quit%(%)" }
    local missing = {}
    local p = io.popen('find "' .. dir .. '" -type f -name "*.lua"')
    for path in p:lines() do
        local name = path:sub(#dir + 1)
        if name:match("%.lua$") and name ~= "jni.lua" then
            local prev = ""
            local n = 0
            for line in io.lines(path) do
                n = n + 1
                local code = line:gsub("%-%-.*$", function(c) return c:find("gate:", 1, true) and c or "" end)
                for _, q in ipairs(pat) do
                    if code:find(q) and not code:match("^%s*%-%-") and not line:find("-- gate:", 1, true)
                        and not prev:find("-- gate:", 1, true) then
                        table.insert(missing, name .. ":" .. n)
                    end
                end
                prev = line
            end
        end
    end
    p:close()
    eq(table.concat(missing, " "), "", "ungated show paths")
end)

test("sleep screen, Every sleep: a setting value", function()
    eq(SP.normalize({ sleep_hours = 0 }).sleep_hours, 0, "Every sleep is a value")
    eq(SP.normalize({ sleep_hours = "0" }).sleep_hours, 0)
    eq(SP.extras({ sleep_hours = 0 }).sleep_hours, "0")
    eq(SP.hoursLabel(0), "Every sleep"); eq(SP.hoursLabel(12), "12 h")
end)


-- Shared settings (docs/design/companion-settings.md §4): one schema, per-key newest-wins merge.
local SettingsSync = M.SettingsSync
local function readFile(path) local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return t end
local schemaText = readFile(here .. "/../../../shared/settings/schema.json")
local SIDX = SettingsSync.index(SettingsSync.decodeJson(schemaText), {["server-home"] = M.HomePlan.SERVER_HOME})

test("settings schema: neutral choices bind opaque adapter keys without changing source data", function()
    local raw = SettingsSync.decodeJson(schemaText)
    local bound = SettingsSync.index(raw, {["server-home"] = "alternate:home"})
    eq(bound.byKey.home_button.values[2].id, "alternate:home")
    eq(SettingsSync.fromWire(SIDX.byKey.home_button, M.HomePlan.SERVER_HOME), M.HomePlan.SERVER_HOME)
    eq(SettingsSync.index(raw).byKey.home_button.values[2].id, "server-home")
end)

test("settings schema: the plugin's own JSON reader loads it", function()
    ok(#SIDX.settings >= 30, "settings: " .. #SIDX.settings)
    eq(#SIDX.sections, 8, "sections")
    for _, d in ipairs(SIDX.settings) do
        ok(d.label and d.label ~= "", d.key .. " label")
        ok(d.line and d.line ~= "", d.key .. " line")
        local known = false
        for _, s in ipairs(SIDX.sections) do if s.id == d.section then known = true end end
        ok(known, d.key .. " section")
        if d.parent then ok(SIDX.byKey[d.parent.key] ~= nil, d.key .. " parent") end
        ok(SettingsSync.fromWire(d, SettingsSync.toWire(d, nil)) ~= nil, d.key .. " default round-trips")
    end
end)

test("settings schema: storage choices match the plugin, including fractional GB", function()
    local d = SIDX.byKey.storage_limit_mb
    eq(d.default, 250)
    eq(#d.values, #M.Cache.STORAGE_LIMITS_MB)
    local labels = { "100 MB", "250 MB", "500 MB", "1 GB", "2.5 GB", "5 GB", "10 GB", "No limit" }
    for i, v in ipairs(d.values) do
        eq(tonumber(v.id), M.Cache.STORAGE_LIMITS_MB[i])
        eq(v.label, labels[i])
        eq(SettingsSync.fromWire(d, v.id), tonumber(v.id))
    end
end)

test("settings schema: every plugin setting is in it, or listed as state", function()
    local STATE = { last_sleep_sync = 1, shared_settings_at = 1, settings_at = 1, patch_update_checked_at = 1,
        patch_update_status = 1, open_book_at_exit = 1, restart_screen = 1, restart_book = 1, home_book = 1,
        saved_pages_before_update = 1, sleep_current_file = 1, choices_asked_at = 1 }
    local src = readFile(here .. "/../orbit.koplugin/ko/settings.lua")
    local body = src:match("DEFAULTS = (%b{})")
    local missing, shared = {}, {}
    for key in body:gmatch("\n%s+([%a_]+)%s*=") do
        if SIDX.byKey[key] then table.insert(shared, key)
        elseif not STATE[key] then table.insert(missing, key) end
    end
    eq(table.concat(missing, " "), "", "plugin settings missing from shared/settings/schema.json")
    -- A shared setting's default is the schema's (ko/settings.lua fills DEFAULTS from it; test_flows checks the result).
    eq(table.concat(shared, " "), "", "shared settings with a default in ko/settings.lua, not the schema")
end)

-- @fixture wifi/policy.json#connect
test("Wi-Fi network-up decisions shared with X4", function()
    for _, c in ipairs(JSON.fixture(here, "wifi/policy.json").connect) do
        eq(WifiPlan.shouldConnect(c.mode, c.reason, c.saved), c.connect, c.mode .. "/" .. c.reason)
    end
end)

-- @fixture settings/merge.json
local MERGE = JSON.fixture(here, "settings/merge.json")
local MERGE_INDEX=SettingsSync.index(SettingsSync.decodeJson(schemaText),{["server-home"]="bookorbit"})
for _, c in ipairs(MERGE.cases) do
    test("settings merge: " .. c.name, function()
        local vals, at, remote = {}, {}, {}
        for k, e in pairs(c["local"]) do vals[k] = SettingsSync.fromWire(MERGE_INDEX.byKey[k], e.v); at[k] = e.at end
        for k, e in pairs(c.remote) do remote[k] = { v = e.v, at = e.at } end
        local taken = SettingsSync.merge(MERGE_INDEX, vals, at, remote, c.now, c.remote_wins_tie)
        local keys = {}
        for _, t in ipairs(taken) do table.insert(keys, t.key); vals[t.key] = t.value; at[t.key] = t.at end
        eq(table.concat(keys, ","), table.concat(c.taken, ","), "taken")
        for k, v in pairs(c.expect) do eq(SettingsSync.toWire(MERGE_INDEX.byKey[k], vals[k]), v, k) end
    end)
end

test("settings seed: legacy keys keep the old time, the rest get 1 ms", function()
    local at = { key_log = 77 }
    local n = SettingsSync.seed(SIDX, at, SettingsSync.LEGACY, 5000)
    eq(at.wifi_mode, 5000); eq(at.sync_on_sleep, 1); eq(at.key_log, 77)
    eq(n, #SIDX.settings - 1)
    local at2 = {}
    SettingsSync.seed(SIDX, at2, SettingsSync.LEGACY, 0)
    eq(at2.wifi_mode, 1, "never shared before")
end)

test("settings encode: only keys with a time, as wire strings", function()
    local out = SettingsSync.encode(SIDX, { sync_on_sleep = false, sleep_leave_out = { "tag:x", "scope:3" } },
        { sync_on_sleep = 9, sleep_leave_out = 4 })
    eq(out.sync_on_sleep.v, "0"); eq(out.sync_on_sleep.at, 9)
    eq(out.sleep_leave_out.v, "tag:x\nscope:3")
    eq(out.wifi_mode, nil)
end)

test("settings visible: rows show only while their parent has the value", function()
    local v = { sleep_mode = "off", sleep_style = "overlay", sync_on_sleep = true, wifi_mode = "jit", sync_mode = "custom" }
    eq(SettingsSync.visible(SIDX, "sleep_text", v), false)
    eq(SettingsSync.visible(SIDX, "sleep_text_position", v), false, "grandparent off")
    v.sleep_mode = "current"
    eq(SettingsSync.visible(SIDX, "sleep_text_position", v), true)
    eq(SettingsSync.visible(SIDX, "sleep_from", v), false, "Recommended only")
    eq(SettingsSync.visible(SIDX, "sleep_cap", v), true)
    v.sync_on_sleep = false
    eq(SettingsSync.visible(SIDX, "sleep_cap", v), false)
    eq(SettingsSync.visible(SIDX, "wifi_idle_min", v), true)
    -- OrbiSmart sets the sync rows and hides them (docs/design/position-sync.md §6); Custom shows them.
    v.sync_on_sleep = true
    for _, k in ipairs({ "sync_on_sleep", "sleep_cap", "sync_on_wake", "reading_schedule" }) do
        eq(SettingsSync.visible(SIDX, k, v), true, k .. " under Custom")
    end
    v.sync_mode = "orbismart"
    for _, k in ipairs({ "sync_on_sleep", "sleep_cap", "sync_on_wake", "reading_schedule" }) do
        eq(SettingsSync.visible(SIDX, k, v), false, k .. " under OrbiSmart")
    end
    eq(SettingsSync.visible(SIDX, "wake_tailscale", v), true)
    eq(SettingsSync.visible(SIDX, "wifi_mode", v), true, "Wi-Fi mode untouched")
end)

test("settings schema: Sync (OrbiSmart / Custom) is the sync section's first row", function()
    local first
    for _, d in ipairs(SIDX.settings) do if d.section == "sync" then first = d; break end end
    eq(first.key, "sync_mode")
    eq(first.default, "orbismart")
    eq(first.label, "Reading position")
    eq(first.values[1].label, "Furthest page wins")
    eq(first.line, "BookSync keeps the furthest place you've read on any device, and asks before jumping.")
end)

test("settings schema: every key KOReader reads has a row in its menu", function()
    local root=here .. "/../orbit.koplugin/"
    local menu = readFile(root .. "logic/settings_ui.lua") .. readFile(root .. "ko/menu.lua") .. readFile(root .. "ko/sleepscreen.lua")
    -- Owned pages may reuse settingRow outside the root menu. Only installed owners count.
    local modules=assert(readFile(root .. "main.lua"):match("local KO = (%b{})"))
    for path in modules:gmatch('"([^"%s]+%.lua)"') do
        for key in readFile(root .. path):gmatch(':settingRow%("([^"]+)"%)') do
            menu=menu .. '"' .. key .. '"'
        end
    end
    local missing = {}
    for _, d in ipairs(SIDX.settings) do
        -- Keys KOReader reads need a row; the companion's own (the clearing flash, its updates) may not.
        local plugin = false
        for _, r in ipairs(d.reader or {}) do if r == "plugin" then plugin = true end end
        if plugin and not d.hidden and not menu:find('"' .. d.key .. '"', 1, true) then table.insert(missing, d.key) end
    end
    eq(table.concat(missing, " "), "", "keys with no menu row")
end)


test("sleep screen: Every sleep (sleep_hours 0) is a valid choice, listed first", function()
    local SP = M.SleepPool
    eq(SP.HOURS[1], 0)
    eq(SP.normalize({ sleep_hours = 0 }).sleep_hours, 0, "kept, not the default")
    eq(SIDX.byKey.sleep_hours.values[1].label, "Every sleep")
    eq(SettingsSync.fromWire(SIDX.byKey.sleep_hours, "0"), 0)
end)

test("recommended choices from the companion", function()
    local c = SettingsSync.choices("bo.auto_sync=ours; g.apps=mine;x=bogus;all=undo")
    eq(#c, 3); eq(c[1].id, "bo.auto_sync"); eq(c[2].what, "mine"); eq(c[3].id, "all")
end)

-- OrbiSmart sync (docs/design/position-sync.md §3): every case of the shared table, which the Xteink's
-- xteink/test/orbismart_test.cpp reads too.
local OrbiSmart = M.OrbiSmart
local OSM = JSON.fixture(here, "orbismart/cases.json")
test("orbismart: every decide case", function()
    local n = 0
    for _, c in ipairs(OSM.decide) do
        local out = OrbiSmart.decide(c["in"])
        eq(out.decision, c.want.decision, c.name .. " decision")
        eq(out.rule, c.want.rule, c.name .. " rule")
        eq(out.dropped, c.want.dropped == true, c.name .. " dropped")
        ok(OrbiSmart.DECISIONS[out.decision], c.name .. ": known decision")
        if c.line then eq(OrbiSmart.line(c["in"], out, c.moment), c.line, c.name .. " line") end
        n = n + 1
    end
    ok(n >= 30, "cases: " .. n)
end)
test("orbismart: every apply case", function()
    for _, c in ipairs(OSM.apply) do
        eq(OrbiSmart.apply(c.decision, c.moment), c.applied, c.decision .. " at " .. c.moment)
    end
end)
test("orbismart: every behind-hold case", function()
    for _, c in ipairs(OSM.push) do
        eq(OrbiSmart.mayPush(c.place, c.server, c.tolerance, c.exempt), c.allowed, c.name)
    end
end)
test("orbismart: the table covers every decision and rule", function()
    local seen = {}
    for _, c in ipairs(OSM.decide) do seen[c.want.decision] = true; seen[c.want.rule] = true end
    for _, k in ipairs({ "same", "take", "follow", "push", "hold", "stay", "override", "rule1", "rule2", "rule3",
        "rule4", "rule5", "rule6", "rule7", "declined", "override", "percent", "no-server" }) do
        ok(seen[k], "no case for " .. k)
    end
    eq(OrbiSmart.SKEW_S, OSM.skew_s, "skew margin")
end)
test("orbismart: the popup's question", function()
    eq(OrbiSmart.question("Boox", 214, "take"), "Continue from Boox, p. 214?")
    eq(OrbiSmart.question("X4 Pro", 12, "follow"), "Continue from X4 Pro, p. 12 (moved back there)?")
end)

test("main loop: all directory enumeration belongs to the companion", function()
    local main=readFile(here.."/../orbit.koplugin/main.lua")
    ok(not main:find("cover_child",1,true),"no thumbnail child module")
    for module in main:gmatch('"(ko/[^"%s]+%.lua)"') do
        local source=readFile(here.."/../orbit.koplugin/"..module)
        ok(not source:find("lfs.dir",1,true),module.." must not enumerate a directory")
    end
end)

test("status layout: default off, sizes, compact strips and proportional battery", function()
    local schema = M.SettingsSync.decodeJson(readFile(here .. "/../../../shared/settings/schema.json"))
    local indexed = M.SettingsSync.index(schema)
    eq(indexed.byKey.status_orbit_layout.default, false)
    eq(indexed.byKey.status_orbit_size.default, "small")
    local L = M.StatusLayout
    eq(L.fontSize("small"), 14); eq(L.fontSize("medium"), 18); eq(L.fontSize("large"), 22)
    eq(L.fontSize("unknown"), 14)
    for _, h in ipairs({12, 16, 24, 40}) do eq(L.stripHeight(h, 1), h+2) end
    eq(indexed.byKey.status_orbit_add_space, nil)
    local program=M.SettingsSync.decodeJson(readFile(here.."/../../../shared/ui/battery.json"))
    for _, charge in ipairs({0, 1, 25, 50, 98, 100}) do
        local rectangles={}
        M.BatteryGlyph.draw(program,20,charge,function(x,y,w,h,color) rectangles[#rectangles+1]={x,y,w,h,color} end)
        eq(#rectangles,4); ok(math.abs(rectangles[4][3]-21.6*charge/100)<0.00001)
    end
    local measure=function(size) return size-2 end
    for margin=0,30 do
        local fit=L.fit(margin,22,1,measure,false)
        eq(fit.extra,0); ok(fit.height<=margin)
        local added=L.fit(margin,22,1,measure,true)
        eq(added.extra,0); eq(added.height,fit.height)
    end
end)

-- @fixture status/format.json
test("status layout: shared progress and clock formats", function()
    local f = M.SettingsSync.decodeJson(readFile(here .. "/../../../shared/fixtures/status/format.json"))
    for _, v in ipairs(f.progress) do eq(M.StatusLayout.progress(v.page,v.total,v.fraction), v.text) end
    for _, v in ipairs(f.clock) do eq(M.StatusLayout.clock(v.hour,v.minute,v.twelve), v.text) end
    eq(M.StatusLayout.progress(1,nil,0), "")
    eq(M.StatusLayout.progress(1,0,0), "")
    eq(M.StatusLayout.progress(1,10,-0.2), "1 / 10 · 0%")
    eq(M.StatusLayout.progress(10,10,1.2), "10 / 10 · 100%")
    eq(M.StatusLayout.progress(1,200), "1 / 200 · 1%")
end)
test("status layout: unequal sides retain physical centre, Unicode ellipsis and narrow fallback", function()
    local L = M.StatusLayout
    local function measure(s) local n=0; for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n=n+1 end; return n end
    eq(L.truncate("日本語の章",4,measure), "日本語…")
    eq(L.truncate("章",0,measure), "")
    eq(L.truncate("",100,measure), "")
    local a=L.layout(60,2,2,"battery","b","A very long chapter title", "12 / 340 · 4%",measure)
    eq(a.cx+measure(a.chapter)/2,30)
    ok(a.cx >= a.lx+measure(a.left)+2)
    ok(a.cx+measure(a.chapter)+2 <= a.rx)
    local b=L.layout(25,2,2,"battery percentage","b","chapter", "12 / 340 · 4%",measure)
    eq(b.chapter, ""); eq(b.left,"b")
    local c=L.layout(15,2,2,"battery percentage","b","chapter", "12 / 340 · 4%",measure)
    eq(c.chapter, ""); eq(c.left, "")
end)

test("status layout: inset full battery group has priority over page text", function()
    local L=M.StatusLayout
    local measure=function(t) return #t end
    local layout=L.layout(35,4,4,"100% + charge","icon","Chapter", "123 / 1234 · 100%",measure,true)
    eq(layout.left,"100% + charge"); eq(layout.lx,4)
    ok(layout.lx+measure(layout.left)+4<=layout.rx)
    ok(layout.rx+measure(layout.right)<=31)
    local hidden=L.layout(12,4,4,"100% + charge","icon","Chapter","1 / 2",measure,true)
    eq(hidden.left,"")
    local rectangles={}
    eq(L.chargingMark(18,function(x,y,w,h,color)
        eq(color,1); ok(x>=0 and x+w<=14 and y>=0 and y+h<=18)
        rectangles[#rectangles+1]={x,y,w,h}
    end),14)
    eq(#rectangles,9)
end)

-- shared/fixtures/REGISTRY.json: every rule table has a row, and this suite reads what it names (test_registry.lua).
test("fixture registry: the plugin reads every table it is named for, and every table has a row", function()
    local problems = dofile(here .. "/test_registry.lua")(here)
    eq(table.concat(problems, "\n"), "", "REGISTRY.json")
end)

dofile(here .. "/layout_tests.lua")(M, test, ok, eq, JSON, here)
dofile(here .. "/booklist_tests.lua")(M,test,ok,eq)

test("settings modes: approved presets use shared wire values and Balanced matches defaults", function()
    local e = setmetatable({}, {__index=_G}); setfenv(assert(loadfile(here .. "/../orbit.koplugin/logic/settings_ui.lua")), e)()
    local UI = e.SettingsUI
    local balanced = UI.modes[2].values
    for _, key in ipairs(UI.modeKeys) do
        eq(balanced[key], SIDX.byKey[key].default, key)
    end
    for _, mode in ipairs(UI.modes) do
        for _, key in ipairs(UI.modeKeys) do
            local d = SIDX.byKey[key]
            eq(SettingsSync.fromWire(d, SettingsSync.toWire(d, mode.values[key])), mode.values[key])
        end
        eq(UI.mode(mode.values), mode.id)
    end
    local unset = {}
    for _, key in ipairs(UI.modeKeys) do if key ~= "wifi_mode" then unset[key] = balanced[key] end end
    eq(UI.mode(unset, "jit"), "balanced", "effective device Wi-Fi default")
    eq(UI.mode(balanced, "always_on"), "custom", "effective capability policy beats stored Wi-Fi preference")
    eq(UI.installed("0.12.0-preview.9"),"BookSync 0.12.0-preview.9 · Preview")
    eq(UI.installed("0.12.0-rc.1"),"BookSync 0.12.0-rc.1 · RC")
    eq(UI.installed("0.12.0"),"BookSync 0.12.0 · Stable")
    ok(UI.channelText("rc","RC","0.12.0-rc.1"):find("installed build",1,true))
    ok(not UI.channelText("preview","Preview","0.12.0-rc.1"):find("installed build",1,true))
    ok(UI.channelText("stable","Stable","0.12.0"):find("Tested releases only",1,true))
    ok(UI.modeCard({},nil,{items={}}):find("Your own settings",1,true))
    ok(UI.modeCard(balanced,nil,{items={}}):find("Estimate pending",1,true))
    eq(UI.words("Server plugin's Home"), "Server plugin's Home")
    eq(UI.words("Server plugin's Home", "booksync"), "BookSync Home")
    eq(UI.words("Wake Tailscale for syncs"), "Wake VPN for syncs")
end)

dofile(here .. "/test_account.lua")(test, eq, ok, here)

dofile(here .. "/test_series.lua")(test,eq,ok,M)
dofile(here .. "/test_filter_sheet.lua")(test, eq, ok, here, M)
dofile(here .. "/test_library.lua")(test, eq, ok, here, M.Cache)
dofile(here .. "/test_delivery.lua")(test, eq, ok, here, M.Cache)

dofile(here .. "/test_storage.lua")(test, eq, ok, here)
dofile(here .. "/test_battery.lua")(test, eq, ok, here)

dofile(here .. "/test_local_completion.lua")(test, eq, ok, here, M.Cache)
dofile(here .. "/test_reading_stats.lua")(test, eq, ok, here, M.Cache)

dofile(here .. "/test_reading_style.lua")(test, eq, ok, here, M)

dofile(here .. "/test_reader_panel.lua")(test, eq, ok, here)

dofile(here .. "/test_local_widgets.lua")(test, eq, ok, here, M.Cache)

dofile(here .. "/home_presentation_logic.lua")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
