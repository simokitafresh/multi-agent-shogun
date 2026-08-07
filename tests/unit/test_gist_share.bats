#!/usr/bin/env bats
# test_necessity: gist-share must create only secret Gists, stop at the commit boundary, and publish existing masters only after verified hash equality and index success; violation can publish unverified or public content and is BLOCK.

setup() {
  export ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/bin"
  git -C "$R" init -q
  git -C "$R" config user.email test@example.com
  git -C "$R" config user.name test
  printf 'body\n' > "$R/master.md"
  git -C "$R" add master.md && git -C "$R" commit -qm initial
  cp "$ROOT/scripts/gist_share.sh" "$R/gist_share.sh"
  export GH_CMD="$R/bin/gh"
  export GIST_VERIFIED_WRITE_CMD="$R/bin/writer"
  export GIST_INDEX_UPDATE_CMD="$R/bin/indexer"
  export CALLS="$R/calls"
  cat > "$GH_CMD" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >> "$CALLS"
previous=""
for argument in "$@"; do
  if [ "$previous" = --input ]; then cp "$argument" "$R/create-payload.json"; fi
  previous="$argument"
done
case "${MODE:-create_ok}" in create_fail) exit 44;; invalid_id) printf '{"id":"bad-id","public":false}\n';; public) printf '{"id":"abc123","public":true}\n';; *) printf '{"id":"abc123","public":false}\n';; esac
SH
  cat > "$GIST_VERIFIED_WRITE_CMD" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'writer %s\n' "$*" >> "$CALLS"
sha="$(git show "HEAD:$2" | sha256sum | awk '{print $1}')"
[ "${MODE:-ok}" != mismatch ] || sha=0000
[ "${MODE:-ok}" != owner_mismatch ] || { echo 'owner mismatch' >&2; exit 1; }
[ "${MODE:-ok}" != visibility_mismatch ] || { echo 'visibility must be secret' >&2; exit 1; }
[ "${MODE:-ok}" != filename_missing ] || { echo 'multiple-file gist requires explicit remote filename' >&2; exit 1; }
printf 'VERIFIED gist=abc123 filename=master.md sha256=%s\n' "$sha"
SH
  cat > "$GIST_INDEX_UPDATE_CMD" <<'SH'
#!/usr/bin/env bash
printf 'index\n' >> "$CALLS"
[ "${MODE:-ok}" != index_fail ]
SH
  chmod +x "$GH_CMD" "$GIST_VERIFIED_WRITE_CMD" "$GIST_INDEX_UPDATE_CMD" "$R/gist_share.sh"
}

@test "new secret gist stops after atomic metadata insertion" {
  run env GIST_ALLOW_CREATE=1 bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -eq 2 ]
  [[ "$output" == *"GIST_CREATED_PENDING_COMMIT gist_id=abc123"* ]]
  [ "$(head -n1 "$R/master.md")" = '<!-- gist-master: abc123 master.md -->' ]
  grep -Fq -- '--method POST gists' "$CALLS"
  [ "$(jq -r '.public' "$R/create-payload.json")" = false ]
  [ "$(grep -c '^writer\|^index' "$CALLS" || true)" -eq 0 ]
}

@test "public selection is not an accepted interface" {
  run bash -c 'cd "$R" && bash ./gist_share.sh --public master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"usage:"* ]]; [ ! -e "$CALLS" ]
}

@test "existing committed master returns URL and equal hashes then indexes" {
  sed -i '1i<!-- gist-master: abc123 master.md -->' "$R/master.md"
  git -C "$R" add master.md && git -C "$R" commit -qm meta
  run bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -eq 0 ]; [[ "$output" == *"GIST_SHARED url=https://gist.github.com/abc123"* ]]
  local_hash="$(git -C "$R" show HEAD:master.md | sha256sum | awk '{print $1}')"
  [[ "$output" == *"sha256_local=$local_hash sha256_remote=$local_hash"* ]]
  [ "$(tail -n1 "$CALLS")" = index ]
}

@test "dirty and staged identity both block before network" {
  printf dirty >> "$R/master.md"
  run bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"differs from HEAD"* ]]
  git -C "$R" add master.md
  run bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"staged changes"* ]]; [ ! -e "$CALLS" ]
}

@test "create failures and unsafe responses expose orphan evidence" {
  run env GIST_ALLOW_CREATE=1 MODE=create_fail bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"title=master.md content_sha256="* ]]
  : > "$CALLS"
  run env GIST_ALLOW_CREATE=1 MODE=invalid_id bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"orphan_candidate title=master.md content_sha256="* ]]
  : > "$CALLS"
  run env GIST_ALLOW_CREATE=1 MODE=public bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"not secret; orphan_candidate gist_id=abc123"* ]]
}

@test "metadata install failure reports the created gist as an orphan candidate" {
  printf '#!/usr/bin/env bash\nexit 73\n' > "$R/bin/install-fail"; chmod +x "$R/bin/install-fail"
  run env GIST_ALLOW_CREATE=1 GIST_SHARE_METADATA_INSTALL_CMD="$R/bin/install-fail" bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"metadata atomic install failed; orphan_candidate gist_id=abc123 title=master.md content_sha256="* ]]
  [ "$(head -n1 "$R/master.md")" = body ]
}

@test "verified mismatch and index failure never report shared" {
  sed -i '1i<!-- gist-master: abc123 master.md -->' "$R/master.md"
  git -C "$R" add master.md && git -C "$R" commit -qm meta
  run env MODE=mismatch bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" != *"GIST_SHARED"* ]]
  run env MODE=index_fail bash -c 'cd "$R" && bash ./gist_share.sh master.md'
  [ "$status" -ne 0 ]; [[ "$output" == *"index update failed"* ]]; [[ "$output" != *"GIST_SHARED"* ]]
}

@test "writer owner visibility and multifile filename blocks propagate" {
  sed -i '1i<!-- gist-master: abc123 -->' "$R/master.md"
  git -C "$R" add master.md && git -C "$R" commit -qm meta
  for mode in owner_mismatch visibility_mismatch filename_missing; do
    run env MODE="$mode" bash -c 'cd "$R" && bash ./gist_share.sh master.md'
    [ "$status" -ne 0 ]; [[ "$output" != *"GIST_SHARED"* ]]
  done
}
