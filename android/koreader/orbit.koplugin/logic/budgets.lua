-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Deterministic render/read limits; device timings are targets, not host-test assertions.
Budgets = { screens = {}, widgets = {} }
local function budget(rows, bytes, ms)
    return { rows=rows, bytes=bytes, spawns=0, roundTrips=1, network=0,
        snapshotBytes=16384, targetMs=ms }
end
for _, id in ipairs({"home", "library", "details", "series", "settings", "battery", "filter", "editor", "reader-top-panel", "book-info"}) do
    Budgets.screens[id] = budget(id == "home" and 128 or 32, id == "home" and 131072 or 32768,
        id == "home" and 500 or id == "editor" and 100 or 50)
end
Budgets.screens["account"] = budget(3, 16384, 50)
-- Upgrade news is five static rows, with no read-model or worker access.
Budgets.screens["whats-new"] = budget(5, 0, 50)
Budgets.screens["whats-new"].roundTrips = 0
-- Owned Search inherits the Library screen family; Home pages inherit home.
Budgets.screens.search = Budgets.screens.library
Budgets.screens.account.displayRows=12
-- Editor draws only its current page; it never reads a catalog or widget snapshot.
Budgets.screens.editor.drawNodes = 208
Budgets.screens.editor.rows = 128
Budgets.screens.editor.bytes = 0
Budgets.screens.editor.roundTrips = 0
Budgets.screens["editor-picker"] = budget(5, 0, 100)
Budgets.screens["editor-picker"].roundTrips = 0
-- Retained editor background plus five bounded illustrated choices.
Budgets.screens["editor-picker"].drawNodes = 208
-- Picker pages inherit the same filter screen limits, including one worker round-trip.
Budgets.screens["filter-picker"] = budget(24, 16384, 50)
Budgets.libraryBootstrap = budget(1,16384,50)
Budgets.libraryWindow = budget(32, 32768, 30)
for _, id in ipairs({"continue-reading", "booklist", "lists", "library", "battery", "this-week",
    "year-in-reading", "when-you-read", "reading-records", "today", "reading-streak", "reading-goal", "pages-read", "monthly-reading", "finish-forecast", "next-stop", "sync-controls", "reader-toggles", "dust", "achievements", "clock", "moon", "glyph", "word", "light", "buddy", "highlight", "yearago", "recommended", "discover"}) do
    Budgets.widgets[id] = budget(id == "booklist" and 12 or id == "lists" and 8 or 1, 16384, 50)
end
-- Library summary + local storage summary are two materialized rows in one batch.
Budgets.widgets.library.rows = 2
local fields = {"rows", "bytes", "spawns", "roundTrips", "network", "snapshotBytes"}
-- Counts must be supplied by the host/read-model boundary, including zeroes. A Home paint
-- checks aggregate counts once; each widget/read also checks its inherited budget.
function Budgets.check(b, counts)
    if type(b) ~= "table" or type(counts) ~= "table" then return nil, "missing budget/counts" end
    for _, k in ipairs(fields) do
        local n, limit = counts[k], b[k]
        if type(n) ~= "number" or n < 0 or n ~= math.floor(n)
            or type(limit) ~= "number" or limit < 0 or limit ~= math.floor(limit) or n > limit then return nil, "budget: " .. k end
    end
    if b.drawNodes and (type(counts.drawNodes) ~= "number" or counts.drawNodes < 0 or counts.drawNodes ~= math.floor(counts.drawNodes) or counts.drawNodes > b.drawNodes) then return nil,"budget: drawNodes" end
    if b.spawns ~= 0 or b.network ~= 0 or b.roundTrips > 1 or b.snapshotBytes > 16384 then
        return nil, "unsafe budget"
    end
    return true
end
-- Inject the logger and monotonic clock at the host boundary. One info line per completed
-- paint/call; no clock, logging, networking or subprocess dependencies in the pure engine.
function Budgets.span(id, clock, info)
    local start = clock()
    return function() info(string.format("BookSync %s %.1f ms", id, (clock()-start)*1000)) end
end

-- Wire/result ceilings for the companion read model. Caller budgets may be narrower.
Budgets.MAX_SNAPSHOT, Budgets.MAX_ROWS = 16384, 24
Budgets.MAX_BATCH, Budgets.MAX_REQUEST = 16, 8192
function Budgets.get(kind, id)
    local b = assert(Budgets[kind] and Budgets[kind][id], "Missing screen/widget budget")
    assert(Budgets.check(b, {rows=0,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0,drawNodes=0}))
    return b
end

-- Settings groups inherit the Settings family limits.
for _, id in ipairs({"account", "sync", "library", "reading", "home", "sleep", "updates", "about"}) do
    Budgets.screens["settings-" .. id] = Budgets.screens.settings
end
-- Reader surfaces consume one book, capability row and optional battery row, in one batch.
for _, id in ipairs({"reader-top-panel", "book-info", "details"}) do
    Budgets.screens[id] = budget(3, 3 * 16384, 50)
end

Budgets.widgets["reader-progress"] = budget(1, 16384, 50)

-- Device-local style editors read one bounded record; no worker or decoded snapshots.
for _, key in ipairs({"font", "margins", "spacing", "contrast"}) do
    Budgets.screens["reading-custom-" .. key] = budget(12, 0, 50)
    Budgets.screens["reading-custom-" .. key].roundTrips = 0
