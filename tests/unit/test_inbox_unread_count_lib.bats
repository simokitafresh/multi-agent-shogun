#!/usr/bin/env bats
# test_necessity: inbox 未読件数はレコード直下の `read: false` フィールドだけを数え、
# content 本文中の「read: false」文字列(単一行/ブロックスカラー)を未読と誤認しない(T3-S-43)。
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  . "$ROOT/scripts/lib/inbox_unread_count.sh"
  TMPD="$(mktemp -d)"
}
teardown() { rm -rf "$TMPD"; }

@test "T3-S-43: content 内の read: false 文字列は未読に数えない" {
  cat > "$TMPD/inbox.yaml" <<'Y'
messages:
- action: 'bulletin_notify'
  content: '掲示板: 旧世代 msg が read: false のまま残存。mark_read BLOCK'
  id: 'm1'
  read: true
  type: 'bulletin_notify'
- action: 'x'
  content: |-
    block scalar line
    read: false
  id: 'm2'
  read: true
  type: 'info'
- action: 'y'
  content: 'real unread'
  id: 'm3'
  read: false
  type: 'task_assigned'
Y
  run inbox_unread_count "$TMPD/inbox.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "missing file → 0" {
  run inbox_unread_count "$TMPD/nope.yaml"
  [ "$output" = "0" ]
}
