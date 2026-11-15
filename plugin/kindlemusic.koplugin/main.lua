--[[--
Sonos remote for KOReader.

Tools menu → "Sonos", or bind the "Sonos: pilot" action to a gesture.

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
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local socketutil = require("socketutil")
local _ = require("gettext")
local Screen = Device.screen

local Sonos = require("sonos")
local Spotify = require("spotify")
local SpotifyUI = require("spotifyui")

-- No built-in speakers: they are found by auto-discovery (subnet scan) or entered in
-- Tools → Sonos → set speaker IP, and stored in koreader/settings/kindlemusic.lua.
local DEFAULT_SPEAKERS = {}
local VOLUME_STEP = 5
local AUTO_REFRESH_SECONDS = 15
-- Created by the "Sonos" scriptlet on the Kindle home screen
local AUTOSTART_FLAG = "/tmp/sonos_autostart"

local STATE_LABELS = {
    PLAYING = "▶ Gra",
    PAUSED_PLAYBACK = "Pauza",
    STOPPED = "Zatrzymane",
    TRANSITIONING = "Ładowanie…",
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

    local title_bar = TitleBar:new{
        width = width,
        fullscreen = true,
        with_bottom_line = true,
        title = "Sonos",
        subtitle = self.connect and ("Spotify Connect: " .. self.connect.name) or (group and group.name or "Brak głośników"),
        close_callback = function() UIManager:close(self) end,
        show_parent = self,
    }

    -- Room selector: one button per group, max 3 per row
    local room_rows, row = {}, {}
    for _, g in ipairs(self.groups) do
        local selected = not self.connect and group and g.coordinator == group.coordinator
        table.insert(row, {
            text = (selected and "● " or "") .. g.name,
            font_bold = selected,
            callback = function() self:selectGroup(g) end,
        })
        if #row == 3 then
            table.insert(room_rows, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(room_rows, row) end
    local extra = {}
    if #self.groups > 0 and not self.connect then
        table.insert(extra, { text = "Grupuj pokoje…", callback = function() self:showGrouping() end })
    end
    table.insert(extra, { text = (self.connect and "● " or "") .. "Inne urządzenia…",
        callback = function() self:showConnectDevices() end })
    table.insert(room_rows, extra)
    if #room_rows == 0 then
        room_rows = { { { text = "Szukaj głośników", callback = function() self:rediscover() end } } }
    end

    local track = self.track or {}
    local title_text = track.title and track.title ~= "" and track.title or "—"
    local sub_parts = {}
    if track.artist and track.artist ~= "" then table.insert(sub_parts, track.artist) end
    if track.album and track.album ~= "" then table.insert(sub_parts, track.album) end
    local status = self.error or (STATE_LABELS[self.state] or self.state or "…")

    local now_playing = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = title_text,
            face = Font:getFace("cfont", 30),
            bold = true,
            width = inner_w,
            height = Screen:scaleBySize(90),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextBoxWidget:new{
            text = #sub_parts > 0 and table.concat(sub_parts, " · ") or " ",
            face = Font:getFace("cfont", 22),
            width = inner_w,
            height = Screen:scaleBySize(60),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = Size.span.vertical_large * 2 },
        TextBoxWidget:new{
            text = status,
            face = Font:getFace("cfont", 20),
            width = inner_w,
        },
    }

    local big = 26
    local btn_h = Screen:scaleBySize(80)
    local is_playing = self.state == "PLAYING" or self.state == "TRANSITIONING"
    local controls = ButtonTable:new{
        width = inner_w,
        buttons = {
            {
                { text = "«", font_size = big + 8, height = btn_h, callback = function() self:command("previous") end },
                { text = is_playing and "Pauza" or "Graj", font_size = big, height = btn_h,
                  callback = function() self:command(is_playing and "pause" or "play") end },
                { text = "»", font_size = big + 8, height = btn_h, callback = function() self:command("next") end },
            },
            {
                { text = "− " .. VOLUME_STEP, font_size = big, height = btn_h,
                  callback = function() self:changeVolume(-VOLUME_STEP) end },
                { text = "Gł. " .. (self.volume and tostring(self.volume) or "?"), font_size = big - 4,
                  height = btn_h, enabled = (self:currentGroup() and #self:currentGroup().members > 1) or false,
                  callback = function() self:showRoomVolumes() end },
                { text = "+ " .. VOLUME_STEP, font_size = big, height = btn_h,
                  callback = function() self:changeVolume(VOLUME_STEP) end },
            },
            {
                { text = "Losowo: " .. ((self.mode and self.mode.shuffle) and "wł." or "wył."), font_size = 20,
                  callback = function() self:togglePlayMode("shuffle") end },
                { text = "Powtarzaj: " .. (({ none = "wył.", all = "wszystko", one = "utwór" })[self.mode and self.mode.rep or "none"]),
                  font_size = 20, callback = function() self:togglePlayMode("repeat") end },
                { text = "Wyłącznik: " .. (self.sleep_label or "wył."), font_size = 20,
                  callback = function() self:cycleSleepTimer() end },
            },
            (function()
                local row = {}
                if self.last_browser then
                    table.insert(row, { text = "‹ " .. (self.last_browser:topTitle() or "Spotify"), font_size = big - 6,
                        height = btn_h, callback = function() self.last_browser:restore() end })
                end
                table.insert(row, { text = "Spotify", font_size = big - 2, height = btn_h,
                    callback = function() self:showSpotify() end })
                if self.track and self.track.spotify_id then
                    table.insert(row, { text = "Radio", font_size = big - 2, height = btn_h,
                        callback = function()
                            self:startSpotify({ kind = "radio", track_id = self.track.spotify_id,
                                name = "Radio: " .. (self.track.title or "") })
                        end })
                end
                if #row < 3 then
                    table.insert(row, { text = "Ulubione Sonos", font_size = big - 6, height = btn_h,
                        callback = function() self:showLibrary() end })
                end
                return row
            end)(),
            {
                { text = "Odśwież", font_size = 20, callback = function() self:refresh(true) end },
                { text = "Ustawienia", font_size = 20, callback = function()
                    self.plugin:showSettings(function()
                        self.groups = self.plugin:visibleGroups()
                        self:refresh(true)
                    end)
                end },
            },
        },
    }

    local rooms = ButtonTable:new{ width = inner_w, buttons = room_rows }

    local content = VerticalGroup:new{
        align = "left",
        title_bar,
        VerticalSpan:new{ width = Size.span.vertical_large * 2 },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = rooms:getSize().h }, rooms },
        VerticalSpan:new{ width = Size.span.vertical_large * 4 },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = now_playing:getSize().h },
            now_playing,
        },
        VerticalSpan:new{ width = Size.span.vertical_large * 4 },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = controls:getSize().h }, controls },
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
        self.volume = guarded(Sonos.getVolume, group) or self.volume
        self.mode = guarded(Sonos.getPlayMode, group.ip) or self.mode
        local rem = guarded(Sonos.getSleepTimer, group.ip)
        self.sleep_label = (rem and rem ~= "") and rem:match("^(%d+:%d+)") or nil
    end
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
        self.track = { title = st.title, artist = st.artist, album = st.album, spotify_id = st.track_id }
        self.volume = st.volume
        self.mode = { shuffle = st.shuffle, rep = st.rep }
    elseif st or err == "none" then
        self.error = nil
        self.state = "STOPPED"
        self.track = { title = "—", artist = st and ("Teraz gra na: " .. tostring(st.device_name)) or "Nic nie gra" }
    else
        self.error = Spotify.describeError(err)
    end
    local after = table.concat({ tostring(self.state), tostring(self.track.title), tostring(self.volume), tostring(self.error) }, "|")
    return before ~= after
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
            local label = d.name .. "  (" .. (({ Computer = "komputer", Smartphone = "telefon", Speaker = "głośnik",
                TV = "TV", Tablet = "tablet", CastVideo = "Chromecast", CastAudio = "Chromecast",
                Automobile = "auto", AVR = "amplituner", STB = "dekoder" })[d.type] or (d.type or "?")) .. ")"
            if d.is_restricted then label = label .. " — bez sterowania" end
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
        rows[1] = { { text = "Brak innych urządzeń Spotify.\nUrządzenie musi być włączone i mieć otwarte Spotify\n(TV, komputer, telefon, głośnik).", enabled = false } }
    end
    rows[#rows + 1] = {
        { text = "Odśwież", callback = function() UIManager:close(dlg); self:showConnectDevices() end },
        { text = "Zamknij", callback = function() UIManager:close(dlg) end },
    }
    dlg = ButtonDialog:new{ title = "Inne urządzenia (Spotify Connect)", buttons = rows }
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
            text = "Brak ulubionych i playlist.\n\nW aplikacji Sonos dodaj playlisty (np. ze Spotify) "
                .. "do „Ulubione” (Moje Sonos) i otwórz tę listę ponownie.",
        })
        return
    end
    menu = Menu:new{
        title = "Playlisty — " .. group.name,
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
            text = "Ten Kindle nie jest połączony ze Spotify.\n\nNa Macu uruchom:\n"
                .. "python3 tools/link_spotify.py <IP Kindla>\ni zaloguj się swoim kontem Spotify.",
        })
        return
    end
    SpotifyUI.open{ plugin = self.plugin, remote = self }
