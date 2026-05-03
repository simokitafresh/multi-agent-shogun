#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2129
# ============================================================
# Instruction File Build System
# ============================================================
# Combines instruction parts into complete instruction files
# for each role and CLI combination.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARTS_DIR="$SCRIPT_DIR/instructions"
OUTPUT_DIR="$SCRIPT_DIR/instructions/generated"

# Source CLI profile lookup library (cmd_143 SSOT)
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

# Default CLI type (instruction files without prefix)
DEFAULT_CLI="claude"

mkdir -p "$OUTPUT_DIR"

echo "=== Instruction File Build System ==="
echo "Building instruction files..."

# ============================================================
# Helper: Get all CLI profile types from cli_profiles.yaml
# ============================================================
get_profile_types() {
    # Use awk instead of python3 to avoid ~80ms interpreter startup overhead (L509: cold measurement)
    awk '/^profiles:/{p=1;next} p && /^  [[:alpha:]][[:alnum:]_-]*:/{key=$0; gsub(/^  |:.*$/, "", key); print key} p && /^[^ \t]/{p=0}' "${_CLI_LOOKUP_PROFILES}" 2>/dev/null
}

# ============================================================
# Helper: Prefer a specific CLI type, fallback to first non-default
# ============================================================
select_profile_type() {
    local preferred_type="$1"
    local profile_types="$2"

    if printf '%s\n' "$profile_types" | grep -qx "$preferred_type"; then
        printf '%s\n' "$preferred_type"
        return 0
    fi

    printf '%s\n' "$profile_types" | grep -vx "$DEFAULT_CLI" | head -1
}

# Codex uses /new instead of /clear for session reset.
# Keep clear_command and /shogun-clear-prep intact; those are protocol/skill names,
# not CLI commands for Codex to run.
normalize_codex_reset_references() {
    local target_file="$1"

    # shellcheck disable=SC2016
    sed -i \
        -e 's|/clear Recovery|/new Recovery|g' \
        -e 's|/clear recovery|/new recovery|g' \
        -e 's|/clear前|/new前|g' \
        -e 's|/clear後|/new後|g' \
        -e 's|after /clear|after /new|g' \
        -e 's|After /clear|After /new|g' \
        -e 's|pre-/clear|pre-/new|g' \
        -e 's|無条件/clear|無条件/new|g' \
        -e 's|家老/clear|家老/new|g' \
        -e 's|test /clear recovery|test /new recovery|g' \
        -e 's|sending /clear|sending /new|g' \
        -e 's|prepare for /clear|prepare for /new|g' \
        -e 's|/clearされた|/newされた|g' \
        -e 's|`/clear` する|`/new` する|g' \
        -e 's|sends `/clear` + Enter|sends `/new` + Enter|g' \
        "$target_file"
}

# ============================================================
# Helper function: Build a complete instruction file
# ============================================================
build_instruction_file() {
    local cli_type="$1"
    local role="$2"
    local output_filename="$3"
    local output_path="$OUTPUT_DIR/$output_filename"
    local original_file="$SCRIPT_DIR/instructions/${role}.md"
    local tools_file="$PARTS_DIR/cli_specific/${cli_type}_tools.md"

    echo "Building: $output_filename (CLI: $cli_type, Role: $role)"

    # Write entire file in a single pass to reduce WSL2 filesystem overhead.
    # Multiple >> appends each open/close the output file; a single {} > file
    # opens it once and streams all content through one file descriptor.
    {
        # Extract YAML front matter from original file
        if [ -f "$original_file" ]; then
            echo "---"
            awk '/^---$/{if(++n==2) {print "---"; exit} if(n==1) next} n==1' "$original_file"
            echo ""
        else
            # Minimal YAML front matter
            printf -- '---\nrole: %s\nversion: "3.0"\ncli_type: %s\n---\n\n' "$role" "$cli_type"
        fi

        # Role-specific content
        cat "$PARTS_DIR/roles/${role}_role.md"

        # Common sections (pre-built once; avoids re-reading 3 files per call)
        cat "$_BUILD_COMMON_TMP"

        # CLI-specific tools section
        if [ -f "$tools_file" ]; then
            printf '\n'
            cat "$tools_file"
        else
            echo "  ⚠️  No CLI tools file for: $cli_type (${tools_file})"
        fi
    } > "$output_path"

    if [[ "$cli_type" == "codex" ]]; then
        normalize_codex_reset_references "$output_path"
    fi

    echo "  ✅ Created: $output_filename"
}

