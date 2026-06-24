#!/usr/bin/env bash
# Codex SessionStart adapter.
# Kept separate from Claude settings so Codex startup behavior can evolve
# without pretending every CLI has the same lifecycle semantics.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/scripts/hooks/codex_session_start.sh}"

bash "$ROOT/scripts/hooks/session_start_inject.sh" || true
