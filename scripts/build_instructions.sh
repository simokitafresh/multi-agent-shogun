#!/usr/bin/env bash
# ============================================================
# Instruction File Build System
# ============================================================
# Combines instruction parts into complete instruction files
# for each role and CLI combination.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PARTS_DIR="$ROOT_DIR/instructions"
OUTPUT_DIR="$ROOT_DIR/instructions/generated"

# Source CLI profile lookup library (cmd_143 SSOT)
source "$SCRIPT_DIR/lib/cli_lookup.sh"

# Default CLI type (instruction files without prefix)
DEFAULT_CLI="claude"

mkdir -p "$OUTPUT_DIR"

echo "=== Instruction File Build System ==="
echo "Building instruction files..."

# ============================================================
# Helper: Get all CLI profile types from cli_profiles.yaml
# ============================================================
get_profile_types() {
    python3 -c "
import yaml
with open('${_CLI_LOOKUP_PROFILES}') as f:
    cfg = yaml.safe_load(f) or {}
profiles = cfg.get('profiles', {})
for p in profiles:
    print(p)
" 2>/dev/null
}

# ============================================================
# Helper function: Build a complete instruction file
# ============================================================
build_instruction_file() {
    local cli_type="$1"
    local role="$2"
    local output_filename="$3"
    local output_path="$OUTPUT_DIR/$output_filename"
    local original_file="$ROOT_DIR/instructions/${role}.md"

    echo "Building: $output_filename (CLI: $cli_type, Role: $role)"

    # Extract YAML front matter from original file
    if [ -f "$original_file" ]; then
        awk '/^---$/{if(++n==2) {print "---"; exit} if(n==1) next} n==1' "$original_file" > "$output_path"
        echo "" >> "$output_path"
    else
        # Minimal YAML front matter
        cat > "$output_path" <<EOFYAML
---
role: $role
version: "3.0"
cli_type: $cli_type
---

EOFYAML
    fi

    # Append role-specific content
    cat "$PARTS_DIR/roles/${role}_role.md" >> "$output_path"

    # Append common sections
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/protocol.md" >> "$output_path"
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/task_flow.md" >> "$output_path"
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/forbidden_actions.md" >> "$output_path"

    # Append CLI-specific tools section (dynamic file lookup)
    echo "" >> "$output_path"
    local tools_file="$PARTS_DIR/cli_specific/${cli_type}_tools.md"
    if [ -f "$tools_file" ]; then
        cat "$tools_file" >> "$output_path"
    else
        echo "  ⚠️  No CLI tools file for: $cli_type (${tools_file})"
    fi

    echo "  ✅ Created: $output_filename"
}

# ============================================================
# Build instruction files — profile-driven from cli_profiles.yaml
# ============================================================
ROLES="shogun karo ashigaru"
PROFILE_TYPES=$(get_profile_types)

# Default CLI — files without prefix
for role in $ROLES; do
    build_instruction_file "$DEFAULT_CLI" "$role" "${role}.md"
done

# Non-default profiles — files with cli_type prefix
for cli_type in $PROFILE_TYPES; do
    if [[ "$cli_type" != "$DEFAULT_CLI" ]]; then
        for role in $ROLES; do
            build_instruction_file "$cli_type" "$role" "${cli_type}-${role}.md"
        done
    fi
done

# CLI types not yet in cli_profiles.yaml (temporary — remove when profiles added)
for cli_type in copilot kimi; do
    if echo "$PROFILE_TYPES" | grep -q "^${cli_type}$"; then
        continue
    fi
    for role in $ROLES; do
        build_instruction_file "$cli_type" "$role" "${cli_type}-${role}.md"
    done
done

# ============================================================
# AGENTS.md generation (Codex auto-load file)
# ============================================================
# Codex CLIはリポジトリルートのAGENTS.mdを自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をCodex固有に置換して生成。
generate_agents_md() {
    # AGENTS.md = Codex CLI auto-load file
    # cli_type derived from profile, not hardcoded
    local cli_type
    cli_type=$(echo "$PROFILE_TYPES" | grep -v "^${DEFAULT_CLI}$" | head -1)
    if [[ -z "$cli_type" ]]; then
        echo "  ⚠️  No non-default CLI profile found. Skipping AGENTS.md generation."
        return 1
    fi

    local output_path="$ROOT_DIR/AGENTS.md"
    local claude_md="$ROOT_DIR/CLAUDE.md"
    local cli_display
    cli_display=$(cli_profile_get "$cli_type" "display_name")
    [[ -z "$cli_display" ]] && cli_display="${cli_type^} CLI"

    echo "Generating: AGENTS.md (${cli_type} auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping AGENTS.md generation."
        return 1
    fi

    sed \
        -e 's|CLAUDE\.md|AGENTS.md|g' \
        -e 's|CLAUDE\.local\.md|AGENTS.override.md|g' \
        -e "s|instructions/shogun\\.md|instructions/generated/${cli_type}-shogun.md|g" \
        -e "s|instructions/karo\\.md|instructions/generated/${cli_type}-karo.md|g" \
        -e "s|instructions/ashigaru\\.md|instructions/generated/${cli_type}-ashigaru.md|g" \
        -e "s|~/\\.claude/|~/.${cli_type}/|g" \
        -e "s|\\.claude\\.json|.${cli_type}/config.toml|g" \
        -e 's|\.mcp\.json|config.toml (mcp_servers section)|g' \
        -e "s|Claude Code|${cli_display}|g" \
        "$claude_md" > "$output_path"

    echo "  ✅ Created: AGENTS.md"
}

