#!/usr/bin/env bash
# semantic-links: [[cmd設計品質ログ]]
# ============================================================
# archive_completed.sh
# 完了cmdと古い戦果をアーカイブし、ファイルを軽量化する
# 家老がcmd完了判定後に呼び出す
#
# Usage: bash scripts/archive_completed.sh [keep_results] [cmd_id]
#   keep_results: ダッシュボードに残す戦果数（デフォルト: 3）
#   cmd_id: 指定時にqueue/gates/{cmd_id}/archive.doneフラグを出力
# ============================================================
set -euo pipefail

# tmpファイルの後始末
TMP=$(mktemp -d)
export TMP  # GP-080: PythonのENVIRON参照用
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ARCHIVE_COMPLETED_PROJECT_DIR: テスト用の差し替え口。未設定時は実リポジトリ。
PROJECT_DIR="${ARCHIVE_COMPLETED_PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/field_get.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/lock_path.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/defense_overhead_writer.sh"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
CHANGELOG_FILE="$PROJECT_DIR/queue/completed_changelog.yaml"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive"
ARCHIVE_CMD_DIR="$ARCHIVE_DIR/cmds"
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
DASHBOARD_TEMPLATE="$PROJECT_DIR/config/dashboard_template.md"
REPORTS_DIR="$PROJECT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$ARCHIVE_DIR/reports"
CHRONICLE_FILE="$PROJECT_DIR/context/cmd-chronicle.md"
CHRONICLE_ARCHIVE_DIR="$PROJECT_DIR/archive/cmd-chronicle"
PENDING_DECISIONS_FILE="$PROJECT_DIR/queue/pending_decisions.yaml"
PENDING_DECISIONS_ARCHIVE="$ARCHIVE_DIR/pending_decisions_archive.yaml"
usage_error() {
    echo "Usage: archive_completed.sh [keep_results] [cmd_id]" >&2
    echo "  keep_results: 正の整数（省略時3）" >&2
    echo "  cmd_id: cmd_XXX形式（任意）" >&2
    echo "受け取った引数: $*" >&2
}

# 引数パース: $1がcmd_で始まる場合はCMD_IDとして扱う
if [[ "${1:-}" == cmd_* ]]; then
    CMD_ID="$1"
    KEEP_RESULTS=${2:-3}
else
    KEEP_RESULTS=${1:-3}
    CMD_ID=${2:-""}
fi

if [[ ! "$KEEP_RESULTS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: keep_results は正の整数で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi

if [ -n "$CMD_ID" ] && [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: cmd_id は cmd_XXX 形式で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi
if [ -n "$CMD_ID" ] && [[ ! "${SHOGUN_COMPLETION_GENERATION:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: SHOGUN_COMPLETION_GENERATION missing or invalid for ${CMD_ID}" >&2
    exit 1
fi

# Tests and gate probes intentionally write ignored receipts/caches inside a
# task worktree.  `git status --porcelain` calls that tree clean, but ordinary
# `git worktree remove` refuses to discard those files.  Preserve every
# ignored path under the infra archive before removal so cleanup remains both
# lossless and non-forcing.
preserve_task_worktree_ignored_artifacts() {
    local worktree="$1" artifact_root entry rel src dst count=0
    artifact_root="$PROJECT_DIR/queue/archive/task-worktree-artifacts/${CMD_ID}"
    while IFS= read -r -d '' entry; do
        [[ "$entry" == "!! "* ]] || continue
        rel="${entry#!! }"
        case "$rel" in
            ""|/*|../*|*/../*|*/..) echo "[archive] BLOCK: unsafe ignored artifact path=$rel" >&2; return 1 ;;
        esac
        src="$worktree/$rel"
        [ -e "$src" ] || [ -L "$src" ] || continue
        dst="$artifact_root/$rel"
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            echo "[archive] BLOCK: ignored artifact archive collision path=$dst" >&2; return 1;
        fi
        mkdir -p "$(dirname "$dst")"
        mv -- "$src" "$dst"
        count=$((count + 1))
    done < <(git -C "$worktree" status --porcelain=v1 --ignored=matching -z 2>/dev/null)
    if [ "$count" -gt 0 ]; then
        echo "[archive] task worktree ignored artifacts preserved: ${count} path(s) root=$artifact_root"
    fi
}

# Gate/test telemetry may update a tracked operational ledger inside the
# isolated task worktree after the source commit.  Preserve its full post-run
# bytes, then restore only the allowlisted ledger to the published HEAD blob.
# Ordinary source dirt remains visible to the existing fail-closed check.
preserve_task_worktree_tracked_runtime_artifacts() {
    local worktree="$1" artifact_root entry rel src dst tree_line mode blob tmp count=0
    artifact_root="$PROJECT_DIR/queue/archive/task-worktree-artifacts/${CMD_ID}/tracked"
    while IFS= read -r -d '' entry; do
        rel="${entry:3}"
        case "$rel" in
            logs/defense_overhead.jsonl|context/semantic-map.md|docs/semantic-index/index.md) ;;
            *) continue ;;
        esac
        src="$worktree/$rel"
        [ -f "$src" ] && [ ! -L "$src" ] || {
            echo "[archive] BLOCK: tracked runtime artifact is not a regular file path=$src" >&2; return 1;
        }
        dst="$artifact_root/$rel"
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            echo "[archive] BLOCK: tracked runtime artifact archive collision path=$dst" >&2; return 1
        fi
        mkdir -p "$(dirname "$dst")"
        cp -p -- "$src" "$dst"
        tree_line="$(git -C "$worktree" ls-tree HEAD -- "$rel")"
        read -r mode _ blob _ <<< "$tree_line"
        [[ "$mode" =~ ^100(644|755)$ && "$blob" =~ ^[0-9a-f]{40}$ ]] || {
            echo "[archive] BLOCK: tracked runtime artifact has no regular HEAD blob path=$rel" >&2; return 1;
        }
        tmp="$(mktemp "${src}.restore.XXXXXX")"
        git -C "$worktree" cat-file blob "$blob" > "$tmp"
        if [ "$mode" = "100755" ]; then chmod 755 "$tmp"; else chmod 644 "$tmp"; fi
        [ "$(git hash-object "$tmp")" = "$blob" ] || {
            echo "[archive] BLOCK: tracked runtime artifact restore hash mismatch path=$rel" >&2; return 1;
        }
        mv -- "$tmp" "$src"
        count=$((count + 1))
    done < <(git -C "$worktree" status --porcelain=v1 -z --untracked-files=no 2>/dev/null)
    if [ "$count" -gt 0 ]; then
        echo "[archive] task worktree tracked runtime artifacts preserved: ${count} path(s) root=$artifact_root"
    fi
}

# Recover a source-only publication that won the race with archive cleanup.
# The durable receipt is accepted only for the exact command, completion
# generation, repository, and verified remote tip; ambiguity remains BLOCK.
recover_task_worktree_published_commit() {
    local marker="$1" cmd_id="$2" repo="$3" receipt tip
    receipt="$PROJECT_DIR/queue/gates/${cmd_id}/source_only_publish.receipt.json"
    [ -f "$receipt" ] || return 1
    tip=$(python3 - "$receipt" "$cmd_id" "${SHOGUN_COMPLETION_GENERATION:-}" "$repo" <<'PY'
import json
import re
import sys

receipt, expected_cmd, expected_generation, expected_repo = sys.argv[1:]
if not re.fullmatch(r"[0-9a-f]{64}", expected_generation):
    raise SystemExit(1)
try:
    data = json.load(open(receipt, encoding="utf-8"))
except (OSError, TypeError, ValueError):
    raise SystemExit(1)
if (
    not isinstance(data, dict)
    or data.get("version") != 1
    or data.get("state") != "published"
    or data.get("cmd_id") != expected_cmd
    or data.get("completion_generation") != expected_generation
    or not isinstance(data.get("entries"), list)
):
    raise SystemExit(1)

tips = set()
for entry in data["entries"]:
    if not isinstance(entry, dict) or entry.get("repo") != expected_repo:
        continue
    if (
        entry.get("cmd_id") != expected_cmd
        or entry.get("completion_generation") != expected_generation
        or entry.get("remote_contains_source_rc") != 0
    ):
        raise SystemExit(1)
    remote_tip = str(entry.get("remote_tip") or "")
    if not re.fullmatch(r"[0-9a-f]{40}", remote_tip):
        raise SystemExit(1)
    tips.add(remote_tip)
if len(tips) != 1:
    raise SystemExit(1)
print(next(iter(tips)))
PY
    ) || return 1
    git -C "$repo" cat-file -e "${tip}^{commit}" 2>/dev/null || return 1
    python3 - "$marker" "$tip" <<'PY'
import json
import os
import sys
import tempfile
import time

marker, published_commit = sys.argv[1:]
with open(marker, encoding="utf-8") as handle:
    data = json.load(handle)
if data.get("state") != "active" or str(data.get("published_commit") or ""):
    raise SystemExit(1)
data["published_commit"] = published_commit
data["published_recovered_at_ns"] = time.time_ns()
directory = os.path.dirname(marker)
fd, temporary = tempfile.mkstemp(prefix=".task_worktree_published_recovered.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, marker)
except Exception:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
    echo "[archive] task worktree publication recovered from durable receipt: commit=$tip"
}

# Narrow lifecycle-only entrypoint used by the linked-worktree contract
# fixture. It applies the same CLEAR/published/clean/ordinary-remove guards
# before the broad archive scan can touch unrelated dashboard data.
if [ "${ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY:-0}" = "1" ] && [ -n "$CMD_ID" ]; then
    _early_marker="$PROJECT_DIR/queue/gates/${CMD_ID}/task_worktree.json"
    _early_meta=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); assert d.get("version")==1 and d.get("parent_cmd")==sys.argv[2] and d.get("state") in {"active","cleaning","cleaned"}; print("\t".join(str(d.get(k) or "") for k in ("repo","worktree","state","published_commit")))' "$_early_marker" "$CMD_ID" 2>/dev/null) || { echo "[archive] BLOCK: invalid task worktree marker for ${CMD_ID}" >&2; exit 1; }
    IFS=$'\t' read -r _early_repo _early_worktree _early_state _early_published <<< "$_early_meta"
    if [ "$_early_state" != "cleaned" ]; then
        [ "${ARCHIVE_REQUIRE_CLEAR_RECEIPT:-0}" = "1" ] || { echo "[archive] BLOCK: CLEAR receipt required" >&2; exit 1; }
        python3 -c 'import json,re,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); assert d.get("version")==1 and d.get("state")=="clear" and d.get("cmd_id")==sys.argv[2] and re.fullmatch(r"[0-9a-f]{64}",str(d.get("completion_generation") or "")) and (not sys.argv[3] or d.get("completion_generation")==sys.argv[3]) and int(d.get("persisted_at_ns"))>0' "$PROJECT_DIR/queue/gates/$CMD_ID/gate_worker.clear.json" "$CMD_ID" "${SHOGUN_COMPLETION_GENERATION:-}" || { echo "[archive] BLOCK: invalid CLEAR receipt" >&2; exit 1; }
        if [ -z "$_early_published" ]; then
            recover_task_worktree_published_commit "$_early_marker" "$CMD_ID" "$_early_repo" || { echo "[archive] BLOCK: published commit receipt missing, mismatched, or unresolved" >&2; exit 1; }
            _early_published=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1],encoding="utf-8")).get("published_commit") or ""))' "$_early_marker")
        fi
        [[ "$_early_published" =~ ^[0-9a-f]{40}$ ]] && git -C "$_early_repo" cat-file -e "${_early_published}^{commit}" 2>/dev/null || { echo "[archive] BLOCK: published commit missing or unresolved" >&2; exit 1; }
        preserve_task_worktree_tracked_runtime_artifacts "$_early_worktree" || exit 1
        [ -z "$(git -C "$_early_worktree" status --porcelain 2>/dev/null)" ] || { echo "[archive] BLOCK: task worktree dirty" >&2; exit 1; }
        preserve_task_worktree_ignored_artifacts "$_early_worktree" || exit 1
        git -C "$_early_repo" worktree remove "$_early_worktree" 2>"$TMP/worktree-remove.stderr" || { sed -n '1,5p' "$TMP/worktree-remove.stderr" >&2; echo "[archive] BLOCK: task worktree remove failed" >&2; exit 1; }
        if git -C "$_early_repo" worktree list --porcelain | grep -Fqx "worktree $_early_worktree"; then echo "[archive] BLOCK: task worktree orphan remains" >&2; exit 1; fi
        python3 -c 'import json,os,sys,tempfile,time; p=sys.argv[1]; d=json.load(open(p,encoding="utf-8")); d["state"]="cleaned"; d["cleaned_at_ns"]=time.time_ns(); fd,t=tempfile.mkstemp(prefix=".task_worktree_cleaned.",dir=os.path.dirname(p)); f=os.fdopen(fd,"w",encoding="utf-8"); json.dump(d,f,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno()); f.close(); os.replace(t,p)' "$_early_marker"
    fi
    echo "[archive] task worktree cleanup: OK path=$_early_worktree"
    exit 0
fi

