#!/usr/bin/env bats
# 先送りBLOCK注入の二重ストア突合(LS078三例目) + 判定根拠(キー本文)表示
# 履歴TSVは追記専用で解消が伝播しない。現在状態の正=session_alertsと突合する。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state_defer.XXXXXX")"
    export PROMPT_STATE_DEFER_HISTORY_FILE="$TEST_TMPDIR/history.tsv"
    export PROMPT_STATE_SESSION_ALERTS_FILE="$TEST_TMPDIR/session_alerts.txt"
    printf '2026-07-02T20:41:51+0900\t先送り判断: SKILL.md script参照: 要確認あり が3セッション連続\n' > "$PROMPT_STATE_DEFER_HISTORY_FILE"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

run_hook() {
    echo '{"prompt":"defer reconcile test"}' | bash "$HOOK" 2>/dev/null
}

@test "session_alertsが全DONEなら履歴TSVの先送りは解消済みとして注入しない" {
    printf '# session_alerts — generated: test\n[DONE] SKILL.md script参照: 解消済み\n' > "$PROMPT_STATE_SESSION_ALERTS_FILE"
    run run_hook
    [ "$status" -eq 0 ]
    [[ "$output" != *"先送りBLOCK"* ]]
}

@test "session_alertsにTODOが残る場合は件数とキー本文を注入する(判定根拠の可視化)" {
    printf '# session_alerts — generated: test\n[TODO] SKILL.md script参照: 要確認あり\n' > "$PROMPT_STATE_SESSION_ALERTS_FILE"
    run run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"先送りBLOCK 現在未解消1件"* ]]
    [[ "$output" == *"SKILL.md script参照"* ]]
}

@test "session_alertsファイル不在時は保守的に履歴TSVの件数を注入する" {
    rm -f "$PROMPT_STATE_SESSION_ALERTS_FILE"
    run run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"先送りBLOCK 現在未解消1件"* ]]
}
