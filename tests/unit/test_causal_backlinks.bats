#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/causal_backlinks.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/causal-backlinks.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/bin" "$TEST_TMPDIR/context" "$TEST_TMPDIR/instructions"
    touch "$TEST_TMPDIR/AGENTS.md"
    cat > "$TEST_TMPDIR/bin/rg" <<'EOF'
#!/usr/bin/env bash
printf 'call\n' >> "$RG_CALL_LOG"
case " $* " in
  *' -l '*) printf 'context/example.md\n' ;;
  *' -n '*) printf 'context/example.md:1:origin: [[L618]]\n' ;;
esac
EOF
    chmod +x "$TEST_TMPDIR/bin/rg"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "all search roots are passed to one rg invocation" {
    cd "$TEST_TMPDIR"
    run env PATH="$TEST_TMPDIR/bin:$PATH" RG_CALL_LOG="$TEST_TMPDIR/calls" bash "$SCRIPT" L618

    [ "$status" -eq 0 ]
    [ "$output" = "context/example.md" ]
    [ "$(wc -l < "$TEST_TMPDIR/calls")" -eq 1 ]
}

@test "detail mode also uses one rg invocation and preserves origin filtering" {
    cd "$TEST_TMPDIR"
    run env PATH="$TEST_TMPDIR/bin:$PATH" RG_CALL_LOG="$TEST_TMPDIR/calls" bash "$SCRIPT" --detail L618

    [ "$status" -eq 0 ]
    [[ "$output" == *"origin: [[L618]]"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/calls")" -eq 1 ]
}
