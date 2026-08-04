#!/usr/bin/env bash
# Select gist-master documents from one committed tree and publish their blobs.
# This trigger never reads document content from the working tree.
set -uo pipefail

warn() { printf 'WARN: gist post-commit sync: %s\n' "$*" >&2; }

repo_root="${GIST_POST_COMMIT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}" \
    || { warn 'not inside a git repository'; exit 0; }
commit="${1:-HEAD}"
commit="$(git -C "$repo_root" rev-parse --verify "${commit}^{commit}" 2>/dev/null)" \
    || { warn "invalid commit: $commit"; exit 0; }
verifier="$repo_root/scripts/gist_verified_write.sh"
[[ -x "$verifier" || -f "$verifier" ]] || { warn "verifier missing: $verifier"; exit 0; }

total_timeout="${GIST_POST_COMMIT_TIMEOUT_SECONDS:-60}"
[[ "$total_timeout" =~ ^[1-9][0-9]*$ ]] || { warn 'timeout must be a positive integer'; exit 0; }
started="$(date +%s)"
failures=0
selected=0

# --root makes the first commit explicit; --diff-filter=ACMR excludes deletes.
# Rename records yield the destination path with --name-only. NUL framing keeps
# every valid Git pathname intact until the newline policy below rejects it.
while IFS= read -r -d '' path; do
    case "$path" in
        docs/research/*.md) ;;
        *) continue ;;
    esac
    [[ "$path" != *$'\n'* ]] || { warn "newline path is unsupported: $path"; failures=$((failures + 1)); continue; }
    first_line="$(git -C "$repo_root" show "$commit:$path" 2>/dev/null | sed -n '1p')" || {
        warn "cannot read committed blob: $path"; failures=$((failures + 1)); continue;
    }
    [[ "$first_line" =~ ^\<\!--[[:space:]]gist-master: ]] || continue
    selected=$((selected + 1))
    elapsed=$(( $(date +%s) - started ))
    remaining=$(( total_timeout - elapsed ))
    if ((remaining <= 0)); then
        warn "total timeout reached after $selected selected file(s)"
        failures=$((failures + 1))
        break
    fi
    if ! (cd "$repo_root" && GIST_TIMEOUT_SECONDS="$remaining" \
        timeout "${remaining}s" bash "$verifier" --master "$path" --commit "$commit"); then
        warn "pending synchronization retained for $path at $commit"
        failures=$((failures + 1))
    fi
done < <(git -C "$repo_root" diff-tree --root --no-commit-id --name-only --diff-filter=ACMR -r -z "$commit")

((failures == 0)) || warn "$failures file(s) failed; retry via existing pending/reconcile path"
exit 0
