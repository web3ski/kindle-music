--[[--
"Now playing" sleep screen.

When the Kindle goes to sleep inside KOReader while music is playing (or while the remote is
open), KOReader's normal sleep screen is replaced by a picture of the current track: cover in
grayscale, title, artist, album and room. E-ink keeps the picture without power, but it is not
updated while the device sleeps; it shows the time it was taken.

We hook Screensaver:show() and hand it a ready-made image (as if it were a book cover), so
KOReader still takes care of rotation, refresh, the unlock gesture and waking up.

@module sleepscreen
--]]

local Blitbuffer = require("ffi/blitbuffer")
local bit = require("bit")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local socketutil = require("socketutil")
local T = require("l10n").T
local Screen = Device.screen

local Sonos = require("sonos")
local SpotifyUI = require("spotifyui")

local SleepScreen = {
    -- last known playback, shared by all plugin instances (reader and file manager):
    -- { title, artist, album, art, state, room, ip (Sonos coordinator) | connect_id, time }
    now_playing = nil,
    remote_open = false,
    plugin = nil, -- most recent plugin instance (for settings and the Spotify client)
}

local STALE_SECONDS = 20
-- Live updates while asleep: wake up (RTC alarm) when the song should end, at the latest after
-- MAX_WAIT seconds (skips/pauses from another device), or MAX_WAIT_CHARGING on the charger.
-- Streams without a track length (internet radio) are checked every STREAM_WAIT seconds.
local MAX_WAIT = 600
local MAX_WAIT_CHARGING = 60
local STREAM_WAIT = 300
local MIN_WAIT = 20
local NETWORK_WAIT = 15 -- seconds to wait for Wi-Fi after a scheduled wakeup

--- "0:03:25" / "3:25" -> seconds (nil when unknown).
function SleepScreen.seconds(s)
    if type(s) == "number" then return s end
    if type(s) ~= "string" then return nil end
    local h, m, sec = s:match("^(%d+):(%d+):(%d+)")
    if not h then
        m, sec = s:match("^(%d+):(%d+)")
        h = 0
    end
    if not m then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)
end

function SleepScreen.update(np)
    if np then np.time = os.time() end
    SleepScreen.now_playing = np
end

-- short timeouts while going to sleep; longer ones after a scheduled wakeup (nobody waits then)
local timeouts = { 1, 2 }

local function quick(fn, ...)
    socketutil:set_timeout(timeouts[1], timeouts[2])
    local ok, a, b = pcall(fn, ...)
    socketutil:reset_timeout()
    if not ok then return nil end
    return a, b
end

--- Re-read the playing track if our copy is old (the remote may have been closed for a while).
local function refresh(np)
    if os.time() - (np.time or 0) < STALE_SECONDS then return np end
    local NetworkMgr = require("ui/network/manager")
    local ok, online = pcall(NetworkMgr.isConnected, NetworkMgr)
    if not ok or not online then return np end
    if np.ip then
        local state = quick(Sonos.getState, np.ip)
        if not state then return np end
        local track = quick(Sonos.getTrack, np.ip) or {}
        np.state = state
        np.title, np.artist, np.album, np.art = track.title, track.artist, track.album, track.art
        np.duration, np.position = SleepScreen.seconds(track.duration), SleepScreen.seconds(track.position)
    elseif np.connect_id and SleepScreen.plugin then
        local sp = SleepScreen.plugin:spotify()
        local st, err
        if sp then st, err = quick(sp.player, sp) end
        if (not st and err == "none") or (st and st.device_id ~= np.connect_id) then
            np.state = "STOPPED" -- nothing playing, or playing on another device now
            np.time = os.time()
            return np
        end
        if not st then return np end
        np.state = st.is_playing and "PLAYING" or "PAUSED_PLAYBACK"
        np.title, np.artist, np.album, np.art = st.title, st.artist, st.album, st.image
        np.duration, np.position = st.duration, st.progress
    end
    np.time = os.time()
    return np
end

