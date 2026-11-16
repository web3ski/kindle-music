--[[--
Sonos remote for KOReader.

Tools menu → "Kindle Music", or bind the "Kindle Music: remote" action to a gesture.

@module koplugin.kindlemusic
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local socketutil = require("socketutil")
local _ = require("gettext")
local L10n = require("l10n")
local T = L10n.T
local Screen = Device.screen

local Sonos = require("sonos")
local Spotify = require("spotify")
local SpotifyUI = require("spotifyui")
local RemoteUI = require("remoteui")
local SleepScreen = require("sleepscreen")

-- No built-in speakers: they are found by auto-discovery (subnet scan) or entered in
-- Tools → Kindle Music → set speaker IP, and stored in koreader/settings/kindlemusic.lua.
local DEFAULT_SPEAKERS = {}
local VOLUME_STEP = 5
local AUTO_REFRESH_SECONDS = 15
-- Created by the "Sonos" scriptlet on the Kindle home screen
local AUTOSTART_FLAG = "/tmp/sonos_autostart"

local STATE_LABELS = {
    PLAYING = "▶ Playing",
    PAUSED_PLAYBACK = "Paused",
    STOPPED = "Stopped",
    TRANSITIONING = "Loading…",
}

--- Run fn with short network timeouts; never throws.
local function guarded(fn, ...)
    socketutil:set_timeout(2, 5)
    local ok, a, b = pcall(fn, ...)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("Sonos: error", a)
        return nil, tostring(a)
    end
    return a, b
end

--- Like guarded(), but with long timeouts for regrouping commands that answer slowly.
local function guarded_slow(fn, ...)
    socketutil:set_timeout(5, 25)
    local ok, a, b = pcall(fn, ...)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("Sonos: error", a)
        return nil, tostring(a)
    end
    return a, b
end

local function toast(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 2 })
end

---------------------------------------------------------------------------
-- Full-screen remote widget
---------------------------------------------------------------------------

local SonosRemote = InputContainer:extend{
    plugin = nil,
    covers_fullscreen = true,
}

function SonosRemote:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.groups = self.plugin:visibleGroups()
    self.connect = self.plugin:profileGet("connect_device") -- { id=, name= } when a Spotify Connect device is selected
    self.state = nil
    self.track = {}
    self.volume = nil
    self.error = nil
    self:build()
end

function SonosRemote:currentGroup()
    local uuid = self.plugin:profileGet("last_group")
    for _, g in ipairs(self.groups) do
        if g.coordinator == uuid then return g end
        for _, m in ipairs(g.members) do
            if m.uuid == uuid then return g end
        end
    end
    return self.groups[1]
end

function SonosRemote:build()
    local width = Screen:getWidth()
    local inner_w = width - 2 * Size.padding.fullscreen
    local group = self:currentGroup()
    local S = function(v) return Screen:scaleBySize(v) end

    local title_bar = TitleBar:new{
        width = width,
        fullscreen = true,
        with_bottom_line = true,
        title = "Kindle Music",
        close_callback = function() UIManager:close(self) end,
        show_parent = self,
    }

    -- Where the music plays: up to 3 rooms (current group first) + "+N more"
    local rooms = self:roomList()
    local in_group = {}
    if group and not self.connect then
        for _, m in ipairs(group.members) do in_group[m.uuid] = true end
    end
    local room_specs = {}
    if self.connect then
        room_specs[#room_specs + 1] = { content = RemoteUI.text(self.connect.name, 18, true, math.floor(inner_w / 3) - S(8)),
            inverted = true, weight = 1.15, callback = function() self:showSpeakers() end }
    end
    local shown = 0
    for _, r in ipairs(rooms) do
        if #room_specs >= 3 then break end
        local m = r.member
        room_specs[#room_specs + 1] = {
            content = RemoteUI.text(m.name, 18, in_group[m.uuid], math.floor(inner_w / 4) - S(8)),
            inverted = in_group[m.uuid] or false,
            callback = function() self:roomTapped(r) end,
        }
        shown = shown + 1
    end
    local more = #rooms - shown
    room_specs[#room_specs + 1] = {
        content = HorizontalGroup:new{ align = "center",
            RemoteUI.text(more > 0 and T("+%1 more", more) or T("More"), 17),
            RemoteUI.icon("chevron_down", S(18)) },
        callback = function() self:showSpeakers() end,
    }
    if #rooms == 0 and not self.connect then
        room_specs = { { content = RemoteUI.text(T("Find speakers"), 18), callback = function() self:rediscover() end } }
    end
    local room_label = RemoteUI.text(T("PLAYING ON"), 13)
    local room_row = RemoteUI.row(room_specs, inner_w, S(64), self)

    -- Now playing: cover, title, artist · album, status + Like / Radio
    local track = self.track or {}
    local title_text = track.title and track.title ~= "" and track.title or "—"
    local sub_parts = {}
    if track.artist and track.artist ~= "" then table.insert(sub_parts, track.artist) end
    if track.album and track.album ~= "" then table.insert(sub_parts, track.album) end
    local status = self.error or (STATE_LABELS[self.state] and T(STATE_LABELS[self.state]) or self.state or "…")

    local has_track = track.title and track.title ~= "" and track.title ~= "—"
    local thumb_side = S(120)
    local thumb_gap = Size.padding.large * 2
    local text_w = has_track and (inner_w - thumb_side - thumb_gap) or inner_w

    local status_line
    local sp_linked = self.plugin:spotify() ~= nil
    if not self.error and has_track and track.spotify_id then
        status_line = HorizontalGroup:new{ align = "center",
            RemoteUI.text(status, 18),
            HorizontalSpan:new{ width = S(12) },
        }
        if sp_linked then
            local liked = self.liked and self.liked[track.spotify_id]
            status_line[#status_line + 1] = RemoteUI.pill(liked and "heart" or "heart_outline",
                liked and T("Liked") or T("Like"), function() self:toggleLike() end, self)
            status_line[#status_line + 1] = HorizontalSpan:new{ width = S(8) }
        end
        status_line[#status_line + 1] = RemoteUI.pill("radio", T("Radio"), function()
            self:startSpotify({ kind = "radio", track_id = track.spotify_id, name = T("Radio: %1", track.title or "") })
        end, self)
    else
        status_line = TextBoxWidget:new{ text = status, face = Font:getFace("cfont", 18), width = text_w }
    end

    local now_playing = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = title_text,
            face = Font:getFace("cfont", 30),
            bold = true,
            width = text_w,
            height = S(90),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextBoxWidget:new{
            text = #sub_parts > 0 and table.concat(sub_parts, " · ") or " ",
            face = Font:getFace("cfont", 22),
            width = text_w,
            height = S(60),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Size.span.vertical_large * 2 },
        status_line,
    }
    if has_track then
        local thumb
        local file = track.art and SpotifyUI.coverCached(track.art)
        if file then
            thumb = ImageWidget:new{
                file = file, width = thumb_side, height = thumb_side,
                scale_factor = 0, file_do_cache = false,
            }
        else
            thumb = FrameContainer:new{
                width = thumb_side, height = thumb_side, padding = 0, bordersize = 0,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = thumb_side, h = thumb_side },
                    TextWidget:new{ text = "♪", face = Font:getFace("cfont", math.floor(thumb_side / 3)) },
                },
            }
        end
        now_playing = HorizontalGroup:new{
            align = "top",
            thumb,
            HorizontalSpan:new{ width = thumb_gap },
            now_playing,
        }
    end

    -- Transport
    local is_playing = self.state == "PLAYING" or self.state == "TRANSITIONING"
    local icon_big = S(44)
    local transport = RemoteUI.row({
        { content = RemoteUI.icon("previous", icon_big), callback = function() self:command("previous") end },
        { content = RemoteUI.icon(is_playing and "pause" or "play", S(52)),
          callback = function() self:command(is_playing and "pause" or "play") end },
        { content = RemoteUI.icon("next", icon_big), callback = function() self:command("next") end },
    }, inner_w, S(90), self)

    -- Volume: − slider + number
    local multi = group and not self.connect and #group.members > 1
    local volume_row = RemoteUI.row({
        { content = RemoteUI.icon("volume_down", S(36)), weight = 0.7,
          callback = function() self:changeVolume(-VOLUME_STEP) end },
        { weight = 3.2, no_sep = true, make = function(w, h)
            return RemoteUI.Slider:new{ width = w, height = h, value = self.volume or 0, show_parent = self,
                on_change = function(v) self:setVolume(v) end }
        end },
        { content = RemoteUI.icon("volume_up", S(36)), weight = 0.7, no_sep = true,
          callback = function() self:changeVolume(VOLUME_STEP) end },
        { content = multi and VerticalGroup:new{ align = "center",
                RemoteUI.text(self.volume and tostring(self.volume) or "?", 22, true),
                HorizontalGroup:new{ align = "center",
                    RemoteUI.text(self:volTarget() and self:volTarget().name or T("All"), 13, false, S(90)),
                    RemoteUI.icon("chevron_down", S(14)) },
            } or RemoteUI.text(self.volume and tostring(self.volume) or "?", 22, true),
          weight = multi and 1.1 or 0.7,
          callback = multi and function() self:showVolumeTarget() end or nil },
    }, inner_w, S(80), self)

    -- Shuffle / repeat / sleep timer (inverted = on)
    local mode = self.mode or {}
    local rep = mode.rep or "none"
    local mode_row = RemoteUI.row({
        { content = RemoteUI.iconLabel("shuffle", T("Shuffle"), S(36), 15), inverted = mode.shuffle and true or false,
          callback = function() self:togglePlayMode("shuffle") end },
        { content = RemoteUI.iconLabel(rep == "one" and "repeat_one" or "repeat", rep == "one" and T("Repeat 1") or T("Repeat"), S(36), 15),
          inverted = rep ~= "none", callback = function() self:togglePlayMode("repeat") end },
        { content = RemoteUI.iconLabel("sleep", self.sleep_label or T("Sleep timer"), S(36), 15),
          inverted = self.sleep_label ~= nil, callback = function() self:showSleepMenu() end },
    }, inner_w, S(90), self)

    local big = 26
    local btn_h = S(76)
    local browse = {}
    if self.last_browser then
        table.insert(browse, { text = "‹ " .. (self.last_browser:topTitle() or "Spotify"), font_size = big - 6,
            height = btn_h, callback = function() self.last_browser:restore() end })
    end
    table.insert(browse, { text = "Spotify", font_size = big - 2, height = btn_h,
        callback = function() self:showSpotify() end })
    table.insert(browse, { text = T("Sonos favorites"), font_size = big - 6, height = btn_h,
        callback = function() self:showLibrary() end })
    local buttons = ButtonTable:new{
        width = inner_w,
        buttons = {
            browse,
            {
                { text = T("Refresh"), font_size = 20, callback = function() self:refresh(true) end },
                { text = T("Settings"), font_size = 20, callback = function()
                    self.plugin:showSettings(function()
                        self.groups = self.plugin:visibleGroups()
                        self:refresh(true)
                    end)
                end },
            },
        },
    }

    local gap = VerticalSpan:new{ width = S(12) }
    local function centered(w)
        return CenterContainer:new{ dimen = Geom:new{ w = width, h = w:getSize().h }, w }
    end
    local content = VerticalGroup:new{
        align = "left",
        title_bar,
        VerticalSpan:new{ width = S(10) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = Size.padding.fullscreen }, room_label },
        VerticalSpan:new{ width = S(4) },
        centered(room_row),
        VerticalSpan:new{ width = S(22) },
        centered(now_playing),
        VerticalSpan:new{ width = S(22) },
        centered(transport),
        gap,
        centered(volume_row),
        gap,
        centered(mode_row),
        gap,
        centered(buttons),
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        content,
    }
