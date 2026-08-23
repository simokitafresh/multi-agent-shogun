#!/usr/bin/env bash
# semantic-links: [[防御階層原則(Level 1-6)]]
# ============================================================
# gate_context_freshness.sh
# dashboardと同じ監視対象に対してソースcommit差分ベースで鮮度を自動チェックする
#
# Usage:
#   bash scripts/gates/gate_context_freshness.sh
#
# チェック内容:
#   scripts/context_freshness_check.sh --dashboard-warnings と同じ対象
#   （直近completed cmdがあるactive projectのcontext）のみを監視する
#   各context/*.mdの先頭コメントから last_updated を解析し、ソースrepoの非auto commit有無を確認
#   フォーマット: <!-- last_updated: YYYY-MM-DD --> または
#                <!-- last_updated: YYYY-MM-DD cmd_XXX ... -->
#   ソースrepoにlast_updated後の新commitあり → ALERT
#     last_updated未記載 → WARN（「未記載」と明示）
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

_self="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_self%/*}"
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR%/scripts/gates}"
CONTROL_ROOT="$SCRIPT_DIR"
ROOT_DIR="${CONTEXT_FRESHNESS_ROOT:-$SCRIPT_DIR}"
source "$CONTROL_ROOT/scripts/lib/yaml_field_set.sh"
CHECK_SCRIPT="${CONTEXT_FRESHNESS_CHECK_SCRIPT:-$ROOT_DIR/scripts/context_freshness_check.sh}"
NTFY_SCRIPT="${CONTEXT_FRESHNESS_NTFY_SCRIPT:-$ROOT_DIR/scripts/ntfy.sh}"
BULLETIN_SCRIPT="${CONTEXT_FRESHNESS_BULLETIN_SCRIPT:-$CONTROL_ROOT/scripts/bulletin_write.sh}"
TODAY_OVERRIDE="${CONTEXT_FRESHNESS_TODAY:-}"
CACHE_TTL="${CONTEXT_FRESHNESS_GATE_CACHE_TTL:-300}"
ALERT_DEBOUNCE_SECONDS="${CONTEXT_FRESHNESS_ALERT_DEBOUNCE_SECONDS:-86400}"
ALERT_STATE_DIR="${CONTEXT_FRESHNESS_ALERT_STATE_DIR:-/tmp/gate_context_freshness_alerts}"
BULLETIN_STATE_DIR="${CONTEXT_FRESHNESS_BULLETIN_STATE_DIR:-$ALERT_STATE_DIR/bulletin}"
# GA-245: 旧既定1秒は、このリポジトリの実行環境(9pマウント/mnt/c)でのgit log
# 実測所要時間(集約後でも1回あたり3〜8秒、不安定域は6秒以下で実証)を大幅に
# 下回っており、対象のほぼ全件がtimeoutする根本原因だった。context_freshness_check.sh
# 側のgit呼出し集約(GA-245)と組み合わせ、実測に安全マージンを載せた値へ適正化する。
# 単純延長ではなく、それでも取得失敗した場合はfail-closedでALERT(exit 1)遮断する
# (check_failed_paths分岐、GA-245で WARN→ALERT に格上げ済み)。
# GA-292: snapshot producerのgit history走査は同じ9p上の履歴I/Oを使い、B0候補で
# 絶対時間326秒を実測した。旧30秒をproducerにも転送すると4 grouped query全てが
# timeoutし、内容が新鮮でも判定不能BLOCKになった。360秒は実測上限+10%余裕の
# bounded budgetであり、consumerはsnapshot hitならgit subprocess 0件のまま。
GIT_TIMEOUT="${CONTEXT_FRESHNESS_GATE_GIT_TIMEOUT:-360}"

HAS_ALERT=0
HAS_BLOCK=0
HAS_WARN=0
ALERT_LIST=()
STALE_TEMPLATE_ROWS=()

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "  action: $action"
}

sanitize_cmd_slug() {
    local value="$1"
    value="${value#context/}"
    value="${value%.md}"
    value="${value//\//_}"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]+/_/g; s/_+/_/g; s/^_//; s/_$//')"
    if [[ -z "$value" ]]; then
        value="context"
    fi
    printf '%s' "$value"
}

record_stale_template_candidate() {
    local rel_path="$1"
    local days_ago="$2"
    local last_updated="$3"
    local sort_days
    if [[ "$days_ago" =~ ^[0-9]+$ ]]; then
        sort_days="$days_ago"
    else
        sort_days=99999
    fi
    STALE_TEMPLATE_ROWS+=("${sort_days}"$'\t'"${rel_path}"$'\t'"${days_ago}"$'\t'"${last_updated}")
}

source_commit_action() {
    local rel_path="$1"
    local alert_line="$2"
    local latest_hash=""
    if [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]]; then
        latest_hash="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$latest_hash" ]]; then
        printf '%s' "一次差分を照合後、bash scripts/context_source_commit_set.sh ${rel_path} ${latest_hash} '<reason>' '<evidence>' で検出済み境界を記録せよ。last_updatedだけの更新は禁止。"
    else
        printf '%s' "${rel_path} をソースPJの最新commitと照合し、必要なら内容とsource_commitをscripts/context_source_commit_set.shで更新せよ。last_updatedだけの更新は禁止。"
    fi
}

