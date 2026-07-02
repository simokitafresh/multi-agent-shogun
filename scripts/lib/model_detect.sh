#!/usr/bin/env bash
# model_detect.sh — CLIの実行中モデル名を検出するライブラリ
# cmd_320: @model_nameリアルタイム同期
#
# Usage: source scripts/lib/model_detect.sh
#
# 提供関数:
#   detect_real_model <agent_name> <pane_target>
#     → 成功時: stdout にモデル名を出力、return 0
#     → 失敗時: stdout 空、return 1
#
# 依存: cli_lookup.sh が既にsourceされていること
#
# 検出方式:
#   Claude Code: バナー行 ▝▜█████▛▘  {Model} · {Plan} をcapture-paneで解析
#   Codex CLI:   │ model: {model_name} /model to change │ を解析
#   その他:      未対応 → return 1（フォールバック利用を前提）
#
# キャッシュ:
#   検出成功時に tmux @real_model ペイン変数に保存。
#   次回検出失敗時はキャッシュ値を返す（バナーがスクロールオフした場合の安全網）。

_model_detect_latest_claude_session() {
    awk '
        /Claude Code/ {
            delete lines
            n = 0
        }
        { lines[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                print lines[i]
            }
        }
    '
}

_model_detect_settings_effort() {
    local agent="$1"
    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "" 2>/dev/null || true)
    case "$model_name" in
        *-xhigh)  echo "xhigh" ;;
        *-high)   echo "high" ;;
        *-medium) echo "medium" ;;
        *-low)    echo "low" ;;
    esac
}

_model_detect_claude_family_display() {
    local agent="$1"
    local family="$2"
    local effort="$3"
    local settings_display=""

    settings_display=$(cli_model_display "$agent" 2>/dev/null || true)
    case "$family" in
        opus)
            if [[ "$settings_display" == Opus* ]]; then
                printf '%s\n' "${settings_display% $effort}"
            else
                printf '%s\n' "Opus"
            fi
            ;;
        sonnet)
            if [[ "$settings_display" == Sonnet* ]]; then
                printf '%s\n' "${settings_display% $effort}"
            else
                printf '%s\n' "Sonnet"
            fi
            ;;
        haiku)
            if [[ "$settings_display" == Haiku* ]]; then
                printf '%s\n' "${settings_display% $effort}"
            else
                printf '%s\n' "Haiku"
            fi
            ;;
        fable)
            if [[ "$settings_display" == Fable* ]]; then
                printf '%s\n' "${settings_display% $effort}"
            else
                printf '%s\n' "Fable"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

