#!/usr/bin/env bash
# ac_physical_verify.sh — AC対象ファイルの物理的検証
# GP-065: draft reviewの「事前調査」を自動化。
# cmdテキストからファイルパス・行番号・セクション参照を抽出し、実在性を検証。
#
# 防御階層 Level 5(事前コンテキスト提供):
#   正しい答えを先に渡すことで、間違いが起きないよう先回りする。
#   Level 1-4(事後検出/事前予防/自動生成/フロー埋込)の上位層。
#
# Usage:
#   bash scripts/ac_physical_verify.sh <cmd_id>
#     → queue/shogun_to_karo.yaml から cmd テキストを抽出して検証
#   echo "AC text" | bash scripts/ac_physical_verify.sh -
#     → stdin から AC テキストを読んで検証
#
# Output: 忍者ナビゲーションシート(各AC対象の検証済みファイルパス+行内容)
# Exit: 0=全パス存在, 1=MISSINGあり

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CMD_ID="${1:-}"

if [[ -z "$CMD_ID" ]]; then
    echo "Usage: bash scripts/ac_physical_verify.sh <cmd_id>" >&2
    echo "       echo 'AC text' | bash scripts/ac_physical_verify.sh -" >&2
    exit 1
fi

# Get cmd text
if [[ "$CMD_ID" == "-" ]]; then
    CMD_TEXT="$(cat)"
else
    CMD_TEXT=$(REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" python3 -c "
import yaml, sys, os
repo_root = os.environ['REPO_ROOT']
cmd_id = os.environ['CMD_ID']
with open(os.path.join(repo_root, 'queue', 'shogun_to_karo.yaml')) as f:
    data = yaml.safe_load(f)
cmds = data.get('commands', data)
cmd = cmds.get(cmd_id, {})
text = cmd.get('command', '')
print(text)
" 2>/dev/null)
    if [[ -z "$CMD_TEXT" ]]; then
        echo "FAIL: cmd_id '${CMD_ID}' not found in shogun_to_karo.yaml" >&2
        exit 1
    fi
fi

# Run verification
REPO_ROOT="$REPO_ROOT" python3 -c "
import re, os, sys

repo_root = os.environ['REPO_ROOT']
cmd_text = sys.stdin.read()

# Extract file paths
path_patterns = [
    r'/mnt/c/[^\s,\"\'\)]+\.(?:md|yaml|sh|py|tsx?|jsx?)',  # absolute
    r'context/[^\s,\"\'\)]+\.md',  # context/
    r'projects/[^\s,\"\'\)]+\.(?:yaml|md)',  # projects/
    r'instructions/[^\s,\"\'\)]+\.md',  # instructions/
    r'scripts/[^\s,\"\'\)]+\.sh',  # scripts/
    r'queue/[^\s,\"\'\)]+\.yaml',  # queue/
    r'docs/[^\s,\"\'\)]+\.md',  # docs/
    r'CLAUDE\.md',  # CLAUDE.md
]

paths = set()
for pat in path_patterns:
    for m in re.finditer(pat, cmd_text):
        paths.add(m.group(0))

# Extract line number references (L123, line 123)
line_refs = re.findall(r'L(\d+)', cmd_text)

# Extract section references (§27)
section_refs = re.findall(r'§(\d+)', cmd_text)

# Extract AC blocks
ac_blocks = re.findall(r'(AC\d+[^A]*?)(?=AC\d+|$)', cmd_text, re.DOTALL)

print('=== AC Physical Verification ===')
print()

# Verify paths
missing = 0
verified = 0
for p in sorted(paths):
    if p.startswith('/'):
        full_path = p
    else:
        full_path = os.path.join(repo_root, p)

    exists = os.path.exists(full_path)
    if exists:
        verified += 1
        # Get file size
        size = os.path.getsize(full_path)
        lines_count = 0
        try:
            with open(full_path) as f:
                lines_count = sum(1 for _ in f)
        except:
            pass
        print(f'  [OK] {p} ({lines_count} lines)')
    else:
        missing += 1
        print(f'  [MISSING] {p}')

print(f'\nPaths: {verified} verified, {missing} missing')

# Verify line contents
if line_refs:
    print(f'\n--- Line References ---')
    for ln_str in line_refs:
        ln = int(ln_str)
        # Find which file this line likely belongs to (check all extracted paths)
        for p in sorted(paths):
            full_path = os.path.join(repo_root, p) if not p.startswith('/') else p
            if not os.path.exists(full_path):
                continue
            try:
                with open(full_path) as f:
                    file_lines = f.readlines()
                if ln <= len(file_lines):
                    content = file_lines[ln-1].rstrip()[:100]
                    if content.strip():  # skip empty lines
                        print(f'  {p} L{ln}: \"{content}\"')
            except:
                pass

# Section verification
if section_refs:
    print(f'\n--- Section References ---')
    for sec in section_refs:
        sec_pat = f'§{sec}'
        for p in sorted(paths):
            full_path = os.path.join(repo_root, p) if not p.startswith('/') else p
            if not os.path.exists(full_path):
                continue
            try:
                with open(full_path) as f:
                    for i, line in enumerate(f, 1):
                        if sec_pat in line or f'## §{sec}' in line or f'§{sec} ' in line:
                            print(f'  {p} L{i}: \"{line.rstrip()[:100]}\"')
                            break
            except:
                pass

# Navigation sheet for ninja
print(f'\n=== Navigation Sheet ===')
for i, block in enumerate(ac_blocks):
    block = block.strip()
    if not block:
        continue
    # Find paths in this AC block
    ac_paths = set()
    for pat in path_patterns:
        for m in re.finditer(pat, block):
            ac_paths.add(m.group(0))
    ac_lines = re.findall(r'L(\d+)', block)
    ac_sections = re.findall(r'§(\d+)', block)

    ac_id = re.match(r'(AC\d+)', block)
    ac_label = ac_id.group(1) if ac_id else f'Block{i}'

    refs = []
    if ac_paths:
        refs.append(', '.join(sorted(ac_paths)))
    if ac_lines:
        refs.append(f'L{\"L\".join(ac_lines)}')
    if ac_sections:
        refs.append(f'§{\"§\".join(ac_sections)}')

    if refs:
        print(f'  {ac_label}: {\" | \".join(refs)}')

if missing > 0:
    sys.exit(1)
else:
    print(f'\nRESULT: ALL PATHS VERIFIED')
    sys.exit(0)
" <<< "$CMD_TEXT"
