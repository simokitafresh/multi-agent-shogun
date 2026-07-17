#!/usr/bin/env bash
# gunshi_log_append.sh — レビューログ末尾追記 + 自動アーカイブ
# Usage: bash scripts/gunshi_log_append.sh <<'ENTRY'
# - cmd_id: cmd_1234
#   review_type: report
#   ...
# ENTRY
#
# 追記後に行数チェック → 2500行超で古いエントリを自動アーカイブ

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
MAX_LINES=2500

# Batch入口は各entryを既存の厳格な単件validatorへ通す。共有logへの書込みは
# 単件側のflockで直列化されるため、並行precheck/notifyと組み合わせてもlost updateしない。
if [ "${1:-}" = "--batch" ]; then
    python3 -c '
import subprocess, sys, yaml
sys.path.insert(0, sys.argv[2])
from scripts.lib.yaml_atomic import yaml_text
items = yaml.safe_load(sys.stdin.read())
if not isinstance(items, list) or not items:
    print("BLOCK: --batch requires a non-empty YAML list", file=sys.stderr); raise SystemExit(2)
for index, item in enumerate(items):
    if not isinstance(item, dict):
        print(f"BLOCK: batch review_entry[{index}] must be a mapping", file=sys.stderr); raise SystemExit(2)
    env = dict(__import__("os").environ); env["GUNSHI_VALIDATE_ONLY"] = "1"
    completed = subprocess.run(["bash", sys.argv[1]], input=yaml_text([item], allow_unicode=True, sort_keys=False), text=True, env=env)
    if completed.returncode: raise SystemExit(completed.returncode)
for item in items:
    completed = subprocess.run(["bash", sys.argv[1]], input=yaml_text([item], allow_unicode=True, sort_keys=False), text=True)
    if completed.returncode: raise SystemExit(completed.returncode)
print(f"OK: batch appended {len(items)} review entries")
' "$0" "$SCRIPT_DIR"
    exit $?
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: $LOG_FILE not found" >&2
    exit 1
fi

# Read entry from stdin
ENTRY=$(cat)

if [ -z "$ENTRY" ]; then
    echo "ERROR: empty entry" >&2
    exit 1
fi

# --- observations必須チェック(draft/report/self_study) ---
if [[ "$ENTRY" =~ review_type:[[:space:]]*(draft|report|self_study) ]]; then
    if [[ "$ENTRY" != *"observations:"* ]]; then
        echo "BLOCK: observationsが未記入(review_type=draft/report/self_study)。事実3点以上を記入してから再実行せよ" >&2
        exit 2
    fi
    HAS_ITEM=$(echo "$ENTRY" | awk '/observations:/{found=1;next} found{if(/^\s*-\s+.+/){print "yes";exit} if(!/^\s*$/){exit}}')
    if [ "$HAS_ITEM" != "yes" ]; then
        echo "BLOCK: observations[]が空。1件以上の事実を記入してから再実行せよ" >&2
        exit 2
    fi
fi

# --- finding_categories必須チェック(draft/report) --- 冷え観点L4化 2026-06-24: 3セッション連続再発の根治
if [[ "$ENTRY" =~ review_type:[[:space:]]*(draft|report) ]]; then
    if [[ "$ENTRY" != *"finding_categories:"* ]]; then
        echo "BLOCK: finding_categoriesが未記入(review_type=draft/report)。6観点カタログ全てを記載せよ(冷え観点防止)" >&2
        exit 2
    fi
    # インラインリスト [a, b, adversarial] と複数行リスト (- adversarial) の両方に対応
    FC_BLOCK=$(echo "$ENTRY" | awk '/finding_categories:/{found=1; print; next} found{if(/^\s*-\s/){print;next} exit}')
    if ! echo "$FC_BLOCK" | grep -qi 'adversarial'; then
        echo "BLOCK: finding_categoriesにadversarialが未記載。全レビューでadversarial必須(3セッション連続再発の根治)" >&2
        exit 2
    fi
    if ! echo "$FC_BLOCK" | grep -qi 'ambiguity'; then
        echo "BLOCK: finding_categoriesにambiguityが未記載。全レビューでambiguity必須(冷え観点遡及 2026-06-25)" >&2
        exit 2
    fi
