#!/usr/bin/env bash
# Fingerprint-bound two-phase review approval storage.

# A single approval transition asks for the same report fingerprint up to three
# times (record, two-phase readiness, manifest). Command substitutions execute
# functions in subshells, so an associative array would not survive between
# those calls. Use an invocation-scoped cache directory inherited by subshells.
# The content hash is also the fingerprint's first component: any byte change
# selects a new entry without relying on coarse mtime/size metadata.
if [ -z "${REVIEW_FP_CACHE_DIR:-}" ] || [ "${REVIEW_FP_CACHE_OWNER_PID:-}" != "$BASHPID" ]; then
    REVIEW_FP_CACHE_DIR="${TMPDIR:-/tmp}/review_fp_cache_${BASHPID}_$RANDOM"
    REVIEW_FP_CACHE_OWNER_PID="$BASHPID"
    export REVIEW_FP_CACHE_DIR REVIEW_FP_CACHE_OWNER_PID
fi
mkdir -p "$REVIEW_FP_CACHE_DIR"

review_report_fingerprint() {
    local report="$1" content_hash raw_hash commit_identity root cache_key cache_file
    [ -f "$report" ] || return 1
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    # Compute a normalized content hash that excludes non-content metadata fields
    # (commit_hash, cross_repo_commits, lifecycle timestamps, etc.) so that
    # post-approval corrections to these fields do not invalidate the approval.
    # verdict, binary_checks, result, ac_evidence_mapping, and all review-payload
    # fields are intentionally kept — changes to them continue to invalidate approval.
    content_hash=$(python3 - "$report" <<'PY'
import hashlib, json, sys, yaml

# Non-content metadata fields that may be amended after approval without
# changing the review-relevant payload (AC results, binary_checks, verdict).
_NON_CONTENT = frozenset({
    "commit_hash", "cross_repo_commits", "commit", "git_commit",
    "status", "timestamp", "submitted_at", "completed_at", "done_at",
    "updated_at", "acknowledged_at",
})

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
for key in _NON_CONTENT:
    data.pop(key, None)
result = data.get("result")
if isinstance(result, dict):
    result.pop("commit_hash", None)
payload = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
PY
    ) || return 1
    # Path is part of the identity boundary: no-code eligibility can depend on
    # whether files_modified names this exact report. Keep path+content in the
    # key so identical bytes at different paths never share a decision.
    raw_hash=$(sha256sum "$report" | awk '{print $1}') || return 1
    cache_key=$(printf '%s:%s:%s' "$(realpath "$report")" "$content_hash" "$raw_hash" | sha256sum | awk '{print $1}')
    cache_file="$REVIEW_FP_CACHE_DIR/$cache_key"
    if [ -s "$cache_file" ]; then
        head -n 1 "$cache_file"
        return 0
    fi
    # Validate that a commit identity is determinable (fail-closed gate).
    # The identity value is NOT included in the fingerprint so that correcting
    # commit_hash / cross_repo_commits after approval does not invalidate it.
    # No-code reports ("no-code-change") satisfy the gate through their structural
    # contract (binary_checks / files_modified), which is part of content_hash.
    commit_identity=$(python3 - "$report" "$root" <<'PY'
import pathlib, sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
report_path = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()
sys.path.insert(0, str(root / "scripts" / "lib"))
from report_commit_identity import permits_no_code_identity
commit_hash = ""
for key in ("commit_hash", "commit", "git_commit"):
    value = d.get(key)
    if isinstance(value, str) and value.strip():
        commit_hash = value.strip()
        break
if not commit_hash:
    result = d.get("result") or {}
    commit_hash = result.get("commit_hash", "") if isinstance(result, dict) else ""

no_code_task_types = ("scout", "recon", "recon2")
task_type = str(d.get("task_type", "")).strip().lower()
if task_type not in no_code_task_types:
    parent_cmd = str(d.get("parent_cmd", "")).strip()
    for task_path in (root / "queue" / "tasks").glob("*.yaml"):
        try:
            task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
            task = task_doc.get("task", task_doc)
        except (OSError, yaml.YAMLError):
            continue
        if isinstance(task, dict) and str(task.get("parent_cmd", "")).strip() == parent_cmd:
            task_type = str(task.get("task_type", task.get("type", task.get("scope_mode", "")))).strip().lower()
            if task_type in no_code_task_types:
                break
files_modified = d.get("files_modified")
checks = d.get("binary_checks") or {}
commit_claimed = False
no_commit_asserted = False
if isinstance(checks, dict):
    for item in checks.get("commit", []) if isinstance(checks.get("commit", []), list) else []:
        check_text = str(item.get("check", "")).strip().lower() if isinstance(item, dict) else ""
        no_commit_assertion = any(marker in check_text for marker in (
            "実行していない", "commit禁止", "commit不要", "no-commit", "no commit",
        ))
        result_yes = item.get("result") is True or str(item.get("result", "")).strip().lower() == "yes" if isinstance(item, dict) else False
        no_commit_asserted = no_commit_asserted or (no_commit_assertion and result_yes)
        if isinstance(item, dict) and not no_commit_assertion and (
            item.get("result") is True
            or str(item.get("result", "")).strip().lower() == "yes"
        ):
            # cmd_karo_hotfix_no_code_identity_20260727: ここで break すると、テンプレートが
            # 固定する第1要素(『git commitが完了したか』result=yes)で打ち切られ、
            # 2件目以降の『[commit不要]』宣言が一度も評価されず no_commit_asserted が False の
            # まま残る(才蔵の報告で実証: marker はbc[1]に在るのに検出されなかった)。
            # 全要素を走査してから判定する。commit_claimed の扱いは下の override が担う。
            commit_claimed = True

# No-code reports have no commit to bind.  Their explicit structural contract is
# part of content_hash, while every report outside this narrow case stays fail-closed.
def reported_path(item):
    value = item.get("path", "") if isinstance(item, dict) else item
    if not isinstance(value, str) or not value.strip():
        return None
    path = pathlib.Path(value)
    return (root / path).resolve() if not path.is_absolute() else path.resolve()

no_code_files = files_modified == [] or (
    isinstance(files_modified, list)
    and bool(files_modified)
    and all(reported_path(item) == report_path for item in files_modified)
)

# Operational queue/log mutations are intentionally uncommitted runtime data.
# Binding their review to the repository HEAD attributes an unrelated agent's
# concurrent commit to this task.  Keep the allowance narrow and explicit:
# every reported path must stay under queue/ or logs/, and the report must
# affirm that no commit is required.  Any source/config/docs path falls back to
# the normal 40-hex implementation identity.
operational_runtime_files = permits_no_code_identity(d, root)
# cmd_karo_hotfix_no_code_identity_20260727: binary_checks.commit の第1要素は報告テンプレートが
# 『git commitが完了したか(untracked/modified=0)』result=yes で固定し、忍者側から書き換えられない
# (report_field_set が保護する)。この定型文が commit_claimed を立てるため、tree_unchanged の
# 積で no-code を証明済みの報告まで no-code経路へ到達できず、報告側の是正では解けない
# deadlock になっていた(才蔵/疾風の2件で実証)。permits_no_code_identity は
# tree_unchanged+before==after(40hex)+[commit不要]宣言+operational_files_only の積であり、
# 定型文より強い証拠なので、40hex identity が無い場合はこちらを優先する。
_valid_hex_identity = (
    isinstance(commit_hash, str)
    and len(commit_hash) == 40
    and all(c in "0123456789abcdef" for c in commit_hash)
)
if operational_runtime_files and not _valid_hex_identity:
    print("no-code-change")
    raise SystemExit(0)

# Legacy scout/recon reports may identify no-code work through their task type
# or explicit commit check.  Operational reports do not use this second
# contract: permits_no_code_identity above is their single structural SSOT.
if no_code_files and not commit_claimed and (
    task_type in no_code_task_types or no_commit_asserted
):
    print("no-code-change")
    raise SystemExit(0)

if isinstance(commit_hash, str) and len(commit_hash) == 40 and all(c in "0123456789abcdef" for c in commit_hash):
    print(commit_hash)
    raise SystemExit(0)

raise SystemExit(1)
PY
) || commit_identity=""
    # cmd_karo_impl_b28_failed_report_close_20260726 (B28):
    # commit identity gate は「レビューを実在の成果物へ束縛する」ためのものだが、
    # verdict=FAIL の報告は成果物が無い/不完全なまま終端することがある。FAILを
    # FAILとして閉じる経路にまでこの gate を課すと、閉じられない報告が永久に残る
    # (才蔵 cmd_karo_ci_fix_30161415740 で実証)。家老のFAIL closeに限り免除する。
    # 免除は review_approval.sh の fail_close 判定(status=failed かつ verdict=FAIL
    # かつ karo:ACCEPT)からのみ有効化される。
    if [ -z "$commit_identity" ]; then
        [ "${REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT:-0}" = 1 ] || return 1
    fi
    # The fingerprint is the normalized content hash alone.  commit_identity is
    # used only as a gate (see above) and intentionally excluded from the value
    # so that correcting commit_hash / cross_repo_commits after approval does
    # not require a new review cycle.
    # One report identity == one cache entry (line 1 = fingerprint, line 2 = the
    # gate's decided commit identity).  The identity is kept in the SAME file
    # rather than a sidecar so the cache boundary stays "1 entry per (path,
    # content)" and a single atomic mv publishes both values together.
    printf '%s\n%s\n' "$content_hash" "$commit_identity" > "$cache_file.tmp.$BASHPID"
    mv -f "$cache_file.tmp.$BASHPID" "$cache_file"
    head -n 1 "$cache_file"
}

