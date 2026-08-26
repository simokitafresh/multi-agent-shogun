#!/usr/bin/env bash
# semantic-links: [[CDP(ブラウザ操作能力)]]
# cdp_measure.sh — CDP計測ワンコマンドラッパー（なぜなぜ7回 自動化ターゲット1-3）
#
# Usage: bash scripts/cdp/cdp_measure.sh <cmd_id> [--baseline <path>] [--pages <page1> <page2>...]
#
# 自動実行:
#   Phase 1: Pre-flight check（認証確認+Chrome CDP接続確認）
#   Phase 2: Artifact path分離（cmd_idベースで出力先を自動決定）
#   Phase 3: 計測実行（perf_measure.py --profile production）
#   Phase 4: ベースライン比較（--baselineで自動比較）
#
# 根因対処:
#   - cmd_2268事故: artifact競合 → cmd_idベース出力先で上書き不可能
#   - cmd_2271事故: 認証不成立 → pre-flightで事前検証
#   - 忍者判断依存 → 全ステップ自動化
set -euo pipefail

# ─── 引数解析 ───
CMD_ID="${1:-}"
if [[ -z "$CMD_ID" ]]; then
    echo "ERROR: cmd_id必須。Usage: bash scripts/cdp/cdp_measure.sh <cmd_id> [--baseline <path>]" >&2
    exit 1
fi
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/project_path.sh
if [ -f "${SCRIPT_DIR}/scripts/lib/project_path.sh" ]; then
    source "${SCRIPT_DIR}/scripts/lib/project_path.sh"
else
    get_project_path() {
        case "$1" in
            auto-ops) printf '%s\n' "/mnt/c/Python_app/auto-ops" ;;
            dm-signal) printf '%s\n' "${DM_SIGNAL_DIR:-/mnt/c/Python_app/DM-signal}" ;;
            *) return 1 ;;
        esac
    }
fi
AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"
AUTO_OPS_ROOT="$(get_project_path 'auto-ops' 2>/dev/null || printf '%s\n' "$AUTO_OPS_ROOT")"
TEMP_CONFIG=""
CDP_LOCK_ACQUIRED=0
CDP_RECEIPT=""

# 終了時にCDPブラウザをcleanup（成功/失敗/中断どれでも）
_cdp_cleanup() {
    if [[ -n "${TEMP_CONFIG:-}" && -f "$TEMP_CONFIG" ]]; then
        rm -f "$TEMP_CONFIG"
    fi
    if [[ -n "${CDP_RECEIPT:-}" && -f "$CDP_RECEIPT" ]]; then
        python3 "${SCRIPT_DIR}/scripts/cdp/cdp_session.py" cleanup --receipt "$CDP_RECEIPT" >/dev/null || true
        rm -f "$CDP_RECEIPT"
        CDP_RECEIPT=""
    fi
    if [[ "${CDP_LOCK_ACQUIRED:-0}" != "1" ]]; then
        return 0
    fi
    if [[ -n "${CDP_REQUESTED_PORT:-}" && "${CDP_PORT:-}" != "$CDP_REQUESTED_PORT" ]]; then
        echo "  SKIP: cleanup skipped because requested port ${CDP_REQUESTED_PORT} differs from actual port ${CDP_PORT}"
        return 0
    fi
}
trap _cdp_cleanup EXIT
PERF_MEASURE="${AUTO_OPS_ROOT}/workflows/perf_measure.py"
PERF_CONFIG="${AUTO_OPS_ROOT}/workflows/perf_config.yaml"
OUTPUT_BASE="$(get_project_path 'dm-signal')/outputs"
FRONTEND_URL="${FRONTEND_URL:-https://dm-signal-frontend.onrender.com}"
FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-${FRONTEND_URL}/}"
# BACKEND_URL不要 — CDP哲学: UI操作でログイン。API直呼出しはしない

BASELINE_PATH=""
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline) BASELINE_PATH="$2"; shift 2 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

OUTPUT_DIR="${OUTPUT_BASE}/${CMD_ID}_measurements"

