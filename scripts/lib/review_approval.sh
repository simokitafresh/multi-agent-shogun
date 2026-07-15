#!/usr/bin/env bash
# Fingerprint-bound two-phase review approval storage.

review_report_fingerprint() {
    local report="$1" content_hash commit_identity root
    [ -f "$report" ] || return 1
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    content_hash=$(sha256sum "$report" | awk '{print $1}') || return 1
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
            commit_claimed = True
            break

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
if (no_code_files or operational_runtime_files) and not commit_claimed and (
    task_type in no_code_task_types or no_commit_asserted
):
    print("no-code-change")
    raise SystemExit(0)

if isinstance(commit_hash, str) and len(commit_hash) == 40 and all(c in "0123456789abcdef" for c in commit_hash):
    print(commit_hash)
    raise SystemExit(0)

raise SystemExit(1)
PY
) || return 1
    [ -n "$commit_identity" ] || return 1
    printf '%s:%s\n' "$content_hash" "$commit_identity"
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

review_validate_cmd_id() { [[ "$1" =~ ^cmd_[A-Za-z0-9_]+$ ]]; }

review_validate_report() {
    local cmd_id="$1" report="$2" root reports_dir resolved parent
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_cmd_id "$cmd_id" || return 1
    reports_dir=$(realpath "$root/queue/reports") || return 1
    resolved=$(realpath "$report") || return 1
    [[ "$resolved" == "$reports_dir/"* ]] || return 1
    [[ "$(dirname "$resolved")" == "$reports_dir" ]] || return 1
    parent=$(python3 - "$resolved" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
print(d.get('parent_cmd', ''))
PY
)
    [ "$parent" = "$cmd_id" ]
}

review_approval_value() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    awk -F': ' -v key="$key" '$1 == key {sub(/^[^:]*: /, ""); print; exit}' "$file"
}

review_two_phase_ready() {
    local cmd_id="$1" report="$2" root dir key fingerprint gunshi_fp gunshi_result karo_fp karo_result
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_report "$cmd_id" "$report" || return 1
    key=$(review_report_key "${report#"$root"/}")
    dir="$root/queue/gates/${cmd_id}/review_approvals/reports/$key"
    fingerprint=$(review_report_fingerprint "$report") || return 1
    gunshi_fp=$(review_approval_value "$dir/gunshi.yaml" fingerprint || true)
    gunshi_result=$(review_approval_value "$dir/gunshi.yaml" result || true)
    karo_fp=$(review_approval_value "$dir/karo.yaml" fingerprint || true)
    karo_result=$(review_approval_value "$dir/karo.yaml" result || true)
    [ "$gunshi_result" = "LGTM" ] && [ "$karo_result" = "ACCEPT" ] && [ "$gunshi_fp" = "$fingerprint" ] && [ "$karo_fp" = "$fingerprint" ]
}

review_two_phase_ready_gunshi() {
    local cmd_id="$1" report="$2" root key dir fingerprint stored result
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    review_validate_report "$cmd_id" "$report" || return 1
    fingerprint=$(review_report_fingerprint "$report") || return 1
    key=$(review_report_key "${report#"$root"/}")
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
        printf '%s:%s\n' "${report#"$root"/}" "$fp"
    done | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

# Formal approvals are intentionally consumed/archived after CLEAR.  A later
# cmd_complete_gate --force must still be able to revalidate the immutable
# reviewed artifact without demanding a second human review.  The marker is
# sufficient only when all of its structured fields and the current manifest
# match exactly; a stale/backfilled/placeholder marker remains fail-closed.
review_gate_manifest_ready() {
    local cmd_id="$1"; shift
    local root marker source result reports stored_manifest current_manifest
    root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    marker="$root/queue/gates/$cmd_id/review_gate.done"
    [ -f "$marker" ] || return 1
    [ "$#" -gt 0 ] || return 1
    source=$(review_approval_value "$marker" source || true)
    result=$(review_approval_value "$marker" result || true)
    reports=$(review_approval_value "$marker" reports || true)
    stored_manifest=$(review_approval_value "$marker" manifest || true)
    [ "$source" = "two_phase_review" ] || return 1
    [ "$result" = "LGTM" ] || return 1
    [ "$reports" = "$#" ] || return 1
    [ -n "$stored_manifest" ] || return 1
    current_manifest=$(review_manifest_fingerprint "$@") || return 1
    [ "$stored_manifest" = "$current_manifest" ]
}
