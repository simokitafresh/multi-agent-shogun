#!/usr/bin/env bash
# scripts/ralph_loop_metrics.sh — ラルフループ効果検証5指標計測
# cmd_1118: 教訓→GATE→学習ループの効果を定量化
#
# 5指標:
#   (1) 同一パターン再発率
#   (2) 差し戻し率の時系列推移
#   (3) cmd完了速度の推移
#   (4) 教訓注入量とCLEAR率の相関
#   (5) PI違反再発率
#
# データソース:
#   - logs/gate_metrics.log (GATE BLOCK/CLEAR記録)
#   - queue/reports/*.yaml (レポートverdict)
#   - queue/archive/cmds/*.yaml (cmd時刻・related_lessons)
#   - projects/dm-signal/lessons.yaml + projects/infra/lessons.yaml
#   - projects/dm-signal.yaml production_invariants

set -euo pipefail

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS_DIR="$BASEDIR/queue/reports"
ARCHIVE_DIR="$BASEDIR/queue/archive/cmds"
GATE_LOG="$BASEDIR/logs/gate_metrics.log"
DM_LESSONS="$BASEDIR/projects/dm-signal/lessons.yaml"
INFRA_LESSONS="$BASEDIR/projects/infra/lessons.yaml"
DM_PROJECT="$BASEDIR/projects/dm-signal.yaml"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ═══════════════════════════════════════════════════════════════
# PRE-COMPUTE: バッチ処理で全データソースから中間データを抽出
# ═══════════════════════════════════════════════════════════════

echo "[前処理] データ抽出中..." >&2

# --- (A) 教訓データ: id|source_cmd_num|date|tags ---
extract_lessons() {
    local file="$1"
    [ -f "$file" ] || return
    awk '
    /^- id: / {
        if (id != "" && source != "") printf "%s|%s|%s|%s\n", id, source, dt, tags
        id = $3; source = ""; dt = ""; tags = ""; in_tags = 0
    }
    /^  source: / {
        s = $0; sub(/.*source: */, "", s); gsub(/["'"'"']/, "", s)
        gsub(/cmd_/, "", s); gsub(/ .*/, "", s)
        source = s
    }
    /^  date: / {
        d = $0; sub(/.*date: */, "", d); gsub(/["'"'"']/, "", d); gsub(/ /, "", d)
        dt = d
    }
    /^  tags:$/ { in_tags = 1; next }
    in_tags && /^  - / {
        t = $2
        tags = (tags == "" ? t : tags "," t)
        next
    }
    in_tags && !/^  - / { in_tags = 0 }
    END { if (id != "" && source != "") printf "%s|%s|%s|%s\n", id, source, dt, tags }
    ' "$file"
}

extract_lessons "$DM_LESSONS" > "$TMP/lessons.tsv" 2>/dev/null
extract_lessons "$INFRA_LESSONS" >> "$TMP/lessons.tsv" 2>/dev/null
echo "  教訓: $(wc -l < "$TMP/lessons.tsv")件抽出" >&2

# --- (B) レポートverdict: cmd_num|verdict ---
# grep一発でバッチ抽出 → sedでcmd番号+verdict解析
grep -rH "^verdict:" "$REPORTS_DIR"/ 2>/dev/null \
    | sed -E 's|^.*/[a-z_]+_report_cmd_([0-9]+)[^:]*:verdict: *(.*)$|\1\|\2|' \
    | sed "s/[\"']//g" \
    > "$TMP/verdicts.tsv" 2>/dev/null || true
echo "  レポートverdict: $(wc -l < "$TMP/verdicts.tsv")件抽出" >&2

# --- (C) GATE outcomes: cmd_num|first_outcome|block_count ---
awk -F'\t' '
{
    cmd = $2; gsub(/cmd_/, "", cmd); cmd_num = cmd + 0
    result = $3
    if (!(cmd_num in first)) first[cmd_num] = result
    if (result == "BLOCK") blocks[cmd_num]++
}
END {
    for (c in first)
        printf "%d|%s|%d\n", c, first[c], (blocks[c] ? blocks[c] : 0)
}
' "$GATE_LOG" | sort -t'|' -k1,1n > "$TMP/gate_outcomes.tsv"
echo "  GATEレコード: $(wc -l < "$TMP/gate_outcomes.tsv")件" >&2

# --- (D) GATE CLEAR timestamps: cmd_num|timestamp ---
awk -F'\t' '
$3 == "CLEAR" && !seen[$2]++ {
    cmd = $2; gsub(/cmd_/, "", cmd)
    print cmd "|" $1
}
' "$GATE_LOG" | sort -t'|' -k1,1n > "$TMP/clear_times.tsv"

