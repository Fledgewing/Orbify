-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).

-- Keep diagnostics in release builds: only timed BookSync work is attributed here,
-- never the input wait or another plugin's scheduled callback. No document data is logged.
MainLoop = { wrapped = setmetatable({}, { __mode = "kv" }), pid = Db.pid(), paused = setmetatable({}, { __mode = "k" }), turns = setmetatable({}, { __mode = "k" }) }
local plugin_env = getfenv(1)
function MainLoop.wrap(fn, where)
    if MainLoop.wrapped[fn] then return MainLoop.wrapped[fn] end
    local function timed(...)
        local co = coroutine.running()
        local function clock() return now_s() - (co and MainLoop.paused[co] or 0) end
        local start = clock()
        local turn = co and MainLoop.turns[co]
        local args = pack(...)
        local result = pack(xpcall(function() return fn(unpack(args,1,args.n)) end,
            function(err) return debug.traceback(tostring(err),2) end))
        local ms = (clock() - start) * 1000
        -- A yielding job spans several turns; its individual resume callbacks are timed above.
        local yielded = co and MainLoop.turns[co] ~= turn
        if ms > 50 and not yielded and Db.pid() == MainLoop.pid then
            log(string.format("booksync: main-loop stall %d ms in %s", math.floor(ms + 0.5), where))
        end
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    MainLoop.wrapped[fn], MainLoop.wrapped[timed] = timed, timed
    return timed
end

-- Include the entire scheduled callback, not just each individual operation inside it.
-- Keep one wrapper per function so unschedule still cancels every registration of it.
for _, name in ipairs({ "scheduleIn", "nextTick" }) do
    local stock = UIManager[name]
    UIManager[name] = function(self, ...)
        local args = pack(...)
        local index = name == "scheduleIn" and 2 or 1
        local fn = args[index]
        if type(fn) == "function" and getfenv(fn) == plugin_env then
            local info = debug.getinfo(fn, "Sl")
            local source = (info.source or ""):match("orbit%.koplugin/(.*)$") or "callback"
            args[index] = MainLoop.wrap(fn, source .. ":" .. info.linedefined)
        end
        return stock(self, unpack(args, 1, args.n))
    end
end
local stock_unschedule = UIManager.unschedule
function UIManager:unschedule(fn, ...)
    return stock_unschedule(self, MainLoop.wrapped[fn] or fn, ...)
end

-- Event handlers, repaint work and synchronous bridges also run outside scheduled tasks.
local function wrapTable(t,name)
    if type(t) == "table" then
        for key, fn in pairs(t) do
            if type(fn) == "function" and getfenv(fn) == plugin_env then
                t[key] = MainLoop.wrap(fn, name .. "." .. key)
            end
        end
    end
end
for _,name in ipairs({"OrbitAndroid","ReadingStatus","Store","Companion","Jni","Shared","Clicks","Channel","Wifi","Net","Sleep","Stats","ReadingSync","Library"}) do
    wrapTable(plugin_env[name],name)
end

-- Catch at the main-loop boundary, including native repaint/input and other plugins.
-- Retain the original traceback before Lua unwinds. Never swallow or restart the loop.
-- This is fatal-path IO only; no file work is added to a normal input/paint turn.
function MainLoop.fatal(err)
    local trace=debug.traceback(tostring(err),2)
    for line in trace:gmatch("[^\n]+") do
        pcall(logger.err,"BookSync: KOReader main loop failed:",line)
    end
    pcall(function()
        Store.writeFile(Store.dir().."/koreader-crash.txt",("KOReader Lua main loop\n"..trace):sub(1,4096))
    end)
    return trace
end
local stock_handleInput=UIManager.handleInput
if type(stock_handleInput)=="function" then
    function UIManager:handleInput(...)
        local args=pack(...)
        local result=pack(xpcall(function() return stock_handleInput(self,unpack(args,1,args.n)) end,MainLoop.fatal))
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
end
