#!/bin/bash
# yaml_check_codex.sh - queue YAML schema integrity check (Codex implementation)
# Usage: bash scripts/yaml_check_codex.sh <yaml_file>

set -u
set -o pipefail

if [ $# -ne 1 ]; then
  echo "Usage: bash scripts/yaml_check_codex.sh <yaml_file>" >&2
  exit 1
fi

YAML_FILE="$1"
if [ ! -f "$YAML_FILE" ]; then
  echo "FAIL: $YAML_FILE (file not found)"
  exit 1
fi

# Single awk pass: CRLF handling + schema detection + all field checks in one invocation.
# Replaces: mktemp + sed + 3 grep (schema) + 21+ individual awk/grep helper calls.
awk -v yaml_file="$YAML_FILE" '
BEGIN { viol_n = 0; schema = "unknown"; cur_top = ""; last_nested = "" }

{ gsub(/\r$/, "") }

# --- Top-level key with empty value (section header) ---
/^[a-zA-Z_][a-zA-Z_0-9]*:[[:space:]]*$/ {
    k = $0; sub(/:.*/, "", k)
    top_present[k] = 1; top_val[k] = ""
    cur_top = k; last_nested = ""
    if (k == "task")    { schema = "task";          cur_root = "task" }
    if (k == "report")  { schema = "report_nested"; cur_root = "report" }
    if (k == "worker_id" && schema == "unknown") schema = "report_flat"
    next
}

# --- Top-level key with inline value ---
/^[a-zA-Z_][a-zA-Z_0-9]*:/ {
    k = $0; sub(/:.*/, "", k)
    v = $0; sub(/^[^:]+:[[:space:]]*/, "", v)
    top_present[k] = 1; top_val[k] = v
    cur_top = k; last_nested = ""
    if (k == "worker_id" && schema == "unknown") schema = "report_flat"
    if (v ~ /^\[/) top_arr[k] = 1
    next
}

# --- 2-space nested key with empty value ---
/^  [a-zA-Z_][a-zA-Z_0-9]*:[[:space:]]*$/ {
    k = $0; sub(/^  /, "", k); sub(/:.*/, "", k)
    nested_present[cur_top SUBSEP k] = 1; nested_val[cur_top SUBSEP k] = ""
    last_nested = k
    next
}

# --- 2-space nested key with inline value ---
/^  [a-zA-Z_][a-zA-Z_0-9]*:/ {
    k = $0; sub(/^  /, "", k); sub(/:.*/, "", k)
    v = $0; sub(/^  [^:]+:[[:space:]]*/, "", v)
    nested_present[cur_top SUBSEP k] = 1; nested_val[cur_top SUBSEP k] = v
    last_nested = k
    if (v ~ /^\[/) nested_arr[cur_top SUBSEP k] = 1
    # found: true|false under a section (e.g. lesson_candidate.found)
    if (k == "found" && v ~ /^(true|false)[[:space:]]*$/) found_bool[cur_top] = 1
    next
}

# --- 2-space array item (  - ...) ---
/^  -/ {
    if (last_nested != "")
        nested_arr[cur_top SUBSEP last_nested] = 1
    else
        top_arr[cur_top] = 1
    next
}

END {
    # ============================================================
    # Task schema
    # ============================================================
    if (schema == "task") {
        task_variant = "stub"
        if ((cur_root SUBSEP "bloom_level")         in nested_present ||
            (cur_root SUBSEP "description")          in nested_present ||
            (cur_root SUBSEP "acceptance_criteria")  in nested_present)
            task_variant = "full"
        schema_str = "task/" task_variant

        # Required string keys
        n = split("task_id parent_cmd task_type assigned_to status title", req, " ")
        for (i = 1; i <= n; i++) {
            k = req[i]
            if (!((cur_root SUBSEP k) in nested_present))
                violations[viol_n++] = "missing required key: task." k
            # check_nested_string: fail when not found OR value starts with [{
            if (!((cur_root SUBSEP k) in nested_present) || nested_val[cur_root SUBSEP k] ~ /^[\[{]/)
                violations[viol_n++] = "type mismatch: task." k " must be string"
        }

        if (task_variant == "full") {
            # Required array keys (full variant)
            n = split("acceptance_criteria blocked_by related_lessons", req, " ")
            for (i = 1; i <= n; i++) {
                k = req[i]
                if (!((cur_root SUBSEP k) in nested_present))
                    violations[viol_n++] = "missing required key: task." k
                if (!((cur_root SUBSEP k) in nested_arr))
                    violations[viol_n++] = "type mismatch: task." k " must be array"
            }
        } else {
            # Stub variant: only check type if key is present
            n = split("acceptance_criteria blocked_by related_lessons", req, " ")
            for (i = 1; i <= n; i++) {
                k = req[i]
                if ((cur_root SUBSEP k) in nested_present &&
                    !((cur_root SUBSEP k) in nested_arr))
                    violations[viol_n++] = "type mismatch: task." k " must be array"
            }
        }
    }

    # ============================================================
    # Report flat schema
    # ============================================================
    else if (schema == "report_flat") {
        schema_str = "report_flat"

        # Required key presence
        n = split("worker_id task_id parent_cmd timestamp status result lesson_candidate lesson_referenced skill_candidate decision_candidate", req, " ")
        for (i = 1; i <= n; i++) {
            k = req[i]
            if (!(k in top_present))
                violations[viol_n++] = "missing required key: " k
        }

        # Required string types (check_top_string: fail when absent OR value starts with [{)
        n = split("worker_id task_id parent_cmd timestamp status", req, " ")
        for (i = 1; i <= n; i++) {
            k = req[i]
            if (!(k in top_present) || top_val[k] ~ /^[\[{]/)
                violations[viol_n++] = "type mismatch: " k " must be string"
        }

        # lesson_referenced must be array (check_top_array: fail when absent OR not array)
        if (!("lesson_referenced" in top_arr))
            violations[viol_n++] = "type mismatch: lesson_referenced must be array"

        # found: bool for section keys
        n = split("lesson_candidate skill_candidate decision_candidate", req, " ")
        for (i = 1; i <= n; i++) {
            k = req[i]
            if (!(k in found_bool))
                violations[viol_n++] = "type mismatch: " k ".found must be boolean"
        }
    }

    # ============================================================
    # Report nested schema
    # ============================================================
    else if (schema == "report_nested") {
        schema_str = "report_nested"
        n = split("task_id parent_cmd status timestamp title", req, " ")
        for (i = 1; i <= n; i++) {
            k = req[i]
            if (!((cur_root SUBSEP k) in nested_present))
                violations[viol_n++] = "missing required key: report." k
            if (!((cur_root SUBSEP k) in nested_present) || nested_val[cur_root SUBSEP k] ~ /^[\[{]/)
                violations[viol_n++] = "type mismatch: report." k " must be string"
        }
    }

    # ============================================================
    # Unknown schema
    # ============================================================
    else {
        schema_str = "unknown"
        violations[viol_n++] = "unknown schema type (expected task/report)"
    }

    # ============================================================
    # Output
    # ============================================================
    if (viol_n == 0)
        print "PASS: " yaml_file " (" schema_str ")"
    else {
        print "FAIL: " yaml_file " (" schema_str ")"
        for (i = 0; i < viol_n; i++)
            print " - " violations[i]
    }
    exit(viol_n > 0 ? 1 : 0)
}
' "$YAML_FILE"