# --- (E)+(F) 統合: 単一gawkパスでarchive全ファイルを1回走査 ---
# GP-079: Section(E) delegated_at抽出 + Section(F) related_lessons計数を統合
# 旧: bash forループ×1178ファイル(~5890 fork, 9.6秒) + grep+awk whileループ(3秒)
# 新: gawk BEGINFILE/ENDFILE 1パス(~2.5秒)
echo "  archive cmdsスキャン中(gawk統合パス)..." >&2
gawk -v tmpdir="$TMP" '
    BEGINFILE {
        cmd = FILENAME
        sub(/.*cmd_/, "", cmd)
        sub(/[^0-9].*/, "", cmd)
        ts = ""
        has_delegated = 0
        in_rl = 0
        rl_count = 0
    }
    /delegated_at:/ && !has_delegated {
        ts = $0; sub(/.*delegated_at: */, "", ts)
        gsub(/["'"'"'\t ]/, "", ts)
        has_delegated = 1
    }
    !has_delegated && /timestamp:/ && ts == "" {
        ts = $0; sub(/.*timestamp: */, "", ts)
        gsub(/["'"'"'\t ]/, "", ts)
    }
    /related_lessons:/ { in_rl = 1; next }
    in_rl && /- id: L/ { rl_count++ }
    in_rl && /^[^ ]/ && !/related_lessons:/ { in_rl = 0 }
    ENDFILE {
        if (cmd != "") {
            if (ts != "") print cmd "|" ts > tmpdir "/start_times.tsv"
            print cmd "|" rl_count > tmpdir "/lesson_counts_raw.tsv"
        }
    }
' "$ARCHIVE_DIR"/cmd_*.yaml 2>/dev/null
echo "  cmd開始時刻: $(wc -l < "$TMP/start_times.tsv" 2>/dev/null || echo 0)件" >&2

# (F) lesson_counts整形(数値ソート)
sort -t'|' -k1,1n "$TMP/lesson_counts_raw.tsv" > "$TMP/lesson_counts.tsv"
echo "  related_lessons: $(awk -F'|' '$2>0' "$TMP/lesson_counts_raw.tsv" 2>/dev/null | wc -l)件にデータあり" >&2

# --- (G) BLOCK理由の正規化: category|period|cmd_num|date ---
awk -F'\t' '$3 == "BLOCK" {
    split($4, reasons, "|")
    cmd = $2; gsub(/cmd_/, "", cmd); cmd_num = cmd + 0
    date = substr($1, 1, 10)
    for (i in reasons) {
        r = reasons[i]
        # 忍者名を除去して正規化
        gsub(/^[a-z]+:/, "", r)
        if (r ~ /^missing_gate:/) category = r
        else if (r ~ /lesson_candidate/) category = "lesson_candidate_issue"
        else if (r ~ /lesson_done/) category = "lesson_done_issue"
        else if (r ~ /unreviewed_lessons/) category = "unreviewed_lessons"
        else if (r ~ /purpose_validation/) category = "purpose_validation_issue"
        else if (r ~ /vercel_phase/) category = "vercel_phase_issue"
        else if (r ~ /review report/) category = r
        else if (r ~ /draft_lessons/) category = "draft_lessons"
        else category = "other:" r
        if (cmd_num <= 300) period = "P1"
        else if (cmd_num <= 600) period = "P2"
        else period = "P3"
        print category "\t" period "\t" cmd_num "\t" date
    }
}' "$GATE_LOG" > "$TMP/block_reasons.tsv"

echo "[前処理完了]" >&2
echo "" >&2

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

echo "============================================================"
echo "ラルフループ効果検証レポート"
echo "計測日: $(date '+%Y-%m-%d %H:%M')"
echo "データ範囲: cmd_126〜cmd_1117+ (gate_metrics: cmd_158〜)"
echo "============================================================"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 指標1: 同一パターン再発率
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "指標1: 同一パターン再発率"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "定義: 各教訓のsource_cmd登録日以降に、同一タグ組合せの教訓が"
echo "      再度登録されていれば「同種ミス再発」としてカウント"
echo ""