# Commit identity of a report as decided by the fingerprint gate:
# "no-code-change" for structurally no-code reports, otherwise the 40-hex
# implementation commit.  Empty output means no identity was determinable
# (only reachable under REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT=1).
review_report_commit_identity() {
    local report="$1" content_hash raw_hash cache_key cache_file
    content_hash=$(review_report_fingerprint "$report") || return 1
    raw_hash=$(sha256sum "$report" | awk '{print $1}') || return 1
    cache_key=$(printf '%s:%s:%s' "$(realpath "$report")" "$content_hash" "$raw_hash" | sha256sum | awk '{print $1}')
    cache_file="$REVIEW_FP_CACHE_DIR/$cache_key"
    [ -f "$cache_file" ] || return 1
    sed -n '2p' "$cache_file"
}

# RC on a report-only task must require a substantive report correction, not an
# unrelated HEAD change.  Exclude lifecycle/commit identity fields that change
# during resubmission and hash the review payload itself.
review_report_payload_hash() {
    local report="$1"
    [ -f "$report" ] || return 1
    python3 - "$report" <<'PY'
import hashlib
import json
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
for key in (
    "status", "commit_hash", "commit", "git_commit", "timestamp",
    "submitted_at", "completed_at", "done_at", "updated_at",
):
    data.pop(key, None)
result = data.get("result")
if isinstance(result, dict):
    result.pop("commit_hash", None)
payload = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
PY
}

