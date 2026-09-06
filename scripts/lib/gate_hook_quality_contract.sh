#!/usr/bin/env bash
# semantic-links: [[品質検査の共通関数化三入口再利用]]
# gate/hook検知器品質の共有契約。呼出元は候補判定を渡し、本文評価を三入口で共用する。
# 加えて、変更scriptを参照する既存bats列挙契約(reference test contract)も共有する
# (cmd_karo_hotfix_reference_test_contract_20260906)。

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
# runner locale.  A variable-backed [[ ]] pattern treats the vocabulary as a
# literal substring.  Do not assign LC_ALL inside this function: under
# `bash -x`, Bash emits the expanded Japanese operand using the active locale,
# and a local C-locale assignment can corrupt the inherited UTF-8 xtrace
# stream.  Literal substring matching does not invoke regex or case-folding,
# so changing the caller's locale provides no determinism benefit here.
gate_hook_quality_contract_has_measurement_vocabulary() {
    local text="${1:-}"
    local term
    for term in \
        "FP率" "FP計" "FP測" "false_positive" "false positive" \
        "false-positive" "falsepositive" "偽陽性" "誤発報" \
        "誤BLOCK" "誤遮断" "detector_fp_rate" "gate_fire_log" \
        "loop_ledger" "cmd_design_quality"; do
        if [[ "$text" == *"$term"* ]]; then
            return 0
        fi
    done
    return 1
}

# The action-conversion side used `grep -qiE` with a mixed ASCII/Japanese
# alternation (case-insensitive, plus a `[[:space:]]+` quantifier for
# "exit 1"). L1660 already replaced the equivalent measurement-vocabulary
# grep with literal substring matching because grep's multibyte case-folding
# is locale/engine dependent; this action check was left on the old grep
# path and kept reintroducing the same class of failure. Mirror the fixed
# pattern here: fold only the ASCII case (`${var,,}` is safe for plain
# ASCII regardless of locale) and collapse literal whitespace bytes instead
# of relying on a regex quantifier, so no code path needs grep -i.
gate_hook_quality_contract_has_action_vocabulary() {
    local text="${1:-}"
    local lower="${text,,}"
    local collapsed
    collapsed="$(printf '%s' "$lower" | tr -s ' \t\n\r\f\v' ' ')"
    case "$collapsed" in
        *block*|*'exit 1'*) return 0 ;;
    esac
    local term
    for term in "強制" "自動実行" "自動化" "遮断" "停止" "失敗させ" "必須化" "止める"; do
        if [[ "$text" == *"$term"* ]]; then
            return 0
        fi
    done
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
    if ! gate_hook_quality_contract_has_action_vocabulary "$action_text"; then
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

# --- Reference test enumeration (cmd_karo_hotfix_reference_test_contract_20260906) ---
# F-11/F-12/F-13/F-16: a hotfix to a shared script repeatedly broke an existing
# bats contract that referenced the script only as a literal path string inside
# a test body (e.g. `c2a="$BATS_TEST_DIRNAME/../../scripts/publisher_c2a_merge.sh"`),
# never via `source`/`bash`/`.`. scripts/test_select.sh's naming-convention and
# source/bash-invocation layers do not see a bare path assignment, so the
# git-pre-commit D0 (no task) affected-test run silently skipped the contract
# test and CI caught the regression instead. This scans test bodies for the
# literal script path/basename directly and independently of test_select.sh's
# own mapping, to close that class of gap at the existing pre-commit boundary
# without duplicating or replacing test_select.sh's selection mechanism.
gate_hook_quality_contract_reference_test_matches() {
    local script_path="${1:-}" repo_root="${2:-}"
    [[ -n "$script_path" && -n "$repo_root" ]] || return 0
    local test_dir="$repo_root/tests/unit"
    [[ -d "$test_dir" ]] || return 0
    local base="${script_path##*/}"
    # An empty match set is a valid outcome (no existing bats references the
    # script), not a failure: grep exits 1 on no-match. Under a caller's
    # `set -e -o pipefail` (git-pre-commit.sh itself does not set either, but
    # callers/tests may), `set -e` aborts as soon as a pipeline reports
    # non-zero -- it does not wait for a later `return 0` to override that,
    # so each grep must be individually defused with `|| true` rather than
    # relying on a trailing return.
    {
        grep -rlF -- "$script_path" "$test_dir" --include='test_*.bats' 2>/dev/null || true
        grep -rlF -- "$base" "$test_dir" --include='test_*.bats' 2>/dev/null || true
    } | sed "s|^$repo_root/||" | sort -u
    return 0
}
