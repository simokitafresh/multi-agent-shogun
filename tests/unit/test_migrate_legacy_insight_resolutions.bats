#!/usr/bin/env bats

setup() {
  export ROOT="$BATS_TEST_DIRNAME/../.."
  export INSIGHTS_FILE="$BATS_TEST_TMPDIR/insights.yaml"
  cat > "$INSIGHTS_FILE" <<'YAML'
insights:
- id: INS-LEGACY
  ts: "2026-01-01T00:00:00+09:00"
  insight: "legacy body"
  created_at: "2026-01-01T00:00:00+09:00"
  status: done
  resolved_at: "2026-01-02T00:00:00+09:00"
- id: INS-VALID
  ts: "2026-01-03T00:00:00+09:00"
  insight: "valid body"
  status: resolved
  resolved_reason: "implemented"
  action_artifact: "commit=abc"
  resolved_at: "2026-01-04T00:00:00+09:00"
YAML
}

@test "migration restores evidence-less done only and preserves non-state fields exactly" {
  before_hash="$(python3 - "$INSIGHTS_FILE" <<'PY'
import hashlib, sys, yaml
d=yaml.safe_load(open(sys.argv[1]))['insights'][0]
state={'status','resolved_at','resolved_reason','action_artifact'}
print(hashlib.sha256(repr(sorted((k,v) for k,v in d.items() if k not in state)).encode()).hexdigest())
PY
)"
  run bash "$ROOT/scripts/migrate_legacy_insight_resolutions.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "migrated=1" ]]
  python3 - "$INSIGHTS_FILE" "$before_hash" <<'PY'
import hashlib, sys, yaml
rows={x['id']:x for x in yaml.safe_load(open(sys.argv[1]))['insights']}
legacy=rows['INS-LEGACY']; valid=rows['INS-VALID']
state={'status','resolved_at','resolved_reason','action_artifact'}
after=hashlib.sha256(repr(sorted((k,v) for k,v in legacy.items() if k not in state)).encode()).hexdigest()
assert after == sys.argv[2]
assert legacy['status'] == 'pending'
assert not any(k in legacy for k in ('resolved_at','resolved_reason','action_artifact'))
assert valid['status'] == 'resolved' and valid['action_artifact'] == 'commit=abc'
PY
}
