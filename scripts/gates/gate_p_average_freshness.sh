#!/usr/bin/env bash
# ============================================================
# gate_p_average_freshness.sh
# p̄バッチの鮮度チェックゲート
#
# Usage:
#   bash scripts/gates/gate_p_average_freshness.sh
#
# 判定:
#   - calculated_at が 30日以内: OK
#   - 30-35日: WARN
#   - 35日超: ALERT + ntfy通知
#   - null/取得失敗: ALERT + ntfy通知
#
# Exit code: 0=OK, 1=ALERT, 2=WARN
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib/project_path.sh
if [ -f "${SCRIPT_DIR}/scripts/lib/project_path.sh" ]; then
    source "${SCRIPT_DIR}/scripts/lib/project_path.sh"
else
    get_project_path() {
        case "$1" in
            dm-signal) printf '%s\n' "${DM_SIGNAL_DIR:-/mnt/c/Python_app/DM-signal}" ;;
            *) return 1 ;;
        esac
    }
fi
_DM_PATH="$(get_project_path 'dm-signal')"
ENV_FILE="${P_AVERAGE_ENV_FILE:-${_DM_PATH}/backend/.env}"
API_BASE="${P_AVERAGE_API_BASE:-https://dm-signal-backend.onrender.com}"
CACHE_FILE="${P_AVERAGE_CACHE_FILE:-/tmp/gate_p_average_cache.txt}"
CURL_BIN="${P_AVERAGE_CURL_BIN:-curl}"
CACHE_TTL_SECONDS=21600  # 6時間キャッシュ(p̄は月次更新のため十分)

# キャッシュチェック: 6時間以内ならAPI呼出しをスキップ
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -lt "$CACHE_TTL_SECONDS" ]; then
        head -1 "$CACHE_FILE"
        cached_exit=$(awk -F= '/^exit_code=/{print $2; exit}' "$CACHE_FILE" 2>/dev/null)
        exit "${cached_exit:-0}"
    fi
fi

# 認証情報を取得
if [ ! -f "$ENV_FILE" ]; then
    echo "ALERT: p̄鮮度: backend/.env が見つかりません"
    echo "  action: ${_DM_PATH}/backend/.env を配置し ADMIN_USER および ADMIN_PASS を設定せよ"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — backend/.env不在"
    exit 1
fi

ADMIN_USER=""
ADMIN_PASS=""
while IFS='=' read -r key value; do
    case "$key" in
        ADMIN_USER) ADMIN_USER="$value" ;;
        ADMIN_PASS) ADMIN_PASS="$value" ;;
    esac
done < <(grep -E '^ADMIN_(USER|PASS)=' "$ENV_FILE" | tr -d '\r')

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "ALERT: p̄鮮度: ADMIN認証情報が取得できません"
    echo "  action: backend/.env に ADMIN_USER=<user> および ADMIN_PASS=<pass> を設定し再実行せよ"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — ADMIN認証情報不在"
    exit 1
fi

# API呼出し
response_file="$(mktemp)"
curl_meta_file="$(mktemp)"
curl_err_file="$(mktemp)"
cleanup_tmp() {
    rm -f "$response_file" "$curl_meta_file" "$curl_err_file"
}
trap cleanup_tmp EXIT

curl_exit=0
"$CURL_BIN" -sS -f -u "${ADMIN_USER}:${ADMIN_PASS}" \
    --max-time 15 \
    -o "$response_file" \
    -w '%{http_code} %{time_total}' \
    "${API_BASE}/api/p-average" >"$curl_meta_file" 2>"$curl_err_file" || curl_exit=$?

IFS=' ' read -r http_code elapsed < "$curl_meta_file" || true
IFS= read -r curl_err < "$curl_err_file" || curl_err=""
http_code="${http_code:-000}"
elapsed="${elapsed:-unknown}"
_api_tmp="${API_BASE#*://}"; api_host="${_api_tmp%%/*}"

