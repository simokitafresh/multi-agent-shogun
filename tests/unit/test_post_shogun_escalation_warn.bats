#!/usr/bin/env bats
# test_post_shogun_escalation_warn.bats — escalation未対処WARN検出テスト (LS090)

setup() {
    export TMPDIR="${BATS_TEST_TMPDIR}"
}

@test "escalation read:false → count 1" {
    local inbox="$TMPDIR/inbox.yaml"
    cat > "$inbox" <<'YAML'
messages:
- content: 'escalation message'
  type: 'escalation'
  read: false
- content: 'normal message'
  type: 'bulletin_notify'
  read: false
YAML
    result=$(awk '/type:.*escalation/{esc=1; next} esc && /read: false/{n++; esc=0; next} /read:/{esc=0} END{print n+0}' "$inbox")
    [ "$result" -eq 1 ]
}

@test "escalation read:true → count 0" {
    local inbox="$TMPDIR/inbox.yaml"
    cat > "$inbox" <<'YAML'
messages:
- content: 'escalation message'
  type: 'escalation'
  read: true
- content: 'normal message'
  type: 'bulletin_notify'
  read: false
YAML
    result=$(awk '/type:.*escalation/{esc=1; next} esc && /read: false/{n++; esc=0; next} /read:/{esc=0} END{print n+0}' "$inbox")
    [ "$result" -eq 0 ]
}

@test "two escalations one unread → count 1" {
    local inbox="$TMPDIR/inbox.yaml"
    cat > "$inbox" <<'YAML'
messages:
- content: 'first escalation'
  type: 'escalation'
  read: true
- content: 'second escalation'
  type: 'escalation'
  read: false
YAML
    result=$(awk '/type:.*escalation/{esc=1; next} esc && /read: false/{n++; esc=0; next} /read:/{esc=0} END{print n+0}' "$inbox")
    [ "$result" -eq 1 ]
}

@test "no escalation → count 0" {
    local inbox="$TMPDIR/inbox.yaml"
    cat > "$inbox" <<'YAML'
messages:
- content: 'gate clear'
  type: 'gate_clear'
  read: false
- content: 'bulletin'
  type: 'bulletin_notify'
  read: false
YAML
    result=$(awk '/type:.*escalation/{esc=1; next} esc && /read: false/{n++; esc=0; next} /read:/{esc=0} END{print n+0}' "$inbox")
    [ "$result" -eq 0 ]
}
