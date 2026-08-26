#!/usr/bin/env bash
# Shared scaffold for deploy_task test family.
# Usage: load '../helpers/deploy_task_scaffold' in test files.

deploy_task_setup_file() {
    # Unit fixtures validate deploy_task behavior, not production telemetry.
    # Keep the async Python/SQLite/flock writer out of the canonical parallel
    # test lane; telemetry-specific tests must opt in explicitly with =1.
    export DEFENSE_OVERHEAD_ENABLED=0

    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    export SRC_CLI_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_PROJECT_PATH_SCRIPT="$PROJECT_ROOT/scripts/lib/project_path.sh"
    export SRC_REPO_ROOT_SCRIPT="$PROJECT_ROOT/scripts/lib/repo_root.sh"
    export SRC_AGENT_STATE_LIB="$PROJECT_ROOT/lib/agent_state.sh"
    export SRC_CTX_UTILS_SCRIPT="$PROJECT_ROOT/scripts/lib/ctx_utils.sh"
    export SRC_PANE_LOOKUP_SCRIPT="$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
    export SRC_TMUX_UTILS_SCRIPT="$PROJECT_ROOT/scripts/lib/tmux_utils.sh"
    export SRC_AGENT_CONFIG_SCRIPT="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    export SRC_INJECT_TASK_MODIFIERS="$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    export SRC_SEMANTIC_CONTEXT_FAST="$PROJECT_ROOT/scripts/lib/deploy_task_semantic_context_fast.py"
    export SRC_PREFLIGHT_FAST="$PROJECT_ROOT/scripts/lib/deploy_task_preflight_fast.py"
    export SRC_REPORT_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/report_field_set.sh"
    export SRC_REPORT_COMMIT_IDENTITY="$PROJECT_ROOT/scripts/lib/report_commit_identity.py"
    export SRC_REPORT_UNIQUE_IDENTITY="$PROJECT_ROOT/scripts/lib/report_unique_identity.py"
    export SRC_FIREFIGHTING_KEYWORDS_SCRIPT="$PROJECT_ROOT/scripts/lib/firefighting_keywords.sh"
    export SRC_GATE_HOOK_QUALITY_CONTRACT_SCRIPT="$PROJECT_ROOT/scripts/lib/gate_hook_quality_contract.sh"
    export SRC_MODEL_INJECTION_PROFILE_SCRIPT="$PROJECT_ROOT/scripts/lib/model_injection_profile.sh"
    export SRC_UNIVERSAL_SHARD_CONTRACT="$PROJECT_ROOT/scripts/lib/universal_shard_contract.py"
    export SRC_DASHBOARD_AUTO_SECTION_SCRIPT="$PROJECT_ROOT/scripts/dashboard_auto_section.sh"
    export SRC_SEMANTIC_ALIAS_QUALITY_SCRIPT="$PROJECT_ROOT/scripts/semantic_alias_quality.sh"
    export SRC_MARKDOWN_LINK_COUNTS_SCRIPT="$PROJECT_ROOT/scripts/markdown_link_counts.sh"
    export SRC_CAUSAL_BACKLINK_COUNTS_SCRIPT="$PROJECT_ROOT/scripts/causal_backlink_counts.sh"
    export SRC_DEFENSE_OVERHEAD_WRITER="$PROJECT_ROOT/scripts/lib/defense_overhead_writer.sh"

    [ -f "$SRC_DEPLOY_SCRIPT" ] || return 1
    [ -f "$SRC_CLI_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_PROJECT_PATH_SCRIPT" ] || return 1
    [ -f "$SRC_REPO_ROOT_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_STATE_LIB" ] || return 1
    [ -f "$SRC_CTX_UTILS_SCRIPT" ] || return 1
    [ -f "$SRC_PANE_LOOKUP_SCRIPT" ] || return 1
    [ -f "$SRC_TMUX_UTILS_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_CONFIG_SCRIPT" ] || return 1
    [ -f "$SRC_INJECT_TASK_MODIFIERS" ] || return 1
    [ -f "$SRC_SEMANTIC_CONTEXT_FAST" ] || return 1
    [ -f "$SRC_PREFLIGHT_FAST" ] || return 1
    [ -f "$SRC_REPORT_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_REPORT_COMMIT_IDENTITY" ] || return 1
    [ -f "$SRC_FIREFIGHTING_KEYWORDS_SCRIPT" ] || return 1
    [ -f "$SRC_MODEL_INJECTION_PROFILE_SCRIPT" ] || return 1
    [ -f "$SRC_UNIVERSAL_SHARD_CONTRACT" ] || return 1
    [ -f "$SRC_DASHBOARD_AUTO_SECTION_SCRIPT" ] || return 1
    [ -f "$SRC_SEMANTIC_ALIAS_QUALITY_SCRIPT" ] || return 1
    [ -f "$SRC_MARKDOWN_LINK_COUNTS_SCRIPT" ] || return 1
    [ -f "$SRC_CAUSAL_BACKLINK_COUNTS_SCRIPT" ] || return 1
    [ -f "$SRC_DEFENSE_OVERHEAD_WRITER" ] || return 1
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

    # cmd_2117: cp instead of ln -s → reads from /tmp (Linux ext4) not /mnt/c (WSL2 NTFS)
    cp "$SRC_DEPLOY_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/deploy_task.sh"
    cp "$SRC_CLI_LOOKUP_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/cli_lookup.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/yaml_field_set.sh"
    cp "$SRC_PROJECT_PATH_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/project_path.sh"
    cp "$SRC_REPO_ROOT_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/repo_root.sh"
    cp "$SRC_AGENT_STATE_LIB" "$DEPLOY_TASK_TEMPLATE_DIR/lib/agent_state.sh"
    cp "$SRC_CTX_UTILS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/ctx_utils.sh"
    cp "$SRC_PANE_LOOKUP_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/pane_lookup.sh"
    cp "$SRC_TMUX_UTILS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/tmux_utils.sh"
    cp "$SRC_AGENT_CONFIG_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/agent_config.sh"
    cp "$SRC_INJECT_TASK_MODIFIERS" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/inject_task_modifiers.py"
    cp "$SRC_SEMANTIC_CONTEXT_FAST" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/deploy_task_semantic_context_fast.py"
    cp "$SRC_PREFLIGHT_FAST" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/deploy_task_preflight_fast.py"
    cp "$SRC_REPORT_FIELD_SET_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/report_field_set.sh"
    cp "$SRC_REPORT_COMMIT_IDENTITY" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/report_commit_identity.py"
    cp "$SRC_REPORT_UNIQUE_IDENTITY" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/report_unique_identity.py"
    cp "$SRC_FIREFIGHTING_KEYWORDS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/firefighting_keywords.sh"
    cp "$SRC_GATE_HOOK_QUALITY_CONTRACT_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/gate_hook_quality_contract.sh"
    cp "$SRC_MODEL_INJECTION_PROFILE_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/model_injection_profile.sh"
    cp "$SRC_UNIVERSAL_SHARD_CONTRACT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/universal_shard_contract.py"
    cp "$SRC_DASHBOARD_AUTO_SECTION_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/dashboard_auto_section.sh"
    cp "$SRC_SEMANTIC_ALIAS_QUALITY_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/semantic_alias_quality.sh"
    cp "$SRC_MARKDOWN_LINK_COUNTS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/markdown_link_counts.sh"
    cp "$SRC_CAUSAL_BACKLINK_COUNTS_SCRIPT" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/causal_backlink_counts.sh"
    cp "$SRC_DEFENSE_OVERHEAD_WRITER" "$DEPLOY_TASK_TEMPLATE_DIR/scripts/lib/defense_overhead_writer.sh"

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

    cat > "$DEPLOY_TASK_TEMPLATE_DIR/config/projects.yaml" <<'EOF'
current_project: infra
projects:
  - id: infra
    type: platform
EOF

    cat > "$DEPLOY_TASK_TEMPLATE_DIR/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    ctx_pattern: ""
    ctx_mode: used
    busy_patterns: []
    idle_pattern: ""
EOF

    # cmd_2117: pre-build template project dir for fast cp -r per test (avoid mkdir+ln-s overhead)
    export DEPLOY_TASK_PROJECT_TEMPLATE
    DEPLOY_TASK_PROJECT_TEMPLATE="$(mktemp -d "$BATS_TMPDIR/dts_proj_tmpl.XXXXXX")"
    mkdir -p \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/queue/tasks" \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/queue/reports" \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/queue/inbox" \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/logs" \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/projects" \
        "$DEPLOY_TASK_PROJECT_TEMPLATE/archive"
    ln -s "$DEPLOY_TASK_TEMPLATE_DIR/scripts" "$DEPLOY_TASK_PROJECT_TEMPLATE/scripts"
    ln -s "$DEPLOY_TASK_TEMPLATE_DIR/lib" "$DEPLOY_TASK_PROJECT_TEMPLATE/lib"
    ln -s "$DEPLOY_TASK_TEMPLATE_DIR/config" "$DEPLOY_TASK_PROJECT_TEMPLATE/config"
    printf '<!-- DASHBOARD_AUTO_START -->\n<!-- DASHBOARD_AUTO_END -->\n' \
        > "$DEPLOY_TASK_PROJECT_TEMPLATE/dashboard.md"


}

