--[[
Small widgets for the remote screen: tappable cells with icons, segmented rows,
pill buttons and a volume slider. Plain KOReader widgets, drawn for e-ink:
black on white, an "on" state is drawn inverted (white on black).
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local RemoteUI = {}

local PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*/)[^/]*$") or "./"
RemoteUI.ICON_DIR = PLUGIN_DIR .. "icons/"

function RemoteUI.icon(name, size)
    return IconWidget:new{ file = RemoteUI.ICON_DIR .. name .. ".svg", width = size, height = size }
end

function RemoteUI.text(text, size, bold, max_width)
    return TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = bold, max_width = max_width }
end

--- Icon above a short label (or either one alone).
function RemoteUI.iconLabel(icon, label, icon_size, font_size)
    local g = VerticalGroup:new{ align = "center" }
    if icon then g[#g + 1] = RemoteUI.icon(icon, icon_size) end
    if label then g[#g + 1] = RemoteUI.text(label, font_size or 16) end
    return g
end

---------------------------------------------------------------------------
-- Cell: a tappable rectangle, content centered, optionally drawn inverted.
---------------------------------------------------------------------------
local Cell = InputContainer:extend{
    width = nil,
    height = nil,
    content = nil,
    inverted = false,
    callback = nil,
    hold_callback = nil,
    show_parent = nil,
}
RemoteUI.Cell = Cell

function Cell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        self.content or HorizontalSpan:new{ width = 0 },
    }
    self.ges_events = {}
    if self.callback then
        self.ges_events.TapCell = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if self.hold_callback then
        self.ges_events.HoldCell = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
end

function Cell:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.inverted then bb:invertRect(x, y, self.width, self.height) end
end

function Cell:flash()
    local d = self.dimen
    UIManager:widgetInvert(self, d.x, d.y, d.w, d.h)
    UIManager:setDirty(nil, "fast", Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h })
    UIManager:forceRePaint()
end

function Cell:onTapCell()
    if not self.callback then return end
    self:flash()
    local d = Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.dimen.w, h = self.dimen.h }
    local parent = self.show_parent
    UIManager:nextTick(function()
        self.callback()
        -- undo the flash if the callback did not redraw the screen
        if parent and not parent.closed then UIManager:setDirty(parent, "fast", d) end
    end)
    return true
end

function Cell:onHoldCell()
    if self.hold_callback then self.hold_callback() end
    return true
end

---------------------------------------------------------------------------
-- Segmented row: cells side by side inside one rounded frame, thin separators.
-- specs: { { content=widget, callback=fn, inverted=bool, weight=1 }, ... }
---------------------------------------------------------------------------
function RemoteUI.row(specs, width, height, show_parent)
    local border = Size.border.button
    local sep = Size.line.medium
    local n = #specs
    local total_weight = 0
    for _, s in ipairs(specs) do total_weight = total_weight + (s.weight or 1) end
    local avail = width - 2 * border - (n - 1) * sep
    local group = HorizontalGroup:new{ align = "center" }
    local used = 0
    for i, s in ipairs(specs) do
        local w = (i == n) and (avail - used) or math.floor(avail * (s.weight or 1) / total_weight)
        used = used + w
        if i > 1 then
            group[#group + 1] = LineWidget:new{
                background = s.no_sep and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = sep, h = height },
            }
        end
        if s.make then
            group[#group + 1] = s.make(w, height) -- custom widget of exactly w x height
        else
            group[#group + 1] = Cell:new{
                width = w, height = height, content = s.content, inverted = s.inverted,
                callback = s.callback, hold_callback = s.hold_callback, show_parent = show_parent,
            }
        end
    end
    return FrameContainer:new{
        bordersize = border,
        radius = Size.radius.button,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
end

---------------------------------------------------------------------------
-- Pill: small rounded button with an icon and a word, e.g. "♥ Like".
---------------------------------------------------------------------------
function RemoteUI.pill(icon, label, callback, show_parent, font_size)
    font_size = font_size or 17
    local icon_size = Screen:scaleBySize(font_size + 3)
    local h = Screen:scaleBySize(font_size * 2 + 6)
    local inner = HorizontalGroup:new{
        align = "center",
        RemoteUI.icon(icon, icon_size),
        HorizontalSpan:new{ width = Screen:scaleBySize(5) },
        RemoteUI.text(label, font_size),
    }
    local frame = FrameContainer:new{
        bordersize = Size.border.button,
        radius = math.floor(h / 2),
        padding = 0,
        padding_left = Screen:scaleBySize(10),
        padding_right = Screen:scaleBySize(12),
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = inner:getSize().w, h = h - 2 * Size.border.button },
            inner,
        },
    }
    local size = frame:getSize()
    return Cell:new{ width = size.w, height = size.h, content = frame, callback = callback, show_parent = show_parent }
