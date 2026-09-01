#!/usr/bin/env bash
# Shared guard for CLI confirmation prompts.
# A nudge sent while this prompt is active can be consumed as the choice
# itself, so callers must defer delivery and preserve the unread message.
#
# 2026-09-01 13:14 殿『将軍が起きない』: 旧実装は scrollback 30 行を緩い regex
# ([[:space:]]1\.[[:space:]]*Yes 等)で検索し、将軍の説明文中の引用『❯ 1. Yes』に
# 4 回連続で誤 match して nudge を 0 件に抑止した。実プロンプトは「行頭(任意の
# カーソル ❯/› と空白)から始まる番号付き選択肢が連続する」構造を持つ。散文中の
# 引用は行頭に来ない。∴ 可視画面のみ・行頭構造のみで判定する。

# $1 = 可視画面テキスト。実確認プロンプトなら 0。
_pane_confirmation_screen_has_prompt() {
    local screen="${1:-}"
    [ -n "$screen" ] || return 1
    printf '%s\n' "$screen" | awk '
        function is_choice(line, n) {
            return line ~ ("^[[:space:]]*[❯›>]?[[:space:]]*" n "\\.[[:space:]]+[^[:space:]]")
        }
        {
            lines[NR] = $0
        }
        END {
            for (i = 1; i <= NR; i++) {
                # 質問文が行頭にある(散文の途中ではない)
                # 質問文が行頭にある(散文の途中ではない)=単独で dialog とみなす(安全側: nudge 保留)
                if (lines[i] ~ /^[[:space:]]*[│|•●]?[[:space:]]*(Do you want to proceed\?|Do you trust|Confirm(ation)? required|Approval required)/) {
                    found = 1
                }
                # 質問文なしでも 1. と 2. の選択肢が行頭で連続していれば dialog
                if (is_choice(lines[i], 1)) {
                    for (j = i + 1; j <= NR && j <= i + 3; j++) {
                        if (is_choice(lines[j], 2)) { found = 1; break }
                    }
                }
                if (found) break
            }
            exit(found ? 0 : 1)
        }'
}

# Return 0 when the pane is waiting for an authorized confirmation decision.
_pane_has_confirmation_prompt() {
    local pane_target="$1"
    local capture
    capture=$(tmux capture-pane -t "$pane_target" -p 2>/dev/null || true)
    _pane_confirmation_screen_has_prompt "$capture"
}
