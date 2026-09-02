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
lessons_useful: []
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

@test "review fingerprint uses the no-code SSOT and keeps invalid variants fail-closed" {
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: operational_tree_unchanged\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"

  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]]
  [ "$(PROJECT_ROOT="$ROOT" review_report_commit_identity "$REPORT")" = "no-code-change" ]

  base_report
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: missing_evidence\n' >> "$REPORT"
  sed -i '/^no_code_change_evidence:/,$d' "$REPORT"
  run env PROJECT_ROOT="$ROOT" bash -c 'source "$1"; review_report_fingerprint "$2"' _ \
    "$ROOT/scripts/lib/review_approval.sh" "$REPORT"
  [ "$status" -ne 0 ]

  base_report
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: source_mixed\n' >> "$REPORT"
  sed -i 's#logs/loop_ledger.yaml#scripts/report_field_set.sh#' "$REPORT"
  run env PROJECT_ROOT="$ROOT" bash -c 'source "$1"; review_report_fingerprint "$2"' _ \
    "$ROOT/scripts/lib/review_approval.sh" "$REPORT"
  [ "$status" -ne 0 ]

  base_report
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: tree_changed\n' >> "$REPORT"
  sed -i 's/after_tree: 1111111111111111111111111111111111111111/after_tree: 2222222222222222222222222222222222222222/' "$REPORT"
  run env PROJECT_ROOT="$ROOT" bash -c 'source "$1"; review_report_fingerprint "$2"' _ \
    "$ROOT/scripts/lib/review_approval.sh" "$REPORT"
  [ "$status" -ne 0 ]

  base_report
  sed -i 's/運用データのみのためcommit不要/運用データ処理を確認/' "$REPORT"
  printf '\ncommit_contract:\n  required: false\n  reason: valid_hash_wins\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' >> "$REPORT"
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]]
  [ "$(PROJECT_ROOT="$ROOT" review_report_commit_identity "$REPORT")" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
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
  - {path: projects/private-runtime.yaml, change: ignored project knowledge}
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
  # cmd_4156(3718e7245)で fingerprint は「正規化content hash単独」へ変更され、commit identity は
  # gate としてのみ使われ値には含まれなくなった。守る不変量は変わらず
  # 「no-code報告でも identity gate を通過し fingerprint が得られる(fail-closedにならない)」こと。
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]]
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
  # cmd_4156(3718e7245)で fingerprint は「正規化content hash単独」へ変更され、commit identity は
  # gate としてのみ使われ値には含まれなくなった。守る不変量は変わらず
  # 「no-code報告でも identity gate を通過し fingerprint が得られる(fail-closedにならない)」こと。
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]]
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

@test "no-code identity comes from the gate accessor, not from slicing the fingerprint" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"

  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  # 恒偽の再発防止: fingerprint は content hash 単独であり区切り文字を持たない。
  # ∴ 呼び出し側の "${fingerprint##*:}" は常に hash 全体を返し no-code 判定は恒偽になる。
  [[ "$fp" != *:* ]]
  [ "${fp##*:}" = "$fp" ]
  [ "${fp##*:}" != "no-code-change" ]
  # gate が決めた commit identity は専用アクセサからのみ得られる。
  [ "$(PROJECT_ROOT="$ROOT" review_report_commit_identity "$REPORT")" = "no-code-change" ]
}

@test "review fingerprint cache entry holds fingerprint and identity in one two-line file" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"

  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  # (realpath, content_hash)組ごとにちょうど1エントリ。sidecarを作らない。
  [ "$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f | wc -l)" -eq 1 ]
  cache_file=$(find "$REVIEW_FP_CACHE_DIR" -maxdepth 1 -type f)
  [ "$(wc -l < "$cache_file")" -eq 2 ]
  [ "$(sed -n '1p' "$cache_file")" = "$fp" ]
  [ "$(sed -n '2p' "$cache_file")" = "no-code-change" ]
  [ "$(PROJECT_ROOT="$ROOT" review_report_commit_identity "$REPORT")" = "no-code-change" ]
}

