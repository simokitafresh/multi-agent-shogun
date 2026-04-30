#!/bin/bash
# gate_gunshi_startup.sh — 軍師セッション起動時の全チェックを一括実行
# 目的: /clear後の状態復元に必要な6項目を一括チェック（知性の外部化原則）
# Usage: bash scripts/gates/gate_gunshi_startup.sh
# 参考: gate_karo_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

overall="OK"
alerts=()

echo "=== 軍師起動チェック $(date '+%H:%M:%S') ==="
echo ""

# --- Check 1: deepdive必読ファイル存在確認 + 強制表示 ---
echo "■ deepdive必読ファイル"
REQUIRED_READ="$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md"
if [ -f "$REQUIRED_READ" ]; then
    echo "  OK: $(basename "$REQUIRED_READ") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_why_chain_20260321.md")
    echo "  ALERT: $REQUIRED_READ が存在しない"
fi
echo ""

# Phase逐次読込ガイド（全文一括禁止 — 2026-04-15殿指示）
echo "  ■ Phase逐次読込ガイド（全文一括Read禁止。1 Phaseずつ読み、自問してから次へ）"
if [ -f "$REQUIRED_READ" ]; then
    echo "  $(basename "$REQUIRED_READ"):"
    python3 -c "
import sys
lines = []
with open(sys.argv[1]) as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## Phase'):
            lines.append((i, line.strip().replace('## ', '')))
    total = i
if lines:
    print(f'    前文: Read(offset=1, limit={lines[0][0]-2})')
for j, (start, title) in enumerate(lines):
    end = lines[j+1][0]-1 if j+1 < len(lines) else total
    limit = end - start + 1
    print(f'    {title}: Read(offset={start}, limit={limit})')
" "$REQUIRED_READ"
fi
echo "  ★ 全Phase必読（スキップ禁止）。1 Phaseずつ Read(offset, limit) で読め。各Phase後に1行自問。全文一括禁止。"
echo ""

