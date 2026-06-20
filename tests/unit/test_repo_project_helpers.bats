#!/usr/bin/env bats
# test_repo_project_helpers.bats — scripts/lib/repo_root.sh と scripts/lib/project_path.sh のユニットテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export REPO_ROOT_LIB="$PROJECT_ROOT/scripts/lib/repo_root.sh"
    export PROJECT_PATH_LIB="$PROJECT_ROOT/scripts/lib/project_path.sh"

    [ -f "$REPO_ROOT_LIB" ]     || return 1
    [ -f "$PROJECT_PATH_LIB" ]  || return 1
}

# ── repo_root.sh ──────────────────────────────────────────────────────────────

@test "get_repo_root: git rev-parse --show-toplevel と一致する" {
    run bash -lc "source '$REPO_ROOT_LIB'; get_repo_root"
    [ "$status" -eq 0 ]
    expected="$(git rev-parse --show-toplevel)"
    [ "$output" = "$expected" ]
}

@test "get_repo_root: 同一プロセスで2回呼んでも同じ値を返す" {
    run bash -lc "
source '$REPO_ROOT_LIB'
r1=\$(get_repo_root)
r2=\$(get_repo_root)
[ \"\$r1\" = \"\$r2\" ] && echo SAME || echo DIFF
"
    [ "$status" -eq 0 ]
    [ "$output" = "SAME" ]
}

@test "get_repo_root: git リポジトリ外では失敗する" {
    run bash -lc "
cd /tmp
source '$REPO_ROOT_LIB'
get_repo_root
"
    [ "$status" -ne 0 ]
}

# ── project_path.sh ───────────────────────────────────────────────────────────

@test "get_project_path: dm-signal のパスを返す" {
    run bash -lc "source '$PROJECT_PATH_LIB'; get_project_path dm-signal"
    [ "$status" -eq 0 ]
    [ "$output" = "/mnt/c/Python_app/DM-signal" ]
}

@test "get_project_path: infra のパスを返す" {
    run bash -lc "source '$PROJECT_PATH_LIB'; get_project_path infra"
    [ "$status" -eq 0 ]
    [ "$output" = "/mnt/c/tools/multi-agent-shogun" ]
}

@test "get_project_path: 存在しない id は失敗する" {
    run bash -lc "source '$PROJECT_PATH_LIB'; get_project_path __no_such_project__"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]]
}

@test "get_project_path: id 引数なしは失敗する" {
    run bash -lc "source '$PROJECT_PATH_LIB'; get_project_path"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "required" ]]
}

@test "get_project_path: カスタム projects.yaml を参照できる" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/config"
    cat > "$tmpdir/config/projects.yaml" <<'YAML'
projects:
  - id: test-proj
    name: "Test Project"
    path: "/tmp/test-project"
YAML

    run bash -lc "
source '$REPO_ROOT_LIB'
_REPO_ROOT_CACHE='$tmpdir'
source '$PROJECT_PATH_LIB'
get_project_path test-proj
"
    rm -rf "$tmpdir"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/test-project" ]
}
