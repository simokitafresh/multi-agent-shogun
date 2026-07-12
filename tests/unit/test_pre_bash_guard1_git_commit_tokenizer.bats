#!/usr/bin/env bats
# test_pre_bash_guard1_git_commit_tokenizer.bats
# cmd_karo_hotfix_guard1_git_commit_tokenizer_202607121350
#
# Guard1(GA-220)は旧実装で"$command"全文への*git*/*commit*部分文字列andを使っていた。
# report_field_set.shのlesson_candidate/result本文に"git"と"committed"という単語が
# プレーンテキストで含まれるだけの無関係commandでも発火し、awk抽出の未unescape
# (Guard14と同根)によりshlex token化が失敗してfail-closed BLOCKする事故が実測3/3で
# 再現した。修正後は生payloadをjson.loadsして正規のcommand文字列を復元し、
# shlex.shlex(posix=True, punctuation_chars=";&|")でquote-awareに実行位置token判定する。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

_run_hook() {
    local cmd="$1"
    local payload
    payload="$(COMMAND="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name":"Bash","tool_input":{"command": os.environ["COMMAND"]}}))
')"
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=shogun bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- 修正前の実測誤BLOCK再現(修正後はALLOWになること) ---

@test "AC1 repro1: report_field_set lesson_candidate with apostrophe quote-splicing mentioning git/committed is ALLOWED" {
    _run_hook "bash scripts/report_field_set.sh queue/reports/foo.yaml lesson_candidate.detail 'Guard0'\"'\"'s design already checks git commit position; not yet committed to git here'"
    [ "$status" -eq 0 ]
}

@test "AC1 repro2: report_field_set result.details with apostrophe quote-splicing mentioning git/committed is ALLOWED" {
    _run_hook "bash scripts/report_field_set.sh queue/reports/foo.yaml result.details 'Doesn'\"'\"'t need git commit here; report only, nothing was committed to git'"
    [ "$status" -eq 0 ]
}

@test "AC1 repro3: report_field_set causal_verification with apostrophe quote-splicing mentioning git/committed is ALLOWED" {
    _run_hook "bash scripts/report_field_set.sh queue/reports/foo.yaml causal_verification.cause_checked 'Guard0'\"'\"'s git commit filter-repo detection reused; nothing committed yet'"
    [ "$status" -eq 0 ]
}

@test "well-formed prose mentioning git/committed (no apostrophe) is ALLOWED" {
    _run_hook 'bash scripts/report_field_set.sh queue/reports/foo.yaml lesson_candidate.detail "Guard0 already checks git commit position before allowing committed changes"'
    [ "$status" -eq 0 ]
}

# --- git status/add/diff: false positive 0 ---

@test "git status alone is ALLOWED" {
    _run_hook "git status"
    [ "$status" -eq 0 ]
}

@test "git add followed by git diff (no commit) is ALLOWED" {
    _run_hook "git add scripts/foo.sh && git diff --cached"
    [ "$status" -eq 0 ]
}

@test "quoted git-add/git-diff text embedded inside a wrapper command does not corrupt outer segment splitting" {
    _run_hook "echo pretest && bash -c \"echo 'git add scripts/foo.sh && git diff --cached'\""
    [ "$status" -eq 0 ]
}

# --- 実git commitは既存GA-220 check-commandへ必ず到達すること (non-DM repo = pass-through no-op) ---

@test "real git commit in a non-DM-Signal repo reaches check-command and is ALLOWED (reflux guard no-ops outside DM-Signal)" {
    _run_hook 'git commit -m "test commit message"'
    [ "$status" -eq 0 ]
}

@test "real git commit -C <path> form reaches check-command (non-DM repo, ALLOWED)" {
    _run_hook "git -C '$PROJECT_ROOT' commit -m test"
    [ "$status" -eq 0 ]
}

@test "cd && git commit form reaches check-command (non-DM repo, ALLOWED)" {
    _run_hook "cd '$PROJECT_ROOT' && git commit -m test"
    [ "$status" -eq 0 ]
}

@test "GA-231: ninja direct git commit is BLOCKED before shared index contamination" {
    local payload
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m direct"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=hanzo bash "$2"' _ "$payload" "$HOOK_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-231)"* ]]
    [[ "$output" == *"ninja_scope_commit.sh"* ]]
}

@test "GA-231: ninja scoped commit helper command is ALLOWED" {
    local payload
    payload='{"tool_name":"Bash","tool_input":{"command":"bash scripts/ninja_scope_commit.sh -m scoped -- scripts/foo.sh"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=hanzo bash "$2"' _ "$payload" "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "GA-231 ontology: settings.yamlに追加したninjaもhook編集なしでBLOCKED" {
    local payload config_root
    config_root="$BATS_TEST_TMPDIR/dynamic-roster"
    mkdir -p "$config_root/config"
    cat > "$config_root/config/settings.yaml" <<'YAML'
  agents:
    shadow:
      role: ninja
      japanese_name: 影
    advisor:
      role: gunshi
      japanese_name: 軍師
YAML
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m direct"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture _AGENT_CONFIG_SCRIPT_DIR="$2" TMUX_AGENT_ID=shadow bash "$3"' _ "$payload" "$config_root" "$HOOK_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-231)"* ]]
}

@test "GA-231 ontology: settings.yamlの非ninja roleはdirect commit guard対象外" {
    local payload config_root
    config_root="$BATS_TEST_TMPDIR/dynamic-roster-role"
    mkdir -p "$config_root/config"
    cat > "$config_root/config/settings.yaml" <<'YAML'
  agents:
    shadow:
      role: ninja
      japanese_name: 影
    advisor:
      role: gunshi
      japanese_name: 軍師
YAML
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m direct"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture _AGENT_CONFIG_SCRIPT_DIR="$2" TMUX_AGENT_ID=advisor bash "$3"' _ "$payload" "$config_root" "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "GA-232: isolated hook without agent_config blocks direct git commit explicitly with exit 2" {
    local iso payload
    iso="$BATS_TEST_TMPDIR/isolated-no-agent-config"
    mkdir -p "$iso/.claude/hooks" "$iso/scripts/hooks"
    cp "$HOOK_SCRIPT" "$iso/.claude/hooks/pre-bash-combined.sh"
    cp "$PROJECT_ROOT/scripts/hooks/three_layer_preflight.sh" "$iso/scripts/hooks/three_layer_preflight.sh"
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m direct"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=hanzo bash "$2"' _ "$payload" "$iso/.claude/hooks/pre-bash-combined.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-231)"* ]]
    [[ "$output" == *"agent role config"* ]]
}

@test "GA-232: isolated hook without agent_config lets normal commands reach their own guard" {
    local iso payload
    iso="$BATS_TEST_TMPDIR/isolated-normal-command"
    mkdir -p "$iso/.claude/hooks" "$iso/scripts/hooks"
    cp "$HOOK_SCRIPT" "$iso/.claude/hooks/pre-bash-combined.sh"
    cp "$PROJECT_ROOT/scripts/hooks/three_layer_preflight.sh" "$iso/scripts/hooks/three_layer_preflight.sh"
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}'
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture bash "$2"' _ "$payload" "$iso/.claude/hooks/pre-bash-combined.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Guard14"* ]]
    [[ "$output" != *"agent role config"* ]]
}

# --- non-Bash payload passthrough ---

@test "non-Bash tool payload is ALLOWED" {
    run bash -c 'printf "%s" "$1" | BATS_TEST_FILENAME=fixture bash "$2"' _ '{"tool_name":"Read","tool_input":{"file_path":"foo.py"}}' "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
}
