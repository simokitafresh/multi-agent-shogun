#!/usr/bin/env bash
# Shared scaffold for deploy_task test family.
# Usage: load '../helpers/deploy_task_scaffold' in test files.

deploy_task_setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    export SRC_CLI_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_AGENT_STATE_LIB="$PROJECT_ROOT/lib/agent_state.sh"
    export SRC_CTX_UTILS_SCRIPT="$PROJECT_ROOT/scripts/lib/ctx_utils.sh"
    export SRC_PANE_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
    export SRC_AGENT_CONFIG_SCRIPT="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    export SRC_INJECT_TASK_MODIFIERS="$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    export SRC_FIREFIGHTING_KEYWORDS_SCRIPT="$PROJECT_ROOT/scripts/lib/firefighting_keywords.sh"
    export SRC_DASHBOARD_AUTO_SECTION_SCRIPT="$PROJECT_ROOT/scripts/dashboard_auto_section.sh"

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_CLI_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_STATE_LIB" ] || return 1
    [ -f "$SRC_CTX_UTILS_SCRIPT" ] || return 1
    [ -f "$SRC_PANE_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_CONFIG_SCRIPT" ] || return 1
    [ -f "$SRC_INJECT_TASK_MODIFIERS" ] || return 1
    [ -f "$SRC_FIREFIGHTING_KEYWORDS_SCRIPT" ] || return 1
    [ -f "$SRC_DASHBOARD_AUTO_SECTION_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export DEPLOY_TASK_TEMPLATE_DIR
    DEPLOY_TASK_TEMPLATE_DIR="$(mktemp -d "$BATS_TMPDIR/deploy_task_template.XXXXXX")"

    mkdir -p \
        "$DEPLOY_TASK_TEMPLATE_DIR/lib" \
        "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib" \
        "$DEPLOY_TASK_TEMPLATE_DIR/queue/tasks" \
        "$DEPLOY_TASK_TEMPLATE_DIR/queue/reports" \
        "$DEPLOY_TASK_TEMPLATE_DIR/queue/inbox" \
        "$DEPLOY_TASK_TEMPLATE_DIR/logs" \
        "$DEPLOY_TASK_TEMPLATE_DIR/config" \
        "$DEPLOY_TASK_TEMPLATE_DIR/projects"

    ln -s "$SRC_DEPLOY_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/deploy_task.sh"
    ln -s "$SRC_CLI_LOOKUP_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/cli_lookup.sh"
    ln -s "$SRC_FIELD_GET_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/field_get.sh"
    ln -s "$SRC_YAML_FIELD_SET_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/yaml_field_set.sh"
    ln -s "$SRC_AGENT_STATE_LIB" "$DEPLOY_TASK_TEMPLATE_DIR/lib/agent_state.sh"
    ln -s "$SRC_CTX_UTILS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/ctx_utils.sh"
    ln -s "$SRC_PANE_LOOKUP_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/pane_lookup.sh"
    ln -s "$SRC_AGENT_CONFIG_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/agent_config.sh"
    ln -s "$SRC_INJECT_TASK_MODIFIERS" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/inject_task_modifiers.py"
    ln -s "$SRC_FIREFIGHTING_KEYWORDS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/firefighting_keywords.sh"
    ln -s "$SRC_DASHBOARD_AUTO_SECTION_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/dashboard_auto_section.sh"

    for stub in inbox_write ntfy_cmd lesson_check; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$DEPLOY_TASK_TEMPLATE_DIR/scripts/${stub}.sh"
    done

    chmod +x "$DEPLOY_TASK_TEMPLATE_DIR/scripts/"*.sh

    cat > "$DEPLOY_TASK_TEMPLATE_DIR/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents:
    sasuke:
      type: codex
      role: ninja
      japanese_name: 佐助
EOF

    cat > "$DEPLOY_TASK_TEMPLATE_DIR/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    ctx_pattern: ""
    ctx_mode: used
    busy_patterns: []
    idle_pattern: ""
EOF

}

