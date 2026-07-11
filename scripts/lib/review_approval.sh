#!/usr/bin/env bash
# Fingerprint-bound two-phase review approval storage.

review_report_fingerprint() {
    local report="$1" content_hash commit_hash
    [ -f "$report" ] || return 1
    content_hash=$(sha256sum "$report" | awk '{print $1}') || return 1
    commit_hash=$(python3 - "$report" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
for key in ("commit_hash", "commit", "git_commit"):
    value = d.get(key)
    if isinstance(value, str) and value.strip():
        print(value.strip()); break
else:
    result = d.get("result") or {}
    print(result.get("commit_hash", "") if isinstance(result, dict) else "")
PY
)
    [ -n "$commit_hash" ] || commit_hash="MISSING"
    printf '%s:%s\n' "$content_hash" "$commit_hash"
}

review_approval_value() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    awk -F': ' -v key="$key" '$1 == key {sub(/^[^:]*: /, ""); print; exit}' "$file"
}

review_two_phase_ready() {
    local cmd_id="$1" report="$2" dir fingerprint gunshi_fp karo_fp karo_result
    dir="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/queue/gates/${cmd_id}/review_approvals"
    fingerprint=$(review_report_fingerprint "$report") || return 1
    gunshi_fp=$(review_approval_value "$dir/gunshi.yaml" fingerprint || true)
    karo_fp=$(review_approval_value "$dir/karo.yaml" fingerprint || true)
    karo_result=$(review_approval_value "$dir/karo.yaml" result || true)
    [ "$karo_result" = "ACCEPT" ] && [ "$gunshi_fp" = "$fingerprint" ] && [ "$karo_fp" = "$fingerprint" ]
}