# A completed report remains at queue/reports as a compatibility symlink.
# Accept it as terminal only when it resolves inside the archive report root,
# points at a regular file, and both hashes match the exact completion
# generation. Outside, dangling, or stale links remain live and are never
# opened or moved.
archive_report_symlink_is_terminal() {
    local report_file="$1" archive_dir target target_hash link_hash
    [ -L "$report_file" ] || return 1
    archive_dir="$(realpath -e -- "$ARCHIVE_REPORT_DIR" 2>/dev/null)" || return 1
    target="$(realpath -e -- "$report_file" 2>/dev/null)" || return 1
    case "$target" in
        "$archive_dir"/*) ;;
        *) return 1 ;;
    esac
    [ -f "$target" ] || return 1
    target_hash="$(sha256sum -- "$target" 2>/dev/null | awk '{print $1}')" || return 1
    link_hash="$(sha256sum -- "$report_file" 2>/dev/null | awk '{print $1}')" || return 1
    [[ "$target_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$link_hash" == "$target_hash" && "$target_hash" == "${SHOGUN_COMPLETION_GENERATION:-}" ]]
}

mkdir -p "$ARCHIVE_DIR" "$ARCHIVE_CMD_DIR" "$ARCHIVE_REPORT_DIR"

# postcondition用グローバル変数（archive_cmdsが設定）
_POSTCOND_COMPLETED=0
_POSTCOND_ARCHIVED=0

# ============================================================
# 0.5 CMD年代記への追記
# ============================================================
get_report_summary_for_cmd() {
    local cmd_id="$1"
    python3 - "$REPORTS_DIR" "$cmd_id" <<'PY'
import glob
import os
import sys
import yaml

report_dir, cmd_id = sys.argv[1:3]

patterns = [
    os.path.join(report_dir, f"*_report_{cmd_id}.yaml"),
    os.path.join(report_dir, "subtask_*.yaml"),
]

def normalize(value):
    if value is None:
        return ""
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    return " ".join(text.split())

for pattern in patterns:
    for path in sorted(glob.glob(pattern)):
        if os.path.islink(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        parent_cmd = normalize(data.get("parent_cmd"))
        if parent_cmd and parent_cmd != cmd_id:
            continue
        nested_report = data.get("report") if isinstance(data.get("report"), dict) else {}
        nested_result = data.get("result") if isinstance(data.get("result"), dict) else {}
        for candidate in (data.get("summary"), nested_report.get("summary"), nested_result.get("summary")):
            text = normalize(candidate)
            if text and text != "|":
                print(text[:30])
                sys.exit(0)

print("")
PY
}

sync_chronicle_entry() {
    local cmd_id="$1"
    local entry="$2"

    local title project key_result
    title=$(printf '%s\n' "$entry" | grep -m1 '^ *purpose:' | sed 's/^ *purpose: *//; s/^"//; s/"$//')
    if [ -z "$title" ]; then
        title=$(printf '%s\n' "$entry" | grep -m1 '^ *title:' | sed 's/^ *title: *//; s/^"//; s/"$//')
    fi
    project=$(printf '%s\n' "$entry" | grep -m1 '^ *project:' | sed 's/^ *project: *//; s/^"//; s/"$//')
    key_result=$(get_report_summary_for_cmd "$cmd_id")

    local date_mm_dd year_month
    date_mm_dd="$(date '+%m-%d')"
    year_month="$(date '+%Y-%m')"

    local chronicle_rc
    (
        flock -w 10 200 || { echo "[chronicle] WARN: flock timeout on chronicle" >&2; return 1; }

        python3 - "$CHRONICLE_FILE" "$cmd_id" "$title" "$project" "$date_mm_dd" "$key_result" "$year_month" <<'PY'
import os
import sys

chronicle_path, cmd_id, title, project, date_mm_dd, key_result, year_month = sys.argv[1:8]
today = __import__("datetime").datetime.now().strftime("%Y-%m-%d")

def norm(value, fallback="—"):
    value = (value or "").strip()
    return value if value else fallback

def blankish(value):
    return value.strip() in {"", "—"}

if not os.path.exists(chronicle_path):
    with open(chronicle_path, "w", encoding="utf-8") as f:
        f.write(f"# CMD年代記\n<!-- last_updated: {today} -->\n")

with open(chronicle_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

if not lines:
    lines = ["# CMD年代記", f"<!-- last_updated: {today} -->"]
elif len(lines) == 1:
    lines.append(f"<!-- last_updated: {today} -->")

if not lines[1].startswith("<!-- last_updated: "):
    lines.insert(1, f"<!-- last_updated: {today} -->")

row_idx = next((i for i, line in enumerate(lines) if line.startswith(f"| {cmd_id} |")), None)
action = "noop"

if row_idx is not None:
    parts = [part.strip() for part in lines[row_idx].split("|")[1:-1]]
    while len(parts) < 5:
        parts.append("")
    if blankish(parts[1]) and title.strip():
        parts[1] = title.strip()
        action = "updated"
    if blankish(parts[4]) and key_result.strip():
        parts[4] = key_result.strip()
        action = "updated"
    if blankish(parts[2]):
        parts[2] = norm(project)
        action = "updated" if action == "noop" else action
    if blankish(parts[3]):
        parts[3] = norm(date_mm_dd)
        action = "updated" if action == "noop" else action
    lines[row_idx] = f"| {parts[0] or cmd_id} | {norm(parts[1])} | {norm(parts[2])} | {norm(parts[3])} | {norm(parts[4])} |"
else:
    month_idx = next((i for i, line in enumerate(lines) if line == f"## {year_month}"), None)
    if month_idx is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend([
            f"## {year_month}",
            "",
            "| cmd | title | project | date | key_result |",
            "|-----|-------|---------|------|------------|",
        ])
    lines.append(f"| {cmd_id} | {norm(title)} | {norm(project)} | {norm(date_mm_dd)} | {norm(key_result)} |")
    action = "appended"

lines[1] = f"<!-- last_updated: {today} -->"

with open(chronicle_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(action)
PY
    ) 200>"/tmp/mas-chronicle.lock"
    chronicle_rc=$?
    if [ "$chronicle_rc" -ne 0 ]; then
        return "$chronicle_rc"
    fi

    echo "[chronicle] synced: $cmd_id"
}

sync_chronicle_entries_batch() {
    local batch_file="$1"
    [ -s "$batch_file" ] || return 0

    local chronicle_rc
    (
        flock -w 10 200 || { echo "[chronicle] WARN: flock timeout on chronicle" >&2; return 1; }

        python3 - "$CHRONICLE_FILE" "$REPORTS_DIR" "$batch_file" "${CMD_ID:-}" "${_TARGET_REPORT_MANIFEST:-}" <<'PY'
import glob
import os
import re
import sys
from datetime import datetime

import yaml

chronicle_path, report_dir, batch_file, target_cmd_id, target_manifest = sys.argv[1:6]
today = datetime.now().strftime("%Y-%m-%d")
date_mm_dd = datetime.now().strftime("%m-%d")
year_month = datetime.now().strftime("%Y-%m")


def norm(value, fallback="—"):
    text = (value or "").strip()
    return text if text else fallback


def blankish(value):
    return (value or "").strip() in {"", "—"}


def normalize(value):
    if value is None:
        return ""
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    return " ".join(text.split())


def load_report_summaries():
    summaries = {}
    if target_cmd_id:
        # The completion caller already knows the immutable cmd generation.
        # Reuse its cmd/worker/report manifest instead of parsing every report
        # merely to discard unrelated parent_cmd values afterwards.
        paths = []
        try:
            with open(target_manifest, encoding="utf-8") as f:
                for line in f:
                    parts = line.rstrip("\n").split("\t", 2)
                    if len(parts) == 3 and parts[0] == target_cmd_id:
                        paths.append(parts[2])
        except OSError:
            pass
        # archive_cmds can batch several already-terminal STK entries during
        # one targeted completion. Preserve their chronicle summaries without
        # returning to a directory-wide payload scan: resolve each batch cmd
        # first, then use its boundary-safe canonical basename patterns.
        try:
            with open(batch_file, encoding="utf-8") as f:
                archive_paths = [line.strip() for line in f if line.strip()]
        except OSError:
            archive_paths = []
        for archive_path in archive_paths:
            batch_cmd_id, _entry = load_archived_entry(archive_path)
            if not batch_cmd_id:
                continue
            paths.extend(glob.glob(os.path.join(report_dir, f"*_report_{batch_cmd_id}.yaml")))
            paths.extend(glob.glob(os.path.join(report_dir, f"*_report_{batch_cmd_id}_*.yaml")))
    else:
        patterns = [
            os.path.join(report_dir, "*_report_*.yaml"),
            os.path.join(report_dir, "subtask_*.yaml"),
        ]
        paths = [path for pattern in patterns for path in glob.glob(pattern)]
    for path in sorted(set(paths)):
        if os.path.islink(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue
        if not isinstance(data, dict):
            continue

        parent_cmd = normalize(data.get("parent_cmd"))
        if not parent_cmd:
            match = re.match(r".*_report_(cmd_[^.]+)\.yaml$", os.path.basename(path))
            if match:
                parent_cmd = match.group(1)
        if not parent_cmd or parent_cmd in summaries:
            continue

        nested_report = data.get("report") if isinstance(data.get("report"), dict) else {}
        nested_result = data.get("result") if isinstance(data.get("result"), dict) else {}
        for candidate in (
            data.get("summary"),
            nested_report.get("summary"),
            nested_result.get("summary"),
        ):
            text = normalize(candidate)
            if text and text != "|":
                summaries[parent_cmd] = text[:30]
                break
    return summaries


def load_archived_entry(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        return None, None

    commands = data.get("commands")
    if isinstance(commands, dict):
        for cmd_id, entry in commands.items():
            if isinstance(entry, dict):
                return normalize(cmd_id), entry
    elif isinstance(commands, list):
        for entry in commands:
            if isinstance(entry, dict):
                cmd_id = normalize(entry.get("id"))
                if cmd_id:
                    return cmd_id, entry
    return None, None


if not os.path.exists(chronicle_path):
    with open(chronicle_path, "w", encoding="utf-8") as f:
        f.write(f"# CMD年代記\n<!-- last_updated: {today} -->\n")

with open(chronicle_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

if not lines:
    lines = ["# CMD年代記", f"<!-- last_updated: {today} -->"]
elif len(lines) == 1:
    lines.append(f"<!-- last_updated: {today} -->")

if not lines[1].startswith("<!-- last_updated: "):
    lines.insert(1, f"<!-- last_updated: {today} -->")

summaries = load_report_summaries()
rows_to_append = []
synced_ids = []

with open(batch_file, encoding="utf-8") as f:
    archive_paths = [line.strip() for line in f if line.strip()]

for archive_path in archive_paths:
    cmd_id, entry = load_archived_entry(archive_path)
    if not cmd_id or not isinstance(entry, dict):
        continue

    title = normalize(entry.get("purpose")) or normalize(entry.get("title"))
    project = normalize(entry.get("project"))
    key_result = summaries.get(cmd_id, "")

    row_idx = next((i for i, line in enumerate(lines) if line.startswith(f"| {cmd_id} |")), None)
    if row_idx is not None:
        parts = [part.strip() for part in lines[row_idx].split("|")[1:-1]]
        while len(parts) < 5:
            parts.append("")
        if blankish(parts[1]) and title:
            parts[1] = title
        if blankish(parts[2]) and project:
            parts[2] = project
        if blankish(parts[3]):
            parts[3] = date_mm_dd
        if blankish(parts[4]) and key_result:
            parts[4] = key_result
        lines[row_idx] = (
            f"| {parts[0] or cmd_id} | {norm(parts[1])} | {norm(parts[2])} | "
            f"{norm(parts[3])} | {norm(parts[4])} |"
        )
    else:
        rows_to_append.append(
            f"| {cmd_id} | {norm(title)} | {norm(project)} | {norm(date_mm_dd)} | {norm(key_result)} |"
        )
    synced_ids.append(cmd_id)

if rows_to_append:
    if next((i for i, line in enumerate(lines) if line == f"## {year_month}"), None) is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend([
            f"## {year_month}",
            "",
            "| cmd | title | project | date | key_result |",
            "|-----|-------|---------|------|------------|",
        ])
    lines.extend(rows_to_append)

lines[1] = f"<!-- last_updated: {today} -->"

with open(chronicle_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"synced:{len(synced_ids)}")
PY
    ) 200>"/tmp/mas-chronicle.lock"
    chronicle_rc=$?
    if [ "$chronicle_rc" -ne 0 ]; then
        return "$chronicle_rc"
    fi

    echo "[chronicle] batch synced"
}

archive_pending_decisions_for_cmd_locked() {
    local cmd_id="$1"
    (
        flock -w 10 200 || { echo "[pending_decisions] WARN: flock timeout on pending_decisions" >&2; exit 1; }
        flock -w 10 201 || { echo "[pending_decisions] WARN: flock timeout on pending_decisions_archive" >&2; exit 1; }

        PYTHONPATH="$PROJECT_DIR" python3 - "$PENDING_DECISIONS_FILE" "$PENDING_DECISIONS_ARCHIVE" "$cmd_id" <<'PY'
import os
import sys
import yaml
from scripts.lib.yaml_atomic import atomic_yaml_write

pending_path, archive_path, cmd_id = sys.argv[1:4]

def load_yaml(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

def write_yaml(path, data):
    atomic_yaml_write(path, data, indent=2, sort_keys=False)

def build_doc(decisions):
    total = len(decisions)
    resolved = sum(1 for d in decisions if isinstance(d, dict) and d.get("status") == "resolved")
    pending = total - resolved
    return {"summary": {"total": total, "resolved": resolved, "pending": pending}, "decisions": decisions}

pending_data = load_yaml(pending_path)
decisions = pending_data.get("decisions") or []
matched = []
kept = []
for decision in decisions:
    if isinstance(decision, dict) and str(decision.get("resolved_by", "")).strip() == cmd_id and str(decision.get("status", "")).strip() == "resolved":
        matched.append(decision)
    else:
        kept.append(decision)

if not matched:
    print(0)
    sys.exit(0)

archive_data = load_yaml(archive_path)
archive_decisions = archive_data.get("decisions") or []
existing_ids = {d.get("id") for d in archive_decisions if isinstance(d, dict)}
for decision in matched:
    if decision.get("id") not in existing_ids:
        archive_decisions.append(decision)

write_yaml(pending_path, build_doc(kept))
write_yaml(archive_path, build_doc(archive_decisions))
print(len(matched))
PY
    ) 200>"$(lock_path "$PENDING_DECISIONS_FILE")" 201>"$(lock_path "$PENDING_DECISIONS_ARCHIVE")"
}

archive_pending_decisions_for_cmd() {
    local cmd_id="$1"
    [ -f "$PENDING_DECISIONS_FILE" ] || return 0
    mkdir -p "$(dirname "$PENDING_DECISIONS_ARCHIVE")"

    local archived_count archive_rc
    set +e
    archived_count="$(archive_pending_decisions_for_cmd_locked "$cmd_id")"
    archive_rc=$?
    set -e

    if [ "$archive_rc" -ne 0 ] || [ -z "$archived_count" ]; then
        echo "[pending_decisions] WARN: archive failed cmd=$cmd_id rc=$archive_rc archived_count_empty=$([ -z "$archived_count" ] && echo yes || echo no)" >&2
        return 1
    fi

    if [ "${archived_count:-0}" -gt 0 ]; then
        echo "[pending_decisions] archived=$archived_count cmd=$cmd_id"
    else
        echo "[pending_decisions] none for $cmd_id"
    fi
}

# ============================================================
# 0.85 STK安全書込みヘルパー (yaml.dump禁止対策)
#   dict形式STKからcmd_idブロックをテキストベースで除去する。
#   yaml.dumpのround-trip問題(マルチライン文字列消失)を回避。
# ============================================================
stk_remove_cmd_blocks() {
    local file="$1" cmd_csv="$2"
    [ -z "$cmd_csv" ] && return 0

    local tmp_file="$TMP/stk_safe_rewrite.yaml"
    gawk -v ids="$cmd_csv" '
        BEGIN {
            n = split(ids, arr, ",")
            for (i = 1; i <= n; i++) remove[arr[i]] = 1
            skip = 0
        }
        /^  cmd_[0-9a-zA-Z_]+:/ {
            id = $0
            sub(/^  /, "", id)
            sub(/:.*/, "", id)
            if (id in remove) { skip = 1; next }
            skip = 0
            print; next
        }
        skip && (/^    / || /^$/) { next }
        skip { skip = 0 }
        { print }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

# ============================================================
# 0.9 STK dict形式status同期+アーカイブ退避
#   1. archive/cmds/ + 完了報告 から完了cmd_idを収集
#   2. STK内delegated→doneに更新
#   3. done/canceled/cancelled/absorbed エントリをarchive/cmds/に退避しSTKから除去
# ============================================================
sync_stk_status_from_archive() {
    # GP-XXX: sync_stk + trim_stk_old を単一Python呼び出しに統合
    # STK yaml.safe_load を2回→1回に削減 (Python起動コスト×1回 + yaml.safe_load×1回 削減)
    [ -f "$QUEUE_FILE" ] || return 0

    # list形式のshogun_to_karo.yamlはarchive_cmds側の対象。
    # dict形式STKエントリが無い場合はPython/yaml.safe_loadを起動しない。
    if ! grep -qE '^[[:space:]]{2}cmd_[0-9A-Za-z_]+:' "$QUEUE_FILE" 2>/dev/null; then
        echo "[stk-sync] skipped: no dict-form STK entries"
        echo "[stk-trim] skipped: no dict-form STK entries"
        return 0
    fi

    local result
    result=$(
        (
            flock -w 10 200 || { echo "[stk-sync] WARN: flock timeout" >&2; echo "0 0"; exit 1; }

            PYTHONPATH="$PROJECT_DIR" python3 - "$QUEUE_FILE" "$ARCHIVE_CMD_DIR" "$REPORTS_DIR" "$ARCHIVE_REPORT_DIR" "$STK_ARCHIVE_DIR" <<'PY'
import os
import sys
from datetime import datetime, timedelta, timezone

import yaml
from scripts.lib.yaml_atomic import atomic_yaml_write

stk_path, archive_cmd_dir, reports_dir, archive_report_dir, stk_archive_dir = sys.argv[1:6]
SAFE_STATUSES = {"pending", "in_progress", "acknowledged", "assigned", "parked", "draft"}
DONE_STATUSES = {"done", "canceled", "cancelled", "absorbed"}
TRIM_STATUSES = {"done", "absorbed", "canceled", "cancelled"}
CUTOFF_DAYS = 30

# === Phase 1: 完了cmd_idを収集 (sync用) ===

completed_ids = set()

# Source 1: archive/cmds/ のファイル名 (非完了status=delegatedを除外)
# delegatedはSTKに残るべき。completed/done/canceled/cancelled/absorbed/superseded/closed/shelved/halted=STK除去対象
_NON_COMPLETED_STATUSES = {"delegated"}
if os.path.isdir(archive_cmd_dir):
    for fname in os.listdir(archive_cmd_dir):
        if fname.startswith("cmd_") and fname.endswith(".yaml"):
            parts = fname.split("_")
            if len(parts) >= 3:
                status_part = parts[2]
                if status_part not in _NON_COMPLETED_STATUSES:
                    completed_ids.add(f"{parts[0]}_{parts[1]}")
            elif len(parts) == 2:
                completed_ids.add(f"{parts[0]}_{parts[1].replace('.yaml', '')}")

# Source 2: 現行報告 (status: done/completed) — GP-080: TSVキャッシュから読取り
cache_path = os.path.join(os.environ.get("TMP", "/tmp"), "report_fields_cache.tsv")
if os.path.isfile(cache_path):
    with open(cache_path, encoding="utf-8") as cf:
        for line in cf:
            parts = line.strip().split("|", 2)
            if len(parts) < 3:
                continue
            fname, status, parent = parts
            if status in ("done", "completed", "complete", "success"):
                if parent.startswith("cmd_"):
                    cid = "_".join(parent.split("_")[:2])
                    completed_ids.add(cid)

# Source 3: GP-077: スキップ (archive/cmds/ファイル名で十分カバー)

# === Phase 2: STK読み込み (1回) — sync + trim 両方に使用 ===

with open(stk_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

cmds = data.get("commands")
if not isinstance(cmds, dict):
    print("0 0")
    sys.exit(0)

now = datetime.now(timezone(timedelta(hours=9)))
cutoff = now - timedelta(days=CUTOFF_DAYS)
date_stamp = now.strftime("%Y%m%d")

synced = 0
archived = 0
sync_removed = []
keep_after_sync = {}  # syncが残したエントリ群 (trimの入力)

# --- sync パス ---
for cmd_id, entry in cmds.items():
    if not isinstance(entry, dict):
        keep_after_sync[cmd_id] = entry
        continue
    status = str(entry.get("status", "")).strip()
    if status in SAFE_STATUSES:
        keep_after_sync[cmd_id] = entry
        continue
    if status == "delegated" and cmd_id in completed_ids:
        entry["status"] = "done"
        status = "done"
        synced += 1
    elif status == "delegated":
        # LK002: delegatedだが未完了 → 保護(cmd_2320消失事故の根因修正)
        keep_after_sync[cmd_id] = entry
        continue
    if status in DONE_STATUSES:
        archive_path = os.path.join(archive_cmd_dir, f"{cmd_id}_{status}_{date_stamp}.yaml")
        if not os.path.exists(archive_path):
            atomic_yaml_write(archive_path, {"commands": {cmd_id: entry}}, indent=2, sort_keys=False)
        archived += 1
        sync_removed.append(cmd_id)
        continue
    keep_after_sync[cmd_id] = entry

# --- trim パス: syncが残したエントリのうち done+30日超を stk_archive_dir退避 ---
trim_to_archive = {}
trim_removed = []
final_keep = {}

for cmd_id, entry in keep_after_sync.items():
    if not isinstance(entry, dict):
        final_keep[cmd_id] = entry
        continue
    status_l = str(entry.get("status", "")).strip().lower()
    if status_l not in TRIM_STATUSES:
        final_keep[cmd_id] = entry
        continue
    ts_raw = entry.get("timestamp") or entry.get("delegated_at") or ""
    ts_str = str(ts_raw).strip().strip("'\"")
    entry_dt = None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S+09:00",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            entry_dt = datetime.strptime(ts_str, fmt)
            if entry_dt.tzinfo is None:
                entry_dt = entry_dt.replace(tzinfo=timezone(timedelta(hours=9)))
            break
        except ValueError:
            continue
    if entry_dt is not None and entry_dt < cutoff:
        ym = entry_dt.strftime("%Y-%m")
        trim_to_archive.setdefault(ym, {})[cmd_id] = entry
        trim_removed.append(cmd_id)
    else:
        final_keep[cmd_id] = entry

# trim: 退避先に書き出し (月別 YYYY-MM.yaml)
if trim_to_archive:
    os.makedirs(stk_archive_dir, exist_ok=True)
    for ym, entries in trim_to_archive.items():
        archive_path = os.path.join(stk_archive_dir, f"{ym}.yaml")
        if os.path.exists(archive_path):
            with open(archive_path, encoding="utf-8") as f:
                existing = yaml.safe_load(f) or {}
            existing_cmds = existing.get("commands") or {}
        else:
            existing_cmds = {}
        existing_cmds.update(entries)
        atomic_yaml_write(archive_path, {"commands": existing_cmds}, indent=2, sort_keys=False)

all_removed = sync_removed + trim_removed
trim_archived = len(trim_removed)
print(f"{synced} {archived}")
if all_removed:
    print(f"REMOVE:{','.join(all_removed)}")
if trim_archived > 0:
    print(f"TRIM:trimmed: archived={trim_archived} kept={len(final_keep)}")
else:
    print("TRIM:noop: no entries to archive")
PY
        ) 200>"/tmp/mas-stk.lock"
    )

    # yaml.dump禁止: テキストベースでSTKからcmdブロックを除去
    local remove_csv
    remove_csv=$(echo "$result" | grep '^REMOVE:' | sed 's/^REMOVE://' || true)
    if [ -n "$remove_csv" ]; then
        (
            flock -w 10 200 || { echo "[stk-sync] WARN: flock timeout on rewrite" >&2; return 1; }
            stk_remove_cmd_blocks "$QUEUE_FILE" "$remove_csv"
        ) 200>"/tmp/mas-stk.lock"
    fi

    local synced archived
    synced=$(echo "$result" | head -1 | awk '{print $1}')
    archived=$(echo "$result" | head -1 | awk '{print $2}')
    echo "[stk-sync] delegated→done: ${synced:-0}, archived: ${archived:-0}"
    echo "[stk-trim] $(echo "$result" | grep '^TRIM:' | sed 's/^TRIM://' || echo 'done')"
}

# ============================================================
# 1. shogun_to_karo.yaml — 完了cmdをアーカイブに退避
# ============================================================
archive_cmds() {
    [ -f "$QUEUE_FILE" ] || return 0

    local tmp_active="$TMP/stk_active.yaml"
    local chronicle_batch="$TMP/chronicle_batch.list"
    local archive_todo="$TMP/stk_archive_todo.list"
    local archive_result="$TMP/stk_archive_result.env"
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"

    : > "$chronicle_batch"
    : > "$archive_todo"
    echo "commands:" > "$tmp_active"

    # フェーズ1: flock内でQUEUE_FILE読込・分類・QUEUE_FILE更新
    # GP-XXX: 21x sed+grep ループ → 単一 gawk パスに置換（WSL2プロセス起動コスト削減）
    # AC1: QUEUE_FILEのすべての読み込みをflock内に包含
    # AC2: アーカイブファイル書き出し等QUEUE_FILE以外のI/OはこのサブシェルをEXIT後に実行
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on QUEUE_FILE" >&2; exit 1; }

        # changelog IDs を事前ロード（status欠損エントリ用フォールバック）
        local _cl_ids=""
        if [ -f "$CHANGELOG_FILE" ]; then
            _cl_ids=$(gawk '/^[[:space:]]*(-[[:space:]]*)?(id|cmd_id):[[:space:]]*cmd_[^[:space:]]+/{
                id=$0; sub(/^[[:space:]]*(-[[:space:]]*)?(id|cmd_id):[[:space:]]*/,"",id)
                gsub(/[[:space:]]+$/,"",id)
                if (id~/^cmd_/) print id
            }' "$CHANGELOG_FILE" 2>/dev/null | paste -sd, || true)
        fi

        # 単一 gawk パス: エントリ分類 + active/archive 振り分け
        gawk -v tmp_dir="$TMP" \
             -v active_f="$tmp_active" \
             -v todo_f="$archive_todo" \
             -v result_f="$archive_result" \
             -v cl_ids="$_cl_ids" \
        'BEGIN {
            archived=0; kept=0; completed_count=0
            in_entry=0; cur_cmd=""; cur_status=""; buf_n=0
            n=split(cl_ids,arr,","); for(i=1;i<=n;i++) if(arr[i]!="") cl[arr[i]]=1
        }
        /^  cmd_[0-9a-z_]+:/ {
            if(cur_cmd!="") _flush()
            cur_cmd=$0; sub(/^  /,"",cur_cmd); sub(/:.*$/,"",cur_cmd)
            cur_status=""; buf_n=0; buf[++buf_n]=$0; in_entry=1; next
        }
        /^[[:space:]]*-[[:space:]]id:[[:space:]]*cmd_/ {
            if(cur_cmd!="") _flush()
            cur_cmd=$0; sub(/^[[:space:]]*-[[:space:]]id:[[:space:]]*/,"",cur_cmd)
            gsub(/[[:space:]]+$/,"",cur_cmd)
            cur_status=""; buf_n=0; buf[++buf_n]=$0; in_entry=1; next
        }
        in_entry && /^[[:space:]]*status:/ && cur_status=="" {
            cur_status=$0; sub(/^[[:space:]]*status:[[:space:]]*/,"",cur_status)
            gsub(/["'"'"'\t ]/,"",cur_status)
        }
        in_entry { buf[++buf_n]=$0; next }
        END {
            if(cur_cmd!="") _flush()
            printf "no_entries=%d\narchived=%d\nkept=%d\ncompleted_count=%d\n", \
                (archived==0&&kept==0?1:0), archived, kept, completed_count > result_f
            close(result_f)
        }
        function _flush(    i,stat,arch_stat,out) {
            stat=tolower(cur_status)
            if(stat==""&&(cur_cmd in cl)) stat="completed"
            if(stat~/^(completed|canceled|cancelled|absorbed|halted|superseded|done|shelved|closed)/) {
                completed_count++
                match(stat,/^(completed|canceled|cancelled|absorbed|halted|superseded|done|shelved|closed)/)
                arch_stat=substr(stat,1,RLENGTH)
                out=tmp_dir "/entry_" cur_cmd ".tmp"
                for(i=1;i<=buf_n;i++) print buf[i] > out; close(out)
                printf "%s|%s\n",cur_cmd,arch_stat >> todo_f
                archived++
            } else {
                for(i=1;i<=buf_n;i++) print buf[i] >> active_f
                kept++
            }
            cur_cmd=""; cur_status=""; buf_n=0; delete buf
        }' "$QUEUE_FILE"

        # 結果読込
        local no_entries=0 archived_i=0 completed_count=0
        if [ -f "$archive_result" ]; then
            while IFS='=' read -r key val; do
                case "$key" in
                    no_entries)      no_entries="$val" ;;
                    archived)        archived_i="$val" ;;
                    completed_count) completed_count="$val" ;;
                esac
            done < "$archive_result"
        fi

        if [ "${no_entries:-0}" -eq 1 ]; then
            local pre_check
            pre_check=$(awk '/^ *status: *(completed|canceled|cancelled|absorbed|halted|superseded|done)/{c++} END{print c+0}' "$QUEUE_FILE")
            printf 'no_entries=1\npre_check=%s\narchived=0\nkept=0\ncompleted_count=%s\n' \
                "$pre_check" "$pre_check" > "$archive_result"
            exit 0
        fi

        if [ "${archived_i:-0}" -gt 0 ]; then
            # QUEUE_FILE更新（flock内でアトミックに実行）
            [ -f "$tmp_active" ] || { echo "[archive] FATAL: tmp_active not found: $tmp_active" >&2; exit 1; }
            mv "$tmp_active" "$QUEUE_FILE" || { echo "[archive] FATAL: mv failed: $tmp_active → $QUEUE_FILE" >&2; exit 1; }
        fi

    ) 200>"/tmp/mas-stk.lock"

    local flock_exit=$?
    if [ "$flock_exit" -ne 0 ]; then
        rm -f "$tmp_active" "$archive_todo"
        return 1
    fi

    # フェーズ2: flock外で結果読み込み・アーカイブファイル書き出し
    if [ ! -f "$archive_result" ]; then
        echo "[archive] FATAL: archive_result not found" >&2
        return 1
    fi

    local no_entries=0 archived=0 kept=0 completed_count=0 pre_check=0
    while IFS='=' read -r key val; do
        case "$key" in
            no_entries)      no_entries="$val" ;;
            archived)        archived="$val" ;;
            kept)            kept="$val" ;;
            completed_count) completed_count="$val" ;;
            pre_check)       pre_check="$val" ;;
        esac
    done < "$archive_result"

    if [ "$no_entries" -eq 1 ]; then
        if [ "$pre_check" -gt 0 ]; then
            echo "[archive] WARN: $pre_check completed cmds found but 0 archived — grep pattern mismatch?" >&2
        fi
        _POSTCOND_COMPLETED=$pre_check
        echo "[archive] cmds: no entries found"
        rm -f "$tmp_active"
        return 0
    fi

    # postcondition用グローバル変数を設定
    _POSTCOND_COMPLETED=$completed_count
    _POSTCOND_ARCHIVED=$archived

    if [ "$completed_count" -gt 0 ] && [ "$archived" -eq 0 ]; then
        echo "[archive] WARN: $completed_count completed cmds found but 0 archived — grep pattern mismatch?" >&2
    fi

    if [ "$archived" -gt 0 ]; then
        # AC2: flock外でアーカイブファイル書き出し（QUEUE_FILE以外のI/O。flock保持時間最小化）
        while IFS='|' read -r cmd_id archive_status; do
            local cmd_archive_file="$ARCHIVE_CMD_DIR/${cmd_id}_${archive_status}_${date_stamp}.yaml"
            {
                echo "commands:"
                cat "$TMP/entry_${cmd_id}.tmp"
            } > "$cmd_archive_file"
            rm -f "$TMP/entry_${cmd_id}.tmp"
            archive_pending_decisions_for_cmd "$cmd_id" || true
            printf '%s\n' "$cmd_archive_file" >> "$chronicle_batch"
        done < "$archive_todo"
        sync_chronicle_entries_batch "$chronicle_batch" || true
        echo "[archive] cmds: archived=$archived kept=$kept"
    else
        rm -f "$tmp_active"
        echo "[archive] cmds: nothing to archive (kept=$kept)"
    fi

}