end

Budgets.screens["reading-copy"] = budget(3, 0, 50)
Budgets.screens["reading-copy"].roundTrips = 0
for _,id in ipairs({"summary","form","signout","remove","result"}) do
    Budgets.screens["account-" .. id] = Budgets.screens.account
end
-- Battery tabs select bounded windows from one companion materialization.
Budgets.screens.battery.rows = 1
Budgets.screens.battery.bytes = 16384
-- Book list settings draw small configuration; source pages read one companion window.
Budgets.screens["booklist-config"] = budget(0, 0, 100)
Budgets.screens["booklist-config"].roundTrips = 0
Budgets.screens["booklist-sources"] = budget(6, 16384, 50)

Budgets.screens["position-consent"] = budget(1, 16384, 50)
Budgets.screens["position-verification"] = budget(1, 16384, 50)
-- Storage, its confirmations and folder chooser use one local materialized row.
Budgets.screens.storage = budget(1,16384,50)
Budgets.screens.collections = budget(6,16384,50)

Budgets.screens["storage-folder"] = Budgets.screens.storage
Budgets.screens["storage-confirm"] = Budgets.screens.storage
-- Reader controls are one companion-materialized row; native inputs are capped at 64 markers per kind.
Budgets.screens["reader-top-panel"].rows = 4
Budgets.screens["reader-top-panel"].bytes = 4 * 16384
Budgets.screens["reader-bottom-panel"] = budget(2, 2 * 16384, 50)
Budgets.widgets["reader-controls"] = budget(1, 16384, 50)

Budgets.readerControls = { markersPerKind=64, tocComparisons=32 }



-- One local cover reference per lookup. Acquisition is owned by the off-paint host.
Budgets.screens["cover-cache"] = budget(1,16384,30)
Budgets.screens["cover-cache"].roundTrips = 0

-- Series/grouped windows charge summary, preview books and one capability row.
Budgets.screens.series.rows = Budgets.MAX_ROWS + 1


-- Sleep picker pages inherit six companion-materialized names/counts, never a choice catalog.
Budgets.screens["settings-sleep-choices"] = budget(6,16384,50)
Budgets.screens["settings-device"] = budget(1,16384,50)


Budgets.screens["settings-sleep-choices"].displayRows = 10

Budgets.screens["catalog-refresh"] = budget(1,16384,50)
Budgets.screens["catalog-refresh"].roundTrips = 0

-- Finish summary + two selected cards, current reader and optional local next cover.
-- All five materialized rows share one bounded worker batch.
Budgets.screens["end-of-book"] = budget(5,16384,50)
Budgets.widgets["end-of-book"] = budget(3,16384,50)
Budgets.screens["settings-recommendations"] = budget(10,16384,50)
Budgets.screens["settings-recommendations"].displayRows=18
Budgets.widgets["recommendations"] = budget(10,16384,50)
Budgets.screens["copies-state"] = budget(1,16384,30)
Budgets.screens["copies-state"].roundTrips = 0

-- Card overflow is a static five-row sheet; bitmap input is separate from snapshot bytes.
Budgets.screens["book-actions"] = budget(5,0,50)
Budgets.screens["book-actions"].roundTrips = 0
Budgets.CARD_COVER_BYTES = 524288

-- Yield between post-paint card cover windows, including local bitmap delivery.
Budgets.CARD_COVER_BATCH = 4

-- Explicit remove preview/confirmation: one worker row and static native controls.
Budgets.screens["book-removal"] = budget(1,16384,50)
Budgets.screens["book-removal"].displayRows=4

Budgets.screens["book-status"] = budget(1,16384,50)
Budgets.screens["book-status"].displayRows=3

-- User-started transfer sheets: bounded file choices and one worker-owned job snapshot.
Budgets.screens["download-options"] = budget(8,16384,50)
Budgets.screens["download-options"].displayRows = 10
Budgets.screens["download-job"] = budget(1,16384,50)
Budgets.screens["download-job"].displayRows = 4

-- One Series summary and at most ten exact file/job rows.
Budgets.screens["series-downloads"] = budget(11,16384,50)
Budgets.screens["series-downloads"].displayRows=15

-- Cached native navigation: one summary plus eight rows, no render-time IO.
Budgets.screens["reader-navigation"] = budget(12,16384,50)
Budgets.screens["reader-navigation"].roundTrips=0

Budgets.screens["settings-reading-statistics"] = budget(1, 16384, 50)
Budgets.screens["settings-reading-statistics"].displayRows = 3

-- Reader companion: four local summary/action rows, one bounded snapshot and batch.
for _,id in ipairs({"reader-status","reader-helpers"}) do
    Budgets.screens[id]=budget(4,16384,50)
    Budgets.screens[id].displayRows=9
end

-- Reminder values are materialized on a lifecycle/worker boundary, never during paint.
Budgets.screens["reminders-runtime"] = budget(9,8192,50)
Budgets.screens["reminders-list"] = budget(9,8192,50)
Budgets.screens["reminders-list"].displayRows=12
Budgets.screens["reminders-list"].roundTrips=0
Budgets.screens["reminders-editor"] = budget(8,1024,50)
Budgets.screens["reminders-editor"].roundTrips=0
Budgets.screens["reminders-sheet"] = budget(1,1024,50)
Budgets.screens["reminders-sheet"].roundTrips=0
