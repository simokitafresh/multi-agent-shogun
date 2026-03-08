#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "bloom routing: local pool keeps codex and claude ninja sets distinct" {
    run python3 - <<'PY'
import yaml
from pathlib import Path

root = Path(r"/mnt/c/tools/multi-agent-shogun")
with open(root / "config/settings.yaml", encoding="utf-8") as fh:
    settings = yaml.safe_load(fh) or {}

agents = (settings.get("cli") or {}).get("agents") or {}
codex = sorted(name for name, cfg in agents.items() if isinstance(cfg, dict) and cfg.get("type") == "codex")
claude = sorted(name for name, cfg in agents.items() if not (isinstance(cfg, dict) and cfg.get("type") == "codex"))

assert codex == ["hayate", "kirimaru", "saizo", "sasuke"], codex
assert all(name in claude for name in ["hanzo", "kagemaru", "kotaro", "tobisaru"]), claude
print("ok")
PY
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
