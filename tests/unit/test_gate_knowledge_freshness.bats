#!/usr/bin/env bats
# test_necessity: freshness_class別30/180日境界と未知class fail-closed契約を固定する。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/docs/research/systems-knowledge-base/systems" "$FIXTURE/docs/research/systems-knowledge-base/sources"
}

teardown() { rm -rf "$FIXTURE"; }

doc() {
  local name="$1" verified="$2" class="${3:-}"
  {
    echo '# fixture'
    echo "- verified_at: $verified"
    [[ -n "$class" ]] && echo "- freshness_class: $class"
    true
  } > "$FIXTURE/docs/research/systems-knowledge-base/systems/$name.md"
}

scan() {
  KNOWLEDGE_FRESHNESS_ROOT="$FIXTURE" KNOWLEDGE_FRESHNESS_TODAY=2026-07-21 \
    KNOWLEDGE_FRESHNESS_DISABLE_CACHE=1 bash "$ROOT/scripts/gates/gate_knowledge_freshness.sh"
}

@test "31日operationalはSTALE、31日stableはFRESH" {
  doc operational-31 2026-06-20 operational
  doc default-31 2026-06-20
  doc stable-31 2026-06-20 stable_reference
  run scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE: docs/research/systems-knowledge-base/systems/operational-31.md (31 days old; class=operational; limit=30"* ]]
  [[ "$output" == *"STALE: docs/research/systems-knowledge-base/systems/default-31.md (31 days old; class=operational; limit=30"* ]]
  [[ "$output" == *"FRESH: docs/research/systems-knowledge-base/systems/stable-31.md (31 days old; class=stable_reference; limit=180"* ]]
}

@test "stable_referenceは180日FRESH、181日STALE" {
  doc stable-180 2026-01-22 stable_reference
  doc stable-181 2026-01-21 stable_reference
  run scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"FRESH: docs/research/systems-knowledge-base/systems/stable-180.md (180 days old"* ]]
  [[ "$output" == *"STALE: docs/research/systems-knowledge-base/systems/stable-181.md (181 days old"* ]]
}

@test "未知classはWARNでfail closed" {
  doc unknown 2026-07-21 forever
  run scan
  [ "$status" -eq 2 ]
  [[ "$output" == *"WARN: docs/research/systems-knowledge-base/systems/unknown.md (unknown freshness_class=forever)"* ]]
}
