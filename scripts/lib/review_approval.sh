#!/usr/bin/env bash
# Fingerprint-bound two-phase review approval storage.

review_report_fingerprint() {
    local report="$1" content_hash commit_identity
    [ -f "$report" ] || return 1
    content_hash=$(sha256sum "$report" | awk '{print $1}') || return 1
    commit_identity=$(python3 - "$report" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
commit_hash = ""
for key in ("commit_hash", "commit", "git_commit"):
    value = d.get(key)
    if isinstance(value, str) and value.strip():
        commit_hash = value.strip()
        break
if not commit_hash:
    result = d.get("result") or {}
    commit_hash = result.get("commit_hash", "") if isinstance(result, dict) else ""

if isinstance(commit_hash, str) and len(commit_hash) == 40 and all(c in "0123456789abcdef" for c in commit_hash):
    print(commit_hash)
    raise SystemExit(0)

task_type = str(d.get("task_type", "")).strip().lower()
files_modified = d.get("files_modified")
checks = d.get("binary_checks") or {}
commit_claimed = False
if isinstance(checks, dict):
    for item in checks.get("commit", []) if isinstance(checks.get("commit", []), list) else []:
        if isinstance(item, dict) and (
            item.get("result") is True
            or str(item.get("result", "")).strip().lower() == "yes"
        ):
            commit_claimed = True
            break

# No-code reports have no commit to bind.  Their explicit structural contract is
# part of content_hash, while every report outside this narrow case stays fail-closed.
if task_type in ("scout", "recon") and files_modified == [] and not commit_claimed and not commit_hash:
    print("no-code-change")
    raise SystemExit(0)

raise SystemExit(1)
PY
) || return 1
    [ -n "$commit_identity" ] || return 1
    printf '%s:%s\n' "$content_hash" "$commit_identity"
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
