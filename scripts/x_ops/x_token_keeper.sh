#!/usr/bin/env bash
# X OAuth2 token keeper — 殿指示 2026-09-04 13:19『X API の認可も自動で出来るようにせよ。1 回目は俺が助ける』。
# 役割: (1) access token が 90 分以上古ければ refresh(rotate した refresh token も永続化)
#       (2) refresh が連続 3 回失敗したら PKCE の再認可 URL を生成し listener を起動、要操作 topic へ 1 回だけ送る
#       (3) 認可完了(listener が token ok)を検知したら失敗カウンタを戻し、ntfy(情報)で報告
# 起動: cron */30 分(scripts/x_ops/x_token_keeper.sh install で登録)。冪等。secret はログに出さない。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${X_POST_API_ENV_FILE:-$ROOT/config/x_api.env}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/multi-agent-shogun/x_token_keeper"
LOG="$ROOT/logs/x_token_keeper.log"
LISTENER="$ROOT/scripts/x_ops/x_oauth_listener.py"
REFRESH="$ROOT/scripts/x_ops/x_token_refresh.py"
MAX_AGE_SEC="${X_TOKEN_MAX_AGE_SEC:-5400}"   # 90 分(access token は 7200 秒で失効)
mkdir -p "$STATE_DIR" "$(dirname "$LOG")"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

if [[ "${1:-}" == "install" ]]; then
    line="*/30 * * * * bash $ROOT/scripts/x_ops/x_token_keeper.sh >> $ROOT/logs/x_token_keeper_cron.log 2>&1 # x-token-keeper"
    (crontab -l 2>/dev/null | grep -v '# x-token-keeper'; echo "$line") | crontab -
    echo "installed: $line"; exit 0
fi

[[ -f "$ENV_FILE" ]] || { log "env missing: $ENV_FILE"; exit 2; }
obtained="$(grep -E '^X_TOKEN_OBTAINED_AT=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d "'\"")"
if [[ "$obtained" =~ ^[0-9]{9,}$ ]]; then obtained_epoch="$obtained"; else obtained_epoch="$(date -d "$obtained" +%s 2>/dev/null || echo 0)"; fi
age=$(( $(date +%s) - obtained_epoch ))
fail_file="$STATE_DIR/refresh_failures"
fails="$(cat "$fail_file" 2>/dev/null || echo 0)"

# 認可完了の検知(listener が env を更新した)
if [[ -f "$STATE_DIR/reauth_sent" && "$age" -lt 600 ]]; then
    rm -f "$STATE_DIR/reauth_sent"; echo 0 >"$fail_file"
    log "reauth completed (token age ${age}s)"
    bash "$ROOT/scripts/ntfy.sh" "【将軍】X 再認可完了。以後は keeper が 30 分ごとに自動更新する" >/dev/null 2>&1 || true
fi

if [[ "$age" -lt "$MAX_AGE_SEC" ]]; then
    log "fresh (age ${age}s) skip"; exit 0
fi

if python3 "$REFRESH" "$ENV_FILE" >>"$LOG" 2>&1; then
    echo 0 >"$fail_file"; log "refreshed"; exit 0
fi
fails=$((fails + 1)); echo "$fails" >"$fail_file"; log "refresh failed ($fails)"
[[ "$fails" -ge 3 ]] || exit 1
[[ -f "$STATE_DIR/reauth_sent" ]] && { log "reauth already requested"; exit 1; }

# 再認可 URL(PKCE)を生成し listener を起動
python3 - "$ENV_FILE" <<'PY'
import base64, hashlib, os, secrets, sys, urllib.parse
env = {}
for l in open(sys.argv[1], encoding="utf-8"):
    if "=" in l and not l.lstrip().startswith("#"):
        k, v = l.strip().split("=", 1); env[k] = v.strip('"').strip("'")
ver = base64.urlsafe_b64encode(os.urandom(48)).decode().rstrip("=")
st = secrets.token_urlsafe(16)
open("/tmp/x_pkce_verifier.txt", "w").write(ver); open("/tmp/x_pkce_state.txt", "w").write(st)
ch = base64.urlsafe_b64encode(hashlib.sha256(ver.encode()).digest()).decode().rstrip("=")
q = urllib.parse.urlencode({"response_type": "code", "client_id": env["X_CLIENT_ID"], "redirect_uri": env["X_REDIRECT_URI"],
    "scope": "tweet.read tweet.write users.read media.write offline.access", "state": st,
    "code_challenge": ch, "code_challenge_method": "S256"})
open("/tmp/x_auth_url.txt", "w").write("https://x.com/i/oauth2/authorize?" + q)
PY
if ! ss -ltn 2>/dev/null | grep -q ':8585 '; then
    nohup python3 "$LISTENER" >>"$ROOT/logs/x_oauth_listener.out" 2>&1 &
    log "listener started"
fi
bash "$ROOT/scripts/ntfy_action.sh" "X 再認可(要操作): refresh が 3 回失敗。ブラウザで開いて許可: $(cat /tmp/x_auth_url.txt)" >/dev/null 2>&1 && touch "$STATE_DIR/reauth_sent"
log "reauth requested"
exit 1
