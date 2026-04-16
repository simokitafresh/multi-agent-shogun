#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT_UNDER_TEST="$PROJECT_ROOT/scripts/gist_index_update.sh"
    [ -f "$SCRIPT_UNDER_TEST" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gist_index_update.XXXXXX")"
    export MOCK_BIN="$TEST_TMPDIR/bin"
    export GIST_OUTPUT_FILE="$TEST_TMPDIR/gist-index.md"
    export GIST_EDIT_ARGS_FILE="$TEST_TMPDIR/gist-edit-args.txt"
    mkdir -p "$MOCK_BIN"

    cat > "$TEST_TMPDIR/gist-list.txt" <<'EOF'
83a17157247174e9faefc3962968fe1b	DM-Signal Gist Index — 全gist一覧（随時更新）	1 file	public	2026-04-15T16:43:18Z
268715f0b033f4179baced214b2867dc	21体から最強の3体を選べ — 1,330通り全探索で分かったこと	1 file	public	2026-04-15T16:30:07Z
520a406c64d2169ca5071c1c9e4f008b	deepdive_why_chain_20260321.md	1 file	public	2026-04-15T09:53:54Z
eb537820afa71cd07f3c12389e9b5318	因果探索原則 — 記憶するな、たどれ (2026-04-15)	1 file	public	2026-04-15T09:40:34Z
e83099b20ad9137fb24e8877f1733e8d	note記事下書き: AIが作ったバックテスト戦略、信じていいの? — 過剰最適化を見抜く5つの検証	1 file	public	2026-04-14T17:16:46Z
0bb2e881fb9d97cac50fb593a8488f60	奥義α6指標 完全解説 — L2 168体・L3 3486ペアのβ調整堅牢性分析	1 file	public	2026-04-14T17:07:13Z
0223c24ec96712982a461ec61353b274	DM-Signal Weekly 2026-04-14	1 file	public	2026-04-14T11:11:24Z
8de3643d8f064c687394437f1beaa2b1	L2奥義168体 完全解説 — 2×2因子分析・β調整・本番DB登録推薦	1 file	public	2026-04-13T18:05:56Z
9893007f059d87db8059eee076a1f504	SPA検定はなぜ株価で使えないのか — SPYを過適合と判定する理論の矛盾	1 file	secret	2026-04-12T05:50:09Z
de927193b98f43c5515d0e73483180bd	cmd_1852: L0/L1/L2 β調整α分析	1 file	public	2026-04-10T23:21:53Z
5f2468312ed5cdb052b0ecaa472ea88f	cmd_1850: CPCV 3層比較レポート (L0四神12体/L1スキップ/L2奥義シン忍法20体×7忍法)	1 file	public	2026-04-10T17:19:16Z
8b6c7877f450c9e5acbbf53c496fdc80	cmd_1847 21チャンピオン近傍パラメータ分析 (okugi_shin_ninpo_20body GS)	1 file	secret	2026-04-10T16:59:08Z
db49e13f85f49b520f671291a3ee795e	cmd_1848: GS IS/OOS チャンピオン分析 (前半IS選出 + OOS劣化率テーブル)	1 file	public	2026-04-10T16:54:44Z
80b4451ae3a2333e9904fb16fe096369	cmd_1849 space quality analysis	1 file	public	2026-04-10T16:49:48Z
10676115aedb50743799fb14c66940b6	cmd_1846: GS21チャンピオン selection_timeline分析	1 file	secret	2026-04-10T16:45:17Z
b0e5db4d1f66311ea33a79df79561a7b	cmd_1846: GS21チャンピオン selection_timeline分析	1 file	secret	2026-04-10T16:44:00Z
25f4843c3ee01d3f641cd5bf9c56bc90	cmd_1845: シン忍法3層メトリクス比較表 (20+21+21体, 6メトリクス)	1 file	public	2026-04-10T15:39:23Z
b6b6a8392eb96cdc08931b0d66a4efab	cmd_1845: シン忍法3層メトリクス比較表 (20+21+21体, 6メトリクス)	1 file	public	2026-04-10T14:47:03Z
7216120c4b48d565f0d0de35ae315830	cmd_1845: シン忍法3層メトリクス比較表 (20+21+21体, 6メトリクス)	1 file	public	2026-04-10T14:46:40Z
59e4a14a12abf02da2a27e9cb2964a8e	cmd_1845: シン忍法3層メトリクス比較表 (20+21+21体, 6メトリクス)	1 file	public	2026-04-10T14:38:27Z
395177cab204cd3a2c5ac7b8f0179318	奥義-シン忍法 GS事後チャンピオン21体 (cmd_1844)	1 file	secret	2026-04-10T14:17:51Z
ea687a966e627b5e454524004fdd747e	ALM忍法19体 全メトリクス一覧 (2026-04-06)	4 files	public	2026-04-06T10:37:53Z
4fcef9ea238d4f236bd7aaf9da1a6237	バグ報告 — 月初シグナル表示の遅延について (2026-04-02)	1 file	public	2026-04-02T06:48:48Z
4aca8c1c909ce511c40e322b44335fa4	DM-Signal シグナル表示差異 調査報告書 (2026-04-02)	1 file	public	2026-04-02T06:11:43Z
aa7d9a9fc8840553af5a7e561edf44be	Standard PF前処理研究日誌 (2026-03-31)	1 file	secret	2026-04-03T15:07:05Z
e713be610888d700dd1b2c298fb3fcf2	DM-Signal Weekly Report 2026-03-26	1 file	public	2026-03-26T08:11:23Z
38ffd4c0074f4ab75c169d05f4ff6f60	DM-Signal User Manual (Standard Tier)	1 file	public	2026-03-26T06:26:36Z
f7c8363faff9dbf8082d2edee654bbca	シン忍法v2 20体パフォーマンス8指標一覧 (cmd_1381)	1 file	secret	2026-03-24T15:17:26Z
e7e3286a497855389f9f2160d2b3a411	シン忍法v2 20体パフォーマンス8指標一覧 (cmd_1381)	1 file	public	2026-03-24T15:16:01Z
f8808f17b7ff114a0578a03bd1eb6cad	シン忍法v2 21体パフォーマンス一覧 (Step 4完了 2026-03-24)	1 file	public	2026-03-24T09:35:39Z
aa3ee2327d3ce18bf91665ce0b788081	シン四神v2 12体チャンピオン (cmd_1363)	1 file	public	2026-03-24T05:06:07Z
5a5ae108166003f17a934a099b1de847	WHY深掘り全記録 — 観察スキップからシステム免疫論へ (2026-03-21)	1 file	public	2026-03-24T03:58:12Z
8e81b767ea84a229f0db6ab78babab96	WHY深掘り全記録 2026-03-23 — 累積値の盲点から統計的車輪カタログへ	1 file	public	2026-03-23T06:39:05Z
b5af6bff7780afd261ad1341fa519c30	将軍必読ドキュメント - WHY深掘り全記録	1 file	secret	2026-03-21T20:00:06Z
eaaccfa00795230e48f4c06bc104dbdf	将軍必読: Why Chain Deep Dive (Phase 1-14) — 思考過程の全記録	1 file	public	2026-03-21T16:48:52Z
3c9c02fc8072f97b888d0eec4e737015	shin_ninpo_v2_12body_champions.csv	1 file	public	2026-03-20T17:34:29Z
312f815aa5cbff37c184fb4b9904e6ab	deepdive_why_chain_20260321.md	1 file	public	2026-03-20T17:33:23Z
53e43148af06be1f3375df324848451d	cmd_1010: 四神12体+忍法15体 極値プロファイル・相関構造・忍法コンビネーション分析	1 file	public	2026-03-16T12:25:26Z
f30323142cd05cccdfae13a41c51a2f1	p̄ (p-average) バックテスト総合レポート — DM-Signal 四神PF 5シリーズ288テスト全結果	1 file	public	2026-03-16T11:10:59Z
56fcb4630c95e2dfd84979b847457eeb	p平均法 note記事下書き	1 file	secret	2026-03-15T19:45:11Z
81057c73b1f6df0cf27f1d416dbaa3e4	確定申告2025 自動化フロー全体像（cmd_704〜cmd_941）	1 file	public	2026-03-14T08:57:01Z
98d300b1711f9a035a7998d0e6e1d118	確定申告パイプライン2025 失敗の構造と来年への改善 将軍反省報告書	1 file	public	2026-03-14T07:13:33Z
ee2bbbb82ee2564d8dec53c1777dbca3	確定申告2025 年度統合パイプライン実行報告+汚染復旧 将軍報告書 2026-03-14	1 file	public	2026-03-14T04:38:16Z
df87af65eb93b6c1d6959882bb88f963	gstack知見取込 As-Is/To-Be/Why/What 将軍報告書 2026-03-14	1 file	public	2026-03-14T03:34:28Z
eed799f728ea974de99b94d516c8c792	個人事業経費管理 README (cmd_898)	1 file	secret	2026-03-13T04:02:24Z
dda6b5deed56cbe6fbf32fd23e24143c	7システム比較ドキュメント (ACE/Vercel/GSD/gstack/おしお殿/Claude Teams/我が軍) 2026-03-13	1 file	secret	2026-03-12T17:14:18Z
3d1d0914bc28030d2c4a741af8aa12b6	DM-Signal Weekly Report 2026-03-10	1 file	public	2026-03-10T06:43:47Z
ab5f2c60d6cb6386619f12f8ee3184b3	6システム対比分析（将軍再分析版）2026-03-10	1 file	secret	2026-03-09T15:06:34Z
b7548f6aae74850e35b506b2fe0369e1	mcas dashboard	1 file	secret	2026-02-25T19:14:07Z
6eb495d917fb00ba4d4333c237a4ee0c	🏯 将軍ダッシュボード	1 file	secret	2026-04-15T16:46:34Z
92ab8267cf4fc957b9d95331ceb814c6	untitled52-ipynb.ipynb	1 file	secret	2025-03-20T18:46:45Z
bafcbaf19d6cef331b5af1dc4e3aa71f	Untitled52.ipynb のコピー	1 file	secret	2025-03-20T18:46:26Z
528f09bda03290c6034992ccaa1137fe	Untitled52.ipynb	1 file	secret	2025-03-20T17:59:39Z
EOF

    cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "gist" ] && [ "$2" = "list" ]; then
    cat "$TEST_TMPDIR/gist-list.txt"
    exit 0