_model_detect_process_args() {
    local agent="$1"
    local pane_target="$2"
    local cli_t="$3"
    local pane_pid

    pane_pid=$(tmux display-message -p -t "$pane_target" '#{pane_pid}' 2>/dev/null || true)
    [[ "$pane_pid" =~ ^[0-9]+$ ]] || return 1

    local proc_rows
    proc_rows=$(ps -eo pid=,ppid=,args= 2>/dev/null || true)
    [ -n "$proc_rows" ] || return 1

    local args
    args=$(printf '%s\n' "$proc_rows" | awk -v root="$pane_pid" -v cli="$cli_t" '
        {
            pid=$1
            ppid=$2
            $1=""; $2=""
            sub(/^[[:space:]]+/, "")
            parent[pid]=ppid
            cmd[pid]=$0
        }
        END {
            changed=1
            while (changed) {
                changed=0
                for (pid in parent) {
                    if (parent[pid] == root || ((parent[pid] in desc) && desc[parent[pid]])) {
                        if (!desc[pid]) {
                            desc[pid]=1
                            changed=1
                        }
                    }
                }
            }
            for (pid in desc) {
                if (cli == "claude" && cmd[pid] ~ /(^|[\/[:space:]])claude([[:space:]]|$)/) {
                    print cmd[pid]
                } else if (cli == "codex" && cmd[pid] ~ /(^|[\/[:space:]])codex([[:space:]]|$)/) {
                    print cmd[pid]
                }
            }
        }
    ' | tail -1)

    if [ -z "$args" ]; then
        local pane_tty tty_name
        pane_tty=$(tmux display-message -p -t "$pane_target" '#{pane_tty}' 2>/dev/null || true)
        tty_name="${pane_tty#/dev/}"
        if [ -n "$tty_name" ] && [ "$tty_name" != "$pane_tty" ]; then
            args=$(ps -t "$tty_name" -o args= 2>/dev/null | awk -v cli="$cli_t" '
                cli == "claude" && /(^|[\/[:space:]])claude([[:space:]]|$)/ { print }
                cli == "codex" && /(^|[\/[:space:]])codex([[:space:]]|$)/ { print }
            ' | tail -1)
        fi
    fi
    [ -n "$args" ] || return 1

    case "$cli_t" in
        claude)
            local family effort base
            family=$(printf '%s\n' "$args" | sed -nE 's/.*(^|[[:space:]])--model[=[:space:]]+([A-Za-z0-9._-]+).*/\2/p' | tail -1)
            effort=$(printf '%s\n' "$args" | sed -nE 's/.*(^|[[:space:]])--effort[=[:space:]]+([A-Za-z0-9._-]+).*/\2/p' | tail -1)
            effort="${effort:-$(_model_detect_settings_effort "$agent")}"
            family="${family,,}"
            [ -n "$family" ] || return 1
            base=$(_model_detect_claude_family_display "$agent" "$family" "$effort") || return 1
            if [ -n "$effort" ]; then
                printf '%s %s\n' "$base" "$effort"
            else
                printf '%s\n' "$base"
            fi
            ;;
        codex)
            local display
            display=$(cli_model_display "$agent" 2>/dev/null || true)
            [ -n "$display" ] || return 1
            printf '%s\n' "$display"
            ;;
        *)
            return 1
            ;;
    esac
}

