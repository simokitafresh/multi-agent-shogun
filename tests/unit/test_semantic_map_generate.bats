#!/usr/bin/env bats

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_map_generate.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/tasks" "$TEST_TMPDIR/projects/infra" \
        "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/context"
    cp "$BATS_TEST_DIRNAME/../../scripts/semantic_map_generate.sh" "$TEST_TMPDIR/scripts/semantic_map_generate.sh"
    chmod +x "$TEST_TMPDIR/scripts/semantic_map_generate.sh"
    cd "$TEST_TMPDIR"
    git init -q
    git config user.email test@example.invalid
    git config user.name "test"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
}

write_fixture() {
    cat > tasks/lessons.md <<'EOF'
### L001: SSOT origin wins
- **origin**: [[ssot_origin]]
- lesson body
EOF

    cat > projects/infra/lessons.yaml <<'EOF'
lessons:
- id: L001
  origin: '[[committed_project_origin]]'
EOF

    cat > docs/semantic-index/index.md <<'EOF'
## concept_one — Concept One

| 属性 | 値 |
|------|---|
| id | concept_one |
| label | Concept One |
| aliases | one |
| lesson | `L001` SSOT origin wins |
| causal_chain | `[[old_origin]]` (L001) |
EOF
}

@test "semantic_map_generate uses tasks lessons SSOT before dirty project lesson YAML" {
    write_fixture
    git add tasks/lessons.md projects/infra/lessons.yaml docs/semantic-index/index.md
    git commit -q -m "fixture"

    cat > projects/infra/lessons.yaml <<'EOF'
lessons:
- id: L001
  origin: '[[dirty_project_origin]]'
EOF

    run bash scripts/semantic_map_generate.sh
    [ "$status" -eq 0 ]
    [ "$(grep -F -c '[[ssot_origin]]' docs/semantic-index/index.md)" -eq 1 ]
    [ "$(grep -F -c '[[dirty_project_origin]]' docs/semantic-index/index.md)" -eq 0 ]
    [ "$(grep -F -c '[[committed_project_origin]]' docs/semantic-index/index.md)" -eq 0 ]
}

@test "qualified lesson refs resolve exactly while ambiguous bare refs fail closed" {
    cat > tasks/lessons.md <<'EOF'
### L893: infra lesson
- **origin**: [[infra_origin]]
### L001: unique lesson
- **origin**: [[unique_origin]]
EOF
    mkdir -p projects/dm-signal
    cat > projects/dm-signal/lessons.yaml <<'EOF'
lessons:
- id: L893
  origin: '[[dm_origin]]'
EOF
    cat > docs/semantic-index/index.md <<'EOF'
## exact_refs — Exact refs
| id | exact_refs |
| label | Exact refs |
| lesson | `infra:L893` infra title |
| lesson | `dm-signal:L893` dm title |
## ambiguous_bare — Ambiguous bare
| id | ambiguous_bare |
| label | Ambiguous bare |
| lesson | `L893` ambiguous title |
## unique_bare — Unique bare
| id | unique_bare |
| label | Unique bare |
| lesson | `L001` unique title |
EOF
    git add tasks/lessons.md projects/dm-signal/lessons.yaml docs/semantic-index/index.md
    git commit -q -m fixture

    run bash scripts/semantic_map_generate.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"AMBIGUOUS lesson refs skipped: 1"* ]]
    [ "$(grep -F -c '[[infra_origin]]' docs/semantic-index/index.md)" -eq 1 ]
    [ "$(grep -F -c '[[dm_origin]]' docs/semantic-index/index.md)" -eq 1 ]
    [ "$(grep -F -c '[[unique_origin]]' docs/semantic-index/index.md)" -eq 1 ]
    [ "$(awk '/^## ambiguous_bare/{f=1;next}/^## /{f=0}f' docs/semantic-index/index.md | grep -c causal_chain || true)" -eq 0 ]
}

@test "semantic_map_generate does not re-flag a registered file whose row has a trailing description" {
    cp "$BATS_TEST_DIRNAME/../../scripts/insight_write.sh" "$TEST_TMPDIR/scripts/insight_write.sh"
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"
    mkdir -p docs/research
    echo "# already registered" > docs/research/already_registered.md

    cat > docs/semantic-index/index.md <<'EOF'
## concept_one — Concept One

| 属性 | 値 |
|------|---|
| id | concept_one |
| label | Concept One |
| aliases | one |
| file | `docs/research/already_registered.md` — 説明文が末尾に付く既知パターン(cmd_reflux_insight_202607080538_saizo) |
EOF

    git add docs/semantic-index/index.md
    git commit -q -m "fixture"

    run bash scripts/semantic_map_generate.sh
    [ "$status" -eq 0 ]
    if [ -f queue/insights.yaml ]; then
        [ "$(grep -F -c 'docs/research/already_registered.md' queue/insights.yaml)" -eq 0 ]
    fi
}

@test "semantic_map_generate ignores karo worktree assets but retains ordinary new code" {
    write_fixture
    mkdir -p .karo_worktrees/probe scripts queue
    touch .karo_worktrees/probe/transient.sh scripts/ordinary_candidate.sh
    cat > scripts/insight_stub.sh <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> queue/insights.log
EOF
    chmod +x scripts/insight_stub.sh

    run env SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_stub.sh" \
        SEMANTIC_NEW_FILE_LIST=$'.karo_worktrees/probe/transient.sh\nscripts/ordinary_candidate.sh' \
        bash scripts/semantic_map_generate.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"new file semantic insights queued: 1"* ]]
    [ "$(grep -F -c '.karo_worktrees/probe/transient.sh' queue/insights.log || true)" -eq 0 ]
    [ "$(grep -F -c 'scripts/ordinary_candidate.sh' queue/insights.log)" -eq 1 ]
}
