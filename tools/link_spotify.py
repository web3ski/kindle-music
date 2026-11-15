#!/usr/bin/env python3
"""
Link a Kindle (kindlemusic.koplugin) with a Spotify account — run once per Kindle.

    python3 tools/link_spotify.py <kindle-ip> [--client-id ID] [--sn N] [--mode auto|connect|sonos]

1. Opens the Spotify login in your browser (Authorization Code + PKCE, no client secret).
2. Receives the code on http://127.0.0.1:8888/callback and exchanges it for a refresh token.
3. Writes koreader/settings/sonos_spotify_accounts/<spotify-user-id>.lua on the Kindle over SSH
   (several accounts can be linked; pick the active one on the Kindle: Tools → Kindle Music → Spotify) (you type the Kindle
   root password when ssh asks). The token is never stored on this Mac.

Client ID: pass --client-id once; it is remembered in tools/spotify_client_id.txt
(not secret, but kept out of git anyway).

--sn: serial number of this person's Spotify account inside the Sonos app (1 = first
Spotify account added to Sonos, 2 = second, ...). Only used when the plugin has to play
via Sonos instead of Spotify Connect. Default: auto-detect.

Only Python standard library is used.
"""
import argparse
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

REDIRECT_URI = "http://127.0.0.1:8888/callback"
SCOPES = " ".join([
    "playlist-read-private",
    "playlist-read-collaborative",
    "user-library-read",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-read-private",
    "user-top-read",
    "user-read-recently-played",
    "user-follow-read",
])
HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT_ID_FILE = os.path.join(HERE, "spotify_client_id.txt")
REMOTE_DIR = "/mnt/us/koreader/settings/sonos_spotify_accounts"


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def pkce_pair():
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(64)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def wait_for_code(state):
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.urlparse(self.path)
            if q.path != "/callback":
                self.send_response(404)
                self.end_headers()
                return
            params = urllib.parse.parse_qs(q.query)
            if params.get("state", [""])[0] != state:
                result["error"] = "state mismatch"
            elif "error" in params:
                result["error"] = params["error"][0]
            else:
                result["code"] = params.get("code", [""])[0]
            ok = "code" in result
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = ("Done! You can close this tab and go back to the terminal." if ok
                   else "Error: " + result.get("error", "?"))
            self.wfile.write(f"<html><body style='font:20px sans-serif;padding:40px'>{msg}</body></html>".encode())
            threading.Thread(target=self.server.shutdown, daemon=True).start()

        def log_message(self, *args):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 8888), Handler)
    srv.serve_forever()
    if "code" not in result:
        sys.exit("Sign-in failed: " + result.get("error", "?"))
    return result["code"]


def post_form(url, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def get_json(url, token):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kindle_ip")
    ap.add_argument("--client-id")
    ap.add_argument("--sn", type=int, help="Spotify account serial in Sonos (1, 2, ...)")
    ap.add_argument("--mode", choices=["auto", "connect", "sonos"], default="auto")
    ap.add_argument("--add", action="store_true",
                    help="(default behaviour) add this account next to already linked ones")
    ap.add_argument("--iface", default="en0",
                    help="network interface for SSH (works around VPNs like Tailscale; '' to disable)")
    args = ap.parse_args()

    client_id = args.client_id
    if client_id:
        with open(CLIENT_ID_FILE, "w") as f:
            f.write(client_id.strip())
    elif os.path.exists(CLIENT_ID_FILE):
        client_id = open(CLIENT_ID_FILE).read().strip()
    if not client_id:
        sys.exit("Podaj --client-id (Client ID z developer.spotify.com/dashboard)")

    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(16)
    auth_url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
        "scope": SCOPES,
        "state": state,
        "show_dialog": "true",  # always ask which account — important when linking several Kindles
    })
    print("Opening the Spotify sign-in page in your browser…")
    print("If it doesn't open, go to:\n" + auth_url + "\n")
    webbrowser.open(auth_url)
    code = wait_for_code(state)

    tok = post_form("https://accounts.spotify.com/api/token", {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "client_id": client_id,
        "code_verifier": verifier,
    })
    me = get_json("https://api.spotify.com/v1/me", tok["access_token"])
    name = me.get("display_name") or me.get("id")
    print(f"Signed in as: {name} (account {me.get('product', '?')})")
    if me.get("product") != "premium":
        print("Note: without Spotify Premium, playback control through Spotify Connect will not work.")

    lines = [
        "-- written by tools/link_spotify.py — Spotify link for this Kindle (keep private)",
        "return {",
        f'    ["client_id"] = {lua_str(client_id)},',
        f'    ["refresh_token"] = {lua_str(tok["refresh_token"])},',
        f'    ["account_name"] = {lua_str(name)},',
        f'    ["account_id"] = {lua_str(me.get("id", ""))},',
        f'    ["play_mode"] = {lua_str(args.mode)},',
    ]
    if args.sn:
        lines.append(f'    ["sonos_sn"] = {args.sn},')
    lines.append("}")
    content = "\n".join(lines) + "\n"

    ssh = ["ssh", "-o", "StrictHostKeyChecking=accept-new", "-o", "PubkeyAuthentication=no"]
    if args.iface:
        ssh += ["-o", f"ProxyCommand=nc -b {args.iface} %h %p"]
    acc_id = "".join(c for c in me.get("id", "account") if c.isalnum() or c in "-_") or "account"
    remote = f"{REMOTE_DIR}/{acc_id}.lua"
    ssh += [f"root@{args.kindle_ip}", f"mkdir -p {REMOTE_DIR} && cat > {remote}.tmp && mv {remote}.tmp {remote}"]
    print(f"Copying the link to the Kindle at {args.kindle_ip} (enter the Kindle's SSH password)…")
    r = subprocess.run(ssh, input=content.encode())
    if r.returncode != 0:
        sys.exit("Could not write to the Kindle (is SSH enabled?)")
    print("Done. Restart KOReader on the Kindle (or reopen the remote), then: remote → Spotify.")


if __name__ == "__main__":
    main()