if [ "$curl_exit" -ne 0 ]; then
    case "$curl_exit:$http_code" in
        6:*)
            echo "ALERT: p̄鮮度: API_BASE DNS解決失敗 (HTTP ${http_code}, curl_exit=${curl_exit}, elapsed=${elapsed}s)"
            echo "  diagnosis: curl_exit=6 はホスト名を解決できない状態。DNS/API_BASEを先に確認し、サーバ到達性・cold sleep・バッチ鮮度はAPI到達後に確認せよ"
            echo "  action: API_BASE=${API_BASE} host=${api_host}。getent hosts ${api_host} と P_AVERAGE_API_BASE/backend/.env の参照先を確認せよ"
            if [ -n "$curl_err" ]; then
                echo "  curl_error: ${curl_err}"
            fi
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — API_BASE DNS解決失敗 HTTP ${http_code} curl ${curl_exit}"
            ;;
        22:401|22:403)
            echo "ALERT: p̄鮮度: API認証失敗 (HTTP ${http_code}, curl_exit=${curl_exit}, elapsed=${elapsed}s)"
            echo "  action: backend/.env の ADMIN_USER/ADMIN_PASS と Render 側の認証設定を照合せよ"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — API認証失敗 HTTP ${http_code}"
            ;;
        22:5*)
            echo "ALERT: p̄鮮度: APIサーバーエラー (HTTP ${http_code}, curl_exit=${curl_exit}, elapsed=${elapsed}s)"
            echo "  action: Render バックエンド (${API_BASE}) の稼働状態とログを確認せよ"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — API 5xx HTTP ${http_code}"
            ;;
        28:*)
            echo "ALERT: p̄鮮度: APIタイムアウト (HTTP ${http_code}, curl_exit=${curl_exit}, elapsed=${elapsed}s)"
            echo "  action: Render バックエンド (${API_BASE}) のcold start/timeoutを確認せよ"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — APIタイムアウト"
            ;;
        *)
            echo "ALERT: p̄鮮度: API呼出し失敗 (HTTP ${http_code}, curl_exit=${curl_exit}, elapsed=${elapsed}s)"
            echo "  action: Render バックエンド (${API_BASE}) が起動中か確認せよ。curl -u \$ADMIN_USER:\$ADMIN_PASS ${API_BASE}/api/p-average で手動確認"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — API応答なし HTTP ${http_code} curl ${curl_exit}"
            ;;
    esac
    exit 1
fi

calc_result="$(
    python3 - "$response_file" <<'PY' 2>/dev/null
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
calculated_at = (data.get("data") or {}).get("calculated_at")
if not calculated_at:
    print("NULL\t")
    raise SystemExit(0)
try:
    normalized = str(calculated_at).replace("Z", "+00:00")
    calc_dt = datetime.fromisoformat(normalized)
    if calc_dt.tzinfo is None:
        calc_dt = calc_dt.replace(tzinfo=timezone.utc)
    now_dt = datetime.now(timezone.utc)
    days_ago = int((now_dt.timestamp() - calc_dt.timestamp()) // 86400)
except Exception:
    print(f"PARSE\t{calculated_at}")
    raise SystemExit(0)
print(f"OK\t{calculated_at}\t{days_ago}")
PY
)" || calc_result="NULL"

IFS=$'\t' read -r calc_status calculated_at days_ago <<< "$calc_result"

if [ "$calc_status" = "NULL" ] || [ -z "${calculated_at:-}" ]; then
    echo "ALERT: p̄ never calculated (calculated_at=null)"
    echo "  action: p̄バッチが未実行。DM-Signal の p̄計算エンドポイントを呼び出し calculated_at を設定せよ"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄未計算(calculated_at=null)"
    exit 1
fi

if [ "$calc_status" = "PARSE" ]; then
    echo "ALERT: p̄鮮度: calculated_at パース失敗(${calculated_at})"
    echo "  action: DM-Signal バックエンドの p̄計算ロジックを確認し、calculated_at を ISO 8601 形式(YYYY-MM-DDTHH:MM:SSZ)で出力するよう修正せよ"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄鮮度チェック失敗 — 日付パース不可"
    exit 1
fi

if [ "$days_ago" -gt 35 ]; then
    msg="ALERT: p̄ stale (${days_ago}d)"
    echo "$msg" | tee "$CACHE_FILE"
    echo "  action: 月次p̄バッチが${days_ago}日間未実行。DM-Signal の p̄計算を手動トリガーし calculated_at を更新せよ"
    echo "exit_code=1" >> "$CACHE_FILE"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄計算が${days_ago}日前"
    exit 1
elif [ "$days_ago" -gt 30 ]; then
    msg="WARN: p̄ calculated_at ${days_ago}d ago"
    echo "$msg" | tee "$CACHE_FILE"
    echo "  action: p̄計算から${days_ago}日経過。月次バッチのスケジュールを確認し、必要に応じて手動実行せよ"
    echo "exit_code=2" >> "$CACHE_FILE"
    exit 2
else
    msg="OK: p̄ calculated_at within 30 days (${days_ago}d ago, ${calculated_at})"
    echo "$msg" | tee "$CACHE_FILE"
    echo "exit_code=0" >> "$CACHE_FILE"
    exit 0
fi
