#!/bin/bash
# gate_workaround_rate.sh — 直近N件のGATE CLEARedcmdsに対するworkaround率を計算
# Usage: bash scripts/gates/gate_workaround_rate.sh [--last N]
# 分母: gate_metrics.logのユニークCLEAR cmd数（直近N件）
# 分子: そのcmd群のうちmanual_waかつworkaround:trueがあるcmd数
# フォールバック: gate_metrics.log不在時はkaro_workarounds.yamlのエントリ数を分母に使用
# Output: OK/WARN/ALERT + WA率 + カテゴリ内訳
# 閾値: OK=<15%, WARN=15-30%, ALERT=>30%
# 手動WA率はGATE判定に影響しない（情報表示のみ）。
# 完了済みreworkの自動捕捉欠落は別行でALERT表示し、startup gateが回収する。
# 最適化(cmd_1970): python3+grep+awk3本 → awk1本に統合(-44%)
# 最適化(cmd_2092): BEGIN内getline from tac → gate_log処理21ms→3ms(-86%) 全体36ms→25ms(-31%)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WA_FILE="${KARO_WORKAROUNDS_FILE:-$SCRIPT_DIR/logs/karo_workarounds.yaml}"
GATE_LOG="${GATE_METRICS_LOG:-$SCRIPT_DIR/logs/gate_metrics.log}"
REWORK_CAPTURE_SINCE="${REWORK_CAPTURE_SINCE:-today 00:00}"
REWORK_CAPTURE_SINCE_LOCAL_ISO="$(date -d "$REWORK_CAPTURE_SINCE" +%Y-%m-%dT%H:%M:%S 2>/dev/null || true)"
# PUBLISHER_SINGLE queues append operations outside the checkout.  The runtime
# state defaults to /tmp (ninja_monitor's state), while tests and deployments
# may provide an explicit state directory or pending ledger directory.
REWORK_CAPTURE_PENDING_DIR="${REWORK_CAPTURE_PENDING_DIR:-${REWORK_CAPTURE_LEDGER_DIR:-${SHOGUN_STATE_DIR:-/tmp}/ledger_inbox/workarounds}}"
LAST_N=10

# 引数パース
while [ $# -gt 0 ]; do
    case "$1" in
        --last)
            LAST_N="${2:-10}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -f "$GATE_LOG" ]; then
    echo "■ Workaround率 (GATE CLEAR直近${LAST_N}cmd)"
else
    echo "■ Workaround率 (WAログ直近${LAST_N}件)"
fi

if [ ! -f "$WA_FILE" ]; then
    echo "  SKIP: karo_workarounds.yaml不在"
    exit 0
fi

# gate_metrics.log が存在する場合:
#   BEGIN内でtacコマンドからgetlineし、末尾からN件ユニークCLEARを取得(~3ms)
#   その後karo_workarounds.yamlを1パスで処理(~15ms)
# 不在の場合: fallbackモード(karo_workarounds.yamlのみ処理)
if [ -f "$GATE_LOG" ]; then
    _HAS_GATE="true"
else
    _HAS_GATE="false"
fi

if [ -x /usr/bin/mawk ]; then
    _AWK_BIN=/usr/bin/mawk
else
    _AWK_BIN=awk
fi

