#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate-meta.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "gate_enforcement_audit: hook登録済みとallowlistを尊重してOK" {
    mkdir -p "$TEST_TMPDIR/.claude" "$TEST_TMPDIR/config" "$TEST_TMPDIR/home/.claude"
    cat > "$TEST_TMPDIR/CLAUDE.md" <<'EOF'
`bash scripts/hooks/auto_a.sh`
`bash scripts/manual/manual_only.sh`
EOF
    cat > "$TEST_TMPDIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {"command": "bash scripts/hooks/auto_a.sh"}
        ]
      }
    ]
  }
}
EOF
    cat > "$TEST_TMPDIR/config/enforcement_audit_allowlist.txt" <<'EOF'
manual_only.sh
EOF

    run env \
        HOME="$TEST_TMPDIR/home" \
        ENFORCEMENT_AUDIT_ROOT="$TEST_TMPDIR" \
        bash "$PROJECT_ROOT/scripts/gates/gate_enforcement_audit.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"意志依存 script 0 本"* ]]
}

@test "gate_enforcement_audit: 未hook scriptをALERTする" {
    mkdir -p "$TEST_TMPDIR/.claude" "$TEST_TMPDIR/config" "$TEST_TMPDIR/home/.claude"
    cat > "$TEST_TMPDIR/CLAUDE.md" <<'EOF'
`bash scripts/hooks/auto_a.sh`
`bash scripts/hooks/manual_b.sh`
EOF
    cat > "$TEST_TMPDIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {"command": "bash scripts/hooks/auto_a.sh"}
        ]
      }
    ]
  }
}
EOF
    : > "$TEST_TMPDIR/config/enforcement_audit_allowlist.txt"

    run env \
        HOME="$TEST_TMPDIR/home" \
        ENFORCEMENT_AUDIT_ROOT="$TEST_TMPDIR" \
        bash "$PROJECT_ROOT/scripts/gates/gate_enforcement_audit.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"scripts/hooks/manual_b.sh"* ]]
    [[ "$output" == *"hooks登録コマンド候補(settings.json追記例)"* ]]
    [[ "$output" == *"python3 - $TEST_TMPDIR/.claude/settings.json <<'PY'"* ]]
    [[ "$output" == *"'bash scripts/hooks/manual_b.sh',"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "gate_wa_data_quality: false WA と duplicate を修復できる" {
    cat > "$TEST_TMPDIR/wa.yaml" <<'EOF'
- cmd_id: cmd_1
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: workaround不要
- cmd_id: cmd_2
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 詳細は十分ある
- cmd_id: cmd_2
  ninja: hayate
  workaround: false
  category: clean
  detail: 正規フロー完了
EOF

    run env WA_FILE="$TEST_TMPDIR/wa.yaml" bash "$PROJECT_ROOT/scripts/gates/gate_wa_data_quality.sh" --fix

    [ "$status" -eq 1 ]
    [[ "$output" == *"FIXED:"* ]]

    run grep -c "cmd_id: cmd_2" "$TEST_TMPDIR/wa.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    run grep -A4 "cmd_id: cmd_1" "$TEST_TMPDIR/wa.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workaround: false"* ]]
    [[ "$output" == *"category: clean"* ]]
}

@test "gate_wa_data_quality: check mode detects issues without rewriting" {
    cat > "$TEST_TMPDIR/wa.yaml" <<'EOF'
- cmd_id: cmd_1
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: workaround不要
- cmd_id: cmd_1
  ninja: hayate
  workaround: false
  category: clean
  detail: 正規フロー完了
EOF

    run env WA_FILE="$TEST_TMPDIR/wa.yaml" bash "$PROJECT_ROOT/scripts/gates/gate_wa_data_quality.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"ISSUES:"* ]]
    [[ "$output" == *"FALSE_WA"* ]]
    [[ "$output" == *"DUPLICATE"* ]]
    [[ "$output" == *"False WAパターン TOP3:"* ]]
    [[ "$output" == *"category=DUPLICATE count=1"* ]]
    [[ "$output" == *"category=FALSE_WA count=1"* ]]
    [[ "$output" == *"command: bash scripts/gates/gate_wa_data_quality.sh --fix"* ]]
    [[ "$output" == *"action: bash scripts/gates/gate_wa_data_quality.sh --fix を実行して自動修復せよ"* ]]

    run grep -c "cmd_id: cmd_1" "$TEST_TMPDIR/wa.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "gate_wa_data_quality: wrapper dict を保ったまま修復する" {
    cat > "$TEST_TMPDIR/wa.yaml" <<'EOF'
version: 1
workarounds:
  - cmd_id: cmd_9
    ninja: hayate
    workaround: true
    category: report_yaml_format
    detail: workaround不要
EOF

    run env WA_FILE="$TEST_TMPDIR/wa.yaml" bash "$PROJECT_ROOT/scripts/gates/gate_wa_data_quality.sh" --fix

    [ "$status" -eq 1 ]
    run sed -n '1,20p' "$TEST_TMPDIR/wa.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'version: 1\nworkarounds:'* ]]
}

@test "gate_context_freshness: WARNのみではntfyせず exit 2" {
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/context"
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'EOF'
#!/usr/bin/env bash
echo "WARN: context/foo.md last_updated stale"
EOF
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$TEST_TMPDIR/ntfy.log"
EOF
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"
    cat > "$TEST_TMPDIR/context/foo.md" <<'EOF'
<!-- last_updated: 2026-04-08 -->
# foo
EOF

    run env \
        TEST_TMPDIR="$TEST_TMPDIR" \
        CONTEXT_FRESHNESS_ROOT="$TEST_TMPDIR" \
        CONTEXT_FRESHNESS_TODAY="2026-04-18" \
        bash "$PROJECT_ROOT/scripts/gates/gate_context_freshness.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: foo.md (10日前更新)"* ]]
    [ ! -f "$TEST_TMPDIR/ntfy.log" ]
}

@test "gate_context_freshness: ALERTではntfyし exit 1" {
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/context"
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'EOF'
#!/usr/bin/env bash
echo "WARN: context/foo.md last_updated stale"
EOF
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$TEST_TMPDIR/ntfy.log"
EOF
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"
    cat > "$TEST_TMPDIR/context/foo.md" <<'EOF'
<!-- last_updated: 2026-04-01 -->
# foo
EOF

    run env \
        TEST_TMPDIR="$TEST_TMPDIR" \
        CONTEXT_FRESHNESS_ROOT="$TEST_TMPDIR" \
        CONTEXT_FRESHNESS_TODAY="2026-04-18" \
        bash "$PROJECT_ROOT/scripts/gates/gate_context_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: foo.md (17日前更新)"* ]]
    run cat "$TEST_TMPDIR/ntfy.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"【将軍】context鮮度ALERT: foo.md(17日)"* ]]
}
