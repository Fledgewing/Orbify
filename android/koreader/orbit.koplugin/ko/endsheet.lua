-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).
-- Part of orbit.koplugin: loaded by main.lua into the plugin's shared environment, in the
-- order main.lua lists (docs/design/orbit-plugin.md "Module layout").

-- The end-of-book sheet (docs/design/end-of-book/DESIGN.md §4 "Layout", mockups.html Android
-- screens 1-6): full width at the bottom, a heavy rule on top, one e-ink paint, no dimming; the
-- last page stays visible above it, and a tap there closes it (the mark stays). Rows: status +
-- Undo; title, "by Author ›", series line; five stars and "Tap a star · tap it again to clear ·
-- Review"; the next-in-series card; one suggestion card; Back to book | Home.
-- Geometry comes from SheetLayout (logic/sheet_layout.lua): every row is built at its planned
-- size, measured, and the plan grows a row whose widget came out taller, so rows never overlap.
---------------------------------------------------------------------------------------------

local function W(name) return require("ui/widget/" .. name) end

EndSheet = nil
do
    local InputContainer = W("container/inputcontainer")
    EndSheet = InputContainer:extend{
        name = "orbit_end_of_book",
        modal = true,
        covers_fullscreen = false,
    }
end

-- A KOReader Size value (ui/size.lua), or fallback when this KOReader lacks it.
local function size(group, name, fallback)
    local g = type(Size) == "table" and Size[group]
    return type(g) == "table" and g[name] or fallback
end

local function scaler()
    local Device = require("device")
    local s = Device.screen
    if s and type(s.scaleBySize) == "function" then return function(px) return s:scaleBySize(px) end end
    return function(px) return px end
end