awk -F'|' '
{
    id = $1; src = $2; dt = $3; tags_raw = $4
    # タグをソートして正規化パターンを生成
    n = split(tags_raw, ta, ",")
    for (i = 1; i <= n; i++)
        for (j = i+1; j <= n; j++)
            if (ta[i] > ta[j]) { tmp = ta[i]; ta[i] = ta[j]; ta[j] = tmp }
    pattern = ""
    for (i = 1; i <= n; i++) pattern = (pattern == "" ? ta[i] : pattern "," ta[i])
    if (pattern == "") pattern = "(no-tags)"

    # 最早日を追跡
    if (!(pattern in first_date) || dt < first_date[pattern]) {
        first_date[pattern] = dt
        first_id[pattern] = id
    }
    count[pattern]++
    all_entries++
    entries[++eidx] = pattern SUBSEP dt SUBSEP id
}
END {
    # 再発数: 同一パターンの初回以降に登録された教訓
    recur = 0
    for (i = 1; i <= eidx; i++) {
        split(entries[i], e, SUBSEP)
        pat = e[1]; dt = e[2]; lid = e[3]
        if (lid != first_id[pat] && dt >= first_date[pat]) recur++
    }

    unique_patterns = 0; multi_patterns = 0
    for (p in count) {
        unique_patterns++
        if (count[p] > 1) multi_patterns++
    }

    printf "教訓総数: %d\n", all_entries
    printf "一意パターン(タグ組合せ)数: %d\n", unique_patterns
    printf "複数回出現パターン数: %d\n", multi_patterns
    printf "再発教訓数(初回除く): %d\n", recur
    printf "再発率: %.1f%% (%d/%d)\n\n", (all_entries > 0 ? recur * 100 / all_entries : 0), recur, all_entries

    # 上位再発パターン
    printf "上位再発パターン(3件以上):\n"
    printf "  %-50s  件数  初出日\n", "タグ組合せ"
    printf "  ──────────────────────────────────────────────────  ────  ──────────\n"
    for (p in count) {
        if (count[p] >= 3)
            printf "  %-50s  %4d  %s\n", p, count[p], first_date[p]
    }
}
' "$TMP/lessons.tsv"

echo ""
echo "  [補足A] BLOCK理由の期間別推移(教訓により消滅したBLOCK理由の確認):"
echo ""
printf "  %-50s  %4s  %4s  %4s\n" "BLOCK理由" "P1" "P2" "P3"
printf "  ──────────────────────────────────────────────────  ────  ────  ────\n"
awk -F'\t' '{
    cat = $1; period = $2
    count[cat][period]++
    cats[cat] = 1
}
END {
    for (c in cats) {
        p1 = count[c]["P1"]+0; p2 = count[c]["P2"]+0; p3 = count[c]["P3"]+0
        printf "  %-50s  %4d  %4d  %4d\n", c, p1, p2, p3
    }
}' "$TMP/block_reasons.tsv" | sort

echo ""
awk -F'\t' '{
    cat = $1; period = $2
    seen[cat][period] = 1
}
END {
    total = 0; recurring = 0; resolved = 0; new_in_p3 = 0
    for (c in seen) {
        total++
        np = 0; for (p in seen[c]) np++
        if (np > 1) recurring++
        has_early = (("P1" in seen[c]) || ("P2" in seen[c]))
        has_p3 = ("P3" in seen[c])
        if (has_early && !has_p3) resolved++
        if (!has_early && has_p3) new_in_p3++
    }
    printf "  BLOCK理由カテゴリ総数: %d\n", total
    printf "  複数期間で再発: %d (%.1f%%)\n", recurring, (total>0 ? recurring*100/total : 0)
    printf "  初期→P3消滅(教訓で解決): %d\n", resolved
    printf "  P3で新規出現: %d\n", new_in_p3
}' "$TMP/block_reasons.tsv"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 指標2: 差し戻し率の時系列推移
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "指標2: 差し戻し率の時系列推移"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "期間分割: P1=cmd_1〜300 / P2=cmd_301〜600 / P3=cmd_601〜885+"
echo ""

echo "[A] GATEベース: 各cmdの初回GATE判定結果"
echo ""
awk -F'|' '
{
    cmd = $1 + 0; outcome = $2
    if (cmd <= 300) p = 1
    else if (cmd <= 600) p = 2
    else p = 3
    total[p]++
    if (outcome == "BLOCK") block[p]++
    else clear[p]++
}
END {
    printf "  期間             cmd数  初回BLOCK  初回CLEAR  初回BLOCK率\n"
    printf "  ──────────────────────────────────────────────────────────\n"
    labels[1] = "P1(1-300)    "; labels[2] = "P2(301-600)  "; labels[3] = "P3(601-885+) "
    ta = 0; ba = 0
    for (i = 1; i <= 3; i++) {
        t = total[i]+0; b = block[i]+0; c = clear[i]+0
        rate = (t > 0 ? b * 100 / t : 0)
        printf "  %s  %5d  %9d  %9d  %10.1f%%\n", labels[i], t, b, c, rate
        ta += t; ba += b
    }
    printf "  ──────────────────────────────────────────────────────────\n"
    printf "  合計             %5d  %9d  %9d  %10.1f%%\n", ta, ba, ta-ba, (ta>0 ? ba*100/ta : 0)
}
' "$TMP/gate_outcomes.tsv"

