#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]] [[cmd起票フロー]]
# ============================================================
# cmd_skeleton.sh — 将軍cmd起票用の完全雛形ジェネレータ
#
# Usage: bash scripts/cmd_skeleton.sh ["タイトル"] [project]
#   → stdoutに次cmd_idで全必須フィールド入りのcmdブロックを出力する
#
# 起票フロー(3ステップ固定):
#   1. bash scripts/cmd_skeleton.sh "タイトル" project   ← 雛形生成
#   2. Edit toolで queue/shogun_to_karo.yaml の commands: 直下に貼り、FILL_THISを全て埋める
#   3. bash scripts/cmd_save.sh --preflight <id> で保存前検証 → bash scripts/cmd_save.sh <id> → PASS後 bash scripts/cmd_delegate.sh cmd_<id> "<msg>"
#
# 起源: 2026-06-10殿指示「性能の劣るLLMでもスムーズにCMD起票できる環境を整えよ」
#   必須フィールド・形式規約を記憶からの作文に頼るとBLOCK往復が増える。
#   雛形が形式を保証し、LLMは内容だけ埋める(HOWを環境へ、WHAT/WHYをLLMへ)。
#   各FILL_THISに形式規約を埋込み、埋める瞬間にルールが見える(受動的知識・判断0回)。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUEUE_FILE="${CMD_SKELETON_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
ARCHIVE_CMD_DIR="${CMD_SKELETON_ARCHIVE_CMD_DIR:-$PROJECT_DIR/queue/archive/cmds}"
LAST_CMD_FILE="${CMD_SKELETON_LAST_CMD_FILE:-$PROJECT_DIR/logs/cmd_save_last_cmd.txt}"

TITLE="${1:-FILL_THIS: タイトル(パリティ/新規作成/new_fileの語を含めるな=偽陽性トリガー)}"
PROJECT="${2:-FILL_THIS_project}"

# --- 次cmd_id算出: queue + last_cmd の最大値+1 ---
# archiveは採番の正本にしない: cmd_9997-9999等の帯域外IDが混在し採番が飛ぶ(実測2026-06-10)。
# last_cmdはcmd_save PASS毎に更新される=連番の正本。queueは保存前の手動採番をカバー。
max_id=0
if [[ -f "$QUEUE_FILE" ]]; then
    while read -r n; do
        (( n > max_id )) && max_id=$n
    done < <(grep -oE '^  cmd_[0-9]+:' "$QUEUE_FILE" 2>/dev/null | grep -oE '[0-9]+' || true)
fi
if [[ -f "$LAST_CMD_FILE" ]]; then
    n="$(grep -oE '[0-9]+' "$LAST_CMD_FILE" 2>/dev/null | head -1 || true)"
    [[ -n "$n" ]] && (( n > max_id )) && max_id=$n
