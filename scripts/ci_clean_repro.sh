#!/usr/bin/env bash
# ci_clean_repro.sh — run one explicit test command in a reproducible clean-CI envelope.

set -uo pipefail

usage() {
    cat <<'EOF'
Usage: ci_clean_repro.sh --receipt PATH -- COMMAND [ARG...]

Creates a fresh HOME/TMPDIR, exposes only a minimal environment, removes
external-repository hints, and writes PATH plus PATH.clean.json receipts.
The command is explicit: shell strings are not evaluated by this harness.
EOF
}

receipt=""
while (($#)); do
    case "$1" in
        --receipt) receipt="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        *) printf 'BLOCK: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -n "$receipt" && $# -gt 0 ]] || { usage >&2; exit 2; }
[[ "$receipt" = /* ]] || { echo "BLOCK: receipt path must be absolute" >&2; exit 2; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
parent_home="${HOME:-}"
clean_root="$(mktemp -d "${TMPDIR:-/tmp}/shogun-clean-ci.XXXXXX")"
clean_home="$clean_root/home"
clean_tmp="$clean_root/tmp"
metadata="${receipt%.json}.clean.json"
mkdir -p "$clean_home" "$clean_tmp" "$(dirname "$receipt")"

cleanup() { rm -rf -- "$clean_root"; }
trap cleanup EXIT

# The parent directory identity/metadata catches direct writes without walking
# a concurrently active user HOME (whose unrelated cache writes would create
# false failures). The stronger boundary is that its path is not exposed.
home_digest() {
    [[ -n "$parent_home" && -d "$parent_home" ]] || { printf 'absent'; return; }
    stat -c '%d:%i:%s:%Y:%Z' "$parent_home"
}
before_home="$(home_digest)"
started_ms="$(date +%s%3N)"

set +e
env -i \
    PATH="${PATH:-/usr/bin:/bin}" \
    HOME="$clean_home" \
    TMPDIR="$clean_tmp" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 CI=true CLEAN_CI=1 \
    SHOGUN_REPO_ROOT="$repo_root" \
    bash "$script_dir/run_with_receipt.sh" --receipt "$receipt" -- "$@"
rc=$?
set -e

after_home="$(home_digest)"
parent_home_unchanged=false
[[ "$before_home" == "$after_home" ]] && parent_home_unchanged=true
ended_ms="$(date +%s%3N)"
meta_tmp="$(mktemp "$(dirname "$metadata")/.ci_clean_meta.XXXXXX")"
python3 - "$meta_tmp" "$receipt" "$clean_home" "$clean_tmp" "$repo_root" \
    "$before_home" "$after_home" "$parent_home_unchanged" "$started_ms" "$ended_ms" "$rc" "$@" <<'PY'
import json, os, sys
(path, receipt, home, tmp, repo, before, after, unchanged,
 started, ended, rc, *command) = sys.argv[1:]
data = {
    "version": 1,
    "receipt": receipt,
    "clean_home_created": os.path.isdir(home),
    "clean_tmp_created": os.path.isdir(tmp),
    "external_repo_env_absent": True,
    "minimal_env": ["CI", "CLEAN_CI", "HOME", "LANG", "LC_ALL", "PATH", "SHOGUN_REPO_ROOT", "TMPDIR"],
    "production_env_exposed": False,
    "parent_home_digest_before": before,
    "parent_home_digest_after": after,
    "parent_home_unchanged": unchanged == "true",
    "duration_ms": int(ended) - int(started),
    "rc": int(rc),
    "result": "PASS" if int(rc) == 0 and unchanged == "true" else "FAIL",
    "command": command,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
PY
mv -f -- "$meta_tmp" "$metadata"

[[ "$parent_home_unchanged" == true ]] || { echo "BLOCK: parent HOME changed" >&2; exit 2; }
printf 'CLEAN_CI_RECEIPT path=%s metadata=%s rc=%s duration_ms=%s\n' \
    "$receipt" "$metadata" "$rc" "$((ended_ms - started_ms))"
exit "$rc"
