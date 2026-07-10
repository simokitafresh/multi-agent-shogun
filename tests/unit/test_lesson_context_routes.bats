#!/usr/bin/env bats
# GA-216/GA-217: resolve_lesson_context_route() SSOT unit tests.
# scripts/lesson_write.sh (write-time sync) and scripts/gates/gate_lesson_health.sh
# (unsynced check) both source scripts/gates/lesson_context_routes.sh so their
# understanding of "which file does subdomain X sync to" cannot drift apart.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export ROUTES_SCRIPT="$PROJECT_ROOT/scripts/gates/lesson_context_routes.sh"
    [ -f "$ROUTES_SCRIPT" ] || return 1
}

setup() {
    # shellcheck disable=SC1090
    source "$ROUTES_SCRIPT"
}

@test "dm-signal:fe routes to dm-signal-frontend.md" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "fe"
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal-frontend.md" ]
    [[ "$CONTEXT_ROUTE_ANCHOR" == *"Frontend関連教訓"* ]]
}

@test "dm-signal:be routes to dm-signal-ops.md section 6-7" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "be"
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal-ops.md" ]
    [[ "$CONTEXT_ROUTE_ANCHOR" == *"§6-7"* ]]
}

@test "dm-signal:gs routes to dm-signal-ops.md section 33" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "gs"
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal-ops.md" ]
    [[ "$CONTEXT_ROUTE_ANCHOR" == *"§33"* ]]
}

@test "dm-signal:infra and infra:infra both route to infrastructure.md" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "infra"
    [ "$CONTEXT_ROUTE_FILE" = "context/infrastructure.md" ]

    PROJECT_META_CONTEXT_FILE="context/infrastructure.md" resolve_lesson_context_route "infra" "infra"
    [ "$CONTEXT_ROUTE_FILE" = "context/infrastructure.md" ]
}

@test "infra:* (any subdomain) routes to infrastructure.md" {
    PROJECT_META_CONTEXT_FILE="context/infrastructure.md" resolve_lesson_context_route "infra" "gate"
    [ "$CONTEXT_ROUTE_FILE" = "context/infrastructure.md" ]
}

@test "unknown subdomain falls back to the project's default context file" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "research"
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal.md" ]
    [ -z "$CONTEXT_ROUTE_ANCHOR" ]
}

@test "empty subdomain falls back to the project's default context file" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" ""
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal.md" ]
}

@test "unrouted project falls back to its default context file regardless of subdomain" {
    PROJECT_META_CONTEXT_FILE="context/database.md" resolve_lesson_context_route "database" "gs"
    [ "$CONTEXT_ROUTE_FILE" = "context/database.md" ]
}

@test "comma-separated subdomain uses only the first segment for routing" {
    PROJECT_META_CONTEXT_FILE="context/dm-signal.md" resolve_lesson_context_route "dm-signal" "gs,extra"
    [ "$CONTEXT_ROUTE_FILE" = "context/dm-signal-ops.md" ]
    [[ "$CONTEXT_ROUTE_ANCHOR" == *"§33"* ]]
}

@test "LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS lists every subdomain that has a non-default route" {
    # gate_lesson_health.sh iterates this array to discover which subdomains need
    # their own marker lookup. Any case-statement subdomain missing from this list
    # would silently fall back to the old (buggy) single-file check for that subdomain.
    local -A known=()
    local sd
    for sd in "${LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS[@]}"; do
        known["$sd"]=1
    done
    [ -n "${known[fe]:-}" ]
    [ -n "${known[be]:-}" ]
    [ -n "${known[gs]:-}" ]
    [ -n "${known[infra]:-}" ]
}