function EndSheet:init()
    local Device = require("device")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    self.screen_w, self.screen_h = Device.screen:getWidth(), Device.screen:getHeight()
    self.metrics = SheetLayout.metrics(self.screen_w, scaler())
    if self.min_button then self.metrics.button = math.max(self.metrics.button, scaler()(self.min_button)) end
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }
    self.ges_events = {
        TapAnywhere = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:build()
end

-- Taps above the sheet close it (the book is still marked); taps on it go to its buttons.
function EndSheet:onTapAnywhere(_arg, ges)
    local y0 = self.screen_h - (self.sheet_h or 0)
    if ges and ges.pos and ges.pos.y < y0 then
        Library.endAction("back")
        return true
    end
    return false
end

function EndSheet:onClose()
    Library.endAction("back")
    return true
end

function EndSheet:update(model, card_state)
    self.model = model
    self.card_state = card_state
    self:build()
    UIManager:setDirty(self, function() return "ui", self.frame and self.frame.dimen end)
end

-- What the sheet shows and does, flat and in drawing order: { kind, text, action, ... }. The
-- tests tap these; SheetLayout.blocks groups them into rows.
function EndSheet:rows()
    local m, cs, rows = self.model, self.card_state, {}
    local ui, b = self.ui, self.book
    local function add(r) table.insert(rows, r) end
    local status = { kind = "status", text = m.status }
    if m.undo then status.label, status.action = "Undo", function() Library.endAction("undo",ui, b) end
    elseif m.can_mark then status.label, status.action = "Mark as finished", function() Library.endAction("mark",ui, b) end end
    add(status)
    add({ kind = "title", text = m.title })
    if m.author then add({ kind = "author", text = "by " .. m.author .. " ›", action = function() Library.endAction("author",ui, b, m.author) end }) end
    if m.series_line then add({ kind = "series", text = m.series_line }) end
    for n = 1, 5 do
        add({ kind = "star", n = n, text = (m.stars and n <= m.stars) and "★" or "☆", action = function() Library.endAction("star",ui, b, n) end })
    end
    add({ kind = "hint", text = m.stars and "Tap a star · tap it again to clear" or "Tap a star to rate it" })
    add({ kind = "review", text = "Review ›", action = function() Library.endAction("review",ui) end })
    local function card(c)
        local busy = cs and cs.book_id == c.book_id
        if busy and cs.failure == "failed" then
            add({ kind = "notice", text = "Couldn't connect · your finish is saved and will be sent later" })
            add({ kind = "button", text = "Try again", action = function() Library.endAction("retry",ui, b, c.book_id, c.title) end })
            add({ kind = "button", text = "Get it at the next sync", secondary = true, action = function() Library.endAction("later",ui, b, c.book_id, c.title) end })
            return
        elseif busy and cs.failure == "error" then
            add({ kind = "notice", text = "Download failed: " .. tostring(cs.err or "server error") })
            add({ kind = "button", text = "Try again", action = function() Library.endAction("retry",ui, b, c.book_id, c.title) end })
            return
        end
        add({ kind = "card", text = tostring(c.title), sub = busy and cs.text or c.sub, book = c.book,
            label = busy and cs.text and "" or (c.action == "open" and "Open" or "Download & open"),
            action = function() Library.endAction("book",ui, b, c.book_id, c.title, c.local_path) end })
    end
    local nxt = m.next
    if nxt then
        add({ kind = "label", text = nxt.line })
        if nxt.book_id then card(nxt) end
    end
    if m.series_key then
        add({ kind = "button", text = "View series", secondary = true,
            action = function() Library.endAction("series",ui, b, m.series_key) end })
    end
    local s = m.suggestion
    if s then
        add({ kind = "label", text = s.line })
        card(s)
    end
    add({ kind = "footer", text = "‹ Back to book", action = function() Library.endAction("back") end })
    add({ kind = "footer", text = "Home", action = function() Library.endAction("home",ui) end })
    return rows
end

-- The cover for a card: the plugin's cached thumbnail when the catalog has one, else nil.
local function coverPath(book)
    return type(book)=="table" and book.cover_path or nil
end

-- One row's widget at width w and planned height h.
function EndSheet:rowWidget(block, w, h, mt)
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local Button = W("button")
    local ButtonTable = W("buttontable")
    local CenterContainer = W("container/centercontainer")
    local FrameContainer = W("container/framecontainer")
    local HorizontalGroup = W("horizontalgroup")
    local HorizontalSpan = W("horizontalspan")
    local InputContainer = W("container/inputcontainer")
    local LeftContainer = W("container/leftcontainer")
    local TextWidget = W("textwidget")
    local VerticalGroup = W("verticalgroup")
    local GestureRange = require("ui/gesturerange")

    local scale = scaler()
    local function text(t, size, bold, maxw, fgcolor)
        return TextWidget:new{ text = t or "", face = Font:getFace("cfont", size), bold = bold,
            max_width = maxw or w, fgcolor = fgcolor }
    end
    local function box(widget, bw, bh) -- fixed-size, left-aligned, vertically centred
        return LeftContainer:new{ dimen = Geom:new{ w = bw or w, h = bh or h }, widget }
    end
    -- A plain line that runs action on tap.
    local function link(widget, action, bw)
        local area = InputContainer:new{ dimen = Geom:new{ w = bw or w, h = h }, box(widget, bw) }
        area.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return area.dimen end } } }
        area.onTap = function() action(); return true end
        return area
    end
    local grey = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
    local k = block.kind
    local r = block.row
    if k == "progress" then
        -- A solid fill over a solid track: no ticks, brackets or chapter labels.
        local finish = Budgets.span("reader-progress.draw", now_s, log)
        local bar = W("progresswidget"):new{ width=w, height=math.max(4, scaler()(8)),
            percentage=r.value or 0, ticks={}, bordersize=0, radius=0, margin_h=0, margin_v=0,
            fillcolor=Blitbuffer.COLOR_BLACK, bgcolor=Blitbuffer.COLOR_LIGHT_GRAY }
        finish()
        return bar
    elseif k == "status" then
        local bw = r.action and mt.action_w or 0
        local hg = HorizontalGroup:new{ box(text(r.text, SheetLayout.FONTS.status, false, w - bw), w - bw) }
        if r.action then
            table.insert(hg, Button:new{ text = r.label, callback = r.action, width = bw, height = mt.button - 2 * size("border", "button", 1),
                bordersize = size("border", "button", 1), radius = size("radius", "button", 0) })
        end
        return hg
    elseif k == "title" then
        return box(text(r.text, SheetLayout.FONTS.title, true))
    elseif k == "author" then
        return link(text(r.text, SheetLayout.FONTS.author, false, w, grey), r.action)
    elseif k == "series" or k == "label" then
        return box(text(r.text, SheetLayout.FONTS.label, k == "label", w, grey))
    elseif k == "stars" then
        local cells = SheetLayout.centred(w, #block.items, mt.star * 2)
        local hg = HorizontalGroup:new{ HorizontalSpan:new{ width = cells[1].x } }
        for i, s in ipairs(block.items) do
            local star = CenterContainer:new{ dimen = Geom:new{ w = cells[i].w, h = h }, text(s.text, SheetLayout.FONTS.star) }
            table.insert(hg, link(star, s.action, cells[i].w))
        end
        return hg
    elseif k == "hint" then
        local review = block.items[1]
        local rw = review and scale(110) or 0
        local hg = HorizontalGroup:new{ box(text(block.text, SheetLayout.FONTS.hint, false, w - rw, grey), w - rw) }
        if review then table.insert(hg, link(text(review.text, SheetLayout.FONTS.review, true), review.action, rw)) end
        return hg
    elseif k == "card" then
        local cw, aw = mt.cover_w, mt.action_w
        local gap = scale(10)
        local path = coverPath(r.book)
        local cover
        if path then
            local okw, ImageWidget = pcall(W, "imagewidget")
            if okw then cover = ImageWidget:new{ file = path, width = cw, height = h, scale_factor = 0 } end
        end
        cover = cover or FrameContainer:new{ bordersize = size("border", "thin", 1), padding = 0, margin = 0,
            W("verticalspan"):new{ width = h - 2 * size("border", "thin", 1) } }
        local tw = w - cw - aw - 2 * gap
        local lines = VerticalGroup:new{ align = "left", text(r.text, SheetLayout.FONTS.card_title, true, tw), text(r.sub or "", SheetLayout.FONTS.card_sub, false, tw, grey) }
        local hg = HorizontalGroup:new{ align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = cw, h = h }, cover },
            HorizontalSpan:new{ width = gap },
            link(lines, r.action, tw),
            HorizontalSpan:new{ width = gap } }
        if r.label ~= "" then
            table.insert(hg, Button:new{ text = r.label, callback = r.action, width = aw, height = mt.button - 2 * size("border", "button", 1),
                bordersize = size("border", "button", 1), radius = size("radius", "button", 0), text_font_bold = true })
        end
        return hg
    elseif k == "notice" then
        return box(text(r.text, SheetLayout.FONTS.notice, false, w))
    elseif k == "button" then
        return Button:new{ text = r.text, callback = r.action, width = w, height = h - 2 * size("border", "button", 1),
            bordersize = size("border", "button", 1), radius = size("radius", "button", 0), text_font_bold = not r.secondary }
    elseif k == "footer" then
        local row = {}
        for _, f in ipairs(block.items) do table.insert(row, { text = f.text, callback = f.action }) end
        return ButtonTable:new{ width = w, buttons = { row }, zero_sep = true, sep_width = 0 }
    end
    return box(text(r and r.text or "", 16))
