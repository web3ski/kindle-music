--[[--
Spotify browser for the Sonos remote: e-ink friendly pages with cover thumbnails.

Screens: Home (section tiles + "Recently played"), lists of playlists/albums/
artists/tracks, artist page (albums), album/playlist page (tracks), search.
Covers are downloaded lazily per page into a cache dir and shown in grayscale.

@module spotifyui
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
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
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local Screen = Device.screen

local Spotify = require("spotify")
local T = require("l10n").T

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/sonos-covers"
local CACHE_MAX_FILES = 600

local SpotifyUI = {}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function guarded(fn, ...)
    socketutil:set_timeout(3, 8)
    local ok, a, b = pcall(fn, ...)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("Sonos/Spotify UI error:", a)
        return nil, tostring(a)
    end
    return a, b
end

local function toast(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 2 })
end

local function ensure_cache_dir()
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(CACHE_DIR)
    end
end

--- Short stable hash (hex) for URLs without a usable ID (e.g. Sonos /getaa?… art links).
local function url_hash(s)
    local bit = require("bit")
    local h1, h2 = 5381, 52711
    for i = 1, #s do
        local c = s:byte(i)
        h1 = bit.tobit(h1 * 33 + c)
        h2 = bit.tobit(bit.bxor(h2 * 31, c))
    end
    return bit.tohex(h1) .. bit.tohex(h2)
end

local function cover_path(url)
    if not url then return nil end
    -- Spotify image URLs end with a long unique ID; anything else gets hashed
    local key = url:match("([%w]+)$")
    if not key or #key < 20 then key = "u" .. url_hash(url) end
    return CACHE_DIR .. "/" .. key .. ".jpg"
end

local function cover_cached(url)
    local p = cover_path(url)
    return p and lfs.attributes(p, "size") and lfs.attributes(p, "size") > 0 and p or nil
end

local function download_cover(url)
    local path = cover_path(url)
    if not path then return end
    ensure_cache_dir()
    local tmp = path .. ".part"
    local f = io.open(tmp, "wb")
    if not f then return end
    socketutil:set_timeout(3, 8)
    local ok, code, status = pcall(http.request, { url = url, sink = ltn12.sink.file(f) })
    socketutil:reset_timeout()
    if ok and code == 1 and (status == nil or status == 200) then
        os.rename(tmp, path)
    else
        os.remove(tmp)
    end
end

--- Keep the cover cache bounded (oldest files removed first).
local function prune_cache()
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then return end
    local files = {}
    for name in lfs.dir(CACHE_DIR) do
        if name:match("%.jpg$") then
            local p = CACHE_DIR .. "/" .. name
            files[#files + 1] = { p = p, t = lfs.attributes(p, "modification") or 0 }
        end
    end
    if #files <= CACHE_MAX_FILES then return end
    table.sort(files, function(a, b) return a.t < b.t end)
    for i = 1, #files - CACHE_MAX_FILES do os.remove(files[i].p) end
end

---------------------------------------------------------------------------
-- Row: cover + two lines of text, tappable
---------------------------------------------------------------------------

local Row = InputContainer:extend{
    item = nil,
    width = nil,
    height = nil,
    callback = nil,
    hold_callback = nil,
}

function Row:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    local pad = Size.padding.large
    local cover_size = self.height - 2 * pad
    local item = self.item

    local cover
    local file = item.image and cover_cached(item.image)
    if file then
        cover = ImageWidget:new{
            file = file,
            width = cover_size,
            height = cover_size,
            scale_factor = 0,
            file_do_cache = false,
        }
    else
        -- placeholder: grey square with a glyph for the item kind
        local glyph = ({ playlist = "♫", album = "◉", artist = "☺", track = "♪", section = "›" })[item.kind] or "♪"
        if item.glyph then glyph = item.glyph end
        cover = FrameContainer:new{
            width = cover_size, height = cover_size,
            padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{
                dimen = Geom:new{ w = cover_size, h = cover_size },
                TextWidget:new{ text = glyph, face = Font:getFace("cfont", math.floor(cover_size / 3)) },
            },
        }
    end
    -- artists are round in Spotify; we keep square covers but mark artists with a thin frame
    cover = FrameContainer:new{
        padding = 0, margin = 0,
        bordersize = item.kind == "artist" and Size.border.thin or 0,
        radius = item.kind == "artist" and math.floor(cover_size / 2) or nil,
        cover,
    }

    local text_w = self.width - cover_size - 3 * pad
    local texts = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = item.name or "?",
            face = Font:getFace("cfont", 21),
            bold = true,
            width = text_w,
            height = math.floor(cover_size * 0.62),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        TextWidget:new{
            text = item.sub or "",
            face = Font:getFace("cfont", 16),
            max_width = text_w,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
    }

    self[1] = FrameContainer:new{
        width = self.width, height = self.height,
        padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            cover,
            HorizontalSpan:new{ width = pad },
            texts,
        },
    }
end

function Row:onTapSelect()
    if self.callback then self.callback(self.item) end
    return true
end

function Row:onHoldSelect()
    if self.hold_callback then self.hold_callback(self.item) end
    return true
end

---------------------------------------------------------------------------
-- Page: paged list of rows with title bar, optional header buttons
---------------------------------------------------------------------------

local Page = InputContainer:extend{
    browser = nil,      -- SpotifyUI browser state
    title = "",
    subtitle = nil,
    items = nil,        -- list of normalised items
    header_buttons = nil, -- ButtonTable rows shown above the list
    on_tap = nil,       -- function(item)
    empty_text = nil,
    covers_fullscreen = true,
    page = 1,
}

function Page:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.items = self.items or {}
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    self:build()
end

function Page:build()
    local W, H = self.dimen.w, self.dimen.h
    local title_bar = TitleBar:new{
        width = W,
        fullscreen = true,
        with_bottom_line = true,
        title = self.title,
        subtitle = self.subtitle,
        left_icon = "chevron.left",
        left_icon_tap_callback = function() self.browser:back() end,
        close_callback = function() self.browser:closeAll() end,
        show_parent = self,
    }
    local inner_w = W - 2 * Size.padding.default
    local header
    if self.header_buttons then
        header = ButtonTable:new{ width = inner_w, buttons = self.header_buttons, show_parent = self }
    end

    local footer_h = Screen:scaleBySize(56)
    local used = title_bar:getSize().h + (header and (header:getSize().h + Size.padding.large * 2) or 0) + footer_h
    local row_h = Screen:scaleBySize(96)
    self.per_page = math.max(1, math.floor((H - used) / (row_h + Size.line.thin)))
    self.pages = math.max(1, math.ceil(#self.items / self.per_page))
    if self.page > self.pages then self.page = self.pages end

    local list = VerticalGroup:new{ align = "left" }
    local first = (self.page - 1) * self.per_page + 1
    self.visible = {}
    for i = first, math.min(#self.items, first + self.per_page - 1) do
        local item = self.items[i]
        self.visible[#self.visible + 1] = item
        table.insert(list, Row:new{
            item = item, width = W, height = row_h,
            callback = function(it) self.on_tap(it) end,
            hold_callback = function(it) self.browser:itemMenu(it, self) end,
        })
        table.insert(list, LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{ w = W, h = Size.line.thin },
        })
    end
    if #self.items == 0 then
        table.insert(list, CenterContainer:new{
            dimen = Geom:new{ w = W, h = row_h * 2 },
            TextBoxWidget:new{ text = self.empty_text or T("Empty"), face = Font:getFace("cfont", 20), width = inner_w, alignment = "center" },
        })
    end

    local footer = ButtonTable:new{
        width = inner_w,
        buttons = { {
            { text = T("‹ Back"), callback = function() self.browser:back() end },
            { text = "«", enabled = self.page > 1, callback = function() self:goPage(self.page - 1) end },
            { text = string.format("%d / %d", self.page, self.pages), enabled = false },
            { text = "»", enabled = self.page < self.pages, callback = function() self:goPage(self.page + 1) end },
        } },
        show_parent = self,
    }

    local content = VerticalGroup:new{ align = "center", title_bar }
    if header then
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
        table.insert(content, header)
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    end
    table.insert(content, list)

    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            content,
            VerticalSpan:new{ width = math.max(0, H - content:getSize().h - footer:getSize().h) },
            CenterContainer:new{ dimen = Geom:new{ w = W, h = footer:getSize().h }, footer },
        },
    }
end

function Page:redraw()
    self:build()
    UIManager:setDirty(self, "ui")
end

function Page:goPage(n)
    if n < 1 or n > self.pages then return end
    self.page = n
    self:redraw()
    self:loadCovers()
end

function Page:onSwipe(_, ges)
    if ges.direction == "west" then self:goPage(self.page + 1) return true end
    if ges.direction == "east" then
        if self.page > 1 then self:goPage(self.page - 1) else self.browser:back() end
        return true
    end
    if ges.direction == "south" then self.browser:back() return true end
end

--- Download missing covers for the visible page in the background, then repaint once.
function Page:loadCovers()
    local missing = {}
    for _, it in ipairs(self.visible or {}) do
        if it.image and not cover_cached(it.image) then missing[#missing + 1] = it.image end
    end
    if #missing == 0 then return end
    local page_at_start = self.page
    local idx = 0
    local function step()
        if self.closed or self.page ~= page_at_start then return end
        idx = idx + 1
        if missing[idx] then
            download_cover(missing[idx])
            -- small batches keep taps responsive
            UIManager:scheduleIn(0.05, step)
        else
            self:redraw()
        end
    end
    UIManager:scheduleIn(0.2, step)
end

function Page:onShow()
    self.closed = false
    UIManager:setDirty(self, "ui")
    self:loadCovers()
    return true
end

function Page:onCloseWidget()
    self.closed = true
end

---------------------------------------------------------------------------
-- Browser: a stack of pages, with loaders and actions
---------------------------------------------------------------------------

local Browser = {}
Browser.__index = Browser

--- @param opts { plugin=, remote=, group= }
function SpotifyUI.open(opts)
    local self = setmetatable({ plugin = opts.plugin, remote = opts.remote, stack = {} }, Browser)
    self.sp = opts.plugin:spotify()
    self:home()
    return self
end

function Browser:push(page_opts)
    page_opts.browser = self
    local page = Page:new(page_opts)
    table.insert(self.stack, page)
    UIManager:show(page)
    return page
end

-- e-ink: closing a full-screen widget doesn't repaint what's below by itself
function Browser:repaintTop()
    local top = self.stack[#self.stack]
    if top then
        UIManager:setDirty(top, "ui")
    else
        self.remote:redraw()
        UIManager:setDirty(self.remote, "ui")
    end
end

function Browser:back()
    local top = table.remove(self.stack)
    if top then UIManager:close(top) end
    self:repaintTop()
end

function Browser:closeAll()
    for i = #self.stack, 1, -1 do UIManager:close(self.stack[i]) end
    self.stack = {}
    self:repaintTop()
end

--- Run a loader with a short "loading" message; show an error toast on failure.
function Browser:load(fn, ...)
    local msg = InfoMessage:new{ text = T("Loading…"), dismissable = false }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local res, err = guarded(fn, self.sp, ...)
    UIManager:close(msg)
    if not res then
        if tostring(err):match("[Ss]cope") then
            toast(T("This section needs Spotify to be linked again (new permissions).\nSettings → Account → Add account."))
        else
            toast(Spotify.describeError(err))
        end
    end
    return res
end

function Browser:roomName()
    local g = self.remote:currentGroup()
    return g and g.name or "?"
end

--- Tap on any item: open a page or play.
function Browser:open(item)
    if item.kind == "section" then
        return item.action()
    elseif item.kind == "artist" then
        return self:artistPage(item)
    elseif item.kind == "album" then
        return self:albumPage(item)
    elseif item.kind == "playlist" then
        return self:playlistPage(item)
    elseif item.kind == "track" then
        return self:play(item)
    end
end

--- Play an item (context, track-in-context, or list of tracks) in the current room.
function Browser:play(item, track_list, index)
    self:hide()
    self.remote:startSpotify(item, track_list, index)
end

--- Hide the Spotify screens but keep them (pages, scroll position, loaded data) for "‹ Back".
function Browser:hide()
    self.saved = self.stack
    for i = #self.stack, 1, -1 do UIManager:close(self.stack[i]) end
    self.stack = {}
    self.remote.last_browser = self
end

function Browser:topTitle()
    local st = self.saved or self.stack
    local top = st and st[#st]
    local t = top and top.title
    if t and #t > 22 then t = t:sub(1, 20):gsub("[\128-\191]*$", "") .. "…" end
    return t
end

--- Back from the remote to exactly the last Spotify screen.
function Browser:restore()
    if not self.saved or #self.saved == 0 then
        return SpotifyUI.open{ plugin = self.plugin, remote = self.remote }
    end
    self.stack = self.saved
    self.saved = nil
    for _, page in ipairs(self.stack) do
        if page.subtitle then page.subtitle = page.subtitle:gsub("→ .*$", "→ " .. self:roomName()) end
        page:build()
        UIManager:show(page)
    end
end

--- Long-press on an item: more actions.
function Browser:itemMenu(item, page)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local rows = {}
    local function add(text, fn)
        rows[#rows + 1] = { { text = text, callback = function() UIManager:close(dlg); fn() end } }
    end
    if item.kind == "track" then
        add(T("▶ Play"), function() page.on_tap(item) end)
        add(T("Radio from this song"), function()
            self:play({ kind = "radio", track_id = item.id, name = T("Radio: %1", item.name or "") })
        end)
        if item.artist_names and item.artist_names[1] then
            add(T("Artist mix: %1", item.artist_names[1]), function()
                self:artistMix(item.artist_names[1], item, item.artist_ids and item.artist_ids[1])
            end)
        end
        if item.album_id then
            add(T("Go to album"), function()
                self:albumPage({ kind = "album", id = item.album_id, uri = "spotify:album:" .. item.album_id,
                    name = item.album_name or "Album", sub = item.artist_names and item.artist_names[1] or "",
                    image = item.image })
            end)
        end
        if item.artist_ids and item.artist_ids[1] then
            add(T("Go to artist"), function()
                self:artistPage({ kind = "artist", id = item.artist_ids[1], name = item.artist_names[1] })
            end)
        end
    elseif item.kind == "album" or item.kind == "playlist" then
        add(T("▶ Play"), function() self:play(item) end)
        add(T("Shuffle play"), function()
            self:play({ kind = item.kind, uri = item.uri, name = item.name, shuffle = true, total = item.total })
        end)
        add(T("Open"), function() self:open(item) end)
    elseif item.kind == "artist" then
        add(T("Artist radio"), function()
            self:play({ kind = "radio", artist_id = item.id, name = T("Radio: %1", item.name or "") })
        end)
        add(T("Artist mix"), function() self:artistMix(item.name, nil, item.id) end)
        add(T("Open"), function() self:open(item) end)
    else
        return
    end
    dlg = ButtonDialog:new{ title = item.name, buttons = rows }
    UIManager:show(dlg)
end

--- Artist mix (approximate radio from the artist's songs, shuffled).
function Browser:artistMix(artist_name, seed, artist_id)
    local tracks = self:load(self.sp.artistMix, artist_name, seed, artist_id)
    if not tracks or #tracks == 0 then return end
    self:play({ kind = "tracks", name = T("Mix: %1", artist_name) }, tracks, 1)
end

function Browser:listPage(title, items, empty)
    if not items then return end
    self:push{ title = title, subtitle = "→ " .. self:roomName(), items = items, empty_text = empty,
        on_tap = function(it) self:open(it) end }
end

function Browser:home()
    local sp = self.sp
    local function section(name, glyph, action)
        return { kind = "section", name = name, sub = nil, glyph = glyph, action = action }
    end
    local tiles = {
        {
            { text = T("Search"), callback = function() self:searchDialog() end },
            { text = T("♥ Liked"), callback = function()
                self:play({ kind = "liked", name = T("Liked songs") }) end },
        },
        {
            { text = T("Playlists"), callback = function() self:playlistsPage() end },
            { text = T("Albums"), callback = function()
                self:listPage(T("Saved albums"), self:load(sp.savedAlbums), T("No saved albums")) end },
        },
        {
            { text = T("Top artists"), callback = function()
                self:listPage(T("Your top artists"), self:load(sp.topArtists), T("No data")) end },
            { text = T("Top tracks"), callback = function()
                local tracks = self:load(sp.topTracks)
                if not tracks then return end
                self:push{ title = T("Your top tracks"), subtitle = "→ " .. self:roomName(), items = tracks,
                    header_buttons = { { { text = T("▶ Play all"), callback = function()
                        self:play({ kind = "tracks", name = T("Top tracks") }, tracks, 1) end } } },
                    on_tap = function(it)
                        for i, t in ipairs(tracks) do if t == it then return self:play(it, tracks, i) end end
                    end }
            end },
        },
        {
            { text = T("Following"), callback = function()
                self:listPage(T("Followed artists"), self:load(sp.followedArtists), T("You don't follow any artists")) end },
        },
    }
    -- "Recently played" fills the list part of the home page (like Spotify's Recents)
    local recent = guarded(sp.recent, sp)
    local items, empty = recent or {}, T("Recently played items will appear here")
    if not recent then
        -- fall back to the user's playlists when recents need re-linking
        items = guarded(sp.myPlaylists, sp) or {}
        empty = T("No data")
    end
    self:push{
        title = "Spotify",
        subtitle = (self.plugin.spotify_settings:readSetting("account_name") or "")
            .. " → " .. self:roomName() .. (recent and (" · " .. T("Recently played")) or (" · " .. T("Your playlists"))),
        items = items,
        empty_text = empty,
        header_buttons = tiles,
        on_tap = function(it) self:open(it) end,
    }
end

local SORTS = {
    { id = "spotify", label = "As in Spotify" },
    { id = "changed", label = "Recently changed" },
    { id = "played", label = "Recently played" },
    { id = "az", label = "A–Z" },
    { id = "size", label = "Number of tracks" },
}
local function sort_label(id)
    for _, s in ipairs(SORTS) do if s.id == id then return T(s.label) end end
    return T(SORTS[1].label)
end

--- "Recently changed": date of the newest item, cached per playlist snapshot.
function Browser:lastAddedDates(playlists)
    local LuaSettings = require("luasettings")
    local cache = LuaSettings:open(DataStorage:getSettingsDir() .. "/sonos_spotify_cache.lua")
    local dates = cache:readSetting("last_added") or {}
    local my_id = self.plugin.spotify_settings:readSetting("account_id")
    local changed = false
    for _, p in ipairs(playlists) do
        if p.owner_id == my_id or p.collaborative then
            local c = dates[p.id]
            if not (c and c.snapshot == p.snapshot) then
                local d = guarded(self.sp.playlistLastAdded, self.sp, p)
                if d then dates[p.id] = { snapshot = p.snapshot, date = d }; changed = true end
            end
        end
    end
    if changed then cache:saveSetting("last_added", dates); cache:flush() end
    return dates
end

function Browser:sortPlaylists(list, mode)
    local sorted = {}
    for i, p in ipairs(list) do sorted[i] = p; p._pos = i end
    local function stable(a, b, ka, kb)
        if ka ~= kb then return ka > kb end
        return a._pos < b._pos
    end
    if mode == "az" then
        table.sort(sorted, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    elseif mode == "size" then
        table.sort(sorted, function(a, b) return stable(a, b, a.total or -1, b.total or -1) end)
    elseif mode == "changed" then
        local dates = self:lastAddedDates(list)
        table.sort(sorted, function(a, b)
            return stable(a, b, (dates[a.id] or {}).date or "", (dates[b.id] or {}).date or "")
        end)
        for _, p in ipairs(sorted) do
            local d = (dates[p.id] or {}).date
            p.sub = p.sub_base .. (d and d ~= "" and (" · " .. T("changed %1", d:sub(1, 10))) or "")
        end
    elseif mode == "played" then
        local recent = guarded(self.sp.recent, self.sp) or {}
        local rank = {}
        for i, r in ipairs(recent) do rank[r.uri] = i end
        table.sort(sorted, function(a, b)
            local ra, rb = rank[a.uri] or 1e9, rank[b.uri] or 1e9
            if ra ~= rb then return ra < rb end
            return a._pos < b._pos
        end)
    end
    if mode ~= "changed" then
        for _, p in ipairs(sorted) do p.sub = p.sub_base end
    end
    return sorted
end

function Browser:playlistsPage()
    local all = self:load(self.sp.myPlaylists)
    if not all then return end
    for _, p in ipairs(all) do
        if p.total then p.sub = p.sub .. " · " .. T("%1 tracks", p.total) end
        p.sub_base = p.sub
    end
    local mode = self.plugin.settings:readSetting("spotify_playlist_sort") or "spotify"
    local page
    local function header()
        return { { { text = T("Sort: %1", sort_label(mode)) .. " ▾", callback = function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local dlg
            local rows = {}
            for _, s in ipairs(SORTS) do
                rows[#rows + 1] = { { text = (s.id == mode and "● " or "") .. T(s.label), callback = function()
                    UIManager:close(dlg)
                    mode = s.id
                    self.plugin.settings:saveSetting("spotify_playlist_sort", mode)
                    self.plugin.settings:flush()
                    local msg = InfoMessage:new{ text = T("Sorting…"), dismissable = false }
                    UIManager:show(msg); UIManager:forceRePaint()
                    page.items = self:sortPlaylists(all, mode)
                    UIManager:close(msg)
                    page.header_buttons = header()
                    page.page = 1
                    page:redraw()
                    page:loadCovers()
                end } }
            end
            dlg = ButtonDialog:new{ title = T("Sort playlists"), buttons = rows }
            UIManager:show(dlg)
        end } } }
    end
    page = self:push{ title = T("Your playlists"), subtitle = "→ " .. self:roomName(),
        items = self:sortPlaylists(all, mode), empty_text = T("No playlists"),
        header_buttons = header(), on_tap = function(it) self:open(it) end }
end

function Browser:artistPage(artist)
    local albums = self:load(self.sp.artistAlbums, artist.id)
    if not albums then return end
    self:push{ title = artist.name, subtitle = T("Albums and singles") .. " → " .. self:roomName(), items = albums,
        header_buttons = { {
            { text = T("Artist radio"), callback = function()
                self:play({ kind = "radio", artist_id = artist.id, name = T("Radio: %1", artist.name or "") })
            end },
            { text = T("Artist mix"), callback = function() self:artistMix(artist.name, nil, artist.id) end },
        } },
        empty_text = T("No albums"), on_tap = function(it) self:open(it) end }
end

function Browser:albumPage(album)
    local tracks = guarded(self.sp.albumTracks, self.sp, album) or {}
    self:push{
        title = album.name, subtitle = (album.sub or "") .. " → " .. self:roomName(),
        items = tracks, empty_text = T("Couldn't load the tracks. You can still play the whole album"),
        header_buttons = { {
            { text = T("▶ Play album"), callback = function() self:play(album) end },
            { text = T("Shuffle"), callback = function()
                self:play({ kind = album.kind, uri = album.uri, name = album.name, shuffle = true, total = #tracks })
            end },
        } },
        on_tap = function(t) self:play(t) end,
    }
end

local TRACK_SORTS = {
    { id = "order", label = "Playlist order" },
    { id = "added", label = "Recently added" },
    { id = "az", label = "A–Z" },
    { id = "artist", label = "Artist" },
}

local function sort_tracks(tracks, mode)
    local out = {}
    for i, t in ipairs(tracks) do out[i] = t end
    if mode == "added" then
        table.sort(out, function(a, b)
            if (a.added_at or "") ~= (b.added_at or "") then return (a.added_at or "") > (b.added_at or "") end
            return (a.offset or 0) < (b.offset or 0)
        end)
    elseif mode == "az" then
        table.sort(out, function(a, b)
            local x, y = (a.name or ""):lower(), (b.name or ""):lower()
            if x ~= y then return x < y end
            return (a.offset or 0) < (b.offset or 0)
        end)
    elseif mode == "artist" then
        table.sort(out, function(a, b)
            local x, y = (a.sub_base or a.sub or ""):lower(), (b.sub_base or b.sub or ""):lower()
            if x ~= y then return x < y end
            return (a.offset or 0) < (b.offset or 0)
        end)
    end
    return out
end

local function track_sort_label(id)
    for _, so in ipairs(TRACK_SORTS) do if so.id == id then return T(so.label) end end
    return T(TRACK_SORTS[1].label)
end

function Browser:playlistPage(pl)
    local my_id = self.plugin.spotify_settings:readSetting("account_id")
    local tracks, note
    if (pl.owner_id and my_id and pl.owner_id == my_id) or pl.collaborative then
        tracks = guarded(self.sp.playlistTracks, self.sp, pl)
    end
    local can_sort = tracks and #tracks > 1
    if not tracks then
        -- Spotify only exposes tracks of playlists you own (2026 API rules)
        tracks, note = {}, T("Spotify doesn't share the tracks of this playlist. You can still play all of it")
    end
    for _, t in ipairs(tracks) do t.sub_base = t.sub_base or t.sub end
    local mode = can_sort and (self.plugin.settings:readSetting("spotify_track_sort") or "order") or "order"
    local shown
    local function resort()
        shown = sort_tracks(tracks, mode)
        for _, t in ipairs(shown) do
            t.sub = t.sub_base .. ((mode == "added" and t.added_at) and (" · " .. T("added %1", t.added_at:sub(1, 10))) or "")
        end
    end
    resort()
    local page
    local function header()
        local rows = { {
            { text = T("▶ Play"), callback = function()
                if mode == "order" or #shown == 0 then
                    self:play(pl)
                else
                    self:play({ kind = "tracks", name = pl.name }, shown, 1)
                end
            end },
            { text = T("Shuffle"), callback = function()
                self:play({ kind = pl.kind, uri = pl.uri, name = pl.name, shuffle = true, total = pl.total })
            end },
        } }
        if can_sort then
            rows[2] = { { text = T("Sort: %1", track_sort_label(mode)) .. " ▾", callback = function()
                local ButtonDialog = require("ui/widget/buttondialog")
                local dlg
                local opts = {}
                for _, so in ipairs(TRACK_SORTS) do
                    opts[#opts + 1] = { { text = (so.id == mode and "● " or "") .. T(so.label), callback = function()
                        UIManager:close(dlg)
                        mode = so.id
                        self.plugin.settings:saveSetting("spotify_track_sort", mode)
                        self.plugin.settings:flush()
                        resort()
                        page.items = shown
                        page.header_buttons = header()
                        page.page = 1
                        page:redraw()
                        page:loadCovers()
                    end } }
                end
                dlg = ButtonDialog:new{ title = T("Sort tracks"), buttons = opts }
                UIManager:show(dlg)
            end } }
        end
        return rows
    end
    page = self:push{
        title = pl.name, subtitle = (pl.sub or "") .. " → " .. self:roomName(),
        items = shown, empty_text = note or T("Empty playlist"),
        header_buttons = header(),
        -- unsorted: play the playlist itself from this song (playlist order continues);
        -- sorted: queue the songs in the order shown, starting from the tapped one
        on_tap = function(t)
            if mode == "order" then return self:play(t) end
            for i, x in ipairs(shown) do
                if x == t then return self:play(t, shown, i) end
            end
        end,
    }
end

function Browser:searchDialog()
    local dialog
    dialog = InputDialog:new{
        title = T("Search Spotify"),
        input = self.last_query or "",
        buttons = { {
            { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = T("Search"), is_enter_default = true, callback = function()
                local q = dialog:getInputText()
                UIManager:close(dialog)
                if not q or q:match("^%s*$") then return end
                self.last_query = q
                local res = self:load(self.sp.search, q)
                if res then
                    self:listPage("“" .. q .. "”", res, T("Nothing found"))
                end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

SpotifyUI.pruneCache = prune_cache
SpotifyUI.coverCached = cover_cached
SpotifyUI.downloadCover = download_cover

return SpotifyUI