# detect_real_model <agent_name> <pane_target>
# CLI種別に応じた方式でペインから実行中のモデル名を検出
detect_real_model() {
    local agent="$1"
    local pane_target="$2"
    local cli_t

    cli_t=$(cli_type "$agent")

    case "$cli_t" in
        claude)
            local process_model
            process_model=$(_model_detect_process_args "$agent" "$pane_target" "$cli_t" 2>/dev/null || true)
            if [ -n "$process_model" ]; then
                tmux set-option -p -t "$pane_target" @real_model "$process_model" 2>/dev/null
                echo "$process_model"
                return 0
            fi

            # Claude Code: バナー検出（幅差分を吸収）
            #   狭幅(200K): ▐▛███▜▌   Sonnet 5 with high effort
            #   狭幅(200K): ▐▛███▜▌   Sonnet 4.6 with high effort
            #   狭幅(1M):   ▐▛███▜▌\n           Opus 4.6 (1M contex…\n▝▜█████▛▘  （モデル名が別行）
            #   標準幅(1M): ▐▛███▜▌   Opus 4.6 (1M context) with high effort
            #   標準幅(200K): ▝▜█████▛▘  Sonnet 5 with high effort · path
            #   標準幅(200K): ▝▜█████▛▘  Sonnet 4.6 with high effort · path
            local output
            output=$(tmux capture-pane -t "$pane_target" -p -J -S -1000 2>/dev/null)
            output=$(printf '%s\n' "$output" | _model_detect_latest_claude_session)

            if [ -n "$output" ]; then
                local banner model

                # Pattern 1: アート行と同じ行にモデル名（幅共通）
                # (1M context)等の括弧部分も許容
                # tail -1: 同一pane内でrespawn後の最新Claude起動バナーを優先する。
                banner=$(echo "$output" | grep -E '(▐▛███▜▌|▝▜█████▛▘)[[:space:]]+(Opus|Sonnet|Haiku|Fable)[[:space:]]+[0-9]+(\.[0-9]+)?' | tail -1)
                if [ -n "$banner" ]; then
                    # 5 sed→1 sed: subprocess削減
                    model=$(echo "$banner" | sed -E \
                        -e 's/.*(▐▛███▜▌|▝▜█████▛▘)[[:space:]]*//' \
                        -e 's/[[:space:]]*\(.*\)//' \
                        -e 's/[[:space:]]+with[[:space:]]+([a-z]+)[[:space:]]+eff.*/ \1/' \
                        -e 's/[[:space:]]*·.*//' \
                        -e 's/[[:space:]]*$//')
                fi

                # Pattern 2: モデル名が別行（狭幅ペイン、1Mコンテキスト時）
                #   行頭空白 + Opus/Sonnet/Haiku + バージョン
                if [ -z "$model" ]; then
                    local model_line
                    model_line=$(echo "$output" | grep -E '^[[:space:]]+(Opus|Sonnet|Haiku|Fable)[[:space:]]+[0-9]+(\.[0-9]+)?' | tail -1)
                    if [ -n "$model_line" ]; then
                        # 4 sed→1 sed: subprocess削減
                        model=$(echo "$model_line" | sed -E \
                            -e 's/^[[:space:]]*//' \
                            -e 's/[[:space:]]*\(.*$//' \
                            -e 's/[[:space:]]+with[[:space:]]+([a-z]+)[[:space:]]+eff.*/ \1/' \
                            -e 's/[[:space:]]*$//')
                    fi
                fi

                # Validate: reject model names containing non-ASCII (false positive from file content in pane)
                if [[ -n "$model" && "$model" =~ [^A-Za-z0-9.\ \(\)/-] ]]; then
                    model=""
                fi

                if [ -n "$model" ]; then
                    tmux set-option -p -t "$pane_target" @real_model "$model" 2>/dev/null
                    echo "$model"
                    return 0
                fi
            fi

            tmux set-option -pu -t "$pane_target" @real_model 2>/dev/null || true

            return 1
            ;;
        codex)
            local process_model
            process_model=$(_model_detect_process_args "$agent" "$pane_target" "$cli_t" 2>/dev/null || true)
            if [ -n "$process_model" ]; then
                tmux set-option -p -t "$pane_target" @real_model "$process_model" 2>/dev/null
                echo "$process_model"
                return 0
            fi

            # Codex CLI: │ model: {model_name} /model to change │
            local output
            output=$(tmux capture-pane -t "$pane_target" -p -J -S -1000 2>/dev/null)

            if [ -n "$output" ]; then
                local model_line model
                model_line=$(echo "$output" | grep -E '│.*model:' | tail -1)

                if [ -n "$model_line" ]; then
                    # "model:" の後ろ、"/model" or "│" の前
                    # cmd_583: tr -s ' ' で連続空白を正規化（fast ON時に "gpt-5.5 high fast" を得る）
                    # 2 sed→1 sed -e: subprocess削減
                    model=$(echo "$model_line" | sed -E \
                        -e 's/.*model:[[:space:]]*//' \
                        -e 's/[[:space:]]*(\/model|│).*//' | tr -s ' ')
                fi

                # バナーがスクロールアウトした場合のフォールバック:
                # フッター行 "model_name · XX% left · YY% used" から抽出
                if [ -z "$model" ]; then
                    local footer_line
                    footer_line=$(echo "$output" | grep -E '·[[:space:]]*[0-9]+% left[[:space:]]*·[[:space:]]*[0-9]+% used' | tail -1)
                    if [ -n "$footer_line" ]; then
                        # cmd_583: tr -s ' ' で連続空白を正規化
                        model=$(echo "$footer_line" \
                            | sed -E 's/^[[:space:]]*//' \
                            | sed -E 's/[[:space:]]*·[[:space:]]*[0-9]+% left[[:space:]]*·[[:space:]]*[0-9]+% used.*$//' \
                            | tr -s ' ')
                    fi
                fi

                # "loading" は検出失敗扱い
                if [ -n "$model" ] && [ "$model" != "loading" ]; then
                    tmux set-option -p -t "$pane_target" @real_model "$model" 2>/dev/null
                    echo "$model"
                    return 0
                fi
            fi

            tmux set-option -pu -t "$pane_target" @real_model 2>/dev/null || true

            return 1
            ;;
        *)
            # copilot, kimi等: 未対応 → fallback
            return 1
            ;;
    esac
}