echo "═══════════════════════════════════════════════════"
echo "  CDP計測 — ${CMD_ID}"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Phase 1: Pre-flight check ───
echo "■ Phase 1: Pre-flight check"

# 1a. CDP認証 — shared receipt adapter（fixture-onlyは外部preflight不要）
#     hosted compatibilityでは外部Render/auto-opsが存在しないため、
#     receipt発行までをfixture-onlyの最小契約として先に完了させる。
CDP_PORT="${CDP_PORT:-9222}"
CDP_REQUESTED_PORT="$CDP_PORT"
CDP_RECEIPT="$(mktemp /tmp/cdp-measure-receipt.XXXXXX)"
if [[ -n "${CDP_SESSION_ESTABLISHER:-}" ]]; then
    "$CDP_SESSION_ESTABLISHER" --consumer measurement --ports "$CDP_PORT" --receipt "$CDP_RECEIPT" >/dev/null
else
    python3 "${SCRIPT_DIR}/scripts/cdp/cdp_session.py" establish --consumer measurement --ports "$CDP_PORT" --receipt "$CDP_RECEIPT" >/dev/null
fi
if [[ "${CDP_CONSUMER_FIXTURE_ONLY:-0}" == "1" ]]; then
    echo "consumer=measurement receipt=$CDP_RECEIPT port=$CDP_PORT baseline=$BASELINE_PATH"
    exit 0
fi

# 1b. perf_measure.py存在確認
if [[ ! -f "$PERF_MEASURE" ]]; then
    echo "  FAIL: perf_measure.py not found: $PERF_MEASURE" >&2
    exit 1
fi
echo "  OK: perf_measure.py exists"

# 1c. Frontend healthz確認
echo -n "  Frontend healthz: "
HTTP_CODE=$(curl -sS -L -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$FRONTEND_HEALTH_URL" 2>/dev/null || true)
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "FAIL (HTTP ${HTTP_CODE:-timeout})" >&2
    echo "  → Frontend が起動していない or Render cold-start中。数分待って再実行せよ" >&2
    exit 1
fi
echo "OK (HTTP 200)"

# 1d. CDP計測ロック
LOCK_DIR="${SCRIPT_DIR}/queue/locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="${LOCK_DIR}/cdp_measure_port_${CDP_PORT}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "FAIL: CDP measurement already running for cmd=${CMD_ID} port=${CDP_PORT}" >&2
    echo "  → 既存計測の完了を待つか、別cmd_idで最小再現を実行せよ" >&2
    exit 75
fi
CDP_LOCK_ACQUIRED=1
ENV_FILE="$(get_project_path 'dm-signal')/backend/.env"
ADMIN_URL="${FRONTEND_URL}/admin"
echo -n "  CDP Admin Login (UI): "
set +e
LOGIN_RESULT=$(python3 "${SCRIPT_DIR}/scripts/cdp/dm_signal_adapters.py" \
    --receipt "$CDP_RECEIPT" auth-strategy \
    --target-url "$ADMIN_URL" --required-capability admin --env-file "$ENV_FILE")
LOGIN_RC=$?
set -e
if [[ "$LOGIN_RC" -ne 0 ]]; then
    echo "FAIL" >&2
    echo "  → ${LOGIN_RESULT}" >&2
    exit 1
fi
CDP_PORT=$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["daemon_cdp_port"]))' "$CDP_RECEIPT")
echo "OK (port ${CDP_PORT})"

echo ""

# ─── Phase 2: Artifact path分離 ───
echo "■ Phase 2: Artifact path分離"
if [[ -d "$OUTPUT_DIR" ]]; then
    echo "  WARN: ${OUTPUT_DIR} already exists. 前回計測が残っている"
    echo "  → 上書きせず追記。timestampで区別可能"
else
    mkdir -p "$OUTPUT_DIR"
    echo "  Created: ${OUTPUT_DIR}"
fi
echo ""

# ─── Phase 3: 計測実行 ───
echo "■ Phase 3: 計測実行"
echo "  Running: python3 perf_measure.py --profile production --config ${PERF_CONFIG}"
echo "  Output: ${OUTPUT_DIR}"
echo ""

