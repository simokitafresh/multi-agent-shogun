# precompute全量最速化 — /goal自律ループ設計書 v1.1

- v1.1: 家老覚醒レビュー(blt_20260710_032048、APPROVE WITH FIXES)の修正必須3点を反映: 評価器凍結(§4)+canonical parity定義(§4)+immutable baseline DB(§7)。追加推奨(H1/H3のAC数値化+P4区間計測)も反映
- 起票: 将軍 2026-07-10 03:11 | 殿指示「precompute全量を最速で実行するための/goalを使った設計書を作ろう」
- 対象: DM-Signal `backend/app/jobs/precompute_raw.py`（Layer 5 raw API precompute job）
- 駆動装置: Codex CLI `/goal`（自律目標モード。2026-06-23家老実証済み: Goal active→実行→Goal achieved）
- origin: `[[殿観測20260709_2353_precompute遅い]] -> [[殿指示20260710_0311_goal設計書]] -> [[precompute-fullspeed-goal-design]]`

## §0 大原則

1. **本番が正・出力不変**: 高速化はPrecomputedRawの**出力バイト等価**（同一DB状態からの raw_json 完全一致）を保ったまま行う。数値・構造を1バイトでも変える変更は不採用
2. **可逆なら行動せよ（殿裁定2026-07-10 02:41/02:46）**: コード変更はrevert可能=裁可待ち不要。ローカルテストPASS+revert手順明確なら自走deploy、失敗はrevert+事実報告（§42v2）
3. **基準は探索（殿速度3原則）**: 目標値を先に固定しない。理論下限（支配的コストの計測値）を先に測り、それに漸近するまで回す
4. **計測なき改善は改善ではない**: 全iterationで before→after 数値を記録。安全パターン（try/except, invalidate順序等）の削除によるスピードアップは禁止（check_safety_pattern_removal準拠）

## §1 As-Is（実測 2026-07-09〜10）

- 実装: `precompute_raw_for_portfolios()` — docstring明記「one PF at a time」の**完全直列ループ**。並列化なし（ThreadPool/asyncio/multiprocessing 0件をgrepで確認）
- 実測: fullrecalculate(id=196)の尻尾で **103PF×約4秒/PF ≒ 7分**、`rss=1923.8MB`
- 1PFあたりの中身: 6種ビルダー（performance/monthly_returns/annual_returns/drawdowns/rolling_returns/monthly_trade）×複数パラメータ=**15行/PF** のraw_json生成+upsert
- 既存の部分最適: compare_returns_bulk/metrics_summary_bulkは先頭でbulk一括生成済み（先行最適化の余地実証）。partial recalc時は対象PFのみ（cmd_3804裁定で採用済み）
- 発生頻度: fullrecalculate毎+日次cron再計算の尻尾=**毎日全ユーザーの画面鮮度に直結**

## §2 To-Be

- 全量precompute（103PF×15行）を出力等価のまま**理論下限に漸近**させる
- 副次: rssピークの削減（1.9GBは並列化の障害になる）
- 完了定義: /goalループのstop condition（§4）到達+パリティゲートPASS+本番実測

## §3 改善仮説（/goalループの初期弾。順序は計測が決める）

| # | 仮説 | 期待 | リスク |
|---|---|---|---|
| H1 | PF間並列化（DBセッション分離のworker N並列。one-PF-at-a-timeの解消） | 支配的。コア数分の短縮 | DBセッション共有不可・rss×N。要セッションfactory設計 |
| H2 | PF内6ビルダーの共通中間データ再利用（月次リターン系列を6回別々に引いている疑い→1回取得して共有） | PF内の重複I/O消滅 | ビルダー間の暗黙依存。要プロファイルで確定 |
| H3 | bulk化の横展開（compare_returns_bulk方式を per-PF エンドポイントにも: 全PFの月次系列を1クエリで先読み） | DB往復をO(PF)→O(1) | メモリ増。チャンク分割で対処（殿原則: チャンクに分けよ） |
| H4 | jsonable_encoder/serializeの高速化（orjson等価出力 or 事前dict化） | CPU時間削減 | 出力バイト差（float表現）。パリティゲートで検出 |
| H5 | upsertのexecutemany/COPY化 | 書込み時間削減 | dialect差。get_insert_dialect既存準拠 |
| H6 | gc/rss管理（GS道具磨き第二弾のGC条件化と同型: 強制gcの条件化） | 直列でも数%〜 | OOM再発。RSS閾値ガード維持（cmd_3776前例） |

## §4 /goalループ設計（Loop Engineering準拠: generator/evaluator分離）

**goal忍者（Codex、generator）への/goal文（雛形）**:

```
/goal DM-Signalのprecompute全量(103PF)をローカル環境で最速化せよ。
反復手順: (1)ベンチ実行(scripts/oneshot/cmd_XXXX_precompute_bench.py、全量+PF別秒割りを記録)
(2)最遅コンポーネントをプロファイルで特定 (3)出力等価の改善を1つ実装
(4)パリティゲート(scripts/oneshot/cmd_XXXX_precompute_parity.py=修正前後のPrecomputedRaw raw_json全行diff)PASS確認
(5)再ベンチして数値をdocs/research/cmd_XXXX_precompute_speedup.mdへ累積追記。
stop condition: 直近2 iterationの改善が各5%未満、またはH1-H6全仮説消化。
禁止: raw_json出力の変更、安全パターン削除、本番DBへの書込み。
```

- **evaluator分離+凍結（レビュー修正1）**: bench/parityの2スクリプトは**/goal開始前に非goal側（別忍者、家老レビュー）で作成・凍結**する。凍結commit hashを記録し、goal忍者はこの2ファイルを変更禁止（変更を含むiterationは無効）。generatorが評価基準を都合よく変えられない構造にする（評価器汚染防止）
- **parity判定のFP防止（レビュー修正2）**: 「バイト等価」はPostgres JSON化・辞書キー順・float表現で偽陽性/偽陰性化し得る。SSOTは**canonical JSON hash（`json.dumps(sort_keys=True, separators=(',',':'))`のhash）+Pythonオブジェクト等価**の2判定。`computed_at`等の非出力メタ列は比較対象外と明記
- **stop condition明文化**（blind loop防止）: 改善飽和(2連続<5%) or 仮説消化。token blowout防止でiteration上限=10
- **各iterationの記録契約**: iteration番号/変更1行要約/全量秒数(3回中央値)/rssピーク/パリティ判定(canonical hash一致=必須)。記録なきiterationは無効
- 環境: **immutable baseline方式（レビュー修正3）** — 本番同期のbaseline dumpを凍結→作業DBはそこからclone→パリティは常にbaseline由来の期待値と比較。DB snapshot id/source commit/seedを記録必須。共有ローカルDBの直接使用は禁止（他cmdの書込みで期待値が汚れる）。本番非接触=cmd_3812等と完全並列可

## §5 Phase構成

| Phase | 内容 | 完了条件 |
|---|---|---|
| P1 ベンチ+パリティ道具（評価器） | 全量ベンチ(PF別・ビルダー別秒割り)+canonical parityゲートの2道具を**非goal側で**作成・レビュー・凍結。baseline DB dump作成。理論下限(総I/O+総CPU の実測)を推定 | 道具2本の凍結hash+baseline snapshot id+初回ベンチ数値+下限推定 |
| P2 /goalループ | §4のgoalをCodex忍者に設定し自律反復。H1並列化はDB pool size/worker別Session/RSS閾値/chunk sizeをACで数値指定、H3 bulk化はメモリ上限を数値化 | stop condition到達。全iteration数値記録 |
| P3 検証 | canonical parityゲートPASS+既存テスト全PASS+回帰テスト追加 | テスト全PASS |
| P4 本番反映 | §42v2で自走deploy→本番実測は**L5/precompute区間の開始終了ログで区間計測**(fullrecalculate全体ではなく)→before 7分と比較→失敗ならrevert | 本番区間実測数値の報告 |

- **P1とP2は別cmdに分離**（レビュー修正1: 評価器を先に凍結してからgeneratorを走らせる）。cmd分割は P1 / P2 / P3+P4 の3本を基本とする
- 配備: goal忍者はCodex CLIの忍者（M:GPT）を優先（/goalはCodex機能）。他忍者・他cmdと並列可

## §6 5W1H

- WHY: 全量precompute7分が毎再計算の尻尾として恒常発生し、画面鮮度と検証サイクルを遅延させる
- WHAT: 出力等価のまま理論下限に漸近する高速化を/goal自律ループで探索
- WHEN: 即時（パリティ計画と独立・並列）
- WHERE: `backend/app/jobs/precompute_raw.py`+ビルダー群（ローカルで開発、§42v2でdeploy）
- WHO: goal忍者(Codex)=generator、パリティゲート+軍師=evaluator、家老=配備・監視
- HOW: ベンチ→プロファイル→改善→パリティ→再ベンチの自律反復（§4）
- 複利: 高速化は日次cron・全fullrecalculate・全パリティ検証サイクルに毎回効く

## §7 着手前提・無効化条件

- 前提: ローカルDBが本番同期であること（gs_price_preflight系の確認）。/goalが対象忍者CLIで動作すること（v0.142.0実証済み）
- 無効化: precompute_rawのスキーマ・エンドポイント構成が変わったら理論下限を再計測

## 因果リンク

- [[殿観測20260709_2353_precompute遅い]] -> [[one_PF_at_a_time直列7分]] -> [[precompute-fullspeed-goal-design]]
- [[codex_goal_mode]] -> [[Loop_Engineering_generator_evaluator分離]] -> [[goal自律最適化ループ]]
- [[殿裁定20260710_0241_可逆なら行動せよ]] -> [[§42v2自走deploy]] -> [[P4本番実測]]