# ============================================================
# 1.5 queue/reports — 完了報告をアーカイブ
#   - 新形式: {ninja}_report_{cmd}.yaml
#   - 旧形式: {ninja}_report.yaml（後方互換）
# ============================================================
archive_reports() {
    [ -d "$REPORTS_DIR" ] || return 0

    local archived=0 kept=0 skipped=0 junk=0
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"
    local _gate_metrics_loaded=0
    declare -A _gate_metrics_clear=()
    declare -A _stale_gate_incomplete=()

    # One find process for stale checks. In targeted completion mode the
    # report manifest is the scope boundary; sweep mode retains the global
    # stale-recovery behavior.
    if [ -n "$CMD_ID" ]; then
        if [ ${#_TARGET_REPORT_FILES[@]} -gt 0 ]; then
            while IFS= read -r _stale_path; do
                [ -n "$_stale_path" ] && _stale_gate_incomplete["$_stale_path"]=1
            done < <(find "${_TARGET_REPORT_FILES[@]}" -daystart -maxdepth 0 -type f -mtime +13 -print 2>/dev/null || true)
        fi
    else
        while IFS= read -r _stale_path; do
            [ -n "$_stale_path" ] && _stale_gate_incomplete["$_stale_path"]=1
        done < <(find "$REPORTS_DIR" -daystart -maxdepth 1 -type f -name '*.yaml' -mtime +13 -print 2>/dev/null || true)
    fi

    load_gate_metrics_clear_cache() {
        [ "$_gate_metrics_loaded" -eq 1 ] && return 0
        _gate_metrics_loaded=1
        local _gate_metrics_log="$PROJECT_DIR/logs/gate_metrics.log"
        [ -f "$_gate_metrics_log" ] || return 0
        while IFS= read -r _clear_cmd; do
            [ -n "$_clear_cmd" ] && _gate_metrics_clear["$_clear_cmd"]=1
        done < <(awk -F'\t' '
            $2 == "CLEAR" && $3 != "" { print $3; next }
            $3 == "CLEAR" && $2 != "" { print $2; next }
        ' "$_gate_metrics_log" 2>/dev/null | sort -u)
    }

    gate_metrics_has_clear() {
        local _cmd="$1"
        # A reopened parent is active again; historical CLEAR must not recreate
        # review/archive markers until a new completion removes the reopen SSOT.
        [ ! -f "$PROJECT_DIR/queue/reopened_cmds/${_cmd}.yaml" ] || return 1
        load_gate_metrics_clear_cache
        [ "${_gate_metrics_clear[$_cmd]+x}" = "x" ]
    }

    write_review_gate_from_metrics() {
        local _cmd="$1"
        local _gate_dir="$PROJECT_DIR/queue/gates/${_cmd}"
        mkdir -p "$_gate_dir"
        cat > "$_gate_dir/review_gate.done" <<EOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: gate_metrics_backfill
result: CLEAR
note: archive_completed.sh補完。gate_metrics.logのCLEAR記録を正本としてreview_gate.doneを復元。
EOF
    }

    write_archive_done_from_metrics() {
        local _cmd="$1"
        local _gate_dir="$PROJECT_DIR/queue/gates/${_cmd}"
        mkdir -p "$_gate_dir"
        touch "$_gate_dir/archive.done"
    }

    report_is_stale_gate_incomplete() {
        local _report_file="$1"
        [ "${_stale_gate_incomplete[$_report_file]+x}" = "x" ]
    }

    # cmd_karo_impl_fail_close_path_20260725 (設計書v2.0 B21):
    # 家老がこの報告を正式にレビューした証跡(fingerprint束縛のkaro.yaml)があるか。
    # review_gate.done検査の目的は「家老レビュー未完了の報告を退避させない」ことであり、
    # 家老の正式判定が記録済みならその目的は満たされている。CLEARの有無とは別軸である。
    karo_review_decision_recorded() {
        local _cmd="$1" _f
        for _f in "$PROJECT_DIR/queue/gates/${_cmd}/review_approvals/reports"/*/karo.yaml; do
            [ -f "$_f" ] && return 0
        done
        return 1
    }

    # verdict=FAIL の報告か。FAIL close経路は本来CLEARに到達しないcmdだけに限定する。
    report_verdict_is_fail() {
        local _report_file="$1" _v
        _v="$(grep -m1 '^verdict:' "$_report_file" 2>/dev/null || true)"
        _v="${_v#verdict:}"
        _v="${_v//[\"\' ]/}"
        [ "$_v" = "FAIL" ]
    }

    archive_overflow_reports_to_cap() {
        local cap=10
        local overflow_list="$TMP/report_overflow_candidates.tsv"
        python3 - "$PROJECT_DIR" "$REPORTS_DIR" <<'PY' > "$overflow_list"
import glob
import os
import sys
import yaml

project_dir, reports_dir = sys.argv[1:3]

active_parents = set()
for task_path in glob.glob(os.path.join(project_dir, "queue", "tasks", "*.yaml")):
    try:
        with open(task_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    task = data.get("task") if isinstance(data.get("task"), dict) else data
    if not isinstance(task, dict):
        continue
    status = str(task.get("status") or "").strip()
    parent = str(task.get("parent_cmd") or "").strip()
    if parent and status not in {"", "done", "completed", "complete", "success", "failed"}:
        active_parents.add(parent)

eligible_statuses = {"done", "completed", "complete", "success", "failed", "pass", "fail", "blocked", "waived", "stop_for"}
candidates = []
skipped_pending = 0
skipped_ineligible = 0
skipped_active_parent = 0
skipped_gate_incomplete = 0

def gate_complete(parent):
    if not parent:
        return True
    if parent.startswith(("cmd_training_", "cmd_cycle_", "cmd_selfimprovement_")):
        return True
    archive_done = os.path.join(project_dir, "queue", "gates", parent, "archive.done")
    if os.path.isfile(archive_done):
        return True
    gate_metrics_log = os.path.join(project_dir, "logs", "gate_metrics.log")
    try:
        with open(gate_metrics_log, encoding="utf-8") as f:
            for line in f:
                fields = line.rstrip("\n").split("\t")
                if len(fields) >= 3 and (
                    (fields[1] == parent and fields[2] == "CLEAR")
                    or (fields[1] == "CLEAR" and fields[2] == parent)
                ):
                    os.makedirs(os.path.dirname(archive_done), exist_ok=True)
                    open(archive_done, "a", encoding="utf-8").close()
                    return True
    except OSError:
        pass
    return False

for report_path in glob.glob(os.path.join(reports_dir, "*.yaml")):
    if os.path.islink(report_path) or not os.path.isfile(report_path):
        continue
    try:
        with open(report_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    status = str(data.get("status") or "").strip().lower()
    parent = str(data.get("parent_cmd") or "").strip()
    if status == "pending":
        skipped_pending += 1
        continue
    if status not in eligible_statuses:
        skipped_ineligible += 1
        continue
    if parent in active_parents:
        skipped_active_parent += 1
        continue
    if not gate_complete(parent):
        skipped_gate_incomplete += 1
        continue
    candidates.append((os.path.getmtime(report_path), report_path))

print(
    "[archive] overflow candidates: "
    f"eligible={len(candidates)} skipped_pending={skipped_pending} "
    f"skipped_ineligible={skipped_ineligible} skipped_active_parent={skipped_active_parent} "
    f"skipped_gate_incomplete={skipped_gate_incomplete}",
    file=sys.stderr,
)

for _mtime, path in sorted(candidates):
    print(path)
PY

        # capの分母はCLEAR済み候補のみ。pending/active/GATE未完了は数えない。
        local remaining
        remaining="$(wc -l < "$overflow_list")"
        [ "$remaining" -le "$cap" ] && return 0

        local overflow_archived=0
        local overflow_path overflow_base overflow_dest
        while IFS= read -r overflow_path; do
            [ "$remaining" -le "$cap" ] && break
            [ -f "$overflow_path" ] || continue
            [ -L "$overflow_path" ] && continue
            overflow_base="${overflow_path##*/}"
            overflow_dest="$ARCHIVE_REPORT_DIR/${overflow_base%.yaml}_${date_stamp}.yaml"
            if [ -e "$overflow_dest" ]; then
                overflow_dest="$ARCHIVE_REPORT_DIR/${overflow_base%.yaml}_$(date '+%H%M%S').yaml"
            fi
            mv "$overflow_path" "$overflow_dest" || { echo "[archive] WARN: overflow mv failed: $overflow_path → $overflow_dest" >&2; continue; }
            overflow_archived=$((overflow_archived + 1))
            archived=$((archived + 1))
            remaining=$((remaining - 1))
            echo "[archive] OVERFLOW: archived completed report beyond cap=${cap}: $overflow_base"
        done < "$overflow_list"

        if [ "$overflow_archived" -gt 0 ]; then
            kept=$((kept - overflow_archived))
            [ "$kept" -lt 0 ] && kept=0
            echo "[archive] overflow-cap: archived=${overflow_archived} remaining=${remaining} cap=${cap}"
        fi
    }

    # Keep compatibility symlinks until the report owner replaces them under
    # the report-unit lock.  Removing them here used to race formal RC: the
    # RC writer could resolve a disappearing live path to the archived inode
    # and mutate the historical report instead of publishing a fresh one.

    # --- 非YAMLファイルの掃除 (忍者の成果物混入防止) ---
    # cmd指定は対象reportだけを動かす単一完了処理。無関係junkの回収は
    # sweep modeへ委ね、運用成果物をtargeted callの走査対象へ戻さない。
    if [ -z "$CMD_ID" ]; then
        shopt -s nullglob
        local all_files=("$REPORTS_DIR"/*)
        shopt -u nullglob
        for f in "${all_files[@]}"; do
            [ -f "$f" ] || continue
            case "$f" in *.yaml) continue ;; esac
            mv "$f" "$ARCHIVE_REPORT_DIR/" || { echo "[archive] WARN: mv failed: $f" >&2; continue; }
            junk=$((junk + 1))
        done
    fi

    # --- YAML報告のアーカイブ ---
    local report_files=()
    if [ -n "$CMD_ID" ]; then
        report_files=("${_TARGET_REPORT_FILES[@]}")
    else
        shopt -s nullglob
        report_files=("$REPORTS_DIR"/*_report*.yaml "$REPORTS_DIR"/subtask_*.yaml)
        shopt -u nullglob
    fi

    if [ ${#report_files[@]} -eq 0 ] && [ "$junk" -eq 0 ]; then
        echo "[archive] reports: none"
        return 0
    fi

    # GP-080: 共有キャッシュTSVから連想配列ロード (gawk実行は Main で1回のみ)
    declare -A _rpt_status _rpt_parent
    if [ -f "$_REPORT_CACHE" ]; then
        while IFS='|' read -r _rf _rs _rp; do
            _rpt_status["$_rf"]="$_rs"
            _rpt_parent["$_rf"]="$_rp"
        done < "$_REPORT_CACHE"
    fi

    # task files キャッシュ (L667-669のfield_get置換)
    # cmd_2529: 永続キャッシュはstatus変化をファイル数だけで判定できず、古いactive child判定で報告が残存する。
    # /tmp内の当該実行キャッシュに限定し、毎回現在のtask YAMLから生成する。
    declare -A _task_parent _task_status
    declare -A _queue_cmd_status _parent_has_active_child
    local _task_glob=("$PROJECT_DIR/queue/tasks"/*.yaml)
    if [ -z "$CMD_ID" ] && [ -f "${_task_glob[0]}" ]; then
        local _task_tsv="$TMP/task_fields.tsv"
        gawk '
            BEGINFILE {
                fname = FILENAME; sub(/.*\//, "", fname)
                st = ""; pc = ""; printed = 0
            }
            # GP-OPT3: 両フィールド発見後に nextfile で残行読込をスキップ（WSL2 I/O削減）
            # printed フラグで ENDFILE との二重出力を防止（gawk 5.x は nextfile 後も ENDFILE を実行する）
            !st && /status:/ && !/^#/ { st = $0; sub(/.*status: */, "", st); gsub(/["'"'"'\t ]/, "", st) }
            !pc && /parent_cmd:/ { pc = $0; sub(/.*parent_cmd: */, "", pc); gsub(/["'"'"'\t ]/, "", pc) }
            !printed && st && pc { print fname "|" st "|" pc; printed = 1; nextfile }
            ENDFILE { if (!printed) print fname "|" st "|" pc }
        ' "${_task_glob[@]}" 2>/dev/null > "$_task_tsv"
        while IFS='|' read -r _tf _ts _tp; do
            _task_status["$_tf"]="$_ts"
            _task_parent["$_tf"]="$_tp"
            case "$_ts" in
                done|completed|complete|success|failed|"") ;;
                *)
                    if [ -n "$_tp" ]; then
                        _parent_has_active_child["$_tp"]=1
                    fi
                    ;;
            esac
        done < "$_task_tsv"
    fi

    if [ -z "$CMD_ID" ] && [ -f "$QUEUE_FILE" ]; then
        while IFS='|' read -r _cid _cs; do
            [ -n "$_cid" ] || continue
            _queue_cmd_status["$_cid"]="$_cs"
        done < <(gawk '
            function emit() {
                if (cmd_id != "") print cmd_id "|" status
            }
            BEGINFILE {
                cmd_id = ""
                status = ""
            }
            /^[[:space:]]*-[[:space:]]id:[[:space:]]*cmd_/ {
                emit()
                cmd_id = $0
                sub(/^[[:space:]]*-[[:space:]]id:[[:space:]]*/, "", cmd_id)
                gsub(/[[:space:]]+$/, "", cmd_id)
                status = ""
                next
            }
            /^[[:space:]]{2}cmd_[0-9A-Za-z_]+:/ {
                emit()
                cmd_id = $0
                sub(/^[[:space:]]*/, "", cmd_id)
                sub(/:.*/, "", cmd_id)
                status = ""
                next
            }
            cmd_id != "" && /^[[:space:]]*status:[[:space:]]*/ {
                status = $0
                sub(/^[[:space:]]*status:[[:space:]]*/, "", status)
                gsub(/["'"'"'\t ]/, "", status)
                next
            }
            ENDFILE { emit() }
        ' "$QUEUE_FILE" 2>/dev/null)
    fi

    # _gate_status[cmd]: "missing"=gate不在, "placeholder"=deploy_preflight, "ok"=レビュー完了
    # cmd_2529: gate_statusはarchive sweep自身が補完するため、永続キャッシュ再利用は禁止。
    declare -A _gate_status=()
    classify_review_gate_status() {
        local _crg_path="$1"
        local _crg_status
        if grep -q "source: deploy_preflight" "$_crg_path" 2>/dev/null; then
            printf 'placeholder'
            return 0
        else
            _crg_status=$?
        fi
        case "$_crg_status" in
            1) printf 'ok' ;;       # readable, but not a deploy_preflight placeholder
            *) printf 'missing' ;;  # missing/unreadable, including TOCTOU deletion
        esac
    }
    if [ -f "$_REPORT_CACHE" ]; then
        # GP-OPT-kotaro: report件数分のgrepプロセスforkを1回のバルクgrepへ集約。
        # TOCTOU対応は維持: grep実行時点でファイルが消えていればstderrに
        # "No such file or directory"が出るためmissing判定できる(個別grep版と同じ意味論)。
        declare -A _seen_gate=()
        local -a _gate_paths=() _gate_parents=()
        while IFS='|' read -r _rc_fname _rc_status _rc_parent; do
            [ -z "$_rc_parent" ] && continue
            [ -n "${_seen_gate[$_rc_parent]:-}" ] && continue
            _seen_gate["$_rc_parent"]=1
            _gate_parents+=("$_rc_parent")
            _gate_paths+=("$PROJECT_DIR/queue/gates/${_rc_parent}/review_gate.done")
        done < "$_REPORT_CACHE"

        if [ ${#_gate_paths[@]} -gt 0 ]; then
            local _gs_out="$TMP/gate_status_bulk_out.log"
            local _gs_err="$TMP/gate_status_bulk_err.log"
            LC_ALL=C grep -l -- "source: deploy_preflight" "${_gate_paths[@]}" >"$_gs_out" 2>"$_gs_err" || true

            declare -A _placeholder_paths=()
            while IFS= read -r _pf; do
                [ -n "$_pf" ] && _placeholder_paths["$_pf"]=1
            done < "$_gs_out"

            declare -A _missing_paths=()
            while IFS= read -r _errline; do
                case "$_errline" in
                    *": No such file or directory")
                        local _mf="${_errline#*: }"
                        _mf="${_mf%: No such file or directory}"
                        _missing_paths["$_mf"]=1
                        ;;
                esac
            done < "$_gs_err"

            local _gi
            for _gi in "${!_gate_paths[@]}"; do
                local _gp="${_gate_paths[$_gi]}" _gparent="${_gate_parents[$_gi]}"
                if [ -n "${_placeholder_paths[$_gp]:-}" ]; then
                    _gate_status["$_gparent"]="placeholder"
                elif [ -n "${_missing_paths[$_gp]:-}" ]; then
                    _gate_status["$_gparent"]="missing"
                else
                    _gate_status["$_gparent"]="ok"
                fi
            done
        fi
    fi
    # CMD_ID指定時: _gate_statusに追加(REPORT_CACHEにない場合あり)
    if [ -n "$CMD_ID" ] && [ "${_gate_status[$CMD_ID]+x}" != "x" ]; then
        local _gc_g="$PROJECT_DIR/queue/gates/${CMD_ID}/review_gate.done"
        # GP-OPT1: $()サブシェル排除（CMD_IDパス）。||でset -e回避
        local _opt1_rc=0
        grep -q "source: deploy_preflight" "$_gc_g" 2>/dev/null || _opt1_rc=$?
        case "$_opt1_rc" in
            0) _gate_status["$CMD_ID"]="placeholder" ;;
            1) _gate_status["$CMD_ID"]="ok" ;;
            *) _gate_status["$CMD_ID"]="missing" ;;
        esac
    fi

    for report_file in "${report_files[@]}"; do
        if [ -L "$report_file" ]; then
            if archive_report_symlink_is_terminal "$report_file"; then
                echo "[archive] terminal symlink retained: ${report_file##*/}"
            else
                kept=$((kept + 1))
                echo "[archive] SKIP: invalid report symlink retained: ${report_file##*/}"
            fi
            continue
        fi
        [ -f "$report_file" ] || continue

        local status_val parent_cmd base_name target_name dest_path
        local _bname; _bname="${report_file##*/}"
        status_val="${_rpt_status[$_bname]:-}"
        parent_cmd="${_rpt_parent[$_bname]:-}"

        # cmd指定時は該当cmdの報告のみを対象化
        if [ -n "$CMD_ID" ] && [ -n "$parent_cmd" ] && [ "$parent_cmd" != "$CMD_ID" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        # CMD_ID指定パス: status=pending → スキップ（生成直後のテンプレート保護）
        if [ -n "$CMD_ID" ] && [ "$status_val" = "pending" ]; then
            echo "[archive] WARNING: Skipping pending report: $_bname"
            kept=$((kept + 1))
            continue
        fi

        # review_gate.done未存在 → 家老レビュー未完了なのでアーカイブをスキップ
        local check_cmd_for_review=""
        if [ -n "$CMD_ID" ]; then
            check_cmd_for_review="$CMD_ID"
        elif [ -n "$parent_cmd" ]; then
            check_cmd_for_review="$parent_cmd"
        fi
        if [ -n "$check_cmd_for_review" ]; then
            # 修練cmd例外: training/cycle/selfimprovementはGATEフロー外のためreview_gate.doneチェック不要
            local is_training_cmd=false
            case "$check_cmd_for_review" in
                cmd_training_*|cmd_cycle_*|cmd_selfimprovement_*) is_training_cmd=true ;;
            esac
            if [ "$is_training_cmd" = "false" ]; then
                # GP-XXX2: O(1) lookup via pre-scanned _gate_status (per-file [ -f ] + grep -q を排除)
                case "${_gate_status[$check_cmd_for_review]:-missing}" in
                    missing)
                        if gate_metrics_has_clear "$check_cmd_for_review"; then
                            write_review_gate_from_metrics "$check_cmd_for_review"
                            _gate_status["$check_cmd_for_review"]="ok"
                            echo "[archive] BACKFILL: review_gate.done missing but gate_metrics CLEAR found for ${check_cmd_for_review}: $_bname"
                        elif karo_review_decision_recorded "$check_cmd_for_review" \
                             && report_verdict_is_fail "$report_file"; then
                            # cmd_karo_impl_fail_close_path_20260725: FAIL verdictのcmdは
                            # 定義上CLEARへ到達せず、従来はここでkept++され報告が永久に滞留し
                            # 忍者が解放されなかった。家老の正式レビュー証跡がある場合に限り退避を許す。
                            # CLEARは捏造しない(review_gate.doneを書かない)ため、gate_metrics上は
                            # CLEARにならず品質記録にはFAILのまま残る。
                            echo "[archive] FAIL_CLOSE: verdict=FAIL with recorded Karo review and no CLEAR for ${check_cmd_for_review}; archiving without creating a CLEAR marker: $_bname"
                        elif report_is_stale_gate_incomplete "$report_file"; then
                            echo "[archive] STALE: review_gate.done missing and no CLEAR for ${check_cmd_for_review}; archiving 14d+ report as gate-incomplete: $_bname"
                        else
                            echo "[archive] SKIP: review_gate.done not found for ${check_cmd_for_review}: $_bname"
                            kept=$((kept + 1)); continue
                        fi
                        ;;
                    placeholder)
                        if gate_metrics_has_clear "$check_cmd_for_review"; then
                            write_review_gate_from_metrics "$check_cmd_for_review"
                            _gate_status["$check_cmd_for_review"]="ok"
                            echo "[archive] BACKFILL: review_gate.done placeholder replaced from gate_metrics CLEAR for ${check_cmd_for_review}: $_bname"
                        elif karo_review_decision_recorded "$check_cmd_for_review" \
                             && report_verdict_is_fail "$report_file"; then
                            # cmd_karo_impl_fail_close_path_20260725: missing側と同一根拠。
                            # placeholderのままCLEARに到達しないFAIL cmdも滞留させない。
                            echo "[archive] FAIL_CLOSE: verdict=FAIL with recorded Karo review and placeholder gate for ${check_cmd_for_review}; archiving without creating a CLEAR marker: $_bname"
                        else
                            # GP-133: deploy_preflightのplaceholderはレビュー未完了。アーカイブ禁止。
                            if report_is_stale_gate_incomplete "$report_file"; then
                                echo "[archive] STALE: review_gate.done placeholder and no CLEAR for ${check_cmd_for_review}; archiving 14d+ report as gate-incomplete: $_bname"
                            else
                                echo "[archive] SKIP: review_gate.done is placeholder (deploy_preflight) for ${check_cmd_for_review}: $_bname"
                                kept=$((kept + 1)); continue
                            fi
                        fi
                        ;;
                esac
            fi
        fi

        # CMD_ID指定なし(sweep mode): 完了報告のみ。CMD_ID指定あり: status不問で全archive
        if [ -z "$CMD_ID" ]; then
            local status_lower="${status_val,,}"
            case "$status_lower" in
                done|completed|complete|success|failed|pass|fail|blocked|waived|stop_for) ;;
                *)
                    kept=$((kept + 1))
                    continue
                    ;;
            esac

            # sweep mode安全弁: 親cmdが進行中なら報告を退避しない
            # 取得失敗(空文字)は安全側(keep)へ倒す。
            if [ -n "$parent_cmd" ]; then
                local cmd_status
                if [ ! -f "$QUEUE_FILE" ]; then
                    kept=$((kept + 1))
                    continue
                fi

                cmd_status="${_queue_cmd_status[$parent_cmd]:-}"

                case "$cmd_status" in
                    pending|delegated|in_progress|acknowledged)
                        kept=$((kept + 1))
                        continue
                        ;;
                    "")
                        # parent cmd not in QUEUE_FILE — check child tasks
                        if [ "${_parent_has_active_child[$parent_cmd]:-}" = "1" ]; then
                            kept=$((kept + 1))
                            continue
                        fi
                        # No active children — safe to archive
                        ;;
                esac
            fi

            # archive.doneチェック: GATE未完了cmdの報告をsweepから保護
            # archive.doneはcmd_complete_gate.shのGATE CLEAR最終ステップで作成される。
            # これがない=GATEの全処理未完了→報告退避は早すぎる(cmd_1519-1522レース事故の再発防止)
            if [ -n "$parent_cmd" ]; then
                # 修練cmd例外: training/cycle/selfimprovementはGATEフロー外のためarchive.doneチェック不要
                local skip_archive_done=false
                case "$parent_cmd" in
                    cmd_training_*|cmd_cycle_*|cmd_selfimprovement_*) skip_archive_done=true ;;
                esac
                if [ "$skip_archive_done" = "false" ]; then
                    local archive_done_flag="$PROJECT_DIR/queue/gates/${parent_cmd}/archive.done"
                    if [ ! -f "$archive_done_flag" ]; then
                        if gate_metrics_has_clear "$parent_cmd"; then
                            write_archive_done_from_metrics "$parent_cmd"
                            echo "[archive] BACKFILL: archive.done missing but gate_metrics CLEAR found for ${parent_cmd}: $_bname"
                        elif report_is_stale_gate_incomplete "$report_file"; then
                            echo "[archive] STALE(sweep): archive.done missing and no CLEAR for ${parent_cmd}; archiving 14d+ report as gate-incomplete: $_bname"
                        else
                            echo "[archive] SKIP(sweep): archive.done not found for ${parent_cmd}: $_bname"
                            kept=$((kept + 1))
                            continue
                        fi
                    fi
                fi
            fi
        fi

        base_name="$_bname"
        target_name="$base_name"

        # 旧形式はアーカイブ時にcmdサフィックスを付与（識別性向上）
        if [[ "$base_name" =~ _report\.yaml$ ]] && [[ "$parent_cmd" == cmd_* ]]; then
            target_name="${base_name%.yaml}_${parent_cmd}.yaml"
        fi

        # The eligibility scan above is only a candidate selection. Recheck
        # the live report under the same report-unit lock as mv+symlink so a
        # concurrent formal RC cannot archive a report after it was reopened.
        local report_lock_fd report_lock_file report_move_rc
        report_lock_file="$(lock_path "${report_file}.report-unit")"
        exec {report_lock_fd}>"$report_lock_file"
        if ! flock -w 10 "$report_lock_fd"; then
            echo "[archive] WARN: report lock timeout: $report_file" >&2
            eval "exec ${report_lock_fd}>&-"
            kept=$((kept + 1))
            continue
        fi

        report_move_rc=0
        if [ -L "$report_file" ] || [ ! -f "$report_file" ]; then
            report_move_rc=2
        else
            local locked_status
            locked_status="$(FIELD_GET_NO_LOG=1 field_get "$report_file" status "" 2>/dev/null || true)"
            case "${locked_status,,}" in
                pending|revision_requested|assigned|acknowledged|in_progress)
                    report_move_rc=2
                    ;;
                *)
                    dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_${date_stamp}.yaml"
                    if [ -e "$dest_path" ]; then
                        dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_$(date '+%H%M%S').yaml"
                    fi
                    mv "$report_file" "$dest_path" || report_move_rc=1
                    if [ "$report_move_rc" -eq 0 ]; then
                        ln -sf "$dest_path" "$report_file" 2>/dev/null || true  # GP-230: compatibility path
                    fi
                    ;;
            esac
        fi
        flock -u "$report_lock_fd" || true
        eval "exec ${report_lock_fd}>&-"

        case "$report_move_rc" in
            0) archived=$((archived + 1)) ;;
            2) kept=$((kept + 1)); echo "[archive] SKIP: report changed during selection: $_bname" ;;
            *) echo "[archive] WARN: mv failed: $report_file → $dest_path" >&2; kept=$((kept + 1)) ;;
        esac
    done

    if [ -z "$CMD_ID" ]; then
        archive_overflow_reports_to_cap
    else
        # Targeted completion moves zero or more physical reports out of the
        # live set and therefore cannot increase the eligible-report count.
        # The cap invariant is monotonic here; global overflow repair remains
        # in sweep mode without paying full YAML parse cost per completion.
        echo "[archive] overflow-cap: targeted monotonic-decrease; sweep deferred"
    fi

    echo "[archive] reports: archived=$archived kept=$kept skipped=$skipped junk=$junk"
}