deploy_task_scaffold() {
    local tmpdir_prefix="${1:-deploy_task}"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/${tmpdir_prefix}.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p "$TEST_PROJECT"
    cp -a "$DEPLOY_TASK_TEMPLATE_DIR"/. "$TEST_PROJECT"/
}

deploy_task_teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

teardown_file() {
    [ -n "$DEPLOY_TASK_TEMPLATE_DIR" ] && [ -d "$DEPLOY_TASK_TEMPLATE_DIR" ] && rm -rf "$DEPLOY_TASK_TEMPLATE_DIR"
}

maybe_normalize_task_yaml() {
    :
}

deploy_task_fast() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        # shellcheck disable=SC2153
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        maybe_normalize_task_yaml "$task_file"

        if [ -n "$CMD_ID" ]; then
            if [ "$DIRECT_MODE" = true ]; then
                log "direct_mode(test): skipping resolve_cmd_to_task for ${CMD_ID}"
            elif ! resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                return 1
            fi
        fi

        inject_task_id "$task_file" || true
        inject_ac_version "$task_file" || true
        inject_related_lessons "$task_file" || true

        local clear_fields clear_tmp
        clear_fields="stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok"
        clear_tmp=$(mktemp)
        if awk -v fields="$clear_fields" '
            BEGIN { n=split(fields,arr,"|"); for(i=1;i<=n;i++) fset[arr[i]]=1; skip=0 }
            {
                if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
                if (skip) {
                    if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                    else { next }
                }
                if (indent == 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                    key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
                    if (key in fset) { skip = 1; next }
                }
                print
            }
        ' "$task_file" > "$clear_tmp" 2>/dev/null; then
            mv "$clear_tmp" "$task_file"
        else
            rm -f "$clear_tmp"
            return 1
        fi

        inject_task_modifiers "$task_file" || true
        yaml_field_set "$task_file" "task" "report_filename" ""
        yaml_field_set "$task_file" "task" "report_path" ""
        inject_report_filename "$task_file" || true

        local task_id parent_cmd project
        task_id=$(field_get "$task_file" "task_id" "")
        parent_cmd=$(field_get "$task_file" "parent_cmd" "")
        project=$(field_get "$task_file" "project" "")
        generate_report_template "$NINJA_NAME" "$task_id" "$parent_cmd" "$project"
    )
}

deploy_task_template_only() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        # shellcheck disable=SC2153
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        maybe_normalize_task_yaml "$task_file"

        if [ -n "$CMD_ID" ]; then
            if [ "$DIRECT_MODE" = true ]; then
                log "direct_mode(test): skipping resolve_cmd_to_task for ${CMD_ID}"
            elif ! resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                return 1
            fi
        fi

        inject_task_id "$task_file" || true
        inject_ac_version "$task_file" || true

        local clear_fields clear_tmp
        clear_fields="stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok"
        clear_tmp=$(mktemp)
        if awk -v fields="$clear_fields" '
            BEGIN { n=split(fields,arr,"|"); for(i=1;i<=n;i++) fset[arr[i]]=1; skip=0 }
            {
                if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
                if (skip) {
                    if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                    else { next }
                }
                if (indent == 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                    key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
                    if (key in fset) { skip = 1; next }
                }
                print
            }
        ' "$task_file" > "$clear_tmp" 2>/dev/null; then
            mv "$clear_tmp" "$task_file"
        else
            rm -f "$clear_tmp"
            return 1
        fi

        inject_task_modifiers "$task_file" || true
        yaml_field_set "$task_file" "task" "report_filename" ""
        yaml_field_set "$task_file" "task" "report_path" ""
        inject_report_filename "$task_file" || true

        local task_id parent_cmd project
        task_id=$(field_get "$task_file" "task_id" "")
        parent_cmd=$(field_get "$task_file" "parent_cmd" "")
        project=$(field_get "$task_file" "project" "")
        generate_report_template "$NINJA_NAME" "$task_id" "$parent_cmd" "$project"
    )
}

deploy_task_lessons_only() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        local ninja_name="${1:-sasuke}"
        local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"

        maybe_normalize_task_yaml "$task_file"
        inject_related_lessons "$task_file" || true
    )
}