end

function SonosRemote:redraw()
    self:build()
    UIManager:setDirty(self, "ui")
end

--- Fetch state/track/volume of the current group. Returns true if UI changed.
function SonosRemote:fetch()
    if self.connect then return self:fetchConnect() end
    local group = self:currentGroup()
    if not group then return false end
    local state, err = guarded(Sonos.getState, group.ip)
    local snapshot = table.concat({ tostring(self.state), tostring(self.track.title),
        tostring(self.track.artist), tostring(self.volume), tostring(self.error) }, "|")
    if not state then
        self.error = Sonos.describeError(err)
    else
        self.error = nil
        self.state = state
        self.track = guarded(Sonos.getTrack, group.ip) or {}
        self.track.spotify_id = self.track.uri and self.track.uri:match("spotify%%3atrack%%3a(%w+)") or nil
        self:checkLiked()
        local vt = self:volTarget()
        self.volume = (vt and guarded(Sonos.getSpeakerVolume, vt.ip)) or guarded(Sonos.getVolume, group) or self.volume
        self.mode = guarded(Sonos.getPlayMode, group.ip) or self.mode
        local rem = guarded(Sonos.getSleepTimer, group.ip)
        local secs = (rem and rem ~= "") and SleepScreen.seconds(rem) or nil
        self.sleep_label = (secs and secs > 0) and T("%1 min", math.ceil(secs / 60)) or nil
        SleepScreen.update{ title = self.track.title, artist = self.track.artist, album = self.track.album,
            art = self.track.art, state = state, room = group.name, ip = group.ip,
            duration = SleepScreen.seconds(self.track.duration), position = SleepScreen.seconds(self.track.position) }
    end
    self:loadArt()
    local new_snapshot = table.concat({ tostring(self.state), tostring(self.track.title),
        tostring(self.track.artist), tostring(self.volume), tostring(self.error) }, "|")
    -- mode/timer changes alone don't force a full-screen repaint on auto refresh
    return snapshot ~= new_snapshot
end

function SonosRemote:fetchConnect()
    local before = table.concat({ tostring(self.state), tostring(self.track.title), tostring(self.volume), tostring(self.error) }, "|")
    local sp = self.plugin:spotify()
    local st, err = sp and guarded(sp.player, sp)
    if st and st.device_id == self.connect.id then
        self.error = nil
        self.state = st.is_playing and "PLAYING" or "PAUSED_PLAYBACK"
        self.track = { title = st.title, artist = st.artist, album = st.album, spotify_id = st.track_id, art = st.image }
        self:checkLiked()
        self.volume = st.volume
        self.mode = { shuffle = st.shuffle, rep = st.rep }
        SleepScreen.update{ title = st.title, artist = st.artist, album = st.album, art = st.image,
            state = self.state, room = self.connect.name, connect_id = self.connect.id,
            duration = st.duration, position = st.progress }
    elseif st or err == "none" then
        self.error = nil
        self.state = "STOPPED"
        self.track = { title = "—", artist = st and T("Now playing on: %1", tostring(st.device_name)) or T("Nothing is playing") }
    else
        self.error = Spotify.describeError(err)
    end
    local after = table.concat({ tostring(self.state), tostring(self.track.title), tostring(self.volume), tostring(self.error) }, "|")
    self:loadArt()
    return before ~= after
end

--- Download the current cover in the background (once per URL), then repaint.
function SonosRemote:loadArt()
    local url = self.track and self.track.art
    if not url or SpotifyUI.coverCached(url) then return end
    self._art_tried = self._art_tried or {}
    if self._art_tried[url] then return end
    self._art_tried[url] = true
    UIManager:scheduleIn(0.2, function()
        if self.closed then return end
        guarded(SpotifyUI.downloadCover, url)
        if self.track and self.track.art == url and SpotifyUI.coverCached(url) then self:redraw() end
    end)
end

--- Spotify Connect devices other than Sonos (TVs, computers, phones, speakers, a Raspberry Pi…).
function SonosRemote:showConnectDevices()
    local sp = self.plugin:spotify()
    if not sp then
        toast(Spotify.describeError("not_linked"))
        return
    end
    local devices, err = guarded(sp.devices, sp)
    if not devices then toast(Spotify.describeError(err)) return end
    local sonos_names = {}
    for _, g in ipairs(self.plugin.groups or {}) do
        for _, m in ipairs(g.members) do sonos_names[(m.name or ""):lower()] = true end
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local rows = {}
    for _, d in ipairs(devices) do
        if type(d) == "table" and d.id and not sonos_names[(d.name or ""):lower()] then
            local label = d.name .. "  (" .. T(({ Computer = "computer", Smartphone = "phone", Speaker = "speaker",
                TV = "TV", Tablet = "tablet", CastVideo = "Chromecast", CastAudio = "Chromecast",
                Automobile = "car", AVR = "AV receiver", STB = "set-top box" })[d.type] or (d.type or "?")) .. ")"
            if d.is_restricted then label = label .. " — " .. T("no remote control") end
            rows[#rows + 1] = { {
                text = ((self.connect and self.connect.id == d.id) and "● " or "") .. label,
                enabled = not d.is_restricted,
                callback = function()
                    UIManager:close(dlg)
                    self.connect = { id = d.id, name = d.name }
                    self.plugin:profileSet("connect_device", self.connect)
                    self.state, self.track, self.volume, self.error = nil, {}, d.volume_percent, nil
                    self:refresh(true)
                end,
            } }
        end
    end
    if #rows == 0 then
        rows[1] = { { text = T("No other Spotify devices.\nThe device must be on and have Spotify open\n(TV, computer, phone, speaker)."), enabled = false } }
    end
    rows[#rows + 1] = {
        { text = T("Refresh"), callback = function() UIManager:close(dlg); self:showConnectDevices() end },
        { text = T("Close"), callback = function() UIManager:close(dlg) end },
    }
    dlg = ButtonDialog:new{ title = T("Other devices (Spotify Connect)"), buttons = rows }
    UIManager:show(dlg)
end

function SonosRemote:refresh(force)
    if self:fetch() or force then
        self:redraw()
    end
end

function SonosRemote:scheduleAutoRefresh()
    self:unscheduleAutoRefresh()
    self._auto = function()
        self._auto = nil
        if NetworkMgr:isOnline() then self:refresh(false) end
        self:scheduleAutoRefresh()
    end
    UIManager:scheduleIn(AUTO_REFRESH_SECONDS, self._auto)
end

function SonosRemote:unscheduleAutoRefresh()
    if self._auto then
        UIManager:unschedule(self._auto)
        self._auto = nil
    end
end

function SonosRemote:selectGroup(g)
    self.connect = nil
    self.plugin:profileSet("connect_device", nil)
    self.plugin:profileSet("last_group", g.coordinator)
    self.state, self.track, self.volume, self.error = nil, {}, nil, nil
    self:refresh(true)
