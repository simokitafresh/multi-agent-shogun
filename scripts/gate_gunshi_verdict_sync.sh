#!/usr/bin/env bash
# gate_gunshi_verdict_sync.sh — GATE CLEAR時にlogs/gunshi_review_log.yaml(+archive直近2件)の
# draft verdictをlogs/cmd_design_quality.yamlのgunshi_verdictへ反映する。
# Usage: bash scripts/gate_gunshi_verdict_sync.sh <cmd_id>
#
# cmd_karo_hotfix_t3s40_post_source_v6: cmd_complete_gate.shのGATE CLEAR終端に
# インラインで書かれていたこの処理を、durable worker(nohup+setsid)から呼べる
# 独立scriptへ抽出した(既存のgunshi_gate_reflux.shと同じパターン)。ロジックは
# 移動のみで変更なし。plain background `&` はこのプロセスと同じprocess groupに
# 留まるためtmux respawn-pane -k等のgroup-wide killで道連れに消える
# (semantic_causal_post_clear.shのnohup+setsidコメントと同じ理由)。

set -uo pipefail

CMD_ID="${1:?Usage: gate_gunshi_verdict_sync.sh <cmd_id>}"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/lock_path.sh
source "$SCRIPT_DIR/scripts/lib/lock_path.sh"

_GV_REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
_GV_ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
_GV_DQ_FILE="$SCRIPT_DIR/logs/cmd_design_quality.yaml"

if [ -f "$_GV_DQ_FILE" ] && [ -f "$_GV_REVIEW_LOG" ]; then
    _gv_result=$(
        (
            flock -w 10 200 || exit 1
            python3 - "$CMD_ID" "$_GV_REVIEW_LOG" "$_GV_ARCHIVE_DIR" "$_GV_DQ_FILE" 2>/dev/null <<'END_GV_PY'
import sys, re, os, glob, tempfile

cmd_id = sys.argv[1]
review_log = sys.argv[2]
archive_dir = sys.argv[3]
dq_file = sys.argv[4]

# データソース: gunshi_review_log.yaml + archive直近2ファイル
sources = []
if os.path.exists(review_log):
    sources.append(review_log)
archives = sorted(glob.glob(os.path.join(archive_dir, "gunshi_review_log*.yaml")))
sources.extend(archives[-2:])

# draft verdictを取得: REQUEST_CHANGESが一度でも出た場合はそちらを優先
found_rc = False
found_approve = False
for src in sources:
    try:
        with open(src, encoding='utf-8') as f:
            content = f.read()
    except Exception:
        continue
    for m in re.finditer(r'^- cmd_id:.*?(?=^- cmd_id:|\Z)', content, re.MULTILINE | re.DOTALL):
        entry = m.group(0)
        cm = re.match(r'^- cmd_id:\s*["\']?([^"\'\n]+)["\']?', entry)
        if not cm or cm.group(1).strip() != cmd_id:
            continue
        if 'review_type: draft' not in entry:
            continue
        vm = re.search(r'(?<![a-z_])verdict:\s*(\S+)', entry)
        if vm:
            v = vm.group(1).strip('"\'')
            if v == 'REQUEST_CHANGES':
                found_rc = True
            elif v == 'APPROVE':
                found_approve = True

if found_rc:
    new_verdict = 'REQUEST_CHANGES'
elif found_approve:
    new_verdict = 'LGTM'
else:
    print(f"[INFO] {cmd_id}: no draft verdict found, keeping existing")
    sys.exit(0)

# cmd_design_quality.yaml の対象cmd_idエントリのgunshi_verdictを更新
try:
    with open(dq_file, encoding='utf-8') as f:
        lines = f.readlines()
except Exception as e:
    print(f"[ERROR] Failed to read {dq_file}: {e}")
    sys.exit(0)

updated = 0
in_entry = False
match_entry = False
new_lines = []
for line in lines:
    if re.match(r'\s*- cmd_id:', line):
        cid_m = re.search(r'cmd_id:\s*["\']?([^"\'\n]+)["\']?', line)
        match_entry = bool(cid_m and cid_m.group(1).strip() == cmd_id)
        in_entry = True
    elif line.strip() and not line.startswith(' ') and not line.startswith('\t') and not line.strip().startswith('#'):
        in_entry = False
        match_entry = False
    if match_entry and re.match(r'\s+gunshi_verdict:', line):
        new_lines.append(re.sub(r'(gunshi_verdict:\s*)["\']?[^"\'\n]*["\']?', f'\\1"{new_verdict}"', line))
        updated += 1
    else:
        new_lines.append(line)

if updated > 0:
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(dq_file), suffix='.tmp')
        os.close(tmp_fd)
        with open(tmp_path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        os.replace(tmp_path, dq_file)
        print(f"{cmd_id}: gunshi_verdict → {new_verdict} ({updated} entries updated)")
    except Exception as e:
        print(f"[ERROR] Failed to write {dq_file}: {e}")
else:
    print(f"[INFO] {cmd_id}: no matching entries found in cmd_design_quality.yaml")
END_GV_PY
        ) 200>"$(lock_path "$_GV_DQ_FILE")"
    ) || _gv_result="[INFO] gunshi_verdict update failed (non-blocking)"
    echo "  ${_gv_result}"
else
    echo "  SKIP (cmd_design_quality.yaml or gunshi_review_log.yaml not found)"
fi
