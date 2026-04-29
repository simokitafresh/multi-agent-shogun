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

    local result
    result=$(_cli_lookup_settings_get "$agent" "type" "claude")
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
cli_profile_get() {
    local agent="$1"
    local key="$2"

    # キャッシュ確認
    local cache_key="${agent}:${key}"
    if [[ -n "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]+x}" ]]; then
        echo "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]}"
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
        claude-opus-4-6*)    echo "Opus 4.6" ;;
        claude-opus-4*)      echo "Opus 4" ;;
        claude-sonnet-4-6*)  echo "Sonnet 4.6" ;;
        claude-sonnet-4*)    echo "Sonnet 4" ;;
        claude-haiku-4-5*)   echo "Haiku 4.5" ;;
        claude-haiku-4*)     echo "Haiku 4" ;;
        *)                   echo "$model_name" ;;
    esac
}

# cli_launch_cmd <agent_name>
# 起動コマンド文字列を返す
# codex型エージェントかつmodel_nameがgpt-X.X-{effort}形式なら
# -c model_reasoning_effort={effort} を自動追加する
cli_launch_cmd() {
    local agent="$1"
    local base_cmd
    base_cmd=$(cli_profile_get "$agent" "launch_cmd")

    # model_nameからeffortを自動抽出 (gpt-X.X-{effort} パターン)
    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "")
    local extra_args=""
    if [[ "$model_name" == gpt-* ]]; then
        local effort="${model_name##*-}"
        case "$effort" in
            medium|low|high)
                extra_args="-c model_reasoning_effort=${effort}"
                ;;
        esac
    fi

    # cli_profiles.yaml の launch_args (静的追加引数) をマージ
    local static_args
    static_args=$(cli_profile_get "$agent" "launch_args")
    if [[ -n "$static_args" && "$static_args" != '""' ]]; then
        extra_args="${static_args}${extra_args:+ $extra_args}"
    fi

    if [[ -n "$extra_args" ]]; then
        printf '%s %s\n' "$base_cmd" "$extra_args"
    else
        printf '%s\n' "$base_cmd"
    fi
}