# ============================================================
# 1.6 dashboard.md KARO_SECTION 最新更新 — 古い更新をアーカイブ（直近3件を残す）
# ============================================================
archive_karo_section() {
    local karo_archive="$ARCHIVE_DIR/dashboard_karo_archive.md"
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; exit 1; }
        [ -f "$DASHBOARD" ] || { echo "[archive] ERROR: dashboard missing under lock" >&2; exit 1; }
        local update_start update_end total_updates archived_count delete_csv tmp_dash
        local -a update_lines delete_lines
        update_start=$(grep -n '^## 最新更新' "$DASHBOARD" | head -1 | cut -d: -f1 || true)
        if [[ -z "$update_start" ]]; then
            echo "[archive] WARN: DATA_QUALITY karo_section '## 最新更新' not found; archive skipped"
            exit 0
        fi
        update_end=$(awk -v s="$update_start" 'NR > s && /^## / { print NR - 1; found=1; exit } END { if (!found) print NR }' "$DASHBOARD")
        mapfile -t update_lines < <(awk -v s="$update_start" -v e="$update_end" 'NR > s && NR <= e && /^- \*\*cmd_[^*]*\*\*:/ { print NR }' "$DASHBOARD")
        total_updates=${#update_lines[@]}
        if [[ $total_updates -le 3 ]]; then
            echo "[archive] karo_updates: $total_updates entries <= 3, skip"
            exit 0
        fi
        delete_lines=("${update_lines[@]:3}")
        archived_count=${#delete_lines[@]}
        delete_csv=$(IFS=,; echo "${delete_lines[*]}")
        {
            echo ""
            echo "# Archived KARO updates $(date '+%Y-%m-%d %H:%M')"
            for line_no in "${delete_lines[@]}"; do sed -n "${line_no}p" "$DASHBOARD"; done
        } >> "$karo_archive"
        tmp_dash=$(mktemp "${DASHBOARD}.archive.XXXXXX")
        trap 'rm -f -- "$tmp_dash"' EXIT
        awk -v csv="$delete_csv" '
            BEGIN {
                n = split(csv, arr, ",")
                for (i = 1; i <= n; i++) {
                    if (arr[i] != "") del[arr[i]] = 1
                }
            }
            !(NR in del) { print }
        ' "$DASHBOARD" > "$tmp_dash"
        mv -f -- "$tmp_dash" "$DASHBOARD" || { echo "[archive] FATAL: atomic publish failed: karo trim" >&2; exit 1; }
        trap - EXIT
        echo "[archive] karo_updates: archived=$archived_count kept=3"
    ) 200>"${DASHBOARD}.lock"
}

