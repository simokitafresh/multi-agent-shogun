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
  run_gate; [ "$status" -eq 0 ]
  [ "$(grep -c 'WARN: .*demo.sh' <<<"$output")" -eq 0 ]
  [[ "$output" == *"required=0, deduped=1"* ]]
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

@test "37 distinct checked_at values use one aggregate history walk" {
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email fixture@example.invalid
  git -C "$FIXTURE" config user.name fixture
  git -C "$FIXTURE" add scripts/demo.sh skills/demo/SKILL.md
  GIT_AUTHOR_DATE=2025-01-01T00:00:00Z GIT_COMMITTER_DATE=2025-01-01T00:00:00Z \
    git -C "$FIXTURE" commit -qm fixture
  rm -rf "$FIXTURE/skills"
  mkdir -p "$FIXTURE/skills" "$FIXTURE/bin"
  for i in $(seq 1 37); do
    mkdir -p "$FIXTURE/skills/demo$i"
    printf '# demo\nRun `bash scripts/demo.sh`.\n<!-- script_refs_checked_at: 2025-01-%02dT00:00:00+00:00 -->\n' \
      "$i" > "$FIXTURE/skills/demo$i/SKILL.md"
  done
  real_git="$(command -v git)"
  printf '#!/usr/bin/env bash\nif [[ " $* " == *" rev-list "* ]]; then printf "walk\\n" >> %q; fi\nexec %q "$@"\n' \
    "$FIXTURE/rev-list.log" "$real_git" > "$FIXTURE/bin/git"
  chmod +x "$FIXTURE/bin/git"
  PATH="$FIXTURE/bin:$PATH" SKILL_REF_DISABLE_CACHE=1 run_gate
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FIXTURE/rev-list.log")" -eq 2 ]
  [[ "$output" == *"走査: 37 SKILL.md"* ]]
}
