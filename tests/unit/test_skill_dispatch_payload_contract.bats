#!/usr/bin/env bats
# test_necessity: Skill hook routing must inspect structured skill/result fields so explanatory text cannot cause false blocks or false failure logs.
# regression_justification: Payload-wide substring matching previously blocked unrelated skills and logged successful "FAIL count is zero" results as failures.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "pretool clear guard exact-matches skill and ignores args mention" {
  payload='{"tool_name":"Skill","tool_input":{"skill":"unrelated-skill","args":"audit shogun-clear-prep documentation"}}'
  run env AGENT_ID=shogun bash "$ROOT/.claude/hooks/pretool-dispatch.sh" <<<"$payload"
  [ "$status" -eq 0 ]

  payload='{"tool_name":"Skill","tool_input":{"skill":"shogun-clear-prep","args":""}}'
  run env AGENT_ID=shogun bash "$ROOT/.claude/hooks/pretool-dispatch.sh" <<<"$payload"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: /clear自発禁止"* ]]
}

@test "post skill result classifier ignores success wording and detects structured failure" {
  hook="$ROOT/.claude/hooks/post-skill-execution.sh"
  classifier="$(sed -n '/failure_meta=/,/unset failure_meta result_text/p' "$hook")"

  run bash -c 'payload=$1; eval "$2"; printf "%s" "$result"' _ \
    '{"tool_name":"Skill","tool_input":{"skill":"demo"},"status":"success","tool_result":"FAIL count is zero; audit passed"}' \
    "result=PASS; stumbling_points=''; $classifier"
  [ "$status" -eq 0 ]
  [ "$output" = "PASS" ]

  run bash -c 'payload=$1; eval "$2"; printf "%s" "$result"' _ \
    '{"tool_name":"Skill","tool_input":{"skill":"demo"},"status":"failed","tool_result":"diagnostic details"}' \
    "result=PASS; stumbling_points=''; $classifier"
  [ "$status" -eq 0 ]
  [ "$output" = "FAIL" ]

  run bash -c 'payload=$1; eval "$2"; printf "%s" "$result"' _ \
    '{"tool_name":"Skill","tool_input":{"skill":"demo"},"tool_result":"ERROR: actual failure"}' \
    "result=PASS; stumbling_points=''; $classifier"
  [ "$status" -eq 0 ]
  [ "$output" = "FAIL" ]
}
