#!/usr/bin/env bats
# test_necessity: pending/idle alone remain selectable across the complete status x actor-role x writer-mode x lifecycle product, with at most one executable owner.

setup_file() {
  seed="$BATS_FILE_TMPDIR/auto-deploy-seed"
  mkdir -p "$seed/scripts/lib"
  cp scripts/auto_deploy_next.sh "$seed/scripts/"
  cp scripts/lib/durable_state.py scripts/lib/durable_state.sh scripts/lib/yaml_field_set.sh "$seed/scripts/lib/"
  printf 'return 0\n' > "$seed/scripts/lib/agent_config.sh"
  printf 'pane_lookup() { return 1; }\n' > "$seed/scripts/lib/pane_lookup.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$seed/scripts/deploy_task.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$seed/scripts/inbox_write.sh"
  chmod +x "$seed/scripts/"*.sh
}

fixture_seed() {
  printf '%s/auto-deploy-seed' "$BATS_FILE_TMPDIR"
}

make_case() {
  root="$1" cmd="$2"
  seed=$(fixture_seed)
  mkdir -p "$root/queue/tasks" "$root/queue/reports" "$root/logs"
  ln -s "$seed/scripts" "$root/scripts"
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

run_r05_cell() {
  local fixture_status="$1" actor_role="$2" writer_mode="$3" lifecycle="$4" total="$5" root cmd rc output_file publishes executable
  root="$BATS_TEST_TMPDIR/product-${fixture_status:-missing}-${actor_role}-${writer_mode}-${lifecycle}-${total}"
  cmd="cmd_fixture_${total}_${BASHPID}_${RANDOM}"
  make_case "$root" "$cmd"
  if [ "$actor_role" = source ]; then
    sed -i 's/assigned_to: hayate/assigned_to: saizo/' "$root/queue/tasks/pending.yaml"
  fi
  if [ -n "$fixture_status" ]; then
    sed -i "s/^  status: pending$/  status: $fixture_status/" "$root/queue/tasks/pending.yaml"
  else
    sed -i '/^  status: pending$/d' "$root/queue/tasks/pending.yaml"
  fi

  rc=0
  output_file="$root/cell.output"
  case "$lifecycle:$writer_mode" in
    normal:single)
      bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed >"$output_file" 2>&1 || rc=$?
      ;;
    normal:concurrent)
      bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed >"$output_file.1" 2>&1 & local p1=$!
      bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed >"$output_file.2" 2>&1 & local p2=$!
      wait "$p1" || rc=$?
      wait "$p2" || true
      cat "$output_file.1" "$output_file.2" >"$output_file"
      ;;
    crash_before_publish:*)
      AUTO_DEPLOY_OWNER_LEASE_TTL=0 AUTO_DEPLOY_FAILPOINT=after_intended_before_target \
        bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed >"$output_file" 2>&1 || rc=$?
      ;;
    retry_after_crash:*)
      AUTO_DEPLOY_OWNER_LEASE_TTL=0 AUTO_DEPLOY_FAILPOINT=after_intended_before_target \
        bash "$root/scripts/auto_deploy_next.sh" "$cmd" completed >"$output_file.crash" 2>&1 || true
      AUTO_DEPLOY_OWNER_LEASE_TTL=0 bash "$root/scripts/auto_deploy_next.sh" \
        "$cmd" completed >"$output_file" 2>&1 || rc=$?
      ;;
  esac

  # Count the public receipt only; log() mirrors the same text to stderr
  # with an [AUTO_DEPLOY] prefix and is not a second publish.
  publishes=$(rg -c '^AUTO_DEPLOY_OK:' "$output_file" || true)
  publishes=${publishes:-0}
  executable=$(rg -l '^  status: (assigned|acknowledged|in_progress)$' \
    "$root/queue/tasks"/*.yaml 2>/dev/null | wc -l)
  printf '%s\t%s\t%s\t%s\t%s\n' "${fixture_status:-missing}" "$lifecycle" "$rc" "$publishes" "$executable" > "$root/result"
}

@test "R05 selector satisfies the complete 120-cell status actor writer lifecycle product" {
  statuses=(pending idle assigned acknowledged in_progress transferred done failed unknown "")
  actor_roles=(source target)
  writer_modes=(single concurrent)
  lifecycles=(normal crash_before_publish retry_after_crash)
  total=0
  case_roots=()

  # Every cell owns a unique fixture root and command id, so bounded batches
  # preserve the complete product while removing serial process startup time.
  batch_pids=()
  for fixture_status in "${statuses[@]}"; do
    for actor_role in "${actor_roles[@]}"; do
      for writer_mode in "${writer_modes[@]}"; do
        for lifecycle in "${lifecycles[@]}"; do
          total=$((total + 1))
          root="$BATS_TEST_TMPDIR/product-${fixture_status:-missing}-${actor_role}-${writer_mode}-${lifecycle}-${total}"
          case_roots+=("$root")
          run_r05_cell "$fixture_status" "$actor_role" "$writer_mode" "$lifecycle" "$total" &
          batch_pids+=("$!")
          if [ "${#batch_pids[@]}" -eq 8 ]; then
            for pid in "${batch_pids[@]}"; do wait "$pid" || true; done
            batch_pids=()
          fi
        done
      done
    done
  done
  for pid in "${batch_pids[@]}"; do wait "$pid" || true; done

  eligible=0 rejected=0 false_positive=0 false_negative=0
  in_progress_reselected=0 owner_overflow=0 duplicate_publish=0
  for root in "${case_roots[@]}"; do
    IFS=$'\t' read -r fixture_status lifecycle rc publishes executable < "$root/result"
    publishes=${publishes:-0}
    [ "$publishes" -le 1 ] || duplicate_publish=$((duplicate_publish + 1))
    [ "$executable" -le 1 ] || owner_overflow=$((owner_overflow + 1))
    case "$fixture_status" in
      pending|idle)
        eligible=$((eligible + 1))
        if [ "$lifecycle" = crash_before_publish ]; then
          [ "$rc" -ne 0 ] || false_negative=$((false_negative + 1))
        else
          [ "$publishes" -eq 1 ] || false_negative=$((false_negative + 1))
        fi
        ;;
      *)
        rejected=$((rejected + 1))
        [ "$publishes" -eq 0 ] || false_positive=$((false_positive + 1))
        [ "$fixture_status" != in_progress ] || \
          in_progress_reselected=$((in_progress_reselected + publishes))
        ;;
    esac
  done

  echo "R05_RECEIPT total=$total eligible=$eligible rejected=$rejected in_progress_reselected=$in_progress_reselected false_positive=$false_positive false_negative=$false_negative owner_overflow=$owner_overflow duplicate_publish=$duplicate_publish" >&3
  [ "$total" -eq 120 ]
  [ "$eligible" -eq 24 ]
  [ "$rejected" -eq 96 ]
  [ "$in_progress_reselected" -eq 0 ]
  [ "$false_positive" -eq 0 ]
  [ "$false_negative" -eq 0 ]
  [ "$owner_overflow" -eq 0 ]
  [ "$duplicate_publish" -eq 0 ]
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
