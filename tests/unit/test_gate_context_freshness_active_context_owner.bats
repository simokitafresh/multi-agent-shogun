#!/usr/bin/env bats
# test_necessity: freshness missing-metadata suppression must share the fail-closed active owner predicate.
@test "freshness uses shared predicate and retains WARN fallback" {
  gate="$BATS_TEST_DIRNAME/../../scripts/gates/gate_context_freshness.sh"
  run grep -F 'active_context_defer_allowed "$ROOT_DIR" "$rel_path"' "$gate"; [ "$status" -eq 0 ]
  run grep -F 'WARN: ${basename_file} (last_updated 未記載)' "$gate"; [ "$status" -eq 0 ]
}
