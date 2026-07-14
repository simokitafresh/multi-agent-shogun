#!/usr/bin/env bats

setup_file() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export ROOT SOURCE_MARKER_TEMPLATE
  SOURCE_MARKER_TEMPLATE="$(mktemp -d "$BATS_TMPDIR/source-marker-template.XXXXXX")"
  mkdir -p "$SOURCE_MARKER_TEMPLATE/scripts/config" "$SOURCE_MARKER_TEMPLATE/scripts/lib" "$SOURCE_MARKER_TEMPLATE/context" "$SOURCE_MARKER_TEMPLATE/config"
  cp "$ROOT/scripts/context_source_commit_set.sh" "$SOURCE_MARKER_TEMPLATE/scripts/"
  cp "$ROOT/scripts/lib/project_path.sh" "$ROOT/scripts/lib/repo_root.sh" "$SOURCE_MARKER_TEMPLATE/scripts/lib/"
  printf 'context/test.md\tinfra\n' > "$SOURCE_MARKER_TEMPLATE/scripts/config/context_source_commits.tsv"
  git -C "$SOURCE_MARKER_TEMPLATE" init -q
  git -C "$SOURCE_MARKER_TEMPLATE" config user.email test@example.invalid
  git -C "$SOURCE_MARKER_TEMPLATE" config user.name Test
  printf '# Test\n<!-- last_updated: 2026-07-01 -->\n' > "$SOURCE_MARKER_TEMPLATE/context/test.md"
  git -C "$SOURCE_MARKER_TEMPLATE" add . && git -C "$SOURCE_MARKER_TEMPLATE" commit -qm init
}

setup() {
  TMP="$(mktemp -d "$BATS_TMPDIR/source-marker.XXXXXX")"
  cp -r "$SOURCE_MARKER_TEMPLATE/." "$TMP/"
  SHA="$(git -C "$TMP" rev-parse HEAD)"
}

@test "validates dm-signal marker in the registered external source repo" {
  mkdir -p "$TMP/dm/.git-placeholder"
  git -C "$TMP/dm" init -q
  git -C "$TMP/dm" config user.email test@example.invalid
  git -C "$TMP/dm" config user.name Test
  echo source > "$TMP/dm/source"; git -C "$TMP/dm" add .; git -C "$TMP/dm" commit -qm source
  dm_sha="$(git -C "$TMP/dm" rev-parse HEAD)"
  printf 'projects:\n  - id: dm-signal\n    path: "%s"\n' "$TMP/dm" > "$TMP/config/projects.yaml"
  printf 'context/test.md\tdm-signal\n' > "$TMP/scripts/config/context_source_commits.tsv"
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$dm_sha" audit exact-pathspec
  [ "$status" -eq 0 ]
  grep -q "source_commit:$dm_sha" "$TMP/context/test.md"
}

@test "fails closed for duplicate and unknown registry projects" {
  printf 'context/test.md\tinfra\ncontext/test.md\tinfra\n' > "$TMP/scripts/config/context_source_commits.tsv"
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$SHA" audit evidence
  [ "$status" -ne 0 ]
  printf 'context/test.md\tunknown\n' > "$TMP/scripts/config/context_source_commits.tsv"
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$SHA" audit evidence
  [ "$status" -ne 0 ]
}

teardown() { rm -rf "$TMP"; }

teardown_file() { rm -rf "$SOURCE_MARKER_TEMPLATE"; }

@test "sets validated source commit with reason and evidence" {
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$SHA" audit log-zero
  [ "$status" -eq 0 ]
  grep -q "source_commit:$SHA reason:audit evidence:log-zero" "$TMP/context/test.md"
}

@test "replaces a source marker whose evidence contains an arrow" {
  printf '# Test\n<!-- last_updated: 2026-07-01 -->\n<!-- source_commit:deadbee reason:old evidence:alerts:3->0 -->\n<!-- source_commit:feedbee reason:duplicate evidence:stale -->\n' > "$TMP/context/test.md"
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md "$SHA" audit current
  [ "$status" -eq 0 ]
  [ "$(grep -c '<!-- source_commit:' "$TMP/context/test.md")" -eq 1 ]
  grep -q "source_commit:$SHA reason:audit evidence:current" "$TMP/context/test.md"
}

@test "rejects invalid or non-ancestor commit" {
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md HEAD audit evidence
  [ "$status" -ne 0 ]
  run bash "$TMP/scripts/context_source_commit_set.sh" context/test.md deadbee audit evidence
  [ "$status" -ne 0 ]
}
