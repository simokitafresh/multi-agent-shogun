#!/usr/bin/env bats
# test_necessity: a SessionStart hook running without TMUX_PANE (a child
# `claude -p`, a daemon-spawned CLI) must NOT resolve its agent from the tmux
# active pane and must therefore never rewrite another agent's deepdive
# session marker. Invariant guards 2026-09-01 15:19 (marker of shogun rewritten
# by a foreign process -> 16/16 receipts expired -> false stop-hook BLOCK).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts/hooks" "$T/scripts/lib" "$T/logs/deepdive_replay" "$T/queue" "$T/config"
  cp "$ROOT/scripts/hooks/session_start_inject.sh" "$T/scripts/hooks/"
  cp -r "$ROOT/scripts/lib/." "$T/scripts/lib/" 2>/dev/null || true
  # fake tmux: any -p query without -t returns "shogun" (the active pane);
  # with -t it returns the pane's own id.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -t "* ]]; then echo "gunshi"; else echo "shogun"; fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
}

@test "startup without TMUX_PANE does not touch any deepdive session marker" {
  run env -u TMUX_PANE -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" >/dev/null 2>&1; ls "$1/logs/deepdive_replay"' _ "$T"
  [ "$status" -eq 0 ]
  [[ "$output" != *"shogun.session"* ]]
  [[ "$output" != *".session"* ]]
}

@test "startup with TMUX_PANE resolves the pane's own agent and writes only that marker" {
  run env -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" >/dev/null 2>&1; ls "$1/logs/deepdive_replay"' _ "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gunshi.session"* ]]
  [[ "$output" != *"shogun.session"* ]]
}

# test_necessity: cmd_karo_hotfix_inbox_unread_source_202609031435 — the
# `inbox_unread:` field injected at session start must equal the inbox file's
# actual read:false field count for its own generation, even when a
# multi-line block-scalar `content: |-` value happens to contain a standalone
# line shaped like "read: false". Guards the regression where an
# already-read (read:true) message kept inflating the displayed unread count.
@test "session start inbox_unread stays 0 when a phantom 'read: false' line lives only inside a read:true message's block content" {
  mkdir -p "$T/queue/inbox"
  cat > "$T/queue/inbox/gunshi.yaml" <<'EOF'
messages:
- content: |-
    これはブロックリテラルの例。
    read: false
    という行がcontent内にあるが実フィールドではない。
  from: 'karo'
  id: 'msg1'
  read: true
  timestamp: '2026-09-03T13:40:00'
  type: 'task_supplement'
EOF
  run env -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" 2>/dev/null' _ "$T"
  [[ "$output" == *"inbox_unread: 0"* ]]
}

@test "session start inbox_unread shows 1 for a genuinely unread message even with the phantom line present" {
  mkdir -p "$T/queue/inbox"
  cat > "$T/queue/inbox/gunshi.yaml" <<'EOF'
messages:
- content: |-
    これはブロックリテラルの例。
    read: false
    という行がcontent内にあるが実フィールドではない。
  from: 'karo'
  id: 'msg1'
  read: true
  timestamp: '2026-09-03T13:40:00'
  type: 'task_supplement'
- content: '本物の未読'
  from: 'karo'
  id: 'msg2'
  read: false
  timestamp: '2026-09-03T13:41:00'
  type: 'wake_up'
EOF
  run env -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" 2>/dev/null' _ "$T"
  [[ "$output" == *"inbox_unread: 1"* ]]
}

@test "session start inbox_unread returns to 0 after the genuinely unread message is marked read, phantom line still present" {
  mkdir -p "$T/queue/inbox"
  cat > "$T/queue/inbox/gunshi.yaml" <<'EOF'
messages:
- content: |-
    これはブロックリテラルの例。
    read: false
    という行がcontent内にあるが実フィールドではない。
  from: 'karo'
  id: 'msg1'
  read: true
  timestamp: '2026-09-03T13:40:00'
  type: 'task_supplement'
- content: '本物の未読'
  from: 'karo'
  id: 'msg2'
  read: true
  timestamp: '2026-09-03T13:41:00'
  type: 'wake_up'
EOF
  run env -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" 2>/dev/null' _ "$T"
  [[ "$output" == *"inbox_unread: 0"* ]]
}