end

function SonosRemote:rediscover()
    self.plugin:discover(true)
    self.groups = self.plugin:visibleGroups()
    self:refresh(true)
end

--- Check once per track whether it is already in Liked Songs.
function SonosRemote:checkLiked()
    local id = self.track and self.track.spotify_id
    self.liked = self.liked or {}
    if not id or self.liked[id] ~= nil or self.like_checked == id then return end
    self.like_checked = id
    local sp = self.plugin:spotify()
    if not sp then return end
    local saved = guarded(sp.isSaved, sp, id)
    if saved ~= nil then self.liked[id] = saved end
end

--- Add the current track to Spotify Liked Songs (or remove it if it is already there).
function SonosRemote:toggleLike()
    local id = self.track and self.track.spotify_id
    local sp = self.plugin:spotify()
    if not id or not sp then return end
    self.liked = self.liked or {}
    local save = not self.liked[id]
    local ok, err = guarded(sp.saveTrack, sp, id, save)
    if not ok then toast(Spotify.describeError(err)) return end
    self.liked[id] = save
    toast(save and T("Added to Liked Songs") or T("Removed from Liked Songs"))
    self:redraw()
end

function SonosRemote:command(name)
    if self.connect then
        local sp = self.plugin:spotify()
        if not sp then return end
        local fn = ({ play = sp.resume, pause = sp.pause, next = sp.nextTrack, previous = sp.previousTrack })[name]
        local ok, err = guarded(fn, sp, self.connect.id)
        if not ok then toast(Spotify.describeError(err)) return end
        if name == "play" then self.state = "PLAYING" elseif name == "pause" then self.state = "PAUSED_PLAYBACK" end
        self:redraw()
        UIManager:scheduleIn(1.5, function() self:refresh(false) end)
        return
    end
    local group = self:currentGroup()
    if not group then return end
    local ok, err = guarded(Sonos[name], group.ip)
    if not ok then
        toast(Sonos.describeError(err))
        return
    end
    -- optimistic update, then re-read once the speaker settled
    if name == "play" then self.state = "PLAYING" elseif name == "pause" then self.state = "PAUSED_PLAYBACK" end
    self:redraw()
    UIManager:scheduleIn(1.5, function() self:refresh(false) end)
end

--- List of Sonos favorites + Sonos playlists; tap to play in the current room.
function SonosRemote:showLibrary()
    local group = self:currentGroup()
    if not group then return end
    local favorites = guarded(Sonos.browse, group.ip, "FV:2") or {}
    local playlists, err = guarded(Sonos.browse, group.ip, "SQ:")
    if not playlists and #favorites == 0 then
        toast(Sonos.describeError(err))
        return
    end
    playlists = playlists or {}
    local menu
    local item_table = {}
    local function add(prefix, entry)
        table.insert(item_table, {
            text = prefix .. (entry.title or "?"),
            callback = function()
                UIManager:close(menu)
                local ok, perr = guarded(Sonos.playItem, group, entry)
                if not ok then
                    toast(Sonos.describeError(perr))
                    return
                end
                toast("▶ " .. (entry.title or "") .. "\n" .. group.name)
                self.state = "TRANSITIONING"
                self:redraw()
                UIManager:scheduleIn(2, function() self:refresh(true) end)
            end,
        })
    end
    for _, e in ipairs(favorites) do add("★ ", e) end
    for _, e in ipairs(playlists) do add("♫ ", e) end
    if #item_table == 0 then
        UIManager:show(InfoMessage:new{
            text = T("No favorites or playlists.\n\nIn the Sonos app, add playlists (e.g. from Spotify) "
                .. "to Favorites (My Sonos) and open this list again."),
        })
        return
    end
    menu = Menu:new{
        title = T("Playlists — %1", group.name),
        item_table = item_table,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        single_line = true,
    }
    UIManager:show(menu)
end

--- Spotify browser (covers, sections, search) for the account linked to THIS Kindle.
function SonosRemote:showSpotify()
    if not self:currentGroup() then return end
    if not self.plugin:spotify() then
        UIManager:show(InfoMessage:new{
            text = T("This Kindle is not linked to Spotify.\n\nOn your computer run:\n"
                .. "python3 tools/link_spotify.py <Kindle IP>\nand sign in with your Spotify account."),
        })
        return
    end
    SpotifyUI.open{ plugin = self.plugin, remote = self }
end

--- Start Spotify playback without blocking: show the remote right away with
-- "Starting…", run the (slow) Sonos queue calls on the next UI tick.
function SonosRemote:startSpotify(item, track_list, index)
    local group = self:currentGroup()
    if not group and not self.connect then return end
    self.state = "TRANSITIONING"
    self.track = { title = T("Starting…"), artist = item.name, album = nil }
    self.error = nil
    self:redraw()
    self._play_seq = (self._play_seq or 0) + 1
    local seq = self._play_seq
    UIManager:scheduleIn(0.3, function()
        if seq ~= self._play_seq then return end -- superseded by a newer tap
        local t0 = os.clock()
        local ok, err, how, rest = self.plugin:playSpotify(group, item, track_list, index, self.connect)
        logger.info("Sonos: Spotify start took", os.clock() - t0, "cpu-s via", how)
        if not ok then
            self.track = {}
            self.state = nil
            toast(err)
            self:refresh(true)
            return
        end
        -- remaining tracks are appended in small batches so taps stay responsive
        if rest and #rest > 0 then
            local i = 0
            local function step()
                if seq ~= self._play_seq then return end
                for _ = 1, 4 do
                    i = i + 1
                    if not rest[i] then return end
                    guarded(Sonos.enqueue, group.ip, rest[i])
                end
                UIManager:scheduleIn(0.1, step)
            end
            UIManager:scheduleIn(0.5, step)
        end
        UIManager:scheduleIn(1.5, function() self:refresh(true) end)
    end)
end

--- Join one room to the coordinator, lowering it first if it's much louder than the group.
function SonosRemote:joinRoom(coord, m)
    local gv = guarded(Sonos.getSpeakerVolume, coord.ip)
    local mv = guarded(Sonos.getSpeakerVolume, m.ip)
    if gv and mv and mv > gv + 15 then
        guarded(Sonos.setSpeakerVolume, m.ip, gv)
        toast(T("%1: volume lowered %2 → %3 (to match the group)", m.name, mv, gv))
    end
    return guarded(Sonos.joinGroup, m.ip, coord.uuid)
end