--- Data to show, or nil to keep KOReader's own sleep screen.
local function current()
    local plugin = SleepScreen.plugin
    if not plugin or plugin.settings:isFalse("sleep_screen") then return nil end
    local np = SleepScreen.now_playing
    if not np then return nil end
    np = refresh(np)
    if not np.title or np.title == "" or np.title == "—" then return nil end
    if np.state == "PLAYING" or np.state == "TRANSITIONING" or SleepScreen.remote_open then
        return np
    end
end

--- Render the sleep screen into a portrait blitbuffer of the given size.
function SleepScreen.render(np, w, h)
    local pad = math.floor(w * 0.08)
    local inner_w = w - 2 * pad
    local cover_side = math.floor(math.min(inner_w, h * 0.5))

    local cover
    local file = np.art and SpotifyUI.coverCached(np.art)
    if not file and np.art then
        quick(SpotifyUI.downloadCover, np.art)
        file = SpotifyUI.coverCached(np.art)
    end
    if file then
        cover = ImageWidget:new{
            file = file,
            width = cover_side,
            height = cover_side,
            scale_factor = 0,
            file_do_cache = false,
        }
    else
        cover = FrameContainer:new{
            width = cover_side, height = cover_side,
            padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{
                dimen = Geom:new{ w = cover_side, h = cover_side },
                TextWidget:new{ text = "♪", face = Font:getFace("cfont", math.floor(cover_side / 3)) },
            },
        }
    end

    local state_label = ({ PLAYING = T("Now playing"), TRANSITIONING = T("Now playing"),
        PAUSED_PLAYBACK = T("Paused"), STOPPED = T("Stopped") })[np.state] or T("Now playing")
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = math.floor(h * 0.07) },
        TextWidget:new{
            text = state_label .. (np.room and np.room ~= "" and ("  ·  " .. np.room) or ""),
            face = Font:getFace("cfont", 22),
            max_width = inner_w,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(24) },
        cover,
        VerticalSpan:new{ width = Screen:scaleBySize(36) },
        TextBoxWidget:new{
            text = np.title,
            face = Font:getFace("cfont", 34),
            bold = true,
            width = inner_w,
            alignment = "center",
            height = Screen:scaleBySize(100),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(12) },
        TextBoxWidget:new{
            text = (np.artist and np.artist ~= "") and np.artist or " ",
            face = Font:getFace("cfont", 26),
            width = inner_w,
            alignment = "center",
            height = Screen:scaleBySize(70),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        TextBoxWidget:new{
            text = (np.album and np.album ~= "") and np.album or " ",
            face = Font:getFace("cfont", 20),
            width = inner_w,
            alignment = "center",
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            height = Screen:scaleBySize(56),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
    local footer = TextWidget:new{
        text = T("Kindle Music · as of %1", os.date("%H:%M", np.time or os.time())),
        face = Font:getFace("cfont", 16),
        max_width = inner_w,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }

    local bb = Blitbuffer.new(w, h, Screen.bb:getType())
    bb:fill(Blitbuffer.COLOR_WHITE)
    local gs = group:getSize()
    group:paintTo(bb, math.floor((w - gs.w) / 2), 0)
    local fs = footer:getSize()
    footer:paintTo(bb, math.floor((w - fs.w) / 2), h - fs.h - Screen:scaleBySize(24))
    group:free()
    footer:free()
    return bb
end

---------------------------------------------------------------------------
-- Live updates: scheduled wakeups at the end of each song
---------------------------------------------------------------------------

local function live_enabled()
    local plugin = SleepScreen.plugin
    return plugin and not plugin.settings:isFalse("sleep_screen")
        and not plugin.settings:isFalse("sleep_screen_live")
        and Device:isKindle() and Device.wakeup_mgr ~= nil
end

local function is_charging()
    local ok, charging = pcall(function() return Device.powerd:isCharging() end)
    return ok and charging or false
end

--- Seconds until we should look again, or nil when nothing is playing.
function SleepScreen.nextCheck(np)
    if not np or not (np.state == "PLAYING" or np.state == "TRANSITIONING") then return nil end
    local cap = is_charging() and MAX_WAIT_CHARGING or MAX_WAIT
    local wait
    if np.duration and np.duration > 0 and np.position then
        -- +5 s so the next song has started; Kindle alarms can fire up to ~10 s early
        wait = np.duration - np.position - (os.time() - (np.time or os.time())) + 5
    else
        wait = STREAM_WAIT
    end
    return math.max(MIN_WAIT, math.min(cap, wait))
end

local function unschedule()
    if Device.wakeup_mgr and SleepScreen._wake then
        Device.wakeup_mgr:removeTasks(nil, SleepScreen._wake)
    end
end

local function schedule(np)
    unschedule()
    if not live_enabled() then return end
    local wait = SleepScreen.nextCheck(np)
    if not wait then return end
    logger.info("kindlemusic: next sleep-screen update in", wait, "s")
    Device.wakeup_mgr:addTask(wait, SleepScreen._wake)
end

--- Replace the picture on the sleep screen that is currently shown.
local function repaint(np)
    local Screensaver = require("ui/screensaver")
    local UIManager = require("ui/uimanager")
    local sw = Screensaver.screensaver_widget
    if not sw or not sw[1] then return false end
    local w, h = Screen:getWidth(), Screen:getHeight()
    local img = ImageWidget:new{ image = SleepScreen.render(np, w, h), image_disposable = true, width = w, height = h }
    local old = sw[1][1]
    sw[1][1] = img
    sw.widget = img
    if old and old.free then old:free() end
    UIManager:setDirty(sw, "full")
    UIManager:forceRePaint()
    return true
end

--- Called by KOReader's WakeupMgr about 15 s after a scheduled wakeup (device still on the sleep screen).
function SleepScreen._wake()
    local UIManager = require("ui/uimanager")
    local NetworkMgr = require("ui/network/manager")
    local np = SleepScreen.now_playing
    if not np or not live_enabled() then return end
    local started = os.time()
    local function attempt()
        local Screensaver = require("ui/screensaver")
        if not Screensaver.screensaver_widget then return end -- the user woke the Kindle meanwhile
        local ok, online = pcall(NetworkMgr.isConnected, NetworkMgr)
        if not (ok and online) and os.time() - started < NETWORK_WAIT then
            UIManager:scheduleIn(1, attempt)
            return
        end
        np.time = 0 -- force a fresh read
        timeouts = { 3, 8 }
        np = refresh(np)
        timeouts = { 1, 2 }
        if np.time == 0 then
            -- no network / no answer: keep the old picture, try again later
            np.time = os.time()
            np.failures = (np.failures or 0) + 1
            logger.warn("kindlemusic: sleep-screen update failed (offline?)", np.failures)
            unschedule()
            if np.failures < 3 then
                Device.wakeup_mgr:addTask(is_charging() and MAX_WAIT_CHARGING or STREAM_WAIT, SleepScreen._wake)
            end
            return
        end
        np.failures = 0
        local okp, err = pcall(repaint, np)
        if not okp then logger.warn("kindlemusic: sleep-screen repaint failed:", err) end
        schedule(np)
    end
    attempt()
end

--- Install the Screensaver hook once per KOReader run; `plugin` is the newest plugin instance.
function SleepScreen.install(plugin)
    SleepScreen.plugin = plugin
    local Screensaver = require("ui/screensaver")
    if Screensaver._kindlemusic_orig_show then return end
    local orig_show = Screensaver.show
    Screensaver._kindlemusic_orig_show = orig_show
    Screensaver.show = function(ss, ...)
        -- only for a normal sleep (not power-off / reboot screens) with a UI to return to
        if ss.ui and (ss.prefix == nil or ss.prefix == "") then
            pcall(unschedule)
            local ok, err = pcall(function()
                local np = current()
                if not np then return end
                local w, h = Screen:getWidth(), Screen:getHeight()
                if bit.band(Screen:getRotationMode(), 1) == 1 then w, h = h, w end -- shown in portrait
                local img = SleepScreen.render(np, w, h)
                if ss.image then ss.image:free() end -- book cover prepared by setup()
                ss.image = img
                ss.image_file = nil
                ss.screensaver_type = "cover"
                ss.screensaver_background = "white"
                ss.show_message = false
                schedule(np)
            end)
            if not ok then logger.warn("kindlemusic: sleep screen failed:", err) end
        end
        return orig_show(ss, ...)
    end
end

return SleepScreen