end

---------------------------------------------------------------------------
-- Volume slider: tap anywhere to set; drag to preview (fast refresh) and the
-- value is sent once the finger lifts, so e-ink doesn't lag behind the finger.
---------------------------------------------------------------------------
local Slider = InputContainer:extend{
    width = nil,
    height = nil,
    value = 0,        -- 0..100
    on_change = nil,  -- function(new_value), called on tap / release
    show_parent = nil,
}
RemoteUI.Slider = Slider

function Slider:init()
    self.knob = math.floor(self.height * 0.55)
    self.bar_h = math.max(Screen:scaleBySize(10), math.floor(self.height * 0.2))
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapSlider = { GestureRange:new{ ges = "tap", range = self.dimen } },
        PanSlider = { GestureRange:new{ ges = "pan", range = self.dimen, rate = 4 } },
        PanReleaseSlider = { GestureRange:new{ ges = "pan_release", range = self.dimen } },
        SwipeSlider = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        HoldSlider = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Slider:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function Slider:valueAt(x)
    local pad = self.knob / 2
    local v = (x - self.dimen.x - pad) / (self.width - 2 * pad) * 100
    return math.max(0, math.min(100, math.floor(v + 0.5)))
end

function Slider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local knob, bar_h = self.knob, self.bar_h
    local pad = math.floor(knob / 2)
    local bx, bw = x + pad, self.width - 2 * pad
    local by = y + math.floor((self.height - bar_h) / 2)
    local r = math.floor(bar_h / 2)
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local fill = math.floor(bw * (self.value or 0) / 100)
    if fill > 0 then
        bb:paintRoundedRect(bx, by, math.max(fill, bar_h), bar_h, Blitbuffer.COLOR_BLACK, r)
    end
    bb:paintBorder(bx, by, bw, bar_h, Size.border.thick, Blitbuffer.COLOR_BLACK, r)
    local kx = bx + fill - pad
    local ky = y + math.floor((self.height - knob) / 2)
    bb:paintRoundedRect(kx, ky, knob, knob, Blitbuffer.COLOR_WHITE, pad)
    bb:paintBorder(kx, ky, knob, knob, Size.border.thick + Size.border.default, Blitbuffer.COLOR_BLACK, pad)
end

function Slider:preview(v)
    if v == self.value then return end
    self.value = v
    local d = self.dimen
    UIManager:setDirty(self.show_parent, function()
        return "fast", Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h }
    end)
end

function Slider:commit(v)
    if self._commit_timer then UIManager:unschedule(self._commit_timer); self._commit_timer = nil end
    self._dragging = false
    self:preview(v)
    if self.on_change then self.on_change(v) end
end

function Slider:onTapSlider(_, ges)
    self:commit(self:valueAt(ges.pos.x))
    return true
end

function Slider:onHoldSlider(_, ges)
    self:preview(self:valueAt(ges.pos.x))
    self._dragging = true
    return true
end

function Slider:onPanSlider(_, ges)
    self._dragging = true
    self:preview(self:valueAt(ges.pos.x))
    -- the finger may be lifted outside the bar (no pan_release here): commit after a pause
    if self._commit_timer then UIManager:unschedule(self._commit_timer) end
    self._commit_timer = function()
        self._commit_timer = nil
        if self._dragging then self:commit(self.value) end
    end
    UIManager:scheduleIn(0.8, self._commit_timer)
    return true
end

function Slider:onPanReleaseSlider(_, ges)
    if not self._dragging then return true end
    self:commit(self:valueAt(ges.pos.x))
    return true
end

function Slider:onSwipeSlider(_, ges)
    if ges.end_pos and (ges.direction == "east" or ges.direction == "west") then
        self:commit(self:valueAt(ges.end_pos.x))
    end
    return true
end

return RemoteUI