review_report_key() {
    local report="$1"
    printf '%s' "$report" | sha256sum | awk '{print $1}'
}

review_report_logical_path() {
    local report="$1" root resolved base
    root=$(realpath "${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}") || return 1
    resolved=$(realpath "$report") || return 1
    base=$(basename "$report")
    [[ "$resolved" == "$root/queue/reports/$base" \
        || "$resolved" == "$root/queue/archive/reports/$base" ]] || return 1
    printf 'queue/reports/%s\n' "$base"
}

review_validate_cmd_id() { [[ "$1" =~ ^cmd_[A-Za-z0-9_]+$ || "$1" =~ ^campaign_lane_[A-Za-z0-9._-]+$ ]]; }

# Resolve the terminal report set from report-owned identity.  Task YAML is a
# volatile deployment slot and may already contain a later generation when a
# completion resumes.  Both live and flat archive reports are accepted, while
# duplicate basenames/report_ids, nested archives, and symlinks fail closed.
review_resolve_reports() {
    local cmd_id="$1" root
    root=$(realpath "${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}") || return 1
    review_validate_cmd_id "$cmd_id" || return 1
    python3 - "$root" "$cmd_id" <<'PY'
import pathlib, re, sys, yaml
root, cmd_id = pathlib.Path(sys.argv[1]).resolve(), sys.argv[2]
reports_dir = root / "queue" / "reports"
archive_dir = root / "queue" / "archive" / "reports"
found, basenames, report_ids = [], set(), set()
live_names = set()
for task_path in sorted((root / "queue" / "tasks").glob("*.yaml")):
    try:
        task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        continue
    task = task_doc.get("task", task_doc)
    if not isinstance(task, dict) or str(task.get("parent_cmd") or "") != cmd_id:
        continue
    filename = str(task.get("report_filename") or "").strip()
    live_names.add(filename or f"{task_path.stem}_report_{cmd_id}.yaml")
candidates = list(reports_dir.glob("*.yaml")) + list(archive_dir.glob("*.yaml"))
# A matching nested archive is an invalid ambiguous storage location, not a
# candidate to silently ignore.
candidates += list(archive_dir.glob("**/*.yaml"))
# The shared archive contains reports for every command.  Select by the
# basename-owned command token before touching the path or payload so a broken
# report belonging to another command cannot poison this command's recovery.
# The boundary after cmd_id prevents cmd_42 from claiming cmd_4200.
cmd_name = re.compile(r"_report_" + re.escape(cmd_id) + r"(?:_[^/]*)?\.yaml\Z")
candidates = [path for path in candidates if cmd_name.search(path.name)]
seen_paths = set()
for report_path in sorted(candidates):
    if report_path in seen_paths:
        continue
    seen_paths.add(report_path)
    # Authenticate the storage boundary before reading attacker-controlled
    # content.  In particular, a symlink carrying another command's payload
    # must not escape validation through the parent_cmd mismatch branch.
    if report_path.is_symlink() or report_path.parent not in (reports_dir, archive_dir):
        raise SystemExit(1)
    resolved = report_path.resolve()
    if resolved.parent not in (reports_dir.resolve(), archive_dir.resolve()):
        raise SystemExit(1)
    try:
        doc = yaml.safe_load(report_path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        raise SystemExit(1)
    if not isinstance(doc, dict) or str(doc.get("parent_cmd") or "") != cmd_id:
        continue
    is_live = report_path.parent == reports_dir
    if is_live and report_path.name not in live_names:
        continue
    report_id = str(doc.get("report_id") or "").strip()
    # Active legacy reports remain task-bound for compatibility.  Archived
    # reports have no task slot to authenticate them and therefore require a
    # durable report_id of their own.
    if (not report_id and not is_live) or report_path.name in basenames or (report_id and report_id in report_ids):
        raise SystemExit(1)
    basenames.add(report_path.name)
    if report_id:
        report_ids.add(report_id)
    found.append(str(report_path))
for report in sorted(found, key=lambda p: pathlib.Path(p).name):
    print(report)
PY
}

review_validate_campaign_shard() {
    local cmd_id="$1" report="$2" root item_id
    root=$(realpath "${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}") || return 1
    [[ "$cmd_id" =~ ^campaign_lane_(.+)$ ]] || return 1
    item_id="${BASH_REMATCH[1]}"
    python3 - "$root" "$item_id" "$report" <<'PY'
import json, pathlib, sys, yaml
root, item_id, report_path = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3]).resolve()
report = yaml.safe_load(report_path.read_text(encoding="utf-8")) or {}
matches = []
for manifest_path in (root / "queue" / "campaign_lane").glob("*/manifest.yaml"):
    manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8")) or {}
    for item in manifest.get("items") or []:
        if isinstance(item, dict) and str(item.get("id")) == item_id:
            state_dir = pathlib.Path(str(manifest.get("state_dir") or ""))
            if not state_dir.is_absolute():
                state_dir = root / state_dir
            result_path = state_dir / "shards" / item_id / "output_dir" / "result.json"
            try:
                result = json.loads(result_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if str(result.get("commit_sha")) == str(report.get("commit_hash")):
                matches.append((item, result))
if len(matches) != 1:
    raise SystemExit(1)
item, result = matches[0]
contract = str(item.get("contract_fingerprint") or "")
if len(contract) != 64 or any(c not in "0123456789abcdef" for c in contract):
    raise SystemExit(1)
if result.get("status") != "success" or int(result.get("fail_count", -1)) != 0 or int(result.get("skip_count", -1)) != 0:
    raise SystemExit(1)
if str(result.get("item_id")) != item_id or str(result.get("commit_sha")) != str(report.get("commit_hash")):
    raise SystemExit(1)
if str(report.get("parent_contract_fingerprint") or contract) != contract:
    raise SystemExit(1)
if str(report.get("parent_cmd") or "") not in ("", "campaign_lane_" + item_id):
    raise SystemExit(1)
PY
}