normalize_simple_ac_ids() {
    local task_file="$1"

    sed -Ei "s/^([[:space:]]*-?[[:space:]]*id:[[:space:]]*)'([A-Za-z0-9_.:+-]+)'$/\\1\\2/" "$task_file"
}

deploy_task_ac_only() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        # shellcheck disable=SC2153
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        maybe_normalize_task_yaml "$task_file"

        if [ -n "$CMD_ID" ]; then
            if [ "$DIRECT_MODE" = true ]; then
                log "direct_mode(test): skipping resolve_cmd_to_task for ${CMD_ID}"
            elif ! resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                return 1
            fi
        fi

        inject_task_id "$task_file" || true
        inject_ac_version "$task_file" || true
        normalize_simple_ac_ids "$task_file"
    )
}

deploy_task_resolve_only() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        # shellcheck disable=SC2153
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        maybe_normalize_task_yaml "$task_file"

        if [ -n "$CMD_ID" ]; then
            if [ "$DIRECT_MODE" = true ]; then
                log "direct_mode(test): skipping resolve_cmd_to_task for ${CMD_ID}"
            elif ! resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                return 1
            fi
        fi

        inject_task_id "$task_file" || true
        inject_ac_version "$task_file" || true
        normalize_simple_ac_ids "$task_file"
    )
}

inject_report_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        NINJA_NAME="$ninja_name"
        # SCRIPT_DIR is set by deploy_task.sh on source (BASH_SOURCE[0] → TEST_PROJECT)

        # AC overwrite: if _ac_task_id != task_id, overwrite ACs from cmd source
        # (needed for binary_checks generation from nested ac: format)
        local curr_task_id prev_ac_task_id
        curr_task_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_id" "")
        prev_ac_task_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "_ac_task_id" "")
        if [ "$curr_task_id" != "$prev_ac_task_id" ]; then
            _overwrite_ac_from_cmd "$task_file" || true
            normalize_simple_ac_ids "$task_file"
        fi

        yaml_field_set "$task_file" "task" "report_filename" ""
        yaml_field_set "$task_file" "task" "report_path" ""
        inject_report_filename "$task_file" || true

        local task_id parent_cmd project
        task_id=$(field_get "$task_file" "task_id" "")
        parent_cmd=$(field_get "$task_file" "parent_cmd" "")
        project=$(field_get "$task_file" "project" "")
        generate_report_template "$NINJA_NAME" "$task_id" "$parent_cmd" "$project"
    )
}

inject_ac_version_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        # shellcheck disable=SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        inject_ac_version "$task_file"
    )
}

inject_modifiers_only() {
    local ninja_name="$1"
    local only_ops="${2:-execution_controls}"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    local clear_fields clear_tmp

    clear_fields="stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok"
    clear_tmp="$(mktemp)"
    if ! awk -v fields="$clear_fields" '
        BEGIN { n=split(fields,arr,"|"); for(i=1;i<=n;i++) fset[arr[i]]=1; skip=0 }
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
                if (key in fset) { skip = 1; next }
            }
            print
        }
    ' "$task_file" > "$clear_tmp"; then
        rm -f "$clear_tmp"
        return 1
    fi
    mv "$clear_tmp" "$task_file"

    TASK_FILE_ENV="$task_file" \
    SCRIPT_DIR_ENV="$TEST_PROJECT" \
    INJECT_TASK_MODIFIERS_ONLY="$only_ops" \
        python3 "$TEST_PROJECT/scripts/lib/inject_task_modifiers.py"
}

inject_engineering_preferences_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    local clear_tmp

    clear_tmp="$(mktemp)"
    if ! awk '
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  engineering_preferences:/) {
                skip = 1
                next
            }
            print
        }
    ' "$task_file" > "$clear_tmp"; then
        rm -f "$clear_tmp"
        return 1
    fi
    mv "$clear_tmp" "$task_file"

    TASK_FILE_ENV="$task_file" \
    SCRIPT_DIR_ENV="$TEST_PROJECT" \
    INJECT_TASK_MODIFIERS_ONLY="engineering_preferences" \
        python3 "$TEST_PROJECT/scripts/lib/inject_task_modifiers.py"
}