fi

# --- ambiguity_points必須チェック(draft) --- 冷え観点遡及 2026-06-26: ambiguity記録漏れ根治
if [[ "$ENTRY" =~ review_type:[[:space:]]*draft ]]; then
    if [[ "$ENTRY" != *"ambiguity_points:"* ]]; then
        echo "BLOCK: ambiguity_pointsが未記入(review_type=draft)。none または曖昧箇所を記載せよ(冷え観点防止)" >&2
        exit 2
    fi
fi

# --- brainwash_check数値強制(draft/report/self_study/consultation) --- 覚醒洗脳監査2026-06-09: L4貫通
# brainwash_checkに数値(0-9)が含まれない場合BLOCK。「OK」「確認済み」は形骸化(LG027横展開)
if [[ "$ENTRY" =~ review_type:[[:space:]]*(draft|report|self_study|consultation) ]]; then
    if [[ "$ENTRY" != *"brainwash_check:"* ]]; then
        echo "BLOCK: brainwash_checkが未記入。8パターン自問+数値証拠を記入してから再実行せよ" >&2
        exit 2
    fi
    BC_LINE=$(echo "$ENTRY" | grep 'brainwash_check:' | head -1)
    if ! echo "$BC_LINE" | grep -qP '[0-9]'; then
        echo "BLOCK: brainwash_checkに数値がない。修正前→修正後の数値、またはN件中N件確認の形式で記載せよ(LG027横展開)" >&2
        exit 2
    fi
fi

# --- LGTM+BLOCK矛盾チェック(report) --- 今セッション3件連続事故の根治(L4貫通)
if [[ "$ENTRY" =~ review_type:[[:space:]]*report ]] && [[ "$ENTRY" =~ verdict:[[:space:]]*LGTM ]] && echo "$ENTRY" | grep -Pq 'gate_prediction:\s*BLOCK(\s|$|\(|\[|/)'; then
    echo "BLOCK: verdict=LGTMとgate_prediction=BLOCKの矛盾。BLOCKが予測される報告にLGTMを出すな。FAILに変更するか、BLOCK理由を解消してからLGTMせよ" >&2
    exit 2
fi

# --- gate_prediction_reason必須チェック(report) --- GP-259: prediction偽陽性分析の材料を残す
if [[ "$ENTRY" =~ review_type:[[:space:]]*report ]] && [[ "$ENTRY" =~ gate_prediction:[[:space:]]*(CLEAR|WARN|BLOCK) ]]; then
    if [[ "$ENTRY" != *"gate_prediction_reason:"* ]]; then
        echo "BLOCK: gate_prediction_reasonが未記入。precheckのreasonをreview_logへ転記せよ(GP-259)" >&2
        exit 2
    fi
    GPR_LINE=$(echo "$ENTRY" | grep 'gate_prediction_reason:' | head -1)
    if echo "$GPR_LINE" | grep -Eq 'gate_prediction_reason:[[:space:]]*($|null|N/A|none|engine未実行)'; then
        echo "BLOCK: gate_prediction_reasonが実質空。precheckの具体reasonを記入せよ(GP-259)" >&2
        exit 2
    fi
fi

# --- review evidence contract ---
# Detection at startup is too late: validate the common append point so an
# incomplete review can never become an APPROVE/LGTM record.
python3 - "$ENTRY" "$SCRIPT_DIR" <<'PY'
import re, sys, yaml
sys.path.insert(0, sys.argv[2])
from scripts.lib.yaml_atomic import yaml_text
try:
    parsed = yaml.safe_load(sys.argv[1])
except Exception as exc:
    print(f"BLOCK: review entry YAML parse error: {exc}", file=sys.stderr); raise SystemExit(2)
if not isinstance(parsed, list) or len(parsed) != 1 or not isinstance(parsed[0], dict):
    print("BLOCK: review entry must be one YAML list item", file=sys.stderr); raise SystemExit(2)
