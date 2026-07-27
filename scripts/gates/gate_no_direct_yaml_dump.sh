#!/usr/bin/env bash
# semantic-links: [[YAML安全書込み]], [[インフラ不変量]]
# Direct yaml.dump/safe_dump in shell-controlled scripts is forbidden.
# Use scripts.lib.yaml_atomic.{atomic_yaml_write,yaml_text} instead.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys

import re

# cmd_karo_hotfix_lesson_impact_yaml_dump: widen vocabulary to aliased imports
# (`import yaml as yaml_module` -> `yaml_module.dump(...)`, `import yaml as
# _yaml_nm` -> `_yaml_nm.dump(...)`). The old literal-substring check
# ("yaml.dump(" / "yaml.safe_dump(") let these through and the family regex
# below is the same pattern 家老/軍師 confirmed matches exactly these two
# real call sites plus the canonical form, without catching unrelated
# json.dump(/pickle.dump( calls (the "yaml" token is required in the
# identifier). fail-open/fail-closed behavior is unchanged: still BLOCK-only,
# still skipped for comments/detector-self-references.
YAML_DUMP_RE = re.compile(r"(yaml[a-zA-Z_]*|[a-zA-Z_]*yaml[a-zA-Z_]*)\.(safe_)?dump\(")

root = Path(sys.argv[1])
violations = []

for path in sorted((root / "scripts").rglob("*.sh")):
    rel = path.relative_to(root)
    if str(rel) == "scripts/gates/gate_no_direct_yaml_dump.sh":
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not YAML_DUMP_RE.search(stripped):
            continue
        if "grep" in stripped or "rg " in stripped or "BLOCK" in stripped or "detected" in stripped:
            continue
        violations.append(f"{rel}:{lineno}: {stripped}")

if violations:
    print("BLOCK: direct yaml.dump/yaml.safe_dump in shell-controlled scripts", file=sys.stderr)
    print("Use scripts.lib.yaml_atomic.atomic_yaml_write or yaml_text.", file=sys.stderr)
    for item in violations:
        print(item, file=sys.stderr)
    sys.exit(1)

print("OK: direct yaml.dump/yaml.safe_dump active hits = 0")
PY
