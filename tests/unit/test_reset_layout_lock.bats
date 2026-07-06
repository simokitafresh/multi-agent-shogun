#!/usr/bin/env bats
# test_reset_layout_lock.bats
# reset_layout.sh の並行実行ガード(flock)を検証する。
#
# 背景: cmd_karo_hotfix_auto_update_pane_spawn_202607031806
#   2026-07-03 16:55、agentsウィンドウにclaude 2.1.199(auto-update版)の
#   無主pane6枚が生成された(殿発見)。reset_layout.sh/shutsujin_departure.sh
#   はtmuxペインを新規作成できる唯一の2スクリプトだが、いずれもflock等の
#   排他制御を持たず、split-window→swap-pane→CLI起動という非原子的な
#   複数tmux操作を行う。2重起動されるとメガバッチで取得したペイン索引が
#   互いに古くなり、想定外のペインにCLI起動コマンドが送られて
#   @agent_id未設定の無主ペインが生じ得る（既存ペインは無傷のまま=
#   実際の障害報告と整合）。本テストはreset_layout.shに追加したflock
#   排他ガードが機能することを検証する。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    LOCK_FILE="/tmp/shogun_reset_layout.lock"
}

@test "reset_layout.sh: ソース内にflock排他ガードが存在する" {
    run bash -c "grep -q 'LOCK_FILE=\"/tmp/shogun_reset_layout.lock\"' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]

    run bash -c "grep -q 'flock -n 201' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]
}

@test "reset_layout.sh: flockガードは最初の実tmuxコマンド(コメント除く)より前に配置されている" {
    # ロックガード行番号が最初の実tmux呼び出しより前であることを保証する。
    # 後方に置かれるとsplit-window等が先に実行され、ガードの意味がなくなる。
    lock_line=$(grep -n 'flock -n 201' "$PROJECT_ROOT/scripts/reset_layout.sh" | head -1 | cut -d: -f1)
    first_tmux_line=$(grep -n 'tmux \(list-panes\|split-window\|swap-pane\|respawn-pane\|send-keys\|set-option\|select-layout\|show-options\)' \
        "$PROJECT_ROOT/scripts/reset_layout.sh" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)

    [ -n "$lock_line" ]
    [ -n "$first_tmux_line" ]
    [ "$lock_line" -lt "$first_tmux_line" ]
}

@test "reset_layout.sh: 2重起動時は後発プロセスがSKIPし、exit 0で即座に終了する" {
    rm -f "$LOCK_FILE"

    # ロックを保持するホルダープロセスをバックグラウンドで起動
    (
        exec 201>"$LOCK_FILE"
        flock 201
        sleep 5
    ) &
    holder_pid=$!

    # ホルダーがflockを確実に取得するまで短時間待つ（同一マシン上のflockは即時取得のため十分）
    sleep 0.5

    run timeout 10 bash "$PROJECT_ROOT/scripts/reset_layout.sh" --dry-run

    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true

    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: another reset_layout.sh instance is already running"* ]]
    # ロック取得に失敗して即終了したことを保証: Step以降のログが出ていないこと
    [[ "$output" != *"Step 1: 前提確認"* ]]
}

@test "reset_layout.sh: 期待数超過時に無主paneだけを自動回収するガードがある" {
    run bash -c "grep -q 'exceeds the expected roster' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]

    run bash -c "grep -q 'removed orphan unowned pane' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]

    run bash -c "grep -q 'tmux kill-pane -t' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]

    run bash -c "grep -Fq 'if [[ -z \"\$_aid\" ]]; then' '$PROJECT_ROOT/scripts/reset_layout.sh'"
    [ "$status" -eq 0 ]
}
