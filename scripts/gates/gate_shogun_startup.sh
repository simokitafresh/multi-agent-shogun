#!/bin/bash
# gate_shogun_startup.sh — 将軍セッション起動時の全チェックを一括実行
# 目的: 3つの個別gateを覚えて実行する「意志依存」を排除（知性の外部化原則 2026-03-21）
# Usage: bash scripts/gates/gate_shogun_startup.sh

set -e

run_gate_shogun_startup() {
local SCRIPT_DIR="${SHOGUN_STARTUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
local GATE_DIR="$SCRIPT_DIR/scripts/gates"
local LIGHT_MODE="${SHOGUN_STARTUP_LIGHTWEIGHT:-0}"

overall="OK"
alerts=()
# ダイジェスト用変数（殿裁定2026-03-24: grepフィルタで情報欠落→想像で埋める問題の根本修正）
_d_insights=0
_d_proposals=0
_d_inbox=0
_d_idle_trigger=""

echo "=== 将軍起動チェック $(date '+%H:%M:%S') ==="
echo ""

# --- Parallel launch: Gate 1, 12, 13 (独立サブスクリプト並列化 cmd_1516) ---
_TMP_G1=$(mktemp) _TMP_G12=$(mktemp) _TMP_G13=$(mktemp) _TMP_G25=$(mktemp) _TMP_UNPUSHED=$(mktemp)
trap 'rm -f "$_TMP_G1" "$_TMP_G12" "$_TMP_G13" "$_TMP_G25" "$_TMP_UNPUSHED"' EXIT
"$GATE_DIR/gate_shogun_memory.sh" > "$_TMP_G1" 2>&1 &
_PID_G1=$!
bash "$GATE_DIR/gate_loop_health.sh" > "$_TMP_G12" 2>&1 &
_PID_G12=$!
bash "$GATE_DIR/gate_lesson_health.sh" > "$_TMP_G13" 2>&1 &
_PID_G13=$!
"$GATE_DIR/gate_knowledge_freshness.sh" > "$_TMP_G25" 2>&1 &
_PID_G25=$!
(cd "$SCRIPT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo "?") > "$_TMP_UNPUSHED" &
_PID_UNPUSHED=$!

# --- Gate 1: Memory健全度 (Step 2.5) ---
echo "■ Memory健全度"
wait $_PID_G1 || true
result1=$(tail -1 "$_TMP_G1")
echo "  $result1"
if echo "$result1" | grep -q "ALERT"; then
    overall="ALERT"
    alerts+=("Memory健全度: ALERT")
fi

# --- Gate 2: p̄鮮度 (Step 2.57) ---
echo "■ p̄鮮度"
result2=$("$GATE_DIR/gate_p_average_freshness.sh" 2>&1 | tail -1)
echo "  $result2"
if echo "$result2" | grep -q "ALERT\|WARN"; then
    if echo "$result2" | grep -q "ALERT"; then
        overall="ALERT"
        alerts+=("p̄鮮度: ALERT")
    elif [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("p̄鮮度: WARN")
    fi
fi

# --- Gate 3: cmd委任状態 (Step 2.6) ---
echo "■ 知識辞書鮮度"
wait $_PID_G25 || true
result2_5=$(grep '^知識鮮度:' "$_TMP_G25" | tail -1)
if [ -z "$result2_5" ]; then
    result2_5=$(tail -1 "$_TMP_G25")
fi
echo "  $result2_5"
knowledge_top3=$(awk '/^■ STALE更新候補 TOP3/{flag=1} flag{print} /^  action:/{flag=0}' "$_TMP_G25")
if [ -n "$knowledge_top3" ]; then
    printf '%s\n' "$knowledge_top3" | sed 's/^/  /'
fi
if echo "$result2_5" | grep -q "ALERT\|WARN"; then
    if echo "$result2_5" | grep -q "ALERT"; then
        overall="ALERT"
        alerts+=("知識辞書鮮度: ALERT")
    elif [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("知識辞書鮮度: WARN")
    fi
fi

# --- Gate 3.5: セマンティクスインデックス鮮度 (cmd_2563) ---
echo "■ セマンティクスインデックス鮮度"
semantic_index="$SCRIPT_DIR/docs/semantic-index/index.md"
if [ -f "$semantic_index" ]; then
    last_mod=$(stat -c %Y "$semantic_index")
    now=$(date +%s)
    age_days=$(( (now - last_mod) / 86400 ))
    if [ "$age_days" -ge 14 ]; then
        echo "  ALERT: セマンティクスインデックスが${age_days}日間未更新"
        overall="ALERT"
        alerts+=("セマンティクスインデックス鮮度: ALERT (${age_days}日)")
    else
        echo "  OK: ${age_days}日前に更新"
    fi
else
    echo "  WARN: docs/semantic-index/index.md 不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
    fi
    alerts+=("セマンティクスインデックス鮮度: index不在")
fi

# --- Gate 3: cmd委任状態 (Step 2.6) ---
echo "■ cmd委任状態"
result3=$("$GATE_DIR/gate_cmd_state.sh" 2>&1 | tail -1)
echo "  $result3"
if echo "$result3" | grep -q "ALERT"; then
    overall="ALERT"
    alerts+=("cmd委任状態: ALERT")
fi

# --- Gate 4: 未読inbox ---
echo "■ inbox未読"
inbox_file="$SCRIPT_DIR/queue/inbox/shogun.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(grep -c 'read: false' "$inbox_file" 2>/dev/null) || unread=0
    _d_inbox=$unread
    echo "  未読: ${unread}件"
    if [ "$unread" -gt 0 ] && [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("inbox未読: ${unread}件")
    fi
else
    echo "  未読: 0件"
fi

# --- Gate 4.1: 未確認GATE CLEAR ---
echo "■ 未確認GATE CLEAR"
if [ -f "$inbox_file" ]; then
    gate_clear_result=$(python3 - "$inbox_file" <<'PY'
import re
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
messages = data.get("messages") or []
pending = []
for msg in messages:
    if not isinstance(msg, dict):
        continue
    if msg.get("read") is not False:
        continue
    if str(msg.get("type", "")).strip() != "gate_clear":
        continue
    content = str(msg.get("content", ""))
    cmd_match = re.search(r"\bcmd_[A-Za-z0-9_-]+\b", content)
    cmd_id = cmd_match.group(0) if cmd_match else "cmd不明"
    pending.append((cmd_id, str(msg.get("id", "?")), str(msg.get("timestamp", "?")), content.splitlines()[0][:80]))
print(len(pending))
for cmd_id, msg_id, ts, head in pending[:10]:
    print(f"{cmd_id}\t{msg_id}\t{ts}\t{head}")
PY
)
    gate_clear_count=$(printf '%s\n' "$gate_clear_result" | head -1)
    if [ "${gate_clear_count:-0}" -gt 0 ]; then
        echo "  WARN: 未確認GATE CLEAR ${gate_clear_count}件"
        echo "  ★ GATE CLEAR後の結果確認・push/次cmd/殿報告はF004 pollingではない。殿の入力を待たず処理せよ。"
        printf '%s\n' "$gate_clear_result" | tail -n +2 | awk -F'\t' '{printf "    %s %s (%s) — %s\n", $1, $2, $3, $4}'
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("未確認GATE CLEAR: ${gate_clear_count}件")
        fi
    else
        echo "  未確認: 0件"
    fi
else
    echo "  未確認: 0件"
fi

# --- Gate 4.5: 掲示板未確認 ---
echo "■ 掲示板未確認"
bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
if [ -f "$bulletin_file" ]; then
    bulletin_result=$(python3 - "$bulletin_file" shogun <<'PY'
import sys, yaml
path, agent = sys.argv[1:3]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
entries = data.get("entries") or []
pending = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    # 自分の投稿はスキップ
    if entry.get("posted_by") == agent:
        continue
    # closed はスキップ
    if str(entry.get("status", "")).lower() == "closed":
        continue
    # 既に確認済みならスキップ
    confirmed = entry.get("confirmed_by") or []
    if agent in confirmed:
        continue
    # 将軍宛: requires_confirmation に含まれる OR posted_by が他者(将軍宛報告チャネル)
    rc = entry.get("requires_confirmation", False)
    is_for_agent = False
    if rc:
        if isinstance(rc, list):
            is_for_agent = agent in rc
        else:
            is_for_agent = True  # requires_confirmation: true = 全員対象
    else:
        # requires_confirmation未設定でも、他者からのopen投稿は将軍の確認対象
        is_for_agent = True
    if not is_for_agent:
        continue
    text = str(entry.get("content", "")).splitlines()
    head = text[0] if text else ""
    pending.append(f"{entry.get('id', '?')} by {entry.get('posted_by', '?')} — {head[:60]}")
print(len(pending))
for item in pending[:5]:
    print(item)
PY
)
    bulletin_count=$(printf '%s\n' "$bulletin_result" | head -1)
    if [ "${bulletin_count:-0}" -gt 0 ]; then
        echo "  WARN: 未確認掲示板 ${bulletin_count}件"
        echo "  ★ 未確認投稿を確認処理せよ。掲示板=将軍宛報告チャネル(殿裁定)"
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

# --- Gate 5: 陣形図鮮度 ---
echo "■ 陣形図鮮度"
snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
if [ -f "$snapshot" ]; then
    IFS=$'\t' read -r snap_time _snapshot_active_cmds _snapshot_total_ninjas _snapshot_idle_or_done <<< "$(awk '
/^# Generated:/ { sub(/^# Generated: /, ""); snap=$0 }
/^ninja\|/ {
    total++
    if ($0 ~ /\|(in_progress|assigned|acknowledged)\|/) active++
    if ($0 ~ /\|(idle|done)\|/) idle_done++
}
END { printf "%s\t%d\t%d\t%d\n", snap, active, total, idle_done }
' "$snapshot")"
    echo "  最終更新: $snap_time"
else
    echo "  WARNING: karo_snapshot.txt不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("陣形図不在")
    fi
fi

# --- Gate 6: 必読ファイル存在チェック ---
echo "■ 必読ファイル"
REQUIRED_READ="$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md"
if [ -f "$REQUIRED_READ" ]; then
    echo "  OK: $(basename "$REQUIRED_READ") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_why_chain_20260321.md")
    echo "  ALERT: $REQUIRED_READ が存在しない"
fi
REQUIRED_READ2="$SCRIPT_DIR/memory/deepdive_causal_tracing_20260415.md"
if [ -f "$REQUIRED_READ2" ]; then
    echo "  OK: $(basename "$REQUIRED_READ2") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_causal_tracing_20260415.md")
    echo "  ALERT: $REQUIRED_READ2 が存在しない"
fi

# Phase逐次読込ガイド（全文一括禁止 — 2026-04-15殿指示）
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  ■ Phase逐次読込ガイド: SKIP(lightweight)"
else
echo "  ■ Phase逐次読込ガイド（全文一括Read禁止。1 Phaseずつ読み、自問してから次へ）"
_phase_guides=$(python3 - "$REQUIRED_READ" "$REQUIRED_READ2" <<'PY'
from pathlib import Path
import sys

for path in sys.argv[1:]:
    p = Path(path)
    if not p.is_file():
        continue
    print(f"{p.name}:")
    lines = []
    total = 0
    with p.open(encoding="utf-8", errors="ignore") as fh:
        for total, line in enumerate(fh, 1):
            if line.startswith("## Phase"):
                lines.append((total, line.strip().replace("## ", "")))
    if lines:
        print(f"  前文: Read(offset=1, limit={lines[0][0]-2})")
    for idx, (start, title) in enumerate(lines):
        end = lines[idx + 1][0] - 1 if idx + 1 < len(lines) else total
        limit = end - start + 1
        print(f"  {title}: Read(offset={start}, limit={limit})")
PY
)
while IFS= read -r _pg_line; do
    [ -n "$_pg_line" ] || continue
    echo "  $_pg_line"
done <<< "$_phase_guides"
echo "  ★ 全Phase必読（スキップ禁止）。1 Phaseずつ Read(offset, limit) で読め。各Phase後に1行自問。全文一括禁止。"
fi

# --- Gate 6.5: 追体験検証 (deepdive読了後の自問強制) ---
# 結論を知っていることが追体験を殺す(2026-04-07殿指摘)。
# 読んだだけでは不十分。各Phaseを今の自分に重ねて自問したかを検証する。
# gateは補助。追体験が主体。追体験が正しく動けば間違いは自然に避けられる。
if [ "$LIGHT_MODE" = "1" ]; then
echo "■ 追体験検証（CLAUDE.md Step 2.56 — 省略厳禁）"
echo "  SKIP(lightweight)"
else
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

echo "■ 追体験検証（CLAUDE.md Step 2.56 — 省略厳禁）"
echo "  deepdive読了後に以下4問に各1行で回答せよ。回答なしに作業開始するな。"
echo "  Q1: Phase 3「考えて進む×無限ループ」— 今の自分は考えるだけで止まっていないか？止まっているなら何を確認すべきか？"
echo "  Q2: 「行動→即確認」— 今の本番は正常か？前セッション以降に本番に入った変更は何か？その結果を確認したか？想像で答えるな。"
echo "  Q3: 今クリアされても強くてニューゲームできるか？環境に埋め込まれていない学びはないか？"
echo "  Q4: deepdiveのPhase NがPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）"
echo "  [前セッション出来事] ${_prev_session_summary}"
echo "  ※ Q4は前セッションの出来事を手がかりに因果をたどれ。暗記したPhase例を貼るな。"
echo "  ※ 結論(自動化×強制が大事)を書くな。今の自分の具体的状況を書け。"
echo "  ※ reason: 結論を知っていることが追体験を殺す。テキスト処理ではなく自己診断(2026-04-07殿指摘)"
fi

# --- Gate 7: 前セッション裁定の知識還流チェック ---
LORD_INDEX="$SCRIPT_DIR/context/lord-conversation-index.md"
echo "■ 前セッション裁定"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
if [ -f "$LORD_INDEX" ]; then
    ruling_count=$(grep -c "^- " <(sed -n '/殿の直近裁定・方針/,/^## /p' "$LORD_INDEX") 2>/dev/null) || ruling_count=0
    if [ "$ruling_count" -gt 0 ]; then
        echo "  前セッション裁定${ruling_count}件あり。projects/*.yamlへの反映を確認せよ"
    else
        echo "  裁定なし"
    fi
else
    echo "  lord-conversation-index.md不在"
fi
echo "  ⚠ lord_conversationの「未完了」「未実装」は当時の事実。現在も未完了かはls/grepで現物確認せよ(LS080)"
fi

# --- Gate 7.5: 戦局日誌 直近5エントリ ---
# 目的: cmd完了ごとの意図・結果・因果を将軍起動時に自動想起させる(cmd_2648)
echo "■ 戦局日誌 直近5エントリ"
SENKYOKU_LOG="$SCRIPT_DIR/context/senkyoku-log.md"
if [ -f "$SENKYOKU_LOG" ]; then
    _senkyoku_recent=$(awk '
/^- / {
    rows[++n] = $0
}
END {
    start = (n > 5) ? n - 4 : 1
    for (i = start; i <= n; i++) {
        if (rows[i] != "") print rows[i]
    }
}
' "$SENKYOKU_LOG")
    if [ -n "$_senkyoku_recent" ]; then
        while IFS= read -r _senkyoku_line; do
            echo "  $_senkyoku_line"
        done <<< "$_senkyoku_recent"
    else
        echo "  INFO: エントリなし"
    fi
else
    echo "  INFO: context/senkyoku-log.md 不在"
fi

# --- Gate 8: 気づきキュー（自動アーカイブ付き） ---
INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"
INSIGHTS_ARCHIVE="$SCRIPT_DIR/queue/archive/insights_archive.yaml"
echo "■ 気づきキュー"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
if [ -f "$INSIGHTS_FILE" ]; then
    # Auto-archive: done/monitoring/observation/deferred が合計5件以上なら自動アーカイブ
    # 高速パス: grepで先にarchivable件数チェック（閾値未満ならPythonスキップ）
    archivable_count=$(grep -cE 'status: (done|monitoring|observation|deferred)' "$INSIGHTS_FILE" 2>/dev/null) || archivable_count=0
    total_status=$(grep -cE 'status: ' "$INSIGHTS_FILE" 2>/dev/null) || total_status=0
    remaining_count=$((total_status - archivable_count))
    if [ "$archivable_count" -ge 5 ]; then
        # 閾値到達時のみテキストベースでアーカイブ実行（yaml.dump禁止準拠 cmd_training_L4_R7）
        # gawkでinsightsブロックをstatus別に分離→テキスト追記/書戻し
        _ins_tmp_archive=$(mktemp)
        _ins_tmp_remain=$(mktemp)
        _ins_counts=$(gawk -v arc_file="$_ins_tmp_archive" -v rem_file="$_ins_tmp_remain" '
        BEGIN { in_item=0; buf=""; status="" }
        /^insights:/ { next }
        /^- / {
            if (in_item && buf != "") { flush_item() }
            in_item=1; buf=$0; status=""; next
        }
        /^[^ -]/ {
            if (in_item && buf != "") { flush_item() }
            in_item=0; buf=""; next
        }
        in_item {
            buf = buf "\n" $0
            if (/^  status: /) { s=$0; sub(/^  status: /, "", s); status=s }
        }
        function flush_item() {
            if (status == "done" || status == "monitoring" || status == "observation" || status == "deferred") {
                print buf > arc_file; arc++
            } else {
                print buf > rem_file; rem++
            }
        }
        END {
            if (in_item && buf != "") { flush_item() }
            print arc+0, rem+0
        }
        ' "$INSIGHTS_FILE")
        read -r _ins_archived _ins_remaining <<< "$_ins_counts"
        # アーカイブ追記（既存ファイルの末尾に追記。ヘッダなければ追加）
        if [ -s "$_ins_tmp_archive" ]; then
            mkdir -p "$(dirname "$INSIGHTS_ARCHIVE")"
            if [ ! -f "$INSIGHTS_ARCHIVE" ] || [ ! -s "$INSIGHTS_ARCHIVE" ]; then
                echo "insights:" > "$INSIGHTS_ARCHIVE"
            fi
            cat "$_ins_tmp_archive" >> "$INSIGHTS_ARCHIVE"
        fi
        # メインファイル書戻し（残留分のみ）
        {
            echo "insights:"
            if [ -s "$_ins_tmp_remain" ]; then
                cat "$_ins_tmp_remain"
            fi
        } > "${INSIGHTS_FILE}.tmp" && mv "${INSIGHTS_FILE}.tmp" "$INSIGHTS_FILE"
        rm -f "$_ins_tmp_archive" "$_ins_tmp_remain"
        archive_result="ARCHIVED ${_ins_archived}件→insights_archive.yaml, 残${_ins_remaining}件"
    else
        archive_result="アーカイブ対象${archivable_count}件(閾値5未満), pending${remaining_count}件"
    fi
    echo "  $archive_result"

    # Count pending (after potential archive)
    pending_count=$(grep -c "status: pending" "$INSIGHTS_FILE" 2>/dev/null) || pending_count=0
    _d_insights=$pending_count
    if [ "$pending_count" -gt 0 ]; then
        echo "  未処理: ${pending_count}件（idle時に確認推奨）"
    else
        echo "  未処理: 0件"
    fi
    insight_stale_days="${INSIGHT_STALE_DAYS:-7}"
    stale_insights=$(python3 - "$INSIGHTS_FILE" "$insight_stale_days" <<'PY' 2>/dev/null || true
import sys, yaml
from datetime import datetime, timezone, timedelta

path, days_s = sys.argv[1], sys.argv[2]
try:
    days = int(days_s)
except ValueError:
    days = 7
cutoff = datetime.now(timezone.utc) - timedelta(days=days)

def parse_ts(value):
    if not value:
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        text = str(value).strip().strip('"').replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)

with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
items = data.get("insights") or []
rows = []
for item in items:
    if not isinstance(item, dict):
        continue
    if str(item.get("status", "")).strip() != "pending":
        continue
    dt = parse_ts(item.get("ts") or item.get("timestamp"))
    if dt and dt <= cutoff:
        age = (datetime.now(timezone.utc) - dt).days
        rows.append((age, str(item.get("id", "?"))))
if rows:
    print(f"__TOTAL__\t{len(rows)}")
    for age, iid in sorted(rows, reverse=True)[:5]:
        print(f"{iid}:{age}日")
PY
)
    if [ -n "$stale_insights" ]; then
        stale_count=$(printf '%s\n' "$stale_insights" | awk -F'\t' '$1=="__TOTAL__"{print $2; found=1} END{if(!found) print 0}')
        echo "  ALERT: 未消化insights ${stale_count}件が${insight_stale_days}日超過"
        printf '%s\n' "$stale_insights" | grep -v '^__TOTAL__' | sed 's/^/    /'
        overall="ALERT"
        alerts+=("未消化insights滞留: ${stale_count}件/${insight_stale_days}日超")
    fi
else
    echo "  キューなし"
fi
fi

# --- Gate 9: 将軍パフォーマンスフィードバック ---
echo "■ 将軍パフォーマンスフィードバック"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
DESIGN_QUALITY="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
WORKAROUNDS_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"
REWORK_PCT="N/A"
BLOCK_PCT="N/A"
WA_COUNT=0

# 9a: cmd設計品質 (直近10件)
if [ -f "$DESIGN_QUALITY" ]; then
    dq_result=$(awk '
/karo_rework:/ { rw[++n] = ($2 ~ /yes|true/) }
/gate_result:.*BLOCK/ { bl[n] = 1 }
END {
    start = (n > 10) ? n - 9 : 1
    total = n - start + 1
    rc = 0; bc = 0
    for (i = start; i <= n; i++) {
        if (rw[i]) rc++
        if (bl[i]) bc++
    }
    if (total == 0) print "N/A N/A"
    else printf "%d %d\n", int(rc*100/total), int(bc*100/total)
}
' "$DESIGN_QUALITY" 2>/dev/null || echo "N/A N/A")
    read -r REWORK_PCT BLOCK_PCT <<< "$dq_result"
    echo "  直近10件: rework率=${REWORK_PCT}% blocker率=${BLOCK_PCT}%"
else
    echo "  cmd_design_quality.yaml不在"
fi

# 9b: 家老workaround (直近5件)
if [ -f "$WORKAROUNDS_FILE" ]; then
    wa_result=$(awk '
/^- cmd_id:/ { n++; wa[n] = 0; cat[n] = "uncategorized" }
/^  workaround: true/ { wa[n] = 1 }
/^  category:/ { sub(/^  category: /, ""); cat[n] = $0 }
END {
    start = (n > 5) ? n - 4 : 1
    total = n - start + 1
    wc = 0
    for (i = start; i <= n; i++) {
        if (wa[i]) { wc++; cats[cat[i]]++ }
    }
    cat_str = ""
    for (c in cats) {
        if (cat_str != "") cat_str = cat_str ", "
        cat_str = cat_str c ":" cats[c]
    }
    if (cat_str == "") cat_str = "none"
    printf "%d %d %s\n", wc, total, cat_str
}
' "$WORKAROUNDS_FILE" 2>/dev/null || echo "0 0 error")
    read -r WA_COUNT WA_TOTAL WA_CATS <<< "$wa_result"
    echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件 (${WA_CATS})"
else
    echo "  karo_workarounds.yaml不在"
fi

# 9c: 軍師draft RC傾向 (直近20件)
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
REVIEW_LOG_ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
rc_data=$(python3 - "$REVIEW_LOG" "$REVIEW_LOG_ARCHIVE_DIR" 2>/dev/null <<'END_RC_PY'
import sys, os, glob, re

review_log = sys.argv[1]
archive_dir = sys.argv[2]

# データソース: gunshi_review_log.yaml + archive直近2ファイル
sources = []
if os.path.exists(review_log):
    sources.append(review_log)
archives = sorted(glob.glob(os.path.join(archive_dir, "gunshi_review_log*.yaml")))
sources.extend(archives[-2:])

drafts = []
kw_patterns = [
    ('前提崩壊', re.compile(r'前提崩壊|premise', re.I)),
    ('パス誤り', re.compile(r'パス.*誤|誤.*パス|path.*err|wrong.*path', re.I)),
    ('runtime', re.compile(r'runtime', re.I)),
    ('scope', re.compile(r'scope|スコープ', re.I)),
]

for src in sources:
    try:
        with open(src, encoding='utf-8') as f:
            content = f.read()
    except Exception:
        continue
    for m in re.finditer(r'^- cmd_id:.*?(?=^- cmd_id:|\Z)', content, re.MULTILINE | re.DOTALL):
        entry = m.group(0)
        if 'review_type: draft' not in entry:
            continue
        vm = re.search(r'verdict:\s*(\S+)', entry)
        verdict = vm.group(1).strip('"\'') if vm else 'unknown'
        fm = re.search(r'findings_summary:\s*"(.+?)"', entry, re.DOTALL)
        summary = fm.group(1) if fm else ''
        drafts.append((verdict, summary))

drafts = drafts[-20:]
total = len(drafts)
if total == 0:
    print("N/A (データなし)")
    sys.exit(0)

rc_count = sum(1 for v, _ in drafts if v == 'REQUEST_CHANGES')
rc_pct = rc_count * 100 // total

kw_counts = {}
for v, summary in drafts:
    if v != 'REQUEST_CHANGES':
        continue
    for kw, pat in kw_patterns:
        if pat.search(summary):
            kw_counts[kw] = kw_counts.get(kw, 0) + 1

kw_parts = sorted(kw_counts.items(), key=lambda x: -x[1])
kw_str = '  ' + ', '.join(f'{k}: {v}件' for k, v in kw_parts) if kw_parts else ''
print(f"RC={rc_count}/{total} ({rc_pct}%){kw_str}")
END_RC_PY
) || rc_data="N/A (スクリプトエラー)"
echo "  軍師draft RC傾向(直近20件): ${rc_data}"
fi

# --- Gate 10: idle自走トリガー ---
echo "■ idle自走トリガー"
IDLE_TRIGGER="OFF"
if [ -f "$snapshot" ]; then
    active_cmds=${_snapshot_active_cmds:-0}
    total_ninjas=${_snapshot_total_ninjas:-0}
    idle_or_done=${_snapshot_idle_or_done:-0}

    if [ "$active_cmds" -eq 0 ] && [ "$total_ninjas" -gt 0 ] && [ "$idle_or_done" -eq "$total_ninjas" ]; then
        IDLE_TRIGGER="ON"
        echo "  全忍者idle・パイプライン空。idle時自己分析に入れ:"
        echo "  Step 1: insightsキュー消費 (queue/insights.yaml)"
        echo "  Step 2: karo_workarounds直近10件分析"
        echo "  Step 3: cmd_design_quality直近10件分析"
        echo "  Step 4: gunshi_review_log確認"
        echo "  Step 5: パターン発見→why-chain→アクション"
    else
        echo "  稼働中cmd: ${active_cmds}件、idle忍者: ${idle_or_done}/${total_ninjas}"
    fi
else
    echo "  karo_snapshot.txt不在 — 判定不可"
fi

# --- Gate 10.5: idle時BLOCK提案自動化 ---
echo "■ idle時BLOCK提案"
_AUTOFIX_PROPOSAL_GATE="$GATE_DIR/gate_autofix_proposal.sh"
if [ "$IDLE_TRIGGER" = "ON" ]; then
    if [ -x "$_AUTOFIX_PROPOSAL_GATE" ]; then
        _autofix_output=$(bash "$_AUTOFIX_PROPOSAL_GATE" 2>&1 || true)
        if [ -n "$_autofix_output" ]; then
            while IFS= read -r _autofix_line; do
                [ -n "$_autofix_line" ] || continue
                echo "  $_autofix_line"
            done <<< "$_autofix_output"
        else
            echo "  INFO: 出力なし"
        fi
    else
        echo "  INFO: gate_autofix_proposal.sh 未配備"
    fi
else
    echo "  SKIP: active cmdあり"
fi

# --- Gate 11: 未処理PROPOSAL (cmd_1256 + cmd_1261) ---
DASHBOARD="$SCRIPT_DIR/dashboard.md"
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
dash_proposals=0
log_proposals=0

# 11a: ダッシュボードの[PROPOSAL]
if [ -f "$DASHBOARD" ]; then
    IFS=$'\t' read -r dash_proposals completed_gps <<< "$(awk '
BEGIN { dash = 0; done_count = 0 }
/\[PROPOSAL\]/ { dash++ }
/完了:.*GP-/ {
    while (match($0, /GP-[0-9]+[a-z]*/)) {
        done[++done_count] = substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
    }
}
END {
    printf "%d\t", dash
    for (i = 1; i <= done_count; i++) {
        printf "%s%s", (i > 1 ? "|" : ""), done[i]
    }
    printf "\n"
}' "$DASHBOARD")"
fi

# 11b: gunshi_review_log.yamlのproposals status=pending (completed_gps除外)
pending_gp_ids=""
if [ -f "$REVIEW_LOG" ]; then
    raw_pending=$(awk '/^[[:space:]]*- id: GP-/{id=$NF} /^[[:space:]]*status: pending/{if(id!="") print id; id=""}' "$REVIEW_LOG" 2>/dev/null)
    if [ -n "$completed_gps" ] && [ -n "$raw_pending" ]; then
        filtered=$(echo "$raw_pending" | grep -vE "^($completed_gps)$")
    else
        filtered=$raw_pending
    fi
    pending_gp_ids=$(echo "$filtered" | grep -v '^$' | paste -sd, -)
    log_proposals=$(echo "$filtered" | grep -cv '^$') || log_proposals=0
fi

proposal_total=$((log_proposals))
_d_proposals=$proposal_total
if [ "$proposal_total" -gt 0 ]; then
    echo "■ 未処理PROPOSAL"
    gp_list_suffix=""
    if [ -n "$pending_gp_ids" ]; then
        gp_list_suffix=" ($pending_gp_ids)"
    fi
    echo "  WARN: 軍師未処理提案 ${proposal_total}件${gp_list_suffix} (dashboard:${dash_proposals} review_log:${log_proposals})"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("軍師未処理提案: ${proposal_total}件${gp_list_suffix}")
    fi
fi

# --- Gate 11.5: GP proposal滞留検出 (cmd_2621) ---
# 目的: karo_sent のまま長期滞留するGPを起動時ALERT化し、「低優先=やらない」を防ぐ。
gp_stale_days="${GP_STALE_DAYS:-14}"
if [ -f "$REVIEW_LOG" ]; then
    stale_gp=$(python3 - "$REVIEW_LOG" "$gp_stale_days" <<'PY' 2>/dev/null || true
import sys, yaml
from datetime import datetime, timezone, timedelta

path, days_s = sys.argv[1], sys.argv[2]
try:
    days = int(days_s)
except ValueError:
    days = 14
cutoff = datetime.now(timezone.utc) - timedelta(days=days)

def parse_ts(value):
    if not value:
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        text = str(value).strip().strip('"').replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)

def iter_entries(data):
    if isinstance(data, list):
        yield from data
    elif isinstance(data, dict):
        entries = data.get("entries")
        if isinstance(entries, list):
            yield from entries

with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or []
rows = []
for entry in iter_entries(data):
    if not isinstance(entry, dict):
        continue
    entry_ts = parse_ts(entry.get("timestamp") or entry.get("ts"))
    proposals = entry.get("proposals") or []
    if not isinstance(proposals, list):
        continue
    for proposal in proposals:
        if not isinstance(proposal, dict):
            continue
        if str(proposal.get("status", "")).strip() != "karo_sent":
            continue
        dt = parse_ts(proposal.get("sent_at") or proposal.get("timestamp") or entry_ts)
        if dt and dt <= cutoff:
            age = (datetime.now(timezone.utc) - dt).days
            rows.append((age, str(proposal.get("id", "?"))))
if rows:
    print(f"__TOTAL__\t{len(rows)}")
    for age, gid in sorted(rows, reverse=True)[:5]:
        print(f"{gid}:{age}日")
PY
)
    if [ -n "$stale_gp" ]; then
        stale_gp_count=$(printf '%s\n' "$stale_gp" | awk -F'\t' '$1=="__TOTAL__"{print $2; found=1} END{if(!found) print 0}')
        echo "■ GP proposal滞留"
        echo "  ALERT: karo_sent GP ${stale_gp_count}件が${gp_stale_days}日超過"
        printf '%s\n' "$stale_gp" | grep -v '^__TOTAL__' | sed 's/^/    /'
        overall="ALERT"
        alerts+=("GP proposal滞留: ${stale_gp_count}件/${gp_stale_days}日超")
    fi
fi

# --- Gate 12: 三層学習ループ健全性 ---
echo "■ 三層学習ループ"
if [ -f "$GATE_DIR/gate_loop_health.sh" ]; then
    wait $_PID_G12 || true
    loop_result=$(cat "$_TMP_G12")
    # Extract key metrics for brief summary
    loop_fires=$(echo "$loop_result" | grep "Total fires:" | grep -oP '\d+' || echo "0")
    loop_fail=$(echo "$loop_result" | grep "FAIL:" | head -1 | grep -oP '\d+' | head -1 || echo "0")
    loop_autofix=$(echo "$loop_result" | grep "AUTO-FIXED:" | grep -oP '\d+' || echo "0")
    loop_status=$(echo "$loop_result" | grep "Loop Status" -A1 | tail -1 | sed 's/^ *//')
    echo "  gate発火: ${loop_fires}件, FAIL: ${loop_fail}件, AUTO-FIX: ${loop_autofix}件"
    echo "  $loop_status"
    # Show maturation recommendations if any
    echo "$loop_result" | grep -A20 "成熟提案" | grep "UPGRADE\|INVESTIGATE" | while IFS= read -r rec; do
        if echo "$rec" | grep -q "result\.summary.*MISSING\|result\.summary.*empty"; then
            echo "  $rec (対処済み: cmd_1857)"
        else
            echo "  $rec"
        fi
    done
    if echo "$loop_status" | grep -q "WARNING"; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("三層ループ: $loop_status")
        fi
    fi
else
    echo "  gate_loop_health.sh不在"
fi

# --- Gate 12.5: 遡及学習 — WARN/BLOCK頻度TOP 5 + 再発率/有効率 (殿裁定2026-04-21, cmd_2289拡張) ---
# 目的: 毎セッション起動時に「何を根本修正すべきか」+「ワクチンが効いているか」を自動表示
# 再発率=前50cmdに出現したパターンが直近50cmdにも再出現した割合(将軍定義 2026-04-26)
# 有効率=前50cmdに出現したパターンが直近50cmdで消滅した割合
echo "■ 遡及学習(WARN/BLOCK頻度+再発率)"
_DQ_FILE_125="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
if [ -f "$_DQ_FILE_125" ]; then
    _retro_result=$(python3 - "$_DQ_FILE_125" <<'RETRO_PY'
import sys
from collections import Counter

dq_file = sys.argv[1]
NINJA_NAMES = {'hayate', 'kagemaru', 'hanzo', 'saizo', 'kotaro', 'tobisaru'}
SKIP_STARTS = ('draft_lessons', 'ci_failure')

def normalize_class(p):
    p = p.strip()
    if not p: return None
    if any(p.startswith(s) for s in SKIP_STARTS) or ':binary_checks_fail' in p: return None
    parts = p.split(':')
    cls = parts[0].strip()
    if cls in NINJA_NAMES and len(parts) > 1:
        cls = parts[1].strip()
    return cls if cls else None

# Fast line-based parse (yaml.safe_load takes ~4s on WSL2/NTFS)
entries_raw = []
current = {}
with open(dq_file, encoding='utf-8', errors='ignore') as f:
    for line in f:
        line = line.rstrip()
        if '  - cmd_id:' in line:
            if current.get('cmd_id') and current.get('timestamp'):
                entries_raw.append(current)
            current = {}
            current['cmd_id'] = line.split('cmd_id:', 1)[1].strip().strip('"')
        elif 'gate_result:' in line and current:
            current['gate_result'] = line.split('gate_result:', 1)[1].strip().strip('"')
        elif '    notes:' in line and current:
            current['notes'] = line.split('notes:', 1)[1].strip().strip('"')
        elif 'timestamp:' in line and current:
            current['timestamp'] = line.split('timestamp:', 1)[1].strip().strip('"')
    if current.get('cmd_id') and current.get('timestamp'):
        entries_raw.append(current)

entries = sorted(entries_raw, key=lambda e: e.get('timestamp', ''))

# Sliding windows: 直近50cmd vs 前50cmd
recent50 = entries[-50:]
prev50 = entries[-100:-50] if len(entries) >= 100 else []

# TOP 5: 直近50件のWARN/BLOCK頻出パターン (full pattern for specificity)
c = Counter()
for e in recent50:
    notes = e.get('notes', '') or ''
    for p in notes.split('|'):
        p = p.strip()
        if p and not p.startswith('draft_lessons') and ':binary_checks_fail' not in p and not p.startswith('ci_failure'):
            c[p] += 1
if c:
    for reason, count in c.most_common(5):
        print(f'  {count:4d}回(50cmd)  {reason[:65]}')
else:
    print('  直近50cmdのWARN/BLOCKなし — 学習ループ健全')

# 再発率/有効率: 前50cmdパターン vs 直近50cmdパターン (class-normalized)
def extract_classes(entry_list):
    classes = set()
    for e in entry_list:
        if e.get('gate_result') not in ('BLOCK', 'WARN'):
            continue
        notes = e.get('notes', '') or ''
        for p in notes.split('|'):
            cls = normalize_class(p)
            if cls and 'environment_change' not in cls and 'WARN累計昇格' not in cls:
                classes.add(cls)
    return classes

classes_recent = extract_classes(recent50)
classes_prev = extract_classes(prev50)

if classes_prev:
    recur = classes_prev & classes_recent
    elim = classes_prev - classes_recent
    rate = len(recur) * 100 // len(classes_prev)
    eff = len(elim) * 100 // len(classes_prev)
    print(f'  再発率 {rate}% — 前50cmdパターンが直近50cmdに再出現({len(recur)}/{len(classes_prev)}クラス)')
    print(f'  有効率 {eff}% — 前50cmdパターンが直近50cmdで消滅({len(elim)}/{len(classes_prev)}クラス)')
else:
    print('  再発率/有効率: データ不足(前50cmd未満)')
RETRO_PY
) 2>/dev/null
    if [ -n "$_retro_result" ]; then
        echo "$_retro_result"
    else
        echo "  データなし"
    fi
else
    echo "  cmd_design_quality.yaml不在"
fi

# --- Gate 13: 教訓健全度 (lesson_sort trigger) ---
echo "■ 教訓健全度"
if [ -f "$GATE_DIR/gate_lesson_health.sh" ]; then
    wait $_PID_G13 || true
    lesson_result=$(tail -1 "$_TMP_G13")
    echo "  $lesson_result"
    if echo "$lesson_result" | grep -q "ALERT"; then
        overall="ALERT"
        alerts+=("教訓健全度: ALERT → /lesson-sort実行せよ")
    elif echo "$lesson_result" | grep -q "WARN"; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("教訓健全度: WARN")
        fi
    fi
else
    echo "  gate_lesson_health.sh不在"
fi

# --- Gate 13.5: 将軍教訓ファイル存在+件数チェック ---
echo "■ 将軍教訓"
_LS_FILE="$SCRIPT_DIR/projects/infra/lessons_shogun.yaml"
if [ -f "$_LS_FILE" ]; then
    _ls_count=$(grep -c '^- id:' "$_LS_FILE" 2>/dev/null || echo 0)
    if [ "$_ls_count" -ge 31 ]; then
        echo "  WARN: lessons_shogun.yaml ${_ls_count}件(上限31件)。統合・パターン昇格が必要"
        if [ "$overall" != "ALERT" ]; then overall="WARN"; fi
        alerts+=("将軍教訓: ${_ls_count}件(上限31)。既存教訓を統合せよ")
    else
        echo "  OK: lessons_shogun.yaml (${_ls_count}件/上限31)"
    fi
else
    echo "  WARN — lessons_shogun.yaml不在。将軍教訓ファイルが存在しない"
    if [ "$overall" != "ALERT" ]; then overall="WARN"; fi
fi

# --- Gate 13.6: 教訓Stats (type別/活用率) ---
# GStack/GBrain takeaway #12 (教訓Stats — type別/信頼度/活用率)
echo "■ 教訓Stats"
if [ -f "$_LS_FILE" ]; then
    # クラスタ別件数
    _cluster_stats=$(awk '
        /^# === クラスタ/ { gsub(/^# === クラスタ[0-9]+: /, ""); gsub(/ ===$/, ""); cluster=$0; count[cluster]=0 }
        /^- id:/ && cluster != "" { count[cluster]++ }
        END { for (c in count) printf "    %s: %d件\n", c, count[c] }
    ' "$_LS_FILE" 2>/dev/null | sort || true)
    if [ -n "$_cluster_stats" ]; then
        echo "  クラスタ別:"
        echo "$_cluster_stats"
    fi
    # 活用率: queue/reports/ の lessons_useful から useful:true/false 集計
    _rep_dir="$SCRIPT_DIR/queue/reports"
    if [ -d "$_rep_dir" ]; then
        _useful_true=$(grep -rc "useful: true" "$_rep_dir/" 2>/dev/null | awk -F: '{s+=$NF}END{print s+0}')
        _useful_false=$(grep -rc "useful: false" "$_rep_dir/" 2>/dev/null | awk -F: '{s+=$NF}END{print s+0}')
        _useful_total=$(( _useful_true + _useful_false ))
        if [ "$_useful_total" -gt 0 ]; then
            _useful_rate=$(( _useful_true * 100 / _useful_total ))
            echo "  活用率: ${_useful_true}/${_useful_total} (${_useful_rate}%)"
        else
            echo "  活用率: 計測データなし"
        fi
    fi
fi

# --- Gate 13.7: cmd品質直近BLOCK（将軍のworkarounds相当） ---
echo "■ cmd品質(直近10件)"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
_DQ_FILE="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
if [ -f "$_DQ_FILE" ]; then
    _dq_total=$(grep -c 'cmd_id:' "$_DQ_FILE" 2>/dev/null || true)
    _dq_total=${_dq_total:-0}; _dq_total=${_dq_total//[^0-9]/}; _dq_total=${_dq_total:-0}
    _dq_block=$(grep -c 'gate_result.*BLOCK' "$_DQ_FILE" 2>/dev/null || true)
    _dq_block=${_dq_block:-0}; _dq_block=${_dq_block//[^0-9]/}; _dq_block=${_dq_block:-0}
    if [ "$_dq_total" -gt 0 ]; then
        _dq_rate=$(( _dq_block * 100 / _dq_total ))
        echo "  全体: ${_dq_total}件中BLOCK ${_dq_block}件 (${_dq_rate}%)"
    fi
    # 直近10件のBLOCK理由を表示
    _recent_blocks=$(tail -200 "$_DQ_FILE" | grep -B 1 'gate_result.*BLOCK' 2>/dev/null | grep 'notes:' 2>/dev/null | tail -5 | sed 's/.*notes: */  BLOCK: /' || true)
    if [ -n "$_recent_blocks" ]; then
        echo "  直近BLOCK理由:"
        echo "$_recent_blocks"
    else
        echo "  直近BLOCK: なし"
    fi
fi
fi

# --- Gate 13.8: Gate偽陽性率（事後→事前フィードバック） ---
# 起源: cmd_2181バンドル偽陽性12回蓄積→累計昇格BLOCK。gateの精度劣化を計測する仕組みがなかった
# 目的: cmd_save WARNを出したcmdがcmd_complete_gateでCLEARした場合、そのWARNは偽陽性候補。FP率が高いWARN typeをALERT
echo "■ gate偽陽性率"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
if [ -f "$_DQ_FILE" ]; then
    _fp_report=$(python3 - "$_DQ_FILE" <<'PY'
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

dq_file = sys.argv[1]
cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()

# Parse entries from YAML (simple line-based parsing)
entries = []
current = {}
with open(dq_file, 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        line = line.rstrip()
        if '  - cmd_id:' in line:
            if current:
                entries.append(current)
            current = {'cmd_id': line.split('"')[1] if '"' in line else ''}
        elif 'gate_result:' in line and current:
            current['gate_result'] = line.split('"')[1] if '"' in line else ''
        elif 'source:' in line and current:
            current['source'] = line.split('"')[1] if '"' in line else ''
        elif 'notes:' in line and current:
            current['notes'] = line.split('"')[1] if '"' in line else line.split('notes:')[1].strip().strip('"')
        elif 'timestamp:' in line and current:
            current['timestamp'] = line.split('"')[1] if '"' in line else ''
    if current:
        entries.append(current)

# Filter to last 30 days only
entries = [e for e in entries if e.get('timestamp', '') >= cutoff[:10]]

# Find WARNs from cmd_save_warn
warn_by_cmd = defaultdict(set)  # cmd_id -> set of warn notes
for e in entries:
    if e.get('source') == 'cmd_save_warn' and e.get('gate_result') == 'WARN':
        warn_by_cmd[e['cmd_id']].add(e.get('notes', 'unknown'))

# Find CLEARed cmds from cmd_complete_gate
cleared_cmds = set()
for e in entries:
    if e.get('source') == 'cmd_complete_gate' and e.get('gate_result') == 'CLEAR':
        cleared_cmds.add(e['cmd_id'])

# Count cmd_save executions per cmd (to distinguish "fixed then CLEAR" from "WARN ignored then CLEAR")
cmd_save_runs = defaultdict(int)
for e in entries:
    if e.get('source') in ('cmd_save_warn', 'cmd_save_block') and e.get('cmd_id'):
        cmd_save_runs[e['cmd_id']] += 1

# Compute FP rate per WARN type
# FP = WARN出た + CLEARされた + 同一cmdでcmd_save実行が1回のみ(=修正せずに通った)
# TP = WARN出た + CLEARされた + 同一cmdでcmd_save実行が2回以上(=修正して通した=gateが機能した)
warn_type_total = defaultdict(int)
warn_type_fp = defaultdict(int)
for cmd_id, notes_set in warn_by_cmd.items():
    for note in notes_set:
        warn_type_total[note] += 1
        if cmd_id in cleared_cmds and cmd_save_runs.get(cmd_id, 0) <= 1:
            warn_type_fp[note] += 1

# Report
if not warn_type_total:
    print("  WARN記録なし")
    sys.exit(0)

high_fp = []
for wtype, total in sorted(warn_type_total.items(), key=lambda x: -x[1]):
    fp = warn_type_fp.get(wtype, 0)
    rate = fp * 100 // total if total > 0 else 0
    if total >= 3 and rate >= 60:
        high_fp.append(f"  ALERT: \"{wtype}\" FP率={rate}% ({fp}/{total}) → gate精度劣化。修正を検討せよ")
    elif total >= 3:
        print(f"  OK: \"{wtype}\" FP率={rate}% ({fp}/{total})")

if high_fp:
    for line in high_fp:
        print(line)
else:
    print("  高FP率のWARN typeなし")
PY
)
    echo "$_fp_report"
    if echo "$_fp_report" | grep -q "ALERT"; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("gate偽陽性: 高FP率のWARN type検出。精度改善を検討せよ")
        fi
    fi
else
    echo "  cmd_design_quality.yaml不在"
fi
fi

# --- Gate 14: 軍師分析状態（知識循環チェック） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに将軍が偵察cmd重複起票
# 目的: 起動時に軍師の最新分析テーマを表示し、cmd起票前の情報基盤を整える
echo "■ 軍師分析状態"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
_gunshi_info=$(
    python3 - "$SCRIPT_DIR/context" <<'PY'
from pathlib import Path
import sys
import time

context_dir = Path(sys.argv[1])
for gfile in sorted(context_dir.glob("gunshi-*.md")):
    if not gfile.is_file():
        continue
    title = ""
    try:
        with gfile.open(encoding="utf-8", errors="ignore") as fh:
            for _ in range(5):
                line = fh.readline()
                if not line:
                    break
                if line.startswith("#"):
                    title = line.lstrip("#").strip()
                    break
        mtime = time.strftime("%m-%d %H:%M", time.localtime(gfile.stat().st_mtime))
    except Exception:
        mtime = "?"
    print(f"{gfile.name}\t{mtime}\t{title}")
PY
)
if [ -n "$_gunshi_info" ]; then
    while IFS=$'\t' read -r _g_name _g_mtime _g_title; do
        [ -n "$_g_name" ] || continue
        printf '  %s [%s] — %s\n' "$_g_name" "$_g_mtime" "$_g_title"
    done <<< "$_gunshi_info"
    echo "  → cmd起票前にこれらを確認せよ（cmd_1451重複防止）"
else
    echo "  軍師分析ファイルなし"
fi
fi

# --- Context著者: 遅延取得（孤立ファイルのみgit log -1） ---
# 高速化: 全履歴走査(2.5s/1965行)→孤立時のみper-file git log -1(0s〜0.1s)
# 根因: Gate15は孤立ファイル(通常0-5件)の著者だけ必要。42ファイル全履歴は過剰
_get_context_author() {
    git log -1 --format='%an' -- "context/$1" 2>/dev/null || echo "?"
}

# --- Gate 15: 進化検知（知識循環の上流検知） ---
# 起源: cmd_1451→なぜなぜ5段 — 失敗は検知するが進化(新能力・新出力)は検知しない
# 目的: context/に知識マップ(CLAUDE.md/MEMORY.md/instructions/config/dashboard)から
#        参照されていないファイルがあれば、進化シグナルとしてフラグ。知識循環を自動促進
# 高速版: 核心ファイルをcatして一括grepで判定(WSL2 /mnt/c でのfull-repo scan回避)
echo "■ 進化検知（孤立context）"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
_evo_orphans=""
_evo_count=0
_KMAP_MISSING=()
_evo_scan=$(
    python3 - "$SCRIPT_DIR" "$HOME" <<'PY'
from pathlib import Path
import sys
import time

script_dir = Path(sys.argv[1])
home_dir = Path(sys.argv[2])
sources = [
    script_dir / "CLAUDE.md",
    home_dir / ".claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md",
]
sources.extend(sorted((script_dir / "instructions").glob("*.md")))
sources.extend([
    script_dir / "config/projects.yaml",
    script_dir / "dashboard.md",
])

kmap_parts = []
missing = []
for src in sources:
    if src.is_file():
        try:
            kmap_parts.append(src.read_text(encoding="utf-8", errors="ignore"))
        except Exception:
            missing.append(src.name)
    else:
        missing.append(src.name)
kmap_text = "\n".join(kmap_parts)

for name in missing:
    print(f"MISSING\t{name}")

for cfile in sorted((script_dir / "context").glob("*.md")):
    if not cfile.is_file() or cfile.name == "README.md":
        continue
    if cfile.name in kmap_text:
        continue
    title = ""
    try:
        with cfile.open(encoding="utf-8", errors="ignore") as fh:
            for _ in range(5):
                line = fh.readline()
                if not line:
                    break
                if line.startswith("#"):
                    title = line.lstrip("#").strip()
                    break
        mtime = time.strftime("%m-%d %H:%M", time.localtime(cfile.stat().st_mtime))
    except Exception:
        mtime = "?"
    print(f"ORPHAN\t{cfile.name}\t{mtime}\t{title}")
PY
)
if [ -n "$_evo_scan" ]; then
    while IFS=$'\t' read -r _evo_kind _evo_name _evo_mtime _evo_title; do
        case "$_evo_kind" in
            MISSING)
                [ -n "$_evo_name" ] && _KMAP_MISSING+=("$_evo_name")
                ;;
            ORPHAN)
                [ -n "$_evo_name" ] || continue
                _c_author=$(_get_context_author "$_evo_name")
                _evo_orphans="${_evo_orphans}  ${_evo_name} [${_evo_mtime}] by ${_c_author} — ${_evo_title}\n"
                _evo_count=$((_evo_count + 1))
                ;;
        esac
    done <<< "$_evo_scan"
fi
fi
if [ ${#_KMAP_MISSING[@]} -gt 0 ]; then
    echo "  INFO: 知識マップ参照元欠落: $(printf '%s, ' "${_KMAP_MISSING[@]}" | sed 's/, $//')"
fi
	if [ "${_evo_count:-0}" -gt 0 ]; then
    echo -e "$_evo_orphans"
    echo "  → ${_evo_count}件: 知識マップ(CLAUDE.md/MEMORY.md/instructions/config)に未参照。進化シグナルか確認し統合せよ"
    if [ "$_evo_count" -ge 3 ]; then
        alerts+=("進化検知: context/に孤立ファイル${_evo_count}件")
        overall="ALERT"
    fi
else
    echo "  孤立context/ファイルなし（知識マップ完全同期）"
fi

# --- Gate 16: AC注入検証（配備済みタスク vs cmdソース, cmd_1668） ---
# 起源: AC注入失敗WA 6件 — _overwrite_ac_from_cmdのネスト形式未対応/stale AC残留
# 目的: 起動時に稼働中タスクのACがcmdソースと一致するか検証。不一致時WARNING（BLOCK不要）
echo "■ AC注入検証"
_ac16_warn_msgs=()
_ac16_checked=0
_AC16_STK="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
_AC16_TDIR="$SCRIPT_DIR/queue/tasks"

if [ -d "$_AC16_TDIR" ] && [ -f "$_AC16_STK" ]; then
    for _ac16_tf in "$_AC16_TDIR"/*.yaml; do
        [ ! -f "$_ac16_tf" ] && continue
        _ac16_st=$(awk '/^  status:/{print $2; exit}' "$_ac16_tf")
        case "$_ac16_st" in
            assigned|acknowledged|in_progress) ;;
            *) continue ;;
        esac
        _ac16_pcmd=$(awk '/^  parent_cmd:/{print $2; exit}' "$_ac16_tf")
        [ -z "$_ac16_pcmd" ] && continue

        # scout_exempt=trueのcmdはAC段階配備のためスキップ
        _ac16_scout=$(awk -v cmd="$_ac16_pcmd" '
            BEGIN { t="  "cmd":" }
            $0==t { c=1; next }
            c && /^  [a-zA-Z]/ { exit }
            c && /^    scout_exempt: / { sub(/.*scout_exempt: */, ""); print; exit }
        ' "$_AC16_STK")
        if [ "$_ac16_scout" = "true" ]; then
            continue
        fi

        # Task YAML: AC IDs (sorted). [- ]* handles both "  - id:" and "    id:" formats
        _ac16_tids=$(awk '
            /^  acceptance_criteria:/ { f=1; next }
            f && /^  [a-zA-Z_]/ { exit }
            f && /^  [- ]*id: / { sub(/.*id: */, ""); gsub(/[" ]/, ""); if ($0!="") print }
        ' "$_ac16_tf" | sort)

        # STK: AC IDs from acceptance_criteria list (sorted)
        _ac16_cids=$(awk -v cmd="$_ac16_pcmd" '
            BEGIN { t="  "cmd":" }
            $0==t { c=1; next }
            c && /^  [a-zA-Z_]/ { exit }
            c && /^    acceptance_criteria:/ { a=1; next }
            a && /^    [a-zA-Z_]/ { exit }
            a && /^      [- ]*id: / { sub(/.*id: */, ""); gsub(/[" ]/, ""); if ($0!="") print }
        ' "$_AC16_STK" | sort)

        # Fallback: ac: nested format (AC1:, AC2: as keys)
        if [ -z "$_ac16_cids" ]; then
            _ac16_cids=$(awk -v cmd="$_ac16_pcmd" '
                BEGIN { t="  "cmd":" }
                $0==t { c=1; next }
                c && /^  [a-zA-Z_]/ { exit }
                c && /^    ac:$/ { a=1; next }
                a && /^    [a-zA-Z_]/ { exit }
                a && /^      AC[0-9]/ { sub(/:.*/, ""); gsub(/[[:space:]]/, ""); if ($0!="") print }
            ' "$_AC16_STK" | sort)
        fi

        [ -z "$_ac16_cids" ] && continue
        _ac16_checked=$((_ac16_checked + 1))
        _ac16_nn=$(basename "$_ac16_tf" .yaml)

        if [ "$_ac16_tids" != "$_ac16_cids" ]; then
            _ac16_tc=$(printf '%s\n' "$_ac16_tids" | awk 'NF{n++}END{print n+0}')
            _ac16_cc=$(printf '%s\n' "$_ac16_cids" | awk 'NF{n++}END{print n+0}')
            _ac16_tcsv=$(echo "$_ac16_tids" | paste -sd, -)
            _ac16_ccsv=$(echo "$_ac16_cids" | paste -sd, -)
            _ac16_warn_msgs+=("${_ac16_nn}(${_ac16_pcmd}): task=[${_ac16_tcsv}](${_ac16_tc}) cmd=[${_ac16_ccsv}](${_ac16_cc})")
        fi
    done

    if [ ${#_ac16_warn_msgs[@]} -gt 0 ]; then
        for _ac16_wm in "${_ac16_warn_msgs[@]}"; do
            echo "  WARNING: AC不一致 — $_ac16_wm"
        done
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("AC注入不一致: ${#_ac16_warn_msgs[@]}/${_ac16_checked}件")
    else
        echo "  OK: 稼働中${_ac16_checked}件のAC整合確認"
    fi
else
    echo "  SKIP: task/cmd不在"
fi

# --- Gate 17: scripts/未コミット変更チェック (cmd_1675) ---
# 起源: scripts/配下に未コミットの変更があると気付かずに消失するリスク
# 目的: 起動時にscripts/の変更をWARNして把握漏れを防止。変更なしなら無音通過
_scripts_status=$(cd "$SCRIPT_DIR" && git status --porcelain --branch -- scripts/ 2>/dev/null) || _scripts_status=""
_scripts_dirty=()
_d_unpushed="?"
if [ "$LIGHT_MODE" = "1" ]; then
    _scripts_status=""
    _d_unpushed="0"
elif [ -n "$_scripts_status" ]; then
    while IFS= read -r _scripts_line; do
        case "$_scripts_line" in
            '## '*)
                if [[ "$_scripts_line" =~ \[ahead[[:space:]]+([0-9]+) ]]; then
                    _d_unpushed="${BASH_REMATCH[1]}"
                else
                    _d_unpushed="0"
                fi
                ;;
            '?? scripts/oneshot/'*)
                ;;
            '')
                ;;
            *)
                _scripts_dirty+=("$_scripts_line")
                ;;
        esac
    done <<< "$_scripts_status"
fi
if [ ${#_scripts_dirty[@]} -gt 0 ]; then
    _sd_count=${#_scripts_dirty[@]}
    echo "■ scripts/未コミット変更"
    for _sd_line in "${_scripts_dirty[@]}"; do
        echo "  WARN: $_sd_line"
    done
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
    fi
    alerts+=("scripts/未コミット変更: ${_sd_count}件")
fi

# --- Gate 19: 強制度監査 (meta-gate, 2026-04-12) ---
# 起源: 軍師 /clear 後に gate_gunshi_startup.sh が自動実行されなかった
# なぜなぜ7回で到達した根因=「gate の gate 不在」メタレベル欠落
# 目的: CLAUDE.md 記述と settings hooks 登録の乖離(意志依存 script)を検出
echo "■ 強制度監査 (meta-gate)"
if [ "$LIGHT_MODE" = "1" ]; then
    echo "  SKIP(lightweight)"
else
_ENFORCE_AUDIT="$SCRIPT_DIR/scripts/gates/gate_enforcement_audit.sh"
if [ -x "$_ENFORCE_AUDIT" ]; then
    if _ea_out=$(bash "$_ENFORCE_AUDIT" 2>&1); then
        echo "  OK: 意志依存 script 0 本"
    else
        _ea_count=$(printf '%s\n' "$_ea_out" | grep -oE '意志依存 script 検出: [0-9]+ 本' | grep -oE '[0-9]+' | head -1)
        [ -z "$_ea_count" ] && _ea_count="?"
        overall="ALERT"
        alerts+=("強制度監査: 意志依存 script ${_ea_count}本 — bash scripts/gates/gate_enforcement_audit.sh")
        echo "  ALERT: 意志依存 script ${_ea_count} 本 — CLAUDE.md参照のみでhooks未登録"
        printf '%s\n' "$_ea_out" | grep -E '^  - ' | head -10
        _ea_proposal=$(printf '%s\n' "$_ea_out" | awk '/^■ hooks登録コマンド候補/{flag=1} flag{print} /^=== 総合判定: ALERT/{flag=0}')
        if [ -n "$_ea_proposal" ]; then
            printf '%s\n' "$_ea_proposal" | sed 's/^/  /'
        fi
    fi
else
    echo "  INFO: gate_enforcement_audit.sh 未配備"
fi
fi

# --- Gate 20: スキル別FAIL率 (cmd_2459) ---
# 目的: スキル実行ログから改善対象スキルを起動時に提示し、失敗をSKILL.md改善に還流する。
echo "■ スキル別FAIL率"
_skill_exec_log="$SCRIPT_DIR/logs/skill_execution_log.yaml"
if [ -f "$_skill_exec_log" ]; then
    _skill_stats=$(python3 - "$_skill_exec_log" <<'PY' 2>/dev/null || true
import sys
from collections import defaultdict
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
entries = data.get("executions") or []
stats = defaultdict(lambda: {"total": 0, "fail": 0, "last": ""})
by_skill = defaultdict(list)
for entry in entries:
    if not isinstance(entry, dict):
        continue
    skill = str(entry.get("skill") or "").strip()
    if not skill:
        continue
    by_skill[skill].append(entry)
for skill, skill_entries in by_skill.items():
    recent_entries = skill_entries[-50:]
    stats[skill]["total"] = len(recent_entries)
    if recent_entries:
        stats[skill]["last"] = str(recent_entries[-1].get("ts") or "")
    for entry in recent_entries:
        result = str(entry.get("result") or "").upper()
        if result == "FAIL":
            stats[skill]["fail"] += 1
rows = []
for skill, item in stats.items():
    total = item["total"]
    fail = item["fail"]
    pct = int(round((fail / total) * 100)) if total else 0
    rows.append((pct, fail, total, skill, item["last"]))
rows.sort(key=lambda row: (row[0], row[1], row[3]), reverse=True)
for pct, fail, total, skill, last in rows[:5]:
    print(f"{skill}\t{pct}\t{fail}\t{total}\t{last}")
PY
)
    if [ -n "$_skill_stats" ]; then
        _skill_warn=0
        while IFS=$'\t' read -r _sk _pct _fail _total _last; do
            [ -n "$_sk" ] || continue
            echo "  ${_sk}: 直近50件FAIL率=${_pct}% (${_fail}/${_total}) last=${_last}"
            if [ "${_pct:-0}" -gt 10 ]; then
                _skill_warn=1
            fi
        done <<< "$_skill_stats"
        if [ "$_skill_warn" -eq 1 ] && [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("スキル別FAIL率: 直近50件FAIL率10%超の改善対象あり")
        elif [ "$_skill_warn" -eq 0 ]; then
            echo "  OK: 直近50件FAIL率10%超スキルなし"
        fi
    else
        echo "  OK: 実行ログあり、集計対象0件"
    fi
else
    echo "  SKIP: logs/skill_execution_log.yaml 不在"
fi

# --- Gate 20.5: SKILL.md script参照鮮度 (cmd_2489) ---
# 目的: SKILL.mdが参照する scripts/* の消滅・更新漏れを起動時に検出する。
echo "■ SKILL.md script参照"
_skill_ref_gate="$SCRIPT_DIR/scripts/gates/gate_skill_script_refs.sh"
if [ -x "$_skill_ref_gate" ]; then
    if _skill_ref_out=$(bash "$_skill_ref_gate" "$SCRIPT_DIR" 2>&1); then
        printf '%s\n' "$_skill_ref_out" | grep -E '^(走査:|OK:|--- 総合判定)' | sed 's/^/  /'
    else
        _skill_ref_status=$?
        printf '%s\n' "$_skill_ref_out" | grep -E '^(走査:|=== 要更新|=== 参照先|  WARN:|--- 総合判定)' | head -20 | sed 's/^/  /'
        if [ "$_skill_ref_status" -eq 2 ] && [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("SKILL.md script参照: 要確認あり — bash scripts/gates/gate_skill_script_refs.sh")
        else
            overall="ALERT"
            alerts+=("SKILL.md script参照: gate実行失敗 — bash scripts/gates/gate_skill_script_refs.sh")
        fi
    fi
else
    echo "  INFO: gate_skill_script_refs.sh 未配備"
fi

# --- Gate 21: L6学習速度 (cmd_2668) ---
# 目的: gate_fire_logのFAIL→PASS回復速度と防御仕組みのL6化率を起動時に可視化する。
echo "■ L6学習速度"
_l6_out=$(L6_REPO_ROOT="$SCRIPT_DIR" \
    L6_NOW="${L6_LEARNING_NOW:-}" \
    L6_UNRECOVERED_FAIL_ALERT_DAYS="${L6_UNRECOVERED_FAIL_ALERT_DAYS:-30}" \
    python3 <<'PY' 2>/dev/null || true
import os
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

repo = Path(os.environ["L6_REPO_ROOT"])
now_raw = os.environ.get("L6_NOW", "").strip()
if now_raw:
    now = datetime.fromisoformat(now_raw.replace("Z", "+00:00"))
else:
    now = datetime.now(timezone.utc)
if now.tzinfo is None:
    now = now.replace(tzinfo=timezone.utc)
cutoff = now - timedelta(days=30)
try:
    unresolved_threshold_days = int(os.environ.get("L6_UNRECOVERED_FAIL_ALERT_DAYS", "30"))
except ValueError:
    unresolved_threshold_days = 30

fire_log = repo / "logs" / "gate_fire_log.yaml"
re_ts = re.compile(r'ts:\s*"([^"]+)"')
re_file = re.compile(r'file:\s*"([^"]*)"')
re_gate = re.compile(r'gate:\s*"?(.*?)"?(?:,|\s+result:)')
re_result = re.compile(r'result:\s*([A-Z][A-Z-]*)')

entries = []
all_entries = []
if fire_log.exists():
    for raw in fire_log.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line.startswith("- "):
            continue
        tm = re_ts.search(line)
        gm = re_gate.search(line)
        rm = re_result.search(line)
        if not (tm and gm and rm):
            continue
        fm = re_file.search(line)
        file_value = fm.group(1) if fm else ""
        if file_value.startswith("/tmp/"):
            continue
        try:
            ts = datetime.fromisoformat(tm.group(1).replace("Z", "+00:00"))
        except ValueError:
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        if ts > now + timedelta(minutes=5):
            continue
        entry = (ts, gm.group(1).strip(), rm.group(1).strip())
        all_entries.append(entry)
        if ts < cutoff:
            continue
        entries.append(entry)

entries.sort(key=lambda item: item[0])
stats = defaultdict(lambda: {"fail": 0, "recovered": 0, "open": 0, "pass": 0})
for _ts, gate, result in entries:
    if result == "FAIL":
        stats[gate]["fail"] += 1
        stats[gate]["open"] += 1
    elif result == "PASS":
        stats[gate]["pass"] += 1
        if stats[gate]["open"] > 0:
            stats[gate]["recovered"] += stats[gate]["open"]
            stats[gate]["open"] = 0

print("FAIL→PASS遷移率(直近30日):")
if stats:
    rows = []
    for gate, item in stats.items():
        fail = item["fail"]
        recovered = item["recovered"]
        rate = round((recovered / fail) * 100) if fail else 100
        rows.append((fail, recovered, rate, gate, item["open"], item["pass"]))
    rows.sort(key=lambda row: (-row[0], row[3]))
    for fail, recovered, rate, gate, open_count, pass_count in rows[:5]:
        print(f"  {gate}: {rate}% ({recovered}/{fail} FAIL回復, 未回復={open_count}, PASS={pass_count})")
else:
    print("  SKIP: gate_fire_log直近30日データなし")

open_failures = defaultdict(list)
for ts, gate, result in sorted(all_entries, key=lambda item: item[0]):
    if result == "FAIL":
        open_failures[gate].append(ts)
    elif result == "PASS":
        open_failures[gate].clear()

stale_open = []
for gate, failures in open_failures.items():
    if not failures:
        continue
    oldest = min(failures)
    age_days = (now - oldest).days
    if age_days >= unresolved_threshold_days:
        stale_open.append((age_days, gate, len(failures)))

if stale_open:
    stale_open.sort(key=lambda row: (-row[0], row[1]))
    print(f"未回復FAIL ALERT(閾値{unresolved_threshold_days}日):")
    for age_days, gate, fail_count in stale_open[:5]:
        print(f"  ALERT: {gate} 未回復{age_days}日 FAIL={fail_count}件")
        print(f"__L6_UNRECOVERED_ALERT__\t{gate}\t{age_days}\t{fail_count}")

def compact(value):
    value = re.sub(r"\s+", " ", value).strip().strip("\"'")
    return value[:120] if value else "summary不明"

l6_source = repo / "context" / "growth-loop.md"
mechanisms = []

def section_11(text):
    match = re.search(r"^## §11\b.*?(?=^## |\Z)", text, re.M | re.S)
    return match.group(0) if match else ""

def table_after(section, marker):
    marker_pos = section.find(marker)
    if marker_pos < 0:
        return []
    lines = section[marker_pos:].splitlines()
    rows = []
    in_table = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("|") and stripped.endswith("|"):
            in_table = True
            rows.append(stripped)
            continue
        if in_table:
            break
    return rows

def parse_table(rows):
    parsed = []
    for row in rows:
        cells = [cell.strip() for cell in row.strip("|").split("|")]
        if not cells or cells[0] in {"対象", "名称"}:
            continue
        if all(re.fullmatch(r"-+", cell) for cell in cells):
            continue
        parsed.append(cells)
    return parsed

if l6_source.exists():
    section = section_11(l6_source.read_text(encoding="utf-8", errors="ignore"))
    for cells in parse_table(table_after(section, "L6化済み仕組み完全リスト")):
        if len(cells) < 4:
            continue
        mechanisms.append({
            "level": 6,
            "id": compact(cells[1]),
            "summary": compact(cells[3]),
            "source": "context/growth-loop.md §11",
        })
    for cells in parse_table(table_after(section, "L6未化仕組み")):
        if len(cells) < 4:
            continue
        lm = re.search(r"Level\s*([0-9]+)", cells[1])
        mechanisms.append({
            "level": int(lm.group(1)) if lm else 0,
            "id": compact(cells[0]),
            "summary": compact(cells[2]),
            "source": "context/growth-loop.md §11",
        })

total = len(mechanisms)
l6_count = sum(1 for item in mechanisms if item["level"] >= 6)
rate = round((l6_count / total) * 100) if total else 0
print(f"L6化率: {rate}% ({l6_count}/{total})")
not_l6 = [item for item in mechanisms if item["level"] < 6]
not_l6.sort(key=lambda item: (item["level"], item["source"], item["id"]))
if not_l6:
    print("L6未到達仕組みTOP3:")
    for item in not_l6[:3]:
        print(f"  L{item['level']} {item['id']}: {item['summary']} ({item['source']})")
elif total:
    print("L6未到達仕組みTOP3: なし")
else:
    print("L6未到達仕組みTOP3: SKIP(defense_levelデータなし)")
PY
)
if [ -n "$_l6_out" ]; then
    printf '%s\n' "$_l6_out" | grep -v '^__L6_UNRECOVERED_ALERT__' | sed 's/^/  /'
    while IFS=$'\t' read -r _l6_marker _l6_gate _l6_age _l6_count; do
        [ "$_l6_marker" = "__L6_UNRECOVERED_ALERT__" ] || continue
        overall="ALERT"
        alerts+=("L6学習速度: ${_l6_gate} 未回復FAIL ${_l6_age}日 (${_l6_count}件)")
        _l6_bulletin="L6学習速度ALERT: ${_l6_gate} の未回復FAILが${_l6_age}日継続(FAIL=${_l6_count}件)。将軍は原因修正cmdを起票されたし。"
        if [ -x "$SCRIPT_DIR/scripts/bulletin_write.sh" ]; then
            BULLETIN_NOTIFY=shogun bash "$SCRIPT_DIR/scripts/bulletin_write.sh" shogun "$_l6_bulletin" shogun >/dev/null 2>&1 || true
        fi
    done <<< "$_l6_out"
else
    echo "  SKIP: L6学習速度集計失敗"
fi

# --- 総合判定 ---
STARTUP_WARN_STREAK_THRESHOLD="${STARTUP_WARN_STREAK_THRESHOLD:-3}"
STARTUP_ALERT_HISTORY="$SCRIPT_DIR/logs/shogun_startup_alert_history.tsv"
if [ "${#alerts[@]}" -gt 0 ]; then
    mkdir -p "$(dirname "$STARTUP_ALERT_HISTORY")"
    _streak_result=$(python3 - "$STARTUP_ALERT_HISTORY" "${STARTUP_WARN_STREAK_THRESHOLD}" "${alerts[@]}" <<'PY' 2>/dev/null || true
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    threshold = int(sys.argv[2])
except ValueError:
    threshold = 3
current = [a.strip() for a in sys.argv[3:] if a.strip()]
if not current or threshold <= 1:
    sys.exit(0)

runs = []
if path.exists():
    current_run = None
    current_keys = set()
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = raw.split("\t", 1)
        if len(parts) != 2:
            continue
        run_id, key = parts
        if current_run is None:
            current_run = run_id
        if run_id != current_run:
            runs.append(current_keys)
            current_run = run_id
            current_keys = set()
        if key != "__OK__":
            current_keys.add(key)
    if current_run is not None:
        runs.append(current_keys)

previous = runs[-(threshold - 1):]
for key in current:
    if len(previous) == threshold - 1 and all(key in run for run in previous):
        print(key)
PY
)
    if [ -n "$_streak_result" ]; then
        echo "■ startup WARN/ALERT連続出現"
        while IFS= read -r _streak_key; do
            [ -n "$_streak_key" ] || continue
            echo "  BLOCK: ${_streak_key} が${STARTUP_WARN_STREAK_THRESHOLD}セッション連続"
            alerts+=("startup連続出現BLOCK: ${_streak_key}")
        done <<< "$_streak_result"
        overall="BLOCK"
    fi
fi

echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
echo ""
# ─── ダイジェスト: 全項目1行（grepフィルタ不要化。殿裁定2026-03-24） ───
wait "$_PID_UNPUSHED" || true
if [ -z "${_d_unpushed:-}" ] || [ "${_d_unpushed:-?}" = "?" ]; then
    _d_unpushed=$(cat "$_TMP_UNPUSHED" 2>/dev/null)
    [ -n "$_d_unpushed" ] || _d_unpushed="?"
fi
echo "■ DIGEST: inbox=${_d_inbox} insights=${_d_insights} proposals=${_d_proposals} unpushed=${_d_unpushed} idle_trigger=${IDLE_TRIGGER} judge=${overall}"
echo ""
echo "■ 必読: projects/infra/lessons_shogun.yaml（将軍教訓。deepdive前に通読せよ=Step 2.45。superseded_by付きは参考扱い）"
echo "■ 必読: memory/deepdive_why_chain_20260321.md（知性の外部化原則 全過程）"

mkdir -p "$(dirname "$STARTUP_ALERT_HISTORY")"
_startup_run_id="$(date '+%Y-%m-%dT%H:%M:%S%z')"
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        printf '%s\t%s\n' "$_startup_run_id" "$a" >> "$STARTUP_ALERT_HISTORY"
    done
else
    printf '%s\t__OK__\n' "$_startup_run_id" >> "$STARTUP_ALERT_HISTORY"
fi

# Step 6: ALERT項目をinsightsに自動保存（将軍の「後でやる」放置防止）
if { [ "$overall" = "ALERT" ] || [ "$overall" = "BLOCK" ]; } && [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        # 教訓健全度ALERTなど既知パターンのみ自動保存（ノイズ防止）
        case "$a" in
            *教訓健全度*|*三層ループ*|*軍師未処理*)
                bash "$SCRIPT_DIR/scripts/insight_write.sh" "起動ALERT未対処: $a" 2>/dev/null || true
                ;;
        esac
    done
fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${SHOGUN_STARTUP_LIB_ONLY:-0}" != "1" ]]; then
    run_gate_shogun_startup "$@"
    # 復帰完了マーカー: PostToolUse hookが未完了を警告する仕組み(LS084)
    touch /tmp/shogun_recovery_complete
fi
