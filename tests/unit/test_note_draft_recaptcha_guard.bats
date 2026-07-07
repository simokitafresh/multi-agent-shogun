#!/usr/bin/env bats
# Static regression tests for LS029 reCAPTCHA image challenge guard.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export NOTE_DRAFT_SCRIPT="$PROJECT_ROOT/scripts/note_draft.sh"
}

@test "note_draft blocks automated reCAPTCHA image solving immediately" {
    run bash -c "grep -q 'LS029 guard: automated image-tile solving is blocked' '$NOTE_DRAFT_SCRIPT'"
    [ "$status" -eq 0 ]

    run bash -c "grep -q 'raise RuntimeError(RECAPTCHA_BLOCK_HINT)' '$NOTE_DRAFT_SCRIPT'"
    [ "$status" -eq 0 ]

    run bash -c "! grep -q 'via agent vision; waiting up to 120s' '$NOTE_DRAFT_SCRIPT'"
    [ "$status" -eq 0 ]
}

@test "note_draft maps LS029 reCAPTCHA guard to SKIP not FAIL" {
    run bash -c "grep -q 'reCAPTCHA image challenge blocked\\|LS029 Level4 guard' '$NOTE_DRAFT_SCRIPT'"
    [ "$status" -eq 0 ]

    run bash -c "grep -q 'External reCAPTCHA image challenge blocked by LS029 Level4 guard; draft creation skipped' '$NOTE_DRAFT_SCRIPT'"
    [ "$status" -eq 0 ]
}