review_validate_report() {
    local cmd_id="$1" report="$2" root reports_dir archive_dir resolved parent base
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_cmd_id "$cmd_id" || return 1
    reports_dir=$(realpath "$root/queue/reports") || return 1
    archive_dir=$(realpath -m "$root/queue/archive/reports") || return 1
    resolved=$(realpath "$report") || return 1
    base=$(basename "$report")
    [ ! -L "$report" ] || return 1
    [[ "$resolved" == "$reports_dir/$base" || "$resolved" == "$archive_dir/$base" ]] || return 1
    parent=$(python3 - "$resolved" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
print(d.get('parent_cmd', ''))
PY
)
    if [[ "$cmd_id" =~ ^campaign_lane_ ]]; then
        review_validate_campaign_shard "$cmd_id" "$resolved"
    else
        [ "$parent" = "$cmd_id" ]
    fi
}

review_approval_value() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    awk -F': ' -v key="$key" '$1 == key {sub(/^[^:]*: /, ""); print; exit}' "$file"
}

review_two_phase_ready() {
    local cmd_id="$1" report="$2" root dir key logical fingerprint gunshi_fp gunshi_result karo_fp karo_result
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_report "$cmd_id" "$report" || return 1
    logical=$(PROJECT_ROOT="$root" review_report_logical_path "$report") || return 1
    key=$(review_report_key "$logical")
    dir="$root/queue/gates/${cmd_id}/review_approvals/reports/$key"
    fingerprint=$(review_report_fingerprint "$report") || return 1
    gunshi_fp=$(review_approval_value "$dir/gunshi.yaml" fingerprint || true)
    gunshi_result=$(review_approval_value "$dir/gunshi.yaml" result || true)
    karo_fp=$(review_approval_value "$dir/karo.yaml" fingerprint || true)
    karo_result=$(review_approval_value "$dir/karo.yaml" result || true)
    [ "$gunshi_result" = "LGTM" ] && [ "$karo_result" = "ACCEPT" ] && [ "$gunshi_fp" = "$fingerprint" ] && [ "$karo_fp" = "$fingerprint" ]
}

