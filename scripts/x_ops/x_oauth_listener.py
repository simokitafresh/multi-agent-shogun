#!/usr/bin/env python3
"""127.0.0.1:8585/callback で code を受け取り、即座に token 交換して config/x_api.env に追記する(30 秒失効対策)。
secret はログに出さない。1 回受けたら終了。"""
import base64, http.server, json, os, sys, urllib.parse, urllib.request, time

ENV = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "config", "x_api.env")
VERIFIER = open("/tmp/x_pkce_verifier.txt").read().strip()
STATE = open("/tmp/x_pkce_state.txt").read().strip()
LOG = "/tmp/x_oauth_listener.log"

def env():
    d = {}
    for line in open(ENV):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            d[k] = v.strip().strip('"')
    return d

def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path != "/callback" or "code" not in q:
            self.send_response(404); self.end_headers(); return
        if q.get("state", [""])[0] != STATE:
            self.send_response(400); self.end_headers(); self.wfile.write(b"state mismatch"); log("state mismatch"); return
        e = env()
        data = urllib.parse.urlencode({
            "grant_type": "authorization_code", "code": q["code"][0],
            "redirect_uri": e["X_REDIRECT_URI"], "code_verifier": VERIFIER, "client_id": e["X_CLIENT_ID"],
        }).encode()
        req = urllib.request.Request("https://api.x.com/2/oauth2/token", data=data)
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        basic = base64.b64encode(f"{e['X_CLIENT_ID']}:{e['X_CLIENT_SECRET']}".encode()).decode()
        req.add_header("Authorization", "Basic " + basic)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                tok = json.loads(r.read().decode())
        except urllib.error.HTTPError as ex:
            body = ex.read().decode()
            log(f"token exchange http={ex.code} body={body[:200]}")
            self.send_response(500); self.end_headers(); self.wfile.write(("token exchange failed: " + body).encode()); return
        # 2026-09-04 13:35 将軍 D0(T3-S-65): 追記方式は X_REFRESH_TOKEN を 2 行にし、keeper が旧行(head -1)を読んで
        # 旧 refresh token で refresh→X の再利用検知で新 grant ごと revoke された。置換方式+ISO 時刻に変更。
        repl = {"X_ACCESS_TOKEN": tok["access_token"], "X_TOKEN_OBTAINED_AT": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        if "refresh_token" in tok:
            repl["X_REFRESH_TOKEN"] = tok["refresh_token"]
        lines, seen = [], set()
        for line in open(ENV, encoding="utf-8").read().splitlines():
            k = line.split("=", 1)[0].strip() if "=" in line else ""
            if k in repl:
                if k in seen:
                    continue
                lines.append(f"{k}={repl[k]}"); seen.add(k)
            else:
                lines.append(line)
        for k, v in repl.items():
            if k not in seen:
                lines.append(f"{k}={v}")
        tmp = ENV + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.chmod(tmp, 0o600); os.replace(tmp, ENV)
        log(f"token ok scope={tok.get('scope')} expires_in={tok.get('expires_in')} refresh={'refresh_token' in tok}")
        self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8"); self.end_headers()
        self.wfile.write("認可完了。token を保存しました。このタブは閉じてよい。".encode())
        self.server.done = True

srv = http.server.HTTPServer(("127.0.0.1", 8585), H)
srv.done = False
log("listening 127.0.0.1:8585")
while not srv.done:
    srv.handle_request()
log("exit")
