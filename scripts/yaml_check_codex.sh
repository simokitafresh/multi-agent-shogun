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

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
sed 's/\r$//' "$YAML_FILE" > "$TMP_FILE"

violations=()
schema_type=""

add_violation() {
  violations+=("$1")
}

has_top_key() {
  local key="$1"
  grep -Eq "^${key}:[[:space:]]*" "$TMP_FILE"
}

has_nested_key() {
  local root="$1"
  local key="$2"
  awk -v root="$root" -v key="$key" '
    $0 ~ ("^" root ":[[:space:]]*$") { inside=1; next }
    inside && /^[^[:space:]]/ { inside=0 }
    inside && $0 ~ ("^  " key ":[[:space:]]*") { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$TMP_FILE"
}

check_top_string() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ ("^" key ":[[:space:]]*") {
      found=1
      line=$0
      sub("^" key ":[[:space:]]*", "", line)
      if (line ~ /^[\[{]/) exit 1
      exit 0
    }
    END { if (!found) exit 1 }
  ' "$TMP_FILE"
}

check_nested_string() {
  local root="$1"
  local key="$2"
  awk -v root="$root" -v key="$key" '
    $0 ~ ("^" root ":[[:space:]]*$") { inside=1; next }
    inside && /^[^[:space:]]/ { inside=0 }
    inside && $0 ~ ("^  " key ":[[:space:]]*") {
      found=1
      line=$0
      sub("^  " key ":[[:space:]]*", "", line)
      if (line ~ /^[\[{]/) exit 1
      exit 0
    }
    END { if (!found) exit 1 }
  ' "$TMP_FILE"
}

check_top_array() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ ("^" key ":[[:space:]]*") {
      found=1
      line=$0
      sub("^" key ":[[:space:]]*", "", line)
      if (line ~ /^\[/) { ok=1; exit }
      expect=1
      next
    }
    expect {
      if ($0 ~ /^[^[:space:]]/) exit
      if ($0 ~ /^  -[[:space:]]*/) { ok=1; exit }
      if ($0 ~ /^  [^[:space:]][^:]*:[[:space:]]*/) exit
    }
    END { exit((found && ok) ? 0 : 1) }
  ' "$TMP_FILE"
}

check_nested_array() {
  local root="$1"
  local key="$2"
  awk -v root="$root" -v key="$key" '
    $0 ~ ("^" root ":[[:space:]]*$") { inside=1; next }
    inside && /^[^[:space:]]/ { if (seen) exit; inside=0 }
    inside && !seen && $0 ~ ("^  " key ":[[:space:]]*") {
      seen=1
      line=$0
      sub("^  " key ":[[:space:]]*", "", line)
      if (line ~ /^\[/) { ok=1; exit }
      next
    }
    inside && seen {
      if ($0 ~ /^  -[[:space:]]*/) { ok=1; exit }
      if ($0 ~ /^  [^[:space:]][^:]*:[[:space:]]*/) exit
    }
    END { exit((seen && ok) ? 0 : 1) }
  ' "$TMP_FILE"
}

check_section_found_bool() {
  local section="$1"
  awk -v section="$section" '
    $0 ~ ("^" section ":[[:space:]]*$") { inside=1; next }
    inside && /^[^[:space:]]/ { inside=0 }
    inside && /^  found:[[:space:]]*(true|false)[[:space:]]*$/ { ok=1; exit }
    END { exit(ok ? 0 : 1) }
  ' "$TMP_FILE"
}

if grep -Eq '^task:[[:space:]]*$' "$TMP_FILE"; then
  schema_type="task"
elif grep -Eq '^report:[[:space:]]*$' "$TMP_FILE"; then
  schema_type="report_nested"
elif grep -Eq '^worker_id:[[:space:]]*' "$TMP_FILE"; then
  schema_type="report_flat"
else
  schema_type="unknown"
fi

if [ "$schema_type" = "unknown" ]; then
  add_violation "unknown schema type (expected task/report)"
fi

if [ "$schema_type" = "task" ]; then
  task_variant="stub"
  if has_nested_key task bloom_level || has_nested_key task description || has_nested_key task acceptance_criteria; then
    task_variant="full"
  fi

  for key in task_id parent_cmd task_type assigned_to status title; do
    has_nested_key task "$key" || add_violation "missing required key: task.$key"
    check_nested_string task "$key" || add_violation "type mismatch: task.$key must be string"
  done

  if [ "$task_variant" = "full" ]; then
    for key in acceptance_criteria blocked_by related_lessons; do
      has_nested_key task "$key" || add_violation "missing required key: task.$key"
      check_nested_array task "$key" || add_violation "type mismatch: task.$key must be array"
    done
  else
    for key in acceptance_criteria blocked_by related_lessons; do
      if has_nested_key task "$key"; then
        check_nested_array task "$key" || add_violation "type mismatch: task.$key must be array"
      fi
    done
  fi

  schema_type="${schema_type}/${task_variant}"
fi

if [ "$schema_type" = "report_flat" ]; then
  for key in worker_id task_id parent_cmd timestamp status result lesson_candidate lesson_referenced skill_candidate decision_candidate; do
    has_top_key "$key" || add_violation "missing required key: $key"
  done

  for key in worker_id task_id parent_cmd timestamp status; do
    check_top_string "$key" || add_violation "type mismatch: $key must be string"
  done

  check_top_array lesson_referenced || add_violation "type mismatch: lesson_referenced must be array"

  for section in lesson_candidate skill_candidate decision_candidate; do
    check_section_found_bool "$section" || add_violation "type mismatch: ${section}.found must be boolean"
  done
fi

if [ "$schema_type" = "report_nested" ]; then
  for key in task_id parent_cmd status timestamp title; do
    has_nested_key report "$key" || add_violation "missing required key: report.$key"
    check_nested_string report "$key" || add_violation "type mismatch: report.$key must be string"
  done
fi

if [ ${#violations[@]} -eq 0 ]; then
  echo "PASS: ${YAML_FILE} (${schema_type})"
  exit 0
fi

echo "FAIL: ${YAML_FILE} (${schema_type})"
for v in "${violations[@]}"; do
  echo " - ${v}"
done
exit 1