# ============================================================
# Pre-build common sections into a temp file (read once, reuse 12×)
# ============================================================
_BUILD_COMMON_TMP=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$_BUILD_COMMON_TMP'" EXIT INT TERM
{
    printf '\n'
    cat "$PARTS_DIR/common/protocol.md"
    printf '\n'
    cat "$PARTS_DIR/common/task_flow.md"
    printf '\n'
    cat "$PARTS_DIR/common/forbidden_actions.md"
} > "$_BUILD_COMMON_TMP"

# ============================================================
# Build instruction files — profile-driven from cli_profiles.yaml
# ============================================================
ROLES="shogun karo gunshi ashigaru"
PROFILE_TYPES=$(get_profile_types)

# Default CLI — files without prefix (parallel builds: WSL2 NTFS write bottleneck bypassed)
for role in $ROLES; do
    build_instruction_file "$DEFAULT_CLI" "$role" "${role}.md" &
done

# Non-default profiles — files with cli_type prefix
for cli_type in $PROFILE_TYPES; do
    if [[ "$cli_type" != "$DEFAULT_CLI" ]]; then
        for role in $ROLES; do
            build_instruction_file "$cli_type" "$role" "${cli_type}-${role}.md" &
        done
    fi
done

# CLI types not yet in cli_profiles.yaml (temporary — remove when profiles added)
for cli_type in copilot kimi; do
    if echo "$PROFILE_TYPES" | grep -q "^${cli_type}$"; then
        continue
    fi
    for role in $ROLES; do
        build_instruction_file "$cli_type" "$role" "${cli_type}-${role}.md" &
    done
done

# Wait for all parallel instruction builds to finish
wait

# ============================================================
# Helper: Transform CLAUDE.md to CLI-specific auto-load file
# ============================================================
# Centralizes sed substitution patterns used by all generate_* functions.
# Args: cli_type autoload_md autoload_local_md config_path mcp_path display_name input output
transform_claude_md() {
    local cli_type="$1"
    local autoload_md="$2"
    local autoload_local_md="$3"
    local config_path="$4"
    local mcp_path="$5"
    local display_name="$6"
    local input_file="$7"
    local output_file="$8"

    sed \
        -e "s|CLAUDE\\.md|${autoload_md}|g" \
        -e "s|CLAUDE\\.local\\.md|${autoload_local_md}|g" \
        -e "s|instructions/shogun\\.md|instructions/generated/${cli_type}-shogun.md|g" \
        -e "s|instructions/karo\\.md|instructions/generated/${cli_type}-karo.md|g" \
        -e "s|instructions/gunshi\\.md|instructions/generated/${cli_type}-gunshi.md|g" \
        -e "s|instructions/ashigaru\\.md|instructions/generated/${cli_type}-ashigaru.md|g" \
        -e "s|~/\\.claude/|~/.${cli_type}/|g" \
        -e "s|\\.claude\\.json|${config_path}|g" \
        -e "s|\\.mcp\\.json|${mcp_path}|g" \
        -e "s|Claude Code|${display_name}|g" \
        "$input_file" > "$output_file"
}