deploy_task_scaffold() {
    local tmpdir_prefix="${1:-deploy_task}"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/${tmpdir_prefix}.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export DEPLOY_LESSON_CACHE_DIR="$TEST_TMPDIR"

    # cmd_2117: cp -rP preserves symlinks (scripts/lib/config → /tmp copies)
    if [[ -n "${DEPLOY_TASK_PROJECT_TEMPLATE:-}" && -d "$DEPLOY_TASK_PROJECT_TEMPLATE" ]]; then
        cp -rP "$DEPLOY_TASK_PROJECT_TEMPLATE" "$TEST_PROJECT"
    else
        mkdir -p \
            "$TEST_PROJECT/queue/tasks" \
            "$TEST_PROJECT/queue/reports" \
            "$TEST_PROJECT/queue/inbox" \
            "$TEST_PROJECT/logs" \
            "$TEST_PROJECT/projects" \
            "$TEST_PROJECT/archive"
        ln -s "$DEPLOY_TASK_TEMPLATE_DIR/scripts" "$TEST_PROJECT/scripts"
        ln -s "$DEPLOY_TASK_TEMPLATE_DIR/lib" "$TEST_PROJECT/lib"
        ln -s "$DEPLOY_TASK_TEMPLATE_DIR/config" "$TEST_PROJECT/config"
        printf '<!-- DASHBOARD_AUTO_START -->\n<!-- DASHBOARD_AUTO_END -->\n' \
            > "$TEST_PROJECT/dashboard.md"
    fi

    # Cache the 10k-line deploy library once per Bats test process.  The helper
    # entry points below run in subshells, so the functions remain isolated
    # while avoiding repeated parsing on every deploy_task_* invocation.
    if ! declare -F parse_deploy_task_args >/dev/null 2>&1; then
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
    fi
}

