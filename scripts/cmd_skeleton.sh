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
#   3. bash scripts/cmd_save.sh --preflight <id> で保存前検証 → bash scripts/cmd_save.sh <id> でdraft→pending昇格 → bash scripts/cmd_delegate.sh cmd_<id> "<msg>"
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
RESERVATION_FILE="${CMD_SKELETON_RESERVATION_FILE:-$PROJECT_DIR/config/cmd_id_reservations.txt}"
RESERVATION_LOCK="${CMD_SKELETON_RESERVATION_LOCK:-${RESERVATION_FILE}.lock}"

TITLE="${1:-FILL_THIS: タイトル(パリティ/新規作成/new_fileの語を含めるな=偽陽性トリガー)}"
PROJECT="${2:-FILL_THIS_project}"

# --- 次cmd_id算出: queue + last_cmd + 明示予約の最大値+1 ---
# archiveは採番の正本にしない: cmd_9997-9999等の帯域外IDが混在し採番が飛ぶ(実測2026-06-10)。
# last_cmdはcmd_save PASS毎に更新される。queueは保存前の手動採番、予約SSOTは設計段階の未来IDをカバー。
# flockを採番から予約追記まで保持し、並行skeletonが同じ番号を返す競合を防ぐ。
mkdir -p "$(dirname "$RESERVATION_FILE")" "$(dirname "$RESERVATION_LOCK")"
exec 9>>"$RESERVATION_LOCK"
flock -x 9
max_id=0
if [[ -f "$QUEUE_FILE" ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]{2}cmd_([0-9]+): ]] || continue
        n="${BASH_REMATCH[1]}"
        (( n > max_id )) && max_id=$n
    done < "$QUEUE_FILE"
fi
if [[ -f "$LAST_CMD_FILE" ]]; then
    IFS= read -r line < "$LAST_CMD_FILE" || line=""
    if [[ "$line" =~ ([0-9]+) ]]; then
        n="${BASH_REMATCH[1]}"
        (( n > max_id )) && max_id=$n
    fi
fi
# 予約形式: cmd_N または cmd_A-cmd_B。コメント/空行は無視する。
if [[ -f "$RESERVATION_FILE" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^cmd_([0-9]+)-cmd_([0-9]+)([[:space:]]|$) ]]; then
            n="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^cmd_([0-9]+)([[:space:]]|$) ]]; then
            n="${BASH_REMATCH[1]}"
        else
            continue
        fi
        (( n > max_id )) && max_id=$n
    done < "$RESERVATION_FILE"
fi
# フォールバック: queue/last_cmd/予約が全て空の環境のみarchiveを参照
if (( max_id == 0 )) && [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    while read -r n; do
        (( n > max_id )) && max_id=$n
    done < <(ls "$ARCHIVE_CMD_DIR" 2>/dev/null | grep -oE '^cmd_[0-9]+' | grep -oE '[0-9]+' || true)
fi
NEXT_ID=$(( max_id + 1 ))
TODAY="$(date +%Y-%m-%d)"
printf 'cmd_%s skeleton %s\n' "$NEXT_ID" "$TODAY" >> "$RESERVATION_FILE"

# --- 雛形出力(stdout=貼付け用YAML。ガイドはFILL_THIS内に埋込み) ---
cat <<SKELETON
  cmd_${NEXT_ID}:
    title: "${TITLE}"
    status: draft
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
      1. FILL_THIS: ステップ数はAC数以下。目視確認/セルフレビュー/自問の語は禁止(BLOCK)。テスト/CI修正ではACに全量実行コマンド+FAIL0/SKIP0+中断再開成果物引継ぎ、本番DB書込みではrestore手順+実行identity+破壊時復元証跡を固定。
      2. FILL_THIS: 日付・数値はq8_why_whatのWHATにも同一表記で書け(片側のみだと数値緩和WARN)
    assumptions:
      claim: "FILL_THIS: 前提とその確認方法+確認日(${TODAY})。未確認の前提を書くな"
      source: "FILL_THIS: 一次情報のパス(コード現物/DB/設計書§)"
      trust: verified
    depends_on: none
    execution_env: "FILL_THIS_or_DELETE: Linux venv必須/RSS計測=/usr/bin/time -v等。不要なら行削除(GS/DB系cmdは必須。origin: cmd_3496 kagemaru PowerShell事故)"
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
5. 保存: bash scripts/cmd_save.sh <id> (PASS時にstatus:draft→pendingへ自動昇格)
6. BLOCK/WARNが出たら: 根本原因をdiagnosisに書き、environment_change: "type=gate|lesson|hook; file=...; pattern=既存文字列" を追記(patternはrg -nFで存在確認)
7. PASS後: bash scripts/cmd_delegate.sh cmd_<id> "<家老への配備メッセージ>" (draft起票→cmd_save PASS→pending昇格→delegate。inbox_write直接のcmd_newはgateがBLOCK)
8. 新規ファイル/ディレクトリを伴うcmdは意図的新設である理由をdiagnosisに書け(new_file WARN対策。無自覚な新設=車輪の再発明検査)
9. 性能ACに合格点(閾値)を書くな(LS053)。構造的二値(プロセス起動O(1)等)+実測値報告+理論限界比で書け。閾値はデータ量変化で無意味化し、到達で最適化が止まる
10. execution_env: GS/DB/本番系cmdでは実行環境制約を明記(Linux venv/RSS計測方法等)。不要なcmdでは行ごと削除。origin: cmd_3496 kagemaru PowerShell経由Windows python事故
10. gate/hook/script修正cmd: q5に実行証拠(コマンド・exit code・出力要点)を必ず記載せよ。grep/コード断片だけは不可(LS063: check_gate_script_execution_evidence)
11. インフラ(gate/hook/daemon/記憶DB/semantic)cmd: q5/q8/originにgit log・教訓・設計意図を明記せよ(check_causal_verification_requirement)
12. 同一BLOCKが3回以上続いたら: quality_gate.nazenaze_root_cause になぜなぜ7回分析を記載せよ(VALID_QG_FIELDSに登録済み)
13. ACフェーズ混在禁止(ac_phase_mixing): 同一AC内に実装キーワード(実装/追加/修正/fix等)と計測/deploy(計測/benchmark/push/deploy等)を共起させるな。分割せよ: AC-impl=「実装+テストPASS+commit」、AC-verify=「計測/CDP確認/deploy」。snake_case変数名・ファイルパスは自動除外されるがAC本文の自然言語キーワードは発火する。他責(FP扱い)で放置するな=洗脳(殿指摘2026-06-26)
14. AC4本以上のcmdはBLOCK率75%(score_matrix実測2026-06-26)。AC4+は分割を最初に検討せよ。1CMD1道具(殿裁定cmd_2316)×AC2-3本が最適帯
15. テスト/CI修正cmdはACに全量実行コマンド・FAIL0・SKIP0・中断再開時の成果物引継ぎを、本番DB書込みcmdはrestore手順・実行identity・破壊時復元証跡を固定せよ。cmd_save.shが不足をBLOCKしgate_fire_logへ記録する。
16. check関数のoriginと防御対象を逆引きするには: docs/research/cmd_save_gate_catalog.md を参照せよ(82check関数の発火origin・防御対象・severity・教訓逆引き一覧。中間レイヤー: 教訓→設計思想カタログ→個別check関数)
GUIDE
