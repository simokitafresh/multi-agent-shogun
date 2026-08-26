#!/usr/bin/env bash
# cli_lookup.sh — CLI Profile SSOT参照ライブラリ
# cmd_143 Phase 1: Profile SSOT基盤
#
# Usage: source scripts/lib/cli_lookup.sh
#
# 提供関数:
#   cli_type <agent_name>          → "claude" / "codex"
#   cli_profile_get <agent_name> <key> → cli_profiles.yamlから任意のキーを取得
#   cli_launch_cmd <agent_name>    → 起動コマンド文字列
#
# 設計:
#   settings.yaml → type取得 → cli_profiles.yaml → 値取得 の2段参照
#   WSL2 /mnt/c では python3 起動コストが支配的なため、単純なYAMLはbash 1-passで解決
#   同一セッション内の繰り返し呼び出しに変数キャッシュで対応

# パス解決（source元からの相対パス）
_cli_lookup_self="${BASH_SOURCE[0]}"
[[ "$_cli_lookup_self" != /* ]] && _cli_lookup_self="$PWD/$_cli_lookup_self"
_CLI_LOOKUP_DIR="${_cli_lookup_self%/scripts/lib/cli_lookup.sh}"
unset _cli_lookup_self
_CLI_LOOKUP_SETTINGS="${CLI_ADAPTER_SETTINGS:-${CLI_LOOKUP_SETTINGS:-${_CLI_LOOKUP_DIR}/config/settings.yaml}}"
_CLI_LOOKUP_PROFILES="${CLI_LOOKUP_PROFILES:-${_CLI_LOOKUP_DIR}/config/cli_profiles.yaml}"

# キャッシュ（連想配列、bash 4+）
# re-source時にキャッシュをクリアし、declare -gAでグローバルスコープに宣言
# （関数内からsourceされた場合でもグローバルになるよう -g フラグを使用）
unset _CLI_LOOKUP_TYPE_CACHE _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null
declare -gA _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || declare -A _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || true
declare -gA _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || declare -A _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || true

# --- 内部ヘルパー ---

_cli_lookup_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    REPLY="$s"
}

_cli_lookup_strip_inline_comment() {
    local s="$1"
    case "$s" in
        \"*\"|\'*\') REPLY="$s" ;;
        *) REPLY="${s%%#*}" ;;
    esac
}

_cli_lookup_unquote() {
    local s="$1"
    if [[ ${#s} -ge 2 ]]; then
        case "$s" in
            \"*\") s="${s#\"}"; s="${s%\"}"; s="${s//\\\"/\"}" ;;
            \'*\') s="${s#\'}"; s="${s%\'}" ;;
        esac
    fi
    REPLY="$s"
}

_cli_lookup_normalize_scalar() {
    local s="$1"
    _cli_lookup_trim "$s"
    s="$REPLY"
    _cli_lookup_strip_inline_comment "$s"
    s="$REPLY"
    _cli_lookup_trim "$s"
    s="$REPLY"
    _cli_lookup_unquote "$s"
    s="$REPLY"
    _cli_lookup_trim "$s"
}

# _cli_lookup_settings_get <agent_name> <field> <default>
# settings.yaml の cli.agents.<agent_name>.<field> を取得
_cli_lookup_settings_get() {
    local agent="$1"
    local field="$2"
    local default="$3"
    local settings_path="$_CLI_LOOKUP_SETTINGS"
    local in_cli=0
    local in_agents=0
    local in_agent=0
    local result=""
    local cli_default="$default"
    local line=""

    [[ -f "$settings_path" ]] || {
        printf '%s\n' "$default"
        return 0
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_cli -eq 0 ]]; then
            [[ "$line" == "cli:" ]] && in_cli=1
            continue
        fi

        if [[ $in_agents -eq 0 ]]; then
            if [[ "$line" == "  default: "* ]]; then
                _cli_lookup_normalize_scalar "${line#  default: }"
                cli_default="$REPLY"
            elif [[ "$line" == "  agents:" ]]; then
                in_agents=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ $in_agent -eq 0 ]]; then
            if [[ "$line" == "    ${agent}: "* ]]; then
                if [[ "$field" == "type" ]]; then
                    _cli_lookup_normalize_scalar "${line#*: }"
                    result="$REPLY"
                fi
                break
            elif [[ "$line" == "    ${agent}:" ]]; then
                in_agent=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ "$line" == "      ${field}: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"${field}": }"
            result="$REPLY"
            break
        elif [[ "$line" =~ ^"    "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi
    done < "$settings_path"

    if [[ "$field" == "type" ]]; then
        printf '%s\n' "${result:-$cli_default}"
    else
        printf '%s\n' "${result:-$default}"
    fi
}

# _cli_lookup_profile_get <cli_type> <key>
# cli_profiles.yaml の profiles.<cli_type>.<key> を取得
_cli_lookup_profile_get() {
    local cli_type="$1"
    local key="$2"
    local profiles_path="$_CLI_LOOKUP_PROFILES"
    local in_profiles=0
    local in_type=0
    local in_list=0
    local result=""
    local line=""
    local trimmed=""
    local item=""
    local items=()

    [[ -f "$profiles_path" ]] || {
        printf '\n'
        return 0
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_profiles -eq 0 ]]; then
            [[ "$line" == "profiles:" ]] && in_profiles=1
            continue
        fi

        _cli_lookup_trim "$line"
        trimmed="$REPLY"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        if [[ $in_type -eq 0 ]]; then
            if [[ "$line" == "  ${cli_type}:" ]]; then
                in_type=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ $in_list -eq 1 ]]; then
            if [[ "$line" == "      - "* ]]; then
                _cli_lookup_normalize_scalar "${line#      - }"
                item="$REPLY"
                items+=("$item")
                continue
            fi

            if [[ ${#items[@]} -gt 0 ]]; then
                local joined=""
                local list_item=""
                for list_item in "${items[@]}"; do
                    [[ -n "$joined" ]] && joined+="|"
                    joined+="$list_item"
                done
                printf '%s\n' "$joined"
                return 0
            fi
            break
        fi

        if [[ "$line" == "    ${key}: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"${key}": }"
            result="$REPLY"
            printf '%s\n' "$result"
            return 0
        elif [[ "$line" == "    ${key}:" ]]; then
            in_list=1
        elif [[ "$line" =~ ^"  "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi
    done < "$profiles_path"

    if [[ $in_list -eq 1 && ${#items[@]} -gt 0 ]]; then
        local joined=""
        local list_item=""
        for list_item in "${items[@]}"; do
            [[ -n "$joined" ]] && joined+="|"
            joined+="$list_item"
        done
        printf '%s\n' "$joined"
        return 0
    fi

    printf '\n'
}

# --- 公開API ---

# cli_type <agent_name>
# settings.yaml の cli.agents.<name>.type を返す。未定義なら cli.default → "claude"
cli_type() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        echo "claude"
        return 0
    fi

    # キャッシュ確認
    if [[ -n "${_CLI_LOOKUP_TYPE_CACHE[$agent]+x}" ]]; then
        echo "${_CLI_LOOKUP_TYPE_CACHE[$agent]}"
        return 0
    fi

    local result=""
    # L821: pane実態が一次情報。settings.yamlは二次情報(multi-CLIで動的変更される)
    if [[ -n "${TMUX:-}" ]]; then
        local _pane_idx
        _pane_idx=$(tmux list-panes -t "${TMUX_WINDOW:-shogun:2}" -F '#{pane_index} #{@agent_id}' 2>/dev/null \
            | awk -v a="$agent" '$2==a {print $1; exit}')
        if [[ -n "$_pane_idx" ]]; then
            local _cmd
            _cmd=$(tmux display-message -t "${TMUX_WINDOW:-shogun:2}.${_pane_idx}" -p '#{pane_current_command}' 2>/dev/null)
            case "$_cmd" in
                node) result="codex" ;;
                claude) result="claude" ;;
            esac
        fi
    fi
    # tmux外 or pane未検出時はsettings.yamlフォールバック
    if [[ -z "$result" ]]; then
        result=$(_cli_lookup_settings_get "$agent" "type" "claude")
    fi
    # 不正なCLI種別はclaude にフォールバック
    case "$result" in
        claude|codex|copilot|kimi) ;;
        *) result="claude" ;;
    esac
    _CLI_LOOKUP_TYPE_CACHE[$agent]="$result"
    echo "$result"
}

# cli_profile_get <agent_name> <key>
# settings.yaml → type特定 → cli_profiles.yaml から任意のキーを取得
# settings.yaml にエージェント個別の <key> があればそちらを優先（pane単位オーバーライド）
cli_profile_get() {
    local agent="$1"
    local key="$2"

    # キャッシュ確認
    local cache_key="${agent}:${key}"
    if [[ -n "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]+x}" ]]; then
        echo "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]}"
        return 0
    fi

    # settings.yaml の個別オーバーライドを先に確認（pane単位切替）
    local override
    override=$(_cli_lookup_settings_get "$agent" "$key" "")
    if [[ -n "$override" ]]; then
        _CLI_LOOKUP_PROFILE_CACHE[$cache_key]="$override"
        echo "$override"
        return 0
    fi

    local ct
    ct=$(cli_type "$agent")
    local result
    result=$(_cli_lookup_profile_get "$ct" "$key")
    _CLI_LOOKUP_PROFILE_CACHE[$cache_key]="$result"
    echo "$result"
}

# cli_profile_get_for_type <cli_type> <key>
# CLI typeを直接指定してcli_profiles.yamlからプロファイル値を取得
# agent名→settings.yaml→type解決をスキップする（ランタイムオーバーライド用）
cli_profile_get_for_type() {
    local cli_type="$1"
    local key="$2"
    _cli_lookup_profile_get "$cli_type" "$key"
}

# cli_model_display <agent_name>
# settings.yamlのmodel_nameからユーザーフレンドリーな表示名を導出
# claude-opus-4-6 → "Opus 4.6", claude-sonnet-4-6 → "Sonnet 4.6", gpt-5.5 → "gpt-5.5"
cli_model_display() {
    local agent="$1"
    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "")
    if [[ -z "$model_name" ]]; then
        return 1
    fi
    case "$model_name" in
        claude-fable-5*)    echo "Fable 5" ;;
        fable-5*)           echo "Fable 5" ;;
        fable*)             echo "Fable 5" ;;
        claude-opus-4-8*)    echo "Opus 4.8" ;;
        opus-4-8*)           echo "Opus 4.8" ;;
        claude-opus-4-6*)    echo "Opus 4.6" ;;
        opus-4-6*)           echo "Opus 4.6" ;;
        claude-opus-4*)      echo "Opus 4" ;;
        opus-4*)             echo "Opus 4" ;;
        claude-sonnet-5*)    echo "Sonnet 5" ;;
        sonnet-5*)           echo "Sonnet 5" ;;
        claude-sonnet-4-6*)  echo "Sonnet 4.6" ;;
        sonnet-4-6*)         echo "Sonnet 4.6" ;;
        claude-sonnet-4*)    echo "Sonnet 4" ;;
        sonnet-4*)           echo "Sonnet 4" ;;
        claude-haiku-4-5*)   echo "Haiku 4.5" ;;
        haiku-4-5*)          echo "Haiku 4.5" ;;
        claude-haiku-4*)     echo "Haiku 4" ;;
        haiku-4*)            echo "Haiku 4" ;;
        gpt-5.6-sol*)        echo "GPT 5.6 Sol" ;;
        gpt-5.6-terra*)      echo "GPT 5.6 Terra" ;;
        gpt-5.6-luna*)       echo "GPT 5.6 Luna" ;;
        gpt-5.6*)            echo "GPT 5.6" ;;
        gpt-5.5*)            echo "GPT 5.5" ;;
        *)                   echo "$model_name" ;;
    esac | awk -v raw="$model_name" '
        {
            effort = ""
            if (raw ~ /-(xhigh|high|medium|low)$/) {
                effort = raw
                sub(/^.*-/, "", effort)
            }
            if (effort != "" && $0 != raw && $0 !~ (" " effort "$")) {
                print $0 " " effort
            } else {
                print
            }
        }
    '
}

# _cli_launch_read_settings <agent_name>
# settings.yaml を1回のみ読み、type と model_name を
# _CLI_LAUNCH_TYPE / _CLI_LAUNCH_MODEL に設定する
# （サブシェル不使用 — cli_launch_cmd 内からの直接呼び出し専用）
_cli_launch_read_settings() {
    local agent="$1"
    local settings_path="$_CLI_LOOKUP_SETTINGS"
    local in_cli=0 in_agents=0 in_agent=0
    local cli_default="claude"
    local line=""

    _CLI_LAUNCH_TYPE="" _CLI_LAUNCH_MODEL="" _CLI_LAUNCH_SERVICE_TIER="" _CLI_LAUNCH_CMD_OVERRIDE=""

    [[ -f "$settings_path" ]] || { _CLI_LAUNCH_TYPE="$cli_default"; return 0; }

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_cli -eq 0 ]]; then
            [[ "$line" == "cli:" ]] && in_cli=1
            continue
        fi

        if [[ $in_agents -eq 0 ]]; then
            if [[ "$line" == "  default: "* ]]; then
                _cli_lookup_normalize_scalar "${line#  default: }"
                cli_default="$REPLY"
            elif [[ "$line" == "  agents:" ]]; then
                in_agents=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ $in_agent -eq 0 ]]; then
            if [[ "$line" == "    ${agent}: "* ]]; then
                _cli_lookup_normalize_scalar "${line#*: }"
                _CLI_LAUNCH_TYPE="$REPLY"
                break
            elif [[ "$line" == "    ${agent}:" ]]; then
                in_agent=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ "$line" == "      type: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"type": }"
            _CLI_LAUNCH_TYPE="$REPLY"
        elif [[ "$line" == "      model_name: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"model_name": }"
            _CLI_LAUNCH_MODEL="$REPLY"
        elif [[ "$line" == "      service_tier: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"service_tier": }"
            _CLI_LAUNCH_SERVICE_TIER="$REPLY"
        elif [[ "$line" == "      launch_cmd: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"launch_cmd": }"
            _CLI_LAUNCH_CMD_OVERRIDE="$REPLY"
        elif [[ "$line" =~ ^"    "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi
    done < "$settings_path"

    case "${_CLI_LAUNCH_TYPE:-}" in
        claude|codex|copilot|kimi) ;;
        *) _CLI_LAUNCH_TYPE="$cli_default" ;;
    esac
}

# _cli_launch_read_profile <cli_type>
# cli_profiles.yaml を1回のみ読み、launch_cmd と launch_args を
# _CLI_LAUNCH_CMD / _CLI_LAUNCH_ARGS に設定する
# （サブシェル不使用 — cli_launch_cmd 内からの直接呼び出し専用）
_cli_launch_read_profile() {
    local cli_type="$1"
    local profiles_path="$_CLI_LOOKUP_PROFILES"
    local in_profiles=0 in_type=0 in_list=0
    local list_key="" line="" trimmed=""
    local items=()

    _CLI_LAUNCH_CMD="" _CLI_LAUNCH_ARGS=""

    [[ -f "$profiles_path" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_profiles -eq 0 ]]; then
            [[ "$line" == "profiles:" ]] && in_profiles=1
            continue
        fi

        _cli_lookup_trim "$line"
        trimmed="$REPLY"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        if [[ $in_type -eq 0 ]]; then
            if [[ "$line" == "  ${cli_type}:" ]]; then
                in_type=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ $in_list -eq 1 ]]; then
            if [[ "$line" == "      - "* ]]; then
                _cli_lookup_normalize_scalar "${line#      - }"
                items+=("$REPLY")
                continue
            fi
            local joined="" list_item=""
            for list_item in "${items[@]}"; do
                [[ -n "$joined" ]] && joined+="|"
                joined+="$list_item"
            done
            [[ "$list_key" == "launch_cmd"  ]] && _CLI_LAUNCH_CMD="$joined"
            [[ "$list_key" == "launch_args" ]] && _CLI_LAUNCH_ARGS="$joined"
            items=() in_list=0
        fi

        if [[ "$line" == "    launch_cmd: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"launch_cmd": }"
            _CLI_LAUNCH_CMD="$REPLY"
        elif [[ "$line" == "    launch_cmd:" ]]; then
            list_key="launch_cmd" in_list=1 items=()
        elif [[ "$line" == "    launch_args: "* ]]; then
            _cli_lookup_normalize_scalar "${line#*"launch_args": }"
            _CLI_LAUNCH_ARGS="$REPLY"
        elif [[ "$line" == "    launch_args:" ]]; then
            list_key="launch_args" in_list=1 items=()
        elif [[ "$line" =~ ^"  "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi
    done < "$profiles_path"

    if [[ $in_list -eq 1 && ${#items[@]} -gt 0 ]]; then
        local joined="" list_item=""
        for list_item in "${items[@]}"; do
            [[ -n "$joined" ]] && joined+="|"
            joined+="$list_item"
        done
        [[ "$list_key" == "launch_cmd"  ]] && _CLI_LAUNCH_CMD="$joined"
        [[ "$list_key" == "launch_args" ]] && _CLI_LAUNCH_ARGS="$joined"
    fi
}

# cli_launch_cmd <agent_name>
# 起動コマンド文字列を返す
# codex型エージェントかつmodel_nameがgpt-X.X-{effort}形式なら
# -c model_reasoning_effort={effort} を自動追加する
#
# 最適化: settings.yaml/cli_profiles.yamlをそれぞれ1回のみ読む
# （旧実装: cli_profile_get×2 + _cli_lookup_settings_get = サブシェル~9個+ファイル読込5回）
cli_launch_cmd() {
    local agent="$1"

    # settings.yaml を1回のみ読み込み type / model_name / service_tier を取得
    _cli_launch_read_settings "$agent"
    local model_name="$_CLI_LAUNCH_MODEL"
    local service_tier="$_CLI_LAUNCH_SERVICE_TIER"

    # cli_profiles.yaml を1回のみ読み込み launch_cmd と launch_args を取得
    _cli_launch_read_profile "$_CLI_LAUNCH_TYPE"
    local base_cmd="$_CLI_LAUNCH_CMD"
    local static_args="$_CLI_LAUNCH_ARGS"

    # settings.yaml per-agent launch_cmd override (2層SSOT: profile=デフォルト, settings=個別)
    if [[ -n "${_CLI_LAUNCH_CMD_OVERRIDE:-}" ]]; then
        base_cmd="$_CLI_LAUNCH_CMD_OVERRIDE"
    fi

    # model_nameからCLI引数を自動生成
    local extra_args=""
    if [[ "$model_name" == gpt-* ]]; then
        # Codex: gpt-X.X-{effort} → -c model_reasoning_effort={effort}
        local effort="${model_name##*-}"
        case "$effort" in
            medium|low|high)
                extra_args="-c model_reasoning_effort=${effort}"
                ;;
        esac
        # Codex: settings.yaml の service_tier フィールドで per-agent 上書き
        case "$service_tier" in
            fast|auto|default)
                extra_args="${extra_args:+$extra_args }-c service_tier=${service_tier}"
                ;;
        esac
    elif [[ "$model_name" == claude-* && "$_CLI_LAUNCH_TYPE" == "claude" ]]; then
        # Claude Code: claude-sonnet-4-6 → --model sonnet, claude-haiku-4-5 → --model haiku
        # claude-opus-4-6はデフォルトのため指定不要(指定しても害はないが冗長)
        case "$model_name" in
            claude-sonnet-*)  extra_args="--model sonnet" ;;
            claude-haiku-*)   extra_args="--model haiku" ;;
        esac
    fi

    # cli_profiles.yaml の launch_args (静的追加引数) をマージ
    if [[ -n "$static_args" && "$static_args" != '""' ]]; then
        extra_args="${static_args}${extra_args:+ $extra_args}"
    fi

    if [[ -n "$extra_args" ]]; then
        printf '%s %s\n' "$base_cmd" "$extra_args"
    else
        printf '%s\n' "$base_cmd"
    fi
}

# apply_model_name_tag <agent_name> <pane_target>
# LS078(真実の在処不一致)根治: settings.yaml cli.agents.<agent>.model_name の
# 文字列をそのまま(整形・表示名変換なし)tmux @model_name へ焼き込む。
# バナーパース(detect_real_model)や表示名変換(cli_model_display)は経由しない。
# 呼び出しチョークポイントはagent_respawn.sh/switch_cli_mode.sh/ninja_monitor.shの
# 各respawn経路のみ(respawn直後に1回だけ呼ぶ)。
# 突合結果(settings.yaml値 vs 焼込み後の実tmux値)をログへ記録する。
# 戻り値: 0=model_name設定済みかつ焼込み一致 / 1=model_name未設定 or 焼込み不一致
apply_model_name_tag() {
    local agent="$1"
    local target="$2"
    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "")
    [[ -z "$model_name" ]] && return 1

    tmux set-option -p -t "$target" @model_name "$model_name" 2>/dev/null || true

    local actual result
    actual=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")
    if [[ "$actual" == "$model_name" ]]; then
        result="match"
    else
        result="mismatch"
    fi

    local log_file="${MODEL_NAME_TAG_LOG:-${_CLI_LOOKUP_DIR}/logs/model_name_tag_verify.log}"
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    printf '%s agent=%s pane=%s settings_model=%s tmux_model=%s result=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$target" "$model_name" "$actual" "$result" \
        >> "$log_file" 2>/dev/null || true

    [[ "$result" == "match" ]]
}

# codex_config_apply_agent <agent_name>
# settings.yamlのmodel_name/service_tierからconfig.tomlを一時切替する。
# SSOT: この関数がconfig.toml per-agent切替の唯一の実装(2層SSOT: settings.yaml→config.toml)
_CODEX_CFG_BACKUP_MODEL=""
_CODEX_CFG_BACKUP_EFFORT=""
_CODEX_CFG_BACKUP_TIER=""
_CODEX_CFG_CHANGED=false

codex_config_apply_agent() {
    local agent="$1"
    local cfg="$HOME/.codex/config.toml"
    [[ ! -f "$cfg" ]] && return 1
    _CODEX_CFG_CHANGED=false

    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "")
    [[ -z "$model_name" || "$model_name" != gpt-* ]] && return 0

    _CODEX_CFG_BACKUP_MODEL=$(grep -oP '^model\s*=\s*"\K[^"]+' "$cfg" || true)
    # 自己修復(2026-08-26 23:42 殿指摘): config.toml の model に effort 接尾辞付きラベル
    # (例 gpt-5.6-luna-high)が手で書かれると Codex が 400 "model is not supported" で全忍者停止する。
    # model と effort は別キー。接尾辞付きなら model を剥がし effort へ移す(単一writerで構造的に防ぐ)。
    # BASH_REMATCHはninja_monitor内のtrapで潰される(d3b1b85be同型・2026-08-27 00:00 tobisaru実証)ため
    # 正規表現ではなくパラメータ展開で分解する。
    local _heal_suffix="${_CODEX_CFG_BACKUP_MODEL##*-}" _heal_base="${_CODEX_CFG_BACKUP_MODEL%-*}"
    if [[ "$_CODEX_CFG_BACKUP_MODEL" == gpt-*-* ]]; then
        case "$_heal_suffix" in
            low|medium|high|xhigh)
                sed -i "s|^model = \".*\"|model = \"${_heal_base}\"|" "$cfg"
                sed -i "s|^model_reasoning_effort = \".*\"|model_reasoning_effort = \"${_heal_suffix}\"|" "$cfg"
                echo "[cli_lookup] config.toml model '${_CODEX_CFG_BACKUP_MODEL}' → model=${_heal_base} effort=${_heal_suffix} (effort接尾辞を自己修復)" >&2
                _CODEX_CFG_BACKUP_MODEL="$_heal_base"
                _CODEX_CFG_CHANGED=true ;;
        esac
    fi
    _CODEX_CFG_BACKUP_EFFORT=$(grep -oP '^model_reasoning_effort\s*=\s*"\K[^"]+' "$cfg" || true)
    _CODEX_CFG_BACKUP_TIER=$(grep -oP '^service_tier\s*=\s*"\K[^"]+' "$cfg" || true)

    local target_effort="" target_model=""
    # BASH_REMATCH依存を排除(trapで潰され model_name 全体が model に書かれる事故 2026-08-27 00:00)
    local suffix="${model_name##*-}" base="${model_name%-*}"
    case "$suffix" in
        low|medium|high|xhigh) target_effort="$suffix"; target_model="$base" ;;
        *) target_model="$model_name" ;;
    esac

    local target_tier
    target_tier=$(_cli_lookup_settings_get "$agent" "service_tier" "default")

    if [[ -n "$target_model" && "$target_model" != "$_CODEX_CFG_BACKUP_MODEL" ]]; then
        sed -i "s|^model = \".*\"|model = \"$target_model\"|" "$cfg"
        _CODEX_CFG_CHANGED=true
    fi
    if [[ -n "$target_effort" && "$target_effort" != "$_CODEX_CFG_BACKUP_EFFORT" ]]; then
        sed -i "s|^model_reasoning_effort = \".*\"|model_reasoning_effort = \"$target_effort\"|" "$cfg"
        _CODEX_CFG_CHANGED=true
    fi
    if [[ "$target_tier" != "$_CODEX_CFG_BACKUP_TIER" ]]; then
        sed -i "s|^service_tier = \".*\"|service_tier = \"$target_tier\"|" "$cfg"
        _CODEX_CFG_CHANGED=true
    fi
    return 0
}