# Canonical fixture contract for full deploy benchmarks.  Keep every durable
# output inside TEST_PROJECT so a benchmark cannot accidentally inspect or
# mutate the live queue.
full_deploy_e2e_setup() {
    deploy_task_scaffold "full_deploy_e2e"
    export FULL_DEPLOY_E2E_DIR="$TEST_TMPDIR/full_deploy_e2e"
    export FULL_DEPLOY_E2E_RESULTS="$FULL_DEPLOY_E2E_DIR/results.tsv"
    export FULL_DEPLOY_E2E_TELEMETRY="$FULL_DEPLOY_E2E_DIR/phase.telemetry"
    export FULL_DEPLOY_E2E_GATE_LOG="$TEST_PROJECT/logs/gates.log"
    mkdir -p "$FULL_DEPLOY_E2E_DIR" "$TEST_PROJECT/archive/reports"
    : > "$FULL_DEPLOY_E2E_RESULTS"
    : > "$FULL_DEPLOY_E2E_TELEMETRY"
    : > "$FULL_DEPLOY_E2E_GATE_LOG"

    local required
    for required in \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/archive/reports" \
        "$FULL_DEPLOY_E2E_GATE_LOG" \
        "$FULL_DEPLOY_E2E_TELEMETRY"; do
        [ -e "$required" ] || {
            echo "BLOCK: missing full deploy fixture: $required" >&2
            return 2
        }
    done
}

deploy_task_teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

