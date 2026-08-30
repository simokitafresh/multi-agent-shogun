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

SCRIPT_DIR="${GUNSHI_SCRIPT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_FILE="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
MAX_LINES=2500

# The review ledger is live runtime state.  A clean checkout intentionally
# does not track it, so the first review must be able to create the ledger
# without a bootstrap race.  Use the same lock as append/archive and publish
# only when the path is still absent after acquiring it.
mkdir -p "$(dirname "$LOG_FILE")"
if [ ! -f "$LOG_FILE" ]; then
    exec 198>"$LOG_FILE.lock"
    flock -w 30 198 || { echo "ERROR: review ledger init lock timeout" >&2; exit 1; }
    if [ ! -f "$LOG_FILE" ]; then
        printf '# gunshi review runtime ledger\n' > "$LOG_FILE"
    fi
    flock -u 198 2>/dev/null || true
    exec 198>&-
fi

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

# Read entry from stdin
ENTRY=$(cat)

if [ -z "$ENTRY" ]; then
    echo "ERROR: empty entry" >&2
    exit 1
fi

# Parse only the entry's top-level review_type. Stable remediation identity
# contains target_review_type and must not trigger draft/report guards.
ENTRY_REVIEW_TYPE=$(printf '%s\n' "$ENTRY" | awk '/^  review_type:[[:space:]]*/ {v=$0; sub(/^  review_type:[[:space:]]*/, "", v); gsub(/["'\'' ]/, "", v); print v; exit}')

# --- observations必須チェック(draft/report/self_study) ---
if [[ "$ENTRY_REVIEW_TYPE" =~ ^(draft|report|self_study)$ ]]; then
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
if [[ "$ENTRY_REVIEW_TYPE" =~ ^(draft|report)$ ]]; then
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

# --- step3_5_verified必須チェック(report) --- LG036 L4化 2026-08-25: 3セッション連続未記入根治
if [ "$ENTRY_REVIEW_TYPE" = "report" ]; then
    if [[ "$ENTRY" != *"step3_5_verified:"* ]]; then
        echo "BLOCK: step3_5_verifiedが未記入(review_type=report)。command欄×files_modified名前照合の実施結果(true/false)を記入してから再実行せよ(LG036)" >&2
        exit 2
    fi
fi

# --- ambiguity_points必須チェック(draft) --- 冷え観点遡及 2026-06-26: ambiguity記録漏れ根治
if [ "$ENTRY_REVIEW_TYPE" = "draft" ]; then
    if [[ "$ENTRY" != *"ambiguity_points:"* ]]; then
        echo "BLOCK: ambiguity_pointsが未記入(review_type=draft)。none または曖昧箇所を記載せよ(冷え観点防止)" >&2
        exit 2
    fi
fi

# --- brainwash_check数値強制(draft/report/self_study/consultation) --- 覚醒洗脳監査2026-06-09: L4貫通
# brainwash_checkに数値(0-9)が含まれない場合BLOCK。「OK」「確認済み」は形骸化(LG027横展開)
if [[ "$ENTRY_REVIEW_TYPE" =~ ^(draft|report|self_study|consultation)$ ]]; then
    if [[ "$ENTRY" != *"brainwash_check:"* ]]; then
        echo "BLOCK: brainwash_checkが未記入。8パターン自問+数値証拠を記入してから再実行せよ" >&2
        exit 2
    fi
    BC_LINE=$(echo "$ENTRY" | grep 'brainwash_check:' | head -1)
    if ! echo "$BC_LINE" | grep -qP '[0-9]'; then
        echo "BLOCK: brainwash_checkに数値がない。修正前→修正後の数値、またはN件中N件確認の形式で記載せよ(LG027横展開)" >&2
        exit 2
    fi
    # --- 8パターン番号強制(2026-07-20 D0): #Nno/#Nyes形式が最低1つ必要 ---
    if ! echo "$BC_LINE" | grep -qP '#[1-8](no|yes)'; then
        echo "BLOCK: brainwash_checkに8パターン番号(#1no/#1yes形式、スペースなし連結)がない。例: #1no #2no #3no ... 具体的にどのパターンを検査したか明記せよ" >&2
        exit 2
    fi
