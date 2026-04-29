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

    # Project directory detection (cmd_2426事故: shogunリポのみ検索→DM-Signalファイル不在と誤判定)
    PROJECT_DIR=$(REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" python3 -c "
import yaml, os
repo_root = os.environ['REPO_ROOT']
cmd_id = os.environ['CMD_ID']
with open(os.path.join(repo_root, 'queue', 'shogun_to_karo.yaml')) as f:
    data = yaml.safe_load(f)
cmds = data.get('commands', data)
cmd = cmds.get(cmd_id, {})
project = cmd.get('project', '')
project_dirs = {'dm-signal': '/mnt/c/Python_app/DM-Signal'}
print(project_dirs.get(project, ''))
" 2>/dev/null || echo "")
    export PROJECT_DIR

    # LG021 gate: AC数カウント (AC>4→WARN)
    AC_COUNT=$(REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" python3 -c "
import yaml, os
repo_root = os.environ['REPO_ROOT']
cmd_id = os.environ['CMD_ID']
with open(os.path.join(repo_root, 'queue', 'shogun_to_karo.yaml')) as f:
    data = yaml.safe_load(f)
cmds = data.get('commands', data)
cmd = cmds.get(cmd_id, {})
acs = cmd.get('acceptance_criteria', [])
print(len(acs) if isinstance(acs, list) else 0)
" 2>/dev/null || echo "0")
    if [[ "$AC_COUNT" -gt 4 ]]; then
        echo "★ WARN(LG021): AC数=${AC_COUNT} > 4。cmd分割を検討せよ(REQUEST_CHANGES候補)"
    fi
fi

# Run verification
REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" PROJECT_DIR="${PROJECT_DIR:-}" python3 -c "
import re, os, sys

repo_root = os.environ['REPO_ROOT']
project_dir = os.environ.get('PROJECT_DIR', '')
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
ac_blocks = re.findall(r'(AC\d+.*?)(?=AC\d+|$)', cmd_text, re.DOTALL)

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
    # Fallback: project directory (cmd_2426事故防止)
    if not exists and project_dir and not p.startswith('/'):
        alt_path = os.path.join(project_dir, p)
        if os.path.exists(alt_path):
            full_path = alt_path
            exists = True
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
        for p in sorted(paths):
            full_path = os.path.join(repo_root, p) if not p.startswith('/') else p
            if not os.path.exists(full_path):
                continue
            try:
                with open(full_path) as f:
                    for i, line in enumerate(f, 1):
                        if re.search(r'§' + re.escape(sec) + r'(?!\d)', line):
                            print(f'  {p} L{i}: \"{line.rstrip()[:100]}\"')
                            break
            except Exception:
                pass

# Gitignore check — detect gitignored files with commit ACs (workaround prevention)
import subprocess
gitignored = []
for p in sorted(paths):
    rel_path = p if not p.startswith('/') else os.path.relpath(p, repo_root)
    try:
        result = subprocess.run(['git', '-C', repo_root, 'check-ignore', '-q', rel_path],
                                capture_output=True, timeout=5)
        if result.returncode == 0:
            gitignored.append(rel_path)
    except Exception:
        pass

if gitignored:
    has_commit_ac = bool(re.search(r'commit|push|git\s+add', cmd_text, re.IGNORECASE))
    print(f'\n--- Gitignore Check ---')
    for gp in gitignored:
        if has_commit_ac:
            print(f'  [WARN] {gp} is gitignored but cmd has commit/push AC — verdict FAIL risk')
        else:
            print(f'  [INFO] {gp} is gitignored (commit不要)')

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


# Parallel work detection — cmd_idのcommitが既に存在するか警告 (GP-185: premature_shelve防止)
cmd_id = os.environ.get('CMD_ID', '')
if cmd_id and cmd_id != '-':
    try:
        result = subprocess.run(
            ['git', '-C', repo_root, 'log', f'--grep={cmd_id}', '--oneline', '-5'],
            capture_output=True, text=True, timeout=15
        )
        if result.stdout.strip():
            print(f'\n--- Parallel Work Detection (GP-185) ---')
            print(f'  [WARN] {cmd_id}を含むcommitが既に存在:')
            for line in result.stdout.strip().split('\n'):
                print(f'    {line}')
            print(f'  → 「既実装」判定注意: これらは忍者の実装であり既存コードではない(LG001)')
    except Exception:
        pass

if missing > 0:
    sys.exit(1)
else:
    print(f'\nRESULT: ALL PATHS VERIFIED')
    sys.exit(0)
" <<< "$CMD_TEXT"
