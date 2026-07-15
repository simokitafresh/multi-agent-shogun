#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/queue/archive/cmds" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/scripts/lib"

    ln -sf "$PROJECT_ROOT/scripts/dashboard_auto_section.sh" "$TEST_PROJECT/scripts/dashboard_auto_section.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/agent_config.sh" "$TEST_PROJECT/scripts/lib/agent_config.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/model_family.sh" "$TEST_PROJECT/scripts/lib/model_family.sh"

    cat > "$TEST_PROJECT/scripts/ci_status_check.sh" <<'EOF'
#!/usr/bin/env bash
echo GREEN
EOF
    chmod +x "$TEST_PROJECT/scripts/ci_status_check.sh"

    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
language: ja
cli:
  default: codex
  agents:
    hayate:
      type: codex
      model_name: gpt-test
      role: ninja
      japanese_name: 疾風
    kagemaru:
      type: codex
      model_name: gpt-test
      role: ninja
      japanese_name: 影丸
EOF

    cat > "$TEST_PROJECT/config/cli_profiles.yaml" <<'EOF'
profiles:
  codex:
    display_name: gpt-test
EOF

    : > "$TEST_PROJECT/logs/gate_metrics.log"
    printf '<!-- DASHBOARD_AUTO_START -->\n<!-- DASHBOARD_AUTO_END -->\n<!-- KARO_SECTION_START -->\n' > "$TEST_PROJECT/dashboard.md"
}

@test "idle task with parent_cmd renders idle and active count zero" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  parent_cmd: cmd_999
  status: idle
EOF
    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  parent_cmd: cmd_998
  status: idle
EOF

    run bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"| hayate | gpt-test | idle | — | — |"* ]]
    [[ "$output" == *"| kagemaru | gpt-test | idle | — | — |"* ]]
    [[ "$output" == *"| 稼働忍者 | 0/2 (—) |"* ]]
    [[ "$output" != *"稼働中 | cmd_999"* ]]
    [[ "$output" == *"## 📊 リアルタイム状況 ($(TZ=Asia/Tokyo date +%Y-%m-%d) "* ]]
}

@test "missing DASHBOARD_AUTO_END is repaired before KARO section" {
    cat > "$TEST_PROJECT/dashboard.md" <<'EOF'
<!-- DASHBOARD_AUTO_START -->
stale auto content
<!-- DASHBOAR
<!-- KARO_SECTION_START -->
manual content
EOF
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: idle
EOF
    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: idle
EOF

    run bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh"

    [ "$status" -eq 0 ]
    grep -q '<!-- DASHBOARD_AUTO_END -->' "$TEST_PROJECT/dashboard.md"
    grep -q '<!-- KARO_SECTION_START -->' "$TEST_PROJECT/dashboard.md"
    awk '
        /<!-- DASHBOARD_AUTO_END -->/ { end_line = NR }
        /<!-- KARO_SECTION_START -->/ { karo_line = NR }
        END { exit !(end_line > 0 && karo_line > 0 && end_line < karo_line) }
    ' "$TEST_PROJECT/dashboard.md"
    grep -q '| 稼働忍者 | 0/2 (—) |' "$TEST_PROJECT/dashboard.md"
}

@test "concurrent auto section updates use private candidates and preserve markers" {
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: idle
EOF
    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: idle
EOF

    failures=0
    pids=()
    for round in $(seq 1 20); do
        bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh" >"$BATS_TEST_TMPDIR/a.$round.log" 2>&1 &
        pids+=("$!")
        bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh" >"$BATS_TEST_TMPDIR/b.$round.log" 2>&1 &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done

    [ "$failures" -eq 0 ]
    [ "$(grep -c '^<!-- DASHBOARD_AUTO_START -->$' "$TEST_PROJECT/dashboard.md")" -eq 1 ]
    [ "$(grep -c '^<!-- DASHBOARD_AUTO_END -->$' "$TEST_PROJECT/dashboard.md")" -eq 1 ]
    [ "$(grep -c '^<!-- KARO_SECTION_START -->$' "$TEST_PROJECT/dashboard.md")" -eq 1 ]
    ! grep -Rqs 'No such file or directory' "$BATS_TEST_TMPDIR"/*.log
    [ "$(find "$TEST_PROJECT" -maxdepth 1 -name 'dashboard.md.tmp.*' | wc -l)" -eq 0 ]
}

@test "all dashboard writers share one lock and archive publishes beside dashboard" {
    local archive="$PROJECT_ROOT/scripts/archive_completed.sh"
    local update="$PROJECT_ROOT/scripts/dashboard_update.sh"
    local auto="$PROJECT_ROOT/scripts/dashboard_auto_section.sh"

    run python3 - "$archive" "$update" "$auto" <<'PY'
import pathlib, sys
archive, update, auto = [pathlib.Path(p).read_text() for p in sys.argv[1:]]
assert '/tmp/mas-dashboard.lock' not in archive
assert archive.count('200>"${DASHBOARD}.lock"') >= 2
assert 'mktemp "${DASHBOARD}.archive.XXXXXX"' in archive
assert 'LOCK_FILE="${DASHBOARD}.lock"' in update
assert 'DASHBOARD_LOCK_HELD=1 bash "$SCRIPT_DIR/dashboard_auto_section.sh"' in update
assert 'ERROR: Step 6.5 dashboard_auto_section.sh failed' in update
assert 'exec 200>"${DASHBOARD}.lock"' in auto
print('PASS: canonical lock + same-filesystem atomic publish + fail propagation')
PY
    [ "$status" -eq 0 ]
}