--- Per-room volume inside the current group.
function SonosRemote:showRoomVolumes()
    local group = self:currentGroup()
    if not group then return end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local rows = {}
    for _, m in ipairs(group.members) do
        local v = guarded(Sonos.getSpeakerVolume, m.ip)
        local function change(d)
            UIManager:close(dlg)
            local cur = guarded(Sonos.getSpeakerVolume, m.ip) or v or 0
            guarded(Sonos.setSpeakerVolume, m.ip, cur + d)
            self.volume = guarded(Sonos.getVolume, group) or self.volume
            self:redraw()
            self:showRoomVolumes()
        end
        rows[#rows + 1] = {
            { text = "− 5", callback = function() change(-VOLUME_STEP) end },
            { text = m.name .. ": " .. (v and tostring(v) or "?"), enabled = false },
            { text = "+ 5", callback = function() change(VOLUME_STEP) end },
        }
    end
    rows[#rows + 1] = { { text = T("Done"), callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{ title = T("Room volumes in this group"), buttons = rows }
    UIManager:show(dlg)
end

--- Choose which rooms play together with the current room.
function SonosRemote:showGrouping()
    local group = self:currentGroup()
    if not group then return end
    local ButtonDialog = require("ui/widget/buttondialog")
    local coord = group.members[1]
    local in_group = {}
    for _, m in ipairs(group.members) do in_group[m.uuid] = true end
    local all = {}
    for _, g in ipairs(self.plugin.groups or {}) do
        for _, m in ipairs(g.members) do all[#all + 1] = m end
    end
    table.sort(all, function(a, b) return (a.name or "") < (b.name or "") end)
    local hidden = (self.plugin.profile and self.plugin.profile.hidden) or {}
    local dlg
    local rows = {}
    for _, m in ipairs(all) do
        if m.uuid == coord.uuid then
            rows[#rows + 1] = { { text = "☑ " .. m.name .. "  (" .. T("main") .. ")", enabled = false } }
        elseif not hidden[m.uuid] then
            local on = in_group[m.uuid]
            rows[#rows + 1] = { { text = (on and "☑ " or "☐ ") .. m.name, callback = function()
                UIManager:close(dlg)
                local ok, err
                if on then
                    ok, err = guarded(Sonos.leaveGroup, m.ip)
                else
                    ok, err = self:joinRoom(coord, m)
                end
                if not ok then toast(Sonos.describeError(err)) end
                self.plugin:refreshTopology(coord.ip)
                self.groups = self.plugin:visibleGroups()
                self.plugin:profileSet("last_group", coord.uuid)
                self:refresh(true)
                self:showGrouping()
            end } }
        end
    end
    local function after()
        self.plugin:refreshTopology(coord.ip)
        self.groups = self.plugin:visibleGroups()
        self.plugin:profileSet("last_group", coord.uuid)
        self:refresh(true)
    end
    table.insert(rows, 1, {
        { text = T("All rooms"), callback = function()
            UIManager:close(dlg)
            for _, m in ipairs(all) do
                if m.uuid ~= coord.uuid and not in_group[m.uuid] and not hidden[m.uuid] then self:joinRoom(coord, m) end
            end
            after()
        end },
        { text = T("Ungroup"), callback = function()
            UIManager:close(dlg)
            for _, m in ipairs(group.members) do
                if m.uuid ~= coord.uuid then guarded(Sonos.leaveGroup, m.ip) end
            end
            after()
        end },
    })
    if #group.members > 1 then
        rows[#rows + 1] = { { text = T("Volume of each room…"), callback = function()
            UIManager:close(dlg)
            self:showRoomVolumes()
        end } }
    end
    rows[#rows + 1] = { { text = T("Done"), callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{
        title = T("Playing together with: %1\nTick the rooms that should play the same music.", coord.name),
        buttons = rows,
    }
    UIManager:show(dlg)
end

function SonosRemote:togglePlayMode(which)
    local group = self:currentGroup()
    if not group and not self.connect then return end
    local m = self.mode or { shuffle = false, rep = "none" }
    local shuffle, rep = m.shuffle, m.rep
    if which == "shuffle" then
        shuffle = not shuffle
    else
        rep = ({ none = "all", all = "one", one = "none" })[rep] or "none"
    end
    local ok, err
    if self.connect then
        local sp = self.plugin:spotify()
        if which == "shuffle" then ok, err = guarded(sp.setShuffle, sp, self.connect.id, shuffle)
        else ok, err = guarded(sp.setRepeat, sp, self.connect.id, rep) end
        if not ok then toast(Spotify.describeError(err)) return end
    else
        ok, err = guarded(Sonos.setPlayMode, group.ip, shuffle, rep)
    end
    if not ok then toast(Sonos.describeError(err)) return end
    self.mode = { shuffle = shuffle, rep = rep }
    self:redraw()
end

--- Sleep timer menu: off / 15 / 30 / 60 / 90 min / end of this track.
function SonosRemote:showSleepMenu()
    if self.connect then toast(T("The sleep timer only works with Sonos speakers")) return end
    local group = self:currentGroup()
    if not group then return end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local function set(seconds, label)
        UIManager:close(dlg)
        local ok, err = guarded(Sonos.setSleepTimerSeconds, group.ip, seconds)
        if not ok then toast(Sonos.describeError(err)) return end
        self.sleep_label = seconds > 0 and T("%1 min", math.ceil(seconds / 60)) or nil
        toast(label)
        self:redraw()
    end
    local rows = {}
    if self.sleep_label then
        rows[#rows + 1] = { { text = T("Turn off"), callback = function() set(0, T("Sleep timer off")) end } }
    end
    for _, m in ipairs({ 15, 30, 60, 90 }) do
        rows[#rows + 1] = { { text = T("%1 min", m), callback = function()
            set(m * 60, T("Music will stop in %1 min", m))
        end } }
    end
    local track = self.track or {}
    local dur, pos = SleepScreen.seconds(track.duration), SleepScreen.seconds(track.position)
    if dur and pos and dur > pos then
        local left = dur - pos + 2
        rows[#rows + 1] = { { text = T("End of this track"), callback = function()
            set(left, T("Music will stop after this track"))
        end } }
    end
    rows[#rows + 1] = { { text = T("Close"), callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{
        title = self.sleep_label and T("Sleep timer · %1 left", self.sleep_label) or T("Sleep timer"),
        buttons = rows,
    }
    UIManager:show(dlg)
end

--- Set the volume to an absolute value (from the slider).
function SonosRemote:setVolume(v)
    logger.info("KindleMusic: slider volume", v, "was", self.volume)
    if self.connect then
        local sp = self.plugin:spotify()
        if not sp then return end
        local ok, err = guarded(sp.setVolume, sp, self.connect.id, v)
        if not ok then toast(Spotify.describeError(err)) return end
        self.volume = v
        self:redraw()
        return
    end
    local group = self:currentGroup()
    if not group then return end
    local t = self:volTarget()
    if t then
        local ok, err = guarded(Sonos.setSpeakerVolume, t.ip, v)
        if not ok then toast(Sonos.describeError(err)) return end
        self.volume = math.max(0, math.min(100, v))
        return self:redraw()
    end
    local vol, err = guarded(Sonos.setVolume, group, v)
    if not vol then toast(Sonos.describeError(err)) return end
    self.volume = vol
    self:redraw()
end

--- All visible rooms: rooms of the current group first, then the rest by name.
function SonosRemote:roomList()
    local hidden = (self.plugin.profile and self.plugin.profile.hidden) or {}
    local current = (not self.connect) and self:currentGroup() or nil
    local first, rest = {}, {}
    for _, g in ipairs(self.plugin.groups or self.groups or {}) do
        for _, m in ipairs(g.members) do
            if not hidden[m.uuid] then
                local r = { member = m, group = g }
                if current and g.coordinator == current.coordinator then first[#first + 1] = r
                else rest[#rest + 1] = r end
            end
        end
    end
    table.sort(rest, function(a, b) return (a.member.name or "") < (b.member.name or "") end)
    for _, r in ipairs(rest) do first[#first + 1] = r end
    return first
end

-- Sonos publishes the new grouping 1-3 s after the command, so read it again a bit later.
function SonosRemote:afterRegroup(seed_ip, focus_uuid)
    if focus_uuid then self.plugin:profileSet("last_group", focus_uuid) end
    local function reload()
        if self.closed then return end
        self.plugin:refreshTopology(seed_ip)
        self.groups = self.plugin:visibleGroups()
        self.state, self.volume = nil, nil
        self:refresh(true)
    end
    reload()
    UIManager:scheduleIn(3, reload)
end

--- Busy message while speakers are regrouped (taps on rooms are ignored meanwhile).
function SonosRemote:busy(text)
    self:unbusy()
    self._busy = InfoMessage:new{ text = text, dismissable = false }
    UIManager:show(self._busy)
    UIManager:forceRePaint()
end

function SonosRemote:unbusy()
    if self._busy then
        UIManager:close(self._busy)
        self._busy = nil
    end
end

local function group_of(groups, uuid)
    for _, g in ipairs(groups or {}) do
        for _, x in ipairs(g.members) do
            if x.uuid == uuid then return g end
        end
    end
end

--- Poll the Sonos topology (via ip) until cond(groups) is true or `timeout` seconds pass.
function SonosRemote:waitTopology(ip, cond, timeout, cb)
    local deadline = os.time() + timeout
    local function check()
        if self.closed then return end
        local groups = guarded(Sonos.getGroups, ip)
        if groups then
            local desc = {}
            for _, g in ipairs(groups) do
                local names = {}
                for _, x in ipairs(g.members) do names[#names + 1] = x.name end
                desc[#desc + 1] = table.concat(names, "+")
            end
            logger.info("KindleMusic: topology", table.concat(desc, " | "))
        end
        if groups and cond(groups) then return cb(true) end
        if os.time() >= deadline then return cb(false) end
        UIManager:scheduleIn(0.6, check)
    end
    UIManager:scheduleIn(0.5, check)
end

--- Finish a regroup: close the busy message, reload topology and focus on `uuid`.
function SonosRemote:regroupDone(ip, uuid, failed_text)
    self:unbusy()
    if failed_text then toast(failed_text) end
    self:afterRegroup(ip, uuid)
end

--- Room shown in the main volume control (nil = the whole group).
function SonosRemote:volTarget()
    local group = self:currentGroup()
    if not self.vol_target or self.connect or not group or #group.members < 2 then return nil end
    for _, x in ipairs(group.members) do
        if x.uuid == self.vol_target then return x end
    end
    self.vol_target = nil
end

--- Choose what the main volume slider controls: the whole group or one room.
function SonosRemote:showVolumeTarget()
    local group = self:currentGroup()
    if not group or #group.members < 2 then return end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local cur = self:volTarget()
    local function pick(uuid)
        UIManager:close(dlg)
        self.vol_target = uuid
        local t = self:volTarget()
        self.volume = (t and guarded(Sonos.getSpeakerVolume, t.ip)) or guarded(Sonos.getVolume, group) or self.volume
        self:redraw()
    end
    local rows = { { { text = (cur and "" or "● ") .. T("All rooms (group)"), callback = function() pick(nil) end } } }
    for _, x in ipairs(group.members) do
        rows[#rows + 1] = { { text = ((cur and cur.uuid == x.uuid) and "● " or "") .. x.name,
            callback = function() pick(x.uuid) end } }
    end
    dlg = ButtonDialog:new{ title = T("Volume slider controls"), buttons = rows }
    UIManager:show(dlg)
end

--- Speaker card: its own volume slider, plus group actions.
local SpeakerDialog = InputContainer:extend{
    remote = nil,
    member = nil,
    actions = nil,
    modal = true,
}

function SpeakerDialog:init()
    self.volume = guarded(Sonos.getSpeakerVolume, self.member.ip)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:build()
end

function SpeakerDialog:build()
    local S = function(v) return Screen:scaleBySize(v) end
    local w = math.floor(Screen:getWidth() * 0.88)
    local inner = w - 2 * Size.padding.large * 2
    local vol_row = RemoteUI.row({
        { content = RemoteUI.icon("volume_down", S(32)), weight = 0.7,
          callback = function() self:setVolume((self.volume or 0) - VOLUME_STEP) end },
        { weight = 3.2, no_sep = true, make = function(cw, ch)
            return RemoteUI.Slider:new{ width = cw, height = ch, value = self.volume or 0, show_parent = self,
                on_change = function(v) self:setVolume(v) end }
        end },
        { content = RemoteUI.icon("volume_up", S(32)), weight = 0.7, no_sep = true,
          callback = function() self:setVolume((self.volume or 0) + VOLUME_STEP) end },
        { content = RemoteUI.text(self.volume and tostring(self.volume) or "?", 22, true), weight = 0.7 },
    }, inner, S(76), self)
    local rows = {}
    for _, a in ipairs(self.actions or {}) do
        rows[#rows + 1] = { { text = a.text, callback = function()
            UIManager:close(self)
            a.callback()
        end } }
    end
    rows[#rows + 1] = { { text = T("Close"), callback = function() UIManager:close(self) end } }
    local buttons = ButtonTable:new{ width = inner, buttons = rows, show_parent = self }
    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Size.padding.large * 2,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = self.member.name, face = Font:getFace("cfont", 26), bold = true, max_width = inner },
            VerticalSpan:new{ width = S(6) },
            TextWidget:new{ text = T("Volume of this room"), face = Font:getFace("cfont", 16), max_width = inner },
            VerticalSpan:new{ width = S(10) },
            vol_row,
            VerticalSpan:new{ width = S(16) },
            buttons,
        },
    }
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h }, self.frame }
end

