-- SPDX-License-Identifier: MIT
-- Test-only user patch installed on a dedicated emulator, never packaged with BookSync.
-- Seed the native first-run preference before reader.lua:195 tests it. This late
-- user patch runs at reader.lua:190, while G_reader_settings is already open.
-- A known emulator color screen needs no first-run notice over a reviewed sheet.
G_reader_settings:makeTrue("color_rendering")
G_reader_settings:flush()
local UI=require("ui/uimanager")
local base="/sdcard/koreader/e2e-"
local running=false
local function run()
    UI:scheduleIn(.2,run)
    if running then return end
    local file=io.open(base.."command.lua","rb")
    if not file then return end
    local code=file:read("*a");file:close();os.remove(base.."command.lua")
    running=true
    local request_id=code:match("^%-%- booksync%-request:([%x]+)\n") or "unknown"
    local plugin=require("pluginloader"):getPluginInstance("orbit")
    local ok,result=pcall(function()
        assert(plugin,"plugin not loaded")
        local method=plugin.onSuspend
        -- KOReader's HandlerSandbox retains the original function as .f.
        if type(method)=="table" then method=method.f end
        local env=getfenv(assert(method,"Home handler missing"))
        local top=env.topWidget or function() return UI:getTopmostVisibleWidget() end
        local chunk=assert(loadstring(code))
        local function click(text)
            local seen={}
            local function visit(node)
                if type(node)~="table" or seen[node] then return false end
                seen[node]=true
                if node.text==text and node.callback then node.callback();return true end
                for _,child in ipairs(node) do if visit(child) then return true end end
                if node.buttons and visit(node.buttons) then return true end
                return false
            end
            assert(visit(top()),"missing button: "..text)
        end
        setfenv(chunk,setmetatable({plugin=plugin,UI=UI,click=click,top=top},{__index=env}))
        return chunk()
    end)
    local out=assert(io.open(base.."result.tmp","wb"));out:write(ok and "OK " or "FAIL ",request_id,"\n",tostring(result));out:close()
    assert(os.rename(base.."result.tmp",base.."result"))
    running=false
end
UI:scheduleIn(1,run)
