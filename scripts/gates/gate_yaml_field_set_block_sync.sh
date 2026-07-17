#!/usr/bin/env bash
# Level4 guard for LG047: list block identifiers must stay synchronized across
# every begin_target/is_boundary implementation, and one-line blocks must flush.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${YFS_SYNC_TARGET:-$ROOT_DIR/scripts/lib/yaml_field_set.sh}"

if [ ! -r "$TARGET" ]; then
    echo "BLOCK(LG047): yaml_field_set target is unreadable: $TARGET" >&2
    exit 1
fi

python3 - "$TARGET" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def bodies(name: str) -> list[str]:
    starts = list(re.finditer(rf"function\s+{name}\([^\n]*\)\s*\{{", text))
    result = []
    for start in starts:
        next_function = re.search(r"\nfunction\s+", text[start.end():])
        end = start.end() + next_function.start() if next_function else len(text)
        result.append(text[start.end():end])
    return result

begin_bodies = bodies("begin_target")
boundary_bodies = bodies("is_boundary")
flush_bodies = bodies("flush_block")
if len(begin_bodies) != 3 or len(boundary_bodies) != 3 or len(flush_bodies) != 2:
    raise SystemExit(
        f"BLOCK(LG047): implementation count drift "
        f"begin={len(begin_bodies)} boundary={len(boundary_bodies)} flush={len(flush_bodies)}"
    )

def begin_ids(body: str) -> set[str]:
    found = set()
    for match in re.finditer(r"if\s*\(t\s*~\s*/([^/]+)/\)\s*\{", body):
        tail = body[match.end():match.end() + 500]
        if 'block_kind = "id"' not in tail:
            continue
        keys = re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:\[\[:space:\]\]", match.group(1))
        found.update(keys)
    return found

def boundary_ids(body: str) -> set[str]:
    marker = 'block_kind == "id"'
    pos = body.find(marker)
    if pos < 0:
        return set()
    section = body[pos:pos + 700]
    match = re.search(r"\((?:\?:)?([A-Za-z_][A-Za-z0-9_]*(?:\|[A-Za-z_][A-Za-z0-9_]*)+)\)\s*:", section)
    return set(match.group(1).split("|")) if match else set()

expected = begin_ids(begin_bodies[0])
begin_sets = [begin_ids(body) for body in begin_bodies]
boundary_sets = [boundary_ids(body) for body in boundary_bodies]
if not expected or any(keys != expected for keys in begin_sets + boundary_sets):
    raise SystemExit(
        "BLOCK(LG047): begin_target/is_boundary ID sets differ: "
        f"begin={begin_sets} boundary={boundary_sets}"
    )
PY

mapfile -t block_ids < <(python3 - "$TARGET" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = re.search(r"function\s+begin_target\([^\n]*\)\s*\{(.*?)\nfunction\s+is_boundary", text, re.S).group(1)
for match in re.finditer(r"if\s*\(t\s*~\s*/([^/]+)/\)\s*\{", body):
    if 'block_kind = "id"' not in body[match.end():match.end() + 500]:
        continue
    for key in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:\[\[:space:\]\]", match.group(1)):
        print(key)
PY
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
for key in "${block_ids[@]}"; do
    yaml="$tmp_dir/$key.yaml"
    printf -- '- %s: first\n- %s: second\n  state: keep\n' "$key" "$key" > "$yaml"
    bash "$TARGET" "$yaml" first state added
    python3 - "$yaml" "$key" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
key = sys.argv[2]
assert data == [{key: "first", "state": "added"}, {key: "second", "state": "keep"}], data
PY
done

echo "PASS(LG047): begin/is_boundary/flush synchronized (${#block_ids[@]} block IDs)"