end

function EndSheet:build()
    if self.name=="orbit_end_of_book" then return CatalogUI.finish(self) end
    local finish=Budgets.span("end-of-book.draw",now_s,log)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local BottomContainer = W("container/bottomcontainer")
    local FrameContainer = W("container/framecontainer")
    local LineWidget = W("linewidget")
    local VerticalGroup = W("verticalgroup")
    local VerticalSpan = W("verticalspan")
    local LeftContainer = W("container/leftcontainer")

    local mt = self.metrics
    local blocks = SheetLayout.blocks(self:rows())
    local inner = mt.w - 2 * mt.pad
    -- Build each row at its planned height, measure it, and let the plan grow any that need it.
    mt.measured = {}
    local planned = SheetLayout.plan(blocks, mt)
    local widgets = {}
    for i, it in ipairs(planned.items) do
        local wdg = self:rowWidget(it.block, inner, it.h, mt)
        widgets[i] = wdg
        local okg, size = pcall(function() return wdg:getSize() end)
        if okg and type(size) == "table" and type(size.h) == "number" and size.h > it.h then mt.measured[it.block] = size.h end
    end
    self.plan = SheetLayout.plan(blocks, mt)
    local vg = VerticalGroup:new{ align = "left" }
    local y = mt.rule + mt.pad
    for i, it in ipairs(self.plan.items) do
        if it.y > y then table.insert(vg, VerticalSpan:new{ width = it.y - y }) end
        table.insert(vg, LeftContainer:new{ dimen = Geom:new{ w = inner, h = it.h }, widgets[i] })
        y = it.y + it.h
    end
    self.sheet_h = math.min(self.plan.h, math.floor(self.screen_h * 0.9))
    local rule = LineWidget:new{ dimen = Geom:new{ w = mt.w, h = mt.rule }, background = Blitbuffer.COLOR_BLACK }
    self.frame = FrameContainer:new{
        width = mt.w, height = self.sheet_h, bordersize = 0, margin = 0,
        padding = 0, padding_left = mt.pad, padding_right = mt.pad, padding_top = 0, padding_bottom = mt.pad,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left",
            -- The rule spans the screen: pulled out of the side padding.
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = mt.rule }, rule },
            VerticalSpan:new{ width = mt.pad }, vg },
    }
    self.rule_widget = rule
    self[1] = BottomContainer:new{ dimen = Geom:new{ w = self.screen_w, h = self.screen_h }, self.frame }
    finish()
end