@test "cross-repo commit contract proves every path in its owning repository" {
  local repo_a="$BATS_TEST_TMPDIR/repo-a" repo_b="$BATS_TEST_TMPDIR/repo-b"
  for repo in "$repo_a" "$repo_b"; do
    git -C "$BATS_TEST_TMPDIR" init -q "${repo##*/}"
    git -C "$repo" config user.email fixture@example.invalid
    git -C "$repo" config user.name fixture
  done
  printf 'a\n' >"$repo_a/a.txt"
  printf 'stable\n' >"$repo_b/stable.txt"
  git -C "$repo_b" add stable.txt && git -C "$repo_b" commit -qm stable
  printf 'b\n' >"$repo_b/b.txt"
  git -C "$repo_a" add a.txt && git -C "$repo_a" commit -qm a
  git -C "$repo_b" add b.txt && git -C "$repo_b" commit -qm b
  sha_a="$(git -C "$repo_a" rev-parse HEAD)"
  sha_b="$(git -C "$repo_b" rev-parse HEAD)"

  run python3 - "$ROOT" "$repo_a" "$sha_a" "$repo_b" "$sha_b" <<'PY'
import copy, pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "lib"))
from cross_repo_commit_contract import validate_cross_repo_commit_ownership
report = {
    "commit_hash": sys.argv[3],
    "files_modified": [{"path": "a.txt"}],
    "cross_repo_commits": [
        {"repo": sys.argv[2], "commit_hash": sys.argv[3], "paths": ["a.txt"]},
        {"repo": sys.argv[4], "commit_hash": sys.argv[5], "paths": ["b.txt"]},
    ],
}
errors, _ = validate_cross_repo_commit_ownership(report)
assert errors == [], errors
# test_necessity: cross_repo ownership is limited to paths actually changed by
# the declared commit; mere existence in that commit's tree is not ownership.
case = copy.deepcopy(report)
case["cross_repo_commits"][1]["paths"] = ["stable.txt"]
errors, _ = validate_cross_repo_commit_ownership(case)
assert errors == ["cross_repo_commits[1] commit does not change path: stable.txt"], errors
case = copy.deepcopy(report)
case["files_modified"].append({"path": "undeclared.txt"})
errors, _ = validate_cross_repo_commit_ownership(case)
assert errors == ["files_modified path lacks cross-repo ownership: undeclared.txt"], errors
case = copy.deepcopy(report)
case["cross_repo_commits"][1]["paths"] = ["a.txt"]
errors, _ = validate_cross_repo_commit_ownership(case)
assert errors == ["cross_repo_commits[1] commit does not change path: a.txt"], errors
# Same path in two entries is allowed when both commits actually change it
case = copy.deepcopy(report)
case["cross_repo_commits"][1]["paths"] = ["b.txt", "b.txt"]
errors, _ = validate_cross_repo_commit_ownership(case)
assert errors == ["cross_repo path appears multiple times in cross_repo_commits[1]: b.txt"], errors
case = copy.deepcopy(report)
case["cross_repo_commits"][1]["commit_hash"] = "f" * 40
errors, _ = validate_cross_repo_commit_ownership(case)
assert errors == [
    "cross_repo_commits[1].commit_hash is not a resolvable 40-hex commit",
], errors
PY
  [ "$status" -eq 0 ]
}

# test_necessity: cross-repo and gate-alert path normalization must remove only
# explicit relative prefixes; stripping the leading dot from .github paths
# causes valid changed-file ownership and alert closure to disagree.
@test "dot-prefixed paths preserve leading dots while removing explicit relative prefixes" {
  run python3 - "$ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts" / "lib"))
from close_gate_alerts import _normalize as normalize_alert_path
from cross_repo_commit_contract import _normalize_path

for normalize in (_normalize_path, normalize_alert_path):
    assert normalize(".github/x") == ".github/x"
    assert normalize("./.github/x") == ".github/x"
    assert normalize("././.github/x") == ".github/x"
    assert normalize(".../x") == ".../x"
PY
  [ "$status" -eq 0 ]
}

# test_necessity: explicit cross-repo ownership must accept a different-task
# subject only when all three declared B2e paths are in that commit's diff.
@test "B2e cross-repo diff ownership accepts 3/3 paths without subject matching" {
  repo="$BATS_TEST_TMPDIR/b2e"
  git -C "$BATS_TEST_TMPDIR" init -q b2e
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  for path in jobs/recalculate_fof.py jobs/recalculate_fast.py api/debug.py; do
    mkdir -p "$repo/${path%/*}"
    printf '%s\n' "$path" >"$repo/$path"
  done
  git -C "$repo" add . && git -C "$repo" commit -qm "different task subject"
  cross_sha="$(git -C "$repo" rev-parse HEAD)"
  printf 'stable\n' >"$repo/stable.txt"
  git -C "$repo" add stable.txt && git -C "$repo" commit -qm cmd_b2e
  own_sha="$(git -C "$repo" rev-parse HEAD)"

  run python3 - "$ROOT" "$repo" "$cross_sha" "$own_sha" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "gates"))
import gate_report_format_main as m

paths = ["jobs/recalculate_fof.py", "jobs/recalculate_fast.py", "api/debug.py"]
report = {
    "commit_hash": sys.argv[4], "task_id": "cmd_b2e_normal", "parent_cmd": "cmd_b2e",
    "files_modified": [{"path": path} for path in paths],
    "cross_repo_commits": [
        {"repo": sys.argv[2], "commit_hash": sys.argv[3], "paths": paths},
        {"repo": sys.argv[2], "commit_hash": sys.argv[4], "paths": ["stable.txt"]},
    ],
}
task = {"task_id": "cmd_b2e_normal", "commit_contract": {
    "required": True, "repo_root": sys.argv[2], "planned_paths": paths,
}}
assert m.validate_cross_repo_commits(report) == []
errors = m.commit_contract_errors(report, task, pathlib.Path(sys.argv[2]))
assert errors == [], errors
PY
  [ "$status" -eq 0 ]
}