# ============================================================
# 2. dashboard.md — 古い戦果をアーカイブ（直近N件を残す）
# ============================================================
archive_dashboard() {
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; exit 1; }
        [ -f "$DASHBOARD" ] || { echo "[archive] ERROR: dashboard missing under lock" >&2; exit 1; }
        local total archive_first_line last_data_line archived_count tmp_dash
        local -a result_lines
        mapfile -t result_lines < <(grep -n '^| [0-9]' "$DASHBOARD" | cut -d: -f1)
        total=${#result_lines[@]}
        if [ "$total" -le "$KEEP_RESULTS" ]; then
            echo "[archive] dashboard: $total results <= keep=$KEEP_RESULTS, skip"
            exit 0
        fi
        archive_first_line=${result_lines[$KEEP_RESULTS]}
        last_data_line=${result_lines[$((total - 1))]}
        archived_count=$((total - KEEP_RESULTS))
        {
            echo ""
            echo "# Archived $(date '+%Y-%m-%d %H:%M')"
            sed -n "${archive_first_line},${last_data_line}p" "$DASHBOARD"
        } >> "$DASH_ARCHIVE"
        tmp_dash=$(mktemp "${DASHBOARD}.archive.XXXXXX")
        trap 'rm -f -- "$tmp_dash"' EXIT
        if ! sed "${archive_first_line},${last_data_line}d" "$DASHBOARD" > "$tmp_dash"; then
            echo "[archive] FATAL: sed failed for dashboard trim" >&2
            exit 1
        fi
        mv -f -- "$tmp_dash" "$DASHBOARD" || { echo "[archive] FATAL: atomic publish failed: dashboard trim" >&2; exit 1; }
        trap - EXIT
        echo "[archive] dashboard: archived=$archived_count kept=$KEEP_RESULTS"
    ) 200>"${DASHBOARD}.lock"
}

