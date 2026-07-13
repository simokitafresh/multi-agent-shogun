#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$(mktemp -d "$BATS_TMPDIR/source-marker.XXXXXX")"
  mkdir -p "$TMP/scripts" "$TMP/context"
  cp "$ROOT/scripts/context_source_commit_set.sh" "$TMP/scripts/"
  git -C "$TMP" init -q
  git -C "$TMP" config user.email test@example.invalid
  git -C "$TMP" config user.name Test
  printf '# Test\n<!-- last_updated: 2026-07-01 -->\n' > "$TMP/context/test.md"
  git -C "$TMP" add . && git -C "$TMP" commit -qm init
  SHA="$(git -C "$TMP" rev-parse HEAD)"
}

teardown() { rm -rf "$TMP"; }

@test "sets validated source commit with reason and evidence" {
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$SHA" audit log-zero
  [ "$status" -eq 0 ]
  grep -q "source_commit:$SHA reason:audit evidence:log-zero" "$TMP/context/test.md"
}

@test "rejects invalid or non-ancestor commit" {
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md HEAD audit evidence
  [ "$status" -ne 0 ]
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md deadbee audit evidence
  [ "$status" -ne 0 ]
}
