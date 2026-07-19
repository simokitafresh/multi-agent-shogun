#!/usr/bin/env bats
# test_necessity: terminal reportのcommit identityは解決可能な40桁hashまたは厳格なno-code契約に限る

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
no_code_change_evidence:
  before_tree: 1111111111111111111111111111111111111111
  after_tree: 1111111111111111111111111111111111111111
  tree_unchanged: true
YAML
}

@test "report_field_set accepts explicit no-commit for queue and logs only" {
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -eq 0 ]
  grep -q '^commit_hash: no-code-change$' "$REPORT"
}

@test "commit contract required false is the no-code SSOT without free-text marker" {
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: allowed_no_code_task_type_and_no_code_scope\n' >> "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -eq 0 ]
}

@test "commit contract false remains fail-closed for mixed source" {
  sed -i 's#logs/loop_ledger.yaml#scripts/report_field_set.sh#' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: forged\n' >> "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "seventeen valid contract reports do not require unrelated HEAD" {
  local i
  for i in $(seq 1 17); do
    base_report
    sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
    printf '\ncommit_contract:\n  required: false\n  reason: fixture_%s\n' "$i" >> "$REPORT"
    run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
    [ "$status" -eq 0 ]
    run python3 "$ROOT/scripts/gates/gate_report_format_main.py" "$REPORT"
    [[ "$output" != *"commit_hash: 'no-code-change'"* ]]
  done
}

@test "batch derives legacy test_results from operational simulation SSOT" {
  cat >> "$REPORT" <<'YAML'
operational_simulation:
  command: bats fixture.bats
  expected: PASS
  actual: 1/1 PASS
  result: PASS
YAML
  printf 'result.details: fixture\nbinary_checks.commit[0].result: "yes"\n' | bash "$ROOT/scripts/report_field_set.sh" --batch "$REPORT"
  run python3 - "$REPORT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d['test_results'] == d['operational_simulation']
PY
  [ "$status" -eq 0 ]
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
no_code_change_evidence:
  before_tree: 2222222222222222222222222222222222222222
  after_tree: 2222222222222222222222222222222222222222
  tree_unchanged: true
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
        "no_code_change_evidence": {
            "before_tree": "3" * 40,
            "after_tree": "3" * 40,
            "tree_unchanged": True,
        },
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

@test "review fingerprint cache reuses unchanged content and invalidates on byte change" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"

  first=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 1 ]
  second=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [ "$second" = "$first" ]
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 1 ]

  printf '\nresult: {summary: changed}\n' >> "$REPORT"
  third=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [ "$third" != "$first" ]
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 2 ]
}

@test "review fingerprint cache keeps report path in the cache boundary" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  local alias_report="$BATS_TEST_TMPDIR/alias.yaml"
  cp "$REPORT" "$alias_report"
  source "$ROOT/scripts/lib/review_approval.sh"

  PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT" >/dev/null
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 1 ]
  PROJECT_ROOT="$ROOT" review_report_fingerprint "$alias_report" >/dev/null
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 2 ]
}