# --- Check 1.5: 追体験検証Q4 (前セッション出来事注入) ---
_prev_session_summary=$(python3 - "$SCRIPT_DIR/queue/lord_conversation.jsonl" 2>/dev/null <<'PY'
import sys, json
log_file = sys.argv[1]
summary = "(前セッション要約なし)"
try:
    with open(log_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get("direction") == "session_summary":
                    s = entry.get("summary", "").strip()
                    if s:
                        summary = s
            except (json.JSONDecodeError, Exception):
                continue
except (FileNotFoundError, OSError):
    pass
print(summary)
PY
) || _prev_session_summary="(取得失敗)"
echo "■ 追体験検証Q4（CLAUDE.md Step 2.9 — 省略厳禁）"
echo "  Q4: deepdiveのPhase NがPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）"
echo "  [前セッション出来事] ${_prev_session_summary}"
echo "  ※ Q4は前セッションの出来事を手がかりに因果をたどれ。暗記したPhase例を貼るな。"
echo ""

# --- Check 2: inbox未読件数 ---
echo "■ inbox未読"
inbox_file="$SCRIPT_DIR/queue/inbox/gunshi.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(grep -c 'read: false' "$inbox_file" 2>/dev/null) || unread=0
    echo "  未読: ${unread}件"
    if [ "$unread" -gt 0 ]; then
        echo "  → 未読メッセージあり。処理せよ"
    fi
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

# --- Check 2.5: 掲示板未確認 ---
echo "■ 掲示板未確認"
bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
if [ -f "$bulletin_file" ]; then
    bulletin_result=$(python3 - "$bulletin_file" gunshi <<'PY'
import sys, yaml
path, agent = sys.argv[1:3]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
entries = data.get("entries") or []
pending = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    rc = entry.get("requires_confirmation", False)
    if not rc:
        continue
    if isinstance(rc, list) and agent not in rc:
        continue
    if str(entry.get("status", "")).lower() == "closed":
        continue
    confirmed = entry.get("confirmed_by") or []
    if agent in confirmed:
        continue
    text = str(entry.get("content", "")).splitlines()
    head = text[0] if text else ""
    pending.append(f"{entry.get('id', '?')} by {entry.get('posted_by', '?')} — {head[:60]}")
print(len(pending))
for item in pending[:3]:
    print(item)
PY
)
    bulletin_count=$(printf '%s\n' "$bulletin_result" | head -1)
    if [ "${bulletin_count:-0}" -gt 0 ]; then
        echo "  WARN: 未確認掲示板 ${bulletin_count}件"
        printf '%s\n' "$bulletin_result" | tail -n +2 | sed 's/^/    /'
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("掲示板未確認: ${bulletin_count}件")
        fi
    else
        echo "  未確認: 0件"
    fi
else
    echo "  掲示板なし"
fi

# --- Check 3: レビューログ統計 ---
echo "■ レビューログ統計"
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
STATS_FILE="$SCRIPT_DIR/logs/gunshi_stats.yaml"
GP_TRACKER="$SCRIPT_DIR/logs/gunshi_gp_tracker.yaml"
if [ -f "$STATS_FILE" ]; then
    # 統計をgunshi_stats.yamlから抽出
    log_stats=$(awk '
    /^# 累計:/ { sub(/^# /, ""); cum=$0 }
    /^# accuracy公式:/ { sub(/^# /, ""); acc=$0 }
    /^# verdict分布:/ { sub(/^# /, ""); vd=$0 }
    /^# workaround率推移:/ { sub(/^# /, ""); wt=$0 }
    END { printf "%s|%s|%s|%s", cum, acc, vd, wt }
    ' "$STATS_FILE" 2>/dev/null || echo "|||")
    IFS='|' read -r LOG_CUMUL LOG_ACC LOG_VERDICT LOG_WA_TREND <<< "$log_stats"
    [ -n "$LOG_CUMUL" ] && echo "  $LOG_CUMUL"
    [ -n "$LOG_ACC" ] && echo "  $LOG_ACC"
    [ -n "$LOG_VERDICT" ] && echo "  $LOG_VERDICT"
    [ -n "$LOG_WA_TREND" ] && echo "  $LOG_WA_TREND"
else
    echo "  ALERT: gunshi_stats.yaml不在"
    overall="ALERT"
    alerts+=("統計ファイル不在")
fi

echo "■ 観点別集計（Adaptive gating）"
if [ -f "$REVIEW_LOG" ]; then
    category_stats=$(python3 - "$REVIEW_LOG" <<'PY'
import re
import sys

path = sys.argv[1]
catalog = [
    ("assumptions", 10, [r"assumption", r"前提"]),
    ("numbers", 10, [r"number", r"数値", r"再計算", r"分母", r"分子"]),
    ("simulation", 10, [r"simulation", r"時系列", r"依存", r"並列", r"衝突"]),
    ("premortem", 10, [r"premortem", r"失敗", r"failure", r"リスク", r"silent fallback"]),
    ("north_star", 10, [r"north.?star", r"複利", r"品質向上", r"消火"]),
    ("ambiguity", 10, [r"ambiguity", r"曖昧", r"不明瞭"]),
    ("adversarial", 10, [r"adversarial", r"red.?team", r"chaos", r"攻撃"]),
]

entries = []
current = None
capture_field = None
capture_items = None

def flush():
    global current
    if current:
        entries.append(current)
    current = None

with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if re.match(r"^- (cmd_id|id):", line):
            flush()
            current = {"review_type": "", "verdict": "", "finding_categories": [], "text": []}
            capture_field = None
            capture_items = None
        if current is None:
            continue
        current["text"].append(line)
        if re.match(r"^\s{2}review_type:\s*", line):
            current["review_type"] = re.sub(r"^\s{2}review_type:\s*", "", line).strip().strip('"\'')
            capture_field = None
            continue
        if re.match(r"^\s{2}verdict:\s*", line):
            current["verdict"] = re.sub(r"^\s{2}verdict:\s*", "", line).strip().strip('"\'')
            capture_field = None
            continue
        if re.match(r"^\s{2}finding_categories:\s*\[", line):
            values = re.sub(r"^\s{2}finding_categories:\s*\[|\]\s*$", "", line).strip()
            if values:
                current["finding_categories"].extend([v.strip().strip('"\'') for v in values.split(",") if v.strip()])
            capture_field = None
            continue
        if re.match(r"^\s{2}finding_categories:\s*$", line):
            capture_field = "finding_categories"
            continue
        if capture_field == "finding_categories":
            if re.match(r"^\s{4}-\s*", line):
                current["finding_categories"].append(re.sub(r"^\s{4}-\s*", "", line).strip().strip('"\''))
                continue
            capture_field = None

flush()

reviews = [e for e in entries if e["review_type"] in ("draft", "report")]
window = reviews[-10:]
for name, threshold, patterns in catalog:
    hits = 0
    zero_streak = 0
    for entry in window:
        categories = {c.lower() for c in entry["finding_categories"]}
        haystack = "\n".join(entry["text"]).lower()
        matched = name in categories or any(re.search(p, haystack) for p in patterns)
        if matched:
            hits += 1
            zero_streak = 0
        else:
            zero_streak += 1
    print(f"{name}|{hits}|{len(window)}|{zero_streak}|{threshold}")
PY
)
    while IFS='|' read -r cat_name cat_hits cat_total cat_zero cat_threshold; do
        [ -n "$cat_name" ] || continue
        echo "  ${cat_name}: ${cat_hits}/${cat_total}件, zero_streak=${cat_zero}/${cat_threshold}"
        if [ "${cat_total:-0}" -gt 0 ] && [ "${cat_zero:-0}" -ge "${cat_threshold:-0}" ]; then
            echo "    LOW confidence候補: ${cat_name}観点が直近${cat_threshold}件で連続0件"
        fi
    done <<< "$category_stats"
else
    echo "  SKIP: gunshi_review_log.yaml不在"
fi

# 未処理GP(提案)件数
if [ -f "$GP_TRACKER" ]; then
    pending_gp=$(grep -c '^# |.*| pending' "$GP_TRACKER" 2>/dev/null) || pending_gp=0
    if [ "$pending_gp" -gt 0 ]; then
        echo "  未処理GP: ${pending_gp}件"
    fi
fi

# --- Check 4: karo_workarounds傾向（軍師の成績表） ---
echo "■ karo_workarounds傾向（成績表）"
wa_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
if [ -f "$wa_file" ]; then
    wa_result=$(awk '
    /^- (cmd_id|cmd|timestamp):/ {
        n++; wa[n]=0; cat[n]="uncategorized"; rc[n]=""
    }
    /^  workaround:/ {
        v=$2; if (v ~ /true|yes/) wa[n]=1
    }
    /^  category:/ {
        sub(/^  category: */, ""); gsub(/["'"'"']/, ""); cat[n]=$0
    }
    /^  root_cause:/ {
        sub(/^  root_cause: */, ""); gsub(/["'"'"']/, ""); rc[n]=substr($0,1,60)
    }
    END {
        s = (n > 5) ? n-4 : 1; total = n - s + 1
        wc=0; cat_str=""; cause_str=""
        for (i=s; i<=n; i++) {
            if (wa[i]) {
                wc++
                cats[cat[i]]++
                if (rc[i] != "") cause_str = cause_str (cause_str != "" ? " / " : "") rc[i]
            }
        }
        for (c in cats) cat_str = cat_str (cat_str != "" ? ", " : "") c ":" cats[c]
        if (cat_str == "") cat_str = "none"
        if (cause_str == "") cause_str = "none"
        printf "%d|%d|%s|%s\n", wc, total, cat_str, cause_str
    }
    ' "$wa_file" 2>/dev/null || echo "0|0|error|awk error")
    IFS='|' read -r WA_COUNT WA_TOTAL WA_CATS WA_CAUSES <<< "$wa_result"
    echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件"
    if [ "$WA_COUNT" -gt 0 ]; then
        echo "  カテゴリ: ${WA_CATS}"
        echo "  原因: ${WA_CAUSES}"
        echo "  → Step 0 Workaround Pattern Checkで重点確認せよ"
    fi
else
    echo "  karo_workarounds.yaml不在"
fi

# --- Check 4.6: 教訓注入参照率（lesson_impact.tsv） ---
li_file="$SCRIPT_DIR/logs/lesson_impact.tsv"
if [ -f "$li_file" ] && [ "$(wc -l < "$li_file")" -gt 1 ]; then
    echo "■ 教訓注入参照率"
    awk -F'\t' 'NR>1 && $5=="injected" {inj++; if($7=="yes") ref++}
    END {
        rate=(inj>0) ? ref*100/inj : 0
        printf "  注入%d件, 参照%d件, 参照率%.0f%%\n", inj, ref+0, rate
        if (rate < 20) printf "  ★WARN: 参照率20%%未満。task_type設定またはフィルタ精度を確認せよ\n"
    }' "$li_file" 2>/dev/null
fi

# --- Check 4.5: missed_sg傾向（見逃したSG観点の蓄積） ---
echo "■ missed_sg Top3"
if [ -f "$wa_file" ]; then
    missed_sg_lines=$(awk '
    function flush_entry() {
        if (entry_started && is_wa && missed_sg != "") counts[missed_sg]++
    }
    /^- (cmd_id|cmd|timestamp|category):/ {
        flush_entry()
        entry_started=1
        is_wa=0
        missed_sg=""
        next
    }
    /^  workaround:/ {
        v=$2
        if (v ~ /true|yes/) is_wa=1
        next
    }
    /^  missed_sg:/ {
        v=$0
        sub(/^  missed_sg: */, "", v)
        gsub(/["'"'"' ]/, "", v)
        if (v != "" && v != "null" && v != "none") missed_sg=v
        next
    }
    END {
        flush_entry()
        for (sg in counts) print counts[sg] "|" sg
    }
    ' "$wa_file" 2>/dev/null | sort -t'|' -k1,1nr -k2,2 | head -3)
    if [ -n "$missed_sg_lines" ]; then
        while IFS='|' read -r sg_count sg_name; do
            [ -n "$sg_name" ] || continue
            echo "  ${sg_name}: ${sg_count}件"
            if [ "$sg_count" -ge 3 ]; then
                echo "  ALERT: missed_sg ${sg_name} が${sg_count}件蓄積。軍師レビュー観点の構造改善を急げ"
                overall="ALERT"
                alerts+=("missed_sg ${sg_name} が${sg_count}件")
            fi
        done <<< "$missed_sg_lines"
    else
        echo "  missed_sg記録なし"
    fi
else
    echo "  karo_workarounds.yaml不在"
fi

# --- Check 5: lessons_gunshi.yaml存在確認 ---
echo "■ レビュー教訓"
lessons_file="$SCRIPT_DIR/projects/infra/lessons_gunshi.yaml"
if [ -f "$lessons_file" ]; then
    lesson_count=$(grep -c '^- id: ' "$lessons_file" 2>/dev/null) || lesson_count=0
    echo "  OK: lessons_gunshi.yaml (${lesson_count}件)"
else
    echo "  WARN: lessons_gunshi.yaml不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("レビュー教訓不在")
    fi
fi

# --- Check 6: 直近レビュー(未GATE確認)件数 ---
echo "■ GATE未確認レビュー"
if [ -f "$REVIEW_LOG" ]; then
    ungated=$(awk '
    /^- (cmd_id|id):/ {
        if (n > 0 && !has_gate && (rt == "draft" || rt == "report")) count++
        n++; has_gate=0; rt=""
    }
    /^  gate_result:/ {
        v=$0; sub(/^  gate_result: */, "", v); gsub(/["'"'"' ]/, "", v)
        if (v != "" && v != "null" && v != "pending") has_gate=1
    }
    /^  (review_type|type):/ {
        v=$0; sub(/^  (review_type|type): */, "", v); gsub(/["'"'"']/, "", v)
        if (v == "draft" || v == "report") rt=v
    }
    END {
        if (n > 0 && !has_gate && (rt == "draft" || rt == "report")) count++
        print count+0
    }
    ' "$REVIEW_LOG" 2>/dev/null || echo "0")
    if [ "$ungated" -gt 0 ]; then
        # 自動sync実行（gate_result: nullをinbox/archiveから自動更新）
        GATE_SYNC="$SCRIPT_DIR/scripts/gunshi_gate_sync.sh"
        if [ -f "$GATE_SYNC" ]; then
            sync_out=$(bash "$GATE_SYNC" 2>&1) || true
            echo "  自動sync実行: $sync_out"
            # sync後に再計測
            ungated_after=$(awk '
            /^- (cmd_id|id):/ {
                if (n > 0 && !has_gate && (rt == "draft" || rt == "report")) count++
                n++; has_gate=0; rt=""
            }
            /^  gate_result:/ {
                v=$0; sub(/^  gate_result: */, "", v); gsub(/["'"'"' ]/, "", v)
                if (v != "" && v != "null" && v != "pending") has_gate=1
            }
            /^  (review_type|type):/ {
                v=$0; sub(/^  (review_type|type): */, "", v); gsub(/["'"'"']/, "", v)
                if (v == "draft" || v == "report") rt=v
            }
            END {
                if (n > 0 && !has_gate && (rt == "draft" || rt == "report")) count++
                print count+0
            }
            ' "$REVIEW_LOG" 2>/dev/null || echo "0")
            echo "  GATE結果未反映: ${ungated}→${ungated_after}件 (sync後)"
        else
            echo "  GATE結果未反映: ${ungated}件"
            echo "  → scripts/gunshi_gate_sync.sh が不在。手動更新せよ"
        fi
    else
        echo "  GATE結果未反映: 0件"
    fi
else
    echo "  SKIP: レビューログ不在"
fi

# --- Check 7: CS観点チェックリスト(consultation/self_study品質保証) ---
echo "■ CS観点チェックリスト"
cs_gate="$SCRIPT_DIR/scripts/gates/gate_gunshi_cs_checklist.sh"
if [ -f "$cs_gate" ]; then
    cs_result=$(bash "$cs_gate" 2>/dev/null) || true
    cs_exit=$?
    echo "  $cs_result" | head -1
    if [ "$cs_exit" -ne 0 ]; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("CS観点チェックリスト欠落あり")
        echo "  → consultation/self_studyエントリにcs_checklistを追記せよ"
    fi
else
    echo "  SKIP: gate_gunshi_cs_checklist.sh不在"
fi

# --- Check 9: observations必須チェック(draft/reportレビュー深さ保証) ---
echo "■ observations必須チェック"
obs_gate="$SCRIPT_DIR/scripts/gates/gate_gunshi_observations.sh"
if [ -f "$obs_gate" ]; then
    obs_result=$(bash "$obs_gate" 2>/dev/null) || true
    obs_exit=$?
    echo "  $obs_result" | head -1
    if [ "$obs_exit" -ne 0 ]; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("observations欠落あり")
        echo "  → 直近draft/reportレビューにobservationsを追記せよ"
    fi
else
    echo "  SKIP: gate_gunshi_observations.sh不在"
fi

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
echo ""
echo "■ 必読: memory/deepdive_why_chain_20260321.md（知性の外部化原則 全過程）"
echo "■ 必読: logs/gunshi_stats.yaml（accuracy把握）"
echo "■ 必読: projects/infra/lessons_gunshi.yaml（レビュー教訓）"
echo ""
echo "■ ★★★ セッション知見(2026-04-03殿指摘) ★★★"
echo "  共通根因: 「知っている」≠「使っている」"
echo "  穴1: 研究cmdでengine統合を見落とす → SG10(review_logヘッダ)で確認"
echo "  穴2: 参照ドキュメントを読んだつもり → 引用時に定義を1行で明示。書けなければ読み直せ"
echo "  穴3: チェックリスト≠gate → 新SG作成時に「読み飛ばせるか?」自問。YES→gate化提案"
echo "  → 上記がlessons_gunshi.yamlに登録済みか確認せよ。未登録なら家老に催促"

# --- Check 8: idle自走プロンプト ---
echo ""
echo "■ 自走チェック"
if [ "$unread" -eq 0 ]; then
    echo "  inbox未読=0。レビュー依頼なし。"
    echo "  ★★★ idle時自走プロトコルを実行せよ（instructions/gunshi.md参照） ★★★"
    echo "  Step 1: karo_workarounds直近10件分析"
    echo "  Step 2: gunshi_review_log傾向分析"
    echo "  Step 3: 未自動化教訓のgate化"
    echo "  Step 4: CS観点遡及適用"
    echo "  Step 5: パターン発見→因果推論→行動"
    echo "  Step 6: proposed GP即実行（提案は行動ではない。実装して初めて行動）"
    echo "  → 止まるな。1つ完了したら次へ"
fi

# --- Check 9: proposed/pending GP件数（自力実行催促） ---
GP_TRACKER="$SCRIPT_DIR/logs/gunshi_gp_tracker.yaml"
if [ -f "$GP_TRACKER" ]; then
    proposed_count=$(grep -c '| proposed ' "$GP_TRACKER" 2>/dev/null || true)
    proposed_count=${proposed_count:-0}
    pending_count=$(grep -c '| pending ' "$GP_TRACKER" 2>/dev/null || true)
    pending_count=${pending_count:-0}
    actionable=$((proposed_count + pending_count))
    if [ "$actionable" -gt 0 ]; then
        echo ""
        echo "■ GP未実行チェック"
        echo "  proposed: ${proposed_count}件, pending: ${pending_count}件"
        echo "  → 自力実行可能か判定せよ。可能なら即実装+テスト+完了"
        echo "  → 「家老送信=完了」は錯覚。提案は記録であり行動ではない"
        grep -E '\| proposed |\| pending ' "$GP_TRACKER" 2>/dev/null | sed 's/^#/  /' || true
    fi
fi

# --- Check 9.5: 設計書セルフレビュー催促 ---
# docs/research/gunshi_* が直近24h以内に更新されていたら、セルフレビュー3点を表示
recent_designs=$(find "$SCRIPT_DIR/docs/research" /mnt/c/Python_app/DM-signal/docs/research -maxdepth 1 -name "gunshi_*" -mmin -1440 -type f 2>/dev/null | head -5)
if [ -n "$recent_designs" ]; then
    echo ""
    echo "■ 設計書セルフレビュー"
    echo "  直近24h更新の設計書:"
    echo "$recent_designs" | while read -r f; do echo "    $(basename "$f")"; done
    echo "  ★ 保存前セルフレビュー3点を実施したか？"
    echo "    1. 数値検算: 全数値を入力データから再計算(wc -l/head実測)"
    echo "    2. 前提検証: 入力ファイル存在・フォーマット・日付範囲を現物確認"
    echo "    3. 事前検死: 忍者がどこで詰まるか。完了条件・baseline・結果の使い方"
fi

# --- Check 10: 分析結果永続化チェック(GP-165: 自動化×強制) ---
echo ""
echo "■ 分析結果永続化チェック"
# 直近のself_studyエントリにdocs/research/参照があるか確認
# + 直近7日のdocs/research/更新があるか確認
research_dir="$SCRIPT_DIR/docs/research"
if [ -d "$research_dir" ]; then
    recent_research=$(find "$research_dir" -name "*.md" -mtime -7 -type f 2>/dev/null | wc -l)
    echo "  docs/research/ 直近7日更新: ${recent_research}件"
    if [ "$recent_research" -eq 0 ]; then
        echo "  WARN: 直近7日で分析結果の永続化なし"
        echo "  → 分析をinbox_writeで送るだけで終わるな。docs/research/に永続化せよ"
        echo "  → CS4: 気付きをinbox(揮発)に閉じず、永続ドキュメントに変換せよ"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("分析結果永続化なし(7日間)")
    fi
else
    echo "  SKIP: docs/research/不在"
fi

# --- Check 11: 三層学習ループ健全性計測(2026-04-18殿指摘: 環境に埋め込め) ---
# なぜなぜ7回(殿指摘): 累積FAIL数はノイズ含む。FAIL→PASS遷移=免疫が実際に発動した件数
echo ""
echo "■ 三層学習ループ健全性"
_fire_log="$SCRIPT_DIR/logs/gate_fire_log.yaml"
_wa_log="$SCRIPT_DIR/logs/karo_workarounds.yaml"
if [ -f "$_fire_log" ]; then
    # 免疫効果 = 同一ファイルでFAIL後にPASSした件数(gateが止めて忍者が自力修正)
    _healed=$(python3 -c "
import re, sys
lines = open(sys.argv[1]).readlines()
fails = set()
healed = 0
for l in lines:
    m = re.search(r'file: \"([^\"]+)\".*result: (FAIL|PASS)', l)
    if m:
        f, r = m.group(1), m.group(2)
        if r == 'FAIL':
            fails.add(f)
        elif r == 'PASS' and f in fails:
            healed += 1
print(healed)
" "$_fire_log" 2>/dev/null || echo 0)
    _fail_total=$(grep -c 'result: FAIL' "$_fire_log" 2>/dev/null || echo 0)
    # 現存報告のFAIL数(ノイズ除外)
    _fail_live=0
    while IFS= read -r _fl; do
        if [ -f "$_fl" ]; then (( _fail_live++ )) || true; fi
    done < <(grep 'result: FAIL' "$_fire_log" 2>/dev/null | grep -oP '/mnt/c[^"]+' | sort -u)
    echo "  第三層(免疫効果): FAIL→PASS遷移=${_healed}件(gateが止め忍者が自力修正)"
    echo "  第三層(参考): 累積FAIL=${_fail_total}件(うち現存報告=${_fail_live}件。差分=archive済み旧報告ノイズ)"
fi
if [ -f "$_wa_log" ]; then
    _wa_recent=$(tail -50 "$_wa_log" | grep -c 'workaround: true' || true)
    _clean_recent=$(tail -50 "$_wa_log" | grep -c 'workaround: false' || true)
    echo "  第二層(対): 直近WA=${_wa_recent}件 / clean=${_clean_recent}件"
fi
_lessons_count=$(grep -c '^- id: LG' "$SCRIPT_DIR/projects/infra/lessons_gunshi.yaml" 2>/dev/null || echo 0)
_auto_count=$(grep -c 'automated: true' "$SCRIPT_DIR/projects/infra/lessons_gunshi.yaml" 2>/dev/null || echo 0)
echo "  第一層(個): 教訓${_lessons_count}件(automated:${_auto_count}件)"
echo "  ★ FAIL→PASS遷移が免疫の直接計測。累積FAILは旧報告ノイズ含む(なぜなぜ7回, 2026-04-18殿指摘)"