review_two_phase_ready_gunshi() {
    local cmd_id="$1" report="$2" root key dir logical fingerprint stored result
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_report "$cmd_id" "$report" || return 1
    fingerprint=$(review_report_fingerprint "$report") || return 1
    logical=$(PROJECT_ROOT="$root" review_report_logical_path "$report") || return 1
    key=$(review_report_key "$logical")
    dir="$root/queue/gates/$cmd_id/review_approvals/reports/$key"
    stored=$(review_approval_value "$dir/gunshi.yaml" fingerprint || true)
    result=$(review_approval_value "$dir/gunshi.yaml" result || true)
    [ "$result" = LGTM ] && [ "$stored" = "$fingerprint" ]
}

review_all_reports_ready() {
    local cmd_id="$1"; shift
    [ "$#" -gt 0 ] || return 1
    local report
    for report in "$@"; do review_two_phase_ready "$cmd_id" "$report" || return 1; done
}

review_manifest_fingerprint() {
    local root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}" report fp
    [ "$#" -gt 0 ] || return 1
    for report in "$@"; do
        fp=$(review_report_fingerprint "$report") || return 1
        printf '%s:%s\n' "$(PROJECT_ROOT="$root" review_report_logical_path "$report")" "$fp"
    done | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

# Publish the terminal review decision as one immutable, per-report snapshot.
# The compact review_gate.done marker only points at this artifact by SHA256;
# therefore a crash can leave an unreferenced snapshot, but can never publish a
# partially-built decision.  Each row preserves both approvers' lineage before
# archive_completed consumes their live marker files.
review_terminal_snapshot_write() {
    local cmd_id="$1"; shift
    local root gate_dir snapshot tmp rows report logical resolved fp fp2 commit_id report_id key approvals report_fd pinned
    local gunshi_result gunshi_fp karo_result karo_fp
    root=$(realpath "${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}") || return 1
    [ "$#" -gt 0 ] || return 1
    gate_dir="$root/queue/gates/$cmd_id"
    snapshot="$gate_dir/terminal_review_manifest.json"
    rows=$(mktemp "$gate_dir/.terminal_review_rows.XXXXXX") || return 1
    tmp=$(mktemp "$gate_dir/.terminal_review_manifest.XXXXXX") || { rm -f "$rows"; return 1; }
    for report in "$@"; do
        logical=$(PROJECT_ROOT="$root" review_report_logical_path "$report") || { rm -f "$rows" "$tmp"; return 1; }
        resolved=$(realpath "$report") || { rm -f "$rows" "$tmp"; return 1; }
        [[ "$(dirname "$resolved")" == "$root/queue/reports" \
            || "$(dirname "$resolved")" == "$root/queue/archive/reports" ]] \
            || { rm -f "$rows" "$tmp"; return 1; }
        exec {report_fd}<"$report" || { rm -f "$rows" "$tmp"; return 1; }
        pinned="/proc/$BASHPID/fd/$report_fd"
        fp=$(review_report_fingerprint "$pinned") || { exec {report_fd}<&-; rm -f "$rows" "$tmp"; return 1; }
        commit_id=$(review_report_commit_identity "$pinned") || { exec {report_fd}<&-; rm -f "$rows" "$tmp"; return 1; }
        report_id=$(python3 - "$pinned" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(d.get("report_id") or ""))
PY
) || { rm -f "$rows" "$tmp"; return 1; }
        [ -n "$report_id" ] || { rm -f "$rows" "$tmp"; return 1; }
        key=$(review_report_key "$logical")
        approvals="$gate_dir/review_approvals/reports/$key"
        gunshi_result=$(review_approval_value "$approvals/gunshi.yaml" result || true)
        gunshi_fp=$(review_approval_value "$approvals/gunshi.yaml" fingerprint || true)
        karo_result=$(review_approval_value "$approvals/karo.yaml" result || true)
        karo_fp=$(review_approval_value "$approvals/karo.yaml" fingerprint || true)
        [ "$gunshi_result" = LGTM ] && [ "$karo_result" = ACCEPT ] \
            && [ "$gunshi_fp" = "$fp" ] && [ "$karo_fp" = "$fp" ] \
            || { rm -f "$rows" "$tmp"; return 1; }
        # A second read closes the content-change window between identity and
        # lineage collection.  Any concurrent rewrite aborts publication.
        fp2=$(review_report_fingerprint "$pinned") || { exec {report_fd}<&-; rm -f "$rows" "$tmp"; return 1; }
        [ "$fp" = "$fp2" ] || { exec {report_fd}<&-; rm -f "$rows" "$tmp"; return 1; }
        exec {report_fd}<&-
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$logical" "$report_id" "$fp" "$commit_id" \
            "$gunshi_result" "$gunshi_fp" "$karo_result:$karo_fp" >> "$rows"
    done
    python3 - "$cmd_id" "$rows" "$tmp" <<'PY'