item = parsed[0]
review_type = str(item.get("review_type") or "").strip()
if review_type in {"draft", "report", "self_study", "consultation"}:
    ops = item.get("operational_simulation")
    required = {"command", "expected", "actual", "result"}
    if not isinstance(ops, dict) or not required.issubset(ops) or any(str(ops[k]).strip().lower() in {"", "none", "null", "n/a"} for k in required):
        print("BLOCK: operational_simulation must contain command/expected/actual/result for every review path", file=sys.stderr); raise SystemExit(2)
    claim_text = yaml_text(item, allow_unicode=True)
    if "既実装" in claim_text and "git show" not in str(ops.get("command", "")):
        print("BLOCK: 既実装判定にはoperational_simulation.commandのgit show証跡が必須(LG001)", file=sys.stderr); raise SystemExit(2)
verdict = str(item.get("verdict") or "").strip().upper()
if verdict in {"APPROVE", "LGTM"}:
    files = item.get("verified_files")
    if isinstance(files, str): files = [files]
    valid = isinstance(files, list) and any(isinstance(v, str) and re.search(r"^[^:\s]+:(?:[1-9][0-9]*|[A-Za-z_][A-Za-z0-9_.-]*)$", v.strip()) for v in files)
    if not valid:
        print("BLOCK: APPROVE/LGTM requires verified_files file:line or file:symbol evidence", file=sys.stderr); raise SystemExit(2)
if review_type in {"self_study", "consultation"}:
    checklist = item.get("cs_checklist")
    required_cs = {f"CS{i}" for i in range(1, 7)}
    missing = sorted(
        key for key in required_cs
        if not isinstance(checklist, dict)
        or key not in checklist
        or str(checklist.get(key, "")).strip().lower() in {"", "none", "null", "n/a"}
    )
    if missing:
        print(
            "BLOCK: self_study/consultation requires non-empty "
            f"cs_checklist CS1-CS6 (missing: {','.join(missing)}) (LG013)",
            file=sys.stderr,
        )
        raise SystemExit(2)
PY

# Historical reviews are immutable. Retroactive evidence is accepted only as
# a structured self_study remediation for an exact existing cmd_id.
if [[ "$ENTRY" == *"remediation:"* ]]; then
    python3 - "$LOG_FILE" "$ENTRY" <<'PY'
import re, sys, yaml
allowed = {"operational_simulation", "verified_files", "adversarial", "step3_5_verified", "d0_applied"}
try:
    old = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or []
    parsed = yaml.safe_load(sys.argv[2])
except Exception as exc:
    print(f"BLOCK: remediation YAML parse error: {exc}", file=sys.stderr); raise SystemExit(2)
if not isinstance(parsed, list) or len(parsed) != 1 or not isinstance(parsed[0], dict):
    print("BLOCK: remediation entry must be one YAML list item", file=sys.stderr); raise SystemExit(2)
item = parsed[0]; rem = item.get("remediation")
target = str(rem.get("target_cmd_id") or "").strip() if isinstance(rem, dict) else ""
known = {str(x.get("cmd_id") or x.get("id") or "").strip() for x in old if isinstance(x, dict) and "remediation" not in x}
fields = rem.get("fields") if isinstance(rem, dict) else None
evidence = rem.get("evidence") if isinstance(rem, dict) else None
bad_fields = not isinstance(fields, dict) or not fields or any(k not in allowed or v is None or v is False or str(v).strip().lower() in {"", "null", "none", "n/a", "[]", "{}"} for k, v in (fields or {}).items())
bad_evidence = not isinstance(evidence, list) or not evidence or any(not isinstance(v, str) or not v.strip() or not re.search(r"(?:[^:]+:[A-Za-z0-9_.-]+|\b[0-9a-f]{7,40}\b)", v) for v in (evidence or []))
if item.get("review_type") != "self_study" or target not in known or bad_fields or bad_evidence:
    print(f"BLOCK: invalid remediation target/fields/evidence: {target or '<empty>'}", file=sys.stderr); raise SystemExit(2)
PY
fi

