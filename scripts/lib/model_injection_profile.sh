#!/usr/bin/env bash
# model_injection_profile.sh — model label → Level5 injection intensity profile.

model_injection_profile_family() {
    local label="${1:-}" low
    low="${label,,}"
    low="${low//-/ }"
    low="${low//_/ }"

    if [[ "$low" == *gpt* || "$low" == *codex* ]]; then
        printf '%s\n' "gpt"
    elif [[ "$low" == *sonnet* ]]; then
        printf '%s\n' "sonnet"
    elif [[ "$low" == *haiku* ]]; then
        printf '%s\n' "haiku"
    elif [[ "$low" == *opus* ]]; then
        printf '%s\n' "opus"
    else
        printf '%s\n' "unknown"
    fi
}

model_injection_profile_intensity() {
    case "$(model_injection_profile_family "${1:-}")" in
        gpt|sonnet|haiku) printf '%s\n' "max" ;;
        opus) printf '%s\n' "standard" ;;
        *) printf '%s\n' "standard" ;;
    esac
}

model_injection_profile_text() {
    local label="${1:-unknown}" family intensity
    family="$(model_injection_profile_family "$label")"
    intensity="$(model_injection_profile_intensity "$label")"
    cat <<EOF
model_injection_profile:
  model_label: ${label}
  family: ${family}
  injection_intensity: ${intensity}
  protocol: T5弱LLM構造化プロトコル
  rule: settings.yaml/model実態に応じ、GPT/Sonnet/Haikuは明示テンプレート最大、Opusは標準注入
  report_contract: binary_checks全result=yes/no、lessons_useful全reason、files_modifiedはpath形式、gate_report_format実行を省略しない
EOF
}
