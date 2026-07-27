#!/usr/bin/env bash
# T3(cmd_karo_hotfix_auto_clear_recovery_20260727 AC4): logs/ninja_monitor.log から
# 直近WINDOW_SEC秒のCLEAR-BLOCKED-NOTIFY(=T2がしきい値到達で家老へ通知した事実)行を集計し、
# 家老・軍師startup gateへ1行で渡す。0件なら空文字を返し、呼び出し側は無表示にする。
# 軍師レビュー指摘(msg_20260727_141109): 素のCLEAR-BLOCKED skip行は正常な保全動作でも
# 頻発するため、これをgrepすると「0件時無表示」の設計意図が実質常時表示になり崩れる。
# T2が既にしきい値到達を判定済みのCLEAR-BLOCKED-NOTIFY行だけを見ることで、
# T3はT2と同じ「異常」の定義を再利用する(判定ロジックの二重実装を避ける)。
# 契約: このスクリプトはlogを読むだけで一切書き換えない(read-only)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG_FILE="${1:-$SCRIPT_DIR/logs/ninja_monitor.log}"
WINDOW_SEC="${CLEAR_BLOCKED_SUMMARY_WINDOW_SEC:-1800}"
TAIL_LINES="${CLEAR_BLOCKED_SUMMARY_TAIL_LINES:-5000}"  # 軍師red-team指摘(a): log肥大でstartupが遅くならないよう範囲限定

[ -f "$LOG_FILE" ] || exit 0

now_epoch=$(date +%s)

# 1件の定義: `CLEAR-BLOCKED-NOTIFY: <agent> count=... window_sec=...` にマッチする行1本
#   (=T2が窓内しきい値到達で家老へ通知を送った事実そのもの)。
# 網羅範囲: 現行ログの直近TAIL_LINES行のみ。ローテートは対象外(T3は「今どうなっているか」の現況表示)。
tail -n "$TAIL_LINES" "$LOG_FILE" 2>/dev/null | grep -E '^\[[0-9-]+ [0-9:]+\] CLEAR-BLOCKED-NOTIFY: [a-zA-Z0-9_]+ count=' | awk -v now="$now_epoch" -v win="$WINDOW_SEC" '
{
    ts_str = substr($0, 2, 19)
    gsub(/-/, " ", ts_str)
    gsub(/:/, " ", ts_str)
    n = split(ts_str, p, " ")
    if (n != 6) next
    epoch = mktime(p[1]" "p[2]" "p[3]" "p[4]" "p[5]" "p[6])
    if (epoch == -1) next
    if (now - epoch > win) next

    agent = $4
    count[agent]++
    total++
}
END {
    if (total == 0) exit 0
    agents = ""
    n = asorti(count, sorted)
    for (i = 1; i <= n; i++) {
        agents = agents (agents == "" ? "" : ",") sorted[i]
    }
    printf "直近%d分でCLEAR-BLOCKED %d件 / 対象agent: %s\n", win / 60, total, agents
}
'
