#!/usr/bin/env bats

# test_necessity: CDP transport, DOM observation, and persisted artifact are
# distinct evidence states; only the final state may be a successful command.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  FIXTURE_DIR="$BATS_TEST_TMPDIR/cdp-evidence"
  mkdir -p "$FIXTURE_DIR"
  python3 - "$FIXTURE_DIR/receipt.json" <<'PY'
import json, sys, time
path = sys.argv[1]
now = int(time.time())
json.dump({
    "receipt_id": "fixture-receipt",
    "issuer": "cdp_session_foundation",
    "consumer": "inspection",
    "issued_at": now - 1,
    "expires_at": now + 300,
    "endpoint": "http://127.0.0.1:9222",
    "capabilities": ["transport"],
}, open(path, "w"), sort_keys=True)
PY
}

@test "three evidence fixtures classify exclusively and baseline delta is numeric" {
  cli=(python3 "$ROOT/scripts/cdp/cdp_evidence_status.py" --receipt "$FIXTURE_DIR/receipt.json")

  run "${cli[@]}"
  [ "$status" -eq 10 ]
  [ "$output" = "transport_only" ]

  printf '%s\n' '{"observed": true, "value": "Dashboard"}' > "$FIXTURE_DIR/dom.json"
  run "${cli[@]}" --dom-evidence "$FIXTURE_DIR/dom.json"
  [ "$status" -eq 11 ]
  [ "$output" = "dom_observed" ]

  printf 'screenshot-bytes\n' > "$FIXTURE_DIR/artifact.txt"
  run "${cli[@]}" --dom-evidence "$FIXTURE_DIR/dom.json" --artifact "$FIXTURE_DIR/artifact.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_complete" ]

  run python3 - "$ROOT/scripts/cdp/cdp_evidence_status.py" "$FIXTURE_DIR" <<'PY'
import subprocess, sys
from pathlib import Path

cli, fixture_dir = sys.argv[1:]
base = [sys.executable, cli, "--receipt", str(Path(fixture_dir) / "receipt.json")]
results = []
for extra in ([], ["--dom-evidence", str(Path(fixture_dir) / "dom.json")],
              ["--dom-evidence", str(Path(fixture_dir) / "dom.json"),
               "--artifact", str(Path(fixture_dir) / "artifact.txt")]):
    completed = subprocess.run(base + extra, text=True, capture_output=True)
    results.append(completed.stdout.strip())
assert results == ["transport_only", "dom_observed", "artifact_complete"]
print(f"baseline_classifier=0 fixtures=3 classified={len(results)} delta={len(results)}")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "baseline_classifier=0 fixtures=3 classified=3 delta=3" ]
}

@test "normal cdp skill procedure requires terminal artifact state" {
  run python3 - "$ROOT/scripts/cdp/cdp_evidence_status.py" "$ROOT/skills/cdp-browse/SKILL.md" <<'PY'
import sys
from pathlib import Path

cli, skill = sys.argv[1:]
source = Path(skill).read_text(encoding="utf-8")
assert "cdp_evidence_status.py" in source
assert "transport_only" in source and "dom_observed" in source and "artifact_complete" in source
assert "exit 0" in source.lower()
print("skill_connection=present states=3 terminal=artifact_complete")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_complete"* ]]
}
