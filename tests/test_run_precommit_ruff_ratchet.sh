#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

run_case() {
    local name="$1" baseline="$2" staged="$3" expected="$4"
    local fixture
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/scripts" "$fixture/.venv/bin"
    cp "$ROOT_DIR/scripts/run_precommit_checks.sh" "$fixture/scripts/"
    cat > "$fixture/.venv/bin/ruff" <<'RUFF'
#!/usr/bin/env python3
import json, pathlib, sys

args = sys.argv[1:]
if args[0] == "format":
    raise SystemExit(0)
if args[0] != "check" or "--output-format" not in args:
    print("ratchet JSON mode required", file=sys.stderr)
    raise SystemExit(2)
content = sys.stdin.read()
items = []
for token, code, message in (
    ("OLD", "F401", "old violation"),
    ("NEW", "E999", "new violation"),
):
    for _ in range(content.count(token)):
        items.append({"code": code, "message": message})
json.dump(items, sys.stdout)
raise SystemExit(1 if items else 0)
RUFF
    chmod +x "$fixture/.venv/bin/ruff"
    (
        cd "$fixture"
        git init -q
        git config user.email test@example.com
        git config user.name test
        printf '%s\n' "$baseline" > sample.py
        git add sample.py scripts/run_precommit_checks.sh
        git commit -qm baseline
        printf '%s\n' "$staged" > sample.py
        git add sample.py
        set +e
        output="$(bash scripts/run_precommit_checks.sh 2>&1)"
        rc=$?
        set -e
        if [ "$rc" -eq "$expected" ]; then
            exit 0
        fi
        printf 'case=%s expected=%s actual=%s output=%s\n' "$name" "$expected" "$rc" "$output" >&2
        exit 1
    ) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
    rm -rf "$fixture"
}

run_new_file_case() {
    local fixture
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/scripts" "$fixture/.venv/bin"
    cp "$ROOT_DIR/scripts/run_precommit_checks.sh" "$fixture/scripts/"
    cat > "$fixture/.venv/bin/ruff" <<'RUFF'
#!/usr/bin/env python3
import json, sys
if sys.argv[1] == "format": raise SystemExit(0)
content = sys.stdin.read()
items = [{"code": "E999", "message": "new violation"}] if "NEW" in content else []
json.dump(items, sys.stdout)
raise SystemExit(1 if items else 0)
RUFF
    chmod +x "$fixture/.venv/bin/ruff"
    (
        cd "$fixture"
        git init -q
        git config user.email test@example.com
        git config user.name test
        git add scripts/run_precommit_checks.sh
        git commit -qm baseline
        printf 'NEW\n' > added.py
        git add added.py
        ! bash scripts/run_precommit_checks.sh >/dev/null 2>&1
    ) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
    rm -rf "$fixture"
}

run_case "same debt" "OLD" "OLD" 0
run_case "new regression" "OLD" $'OLD\nNEW' 1
run_case "debt reduction" $'OLD\nOLD' "OLD" 0
run_new_file_case

printf 'PASS=%d FAIL=%d SKIP=0\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
