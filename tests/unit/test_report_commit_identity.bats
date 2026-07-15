#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  REPORT="$BATS_TEST_TMPDIR/report.yaml"
  base_report
}

base_report() {
  cat > "$REPORT" <<'YAML'
worker_id: hayate
parent_cmd: cmd_test
task_type: normal
status: pending
files_modified:
  - {path: queue/reports/hayate_report_cmd_test.yaml, change: runtime report}
  - {path: logs/loop_ledger.yaml, change: runtime ledger}
binary_checks:
  commit:
    - {check: 運用データのみのためcommit不要, result: yes}
YAML
}

@test "report_field_set accepts explicit no-commit for queue and logs only" {
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -eq 0 ]
  grep -q '^commit_hash: no-code-change$' "$REPORT"
}

@test "all three consumers accept ignored projects knowledge with explicit no-commit" {
  cat > "$REPORT" <<'YAML'
worker_id: hanzo
parent_cmd: cmd_test
task_type: normal
status: pending
files_modified:
  - {path: projects/infra.yaml, change: core knowledge}
binary_checks:
  commit:
    - {check: gitignore管理データのためcommit不要, result: yes}
YAML

  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -eq 0 ]

  run python3 "$ROOT/scripts/gates/gate_report_format_main.py" "$REPORT"
  [[ "$output" != *"commit_hash: 'no-code-change'"* ]]

  source "$ROOT/scripts/lib/review_approval.sh"
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" == *":no-code-change" ]]
}

@test "no-code allowance stays fail-closed for five forbidden categories" {
  local outside="$BATS_TEST_TMPDIR/../outside.yaml"
  local cases=(
    "projects/infra/lessons.yaml"
    "scripts/report_field_set.sh"
    "config/settings.yaml"
    "docs/research/example.md"
    "$outside"
  )
  local path
  for path in "${cases[@]}"; do
    base_report
    printf -- '- {path: "%s", change: must stay committed}\n' "$path" \
      | bash "$ROOT/scripts/report_field_set.sh" "$REPORT" files_modified -
    run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
    [ "$status" -ne 0 ]
  done
}

@test "projects allowance follows isolated git ignore state, not path prefix" {
  local repo="$BATS_TEST_TMPDIR/isolated-repo"
  mkdir -p "$repo/projects"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  printf 'projects/ignored.yaml\n' > "$repo/.gitignore"
  printf 'tracked\n' > "$repo/projects/tracked.yaml"
  git -C "$repo" add .gitignore projects/tracked.yaml
  git -C "$repo" commit -qm fixture

  run python3 - "$ROOT" "$repo" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "lib"))
from report_commit_identity import permits_no_code_identity

root = pathlib.Path(sys.argv[2])
def report(path):
    return {
        "files_modified": [{"path": path, "change": "knowledge"}],
        "binary_checks": {"commit": [{"check": "commit不要", "result": "yes"}]},
    }

ignored = permits_no_code_identity(report("projects/ignored.yaml"), root)
tracked = permits_no_code_identity(report("projects/tracked.yaml"), root)
print(f"ignored={ignored} tracked={tracked}")
raise SystemExit(0 if ignored and not tracked else 1)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ignored=True tracked=False" ]
}

@test "no-code allowance blocks empty files and negative commit evidence" {
  sed -i '/^files_modified:/,/^binary_checks:/c\files_modified: []\nbinary_checks:' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]

  base_report
  sed -i 's/result: yes/result: no/' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "report_field_set blocks no-code identity when source is mixed" {
  sed -i 's#logs/loop_ledger.yaml#scripts/report_field_set.sh#' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "report_field_set blocks short hash" {
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash ae15fc385
  [ "$status" -ne 0 ]
}

@test "report_field_set blocks no-code identity without affirmative evidence" {
  sed -i 's/result: yes/result: no/' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "format validator accepts the same operational no-code contract" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  run python3 "$ROOT/scripts/gates/gate_report_format_main.py" "$REPORT"
  [[ "$output" != *"commit_hash: 'no-code-change'"* ]]
}

@test "review fingerprint accepts operational no-code without unrelated HEAD" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" == *":no-code-change" ]]
}
