-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Pure presentation regressions: no KOReader stand-ins or data producer.
local here=arg[0]:match("^(.*)/") or "."
local env=setmetatable({},{__index=_G})
setfenv(assert(loadfile(here.."/../orbit.koplugin/logic/home_host.lua")),env)()
local H=env.HomeHostPlan
assert(H.syncFreshness({},1000,nil)=="Not synced yet · Sync")
assert(H.syncFreshness({at=100,ok=false},1000,nil)=="Sync pending · Sync")
assert(H.syncFreshness({at=100,ok=true},820,nil)=="✓ Synced 12 min ago   Sync")
assert(H.syncFreshness({at=1000,ok=true},900,nil)=="✓ Synced just now   Sync")
assert(H.syncFreshness({at=100,ok=true},820,"No sync login · Set up")=="No sync login · Set up")
assert(H.readAge(nil,1000)=="Last read unknown")
assert(H.readAge(1000,1000)=="Read today")
assert(H.readAge(1000,1000+86400)=="Read yesterday")
assert(H.readAge(1000,1000+4*86400)=="Read 4 days ago")
local px=function(n) return n*2 end
local shelf=H.cardGeometry({instance="recent",widget="booklist",w=2,settings={style=0}},{w=654,h=382},px)
assert(shelf.shelf and shelf.capacity==3,"three cover thumbnails in the approved half-width shelf")
local also=H.cardGeometry({instance="also",widget="booklist",w=2,settings={style=1}},{w=654,h=382},px)
assert(not also.shelf and also.capacity==2,"two Also reading rows")
local lists=H.cardGeometry({instance="lists",widget="lists",w=2,settings={}},{w=654,h=586},px)
assert(lists.capacity==4,"four saved list rows")
local compact=H.cardGeometry({instance="saved",widget="booklist",w=2,settings={style=0}},{w=654,h=178},px)
assert(compact.compact and compact.capacity==1,"one-row custom placements retain a bounded compact view")
print("Home presentation: 13 assertions passed")
