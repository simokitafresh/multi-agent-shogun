#!/usr/bin/env bats

# test_necessity: 品質契約のFP計測語彙が日本語の同義表現を受理し、表現差だけの誤BLOCKを防ぐ不変量を守る。
@test "FP measurement accepts all five vocabulary families" {
  run bash -c '
    source "$1/scripts/lib/gate_hook_quality_contract.sh"
    for term in false_positive 偽陽性 誤発報 誤BLOCK 誤遮断; do
      printf -v block_text "gate追加\nquality_gate:\n  action_conversion: BLOCKを検出する\n  fp_measurement: %s" "$term"
      result="$(LC_ALL=C gate_hook_quality_contract_evaluate "$block_text")"
      [[ "$result" == $'"'"'yes\tpass\tpass'"'"' ]] || {
        printf "term=%s result=%s\n" "$term" "$result" >&2
        exit 1
      }
    done
    printf "positive_terms=5 measurement_pass=5\n"
  ' _ "$BATS_TEST_DIRNAME/../.."
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