fi

# --- LGTM+BLOCK矛盾チェック(report) --- 今セッション3件連続事故の根治(L4貫通)
# report_verdict=FAILの正当なFAIL報告ではgate_prediction=BLOCKでも矛盾ではない(GATE適用外)
if [ "$ENTRY_REVIEW_TYPE" = "report" ] && [[ "$ENTRY" =~ verdict:[[:space:]]*LGTM ]] && echo "$ENTRY" | grep -Pq 'gate_prediction:\s*BLOCK(\s|$|\(|\[|/)'; then
    if ! echo "$ENTRY" | grep -Pq 'report_verdict:\s*FAIL'; then
        echo "BLOCK: verdict=LGTMとgate_prediction=BLOCKの矛盾。BLOCKが予測される報告にLGTMを出すな。FAILに変更するか、BLOCK理由を解消してからLGTMせよ" >&2
        exit 2
    fi
fi

# --- LGTM bundle guard: sg7_bundle.json必須(lgtm_bundle_guard, cmd_4157) ---
# LGTM記載とbundle生成を不可分にする。正直FAILもAPPROVE review bundleを先に
# 生成し、report_verdict=FAILはbundle内の別軸として保持する。
if [ "$ENTRY_REVIEW_TYPE" = "report" ] && [[ "$ENTRY" =~ verdict:[[:space:]]*LGTM ]]; then
    _lbg_cmd_id=$(python3 -c "
import sys, yaml
entry = yaml.safe_load(sys.argv[1])
item = entry[0] if isinstance(entry, list) and entry else (entry if isinstance(entry, dict) else {})
print(str(item.get('cmd_id') or ''))
" "$ENTRY" 2>/dev/null || true)
    if [ -n "$_lbg_cmd_id" ]; then
        _lbg_bundle="$SCRIPT_DIR/queue/gates/$_lbg_cmd_id/sg7_bundle.json"
        if [ ! -f "$_lbg_bundle" ]; then
            _lbg_log="$SCRIPT_DIR/logs/gate_fire_log.yaml"
            _lbg_ts=$(date -Iseconds)
            mkdir -p "$(dirname "$_lbg_log")"
            (
                flock -w 5 9 || true
                echo "- ts: \"$_lbg_ts\", file: \"$_lbg_cmd_id\", gate: \"lgtm_bundle_guard\", result: BLOCK, reasons: \"LGTM for $_lbg_cmd_id but queue/gates/$_lbg_cmd_id/sg7_bundle.json is missing\"" >> "$_lbg_log"
            ) 9>>"$_lbg_log.lock"
            echo "BLOCK: lgtm_bundle_guard: $_lbg_cmd_id のsg7_bundle.jsonが未生成。先に bash scripts/review_approval.sh $_lbg_cmd_id gunshi LGTM <report_path> を実行してからreview_log記録せよ" >&2
            exit 2
        fi
    fi
fi

# --- gate_prediction_reason必須チェック(report) --- GP-259: prediction偽陽性分析の材料を残す
if [ "$ENTRY_REVIEW_TYPE" = "report" ] && [[ "$ENTRY" =~ gate_prediction:[[:space:]]*(CLEAR|WARN|BLOCK) ]]; then
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
    _actual_text = str(ops.get("actual", ""))
    import re as _re072
    if _re072.search(r"0件|不在|存在しない|見つからない|実在しない", _actual_text):
        _cmd_text = str(ops.get("command", ""))
        if not _re072.search(r"git log -S|Read\(|cat |head |通読|周辺確認", _cmd_text):
            print("BLOCK: actual「0件/不在」主張にはcommandに同一ファイル通読またはgit log -S証跡が必須(LG072)", file=sys.stderr); raise SystemExit(2)
verdict = str(item.get("verdict") or "").strip().upper()
if verdict in {"APPROVE", "LGTM"}:
    _ops_actual = str((item.get("operational_simulation") or {}).get("actual") or "")
    if re.search(r"\bERRORS\s*=\s*[1-9][0-9]*\b", _ops_actual, re.IGNORECASE):
        print("BLOCK: precheck ERRORS>0の報告はAPPROVE/LGTM不可。理由に関わらずFAIL/RCへ送れ(LG085)", file=sys.stderr); raise SystemExit(2)
    files = item.get("verified_files")
    if isinstance(files, str): files = [files]
    valid = isinstance(files, list) and any(isinstance(v, str) and re.search(r"^[^:\s]+:(?:[1-9][0-9]*|[A-Za-z_][A-Za-z0-9_.-]*)$", v.strip()) for v in files)
    if not valid:
        print("BLOCK: APPROVE/LGTM requires verified_files file:line or file:symbol evidence", file=sys.stderr); raise SystemExit(2)
    # LG073: 軍師の利害に関わる対象のAPPROVE/LGTMにはconflict_of_interest必須
    _conflict_paths = {"gate_gunshi", "review_approval", "gunshi_review_log"}
    if isinstance(files, list) and any(any(cp in str(v) for cp in _conflict_paths) for v in files if isinstance(v, str)):
        _coi = str(item.get("conflict_of_interest") or "").strip()
        if not _coi or _coi.lower() in {"none", "null", "n/a", ""}:
            print("BLOCK: 軍師の利害に関わる対象(gate_gunshi/review_approval/gunshi_review_log)のAPPROVE/LGTMにはconflict_of_interestフィールドが必須(LG073)", file=sys.stderr); raise SystemExit(2)
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
if [[ "$ENTRY" == *"remediation:"* || "$ENTRY" == *"terminal_tombstone:"* ]]; then
    python3 - "$LOG_FILE" "$ARCHIVE_DIR" "$ENTRY" <<'PY'
import glob, os, re, sys, yaml
allowed = {"operational_simulation", "verified_files", "adversarial", "step3_5_verified", "d0_applied", "hole_action"}
try:
    old = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or []
    parsed = yaml.safe_load(sys.argv[3])
except Exception as exc:
    print(f"BLOCK: remediation YAML parse error: {exc}", file=sys.stderr); raise SystemExit(2)
if not isinstance(parsed, list) or len(parsed) != 1 or not isinstance(parsed[0], dict):
    print("BLOCK: remediation entry must be one YAML list item", file=sys.stderr); raise SystemExit(2)
item = parsed[0]; rem = item.get("remediation")
if "terminal_tombstone" in item:
    tomb = item.get("terminal_tombstone")
    target_id = str(tomb.get("target_remediation_cmd_id") or "").strip() if isinstance(tomb, dict) else ""
    matches = [x for x in old if isinstance(x, dict) and str(x.get("cmd_id") or x.get("id") or "").strip() == target_id and "remediation" in x]
    existing = [x for x in old if isinstance(x, dict) and isinstance(x.get("terminal_tombstone"), dict) and str(x["terminal_tombstone"].get("target_remediation_cmd_id") or "").strip() == target_id]
    evidence = tomb.get("evidence") if isinstance(tomb, dict) else None
    if item.get("review_type") != "self_study" or len(matches) != 1 or existing or not str(tomb.get("reason") or "").strip() or not isinstance(evidence, list) or not evidence:
        print(f"BLOCK: invalid terminal tombstone target/evidence: {target_id or '<empty>'}", file=sys.stderr); raise SystemExit(2)
    raise SystemExit(0)
target = str(rem.get("target_cmd_id") or "").strip() if isinstance(rem, dict) else ""
target_type = str(rem.get("target_review_type") or "").strip() if isinstance(rem, dict) else ""
target_at = str(rem.get("target_reviewed_at") or "").strip() if isinstance(rem, dict) else ""
sources = [("active", old)]
for path in sorted(glob.glob(os.path.join(sys.argv[2], "gunshi_review_log*.yaml"))):
    try: archived = yaml.safe_load(open(path, encoding="utf-8")) or []
    except Exception: continue
    sources.append((os.path.basename(path), archived))
generation = str(rem.get("target_generation") or "").strip() if isinstance(rem, dict) else ""
records = [(g, x) for g, items in sources for x in items if isinstance(x, dict) and "remediation" not in x and "terminal_tombstone" not in x]
matches = [(g, x) for g, x in records if str(x.get("cmd_id") or x.get("id") or "").strip() == target and (not generation or g == generation)]
identity_partial = bool(target_type) != bool(target_at)
if target_type and target_at:
    matches = [(g, x) for g, x in matches if str(x.get("review_type") or "").strip() == target_type and str(x.get("reviewed_at") or "").strip() == target_at]
fields = rem.get("fields") if isinstance(rem, dict) else None
evidence = rem.get("evidence") if isinstance(rem, dict) else None
bad_fields = not isinstance(fields, dict) or not fields or any(k not in allowed or v is None or v is False or str(v).strip().lower() in {"", "null", "none", "n/a", "[]", "{}"} for k, v in (fields or {}).items())
bad_evidence = not isinstance(evidence, list) or not evidence or any(not isinstance(v, str) or not v.strip() or not re.search(r"(?:[^:]+:[A-Za-z0-9_.-]+|\b[0-9a-f]{7,40}\b)", v) for v in (evidence or []))
if item.get("review_type") != "self_study" or identity_partial or len(matches) != 1 or bad_fields or bad_evidence:
    print(f"BLOCK: invalid remediation target/fields/evidence: {target or '<empty>'}", file=sys.stderr); raise SystemExit(2)
PY
fi

if [ "${GUNSHI_VALIDATE_ONLY:-0}" = "1" ]; then
    echo "OK: review entry validated"
    exit 0
fi

# Publish append and any resulting archive as one generation transaction.
exec 200>"$LOG_FILE.lock"
flock -w 30 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
echo "$ENTRY" >> "$LOG_FILE"

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

# Archive old entries through atomic rename; readers hold the shared generation
# lock and can therefore see either the complete old or complete new pair.
ARCHIVE_TEMP=$(mktemp "$ARCHIVE_DIR/.gunshi_review_archive.XXXXXX")
sed -n "${FIRST_ENTRY},$((SPLIT_BOUNDARY - 1))p" "$LOG_FILE" > "$ARCHIVE_TEMP"
ARCHIVED_LINES=$(wc -l < "$ARCHIVE_TEMP")

# Rebuild main file: header + remaining entries
TEMP_FILE=$(mktemp)
{ sed -n "1,${HEADER_END}p" "$LOG_FILE"; sed -n "${SPLIT_BOUNDARY},\$p" "$LOG_FILE"; } > "$TEMP_FILE"

# Add archive reference to header (after last archive reference line)
LAST_ARCHIVE_LINE=$(grep -n '# 詳細エントリ:' "$TEMP_FILE" | tail -1 | cut -d: -f1 || true)
if [ -n "$LAST_ARCHIVE_LINE" ]; then
    sed -i "${LAST_ARCHIVE_LINE}a\\# 詳細エントリ: ${ARCHIVE_NAME} → logs/archive/gunshi_review_log_${ARCHIVE_NAME}.yaml" "$TEMP_FILE"
fi

mv "$ARCHIVE_TEMP" "$ARCHIVE_FILE"
mv "$TEMP_FILE" "$LOG_FILE"

NEW_LINES=$(wc -l < "$LOG_FILE")
echo "ARCHIVE: done. ${ARCHIVED_LINES} lines → ${ARCHIVE_FILE##*/}. Main: ${TOTAL_LINES} → ${NEW_LINES} lines"
