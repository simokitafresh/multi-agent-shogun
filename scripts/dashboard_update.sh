#!/usr/bin/env bash
# ============================================================
# dashboard_update.sh
# report YAMLからdashboard.mdの「最新更新」セクションを自動更新
# 家老の手動更新作業を排除する
#
# Usage: bash scripts/dashboard_update.sh <cmd_id> [--dry-run]
#   cmd_id (必須): cmd_XXX 形式
#   --dry-run: 差分のみ表示。dashboard.mdは変更しない
#
# Exit:
#   0: 成功（dashboard.md更新完了）
#   1: 失敗（解析エラー等。stderrにWARN出力）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CMD_ID="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Validation ───
if [[ -z "$CMD_ID" || "$CMD_ID" != cmd_* ]]; then
    echo "Usage: dashboard_update.sh <cmd_id> [--dry-run]" >&2
    echo "  cmd_id: cmd_XXX形式（必須）" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

DASHBOARD="$PROJECT_DIR/dashboard.md"

# 二重化防止: queue/dashboard.md誤作成検出
if [[ -f "$PROJECT_DIR/queue/dashboard.md" ]]; then
    echo "WARN: queue/dashboard.md が存在します。正しいパスは $DASHBOARD です。" >&2
    echo "WARN: queue/dashboard.mdを削除してください（rm queue/dashboard.md）" >&2
fi

REPORTS_DIR="$PROJECT_DIR/queue/reports"
STK_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

# ─── Export for Python ───
TEMPLATE="$PROJECT_DIR/config/dashboard_template.md"
export DASHBOARD REPORTS_DIR STK_FILE CMD_ID DRY_RUN TEMPLATE

# ─── Main processing (flock for concurrency safety) ───
LOCK_FILE="${DASHBOARD}.lock"
(
    flock -w 10 200 || { echo "ERROR: flock取得失敗" >&2; exit 1; }

    python3 << 'PYEOF'
import yaml, glob, os, sys, re

DASHBOARD = os.environ['DASHBOARD']
REPORTS_DIR = os.environ['REPORTS_DIR']
STK_FILE = os.environ['STK_FILE']
CMD_ID = os.environ['CMD_ID']
DRY_RUN = os.environ['DRY_RUN'] == 'true'

NAME_MAP = {
    'sasuke': '佐助', 'kirimaru': '霧丸', 'hayate': '疾風',
    'kagemaru': '影丸', 'hanzo': '半蔵', 'saizo': '才蔵',
    'kotaro': '小太郎', 'tobisaru': '飛猿', 'karo': '家老',
}


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


def summarize_ac(ac_val):
    """AC情報を短縮文字列に変換。"""
    if isinstance(ac_val, dict):
        pass_n = sum(1 for v in ac_val.values()
                     if isinstance(v, str) and 'PASS' in v.upper())
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
                     if isinstance(v, str) and 'PASS' in str(v).upper())
        total = len(ac_val)
        if total > 0:
            return f'AC:{pass_n}/{total} PASS'
    return ''


# ─── Step 1: Find matching report YAMLs ───
matches = []
for fpath in sorted(glob.glob(os.path.join(REPORTS_DIR, '*.yaml'))):
    try:
        with open(fpath) as f:
            raw = yaml.safe_load(f)
        if not raw:
            continue
        pcmd = str(get_first(raw, 'parent_cmd', 'report.parent_cmd'))
        if pcmd != CMD_ID:
            continue
        status = str(get_first(raw, 'status', 'report.status', default=''))
        # Skip placeholder reports (empty status)
        if not status.strip() or status.strip() == 'None':
            continue
        ts = str(get_first(raw, 'timestamp', 'report.timestamp', default=''))
        matches.append({'ts': ts, 'path': fpath, 'data': raw})
    except Exception:
        continue

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
title = ''
try:
    with open(STK_FILE) as f:
        stk = yaml.safe_load(f)
    if stk and 'commands' in stk:
        for cmd in stk['commands']:
            if cmd.get('id') == CMD_ID:
                title = cmd.get('title', cmd.get('purpose', ''))
                break
except Exception:
    pass

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

