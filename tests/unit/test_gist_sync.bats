#!/usr/bin/env bats

setup() {
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts" "$ROOT/config" "$ROOT/logs" "$ROOT/bin"
    cp "$BATS_TEST_DIRNAME/../../scripts/gist_sync.sh" "$ROOT/scripts/gist_sync.sh"
    printf '# 🏯 Dashboard\nfixture\n' > "$ROOT/dashboard.md"
    cat > "$ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = auth ]; then exit 0; fi
if [ "$1" = api ]; then printf '%s\n' "$*" >> "$GH_CALLS"; exit 0; fi
exit 1
EOF
    cat > "$ROOT/bin/jq" <<'EOF'
#!/usr/bin/env bash
printf '{}\n'
EOF
    chmod +x "$ROOT/bin/gh" "$ROOT/bin/jq"
    export GH_CALLS="$ROOT/gh_calls"
}

@test "once mode resolves current project and gist URL with one-pass parser" {
    cat > "$ROOT/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    gist_url: "https://gist.github.com/test/0123456789abcdef0123456789abcdef"
current_project: infra
EOF

    run env PATH="$ROOT/bin:$PATH" bash "$ROOT/scripts/gist_sync.sh" --once
    [ "$status" -eq 0 ]
    run grep -F 'gists/0123456789abcdef0123456789abcdef' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -F 'Gist updated successfully (project=infra)' "$ROOT/logs/gist_sync.log"
    [ "$status" -eq 0 ]
}

@test "once mode preserves default gist fallback when project has no URL" {
    cat > "$ROOT/config/projects.yaml" <<'EOF'
current_project: infra
projects:
  - id: infra
EOF

    run env PATH="$ROOT/bin:$PATH" bash "$ROOT/scripts/gist_sync.sh" --once
    [ "$status" -eq 0 ]
    run grep -F 'gists/6eb495d917fb00ba4d4333c237a4ee0c' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "fixed gist argument bypasses project lookup" {
    printf 'not: [valid yaml\n' > "$ROOT/config/projects.yaml"

    run timeout 1 env PATH="$ROOT/bin:$PATH" bash "$ROOT/scripts/gist_sync.sh" fixed123
    # daemon mode is not entered in this fixture; source-level contract verifies bypass.
    # Use a bounded timeout and require the first API-free startup path to avoid mutation.
    [ "$status" -ne 0 ]
    run grep -F 'GIST_ID=fixed123, project=fixed' "$ROOT/logs/gist_sync.log"
    [ "$status" -eq 0 ]
}