function SpeakerDialog:setVolume(v)
    v = math.max(0, math.min(100, math.floor(v)))
    local ok, err = guarded(Sonos.setSpeakerVolume, self.member.ip, v)
    if not ok then toast(Sonos.describeError(err)) return end
    self.volume = v
    self:build()
    UIManager:setDirty(self, "ui", self.frame.dimen)
end

function SpeakerDialog:onTapOutside(_, ges)
    if self.frame.dimen and self.frame.dimen:contains(ges.pos) then return true end
    UIManager:close(self)
    return true
end

function SpeakerDialog:onShow()
    UIManager:setDirty(self, "ui")
end

function SpeakerDialog:onCloseWidget()
    UIManager:setDirty(nil, "ui")
    local r = self.remote
    if r and not r.closed then
        local group = r:currentGroup()
        local t = r:volTarget()
        if group then
            r.volume = (t and guarded(Sonos.getSpeakerVolume, t.ip)) or guarded(Sonos.getVolume, group) or r.volume
        end
        r:redraw()
    end
end

function SonosRemote:showSpeakerDialog(m, group, actions)
    UIManager:show(SpeakerDialog:new{ remote = self, member = m, actions = actions })
end

--- Tap on a room: play there, add it to the group, or take it out of the group.
function SonosRemote:roomTapped(r)
    if self._busy then return end
    local m = r.member
    if self.connect then
        return self:selectGroup(r.group)
    end
    local group = self:currentGroup()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local function close() UIManager:close(dlg) end
    local rows = {}
    local in_group = false
    for _, x in ipairs(group and group.members or {}) do
        if x.uuid == m.uuid then in_group = true end
    end
    local not_confirmed = T("The speakers did not confirm the change. Check the Sonos app.")
    if in_group then
        local actions = {}
        local coord = group.members[1]
        local others = {}
        for _, x in ipairs(group.members) do
            if x.uuid ~= m.uuid then others[#others + 1] = x end
        end
        if #group.members > 1 then
        actions[#actions + 1] = { text = T("Remove from group"), callback = function()
            self:busy(T("Removing %1 from the group…", m.name))
            local ok, err
            if m.uuid == coord.uuid then
                -- the leader leaves: hand the music to the next room first
                ok, err = guarded_slow(Sonos.delegateTo, coord.ip, others[1].uuid, false)
            else
                ok, err = guarded_slow(Sonos.leaveGroup, m.ip)
            end
            logger.info("KindleMusic: remove from group", m.name, ok and "ok" or tostring(err))
            if not ok and tostring(err):match("^upnp:") then
                return self:regroupDone(others[1].ip, others[1].uuid, Sonos.describeError(err))
            end
            self:waitTopology(others[1].ip, function(gs)
                local g = group_of(gs, m.uuid)
                return g and #g.members == 1
            end, 8, function(confirmed)
                self:regroupDone(others[1].ip, others[1].uuid, not confirmed and not_confirmed or nil)
            end)
        end }
        actions[#actions + 1] = { text = T("Play only here"), callback = function()
            self:busy(T("Switching to %1…", m.name))
            -- everyone except this room and the leader leaves
            for _, x in ipairs(others) do
                if x.uuid ~= coord.uuid then guarded_slow(Sonos.leaveGroup, x.ip) end
            end
            if coord.uuid == m.uuid then
                return self:waitTopology(m.ip, function(gs)
                    local g = group_of(gs, m.uuid)
                    return g and #g.members == 1
                end, 8, function(confirmed)
                    self:regroupDone(m.ip, m.uuid, not confirmed and not_confirmed or nil)
                end)
            end
            local ok, err = guarded_slow(Sonos.delegateTo, coord.ip, m.uuid, false)
            logger.info("KindleMusic: play only here, delegate result", ok and "ok" or tostring(err))
            if not ok and tostring(err):match("^upnp:") then
                return self:regroupDone(m.ip, coord.uuid, Sonos.describeError(err))
            end
            self:waitTopology(m.ip, function(gs)
                local g = group_of(gs, m.uuid)
                return g and g.coordinator == m.uuid and #g.members == 1
            end, 15, function(confirmed)
                self:regroupDone(m.ip, m.uuid, not confirmed and not_confirmed or nil)
            end)
        end }
        end
        return self:showSpeakerDialog(m, group, actions)
    else
        local playing = self.state == "PLAYING" or self.state == "TRANSITIONING"
        if not group or not playing then
            return self:selectGroup(r.group)
        end
        local coord = group.members[1]
        local function join_then(after)
            local ok, err = self:joinRoom(coord, m)
            logger.info("KindleMusic: join", m.name, "->", coord.name, ok and "ok" or tostring(err))
            if not ok then return self:regroupDone(coord.ip, coord.uuid, Sonos.describeError(err)) end
            self:waitTopology(coord.ip, function(gs)
                local g = group_of(gs, m.uuid)
                return g and g.coordinator == coord.uuid
            end, 8, function(confirmed)
                if not confirmed then return self:regroupDone(coord.ip, coord.uuid, not_confirmed) end
                after()
            end)
        end
        rows[#rows + 1] = { { text = T("Play here instead (move the music)"), callback = function()
            close()
            self:busy(T("Moving the music to %1…", m.name))
            -- 1) other rooms of the old group leave, 2) the new room joins,
            -- 3) the old leader hands the music over to it and leaves.
            for _, x in ipairs(group.members) do
                if x.uuid ~= coord.uuid then guarded_slow(Sonos.leaveGroup, x.ip) end
            end
            join_then(function()
                logger.info("KindleMusic: move music", coord.name, "->", m.name, ": delegating")
                local ok, err = guarded_slow(Sonos.delegateTo, coord.ip, m.uuid, false)
                logger.info("KindleMusic: delegate result", ok and "ok" or tostring(err))
                if not ok and tostring(err):match("^upnp:") then
                    -- refused: keep both rooms playing rather than stopping the music
                    return self:regroupDone(coord.ip, coord.uuid, Sonos.describeError(err))
                end
                -- ok, or no answer in time: the hand-over may still be going on, so watch the topology
                self:waitTopology(m.ip, function(gs)
                    local g = group_of(gs, m.uuid)
                    return g and g.coordinator == m.uuid and #g.members == 1
                end, 15, function(confirmed)
                    logger.info("KindleMusic: move confirmed", confirmed)
                    self:regroupDone(m.ip, m.uuid, not confirmed and not_confirmed or nil)
                end)
            end)
        end } }
        rows[#rows + 1] = { { text = T("Add to group (play together)"), callback = function()
            close()
            self:busy(T("Adding %1 to the group…", m.name))
            join_then(function() self:regroupDone(coord.ip, coord.uuid) end)
        end } }
        rows[#rows + 1] = { { text = T("Control this room"), callback = function()
            close()
            self:selectGroup(r.group)
        end } }
    end
    rows[#rows + 1] = { { text = T("Cancel"), callback = close } }
    dlg = ButtonDialog:new{ title = m.name, buttons = rows }
    UIManager:show(dlg)
end

--- Every room (ticked = in the current group) and the Spotify Connect devices.
function SonosRemote:showSpeakers()
    local ButtonDialog = require("ui/widget/buttondialog")
    local group = (not self.connect) and self:currentGroup() or nil
    local in_group = {}
    for _, x in ipairs(group and group.members or {}) do in_group[x.uuid] = true end
    local dlg
    local rows = {}
    for _, r in ipairs(self:roomList()) do
        rows[#rows + 1] = { { text = (in_group[r.member.uuid] and "☑  " or "☐  ") .. r.member.name, callback = function()
            UIManager:close(dlg)
            self:roomTapped(r)
        end } }
    end
    rows[#rows + 1] = { { text = (self.connect and "● " .. self.connect.name .. " · " or "") .. T("Other devices (Spotify)…"),
        callback = function()
            UIManager:close(dlg)
            self:showConnectDevices()
        end } }
    rows[#rows + 1] = {
        { text = T("Find speakers"), callback = function() UIManager:close(dlg); self:rediscover() end },
        { text = T("Close"), callback = function() UIManager:close(dlg) end },
    }
    dlg = ButtonDialog:new{ title = T("Speakers"), buttons = rows }
    UIManager:show(dlg)