fi
if [ "$1" = "gist" ] && [ "$2" = "edit" ]; then
    printf '%s\n' "$*" > "$GIST_EDIT_ARGS_FILE"
    cp "$6" "$GIST_OUTPUT_FILE"
    exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/gh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gist_index_update classifies current gist inventory, removes duplicates/ipynb, and updates index gist" {
    run env \
        PATH="$MOCK_BIN:$PATH" \
        TEST_TMPDIR="$TEST_TMPDIR" \
        GIST_OUTPUT_FILE="$GIST_OUTPUT_FILE" \
        GIST_EDIT_ARGS_FILE="$GIST_EDIT_ARGS_FILE" \
        GIST_INDEX_DATE="2026-04-16" \
        bash "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    [ -f "$GIST_OUTPUT_FILE" ]
    [[ "$output" == *"category_counts: note記事=7 週報=3 研究データ・分析レポート=16 deepdive・将軍記録=6 ユーザー向け=1 インフラ・確定申告・比較分析=9 前処理研究=1"* ]]
    [[ "$output" == *"excluded_counts: self_index=1 duplicate_title=6 ipynb=3"* ]]
    [[ "$output" == *"excluded reason=duplicate_title id=b0e5db4d1f66311ea33a79df79561a7b title=cmd_1846: GS21チャンピオン selection_timeline分析"* ]]
    [[ "$output" == *"excluded reason=ipynb id=528f09bda03290c6034992ccaa1137fe title=Untitled52.ipynb"* ]]
    [[ "$output" == *"updated gist 83a17157247174e9faefc3962968fe1b (gist-index.md)"* ]]
    [[ "$(cat "$GIST_EDIT_ARGS_FILE")" == gist\ edit\ 83a17157247174e9faefc3962968fe1b\ --filename\ gist-index.md\ /tmp/* ]]

    python3 - <<'PY' "$GIST_OUTPUT_FILE"
import re
import sys
from pathlib import Path

expected = {
    "21体から最強の3体を選べ — 1,330通り全探索で分かったこと": "note記事",
    "note記事下書き: AIが作ったバックテスト戦略、信じていいの? — 過剰最適化を見抜く5つの検証": "note記事",
    "奥義α6指標 完全解説 — L2 168体・L3 3486ペアのβ調整堅牢性分析": "note記事",
    "L2奥義168体 完全解説 — 2×2因子分析・β調整・本番DB登録推薦": "note記事",
    "SPA検定はなぜ株価で使えないのか — SPYを過適合と判定する理論の矛盾": "note記事",
    "p̄ (p-average) バックテスト総合レポート — DM-Signal 四神PF 5シリーズ288テスト全結果": "note記事",
    "p平均法 note記事下書き": "note記事",
    "DM-Signal Weekly 2026-04-14": "週報",
    "DM-Signal Weekly Report 2026-03-26": "週報",
    "DM-Signal Weekly Report 2026-03-10": "週報",
    "cmd_1852: L0/L1/L2 β調整α分析": "研究データ・分析レポート",
    "cmd_1850: CPCV 3層比較レポート (L0四神12体/L1スキップ/L2奥義シン忍法20体×7忍法)": "研究データ・分析レポート",
    "cmd_1847 21チャンピオン近傍パラメータ分析 (okugi_shin_ninpo_20body GS)": "研究データ・分析レポート",
    "cmd_1848: GS IS/OOS チャンピオン分析 (前半IS選出 + OOS劣化率テーブル)": "研究データ・分析レポート",
    "cmd_1849 space quality analysis": "研究データ・分析レポート",
    "cmd_1846: GS21チャンピオン selection_timeline分析": "研究データ・分析レポート",
    "cmd_1845: シン忍法3層メトリクス比較表 (20+21+21体, 6メトリクス)": "研究データ・分析レポート",
    "奥義-シン忍法 GS事後チャンピオン21体 (cmd_1844)": "研究データ・分析レポート",
    "ALM忍法19体 全メトリクス一覧 (2026-04-06)": "研究データ・分析レポート",
    "バグ報告 — 月初シグナル表示の遅延について (2026-04-02)": "研究データ・分析レポート",
    "DM-Signal シグナル表示差異 調査報告書 (2026-04-02)": "研究データ・分析レポート",
    "シン忍法v2 20体パフォーマンス8指標一覧 (cmd_1381)": "研究データ・分析レポート",
    "シン忍法v2 21体パフォーマンス一覧 (Step 4完了 2026-03-24)": "研究データ・分析レポート",
    "シン四神v2 12体チャンピオン (cmd_1363)": "研究データ・分析レポート",
    "shin_ninpo_v2_12body_champions.csv": "研究データ・分析レポート",
    "cmd_1010: 四神12体+忍法15体 極値プロファイル・相関構造・忍法コンビネーション分析": "研究データ・分析レポート",
    "deepdive_why_chain_20260321.md": "deepdive・将軍記録",
    "因果探索原則 — 記憶するな、たどれ (2026-04-15)": "deepdive・将軍記録",
    "WHY深掘り全記録 — 観察スキップからシステム免疫論へ (2026-03-21)": "deepdive・将軍記録",
    "WHY深掘り全記録 2026-03-23 — 累積値の盲点から統計的車輪カタログへ": "deepdive・将軍記録",
    "将軍必読ドキュメント - WHY深掘り全記録": "deepdive・将軍記録",
    "将軍必読: Why Chain Deep Dive (Phase 1-14) — 思考過程の全記録": "deepdive・将軍記録",
    "DM-Signal User Manual (Standard Tier)": "ユーザー向け",
    "確定申告2025 自動化フロー全体像（cmd_704〜cmd_941）": "インフラ・確定申告・比較分析",
    "確定申告パイプライン2025 失敗の構造と来年への改善 将軍反省報告書": "インフラ・確定申告・比較分析",
    "確定申告2025 年度統合パイプライン実行報告+汚染復旧 将軍報告書 2026-03-14": "インフラ・確定申告・比較分析",
    "gstack知見取込 As-Is/To-Be/Why/What 将軍報告書 2026-03-14": "インフラ・確定申告・比較分析",
    "個人事業経費管理 README (cmd_898)": "インフラ・確定申告・比較分析",
    "7システム比較ドキュメント (ACE/Vercel/GSD/gstack/おしお殿/Claude Teams/我が軍) 2026-03-13": "インフラ・確定申告・比較分析",
    "6システム対比分析（将軍再分析版）2026-03-10": "インフラ・確定申告・比較分析",
    "mcas dashboard": "インフラ・確定申告・比較分析",
    "🏯 将軍ダッシュボード": "インフラ・確定申告・比較分析",
    "Standard PF前処理研究日誌 (2026-03-31)": "前処理研究",
}

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert text.startswith("# DM-Signal Gist Index\n<!-- last_updated: 2026-04-16 -->"), text.splitlines()[:3]
assert "*53件中43件を掲載（インデックスgist自身=1、重複gist=6、ipynb系gist=3 を除外）*" in text

actual = {}
section = None
for line in text.splitlines():
    if line.startswith("## "):
        section = line[3:]
        continue
    if line.startswith("| ") and "](" in line:
        match = re.match(r"^\| [^|]+ \| \[(.+)\]\((https://gist\.github\.com/simokitafresh/[a-f0-9]{32})\) \|$", line)
        assert match, line
        title = match.group(1)
        actual[title] = section

assert actual == expected, {"missing": sorted(set(expected) - set(actual)), "extra": sorted(set(actual) - set(expected)), "mismatch": {k: (expected.get(k), actual.get(k)) for k in expected if actual.get(k) != expected.get(k)}}
assert "DM-Signal Gist Index — 全gist一覧（随時更新）" not in actual
assert "Untitled52.ipynb" not in actual
assert "Untitled52.ipynb のコピー" not in actual
assert "untitled52-ipynb.ipynb" not in actual
PY
}
