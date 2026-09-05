#!/usr/bin/env bash
# external_project_ref_resolver.sh — shared external-project reference
# resolution for context/*.md link-existence gates (GA-579/GA-580).
#
# A `docs/research/...` (or `context/...`) reference from a context file
# that maps to exactly one external project (e.g. context/dm-signal*.md)
# must be checked against THAT project only — never any other registered
# project that happens to hold a same-named path (GA-580: same-name
# cross-project false-adopt). A context file that maps to no single
# project (platform docs such as context/infrastructure.md) legitimately
# links across many registered projects and keeps the broad
# all-registered-project resolution (GA-314).
#
# A reference must also not be declared missing just because an external
# project's LOCAL checkout is stale or dirty relative to its own tracked
# history (GA-579): a filesystem-only check makes every reference added by
# a commit not yet pulled into that checkout look deleted, even though the
# content is real and reachable in that project's own git history.
#
# Sourced by scripts/gates/gate_context_freshness.sh and
# scripts/gates/gate_vercel_phase.sh. Keep this file dependency-free
# (no external state, no global var reads) so both callers can use it
# without coordinating unrelated internals.

# external_ref_canonical_project_id <rel_path>
# Prints the single project id this rel_path canonically belongs to and
# returns 0, or returns 1 (prints nothing) when no single project owns it.
external_ref_canonical_project_id() {
    local rel_path="$1"
    [[ "$rel_path" == context/dm-signal*.md ]] && { printf 'dm-signal\n'; return 0; }
    [[ "$rel_path" == context/rebalancer.md ]] && { printf 'rebalancer\n'; return 0; }
    return 1
}

# external_ref_project_path <project_id> <projects_yaml_config>
# Prints the registered filesystem path for project_id from a
# projects.yaml-style config (top-level `projects:` list of
# `- id: ... / path: ...` entries). Returns 1 when unresolved.
external_ref_project_path() {
    local project_id="$1" config="$2" result=""
    [[ -f "$config" && -r "$config" ]] || return 1
    result="$(awk -v target="$project_id" '
        function clean(value) {
            gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", value)
            return value
        }
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ {
            id=$0
            sub(/.*id:[[:space:]]*/, "", id)
            id=clean(id)
            next
        }
        id == target && /^[[:space:]]+path:[[:space:]]*/ {
            path=$0
            sub(/.*path:[[:space:]]*/, "", path)
            print clean(path)
            exit 0
        }
    ' "$config")"
    [[ -n "$result" ]] || return 1
    printf '%s\n' "$result"
}

# external_ref_exists_via_git <repo> <candidate> [timeout_sec]
# Fail-closed git-tree fallback: tries HEAD, then the repo's own
# remote-tracking main/master. Glob candidates are left to the caller's
# filesystem check (git cat-file has no glob support). Any git failure
# (missing repo, unresolvable ref, timeout) returns 1 — never silently
# treated as "exists".
external_ref_exists_via_git() {
    local repo="$1" candidate="$2" timeout_sec="${3:-10}" ref
    candidate="${candidate%/}"
    [[ "$candidate" == *"*"* || "$candidate" == *"?"* || "$candidate" == *"["* ]] && return 1
    [[ -e "$repo/.git" ]] || return 1
    for ref in HEAD origin/main origin/master; do
        timeout --kill-after=1 "$timeout_sec" git -C "$repo" cat-file -e "${ref}:${candidate}" 2>/dev/null && return 0
    done
    return 1
}