result=$(LC_ALL=C "$_AWK_BIN" -v has_gate="$_HAS_GATE" -v gate_log="$GATE_LOG" -v last_n="$LAST_N" '
BEGIN {
    cur_cmd = ""; has_wa_field = 0; cur_wa = 0; cur_cat = "uncategorized"; cur_kind = ""
    item_count = 0; clear_count = 0

    # gate_pathの場合: tacでgate_logを末尾から読みlast_n件ユニークCLEARを取得
    # N件見つかり次第breakし、tacにSIGPIPEを送ってI/Oを最小化
    if (has_gate == "true") {
        cmd = "tac \"" gate_log "\""
        while ((cmd | getline line) > 0) {
            n = split(line, f, "\t")
            if (f[3] == "CLEAR" && !seen_cl[f[2]]++) {
                clear_set[f[2]] = 1
                if (++clear_count >= last_n) break
            }
        }
        close(cmd)
    }
}

# karo_workarounds.yaml のエントリ先頭
/^- cmd_id:/ {
    flush_item()
    cur_cmd = $0
    sub(/^- cmd_id:[[:space:]]*/, "", cur_cmd)
    gsub(/["'"'"'[:space:]]/, "", cur_cmd)
    cur_wa = 0; cur_cat = "uncategorized"; cur_kind = ""; has_wa_field = 0
}

/^  workaround:/ {
    val = $0
    sub(/^[[:space:]]*workaround:[[:space:]]*/, "", val)
    gsub(/["'"'"'[:space:]]/, "", val)
    cur_wa = (val == "true" || val == "yes") ? 1 : 0
    has_wa_field = 1
}

/^  category:/ {
    cur_cat = $0
    sub(/^[[:space:]]*category:[[:space:]]*["'"'"']?/, "", cur_cat)
    gsub(/["'"'"']$/, "", cur_cat)
    gsub(/[[:space:]]*$/, "", cur_cat)
    if (cur_cat == "") cur_cat = "uncategorized"
}

/^  event_kind:/ {
    cur_kind = $0
    sub(/^[[:space:]]*event_kind:[[:space:]]*/, "", cur_kind)
    gsub(/[^[:alnum:]_:-]/, "", cur_kind)
}

END {
    flush_item()

    if (has_gate == "true" && clear_count > 0) {
        # gate_metrics.logベース: 分母=CLEAR cmd数
        # 同一cmdに複数エントリある場合 workaround=trueが優先
        total = clear_count; wa_count = 0
        for (i = 0; i < item_count; i++) {
            cmd = item_cmd[i]
            if (cmd in clear_set && item_wa[i] && (item_kind[i] == "" || item_kind[i] == "manual_wa") && !(cmd in wa_seen_true)) {
                wa_seen_true[cmd] = 1
                wa_count++
                cats[item_cat[i]]++
            }
        }
        source = "gate_metrics"
    } else {
        # フォールバック: karo_workarounds.yamlの直近N件を分母に使用
        if (item_count == 0) { print "OK|0|0|0|none|no data"; exit }
        start_i = (item_count > last_n) ? item_count - last_n : 0
        total = item_count - start_i; wa_count = 0
        for (i = start_i; i < item_count; i++) {
            if (item_wa[i] && (item_kind[i] == "" || item_kind[i] == "manual_wa")) {
                wa_count++
                cats[item_cat[i]]++
            }
        }
        source = "fallback"
    }

    rate = (total > 0) ? wa_count / total * 100 : 0
    level = (rate < 15) ? "OK" : (rate <= 30) ? "WARN" : "ALERT"

    # カテゴリ内訳文字列を構築
    cat_str = ""
    for (cat in cats) {
        if (cat_str != "") cat_str = cat_str ", "
        cat_str = cat_str cat ":" cats[cat]
    }
    if (cat_str == "") cat_str = "none"

    printf "%s|%.0f|%d|%d|%s|%s\n", level, rate, wa_count, total, cat_str, source
}

function flush_item() {
    if (cur_cmd != "" && has_wa_field) {
        item_cmd[item_count] = cur_cmd
        item_wa[item_count]  = cur_wa
        item_cat[item_count] = cur_cat
        item_kind[item_count] = cur_kind
        item_count++
    }
    cur_cmd = ""; has_wa_field = 0
}
' "$WA_FILE" 2>/dev/null || echo "ERROR|0|0|0|awk_error|unknown")

IFS='|' read -r LEVEL RATE WA_COUNT TOTAL CATS SOURCE <<< "$result"

echo "  WA率: ${RATE}% (${WA_COUNT}/${TOTAL}件) — ${LEVEL}"
capture_pair=$(REWORK_CAPTURE_PENDING_DIR="$REWORK_CAPTURE_PENDING_DIR" python3 - "$GATE_LOG" "$WA_FILE" "$REWORK_CAPTURE_SINCE_LOCAL_ISO" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

import yaml


gate_log = Path(sys.argv[1])
workaround_file = Path(sys.argv[2])
since = sys.argv[3]
pending_dir = Path(os.environ["REWORK_CAPTURE_PENDING_DIR"])


def event_kind_for(cmd):
    lowered = str(cmd).lower()
    if "karo_direct" in lowered:
        return "karo_direct"
    if "hotfix" in lowered:
        return "hotfix"
    if re.search(r"(^|[_:-])rc([_:-]|$)", lowered):
        return "rc"
    return ""


def as_entries(value):
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        for key in ("workarounds", "entries"):
            if key in value:
                return as_entries(value[key])
        return [value]
    return []


def load_entries(path):
    try:
        return as_entries(yaml.safe_load(path.read_text(encoding="utf-8")))
    except (OSError, UnicodeError, yaml.YAMLError):
        return []


eligible = set()
try:
    for line in gate_log.read_text(encoding="utf-8", errors="replace").splitlines():
        fields = line.split("\t")
        if len(fields) < 3 or fields[0] < since or fields[2] != "CLEAR":
            continue
        kind = event_kind_for(fields[1])
        if kind:
            eligible.add((fields[1], kind))
except OSError:
    pass

# The canonical YAML may lag while its publisher append operation is still
# pending.  Treat both as one logical source and deduplicate by the same
# cmd_id+event_kind identity used for the eligible CLEAR set.
captured = set()
for entry in load_entries(workaround_file):
    if entry.get("auto_captured") is True:
        key = (str(entry.get("cmd_id", "")), str(entry.get("event_kind", "")))
        if key in eligible:
            captured.add(key)

if pending_dir.is_dir():
    for operation_path in sorted(pending_dir.glob("*.yaml")):
        try:
            operation = json.loads(operation_path.read_text(encoding="utf-8"))
            if operation.get("op") != "append" or operation.get("ledger") != "workarounds":
                continue
            entry_text = operation.get("entry_text", "")
            for entry in as_entries(yaml.safe_load(entry_text)):
                if entry.get("auto_captured") is True:
                    key = (str(entry.get("cmd_id", "")), str(entry.get("event_kind", "")))
                    if key in eligible:
                        captured.add(key)
        except (OSError, UnicodeError, json.JSONDecodeError, yaml.YAMLError, TypeError):
            continue

print(f"{len(captured)}|{len(eligible)}")
PY
 2>/dev/null || echo '0|0')
IFS='|' read -r capture_result eligible_result <<< "$capture_pair"
if [ -z "$REWORK_CAPTURE_SINCE_LOCAL_ISO" ]; then
    echo "  手戻り捕捉率: N/A (invalid REWORK_CAPTURE_SINCE=$REWORK_CAPTURE_SINCE)"
elif [ -n "$eligible_result" ] && [ "$eligible_result" -gt 0 ] 2>/dev/null; then
    capture_rate=$(( capture_result * 100 / eligible_result ))
    echo "  手戻り捕捉率: ${capture_rate}% (${capture_result}/${eligible_result}件; auto_captured/completed_rework_cmds)"
    if [ "$capture_result" -lt "$eligible_result" ]; then
        echo "  手戻り捕捉: ALERT (完了済みreworkの自動記録欠落 $((eligible_result - capture_result))件)"
    else
        echo "  手戻り捕捉: OK (完了済みreworkを全件記録)"
    fi
else
    echo "  手戻り捕捉率: N/A (${capture_result}/0件; completed_rework_cmdsなし)"
fi
if [ -n "$SOURCE" ] && [ "$SOURCE" = "fallback" ]; then
    echo "  (gate_metrics.log不在のためkaro_workaroundsエントリ数をフォールバック分母に使用)"
fi
if [ "$WA_COUNT" -gt 0 ] && [ -n "$CATS" ] && [ "$CATS" != "none" ]; then
    echo "  カテゴリ内訳: ${CATS}"
fi

if [ "$LEVEL" = "ALERT" ]; then
    echo "  ⚠ ALERT: workaround率が30%超過。構造的問題の可能性"
elif [ "$LEVEL" = "WARN" ]; then
    echo "  注意: workaround率が15-30%。傾向監視を推奨"
fi
