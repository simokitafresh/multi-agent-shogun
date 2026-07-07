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

_SELF_PATH="${BASH_SOURCE[0]:-$0}"
[[ "$_SELF_PATH" != /* ]] && _SELF_PATH="$PWD/$_SELF_PATH"
SCRIPT_DIR="$(cd "$(dirname "$_SELF_PATH")/../.." && pwd)"

if [ -n "${P_AVERAGE_ENV_FILE:-}" ]; then
    # Tests and ad-hoc checks may run this repo script from outside the repo.
    # When the env file is explicit, avoid repo-root discovery entirely.
    _DM_PATH="${DM_SIGNAL_DIR:-/mnt/c/Python_app/DM-signal}"
else
    # shellcheck source=scripts/lib/project_path.sh
    if [ -f "${SCRIPT_DIR}/scripts/lib/project_path.sh" ]; then
        source "${SCRIPT_DIR}/scripts/lib/project_path.sh"
        _REPO_ROOT_CACHE="${SCRIPT_DIR}"
    else
        get_project_path() {
            case "$1" in
                dm-signal) printf '%s\n' "${DM_SIGNAL_DIR:-/mnt/c/Python_app/DM-signal}" ;;
                *) return 1 ;;
            esac
        }
    fi
    _DM_PATH="$(get_project_path 'dm-signal')"
fi
ENV_FILE="${P_AVERAGE_ENV_FILE:-${_DM_PATH}/backend/.env}"
API_BASE="${P_AVERAGE_API_BASE:-https://dm-signal-backend.onrender.com}"
CACHE_FILE="${P_AVERAGE_CACHE_FILE:-/tmp/gate_p_average_cache.txt}"
CURL_BIN="${P_AVERAGE_CURL_BIN:-curl}"
CACHE_TTL_SECONDS=21600  # 6時間キャッシュ(p̄は月次更新のため十分)

cache_exit_matches_status_line() {
    local status_line="$1"
    local cached_exit="$2"

    case "$cached_exit" in
        0) [[ "$status_line" == OK:* ]] ;;
        1) [[ "$status_line" == ALERT:* ]] ;;
        2) [[ "$status_line" == WARN:* ]] ;;
        *) return 1 ;;
    esac
}

# キャッシュチェック: 6時間以内ならAPI呼出しをスキップ
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -lt "$CACHE_TTL_SECONDS" ]; then
        cached_status_line="$(head -1 "$CACHE_FILE" 2>/dev/null || true)"
        cached_exit=$(awk -F= '/^exit_code=/{print $2; exit}' "$CACHE_FILE" 2>/dev/null)
        if cache_exit_matches_status_line "$cached_status_line" "${cached_exit:-}"; then
            printf '%s\n' "$cached_status_line"
            exit "$cached_exit"
        fi
        echo "WARN: p̄ cache invalid; ignoring stale/corrupt cache and rechecking API"
        echo "  cache_file: ${CACHE_FILE}"
        echo "  cache_status_line: ${cached_status_line:-empty}"
        echo "  cache_exit_code: ${cached_exit:-missing}"
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

db_freshness_fallback() {
    if [ -n "${P_AVERAGE_DB_FALLBACK_RESULT:-}" ]; then
        printf '%s\n' "$P_AVERAGE_DB_FALLBACK_RESULT"
        return 0
    fi

    python3 - "$ENV_FILE" <<'PY' 2>/dev/null
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

try:
    import psycopg2
except Exception:
    raise SystemExit(1)

env_file = sys.argv[1]
database_url = ""
with open(env_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "DATABASE_URL":
            database_url = value.strip().strip('"').strip("'")
            break

if not database_url:
    database_url = os.environ.get("DATABASE_URL", "")
if not database_url:
    raise SystemExit(1)

parsed = urlparse(database_url)
conn = psycopg2.connect(
    host=parsed.hostname,
    port=parsed.port or 5432,
    dbname=(parsed.path or "").lstrip("/"),
    user=parsed.username,
    password=parsed.password,
    sslmode="require",
    connect_timeout=8,
)
cur = conn.cursor()
cur.execute(
    """
    SELECT
        (SELECT COUNT(*) FROM p_average_results) AS portfolio_count,
        (SELECT MAX(calculated_at) FROM p_average_results) AS portfolio_calculated_at,
        (SELECT COUNT(*) FROM benchmark_p_average_results) AS benchmark_count,
        (SELECT MAX(calculated_at) FROM benchmark_p_average_results) AS benchmark_calculated_at
    """
)
portfolio_count, portfolio_calculated_at, benchmark_count, benchmark_calculated_at = cur.fetchone()
cur.close()
conn.close()

values = [v for v in (portfolio_calculated_at, benchmark_calculated_at) if v is not None]
if not values:
    print("NULL\t\t\t")
    raise SystemExit(0)
calculated_at = max(values)
if calculated_at.tzinfo is None:
    calculated_at = calculated_at.replace(tzinfo=timezone.utc)
days_ago = int((datetime.now(timezone.utc) - calculated_at).total_seconds() // 86400)
print(f"OK\t{calculated_at.isoformat()}\t{days_ago}\tportfolio_count={portfolio_count}, benchmark_count={benchmark_count}")
PY
}

classify_db_fallback_on_dns_failure() {
    local db_status="$1"
    local db_calculated_at="$2"
    local db_days_ago="$3"
    local db_counts="$4"

    if [ "$db_status" != "OK" ] || [ -z "${db_calculated_at:-}" ] || [ -z "${db_days_ago:-}" ]; then
        echo "  db_fallback: unavailable_or_empty"
        return 1
    fi

    case "$db_days_ago" in
        ''|*[!0-9]*)
            echo "  db_fallback: p̄ DB freshness unknown (${db_days_ago:-empty}d ago, ${db_calculated_at}; ${db_counts})"
            echo "  classification: API_BASE/DNS到達性問題に加え、DB fallback鮮度を数値判定できない"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄ API_BASE DNS解決失敗。DB鮮度判定不能"
            return 1
            ;;
    esac

    if [ "$db_days_ago" -gt 35 ]; then
        echo "  db_fallback: p̄ DB stale (${db_days_ago}d ago, ${db_calculated_at}; ${db_counts})"
        echo "  classification: API_BASE/DNS到達性問題に加え、p̄ DB calculated_at が stale"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "ALERT: p̄ API_BASE DNS解決失敗。DB鮮度stale ${db_days_ago}日前"
        return 1
    elif [ "$db_days_ago" -gt 30 ]; then
        echo "  db_fallback: p̄ DB freshness WARN (${db_days_ago}d ago, ${db_calculated_at}; ${db_counts})"
        echo "  classification: API_BASE/DNS到達性問題。p̄ DB calculated_at はWARN域"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "WARN: p̄ API_BASE DNS解決失敗。DB鮮度WARN ${db_days_ago}日前"
        return 2
    fi

    echo "  db_fallback: p̄ DB freshness OK (${db_days_ago}d ago, ${db_calculated_at}; ${db_counts})"
    echo "  classification: API_BASE/DNS到達性の問題。p̄バッチ未実行/staleではない"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "WARN: p̄ API_BASE DNS解決失敗。ただしDB鮮度OK ${db_days_ago}日前"
    return 2
}

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
            db_fallback_result="$(db_freshness_fallback || true)"
            IFS=$'\t' read -r db_status db_calculated_at db_days_ago db_counts <<< "$db_fallback_result"
            classify_db_fallback_on_dns_failure "$db_status" "$db_calculated_at" "$db_days_ago" "$db_counts"
            fallback_exit=$?
            if [ "$fallback_exit" -eq 2 ]; then
                exit 2
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
