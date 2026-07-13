#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$(mktemp -d "$BATS_TMPDIR/source-marker.XXXXXX")"
  mkdir -p "$TMP/scripts/config" "$TMP/scripts/lib" "$TMP/context" "$TMP/config"
  cp "$ROOT/scripts/context_source_commit_set.sh" "$TMP/scripts/"
  cp "$ROOT/scripts/lib/project_path.sh" "$ROOT/scripts/lib/repo_root.sh" "$TMP/scripts/lib/"
  printf 'context/test.md\tinfra\n' > "$TMP/scripts/config/context_source_commits.tsv"
  git -C "$TMP" init -q
  git -C "$TMP" config user.email test@example.invalid
  git -C "$TMP" config user.name Test
  printf '# Test\n<!-- last_updated: 2026-07-01 -->\n' > "$TMP/context/test.md"
  git -C "$TMP" add . && git -C "$TMP" commit -qm init
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
