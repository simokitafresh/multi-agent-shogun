#!/usr/bin/env bats
# test_necessity: result-determining input changes must invalidate the TTL cache, while implementation-only changes must not become interface WARNs.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/scripts" "$FIXTURE/skills/demo" "$FIXTURE/logs"
  cp "$REPO_ROOT/scripts/gates/gate_skill_script_refs.sh" "$FIXTURE/gate.sh"
  cat > "$FIXTURE/scripts/demo.sh" <<'EOF'
#!/usr/bin/env bash
# Usage: demo.sh [--name VALUE]
# Exit code: 0=PASS, 2=review required
value=one
printf 'result=%s\n' "$value"
EOF
  cat > "$FIXTURE/skills/demo/SKILL.md" <<'EOF'
# demo
Run `bash scripts/demo.sh`.
<!-- script_refs_checked_at: 2099-01-01T00:00:00+00:00 -->
EOF
  export SKILL_REF_DIRS=skills
  export SKILL_REF_HASH_STATE="$FIXTURE/logs/state.json"
  printf '{"references":{}}\n' > "$SKILL_REF_HASH_STATE"
  export SKILL_REF_CACHE_TTL_SECONDS=3600
}

teardown() { rm -rf "$FIXTURE"; }

run_gate() { run bash "$FIXTURE/gate.sh" "$FIXTURE"; }
establish_verified() {
  export SKILL_REF_RECORD_VERIFIED=1
  run_gate
  [ "$status" -eq 0 ]
  unset SKILL_REF_RECORD_VERIFIED
  run_gate
  [ "$status" -eq 0 ]
}

@test "internal implementation change stays PASS and cache input is recomputed" {
  establish_verified
  sed -i 's/value=one/value=two/' "$FIXTURE/scripts/demo.sh"
  establish_verified
  [[ "$output" == *"総合判定: PASS"* ]]
}

@test "usage interface change produces exactly one WARN" {
  establish_verified
  sed -i 's/--name VALUE/--name VALUE --force/' "$FIXTURE/scripts/demo.sh"
  run_gate; [ "$status" -eq 2 ]
  [ "$(grep -c 'WARN: .*demo.sh' <<<"$output")" -eq 1 ]
}

@test "non-max SKILL and verified state changes invalidate TTL cache" {
  mkdir -p "$FIXTURE/skills/other"
  printf '# other\n' > "$FIXTURE/skills/other/SKILL.md"
  establish_verified
  before_count="$(find /tmp -maxdepth 1 -name 'shogun_gate_skill_script_refs_*.cache' -newer "$FIXTURE/gate.sh" | wc -l)"
  printf '# other changed\n' > "$FIXTURE/skills/other/SKILL.md"
  sed -i '1s/{/{"generation":1,/' "$SKILL_REF_HASH_STATE"
  run_gate
  [ "$status" -eq 0 ]
  after_count="$(find /tmp -maxdepth 1 -name 'shogun_gate_skill_script_refs_*.cache' -newer "$FIXTURE/gate.sh" | wc -l)"
  [ "$after_count" -gt "$before_count" ]
}

@test "identical input second invocation is a cache hit with identical rc and output" {
  establish_verified
  run_gate; first_status="$status"; first_output="$output"
  run_gate
  [ "$status" -eq "$first_status" ]
  [ "$output" = "$first_output" ]
  [ "$(find /tmp -maxdepth 1 -name 'shogun_gate_skill_script_refs_*.cache' -newer "$FIXTURE/gate.sh" | wc -l)" -ge 1 ]
}
