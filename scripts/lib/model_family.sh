#!/usr/bin/env bash
# model_family.sh — model label → stable analytics family helpers.

MODEL_FAMILY_HELPER_VERSION="2"
MODEL_FAMILY_OPUS_46="opus_4_6"
MODEL_FAMILY_GPT_5="gpt_5"
MODEL_FAMILY_CODEX="codex"
MODEL_FAMILY_HAIKU="haiku"
MODEL_FAMILY_OPUS="opus"
MODEL_FAMILY_SONNET="sonnet"
MODEL_FAMILY_UNKNOWN="unknown"
MODEL_FAMILY_TOKEN_OPUS="opus"
MODEL_FAMILY_TOKEN_GPT="gpt"
MODEL_FAMILY_TOKEN_CODEX="codex"
MODEL_FAMILY_TOKEN_SONNET="sonnet"
MODEL_FAMILY_VERSION_46_DOT="4.6"
MODEL_FAMILY_VERSION_46_SPACE="4 6"
MODEL_FAMILY_VERSION_54_DOT="5.4"
MODEL_FAMILY_VERSION_54_SPACE="5 4"
MODEL_FAMILY_VERSION_55_DOT="5.5"
MODEL_FAMILY_VERSION_55_SPACE="5 5"
MODEL_FAMILY_DISPLAY_OPUS="Opus"
MODEL_FAMILY_DISPLAY_SONNET="Sonnet"
MODEL_FAMILY_DISPLAY_HAIKU="Haiku"

model_family_from_label() {
    local label="$1" low slug
    low="${label,,}"
    low="${low//-/ }"
    low="${low//_/ }"
    if [[ "$low" == *opus* && ( "$low" == *4.6* || "$low" == *4\ 6* ) ]]; then
        printf '%s\n' "$MODEL_FAMILY_OPUS_46"
        return 0
    fi
    if [[ ( "$low" == *gpt* || "$low" == *codex* ) && ( "$low" == *5.4* || "$low" == *5\ 4* || "$low" == *5.5* || "$low" == *5\ 5* ) ]]; then
        printf '%s\n' "$MODEL_FAMILY_GPT_5"
        return 0
    fi
    if [[ "$low" == *sonnet* ]]; then
        printf '%s\n' "$MODEL_FAMILY_SONNET"
        return 0
    fi
    if [[ "$low" == *haiku* ]]; then
        printf '%s\n' "$MODEL_FAMILY_HAIKU"
        return 0
    fi
    if [[ "$low" == *opus* ]]; then
        printf '%s\n' "$MODEL_FAMILY_OPUS"
        return 0
    fi
    slug="${low//[^a-z0-9]/_}"
    slug="${slug#"${slug%%[!_]*}"}"
    slug="${slug%"${slug##*[!_]}"}"
    printf '%s\n' "${slug:-$MODEL_FAMILY_UNKNOWN}"
}

model_family_display_group() {
    case "$(model_family_from_label "$1")" in
        "$MODEL_FAMILY_GPT_5"|"$MODEL_FAMILY_CODEX"|gpt*) printf '%s\n' "Codex" ;;
        "$MODEL_FAMILY_HAIKU") printf '%s\n' "Haiku" ;;
        "$MODEL_FAMILY_SONNET") printf '%s\n' "Sonnet" ;;
        "$MODEL_FAMILY_OPUS"|"$MODEL_FAMILY_OPUS_46") printf '%s\n' "Opus" ;;
        *) printf '%s\n' "Claude" ;;
    esac
}

model_family_reset_group() {
    case "$(model_family_display_group "$1")" in
        Opus) printf '%s\n' "opus" ;;
        Sonnet) printf '%s\n' "sonnet" ;;
        Haiku) printf '%s\n' "haiku" ;;
        *) printf '%s\n' "claude" ;;
    esac
}

model_family_python_module_path() {
    local self="${BASH_SOURCE[0]}"
    [[ "$self" != /* ]] && self="$PWD/$self"
    printf '%s\n' "${self%/scripts/lib/model_family.sh}/scripts/lib"
}
