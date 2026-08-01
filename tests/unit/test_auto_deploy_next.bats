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
  status: pending
  blocked_by: [completed]
  assigned_to: hayate
  auto_deploy: true
YAML
  sed -i "s/parent_cmd: cmd_fixture/parent_cmd: $cmd/" "$root/queue/tasks/"*.yaml

}

@test "R05 selector admits only pending and idle statuses" {
  statuses=(pending idle assigned acknowledged in_progress transferred done failed mystery "")
  selected=0 rejected=0 false_positive=0 false_negative=0
  for fixture_status in "${statuses[@]}"; do
    root="$BATS_TEST_TMPDIR/status-${fixture_status:-missing}"
    cmd="cmd_fixture_status_${fixture_status:-missing}_${RANDOM}"
    make_case "$root" "$cmd"
    if [ -n "$fixture_status" ]; then
      sed -i "s/^  status: pending$/  status: $fixture_status/" "$root/queue/tasks/pending.yaml"
    else
      sed -i '/^  status: pending$/d' "$root/queue/tasks/pending.yaml"
    fi

    run bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
    case "$fixture_status" in
      pending|idle)
        [ "$status" -eq 0 ] || false_negative=$((false_negative + 1))
        [[ "$output" == *"AUTO_DEPLOY_OK"* ]] || false_negative=$((false_negative + 1))
        selected=$((selected + 1))
        ;;
      done)
        [ "$status" -eq 0 ]
        [[ "$output" == *"AUTO_DEPLOY_DONE"* ]]
        rejected=$((rejected + 1))
        ;;
      *)
        [ "$status" -eq 3 ] || false_positive=$((false_positive + 1))
        [[ "$output" == *"selector rejected"* ]] || false_positive=$((false_positive + 1))
        rejected=$((rejected + 1))
        ;;
    esac
  done
  [ "$selected" -eq 2 ]
  [ "$rejected" -eq 8 ]
  [ "$false_positive" -eq 0 ]
  [ "$false_negative" -eq 0 ]
}

@test "R05 in_progress owner is never selected again" {
  root="$BATS_TEST_TMPDIR/in-progress-reselection"
  cmd="cmd_fixture_in_progress_${RANDOM}"
  make_case "$root" "$cmd"
  sed -i 's/^  status: pending$/  status: in_progress/' "$root/queue/tasks/pending.yaml"

  run bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
  [ "$status" -eq 3 ]
  [[ "$output" == *"next:in_progress"* ]]
  executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' "$root/queue/tasks"/*.yaml | wc -l)
  [ "$executable" -eq 1 ]
}

