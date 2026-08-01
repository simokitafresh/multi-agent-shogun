#!/usr/bin/env bats
# test_necessity: both context gates must DEFER only for the exact fresh active owner conjunction and fail closed for every rejected dimension.

setup() {
  CASE_ROOT="$BATS_TEST_TMPDIR/matrix"
  mkdir -p "$CASE_ROOT"
  CONTROL="$BATS_TEST_DIRNAME/../.."
}

make_root() {
  local root="$1"
  mkdir -p "$root/context" "$root/queue/tasks" "$root/scripts/gates" "$root/scripts/lib" "$root/projects/infra" "$root/config" "$root/logs"
  cp "$CONTROL/scripts/gates/gate_lesson_health.sh" "$root/scripts/gates/"
  cp "$CONTROL/scripts/gates/lesson_context_routes.sh" "$root/scripts/gates/"
  cp "$CONTROL/scripts/lib/yaml_field_set.sh" "$root/scripts/lib/"
  printf 'projects:\n  - id: infra\n    status: active\n    context_file: context/infrastructure.md\n' > "$root/config/projects.yaml"
  printf 'ssot_path: %s/projects/infra/lessons.md\n' "$root" > "$root/projects/infra/lessons.yaml"
  : > "$root/projects/infra/lessons.md"
  local n
  for n in 1 2 3 4 5 6; do
    printf -- '- id: L%s\n  when: x\n  how: y\n  origin: "[[x]] -> [[y]] -> [[z]]"\n' "$n" >> "$root/projects/infra/lessons.yaml"
  done
  printf '<!-- last_synced_lesson: L6 -->\n<!-- last_updated: 2026-08-01 -->\nbaseline\n' > "$root/context/infrastructure.md"
  git -C "$root" init -q
  git -C "$root" add .
  git -C "$root" -c user.name=t -c user.email=t@x commit -qm baseline
  BASE="$(git -C "$root" hash-object context/infrastructure.md)"
  printf 'rebuilding without markers\n' > "$root/context/infrastructure.md"
  printf '#!/usr/bin/env bash\nprintf "WARN: context/infrastructure.md stale\\n"\n' > "$root/scripts/check.sh"
  chmod +x "$root/scripts/check.sh"
}

write_owner() {
  local root="$1" status="$2" stamp="$3" path="${4:-context/infrastructure.md}" baseline="${5:-$BASE}" file="${6:-owner.yaml}"
  printf '%s\n' 'task:' "  status: $status" "  planned_paths: [$path]" \
    "  target_path_worktree_blob_at_deploy: $baseline" "  progress_updated_at: '$stamp'" > "$root/queue/tasks/$file"
}

prepare_scenario() {
  local root="$1" scenario="$2"
  make_root "$root"
  local fresh=2026-08-01T11:40:00Z
  case "$scenario" in
    age_n) write_owner "$root" in_progress 2026-08-01T11:40:00Z ;;
    age_n1) write_owner "$root" in_progress 2026-08-01T11:39:59Z ;;
    future_5) write_owner "$root" acknowledged 2026-08-01T12:00:05Z ;;
    future_6) write_owner "$root" in_progress 2026-08-01T12:00:06Z ;;
    naive) write_owner "$root" in_progress 2026-08-01T11:40:00 ;;
    parse_error) write_owner "$root" in_progress not-a-time ;;
    missing) write_owner "$root" in_progress "$fresh"; sed -i '/progress_updated_at/d' "$root/queue/tasks/owner.yaml" ;;
    task_mtime_touch_only) write_owner "$root" in_progress 2026-08-01T11:39:59Z; touch -d 2026-08-01T12:00:00Z "$root/queue/tasks/owner.yaml" ;;
    target_mtime_touch_only) write_owner "$root" in_progress 2026-08-01T11:39:59Z; touch -d 2026-08-01T12:00:00Z "$root/context/infrastructure.md" ;;
    assigned) write_owner "$root" assigned "$fresh" ;;
    clean) git -C "$root" add context/infrastructure.md; git -C "$root" -c user.name=t -c user.email=t@x commit -qm changed; write_owner "$root" in_progress "$fresh" ;;
    same_blob) write_owner "$root" in_progress "$fresh" context/infrastructure.md "$(git -C "$root" hash-object context/infrastructure.md)" ;;
    done) write_owner "$root" done "$fresh" ;;
    failed) write_owner "$root" failed "$fresh" ;;
    unrelated) write_owner "$root" in_progress "$fresh" context/other.md ;;
    malformed) printf 'task: [unterminated\n' > "$root/queue/tasks/owner.yaml" ;;
    unknown) write_owner "$root" mystery "$fresh" ;;
    multiple_owner) write_owner "$root" in_progress "$fresh"; write_owner "$root" acknowledged "$fresh" context/infrastructure.md "$BASE" second.yaml ;;
  esac
}

run_case_gate() {
  local root="$1" gate="$2"
  if [[ "$gate" == lesson ]]; then
    run env ACTIVE_CONTEXT_NOW=2026-08-01T12:00:00Z LESSON_EFFECT_NTFY_ENABLED=0 \
      bash "$root/scripts/gates/gate_lesson_health.sh" infra
  else
    run env CONTEXT_FRESHNESS_ROOT="$root" CONTEXT_FRESHNESS_CHECK_SCRIPT="$root/scripts/check.sh" \
      CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 ACTIVE_CONTEXT_NOW=2026-08-01T12:00:00Z \
      bash "$CONTROL/scripts/gates/gate_context_freshness.sh"
  fi
}

