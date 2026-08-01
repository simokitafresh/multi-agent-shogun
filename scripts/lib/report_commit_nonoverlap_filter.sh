#!/bin/bash
# report_commit_nonoverlap_filter.sh — non-overlap dirty hunk判定（SSOT）
# cmd_karo_hotfix_shared_dirty_commit_gate_202607101643:
# cmd_complete_gate.sh専用だった判定をinbox_write.shのgit_uncommitted_gateとも
# 共有可能にするため独立関数として抽出（AC3）。
#
# 目的: 報告者が自分のtask変更をcommit済みでも、同一ファイル内に残る他忍者の
# 非重複(non-overlapping)WIP hunkだけでcommit漏れ扱いされ誤BLOCKされる問題を防ぐ。
# 報告者自身のcommit(commit_hash)が変更した行範囲(commit_ranges)と、現在dirtyな
# 行範囲(dirty_ranges)が重ならない場合のみ「他者の並行変更」とみなしBLOCK対象から
# 除外(suppress)する。重なる場合や比較材料が無い場合は従来通りBLOCK対象として残す(kept)。
#
# Usage: filter_report_commit_nonoverlap_uncommitted <repo_root> <report_file> <uncommitted_paths>
#   repo_root:         gitリポジトリのルートパス
#   report_file:       報告YAMLのパス（commit_hashフィールドを参照）
#   uncommitted_paths: 改行区切りのファイルパス一覧（repo_root相対、状態プレフィックス無し）
#   標準出力: BLOCK対象として残すパス一覧（改行区切り）
#   標準エラー: suppressしたパスのWARNログ
filter_report_commit_nonoverlap_uncommitted() {
    local repo_root="$1"
    local report_file="$2"
    local uncommitted_paths="$3"

    REPO_ROOT="$repo_root" REPORT_FILE="$report_file" UNCOMMITTED_PATHS="$uncommitted_paths" python3 - <<'PY'
import os
import json
import re
import subprocess
import sys
import time
from collections import Counter
import yaml

repo = os.environ.get("REPO_ROOT", "")
report_file = os.environ.get("REPORT_FILE", "")
paths = [p.strip().strip("./") for p in os.environ.get("UNCOMMITTED_PATHS", "").splitlines() if p.strip()]

def run_git(args):
    try:
        return subprocess.check_output(["git", "-C", repo, *args], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""

def hunk_ranges(diff_text):
    ranges = []
    for match in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff_text, re.M):
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count <= 0:
            continue
        ranges.append((start, start + count - 1))
    return ranges

def overlaps(left, right):
    return any(a <= d and c <= b for a, b in left for c, d in right)

SHARED_APPEND_ONLY_YAMLS = {"logs/gunshi_review_log.yaml"}
ALLOWED_AUXILIARY_FIELDS = {
    "gate_result",
    "gate_synced_at",
    "gate_checked_at",
    "gate_evidence",
}

def entry_owner(entry):
    if not isinstance(entry, dict):
        return ""
    return str(entry.get("cmd_id") or entry.get("parent_cmd") or "").strip()

def entry_identity(entry):
    """Return the stable identity of one review-log generation."""
    if not isinstance(entry, dict):
        return None
    owner = entry_owner(entry)
    review_type = str(entry.get("review_type") or "").strip()
    reviewed_at = str(entry.get("reviewed_at") or "").strip()
    if not owner or not review_type or not reviewed_at:
        return None
    return (
        owner,
        review_type,
        reviewed_at,
        str(entry.get("report_id") or ""),
    )

def mapping_has_only_allowed_auxiliary_additions(before, after):
    if not isinstance(before, dict) or not isinstance(after, dict):
        return False
    if any(key not in after or after[key] != value for key, value in before.items()):
        return False
    return set(after) - set(before) <= ALLOWED_AUXILIARY_FIELDS

def stable_file_text(path, attempts=3):
    """Read one stable snapshot; continuous writers fail closed after a bound."""
    full_path = os.path.join(repo, path)
    for _ in range(attempts):
        try:
            before = os.stat(full_path)
            with open(full_path, encoding="utf-8") as f:
                content = f.read()
            after = os.stat(full_path)
        except OSError:
            return None
        signature_before = (before.st_ino, before.st_size, before.st_mtime_ns)
        signature_after = (after.st_ino, after.st_size, after.st_mtime_ns)
        if signature_before != signature_after:
            continue
        time.sleep(0.01)
        try:
            confirm = os.stat(full_path)
        except OSError:
            return None
        signature_confirm = (confirm.st_ino, confirm.st_size, confirm.st_mtime_ns)
        if signature_after == signature_confirm:
            return content
    return None

def shared_yaml_owned_by_other(path, commit, parent_cmd):
    if path not in SHARED_APPEND_ONLY_YAMLS or not parent_cmd:
        return False
    before_text = run_git(["show", f"{commit}:{path}"])
    after_text = stable_file_text(path)
    if after_text is None:
        return False
    try:
        before = yaml.safe_load(before_text)
        after = yaml.safe_load(after_text)
    except Exception:
        return False
    if not isinstance(before, list) or not isinstance(after, list):
        return False

    # Identity must be unique and complete; ambiguity is fail-closed.
    before_by_id = {}
    after_by_id = {}
    legacy_before = Counter()
    legacy_after = Counter()
    for collection, index in ((before, before_by_id), (after, after_by_id)):
        for entry in collection:
            identity = entry_identity(entry)
            if identity is None:
                # Pre-existing legacy entries may lack the modern identity,
                # but they must remain byte-semantically unchanged in count.
                # Deterministic structural key without serializing operational
                # YAML back through a dumper (the repository bans dump-based
                # operational YAML rewrites at the pre-commit boundary).
                canonical = json.dumps(entry, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                (legacy_before if collection is before else legacy_after)[canonical] += 1
                continue
            if identity in index:
                return False
            index[identity] = entry
    if legacy_before != legacy_after:
        return False

    # No deletion or mutation. Additive auxiliary fields are allowed only on
    # entries owned by another command.
    for identity, old_entry in before_by_id.items():
        new_entry = after_by_id.get(identity)
        if new_entry is None:
            return False
        if new_entry != old_entry:
            if entry_owner(old_entry) == parent_cmd:
                return False
            if not mapping_has_only_allowed_auxiliary_additions(old_entry, new_entry):
                return False

    # Every complete new generation must have a known, non-self owner.
    for identity, new_entry in after_by_id.items():
        if identity not in before_by_id and entry_owner(new_entry) == parent_cmd:
            return False
    return True

try:
    with open(report_file, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    report = {}

commit_hash = str(report.get("commit_hash") or "").strip()
parent_cmd = str(report.get("parent_cmd") or "").strip()
if not re.fullmatch(r"[0-9a-f]{40}", commit_hash):
    print("\n".join(paths))
    raise SystemExit(0)

changed_files = set(run_git(["diff-tree", "--no-commit-id", "--name-only", "-r", commit_hash]).splitlines())
if not changed_files:
    print("\n".join(paths))
    raise SystemExit(0)

kept = []
suppressed = []
for path in paths:
    if path not in changed_files:
        kept.append(path)
        continue
    if path in SHARED_APPEND_ONLY_YAMLS:
        if shared_yaml_owned_by_other(path, commit_hash, parent_cmd):
            suppressed.append(path)
        else:
            kept.append(path)
        continue
    commit_ranges = hunk_ranges(run_git(["diff", "--unified=0", f"{commit_hash}^", commit_hash, "--", path]))
    dirty_ranges = hunk_ranges(run_git(["diff", "--unified=0", "--", path]) + "\n" + run_git(["diff", "--cached", "--unified=0", "--", path]))
    if commit_ranges and dirty_ranges and not overlaps(commit_ranges, dirty_ranges):
        suppressed.append(path)
    else:
        kept.append(path)

for path in suppressed:
    print(f"  [WARN] {path}: uncommitted non-overlapping diff after report commit_hash; treating as concurrent unrelated change", file=sys.stderr)
print("\n".join(kept))
PY
}
