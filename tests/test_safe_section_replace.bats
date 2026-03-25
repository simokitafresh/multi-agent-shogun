#!/usr/bin/env bats
# test_safe_section_replace.bats — deploy_task.sh _safe_section_replace テスト
# cmd_1407 AC2/AC3: yaml.dump安全化（対象セクション限定書込み）の検証

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/safe_section_test.XXXXXX")"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# Helper: run _safe_section_replace on a YAML file
_run_safe_replace() {
    local input_file="$1"
    local section_name="$2"
    local value_json="$3"

    python3 - "$input_file" "$section_name" "$value_json" <<'PYEOF'
import yaml, re, sys, json

task_file = sys.argv[1]
section_name = sys.argv[2]
new_value = json.loads(sys.argv[3])

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

def _safe_section_replace(text, section_name, new_value):
    """Replace a 2-space-indented section under task: without full yaml.dump"""
    frag = yaml.safe_dump(
        {section_name: new_value},
        default_flow_style=False, allow_unicode=True, sort_keys=False,
    ).rstrip('\n')
    indented = '\n'.join('  ' + line for line in frag.split('\n'))
    pat = re.compile(
        r'^  ' + re.escape(section_name) + r':.*?(?=\n  [a-zA-Z_]|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    m = pat.search(text)
    if m:
        text = text[:m.start()] + indented + text[m.end():]
    else:
        task_idx = text.index('task:')
        rest = text[task_idx + 5:]
        top_m = re.search(r'^\S', rest, re.MULTILINE)
        if top_m:
            pos = task_idx + 5 + top_m.start()
            text = text[:pos] + indented + '\n' + text[pos:]
        else:
            text = text.rstrip('\n') + '\n' + indented + '\n'
    return text

raw = _safe_section_replace(raw, section_name, new_value)

with open(task_file, 'w', encoding='utf-8') as f:
    f.write(raw)
PYEOF
}

# --- Replace existing section ---

@test "T-101: replace existing related_lessons section" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: test
  related_lessons:
  - id: L001
    summary: old lesson
  report_filename: test.yaml
  status: assigned
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "related_lessons" \
        '[{"id": "L074", "summary": "new lesson"}]'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
assert task['command'] == 'test', f'command lost: {task}'
assert task['report_filename'] == 'test.yaml', f'report_filename lost: {task}'
assert task['status'] == 'assigned', f'status lost: {task}'
assert len(task['related_lessons']) == 1
assert task['related_lessons'][0]['id'] == 'L074'
"
}

# --- Insert new section ---

@test "T-102: insert new ninja_weak_points section" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: test
  related_lessons: []
  status: assigned
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "ninja_weak_points" \
        '{"source": "test", "total_workarounds": 5, "warning": "test warning"}'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
assert task['command'] == 'test', f'command lost: {task}'
assert task['ninja_weak_points']['source'] == 'test'
assert task['ninja_weak_points']['total_workarounds'] == 5
"
}

# --- Multiline strings ---

@test "T-103: multiline description replacement preserves other fields" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: test
  description: |
    Original multiline
    description text
  status: assigned
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "description" \
        '"New prefix\nOriginal multiline\ndescription text"'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
assert task['command'] == 'test', f'command lost: {task}'
assert task['status'] == 'assigned', f'status lost: {task}'
assert 'New prefix' in task['description']
assert 'Original multiline' in task['description']
"
}

# --- Multiple replacements ---

@test "T-104: YAML remains parseable after multiple replacements" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: test
  description: original desc
  related_lessons: []
  report_filename: test.yaml
  status: assigned
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "related_lessons" \
        '[{"id": "L001", "summary": "lesson 1"}, {"id": "L002", "summary": "lesson 2", "detail": "some detail"}]'

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "ninja_weak_points" \
        '{"source": "karo", "total_workarounds": 3, "breakdown": "format(2), commit(1)"}'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
assert task['command'] == 'test', f'command lost: {task}'
assert task['report_filename'] == 'test.yaml', f'report_filename lost: {task}'
assert len(task['related_lessons']) == 2
assert task['ninja_weak_points']['total_workarounds'] == 3
assert task['status'] == 'assigned', f'status lost: {task}'
"
}

# --- Special characters ---

@test "T-105: special characters in values don't break YAML" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: test
  status: assigned
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "ninja_weak_points" \
        '{"warning": "\u26a0 report_field_set.sh\u5fc5\u305a\u4f7f\u7528\u3002dict(0:{},1:{})\u7981\u6b62\u2192list\u5f62\u5f0f", "source": "karo"}'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
assert task['command'] == 'test'
assert task['status'] == 'assigned'
assert '\u26a0' in task['ninja_weak_points']['warning']
assert 'dict(0:{},1:{})' in task['ninja_weak_points']['warning']
"
}

# --- No data loss ---

@test "T-106: non-target fields are not modified" {
    cat > "$TEST_TMPDIR/task.yaml" <<'EOF'
task:
  command: complex command with "quotes" and 'singles'
  description: |
    Multi-line description
    with special chars: {}, [], #
    and unicode: 日本語テスト
  acceptance_criteria:
  - id: AC1
    description: first criterion
  - id: AC2
    description: second criterion
  related_lessons: []
  report_filename: test.yaml
  status: assigned
  parallel_ok:
  - AC1
  - AC2
EOF

    _run_safe_replace "$TEST_TMPDIR/task.yaml" "related_lessons" \
        '[{"id": "L074", "summary": "test lesson", "detail": "IF: condition THEN: action"}]'

    python3 -c "
import yaml
with open('$TEST_TMPDIR/task.yaml') as f:
    data = yaml.safe_load(f)
task = data['task']
# All non-target fields must survive
assert 'quotes' in task['command']
assert '日本語テスト' in task['description']
assert len(task['acceptance_criteria']) == 2
assert task['report_filename'] == 'test.yaml'
assert task['status'] == 'assigned'
assert task['parallel_ok'] == ['AC1', 'AC2']
# Target field updated
assert len(task['related_lessons']) == 1
assert task['related_lessons'][0]['id'] == 'L074'
"
}
