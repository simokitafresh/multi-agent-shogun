#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMP"
}

decode_fixture() {
    local file="$1"
    local function_name="$2"
    python3 - "$file" "$function_name" <<'PY'
import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
function_name = sys.argv[2]
text = path.read_text()
start_marker = f"{function_name}() {{\n    base64 -d <<'EOF'\n"
end_marker = "\nEOF\n}"
start = text.index(start_marker) + len(start_marker)
end = text.index(end_marker, start)
print(base64.b64decode("".join(text[start:end].split())).decode(), end="")
PY
}

@test "update_consolidated_fixture replaces one embedded base64 fixture from source" {
    cat > "$TEST_TMP/source.bats" <<'EOF'
#!/usr/bin/env bats

@test "new fixture" {
    [ 1 -eq 1 ]
}
EOF

    old_b64="$(printf 'old fixture\n' | base64)"
    cat > "$TEST_TMP/consolidated.bats" <<EOF_OUTER
content_example() {
    base64 -d <<'EOF'
$old_b64
EOF
}
EOF_OUTER

    run python3 "$PROJECT_ROOT/scripts/update_consolidated_fixture.py" \
        --consolidated "$TEST_TMP/consolidated.bats" \
        --function content_example \
        --source "$TEST_TMP/source.bats"
    [ "$status" -eq 0 ]

    run decode_fixture "$TEST_TMP/consolidated.bats" content_example
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$TEST_TMP/source.bats")" ]
}

@test "update_consolidated_fixture fails when function is missing" {
    cat > "$TEST_TMP/source.bats" <<'EOF'
#!/usr/bin/env bats
EOF
    : > "$TEST_TMP/consolidated.bats"

    run python3 "$PROJECT_ROOT/scripts/update_consolidated_fixture.py" \
        --consolidated "$TEST_TMP/consolidated.bats" \
        --function content_missing \
        --source "$TEST_TMP/source.bats"
    [ "$status" -ne 0 ]
    [[ "$output" == *"function not found"* ]]
}
