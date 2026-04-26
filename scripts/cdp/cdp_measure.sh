#!/usr/bin/env bash
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"
PERF_MEASURE="/mnt/c/Python_app/auto-ops/workflows/perf_measure.py"
PERF_CONFIG="/mnt/c/Python_app/auto-ops/workflows/perf_config.yaml"
OUTPUT_BASE="/mnt/c/Python_app/DM-signal/outputs"
FRONTEND_URL="${FRONTEND_URL:-https://dm-signal-frontend.onrender.com}"
FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-${FRONTEND_URL}/}"
BACKEND_URL="https://dm-signal-backend.onrender.com"

# ─── 引数解析 ───
CMD_ID="${1:-}"
if [[ -z "$CMD_ID" ]]; then
    echo "ERROR: cmd_id必須。Usage: bash scripts/cdp/cdp_measure.sh <cmd_id> [--baseline <path>]" >&2
    exit 1
fi
shift

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

# 1a. perf_measure.py存在確認
if [[ ! -f "$PERF_MEASURE" ]]; then
    echo "  FAIL: perf_measure.py not found: $PERF_MEASURE" >&2
    exit 1
fi
echo "  OK: perf_measure.py exists"

# 1b. Frontend healthz確認
echo -n "  Frontend healthz: "
HTTP_CODE=$(curl -sS -L -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$FRONTEND_HEALTH_URL" 2>/dev/null || true)
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "FAIL (HTTP ${HTTP_CODE:-timeout})" >&2
    echo "  → Frontend が起動していない or Render cold-start中。数分待って再実行せよ" >&2
    exit 1
fi
echo "OK (HTTP 200)"

# 1c. CDP認証 — cdp_cli.sh auth でブラウザ起動+Viewer+Admin Cookie注入
#     CDP哲学: 人間と同じようにブラウザを操作する=未起動でも起動してログインする
#     cdp_cli.sh authは内部でpreflight_cdp_flow→タブ作成→Cookie注入を一括実行
CDP_PORT="${CDP_PORT:-9222}"
CDP_CLI="/mnt/c/Python_app/auto-ops/scripts/cdp/cdp_cli.sh"
ENV_FILE="/mnt/c/Python_app/DM-signal/backend/.env"
echo -n "  CDP Auth (Viewer+Admin): "
set +e
AUTH_RESULT=$(bash "$CDP_CLI" auth --env "$ENV_FILE" --port "$CDP_PORT" --api-base-url "$BACKEND_URL" --base-url "$FRONTEND_URL" 2>&1)
AUTH_RC=$?
set -e
if [[ "$AUTH_RC" -ne 0 ]]; then
    echo "FAIL" >&2
    echo "  → CDP認証に失敗。出力: ${AUTH_RESULT}" >&2
    echo "  → .envのADMIN_USER/ADMIN_PASS/VIEWER_PASSを確認。Chrome CDPが起動しているか確認。" >&2
    exit 1
fi
# auth結果からadmin_authenticated確認
ADMIN_AUTH=$(echo "$AUTH_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('admin_authenticated') else 'no')" 2>/dev/null || echo "unknown")
if [[ "$ADMIN_AUTH" != "yes" ]]; then
    echo "FAIL (admin not authenticated)" >&2
    echo "  → Admin認証が不成立。出力: ${AUTH_RESULT}" >&2
    exit 1
fi
echo "OK (port ${CDP_PORT}, admin+viewer authenticated)"

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
    rm -f "$TEMP_CONFIG"
    exit 1
fi
echo "  OK: 計測完了"
rm -f "$TEMP_CONFIG"

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

echo "═══════════════════════════════════════════════════"
echo "  完了: ${CMD_ID}"
echo "  結果: ${OUTPUT_BASE}/${CMD_ID}_measurements.json"
echo "═══════════════════════════════════════════════════"