@test "18 scenarios x 2 real gates produce a 36-case fail-closed receipt" {
  local scenarios='age_n age_n1 future_5 future_6 naive parse_error missing task_mtime_touch_only target_mtime_touch_only assigned clean same_blob done failed unrelated malformed unknown multiple_owner'
  local scenario gate root expected observable result cases=0 fp=0 fn=0 fail=0
  for scenario in $scenarios; do
    for gate in lesson freshness; do
      root="$CASE_ROOT/${scenario}_${gate}"
      prepare_scenario "$root" "$scenario"
      if [[ "$gate" == lesson && ( "$scenario" == age_n || "$scenario" == future_5 ) ]]; then
        run env ACTIVE_CONTEXT_NOW=2026-08-01T12:00:00Z bash -c 'source "$1/scripts/lib/yaml_field_set.sh"; active_context_defer_allowed "$1" context/infrastructure.md' _ "$root"
        echo "helper_probe case_id=$scenario exit=$status output=$output" >&3
      fi
      run_case_gate "$root" "$gate"
      expected=reject
      [[ "$scenario" == age_n || "$scenario" == future_5 ]] && expected=defer
      if [[ "$output" == *"DEFER:"* && "$status" -eq 0 ]]; then observable=DEFER; result=$([[ "$expected" == defer ]] && echo PASS || echo FAIL); else observable=$([[ "$gate" == lesson ]] && echo ALERT || echo WARN); result=$([[ "$expected" == reject ]] && echo PASS || echo FAIL); fi
      if [[ "$result" == FAIL ]]; then echo "raw_output=${output//$'\n'/ | }" >&3; fi
      [[ "$expected" == defer && "$observable" != DEFER ]] && fn=$((fn+1))
      [[ "$expected" == reject && "$observable" == DEFER ]] && fp=$((fp+1))
      [[ "$result" == FAIL ]] && fail=$((fail+1))
      cases=$((cases+1))
      echo "case_id=$scenario gate=$gate exit=$status observable=$observable result=$result" >&3
    done
  done
  echo "receipt cases=$cases/36 FP=$fp FN=$fn FAIL=$fail SKIP=0" >&3
  [ "$cases" -eq 36 ]
  [ "$fp" -eq 0 ]
  [ "$fn" -eq 0 ]
  [ "$fail" -eq 0 ]
}

@test "flow-style mixed routes count six consecutive lessons against their routed markers" {
  # regression_justification: sync_lessons.sh emits flow-style YAML, while the
  # existing owner matrix does not exercise routed subdomain marker selection.
  local root="$CASE_ROOT/flow_routes"
  mkdir -p "$root/context" "$root/scripts/gates" "$root/scripts/lib" \
    "$root/projects/dm-signal" "$root/config" "$root/logs" "$root/queue/tasks"
  cp "$CONTROL/scripts/gates/gate_lesson_health.sh" "$root/scripts/gates/"
  cp "$CONTROL/scripts/gates/lesson_context_routes.sh" "$root/scripts/gates/"
  cp "$CONTROL/scripts/lib/yaml_field_set.sh" "$root/scripts/lib/"
  printf 'projects:\n  - id: dm-signal\n    status: active\n    context_file: context/dm-signal.md\n' > "$root/config/projects.yaml"
  printf 'ssot_path: %s/projects/dm-signal/lessons.md\nlessons:\n' "$root" > "$root/projects/dm-signal/lessons.yaml"
  : > "$root/projects/dm-signal/lessons.md"
  printf '%s\n' \
    '- {id: L922, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    '- {id: L923, subdomain: gs, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    '- {id: L924, subdomain: be, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    '- {id: L925, subdomain: fe, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    '- {id: L926, subdomain: fe, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    '- {id: L927, subdomain: fe, when: x, how: y, origin: "[[x]] -> [[y]] -> [[z]]"}' \
    >> "$root/projects/dm-signal/lessons.yaml"
  printf '<!-- last_synced_lesson: L922 -->\n- L922: main\n' > "$root/context/dm-signal.md"
  printf '<!-- last_synced_lesson: L927 -->\n- L925: fe\n- L926: fe\n- L927: fe\n' > "$root/context/dm-signal-frontend.md"
  printf '<!-- last_synced_lesson: L924 -->\n- L923: gs\n- L924: be\n' > "$root/context/dm-signal-ops.md"

  run env LESSON_EFFECT_NTFY_ENABLED=0 bash "$root/scripts/gates/gate_lesson_health.sh" dm-signal
  echo "$output" >&3
  [ "$status" -eq 0 ]
  [[ "$output" == *"未合流0件"* ]]
  [ "$(grep -Ec '^- L92[5-7]: fe$' "$root/context/dm-signal-frontend.md")" -eq 3 ]
  [ "$(grep -Ec '^- L92[3-4]: (gs|be)$' "$root/context/dm-signal-ops.md")" -eq 2 ]

  sed -i 's/last_synced_lesson: L922/last_synced_lesson: L0/' "$root/context/dm-signal.md"
  sed -i 's/last_synced_lesson: L927/last_synced_lesson: L0/' "$root/context/dm-signal-frontend.md"
  sed -i 's/last_synced_lesson: L924/last_synced_lesson: L0/' "$root/context/dm-signal-ops.md"
  run env LESSON_EFFECT_NTFY_ENABLED=0 bash "$root/scripts/gates/gate_lesson_health.sh" dm-signal
  echo "$output" >&3
  [ "$status" -eq 1 ]
  [[ "$output" == *"未合流6件"* ]]
}
