#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_usage_metrics.XXXXXX")"
  mkdir -p "$TEST_TMPDIR/skills/used" "$TEST_TMPDIR/skills/unused" "$TEST_TMPDIR/skills/stale"
  cat > "$TEST_TMPDIR/skills/used/SKILL.md" <<'EOF'
---
name: used
---
# used
EOF
  cat > "$TEST_TMPDIR/skills/unused/SKILL.md" <<'EOF'
---
name: unused
---
# unused
EOF
  cat > "$TEST_TMPDIR/skills/stale/SKILL.md" <<'EOF'
---
name: stale
---
# stale
EOF
  touch -d '2099-01-09T00:00:00Z' "$TEST_TMPDIR/skills/used/SKILL.md"
  touch -d '2099-01-09T00:00:00Z' "$TEST_TMPDIR/skills/unused/SKILL.md"
  touch -d '2098-12-01T00:00:00Z' "$TEST_TMPDIR/skills/stale/SKILL.md"
  cat > "$TEST_TMPDIR/skill_recommend_log.yaml" <<'EOF'
recommendations:
- ts: "2099-01-10T00:00:00+09:00"
  agent_id: "hanzo"
  prompt_hash: "a"
  recommended_skills:
  - "used"
  - "stale"
- ts: "2099-01-10T00:01:00+09:00"
  agent_id: "hanzo"
  prompt_hash: "b"
  recommended_skills:
  - "used"
EOF
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "skill usage metrics outputs recommendation counts and stale debt as JSON" {
  run bash "$PROJECT_ROOT/scripts/skill_usage_metrics.sh" \
    --skills-dir "$TEST_TMPDIR/skills" \
    --recommend-log "$TEST_TMPDIR/skill_recommend_log.yaml" \
    --stale-days 30 \
    --now "2099-01-10T00:00:00Z"

  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
by_name = {item["skill"]: item for item in data["skills"]}
assert data["total_skills"] == 3
assert data["used_skill_count"] == 2
assert data["unused_skill_count"] == 1
assert data["stale_skill_count"] == 1
assert by_name["used"]["recommend_count"] == 2
assert by_name["unused"]["unused"] is True
assert by_name["stale"]["stale"] is True
PY
}