end

--- Start Spotify playback without blocking: show the remote right away with
-- "Uruchamiam…", run the (slow) Sonos queue calls on the next UI tick.
function SonosRemote:startSpotify(item, track_list, index)
    local group = self:currentGroup()
    if not group and not self.connect then return end
    self.state = "TRANSITIONING"
    self.track = { title = "Uruchamiam…", artist = item.name, album = nil }
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
        toast(m.name .. ": obniżono głośność " .. mv .. " → " .. gv .. " (jak w grupie)")
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
    rows[#rows + 1] = { { text = "Gotowe", callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{ title = "Głośność pokoi w grupie", buttons = rows }
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
            rows[#rows + 1] = { { text = "☑ " .. m.name .. "  (główny)", enabled = false } }
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
        { text = "Wszystkie pokoje", callback = function()
            UIManager:close(dlg)
            for _, m in ipairs(all) do
                if m.uuid ~= coord.uuid and not in_group[m.uuid] and not hidden[m.uuid] then self:joinRoom(coord, m) end
            end
            after()
        end },
        { text = "Rozgrupuj", callback = function()
            UIManager:close(dlg)
            for _, m in ipairs(group.members) do
                if m.uuid ~= coord.uuid then guarded(Sonos.leaveGroup, m.ip) end
            end
            after()
        end },
    })
    if #group.members > 1 then
        rows[#rows + 1] = { { text = "Głośność poszczególnych pokoi…", callback = function()
            UIManager:close(dlg)
            self:showRoomVolumes()
        end } }
    end
    rows[#rows + 1] = { { text = "Gotowe", callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{
        title = "Grają razem z: " .. coord.name .. "\nZaznacz pokoje, które mają grać to samo.",
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

local SLEEP_STEPS = { 15, 30, 60, 90, 0 }
function SonosRemote:cycleSleepTimer()
    if self.connect then toast("Wyłącznik czasowy działa tylko z głośnikami Sonos") return end
    local group = self:currentGroup()
    if not group then return end
    self._sleep_idx = ((self._sleep_idx or 0) % #SLEEP_STEPS) + 1
    local minutes = SLEEP_STEPS[self._sleep_idx]
    local ok, err = guarded(Sonos.setSleepTimer, group.ip, minutes)
    if not ok then toast(Sonos.describeError(err)) return end
    self.sleep_label = minutes > 0 and string.format("%d min", minutes) or nil
    toast(minutes > 0 and ("Muzyka wyłączy się za " .. minutes .. " min") or "Wyłącznik czasowy wyłączony")
    self:redraw()
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
    local vol, err = guarded(Sonos.changeVolume, group, delta)
    if not vol then
        toast(Sonos.describeError(err))
        return
    end
    self.volume = vol
    self:redraw()
end

function SonosRemote:onShow()
    self:refresh(true)
    self:scheduleAutoRefresh()
    return true
end

function SonosRemote:onCloseWidget()
    self:unscheduleAutoRefresh()
    UIManager:setDirty(nil, "ui")
    if self.autostart then
        -- Launched from the home-screen scriptlet: offer to go straight back to the Kindle UI
        UIManager:nextTick(function()
            UIManager:show(ConfirmBox:new{
                text = "Wrócić do ekranu głównego Kindle?",
                ok_text = "Wyjdź",
                cancel_text = "Zostań w KOReader",
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
        if not uris or #uris == 0 then return nil, "Brak polubionych utworów" end
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
            if not entry then return nil, "Nieobsługiwany typ treści" end
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
        if not dev then return nil, "Spotify nie widzi głośnika „" .. room .. "”" end
        local ok, err = guarded(sp.play, sp, dev.id, context_uri, track_uris, offset)
        if not ok then return nil, Spotify.describeError(err) end
        return true
    end

    if connect_device then
        if item.kind == "radio" then
            return nil, "Radio działa tylko na głośnikach Sonos (Spotify nie udostępnia radia przez API)"
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
                toast("Aktywne konto Spotify: " .. acc.name)
            end },
            { text = "Usuń", callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = "Usunąć konto Spotify „" .. acc.name .. "” z tego Kindla?\n\n"
                        .. "Dostęp możesz też odwołać na spotify.com → Konto → Aplikacje.",
                    ok_text = "Usuń",
                    ok_callback = function() self:removeSpotifyAccount(acc.id) end,
                })
            end },
        })
    end
    table.insert(buttons, { { text = "+ Dodaj konto…", callback = function()
        UIManager:close(dialog)
        UIManager:show(InfoMessage:new{
            text = "Aby dodać konto Spotify do tego Kindla, na Macu uruchom:\n\n"
                .. "python3 tools/link_spotify.py <IP Kindla>\n\n"
                .. "i zaloguj się tym kontem. Konto musi być dodane w panelu Spotify "
                .. "(User Management, maks. 5 osób), a do odtwarzania przez Sonosa także w aplikacji Sonos.\n"
                .. "Potem zrestartuj KOReader.",
        })
    end } })
    dialog = ButtonDialog:new{
        title = #buttons > 1 and "Konta Spotify na tym Kindlu" or "Brak połączonych kont Spotify",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function SonosPlugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("sonos_remote", {
        category = "none", event = "ShowSonosRemote", title = _("Sonos: pilot"), general = true,
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
            UIManager:show(InfoMessage:new{ text = "Szukam głośników Sonos w sieci…", timeout = 2 })
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
        if verbose then toast("Nie znaleziono głośników Sonos w tej sieci" .. (net.ssid and (" (" .. net.ssid .. ")") or "")) end
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
        toast((is_new and "Nowy system: " or "System: ") .. p.name .. "\nGrup: " .. #groups)
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
    table.insert(rows, { { text = "System: " .. (p and p.name or "nie wykryto")
        .. (net_ssid and ("\nWi-Fi: " .. net_ssid) or ""), enabled = false } })
    if p then
        table.insert(rows, { { text = "Zmień nazwę systemu…", callback = function()
            UIManager:close(dialog)
            local input
            input = InputDialog:new{
                title = "Nazwa systemu Sonos",
                input = p.name,
                buttons = { {
                    { text = "Anuluj", id = "close", callback = function() UIManager:close(input) end },
                    { text = "Zapisz", is_enter_default = true, callback = function()
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
        table.insert(rows, { { text = "— Widoczne pokoje —", enabled = false } })
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
    table.insert(rows, { { text = "— Spotify —", enabled = false } })
    table.insert(rows, { { text = "Konto: " .. (self.spotify_active and self.spotify_active.name or "brak")
        .. "  (zmień / dodaj / usuń)", callback = function()
        UIManager:close(dialog)
        self:showSpotifyAccounts()
    end } })
    if p and self.spotify_active then
        local acc = self.spotify_active.id
        local map = p.spotify_sn or {}
        local cur = map[acc]
        table.insert(rows, { { text = "Konto Spotify w aplikacji Sonos: " .. (cur and ("nr " .. cur) or "auto"),
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
        table.insert(rows, { { text = "— Inne systemy Sonos —", enabled = false } })
        for _, op in ipairs(others) do
            table.insert(rows, { { text = op.name .. (op.ssid and (" · Wi-Fi " .. op.ssid) or ""), callback = function()
                UIManager:show(InfoMessage:new{
                    text = "„" .. op.name .. "” jest w innej sieci.\n\nKindle steruje tylko systemem w sieci, "
                        .. "z którą jest połączony. Połącz Kindle z Wi-Fi " .. (op.ssid and ("„" .. op.ssid .. "”") or "tamtego systemu")
                        .. " — plugin przełączy się sam.",
                })
            end } })
        end
    end
    table.insert(rows, { { text = "Szukaj głośników ponownie", callback = function()
        UIManager:close(dialog)
        self:discover(true)
        if on_change then on_change() end
    end } })
    dialog = ButtonDialog:new{ title = "Ustawienia Sonos", buttons = rows }
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
        title = "IP dowolnego głośnika Sonos",
        input = speakers[1] and speakers[1].ip or "",
        input_type = "string",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local ip = dialog:getInputText():match("^%s*([%d%.]+)%s*$")
                UIManager:close(dialog)
                if not ip then toast("Niepoprawny adres IP") return end
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
        text = _("Sonos"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Otwórz pilota",
                callback = function() self:showRemote() end,
            },
            {
                text = "Ustawienia…",
                keep_menu_open = true,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        if not self.groups then self:discover(false) end
                        self:showSettings()
                    end)
                end,
            },
            {
                text = "Szukaj głośników ponownie",
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
                        or "Spotify: niepołączony"
                end,
                keep_menu_open = true,
                callback = function() self:showSpotifyAccounts() end,
            },
            {
                text = "Ustaw IP głośnika…",
                keep_menu_open = true,
                callback = function() self:editSpeakerIP() end,
            },
        },
    }
end

return SonosPlugin
