#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "bloom routing: local pool keeps codex and claude ninja sets distinct" {
    run python3 - <<'PY'
import os
import yaml
from pathlib import Path

root = Path(os.environ["PROJECT_ROOT"])
with open(root / "config/settings.yaml", encoding="utf-8") as fh:
    settings = yaml.safe_load(fh) or {}

agents = (settings.get("cli") or {}).get("agents") or {}
assert len(agents) > 0, "No agents defined in settings.yaml"

codex = sorted(name for name, cfg in agents.items() if isinstance(cfg, dict) and cfg.get("type") == "codex")
claude = sorted(name for name, cfg in agents.items() if not (isinstance(cfg, dict) and cfg.get("type") == "codex"))

# codex + claude must cover all agents (no overlap, no gap)
assert sorted(codex + claude) == sorted(agents.keys()), f"Sets don't cover all agents: codex={codex}, claude={claude}, all={sorted(agents.keys())}"
# Each agent belongs to exactly one set
assert len(codex) + len(claude) == len(agents), f"Overlap detected: codex={codex}, claude={claude}"
print("ok")
PY
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