@test "R03 all owner mutation boundaries converge without lost update or false success" {
  boundaries=(after_intended_before_target after_target_before_pointer after_pointer_before_tombstone after_tombstone_before_activation after_activation_before_published after_published_before_terminal)
  observed=0 lost=0 false_success=0
  for fp in "${boundaries[@]}"; do
    root="$BATS_TEST_TMPDIR/$fp"; cmd="cmd_fixture_${BATS_TEST_NUMBER}_${fp}"
    make_case "$root" "$cmd"
    # The separate competing-writer test covers the live-lease barrier. This
    # loop uses an immediately recoverable lease to exercise every crash edge.
    run env AUTO_DEPLOY_OWNER_LEASE_TTL=0 AUTO_DEPLOY_FAILPOINT="$fp" bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
    [ "$status" -ne 0 ]; observed=$((observed + 1))
    executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' "$root/queue/tasks"/*.yaml | wc -l)
    [ "$executable" -le 1 ] || { echo "pre-reconcile boundary=$fp executable=$executable" >&3; lost=$((lost + 1)); }
    run env AUTO_DEPLOY_OWNER_STATE_ROOT="$root/logs/durable_state/auto_deploy_owner" \
      SHOGUN_STATE_DIR="$root/monitor-state" NINJA_MONITOR_STARTUP_RECONCILE_ONLY=1 \
      bash scripts/ninja_monitor.sh
    [ "$status" -eq 0 ]
    run bash "$root/scripts/auto_deploy_next.sh" --reconcile-owner-transactions
    [ "$status" -eq 0 ]
    pending_status=$(awk '/^  status:/{print $2}' "$root/queue/tasks/pending.yaml")
    if [ "$pending_status" = pending ] || [ "$pending_status" = idle ]; then
      run bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
      [ "$status" -eq 0 ]
    fi
    executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' "$root/queue/tasks"/*.yaml | wc -l)
    [ "$executable" -eq 1 ] || { echo "post-reconcile boundary=$fp executable=$executable" >&3; lost=$((lost + 1)); }
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

@test "R03 stale competing writer cannot mutate source or target bytes" {
  root="$BATS_TEST_TMPDIR/competing"; cmd="cmd_fixture_competing_${RANDOM}"
  make_case "$root" "$cmd"
  run env AUTO_DEPLOY_FAILPOINT=after_target_before_tombstone bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed
  [ "$status" -ne 0 ]
  state=$(find "$root/logs/durable_state" -path '*/active/*/state.json' -type f | head -1)
  record=$(cat "$state")
  subject=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subject_id"])' "$record")
  fence=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["fence_token"])' "$record")
  payload=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["payload_hash"])' "$record")
  before=$(sha256sum "$root/queue/tasks/pending.yaml" "$root/queue/tasks/hayate.yaml")

  run bash "$root/scripts/lib/durable_state.sh" begin "$root/logs/durable_state/auto_deploy_owner" task_owner "$subject" competing-writer "$payload" "$payload"
  [ "$status" -eq 0 ]
  run env AUTO_DEPLOY_OWNER_STATE_ROOT="$root/logs/durable_state/auto_deploy_owner" \
    bash "$root/scripts/auto_deploy_next.sh" --finish-owner-transaction "$subject" \
      "$root/queue/tasks/pending.yaml" "$root/queue/tasks/hayate.yaml" "$fence" "$payload"
  [ "$status" -eq 4 ]
  after=$(sha256sum "$root/queue/tasks/pending.yaml" "$root/queue/tasks/hayate.yaml")
  [ "$before" = "$after" ]

  # Real barrier: finisher has passed CAS and owns the lease, but has not
  # reached its first YAML write. A concurrent begin must be rejected.
  root2="$BATS_TEST_TMPDIR/barrier"; cmd2="cmd_fixture_barrier_${RANDOM}"
  make_case "$root2" "$cmd2"
  run env AUTO_DEPLOY_FAILPOINT=after_target_before_tombstone bash "$root2/scripts/auto_deploy_next.sh" "$cmd2" completed
  [ "$status" -ne 0 ]
  state2=$(find "$root2/logs/durable_state" -path '*/active/*/state.json' -type f | head -1)
  record2=$(cat "$state2")
  subject2=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subject_id"])' "$record2")
  fence2=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["fence_token"])' "$record2")
  payload2=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["payload_hash"])' "$record2")
  barrier="$root2/barrier"
  env AUTO_DEPLOY_OWNER_STATE_ROOT="$root2/logs/durable_state/auto_deploy_owner" AUTO_DEPLOY_OWNER_LEASE_TTL=0.2 AUTO_DEPLOY_BARRIER_AFTER_ASSERT="$barrier" \
    bash "$root2/scripts/auto_deploy_next.sh" --finish-owner-transaction "$subject2" "$root2/queue/tasks/pending.yaml" "$root2/queue/tasks/hayate.yaml" "$fence2" "$payload2" &
  finisher=$!
  for _ in {1..200}; do [ -f "$barrier" ] && break; sleep 0.01; done
  [ -f "$barrier" ]
  before2=$(sha256sum "$root2/queue/tasks/pending.yaml" "$root2/queue/tasks/hayate.yaml")
  sleep 0.3
  run bash "$root2/scripts/lib/durable_state.sh" begin "$root2/logs/durable_state/auto_deploy_owner" task_owner "$subject2" competing-barrier "$payload2" "$payload2"
  [ "$status" -eq 0 ]
  after2=$(sha256sum "$root2/queue/tasks/pending.yaml" "$root2/queue/tasks/hayate.yaml")
  [ "$before2" = "$after2" ]
  touch "${barrier}.release"
  set +e
  wait "$finisher"
  finisher_rc=$?
  set -e
  [ "$finisher_rc" -eq 4 ]
  final2=$(sha256sum "$root2/queue/tasks/pending.yaml" "$root2/queue/tasks/hayate.yaml")
  [ "$before2" = "$final2" ]
}

@test "R03 legacy source mirror writer is absent" {
  run rg -n 'cp "\$TARGET_YAML" "\$TASK_FILE"' scripts/auto_deploy_next.sh
  [ "$status" -eq 1 ]
}
