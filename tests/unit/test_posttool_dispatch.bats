#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/.claude/hooks" "$TMPROOT/logs"
  cp "$ROOT/.claude/hooks/posttool-dispatch.sh" "$TMPROOT/.claude/hooks/"
  cp "$ROOT/.claude/hooks/post-write-edit-combined.sh" "$TMPROOT/.claude/hooks/"
}

teardown() {
  rm -rf "$TMPROOT"
}

post_edit_payload() {
  jq -cn --arg path "$1" '{tool_name:"Edit",tool_input:{file_path:$path}}'
}

@test "PostToolUse shellcheck warning is emitted without crashing dispatcher" {
  cat > "$TMPROOT/bad.sh" <<'SH'
#!/usr/bin/env bash
for item in $(ls); do
  echo $item
done
SH

  run bash "$TMPROOT/.claude/hooks/posttool-dispatch.sh" <<< "$(post_edit_payload bad.sh)"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ShellCheck violations in bad.sh"* ]]
}