# ============================================================
# 2.5 cmd-chronicle.md — 30日超のエントリをarchive/cmd-chronicle/YYYY-MM.mdに退避
# ============================================================
trim_cmd_chronicle() {
    [ -f "$CHRONICLE_FILE" ] || return 0

    local cutoff_date
    cutoff_date=$(date -d '30 days ago' '+%Y-%m-%d')

    # 早期リターン: 30日超エントリが存在しない場合はPython起動をスキップ
    if ! gawk -v co="$cutoff_date" '
        /^## [0-9]{4}-[0-9]{2}$/ {
            section_year = substr($0, 4, 4)
            next
        }
        /^\| cmd_/ {
            n = split($0, p, "|")
            d = p[5]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
            if (d ~ /^[0-9]{2}-[0-9]{2}$/ && section_year != "") {
                d = section_year "-" d
            }
            if (d ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && d < co) { found = 1; exit }
        }
        END { exit !found }
    ' "$CHRONICLE_FILE" 2>/dev/null; then
        echo "[chronicle-trim] noop: no old entries (early exit)"
        return 0
    fi

    local chronicle_rc
    (
        flock -w 10 200 || { echo "[chronicle-trim] WARN: flock timeout" >&2; return 1; }

        python3 - "$CHRONICLE_FILE" "$CHRONICLE_ARCHIVE_DIR" "$cutoff_date" <<'PY'
import os
import sys
from datetime import datetime

chronicle_path, archive_dir, cutoff_str = sys.argv[1:4]
cutoff = datetime.strptime(cutoff_str, "%Y-%m-%d")

def read_text_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines()
    except UnicodeDecodeError as exc:
        print(
            f"[chronicle-trim] WARN: non-utf8 input replaced: {path} "
            f"byte={exc.start} reason={exc.reason}",
            file=sys.stderr,
        )
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()

lines = read_text_lines(chronicle_path)

# Phase 1: Parse into file_header + sections
file_header = []
sections = []  # [(ym, header_lines, data_rows)]
current_ym = None
section_header = []
section_data = []

for line in lines:
    if line.startswith("## "):
        if current_ym is not None:
            sections.append((current_ym, list(section_header), list(section_data)))
        current_ym = line[3:].strip()
        section_header = [line]
        section_data = []
    elif current_ym is None:
        file_header.append(line)
    elif line.startswith("| cmd_"):
        section_data.append(line)
    else:
        if not section_data:
            section_header.append(line)
        else:
            section_data.append(line)

if current_ym is not None:
    sections.append((current_ym, list(section_header), list(section_data)))

# Phase 2: Separate keep vs archive
to_archive = {}  # ym -> [rows]
kept_sections = []
total_archived = 0

for ym, header, data in sections:
    year = ym[:4]
    keep = []
    for row in data:
        if not row.startswith("| cmd_"):
            keep.append(row)
            continue
        parts = [p.strip() for p in row.split("|")]
        date_str = parts[4] if len(parts) > 4 else ""
        try:
            full_date = datetime.strptime(f"{year}-{date_str}", "%Y-%m-%d")
        except (ValueError, IndexError):
            keep.append(row)
            continue
        if full_date < cutoff:
            target_ym = full_date.strftime("%Y-%m")
            to_archive.setdefault(target_ym, []).append(row)
            total_archived += 1
        else:
            keep.append(row)
    has_data = any(r.startswith("| cmd_") for r in keep)
    if has_data:
        kept_sections.append((ym, header, keep))

if total_archived == 0:
    print("noop")
    sys.exit(0)

# Phase 3: Write archive files
os.makedirs(archive_dir, exist_ok=True)
for ym, rows in to_archive.items():
    archive_path = os.path.join(archive_dir, f"{ym}.md")
    if os.path.exists(archive_path):
        existing = read_text_lines(archive_path)
        existing_ids = set()
        for el in existing:
            if el.startswith("| cmd_"):
                existing_ids.add(el.split("|")[1].strip())
        new_rows = [r for r in rows if r.split("|")[1].strip() not in existing_ids]
        if new_rows:
            existing.extend(new_rows)
            with open(archive_path, "w", encoding="utf-8") as f:
                f.write("\n".join(existing) + "\n")
    else:
        content = [
            f"# CMD年代記 Archive: {ym}",
            "",
            "| cmd | title | project | date | key_result |",
            "|-----|-------|---------|------|------------|",
        ]
        content.extend(rows)
        with open(archive_path, "w", encoding="utf-8") as f:
            f.write("\n".join(content) + "\n")

# Phase 4: Rebuild chronicle
output = list(file_header)
for ym, header, data in kept_sections:
    output.extend(header)
    output.extend(data)

today = datetime.now().strftime("%Y-%m-%d")
for idx, line in enumerate(output):
    if line.startswith("<!-- last_updated:"):
        output[idx] = f"<!-- last_updated: {today} -->"
        break

with open(chronicle_path, "w", encoding="utf-8") as f:
    f.write("\n".join(output) + "\n")

print(f"trimmed: archived={total_archived}")
PY
    ) 200>"/tmp/mas-chronicle.lock"
    chronicle_rc=$?
    if [ "$chronicle_rc" -ne 0 ]; then
        return "$chronicle_rc"
    fi

    echo "[chronicle-trim] done"
}

# ============================================================
# 2.7 shogun_to_karo.yaml — 完了済み+30日超のエントリを退避 (cmd_1120_b)
# ============================================================
STK_ARCHIVE_DIR="$PROJECT_DIR/archive/shogun_to_karo"

