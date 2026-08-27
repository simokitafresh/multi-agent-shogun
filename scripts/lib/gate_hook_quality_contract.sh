#!/usr/bin/env bash
# semantic-links: [[品質検査の共通関数化三入口再利用]]
# gate/hook検知器品質の共有契約。呼出元は候補判定を渡し、本文評価を三入口で共用する。

gate_hook_quality_contract_action_text() {
    local block_text="${1:-}"
    printf '%s\n' "$block_text" | awk '
        function indent(line) { match(line, /[^[:space:]]/); return RSTART ? RSTART - 1 : length(line) }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; command_indent=indent($0); print; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; next }
        /^[[:space:]]*acceptance_criteria:[[:space:]]*$/ { in_ac=1; ac_indent=indent($0); print; next }
        /^[[:space:]]*acceptance_criteria:[[:space:]]*\[/ { sub(/^[[:space:]]*acceptance_criteria:[[:space:]]*/, ""); print; next }
        /^[[:space:]]*quality_gate:[[:space:]]*$/ { in_qg=1; qg_indent=indent($0); print; next }
        in_command && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= command_indent { in_command=0; next }
        in_ac && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= ac_indent { in_ac=0; next }
        in_qg && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= qg_indent { in_qg=0; next }
        in_command && indent($0) > command_indent { print; next }
        in_ac && indent($0) > ac_indent { print; next }
        in_qg && indent($0) > qg_indent { print; next }
    '
}

gate_hook_quality_contract_measurement_text() {
    local block_text="${1:-}"
    printf '%s\n' "$block_text" | awk '
        function indent(line) { match(line, /[^[:space:]]/); return RSTART ? RSTART - 1 : length(line) }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; command_indent=indent($0); print; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; next }
        /^[[:space:]]*acceptance_criteria:[[:space:]]*$/ { in_ac=1; ac_indent=indent($0); print; next }
        /^[[:space:]]*acceptance_criteria:[[:space:]]*\[/ { sub(/^[[:space:]]*acceptance_criteria:[[:space:]]*/, ""); print; next }
        /^[[:space:]]*quality_gate:[[:space:]]*$/ { in_qg=1; qg_indent=indent($0); print; next }
        in_command && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= command_indent { in_command=0; next }
        in_ac && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= ac_indent { in_ac=0; next }
        in_qg && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ && indent($0) <= qg_indent { in_qg=0; next }
        in_command && indent($0) > command_indent { print; next }
        in_ac && indent($0) > ac_indent { print; next }
        in_qg && indent($0) > qg_indent { print; next }
    '
}

# Keep the accepted FP vocabulary independent of grep's regex engine and the
# runner locale. Quoted case patterns are literal substring checks; the only
# glob metacharacters are the surrounding wildcards.
gate_hook_quality_contract_has_measurement_vocabulary() {
    local text="${1:-}"
    case "$text" in
        *"FP率"*|*"FP計"*|*"FP測"*|*"false_positive"*|*"false positive"*|\
        *"false-positive"*|*"falsepositive"*|*"偽陽性"*|*"誤発報"*|\
        *"誤BLOCK"*|*"誤遮断"*|*"detector_fp_rate"*|*"gate_fire_log"*|\
        *"loop_ledger"*|*"cmd_design_quality"*)
            return 0 ;;
    esac
    return 1
}

# Prints TSV: applicable\taction_conversion\tfp_measurement.
# Optional second argument is a candidate-detector function receiving block_text.
gate_hook_quality_contract_evaluate() {
    local block_text="${1:-}"
    local detector="${2:-gate_hook_quality_contract_default_candidate}"
    local action_text measurement_text action=pass measurement=pass

    [[ -n "$block_text" ]] || { printf 'no\tpass\tpass\n'; return 0; }
    "$detector" "$block_text" || { printf 'no\tpass\tpass\n'; return 0; }

    action_text="$(gate_hook_quality_contract_action_text "$block_text")"
    if ! printf '%s\n' "$action_text" | grep -qiE 'BLOCK|exit[[:space:]]+1|強制|自動実行|自動化|遮断|停止|失敗させ|必須化|止める'; then
        action=missing
    fi

    measurement_text="$(gate_hook_quality_contract_measurement_text "$block_text")"
    if ! gate_hook_quality_contract_has_measurement_vocabulary "$measurement_text"; then
        measurement=missing
    fi

    printf 'yes\t%s\t%s\n' "$action" "$measurement"
}

# Direct task YAMLs do not have cmd_save's metadata cache. Keep this conservative:
# gate/hook語と能動的な追加語が同時にある場合だけ共有検査を適用する。
gate_hook_quality_contract_default_candidate() {
    local block_text="${1:-}"
    printf '%s\n' "$block_text" | grep -qiE '(^|[^A-Za-z0-9_])(gate|hook)([^A-Za-z0-9_]|$)|ゲート|フック' || return 1
    printf '%s\n' "$block_text" | grep -qiE '追加|新設|導入|実装|作成|(^|[^A-Za-z0-9_])(append|add|new|create|introduce)([^A-Za-z0-9_]|$)' || return 1
    return 0
}
