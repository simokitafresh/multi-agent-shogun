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
import re
import subprocess
import sys
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

try:
    with open(report_file, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    report = {}

commit_hash = str(report.get("commit_hash") or "").strip()
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