context_commit_closes_source_alert() {
    local rel_path="$1"
    local alert_line="$2"
    local file="$ROOT_DIR/$rel_path"
    local latest_hash="" source_hash="" context_hash=""

    [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] || return 1
    latest_hash="${BASH_REMATCH[1]}"
    source_hash="$(
        head -n 5 "$file" 2>/dev/null \
            | sed -nE 's/.*source_commit:([0-9a-f]{7,40}).*/\1/p' \
            | head -n 1
    )"
    [[ -n "$source_hash" ]] || return 1
    git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    context_hash="$(git -C "$ROOT_DIR" log -1 --format=%H -- "$rel_path" 2>/dev/null || true)"
    [[ "$context_hash" =~ ^[0-9a-f]{40}$ ]] || return 1

    # A context-writing commit is machine-checkable reflection evidence. Close
    # only candidates in its ancestry; newer/rewritten history remains stale.
    git -C "$ROOT_DIR" merge-base --is-ancestor "$source_hash" "$context_hash" 2>/dev/null \
        && git -C "$ROOT_DIR" merge-base --is-ancestor "$latest_hash" "$context_hash" 2>/dev/null
}

# GA-493: a revert (or a divergent branch with the same effective source
# content) is still newer than the recorded source marker, but it does not
# require a second knowledge edit.  Compare the registered trigger paths
# against every recorded boundary before turning the checker snapshot into a
# raw ALERT.  The boundary still needs to advance, so the caller routes the
# equivalent result through the existing machine-readable doc-lane consumer.
source_commit_is_equivalent_to_recorded_boundary() {
    local rel_path="$1" alert_line="$2"
    local file="$ROOT_DIR/$rel_path" repo="" latest_hash="" trigger="" marker=""
    local trigger_item cited_dir cited_file
    local -a pathspecs=()
    local -a markers=()

    [[ "$rel_path" == context/*.md && -f "$file" && -r "$file" ]] || return 1
    [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] || return 1
    latest_hash="${BASH_REMATCH[1]}"
    [[ "$alert_line" =~ repo=([^[:space:]]+) ]] || return 1
    repo="${BASH_REMATCH[1]}"
    [[ -d "$repo" ]] || return 1
    git -C "$repo" cat-file -e "${latest_hash}^{commit}" 2>/dev/null || return 1
    [[ "$alert_line" =~ update_trigger=([^[:space:]]+) ]] || return 1
    trigger="${BASH_REMATCH[1]}"

    while IFS= read -r marker; do
        [[ "$marker" =~ ^[0-9a-f]{7,40}$ ]] && markers+=("$marker")
    done < <(head -n 10 "$file" | sed -nE 's/.*source_commit:([0-9a-f]{7,40}).*/\1/p')
    ((${#markers[@]} > 0)) || return 1

    IFS='|' read -r -a trigger_items <<< "$trigger"
    for trigger_item in "${trigger_items[@]}"; do
        [[ -n "$trigger_item" ]] || continue
        if [[ "$trigger_item" == cited:* ]]; then
            cited_dir="${trigger_item#cited:}"
            while IFS= read -r cited_file; do
                [[ -n "$cited_file" ]] && pathspecs+=("$cited_file")
            done < <(grep -oE "\`${cited_dir}/[^\`[:space:]]+\`" "$file" 2>/dev/null | tr -d '`' | sort -u)
        else
            pathspecs+=("$trigger_item")
        fi
    done
    ((${#pathspecs[@]} > 0)) || return 1

    for marker in "${markers[@]}"; do
        git -C "$repo" cat-file -e "${marker}^{commit}" 2>/dev/null || continue
        if git -C "$repo" diff --quiet "$marker" "$latest_hash" -- "${pathspecs[@]}" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# GA-425: DM-Signal docs/research commits are already forced through
# dm_signal_research_reflux_guard.sh before commit.  That guard records the
# exact staged path/status/blob fingerprint in dm-signal-research.md, but the
# generic source_commit ancestry check above cannot consume it because the
# source hash belongs to the external DM-Signal repository.  Recompute the
# latest alerted commit's canonical fingerprint and accept it only when the
# persisted guard receipt matches byte-for-byte.  A later unreviewed commit has
# a different fingerprint and therefore remains actionable.
reflux_receipt_closes_source_alert() {
    local rel_path="$1" alert_line="$2"
    local file="$ROOT_DIR/$rel_path" repo="" latest_hash="" recorded="" actual=""

    [[ "$rel_path" == "context/dm-signal-research.md" ]] || return 1
    [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] || return 1
    latest_hash="${BASH_REMATCH[1]}"
    [[ "$alert_line" =~ repo=([^[:space:]]+) ]] || return 1
    repo="${BASH_REMATCH[1]}"
    [[ -d "$repo" ]] || return 1
    git -C "$repo" cat-file -e "${latest_hash}^{commit}" 2>/dev/null || return 1

    # Receipts accumulate because every scoped docs/research commit records its
    # own immutable fingerprint.  Checking only the first receipt makes every
    # later correctly reviewed commit look stale (GA-428).  Retain the exact
    # equality boundary, but compare the source commit against the full set.
    recorded="$(sed -n 's/.*dm_signal_research_reflux: fingerprint=\([0-9a-f]\{64\}\);.*/\1/p' "$file")"
    [[ -n "$recorded" ]] || return 1
    actual="$(python3 - "$repo" "$latest_hash" <<'PY'
import hashlib
import subprocess
import sys

repo, commit = sys.argv[1:]
raw = subprocess.run(
    ["git", "-C", repo, "diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "-z", commit, "--", "docs/research"],
    check=True, capture_output=True,
).stdout.decode("utf-8", "surrogateescape").split("\0")
entries = []
i = 0
while i < len(raw) and raw[i]:
    status = raw[i]
    path = raw[i + 1]
    i += 2
    # Rename/copy records contain old and new paths.  The staged guard uses
    # diff --name-only plus the destination's name-status prefix.
    if status.startswith(("R", "C")):
        path = raw[i]
        i += 1
    blob_result = subprocess.run(
        ["git", "-C", repo, "rev-parse", f"{commit}:{path}"],
        capture_output=True, text=True,
    )
    blob = blob_result.stdout.strip() if blob_result.returncode == 0 else "DELETED"
    entries.append(f"{status}\t{path}\t{blob}")
if entries:
    canonical = "\n".join(sorted(entries, key=lambda row: row.split("\t", 1)[1])) + "\n"
    print(hashlib.sha256(canonical.encode("utf-8", "surrogateescape")).hexdigest())
PY
)" || return 1
    [[ -n "$actual" ]] && grep -Fqx -- "$actual" <<<"$recorded"
}

# GA-427/475: source commits do not all pass through the research-only reflux
# guard. Their review evidence already exists in terminal reports + the gunshi
# review ledger, but the dashboard gate previously ignored it for infra
# root-fallback contexts (and after report archival), emitting the same ALERT
# until somebody copied the source hash into context. Consume only an exact,
# terminal PASS report whose parent command also has an APPROVE review. This is
# an automatic update *request* receipt, not a content reflection claim: later
# commits and unreviewed commits remain stale.
approved_report_requests_context_update() {
    local rel_path="$1" alert_line="$2"
    local latest_hash="" repo=""

    [[ "$rel_path" == context/*.md ]] || return 1
    [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] || return 1
    latest_hash="${BASH_REMATCH[1]}"
    [[ "$alert_line" =~ repo=([^[:space:]]+) ]] || return 1
    repo="${BASH_REMATCH[1]}"

    python3 - "$ROOT_DIR" "$repo" "$latest_hash" <<'PY'
import glob
import os
import re
import subprocess
import sys

import yaml

root, repo, wanted = sys.argv[1:]
try:
    wanted = subprocess.run(
        ["git", "-C", repo, "rev-parse", wanted],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
except (OSError, subprocess.CalledProcessError):
    raise SystemExit(1)
if len(wanted) != 40:
    raise SystemExit(1)

approved = set()
review_log = os.path.join(root, "logs", "gunshi_review_log.yaml")
try:
    reviews = yaml.safe_load(open(review_log, encoding="utf-8")) or []
except (OSError, yaml.YAMLError):
    reviews = []
if isinstance(reviews, dict):
    reviews = reviews.get("reviews", reviews.get("entries", []))
for row in reviews if isinstance(reviews, list) else []:
    if not isinstance(row, dict):
        continue
    verdict = str(row.get("verdict", row.get("result", ""))).upper()
    if verdict in {"APPROVE", "APPROVED", "PASS"}:
        approved.add(str(row.get("cmd_id", row.get("parent_cmd", ""))))

try:
    subject = subprocess.run(
        ["git", "-C", repo, "show", "-s", "--format=%s", wanted],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
except (OSError, subprocess.CalledProcessError):
    raise SystemExit(1)

source_cmds = set(re.findall(r"\bcmd_[A-Za-z0-9_]+\b", subject))
candidate_cmds = set(source_cmds)
for cmd in tuple(source_cmds):
    for suffix in ("_full", "_normal"):
        if cmd.endswith(suffix):
            candidate_cmds.add(cmd[:-len(suffix)])

report_paths = set()
for report_dir in ("queue/reports", "queue/archive/reports"):
    for cmd in candidate_cmds:
        report_paths.update(glob.glob(os.path.join(root, report_dir, f"*{cmd}*.yaml")))
if not report_paths:
    # Keep compatibility with legacy/nonstandard report filenames only when
    # the source subject has no command identity to narrow the search.
    report_paths.update(glob.glob(os.path.join(root, "queue", "reports", "*_report_*.yaml")))
    report_paths.update(glob.glob(os.path.join(root, "queue", "archive", "reports", "*_report_*.yaml")))

def same_command(source_cmd, parent_cmd):
    if source_cmd == parent_cmd:
        return True
    for suffix in ("_full", "_normal"):
        if source_cmd == parent_cmd + suffix or parent_cmd == source_cmd + suffix:
            return True
    return False

for path in report_paths:
    try:
        report = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        continue
    if not isinstance(report, dict):
        continue
    if report.get("status") not in {"completed", "done"} or report.get("verdict") != "PASS":
        continue
    if str(report.get("parent_cmd", "")) not in approved:
        continue
    parent_cmd = str(report.get("parent_cmd", ""))
    hashes = {str(report.get("commit_hash", ""))}
    hashes.update(
        str(row.get("commit_hash", ""))
        for row in report.get("cross_repo_commits", [])
        if isinstance(row, dict) and os.path.realpath(str(row.get("repo", ""))) == os.path.realpath(repo)
    )
    if wanted in hashes or any(same_command(cmd, parent_cmd) for cmd in source_cmds):
        print(parent_cmd)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

# GA-314: source更新を解消する際、索引本文が参照するrepo相対リンクの欠落を
# source_commit更新だけで隠してはならない。鮮度ALERT対象に限って参照を検査し、
# 欠落が1件でもあれば後段でBLOCKへ倒す。
missing_context_links() {
    local context_file="$1" rel_path="$2" token candidate reference_root found
    local -a reference_roots=("$ROOT_DIR")

    # Context indexes intentionally link both to this control-plane repository
    # and to project repositories.  A single project root therefore cannot be
    # the resolution SSOT: GA-314 replaced ROOT_DIR with the dm-signal root and
    # made every control-plane link in dm-signal contexts a false missing link.
    # Resolve against every registered project root and fail only when none
    # contains the referenced path.
    while IFS= read -r reference_root; do
        [[ -n "$reference_root" && "$reference_root" != "$ROOT_DIR" ]] \
            && reference_roots+=("$reference_root")
    done < <(python3 - "$ROOT_DIR"/projects/*.yaml <<'PY'
import sys, yaml
seen = set()
for filename in sys.argv[1:]:
    try:
        data = yaml.safe_load(open(filename)) or {}
    except (OSError, yaml.YAMLError):
        continue
    path = str((data.get("project") or {}).get("path", "")).strip()
    if path and path not in seen:
        seen.add(path)
        print(path)
PY
)

    while IFS= read -r token; do
        candidate="${token#\`}"
        candidate="${candidate%\`}"
        [[ "$candidate" == docs/* || "$candidate" == context/* ]] || continue
        candidate="${candidate%% *}"
        candidate="${candidate%%#*}"
        found=0
        for reference_root in "${reference_roots[@]}"; do
            if compgen -G "$reference_root/$candidate" >/dev/null; then
                found=1
                break
            fi
        done
        (( found == 1 )) || printf '%s\n' "$candidate"
    done < <(grep -oE '`(docs|context)/[^`]+`' "$context_file" 2>/dev/null || true) \
        | sort -u
}

emit_update_cmd_templates() {
    [[ "${#STALE_TEMPLATE_ROWS[@]}" -gt 0 ]] || return 0

    local today cmd_date
    if [[ -n "$TODAY_OVERRIDE" ]]; then
        today="$TODAY_OVERRIDE"
    else
        today="$(date +%F)"
    fi
    cmd_date="${today//-/}"

    echo "--- 更新cmdテンプレート 全件 (${#STALE_TEMPLATE_ROWS[@]}件) ---"
    printf '%s\n' "${STALE_TEMPLATE_ROWS[@]}" \
        | sort -t $'\t' -k1,1nr \
        | while IFS=$'\t' read -r _sort_days rel_path days_ago last_updated; do
            local slug project_id last_note owner trigger route alert_line
            slug="$(sanitize_cmd_slug "$rel_path")"
            project_id="infra"
            if [[ "$rel_path" == context/dm-signal* ]]; then
                project_id="dm-signal"
            fi
            route="shogun-doc-lane"
            owner="unassigned"
            trigger=""
            alert_line="${source_alerts[$rel_path]:-}"
            if [[ "$alert_line" =~ owner=([^[:space:]]+) ]]; then
                owner="${BASH_REMATCH[1]}"
            fi
            if [[ "$alert_line" =~ update_trigger=([^[:space:]]+) ]]; then
                trigger="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$last_updated" ]]; then
                last_note="last_updated=${last_updated}, ${days_ago}日前"
            else
                last_note="last_updated未記載"
            fi
            cat <<EOF
- id: cmd_ctx_${slug}_${cmd_date}
  purpose: "${rel_path} の鮮度ALERTを解消し、一次データで内容とsource_commit境界を更新する"
  project: ${project_id}
  owner: ${owner}
  route: ${route}
  update_trigger: "${trigger}"
  acceptance_criteria:
    - "AC1: ${rel_path} を一次データと照合し、古い記述を更新または不要なら根拠付きで維持判断する"
    - "AC2: scripts/context_source_commit_set.shで${rel_path}のsource_commitを検証済み最新hashへ更新し、reason/evidenceを記録する。last_updatedだけの更新は禁止"
    - "AC3: bash scripts/gates/gate_context_freshness.sh をcache無効で再実行し、${rel_path} の未解消source commit=0件かつALERT=0件を確認する"
  not_in_scope: "対象ファイル以外の知識整理・設計変更"
  unresolved_decisions: "none"
  command: "${rel_path} の知識鮮度とsource_commit境界を更新。担当=${owner}、起票レーン=${route}、trigger=${trigger}。現状: ${last_note}。境界未更新なら完了せずBLOCKする"
EOF
        done
}

notify_context_alert() {
    local alert_summary="$1"
    local now
    now="${CONTEXT_FRESHNESS_ALERT_NOW:-$(date +%s)}"

    if ! [[ "$ALERT_DEBOUNCE_SECONDS" =~ ^[0-9]+$ ]]; then
        ALERT_DEBOUNCE_SECONDS=3600
    fi

    local alert_hash state_file last_epoch elapsed
    alert_hash="$(printf '%s' "$alert_summary" | sha256sum | awk '{print $1}')"
    mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true
    state_file="$ALERT_STATE_DIR/${alert_hash}.last"

    if [[ -f "$state_file" ]]; then
        last_epoch="$(head -n 1 "$state_file" 2>/dev/null || true)"
        if [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
            elapsed=$((now - last_epoch))
            if (( elapsed >= 0 && elapsed < ALERT_DEBOUNCE_SECONDS )); then
                echo "[gate_context_freshness] ntfy skip: same ALERT sent ${elapsed}s ago (<${ALERT_DEBOUNCE_SECONDS}s): ${alert_summary}" >&2
                return 0
            fi
        fi
    fi

    if bash "$NTFY_SCRIPT" "【将軍】context鮮度ALERT: ${alert_summary}" >/dev/null 2>&1; then
        printf '%s\n' "$now" > "$state_file" 2>/dev/null || true
        echo "[gate_context_freshness] ntfy sent: ${alert_summary}" >&2
    else
        echo "[gate_context_freshness] ntfy failed: ${alert_summary}" >&2
    fi
}

raw_context_alert_is_stale_after_recheck() {
    local rel_path="$1"
    local alert_line="$2"
    local file="$ROOT_DIR/$rel_path"
    local alert_cutoff="" metadata_date="" line="" line_count=0
    local cutoff_epoch metadata_epoch

    # The checker output is a snapshot. Re-read the target immediately before
    # the durable side effect so a context update racing with the checker
    # cannot produce a stale doc-lane notification.
    [[ "$alert_line" =~ last_updated=([0-9]{4}-[0-9]{2}-[0-9]{2}) ]] || return 1
    alert_cutoff="${BASH_REMATCH[1]}"
    [[ -f "$file" && -r "$file" ]] || return 1

    while IFS= read -r line && (( line_count < 10 )); do
        line_count=$((line_count + 1))
        if [[ "$line" =~ last_updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            metadata_date="${BASH_REMATCH[1]}"
            break
        fi
    done < "$file"

    # Missing or malformed dates retain the existing fail-closed notification
    # contract: inability to prove staleness must not suppress an ALERT.
    [[ -n "$metadata_date" ]] || return 1
    cutoff_epoch="$(date -d "$alert_cutoff" +%s 2>/dev/null)" || return 1
    metadata_epoch="$(date -d "$metadata_date" +%s 2>/dev/null)" || return 1

    if (( metadata_epoch > cutoff_epoch )); then
        echo "[gate_context_freshness] raw ALERT stale after metadata recheck; notification dropped: ${rel_path} (metadata=${metadata_date}, cutoff=${alert_cutoff})" >&2
        return 0
    fi
    return 1
}

notify_raw_context_alert() {
    local rel_path="$1"
    local alert_line="$2"
    local content alert_hash state_file state_tmp

    if raw_context_alert_is_stale_after_recheck "$rel_path" "$alert_line"; then
        return 0
    fi

    content="DOC_LANE_ALERT: context=${rel_path} raw_alert=${alert_line}"
    alert_hash="$(printf '%s' "$content" | sha256sum | awk '{print $1}')"
    state_file="$BULLETIN_STATE_DIR/${alert_hash}.sent"

    if [[ -f "$state_file" ]]; then
        echo "[gate_context_freshness] bulletin skip: same raw ALERT already persisted: ${rel_path}" >&2
        return 0
    fi

    # This caller invokes bulletin_write.sh through bash, so the required
    # capability is a readable regular file rather than the executable bit.
    if [[ ! -f "$BULLETIN_SCRIPT" || ! -r "$BULLETIN_SCRIPT" ]]; then
        emit_actionable \
            "BLOCK: ${rel_path} (raw ALERTのdoc-lane永続通知scriptなし)" \
            "bulletin_write.shを復旧し、raw ALERTを将軍doc laneへ永続化してから再実行せよ。"
        return 1
    fi

    if ! mkdir -p "$BULLETIN_STATE_DIR" 2>/dev/null; then
        emit_actionable \
            "BLOCK: ${rel_path} (raw ALERTのdoc-lane state領域を作成できない)" \
            "BULLETIN_STATE_DIR=${BULLETIN_STATE_DIR} の書込み権限を復旧して再実行せよ。"
        return 1
    fi

    if ! BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" \
            gate_context_freshness "$content" false action_required >/dev/null 2>&1; then
        emit_actionable \
            "BLOCK: ${rel_path} (raw ALERTのdoc-lane永続通知に失敗)" \
            "bulletin_write.shの失敗を解消し、将軍doc laneへのraw ALERT永続通知を再実行せよ。"
        return 1
    fi

    # Persist the dedupe marker only after bulletin_write has returned success.
    # A failed notification must remain retryable on the next gate invocation.
    state_tmp="${state_file}.$$"
    if ! printf '%s\n' "$content" > "$state_tmp" || ! mv "$state_tmp" "$state_file"; then
        emit_actionable \
            "BLOCK: ${rel_path} (raw ALERT通知成功後のdedupe state保存に失敗)" \
            "BULLETIN_STATE_DIR=${BULLETIN_STATE_DIR} のatomic書込みを復旧して再実行せよ。"
        return 1
    fi
    echo "[gate_context_freshness] bulletin persisted: ${rel_path}" >&2
    return 0
}

# GA-492/L1610: CONTEXT_UPDATE_REQUEST is a machine-readable producer output.
# Keep the durable doc-lane handoff in the same normal gate flow so a request
# cannot be printed successfully while having zero consumers.  The caller
# supplies the exact line that was emitted; parsing and validating that line
# also prevents a partial request from being routed as if it were complete.
consume_context_update_request() {
    local request_line="$1"
    local project="" context="" source_commit="" parent_cmd="" reason=""

    [[ "$request_line" =~ ^CONTEXT_UPDATE_REQUEST[[:space:]]+project=([^[:space:]]+)[[:space:]]+context=([^[:space:]]+)[[:space:]]+source_commit=([0-9a-f]{7,40})[[:space:]]+parent_cmd=([^[:space:]]+)[[:space:]]+reason=([^[:space:]]+)$ ]] || {
        emit_actionable \
            "BLOCK: context update request (machine-readable request malformed)" \
            "CONTEXT_UPDATE_REQUESTのproject/context/source_commit/parent_cmd/reasonを完全な値で再生成せよ。"
        return 1
    }
    project="${BASH_REMATCH[1]}"
    context="${BASH_REMATCH[2]}"
    source_commit="${BASH_REMATCH[3]}"
    parent_cmd="${BASH_REMATCH[4]}"
    reason="${BASH_REMATCH[5]}"

    [[ -f "$BULLETIN_SCRIPT" && -r "$BULLETIN_SCRIPT" ]] || {
        emit_actionable \
            "BLOCK: ${context} (CONTEXT_UPDATE_REQUEST consumer unavailable)" \
            "bulletin_write.shを復旧し、将軍doc laneへの構造化context更新要求を再実行せよ。"
        return 1
    }

    local payload
    payload="DOC_LANE_REQUEST: ${request_line} owner_route=shogun-doc-lane"
    if ! BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" \
            gate_context_freshness "$payload" false action_required >/dev/null 2>&1; then
        emit_actionable \
            "BLOCK: ${context} (CONTEXT_UPDATE_REQUEST consumer failed)" \
            "bulletin_write.shの失敗を解消し、source_commit=${source_commit} parent_cmd=${parent_cmd} の要求を再実行せよ。"
        return 1
    fi

    # Keep these assignments explicit: shellcheck/static audits can verify
    # that every validated request field reaches the consumer payload.
    : "$project" "$context" "$source_commit" "$parent_cmd" "$reason"
    return 0
}

TODAY_EPOCH=""

today_epoch() {
    [[ -n "$TODAY_EPOCH" ]] && return 0
    if [[ -n "$TODAY_OVERRIDE" ]]; then
        TODAY_EPOCH=$(date -d "$TODAY_OVERRIDE" +%s 2>/dev/null) || {
            echo "WARN: CONTEXT_FRESHNESS_TODAY の日付形式不正: $TODAY_OVERRIDE"
            echo "  action: YYYY-MM-DD 形式に修正せよ。"
            exit 2
        }
    else
        TODAY_EPOCH=$(date +%s)
    fi
}

if [[ ! -f "$CHECK_SCRIPT" ]]; then
    echo "WARN: context_freshness_check.sh not found"
    echo "  action: scripts/context_freshness_check.sh を復旧せよ。"
    exit 2
fi

warnings_output() {
    local cache_file=""
    if [[ "${CONTEXT_FRESHNESS_GATE_DISABLE_CACHE:-0}" != "1" && "$CACHE_TTL" =~ ^[0-9]+$ && "$CACHE_TTL" -gt 0 ]]; then
        local root_key
        root_key="${ROOT_DIR//[^A-Za-z0-9._-]/_}"
        local today_key="${TODAY_OVERRIDE:-today}"
        local stale_key="${CONTEXT_STALE_DAYS:-7}"
        local sig_parts=()
        local path
        for path in \
            "$CHECK_SCRIPT" \
            "$ROOT_DIR/config/projects.yaml" \
            "$ROOT_DIR/context/cmd-chronicle.md" \
            "$ROOT_DIR/queue/archive/cmds"
        do
            if [[ -e "$path" ]]; then
                sig_parts+=("$(stat -c '%n:%y:%s' "$path" 2>/dev/null || printf 'missing')")
            else
                sig_parts+=("missing")
            fi
        done
        while IFS= read -r path_signature; do
            sig_parts+=("$path_signature")
        done < <(find "$ROOT_DIR/context" -maxdepth 1 -type f -name '*.md' \
            -printf '%p:%T@:%s\n' 2>/dev/null | sort)
        sig_parts+=("git_timeout=${GIT_TIMEOUT}")
        local sig sig_hash
        sig="$(printf '%s|' "${sig_parts[@]}")"
        sig_hash="$(printf '%s' "$sig" | sha256sum | awk '{print $1}')"
        cache_file="/tmp/gate_context_freshness_${root_key}_${today_key}_${stale_key}_${sig_hash}.cache"
        local now cache_mtime
        now="$(date +%s)"
        if [[ -f "$cache_file" ]]; then
            cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || printf 0)"
            if (( now - cache_mtime < CACHE_TTL )); then
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    # One source commit after the context's recorded source_commit is enough to
    # make the context stale.  A threshold greater than one lets an ALERT
    # disappear when commits are later merged/squashed even though the context
    # itself was never refreshed (GA-226).
    local _min_sc="${CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS:-1}"
    if [[ -n "$cache_file" ]]; then
        local tmp_cache="${cache_file}.$$"
        # The gate timeout is a total per-attempt budget, not merely the first
        # attempt.  Without forwarding the retry budget the checker falls back
        # to 60s, so e.g. GIT_TIMEOUT=1 can still block for 61s (GA-283).
        # A gate decision cannot consume an asynchronously-produced snapshot on
        # its first run.  Rebuild a cache miss within this bounded gate budget so
        # a new source tip is checked now instead of emitting one false BLOCK and
        # only becoming usable on the next invocation (GA-301).
        CFC_OUTPUT_CACHE_TTL=0 CFC_HISTORY_REFRESH_SYNC=1 CFC_GIT_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_RETRY_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_MAX_WORKERS="${CONTEXT_FRESHNESS_GATE_GIT_MAX_WORKERS:-4}" \
            CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS="$_min_sc" \
            bash "$CHECK_SCRIPT" --dashboard-warnings > "$tmp_cache" 2>/dev/null
        mv "$tmp_cache" "$cache_file"
        cat "$cache_file"
    else
        CFC_OUTPUT_CACHE_TTL=0 CFC_HISTORY_REFRESH_SYNC=1 CFC_GIT_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_RETRY_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_MAX_WORKERS="${CONTEXT_FRESHNESS_GATE_GIT_MAX_WORKERS:-4}" \
            CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS="$_min_sc" \
            bash "$CHECK_SCRIPT" --dashboard-warnings 2>/dev/null
    fi
}

declare -A seen_paths=()
declare -A source_alerts=()
# GA-238: git log呼出しがtimeout/returncode異常でsource commit数を確定できなかった
# ("source commit check failed", context_freshness_check.shのbuild_source_check_warning)
# rel_pathを記録する。source_alertsが空のままdays_ago<=7だと従来はOK扱いへ落ちて
# 未確認状態を隠蔽していた(fail-open) — check_failed_pathsに載ったrel_pathは
# 後段の分類で必ずWARNへ倒す(fail-closed)。
declare -A check_failed_paths=()
target_rel_paths=()
while IFS= read -r warning_line; do
    [[ -n "$warning_line" ]] || continue
    rel_path=""
    if [[ "$warning_line" =~ ^(WARN|ALERT):[[:space:]]([^[:space:]]+) ]]; then
        rel_path="${BASH_REMATCH[2]}"
    fi
    [[ -n "$rel_path" ]] || continue
    if [[ "$warning_line" == ALERT:*"source commits"* ]]; then
        source_alerts["$rel_path"]="$warning_line"
    elif [[ "$warning_line" == WARN:*"source commit check failed"* ]]; then
        check_failed_paths["$rel_path"]=1
    fi
    if [[ -n "${seen_paths[$rel_path]:-}" ]]; then
        continue
    fi
    seen_paths["$rel_path"]=1
    target_rel_paths+=("$rel_path")
done < <(
    warnings_output
)

if [[ "${#target_rel_paths[@]}" -eq 0 ]]; then
    echo "--- 総合判定: OK ---"
    exit 0
fi

# The checker is allowed to emit paths in repository-dependent order.  Sort
# the deduped target set before any doc-lane side effect so repeated runs have
# a stable notification order.
if [[ "${#target_rel_paths[@]}" -gt 1 ]]; then
    mapfile -t target_rel_paths < <(printf '%s\n' "${target_rel_paths[@]}" | sort -u)
fi

for rel_path in "${target_rel_paths[@]}"; do
    file="$ROOT_DIR/$rel_path"
    [[ -f "$file" ]] || continue

    basename_file=$(basename "$file")
    last_updated=""
    line_count=0
    while IFS= read -r line && (( line_count < 10 )); do
        line_count=$((line_count + 1))
        if [[ "$line" =~ last_updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            last_updated="${BASH_REMATCH[1]}"
            break
        fi
    done < "$file"

    if [[ -z "$last_updated" ]]; then
        if active_context_defer_allowed "$ROOT_DIR" "$rel_path" >/dev/null 2>&1; then
            echo "DEFER: ${basename_file} (active ownerによるcontext再構築中)"
            continue
        fi
        emit_actionable \
            "WARN: ${basename_file} (last_updated 未記載)" \
            "${basename_file} に <!-- last_updated: YYYY-MM-DD --> を追記せよ。"
        HAS_WARN=1
        continue
    fi

    file_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || {
        emit_actionable \
            "WARN: ${basename_file} (last_updated日付パース失敗: ${last_updated})" \
            "${basename_file} の last_updated 日付形式を YYYY-MM-DD に修正せよ。"
        HAS_WARN=1
        continue
    }
    today_epoch

    days_ago=$(( (TODAY_EPOCH - file_epoch) / 86400 ))
    record_stale_template_candidate "$rel_path" "$days_ago" "$last_updated"

    if [[ -n "${source_alerts[$rel_path]:-}" ]]; then
        if context_commit_closes_source_alert "$rel_path" "${source_alerts[$rel_path]}" \
            || reflux_receipt_closes_source_alert "$rel_path" "${source_alerts[$rel_path]}"; then
            context_hash="$(git -C "$ROOT_DIR" log -1 --format=%h -- "$rel_path" 2>/dev/null || true)"
            echo "OK: ${basename_file} (${days_ago}日前更新、context commit ${context_hash} が検出済みsource候補を包含)"
            continue
        elif source_commit_is_equivalent_to_recorded_boundary "$rel_path" "${source_alerts[$rel_path]}"; then
            latest_hash=""
            [[ "${source_alerts[$rel_path]}" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] \
                && latest_hash="${BASH_REMATCH[1]}"
            request_project="infra"
            [[ "$rel_path" == context/dm-signal*.md ]] && request_project="dm-signal"
            request_line="CONTEXT_UPDATE_REQUEST project=${request_project} context=${rel_path} source_commit=${latest_hash} parent_cmd=source_${latest_hash} reason=source_equivalent"
            printf '%s\n' "$request_line"
            # An equivalent source tree still has a new durable boundary.  Do
            # not silently suppress it: route the exact setter input through
            # the existing consumer so the next doc-lane action advances the
            # marker and leaves a receipt.
            if ! consume_context_update_request "$request_line"; then
                HAS_BLOCK=1
                continue
            fi
            echo "OK: ${basename_file} (source commitは登録boundaryと内容同値、boundary更新要求をdoc laneへ永続通知)"
            continue
        elif request_cmd="$(approved_report_requests_context_update "$rel_path" "${source_alerts[$rel_path]}")"; then
            latest_hash=""
            [[ "${source_alerts[$rel_path]}" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]] \
                && latest_hash="${BASH_REMATCH[1]}"
            request_project="infra"
            [[ "$rel_path" == context/dm-signal*.md ]] && request_project="dm-signal"
            request_line="CONTEXT_UPDATE_REQUEST project=${request_project} context=${rel_path} source_commit=${latest_hash} parent_cmd=${request_cmd} reason=approved_source_commit"
            printf '%s\n' "$request_line"
            # GA-492: stdout is now paired with an explicit durable consumer.
            # A failed handoff is BLOCK, never a silent OK.
            if ! consume_context_update_request "$request_line"; then
                HAS_BLOCK=1
                continue
            fi
            echo "OK: ${basename_file} (承認済みsource commitのcontext更新要求を将軍doc laneへ永続通知)"
            continue
        fi
        missing_links="$(missing_context_links "$file" "$rel_path")"
        if [[ -n "$missing_links" ]]; then
            emit_actionable \
                "BLOCK: ${basename_file} (source更新あり・参照リンク欠落)" \
                "欠落参照を復旧してから内容とsource_commitを更新せよ: $(printf '%s' "$missing_links" | paste -sd, -)"
            HAS_BLOCK=1
            continue
        fi
        emit_actionable \
            "ALERT: ${basename_file} (source commits since last_updated=${last_updated})" \
            "$(source_commit_action "$rel_path" "${source_alerts[$rel_path]}")"
        if ! notify_raw_context_alert "$rel_path" "${source_alerts[$rel_path]}"; then
            HAS_BLOCK=1
        fi
        HAS_ALERT=1
        ALERT_LIST+=("${basename_file}(source更新)")
    elif [[ -n "${check_failed_paths[$rel_path]:-}" ]]; then
        # A timeout means freshness is unknown, not stale. Keep it fail-closed
        # while distinguishing detector failure (BLOCK) from a verified source
        # change (ALERT), so operators cannot "fix" it by touching timestamps.
        emit_actionable \
            "BLOCK: ${basename_file} (source commit確認失敗: timeout/returncode。last_updated=${last_updated}, ${days_ago}日前、鮮度判定不能)" \
            "${basename_file} のsource commit確認がgit timeout/returncode異常で失敗した。個別文書のlast_updatedは変更せず、検査環境を復旧して再実行せよ。"
        HAS_BLOCK=1
    elif [[ "$days_ago" -gt 14 ]]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新、ソース変更なし)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    elif [[ "$days_ago" -gt 7 ]]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    else
        echo "OK: ${basename_file} (${days_ago}日前更新)"
    fi
done

if [[ "$HAS_ALERT" -gt 0 && "${#ALERT_LIST[@]}" -gt 0 && -f "$NTFY_SCRIPT" ]]; then
    alert_summary=$(IFS=', '; echo "${ALERT_LIST[*]}")
    notify_context_alert "$alert_summary"
fi

if [[ "$HAS_ALERT" -gt 0 ]]; then
    emit_update_cmd_templates
fi

if [[ "$HAS_BLOCK" -gt 0 ]]; then
    echo "--- 総合判定: BLOCK ---"
    exit 1
elif [[ "$HAS_ALERT" -gt 0 ]]; then
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [[ "$HAS_WARN" -gt 0 ]]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