trim_stk_old_entries() {
    # GP-XXX: trim_stk_old logic is now merged into sync_stk_status_from_archive (single Python call)
    echo "[stk-trim] (merged into sync_stk, skipped)"
}

# ============================================================
# Main
# ============================================================
_TARGET_REPORT_MANIFEST="$TMP/target_report_manifest.tsv"
_TARGET_REPORT_FILES=()

# CMD_ID指定時のreport集合は、完了generationが既に持つidentityから先に確定する。
# 優先順は (1) terminal review manifest、(2) worker taskのreport_path、
# (3) cmd_idを境界付きで含む標準basename。report本文の全走査からparent_cmdを
# 後判定する旧経路は、無関係reportのyaml.safe_loadを発生させるため使わない。
build_target_report_manifest() {
    [ -n "$CMD_ID" ] || return 0
    local raw="$TMP/target_report_manifest.raw.tsv"
    : > "$raw"

    local terminal_manifest="$PROJECT_DIR/queue/gates/${CMD_ID}/terminal_review_manifest.json"
    if [ -f "$terminal_manifest" ]; then
        python3 - "$terminal_manifest" "$CMD_ID" "$PROJECT_DIR" <<'PY' >> "$raw"
import json
import os
import sys

manifest_path, cmd_id, project_dir = sys.argv[1:4]
try:
    with open(manifest_path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError):
    raise SystemExit(0)
if not isinstance(data, dict) or str(data.get("cmd_id") or "") != cmd_id:
    raise SystemExit(0)
for row in data.get("reports") or []:
    if not isinstance(row, dict):
        continue
    logical = str(row.get("logical_path") or "").strip()
    if logical.startswith("queue/reports/"):
        print(f"{cmd_id}\tmanifest\t{os.path.join(project_dir, logical)}")
PY
    fi

    shopt -s nullglob
    local task_files=("$PROJECT_DIR/queue/tasks"/*.yaml)
    shopt -u nullglob
    if [ ${#task_files[@]} -gt 0 ]; then
        gawk -v want="$CMD_ID" -v reports="$REPORTS_DIR" '
            BEGINFILE {
                worker=FILENAME; sub(/.*\//,"",worker); sub(/\.yaml$/,"",worker)
                parent=""; report_path=""; report_name=""
            }
            /^[[:space:]]{2}parent_cmd:[[:space:]]*/ && parent=="" {
                parent=$0; sub(/^[^:]*:[[:space:]]*/,"",parent); gsub(/["'"'"'[:space:]]/,"",parent)
            }
            /^[[:space:]]{2}report_path:[[:space:]]*/ && report_path=="" {
                report_path=$0; sub(/^[^:]*:[[:space:]]*/,"",report_path)
                gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/,"",report_path)
            }
            /^[[:space:]]{2}report_filename:[[:space:]]*/ && report_name=="" {
                report_name=$0; sub(/^[^:]*:[[:space:]]*/,"",report_name)
                gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/,"",report_name)
            }
            ENDFILE {
                if (parent == want) {
                    if (report_path != "") {
                        if (report_path ~ /^\//) path=report_path
                        else {
                            sub(/^queue\/reports\//,"",report_path)
                            path=reports "/" report_path
                        }
                    } else if (report_name != "") path=reports "/" report_name
                    else path=reports "/" worker "_report_" want ".yaml"
                    print want "\t" worker "\t" path
                }
            }
        ' "${task_files[@]}" >> "$raw"
    fi

    shopt -s nullglob
    local path base worker
    local named_reports=(
        "$REPORTS_DIR"/*_report_"$CMD_ID".yaml
        "$REPORTS_DIR"/*_report_"$CMD_ID"_*.yaml
    )
    shopt -u nullglob
    for path in "${named_reports[@]}"; do
        base="${path##*/}"
        worker="${base%%_report_*}"
        printf '%s\t%s\t%s\n' "$CMD_ID" "$worker" "$path" >> "$raw"
    done

    local candidate rest
    while IFS=$'\t' read -r _cmd worker candidate; do
        [ "$_cmd" = "$CMD_ID" ] || continue
        case "$candidate" in
            "$PROJECT_DIR"/queue/reports/*) ;;
            "$REPORTS_DIR"/*) ;;
            *) continue ;;
        esac
        rest="${candidate#"$REPORTS_DIR"/}"
        [[ "$rest" != */* && "$rest" == *.yaml ]] || continue
        [ -f "$candidate" ] || [ -L "$candidate" ] || continue
        printf '%s\t%s\t%s\n' "$CMD_ID" "$worker" "$candidate"
    done < "$raw" | awk -F '\t' '!seen[$3]++' > "$_TARGET_REPORT_MANIFEST"

    if [ -s "$_TARGET_REPORT_MANIFEST" ]; then
        mapfile -t _TARGET_REPORT_FILES < <(cut -f3 "$_TARGET_REPORT_MANIFEST")
    fi
    echo "[archive] target-report-manifest: cmd=$CMD_ID reports=${#_TARGET_REPORT_FILES[@]}"
}

echo "[archive_completed] $(date '+%Y-%m-%d %H:%M:%S') start"

# GP-080: 報告ファイルのstatus/parent_cmdを一括抽出 (実行内共有キャッシュ)
# sync_stk Source 2 + archive_reports L582-583 の両方が消費
# cmd_2529: /tmp永続キャッシュはsymlink残置や内容変更をファイル数だけで検知できず、古いreport状態を再利用する。
_REPORT_CACHE="$TMP/report_fields_cache.tsv"
if [ -n "$CMD_ID" ]; then
    build_target_report_manifest
    _rpt_files=("${_TARGET_REPORT_FILES[@]}")
elif compgen -G "$REPORTS_DIR/*_report*.yaml" > /dev/null 2>&1 || compgen -G "$REPORTS_DIR/subtask_*.yaml" > /dev/null 2>&1; then
    shopt -s nullglob
    _rpt_files=("$REPORTS_DIR"/*.yaml)
    shopt -u nullglob
else
    _rpt_files=()
fi
_rpt_read_files=()
for _rpt_file in "${_rpt_files[@]}"; do
    # Never dereference queue symlinks during the metadata cache pass. The
    # archive_reports loop classifies them under the same fail-closed
    # terminal predicate, including dangling and outside targets.
    [ -L "$_rpt_file" ] && continue
    [ -f "$_rpt_file" ] || continue
    _rpt_read_files+=("$_rpt_file")
done
if [ ${#_rpt_read_files[@]} -gt 0 ]; then
    gawk '
        BEGINFILE {
            fname = FILENAME; sub(/.*\//, "", fname)
            st = ""; pc = ""; printed = 0
        }
        # GP-OPT3: 両フィールド発見後に nextfile で残行読込をスキップ（WSL2 I/O削減）
        # printed フラグで ENDFILE との二重出力を防止（gawk 5.x は nextfile 後も ENDFILE を実行する）
        !st && /^status:/ { st = $0; sub(/.*status: */, "", st); gsub(/["'"'"'\t ]/, "", st) }
        !pc && /^parent_cmd:/ { pc = $0; sub(/.*parent_cmd: */, "", pc); gsub(/["'"'"'\t ]/, "", pc) }
        !printed && st && pc { print fname "|" st "|" pc; printed = 1; nextfile }
        ENDFILE { if (!printed) print fname "|" st "|" pc }
    ' "${_rpt_read_files[@]}" 2>/dev/null > "$_REPORT_CACHE"
fi

# ============================================================
# queue配下 一発限りsentinel/flag の保持期限(retention)回収
# cmd_karo_hotfix_queue_flag_retention_20260725
#
# 対象と根拠(参照元コードの現物読解):
#   queue/gates/<cmd>/*              archive_completed.sh / cmd_complete_gate.sh /
#                                    auto_draft_lesson.sh — 全て per-cmd キー参照のみ。
#                                    GATE CLEAR + archive 完了後は読み手なし。
#                                    唯一の後読みは archive_reports() の archive.done 参照だが、
#                                    これは queue/reports に当該cmdの報告が残る間だけ。
#   queue/dispatch_ntfy_started/<cmd>.started        deploy_task.sh(初回通知一回性) と
#                                    cmd_complete_gate.sh(duration fallback)。GATE 完了後は不要。
#   queue/draft_review_started/<cmd>.draft_review.started  deploy_task.sh の一回性のみ。
#   queue/locks/deploy_cmd_*.lock    flock 用の空ファイル。未保持なら削除しても再生成される。
#
# 判定は mtime 単独ではなく cmd の実状態に基づく:
#   (1) archive.done 存在 または gate_metrics.log の CLEAR 記録（完了の一次証跡）
#   (2) 稼働中参照が queue 配下の一次データに 1 件も無い
#   (3) reopen されていない (queue/reopened_cmds/<cmd>.yaml が無い)
#   (4) 完了証跡の mtime が保持日数を超過
# 削除ではなく quarantine 移動を既定とする（即rm禁止）。
# ============================================================
QUEUE_FLAG_RETENTION_MODE="${QUEUE_FLAG_RETENTION_MODE:-quarantine}" # off|dry-run|quarantine
QUEUE_FLAG_RETENTION_INTERVAL_SEC="${QUEUE_FLAG_RETENTION_INTERVAL_SEC:-86400}"
QUEUE_FLAG_RETENTION_STAMP="${QUEUE_FLAG_RETENTION_STAMP:-$PROJECT_DIR/queue/flags/queue_flag_retention.last}"
QUEUE_FLAG_RETENTION_DAYS="${QUEUE_FLAG_RETENTION_DAYS:-30}"
QUEUE_FLAG_QUARANTINE_DIR="${QUEUE_FLAG_QUARANTINE_DIR:-$PROJECT_DIR/archive/queue_flag_quarantine}"
QUEUE_FLAG_RETENTION_REPORT="${QUEUE_FLAG_RETENTION_REPORT:-$PROJECT_DIR/logs/queue_flag_retention_candidates.tsv}"

# 稼働中cmd集合。queue配下の一次データを over-inclusive に走査する（安全側）。
_qfr_build_active_set() {
    local out="$1"
    {
        grep -hoE 'cmd_[A-Za-z0-9_.-]+' \
            "$PROJECT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true
        for _d in tasks reports deferred direct_tasks drafts inbox reopened_cmds; do
            [ -d "$PROJECT_DIR/queue/$_d" ] || continue
            grep -rhoE 'cmd_[A-Za-z0-9_.-]+' "$PROJECT_DIR/queue/$_d" 2>/dev/null || true
            find "$PROJECT_DIR/queue/$_d" -maxdepth 1 -printf '%f\n' 2>/dev/null \
                | grep -oE 'cmd_[A-Za-z0-9_.-]+' || true
        done
    } | sed 's/\.yaml$//' | sort -u > "$out"
}

# gate_metrics.log の CLEAR 済み cmd 集合
_qfr_build_clear_set() {
    local out="$1"
    : > "$out"
    [ -f "$PROJECT_DIR/logs/gate_metrics.log" ] || return 0
    awk -F'\t' '
        $2 == "CLEAR" && $3 != "" { print $3; next }
        $3 == "CLEAR" && $2 != "" { print $2; next }
    ' "$PROJECT_DIR/logs/gate_metrics.log" 2>/dev/null | sort -u > "$out"
}