fi
# フォールバック: queue/last_cmdが共に空の環境のみarchiveを参照
if (( max_id == 0 )) && [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    while read -r n; do
        (( n > max_id )) && max_id=$n
    done < <(ls "$ARCHIVE_CMD_DIR" 2>/dev/null | grep -oE '^cmd_[0-9]+' | grep -oE '[0-9]+' || true)
fi
NEXT_ID=$(( max_id + 1 ))
TODAY="$(date +%Y-%m-%d)"

# --- 雛形出力(stdout=貼付け用YAML。ガイドはFILL_THIS内に埋込み) ---
cat <<SKELETON
  cmd_${NEXT_ID}:
    title: "${TITLE}"
    status: pending
    project: ${PROJECT}
    purpose: "FILL_THIS: 殿指示/発端を日付付きで引用し、このcmdが何を達成するか1-3行"
    scope_mode: FULL
    target_path: FILL_THIS_対象ディレクトリまたはファイルのフルパス
    acceptance_criteria:
      AC1:
        description: "FILL_THIS: 成果物+確認方法を1文に(『〜し、〜で確認する』形式。確認なきACはWARN)"
        binary_check: "FILL_THIS: yes/noで判定できる問い"
      AC2:
        description: "FILL_THIS: AC数はcommandステップ数以上にせよ(不足はBLOCK)。不要なら行ごと削除"
        binary_check: "FILL_THIS"
    command: |
      1. FILL_THIS: ステップ数はAC数以下。目視確認/セルフレビュー/自問の語は禁止(BLOCK)。
      2. FILL_THIS: 日付・数値はq8_why_whatのWHATにも同一表記で書け(片側のみだと数値緩和WARN)
    assumptions:
      claim: "FILL_THIS: 前提とその確認方法+確認日(${TODAY})。未確認の前提を書くな"
      source: "FILL_THIS: 一次情報のパス(コード現物/DB/設計書§)"
      trust: verified
    depends_on: none
    timeout_minutes: 30
    quality_gate:
      q1_firefighting: "FILL_THIS: 消火でなく品質向上である理由"
      q2_learning: "FILL_THIS: 忍者の学習機会を奪わない理由"
      q3_next_quality: "FILL_THIS: 次のcmd品質が上がる理由"
      q4_depth: "FILL_THIS: shallow|medium|deep — 理由(deep/mediumは時間コスト概算WARNが出る)"
      q5_verified_source: "FILL_THIS: code_reading|isolated_test|pipeline_test|production_verified — 何をどう一次確認したか+確認日時(gate/hook/script修正cmdは実行証拠必須: コマンド+exit code+出力要点 LS063)"
      q6_not_hiding: "FILL_THIS: 何も隠していない理由"
      q7_definition_verified: "FILL_THIS: 用語定義の確認内容(確認日: ${TODAY})"
      q8_why_what: "WHY: FILL_THIS / WHAT: FILL_THIS(ACと同じ数値・日付を同一表記で) / WHEN: 今セッション / WHERE: FILL_THIS / WHO: 忍者N名 / HOW: FILL_THIS / 複利: FILL_THIS"
      q9_firefighting_root_cause: "FILL_THIS: 根本対応である理由"
      q10_knowledge_boundary: "FILL_THIS: 検証済み空間の境界+スコープ外の明示"
      q11_not_already_done: "FILL_THIS: rg/grepコマンド+件数(例: rg -c 'X' context/cmd-chronicle.md → 0件)+semantic_search.sh実行結果。証跡なしはBLOCK"
      q_ambiguity: "FILL_THIS: 曖昧さの有無と解消方法"
      q12_lord_30min_cost: "FILL_THIS: yes|no — 殿の判断時間を要するか"
      diagnosis: "BLOCK理由: 該当なし(新規起票) / 対策: FILL_THIS(再BLOCK時は根本原因1行+対策に書換えよ)"
    origin: "[[FILL_THIS発端]] -> [[FILL_THIS原因]] -> [[FILL_THIS結果]]"
SKELETON

# --- ガイド(stderr=YAMLに混入しない) ---
cat >&2 <<'GUIDE'
--- 起票ガイド(雛形はstdout、本ガイドはstderr) ---
1. 上記をEdit toolで queue/shogun_to_karo.yaml の commands: 直下に貼れ(sed/regex直接編集はhookがBLOCK)
2. FILL_THISを全て埋めよ。残存はcmd_save.shがBLOCKする
3. 起票前に必ず: bash scripts/semantic_search.sh "<cmd主題>" (q11に結果を記載)
4. 事前検証: bash scripts/cmd_save.sh --preflight <id> (累計記録/履歴/通知/自動補完の書込みなし)
5. 保存: bash scripts/cmd_save.sh <id>
6. BLOCK/WARNが出たら: 根本原因をdiagnosisに書き、environment_change: "type=gate|lesson|hook; file=...; pattern=既存文字列" を追記(patternはrg -nFで存在確認)
7. PASS後: bash scripts/cmd_delegate.sh cmd_<id> "<家老への配備メッセージ>" (inbox_write直接のcmd_newはgateがBLOCK)
8. 新規ファイル/ディレクトリを伴うcmdは意図的新設である理由をdiagnosisに書け(new_file WARN対策。無自覚な新設=車輪の再発明検査)
9. 性能ACに合格点(閾値)を書くな(LS053)。構造的二値(プロセス起動O(1)等)+実測値報告+理論限界比で書け。閾値はデータ量変化で無意味化し、到達で最適化が止まる
10. gate/hook/script修正cmd: q5に実行証拠(コマンド・exit code・出力要点)を必ず記載せよ。grep/コード断片だけは不可(LS063: check_gate_script_execution_evidence)
11. インフラ(gate/hook/daemon/記憶DB/semantic)cmd: q5/q8/originにgit log・教訓・設計意図を明記せよ(check_causal_verification_requirement)
12. 同一BLOCKが3回以上続いたら: quality_gate.nazenaze_root_cause になぜなぜ7回分析を記載せよ(VALID_QG_FIELDSに登録済み)
GUIDE
