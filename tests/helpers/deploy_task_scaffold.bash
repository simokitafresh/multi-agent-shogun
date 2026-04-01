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

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_CLI_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_STATE_LIB" ] || return 1
    [ -f "$SRC_CTX_UTILS_SCRIPT" ] || return 1
    [ -f "$SRC_PANE_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_CONFIG_SCRIPT" ] || return 1
    [ -f "$SRC_INJECT_TASK_MODIFIERS" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

deploy_task_scaffold() {
    local tmpdir_prefix="${1:-deploy_task}"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/${tmpdir_prefix}.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/lib" \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/projects"

    cp "$SRC_DEPLOY_SCRIPT" "$TEST_PROJECT/scripts/deploy_task.sh"
    cp "$SRC_CLI_LOOKUP_SCRIPT" "$TEST_PROJECT/scripts/lib/cli_lookup.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    cp "$SRC_AGENT_STATE_LIB" "$TEST_PROJECT/lib/agent_state.sh"
    cp "$SRC_CTX_UTILS_SCRIPT" "$TEST_PROJECT/scripts/lib/ctx_utils.sh"
    cp "$SRC_PANE_LOOKUP_SCRIPT" "$TEST_PROJECT/scripts/lib/pane_lookup.sh"
    cp "$SRC_AGENT_CONFIG_SCRIPT" "$TEST_PROJECT/scripts/lib/agent_config.sh"
    cp "$SRC_INJECT_TASK_MODIFIERS" "$TEST_PROJECT/scripts/lib/inject_task_modifiers.py"

    # Non-blocking script stubs
    for stub in inbox_write ntfy_cmd lesson_check; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_PROJECT/scripts/${stub}.sh"
    done

    chmod +x "$TEST_PROJECT/scripts/"*.sh "$TEST_PROJECT/scripts/lib/"*.sh "$TEST_PROJECT/lib/"*.sh

    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents:
    sasuke:
      type: codex
      role: ninja
      japanese_name: 佐助
EOF

    cat > "$TEST_PROJECT/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    ctx_pattern: ""
    ctx_mode: used
    busy_patterns: []
    idle_pattern: ""
EOF
}

deploy_task_teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

deploy_task_fast() {
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090
        source "$TEST_PROJECT/scripts/deploy_task.sh"

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        normalize_task_yaml "$task_file" || true

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