# realpath が queue 配下であることを検証（AC3: blast radius 封じ込め）
_qfr_assert_under_queue() {
    local p rp queue_root
    queue_root="$(cd "$PROJECT_DIR/queue" && pwd -P)"
    for p in "$@"; do
        rp="$(realpath -m "$p")"
        case "$rp" in
            "$queue_root"/*) ;;
            *) echo "[flag-retention] ABORT: queue外パス検出: $rp" >&2; return 1 ;;
        esac
    done
    return 0
}

_qfr_lock_is_free() {
    local lock_file="$1" fd
    exec {fd}>>"$lock_file" 2>/dev/null || return 1
    if flock -n "$fd"; then
        flock -u "$fd"
        exec {fd}>&-
        return 0
    fi
    exec {fd}>&-
    return 1
}

prune_queue_flag_retention() {
    case "$QUEUE_FLAG_RETENTION_MODE" in
        off) return 0 ;;
        dry-run|quarantine) ;;
        *) echo "[flag-retention] ERROR: 未知のMODE: $QUEUE_FLAG_RETENTION_MODE" >&2; return 1 ;;
    esac
    if [[ ! "$QUEUE_FLAG_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        echo "[flag-retention] ERROR: RETENTION_DAYS は非負整数" >&2; return 1
    fi

    # スロットル: 既定は24時間に1回。/mnt/c 上の全走査コストを毎回払わない。
    if [ "${QUEUE_FLAG_RETENTION_INTERVAL_SEC}" -gt 0 ] && [ -f "$QUEUE_FLAG_RETENTION_STAMP" ]; then
        local _last _age
        _last=$(stat -c %Y "$QUEUE_FLAG_RETENTION_STAMP" 2>/dev/null || echo 0)
        _age=$(( $(date +%s) - _last ))
        if [ "$_age" -lt "$QUEUE_FLAG_RETENTION_INTERVAL_SEC" ]; then
            echo "[flag-retention] skip: 前回実行から ${_age}s (interval=${QUEUE_FLAG_RETENTION_INTERVAL_SEC}s)"
            return 0
        fi
    fi
    mkdir -p "$(dirname "$QUEUE_FLAG_RETENTION_STAMP")"
    : > "$QUEUE_FLAG_RETENTION_STAMP"

    local active="$TMP/qfr_active.txt" cleared="$TMP/qfr_clear.txt"
    _qfr_build_active_set "$active"
    _qfr_build_clear_set "$cleared"

    local now cutoff
    now=$(date +%s)
    cutoff=$(( now - QUEUE_FLAG_RETENTION_DAYS * 86400 ))

    local cand="$TMP/qfr_candidates.tsv"
    : > "$cand"

    # /mnt/c は 1 プロセス起動が高価。判定はサブプロセスを起こさず連想配列で回す。
    local -A _qfr_active=() _qfr_clear=() _qfr_reopened=()
    local _k
    while IFS= read -r _k; do
        if [ -n "$_k" ]; then _qfr_active["$_k"]=1; fi
    done < "$active"
    while IFS= read -r _k; do
        if [ -n "$_k" ]; then _qfr_clear["$_k"]=1; fi
    done < "$cleared"
    if [ -d "$PROJECT_DIR/queue/reopened_cmds" ]; then
        while IFS= read -r _k; do
            _qfr_reopened["${_k%.yaml}"]=1
        done < <(find "$PROJECT_DIR/queue/reopened_cmds" -maxdepth 1 -name '*.yaml' -printf '%f\n' 2>/dev/null)
    fi

    local gates_dir="$PROJECT_DIR/queue/gates"
    local cmd ev_mtime has_archive_done
    if [ -d "$gates_dir" ]; then
        # 1 回の find で「cmd dir と archive.done の mtime」をまとめて取る
        while IFS=$'\t' read -r cmd has_archive_done ev_mtime; do
            [ -n "$cmd" ] || continue
            case "$cmd" in cmd_*) ;; *) continue ;; esac
            [ -z "${_qfr_reopened[$cmd]:-}" ] || continue          # (3)
            [ -z "${_qfr_active[$cmd]:-}" ] || continue            # (2)
            if [ "$has_archive_done" != "1" ]; then                # (1)
                [ -n "${_qfr_clear[$cmd]:-}" ] || continue
            fi
            [ "$ev_mtime" -le "$cutoff" ] || continue              # (4)
            printf 'gates\t%s\t%s\n' "$cmd" "$gates_dir/$cmd" >> "$cand"
        done < <(
            {
                find "$gates_dir" -mindepth 1 -maxdepth 1 -type d -printf 'D\t%f\t%T@\n' 2>/dev/null
                find "$gates_dir" -mindepth 2 -maxdepth 2 -type f -name archive.done -printf 'A\t%h\t%T@\n' 2>/dev/null
            } |
            awk -F'\t' '
                { split($3, m, "."); ts = m[1] }
                $1 == "D" { dirmtime[$2] = ts; order[++n] = $2; next }
                $1 == "A" { base = $2; sub(/.*\//, "", base); adone[base] = ts; next }
                END {
                    for (i = 1; i <= n; i++) {
                        d = order[i]
                        if (d in adone) print d "\t1\t" adone[d]
                        else print d "\t0\t" dirmtime[d]
                    }
                }
            '
        )
    fi

    # cmd単位で回収可能と判定できたものだけ、他ディレクトリの同cmdフラグも回収する
    local -A _qfr_reclaim=()
    while IFS=$'\t' read -r _k cmd _; do
        if [ "$_k" = "gates" ]; then _qfr_reclaim["$cmd"]=1; fi
    done < "$cand"

    local f base
    for cmd in ${_qfr_reclaim[@]+"${!_qfr_reclaim[@]}"}; do
        f="$PROJECT_DIR/queue/dispatch_ntfy_started/${cmd}.started"
        [ ! -f "$f" ] || printf 'dispatch_ntfy_started\t%s\t%s\n' "$cmd" "$f" >> "$cand"
        f="$PROJECT_DIR/queue/draft_review_started/${cmd}.draft_review.started"
        [ ! -f "$f" ] || printf 'draft_review_started\t%s\t%s\n' "$cmd" "$f" >> "$cand"
    done
    # lock は cmd 名から一意に導けないため 1 回だけ列挙して突合する
    if [ -d "$PROJECT_DIR/queue/locks" ]; then
        while IFS= read -r base; do
            cmd="${base#deploy_}"
            cmd="${cmd%.lock}"
            while [ -n "$cmd" ] && [ -z "${_qfr_reclaim[$cmd]:-}" ]; do
                case "$cmd" in *_*) cmd="${cmd%_*}" ;; *) cmd="" ;; esac
            done
            [ -n "$cmd" ] || continue
            f="$PROJECT_DIR/queue/locks/$base"
            _qfr_lock_is_free "$f" || continue   # 保持中lockは触らない
            printf 'locks\t%s\t%s\n' "$cmd" "$f" >> "$cand"
        done < <(find "$PROJECT_DIR/queue/locks" -maxdepth 1 -type f -name 'deploy_cmd_*.lock' -printf '%f\n' 2>/dev/null)
    fi

    local total_files total_bytes
    total_files=0; total_bytes=0
    if [ -s "$cand" ]; then
        local _p _cand_paths=()
        while IFS= read -r _p; do _cand_paths+=("$_p"); done < <(cut -f3 "$cand")
        total_files=$(find "${_cand_paths[@]}" -type f 2>/dev/null | wc -l)
        total_bytes=$(du -sb "${_cand_paths[@]}" 2>/dev/null | awk -F'\t' '{s+=$1} END {print s+0}')
    fi

    mkdir -p "$(dirname "$QUEUE_FLAG_RETENTION_REPORT")"
    {
        printf '# queue flag retention candidates\n'
        printf '# generated: %s\tmode: %s\tretention_days: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$QUEUE_FLAG_RETENTION_MODE" "$QUEUE_FLAG_RETENTION_DAYS"
        printf '# entries: %s\tfiles: %s\tbytes: %s\n' "$(wc -l < "$cand")" "$total_files" "$total_bytes"
        cat "$cand"
    } > "$QUEUE_FLAG_RETENTION_REPORT"

    echo "[flag-retention] mode=$QUEUE_FLAG_RETENTION_MODE days=$QUEUE_FLAG_RETENTION_DAYS entries=$(wc -l < "$cand") files=$total_files bytes=$total_bytes report=$QUEUE_FLAG_RETENTION_REPORT"

    [ -s "$cand" ] || return 0

    # (2) realpath 全件検証。1件でもqueue外なら何も動かさない
    local paths=()
    while IFS= read -r f; do paths+=("$f"); done < <(cut -f3 "$cand")
    _qfr_assert_under_queue "${paths[@]}" || return 1

    [ "$QUEUE_FLAG_RETENTION_MODE" = "quarantine" ] || return 0

    local stamp qroot rel dest moved
    stamp="$(date '+%Y%m%d_%H%M%S')"
    qroot="$QUEUE_FLAG_QUARANTINE_DIR/$stamp"
    moved=0
    while IFS=$'\t' read -r _kind _cmd f; do
        [ -e "$f" ] || continue
        rel="${f#"$PROJECT_DIR"/}"
        dest="$qroot/$rel"
        mkdir -p "$(dirname "$dest")"
        mv "$f" "$dest" && moved=$((moved + 1))
    done < "$cand"
    cp "$QUEUE_FLAG_RETENTION_REPORT" "$qroot/candidates.tsv" 2>/dev/null || true
    echo "[flag-retention] quarantined=$moved -> $qroot"
}

# テスト用: 関数定義だけ読み込んで本流を実行しない
if [ "${QUEUE_FLAG_RETENTION_LIB_ONLY:-0}" = "1" ]; then
    # shellcheck disable=SC2317  # sourceされない実行時のみ到達する
    return 0 2>/dev/null || exit 0
fi

archive_cmds
sync_stk_status_from_archive
trim_cmd_chronicle || true
trim_stk_old_entries
archive_reports
archive_karo_section

# ============================================================
# postcondition: archive_cmds結果の事後検証
# L074対策: 算術式は$((var+1))形式。postcondition失敗でもスクリプトを止めない。
# ============================================================
postcondition_archive() {
    local input=$_POSTCOND_COMPLETED
    local output=$_POSTCOND_ARCHIVED

    if [ "$input" -eq 0 ]; then
        echo "[archive] postcondition: OK (no completed cmds)"
        return 0
    fi

    if [ "$output" -eq 0 ]; then
        echo "[archive] ALERT: completed存在するがアーカイブ0件 (expected=$input actual=0)" >&2
        bash "$PROJECT_DIR/scripts/ntfy_batch.sh" "[archive] INFO: completed存在するがアーカイブ0件 (expected=${input} actual=0)" || true
        return 0
    fi

    if [ "$output" -lt "$input" ]; then
        echo "[archive] WARN: アーカイブ不完全 (expected=$input actual=$output)" >&2
        return 0
    fi

    echo "[archive] postcondition: OK (archived=$output/$input)"
}
postcondition_archive || true

# queue flag retention（既定=quarantine, 24h throttle。失敗してもarchive本流を止めない）
prune_queue_flag_retention || echo "[flag-retention] WARN: 回収処理をスキップした" >&2

archive_dashboard

# cmd_579: 会話保持はJSONL専用 `scripts/conversation_retention.sh` に移管。
# archive_completed.sh から旧YAMLローテーションは撤去する。

# Remove the deploy-owned remote-tip worktree only after the terminal archive
# path has completed. The marker is the durable owner identity; no marker means
# this is a legacy task and there is nothing to clean up.
cleanup_task_worktree_marker() {
    local marker="$PROJECT_DIR/queue/gates/${CMD_ID}/task_worktree.json"
    [ -f "$marker" ] || return 0
    local meta repo worktree state
    meta=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); assert d.get("version")==1 and d.get("parent_cmd")==sys.argv[2] and d.get("state") in {"active","cleaning","cleaned"}; print("{}\t{}\t{}".format(d.get("repo", ""), d.get("worktree", ""), d.get("state", "")))' "$marker" "$CMD_ID" 2>/dev/null) \
        || { echo "[archive] BLOCK: invalid task worktree marker for ${CMD_ID}" >&2; return 1; }
    IFS=$'\t' read -r repo worktree state <<< "$meta"
    [ "$state" = "cleaned" ] && return 0
    [ -n "$repo" ] && [ -n "$worktree" ] || return 1
    [ "${ARCHIVE_REQUIRE_CLEAR_RECEIPT:-0}" = "1" ] || {
        echo "[archive] BLOCK: task worktree cleanup requires CLEAR receipt" >&2; return 1;
    }
    local published_commit
    published_commit=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1],encoding="utf-8")).get("published_commit") or ""))' "$marker")
    if [ -z "$published_commit" ]; then
        recover_task_worktree_published_commit "$marker" "$CMD_ID" "$repo" || {
            echo "[archive] BLOCK: published commit receipt missing, mismatched, or unresolved" >&2
            return 1
        }
        published_commit=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1],encoding="utf-8")).get("published_commit") or ""))' "$marker")
    fi
    [[ "$published_commit" =~ ^[0-9a-f]{40}$ ]] && git -C "$repo" cat-file -e "${published_commit}^{commit}" 2>/dev/null || {
        echo "[archive] BLOCK: published commit receipt missing or unresolved" >&2; return 1;
    }
    preserve_task_worktree_tracked_runtime_artifacts "$worktree" || return 1
    if [ -n "$(git -C "$worktree" status --porcelain 2>/dev/null)" ]; then
        echo "[archive] BLOCK: task worktree dirty; retaining path=$worktree" >&2; return 1
    fi
    preserve_task_worktree_ignored_artifacts "$worktree" || return 1
    git -C "$repo" worktree remove "$worktree" 2>"$TMP/worktree-remove.stderr" || {
        sed -n '1,5p' "$TMP/worktree-remove.stderr" >&2
        echo "[archive] BLOCK: task worktree cleanup failed path=$worktree" >&2; return 1;
    }
    if git -C "$repo" worktree list --porcelain | grep -Fqx "worktree $worktree"; then
        echo "[archive] BLOCK: orphan task worktree remains path=$worktree" >&2; return 1
    fi
    python3 -c 'import json,os,sys,tempfile,time; p=sys.argv[1]; d=json.load(open(p,encoding="utf-8")); d["state"]="cleaned"; d["cleaned_at_ns"]=time.time_ns(); fd,t=tempfile.mkstemp(prefix=".task_worktree_cleaned.",dir=os.path.dirname(p)); f=os.fdopen(fd,"w",encoding="utf-8"); json.dump(d,f,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno()); f.close(); os.replace(t,p)' "$marker"
    echo "[archive] task worktree cleanup: OK path=$worktree"
}

# archive.doneフラグ出力（CMD_ID指定時のみ）
if [ -n "$CMD_ID" ]; then
    mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"
    _clear_marker="$PROJECT_DIR/queue/gates/${CMD_ID}/gate_worker.clear.json"
    if [ "${ARCHIVE_REQUIRE_CLEAR_RECEIPT:-0}" = "1" ] && ! python3 - "$_clear_marker" "$CMD_ID" "${SHOGUN_COMPLETION_GENERATION:-}" <<'PY'
import json
import re
import sys

path, expected_cmd, expected_generation = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError, TypeError):
    raise SystemExit(1)
if not isinstance(data, dict) or data.get("version") != 1 or data.get("state") != "clear":
    raise SystemExit(1)
if data.get("cmd_id") != expected_cmd:
    raise SystemExit(1)
generation = str(data.get("completion_generation") or "")
if not re.fullmatch(r"[0-9a-f]{64}", generation):
    raise SystemExit(1)
if expected_generation and generation != expected_generation:
    raise SystemExit(1)
try:
    if int(data.get("persisted_at_ns")) <= 0:
        raise SystemExit(1)
except (TypeError, ValueError):
    raise SystemExit(1)
PY
    then
        echo "[archive] BLOCK: durable gate CLEAR receipt missing or invalid for ${CMD_ID}" >&2
        exit 1
    fi
    cleanup_task_worktree_marker || exit 1
    _archive_event_id="completion-finalize-archive-${CMD_ID}-${SHOGUN_COMPLETION_GENERATION}"
    defense_overhead_write completion_finalize archive 0 PASS "$_archive_event_id" \
        "{\"cmd_id\":\"${CMD_ID}\",\"generation\":\"${SHOGUN_COMPLETION_GENERATION}\"}" \
        || _archive_writer_rc=$?
    if [ "${_archive_writer_rc:-0}" -ne 0 ]; then
        if [ "$_archive_writer_rc" -eq 3 ]; then
            echo "[archive] WARN: completion telemetry unavailable (rc=3); material archive succeeded, continuing marker publication" >&2
        elif [ "$_archive_writer_rc" -ne 4 ]; then
            echo "ERROR: archive completion event write failed (rc=${_archive_writer_rc})" >&2
            exit 1
        fi
    fi
    touch "$TMP/archive.done"
    mv "$TMP/archive.done" "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"
    echo "[archive_completed] gate flag: queue/gates/${CMD_ID}/archive.done"
fi

echo "[archive_completed] done"
