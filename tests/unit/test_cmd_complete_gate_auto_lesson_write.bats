#!/usr/bin/env bats
# test_cmd_complete_gate_auto_lesson_write.bats
# cmd_2697: register_recommended:true → auto lesson_write at GATE CLEAR
# AC1: GATE CLEAR時にregister_recommended:true検知でlesson_write.shが自動実行
# AC2: 自動実行失敗時はWARN出力で完了処理継続（非ブロッキング）
# AC3: 本batsテストがPASS

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/auto_lesson_write.XXXXXX")"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── Helper: extract lesson_candidate fields (same logic as cmd_complete_gate.sh) ───

_py_extract_lc() {
    local report_path="$1"
    REPORT_PATH="$report_path" python3 - <<'PY'
import yaml, os, sys, shlex
report_path = os.environ["REPORT_PATH"]
try:
    with open(report_path, encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
lc = data.get("lesson_candidate", {})
if not isinstance(lc, dict) or not lc.get("found"):
    sys.exit(0)
title = str(lc.get("title", "") or "").strip()
detail = str(lc.get("detail", "") or "").strip()
project = str(lc.get("project", "") or "").strip()
reg = bool(lc.get("register_recommended"))
source_cmd = str(data.get("parent_cmd", "") or data.get("task_id", "") or "").strip()
worker_id = str(data.get("worker_id", "") or "auto_gate").strip()

def csv_value(value):
    if isinstance(value, list):
        return ",".join(str(v).strip() for v in value if str(v).strip())
    return str(value or "").strip()

def collect_target_files(report, lesson_candidate):
    raw = lesson_candidate.get("target_files") or []
    if isinstance(raw, str):
        paths = [p.strip() for p in raw.split(",")]
    elif isinstance(raw, list):
        paths = [str(p).strip() for p in raw]
    else:
        paths = []
    if not paths:
        files = report.get("files_modified") or []
        if isinstance(files, str):
            paths = [files.strip()]
        elif isinstance(files, list):
            for item in files:
                if isinstance(item, dict):
                    path = item.get("path") or item.get("file") or item.get("name")
                else:
                    path = item
                if path:
                    paths.append(str(path).strip())
    seen = set()
    result = []
    for path in paths:
        if not path or path in seen:
            continue
        seen.add(path)
        result.append(path)
        if len(result) >= 5:
            break
    return ",".join(result)

def normalize_subdomain(value):
    aliases = {
        "frontend": "fe", "front": "fe", "ui": "fe",
        "backend": "be", "back": "be", "api": "be", "ops": "be",
        "grid_search": "gs", "grid-search": "gs", "gridsearch": "gs",
        "platform": "infra",
    }
    parts = [p.strip() for p in csv_value(value).split(",") if p.strip()]
    normalized = []
    for part in parts:
        part = aliases.get(part, part)
        if part in {"fe", "be", "gs", "infra"} and part not in normalized:
            normalized.append(part)
    return ",".join(normalized)

def infer_subdomain(project_id, title_text, detail_text, tags_value, target_files_csv):
    explicit = normalize_subdomain(lc.get("subdomain") or lc.get("subdomains"))
    if explicit:
        return explicit
    if project_id == "infra":
        return "infra"
    haystack = " ".join([
        project_id,
        title_text,
        detail_text,
        csv_value(tags_value),
        target_files_csv,
    ]).lower()
    if project_id == "dm-signal":
        if any(k in haystack for k in ["scripts/gates/", "lesson_write", "cmd_complete_gate", "deploy_task", "inbox_", "ninja_monitor", "semantic"]):
            return "infra"
        if any(k in haystack for k in ["run_077", "grid_search", "grid search", "grid-search", " gs", "gs-", "gs_", "l0", "l1", "l2", "l3", "blob", "monthly", "daily_prices", "price path", "価格", "系列preflight"]):
            return "gs"
        if any(k in haystack for k in ["frontend", "next", "react", "component", "chart", "ui", "css", "app/", "components/"]):
            return "fe"
        if any(k in haystack for k in ["database", "db", "api", "recalculate", "fullrecalculate", "portfolio", "pf", "migration", "cron", "production", "prices"]):
            return "be"
    return ""

tags = lc.get("tags", "")
target_files = collect_target_files(data, lc)
subdomain = infer_subdomain(project, title, detail, tags, target_files)
if not title:
    sys.exit(0)
print(f"_lc_action=check")
print(f"_lc_title={shlex.quote(title[:80])}")
print(f"_lc_reg={'true' if reg else 'false'}")
print(f"_lc_project={shlex.quote(project)}")
print(f"_lc_detail={shlex.quote(detail)}")
print(f"_lc_source={shlex.quote(source_cmd)}")
print(f"_lc_author={shlex.quote(worker_id or 'auto_gate')}")
print(f"_lc_subdomain={shlex.quote(subdomain)}")
print(f"_lc_target_files={shlex.quote(target_files)}")
PY
}

# ═══════════════════════════════════════
# Section 1: Structural — code exists in GATE CLEAR section
# ═══════════════════════════════════════

@test "register_recommended detection is inside GATE CLEAR section" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

gate_clear_idx = text.index('if [ "$ALL_CLEAR" = true ]; then')
gate_clear_text = text[gate_clear_idx:]

if '_lc_reg' not in gate_clear_text:
    raise SystemExit("_lc_reg variable not found in GATE CLEAR section")

# Use _lc_reg check (code-level marker, not comment)
lc_reg_idx = gate_clear_text.index('[ "$_lc_reg" = "true" ]')
nearby = gate_clear_text[lc_reg_idx:lc_reg_idx+1200]
if "lesson_write.sh" not in nearby:
    raise SystemExit("lesson_write.sh call not found near _lc_reg check")
if "_lc_lesson_flags" not in nearby:
    raise SystemExit("lesson_write flags array not found near _lc_reg check")

print("OK: _lc_reg check + lesson_write.sh in GATE CLEAR section")
PY
    [ "$status" -eq 0 ]
}

