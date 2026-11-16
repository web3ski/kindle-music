--[[
Link a Spotify account from a phone, without a computer.

The Kindle shows a QR code. It points to a small web page served by the Kindle itself
on the home Wi-Fi (http://<kindle-ip>:8888/<random token>/). There the person pastes the
Client ID of their Spotify app (once) and signs in with Spotify. Spotify sends the browser
back to a static page on GitHub Pages (the registered redirect URI), which forwards the
code to the Kindle's address carried in `state`. The Kindle trades the code for tokens
with its PKCE verifier, which never leaves the Kindle, so the code alone is useless to
anyone else. The token is stored like tools/link_spotify.py does it.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("json")
local LuaSettings = require("luasettings")
local QRWidget = require("ui/widget/qrwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local socket = require("socket")
local PKCE = require("pkce")
local Spotify = require("spotify")
local T = require("l10n").T
local Screen = Device.screen

local SpotifyLink = {
    PORT = 8888,
    REDIRECT_URI = "https://web3ski.github.io/kindle-music/callback/",
    TIMEOUT = 15 * 60, -- the page stops after 15 minutes
}

local ACCOUNTS_DIR = DataStorage:getSettingsDir() .. "/sonos_spotify_accounts"

local function html_escape(s)
    return (tostring(s or ""):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
        ['"'] = "&quot;", ["'"] = "&#39;" }))
end

local function url_decode(s)
    s = (s or ""):gsub("%+", " ")
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function parse_query(q)
    local t = {}
    for pair in (q or ""):gmatch("[^&]+") do
        local k, v = pair:match("^([^=]*)=?(.*)$")
        if k and k ~= "" then t[url_decode(k)] = url_decode(v) end
    end
    return t
end

local function page(title, body)
    return [[<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>]] .. html_escape(title) .. [[</title>
<style>
body{font-family:-apple-system,system-ui,sans-serif;max-width:520px;margin:0 auto;padding:24px 18px;line-height:1.45;color:#111;background:#fff}
h1{font-size:22px;margin:0 0 12px}
ol{padding-left:20px}li{margin:6px 0}
input{width:100%;box-sizing:border-box;font:16px ui-monospace,monospace;padding:12px;border:1px solid #888;border-radius:8px}
button,.btn{display:block;width:100%;margin-top:14px;padding:14px;font-size:17px;font-weight:600;border:0;border-radius:10px;background:#1db954;color:#000;text-align:center;text-decoration:none}
code{background:#f0f0f0;padding:2px 5px;border-radius:4px;word-break:break-all}
.note{color:#555;font-size:14px}.ok{font-size:40px}
</style></head><body>]] .. body .. "</body></html>"
end

local function firewall(open)
    if not Device:isKindle() then return end
    local rule = "INPUT -p tcp --dport " .. SpotifyLink.PORT .. " -j ACCEPT"
    if open then
        os.execute("iptables -D " .. rule .. " 2>/dev/null")
        local rc = os.execute("iptables -I " .. rule .. " 2>/dev/null")
        logger.info("KindleMusic: link page, firewall open", rc)
    else
        local rc = os.execute("iptables -D " .. rule .. " 2>/dev/null")
        logger.info("KindleMusic: link page, firewall closed", rc)
    end
end

--- A Client ID already used on this Kindle (to prefill the form).
local function known_client_id(plugin)
    for _, acc in ipairs(plugin.spotify_accounts or {}) do
        local id = acc.settings and acc.settings:readSetting("client_id")
        if id then return id end
    end
    return plugin.settings and plugin.settings:readSetting("spotify_client_id") or ""
end

---------------------------------------------------------------------------
-- The tiny web server
---------------------------------------------------------------------------
local Server = {}
Server.__index = Server

function Server.start(plugin, ip, on_linked)
    local self = setmetatable({ plugin = plugin, on_linked = on_linked }, Server)
    firewall(true)
    local srv, err = socket.bind("*", SpotifyLink.PORT)
    if not srv then
        firewall(false)
        return nil, err
    end
    srv:settimeout(0)
    self.srv = srv
    self.token = PKCE.randomString(6) -- 8 characters, in the QR code only
    self.base = "/" .. self.token .. "/"
    self.url = "http://" .. ip .. ":" .. SpotifyLink.PORT .. self.base
    self.deadline = os.time() + SpotifyLink.TIMEOUT
    self.poll = function()
        self.poll_scheduled = false
        if not self.srv then return end
        if os.time() > self.deadline then return self:stop() end
        for _ = 1, 4 do
            local c = self.srv:accept()
            if not c then break end
            local ok, e = pcall(self.handle, self, c)
            if not ok then logger.warn("KindleMusic: link page error", e) end
            pcall(c.close, c)
        end
        if self.srv then
            self.poll_scheduled = true
            UIManager:scheduleIn(0.25, self.poll)
        end
    end
    self.poll_scheduled = true
    UIManager:scheduleIn(0.25, self.poll)
    logger.info("KindleMusic: link page at", ip, SpotifyLink.PORT)
    return self
end

function Server:stop()
    if self.poll_scheduled then UIManager:unschedule(self.poll) end
    self.poll_scheduled = false
    if self.srv then
        pcall(self.srv.close, self.srv)
        self.srv = nil
        firewall(false)
    end
end

local function send(c, status, ctype, body, extra)
    c:send("HTTP/1.1 " .. status .. "\r\nContent-Type: " .. ctype .. "\r\nContent-Length: " .. #body
        .. "\r\nCache-Control: no-store\r\nConnection: close\r\n" .. (extra or "") .. "\r\n" .. body)
end

function Server:handle(c)
    c:settimeout(3)
    local line = c:receive("*l")
    if not line then return end
    local method, target = line:match("^(%u+)%s+(%S+)")
    repeat
        local h = c:receive("*l")
    until not h or h == ""
    if method ~= "GET" or not target then
        return send(c, "405 Method Not Allowed", "text/plain", "")
    end
    local path, query = target:match("^([^?]*)%??(.*)$")
    local q = parse_query(query)
    if path == "/favicon.ico" then return send(c, "404 Not Found", "text/plain", "") end
    if path:sub(1, #self.base) ~= self.base then
        return send(c, "404 Not Found", "text/html; charset=utf-8",
            page("Kindle Music", "<h1>" .. html_escape(T("Scan the QR code on the Kindle again.")) .. "</h1>"))
    end
    local action = path:sub(#self.base + 1)
    if action == "" then return self:pageStart(c) end
    if action == "go" then return self:pageGo(c, q) end
    if action == "cb" then return self:pageCallback(c, q) end
    return send(c, "404 Not Found", "text/plain", "")
end

function Server:pageStart(c, error_text)
    local body = "<h1>" .. html_escape(T("Link Spotify to your Kindle")) .. "</h1>"
    if error_text then body = body .. "<p><b>" .. html_escape(error_text) .. "</b></p>" end
    body = body .. "<p>" .. html_escape(T("You need the Client ID of your Spotify app (developer.spotify.com → Dashboard → your app → Settings). In that app, the Redirect URI must be:")) .. "</p>"
        .. "<p><code>" .. html_escape(SpotifyLink.REDIRECT_URI) .. "</code></p>"
        .. '<form action="' .. self.base .. 'go" method="get">'
        .. '<label for="cid">Client ID</label>'
        .. '<input id="cid" name="client_id" autocomplete="off" autocapitalize="off" spellcheck="false" value="'
        .. html_escape(known_client_id(self.plugin)) .. '" placeholder="32 characters">'
        .. "<button type=\"submit\">" .. html_escape(T("Sign in with Spotify")) .. "</button></form>"
        .. "<p class=\"note\">" .. html_escape(T("Each person who uses the app must be added in the Spotify dashboard under User Management (up to 5 people).")) .. "</p>"
    send(c, "200 OK", "text/html; charset=utf-8", page("Kindle Music", body))
end

function Server:pageGo(c, q)
    local cid = (q.client_id or ""):gsub("%s", "")
    if not cid:match("^%x+$") or #cid ~= 32 then
        return self:pageStart(c, T("That doesn't look like a Client ID (32 letters and digits)."))
    end
    self.client_id = cid
    self.verifier, self.challenge = PKCE.pair()
    self.nonce = PKCE.randomString(12)
    local state = PKCE.b64url(JSON.encode{ r = self.url .. "cb", n = self.nonce })
    local auth = "https://accounts.spotify.com/authorize?" .. Spotify.form{
        client_id = cid,
        response_type = "code",
        redirect_uri = SpotifyLink.REDIRECT_URI,
        code_challenge_method = "S256",
        code_challenge = self.challenge,
        scope = Spotify.SCOPES,
        state = state,
        show_dialog = "true",
    }
    send(c, "302 Found", "text/html; charset=utf-8",
        page("Kindle Music", '<p><a class="btn" href="' .. html_escape(auth) .. '">' .. html_escape(T("Sign in with Spotify")) .. "</a></p>"),
        "Location: " .. auth .. "\r\n")
end

function Server:pageCallback(c, q)
    local function fail(text)
        send(c, "200 OK", "text/html; charset=utf-8", page("Kindle Music",
            "<h1>" .. html_escape(T("Spotify was not linked")) .. "</h1><p>" .. html_escape(text) .. "</p>"
            .. '<p><a class="btn" href="' .. self.base .. '">' .. html_escape(T("Try again")) .. "</a></p>"))
    end
    if q.error then return fail(T("Spotify said: %1", q.error)) end
    local st_ok, st = pcall(function() return JSON.decode(PKCE.b64urlDecode(q.state or "")) end)
    if not self.verifier or not q.code or not st_ok or type(st) ~= "table" or st.n ~= self.nonce then
        return fail(T("This sign-in does not belong to this Kindle. Start again from the QR code."))
    end
    local tok, err = Spotify.exchangeCode(self.client_id, q.code, self.verifier, SpotifyLink.REDIRECT_URI)
    if not tok then
        return fail(T("Spotify refused the sign-in (%1). Check that the Redirect URI in your Spotify app is exactly %2", tostring(err), SpotifyLink.REDIRECT_URI))
    end
    local me = Spotify.profile(tok.access_token) or {}
    local id = tostring(me.id or "account")
    local name = me.display_name or id
    local fname = id:gsub("[^%w%-_]", "")
    if fname == "" then fname = "account" end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(ACCOUNTS_DIR, "mode") ~= "directory" then lfs.mkdir(ACCOUNTS_DIR) end
    local acc = LuaSettings:open(ACCOUNTS_DIR .. "/" .. fname .. ".lua")
    acc:saveSetting("client_id", self.client_id)
    acc:saveSetting("refresh_token", tok.refresh_token)
    acc:saveSetting("account_name", name)
    acc:saveSetting("account_id", id)
    acc:saveSetting("play_mode", acc:readSetting("play_mode") or "auto")
    acc:flush()
    if self.plugin.settings then
        self.plugin.settings:saveSetting("spotify_client_id", self.client_id)
        self.plugin.settings:flush()
    end
    logger.info("KindleMusic: Spotify linked from phone:", name, me.product)
    local premium_note = (me.product and me.product ~= "premium")
        and ("<p class=\"note\">" .. html_escape(T("Note: without Spotify Premium, playback control through Spotify Connect will not work.")) .. "</p>") or ""
    send(c, "200 OK", "text/html; charset=utf-8", page("Kindle Music",
        '<p class="ok">✓</p><h1>' .. html_escape(T("Linked: %1", name)) .. "</h1><p>"
        .. html_escape(T("You can close this page. The Kindle is ready.")) .. "</p>" .. premium_note))
    UIManager:nextTick(function()
        self:stop()
        if self.on_linked then self.on_linked(id, name) end
    end)
end

---------------------------------------------------------------------------
-- The dialog on the Kindle
---------------------------------------------------------------------------
local LinkDialog = InputContainer:extend{
    url = nil,
    on_cancel = nil,
    modal = true,
}

function LinkDialog:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local w = math.floor(sw * 0.86)
    local inner = w - 4 * Size.padding.large
    local qr_side = math.floor(math.min(inner, sh * 0.42))
    local steps = T("1. Connect your phone to the same Wi-Fi as this Kindle.\n"
        .. "2. Scan the code with the phone's camera.\n"
        .. "3. Paste the Client ID of your Spotify app and sign in.")
    local buttons = ButtonTable:new{
        width = inner,
        buttons = { { { text = T("Cancel"), callback = function()
            UIManager:close(self)
        end } } },
        show_parent = self,
    }
    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Size.padding.large * 2,
        VerticalGroup:new{
            align = "center",
            TextWidget:new{ text = T("Add a Spotify account"), face = Font:getFace("cfont", 26), bold = true, max_width = inner },
            VerticalSpan:new{ width = Screen:scaleBySize(12) },
            QRWidget:new{ text = self.url, width = qr_side, height = qr_side },
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            TextWidget:new{ text = self.url, face = Font:getFace("cfont", 15), max_width = inner },
            VerticalSpan:new{ width = Screen:scaleBySize(14) },
            TextBoxWidget:new{ text = steps, face = Font:getFace("cfont", 19), width = inner },
            VerticalSpan:new{ width = Screen:scaleBySize(14) },
            buttons,
        },
    }
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, self.frame }
end

function LinkDialog:onShow()
    UIManager:setDirty(self, "ui")
end

function LinkDialog:onCloseWidget()
    UIManager:setDirty(nil, "ui")
    if self.on_cancel then self.on_cancel() end
end

--- Show the QR code and serve the link page until it's done or cancelled.
-- on_linked(id, name) is called after a successful link.
function SpotifyLink.show(plugin, on_linked)
    local net = plugin.networkInfo and plugin:networkInfo() or {}
    if not net.ip then
        UIManager:show(require("ui/widget/infomessage"):new{ text = T("Connect the Kindle to Wi-Fi first.") })
        return
    end
    local dlg
    local server, err = Server.start(plugin, net.ip, function(id, name)
        if dlg then
            dlg.on_cancel = nil
            UIManager:close(dlg)
        end
        if on_linked then on_linked(id, name) end
    end)
    if not server then
        UIManager:show(require("ui/widget/infomessage"):new{
            text = T("Could not open the link page on this Kindle: %1", tostring(err)) })
        return
    end
    dlg = LinkDialog:new{ url = server.url, on_cancel = function() server:stop() end }
    UIManager:show(dlg)
end

return SpotifyLink
