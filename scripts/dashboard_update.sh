#!/usr/bin/env bash
# ============================================================
# dashboard_update.sh
# report YAMLからdashboard.mdの「最新更新」セクションを自動更新
# 家老の手動更新作業を排除する
#
# Usage: bash scripts/dashboard_update.sh <cmd_id> [--dry-run]
#   cmd_id (必須): cmd_XXX 形式（英数字・アンダースコア・ハイフン）
#   --dry-run: 差分のみ表示。dashboard.mdは変更しない
#
# Exit:
#   0: 成功（dashboard.md更新完了）
#   1: 失敗（解析エラー等。stderrにWARN出力）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
source "$PROJECT_DIR/scripts/lib/agent_config.sh"

CMD_ID=""
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [[ -z "$CMD_ID" ]]; then
                CMD_ID="$1"
                shift
            else
                echo "ERROR: unknown extra argument: $1" >&2
                exit 1
            fi
            ;;
    esac
done

_DASHBOARD_UPDATE_LOGGED=0
log_dashboard_update_skill_result() {
    local rc="${1:-0}"
    local result="PASS"
    [ "$rc" -eq 0 ] || result="FAIL"
    [ "$_DASHBOARD_UPDATE_LOGGED" -eq 0 ] || return 0
    _DASHBOARD_UPDATE_LOGGED=1
    [ "${SKILL_EXECUTION_LOG_DISABLE:-0}" != "1" ] || return 0
    local log_script="$PROJECT_DIR/scripts/skill_execution_log.sh"
    [ -x "$log_script" ] || return 0
    bash "$log_script" \
        "dashboard-update" \
        "${AGENT_ID:-${USER:-unknown}}" \
        "$result" \
        "dashboard_update.sh exit=${rc} cmd=${CMD_ID:-<empty>} dry_run=${DRY_RUN}" \
        "dashboard_update" \
        "scripts/dashboard_update.sh ${CMD_ID:-}" \
        "$PROJECT_DIR/skills/dashboard-update/SKILL.md" >/dev/null 2>&1 || true
}
trap 'rc=$?; log_dashboard_update_skill_result "$rc"; exit "$rc"' EXIT

# ─── Validation ───
if [[ -z "$CMD_ID" && "$DRY_RUN" == true ]]; then
    echo "DRY-RUN: cmd_id未指定のためdashboard_update本体をスキップ"
    exit 0
fi