end

function SonosRemote:changeVolume(delta)
    if self.connect then
        local sp = self.plugin:spotify()
        local v = (self.volume or 50) + delta
        local ok, err = guarded(sp.setVolume, sp, self.connect.id, v)
        if not ok then toast(Spotify.describeError(err)) return end
        self.volume = math.max(0, math.min(100, v))
        self:redraw()
        return
    end
    local group = self:currentGroup()
    if not group then return end
    local t = self:volTarget()
    if t then
        local cur = self.volume or guarded(Sonos.getSpeakerVolume, t.ip) or 0
        return self:setVolume(cur + delta)
    end
    local vol, err = guarded(Sonos.changeVolume, group, delta)
    if not vol then
        toast(Sonos.describeError(err))
        return
    end
    self.volume = vol
    self:redraw()
end

function SonosRemote:onShow()
    self.closed = false
    SleepScreen.remote_open = true
    self:refresh(true)
    self:scheduleAutoRefresh()
    return true
end

function SonosRemote:onCloseWidget()
    self.closed = true
    SleepScreen.remote_open = false
    self:unscheduleAutoRefresh()
    UIManager:setDirty(nil, "ui")
    if self.autostart then
        -- Launched from the home-screen scriptlet: offer to go straight back to the Kindle UI
        UIManager:nextTick(function()
            UIManager:show(ConfirmBox:new{
                text = T("Go back to the Kindle home screen?"),
                ok_text = T("Exit"),
                cancel_text = T("Stay in KOReader"),
                ok_callback = function()
                    UIManager:broadcastEvent(Event:new("Exit"))
                end,
            })
        end)
    end
end

-- Pause auto-refresh while the device sleeps
function SonosRemote:onSuspend() self:unscheduleAutoRefresh() end
function SonosRemote:onResume() self:scheduleAutoRefresh() end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------

local SonosPlugin = WidgetContainer:extend{
    name = "kindlemusic",
    is_doc_only = false,
}

function SonosPlugin:init()
    -- crash.log is block-buffered: write our lines out right away so logs taken
    -- just after a problem contain it
    pcall(function() io.stdout:setvbuf("line") end)
    local settings_dir = DataStorage:getSettingsDir()
    local settings_file = settings_dir .. "/kindlemusic.lua"
    -- one-time migration from the old plugin name (sonos.koplugin → settings/sonos.lua)
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(settings_file, "mode") and lfs.attributes(settings_dir .. "/sonos.lua", "mode") then
        local old = LuaSettings:open(settings_dir .. "/sonos.lua")
        local new = LuaSettings:open(settings_file)
        for k, v in pairs(old.data or {}) do new:saveSetting(k, v) end
        new:flush()
        logger.info("kindlemusic: migrated settings from sonos.lua")
    end
    self.settings = LuaSettings:open(settings_file)
    L10n.setLanguage(self.settings:readSetting("language") or "en")
    SleepScreen.install(self)
    -- Spotify accounts linked to this Kindle (one file per account, written by tools/link_spotify.py)
    self:loadSpotifyAccounts()
    math.randomseed(os.time())
    if not self.settings:has("speakers") then
        self.settings:saveSetting("speakers", {})
        self.settings:flush()
    end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:checkAutostart()
end

--- If the home-screen scriptlet launched us, open the remote right away.
function SonosPlugin:checkAutostart()
    local lfs = require("libs/libkoreader-lfs")
    local mtime = lfs.attributes(AUTOSTART_FLAG, "modification")
    if not mtime then return end
    os.remove(AUTOSTART_FLAG)
    -- ignore a stale flag (e.g. KOReader was already running when the scriptlet was tapped)
    if os.time() - mtime > 120 then return end
    UIManager:nextTick(function()
        self:showRemote(true)
    end)
end

local SPOTIFY_ACCOUNTS_DIR = DataStorage:getSettingsDir() .. "/sonos_spotify_accounts"

--- Load all linked Spotify accounts; self.spotify_settings = the active account's settings.
function SonosPlugin:loadSpotifyAccounts()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(SPOTIFY_ACCOUNTS_DIR, "mode") ~= "directory" then
        lfs.mkdir(SPOTIFY_ACCOUNTS_DIR)
    end
    -- migrate the single-account file from v0.3
    local old = DataStorage:getSettingsDir() .. "/sonos_spotify.lua"
    if lfs.attributes(old, "mode") == "file" then
        local o = LuaSettings:open(old)
        local id = o:readSetting("account_id")
        if id and o:readSetting("refresh_token") then
            local target = SPOTIFY_ACCOUNTS_DIR .. "/" .. id .. ".lua"
            if lfs.attributes(target, "mode") ~= "file" then os.rename(old, target) else os.remove(old) end
        end
    end
    self.spotify_accounts = {}
    for name in lfs.dir(SPOTIFY_ACCOUNTS_DIR) do
        local id = name:match("^(.+)%.lua$")
        if id and not name:match("%.old$") then
            local st = LuaSettings:open(SPOTIFY_ACCOUNTS_DIR .. "/" .. name)
            if st:readSetting("refresh_token") then
                table.insert(self.spotify_accounts, {
                    id = st:readSetting("account_id") or id,
                    name = st:readSetting("account_name") or id,
                    file = SPOTIFY_ACCOUNTS_DIR .. "/" .. name,
                    settings = st,
                })
            end
        end
    end
    table.sort(self.spotify_accounts, function(a, b) return a.name < b.name end)
    local active_id = self.settings:readSetting("spotify_active")
    local active = self.spotify_accounts[1]
    for _, acc in ipairs(self.spotify_accounts) do
        if acc.id == active_id then active = acc end
    end
    self.spotify_active = active
    -- empty in-memory settings when nothing is linked (never flushed)
    self.spotify_settings = active and active.settings or LuaSettings:open(SPOTIFY_ACCOUNTS_DIR .. "/.none")
    self._spotify = nil
end

function SonosPlugin:setActiveSpotify(id)
    self.settings:saveSetting("spotify_active", id)
    self.settings:flush()
    self:loadSpotifyAccounts()
end

function SonosPlugin:removeSpotifyAccount(id)
    for _, acc in ipairs(self.spotify_accounts or {}) do
        if acc.id == id then os.remove(acc.file) end
    end
    self:loadSpotifyAccounts()
end

--- Spotify client for the active account linked to this Kindle (nil if not linked).
function SonosPlugin:spotify()
    local st = self.spotify_settings
    local client_id = st:readSetting("client_id")
    local refresh_token = st:readSetting("refresh_token")
    if not client_id or not refresh_token then return nil end
    if not self._spotify or self._spotify.client_id ~= client_id or self._spotify_settings ~= st then
        self._spotify_settings = st
        self._spotify = Spotify.new{
            client_id = client_id,
            refresh_token = refresh_token,
            on_token_update = function(new_token)
                st:saveSetting("refresh_token", new_token)
                st:flush()
            end,
        }
    end
    return self._spotify
end

local function find_device(devices, room)
    room = room:lower()
    for _, d in ipairs(devices or {}) do
        if type(d) == "table" and d.name and d.name:lower() == room and not d.is_restricted then
            return d
        end
    end
end

