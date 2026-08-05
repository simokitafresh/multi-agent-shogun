#!/usr/bin/env bats
# contract test: canceled/cancelled terminal status compatibility
# test_necessity: 米式canceledと英式cancelledのどちらで書かれても正規archiveへ退避し、
#                 active command queueから除去される不変量を守る。欠落すると終端cmdが累積する。
# regression_justification: 2026-08-06にcanceled 50件が認識されず2,845行まで肥大化した
#                           実事故を、両綴りの実走archiveで固定する。
# origin: [[shogun_to_karo肥大化_20260806]] -> [[canceled_cancelled契約不一致]] -> [[終端status両綴り統一]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$FIX/queue/archive/cmds" "$FIX/queue/archive/reports" \
             "$FIX/queue/reports" "$FIX/queue/tasks" "$FIX/queue/gates" \
             "$FIX/queue/locks" "$FIX/context" "$FIX/config" "$FIX/logs" \
             "$FIX/archive/cmd-chronicle"
    printf 'commands:\n  cmd_us:\n    status: canceled\n  cmd_uk:\n    status: cancelled\n  cmd_live:\n    status: in_progress\n' \
        > "$FIX/queue/shogun_to_karo.yaml"
    printf 'entries: []\n' > "$FIX/queue/completed_changelog.yaml"
    printf '# Dashboard\n' > "$FIX/dashboard.md"
    printf '# Chronicle\n' > "$FIX/context/cmd-chronicle.md"
    printf 'decisions: []\n' > "$FIX/queue/pending_decisions.yaml"
}

@test "archive_completed removes both canceled spellings and preserves active command" {
    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        DEFENSE_OVERHEAD_LEDGER="$FIX/logs/defense_overhead.jsonl" \
        bash "$REPO_ROOT/scripts/archive_completed.sh" 3
    echo "$output"
    [ "$status" -eq 0 ]
    run grep -c '^  cmd_' "$FIX/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    grep -q '^  cmd_live:' "$FIX/queue/shogun_to_karo.yaml"
    ! grep -q '^  cmd_us:' "$FIX/queue/shogun_to_karo.yaml"
    ! grep -q '^  cmd_uk:' "$FIX/queue/shogun_to_karo.yaml"
    [ -f "$FIX/queue/archive/cmds/cmd_us_canceled_$(date +%Y%m%d).yaml" ]
    [ -f "$FIX/queue/archive/cmds/cmd_uk_cancelled_$(date +%Y%m%d).yaml" ]
}

# test_necessity: archive後もstartup、slimming、軍師同期、report通知の各consumerが
# 同じterminal-status契約を共有し、別層でcanceledをactive扱いへ戻さないことを守る。
# regression_justification: archive本体だけ直すと、実際に生成された*_canceled_* archiveを
# 軍師同期が発見できず、startup/slimmingも終端判定を分岐させるため横断契約が必要。
@test "all terminal lifecycle consumers accept both canceled spellings" {
    run grep -F '"canceled", "cancelled"' "$REPO_ROOT/scripts/gates/gate_shogun_startup.sh"
    [ "$status" -eq 0 ]
    run grep -F 'canceled|cancelled' "$REPO_ROOT/scripts/gates/gate_karo_startup.sh"
    [ "$status" -eq 0 ]
    run grep -F '"canceled", "cancelled"' "$REPO_ROOT/scripts/slim_yaml.py"
    [ "$status" -eq 0 ]
    run grep -F '*_canceled_*.yaml' "$REPO_ROOT/scripts/gunshi_gate_sync.sh"
    [ "$status" -eq 0 ]
    run grep -F 'canceled|cancelled' "$REPO_ROOT/scripts/yaml_check_opus.sh"
    [ "$status" -eq 0 ]
    run grep -F '"canceled"' "$REPO_ROOT/scripts/lib/gunshi_notify.sh"
    [ "$status" -eq 0 ]
}
