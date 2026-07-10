# precompute全量最速化 — /goal自律ループ設計書 v1.4

- v1.4: 殿裁定「少数PFで高速化を実現するまで反復し、少しずつ対象PFを増やす」を反映。探索対象を `3→10→25→50→103PF` の段階昇格制へ変更し、各段階で速度改善+parity PASSを昇格条件とした
- v1.3: 殿レビュー「全量を実行するため改善サイクルが極端に長い」を反映。各iterationの全量3回を廃止し、全103PFを維持したD1変更対象1回→D2全量1回+parity→D3最終候補のみ全量3回の三段ゲートへ変更
- v1.2: Gist revision `11928e1ae8e850360d67d87e211252942eec1701`を実行実績で再レビュー。P1完了、P2/H2初回結果、日付境界で発生したparity 868件FAIL、同一logical date比較、合格iterationのみをstop conditionへ算入する規則を反映
- v1.1: 家老覚醒レビュー(blt_20260710_032048、APPROVE WITH FIXES)の修正必須3点を反映: 評価器凍結(§4)+canonical parity定義(§4)+immutable baseline DB(§7)。追加推奨(H1/H3のAC数値化+P4区間計測)も反映
- 起票: 将軍 2026-07-10 03:11 | 殿指示「precompute全量を最速で実行するための/goalを使った設計書を作ろう」
- 対象: DM-Signal `backend/app/jobs/precompute_raw.py`（Layer 5 raw API precompute job）
- 駆動装置: Codex CLI `/goal`（自律目標モード。2026-06-23家老実証済み: Goal active→実行→Goal achieved）
- origin: `[[殿観測20260709_2353_precompute遅い]] -> [[殿指示20260710_0311_goal設計書]] -> [[precompute-fullspeed-goal-design]]`

## §0 大原則

1. **本番が正・出力不変**: 高速化はPrecomputedRawの**意味的出力等価**（同一DB状態・同一logical dateからのcanonical JSON hash一致+Pythonオブジェクト等価）を保ったまま行う。数値・構造を変える変更は不採用
2. **可逆なら行動せよ（殿裁定2026-07-10 02:41/02:46）**: コード変更はrevert可能=裁可待ち不要。ローカルテストPASS+revert手順明確なら自走deploy、失敗はrevert+事実報告（§42v2）
3. **基準は探索（殿速度3原則）**: 目標値を先に固定しない。理論下限（支配的コストの計測値）を先に測り、それに漸近するまで回す
4. **計測なき改善は改善ではない**: 全iterationで before→after 数値を記録。安全パターン（try/except, invalidate順序等）の削除によるスピードアップは禁止（check_safety_pattern_removal準拠）

## §1 As-Is（実測 2026-07-09〜10）

- 実装: `precompute_raw_for_portfolios()` — docstring明記「one PF at a time」の**完全直列ループ**。並列化なし（ThreadPool/asyncio/multiprocessing 0件をgrepで確認）
- 実測: fullrecalculate(id=196)の尻尾で **103PF×約4秒/PF ≒ 7分**、`rss=1923.8MB`
- 1PFあたりの中身: 6種ビルダー（performance/monthly_returns/annual_returns/drawdowns/rolling_returns/monthly_trade）×複数パラメータ=**15行/PF** のraw_json生成+upsert
- 既存の部分最適: compare_returns_bulk/metrics_summary_bulkは先頭でbulk一括生成済み（先行最適化の余地実証）。partial recalc時は対象PFのみ（cmd_3804裁定で採用済み）
- 発生頻度: fullrecalculate毎+日次cron再計算の尻尾=**毎日全ユーザーの画面鮮度に直結**
- P1ローカル基準: cmd_3819の隔離Postgresで `1180.64s`（3回中央値）、precompute単体RSS `311.9MB`。本番7分/1.9GBはfullrecalculate累積環境の値であり、改善率の分母へ混在させない

## §1.1 実行状況（v1.2レビュー時点）

| Phase/iteration | 状態 | 計測・判定 |
|---|---|---|
| P1 cmd_3819 | 完了 | 評価器2本をcommit `c956e4e7f2dd6d335c4e7a5eafbd95c0b58a3814`で凍結。baseline snapshot `cmd3819_baseline_20260709T225551Z_a74ad188` |
| P2 H2 cmd_3821 iteration 1 | **無効（parity FAIL）** | `1180.64s → 751.83s`（36.32%短縮）は観測済みだが、canonical mismatch 868件のため改善実績へ算入しない |
| P2 cmd_3825 | 実行中 | 868件を分類し、同一logical dateの対照snapshotで等価版H2を再検証後、stop conditionまで継続 |