--- Start Spotify content on a Sonos group.
-- item.kind: "playlist"/"album" (context), "track" (optionally inside item.context_uri at item.offset),
-- "liked" (liked songs), "tracks" (track_list from index).
-- Order (play_mode "auto"): Sonos itself first (works even when Spotify can't see the speaker),
-- Spotify Connect as fallback. Returns ok, err, how, rest_entries (tracks still to enqueue).
function SonosPlugin:playSpotify(group, item, track_list, index, connect_device)
    local sp = self:spotify()
    if not sp then return nil, Spotify.describeError("not_linked") end
    local mode = self.spotify_settings:readSetting("play_mode") or "auto" -- auto | connect | sonos

    -- Resolve what to play
    local context_uri, offset, track_uris
    if item.kind == "liked" then
        local uris = guarded(sp.likedTrackUris, sp, 50)
        if not uris or #uris == 0 then return nil, T("No liked songs") end
        track_uris, offset = uris, 1
    elseif item.kind == "tracks" or track_list then
        track_uris = {}
        for _, t in ipairs(track_list or {}) do track_uris[#track_uris + 1] = t.uri end
        offset = index or 1
    elseif item.kind == "track" and item.context_uri then
        context_uri, offset = item.context_uri, item.offset
    elseif item.kind == "track" then
        track_uris, offset = { item.uri }, 1
    elseif item.kind == "radio" then
        -- handled in via_sonos (Sonos-native Spotify radio); Connect has no radio API
        track_uris = nil
    else
        context_uri = item.uri
    end

    local function via_sonos()
        -- which Spotify account (serial) inside this Sonos system: set in Settings, else auto-detect
        local acc = self.spotify_active and self.spotify_active.id
        local sn = self.profile and self.profile.spotify_sn and acc and self.profile.spotify_sn[acc]
        if not sn then
            sn = self.profile and self.profile.spotify_sn_auto
            if not sn then
                local serials = guarded(Sonos.spotifySerials, group.ip) or {}
                sn = serials[1] or 1
                if self.profile then self:profileSet("spotify_sn_auto", sn) end
            end
        end
        if item.kind == "radio" then
            local entry = item.artist_id and Sonos.spotifyRadioEntry("artist", item.artist_id, item.name, sn)
                or Sonos.spotifyRadioEntry("track", item.track_id, item.name, sn)
            local ok, err = guarded(Sonos.playItem, group, entry)
            if not ok then return nil, Sonos.describeError(err) end
            return true
        end
        if context_uri then
            local entry = Sonos.spotifyEntry(context_uri, item.name, sn)
            if not entry then return nil, T("Unsupported content type") end
            local ok, err = guarded(Sonos.playItem, group, entry, function(ip)
                -- set mode before Play so the first song is already random when shuffling
                if item.shuffle then
                    Sonos.setPlayMode(ip, true, "none")
                    if item.total and item.total > 1 then Sonos.seekTrack(ip, math.random(1, item.total)) end
                elseif offset and offset > 1 then
                    Sonos.seekTrack(ip, offset)
                end
            end)
            if not ok then return nil, Sonos.describeError(err) end
            return true
        end
        -- list of tracks: start from `offset`, keep earlier tracks at the end (like Spotify)
        local ordered = {}
        for i = offset, #track_uris do ordered[#ordered + 1] = track_uris[i] end
        for i = 1, offset - 1 do ordered[#ordered + 1] = track_uris[i] end
        local entries = {}
        for _, u in ipairs(ordered) do
            local e = Sonos.spotifyEntry(u, nil, sn)
            if e then entries[#entries + 1] = e end
        end
        if item.shuffle then
            for i = #entries, 2, -1 do
                local j = math.random(1, i)
                entries[i], entries[j] = entries[j], entries[i]
            end
        end
        local ok, err = guarded(Sonos.playTracks, group, entries, true)
        if not ok then return nil, Sonos.describeError(err) end
        local rest = {}
        for i = 2, #entries do rest[#rest + 1] = entries[i] end
        return true, nil, rest
    end

    local function via_connect()
        local room = group.members[1] and group.members[1].name or group.name
        local dev = find_device(guarded(sp.devices, sp), room)
        if not dev then return nil, T("Spotify can't see the speaker “%1”", room) end
        local ok, err = guarded(sp.play, sp, dev.id, context_uri, track_uris, offset)
        if not ok then return nil, Spotify.describeError(err) end
        return true
    end

    if connect_device then
        if item.kind == "radio" then
            return nil, T("Radio only works on Sonos speakers (Spotify doesn't offer radio through its API)")
        end
        if item.shuffle then guarded(sp.setShuffle, sp, connect_device.id, true) end
        local ok, err = guarded(sp.play, sp, connect_device.id, context_uri, track_uris,
            (not item.shuffle) and offset or nil)
        if not ok then return nil, Spotify.describeError(err) end
        return true, nil, connect_device.name
    end
    if item.kind == "radio" then
        local ok, err = via_sonos()
        return ok, err, "Sonos"
    end
    if mode == "connect" then
        local ok, err = via_connect()
        return ok, err, "Spotify Connect"
    end
    local ok, err, rest = via_sonos()
    if ok then return true, nil, "Sonos", rest end
    if mode == "sonos" then return nil, err end
    local ok2, err2 = via_connect()
    if ok2 then return true, nil, "Spotify Connect" end
    logger.warn("Sonos: Spotify playback failed:", err, err2)
    return nil, err
end

--- Pick the active Spotify account / remove one / how to add one.
function SonosPlugin:showSpotifyAccounts()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}
    for _, acc in ipairs(self.spotify_accounts or {}) do
        local is_active = self.spotify_active and acc.id == self.spotify_active.id
        table.insert(buttons, {
            { text = (is_active and "● " or "") .. acc.name, callback = function()
                UIManager:close(dialog)
                self:setActiveSpotify(acc.id)
                toast(T("Active Spotify account: %1", acc.name))
            end },
            { text = T("Remove"), callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = T("Remove the Spotify account “%1” from this Kindle?\n\n"
                        .. "You can also revoke access at spotify.com → Account → Apps.", acc.name),
                    ok_text = T("Remove"),
                    ok_callback = function() self:removeSpotifyAccount(acc.id) end,
                })
            end },
        })
    end
    table.insert(buttons, { { text = T("+ Add account…"), callback = function()
        UIManager:close(dialog)
        UIManager:show(InfoMessage:new{
            text = T("To add a Spotify account to this Kindle, run on your computer:\n\n"
                .. "python3 tools/link_spotify.py <Kindle IP>\n\n"
                .. "and sign in with that account. The account must be added in the Spotify dashboard "
                .. "(User Management, max. 5 people), and for playback through Sonos also in the Sonos app.\n"
                .. "Then restart KOReader."),
        })
    end } })
    dialog = ButtonDialog:new{
        title = #buttons > 1 and T("Spotify accounts on this Kindle") or T("No linked Spotify accounts"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function SonosPlugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("sonos_remote", {
        category = "none", event = "ShowSonosRemote", title = _("Kindle Music: remote"), general = true,
    })
end

--- Build group list from topology (asks known speakers in turn), falling
-- back to treating each configured speaker as its own group.
--- Current Wi-Fi: { ssid=, bssid=, ip=, prefix="a.b.c." } (best effort).
function SonosPlugin:networkInfo()
    local info = {}
    local f = io.popen("wpa_cli -i wlan0 status 2>/dev/null")
    if f then
        for line in f:lines() do
            local k, v = line:match("^([%w_]+)=(.*)$")
            if k == "ssid" then info.ssid = v
            elseif k == "bssid" then info.bssid = v
            elseif k == "ip_address" then info.ip = v end
        end
        f:close()
    end
    if not info.ip then
        f = io.popen("ip -4 addr show wlan0 2>/dev/null")
        if f then
            local out = f:read("*a") or ""
            f:close()
            info.ip = out:match("inet (%d+%.%d+%.%d+%.%d+)")
        end
    end
    info.prefix = info.ip and info.ip:match("^(%d+%.%d+%.%d+%.)") or nil
    return info
end

--- Profiles = one per Sonos system (household), stored in kindlemusic.lua settings.
function SonosPlugin:profiles()
    return self.settings:readSetting("profiles") or {}
end

function SonosPlugin:profileGet(key)
    local p = self.profile
    if p then return p[key] end
    return self.settings:readSetting(key) -- pre-profile settings
end

function SonosPlugin:profileSet(key, value)
    if self.profile then
        self.profile[key] = value
        local all = self:profiles()
        all[self.profile.household] = self.profile
        self.settings:saveSetting("profiles", all)
    else
        self.settings:saveSetting(key, value)
    end
    self.settings:flush()
end

local function groups_from_speakers(speakers)
    local groups = {}
    for _, sp in ipairs(speakers or {}) do
        table.insert(groups, { coordinator = sp.uuid or sp.ip, ip = sp.ip, name = sp.name,
            members = { { uuid = sp.uuid or sp.ip, name = sp.name, ip = sp.ip } } })
    end
    return groups
end

