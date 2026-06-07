#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]]
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

_apv_self="${BASH_SOURCE[0]:-$0}"
[[ "$_apv_self" != /* ]] && _apv_self="$PWD/$_apv_self"
SCRIPT_DIR="${_apv_self%/*}"
REPO_ROOT="${SCRIPT_DIR%/*}"

CMD_ID="${1:-}"
CMD_TEXT=""

if [[ -z "$CMD_ID" ]]; then
    echo "Usage: bash scripts/ac_physical_verify.sh <cmd_id>" >&2
    echo "       echo 'AC text' | bash scripts/ac_physical_verify.sh -" >&2
    exit 1
fi

# Get cmd text
if [[ "$CMD_ID" == "-" ]]; then
    CMD_TEXT="$(cat)"
fi

PYTHON_CMD=(python3)
if [[ "$CMD_ID" == "-" ]]; then
    PYTHON_CMD=(python3 -S)
fi

# Run verification
REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" "${PYTHON_CMD[@]}" -c "
import re, os, sys

repo_root = os.environ['REPO_ROOT']
cmd_id = os.environ.get('CMD_ID', '')
project_dir = ''

if cmd_id == '-':
    cmd_text = sys.stdin.read()
else:
    try:
        import glob
        import yaml

        cmd = {}
        candidate_files = [os.path.join(repo_root, 'queue', 'shogun_to_karo.yaml')]
        candidate_files.extend(
            sorted(glob.glob(os.path.join(repo_root, 'queue', 'archive', 'cmds', f'{cmd_id}_*.yaml')), reverse=True)
        )
        for candidate in candidate_files:
            if not os.path.exists(candidate):
                continue
            with open(candidate) as f:
                data = yaml.safe_load(f) or {}
            cmds = data.get('commands', data)
            if isinstance(cmds, dict) and isinstance(cmds.get(cmd_id), dict):
                cmd = cmds[cmd_id]
                break
            if isinstance(cmds, list):
                for entry in cmds:
                    if isinstance(entry, dict) and entry.get('id') == cmd_id:
                        cmd = entry
                        break
            if cmd:
                break
        cmd_text = cmd.get('command', '')
        if not cmd_text:
            print(f\"FAIL: cmd_id '{cmd_id}' not found in active/archive cmd YAML\", file=sys.stderr)
            sys.exit(1)

        project = cmd.get('project', '')
        project_dirs = {'dm-signal': '/mnt/c/Python_app/DM-Signal'}
        project_dir = project_dirs.get(project, '')

        acs = cmd.get('acceptance_criteria', [])
        ac_count = len(acs) if isinstance(acs, list) else 0
        if ac_count > 4:
            print(f'★ WARN(LG021): AC数={ac_count} > 4。cmd分割を検討せよ(REQUEST_CHANGES候補)')
    except Exception as exc:
        print(f\"FAIL: cmd_id '{cmd_id}' could not be loaded: {exc}\", file=sys.stderr)
        sys.exit(1)

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
file_cache = {}
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
    lines = []
    if exists:
        verified += 1
        try:
            with open(full_path, errors='replace') as f:
                lines = f.readlines()
        except Exception:
            lines = []
        lines_count = len(lines)
        print(f'  [OK] {p} ({lines_count} lines)')
    else:
        missing += 1
        print(f'  [MISSING] {p}')
    file_cache[p] = (exists, full_path, lines)

print(f'\nPaths: {verified} verified, {missing} missing')

# Verify line contents
if line_refs:
    print(f'\n--- Line References ---')
    for ln_str in line_refs:
        ln = int(ln_str)
        # Find which file this line likely belongs to (check all extracted paths)
        for p in sorted(paths):
            exists, _full_path, file_lines = file_cache.get(p, (False, '', []))
            if not exists:
                continue
            try:
                if ln <= len(file_lines):
                    content = file_lines[ln-1].rstrip()[:100]
                    if content.strip():  # skip empty lines
                        print(f'  {p} L{ln}: \"{content}\"')
            except Exception:
                pass

# Section verification
if section_refs:
    print(f'\n--- Section References ---')
    for sec in section_refs:
        for p in sorted(paths):
            exists, _full_path, file_lines = file_cache.get(p, (False, '', []))
            if not exists:
                continue
            try:
                for i, line in enumerate(file_lines, 1):
                    if re.search(r'§' + re.escape(sec) + r'(?!\d)', line):
                        print(f'  {p} L{i}: \"{line.rstrip()[:100]}\"')
                        break
            except Exception:
                pass

# Gitignore check — detect gitignored files with commit ACs (workaround prevention)
gitignored = []
rel_paths = []
has_commit_ac = bool(re.search(r'commit|push|git\s+add', cmd_text, re.IGNORECASE))
for p in sorted(paths):
    rel_path = p if not p.startswith('/') else os.path.relpath(p, repo_root)
    rel_paths.append(rel_path)
if rel_paths and (cmd_id != '-' or has_commit_ac):
    try:
        import subprocess
        result = subprocess.run(
            ['git', '-C', repo_root, 'check-ignore', '--stdin'],
            input='\n'.join(rel_paths) + '\n',
            capture_output=True, text=True, timeout=5
        )
        gitignored = [line for line in result.stdout.splitlines() if line]
    except Exception:
        gitignored = []

if gitignored:
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
        import subprocess
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

# LG003 gate: 未検証前提の検出 — 「未実装」「未対応」「のはず」「と思われる」を検出しWARN
lg003_patterns = [
    (r'未実装', '未実装'),
    (r'未対応', '未対応'),
    (r'のはず', 'のはず'),
    (r'と思われる', 'と思われる'),
    (r'おそらく', 'おそらく'),
]
lg003_hits = []
for pat, label in lg003_patterns:
    for m in re.finditer(pat, cmd_text):
        start = max(0, m.start() - 20)
        end = min(len(cmd_text), m.end() + 20)
        context = cmd_text[start:end].replace('\n', ' ').strip()
        lg003_hits.append((label, context))
if lg003_hits:
    print(f'\n--- LG003: 未検証前提の検出 ---')
    for label, ctx in lg003_hits[:5]:
        print(f'  [WARN] 「{label}」: ...{ctx}...')
    print(f'  → 現物確認証拠(grep/git show)なしに信頼するな。前提を裏取りせよ')

# LG037: command欄ファイル参照の3分類リマインド
# cmd_text = command欄の内容そのもの(command:ヘッダなし)
cmd_file_refs = re.findall(r'(?:scripts|tools|skills)/[\w/._-]+\.(?:sh|py|md)', cmd_text)
if cmd_file_refs:
    unique_refs = sorted(set(cmd_file_refs))
    print(f'\n--- LG037: command欄ファイル参照 ({len(unique_refs)}件) ---')
    for ref in unique_refs:
        print(f'  {ref}')
    print(f'  → 各参照を分類せよ: 変更対象 / 既存依存(verified) / 実行のみ(変更対象外)')
    print(f'  → 実行のみなら cmd本文に「実行のみ・変更対象外」と明記させよ(LG037)')

if missing > 0:
    sys.exit(1)
else:
    print(f'\nRESULT: ALL PATHS VERIFIED')
    sys.exit(0)
" <<< "$CMD_TEXT"

if [[ "$CMD_ID" == "-" ]]; then
    exit 0
fi

# --- Adaptive Gating冷え観点サマリ (draft review時の盲点提示) ---
REVIEW_LOG="${REPO_ROOT}/logs/gunshi_review_log.yaml"
if [ -f "$REVIEW_LOG" ]; then
    _cold=$(awk '
        /finding_categories:/ {
            line=$0; gsub(/.*finding_categories: *\[?/, "", line); gsub(/\].*/, "", line)
            gsub(/ /, "", line); split(line,a,",")
            for(i in a) if(a[i]!="") cats[a[i]]++
            n++
        }
        END {
            if (n<10) exit
            split("assumptions,numbers,simulation,premortem,north_star,ambiguity,adversarial",all,",")
            for (i in all) if (!(all[i] in cats)) printf "%s ", all[i]
        }
    ' <(tail -200 "$REVIEW_LOG") 2>/dev/null)
    if [ -n "$_cold" ]; then
        echo ""
        echo "--- Adaptive Gating: 冷え観点 ---"
        echo "  直近レビューで未使用: ${_cold}"
        echo "  → これらの観点を意識的に検討し、finding_categoriesに記録せよ"
    fi
