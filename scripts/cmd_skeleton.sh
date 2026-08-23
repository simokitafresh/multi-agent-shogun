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

if [[ "${1:-}" == "--create" ]]; then
    [[ "${2:-}" == "--input" && -n "${3:-}" && $# -eq 3 ]] || {
        echo "Usage: bash scripts/cmd_skeleton.sh --create --input <typed.yaml|json>" >&2
        exit 2
    }
    INPUT_FILE="$3"
    # cmd_4205 RC3 production parity: before/current/mutant=82/82/82;
    # receipt: logs/test_receipts/run_tests_20260801T044447_2247416.json
    LEDGER_FILE="${CMD_SKELETON_LEDGER_FILE:-$PROJECT_DIR/queue/cmd_generation_receipts.jsonl}"
    INVENTORY_FILE="${CMD_SKELETON_INVENTORY_FILE:-$PROJECT_DIR/docs/research/cmd-save-check-inventory-v1.yaml}"
    # Every writer of shogun_to_karo.yaml uses the lock identity derived from
    # that file, never a writer-private lock.
    source "$PROJECT_DIR/scripts/lib/lock_path.sh"
    COMMON_LOCK="$(lock_path "$(realpath -m "$QUEUE_FILE")")"
    mkdir -p "$(dirname "$LEDGER_FILE")" "$(dirname "$COMMON_LOCK")"
    exec 8>>"$COMMON_LOCK"
    flock -x 8
    python3 - "$QUEUE_FILE" "$LEDGER_FILE" "$INVENTORY_FILE" "$INPUT_FILE" <<'PY'
import hashlib, json, os, re, sys, tempfile
from pathlib import Path
import yaml

queue, ledger, inventory, input_path = map(Path, sys.argv[1:])
SCHEMA_VERSION = 1
WRITER_VERSION = "cmd_skeleton-v1"
CRASH_AT = os.environ.get("CMD_SKELETON_CRASH_AT", "")
def crash(point):
    if CRASH_AT == point:
        os._exit(97)

def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(data); fh.flush(); os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def ledger_append(record):
    old = ledger.read_text(encoding="utf-8") if ledger.exists() else ""
    atomic_write(ledger, old + json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")

def load_ledger():
    out = {}
    if ledger.exists():
        for line in ledger.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r=json.loads(line); out[r["identity"]]=r
    return out

def reconcile():
    text=queue.read_text(encoding="utf-8") if queue.exists() else "commands:\n"
    latest=load_ledger()
    changed=False
    for ident, rec in list(latest.items()):
        if rec.get("state") not in ("prepared", "committed"): continue
        pid=rec["reserved_cmd_id"]
        marker=f"  prepared_{pid}: "
        line=next((x for x in text.splitlines() if x.startswith(marker)), None)
        if line:
            obj=json.loads(line[len(marker):])
            if obj.get("generation_receipt",{}).get("identity")==ident:
                if rec.get("state") == "prepared":
                    ledger_append({**rec,"state":"committed"})
                obj["generation_receipt"]["state"]="committed"
                text=text.replace(line, f"  {pid}: "+json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(",",":")),1)
                atomic_write(queue,text if text.endswith("\n") else text+"\n")
                changed=True; continue
        if rec.get("state") == "prepared":
            ledger_append({**rec,"state":"aborted"})
    return changed

reconcile()
try:
    payload=yaml.safe_load(input_path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"BLOCK: typed input parse failed: {exc}")
if not isinstance(payload,dict): raise SystemExit("BLOCK: typed input must be a mapping")
scalar_str=("title","project","purpose","command","depends_on")
for key in scalar_str:
    if not isinstance(payload.get(key),str) or not payload[key].strip():
        raise SystemExit(f"BLOCK: {key} must be a non-empty string")
for key in ("timeout_minutes","estimated_minutes"):
    if not isinstance(payload.get(key),int) or isinstance(payload.get(key),bool) or payload[key] <= 0:
        raise SystemExit(f"BLOCK: {key} must be a positive integer")
acs=payload.get("acceptance_criteria")
if not isinstance(acs,list) or not acs: raise SystemExit("BLOCK: acceptance_criteria must be a non-empty list")
seen=set()
for i,ac in enumerate(acs):
    if not isinstance(ac,dict) or set(("id","description","binary_check"))-set(ac):
        raise SystemExit(f"BLOCK: acceptance_criteria[{i}] requires id/description/binary_check")
    if any(not isinstance(ac[k],str) or not ac[k].strip() for k in ("id","description","binary_check")):
        raise SystemExit(f"BLOCK: acceptance_criteria[{i}] fields must be non-empty strings")
    if ac["id"] in seen: raise SystemExit(f"BLOCK: duplicate AC id: {ac['id']}")
    seen.add(ac["id"])
if not isinstance(payload.get("quality_gate"),dict) or not payload["quality_gate"]:
    raise SystemExit("BLOCK: quality_gate must be a non-empty mapping")

inv=yaml.safe_load(inventory.read_text(encoding="utf-8"))
baseline=inv["baseline_sha"]
text=queue.read_text(encoding="utf-8") if queue.exists() else "commands:\n"
ids=[int(x) for x in re.findall(r'^  (?:prepared_)?cmd_(\d+):',text,re.M)]
reserved=f"cmd_{max(ids,default=0)+1}"
canonical=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(",",":"))
payload_sha=hashlib.sha256(canonical.encode()).hexdigest()
identity_input=json.dumps([SCHEMA_VERSION,reserved,payload_sha,baseline,WRITER_VERSION],separators=(",",":"))
identity=hashlib.sha256(identity_input.encode()).hexdigest()
receipt={"schema_version":SCHEMA_VERSION,"reserved_cmd_id":reserved,"canonical_payload_sha256":payload_sha,
         "baseline_sha":baseline,"writer_version":WRITER_VERSION,"identity":identity,"state":"prepared"}