echo ""
echo "[B] レポートベース: verdict別集計"
echo ""
awk -F'|' '
{
    cmd = $1 + 0; v = $2
    if (cmd <= 300) p = 1
    else if (cmd <= 600) p = 2
    else p = 3
    total[p]++
    vl = tolower(v)
    if (vl == "pass" || vl == "lgtm" || vl == "clear" || vl == "superseded") pass[p]++
    else if (vl ~ /fail/) fail[p]++
    else if (vl ~ /^ac[0-9]/) pass[p]++
    else other[p]++
}
END {
    printf "  期間             レポート数  PASS系  FAIL系  他/不明  FAIL率\n"
    printf "  ────────────────────────────────────────────────────────────────\n"
    labels[1] = "P1(1-300)    "; labels[2] = "P2(301-600)  "; labels[3] = "P3(601-885+) "
    for (i = 1; i <= 3; i++) {
        t = total[i]+0; pa = pass[i]+0; fa = fail[i]+0; ot = other[i]+0
        rate = (t > 0 ? fa * 100 / t : 0)
        printf "  %s  %10d  %6d  %6d  %7d  %6.1f%%\n", labels[i], t, pa, fa, ot, rate
    }
}' "$TMP/verdicts.tsv"

echo ""
echo "  注: P1/P2初期はレポート形式未標準化。cmd_471以降に標準化開始。"
echo "      verdict文字列が長文(AC列挙等)の場合は「他/不明」に分類。"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 指標3: cmd完了速度の推移
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "指標3: cmd完了速度の推移"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "方法: delegated_at(またはtimestamp) → GATE CLEAR時刻の差分(分)"
echo ""

# start_timesとclear_timesを突合
join -t'|' -j1 \
    <(sort -t'|' -k1,1 "$TMP/start_times.tsv") \
    <(sort -t'|' -k1,1 "$TMP/clear_times.tsv") \
    > "$TMP/time_joined.tsv" 2>/dev/null || true

if [ -s "$TMP/time_joined.tsv" ]; then
    awk -F'|' '
    function to_minutes(ts) {
        gsub(/[+][0-9:]+$/, "", ts)
        gsub(/T/, " ", ts)
        split(ts, parts, " ")
        split(parts[1], ymd, "-")
        if (length(parts) >= 2)
            split(parts[2], hms, ":")
        else { hms[1] = 0; hms[2] = 0 }
        d = (ymd[2]+0 - 1) * 30 + ymd[3]+0
        return d * 1440 + hms[1]+0 * 60 + hms[2]+0
    }
    {
        cmd = $1 + 0
        s = to_minutes($2)
        e = to_minutes($3)
        delta = e - s
        if (delta < 0 || delta >= 1440) next  # >=24h or 負値は除外
        if (cmd <= 300) p = 1
        else if (cmd <= 600) p = 2
        else p = 3
        sum[p] += delta; count[p]++; all_sum += delta; all_count++
        # min/max tracking
        if (!(p in mn) || delta < mn[p]) mn[p] = delta
        if (!(p in mx) || delta > mx[p]) mx[p] = delta
    }
    END {
        printf "  期間             計測cmd数  平均(分)  最短(分)  最長(分)\n"
        printf "  ────────────────────────────────────────────────────────\n"
        labels[1] = "P1(1-300)    "; labels[2] = "P2(301-600)  "; labels[3] = "P3(601-885+) "
        for (i = 1; i <= 3; i++) {
            c = count[i]+0; avg = (c > 0 ? sum[i] / c : 0)
            mmin = (c > 0 ? mn[i] : 0); mmax = (c > 0 ? mx[i] : 0)
            printf "  %s  %9d  %8.1f  %8.1f  %8.1f\n", labels[i], c, avg, mmin, mmax
        }
        printf "  ────────────────────────────────────────────────────────\n"
        avg_all = (all_count > 0 ? all_sum / all_count : 0)
        printf "  合計             %9d  %8.1f\n", all_count, avg_all
    }
    ' "$TMP/time_joined.tsv"
else
    echo "  データ不足: delegated_atとGATE CLEARの突合が取れたcmdなし"
fi

echo ""
echo "  注: cmd_500以前はdelegated_atフィールド未導入のためデータ少。"
echo "      24時間超のcmd(大型偵察等)は異常値として除外。"
echo "      月30日近似のため±1日の誤差あり。"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 指標4: 教訓注入量とCLEAR率の相関
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "指標4: 教訓注入量とCLEAR率の相関"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "方法: 各cmdのrelated_lessons件数別に初回GATE判定(CLEAR/BLOCK)率を比較"
echo ""

