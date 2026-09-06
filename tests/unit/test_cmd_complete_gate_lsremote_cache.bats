#!/usr/bin/env bats
# test_necessity: 隔離 cross-repo 判定(resolve_isolated_cross_repo_state)の
# `git ls-remote origin` は (repo, branch) ごとに TTL 内で 1 回だけ実行され、
# 失敗(未公開 branch)は cache されない、という不変量を守る。
# 2026-09-07 将軍 D0: ls-remote ≈9s/回 × report×entry×周期 で gate が 118-146s/回、
# GATE-STALL 180s ×4/3h になった真因の再発防止。

setup() {
    PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMP="$(mktemp -d)"
    export TMPDIR="$TMP"
    export CMD_COMPLETE_GATE_LSREMOTE_CACHE_DIR="$TMP/cache"
    export LSREMOTE_COUNT_FILE="$TMP/count"
    : > "$LSREMOTE_COUNT_FILE"
    mkdir -p "$TMP/bin" "$TMP/repo"
    # fake git: count ls-remote calls; merge-base --is-ancestor always true;
    # branch name "missing" => unpublished (empty output, rc 2)
    cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
args=("$@")
sub=""
for ((i=0;i<${#args[@]};i++)); do
    case "${args[$i]}" in
        -C) i=$((i+1));;
        *) sub="${args[$i]}"; break;;
    esac
done
case "$sub" in
    ls-remote)
        echo "x" >> "$LSREMOTE_COUNT_FILE"
        ref="${args[${#args[@]}-1]}"
        if [[ "$ref" == *missing* ]]; then exit 2; fi
        printf '%s\t%s\n' "1111111111111111111111111111111111111111" "$ref"
        ;;
    merge-base) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$TMP/bin/git"
    export PATH="$TMP/bin:$PATH"
    SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

teardown() {
    rm -rf "$TMP"
}

write_report() {
    local branch="$1"
    cat > "$TMP/report.yaml" <<EOF
commit_hash: $SHA
cross_repo_commits:
  - repo: $TMP/repo
    commit_hash: $SHA
    branch: $branch
    deploy_forbidden: true
EOF
}

run_state() {
    run bash -c 'SCRIPT_DIR="$1"; source "$1/scripts/lib/cmd_complete_gate_ci.sh"; resolve_isolated_cross_repo_state "$2" "$3" "$4"' _ "$PROJECT_DIR" "$TMP/report.yaml" "$TMP/repo" "$SHA"
}

count() { wc -l < "$LSREMOTE_COUNT_FILE" | tr -d ' '; }

@test "same repo/branch within TTL performs ls-remote once" {
    write_report "isolated/x"
    export CMD_COMPLETE_GATE_LSREMOTE_TTL_SEC=120
    run_state
    [ "$status" -eq 0 ]
    [[ "$output" != BLOCK* ]]
    [ "$(count)" -eq 1 ]
    run_state
    [ "$status" -eq 0 ]
    [[ "$output" != BLOCK* ]]
    [ "$(count)" -eq 1 ]
}

@test "TTL=0 disables the cache (ls-remote per call)" {
    write_report "isolated/x"
    export CMD_COMPLETE_GATE_LSREMOTE_TTL_SEC=0
    run_state
    run_state
    [ "$(count)" -eq 2 ]
    [ ! -d "$CMD_COMPLETE_GATE_LSREMOTE_CACHE_DIR" ]
}

@test "unpublished branch is BLOCK and never cached" {
    write_report "isolated/missing"
    export CMD_COMPLETE_GATE_LSREMOTE_TTL_SEC=120
    run_state
    [[ "$output" == BLOCK* ]]
    [[ "$output" == *"branch not published"* ]]
    run_state
    [[ "$output" == BLOCK* ]]
    [ "$(count)" -eq 2 ]
    [ -z "$(ls -A "$CMD_COMPLETE_GATE_LSREMOTE_CACHE_DIR" 2>/dev/null)" ]
}

@test "bounded staleness: tip cached within TTL is reused even if the remote branch was deleted/force-updated after the lookup (契約=TTL 120s 以内の鮮度は保証しない。次周期で再照会される)" {
    write_report "isolated/x"
    export CMD_COMPLETE_GATE_LSREMOTE_TTL_SEC=120
    run_state
    [ "$status" -eq 0 ]
    [ "$(count)" -eq 1 ]
    # simulate deletion/force-update on the remote: subsequent ls-remote would fail
    write_report "isolated/x"
    cat > "$TMP/bin/git" <<'EOF2'
#!/usr/bin/env bash
case "$*" in
    *ls-remote*) echo "x" >> "$LSREMOTE_COUNT_FILE"; exit 2 ;;
    *merge-base*) exit 0 ;;
    *) exit 0 ;;
esac
EOF2
    chmod +x "$TMP/bin/git"
    run_state
    [[ "$output" != BLOCK* ]]
    [ "$(count)" -eq 1 ]
    # after the cache entry expires, the failure is observed
    touch -d '-200 seconds' "$CMD_COMPLETE_GATE_LSREMOTE_CACHE_DIR"/*
    run_state
    [[ "$output" == BLOCK* ]]
    [ "$(count)" -eq 2 ]
}
