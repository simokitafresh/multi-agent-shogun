#!/bin/bash
# lesson_write_shogun.sh — 将軍専用教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write_shogun.sh "タイトル" "詳細" cmd_XXX ["enforcement記述"]
#        bash scripts/lesson_write_shogun.sh --supersedes LS005 LS029 "新しい検証で覆された"
# → projects/infra/lessons_shogun.yaml に追記 or 既存教訓にsuperseded_by追記
# enforcement省略時はautomated: false, enforcement: "未自動化"で登録

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LESSONS_FILE="$SCRIPT_DIR/projects/infra/lessons_shogun.yaml"
LOCKFILE="${LESSONS_FILE}.lock"

# --- Mode: --supersedes (古い教訓を非優先化) ---
if [ "${1:-}" = "--supersedes" ]; then
    OLD_ID="${2:-}"
    NEW_ID="${3:-}"
    REASON="${4:-}"
    if [ -z "$OLD_ID" ] || [ -z "$NEW_ID" ]; then
        echo "Usage: lesson_write_shogun.sh --supersedes LS00X LS00Y \"覆された理由\"" >&2
        exit 1
    fi
    if [ ! -f "$LESSONS_FILE" ]; then
        echo "ERROR: $LESSONS_FILE not found." >&2
        exit 1
    fi
    # Check old lesson exists
    if ! grep -q "id: .*${OLD_ID}" "$LESSONS_FILE"; then
        echo "ERROR: ${OLD_ID} not found in lessons_shogun.yaml" >&2
        exit 1
    fi
    # Append superseded_by field using python (flock protected)
    (
        flock -w 10 200 || { echo "ERROR: lock timeout" >&2; exit 1; }
        export LESSONS_FILE OLD_ID NEW_ID REASON
        python3 << 'PYEOF'
import os
old_id = os.environ["OLD_ID"]
new_id = os.environ["NEW_ID"]
reason = os.environ.get("REASON", "")
lessons_file = os.environ["LESSONS_FILE"]

with open(lessons_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find the line with old_id and add superseded_by after created_at
found = False
output = []
for i, line in enumerate(lines):
    output.append(line)
    if f"id: '{old_id}'" in line or f'id: {old_id}' in line:
        found = True
    # Insert superseded_by after enforcement line (last field of the entry)
    if found and line.strip().startswith('enforcement:'):
        reason_text = f" ({reason})" if reason else ""
        output.append(f"  superseded_by: '{new_id}{reason_text}'\n")
        found = False

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.writelines(output)

print(f'{old_id} marked as superseded by {new_id}')
PYEOF
    ) 200>"$LOCKFILE"
    exit 0
fi

# --- Mode: normal (新教訓追記) ---
TITLE="${1:-}"
DETAIL="${2:-}"
SOURCE_CMD="${3:-}"
ENFORCEMENT="${4:-未自動化}"

# Validate arguments
if [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write_shogun.sh \"タイトル\" \"詳細\" cmd_XXX [\"enforcement記述\"]" >&2
    exit 1
fi

# Enforcement quality gate — "existing automation" references do not create a new
# environmental change. A lesson with automation=true must point to a concrete new
# gate/hook/check/file that can strengthen the next cycle.
if [ "$ENFORCEMENT" != "未自動化" ]; then
    if printf '%s\n' "$ENFORCEMENT" | grep -Eq '既存自動強制|既存の?自動強制|既存(の)?(gate|hook|チェック|仕組み|自動化)?のみ|^既存$|^既存[[:space:]]*$'; then
        echo "BLOCK: enforcement が既存参照のみです。新規環境変化(新ファイルパス/新チェック名/gate/hook等)を記載せよ。" >&2
        echo "  例: type=gate; file=scripts/gates/gate_x.sh; pattern=new_check_name" >&2
        exit 1
    fi
fi

# Detail quality gate — 将軍教訓は具体的事故+原因+修正を含むべし
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 30 ]; then
    echo "ERROR: detail が30文字未満 (${DETAIL_LEN}文字)。事故状況+原因+修正を具体的に記載せよ" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/infra/lessons_shogun.yaml"
LOCKFILE="${LESSONS_FILE}.lock"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

# Entry count gate — 肥大化防止 (v2統合後: 21件→上限35件)
ENTRY_COUNT=$(grep -c '^- id:' "$LESSONS_FILE" 2>/dev/null || echo 0)
if [ "$ENTRY_COUNT" -ge 35 ]; then
    echo "BLOCK: lessons_shogun.yaml が ${ENTRY_COUNT}件に到達(上限35件)。" >&2
    echo "  新規追加の前に既存教訓を統合・パターン昇格せよ。" >&2
    echo "  個別事故→パターンに昇格し件数を減らしてから再実行。" >&2
    echo "  参考: docs/research/lessons_shogun_v1_archive.md (97件→21件の統合実績)" >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Determine automated status from enforcement field
AUTOMATED="false"
if [ "$ENFORCEMENT" != "未自動化" ]; then
    AUTOMATED="true"
fi

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    # Exit codes: 0=success, 2=lock timeout(retry), other=python3 error(abort)
    (
        flock -w 10 200 || exit 2

        export LESSONS_FILE TIMESTAMP TITLE DETAIL SOURCE_CMD ENFORCEMENT AUTOMATED
        python3 << 'PYEOF'
import yaml, os, sys
from difflib import SequenceMatcher

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
title = os.environ["TITLE"]
detail = os.environ["DETAIL"]
source_cmd = os.environ.get("SOURCE_CMD", "")
enforcement = os.environ.get("ENFORCEMENT", "未自動化")
automated = os.environ.get("AUTOMATED", "false")

with open(lessons_file, encoding='utf-8') as f:
    data = yaml.safe_load(f)

lessons = data.get('lessons', [])

# Find max numeric ID (LS format: LS001, LS-A01, etc.)
max_id = 0
for lesson in lessons:
    lid = str(lesson.get('id', ''))
    if lid.startswith('LS'):
        # Extract trailing digits: LS097→97, LS-A01→01, LS-A21→21
        import re
        m = re.search(r'(\d+)$', lid)
        if m:
            try:
                num = int(m.group(1))
                if num > max_id:
                    max_id = num
            except ValueError:
                pass

new_id = max_id + 1
new_id_str = f'LS{new_id:03d}'

# Duplicate title check
for lesson in lessons:
    existing_title = lesson.get('title', '')
    ratio = SequenceMatcher(None, title, existing_title).ratio()
    if ratio > 0.75:
        print(f'ERROR: 類似教訓あり: {lesson.get("id","")}: {existing_title} (類似度: {ratio:.0%})', file=sys.stderr)
        print(f'重複を確認して再実行せよ', file=sys.stderr)
        sys.exit(1)

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
sq = chr(39)
def _sv(v):
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('    ' + ln for ln in s.split('\n'))
    return sq + s.replace(sq, sq+sq) + sq

with open(lessons_file, 'rb') as f:
    f.seek(0, 2)
    size = f.tell()
    needs_nl = False
    if size > 0:
        f.seek(-1, 2)
        needs_nl = f.read(1) != b'\n'

with open(lessons_file, 'a', encoding='utf-8') as f:
    if needs_nl:
        f.write('\n')
    f.write(f'- id: {_sv(new_id_str)}\n')
    f.write(f'  title: {_sv(title)}\n')
    f.write(f'  detail: {_sv(detail)}\n')
    f.write(f'  source_cmd: {_sv(source_cmd)}\n')
    f.write(f'  created_at: {_sv(timestamp)}\n')
    f.write(f'  automated: {automated}\n')
    f.write(f'  enforcement: {_sv(enforcement)}\n')

print(f'{new_id_str} added to {lessons_file}')
PYEOF

    ) 200>"$LOCKFILE"
    rc=$?
    if [ $rc -eq 0 ]; then
        exit 0
    elif [ $rc -eq 2 ]; then
        # Lock timeout — retry
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write_shogun] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write_shogun] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    else
        # Python3 error (duplicate, etc.) — abort immediately
        exit $rc
    fi
done
