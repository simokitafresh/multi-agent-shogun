#!/bin/bash
# semantic-links: [[セマンティック辞書構想]]
# insight_write.sh — 学習ループの「次の気づき」を即座に保存
# Usage: bash scripts/insight_write.sh "気づきの内容" [priority] [source]
#        bash scripts/insight_write.sh --resolve <id> <reason> <action_artifact>
#   priority: high/medium/low (default: medium)
#   source: 気づきの出所 (default: manual)
#   optional env: INSIGHT_FIX_KNOWN=1 INSIGHT_TARGET_FILE=<path> INSIGHT_VERIFY_COMMAND=<cmd>
#
# 設計原則: 1コマンドで保存完了。コスト最小。/clear後も消えない。
# 消費: idle時 or セッション開始時にqueue/insights.yamlを確認→着手

set -euo pipefail

_insight_self="${BASH_SOURCE[0]:-$0}"
[[ "$_insight_self" != /* ]] && _insight_self="$PWD/$_insight_self"
SCRIPT_DIR="${_insight_self%/scripts/insight_write.sh}"
INSIGHTS_FILE="${INSIGHTS_FILE:-$SCRIPT_DIR/queue/insights.yaml}"
# lock_path()導入: yaml_field_set経路(insight_resolve.sh等)と同一ロックドメインへ統一
# (cmd_3874: 隣接.lockとlock_path()由来の二系統lock不整合がinsights.yaml全損の真因)
# shellcheck source=lib/yaml_field_set.sh
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
BULLETIN_SCRIPT="$SCRIPT_DIR/scripts/bulletin_write.sh"
MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
  MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert.py"
fi
SOURCE_REPEAT_THRESHOLD="${INSIGHT_SOURCE_REPEAT_THRESHOLD:-3}"

usage() {
  cat <<'EOF'
Usage: bash scripts/insight_write.sh "気づきの内容" [priority] [source]
       bash scripts/insight_write.sh --resolve <id> <reason> <action_artifact>

priority: high/medium/low (default: medium)
source: 気づきの出所 (default: manual)
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

# Compatibility entry point. Resolution itself has exactly one writer/contract.
if [ "${1:-}" = "--resolve" ]; then
  [ "$#" -eq 4 ] || { echo "ERROR: --resolve requires <id> <reason> <action_artifact>" >&2; exit 2; }
  INSIGHTS_FILE="$INSIGHTS_FILE" bash "$SCRIPT_DIR/scripts/insight_resolve.sh" "$2" "$3" "$4"
  exit $?
fi

msg="${1:?Usage: insight_write.sh \"message\" [priority] [source]}"
priority="${2:-medium}"
source_info="${3:-manual}"
fix_known="${INSIGHT_FIX_KNOWN:-false}"
target_file="${INSIGHT_TARGET_FILE:-}"
verify_command="${INSIGHT_VERIFY_COMMAND:-}"
verify_timeout="${INSIGHT_VERIFY_TIMEOUT:-10}"

# Validate priority
if [[ ! "$priority" =~ ^(high|medium|low)$ ]]; then
  echo "ERROR: priority must be high/medium/low, got: '$priority'" >&2
  exit 1
fi
if [[ ! "$SOURCE_REPEAT_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: INSIGHT_SOURCE_REPEAT_THRESHOLD must be a non-negative integer, got: '$SOURCE_REPEAT_THRESHOLD'" >&2
  exit 1
fi
case "${fix_known,,}" in
  1|true|yes|y) fix_known="true" ;;
  ""|0|false|no|n) fix_known="false" ;;
  *)
    echo "ERROR: INSIGHT_FIX_KNOWN must be true/false, got: '$fix_known'" >&2
    exit 1
    ;;
esac
if [[ ! "$verify_timeout" =~ ^[0-9]+$ ]] || [[ "$verify_timeout" -le 0 ]]; then
  echo "ERROR: INSIGHT_VERIFY_TIMEOUT must be a positive integer, got: '$verify_timeout'" >&2
  exit 1
fi

# Skip synthetic test fixtures. They are useful in tests, but must not pollute the real queue.
if [[ "$msg" == *"test_pattern"* || "$msg" == *"test_fix"* ]]; then
  echo "SKIP:test-fixture"
  exit 0
fi

verification_status="not_requested"
verification_exit_code=""
verification_output=""
if [[ "$fix_known" == "true" && -n "$verify_command" ]]; then
  set +e
  verification_output="$(timeout "$verify_timeout" bash -lc "$verify_command" 2>&1)"
  verification_exit_code="$?"
  set -e
  if [[ "$verification_exit_code" -eq 0 ]]; then
    verification_status="passed"
  else
    verification_status="failed"
  fi
fi

# Generate ID and ts in a single date call (eliminates redundant second subprocess).
# Placed after test-fixture exit to avoid date overhead on skipped calls.
read -r _insight_uuid < /proc/sys/kernel/random/uuid
_insight_now="$(date '+%Y%m%d-%H%M%S%3N %Y-%m-%dT%H:%M:%S%:z')"
id="INS-${_insight_now%% *}-${_insight_uuid:0:4}"
ts="${_insight_now#* }"

# Insight creation never implies resolution. Evidence must be supplied later to
# insight_resolve.sh; wording alone cannot prove an action happened.
status="pending"
resolved_at=""

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    printf 'insights:\n' > "$INSIGHTS_FILE"
  else
    IFS= read -r _iw_first <"$INSIGHTS_FILE" || true
    [[ "$_iw_first" == 'insights: []' ]] && printf 'insights:\n' > "$INSIGHTS_FILE"
  fi

  # Dedup check + raw YAML append + source repeat count (single Python process).
  # Merging into one pass avoids a second python3 startup and second file read.
  # Parse the controlled YAML shape directly to avoid importing PyYAML on every call.
  raw_result=$(INSIGHTS_FILE_ENV="$INSIGHTS_FILE" MSG_ENV="$msg" PRIORITY_ENV="$priority" \
               SOURCE_INFO_ENV="$source_info" ID_ENV="$id" TS_ENV="$ts" STATUS_ENV="$status" \
               RESOLVED_AT_ENV="$resolved_at" FIX_KNOWN_ENV="$fix_known" \
               TARGET_FILE_ENV="$target_file" VERIFY_COMMAND_ENV="$verify_command" \
               VERIFICATION_STATUS_ENV="$verification_status" \
               VERIFICATION_EXIT_CODE_ENV="$verification_exit_code" \
               VERIFICATION_OUTPUT_ENV="$verification_output" \
               python3 - <<'PYEOF'
import json
import os
import re
import sys
import tempfile
import time

insights_file = os.environ['INSIGHTS_FILE_ENV']
msg = os.environ['MSG_ENV']
priority = os.environ['PRIORITY_ENV']
source_info = os.environ['SOURCE_INFO_ENV']
entry_id = os.environ['ID_ENV']
ts = os.environ['TS_ENV']
status = os.environ['STATUS_ENV']
resolved_at = os.environ['RESOLVED_AT_ENV']
fix_known = os.environ['FIX_KNOWN_ENV']
target_file = os.environ['TARGET_FILE_ENV']
verify_command = os.environ['VERIFY_COMMAND_ENV']
verification_status = os.environ['VERIFICATION_STATUS_ENV']
verification_exit_code = os.environ['VERIFICATION_EXIT_CODE_ENV']
verification_output = os.environ['VERIFICATION_OUTPUT_ENV']

def repair_trailing_partial_entry(path):
    """Quarantine an incomplete tail entry before scanning/appending."""
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    if not lines:
        return

    truncate_at = None
    current_start = None
    current_has_status = False
    header_seen = False
    known_fields = (
        '  ts:', '  insight:', '  priority:', '  source:', '  status:',
        '  resolved_at:', '  resolved_reason:', '  action_artifact:', '  fix_known:',
        '  target_file:', '  verify_command:', '  verification:',
        '  insight_summary_hash:', '  occurrence_count:', '  last_seen:',
        '    status:', '    exit_code:', '    output:',
    )

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not header_seen:
            # Operational provenance comments are valid YAML and may precede
            # the top-level key.  Treating them as corruption used to
            # quarantine the entire healthy queue on the next append.
            if not stripped or stripped.startswith('#'):
                continue
            if stripped == 'insights:':
                header_seen = True
                continue
            truncate_at = idx
            break
        if stripped.startswith('#'):
            continue
        if not stripped:
            continue
        if line.startswith('- id: '):
            if current_start is not None and not current_has_status:
                truncate_at = current_start
                break
            current_start = idx
            current_has_status = False
            continue
        if current_start is None:
            truncate_at = idx
            break
        if line.startswith('  status:'):
            current_has_status = True
            continue
        if line.startswith(known_fields):
            continue
        truncate_at = idx
        break

    if truncate_at is None and current_start is not None and not current_has_status:
        truncate_at = current_start

    if truncate_at is None:
        return

    keep = lines[:truncate_at]
    corrupt = lines[truncate_at:]
    if not keep:
        keep = ['insights:\n']
    elif keep[-1] and not keep[-1].endswith('\n'):
        keep[-1] += '\n'

    archive_dir = os.environ.get('INSIGHT_CORRUPT_ARCHIVE_DIR')
    if not archive_dir:
        archive_dir = os.path.join(os.path.dirname(os.path.abspath(path)), 'archive', 'insights_corrupt')
    os.makedirs(archive_dir, exist_ok=True)
    corrupt_path = os.path.join(archive_dir, f"{os.path.basename(path)}.corrupt.{int(time.time() * 1000)}")
    with open(corrupt_path, 'w', encoding='utf-8') as f:
        f.writelines(corrupt)
    directory = os.path.dirname(os.path.abspath(path)) or '.'
    fd, tmp_path = tempfile.mkstemp(prefix='.insights.', suffix='.tmp', dir=directory)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.writelines(keep)
            f.flush()
            os.fsync(f.fileno())
        sleep_sec = float(os.environ.get('INSIGHT_TEST_SLEEP_BEFORE_REPLACE', '0') or '0')
        if sleep_sec > 0:
            time.sleep(sleep_sec)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

repair_trailing_partial_entry(insights_file)

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

def normalize_text(value):
    return re.sub(r'\s+', ' ', value).strip().lower()

def yaml_escape(s):
    """JSON double-quoted strings are valid YAML double-quoted scalars."""
    return json.dumps(s, ensure_ascii=False)

def direct_alias_key(value):
    match = re.search(r'\[\[[^\]]+\]\]\s*alias:\s*(.+)', value, flags=re.IGNORECASE)
    if not match:
        return None
    aliases = [normalize_text(part) for part in match.group(1).split(',')]
    aliases = [part for part in aliases if part]
    if not aliases:
        return None
    return 'direct_alias:' + '|'.join(sorted(aliases))

def semantic_query_key(value):
    direct = direct_alias_key(value)
    if direct:
        return direct
    normalized = normalize_text(value)
    if not normalized:
        return None
    return 'query:' + normalized

new_semantic_key = semantic_query_key(msg)

def summary_hash(value):
    import hashlib
    return hashlib.sha256(normalize_text(value).encode('utf-8')).hexdigest()

new_summary_hash = summary_hash(msg)

# A verified fix-known finding represents a conclusion, not a verification
# command invocation.  Repeated detections of the same normalized conclusion
# from the same source are folded into the existing pending ledger entry.
# Once resolved, the ledger is terminal: repeated detections return the stable
# ID without rewriting occurrence_count/last_seen and dirtying the Git worktree.
# Differing commands remain evidence on the caller side, not identity.
if fix_known == 'true':
    with open(insights_file, 'r', encoding='utf-8') as f:
        ledger_lines = f.readlines()

    blocks = []
    start = None
    for idx, line in enumerate(ledger_lines):
        if line.startswith('- id: '):
            if start is not None:
                blocks.append((start, idx))
            start = idx
    if start is not None:
        blocks.append((start, len(ledger_lines)))

    matched = None
    for block_start, block_end in blocks:
        values = {}
        for line in ledger_lines[block_start:block_end]:
            if line.startswith('- id: '):
                values['id'] = line[len('- id: '):].strip()
            elif line.startswith('  insight:'):
                values['insight'] = parse_scalar(line.split(':', 1)[1])
            elif line.startswith('  source:'):
                values['source'] = parse_scalar(line.split(':', 1)[1])
            elif line.startswith('  status:'):
                values['status'] = parse_scalar(line.split(':', 1)[1])
            elif line.startswith('  insight_summary_hash:'):
                values['hash'] = parse_scalar(line.split(':', 1)[1])
            elif line.startswith('  occurrence_count:'):
                values['count'] = parse_scalar(line.split(':', 1)[1])
        existing_hash = values.get('hash')
        if not existing_hash and values.get('insight') is not None:
            existing_hash = summary_hash(values['insight'])
        if values.get('source') == source_info and existing_hash == new_summary_hash:
            matched = (block_start, block_end, values)
            break

    if matched is not None:
        block_start, block_end, values = matched
        if values.get('status') == 'resolved':
            print('AGGREGATE:' + values['id'])
            print(values.get('count', '1'))
            print('resolved_noop')
            sys.exit(0)
        try:
            occurrence_count = int(values.get('count', '1')) + 1
        except ValueError:
            occurrence_count = 2
        replacement = []
        saw_hash = saw_count = saw_last_seen = False
        for line in ledger_lines[block_start:block_end]:
            if line.startswith('  insight_summary_hash:'):
                replacement.append(f'  insight_summary_hash: {yaml_escape(new_summary_hash)}\n')
                saw_hash = True
            elif line.startswith('  occurrence_count:'):
                replacement.append(f'  occurrence_count: {occurrence_count}\n')
                saw_count = True
            elif line.startswith('  last_seen:'):
                replacement.append(f'  last_seen: {yaml_escape(ts)}\n')
                saw_last_seen = True
            else:
                replacement.append(line)
        if not saw_hash:
            replacement.append(f'  insight_summary_hash: {yaml_escape(new_summary_hash)}\n')
        if not saw_count:
            replacement.append(f'  occurrence_count: {occurrence_count}\n')
        if not saw_last_seen:
            replacement.append(f'  last_seen: {yaml_escape(ts)}\n')

        directory = os.path.dirname(os.path.abspath(insights_file)) or '.'
        fd, tmp_path = tempfile.mkstemp(prefix='.insights.', suffix='.tmp', dir=directory)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as out:
                out.writelines(ledger_lines[:block_start])
                out.writelines(replacement)
                out.writelines(ledger_lines[block_end:])
                out.flush()
                os.fsync(out.fileno())
            os.replace(tmp_path, insights_file)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        print('AGGREGATE:' + values['id'])
        print(occurrence_count)
        print('aggregated')
        sys.exit(0)

# Single-pass: dedup check + source repeat count
current_id = None
current_insight = None
current_status = None
current_source = None
current_semantic_key = None
source_pending_count = 0

with open(insights_file, 'r', encoding='utf-8') as f:
    for line in f:
        if line.startswith('- id: '):
            if current_status == 'pending':
                if current_insight is not None:
                    if fix_known != 'true' and (current_insight == msg or (msg and current_insight[:50] == msg[:50])):
                        print('SKIP:' + current_id)
                        sys.exit(0)
                    if (
                        fix_known != 'true'
                        and current_source == source_info
                        and new_semantic_key is not None
                        and current_semantic_key is not None
                        and (
                            current_semantic_key == new_semantic_key
                            or current_insight[:50] == msg[:50]
                        )
                    ):
                        print('SKIP:' + current_id)
                        sys.exit(0)
                if current_source == source_info:
                    source_pending_count += 1
            current_id = line[len('- id: '):].strip()
            current_insight = None
            current_status = None
            current_source = None
            current_semantic_key = None
            continue
        if current_id is None:
            continue
        if line.startswith('  insight:'):
            current_insight = parse_scalar(line.split(':', 1)[1])
            current_semantic_key = semantic_query_key(current_insight)
        elif line.startswith('  status:'):
            current_status = parse_scalar(line.split(':', 1)[1])
        elif line.startswith('  source:'):
            current_source = parse_scalar(line.split(':', 1)[1])

# Finalize last entry
if current_status == 'pending':
    if current_insight is not None:
        if fix_known != 'true' and (current_insight == msg or (msg and current_insight[:50] == msg[:50])):
            print('SKIP:' + current_id)
            sys.exit(0)
        if (
            fix_known != 'true'
            and current_source == source_info
            and new_semantic_key is not None
            and current_semantic_key is not None
            and (
                current_semantic_key == new_semantic_key
                or current_insight[:50] == msg[:50]
            )
        ):
            print('SKIP:' + current_id)
            sys.exit(0)
    if current_source == source_info:
        source_pending_count += 1

# Count new entry itself if it will be pending
if status == 'pending':
    source_pending_count += 1

# Append raw YAML entry via atomic replace. This keeps raw YAML bytes intact while
# preventing a killed writer from leaving a half-written entry in the live file.
entry_lines = [
    f'- id: {entry_id}\n',
    f'  ts: {yaml_escape(ts)}\n',
    f'  insight: {yaml_escape(msg)}\n',
    f'  priority: {yaml_escape(priority)}\n',
    f'  source: {yaml_escape(source_info)}\n',
    f'  fix_known: {fix_known}\n',
    f'  status: {status}\n',
]
if target_file:
    entry_lines.append(f'  target_file: {yaml_escape(target_file)}\n')
if verify_command:
    entry_lines.append(f'  verify_command: {yaml_escape(verify_command)}\n')
if fix_known == 'true':
    entry_lines.extend([
        f'  insight_summary_hash: {yaml_escape(new_summary_hash)}\n',
        '  occurrence_count: 1\n',
        f'  last_seen: {yaml_escape(ts)}\n',
    ])
if verification_status != 'not_requested':
    verification_output = re.sub(r'\s+', ' ', verification_output).strip()
    if len(verification_output) > 300:
        verification_output = verification_output[:300] + '...'
    entry_lines.extend([
        '  verification:\n',
        f'    status: {yaml_escape(verification_status)}\n',
        f'    exit_code: {verification_exit_code or -1}\n',
        f'    output: {yaml_escape(verification_output)}\n',
    ])
if resolved_at:
    entry_lines.append(f'  resolved_at: {yaml_escape(resolved_at)}\n')

directory = os.path.dirname(os.path.abspath(insights_file)) or '.'
fd, tmp_path = tempfile.mkstemp(prefix='.insights.', suffix='.tmp', dir=directory)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        with open(insights_file, 'r', encoding='utf-8') as src:
            for line in src:
                out.write(line)
        out.writelines(entry_lines)
        out.flush()
        os.fsync(out.fileno())
    os.replace(tmp_path, insights_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)

# Line 1: entry_id; Line 2: source_pending_count; Line 3: immediate action flag
print(entry_id)
print(source_pending_count)
print('fix_known_verified' if fix_known == 'true' and verification_status == 'passed' else 'threshold')
PYEOF
) || { echo "ERROR: insight write failed" >&2; exit 1; }

  # Parse the fixed three-line Python result once with a Bash builtin.  The
  # escalation path previously started printf+sed twice for lines 2 and 3.
  mapfile -t _raw_result_lines <<< "$raw_result"
  result="${_raw_result_lines[0]}"
  echo "$result"

  if [[ "$result" == INS-* && -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    memory_db_args=(
      insight
      --entry-id "$result"
      --ts "$ts"
      --insight "$msg"
      --priority "$priority"
      --source "$source_info"
      --status "$status"
      --resolved-at "$resolved_at"
      --source-file "$INSIGHTS_FILE"
    )
    if [[ -n "${SHOGUN_MEMORY_DB:-}" ]]; then
      if ! python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null; then
        echo "WARN: insight DB INSERT skipped" >&2
      fi
    else
      # A background child that only uses `&`/disown still inherits the
      # caller's process group and stdin.  Under Bats/CI that keeps the test
      # formatter pipe and heavy-job PGID alive after every assertion passed.
      # Start a new session and sever all standard streams while preserving
      # the durable async queue/insert contract.
      setsid -f python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" \
        </dev/null >/dev/null 2>&1 200>&-
      disown 2>/dev/null || true
    fi
  fi

  # Escalate repeated pending insights from the same source so important patterns
  # do not remain buried in queue/insights.yaml. Keep this out of the write path:
  # bulletin failures must not break normal insight recording.
  if [[ "$result" == INS-* ]]; then
    repeat_count="${_raw_result_lines[1]:-0}"
    escalation_mode="${_raw_result_lines[2]:-threshold}"
    if [[ "$escalation_mode" == "fix_known_verified" && -f "$BULLETIN_SCRIPT" ]]; then
      _fix_summary="${msg//$'\n'/ }"
      _fix_summary="${_fix_summary//$'\r'/ }"
      _fix_summary="${_fix_summary//$'\t'/ }"
      if (( ${#_fix_summary} > 200 )); then
        _fix_summary="${_fix_summary:0:200}..."
      fi
      BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" saizo \
        "INSIGHT_FIX_KNOWN: latest=${result} source=${source_info} priority=${priority} target_file=${target_file:-none} verify_command=${verify_command} verification=passed insight_summary=${_fix_summary}" \
        false action_required \
        >/dev/null || echo "WARN: insight fix_known bulletin failed for source=$source_info" >&2
    elif [[ "$SOURCE_REPEAT_THRESHOLD" -gt 0 && "$repeat_count" -ge "$SOURCE_REPEAT_THRESHOLD" && -f "$BULLETIN_SCRIPT" ]]; then
      # デバウンス: 同一sourceのINSIGHT_REPEATを24時間以内に重複投稿しない (10分→24h: 2026-06-29 INSIGHT_REPEAT 17件蓄積→確認負荷→先送り誘発の対策)
      _repeat_debounce_file="/tmp/shogun_insight_repeat_${source_info//[^a-zA-Z0-9_]/_}.last"
      _repeat_now=$(date +%s)
      _repeat_last=0
      [[ -f "$_repeat_debounce_file" ]] && _repeat_last=$(cat "$_repeat_debounce_file" 2>/dev/null || echo 0)
      if (( _repeat_now - _repeat_last > 86400 )); then
        printf '%s' "$_repeat_now" > "$_repeat_debounce_file"
        _repeat_summary="${msg//$'\n'/ }"
        _repeat_summary="${_repeat_summary//$'\r'/ }"
        _repeat_summary="${_repeat_summary//$'\t'/ }"
        if (( ${#_repeat_summary} > 200 )); then
          _repeat_summary="${_repeat_summary:0:200}..."
        fi
        BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" saizo \
          "INSIGHT_REPEAT: source=${source_info} pending_count=${repeat_count} threshold=${SOURCE_REPEAT_THRESHOLD} latest=${result} priority=${priority} insight_summary=${_repeat_summary}" \
          false action_required \
          >/dev/null || echo "WARN: insight repeat bulletin failed for source=$source_info" >&2
      fi
    fi
  fi

) 200>"$(lock_path "$INSIGHTS_FILE")"

# Auto-commit: insights.yamlをdirtyのまま放置するとreflux dispatchの
# dirty-guard(reflux dirty dispatch blocked)が発火し、小改善レーン全体が止まる。
# 実証: 2026-08-25 03:28将軍のinsight_write→未commit→03:35のsaizo宛reflux弾BLOCK。
# 書込み成功のたびにscope commitしてレーンを常時通す。repo既定パスのみ対象
# (テストのINSIGHTS_FILE差替えは対象外)。commit失敗は本体成功を壊さない。
if [[ "${INSIGHT_AUTO_COMMIT:-1}" == "1" && "$INSIGHTS_FILE" == "$SCRIPT_DIR/queue/insights.yaml" ]]; then
  if ! git -C "$SCRIPT_DIR" diff --quiet -- queue/insights.yaml 2>/dev/null; then
    # index.lock競合(他忍者のcommit中)はfail-fast BLOCKされるため短いリトライで吸収
    _iac_ok=0
    for _iac_try in 1 2 3; do
      if bash "$SCRIPT_DIR/scripts/ninja_scope_commit.sh" -m "insights: auto-commit (reflux dirty-guard防止)" -- queue/insights.yaml >/dev/null 2>&1; then
        _iac_ok=1
        break
      fi
      # dirtyが他プロセスにより解消済みなら成功扱い
      git -C "$SCRIPT_DIR" diff --quiet -- queue/insights.yaml 2>/dev/null && { _iac_ok=1; break; }
      sleep $(( _iac_try * 3 ))
    done
    [[ "$_iac_ok" == "1" ]] || echo "WARN: insights auto-commit failed after retries (reflux dirty-guardに注意)" >&2
  fi
fi
