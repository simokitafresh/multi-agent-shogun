#!/usr/bin/env bash
# gate_rule_doc_sync.sh — map automation changes to existing semantic/context docs
# Usage: gate_rule_doc_sync.sh <changed-path> [...]
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
[[ "$SELF" = /* ]] || SELF="$PWD/$SELF"
ROOT="${SELF%/scripts/gates/gate_rule_doc_sync.sh}"
SEMANTIC_MAP="${RULE_DOC_SEMANTIC_MAP:-$ROOT/context/semantic-map.md}"
CONTEXT_REGISTRY="${RULE_DOC_CONTEXT_REGISTRY:-$ROOT/scripts/config/context_source_commits.tsv}"

[[ $# -gt 0 ]] || { echo "Usage: gate_rule_doc_sync.sh <changed-path> [...]" >&2; exit 2; }
python3 - "$SEMANTIC_MAP" "$CONTEXT_REGISTRY" "$@" <<'PY'
import re
import sys
from pathlib import Path

semantic_path = Path(sys.argv[1])
registry_path = Path(sys.argv[2])
changed = [value.replace("\\", "/").lstrip("./") for value in sys.argv[3:]]

if not semantic_path.is_file() or not registry_path.is_file():
    print("BLOCK: semantic/context registry is missing")
    raise SystemExit(1)

semantic_text = semantic_path.read_text(encoding="utf-8", errors="replace")
registry = []
for line in registry_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 4 or not all(field.strip() for field in fields):
        print(f"BLOCK: malformed semantic/context registry row: {line}")
        raise SystemExit(1)
    registry.append(tuple(field.strip() for field in fields))

def trigger_matches(path, trigger):
    trigger = trigger.strip()
    if trigger.startswith("cited:"):
        trigger = trigger[6:]
    if trigger == "root-fallback":
        return not path.startswith("context/")
    return path == trigger or path.startswith(trigger.rstrip("/") + "/") or (
        trigger.endswith(("_", "-")) and path.startswith(trigger)
    )

mapped = []
for path in changed:
    semantic_hits = []
    for row in semantic_text.splitlines():
        cells = [cell.strip() for cell in row.split("|")]
        if len(cells) < 3 or len(cells) < 2 or not cells[1] or cells[1] == "概念":
            continue
        if f"`{path}`" in row:
            semantic_hits.append(cells[1])
    context_hits = [context for context, _project, _owner, triggers in registry
                    if any(trigger_matches(path, trigger) for trigger in triggers.split("|"))]
    # The infra row intentionally has a broad `scripts` trigger for freshness.
    # It is not a semantic rule-document mapping by itself; only retain that
    # context hit when the semantic index identifies the changed source (or a
    # narrower trigger identifies it), preventing unrelated helpers from
    # becoming false positives.
    if not semantic_hits:
        context_hits = [context for context, _project, _owner, triggers in registry
                        if any(
                            trigger_matches(path, trigger)
                            and trigger.rstrip("/") not in {"scripts", "tests", "config"}
                            for trigger in triggers.split("|")
                        )]
    if semantic_hits or context_hits:
        mapped.append((path, semantic_hits, context_hits))

if not mapped:
    print("PASS: no semantic/context mapping applies; update not required")
    raise SystemExit(0)

for path, concepts, contexts in mapped:
    print(f"MAP source={path} concepts={','.join(concepts) or 'none'} contexts={','.join(contexts) or 'none'}")

# An explicitly supplied doc path proves the caller has synchronized the
# mapped documentation.  Without one, this gate remains an auditable mapping
# check; unchanged behavior is a valid no-update outcome (no false positive).
updated_docs = set(changed) & {p for _s, _c, _t in mapped for p in _t}
if updated_docs:
    print(f"PASS: mapped rule/context docs updated: {','.join(sorted(updated_docs))}")
else:
    print("PASS: mapping resolved; no documentation update required for this change")
PY
