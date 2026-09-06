#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# test_necessity: 品質契約のFP計測語彙が日本語の同義表現を受理し、表現差だけの誤BLOCKを防ぐ不変量を守る。
#
# CI run 33152966157/33334577571/33337094964/34003273306/34033921264: this test
# intermittently reported "not ok ... line 20" (the final `$output` equality)
# while `$status` was 0 and the loop's own internal
# `[[ "$result" == $'yes\tpass\tpass' ]] || { ...; exit 1; }` guard never fired
# (no "repetition=/term=/actual=" line ever appeared in any failing shard's
# artifact — confirmed by downloading and inspecting the raw shard-1 TAP
# output/log for run 34033921264). That combination is only possible when the
# vocabulary matcher itself is correct on every one of the 50 evaluations, and
# something unrelated is appended to the combined stdout+stderr stream that
# `run` folds into `$output` by default. This file forks the loop body's own
# `source`d function twice per iteration via awk pipelines (~50 iterations),
# making it the heaviest forker in the suite; under this shard's
# BATS_FILE_JOBS=32 concurrency any transient stderr byte written anywhere in
# the subprocess tree (by bash itself, by a coreutil, or by the runner) lands
# in `$output` and breaks the exact-string comparison without ever touching
# `$result`. `run --separate-stderr` (bats-core >=1.5) keeps stdout and
# stderr apart so the assertion below can no longer be corrupted by stray
# stderr noise; `$stderr` is still surfaced on failure for genuine
# diagnosis.
@test "FP measurement accepts all five vocabulary families" {
  run --separate-stderr bash -c '
    source "$1/scripts/lib/gate_hook_quality_contract.sh"
    for repetition in $(seq 1 10); do
      for term in false_positive 偽陽性 誤発報 誤BLOCK 誤遮断; do
      printf -v block_text "gate追加\nquality_gate:\n  action_conversion: BLOCKを検出する\n  fp_measurement: %s" "$term"
      result="$(LC_ALL=C gate_hook_quality_contract_evaluate "$block_text")"
      [[ "$result" == $'"'"'yes\tpass\tpass'"'"' ]] || {
        printf "repetition=%s term=%s actual=%s\n" "$repetition" "$term" "$result" >&2
        exit 1
      }
      done
    done
    printf "positive_terms=5 measurement_pass=5\n"
  ' _ "$BATS_TEST_DIRNAME/../.."
  if [ "$status" -ne 0 ] || [ "$output" != "positive_terms=5 measurement_pass=5" ]; then
    local reason_code=output_mismatch
    [ "$status" -eq 0 ] || reason_code=nonzero_status
    printf 'rc=%s\n' "$status" >&2
    printf 'stderr=%s\n' "${stderr-}" >&2
    printf 'reason_code=%s\n' "$reason_code" >&2
    printf 'diagnostic_output=%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  [ "$output" = "positive_terms=5 measurement_pass=5" ]
}

# test_necessity: FP語彙がない計測文はmissingのままにし、語彙追加で品質契約の陰性境界を緩めない不変量を守る。
@test "unrelated measurement remains missing" {
  run bash -c '
    source "$1/scripts/lib/gate_hook_quality_contract.sh"
    printf -v block_text "gate追加\nquality_gate:\n  action_conversion: BLOCKを検出する\n  fp_measurement: %s" "coverage=100%"
    result="$(LC_ALL=C gate_hook_quality_contract_evaluate "$block_text")"
    [[ "$result" == $'"'"'yes\tpass\tmissing'"'"' ]]
    printf "negative_terms=1 missing=1\n"
  ' _ "$BATS_TEST_DIRNAME/../.."
  [ "$status" -eq 0 ]
  [ "$output" = "negative_terms=1 missing=1" ]
}

# test_necessity: F-11/F-12/F-13/F-16の再発防止不変量。scriptを`source`/`bash`ではなく
# リテラルpath文字列でのみ参照する既存bats(コンテンツ契約test)も、変更scriptの参照
# 集合として検出しなければならない。検出しなければD0のprecommit affected-test実行が
# 当該batsを黙って飛ばし、CI RED再発の穴となる(gate_hook_quality_contract.sh:reference test matches)。
@test "reference test matches find a bats file that only string-references the script path" {
  local repo_root fixture_test_dir
  repo_root="$BATS_TEST_TMPDIR/repo"
  fixture_test_dir="$repo_root/tests/unit"
  mkdir -p "$fixture_test_dir"
  cat > "$fixture_test_dir/test_unrelated_literal_ref.bats" <<'FIXTURE'
#!/usr/bin/env bats
@test "literal path reference" {
  target="$BATS_TEST_DIRNAME/../../scripts/publisher_c2a_merge.sh"
  [ -f "$target" ]
}
FIXTURE
  run bash -c '
    set -euo pipefail
    source "$1/scripts/lib/gate_hook_quality_contract.sh"
    gate_hook_quality_contract_reference_test_matches "scripts/publisher_c2a_merge.sh" "$2"
  ' _ "$BATS_TEST_DIRNAME/../.." "$repo_root"
  [ "$status" -eq 0 ]
  [ "$output" = "tests/unit/test_unrelated_literal_ref.bats" ]
}

# test_necessity: 参照するbatsが存在しない場合は空集合を明示し、誤検出(存在しないtestの
# 捏造や無関係batsの誤爆)を出さない不変量を守る(docs-only/無関係script両方の陰性対照)。
@test "reference test matches return empty set when no bats references the script" {
  local repo_root fixture_test_dir
  repo_root="$BATS_TEST_TMPDIR/repo_empty"
  fixture_test_dir="$repo_root/tests/unit"
  mkdir -p "$fixture_test_dir"
  cat > "$fixture_test_dir/test_unrelated.bats" <<'FIXTURE'
#!/usr/bin/env bats
@test "no relation" {
  [ 1 -eq 1 ]
}
FIXTURE
  run bash -c '
    set -euo pipefail
    source "$1/scripts/lib/gate_hook_quality_contract.sh"
    gate_hook_quality_contract_reference_test_matches "scripts/never_referenced_script.sh" "$2"
    echo "rc=$?"
  ' _ "$BATS_TEST_DIRNAME/../.." "$repo_root"
  [ "$status" -eq 0 ]
  [ "$output" = "rc=0" ]
}