# cmd_karo_impl_b46_commit_ownership_all_history_20260726 (B46)
# test_necessity: commit_contract_errors' ownership check for a path a
# report's own commit_hash did not directly touch must search the recent
# commit history (bounded, not just the single most-recent toucher) for a
# commit that names this cmd — and must never credit a shorter cmd_id merely
# because it is a string-prefix of a longer, unrelated one.

@test "B46陽性(実データ): 244b6eb6cで直近toucherが隠れたgate_three_layer_health.shがaba450d32まで遡って所有と認識される" {
  run python3 - "$ROOT" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "gates"))
import gate_report_format_main as m

report = {
    "commit_hash": "244b6eb6c05f0ded050081e22b6ae22ee340fb65",
    "task_id": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726_normal",
    "parent_cmd": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726",
    "files_modified": [
        {"path": "scripts/memory_db_query.sh"},
        {"path": "scripts/gates/gate_three_layer_health.sh"},
        {"path": "tests/unit/test_memory_db_query_rowid_watermark.bats"},
    ],
}
task = {
    "task_id": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726_normal",
    "commit_contract": {
        "required": True,
        "planned_paths": [
            "scripts/memory_db_query.sh",
            "scripts/gates/gate_three_layer_health.sh",
            "tests/unit/test_memory_db_query_rowid_watermark.bats",
        ],
    },
}
errors = m.commit_contract_errors(report, task, pathlib.Path(sys.argv[1]))
assert errors == [], errors
PY
  [ "$status" -eq 0 ]
}

@test "B46陰性(AC3a): このcmdが一度も触っていないpathは、直近履歴に他cmdのcommitがあっても所有と認めずBLOCKする" {
  run python3 - "$ROOT" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "gates"))
import gate_report_format_main as m

report = {
    "commit_hash": "244b6eb6c05f0ded050081e22b6ae22ee340fb65",
    "task_id": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726_normal",
    "parent_cmd": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726",
    "files_modified": [{"path": "scripts/gunshi_gate_sync.sh"}],
}
task = {
    "task_id": "cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726_normal",
    "commit_contract": {"required": True, "planned_paths": ["scripts/gunshi_gate_sync.sh"]},
}
errors = m.commit_contract_errors(report, task, pathlib.Path(sys.argv[1]))
assert len(errors) == 1 and "scripts/gunshi_gate_sync.sh" in errors[0], errors
PY
  [ "$status" -eq 0 ]
}

@test "B46陰性(AC3c): cmd_idの文字列部分一致では所有を認めない(cmd_417がcmd_4171を含むsubjectで誤って通らない)" {
  run python3 - "$ROOT" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "gates"))
import gate_report_format_main as m

subj = "cmd_4171_normal: some unrelated report fix"
# cmd_417 は cmd_4171 の文字列prefixだが、'1'の直後に単語境界が無いため
# 独立した識別子としては一致しない(誤って所有権を認めてはならない)。
assert m._subject_identifies_cmd(subj, "cmd_417") is False
# 一方、完全な識別子は正しく一致する。
assert m._subject_identifies_cmd(subj, "cmd_4171_normal") is True
assert m._subject_identifies_cmd(subj, "cmd_4171") is False  # コロンの手前は"_normal"境界のみ
PY
  [ "$status" -eq 0 ]
}

@test "B46速度: 履歴の長いファイル(scripts/deploy_task.sh, 500件超commit)でも所有判定がgate速度予算内(p90 2820ms)で完了する" {
  run python3 - "$ROOT" <<'PY'
import pathlib, subprocess, sys, time
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts" / "gates"))
import gate_report_format_main as m

head = subprocess.run(
    ["git", "-C", sys.argv[1], "rev-parse", "HEAD"],
    check=True, capture_output=True, text=True,
).stdout.strip()
report = {
    "commit_hash": head,
    # 実在しないcmd_idを使い、意図的に「所有していない(=フォールバック探索を
    # 最後まで走らせ、n件全てを検討してから諦める)」最悪ケースを計測する。
    "task_id": "cmd_nonexistent_speed_probe_20260726_normal",
    "parent_cmd": "cmd_nonexistent_speed_probe_20260726",
    "files_modified": [{"path": "scripts/deploy_task.sh"}],
}
task = {
    "task_id": "cmd_nonexistent_speed_probe_20260726_normal",
    "commit_contract": {"required": True, "planned_paths": ["scripts/deploy_task.sh"]},
}
start = time.monotonic()
errors = m.commit_contract_errors(report, task, pathlib.Path(sys.argv[1]))
elapsed_ms = (time.monotonic() - start) * 1000
print(f"elapsed_ms={elapsed_ms:.0f}")
assert errors, "expected a BLOCK for a nonexistent cmd_id (fail-closed), got none"
# gate_report_format全体のp90実績(logs/defense_overhead.jsonl source=gate_report_format,
# n=1378, median=530ms/p90=2820ms)の3倍を、単一の所有判定チェックの安全上限とする。
assert elapsed_ms < 8460, f"ownership lookup took {elapsed_ms:.0f}ms, budget is 8460ms (3x p90)"
PY
  [ "$status" -eq 0 ]
}
