#!/bin/bash
# cli_ready.sh — 起動直後の CLI pane が「入力待ちプロンプト」に到達したかを可視画面で判定する。
# 正本は本ファイル 1 箇所。shutsujin_departure.sh / scripts/reset_layout.sh が source する。
#
# 判定=プロンプト行そのもの(cli_profiles.yaml idle_pattern と同じ記号):
#   claude : 行頭 "❯" のあと空(入力欄が空)          例 "❯ "
#   codex  : "› Ask Codex to do anything" または行頭 "›" のあと空
# 意図的に一致させないもの(家老レビュー 2026-09-01 13:05 の敵対 fixture):
#   - footer "⏵⏵ bypass permissions on" 単独(prompt 不在の途中状態)
#   - 確認/更新/上限ダイアログの選択肢行 "❯ 1. Yes" "› 1. Update now"(記号の後に文字が続く)
#   - crash 後のシェルプロンプト "(疾風) ~$"、'database is locked'
# scrollback は見ない(-S なし): crash 後に残る起動バナーで偽 ready になるため。

CLI_READY_PROMPT_REGEX='^[[:space:]]*❯[[:space:]]*$|^[[:space:]]*›[[:space:]]*$|›[[:space:]]+Ask Codex to do anything'
# busy marker: Codex/Claude はプロンプト行を常設したまま作業中表示を出す(家老再レビュー 13:11:
# 起動 hook 実行中の pane が『Running 5 PreToolUse hooks / Working 25s』と『› Ask Codex』を同時に持つ)。
# ready=プロンプト一致 ∧ busy marker 不在。
CLI_BUSY_MARKER_REGEX='esc to interrupt|Working \(|Running [0-9]+ [A-Za-z]* ?hooks?|SessionStart hook'

# $1 = 可視画面テキスト。ready なら 0。
cli_visible_is_ready() {
    local _screen="${1:-}"
    printf '%s\n' "$_screen" | grep -Eq "$CLI_READY_PROMPT_REGEX" || return 1
    if printf '%s\n' "$_screen" | grep -Eq "$CLI_BUSY_MARKER_REGEX"; then
        return 1
    fi
    return 0
}

# $1 = tmux pane target。ready なら 0。
cli_pane_is_ready() {
    local _capture
    _capture="$(tmux capture-pane -t "$1" -p 2>/dev/null || true)"
    [ -n "$_capture" ] || return 1
    cli_visible_is_ready "$_capture"
}

# $1 = pane target, $2 = timeout(sec)。ready で 0、timeout で 1。
cli_wait_pane_ready() {
    local _target="$1" _limit="${2:-60}" _i
    for ((_i = 1; _i <= _limit; _i++)); do
        if cli_pane_is_ready "$_target"; then
            CLI_READY_ELAPSED="$_i"
            return 0
        fi
        sleep 1
    done
    CLI_READY_ELAPSED="$_limit"
    return 1
}

# 稼働中の codex プロセス数を単一整数で返す(pgrep -c は 0 件で "0"+exit 1 → `|| echo 0` だと "0\n0")。
cli_codex_process_count() {
    local _n
    _n="$(pgrep -c -x codex 2>/dev/null || true)"
    _n="${_n%%$'\n'*}"
    [[ "$_n" =~ ^[0-9]+$ ]] || _n=0
    printf '%s\n' "$_n"
}
