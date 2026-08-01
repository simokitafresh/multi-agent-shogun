#!/usr/bin/env bats
# test_necessity: an interrupted source-to-target owner transfer must converge to at most one executable owner.

make_case() {
  root="$1" cmd="$2"
  mkdir -p "$root/scripts/lib" "$root/queue/tasks" "$root/queue/reports" "$root/logs"
  cp scripts/auto_deploy_next.sh "$root/scripts/"
  cp scripts/lib/durable_state.py scripts/lib/durable_state.sh scripts/lib/yaml_field_set.sh "$root/scripts/lib/"
  printf 'return 0\n' > "$root/scripts/lib/agent_config.sh"
  printf 'pane_lookup() { return 1; }\n' > "$root/scripts/lib/pane_lookup.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/deploy_task.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/inbox_write.sh"
  chmod +x "$root/scripts/"*.sh
  cat > "$root/queue/tasks/saizo.yaml" <<'YAML'
task:
  task_id: completed
  parent_cmd: cmd_fixture
  status: done
  assigned_to: saizo
  auto_deploy: false
YAML
  cat > "$root/queue/tasks/pending.yaml" <<'YAML'
task:
  task_id: next
  parent_cmd: cmd_fixture
  status: assigned
  blocked_by: [completed]
  assigned_to: hayate
  auto_deploy: true
YAML
  sed -i "s/parent_cmd: cmd_fixture/parent_cmd: $cmd/" "$root/queue/tasks/"*.yaml

}

@test "R03 all owner mutation boundaries converge without lost update or false success" {
  boundaries=(after_intended_before_target after_target_before_pointer after_pointer_before_tombstone after_tombstone_before_activation after_activation_before_published after_published_before_terminal)
  observed=0 lost=0 false_success=0
  for fp in "${boundaries[@]}"; do
    root="$BATS_TEST_TMPDIR/$fp"; cmd="cmd_fixture_${BATS_TEST_NUMBER}_${fp}"
    make_case "$root" "$cmd"
    run env AUTO_DEPLOY_FAILPOINT="$fp" bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
    [ "$status" -ne 0 ]; observed=$((observed + 1))
    executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' "$root/queue/tasks"/*.yaml | wc -l)
    [ "$executable" -le 1 ] || lost=$((lost + 1))
    run bash "$root/scripts/auto_deploy_next.sh" --reconcile-owner-transactions
    [ "$status" -eq 0 ]
    run bash "$root/scripts/auto_deploy_next.sh" --reconcile-owner-transactions
    [ "$status" -eq 0 ]
    if [ "$(awk '/^  status:/{print $2}' "$root/queue/tasks/pending.yaml")" = assigned ]; then
      run bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
      [ "$status" -eq 0 ]
    fi
    executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' "$root/queue/tasks"/*.yaml | wc -l)
    [ "$executable" -eq 1 ] || lost=$((lost + 1))
    state=$(find "$root/logs/durable_state" -path '*/active/*/state.json' -type f | head -1)
    phase=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phase"])' "$state")
    [ "$phase" = terminal ] || false_success=$((false_success + 1))
  done
  [ "$observed" -eq 6 ]
  [ "$lost" -eq 0 ]
  [ "$false_success" -eq 0 ]

  record=$(cat "$state")
  subject=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subject_id"])' "$record")
  fence=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["fence_token"]+1)' "$record")
  run bash "$root/scripts/lib/durable_state.sh" mutate "$root/logs/durable_state/auto_deploy_owner" task_owner "$subject" "$fence" published
  [ "$status" -eq 4 ]
  run rg -n 'auto_deploy_next\.sh" --reconcile-owner-transactions' scripts/ninja_monitor.sh
  [ "$status" -eq 0 ]
}

@test "R03 legacy source mirror writer is absent" {
  run rg -n 'cp "\$TARGET_YAML" "\$TASK_FILE"' scripts/auto_deploy_next.sh
  [ "$status" -eq 1 ]
}
