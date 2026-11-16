--[[--
Minimal Sonos UPnP/SOAP client (local network, port 1400).

Pure Lua + LuaSocket; no KOReader dependencies, so it can be tested
standalone with KOReader's luajit.

@module sonos
--]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local T = require("l10n").T

local Sonos = {}

local SERVICES = {
    AVTransport = "/MediaRenderer/AVTransport/Control",
    RenderingControl = "/MediaRenderer/RenderingControl/Control",
    GroupRenderingControl = "/MediaRenderer/GroupRenderingControl/Control",
    ZoneGroupTopology = "/ZoneGroupTopology/Control",
    DeviceProperties = "/DeviceProperties/Control",
    ContentDirectory = "/MediaServer/ContentDirectory/Control",
}

local ENTITIES = {
    ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&apos;"] = "'",
}

function Sonos.unescape(s)
    if not s then return nil end
    s = s:gsub("&%a+;", ENTITIES)
    s = s:gsub("&#(%d+);", function(n)
        n = tonumber(n)
        if n and n < 128 then return string.char(n) end
    end)
    s = s:gsub("&amp;", "&")
    return s
end

function Sonos.escape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function tag(xml, name)
    if not xml then return nil end
    -- exact tag name only: "<upnp:album" must not match "<upnp:albumArtURI>"
    local close = "</" .. name .. ">"
    return xml:match("<" .. name .. ">(.-)" .. close)
        or xml:match("<" .. name .. "%s[^>]*>(.-)" .. close)
end
Sonos.tag = tag

local function attrs(s)
    local t = {}
    for k, v in s:gmatch('([%w_:]+)="([^"]*)"') do
        t[k] = v
    end
    return t
end

--- Perform a SOAP call. Returns response body string, or nil + error.
function Sonos.soap(ip, service, action, args)
    local body_args = {}
    for _, kv in ipairs(args or {}) do
        body_args[#body_args + 1] = string.format("<%s>%s</%s>", kv[1], Sonos.escape(kv[2]), kv[1])
    end
    local urn = "urn:schemas-upnp-org:service:" .. service .. ":1"
    local body = '<?xml version="1.0" encoding="utf-8"?>'
        .. '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        .. 's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
        .. "<u:" .. action .. ' xmlns:u="' .. urn .. '">'
        .. table.concat(body_args)
        .. "</u:" .. action .. "></s:Body></s:Envelope>"

    local last_err
    for _ = 1, 2 do -- one retry: speakers occasionally drop a connection
        local chunks = {}
        local ok, code = http.request{
            url = "http://" .. ip .. ":1400" .. SERVICES[service],
            method = "POST",
            headers = {
                ["Content-Type"] = 'text/xml; charset="utf-8"',
                ["Content-Length"] = tostring(#body),
                ["SOAPACTION"] = '"' .. urn .. "#" .. action .. '"',
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(chunks),
        }
        local resp = table.concat(chunks)
        if ok and code == 200 and resp ~= "" then
            return resp
        elseif ok and code == 500 then
            local upnp_code = tag(resp, "errorCode")
            return nil, "upnp:" .. (upnp_code or "?"), upnp_code
        end
        last_err = tostring(code)
    end
    return nil, last_err
end

--- Fetch topology from any speaker. Returns list of groups:
-- { {coordinator = uuid, members = { {uuid=, name=, ip=}, ...}, name = "A + B", ip = coord_ip}, ... }
function Sonos.getGroups(seed_ip)
    local resp, err = Sonos.soap(seed_ip, "ZoneGroupTopology", "GetZoneGroupState")
    if not resp then return nil, err end
    local state = Sonos.unescape(tag(resp, "ZoneGroupState") or "")
    local groups = {}
    for gattrs, ginner in state:gmatch("<ZoneGroup%s([^>]*)>(.-)</ZoneGroup>") do
        local ga = attrs(gattrs)
        local group = { coordinator = ga.Coordinator, id = ga.ID, members = {} }
        for mattrs in ginner:gmatch("<ZoneGroupMember%s([^>]*)>") do
            local m = attrs(mattrs)
            if m.Invisible ~= "1" and m.UUID then
                local ip = (m.Location or ""):match("^http://([%d%.]+):")
                local member = { uuid = m.UUID, name = m.ZoneName, ip = ip }
                if m.UUID == group.coordinator then
                    group.ip = ip
                    table.insert(group.members, 1, member)
                else
                    table.insert(group.members, member)
                end
            end
        end
        if group.ip and #group.members > 0 then
            local names = {}
            for i, m in ipairs(group.members) do names[i] = m.name end
            group.name = table.concat(names, " + ")
            table.insert(groups, group)
        end
    end
    table.sort(groups, function(a, b) return (a.name or "") < (b.name or "") end)
    return groups
end

--- Transport state: "PLAYING", "PAUSED_PLAYBACK", "STOPPED", "TRANSITIONING"
function Sonos.getState(ip)
    local resp, err = Sonos.soap(ip, "AVTransport", "GetTransportInfo", { {"InstanceID", 0} })
    if not resp then return nil, err end
    return tag(resp, "CurrentTransportState")
end

--- Current track: { title=, artist=, album=, uri=, duration=, position= }
function Sonos.getTrack(ip)
    local resp, err = Sonos.soap(ip, "AVTransport", "GetPositionInfo", { {"InstanceID", 0} })
    if not resp then return nil, err end
    local info = {
        uri = Sonos.unescape(tag(resp, "TrackURI")),
        duration = tag(resp, "TrackDuration"),
        position = tag(resp, "RelTime"),
    }
    local didl = Sonos.unescape(tag(resp, "TrackMetaData") or "")
    if didl ~= "" and didl ~= "NOT_IMPLEMENTED" then
        info.title = Sonos.unescape(tag(didl, "dc:title"))
        info.artist = Sonos.unescape(tag(didl, "dc:creator"))
        info.album = Sonos.unescape(tag(didl, "upnp:album"))
        -- cover: usually a relative /getaa?… link served by the speaker itself
        local art = Sonos.unescape(tag(didl, "upnp:albumArtURI"))
        if art and art ~= "" then
            if art:match("^/") then art = "http://" .. ip .. ":1400" .. art end
            if art:match("^https?://") then info.art = art end
        end
        -- Radio streams: "Artist - Title" lives in r:streamContent
        local stream = Sonos.unescape(tag(didl, "r:streamContent"))
        if stream and stream ~= "" then
            local radio = info.title
            local a, t = stream:match("^(.-) %- (.+)$")
            if a then
                info.artist, info.title = a, t
            else
                info.title = stream
            end
            info.album = radio
        end
    end
    -- Radio station name when nothing else is known
    if not info.title or info.title == "" then
        local mresp = Sonos.soap(ip, "AVTransport", "GetMediaInfo", { {"InstanceID", 0} })
        local mdidl = mresp and Sonos.unescape(tag(mresp, "CurrentURIMetaData") or "")
        if mdidl and mdidl ~= "" and mdidl ~= "NOT_IMPLEMENTED" then
            info.title = Sonos.unescape(tag(mdidl, "dc:title"))
        end
    end
    -- never show URIs/paths as names
    for _, k in ipairs({ "title", "artist", "album" }) do
        local v = info[k]
        if v and (v:match("^/") or v:find("://", 1, true) or v:match("^x%-") or v:find("?", 1, true) and not v:find(" ")) then
            info[k] = nil
        end
    end
    return info
end

function Sonos.play(ip)
    return Sonos.soap(ip, "AVTransport", "Play", { {"InstanceID", 0}, {"Speed", 1} })
end

function Sonos.pause(ip)
    return Sonos.soap(ip, "AVTransport", "Pause", { {"InstanceID", 0} })
end

function Sonos.next(ip)
    return Sonos.soap(ip, "AVTransport", "Next", { {"InstanceID", 0} })
end

function Sonos.previous(ip)
    return Sonos.soap(ip, "AVTransport", "Previous", { {"InstanceID", 0} })
end

--- Volume of a group (group volume if >1 member, otherwise speaker volume).
function Sonos.getVolume(group)
    local resp, err
    if #group.members > 1 then
        resp, err = Sonos.soap(group.ip, "GroupRenderingControl", "GetGroupVolume", { {"InstanceID", 0} })
        if not resp then return nil, err end
        return tonumber(tag(resp, "CurrentVolume"))
    end
    resp, err = Sonos.soap(group.ip, "RenderingControl", "GetVolume", { {"InstanceID", 0}, {"Channel", "Master"} })
    if not resp then return nil, err end
    return tonumber(tag(resp, "CurrentVolume"))
end

--- Change volume by delta; returns new volume.
function Sonos.changeVolume(group, delta)
    local resp, err
    if #group.members > 1 then
        Sonos.soap(group.ip, "GroupRenderingControl", "SnapshotGroupVolume", { {"InstanceID", 0} })
        resp, err = Sonos.soap(group.ip, "GroupRenderingControl", "SetRelativeGroupVolume",
            { {"InstanceID", 0}, {"Adjustment", delta} })
        if not resp then return nil, err end
        return tonumber(tag(resp, "NewVolume"))
    end
    resp, err = Sonos.soap(group.ip, "RenderingControl", "SetRelativeVolume",
        { {"InstanceID", 0}, {"Channel", "Master"}, {"Adjustment", delta} })
    if not resp then return nil, err end
    return tonumber(tag(resp, "NewVolume"))
end

--- Set an absolute volume (0..100) for a group or a single room; returns the volume.
function Sonos.setVolume(group, v)
    v = math.max(0, math.min(100, math.floor(v)))
    local resp, err
    if #group.members > 1 then
        Sonos.soap(group.ip, "GroupRenderingControl", "SnapshotGroupVolume", { {"InstanceID", 0} })
        resp, err = Sonos.soap(group.ip, "GroupRenderingControl", "SetGroupVolume",
            { {"InstanceID", 0}, {"DesiredVolume", v} })
    else
        resp, err = Sonos.soap(group.ip, "RenderingControl", "SetVolume",
            { {"InstanceID", 0}, {"Channel", "Master"}, {"DesiredVolume", v} })
    end
    if not resp then return nil, err end
    return v
end

--- Sonos household (system) ID, e.g. "Sonos_XXXXXXXXXXXXXXXX".
function Sonos.getHouseholdID(ip)
    local resp, err = Sonos.soap(ip, "DeviceProperties", "GetHouseholdID")
    if not resp then return nil, err end
    return tag(resp, "CurrentHouseholdID")
end

--- Find hosts with TCP 1400 open in a /24 (e.g. prefix "192.168.1.").
-- Parallel non-blocking connects; SSDP isn't usable because the Kindle's firewall
-- drops unsolicited UDP replies. Returns list of IPs (unverified).
function Sonos.scan(prefix, timeout, skip_ip)
    local socket = require("socket")
    timeout = timeout or 1.5
    local pending, map = {}, {}
    for i = 1, 254 do
        local ip = prefix .. i
        if ip ~= skip_ip then
            local s = socket.tcp()
            s:settimeout(0)
            s:connect(ip, 1400)
            pending[#pending + 1] = s
            map[s] = ip
        end
    end
    local found = {}
    local deadline = socket.gettime() + timeout
    while #pending > 0 and socket.gettime() < deadline do
        local _, writable = socket.select(nil, pending, deadline - socket.gettime())
        local ready = {}
        for _, s in ipairs(writable or {}) do ready[s] = true end
        local rest = {}
        for _, s in ipairs(pending) do
            if ready[s] then
                if s:getpeername() then found[#found + 1] = map[s] end
                s:close()
            else
                rest[#rest + 1] = s
            end
        end
        pending = rest
    end
    for _, s in ipairs(pending) do s:close() end
    table.sort(found, function(a, b)
        return tonumber(a:match("(%d+)$")) < tonumber(b:match("(%d+)$"))
    end)
    return found
end

--- Speaker UUID (RINCON_...) from its device description.
function Sonos.getUUID(ip)
    local chunks = {}
    local ok, code = http.request{
        url = "http://" .. ip .. ":1400/xml/device_description.xml",
        sink = ltn12.sink.table(chunks),
    }
    if not ok or code ~= 200 then return nil, tostring(code) end
    return table.concat(chunks):match("<UDN>uuid:(RINCON_[%w]+)</UDN>")
end

local DIDL_OPEN = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" '
    .. 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
    .. 'xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" '
    .. 'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'

--- Browse a ContentDirectory object, e.g. "FV:2" (favorites), "SQ:" (Sonos playlists).
-- Returns list of { id=, title=, uri=, meta=, class=, container=bool }.
function Sonos.browse(ip, object_id)
    local items = {}
    local start, total = 0, 1
    while start < total and start < 500 do
        local resp, err = Sonos.soap(ip, "ContentDirectory", "Browse", {
            {"ObjectID", object_id}, {"BrowseFlag", "BrowseDirectChildren"}, {"Filter", "*"},
            {"StartingIndex", start}, {"RequestedCount", 100}, {"SortCriteria", ""},
        })
        if not resp then return nil, err end
        total = tonumber(tag(resp, "TotalMatches")) or 0
        local returned = tonumber(tag(resp, "NumberReturned")) or 0
        local didl = Sonos.unescape(tag(resp, "Result") or "")
        for _, kind in ipairs({ "container", "item" }) do
            for elem_attrs, inner in didl:gmatch("<" .. kind .. "%s([^>]*)>(.-)</" .. kind .. ">") do
                local a = attrs(elem_attrs)
                local entry = {
                    id = a.id,
                    title = Sonos.unescape(tag(inner, "dc:title")),
                    uri = Sonos.unescape(tag(inner, "res")),
                    class = tag(inner, "upnp:class"),
                    -- favorites carry the real item's metadata in r:resMD (escaped DIDL)
                    meta = Sonos.unescape(tag(inner, "r:resMD")),
                    container = kind == "container",
                }
                if not entry.meta or entry.meta == "" then
                    entry.meta = DIDL_OPEN .. "<" .. kind .. " " .. elem_attrs .. ">" .. inner
                        .. "</" .. kind .. "></DIDL-Lite>"
                end
                local meta_class = entry.meta:match("<upnp:class>(.-)</upnp:class>")
                if meta_class then entry.class = meta_class end
                if entry.uri and entry.uri ~= "" then
                    table.insert(items, entry)
                end
            end
        end
        if returned == 0 then break end
        start = start + returned
    end
    return items
end

local function is_queueable(entry)
    local uri = entry.uri or ""
    if uri:match("^x%-rincon%-cpcontainer:") or uri:match("^x%-rincon%-playlist:")
        or uri:match("^file:///jffs/settings/savedqueues") then
        return true
    end
    if entry.class and entry.class:match("^object%.container") then return true end
    if entry.class and entry.class:match("^object%.item%.audioItem%.musicTrack") then return true end
    return false
end

--- Start playing a browse entry on a group's coordinator.
function Sonos.playItem(group, entry, before_play)
    local ip = group.ip
    local uuid = group.coordinator
    if not uuid or not uuid:match("^RINCON_") then
        local err
        uuid, err = Sonos.getUUID(ip)
        if not uuid then return nil, err or "no UUID" end
    end
    local ok, err
    if is_queueable(entry) then
        ok, err = Sonos.soap(ip, "AVTransport", "RemoveAllTracksFromQueue", { {"InstanceID", 0} })
        if not ok then return nil, err end
        ok, err = Sonos.soap(ip, "AVTransport", "AddURIToQueue", {
            {"InstanceID", 0}, {"EnqueuedURI", entry.uri}, {"EnqueuedURIMetaData", entry.meta or ""},
            {"DesiredFirstTrackNumberEnqueued", 0}, {"EnqueueAsNext", 0},
        })
        if not ok then return nil, err end
        ok, err = Sonos.soap(ip, "AVTransport", "SetAVTransportURI", {
            {"InstanceID", 0}, {"CurrentURI", "x-rincon-queue:" .. uuid .. "#0"}, {"CurrentURIMetaData", ""},
        })
        if not ok then return nil, err end
    else
        ok, err = Sonos.soap(ip, "AVTransport", "SetAVTransportURI", {
            {"InstanceID", 0}, {"CurrentURI", entry.uri}, {"CurrentURIMetaData", entry.meta or ""},
        })
        if not ok then return nil, err end
    end
    if before_play then before_play(ip) end
    return Sonos.play(ip)
end

--- Spotify on Sonos (service id 9). Builds a queueable entry for a Spotify URI
-- ("spotify:playlist:ID", "spotify:album:ID", "spotify:track:ID") using the
-- Spotify account linked in the Sonos app with serial number `sn`.
Sonos.SPOTIFY_SID = 9

function Sonos.spotifyEntry(spotify_uri, title, sn)
    local kind = spotify_uri:match("^spotify:(%a+):")
    local enc = spotify_uri:gsub(":", "%%3a")
    local sid = Sonos.SPOTIFY_SID
    local desc = string.format("SA_RINCON%d_X_#Svc%d-0-Token", sid * 256 + 7, sid * 256 + 7)
    local item_id, uri, class
    if kind == "playlist" then
        item_id = "1006206c" .. enc
        uri = string.format("x-rincon-cpcontainer:%s?sid=%d&flags=8300&sn=%d", item_id, sid, sn)
        class = "object.container.playlistContainer"
    elseif kind == "album" then
        item_id = "1004206c" .. enc
        uri = string.format("x-rincon-cpcontainer:%s?sid=%d&flags=8300&sn=%d", item_id, sid, sn)
        class = "object.container.album.musicAlbum"
    elseif kind == "track" then
        item_id = "00032020" .. enc
        uri = string.format("x-sonos-spotify:%s?sid=%d&flags=8224&sn=%d", enc, sid, sn)
        class = "object.item.audioItem.musicTrack"
    else
        return nil
    end
    local meta = DIDL_OPEN
        .. '<item id="' .. item_id .. '" parentID="" restricted="true">'
        .. "<dc:title>" .. Sonos.escape(title or "Spotify") .. "</dc:title>"
        .. "<upnp:class>" .. class .. "</upnp:class>"
        .. '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">' .. desc .. "</desc>"
        .. "</item></DIDL-Lite>"
    return { title = title, uri = uri, meta = meta, class = class, container = kind ~= "track" }
end

--- Replace the queue with a list of track entries and start playing.
-- Starts after the first track is queued, then appends the rest.
function Sonos.playTracks(group, entries, async_rest)
    if #entries == 0 then return nil, "no tracks" end
    local ip = group.ip
    local uuid = group.coordinator
    if not uuid or not uuid:match("^RINCON_") then
        local err
        uuid, err = Sonos.getUUID(ip)
        if not uuid then return nil, err or "no UUID" end
    end
    local function enqueue(e) return Sonos.enqueue(ip, e) end
    local ok, err = Sonos.soap(ip, "AVTransport", "RemoveAllTracksFromQueue", { {"InstanceID", 0} })
    if not ok then return nil, err end
    ok, err = enqueue(entries[1])
    if not ok then return nil, err end
    ok, err = Sonos.soap(ip, "AVTransport", "SetAVTransportURI", {
        {"InstanceID", 0}, {"CurrentURI", "x-rincon-queue:" .. uuid .. "#0"}, {"CurrentURIMetaData", ""},
    })
    if not ok then return nil, err end
    ok, err = Sonos.play(ip)
    if not ok then return nil, err end
    if not async_rest then
        for i = 2, #entries do enqueue(entries[i]) end
    end
    return true
end

function Sonos.enqueue(ip, e)
    return Sonos.soap(ip, "AVTransport", "AddURIToQueue", {
        {"InstanceID", 0}, {"EnqueuedURI", e.uri}, {"EnqueuedURIMetaData", e.meta or ""},
        {"DesiredFirstTrackNumberEnqueued", 0}, {"EnqueueAsNext", 0},
    })
end

--- Jump to track n (1-based) of the current queue.
function Sonos.seekTrack(ip, n)
    return Sonos.soap(ip, "AVTransport", "Seek", { {"InstanceID", 0}, {"Unit", "TRACK_NR"}, {"Target", n} })
end

--- Play mode: shuffle (bool) + repeat ("none"|"all"|"one").
local MODES = {
    NORMAL = { false, "none" }, REPEAT_ALL = { false, "all" }, REPEAT_ONE = { false, "one" },
    SHUFFLE_NOREPEAT = { true, "none" }, SHUFFLE = { true, "all" }, SHUFFLE_REPEAT_ONE = { true, "one" },
}

function Sonos.getPlayMode(ip)
    local resp, err = Sonos.soap(ip, "AVTransport", "GetTransportSettings", { {"InstanceID", 0} })
    if not resp then return nil, err end
    local m = MODES[tag(resp, "PlayMode") or "NORMAL"] or MODES.NORMAL
    return { shuffle = m[1], rep = m[2] }
end

function Sonos.setPlayMode(ip, shuffle, rep)
    for name, m in pairs(MODES) do
        if m[1] == (shuffle and true or false) and m[2] == rep then
            return Sonos.soap(ip, "AVTransport", "SetPlayMode", { {"InstanceID", 0}, {"NewPlayMode", name} })
        end
    end
    return nil, "bad mode"
end

--- Sleep timer: minutes (0/nil = off). Remaining as "H:MM:SS" or "".
function Sonos.setSleepTimer(ip, minutes)
    return Sonos.setSleepTimerSeconds(ip, (minutes or 0) * 60)
end

function Sonos.setSleepTimerSeconds(ip, seconds)
    local v = ""
    seconds = math.floor(seconds or 0)
    if seconds > 0 then
        v = string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return Sonos.soap(ip, "AVTransport", "ConfigureSleepTimer", { {"InstanceID", 0}, {"NewSleepTimerDuration", v} })
end

function Sonos.getSleepTimer(ip)
    local resp, err = Sonos.soap(ip, "AVTransport", "GetRemainingSleepTimerDuration", { {"InstanceID", 0} })
    if not resp then return nil, err end
    return tag(resp, "RemainingSleepTimerDuration") or ""
end

--- Sonos-native Spotify radio seeded by a track or an artist
-- (verified: "trackRadio"/"artistRadio" with class #trackRadio/#artistRadio advance to new songs).
function Sonos.spotifyRadioEntry(kind, id, title, sn)
    local sid = Sonos.SPOTIFY_SID
    local radio = kind == "artist" and "artistRadio" or "trackRadio"
    local enc = "spotify%3a" .. radio .. "%3a" .. id
    local desc = string.format("SA_RINCON%d_X_#Svc%d-0-Token", sid * 256 + 7, sid * 256 + 7)
    local class = "object.item.audioItem.audioBroadcast.#" .. radio
    local meta = DIDL_OPEN
        .. '<item id="100c206c' .. enc .. '" parentID="" restricted="true">'
        .. "<dc:title>" .. Sonos.escape(title or "Radio") .. "</dc:title>"
        .. "<upnp:class>" .. class .. "</upnp:class>"
        .. '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">' .. desc .. "</desc>"
        .. "</item></DIDL-Lite>"
    return {
        title = title,
        uri = string.format("x-sonosapi-radio:%s?sid=%d&flags=8300&sn=%d", enc, sid, sn),
        meta = meta,
        class = class,
    }
end

--- Grouping: make member_ip play along with the group led by coordinator_uuid.
function Sonos.joinGroup(member_ip, coordinator_uuid)
    return Sonos.soap(member_ip, "AVTransport", "SetAVTransportURI", {
        {"InstanceID", 0}, {"CurrentURI", "x-rincon:" .. coordinator_uuid}, {"CurrentURIMetaData", ""},
    })
end

--- Hand the group over to another member (new_uuid). rejoin=false: the old
-- coordinator leaves the group, so the music "moves" to the remaining rooms.
function Sonos.delegateTo(coordinator_ip, new_uuid, rejoin)
    return Sonos.soap(coordinator_ip, "AVTransport", "DelegateGroupCoordinationTo", {
        {"InstanceID", 0}, {"NewCoordinator", new_uuid}, {"RejoinGroup", rejoin and 1 or 0},
    })
end

--- Take a speaker out of its group (it becomes a standalone room).
function Sonos.leaveGroup(member_ip)
    return Sonos.soap(member_ip, "AVTransport", "BecomeCoordinatorOfStandaloneGroup", { {"InstanceID", 0} })
end

function Sonos.getSpeakerVolume(ip)
    local resp, err = Sonos.soap(ip, "RenderingControl", "GetVolume", { {"InstanceID", 0}, {"Channel", "Master"} })
    if not resp then return nil, err end
    return tonumber(tag(resp, "CurrentVolume"))
end

function Sonos.setSpeakerVolume(ip, v)
    return Sonos.soap(ip, "RenderingControl", "SetVolume",
        { {"InstanceID", 0}, {"Channel", "Master"}, {"DesiredVolume", math.max(0, math.min(100, v))} })
end

--- Find the Sonos account serial (sn) of the linked Spotify account by looking
-- at Spotify items already present in the queue / saved playlists. Returns list of sn seen.
function Sonos.spotifySerials(ip)
    local seen, list = {}, {}
    for _, obj in ipairs({ "Q:0", "SQ:", "FV:2" }) do
        local resp = Sonos.soap(ip, "ContentDirectory", "Browse", {
            {"ObjectID", obj}, {"BrowseFlag", "BrowseDirectChildren"}, {"Filter", "*"},
            {"StartingIndex", 0}, {"RequestedCount", 50}, {"SortCriteria", ""},
        })
        local didl = resp and Sonos.unescape(Sonos.unescape(tag(resp, "Result") or "")) or ""
        for sn in didl:gmatch("sid=9&flags=%d+&sn=(%d+)") do
            if not seen[sn] then seen[sn] = true; table.insert(list, tonumber(sn)) end
        end
        for sn in didl:gmatch("sid%%3d9%%26flags%%3d%d+%%26sn%%3d(%d+)") do
            if not seen[sn] then seen[sn] = true; table.insert(list, tonumber(sn)) end
        end
    end
    return list
end

--- UPnP error codes -> human readable (English; translated by l10n).
Sonos.ERRORS = {
    ["701"] = "Nothing to play (queue is empty)",
    ["711"] = "No next / previous track",
    ["712"] = "Cannot skip to this track",
    ["800"] = "Speaker is not the group coordinator",
}

function Sonos.describeError(err)
    err = tostring(err)
    local code = err:match("^upnp:(%d+)")
    if code then
        return Sonos.ERRORS[code] and T(Sonos.ERRORS[code]) or T("Sonos error %1", code)
    end
    if err == "timeout" then return T("Speaker is not responding (timeout)") end
    return T("Network error: %1", err)
end

return Sonos
