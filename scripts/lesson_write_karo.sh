#!/bin/bash
# semantic-links: [[教訓ライフサイクル管理]]
# lesson_write_karo.sh — 家老専用教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write_karo.sh "タイトル" "詳細" cmd_XXX ["発動条件"] ["実行手順"] [--origin "[[cmd_XXX]]"] [--role karo|gunshi]
# → projects/infra/lessons_{role}.yaml に追記（default: karo）

set -e

_lwk_self="${BASH_SOURCE[0]}"; [[ "$_lwk_self" != /* ]] && _lwk_self="$PWD/$_lwk_self"
SCRIPT_DIR="${_lwk_self%/scripts/lesson_write_karo.sh}"
if [ -f "$SCRIPT_DIR/scripts/lib/lock_path.sh" ]; then
    # Use the shared helper so role lesson writers and generic lesson writers
    # serialize through the same stable lock namespace.
    source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
else
    lock_path() { printf '%s.lock' "$1"; }
fi
TITLE="${1:-}"
DETAIL="${2:-}"
SOURCE_CMD="${3:-}"
shift 3 || true

WHEN_COND="同種の状況が再発した時"
HOW_ACTION="$DETAIL"
ORIGIN=""
LESSON_ROLE="karo"
_positional=0
while [ $# -gt 0 ]; do
    case "$1" in
        --origin)
            ORIGIN="${2:-}"
            shift 2
            ;;
        --when)
            WHEN_COND="${2:-}"
            shift 2
            ;;
        --how)
            HOW_ACTION="${2:-}"
            shift 2
            ;;
        --role)
            LESSON_ROLE="${2:-}"
            shift 2
            ;;
        *)
            _positional=$((_positional + 1))
            if [ "$_positional" -eq 1 ]; then
                WHEN_COND="$1"
            elif [ "$_positional" -eq 2 ]; then
                HOW_ACTION="$1"
            fi
            shift
            ;;
    esac
done

case "$LESSON_ROLE" in
    karo|gunshi) ;;
    *)
        echo "ERROR: --role は karo または gunshi を指定せよ: $LESSON_ROLE" >&2
        exit 1
        ;;
esac

if [ -z "$ORIGIN" ]; then
    if [[ "$SOURCE_CMD" =~ ^cmd_ ]]; then
        ORIGIN="[[${SOURCE_CMD}]]"
    else
        ORIGIN="未指定"
    fi
fi

# Validate arguments
if [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write_karo.sh \"タイトル\" \"詳細\" cmd_XXX [\"発動条件\"] [\"実行手順\"] [--origin \"[[cmd_XXX]]\"] [--role karo|gunshi]" >&2
    exit 1
fi

# Detail quality gate
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 10 ]; then
    echo "ERROR: detail が10文字未満 (${DETAIL_LEN}文字)。具体的な内容を記載せよ" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/infra/lessons_${LESSON_ROLE}.yaml"
LOCKFILE="$(lock_path "$LESSONS_FILE")"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Entry count gate — 家老台帳のみ肥大化防止 (v2統合後: 22件→上限35件)
ENTRY_COUNT=$(grep -c '^- id:' "$LESSONS_FILE" 2>/dev/null || echo 0)
if [ "$LESSON_ROLE" = "karo" ] && [ "$ENTRY_COUNT" -ge 35 ]; then
    echo "BLOCK: lessons_karo.yaml が ${ENTRY_COUNT}件に到達(上限35件)。" >&2
    echo "  新規追加の前に既存教訓を統合・パターン昇格せよ。" >&2
    echo "  個別事故→パターンに昇格し件数を減らしてから再実行。" >&2
    echo "  参考: docs/research/lessons_karo_v1_archive.md (92件→22件の統合実績)" >&2
    exit 1
fi

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export LESSONS_FILE TIMESTAMP TITLE DETAIL SOURCE_CMD ORIGIN LESSON_ROLE
        export WHEN_COND HOW_ACTION
        python3 << 'PYEOF'
import yaml, os, sys
from difflib import SequenceMatcher

_CLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
title = os.environ["TITLE"]
detail = os.environ["DETAIL"]
source_cmd = os.environ.get("SOURCE_CMD", "")
origin = os.environ.get("ORIGIN", "未指定")
lesson_role = os.environ.get("LESSON_ROLE", "karo")
when_cond = os.environ.get("WHEN_COND", "")
how_action = os.environ.get("HOW_ACTION", "")

with open(lessons_file, encoding='utf-8') as f:
    data = yaml.load(f, Loader=_CLoader)

if data is None:
    data = {}
lessons = data.get('lessons', [])

# Entry count gate (flock内正確チェック: race condition防止)
if lesson_role == "karo" and len(lessons) >= 35:
    print(f'BLOCK: lessons_karo.yaml が {len(lessons)}件に到達(上限35件)。', file=sys.stderr)
    print('  新規追加の前に既存教訓を統合・パターン昇格せよ。', file=sys.stderr)
    print('  個別事故→パターンに昇格し件数を減らしてから再実行。', file=sys.stderr)
    print('  参考: docs/research/lessons_karo_v1_archive.md (92件→22件の統合実績)', file=sys.stderr)
    sys.exit(1)

# Find max numeric ID (LK/LG format)
id_prefix = "LG" if lesson_role == "gunshi" else "LK"
max_id = 0
for lesson in lessons:
    lid = lesson.get('id', '')
    if lid.startswith(id_prefix):
        try:
            num = int(lid[len(id_prefix):])
            if num > max_id:
                max_id = num
        except ValueError:
            pass

new_id = max_id + 1
new_id_str = f'{id_prefix}{new_id:03d}'

# Duplicate title check
for lesson in lessons:
    existing_title = lesson.get('title', '')
    ratio = SequenceMatcher(None, title, existing_title).ratio()
    if ratio > 0.75:
        print(f'ERROR: 類似教訓あり: {lesson.get("id","")}: {existing_title} (類似度: {ratio:.0%})', file=sys.stderr)
        print(f'重複を確認して再実行せよ', file=sys.stderr)
        sys.exit(1)

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
# 既存データを書き換えず、新エントリを末尾に追記
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
    f.write(f'  origin: {_sv(origin)}\n')
    f.write(f'  detail: {_sv(detail)}\n')
    f.write(f'  source_cmd: {_sv(source_cmd)}\n')
    f.write(f'  when: {_sv(when_cond)}\n')
    f.write(f'  how: {_sv(how_action)}\n')
    f.write(f'  created_at: {_sv(timestamp)}\n')

print(f'{new_id_str} added to {lessons_file}')
PYEOF

    ) 200>"$LOCKFILE"; then
        # DB INSERT: eventsテーブルへ教訓記録（非ブロック）
        if [ -f "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" ]; then
            _LW_KARO_NEW_ID=$(grep '^- id:' "$LESSONS_FILE" | tail -1 | sed "s/^- id: '//;s/'\$//" | tr -d "'" 2>/dev/null || true)
            python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" lesson \
                --lesson-id "${_LW_KARO_NEW_ID:-unknown}" \
                --title "$TITLE" \
                --detail "$DETAIL" \
                --source-cmd "${SOURCE_CMD:-}" \
                --agent "$LESSON_ROLE" \
                --ts "$(date -Is)" \
                --project "infra" \
                --source-file "$LESSONS_FILE" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write_karo] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write_karo] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
