#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import yaml
frag = yaml.safe_dump({"a": 1})
print(frag)
PY