レビュー所見: 868件はH2対象だけでなく未変更endpointにも分布し、代表差分は `as_of_date/computed_for/as_of` の `2026-07-09 → 2026-07-10`。immutable DBだけでは日付依存出力を固定できないため、**DB snapshotとlogical evaluation dateの両方**を揃えることが評価前提である。

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
/goal cmd_3825としてDM-Signalのprecompute全量(103PF)を出力等価のまま最速化せよ。
評価器commit c956e4e7f2dd6d335c4e7a5eafbd95c0b58a3814のscripts/oneshot/cmd_3819_precompute_bench.pyとcmd_3819_precompute_parity.pyは変更禁止。
対象PFは固定順序の段階集合3→10→25→50→103。各上位集合は下位集合を包含し、PF ID一覧と選定理由を記録する。
反復手順: (1)同一immutable DB clone・同一logical dateで対照snapshotを作成 (2)現段階のPF集合で最遅コンポーネントを特定 (3)出力等価の改善を1つ実装
(4)現段階の全endpoint・全パラメータを1回計測し、凍結parityでcanonical hash一致+Pythonオブジェクト等価を確認
(5)速度改善+parity PASSを満たすまで同じPF段階で反復。満たしたら次のPF段階へ昇格
(6)103PFまで昇格した最終候補だけ全pipeline 3回中央値+parityで確定。数値をdocs/research/cmd_3825_h2_parity_fix.mdへ累積追記。
parity FAILのiterationは無効として原因修正まで次の仮説へ進まない。
stop condition: 103PFでparity PASSし、改善が2連続5%未満、またはH1-H6を全て計測・判定済み。3/10/25/50PFで停止してはならない。上限10 iterationは各段階ではなく全体の仮説変更回数に適用。
禁止: raw_json出力の変更、安全パターン削除、本番DBへの書込み。
```

- **evaluator分離+凍結（レビュー修正1）**: bench/parityの2スクリプトは**/goal開始前に非goal側（別忍者、家老レビュー）で作成・凍結**する。凍結commit hashを記録し、goal忍者はこの2ファイルを変更禁止（変更を含むiterationは無効）。generatorが評価基準を都合よく変えられない構造にする（評価器汚染防止）
- **parity判定のFP防止（レビュー修正2）**: 「バイト等価」はPostgres JSON化・辞書キー順・float表現で偽陽性/偽陰性化し得る。SSOTは**canonical JSON hash（`json.dumps(sort_keys=True, separators=(',',':'))`のhash）+Pythonオブジェクト等価**の2判定。`computed_at`等の非出力メタ列は比較対象外と明記
- **stop condition明文化**（blind loop防止）: parity PASSした有効iterationのみを母数とし、改善飽和(2連続<5%) or 仮説消化。parity FAILを「消化済み」「改善なし」へ算入して早期終了してはならない。token blowout防止でiteration上限=10
- **段階昇格ゲート（v1.4修正）**: `3→10→25→50→103PF`。最初の3PFは少なくともstandard単体・FoF・monthly_trade高コストPFを各1件含める。各上位集合は下位集合を包含し、段階ごとに全endpoint・全パラメータを実行する。速度改善とparity PASSの両方が揃うまで昇格禁止
- **各iterationの記録契約**: iteration番号/PF段階/PF ID集合/変更1行要約/全endpoint件数/秒数/rssピーク/parity判定/昇格可否。3回中央値は103PF最終判定にのみ必須。記録なきiterationは無効
- 環境: **immutable baseline+logical date固定方式（v1.2修正）** — 本番同期のbaseline dumpを凍結→作業DBはそこからclone→各iterationの対照と変更後を同一logical dateで生成して比較。DB snapshot id/source commit/seed/evaluation dateを記録必須。日跨ぎしたhistorical raw_jsonと当日再生成値を直接比較しない。共有ローカルDBの直接使用は禁止（他cmdの書込みで期待値が汚れる）。本番非接触=他cmdと並列可

## §5 Phase構成

| Phase | 内容 | 完了条件 |
|---|---|---|
| P1 ベンチ+パリティ道具（評価器） | **完了(cmd_3819)**。全量ベンチ+canonical parityゲートを非goal側で凍結、baseline DB dump作成、理論下限を推定 | 凍結commit `c956e4e7...`、snapshot id、1180.64s/RSS 311.9MBを記録済み |
| P2 /goalループ | **実行中(cmd_3825)**。H2初回36.32%短縮はparity FAILで無効。等価版H2を確定後、H1-H6を計測順に反復 | parity PASSした有効iterationだけでstop condition到達。全iteration数値記録 |
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

- 前提: ローカルDBが本番同期であること（gs_price_preflight系の確認）。対照/変更後のDB cloneとlogical evaluation dateが同一であること。/goalが対象忍者CLIで動作すること（v0.142.0実証済み）
- 無効化: precompute_rawのスキーマ・エンドポイント構成が変わったら理論下限を再計測

## 因果リンク

- [[殿観測20260709_2353_precompute遅い]] -> [[one_PF_at_a_time直列7分]] -> [[precompute-fullspeed-goal-design]]
- [[codex_goal_mode]] -> [[Loop_Engineering_generator_evaluator分離]] -> [[goal自律最適化ループ]]
- [[殿裁定20260710_0241_可逆なら行動せよ]] -> [[§42v2自走deploy]] -> [[P4本番実測]]