if [[ -z "$CMD_ID" || ! "$CMD_ID" =~ ^cmd_[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: cmd_id は cmd_XXX 形式（英数字・アンダースコア・ハイフン）で指定せよ。" >&2
    echo "  進捗メモの追記は Edit tool で dashboard.md を直接編集すること。" >&2
    exit 1
fi

DASHBOARD="$PROJECT_DIR/dashboard.md"

# 二重化防止: queue/dashboard.md誤作成検出
if [[ -f "$PROJECT_DIR/queue/dashboard.md" ]]; then
    echo "WARN: queue/dashboard.md が存在します。正しいパスは $DASHBOARD です。" >&2
    echo "WARN: queue/dashboard.mdを削除してください（rm queue/dashboard.md）" >&2
fi

REPORTS_DIR="$PROJECT_DIR/queue/reports"
ARCHIVE_REPORTS_DIR="$PROJECT_DIR/queue/archive/reports"
STK_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

refresh_snapshot_before_auto_section() {
    local monitor_script="$SCRIPT_DIR/ninja_monitor.sh"
    [ -f "$monitor_script" ] || return 0
    # dashboard_auto_section.sh consumes queue/karo_snapshot.txt for fallback
    # status/model/idle data. Refresh it immediately before regenerating the
    # AUTO section so a just-finished task does not leave stale snapshot state
    # on dashboard.md until the next monitor cycle.
    timeout 20 bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$1"
        cycle=0
        refresh_karo_snapshot_fast_path
    ' _ "$monitor_script"
}

# ─── Export for Python ───
TEMPLATE="$PROJECT_DIR/config/dashboard_template.md"
export DASHBOARD REPORTS_DIR STK_FILE CMD_ID DRY_RUN TEMPLATE
export ARCHIVE_REPORTS_DIR

# Revalidate reports before dashboard generation.  After GATE CLEAR, lesson
# merge may legitimately dirty a reported lesson file.  Suppress only the
# commit-state inspection, and only while exact CLEAR + two-phase fingerprint
# approval still hold; schema/binary_checks/verdict always run.
validate_reports_before_dashboard() {
    local latest_status report skip_commit
    [ -d "$REPORTS_DIR" ] || return 0
    latest_status=$(awk -F '\t' -v cmd="$CMD_ID" '$2 == cmd { status=$3 } END { print status }' \
        "$PROJECT_DIR/logs/gate_metrics.log" 2>/dev/null || true)
    # shellcheck source=scripts/lib/review_approval.sh
    source "$PROJECT_DIR/scripts/lib/review_approval.sh"

    while IFS= read -r report; do
        skip_commit=0
        if [ "$latest_status" = "CLEAR" ] && review_two_phase_ready "$CMD_ID" "$report"; then
            skip_commit=1
        fi
        GATE_NO_LOG=1 GATE_SKIP_COMMIT_MISSING_CHECK="$skip_commit" \
            bash "$PROJECT_DIR/scripts/gates/gate_report_format.sh" "$report" || return 1
    done < <(python3 - "$REPORTS_DIR" "$CMD_ID" <<'PY'
import pathlib, sys, yaml
for path in sorted(pathlib.Path(sys.argv[1]).glob('*.yaml')):
    try:
        data = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    except (OSError, yaml.YAMLError):
        continue
    if str(data.get('parent_cmd', '')).strip() == sys.argv[2]:
        print(path)
PY
    )
}

validate_reports_before_dashboard

# ─── Main processing (flock for concurrency safety) ───
LOCK_FILE="${DASHBOARD}.lock"
(
    flock -w 10 200 || { echo "ERROR: flock取得失敗" >&2; exit 1; }

    python3 << 'PYEOF'
import yaml, glob, os, sys, re, shutil, subprocess

DASHBOARD = os.environ['DASHBOARD']
REPORTS_DIR = os.environ['REPORTS_DIR']
ARCHIVE_REPORTS_DIR = os.environ['ARCHIVE_REPORTS_DIR']
STK_FILE = os.environ['STK_FILE']
CMD_ID = os.environ['CMD_ID']
DRY_RUN = os.environ['DRY_RUN'] == 'true'

def atomic_write_text(path, content):
    tmp_path = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, 'w') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

# Build NAME_MAP dynamically from settings.yaml (cmd_1136)
def _build_name_map():
    import yaml as _y
    _map = {'karo': '家老'}
    _settings_path = os.path.join(os.environ.get('DASHBOARD', ''), '..', '..', 'config', 'settings.yaml')
    _settings_path = os.path.normpath(os.path.join(os.path.dirname(DASHBOARD), 'config', 'settings.yaml'))
    try:
        with open(_settings_path) as _f:
            _data = _y.safe_load(_f)
        for _name, _conf in (_data or {}).get('cli', {}).get('agents', {}).items():
            if isinstance(_conf, dict):
                _map[_name] = _conf.get('japanese_name', _name)
    except Exception:
        pass
    return _map

NAME_MAP = _build_name_map()


def get_nested(data, path, default=None):
    """Dot-separated path accessor for nested dicts."""
    keys = path.split('.')
    val = data
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            return default
    return val if val is not None else default


def get_first(data, *paths, default=''):
    """Return first non-empty value from multiple dot-paths."""
    for path in paths:
        val = get_nested(data, path)
        if val is not None and val != '' and val != []:
            return val
    return default


def iter_commands(commands):
    """Yield command dicts from both mapping and legacy list YAML shapes."""
    if isinstance(commands, dict):
        for cmd_id, cmd in commands.items():
            if isinstance(cmd, dict):
                if 'id' not in cmd:
                    cmd = {**cmd, 'id': cmd_id}
                yield cmd
    elif isinstance(commands, list):
        for cmd in commands:
            if isinstance(cmd, dict):
                yield cmd


def _strip_yaml_scalar(value):
    value = value.strip()
    if not value:
        return ''
    if value[0:1] in ('"', "'") and value[-1:] == value[0]:
        return value[1:-1]
    return value


def find_command_title(stk_file, cmd_id):
    """Read only the target command block from shogun_to_karo.yaml."""
    if not os.path.exists(stk_file):
        return ''

    cmd_key_re = re.compile(r'^\s{2}' + re.escape(cmd_id) + r':\s*(?:#.*)?$')
    list_id_re = re.compile(r'^\s*-\s+id:\s*[\'"]?' + re.escape(cmd_id) + r'[\'"]?\s*(?:#.*)?$')
    any_cmd_key_re = re.compile(r'^\s{2}[A-Za-z0-9_]+:\s*(?:#.*)?$')
    field_re = re.compile(r'^\s+(title|purpose):\s*(.*)$')

    in_target = False
    target_indent = None
    pending_multiline = None
    pending_indent = None

    try:
        with open(stk_file, encoding='utf-8', errors='replace') as f:
            for raw_line in f:
                line = raw_line.rstrip('\n')
                stripped = line.strip()
                indent = len(line) - len(line.lstrip(' '))

                if pending_multiline:
                    if stripped and indent > pending_indent:
                        return stripped
                    if stripped and indent <= pending_indent:
                        pending_multiline = None

                if in_target:
                    if target_indent is not None and indent <= target_indent and stripped:
                        if any_cmd_key_re.match(line) or line.lstrip().startswith('- id:'):
                            return ''
                    m = field_re.match(line)
                    if m:
                        value = _strip_yaml_scalar(m.group(2).split(' #', 1)[0])
                        if value in ('|', '>', '|-', '>-', '|+', '>+'):
                            pending_multiline = m.group(1)
                            pending_indent = indent
                            continue
                        if value:
                            return value
                    continue

                if cmd_key_re.match(line) or list_id_re.match(line):
                    in_target = True
                    target_indent = indent
    except Exception:
        return ''

    return ''


def summarize_ac(ac_val):
    """AC情報を短縮文字列に変換。"""
    if isinstance(ac_val, dict):
        pass_n = sum(1 for v in ac_val.values()
                     if isinstance(v, str) and bool(re.search(r'\bPASS\b', v.upper())))
        fail_n = sum(1 for v in ac_val.values()
                     if isinstance(v, str) and bool(re.search(r'\bFAIL\b', v.upper())))
        total = len(ac_val)
        if fail_n == 0 and pass_n > 0:
            return f'AC1-{total}全PASS'
        elif fail_n > 0:
            return f'PASS:{pass_n} FAIL:{fail_n}/{total}'
    elif isinstance(ac_val, str):
        return ac_val[:80]
    elif isinstance(ac_val, list):
        pass_n = sum(1 for v in ac_val
                     if isinstance(v, str) and bool(re.search(r'\bPASS\b', str(v).upper())))
        total = len(ac_val)
        if total > 0:
            return f'AC:{pass_n}/{total} PASS'
    return ''


def find_matches(search_dir, cmd_id_filter=None):
    if not os.path.isdir(search_dir):
        return []

    def cmd_ids_match(candidate, requested):
        candidate = str(candidate or '').strip()
        requested = str(requested or '').strip()
        return (
            candidate == requested
            or candidate.startswith(requested + '_')
            or requested.startswith(candidate + '_')
        )

    parent_cmd_re = re.compile(
        r'^\s*parent_cmd:\s*[\'"]?' + re.escape(CMD_ID) + r'(?:_[A-Za-z0-9_-]+)?[\'"]?\s*(?:#.*)?$'
    )

    def rg_parent_cmd_files():
        if not shutil.which('rg'):
            return None
        pattern = r'^\s*parent_cmd:\s*[\'"]?' + re.escape(CMD_ID) + r'[\'"]?\s*(#.*)?$'
        try:
            proc = subprocess.run(
                ['rg', '-l', pattern, search_dir, '-g', '*.yaml'],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except Exception:
            return None
        if proc.returncode not in (0, 1):
            return None
        return sorted(line for line in proc.stdout.splitlines() if line)

    def file_mentions_parent_cmd(fpath):
        try:
            with open(fpath, encoding='utf-8', errors='ignore') as f:
                for line in f:
                    if parent_cmd_re.match(line.rstrip('\n')):
                        return True
        except Exception:
            return False
        return False

    def scan_files(file_list):
        found = []
        for fpath in file_list:
            try:
                with open(fpath) as f:
                    raw = yaml.safe_load(f)
                if not raw:
                    continue
                pcmd = str(get_first(raw, 'parent_cmd', 'report.parent_cmd'))
                if not cmd_ids_match(pcmd, CMD_ID):
                    continue
                status = str(get_first(raw, 'status', 'report.status', default=''))
                # Skip placeholder reports (empty status)
                if not status.strip() or status.strip() == 'None':
                    continue
                ts = str(get_first(raw, 'timestamp', 'report.timestamp', default=''))
                found.append({'ts': ts, 'path': fpath, 'data': raw})
            except Exception:
                continue
        return found

    # GP-078: cmd_id指定時はファイル名でフィルタ（95→1-6件に削減）
    if cmd_id_filter:
        patterns = [
            os.path.join(search_dir, f'*_{cmd_id_filter}.yaml'),
            os.path.join(search_dir, f'*_{cmd_id_filter}_*.yaml'),
        ]
        candidates = set()
        for pat in patterns:
            candidates.update(glob.glob(pat))
        filtered_list = sorted(candidates)
        found = scan_files(filtered_list)
        if found:
            return found

        # Historical reports sometimes use task_id-based filenames while
        # parent_cmd holds the real cmd id (e.g. cmd_2514). Fall back to a
        # full scan only on miss so the hot path keeps the filename filter.
        scanned = set(filtered_list)
        rg_matches = rg_parent_cmd_files()
        if rg_matches is not None:
            fallback_list = [f for f in rg_matches if f not in scanned]
        else:
            fallback_list = [
                f for f in sorted(glob.glob(os.path.join(search_dir, '*.yaml')))
                if f not in scanned and file_mentions_parent_cmd(f)
            ]
        return scan_files(fallback_list)
    else:
        file_list = sorted(glob.glob(os.path.join(search_dir, '*.yaml')))
        return scan_files(file_list)


# ─── Step 1: Find matching report YAMLs ───
matches = find_matches(REPORTS_DIR, CMD_ID)
if not matches:
    matches = find_matches(ARCHIVE_REPORTS_DIR, CMD_ID)

if not matches:
    print(f"WARN: {CMD_ID}に対応する完了済みreport YAMLが見つかりません", file=sys.stderr)
    sys.exit(1)

# Sort by timestamp (latest first; empty timestamps go last)
matches.sort(key=lambda x: x['ts'] if x['ts'] else '', reverse=True)
latest = matches[0]['data']

# ─── Step 2: Extract fields with fallback ───
status_raw = str(get_first(latest, 'status', 'report.status', default=''))
status_label = '完了' if status_raw.lower() in ('done', 'completed') else status_raw

summary = str(get_first(latest, 'result.summary', 'report.summary',
                        'report.result.summary', 'report.conclusion',
                        default=''))
summary = summary.strip().replace('\n', ' ')
if len(summary) > 120:
    summary = summary[:117] + '...'

# Collect workers from ALL matching reports
workers = set()
for m in matches:
    w = get_first(m['data'], 'worker_id', 'report.agent',
                  'report.assigned_to', 'assigned_to')
    if w and str(w) != 'None':
        workers.add(str(w))

worker_names = [NAME_MAP.get(w, w) for w in sorted(workers)]
worker_str = '+'.join(worker_names) + '完遂' if worker_names else ''

# AC: use first found from any matching report
ac_str = ''
for m in matches:
    ac = get_first(m['data'], 'result.ac_results', 'result.ac_status',
                   'report.ac_checklist', 'report.acceptance_criteria',
                   'report.acceptance_criteria_check')
    if ac:
        ac_str = summarize_ac(ac)
        if ac_str:
            break

# ─── Step 3: Get cmd title from shogun_to_karo.yaml ───
title = find_command_title(STK_FILE, CMD_ID)

# ─── Step 4: Generate dashboard line ───
parts = [f'- **{CMD_ID}**: ']
if status_label:
    parts.append(f'{status_label}。')
if title:
    parts.append(title)
if summary and summary != title:
    parts.append(f' — {summary}')
if worker_str:
    parts.append(f'。{worker_str}')
if ac_str:
    parts.append(f'。{ac_str}')

new_line = ''.join(parts)
# Sanitize: remove control characters (backspace etc.) that break gh gist edit
new_line = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', new_line)

if DRY_RUN:
    print(f'DRY-RUN: {new_line}')
    sys.exit(0)

# ─── Step 5: Update dashboard.md ───
# Determine insert target from template (fallback: '## 最新更新')
TEMPLATE_PATH = os.environ.get('TEMPLATE', '')
insert_target = '## 最新更新'
if TEMPLATE_PATH and os.path.exists(TEMPLATE_PATH):
    with open(TEMPLATE_PATH) as tf:
        for tline in tf:
            if 'insert_target:' in tline and not tline.strip().startswith('#'):
                insert_target = '## ' + tline.split('insert_target:')[1].strip()
                break

with open(DASHBOARD, encoding='utf-8', errors='replace') as f:
    dashboard_text = f.read()
    lines = dashboard_text.split('\n')

if not any(line.startswith(insert_target) for line in lines):
    dashboard_is_empty = all(not line.strip() for line in lines)
    has_template_header = 'Dashboard Template' in dashboard_text
    has_auto_markers = '<!-- DASHBOARD_AUTO_START -->' in dashboard_text or '<!-- DASHBOARD_AUTO_END -->' in dashboard_text
    has_karo_markers = '<!-- KARO_SECTION_START -->' in dashboard_text or '<!-- KARO_SECTION_END -->' in dashboard_text
    has_section_headers = any(line.startswith('## ') for line in lines)
    # A partially written dashboard template can contain the template comment and H1
    # but miss both AUTO/KARO sections. Treat that as recoverable template corruption,
    # while still refusing arbitrary non-empty dashboards without 最新更新.
    dashboard_is_partial_template = (
        has_template_header
        and not has_auto_markers
        and not has_karo_markers
        and not has_section_headers
    )
    if (dashboard_is_empty or dashboard_is_partial_template) and TEMPLATE_PATH and os.path.exists(TEMPLATE_PATH):
        with open(TEMPLATE_PATH) as tf:
            template_content = tf.read()
        atomic_write_text(DASHBOARD, template_content)
        reason = 'empty dashboard' if dashboard_is_empty else 'partial template dashboard'
        print(f'WARN: DATA_QUALITY dashboard.md missing {insert_target}; restored {reason} from template', file=sys.stderr)
        lines = template_content.split('\n')
    elif '<!-- DASHBOARD_AUTO_END -->' in dashboard_text:
        dashboard_text = dashboard_text.replace(
            '<!-- DASHBOARD_AUTO_END -->',
            f'<!-- DASHBOARD_AUTO_END -->\n<!-- KARO_SECTION_START -->\n{insert_target}',
            1,
        )
        print(f'WARN: DATA_QUALITY dashboard.md missing {insert_target}; restored header after AUTO_END', file=sys.stderr)
        lines = dashboard_text.split('\n')
    else:
        print(f"ERROR: DATA_QUALITY '{insert_target}' section not found in dashboard.md; dashboard_update cannot append latest update", file=sys.stderr)
        sys.exit(1)

# Remove existing entry for this cmd_id (dedup) and track if it existed
cmd_pattern = re.compile(rf'^- \*\*{re.escape(CMD_ID)}\*\*:')
is_replacement = any(cmd_pattern.match(l) for l in lines)
lines = [l for l in lines if not cmd_pattern.match(l)]

# Insert after insert_target header
inserted = False
result = []
for line in lines:
    result.append(line)
    if line.startswith(insert_target) and not inserted:
        result.append(new_line)
        inserted = True

if not inserted:
    print(f"ERROR: DATA_QUALITY '{insert_target}' section not found in dashboard.md; dashboard_update cannot append latest update", file=sys.stderr)
    sys.exit(1)

content = '\n'.join(result)

# ─── Step 6: Counter updates (完了 status + 新規エントリのみ) ───
if status_label == '完了' and not is_replacement:
    # 連勝: N → N+1（戦況メトリクス > 本日の戦況）
    m = re.search(r'\| 連勝 \| (\d+)\s*\|', content)
    if m:
        current = int(m.group(1)) + 1
        content = content.replace(
            m.group(0),
            f'| 連勝 | {current} |')

    # cmd完了/配備: C/T → (C+1)/(T)（戦況メトリクス > 本日の戦況）
    m = re.search(r'\| cmd完了/配備 \| (\d+)/(\d+)\s*\|', content)
    if m:
        c = int(m.group(1)) + 1
        t = int(m.group(2))
        content = content.replace(
            m.group(0),
            f'| cmd完了/配備 | {c}/{t} |')

atomic_write_text(DASHBOARD, content)

if is_replacement:
    print(f'UPDATED: {CMD_ID} line replaced in 最新更新')
else:
    print(f'UPDATED: {CMD_ID} line appended to 最新更新')
if status_label == '完了' and not is_replacement:
    print('UPDATED: 連勝/cmd完了 counters')
PYEOF

    # ─── Step 6.5: AUTO域リアルタイム状況更新 (dashboard_auto_section.sh) ───
    # cmd_406: _step65_metricsの手動regex更新を廃止。
    # dashboard_auto_section.shがAUTO域(忍者配備/パイプライン/メトリクス)を一括再生成する。
    # GP-078: SKIP_AUTO_SECTION=1の場合は省略（cmd_complete_gate.shがL4060で別途実行するため二重呼出防止）
    if [[ "$DRY_RUN" != true ]] && [[ "${SKIP_AUTO_SECTION:-}" != "1" ]]; then
        refresh_snapshot_before_auto_section || echo "WARN: Step 6.5 snapshot refresh failed（AUTO域は既存snapshot/一次task YAMLで継続）" >&2
        bash "$SCRIPT_DIR/dashboard_auto_section.sh" || echo "WARN: Step 6.5 dashboard_auto_section.sh失敗（AUTO域は既存値を維持）" >&2
    fi

    # ─── Step 6.7: 要対応セクション安全ネット同期 (pending_decisions → dashboard) ───
    _step67_pd_sync() {
        local pd_file="$PROJECT_DIR/queue/pending_decisions.yaml"
        if [[ ! -f "$pd_file" ]]; then
            echo "WARN: pending_decisions.yaml not found. 要対応セクション更新スキップ" >&2
            return 0
        fi
        if [[ ! -f "$DASHBOARD" ]]; then
            echo "WARN: dashboard.md not found. 要対応セクション更新スキップ" >&2
            return 0
        fi

        export _PD_FILE="$pd_file"

        python3 << 'STEP67_PY'
import os, sys, re

dashboard_path = os.environ['DASHBOARD']
pd_file = os.environ['_PD_FILE']
dry_run = os.environ.get('DRY_RUN', 'false') == 'true'

def atomic_write_text(path, content):
    tmp_path = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, 'w') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

# Read pending_decisions.yaml (manual parse to avoid yaml import overhead if already loaded)
try:
    import yaml
    with open(pd_file) as f:
        pd_data = yaml.safe_load(f)
except Exception as e:
    print(f'WARN: pending_decisions.yaml読み込み失敗: {e}', file=sys.stderr)
    sys.exit(0)

if not pd_data or 'decisions' not in pd_data:
    pending_items = []
else:
    pending_items = [
        d for d in pd_data['decisions']
        if isinstance(d, dict) and d.get('status') == 'pending'
    ]

# Generate 要対応 section content
if pending_items:
    pd_lines = []
    for item in pending_items:
        pd_id = item.get('id', '???')
        summary = item.get('summary', '（詳細なし）')
        source = item.get('source_cmd', '')
        line = f'- **{pd_id}**: {summary}'
        if source:
            line += f'（{source}）'
        pd_lines.append(line)
    new_section_body = '\n'.join(pd_lines) + '\n'
else:
    new_section_body = '（なし）\n'

# Read dashboard.md
with open(dashboard_path, encoding='utf-8', errors='replace') as f:
    content = f.read()

# Split on 要対応 heading (emoji/prefix/suffix tolerant)
heading_match = re.search(r'^(## [^\n]*要対応[^\n]*\n)', content, re.MULTILINE)
if not heading_match:
    print('WARN: 要対応セクションが見つかりません', file=sys.stderr)
    sys.exit(0)

before = content[:heading_match.start()]
heading = heading_match.group(1)
rest = content[heading_match.end():]

# Find the next ## heading in rest
next_heading = re.search(r'^## ', rest, re.MULTILINE)
if next_heading:
    after_section = rest[next_heading.start():]
else:
    after_section = ''

content = before + heading + new_section_body + after_section

if dry_run:
    print(f'DRY-RUN: 要対応セクション → {len(pending_items)}件')
    sys.exit(0)

atomic_write_text(dashboard_path, content)

print(f'UPDATED: 要対応セクション同期完了 ({len(pending_items)}件)')
STEP67_PY
    }
    # dry-runではPD同期不要（dashboard.md変更なし）
    if [[ "$DRY_RUN" != true ]]; then
        _step67_pd_sync || echo "WARN: Step 6.7 要対応セクション同期失敗（既存値を維持）" >&2
    fi

    # ─── Step 6.8: Postcondition — PD⇔要対応件数の整合性検証 ───
    _step68_postcondition() {
        [[ "$DRY_RUN" == true ]] && return 0
        local pd_file="$PROJECT_DIR/queue/pending_decisions.yaml"
        export _PC_PD_FILE="$pd_file"

        python3 << 'STEP68_PY'
import os, sys, re

dashboard_path = os.environ['DASHBOARD']
pd_file = os.environ.get('_PC_PD_FILE', '')

# pending件数
if not pd_file or not os.path.exists(pd_file):
    print('[dashboard] WARN: postcondition: pending_decisions.yaml不在、検証スキップ', file=sys.stderr)
    sys.exit(0)

try:
    import yaml
    with open(pd_file) as f:
        pd_data = yaml.safe_load(f)
    if pd_data and 'decisions' in pd_data:
        expected = len([d for d in pd_data['decisions']
                        if isinstance(d, dict) and d.get('status') == 'pending'])
    else:
        expected = 0
except Exception as e:
    print(f'[dashboard] WARN: postcondition: pending_decisions.yaml読み込み失敗: {e}', file=sys.stderr)
    sys.exit(0)

# 要対応セクション件数
if not os.path.exists(dashboard_path):
    print('[dashboard] WARN: postcondition: dashboard.md不在、検証スキップ', file=sys.stderr)
    sys.exit(0)

try:
    with open(dashboard_path, encoding='utf-8', errors='replace') as f:
        content = f.read()
    heading_match = re.search(r'^## [^\n]*要対応[^\n]*\n', content, re.MULTILINE)
    if not heading_match:
        print('[dashboard] WARN: postcondition: 要対応セクション未発見', file=sys.stderr)
        sys.exit(0)
    rest = content[heading_match.end():]
    next_heading = re.search(r'^## ', rest, re.MULTILINE)
    section_body = rest[:next_heading.start()] if next_heading else rest
    if '（なし）' in section_body:
        actual = 0
    else:
        actual = len(re.findall(r'^- \*\*', section_body, re.MULTILINE))
except Exception as e:
    print(f'[dashboard] WARN: postcondition: dashboard.md読み込み失敗: {e}', file=sys.stderr)
    sys.exit(0)

if expected != actual:
    print(f'[dashboard] WARN: PD⇔要対応不一致 (expected={expected} actual={actual})', file=sys.stderr)
else:
    print(f'[dashboard] OK: PD⇔要対応一致 ({expected}件)')
STEP68_PY
    }
    _step68_postcondition || true

    # ─── Step 7: Update header timestamps (skip in dry-run) ───
    # flock内で実行: 並行呼出し時のdashboard.md書込み競合を防止
    if [[ "$DRY_RUN" != true ]]; then
        NOW_DATE=$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')
        NOW_TIME=$(TZ=Asia/Tokyo date '+%H:%M')
        # 現行ヘッダー: "# 🏯 Dashboard [project] — YYYY-MM-DD HH:MM 更新"
        # Template v3.0 has an HTML comment before the H1, so update the first matching
        # dashboard heading wherever it appears. Also handle unreplaced placeholders.
        python3 - "$DASHBOARD" "$NOW_DATE" <<'HEADER_PY'
import re
import sys

path, now_date = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    lines = f.read().splitlines()

updated = False
for i, line in enumerate(lines):
    if not line.startswith('# 🏯 Dashboard '):
        continue
    m = re.match(r'^(# 🏯 Dashboard \[)([^]]+)(\] — )(.+?)( 更新)$', line)
    if not m:
        continue
    project = m.group(2)
    if project == '{PJ名}':
        project = 'infra'
    lines[i] = f"{m.group(1)}{project}{m.group(3)}{now_date}{m.group(5)}"
    updated = True
    break

if updated:
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
HEADER_PY
        # 旧テンプレート互換（残存環境向け）
        sed -i "s/忍者配備状況（[0-9]\{2\}:[0-9]\{2\}更新）/忍者配備状況（${NOW_TIME}更新）/" "$DASHBOARD"
    fi

) 200>"$LOCK_FILE"

# ─── validate_dashboard: テンプレート駆動の整合性検証（WARN出力のみ） ───
validate_dashboard() {
    local dashboard="$1"
    local settings_file="$2"
    local template="$PROJECT_DIR/config/dashboard_template.md"

    if [[ ! -f "$template" ]]; then
        echo "[WARN] Template not found: $template" >&2
        return
    fi

    # (a) テンプレートから必須セクションパターンを動的生成
    #     {xxx}プレースホルダーを含む行は安定プレフィックスのみ使用
    local -a check_patterns=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^##\  ]]; then
            if [[ "$line" == *"{"* ]]; then
                # Has placeholder: cut at first （ before the placeholder
                local cut="${line%%（*}"
                [[ "$cut" == "$line" ]] && cut="${line%%\{*}"
                cut="${cut%% }"
                check_patterns+=("$cut")
            else
                check_patterns+=("$line")
            fi
        elif [[ "$line" =~ ^\>\  ]]; then
            if [[ "$line" == *"{"* ]]; then
                local cut="${line%%\{*}"
                check_patterns+=("${cut%% }")
            else
                check_patterns+=("$line")
            fi
        fi
    done < "$template"

    # (a)+(b) 単一awkパス: N回grep+N回awk → 1回awk（WSL2プロセス起動コスト削減 L511）
    if [[ ${#check_patterns[@]} -gt 0 ]]; then
        local _pat_tmp
        _pat_tmp=$(mktemp)
        printf '%s\n' "${check_patterns[@]}" > "$_pat_tmp"
        local _line_nums
        _line_nums=$(awk '
            NR==FNR { patterns[FNR]=$0; n=FNR; next }
            { for(i=1;i<=n;i++) if(!found[i] && index($0, patterns[i])) found[i]=NR }
            END { for(i=1;i<=n;i++) print (found[i]+0) }
        ' "$_pat_tmp" "$dashboard")
        rm -f "$_pat_tmp"

        local -a _lnums
        readarray -t _lnums <<< "$_line_nums"

        # (a) 存在チェック
        local _i=0
        for pattern in "${check_patterns[@]}"; do
            if [[ "${_lnums[$_i]:-0}" -eq 0 ]]; then
                echo "[WARN] Missing section: $pattern" >&2
            fi
            (( _i++ )) || true
        done

        # (b) 順序チェック
        local prev_line=0
        _i=0
        for pattern in "${check_patterns[@]}"; do
            local line_num="${_lnums[$_i]:-0}"
            (( _i++ )) || true
            if [[ "$line_num" -gt 0 ]]; then
                if [[ "$line_num" -le "$prev_line" ]]; then
                    echo "[WARN] Section order violation: '$pattern' at line $line_num (expected after line $prev_line)" >&2
                fi
                prev_line=$line_num
            fi
        done
    fi

    # (c) モデル欄整合性チェック（settings.yaml vs dashboard忍者テーブル）
    export SETTINGS_FILE="$settings_file"
    python3 << 'VALIDATE_MODEL_PYEOF' || true
import yaml, sys, os, re

settings_path = os.environ.get('SETTINGS_FILE', '')
dashboard_path = os.environ.get('DASHBOARD', '')
project_dir = os.path.dirname(os.path.dirname(settings_path)) if settings_path else ''
if project_dir:
    sys.path.insert(0, os.path.join(project_dir, 'scripts', 'lib'))
from model_family import FAMILY_CODEX, FAMILY_OPUS, model_display_group

if not settings_path or not dashboard_path or not os.path.exists(settings_path):
    sys.exit(0)

try:
    with open(settings_path) as f:
        settings = yaml.safe_load(f)
    with open(dashboard_path, encoding='utf-8', errors='replace') as f:
        dashboard_text = f.read()
except Exception:
    sys.exit(0)

agents = settings.get('cli', {}).get('agents', {})
expected = {}
for name, conf in agents.items():
    if not isinstance(conf, dict):
        continue
    label = conf.get('type') if conf.get('type') == FAMILY_CODEX else conf.get('model_name', FAMILY_OPUS)
    expected[name] = model_display_group(label)

table_pattern = re.compile(r'^\|\s*(\w+)\s*\|\s*\d+\s*\|\s*(\w+)\s*\|')
for line in dashboard_text.split('\n'):
    m = table_pattern.match(line)
    if m:
        ninja_name = m.group(1)
        actual_model = m.group(2)
        if ninja_name in expected and expected[ninja_name] != actual_model:
            print(f"[WARN] Model mismatch: {ninja_name} — dashboard: {actual_model}, settings.yaml: {expected[ninja_name]}", file=sys.stderr)
VALIDATE_MODEL_PYEOF

    # (d) 日付チェック
    # Template v3.0では1行目はテンプレートコメント。実ヘッダは「# 🏯 Dashboard」行
    local today
    today=$(date +%Y-%m-%d)
    if ! grep -m1 '^# 🏯 Dashboard' "$dashboard" | grep -qF "$today"; then
        echo "[WARN] Dashboard header date does not match today ($today)" >&2
    fi
}

# ─── Run validation ───
SETTINGS_FILE="$PROJECT_DIR/config/settings.yaml"
if [[ "$DRY_RUN" != true ]]; then
    validate_dashboard "$DASHBOARD" "$SETTINGS_FILE"
fi
