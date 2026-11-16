--[[--
Minimal Spotify Web API client (Authorization Code + PKCE refresh flow).

Only needs the app's Client ID and a refresh token obtained once with
tools/link_spotify.py. No client secret is ever stored on the Kindle.

Uses KOReader's bundled LuaSocket/LuaSec (socket.http handles https URLs)
and the "json" module.

@module spotify
--]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("json")
local T = require("l10n").T

local TOKEN_URL = "https://accounts.spotify.com/api/token"
local API = "https://api.spotify.com/v1"

local Spotify = {}
Spotify.__index = Spotify

local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function form(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = urlencode(k) .. "=" .. urlencode(v)
    end
    return table.concat(parts, "&")
end

--- @param opts { client_id=, refresh_token=, on_token_update=function(refresh_token) }
function Spotify.new(opts)
    local self = setmetatable({}, Spotify)
    self.client_id = opts.client_id
    self.refresh_token = opts.refresh_token
    self.on_token_update = opts.on_token_update
    self.access_token = nil
    self.expires_at = 0
    return self
end

local function raw_request(method, url, headers, body)
    local chunks = {}
    local ok, code, resp_headers = http.request{
        url = url,
        method = method,
        headers = headers,
        source = body and ltn12.source.string(body) or nil,
        sink = ltn12.sink.table(chunks),
    }
    if not ok then return nil, tostring(code) end
    return tonumber(code), table.concat(chunks), resp_headers
end

function Spotify:refresh()
    if not self.client_id or not self.refresh_token then
        return nil, "not_linked"
    end
    local body = form{
        grant_type = "refresh_token",
        refresh_token = self.refresh_token,
        client_id = self.client_id,
    }
    local code, resp = raw_request("POST", TOKEN_URL, {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Content-Length"] = tostring(#body),
    }, body)
    if not code then return nil, resp end
    local ok, data = pcall(JSON.decode, resp or "")
    if code ~= 200 or not ok or type(data) ~= "table" or not data.access_token then
        local err = ok and type(data) == "table" and data.error or ("http " .. tostring(code))
        if err == "invalid_grant" then err = "revoked" end
        return nil, err
    end
    self.access_token = data.access_token
    self.expires_at = os.time() + (tonumber(data.expires_in) or 3600) - 60
    -- PKCE refresh tokens rotate: persist the new one
    if data.refresh_token and data.refresh_token ~= self.refresh_token then
        self.refresh_token = data.refresh_token
        if self.on_token_update then self.on_token_update(data.refresh_token) end
    end
    return true
end

--- Authenticated API call. Returns decoded JSON (or true for empty bodies), or nil, err, status.
function Spotify:api(method, path, query, json_body)
    if not self.access_token or os.time() >= self.expires_at then
        local ok, err = self:refresh()
        if not ok then return nil, err end
    end
    local url = path:match("^https://") and path or (API .. path)
    if query then
        local q = form(query)
        if q ~= "" then url = url .. (url:find("?", 1, true) and "&" or "?") .. q end
    end
    local body = json_body and JSON.encode(json_body) or nil
    local headers = { ["Authorization"] = "Bearer " .. self.access_token }
    if body then
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#body)
    elseif method == "PUT" or method == "POST" then
        headers["Content-Length"] = "0"
    end
    local code, resp = raw_request(method, url, headers, body)
    if not code then return nil, resp end
    if code == 401 then
        -- token expired early: refresh once and retry
        self.access_token = nil
        local ok, err = self:refresh()
        if not ok then return nil, err end
        headers["Authorization"] = "Bearer " .. self.access_token
        code, resp = raw_request(method, url, headers, body)
        if not code then return nil, resp end
    end
    if code == 204 or ((code == 200 or code == 202) and (resp == nil or resp == "")) then
        return true
    end
    local ok, data = pcall(JSON.decode, resp or "")
    if code >= 200 and code < 300 then
        return ok and data or true
    end
    local msg = ok and type(data) == "table" and type(data.error) == "table" and data.error.reason
        or (ok and type(data) == "table" and type(data.error) == "table" and data.error.message)
    return nil, msg or ("http " .. code), code
end

function Spotify:me()
    return self:api("GET", "/me")
end

--- All of the user's playlists (owned + followed), up to `max`.
function Spotify:playlists(max)
    max = max or 200
    local items, offset = {}, 0
    while #items < max do
        local page, err = self:api("GET", "/me/playlists", { limit = 50, offset = offset })
        if not page then return nil, err end
        for _, p in ipairs(page.items or {}) do
            if type(p) == "table" and p.uri then
                table.insert(items, {
                    id = p.id,
                    name = p.name,
                    uri = p.uri,
                    owner = type(p.owner) == "table" and (p.owner.display_name or p.owner.id) or nil,
                })
            end
        end
        if not page.next or page.next == JSON.null or #(page.items or {}) == 0 then break end
        offset = offset + 50
    end
    return items
end

function Spotify:devices()
    local data, err = self:api("GET", "/me/player/devices")
    if not data then return nil, err end
    return type(data) == "table" and data.devices or {}
end

--- Start a context (playlist/album) or liked songs on a Connect device.
function Spotify:play(device_id, context_uri, track_uris, offset)
    local body = {}
    if context_uri then body.context_uri = context_uri end
    if track_uris then body.uris = track_uris end
    if offset and offset > 1 then body.offset = { position = offset - 1 } end
    return self:api("PUT", "/me/player/play", { device_id = device_id }, body)
end

--- Playback on Spotify Connect devices (TVs, computers, phones, other speakers).
-- Current player state; nil,"none" when nothing is active.
function Spotify:player()
    local d, e = self:api("GET", "/me/player", { additional_types = "episode" })
    if d == true then return nil, "none" end
    if not d then return nil, e end
    local it = type(d.item) == "table" and d.item or {}
    local artists = {}
    for _, a in ipairs(it.artists or {}) do if type(a) == "table" then artists[#artists + 1] = a.name end end
    return {
        is_playing = d.is_playing == true,
        device_id = type(d.device) == "table" and d.device.id or nil,
        device_name = type(d.device) == "table" and d.device.name or nil,
        volume = type(d.device) == "table" and tonumber(d.device.volume_percent) or nil,
        shuffle = d.shuffle_state == true,
        rep = ({ off = "none", context = "all", track = "one" })[d.repeat_state or "off"] or "none",
        title = it.name,
        artist = table.concat(artists, ", "),
        album = type(it.album) == "table" and it.album.name or (type(it.show) == "table" and it.show.name) or nil,
        track_id = it.type == "track" and it.id or nil,
        progress = tonumber(d.progress_ms) and math.floor(tonumber(d.progress_ms) / 1000) or nil,
        duration = tonumber(it.duration_ms) and math.floor(tonumber(it.duration_ms) / 1000) or nil,
        image = type(it.album) == "table" and Spotify.pickImage(it.album.images, 300)
            or (type(it.show) == "table" and Spotify.pickImage(it.show.images, 300)) or nil,
    }
end

function Spotify:pause(device_id) return self:api("PUT", "/me/player/pause", { device_id = device_id }) end
function Spotify:resume(device_id) return self:api("PUT", "/me/player/play", { device_id = device_id }) end
function Spotify:nextTrack(device_id) return self:api("POST", "/me/player/next", { device_id = device_id }) end
function Spotify:previousTrack(device_id) return self:api("POST", "/me/player/previous", { device_id = device_id }) end
function Spotify:setVolume(device_id, v)
    return self:api("PUT", "/me/player/volume", { device_id = device_id, volume_percent = math.max(0, math.min(100, v)) })
end
function Spotify:setShuffle(device_id, on)
    return self:api("PUT", "/me/player/shuffle", { device_id = device_id, state = on and "true" or "false" })
end
function Spotify:setRepeat(device_id, rep)
    return self:api("PUT", "/me/player/repeat",
        { device_id = device_id, state = ({ none = "off", all = "context", one = "track" })[rep] or "off" })
end

function Spotify:transfer(device_id, start)
    return self:api("PUT", "/me/player", nil, { device_ids = { device_id }, play = start and true or false })
end

--- First N liked songs as track URIs (Liked Songs has no context URI usable by the API).
function Spotify:likedTrackUris(n)
    local data, err = self:api("GET", "/me/tracks", { limit = math.min(n or 50, 50) })
    if not data then return nil, err end
    local uris, names = {}, {}
    for _, it in ipairs(data.items or {}) do
        if type(it) == "table" and type(it.track) == "table" and it.track.uri then
            table.insert(uris, it.track.uri)
            names[it.track.uri] = it.track.name
        end
    end
    return uris, names
end

---------------------------------------------------------------------------
-- Browsing helpers. Everything is normalised to "items":
-- { kind = "playlist"|"album"|"artist"|"track", id, uri, name, sub, image,
--   context_uri (for tracks), offset (1-based position in context) }
---------------------------------------------------------------------------

--- Pick an image URL around `want` px wide (Spotify returns 640/300/64 variants).
local function pick_image(images, want)
    if type(images) ~= "table" or #images == 0 then return nil end
    want = want or 200
    local best
    for _, im in ipairs(images) do
        if type(im) == "table" and im.url then
            local w = tonumber(im.width) or 640
            if w >= want and (not best or w < (tonumber(best.width) or 640)) then best = im end
        end
    end
    best = best or images[1]
    return type(best) == "table" and best.url or nil
end
Spotify.pickImage = pick_image

local function artists_str(list)
    local names = {}
    for _, a in ipairs(list or {}) do
        if type(a) == "table" and a.name then names[#names + 1] = a.name end
    end
    return table.concat(names, ", ")
end

function Spotify.normPlaylist(p)
    if type(p) ~= "table" or not p.uri then return nil end
    return { kind = "playlist", id = p.id, uri = p.uri, name = p.name,
        sub = T("Playlist") .. (type(p.owner) == "table" and (" · " .. (p.owner.display_name or p.owner.id or "")) or ""),
        owner_id = type(p.owner) == "table" and p.owner.id or nil,
        collaborative = p.collaborative == true,
        snapshot = p.snapshot_id,
        total = type(p.items) == "table" and tonumber(p.items.total)
            or (type(p.tracks) == "table" and tonumber(p.tracks.total)) or nil,
        image = pick_image(p.images) }
end

function Spotify.normAlbum(a)
    if type(a) ~= "table" or not a.uri then return nil end
    local year = type(a.release_date) == "string" and a.release_date:sub(1, 4) or nil
    return { kind = "album", id = a.id, uri = a.uri, name = a.name,
        sub = artists_str(a.artists) .. (year and (" · " .. year) or ""),
        image = pick_image(a.images) }
end

function Spotify.normArtist(a)
    if type(a) ~= "table" or not a.uri then return nil end
    return { kind = "artist", id = a.id, uri = a.uri, name = a.name, sub = T("Artist"), image = pick_image(a.images) }
end

function Spotify.normTrack(t, context_uri, offset, album_image)
    if type(t) ~= "table" or not t.uri or t.is_local then return nil end
    local album = type(t.album) == "table" and t.album or nil
    local artist_ids, artist_names = {}, {}
    for _, a in ipairs(t.artists or {}) do
        if type(a) == "table" then artist_ids[#artist_ids + 1] = a.id; artist_names[#artist_names + 1] = a.name end
    end
    return { kind = "track", id = t.id, uri = t.uri, name = t.name,
        artist_ids = artist_ids, artist_names = artist_names,
        album_id = album and album.id or nil, album_name = album and album.name or nil,
        sub = artists_str(t.artists) .. (album and album.name and (" · " .. album.name) or ""),
        image = album and pick_image(album.images) or album_image,
        context_uri = context_uri or (album and album.uri) or nil,
        offset = offset or (context_uri == nil and album and tonumber(t.track_number)) or nil }
end

local function map(list, fn, ...)
    local out = {}
    for _, x in ipairs(list or {}) do
        local n = fn(x, ...)
        if n then out[#out + 1] = n end
    end
    return out
end

function Spotify:savedAlbums()
    local d, e = self:api("GET", "/me/albums", { limit = 50 })
    if not d then return nil, e end
    local out = {}
    for _, it in ipairs(d.items or {}) do
        local n = type(it) == "table" and Spotify.normAlbum(it.album)
        if n then out[#out + 1] = n end
    end
    return out
end

function Spotify:myPlaylists()
    local out, offset = {}, 0
    while true do
        local page, err = self:api("GET", "/me/playlists", { limit = 50, offset = offset })
        if not page then return nil, err end
        for _, p in ipairs(page.items or {}) do
            local n = Spotify.normPlaylist(p)
            if n then out[#out + 1] = n end
        end
        if not page.next or #(page.items or {}) < 50 or offset > 250 then break end
        offset = offset + 50
    end
    return out
end

function Spotify:topArtists()
    local d, e = self:api("GET", "/me/top/artists", { limit = 30, time_range = "medium_term" })
    if not d then return nil, e end
    return map(d.items, Spotify.normArtist)
end

function Spotify:topTracks()
    local d, e = self:api("GET", "/me/top/tracks", { limit = 50, time_range = "short_term" })
    if not d then return nil, e end
    return map(d.items, Spotify.normTrack)
end

function Spotify:followedArtists()
    local d, e = self:api("GET", "/me/following", { type = "artist", limit = 50 })
    if not d then return nil, e end
    return map(type(d.artists) == "table" and d.artists.items or {}, Spotify.normArtist)
end

--- Recently played, collapsed to unique contexts (album/playlist/artist) like Spotify's "Recents".
function Spotify:recent()
    local d, e = self:api("GET", "/me/player/recently-played", { limit = 50 })
    if not d then return nil, e end
    local out, seen = {}, {}
    for _, it in ipairs(d.items or {}) do
        local tr = type(it) == "table" and it.track
        local ctx = type(it) == "table" and type(it.context) == "table" and it.context.uri or nil
        local key = ctx or (type(tr) == "table" and type(tr.album) == "table" and tr.album.uri)
        if key and not seen[key] and type(tr) == "table" then
            seen[key] = true
            local kind = key:match("^spotify:(%a+):")
            if kind == "album" or not ctx then
                local n = Spotify.normAlbum(tr.album)
                if n then out[#out + 1] = n end
            elseif kind == "playlist" or kind == "artist" then
                -- context details need an extra request; show what we know, fetch name lazily
                out[#out + 1] = { kind = kind, uri = key, id = key:match(":([%w]+)$"),
                    name = nil, sub = kind == "playlist" and T("Playlist") or T("Artist"),
                    image = nil, lazy = true }
            end
        end
    end
    -- resolve lazy contexts (few requests; recents are usually < 15 unique)
    for _, n in ipairs(out) do
        if n.lazy then
            local full = self:api("GET", "/" .. n.kind .. "s/" .. n.id, n.kind == "playlist" and { fields = "name,uri,id,images,owner" } or nil)
            local norm = full and (n.kind == "playlist" and Spotify.normPlaylist(full) or Spotify.normArtist(full))
            if norm then for k, v in pairs(norm) do n[k] = v end end
            n.lazy = nil
            n.name = n.name or "?"
        end
    end
    return out
end

function Spotify:artistAlbums(id)
    -- 2026 dev-mode limit for this endpoint is 10 per page
    local out, offset = {}, 0
    while offset < 30 do
        local d, e = self:api("GET", "/artists/" .. id .. "/albums",
            { include_groups = "album,single,compilation", limit = 10, offset = offset })
        if not d then
            if #out > 0 then break end
            return nil, e
        end
        for _, a in ipairs(d.items or {}) do
            local n = Spotify.normAlbum(a)
            if n then out[#out + 1] = n end
        end
        if not d.next or #(d.items or {}) < 10 then break end
        offset = offset + 10
    end
    return out
end

function Spotify:albumTracks(album)
    local d, e = self:api("GET", "/albums/" .. album.id .. "/tracks", { limit = 50 })
    if not d then return nil, e end
    local out = {}
    for i, t in ipairs(d.items or {}) do
        local n = Spotify.normTrack(t, album.uri, i, album.image)
        if n then n.sub = artists_str(t.artists); out[#out + 1] = n end
    end
    return out
end

--- Tracks of a playlist (only playlists the user owns/collaborates on, per 2026 API rules).
function Spotify:playlistTracks(pl)
    local out, offset = {}, 0
    while offset < 500 do
        local d, e = self:api("GET", "/playlists/" .. pl.id .. "/items", { limit = 50, offset = offset })
        if not d then
            if #out > 0 then break end
            return nil, e
        end
        for i, it in ipairs(d.items or {}) do
            local t = type(it) == "table" and (it.item or it.track)
            local n = Spotify.normTrack(t, pl.uri, offset + i)
            if n then
                n.added_at = it.added_at
                out[#out + 1] = n
            end
        end
        if not d.next or #(d.items or {}) < 50 then break end
        offset = offset + 50
    end
    return out
end

--- Single track (e.g. the one playing now) as a normalised item.
function Spotify:track(id)
    local d, e = self:api("GET", "/tracks/" .. id)
    if not d then return nil, e end
    return Spotify.normTrack(d)
end

--- "Artist mix": the artist's tracks via search (recommendations are blocked for our app).
function Spotify:artistMix(artist_name, seed, artist_id)
    local out, seen = {}, {}
    if seed then out[1] = seed; seen[(seed.name or ""):lower()] = true end
    for _, offset in ipairs({ 0, 10, 20, 30 }) do
        local d = self:api("GET", "/search", { q = 'artist:"' .. artist_name .. '"', type = "track", limit = 10, offset = offset })
        local items = d and type(d.tracks) == "table" and d.tracks.items or {}
        for _, t in ipairs(items) do
            local n = Spotify.normTrack(t)
            local key = n and (n.name or ""):lower()
            if n and not seen[key] then seen[key] = true; out[#out + 1] = n end
        end
        if #items < 10 then break end
    end
    -- search is capped in 2026; top up with songs from the artist's albums
    if #out < 25 then
        if not artist_id then
            local d = self:api("GET", "/search", { q = 'artist:"' .. artist_name .. '"', type = "artist", limit = 1 })
            local a = d and type(d.artists) == "table" and d.artists.items and d.artists.items[1]
            artist_id = type(a) == "table" and a.id or nil
        end
        local albums = artist_id and self:artistAlbums(artist_id) or {}
        for i = 1, math.min(4, #albums) do
            local tracks = self:albumTracks(albums[i]) or {}
            for _, n in ipairs(tracks) do
                local key = (n.name or ""):lower()
                if not seen[key] then
                    seen[key] = true
                    n.context_uri, n.offset = nil, nil -- play as part of the mix, not the album
                    out[#out + 1] = n
                end
            end
            if #out >= 40 then break end
        end
    end
    -- shuffle everything after the seed
    local start = seed and 2 or 1
    for i = #out, start + 1, -1 do
        local j = math.random(start, i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

--- ISO date of the most recently added item (owned/collaborative playlists only).
function Spotify:playlistLastAdded(pl)
    if not pl.total or pl.total == 0 then return "" end
    local d, e = self:api("GET", "/playlists/" .. pl.id .. "/items",
        { fields = "items(added_at)", limit = 1, offset = pl.total - 1 })
    if not d then return nil, e end
    local it = type(d.items) == "table" and d.items[1]
    return type(it) == "table" and it.added_at or ""
end

function Spotify:search(q)
    local d, e = self:api("GET", "/search", { q = q, type = "track,album,artist,playlist", limit = 10 })
    if not d then return nil, e end
    local res = {}
    local function section(key, fn)
        local block = type(d[key]) == "table" and d[key].items or {}
        for _, x in ipairs(block) do
            local n = fn(x)
            if n then res[#res + 1] = n end
        end
    end
    section("artists", Spotify.normArtist)
    section("tracks", Spotify.normTrack)
    section("albums", Spotify.normAlbum)
    section("playlists", Spotify.normPlaylist)
    return res
end

Spotify.ERRORS = {
    not_linked = "This Kindle is not linked to Spotify (run tools/link_spotify.py on your computer)",
    revoked = "Spotify access expired or was revoked. Link the account again",
    PREMIUM_REQUIRED = "Playback control requires Spotify Premium",
    NO_ACTIVE_DEVICE = "Spotify can't see an active speaker",
    UNKNOWN = "Spotify refused the request",
}

function Spotify.describeError(err)
    err = tostring(err)
    if Spotify.ERRORS[err] then return T(Spotify.ERRORS[err]) end
    if err == "timeout" then return T("Spotify is not responding (timeout)") end
    return "Spotify: " .. err
end

return Spotify
