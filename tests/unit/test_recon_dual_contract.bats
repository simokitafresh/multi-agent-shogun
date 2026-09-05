#!/usr/bin/env bats
# test_necessity: a 2-track recon cmd (parallel_ok >= 2 + recon marker) must not
# be saveable without the structured recon_dual independence contract; a
# non-recon parallel cmd and a fully specified recon cmd must pass. Encodes the
# 2026-09-06 00:41 cmd_4480 round trip (Karo had to stop deployment and ask the
# Shogun to add prose keywords) so it cannot recur as a manual step.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB="$ROOT/scripts/lib/recon_dual_contract.py"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

write_cmd() {  # $1=file $2=extra yaml lines (already indented 4)
    cat >"$1" <<EOF
  cmd_fixture:
    title: "新四つ目 3 体の再現差 104 PF-月の根因偵察(A1/A2 2 名並行)"
    purpose: "readonly 偵察"
    parallel_ok:
    - AC1
    - AC2
    acceptance_criteria:
      AC1: {description: "A1"}
      AC2: {description: "A2"}
$2
EOF
}

@test "dual recon without recon_dual mapping or prose is BLOCK" {
    write_cmd "$TMP/c.yaml" ""
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == BLOCK:*recon_dual* ]]
}

@test "dual recon with complete recon_dual mapping is PASS(structured)" {
    write_cmd "$TMP/c.yaml" "    recon_dual:
      mode: independent
      cross_reference: forbidden
      base: fixed_origin_main
      shared_context_embargo: karo_release_required"
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS(recon_dual=structured)" ]
}

@test "dual recon with a wrong recon_dual value is BLOCK naming the key" {
    write_cmd "$TMP/c.yaml" "    recon_dual:
      mode: independent
      cross_reference: allowed
      base: fixed_origin_main
      shared_context_embargo: karo_release_required"
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cross_reference must be 'forbidden'"* ]]
}

@test "dual recon with legacy prose only is WARN (compatibility), exit 0" {
    write_cmd "$TMP/c.yaml" "    command: |
      1. 独立2系統、相互参照禁止"
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == WARN:* ]]
}

@test "parallel implementation cmd (no recon marker) is not_required" {
    cat >"$TMP/c.yaml" <<'EOF'
  cmd_fixture:
    title: "LP の 2 file を並行実装"
    purpose: "実装"
    parallel_ok: [AC1, AC2]
EOF
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS(recon_dual=not_required)" ]
}

@test "single-track recon (no parallel_ok) is not_required" {
    cat >"$TMP/c.yaml" <<'EOF'
  cmd_fixture:
    title: "偵察 1 名"
    purpose: "readonly recon"
EOF
    run python3 "$LIB" "$TMP/c.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS(recon_dual=not_required)" ]
}
