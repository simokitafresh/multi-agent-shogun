# precompute全量最速化 — /goal自律ループ設計書 v2.1

- v2.1: 殿North Star「本番100PFを約30秒」を反映。L5を再計算層からL2成果物のpure formatting+chunked一括UPSERT層へ変えるZero-Recompute Architectureを最優先化。100PF×15行で0.3秒/PFを目安とし、L5内のprice/signal/ledger/momentum/MTD再計算を原則ゼロ、parameter variantsは1回のfull結果からslice、評価は本番total/p50/p95/max/RSS+完全parity
- v2.0: 殿指摘「full recalculate時の既存キャッシュを根本的に見落としているのでは」を一次コードで確認。cold単独L5の絶対5秒ゲートを撤回し、production-warm経路を正本へ変更。`recalculate_fast.py`で既に構築済みのmonthly return/signal/portfolio/price/benchmark/business-days/DTB3/rf-map cacheがL5呼出しへ渡されない配管断絶を最優先修正対象とし、cold standaloneとwarm fullrecalculateを別々に計測する
- v1.9: 殿裁定「3PFで41秒は実用に耐えない」を反映。3PFの暫定実用ゲートをunprofiled stage harness `<=5.0s`へ固定し、到達までは10PF昇格禁止。局所micro-cache探索から、monthly/annual等の全履歴中間計算をPFごとに1回化する構造改善へ優先順位を変更。mismatch/missing/extra/FAIL/SKIPが1件でもあれば速度に関係なくFAIL
- v1.8: 殿裁定「重要なのは本番環境での高速化」を反映。ローカルelapsedを候補選別へ格下げし、本番移植可能なDB往復/query数/計算量/割当量の削減と、本番L5区間実測+production parityを成功条件へ固定
- v1.7: 殿裁定「3PFで繰り返し極限まで高速化してから」を反映。1回の速度改善+parityだけでは昇格せず、3PF内で飽和条件と理論下限条件を両方満たすまで反復する段階内ループへ変更
- v1.6: 殿裁定「サンクコストにとらわれず中断」「トータル見込み時間を最小化」を反映。目的関数を総残時間へ変更し、旧bench継続の即時中断基準とstage harness投資の損益分岐を数値化
- v1.5: 段階実行の一次計測で、凍結benchの`--portfolio-ids`がPFループのみを絞りbulk prefixを全103PFで実行することを検出。D1用stage harnessではbulk prefixも対象集合へ限定し、凍結評価器は103PF最終確認へ限定する契約を追加
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
3. **本番経路を正しく再現してから理論下限へ**: cold単独L5とproduction-warm fullrecalculate L5を混同しない。実用ゲートはwarm経路のbefore→afterと本番L5ログで判定し、任意のcold絶対秒数を本番目標に代用しない
4. **計測なき改善は改善ではない**: 全iterationで before→after 数値を記録。安全パターン（try/except, invalidate順序等）の削除によるスピードアップは禁止（check_safety_pattern_removal準拠）
5. **総見込み時間を最小化**: 目的関数は `T_total = 道具改修時間 + 残り探索run時間 + 昇格検証時間 + 最終103PF検証時間`。開始済みrunの経過時間は意思決定から除外し、今後の残時間が代替案より長いと判明した時点で中断する
6. **本番速度が目的**: ローカルpgserverのelapsedは候補選別・回帰検出にのみ使う。採用する変更は本番へ移植可能なDB往復数、SQL query数、計算量、メモリ割当量の削減に限る。WSL/pgserver/cache固有の高速化を成果へ数えない
7. **Zero-Recompute**: fullrecalculateのL2で算出済みのデータをL5で再計算しない。L5は既存artifactのpure formatting、params別slice、raw JSON化、chunked一括UPSERTだけを担う

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

総時間レビュー: 3PFを旧benchで実行した結果は `373.76s`。PF本体3件の合計は `40.82s`、不変bulk prefix等の固定費は約 `332.94s`（89.1%）。stage harnessなら1 run約41秒が見込まれ、1回あたり約5.55分短縮する。残り3回以上で約16.6分以上を回収できるため、10分以内のharness実装は総時間で黒字。旧benchによる10PF以降のrunは開始済みでも中断対象とする。

