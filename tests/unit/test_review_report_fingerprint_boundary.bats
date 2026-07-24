#!/usr/bin/env bats
# test_necessity: review_report_fingerprintの同一性境界 — 非内容フィールドのみの変更は
# 承認を維持し、レビュー内容(binary_checks・ac_evidence_mapping等)の変更は承認を無効化する
# invariant: verdictやbinary_checks等の内容フィールドは除外リストに含まれない

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    # Minimal fake project root: scripts/lib is symlinked to real lib,
    # queue dirs are created for review_validate_report compatibility.
    export FAKE_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$FAKE_ROOT/queue/reports" \
             "$FAKE_ROOT/queue/gates" \
             "$FAKE_ROOT/queue/tasks"
    ln -s "$PROJECT_ROOT/scripts" "$FAKE_ROOT/scripts"
}

# Helper: compute review_report_fingerprint for a given report file.
# Uses FAKE_ROOT so that scripts/lib/report_commit_identity.py is importable.
_fingerprint() {
    local report="$1"
    PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_fingerprint "$2"
    ' _ "$FAKE_ROOT" "$report"
}

# Helper: create the base report fixture in FAKE_ROOT/queue/reports/.
_make_report() {
    local name="${1:-fixture}"
    local report="$FAKE_ROOT/queue/reports/${name}.yaml"
    cat > "$report" <<'YAML'
parent_cmd: cmd_fp_boundary_test
status: completed
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
cross_repo_commits:
  - repo: /mnt/c/Python_app/DM-signal
    commit_hash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    paths:
      - backend/app/main.py
binary_checks:
  commit:
    - check: "commitが完了したか"
      result: "yes"
ac_evidence_mapping:
  AC1: "all tests passed"
files_modified:
  - path: scripts/lib/review_approval.sh
YAML
    echo "$report"
}

# -----------------------------------------------------------------------
# AC1 fixture A: non-content field changes do NOT change the fingerprint
# -----------------------------------------------------------------------

@test "cross_repo_commits change does not invalidate fingerprint" {
    local report
    report="$(_make_report fp_nonc)"
    local fp1
    fp1="$(_fingerprint "$report")"
    [ -n "$fp1" ]

    # Modify cross_repo_commits (non-content metadata)
    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["cross_repo_commits"] = [
    {"repo": "/mnt/c/Python_app/DM-signal",
     "commit_hash": "cccccccccccccccccccccccccccccccccccccccc",
     "paths": ["backend/app/main.py"]}
]
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY
    local fp2
    fp2="$(_fingerprint "$report")"
    [ -n "$fp2" ]
    [ "$fp1" = "$fp2" ]
}

@test "commit_hash field change does not invalidate fingerprint" {
    local report
    report="$(_make_report fp_cmhash)"
    local fp1
    fp1="$(_fingerprint "$report")"
    [ -n "$fp1" ]

    # Modify top-level commit_hash (non-content metadata)
    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["commit_hash"] = "dddddddddddddddddddddddddddddddddddddddd"
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY
    local fp2
    fp2="$(_fingerprint "$report")"
    [ -n "$fp2" ]
    [ "$fp1" = "$fp2" ]
}

@test "status and timestamp change do not invalidate fingerprint" {
    local report
    report="$(_make_report fp_lifecycle)"
    local fp1
    fp1="$(_fingerprint "$report")"
    [ -n "$fp1" ]

    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["status"] = "archived"
d["completed_at"] = "2026-07-24T15:00:00Z"
d["updated_at"] = "2026-07-24T15:00:00Z"
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY
    local fp2
    fp2="$(_fingerprint "$report")"
    [ -n "$fp2" ]
    [ "$fp1" = "$fp2" ]
}

# -----------------------------------------------------------------------
# AC1 fixture B: content field changes DO change the fingerprint
# -----------------------------------------------------------------------

@test "binary_checks result change invalidates fingerprint" {
    local report
    report="$(_make_report fp_bc)"
    local fp1
    fp1="$(_fingerprint "$report")"
    [ -n "$fp1" ]

    # Change binary_checks result (content field — must NOT be excluded)
    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["binary_checks"]["commit"][0]["result"] = "no"
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY
    local fp2
    fp2="$(_fingerprint "$report")"
    [ -n "$fp2" ]
    [ "$fp1" != "$fp2" ]
}

@test "ac_evidence_mapping change invalidates fingerprint" {
    local report
    report="$(_make_report fp_ac)"
    local fp1
    fp1="$(_fingerprint "$report")"
    [ -n "$fp1" ]

    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["ac_evidence_mapping"]["AC1"] = "FAIL: tests not run"
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY
    local fp2
    fp2="$(_fingerprint "$report")"
    [ -n "$fp2" ]
    [ "$fp1" != "$fp2" ]
}

# -----------------------------------------------------------------------
# AC2: LGTM + ACCEPT stored approval is maintained after non-content change
# -----------------------------------------------------------------------

@test "stored LGTM+ACCEPT approval is maintained after commit_hash correction" {
    local report
    report="$(_make_report fp_e2e)"

    # Compute initial fingerprint
    local fp1
    fp1="$(PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_fingerprint "$2"
    ' _ "$FAKE_ROOT" "$report")"
    [ -n "$fp1" ]

    # Simulate stored approval (gunshi LGTM + karo ACCEPT) with fp1
    local key dir
    key="$(PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_key "queue/reports/fp_e2e.yaml"
    ' _ "$FAKE_ROOT")"
    dir="$FAKE_ROOT/queue/gates/cmd_fp_boundary_test/review_approvals/reports/$key"
    mkdir -p "$dir"
    printf 'fingerprint: %s\nresult: LGTM\n' "$fp1" > "$dir/gunshi.yaml"
    printf 'fingerprint: %s\nresult: ACCEPT\n' "$fp1" > "$dir/karo.yaml"

    # Simulate fixing commit_hash (non-content correction post-approval)
    python3 - "$report" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
d = yaml.safe_load(p.read_text()) or {}
d["commit_hash"] = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
d["cross_repo_commits"][0]["commit_hash"] = "ffffffffffffffffffffffffffffffffffffffff"
p.write_text(yaml.dump(d, allow_unicode=True, default_flow_style=False))
PY

    # Compute fingerprint after correction — must equal fp1
    local fp2
    fp2="$(PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_fingerprint "$2"
    ' _ "$FAKE_ROOT" "$report")"
    [ -n "$fp2" ]
    [ "$fp1" = "$fp2" ]

    # review_two_phase_ready must still pass (run via helper to avoid bats quoting issues)
    local check_script="$BATS_TEST_TMPDIR/check_two_phase.sh"
    cat > "$check_script" <<SCRIPT
#!/usr/bin/env bash
export PROJECT_ROOT="$FAKE_ROOT"
source "$FAKE_ROOT/scripts/lib/review_approval.sh"
review_two_phase_ready "cmd_fp_boundary_test" "$report"
SCRIPT
    run bash "$check_script"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
    [ "$status" -eq 0 ]
}