import json, pathlib, sys
cmd_id, rows_path, output = sys.argv[1:]
reports = []
for line in pathlib.Path(rows_path).read_text(encoding="utf-8").splitlines():
    logical, report_id, content_sha, commit_id, gr, gf, karo = line.split("\t")
    kr, kf = karo.split(":", 1)
    reports.append({
        "logical_path": logical, "report_id": report_id,
        "content_sha": content_sha, "commit_identity": commit_id,
        "gunshi": {"result": gr, "fingerprint": gf},
        "karo": {"result": kr, "fingerprint": kf},
    })
reports.sort(key=lambda item: item["logical_path"])
doc = {"version": 1, "cmd_id": cmd_id, "reports": reports}
pathlib.Path(output).write_text(json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
    rm -f "$rows"
    mv -f "$tmp" "$snapshot"
    sha256sum "$snapshot" | awk '{print $1}'
}

# Formal approvals are intentionally consumed/archived after CLEAR.  A later
# cmd_complete_gate --force must still be able to revalidate the immutable
# reviewed artifact without demanding a second human review.  The marker is
# sufficient only when all of its structured fields and the current manifest
# match exactly; a stale/backfilled/placeholder marker remains fail-closed.
review_gate_manifest_ready() {
    local cmd_id="$1"; shift
    local root marker source result reports snapshot_rel snapshot snapshot_sha actual_sha rows report logical resolved fp fp2 commit_id report_id report_fd pinned
    root=$(realpath "${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}") || return 1
    marker="$root/queue/gates/$cmd_id/review_gate.done"
    [ -f "$marker" ] || return 1
    [ "$#" -gt 0 ] || return 1
    source=$(review_approval_value "$marker" source || true)
    result=$(review_approval_value "$marker" result || true)
    reports=$(review_approval_value "$marker" reports || true)
    snapshot_rel=$(review_approval_value "$marker" terminal_manifest || true)
    snapshot_sha=$(review_approval_value "$marker" terminal_manifest_sha || true)
    [ "$source" = "two_phase_review" ] || return 1
    [ "$result" = "LGTM" ] || return 1
    [ "$reports" = "$#" ] || return 1
    [ "$snapshot_rel" = "queue/gates/$cmd_id/terminal_review_manifest.json" ] || return 1
    snapshot="$root/$snapshot_rel"
    [ -f "$snapshot" ] || return 1
    [[ "$snapshot_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual_sha=$(sha256sum "$snapshot" | awk '{print $1}')
    [ "$snapshot_sha" = "$actual_sha" ] || return 1
    rows=$(mktemp) || return 1
    for report in "$@"; do
        logical=$(PROJECT_ROOT="$root" review_report_logical_path "$report") || { rm -f "$rows"; return 1; }
        resolved=$(realpath "$report") || { rm -f "$rows"; return 1; }
        [[ "$(dirname "$resolved")" == "$root/queue/reports" \
            || "$(dirname "$resolved")" == "$root/queue/archive/reports" ]] \
            || { rm -f "$rows"; return 1; }
        exec {report_fd}<"$report" || { rm -f "$rows"; return 1; }
        pinned="/proc/$BASHPID/fd/$report_fd"
        fp=$(review_report_fingerprint "$pinned") || { exec {report_fd}<&-; rm -f "$rows"; return 1; }
        commit_id=$(review_report_commit_identity "$pinned") || { exec {report_fd}<&-; rm -f "$rows"; return 1; }
        report_id=$(python3 - "$pinned" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(d.get("report_id") or ""))
PY
) || { rm -f "$rows"; return 1; }
        [ -n "$report_id" ] || { rm -f "$rows"; return 1; }
        fp2=$(review_report_fingerprint "$pinned") || { exec {report_fd}<&-; rm -f "$rows"; return 1; }
        [ "$fp" = "$fp2" ] || { exec {report_fd}<&-; rm -f "$rows"; return 1; }
        exec {report_fd}<&-
        printf '%s\t%s\t%s\t%s\n' "$logical" "$report_id" "$fp" "$commit_id" >> "$rows"
    done
    python3 - "$cmd_id" "$snapshot" "$rows" <<'PY'
import json, pathlib, sys
cmd_id, snapshot_path, rows_path = sys.argv[1:]
try:
    doc = json.loads(pathlib.Path(snapshot_path).read_text(encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
if doc.get("version") != 1 or doc.get("cmd_id") != cmd_id:
    raise SystemExit(1)
stored = doc.get("reports")
if not isinstance(stored, list):
    raise SystemExit(1)
current = {}
for line in pathlib.Path(rows_path).read_text(encoding="utf-8").splitlines():
    logical, report_id, content_sha, commit_id = line.split("\t")
    if logical in current:
        raise SystemExit(1)
    current[logical] = (report_id, content_sha, commit_id)
if len(stored) != len(current):
    raise SystemExit(1)
for item in stored:
    if not isinstance(item, dict) or set(item) != {"logical_path", "report_id", "content_sha", "commit_identity", "gunshi", "karo"}:
        raise SystemExit(1)
    logical = item["logical_path"]
    if current.get(logical) != (item["report_id"], item["content_sha"], item["commit_identity"]):
        raise SystemExit(1)
    gunshi, karo = item["gunshi"], item["karo"]
    if gunshi != {"result": "LGTM", "fingerprint": item["content_sha"]}:
        raise SystemExit(1)
    if karo != {"result": "ACCEPT", "fingerprint": item["content_sha"]}:
        raise SystemExit(1)
PY
    rc=$?
    rm -f "$rows"
    return "$rc"
}