# ============================================================
# AGENTS.md generation (Codex auto-load file)
# ============================================================
# Codex CLIはリポジトリルートのAGENTS.mdを自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をCodex固有に置換して生成。
generate_agents_md() {
    # AGENTS.md = Codex CLI auto-load file
    # Prefer codex explicitly; "first non-default" is order-dependent.
    local cli_type
    cli_type=$(select_profile_type "codex" "$PROFILE_TYPES")
    if [[ -z "$cli_type" ]]; then
        echo "  ⚠️  No non-default CLI profile found. Skipping AGENTS.md generation."
        return 1
    fi

    local output_path="$SCRIPT_DIR/AGENTS.md"
    local claude_md="$SCRIPT_DIR/CLAUDE.md"
    local cli_display
    cli_display=$(cli_profile_get_for_type "$cli_type" "display_name")
    [[ -z "$cli_display" ]] && cli_display="${cli_type^} CLI"

    echo "Generating: AGENTS.md (${cli_type} auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping AGENTS.md generation."
        return 1
    fi

    transform_claude_md "$cli_type" \
        "AGENTS.md" "AGENTS.override.md" \
        ".${cli_type}/config.toml" "config.toml (mcp_servers section)" \
        "$cli_display" "$claude_md" "$output_path"

    normalize_codex_reset_references "$output_path"

    echo "  ✅ Created: AGENTS.md"
}

# ============================================================
# copilot-instructions.md generation (Copilot auto-load file)
# ============================================================
# GitHub Copilot CLIは .github/copilot-instructions.md を自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をCopilot固有に置換して生成。
generate_copilot_instructions() {
    local github_dir="$SCRIPT_DIR/.github"
    local output_path="$github_dir/copilot-instructions.md"
    local claude_md="$SCRIPT_DIR/CLAUDE.md"

    echo "Generating: .github/copilot-instructions.md (Copilot auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping copilot-instructions.md generation."
        return 1
    fi

    mkdir -p "$github_dir"

    transform_claude_md "copilot" \
        "copilot-instructions.md" "copilot-instructions.local.md" \
        ".copilot/config.json" ".copilot/mcp-config.json" \
        "GitHub Copilot CLI" "$claude_md" "$output_path"

    echo "  ✅ Created: .github/copilot-instructions.md"
}

# ============================================================
# Kimi K2 auto-load files generation
# ============================================================
# Kimi K2 CLIは agents/default/agent.yaml + system.md を自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をKimi固有に置換して生成。
generate_kimi_instructions() {
    local agents_dir="$SCRIPT_DIR/agents/default"
    local system_md_path="$agents_dir/system.md"
    local agent_yaml_path="$agents_dir/agent.yaml"
    local claude_md="$SCRIPT_DIR/CLAUDE.md"

    echo "Generating: agents/default/system.md + agent.yaml (Kimi auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping Kimi auto-load generation."
        return 1
    fi

    mkdir -p "$agents_dir"

    transform_claude_md "kimi" \
        "agents/default/system.md" "agents/default/system.local.md" \
        ".kimi/config.json" ".kimi/mcp.json" \
        "Kimi K2 CLI" "$claude_md" "$system_md_path"

    echo "  ✅ Created: agents/default/system.md"

    # Generate agent.yaml (Kimi agent definition)
    cat > "$agent_yaml_path" <<'EOFYAML'
# Kimi K2 Agent Configuration
# Auto-generated by build_instructions.sh — do not edit manually
name: multi-agent-shogun
description: "Kimi K2 CLI agent for multi-agent-shogun system"
model: moonshot-k2.5
system_prompt_file: system.md
tools:
  - file_read
  - file_write
  - shell_exec
  - web_search
EOFYAML

    echo "  ✅ Created: agents/default/agent.yaml"
}

# Generate CLI auto-load files in parallel (each writes to a separate NTFS path)
generate_agents_md &
generate_copilot_instructions &
generate_kimi_instructions &
wait

echo ""
echo "=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
if [ -t 1 ]; then
    echo "Generated instruction files:"
    ls -lh "$OUTPUT_DIR"/*.md
    echo ""
    echo "CLI auto-load files:"
    [ -f "$SCRIPT_DIR/AGENTS.md" ] && ls -lh "$SCRIPT_DIR/AGENTS.md"
    [ -f "$SCRIPT_DIR/.github/copilot-instructions.md" ] && ls -lh "$SCRIPT_DIR/.github/copilot-instructions.md"
    [ -f "$SCRIPT_DIR/agents/default/system.md" ] && ls -lh "$SCRIPT_DIR/agents/default/system.md"
    [ -f "$SCRIPT_DIR/agents/default/agent.yaml" ] && ls -lh "$SCRIPT_DIR/agents/default/agent.yaml"
fi
