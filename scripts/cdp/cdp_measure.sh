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
PERF_MEASURE="/mnt/c/Python_app/auto-ops/workflows/perf_measure.py"
PERF_CONFIG="/mnt/c/Python_app/auto-ops/workflows/perf_config.yaml"
OUTPUT_BASE="/mnt/c/Python_app/DM-signal/outputs"
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

# 1b. Backend healthz確認
echo -n "  Backend healthz: "
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 "${BACKEND_URL}/healthz" 2>/dev/null || true)
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "FAIL (HTTP ${HTTP_CODE:-timeout})" >&2
    echo "  → Backend が起動していない or Render cold-start中。数分待って再実行せよ" >&2
    exit 1
fi
echo "OK (HTTP 200)"

# 1c. 認証確認（env_fileからcredentials読み取り+viewer password取得テスト）
echo -n "  Auth preflight: "
AUTH_CHECK=$(python3 -c "
import sys, json, base64
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from pathlib import Path

env_file = Path('/mnt/c/Python_app/DM-signal/backend/.env')
if not env_file.exists():
    print('FAIL: .env not found')
    sys.exit(1)

env_vars = {}
for line in env_file.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env_vars[k.strip()] = v.strip()

user = env_vars.get('ADMIN_USER', '')
pw = env_vars.get('ADMIN_PASS', '')
if not user or not pw:
    print('FAIL: ADMIN_USER or ADMIN_PASS missing in .env')
    sys.exit(1)

# Test: fetch viewer password
url = '${BACKEND_URL}/api/admin/tiers/passwords'
cred = base64.b64encode(f'{user}:{pw}'.encode()).decode()
req = Request(url, headers={'Authorization': f'Basic {cred}'})
try:
    resp = urlopen(req, timeout=15)
    data = json.loads(resp.read())
    viewer_pw = data.get('viewer', '')
    if viewer_pw:
        print('OK')
    else:
        print('FAIL: viewer password empty')
        sys.exit(1)
except HTTPError as e:
    print(f'FAIL: HTTP {e.code}')
    sys.exit(1)
except Exception as e:
    print(f'FAIL: {e}')
    sys.exit(1)
" 2>&1)
echo "$AUTH_CHECK"
if [[ "$AUTH_CHECK" != "OK" ]]; then
    echo "  → 認証に失敗。.envの ADMIN_USER/ADMIN_PASS を確認せよ" >&2
    exit 1
fi

# 1d. Chrome CDP接続確認
echo -n "  Chrome CDP: "
CDP_PORT="${CDP_PORT:-9222}"
CDP_CHECK=$(curl -s --connect-timeout 5 "http://localhost:${CDP_PORT}/json/version" 2>/dev/null || true)
if [[ -z "$CDP_CHECK" ]]; then
    echo "FAIL (port ${CDP_PORT} no response)"
    echo "  → Chromeが起動していない。以下で起動:" >&2
    echo "    chrome.exe --remote-debugging-port=${CDP_PORT} --user-data-dir=\"C:\\cdp_profile\"" >&2
    exit 1
fi
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
"${MEASURE_CMD[@]}" || measure_rc=$?
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