# lesson_countsとgate_outcomesを突合
join -t'|' -j1 \
    <(sort -t'|' -k1,1 "$TMP/lesson_counts.tsv") \
    <(sort -t'|' -k1,1 "$TMP/gate_outcomes.tsv") \
    > "$TMP/lesson_outcome.tsv" 2>/dev/null || true

if [ -s "$TMP/lesson_outcome.tsv" ]; then
    awk -F'|' '
    {
        cmd = $1; lcount = $2 + 0; outcome = $3
        if (lcount == 0) bucket = "0件"
        else if (lcount <= 3) bucket = "1-3件"
        else bucket = "4件以上"
        total[bucket]++
        if (outcome == "CLEAR") clear[bucket]++
    }
    END {
        printf "  教訓注入量   cmd数   初回CLEAR   CLEAR率\n"
        printf "  ──────────────────────────────────────────\n"
        order[1] = "0件"; order[2] = "1-3件"; order[3] = "4件以上"
        for (i = 1; i <= 3; i++) {
            b = order[i]; t = total[b]+0; c = clear[b]+0
            rate = (t > 0 ? c * 100 / t : 0)
            printf "  %-10s  %6d  %9d  %7.1f%%\n", b, t, c, rate
        }
    }
    ' "$TMP/lesson_outcome.tsv"
else
    echo "  データ不足: lesson_countsとgate_outcomesの突合なし"
fi

echo ""
echo "  注: related_lessons機能はcmd_158で導入。"
echo "      archived cmds $(wc -l < "$TMP/all_cmds.txt")件中、"
echo "      related_lessonsフィールドを持つのは$(wc -l < "$TMP/has_lessons.tsv")件のみ。"
echo "      大部分のcmdは教訓注入記録なし(0件扱い)。"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 指標5: PI(Production Invariant)違反再発率
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "指標5: PI(Production Invariant)違反再発率"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "方法: 各PIのsource_cmd以降にproduction_invariantタグ付き教訓が"
echo "      新規登録されたか確認(同種問題の再発を示唆)"
echo ""

# PI情報抽出
awk '
/- id: PI-/ { pi_id = $3; pi_fact = "" }
/fact:/ && pi_id != "" {
    f = $0; sub(/.*fact: *"?/, "", f); gsub(/"$/, "", f)
    pi_fact = substr(f, 1, 60)
}
/source:/ && pi_id != "" {
    s = $0
    if (match(s, /cmd_[0-9]+/)) {
        cmd = substr(s, RSTART+4, RLENGTH-4)
        print pi_id "|" cmd "|" pi_fact
    }
    pi_id = ""
}
' "$DM_PROJECT" > "$TMP/pi_data.tsv"

printf "  %-7s  %-10s  %s  %s\n" "PI" "source" "再発教訓" "概要"
printf "  ────────────────────────────────────────────────────────────────────\n"

total_pi=0
recur_pi=0
while IFS='|' read -r pi_id src_cmd pi_fact; do
    total_pi=$((total_pi + 1))

    # source_cmd以降にproduction_invariantタグの教訓が登録されたか
    post_lessons=$(awk -F'|' -v threshold="$src_cmd" '
        $2+0 > threshold+0 && $4 ~ /production_invariant/ { count++ }
        END { print count+0 }
    ' "$TMP/lessons.tsv")

    if [ "$post_lessons" -gt 0 ]; then
        recur_pi=$((recur_pi + 1))
        status="YES($post_lessons件)"
    else
        status="NO"
    fi

    printf "  %-7s  cmd_%-5s  %-12s  %s\n" "$pi_id" "$src_cmd" "$status" "$pi_fact"
done < "$TMP/pi_data.tsv"

echo ""
if [ "$total_pi" -gt 0 ]; then
    rate=$(awk "BEGIN { printf \"%.1f\", $recur_pi * 100 / $total_pi }")
    echo "  PI総数: $total_pi"
    echo "  登録後に関連教訓が再発: $recur_pi件 ($rate%)"
else
    echo "  PIデータなし"
fi

echo ""
echo "  注: PIは主にcmd_1025〜1098に集中(直近2026-03)。"
echo "      データ蓄積期間が短いため再発判定は参考値。"
echo "      「再発教訓」=source_cmdが当該PI source以降かつ"
echo "      production_invariantタグ付きの教訓。"
echo ""

echo "============================================================"
echo "計測完了"
echo "============================================================"