--- Discover the Sonos system on the network the Kindle is on now.
-- 1) known speakers of a profile seen on this Wi-Fi, 2) any known speaker in our subnet,
-- 3) parallel scan of the /24 for port 1400. Identifies the system by household ID and
-- creates/updates its profile automatically.
function SonosPlugin:discover(verbose)
    local net = self:networkInfo()
    self.network = net
    local profiles = self:profiles()
    local candidates, seen = {}, {}
    local function add(ip)
        if ip and not seen[ip] and (not net.prefix or ip:sub(1, #net.prefix) == net.prefix) then
            seen[ip] = true
            candidates[#candidates + 1] = ip
        end
    end
    for _, p in pairs(profiles) do
        if net.ssid and p.ssid == net.ssid then
            for _, sp in ipairs(p.speakers or {}) do add(sp.ip) end
        end
    end
    for _, p in pairs(profiles) do
        for _, sp in ipairs(p.speakers or {}) do add(sp.ip) end
    end
    for _, sp in ipairs(self.settings:readSetting("speakers") or DEFAULT_SPEAKERS) do add(sp.ip) end

    local function try(ip)
        local groups = guarded(Sonos.getGroups, ip)
        if groups and #groups > 0 then
            return groups, guarded(Sonos.getHouseholdID, ip)
        end
    end
    local groups, household
    for _, ip in ipairs(candidates) do
        groups, household = try(ip)
        if groups then break end
    end
    if not groups and net.prefix then
        if verbose then
            UIManager:show(InfoMessage:new{ text = T("Looking for Sonos speakers on the network…"), timeout = 2 })
            UIManager:forceRePaint()
        end
        local hosts = guarded(Sonos.scan, net.prefix, 1.5, net.ip) or {}
        for _, ip in ipairs(hosts) do
            groups, household = try(ip)
            if groups then break end
        end
    end

    if not groups then
        -- offline fallback: show the last known system (control will fail until it's reachable)
        local p = self.profile or profiles[self.settings:readSetting("active_profile") or ""]
        self.groups = groups_from_speakers(p and p.speakers or self.settings:readSetting("speakers") or DEFAULT_SPEAKERS)
        if verbose then toast(T("No Sonos speakers found on this network") .. (net.ssid and (" (" .. net.ssid .. ")") or "")) end
        return false
    end

    household = household or ("unknown-" .. (net.ssid or "net"))
    local p = profiles[household]
    local is_new = not p
    if is_new then
        local n = 0
        for _ in pairs(profiles) do n = n + 1 end
        p = { household = household, name = net.ssid and ("Sonos · " .. net.ssid) or ("Sonos " .. (n + 1)), hidden = {} }
        -- carry over pre-profile settings for the first system
        if n == 0 then p.last_group = self.settings:readSetting("last_group") end
    end
    p.ssid = net.ssid or p.ssid
    p.speakers = {}
    for _, g in ipairs(groups) do
        for _, m in ipairs(g.members) do
            table.insert(p.speakers, { name = m.name, ip = m.ip, uuid = m.uuid })
        end
    end
    profiles[household] = p
    self.settings:saveSetting("profiles", profiles)
    self.settings:saveSetting("active_profile", household)
    self.settings:flush()
    self.profile = p
    self.groups = groups
    if verbose or is_new then
        toast(T(is_new and "New system: %1\nGroups: %2" or "System: %1\nGroups: %2", p.name, #groups))
    end
    return true
end

--- Re-read groups (after grouping changes) from one speaker.
function SonosPlugin:refreshTopology(ip)
    local groups = guarded(Sonos.getGroups, ip)
    if groups and #groups > 0 then self.groups = groups end
end

--- Groups shown in the room picker (rooms hidden in settings are skipped).
function SonosPlugin:visibleGroups()
    local hidden = (self.profile and self.profile.hidden) or {}
    local out = {}
    for _, g in ipairs(self.groups or {}) do
        local visible = false
        for _, m in ipairs(g.members) do
            if not hidden[m.uuid] then visible = true end
        end
        if visible then out[#out + 1] = g end
    end
    if #out == 0 then return self.groups or {} end
    return out
end

--- Settings: system, visible rooms, Spotify account and its Sonos serial.
function SonosPlugin:showSettings(on_change)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function reopen()
        UIManager:close(dialog)
        if on_change then on_change() end
        self:showSettings(on_change)
    end
    local p = self.profile
    local rows = {}
    local net_ssid = self.network and self.network.ssid
    table.insert(rows, { { text = T("System: %1", p and p.name or T("not found"))
        .. (net_ssid and ("\nWi-Fi: " .. net_ssid) or ""), enabled = false } })
    if p then
        table.insert(rows, { { text = T("Rename system…"), callback = function()
            UIManager:close(dialog)
            local input
            input = InputDialog:new{
                title = T("Sonos system name"),
                input = p.name,
                buttons = { {
                    { text = T("Cancel"), id = "close", callback = function() UIManager:close(input) end },
                    { text = T("Save"), is_enter_default = true, callback = function()
                        local name = input:getInputText()
                        UIManager:close(input)
                        if name and name ~= "" then self:profileSet("name", name) end
                        self:showSettings(on_change)
                    end },
                } },
            }
            UIManager:show(input)
            input:onShowKeyboard()
        end } })
        table.insert(rows, { { text = "— " .. T("Visible rooms") .. " —", enabled = false } })
        local hidden = p.hidden or {}
        local room_row = {}
        for _, sp in ipairs(p.speakers or {}) do
            local on = not hidden[sp.uuid]
            table.insert(room_row, { text = (on and "☑ " or "☐ ") .. sp.name, callback = function()
                hidden[sp.uuid] = on and true or nil
                self:profileSet("hidden", hidden)
                reopen()
            end })
            if #room_row == 2 then table.insert(rows, room_row); room_row = {} end
        end
        if #room_row > 0 then table.insert(rows, room_row) end
    end
    table.insert(rows, { { text = "— Kindle Music —", enabled = false } })
    table.insert(rows, {
        { text = T("Language: %1", L10n.languageName(self.settings:readSetting("language") or "en")), callback = function()
            local order = { en = "pl", pl = "auto", auto = "en" }
            local lang = order[self.settings:readSetting("language") or "en"] or "en"
            self.settings:saveSetting("language", lang)
            self.settings:flush()
            L10n.setLanguage(lang)
            reopen()
        end },
        { text = (self.settings:isFalse("sleep_screen") and "☐ " or "☑ ") .. T("Sleep screen: now playing"), callback = function()
            self.settings:saveSetting("sleep_screen", self.settings:isFalse("sleep_screen"))
            self.settings:flush()
            reopen()
        end },
    })
    if not self.settings:isFalse("sleep_screen") then
        table.insert(rows, { { text = (self.settings:isFalse("sleep_screen_live") and "☐ " or "☑ ")
            .. T("Sleep screen: wake up to show the next song"), callback = function()
            self.settings:saveSetting("sleep_screen_live", self.settings:isFalse("sleep_screen_live"))
            self.settings:flush()
            reopen()
        end } })
    end
    table.insert(rows, { { text = "— Spotify —", enabled = false } })
    table.insert(rows, { { text = T("Account: %1", self.spotify_active and self.spotify_active.name or T("none"))
        .. "  (" .. T("change / add / remove") .. ")", callback = function()
        UIManager:close(dialog)
        self:showSpotifyAccounts()
    end } })
    if p and self.spotify_active then
        local acc = self.spotify_active.id
        local map = p.spotify_sn or {}
        local cur = map[acc]
        table.insert(rows, { { text = T("Spotify account in the Sonos app: %1", cur and ("#" .. cur) or T("auto")),
            callback = function()
                -- cycle auto → 1 → 2 → 3 → 4 → auto
                local nxt = (not cur) and 1 or (cur < 4 and cur + 1 or nil)
                map[acc] = nxt
                self:profileSet("spotify_sn", map)
                reopen()
            end } })
    end
    -- other systems (other networks)
    local others = {}
    for hh, op in pairs(self:profiles()) do
        if not p or hh ~= p.household then others[#others + 1] = op end
    end
    if #others > 0 then
        table.insert(rows, { { text = "— " .. T("Other Sonos systems") .. " —", enabled = false } })
        for _, op in ipairs(others) do
            table.insert(rows, { { text = op.name .. (op.ssid and (" · Wi-Fi " .. op.ssid) or ""), callback = function()
                UIManager:show(InfoMessage:new{
                    text = T("“%1” is on another network.\n\nThe Kindle only controls the system on the network "
                        .. "it is connected to. Connect the Kindle to %2 and the plugin will switch by itself.",
                        op.name, op.ssid and T("the Wi-Fi “%1”", op.ssid) or T("that system's Wi-Fi")),
                })
            end } })
        end
    end
    table.insert(rows, { { text = T("Find speakers again"), callback = function()
        UIManager:close(dialog)
        self:discover(true)
        if on_change then on_change() end
    end } })
    dialog = ButtonDialog:new{ title = T("Kindle Music settings"), buttons = rows }
    UIManager:show(dialog)
end

function SonosPlugin:showRemote(autostart)
    NetworkMgr:runWhenOnline(function()
        local net = self:networkInfo()
        if not self.groups or not self.network or net.ssid ~= self.network.ssid or net.ip ~= self.network.ip then
            self:discover(false)
        end
        UIManager:show(SonosRemote:new{ plugin = self, autostart = autostart })
    end)
end

function SonosPlugin:onShowSonosRemote()
    self:showRemote()
    return true
end

function SonosPlugin:editSpeakerIP()
    local speakers = self.settings:readSetting("speakers") or {}
    local dialog
    dialog = InputDialog:new{
        title = T("IP of any Sonos speaker"),
        input = speakers[1] and speakers[1].ip or "",
        input_type = "string",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local ip = dialog:getInputText():match("^%s*([%d%.]+)%s*$")
                UIManager:close(dialog)
                if not ip then toast(T("Invalid IP address")) return end
                table.insert(speakers, 1, { name = ip, ip = ip })
                self.settings:saveSetting("speakers", speakers)
                self.settings:flush()
                self.groups = nil
                NetworkMgr:runWhenOnline(function() self:discover(true) end)
            end },
        } },
    }
    UIManager:show(dialog)
end

function SonosPlugin:addToMainMenu(menu_items)
    menu_items.sonos = {
        text = _("Kindle Music"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = T("Open remote"),
                callback = function() self:showRemote() end,
            },
            {
                text = T("Settings…"),
                keep_menu_open = true,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        if not self.groups then self:discover(false) end
                        self:showSettings()
                    end)
                end,
            },
            {
                text = T("Find speakers again"),
                keep_menu_open = true,
                callback = function()
                    NetworkMgr:runWhenOnline(function() self:discover(true) end)
                end,
            },
            {
                text_func = function()
                    local n = #(self.spotify_accounts or {})
                    local name = self.spotify_active and self.spotify_active.name
                    return name and ("Spotify: " .. name .. (n > 1 and (" (+" .. (n - 1) .. ")") or ""))
                        or ("Spotify: " .. T("not linked"))
                end,
                keep_menu_open = true,
                callback = function() self:showSpotifyAccounts() end,
            },
            {
                text = T("Set speaker IP…"),
                keep_menu_open = true,
                callback = function() self:editSpeakerIP() end,
            },
        },
    }
end

return SonosPlugin