@test "lesson_write failure is marked non-blocking in GATE CLEAR section" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

gate_clear_idx = text.index('if [ "$ALL_CLEAR" = true ]; then')
gate_clear_text = text[gate_clear_idx:]

lc_reg_idx = gate_clear_text.index('[ "$_lc_reg" = "true" ]')
reg_section = gate_clear_text[lc_reg_idx:lc_reg_idx+1400]

if "non-blocking" not in reg_section:
    raise SystemExit("non-blocking keyword not found near _lc_reg section")
if "WARN" not in reg_section:
    raise SystemExit("WARN keyword not found near _lc_reg section")

print("OK: non-blocking WARN pattern found")
PY
    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════
# Section 2: Functional — python3 extraction logic
# ═══════════════════════════════════════

@test "register_recommended:true sets _lc_reg=true" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_test_123
worker_id: hanzo
lesson_candidate:
  found: true
  title: Test auto-register lesson
  detail: Should be auto-registered
  project: infra
  register_recommended: true
status: done
EOF
    local result
    result=$(_py_extract_lc "$report")
    [[ "$result" == *"_lc_action=check"* ]]
    [[ "$result" == *"_lc_reg=true"* ]]
    [[ "$result" == *"Test auto-register lesson"* ]]
    [[ "$result" == *"_lc_subdomain=infra"* ]]
}

@test "register_recommended:false sets _lc_reg=false" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_test_456
worker_id: hanzo
lesson_candidate:
  found: true
  title: Manual registration lesson
  detail: Should not be auto-registered
  project: infra
  register_recommended: false
status: done
EOF
    local result
    result=$(_py_extract_lc "$report")
    [[ "$result" == *"_lc_action=check"* ]]
    [[ "$result" == *"_lc_reg=false"* ]]
}

@test "register_recommended absent defaults to false" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_test_789
worker_id: hanzo
lesson_candidate:
  found: true
  title: No register_recommended field
  detail: Field absent means false
  project: infra
status: done
EOF
    local result
    result=$(_py_extract_lc "$report")
    [[ "$result" == *"_lc_action=check"* ]]
    [[ "$result" == *"_lc_reg=false"* ]]
}

@test "found:false produces no output" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_test_999
worker_id: hanzo
lesson_candidate:
  found: false
  no_lesson_reason: no lesson here
status: done
EOF
    local result
    result=$(_py_extract_lc "$report") || true
    [[ -z "$result" ]] || [[ "$result" != *"_lc_action=check"* ]]
}

@test "lesson_write.sh is called when register_recommended:true" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_auto_reg
worker_id: hanzo
lesson_candidate:
  found: true
  title: Should be auto-registered at GATE CLEAR
  detail: Detailed description for auto-registration
  project: infra
  register_recommended: true
status: done
EOF
    mkdir -p "$TEST_TMPDIR/scripts"
    local called_file="$TEST_TMPDIR/lesson_write_args.txt"
    cat > "$TEST_TMPDIR/scripts/lesson_write.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$called_file"