fi

# --- 関連テスト一覧(Level 5: 事前コンテキスト提供) ---
# target_pathのスクリプト名でtests/unit/*.batsを検索し、変更影響テストを表示
_target_path=""
if [[ "$CMD_ID" != "-" ]] && [[ -f "$REPO_ROOT/queue/shogun_to_karo.yaml" ]]; then
    _target_path=$(grep -A2 "^  *${CMD_ID}:" "$REPO_ROOT/queue/shogun_to_karo.yaml" 2>/dev/null | grep 'target_path:' | head -1 | sed 's/.*target_path: *//' | tr -d '"' | tr -d "'" || true)
fi
if [[ -z "$_target_path" ]] && [[ "$CMD_ID" != "-" ]]; then
    for _cf in "$REPO_ROOT"/queue/archive/cmds/"${CMD_ID}"_*.yaml; do
        [[ -f "$_cf" ]] || continue
        _target_path=$(grep 'target_path:' "$_cf" 2>/dev/null | head -1 | sed 's/.*target_path: *//' | tr -d '"' | tr -d "'")
        [[ -n "$_target_path" ]] && break
    done
fi
if [[ -z "$_target_path" ]]; then
    for _tf in "$REPO_ROOT"/queue/tasks/*.yaml; do
        [[ -f "$_tf" ]] || continue
        grep -q "parent_cmd:.*${CMD_ID}" "$_tf" 2>/dev/null && {
            _target_path=$(grep 'target_path:' "$_tf" | head -1 | sed 's/.*target_path: *//' | tr -d '"' | tr -d "'")
            break
        }
    done
fi
if [[ -n "$_target_path" ]]; then
    _script_name=$(basename "$_target_path" .sh)
    _affected=$(grep -rl "$_script_name" "$REPO_ROOT/tests/unit/"*.bats 2>/dev/null | xargs -r -I{} basename {} 2>/dev/null | sort -u || true)
    if [[ -n "$_affected" ]]; then
        echo ""
        echo "--- 関連テスト一覧(target: $_target_path) ---"
        echo "$_affected" | while read -r t; do echo "  tests/unit/$t"; done
        echo "  → 挙動変更時はこれらのfixture前提崩壊を事前検死で検証せよ"
    fi
fi