record={**receipt,"state":"prepared"}
crash("intent_before")
ledger_append(record)
crash("ledger_prepared_after")
entry=dict(payload); entry["status"]="draft"; entry["schema_version"]=SCHEMA_VERSION; entry["generation_receipt"]=receipt
prepared=f"  prepared_{reserved}: "+json.dumps(entry,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n"
atomic_write(queue,(text if text.endswith("\n") else text+"\n")+prepared)
crash("queue_append_after")
crash("ledger_commit_before")
ledger_append({**record,"state":"committed"})
crash("ledger_commit_after")
entry["generation_receipt"]["state"]="committed"
final=f"  {reserved}: "+json.dumps(entry,ensure_ascii=False,sort_keys=True,separators=(",",":"))
qtext=queue.read_text(encoding="utf-8").replace(prepared.rstrip("\n"),final,1)
atomic_write(queue,qtext if qtext.endswith("\n") else qtext+"\n")
print(reserved)
print(identity)
PY
    exit $?
fi

TITLE="${1:-FILL_THIS: タイトル(パリティ/新規作成/new_fileの語を含めるな=偽陽性トリガー)}"
PROJECT="${2:-FILL_THIS_project}"

# オプション風引数(--help等)をタイトル扱いすると採番予約が走り番号を浪費する
# (実測2026-07-24: --helpでcmd_4149が予約された)。予約前にガードする。
if [[ "$TITLE" == -* ]]; then
    sed -n '4,12p' "$0" >&2
    exit 2
fi

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
# archiveは常時参照する(2026-08-23根治: cmd_saveを通らずlast_cmd未更新のままarchiveされた
# cmd_4376をskeletonが再発行し採番衝突した)。帯域外ID(9000以上)は従来どおり除外して
# 「採番が飛ぶ」問題(2026-06-10実測)を再発させない。
if [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    while read -r n; do
        (( n >= 9000 )) && continue
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
    execution_env:
      runtime_constraints: "FILL_THIS_or_DELETE: Linux venv必須/RSS計測=/usr/bin/time -v等。不要ならexecution_env全体を削除"
      long_runtime_reason: "FILL_THIS_if_estimated_minutes_gt_15: 15分超が不可分である具体的理由"
      measured_runtime_sec: 0  # 15分超のみ実測した正数秒へ置換。15分以下は不要な2行を削除
    timeout_minutes: 30
    estimated_minutes: 10  # 正数必須。10分超はsplit_decision、15分超はexecution_env.long_runtime_reason+measured_runtime_secが配備契約で必須
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
17. estimated_minutesは正数必須。10分超はsplit_decision、15分超はexecution_envをmappingにしてlong_runtime_reason+measured_runtime_secを記入せよ(deploy_task.shのTEN_MIN_CONTRACT)
GUIDE