実用性レビュー(v1.9): stage harness化で改善サイクルは短縮したが、3PF約41秒は約13.7秒/PFであり、103PFへ線形外挿すると約23.5分となる。これは探索道具としても本番処理としても不合格。3PF `<=5.0s`まではSQL数件ずつのmicro-cacheより、`monthly_returns`/`annual_returns`の全履歴走査・MTD・年次集計等をPFごとに1回だけ生成し、各paramsをslice/formatだけにする構造改善を優先する。

本番経路レビュー(v2.0): 上記41秒はL5だけをcold起動したstage harness値であり、本番fullrecalculateの実行状態を再現していなかった。`recalculate_fast.py`はL2開始前後に `monthly_return_cache`、`signal_preload`、`portfolio_preload`、`perf_price_cache`、`benchmark_cum_cache`、`_shared_business_days`、`dtb3_cache`、`rf_map_cache` を構築済みだが、L5の `precompute_raw_for_portfolios()` 呼出しには `db`、`portfolio_ids`、collectorしか渡していない。したがって根本対象は「cold計算を小さく削ること」ではなく、既存production cacheを明示的なcontext契約でL5へ受け渡し、standalone endpointだけfallback構築する配管断絶の解消である。v1.9の`<=5.0s`はproduction-warm baseline取得まで保留する。

## §2 To-Be

- 全量precompute（約100PF×15行）を出力等価のまま**本番30秒程度**へ短縮する。cold standalone経路は機能回帰用、warm fullrecalculate経路を速度評価の正本とする
- 副次: rssピークの削減（1.9GBは並列化の障害になる）
- 完了定義: /goalループのstop condition（§4）到達+パリティゲートPASS+本番実測
- 最終成功指標: Render本番のL5/precompute開始終了ログによる区間秒数before→after、同一本番入力からのproduction output parity、ピークRSS。ローカル秒数だけで完了判定しない

## §3 改善仮説（/goalループの初期弾。順序は計測が決める）