with open(DASHBOARD) as f:
    lines = f.read().split('\n')

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
    print(f"ERROR: '{insert_target}' section not found in dashboard.md", file=sys.stderr)
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

with open(DASHBOARD, 'w') as f:
    f.write(content)

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
    if [[ "$DRY_RUN" != true ]]; then
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
with open(dashboard_path) as f:
    content = f.read()

# Split on 要対応 heading
parts = re.split(r'(## 要対応[^\n]*\n)', content, maxsplit=1)
if len(parts) < 3:
    print('WARN: 要対応セクションが見つかりません', file=sys.stderr)
    sys.exit(0)

before = parts[0]
heading = parts[1]
rest = parts[2]

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

with open(dashboard_path, 'w') as f:
    f.write(content)

print(f'UPDATED: 要対応セクション同期完了 ({len(pending_items)}件)')
STEP67_PY
    }
    _step67_pd_sync || echo "WARN: Step 6.7 要対応セクション同期失敗（既存値を維持）" >&2

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
    with open(dashboard_path) as f:
        content = f.read()
    parts = re.split(r'## 要対応[^\n]*\n', content, maxsplit=1)
    if len(parts) < 2:
        print('[dashboard] WARN: postcondition: 要対応セクション未発見', file=sys.stderr)
        sys.exit(0)
    rest = parts[1]
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

) 200>"$LOCK_FILE"

# ─── Step 7: Update header timestamps (skip in dry-run) ───
if [[ "$DRY_RUN" != true ]]; then
    NOW_DATE=$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')
    NOW_TIME=$(TZ=Asia/Tokyo date '+%H:%M')
    sed -i "s/— [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\} 更新/— ${NOW_DATE} 更新/" "$DASHBOARD"
    sed -i "s/忍者配備状況（[0-9]\{2\}:[0-9]\{2\}更新）/忍者配備状況（${NOW_TIME}更新）/" "$DASHBOARD"
fi

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

    for pattern in "${check_patterns[@]}"; do
        if ! grep -qF "$pattern" "$dashboard"; then
            echo "[WARN] Missing section: $pattern" >&2
        fi
    done

    # (b) セクション順序チェック
    local prev_line=0
    for pattern in "${check_patterns[@]}"; do
        local line_num
        line_num=$(awk -v pat="$pattern" 'index($0, pat) {print NR; exit}' "$dashboard")
        if [[ -n "$line_num" && "$line_num" -gt 0 ]]; then
            if [[ "$line_num" -le "$prev_line" ]]; then
                echo "[WARN] Section order violation: '$pattern' at line $line_num (expected after line $prev_line)" >&2
            fi
            prev_line=$line_num
        fi
    done

    # (c) モデル欄整合性チェック（settings.yaml vs dashboard忍者テーブル）
    export SETTINGS_FILE="$settings_file"
    python3 << 'VALIDATE_MODEL_PYEOF' || true
import yaml, sys, os, re

settings_path = os.environ.get('SETTINGS_FILE', '')
dashboard_path = os.environ.get('DASHBOARD', '')

if not settings_path or not dashboard_path or not os.path.exists(settings_path):
    sys.exit(0)

try:
    with open(settings_path) as f:
        settings = yaml.safe_load(f)
    with open(dashboard_path) as f:
        dashboard_text = f.read()
except Exception:
    sys.exit(0)

agents = settings.get('cli', {}).get('agents', {})
expected = {}
for name, conf in agents.items():
    if not isinstance(conf, dict):
        continue
    if conf.get('type') == 'codex':
        expected[name] = 'Codex'
    elif conf.get('model_name', ''):
        mn = conf['model_name']
        if 'sonnet' in mn.lower():
            expected[name] = 'Sonnet'
        elif 'haiku' in mn.lower():
            expected[name] = 'Haiku'
        else:
            expected[name] = 'Opus'
    else:
        expected[name] = 'Opus'

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
    local today
    today=$(date +%Y-%m-%d)
    if ! head -1 "$dashboard" | grep -qF "$today"; then
        echo "[WARN] Dashboard header date does not match today ($today)" >&2
    fi
}

# ─── Run validation ───
SETTINGS_FILE="$PROJECT_DIR/config/settings.yaml"
validate_dashboard "$DASHBOARD" "$SETTINGS_FILE"