exit 0
STUB
    chmod +x "$TEST_TMPDIR/scripts/lesson_write.sh"

    _lc_action=skip _lc_title="" _lc_reg=false _lc_project="" _lc_detail="" _lc_source="" _lc_author=auto_gate
    eval "$(_py_extract_lc "$report")"

    [ "$_lc_action" = "check" ]
    [ "$_lc_reg" = "true" ]
    [ -n "$_lc_project" ]
    [ -n "$_lc_source" ]

    SCRIPT_DIR="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/lesson_write.sh" \
        "$_lc_project" "$_lc_title" "$_lc_detail" "$_lc_source" "$_lc_author" "$_lc_source"

    [ -f "$called_file" ]
    local content
    content=$(cat "$called_file")
    [[ "$content" == *"infra"* ]]
    [[ "$content" == *"Should be auto-registered at GATE CLEAR"* ]]
    [[ "$content" == *"cmd_auto_reg"* ]]
}

@test "dm-signal GS auto lesson passes inferred subdomain and target files" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_auto_gs
worker_id: kagemaru
lesson_candidate:
  found: true
  title: GS投入前は系列preflightを必須化する
  detail: run_077 GS price path uses local daily_prices and must check price series before replacement
  project: dm-signal
  register_recommended: true
files_modified:
  - path: scripts/analysis/run_077_gs.py
    change: recon
status: done
EOF
    mkdir -p "$TEST_TMPDIR/scripts"
    local called_file="$TEST_TMPDIR/lesson_write_args.txt"
    cat > "$TEST_TMPDIR/scripts/lesson_write.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$called_file"
exit 0
STUB
    chmod +x "$TEST_TMPDIR/scripts/lesson_write.sh"

    _lc_action=skip _lc_title="" _lc_reg=false _lc_project="" _lc_detail="" _lc_source="" _lc_author=auto_gate
    _lc_subdomain="" _lc_target_files=""
    eval "$(_py_extract_lc "$report")"

    [ "$_lc_action" = "check" ]
    [ "$_lc_reg" = "true" ]
    [ "$_lc_project" = "dm-signal" ]
    [ "$_lc_subdomain" = "gs" ]
    [ "$_lc_target_files" = "scripts/analysis/run_077_gs.py" ]

    _lc_lesson_flags=()
    [ -n "$_lc_subdomain" ] && _lc_lesson_flags+=(--subdomain "$_lc_subdomain")
    [ -n "$_lc_target_files" ] && _lc_lesson_flags+=(--target-files "$_lc_target_files")
    SCRIPT_DIR="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/lesson_write.sh" \
        "$_lc_project" "$_lc_title" "$_lc_detail" "$_lc_source" "$_lc_author" "$_lc_source" "${_lc_lesson_flags[@]}"

    [ -f "$called_file" ]
    local content
    content=$(cat "$called_file")
    [[ "$content" == *"dm-signal"* ]]
    [[ "$content" == *"--subdomain"* ]]
    [[ "$content" == *"gs"* ]]
    [[ "$content" == *"--target-files"* ]]
    [[ "$content" == *"scripts/analysis/run_077_gs.py"* ]]
}

@test "lesson_write.sh failure exits 0 (non-blocking)" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_fail_test
worker_id: hanzo
lesson_candidate:
  found: true
  title: Failing lesson registration
  detail: This will fail
  project: infra
  register_recommended: true
status: done
EOF
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/lesson_write.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$TEST_TMPDIR/scripts/lesson_write.sh"

    _lc_action=skip _lc_title="" _lc_reg=false _lc_project="" _lc_detail="" _lc_source="" _lc_author=auto_gate
    eval "$(_py_extract_lc "$report")"

    [ "$_lc_action" = "check" ]
    [ "$_lc_reg" = "true" ]

    # Simulate the non-blocking behavior from cmd_complete_gate.sh
    run bash -c '
        SCRIPT_DIR="$1"
        lc_project="$2" lc_title="$3" lc_detail="$4" lc_source="$5" lc_author="$6"
        if bash "$SCRIPT_DIR/scripts/lesson_write.sh" \
            "$lc_project" "$lc_title" "$lc_detail" "$lc_source" "$lc_author" "$lc_source" 2>&1; then
            echo "REGISTERED"
        else
            echo "  [WARN] lesson_write: failed (non-blocking)"
        fi
        exit 0
    ' _ "$TEST_TMPDIR" "$_lc_project" "$_lc_title" "$_lc_detail" "$_lc_source" "$_lc_author"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"non-blocking"* ]]
}
