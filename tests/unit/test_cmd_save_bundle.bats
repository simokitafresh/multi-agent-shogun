#!/usr/bin/env bats
# test_cmd_save_bundle.bats — バンドル検出テスト
# environment_change: バンドル誤検出3回繰返し修正のテスト不足を塞ぐ

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC" ] || return 1
    eval "$(sed -n '/^collect_primary_cmd_targets()/,/^}/p' "$SRC")"
    export -f collect_primary_cmd_targets
}

@test "BDL-T001: assumptions内パスはバンドル対象外" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "強化 — cmd_save.sh修正"
    target_path: /mnt/c/tools/multi-agent-shogun/scripts/cmd_save.sh
    command: |
      Check 20の閾値変更
    assumptions:
      - claim: "Check 20が既にある"
        source: "scripts/cmd_save.sh L1553確認済み"
        trust: verified
      - claim: "前提崩壊が最多パターン"
        source: "scripts/inbox_write.sh参照"
        trust: verified
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -le 1 ]
}

@test "BDL-T002: command内3パスは検出される" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "修正 — 3スクリプト一括修正"
    command: |
      scripts/inbox_write.sh と scripts/cmd_save.sh と scripts/ninja_done.sh を修正
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -ge 3 ]
}

@test "BDL-T003: diagnosis内パスはバンドル対象外" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "強化 — 単一修正"
    target_path: /mnt/c/tools/multi-agent-shogun/scripts/cmd_save.sh
    command: |
      修正する
    diagnosis: "BLOCK理由: scripts/cmd_save.shのパス検出 対策: scripts/inbox_write.shを参照して修正"
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -le 1 ]
}