# ============================================================
# copilot-instructions.md generation (Copilot auto-load file)
# ============================================================
# GitHub Copilot CLIは .github/copilot-instructions.md を自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をCopilot固有に置換して生成。
generate_copilot_instructions() {
    local github_dir="$ROOT_DIR/.github"
    local output_path="$github_dir/copilot-instructions.md"
    local claude_md="$ROOT_DIR/CLAUDE.md"

    echo "Generating: .github/copilot-instructions.md (Copilot auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping copilot-instructions.md generation."
        return 1
    fi

    mkdir -p "$github_dir"

    sed \
        -e 's|CLAUDE\.md|copilot-instructions.md|g' \
        -e 's|CLAUDE\.local\.md|copilot-instructions.local.md|g' \
        -e 's|instructions/shogun\.md|instructions/generated/copilot-shogun.md|g' \
        -e 's|instructions/karo\.md|instructions/generated/copilot-karo.md|g' \
        -e 's|instructions/ashigaru\.md|instructions/generated/copilot-ashigaru.md|g' \
        -e 's|~/.claude/|~/.copilot/|g' \
        -e 's|\.claude\.json|.copilot/config.json|g' \
        -e 's|\.mcp\.json|.copilot/mcp-config.json|g' \
        -e 's|Claude Code|GitHub Copilot CLI|g' \
        "$claude_md" > "$output_path"

    echo "  ✅ Created: .github/copilot-instructions.md"
}

# ============================================================
# Kimi K2 auto-load files generation
# ============================================================
# Kimi K2 CLIは agents/default/agent.yaml + system.md を自動読み込みする。
# CLAUDE.mdを正本とし、Claude固有部分をKimi固有に置換して生成。
generate_kimi_instructions() {
    local agents_dir="$ROOT_DIR/agents/default"
    local system_md_path="$agents_dir/system.md"
    local agent_yaml_path="$agents_dir/agent.yaml"
    local claude_md="$ROOT_DIR/CLAUDE.md"

    echo "Generating: agents/default/system.md + agent.yaml (Kimi auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping Kimi auto-load generation."
        return 1
    fi

    mkdir -p "$agents_dir"

    # Generate system.md (CLAUDE.md → Kimi版)
    sed \
        -e 's|CLAUDE\.md|agents/default/system.md|g' \
        -e 's|CLAUDE\.local\.md|agents/default/system.local.md|g' \
        -e 's|instructions/shogun\.md|instructions/generated/kimi-shogun.md|g' \
        -e 's|instructions/karo\.md|instructions/generated/kimi-karo.md|g' \
        -e 's|instructions/ashigaru\.md|instructions/generated/kimi-ashigaru.md|g' \
        -e 's|~/.claude/|~/.kimi/|g' \
        -e 's|\.claude\.json|.kimi/config.json|g' \
        -e 's|\.mcp\.json|.kimi/mcp.json|g' \
        -e 's|Claude Code|Kimi K2 CLI|g' \
        "$claude_md" > "$system_md_path"

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

# Generate CLI auto-load files
generate_agents_md
generate_copilot_instructions
generate_kimi_instructions

echo ""
echo "=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Generated instruction files:"
ls -lh "$OUTPUT_DIR"/*.md
echo ""
echo "CLI auto-load files:"
[ -f "$ROOT_DIR/AGENTS.md" ] && ls -lh "$ROOT_DIR/AGENTS.md"
[ -f "$ROOT_DIR/.github/copilot-instructions.md" ] && ls -lh "$ROOT_DIR/.github/copilot-instructions.md"
[ -f "$ROOT_DIR/agents/default/system.md" ] && ls -lh "$ROOT_DIR/agents/default/system.md"
[ -f "$ROOT_DIR/agents/default/agent.yaml" ] && ls -lh "$ROOT_DIR/agents/default/agent.yaml"