if [ "${GUNSHI_VALIDATE_ONLY:-0}" = "1" ]; then
    echo "OK: review entry validated"
    exit 0
fi

# Append to log file (flock for safety)
(
    flock -w 5 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
    echo "$ENTRY" >> "$LOG_FILE"
) 200>"$LOG_FILE.lock"

echo "OK: appended to $LOG_FILE"

# --- Auto-archive check ---
TOTAL_LINES=$(wc -l < "$LOG_FILE")
if [ "$TOTAL_LINES" -le "$MAX_LINES" ]; then
    exit 0
fi

echo "ARCHIVE: $TOTAL_LINES lines > $MAX_LINES threshold"

# Find header end (line before first "- cmd_id:")
HEADER_END=$(grep -n '^- cmd_id:' "$LOG_FILE" | head -1 | cut -d: -f1 || true)
if [ -z "$HEADER_END" ]; then
    echo "WARN: no entries found, skipping archive" >&2
    exit 0
fi
HEADER_END=$((HEADER_END - 1))

# Find midpoint of entries to split
FIRST_ENTRY=$((HEADER_END + 1))
ENTRY_LINES=$((TOTAL_LINES - HEADER_END))
HALF=$((ENTRY_LINES / 2))
SPLIT_LINE=$((FIRST_ENTRY + HALF))

# Find nearest "- cmd_id:" boundary at or after split point
SPLIT_BOUNDARY=$(awk -v start="$SPLIT_LINE" 'NR >= start && /^- cmd_id:/ { print NR; exit }' "$LOG_FILE")
if [ -z "$SPLIT_BOUNDARY" ]; then
    echo "WARN: no clean split boundary found, skipping archive" >&2
    exit 0
fi

# Extract cmd range for archive filename (Vercel: 探す側の言葉で命名)
FIRST_CMD=$(sed -n "${FIRST_ENTRY}p" "$LOG_FILE" | grep -oP 'cmd_id:\s*\K\S+' || true)
LAST_ENTRY_LINE=$((SPLIT_BOUNDARY - 1))
# Walk backward to find the last "- cmd_id:" before split boundary
LAST_CMD=$(awk -v end="$LAST_ENTRY_LINE" 'NR <= end && /^- cmd_id:/ { last=$0 } END { print last }' "$LOG_FILE" | grep -oP 'cmd_id:\s*\K\S+' || true)
ARCHIVE_NAME="${FIRST_CMD:-unknown}_to_${LAST_CMD:-$(date +%Y%m%d)}"
ARCHIVE_FILE="$ARCHIVE_DIR/gunshi_review_log_${ARCHIVE_NAME}.yaml"

mkdir -p "$ARCHIVE_DIR"

# Archive old entries
sed -n "${FIRST_ENTRY},$((SPLIT_BOUNDARY - 1))p" "$LOG_FILE" > "$ARCHIVE_FILE"
ARCHIVED_LINES=$(wc -l < "$ARCHIVE_FILE")

# Rebuild main file: header + remaining entries
TEMP_FILE=$(mktemp)
{ sed -n "1,${HEADER_END}p" "$LOG_FILE"; sed -n "${SPLIT_BOUNDARY},\$p" "$LOG_FILE"; } > "$TEMP_FILE"

# Add archive reference to header (after last archive reference line)
LAST_ARCHIVE_LINE=$(grep -n '# 詳細エントリ:' "$TEMP_FILE" | tail -1 | cut -d: -f1 || true)
if [ -n "$LAST_ARCHIVE_LINE" ]; then
    sed -i "${LAST_ARCHIVE_LINE}a\\# 詳細エントリ: ${ARCHIVE_NAME} → logs/archive/gunshi_review_log_${ARCHIVE_NAME}.yaml" "$TEMP_FILE"
fi

cp "$TEMP_FILE" "$LOG_FILE"
rm -f "$TEMP_FILE"

NEW_LINES=$(wc -l < "$LOG_FILE")
echo "ARCHIVE: done. ${ARCHIVED_LINES} lines → ${ARCHIVE_FILE##*/}. Main: ${TOTAL_LINES} → ${NEW_LINES} lines"