| # | 仮説 | 期待 | リスク |
|---|---|---|---|
| H0 | Zero-Recompute Architecture（L2成果物をcontext/artifactでL5へ渡し、再計算せずpure formatting+slice+一括UPSERT） | 100PF約30秒へ到達する本命。現在99.2%を占めるmonthly/annual/monthly_trade再計算を消す | artifact寿命・型・日付境界。warm/cold双方の完全parity必須 |
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
(4)非凍結stage harnessでPFループとbulk prefixの両方を現段階の集合へ限定し、全endpoint・全パラメータを1回計測。対象集合のcanonical hash一致+Pythonオブジェクト等価を確認
(5)同じPF段階でprofile→最大ボトルネック改善1件→parity→再計測を反復。3PFは本番ログのworst top3を使い、cold standaloneとproduction-warm contextの両方を計測する。速度の正本はwarm値。L5中の再計算を原則ゼロにし、100PF換算30秒程度へ到達後も**2連続改善5%未満かつwarm実測理論下限との差10%以内**まで反復
(6)103PFまで昇格した最終候補だけ凍結bench/parityで全pipeline 3回中央値+全2699行parityを確定。数値をdocs/research/cmd_3825_h2_parity_fix.mdへ累積追記。
parityのmismatch/missing/extraが1件でもある、またはtest FAIL/SKIPが1件でもあるiterationは無効として原因修正まで次の仮説へ進まない。
stop condition: 103PFでparity PASSし、改善が2連続5%未満、またはH1-H6を全て計測・判定済み。3/10/25/50PFで停止してはならない。上限10 iterationは各段階ではなく全体の仮説変更回数に適用。
禁止: raw_json出力の変更、安全パターン削除、本番DBへの書込み。
```

- **evaluator分離+凍結（レビュー修正1）**: bench/parityの2スクリプトは**/goal開始前に非goal側（別忍者、家老レビュー）で作成・凍結**する。凍結commit hashを記録し、goal忍者はこの2ファイルを変更禁止（変更を含むiterationは無効）。generatorが評価基準を都合よく変えられない構造にする（評価器汚染防止）
- **parity判定のFP防止（レビュー修正2）**: 「バイト等価」はPostgres JSON化・辞書キー順・float表現で偽陽性/偽陰性化し得る。SSOTは**canonical JSON hash（`json.dumps(sort_keys=True, separators=(',',':'))`のhash）+Pythonオブジェクト等価**の2判定。`computed_at`等の非出力メタ列は比較対象外と明記
- **stop condition明文化**（blind loop防止）: parity PASSした有効iterationのみを母数とし、改善飽和(2連続<5%) or 仮説消化。parity FAILを「消化済み」「改善なし」へ算入して早期終了してはならない。token blowout防止でiteration上限=10
- **段階昇格ゲート（v2.0修正）**: `3→10→25→50→103PF`。最初の3PFは少なくともstandard単体・FoF・monthly_trade高コストPFを各1件含める。各上位集合は下位集合を包含し、段階ごとに全endpoint・全パラメータを実行する。production-warm contextのbefore→after、canonical parityのmismatch/missing/extra全0、test FAIL/SKIP 0が最低条件。さらに各段階で2連続改善5%未満かつwarm理論下限差10%以内まで磨き切ってから昇格する
- **stage harness契約（v1.5修正）**: 凍結benchの`--portfolio-ids`はPFループだけを絞り、`compare_returns_bulk`/`metrics_summary_bulk`等のbulk prefixを全103PFで実行するため内側ループには使わない。D1用の非凍結harnessはbulk関数にも同じPF ID集合を渡す。103PF指定時に凍結benchと処理行数・対象endpointが一致する回帰テストを必須とし、凍結評価器そのものは変更しない
- **中断規則（v1.6修正）**: 現runの残時間が「中断+道具修正+再実行」の見込みを上回る、または対象PF外の固定費が実行時間の50%を超えると判明した時点で即中断する。既経過時間・取得済みsnapshot・「もう少しで終わる」は継続理由にしない
- **各iterationの記録契約**: iteration番号/PF段階/PF ID集合/変更1行要約/全endpoint件数/秒数/rssピーク/parity判定/昇格可否。3回中央値は103PF最終判定にのみ必須。記録なきiterationは無効
- **本番移植性契約（v1.8修正）**: 各iterationでローカル秒数に加え、SQL query数、DB round-trip数、取得/書込行数、主要CPU区間、RSS/割当量を記録する。削減理由がローカルファイルシステム・pgserver・OS cacheだけに依存する候補は不採用。P4で本番L5区間実測とproduction parityを必ず閉じる
- **production-warm context契約（v2.0追加）**: `precompute_raw_for_portfolios()`は任意の明示contextでfullrecalculate側の既存cacheを受け取る。context未指定のstandalone APIは従来どおり自前fallbackで完全動作する。cacheの暗黙global化・別DB/別runへの漏洩は禁止。warm/cold両経路で同一logical dateのcanonical parityを通す
- **Zero-Recompute契約（v2.1追加）**: performance/monthly/annual/monthly_tradeのparams違いは各PFでfull結果を1回だけ生成してsliceする。rolling/drawdown/metrics/signals/compare_returnsはL2生成済みtable/artifactから整形する。per-PF commitは禁止し、約1500 raw行を安全なchunkにまとめてUPSERTする。L5内のprice/signal/ledger/momentum再計算は計測上0を要求する
- 環境: **immutable baseline+logical date固定方式（v1.2修正）** — 本番同期のbaseline dumpを凍結→作業DBはそこからclone→各iterationの対照と変更後を同一logical dateで生成して比較。DB snapshot id/source commit/seed/evaluation dateを記録必須。日跨ぎしたhistorical raw_jsonと当日再生成値を直接比較しない。共有ローカルDBの直接使用は禁止（他cmdの書込みで期待値が汚れる）。本番非接触=他cmdと並列可

## §5 Phase構成

| Phase | 内容 | 完了条件 |
|---|---|---|
| P1 ベンチ+パリティ道具（評価器） | **完了(cmd_3819)**。全量ベンチ+canonical parityゲートを非goal側で凍結、baseline DB dump作成、理論下限を推定 | 凍結commit `c956e4e7...`、snapshot id、1180.64s/RSS 311.9MBを記録済み |
| P2 /goalループ | **実行中(cmd_3825)**。H2初回36.32%短縮はparity FAILで無効。等価版H2を確定後、H1-H6を計測順に反復 | parity PASSした有効iterationだけでstop condition到達。全iteration数値記録 |
| P3 検証 | canonical parityゲートPASS+既存テスト全PASS+回帰テスト追加 | テスト全PASS |
| P4 本番反映 | §42v2で自走deploy→本番実測は**L5/precompute区間の開始終了ログで区間計測**(fullrecalculate全体ではなく)→total/p50/p95/max/RSSを比較→失敗ならrevert | 約100PFで30秒程度+完全parityの本番証明 |

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
