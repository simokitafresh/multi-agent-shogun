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
# §3.3: python3+yaml.safe_load回避。awk抽出→python3 -S(cmd_3632)
_PROJECT_DIR=""
if [[ "$CMD_ID" == "-" ]]; then
    CMD_TEXT="$(cat)"
else
    # awk抽出: shogun_to_karo.yamlからcmd blockのcommand/projectフィールドを取得
    _stk="$REPO_ROOT/queue/shogun_to_karo.yaml"
    CMD_TEXT=""
    _PROJECT=""
    if [[ -f "$_stk" ]]; then
        CMD_TEXT=$(awk -v target="$CMD_ID" '
        /^  [A-Za-z_]/ {
            id = $0; sub(/:.*/, "", id); gsub(/^[[:space:]]+/, "", id)
            in_target = (id == target)
            in_command = 0
            next
        }
        in_target && /^    command:[[:space:]]*\|/ { in_command = 1; next }
        in_target && /^    command:[[:space:]]*>/ { in_command = 1; next }
        in_target && /^    command:[[:space:]]*[^|>[:space:]]/ {
            v = $0; sub(/^    command:[[:space:]]*/, "", v)
            gsub(/^["'"'"']|["'"'"']$/, "", v)
            print v; next
        }
        in_target && in_command {
            if (/^      / || /^$/) { sub(/^      /, ""); print }
            else in_command = 0
        }
        ' "$_stk")
        _PROJECT=$(awk -v target="$CMD_ID" '
        /^  [A-Za-z_]/ {
            id = $0; sub(/:.*/, "", id); gsub(/^[[:space:]]+/, "", id)
            in_target = (id == target); next
        }
        in_target && /^    project:[[:space:]]/ {
            v = $0; sub(/^    project:[[:space:]]*/, "", v); gsub(/["'"'"']/, "", v)
            print v; exit
        }
        ' "$_stk")
        # AC count check
        _AC_COUNT=$(awk -v target="$CMD_ID" '
        /^  [A-Za-z_]/ {
            id = $0; sub(/:.*/, "", id); gsub(/^[[:space:]]+/, "", id)
            in_target = (id == target); in_ac = 0; next
        }
        in_target && /^    acceptance_criteria:/ { in_ac = 1; next }
        in_target && in_ac && /^      AC[0-9]+:/ { count++ }
        in_target && in_ac && /^    [^ ]/ { in_ac = 0 }
        END { print count+0 }
        ' "$_stk")
        [[ "$_AC_COUNT" -gt 4 ]] && echo "★ WARN(LG021): AC数=${_AC_COUNT} > 4。cmd分割を検討せよ(REQUEST_CHANGES候補)"
    fi
    # archiveフォールバック(awk抽出失敗時。archive=commands:ラッパー+同じインデント構造)
    if [[ -z "$CMD_TEXT" ]]; then
        for _af in "$REPO_ROOT"/queue/archive/cmds/"${CMD_ID}"_*.yaml; do
            [[ -f "$_af" ]] || continue
            CMD_TEXT=$(awk -v target="$CMD_ID" '
            /^  [A-Za-z_]/ {
                id = $0; sub(/:.*/, "", id); gsub(/^[[:space:]]+/, "", id)
                in_target = (id == target); in_command = 0; next
            }
            in_target && /^    command:[[:space:]]*\|/ { in_command = 1; next }
            in_target && /^    command:[[:space:]]*>/ { in_command = 1; next }
            in_target && /^    command:[[:space:]]*[^|>[:space:]]/ {
                v = $0; sub(/^    command:[[:space:]]*/, "", v)
                gsub(/^["'"'"']|["'"'"']$/, "", v)
                print v; next
            }
            in_target && in_command {
                if (/^      / || /^$/) { sub(/^      /, ""); print }
                else in_command = 0
            }
            ' "$_af")
            if [[ -n "$CMD_TEXT" ]]; then
                _PROJECT=$(awk -v target="$CMD_ID" '
                /^  [A-Za-z_]/ {
                    id = $0; sub(/:.*/, "", id); gsub(/^[[:space:]]+/, "", id)
                    in_target = (id == target); next
                }
                in_target && /^    project:[[:space:]]/ {
                    v = $0; sub(/^    project:[[:space:]]*/, "", v); gsub(/["'"'"']/, "", v)
                    print v; exit
                }
                ' "$_af")
                break
            fi
        done
    fi
    if [[ -z "$CMD_TEXT" ]]; then
        echo "FAIL: cmd_id '${CMD_ID}' not found in active/archive cmd YAML" >&2
        exit 1
    fi
    # project → project_dir 解決
    if [[ -n "$_PROJECT" ]] && [[ -f "$REPO_ROOT/config/projects.yaml" ]]; then
        _PROJECT_DIR=$(awk -v pid="$_PROJECT" '
        /- id:/ { cur = $3 }
        cur == pid && /path:/ { v = $2; gsub(/["'"'"']/, "", v); print v; exit }
        ' "$REPO_ROOT/config/projects.yaml")
    fi
fi

# Run verification (always python3 -S — no yaml import needed)
REPO_ROOT="$REPO_ROOT" CMD_ID="$CMD_ID" _PROJECT_DIR="${_PROJECT_DIR:-}" python3 -S -c "
import re, os, sys

repo_root = os.environ['REPO_ROOT']
cmd_id = os.environ.get('CMD_ID', '')
project_dir = os.environ.get('_PROJECT_DIR', '')
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

# --- LG070: ACで選択肢を閉じるな (Level 5 WARN) ---
if echo "$CMD_TEXT" | grep -qiE '(AかBか|どちらか|2択|二択|判定せよ.*(する|しない)|いずれか)'; then
    _choice_count=$(echo "$CMD_TEXT" | grep -oiE '(AかBか|どちらか|2択|二択)' | wc -l)
    if [[ "$_choice_count" -gt 0 ]]; then
        echo ""
        echo "WARN(LG070): ACが選択肢を閉じている可能性。第3の選択肢(どちらでもない/脱出路)が報告可能か確認せよ"
    fi
fi

# --- LG071: 判定基準は測定前に固定せよ (Level 5 WARN) ---
if echo "$CMD_TEXT" | grep -qiE '(閾値|threshold|以上|以下|未満|超えた|を超)'; then
    if ! echo "$CMD_TEXT" | grep -qiE '(判定基準|事前.*固定|baseline|ベースライン)'; then
        echo ""
        echo "WARN(LG071): 閾値/判定条件が検出されたが判定基準の事前固定の明示なし。観測後に基準が動くリスクを確認せよ"
    fi
fi

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
if [[ -n "$_target_path" ]] && [[ "$_target_path" == *.sh ]]; then
    _script_name=$(basename "$_target_path" .sh)
    # Skip overly generic names that would match too many files (WSL2 I/O perf)
    if [[ ${#_script_name} -le 3 ]]; then
        _affected=""
    else
        _affected=$(grep -rl "$_script_name" "$REPO_ROOT/tests/unit/"*.bats 2>/dev/null | xargs -r -I{} basename {} 2>/dev/null | sort -u || true)
    fi
    if [[ -n "$_affected" ]]; then
        echo ""
        echo "--- 関連テスト一覧(target: $_target_path) ---"
        echo "$_affected" | while read -r t; do echo "  tests/unit/$t"; done
        echo "  → 挙動変更時はこれらのfixture前提崩壊を事前検死で検証せよ"
    fi
fi