# perf_measure.pyのoutput_dirをcmd_id固有ディレクトリに設定
# perf_config.yamlのdefaults.output_dirを一時的にオーバーライド
TEMP_CONFIG=$(mktemp "/tmp/perf_config_${CMD_ID}_XXXXXX.yaml")
# コピーしてoutput_dirを書き換え
sed "s|output_dir:.*|output_dir: ${OUTPUT_DIR}|" "$PERF_CONFIG" > "$TEMP_CONFIG"
# screenshot_dirも分離
sed -i "s|screenshot_dir:.*|screenshot_dir: ${OUTPUT_DIR}/screenshots|" "$TEMP_CONFIG"
# preflightで実際に採用したCDPポートを計測本体にも渡す
sed -i "s|^[[:space:]]*port:.*|  port: ${CDP_PORT}|" "$TEMP_CONFIG"

MEASURE_CMD=(
    python3 "$PERF_MEASURE"
    --config "$TEMP_CONFIG"
    --profile production
)
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    MEASURE_CMD+=("${EXTRA_ARGS[@]}")
fi

echo "  Command: ${MEASURE_CMD[*]}"
echo "  ─────────────────────────────────────────"

measure_rc=0
PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" "${MEASURE_CMD[@]}" || measure_rc=$?
echo "  ─────────────────────────────────────────"
if [[ "$measure_rc" -ne 0 ]]; then
    echo "  FAIL: 計測失敗 (exit ${measure_rc})" >&2
    exit 1
fi
echo "  OK: 計測完了"
rm -f "$TEMP_CONFIG"
TEMP_CONFIG=""

# 最新の結果JSONを特定
LATEST_JSON=$(find "${OUTPUT_DIR}" -maxdepth 1 -name 'perf_*.json' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)
if [[ -z "$LATEST_JSON" ]]; then
    echo "  WARN: 計測結果JSONが見つからない" >&2
else
    # cmd_id_measurements.jsonとしてコピー
    cp "$LATEST_JSON" "${OUTPUT_BASE}/${CMD_ID}_measurements.json"
    echo "  Saved: ${OUTPUT_BASE}/${CMD_ID}_measurements.json"
fi
echo ""

# ─── Phase 4: ベースライン比較 ───
echo "■ Phase 4: ベースライン比較"
if [[ -n "$BASELINE_PATH" && -f "$BASELINE_PATH" && -n "$LATEST_JSON" ]]; then
    echo "  Baseline: $BASELINE_PATH"
    echo "  Current:  $LATEST_JSON"

    # cdp_benchmark.pyで比較（存在すれば）
    BENCHMARK="${SCRIPT_DIR}/scripts/cdp/cdp_benchmark.py"
    if [[ -f "$BENCHMARK" ]]; then
        python3 "$BENCHMARK" --baseline "$BASELINE_PATH" --current "$LATEST_JSON" 2>&1 || true
    else
        echo "  (cdp_benchmark.py not found — manual comparison required)"
    fi
elif [[ -z "$BASELINE_PATH" ]]; then
    echo "  SKIP: --baseline未指定。比較する場合:"
    echo "    bash scripts/cdp/cdp_measure.sh ${CMD_ID} --baseline outputs/cmd_XXXX_measurements.json"
elif [[ ! -f "$BASELINE_PATH" ]]; then
    echo "  WARN: baseline not found: $BASELINE_PATH"
fi
echo ""

# ─── Phase 5: CDP Cleanup ───
echo "■ Phase 5: CDP Cleanup"
python3 "${SCRIPT_DIR}/scripts/cdp/cdp_session.py" cleanup --receipt "$CDP_RECEIPT"
rm -f "$CDP_RECEIPT"
CDP_RECEIPT=""
echo ""

echo "═══════════════════════════════════════════════════"
echo "  完了: ${CMD_ID}"
echo "  結果: ${OUTPUT_BASE}/${CMD_ID}_measurements.json"
echo "═══════════════════════════════════════════════════"
