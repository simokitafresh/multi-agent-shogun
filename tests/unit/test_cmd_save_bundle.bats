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

@test "BDL-T002: command内3パスは検出されない" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "修正 — 3スクリプト一括修正"
    command: |
      scripts/inbox_write.sh と scripts/cmd_save.sh と scripts/ninja_done.sh を修正
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 0 ]
}

@test "BDL-T002b: target_path+command併記でもtarget_pathのみを数える" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "修正 — 単一定義の検出"
    purpose: "title/purposeに scripts/ignored.sh があっても無視される"
    target_path: scripts/cmd_save.sh
    command: |
      scripts/inbox_write.sh と scripts/ninja_done.sh を修正
    quality_gate:
      q5_verified_source: "scripts/ignored_q5.sh と scripts/ignored_q5b.sh を確認"
    environment_change: "scripts/ignored_env.sh と scripts/ignored_env2.sh を追加"
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 1 ]
    [[ "$targets" == "scripts/cmd_save.sh" ]]
}

@test "BDL-T002c: target_pathディレクトリ単体はファイル単位カウントしない" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "修正 — scripts配下の単一束"
    target_path: scripts
    command: |
      scripts/cmd_save.sh と scripts/inbox_write.sh を確認
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 0 ]
}

@test "BDL-T002d: target_path複数指定の本来バンドルは別カウント" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "修正 — scriptsとlibの2対象"
    target_path: |
      scripts/cmd_save.sh
      lib/firefighting_keywords.sh
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 2 ]
    [[ "$targets" == *"scripts/cmd_save.sh"* ]]
    [[ "$targets" == *"lib/firefighting_keywords.sh"* ]]
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

@test "BDL-T004: q5/assumptions/environment_change内パスはバンドル対象外" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "強化 — 単一修正"
    purpose: "purpose内の scripts/ignored_purpose.sh は無視"
    target_path: /mnt/c/tools/multi-agent-shogun/scripts/cmd_save.sh
    command: |
      単一ファイル修正を実施
    quality_gate:
      q5_verified_source: "scripts/ignored_q5.sh + scripts/ignored_q5b.sh"
    assumptions:
      - claim: "複数パスを書いても無視"
        source: "scripts/ignored_assumption.sh と scripts/ignored_assumption_b.sh"
        trust: verified
    environment_change: "scripts/ignored_env.sh + scripts/ignored_env_b.sh"
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 1 ]
}

@test "BDL-T005: docs_research起点でoutputs/projects参照してもバンドル対象外" {
    CMD_BLOCK_NC="$(cat <<'YAML'
    title: "文書化 — research bundle false positive防止"
    target_path: docs/research/
    command: |
      outputs/analysis/cmd_2221_after.txt と projects/infra.yaml を参照して追記
YAML
)"
    targets="$(collect_primary_cmd_targets || true)"
    count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    [ "$count" -eq 0 ]
}
