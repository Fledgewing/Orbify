-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Focused entry point for the reader surfaces and their bounded Library adapter.
local here=arg[0]:match("^(.*)/[^/]*$") or "."
local passed,failed=0,0
local function eq(a,b,message) assert(a==b,(message or "values differ")..": "..tostring(a).." ~= "..tostring(b)) end
local function ok(value,message) assert(value,message or "expected truthy") end
local function test(name,fn)
    local success,message=pcall(fn)
    if success then passed=passed+1 else failed=failed+1;io.stderr:write(name..": "..tostring(message).."\n") end
end
dofile(here.."/test_reader_panel.lua")(test,eq,ok,here)
dofile(here.."/reader_panel_flows.lua")(here,test,ok,eq)
print(passed.." reader tests passed; "..failed.." failed")
os.exit(failed==0 and 0 or 1)