teardown_file() {
    [ -n "${DEPLOY_TASK_PROJECT_TEMPLATE:-}" ] && [ -d "$DEPLOY_TASK_PROJECT_TEMPLATE" ] && rm -rf "$DEPLOY_TASK_PROJECT_TEMPLATE"
    [ -n "$DEPLOY_TASK_TEMPLATE_DIR" ] && [ -d "$DEPLOY_TASK_TEMPLATE_DIR" ] && rm -rf "$DEPLOY_TASK_TEMPLATE_DIR"
}

maybe_normalize_task_yaml() {
    :
}

ensure_deploy_task_library() {
    if ! declare -F parse_deploy_task_args >/dev/null 2>&1; then
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
    fi
}

deploy_task_fast() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        ensure_deploy_task_library
        # The library is cached across tests; rebind its project root for the
        # current isolated fixture before any selector or queue operation.
        SCRIPT_DIR="$TEST_PROJECT"
        # shellcheck disable=SC2317
        log() { :; }

        parse_deploy_task_args "$@"
        cleanup_none_task_files
        # shellcheck disable=SC2153
        deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1

        local task_file="$TEST_PROJECT/queue/tasks/${NINJA_NAME}.yaml"
        maybe_normalize_task_yaml "$task_file"
        repair_training_parent_cmd_from_cmd_id "$task_file" || return 1

        if [ -n "$CMD_ID" ]; then
            if [ "$DIRECT_MODE" = true ]; then
                log "direct_mode(test): skipping resolve_cmd_to_task for ${CMD_ID}"
                local direct_task_type direct_task_id_suffix
                direct_task_type=$(field_get "$task_file" "task_type" "normal")
                if [ "$direct_task_type" = "exact" ]; then
                    direct_task_id_suffix="exact"
                else
                    direct_task_id_suffix="normal"
                fi
                yaml_field_set "$task_file" "task" "parent_cmd" "$CMD_ID"
                yaml_field_set "$task_file" "task" "status" "assigned"
                yaml_field_set "$task_file" "task" "task_id" "${CMD_ID}_${direct_task_id_suffix}"
                inject_direct_training_template "$task_file" "$CMD_ID" || return 1
                # The cached library's training template can rewrite the task
                # mapping; select the target after it so fixture roots retain
                # the selector result.
                inject_training_target_path_from_alias_quality "$task_file" "$CMD_ID" || true
            elif ! resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                return 1
            fi
        fi

        # Re-run the target selector at the fixture boundary. This mirrors
        # production's post-template contract and covers cached-library paths
        # where the direct branch is bypassed after argument normalization.
        if [ -n "$CMD_ID" ]; then
            inject_training_target_path_from_alias_quality "$task_file" "$CMD_ID" || true
        fi

        inject_task_id "$task_file" || true
        infer_ac_assigned_from_chunk_task_id "$task_file" || true
        inject_ac_assigned_from_stk "$task_file" || true
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
        inject_standard_skills "$task_file" || true
        inject_direct_training_template "$task_file" "$CMD_ID" || return 1
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
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }

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
        infer_ac_assigned_from_chunk_task_id "$task_file" || true
        inject_ac_assigned_from_stk "$task_file" || true
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
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }

        local ninja_name="${1:-sasuke}"
        local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"

        maybe_normalize_task_yaml "$task_file"
        inject_related_lessons "$task_file" || true
        inject_workaround_pattern_lessons "$task_file" "$ninja_name" || true
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
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }

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
        infer_ac_assigned_from_chunk_task_id "$task_file" || true
        inject_ac_version "$task_file" || true
        normalize_simple_ac_ids "$task_file"
    )
}

deploy_task_resolve_only() {
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }

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
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }

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
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }
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

inject_skill_hint_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }
        inject_skill_hint "$task_file"
    )
}

inject_context_hints_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }
        inject_context_hints "$task_file"
    )
}

inject_production_invariants_only() {
    local ninja_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/${ninja_name}.yaml"
    (
        # shellcheck disable=SC2030,SC2031
        export DEPLOY_TASK_LIB_ONLY=1
        ensure_deploy_task_library
        # shellcheck disable=SC2317
        log() { :; }
        inject_production_invariants "$task_file"
    )
}
