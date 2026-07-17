#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/project"; mkdir -p "$T/queue/inbox" "$T/queue" "$T/logs" "$T/bin"
  cp "$ROOT/.claude/hooks/post-shogun-inbox-check.sh" "$T/hook.sh"
  printf 'messages: []\n' >"$T/queue/inbox/shogun.yaml"
  touch "$T/logs/shogun_recovery_complete"
  cat >"$T/bin/tmux" <<'SH'
#!/usr/bin/env bash
echo shogun
SH
  chmod +x "$T/bin/tmux" "$T/hook.sh"
  export PATH="$T/bin:$PATH" SHOGUN_ROOT="$T" TMUX_PANE="test_$$" SHOGUN_LORD_PENDING_NOW=1784287860 SHOGUN_LORD_PENDING_TTL_SEC=3600
  export SHOGUN_INBOX_PATH="$T/queue/inbox/shogun.yaml" SHOGUN_RECOVERY_MARKER="$T/logs/shogun_recovery_complete"
  export SHOGUN_LORD_CONV_PATH="$T/queue/lord_conversation.jsonl"
}

add_event() {
  printf '%s\n' "$1" >>"$SHOGUN_LORD_CONV_PATH"
}

@test "five duplicate inbound items become newest three unique unanswered" {
  add_event '{"ts":"2026-07-17T11:26:10+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"alpha"}'
  add_event '{"ts":"2026-07-17T11:27:10+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"beta"}'
  add_event '{"ts":"2026-07-17T11:28:10+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"alpha"}'
  add_event '{"ts":"2026-07-17T11:29:10+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"gamma"}'
  add_event '{"ts":"2026-07-17T11:30:10+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"delta"}'
  run "$T/hook.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *'delta | 11:29 gamma | 11:28 alpha'* ]]
  [ "$(grep -o 'alpha' <<<"$output" | wc -l)" -eq 1 ]; [[ "$output" != *beta* ]]
}

@test "response and TTL remove old items but preserve latest unanswered" {
  add_event '{"ts":"2026-07-17T09:00:00+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"expired"}'
  add_event '{"ts":"2026-07-17T11:27:00+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"answered"}'
  add_event '{"ts":"2026-07-17T11:28:00+00:00","direction":"response","agent":"shogun","target":"lord","summary":"reply"}'
  add_event '{"ts":"2026-07-17T11:29:00+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"latest"}'
  run "$T/hook.sh"
  [[ "$output" == *latest* ]]; [[ "$output" != *answered* ]]; [[ "$output" != *expired* ]]
}

@test "ten consecutive tools keep injected context bounded" {
  for n in 1 2 3 4 5; do add_event "{\"ts\":\"2026-07-17T11:3${n}:00+00:00\",\"direction\":\"inbound\",\"agent\":\"lord\",\"target\":\"shogun\",\"summary\":\"item$n\"}"; done
  first=0; max=0
  for _n in $(seq 1 10); do
    value="$("$T/hook.sh")"; bytes=${#value}; [ "$first" -gt 0 ] || first=$bytes; [ "$bytes" -le "$max" ] || max=$bytes
    [ "$(grep -o 'item[0-9]' <<<"$value" | wc -l)" -eq 3 ]
  done
  [ "$max" -le $((first * 11 / 10)) ]
  echo "TOOLS=10 FIRST_BYTES=$first MAX_BYTES=$max"
}

@test "malformed rows and other targets never displace latest lord instruction" {
  add_event 'not-json'
  add_event '{"ts":"2026-07-17T11:29:00+00:00","direction":"inbound","agent":"lord","target":"karo","summary":"other"}'
  add_event '{"ts":"2026-07-17T11:30:00+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"must-keep"}'
  run "$T/hook.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *must-keep* ]]; [[ "$output" != *other* ]]
}

@test "unchanged conversation cache expires by TTL time bucket" {
  add_event '{"ts":"2026-07-17T11:30:00+00:00","direction":"inbound","agent":"lord","target":"shogun","summary":"short-lived"}'
  run "$T/hook.sh"; [[ "$output" == *short-lived* ]]
  export SHOGUN_LORD_PENDING_NOW=1784291520
  run "$T/hook.sh"; [[ "$output" != *short-lived* ]]
}
