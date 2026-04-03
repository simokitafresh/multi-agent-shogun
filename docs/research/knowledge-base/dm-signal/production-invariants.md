# DM-Signal Production Invariants

> Purpose: passive knowledge layer for GS, scouting, and implementation work.
> Sync source: `projects/dm-signal.yaml` `production_invariants` (`last_updated: 2026-03-29`).
> Scope: §1 copies the PI canon, §2 records parity conditions, §3 records GS training rules.

## §1. Production Invariants

### PI-001
Fact: 本番シグナル計算は日次解像度。10D/15D/20D/1M は全て異なるlookback期間として計算される。  
Implication: 全ての解像度変換に適用される原理。低解像度側では高解像度の区別が消滅する。月次解像度のdedupは日次パラメータ差異を破壊する。解像度を下げる操作の前にその操作で何が失われるか確認せよ。

### PI-002
Fact: SQLiteミラー(`backend/static/data/dm_signal.db`)は不完全。本番PostgreSQLとデータ乖離。  
Implication: 全てのデータ複製・ミラー・キャッシュに適用される原理。複製は原本と乖離する前提で検証せよ。SQLite/CSV/ローカルファイルは便宜的コピーであり真実ではない。

### PI-003
Fact: standard PFのconfig JSONには`pipeline_config`が必須。`None`だとrecalculateでCashフォールバック。  
Implication: 全てのDB登録に適用される原理。必須フィールドのデフォルト値は暗黙に仮定するな。既存レコードから同一ファミリーの設定をコピーせよ。`NULL→フォールバック`はPI-018のデータ版。

### PI-004
Fact: GSはnumpy配列操作のみで本番pydanticスキーマを通さない。  
Implication: 全ての外部→本番データ投入に適用される原理。投入先のバリデーション層(Pydantic/ORM)を事前通過させよ。GS等の外部ツールは本番スキーマ制約を知らない(PI-020の具体適用)。

### PI-005
Fact: 新規PF登録後のrecalculateは`full(portfolio_id指定なし)`一発が鉄則。  
Implication: 任意の依存グラフで適用される原理。部分操作の連続実行は暗黙の依存順序を壊しエラー連鎖する。`full`一括実行が依存解決を内部化する。

### PI-006
Fact: 手順書/ランブックの記載はrecalculateコードパスとの照合なしには信頼できない。  
Implication: 全ての手順書・ランブックに適用される原理。文書とコード実体は必ず乖離する。ACに「実際のコードパスとの照合検証」を含めよ。

### PI-007
Fact: GS結果と本番計算結果は構造的に乖離しうる(月次vs日次解像度、pydanticバリデーション差異等)。  
Implication: 全ての外部計算結果(GS/分析/手動)の本番投入に適用される原理。投入前に本番計算結果とのパリティ検証必須。未検証データの本番登録は信頼境界違反(PI-020)。

### PI-008
Fact: `monthly_returns`テーブルには`monthly_return`(Close)と`monthly_return_open`(Open)の2列が存在。  
Implication: 全ての比較検証に適用される原理。比較対象のカラム/フィールドを間違えると偽の一致または偽の不一致が発生する。検証設計時に「何と何を比較しているか」を明示的に確認せよ。

### PI-009
Fact: GSは本番と同一の結果を出さなければならない。全期間`holding_signal`完全一致(必須)+`monthly_return` 1e-6以内。  
Implication: 全ての再現性検証に適用される原理。最敏感指標(`holding_signal`)で完全一致を要求せよ。1期間でも不一致=全体汚染。部分一致で合格にするな。

### PI-010
Fact: 本番は`price_by_symbol`に非市場ティッカー(`^VIX`/`DTB3`)を含めない。  
Implication: 全ての異種データ(異なる日付系列/解像度/ソース)の混合に適用される原理。異種データは混合するな、native系列で個別処理必須。stock grid載せ→lookback参照日ズレ→momentum値乖離→abs/rf判定反転。

### PI-011
Fact: シン忍法v2(21体)の`terminal_block`は全てEqualWeight。`selection_pipeline`が絞り込み→均等保有。  
Implication: 全てのパリティ検証に適用される原理。内部実装の構造(ブロック有無/パイプライン種別等)で検証方法を分岐させるな。出力の事実(シグナル一致/リターン一致)のみで判定せよ。

### PI-012
Fact: `MomentumAccelerationFilter`の`numerator_period`/`denominator_period`には`weight: 1.0`が必須。`{months: N}`のみでは`LookbackPeriod`バリデーションエラー。  
Implication: 全ての遅延バリデーション(書込時OK→処理時FAIL)に適用される原理。保存成功≠データ有効。書込みと処理で異なる制約が適用される場合、書込時に処理側の制約も事前検証せよ。

### PI-013
Fact: DB INSERT前にPydanticモデル(`Portfolio`)の全制約を事前検証必須。`top_n:1-2`, `months:0-36`, `days:<=756`, `weight:0-1`, `rebalance_trigger`有効値, `benchmark_ticker`非空/非DTB3/非CASH。  
Implication: 全てのデータ書込みに適用される原理。アプリケーション層のバリデーション(ORM/Pydantic)を迂回するな。直接SQL INSERTは信頼境界バイパス(PI-020)。1体でも制約違反→バックエンド全PF読込失敗→全機能停止。

### PI-014
Fact: 分析・研究の入力データは出自(provenance)が検証済みであること必須。検証済み=本番DB直接取得 or パリティ検証済み(checklist Step 2 PASS)。`outputs/`配下のCSVはパリティ検証記録がない限り未検証と見なせ。  
Implication: 全てのデータソースに適用される原理。出自(provenance)の検証なしにデータを信頼するな。ファイル名の類似は出自の証明にならない。指定ソースから直接取得せよ。

### PI-015
Fact: ネステッドFoF(FoF of FoF)は`fullrecalculate(portfolio_id=None)`で`signals`/`monthly_returns`が生成されない場合がある。`portfolio_id`指定の個別recalculateでは正常生成(`cmd_1444`実証)。  
Implication: 全てのバッチ処理に適用される原理。バッチ(全件一括)の成功は個別要素の成功を保証しない。特殊構造(ネスト/循環/自己参照)はバッチの暗黙仮定を破る。個別検証で補完せよ(PI-019の具体適用)。

### PI-016
Fact: ループ内で同一DBクエリがN回実行される場合、ループ前に一括ロードしてdict/cacheで渡すこと(N+1 pre-load原則)。実例: `shared_price_cache`(`cmd_116`で15,000query除去), OPT-1/2(`business_days`一括ロードで53,000query除去, `trade_perf` 4627s→0.73s), OPT-6(`signal_cache`非共有で512.97s浪費)。  
Implication: 全てのループ内IO(DB/API/ファイル)操作に適用される原理。ループ前の一括ロード+dict lookupが鉄則。N+1パターンは桁違いの性能劣化源(実績: 53,000query除去→4627s→0.73s)。

### PI-017
Fact: StockData API `/v1/economic/{symbol}` は1リクエスト最大1000レコード。長期経済データ取得にはページネーション必須。  
Implication: 全ての外部API呼出しに適用される原理。APIには暗黙のレコード制限・レート制限がある。長期/大量データ取得はページネーション必須。制限を超えたデータが黙って切り詰められる。  
Source: `cmd_1412` / verified file `backend/app/client.py`

### PI-018
Fact: `except Exception`でデータ値(Cash/0.0/True/1.0/SPY等)をfallback返却する新規コード禁止。エラー時は`None`返却+`logger.error`、または`raise`。  
Implication: 全てのエラーハンドリングに適用される原理。正常値への偽装=信頼境界での検証バイパス。silent fallbackはエラーを隠し下流で汚染データを伝播させる(PI-020の具体適用)。  
Source: `cmd_1483`

### PI-019
Fact: 上流処理がデータの可視性(いつ見えるか)や生存期間(いつ消えるか)を変更すると、下流はそれを知らない。Phase境界・commit・cache・flush・session lifecycleの全てに適用される原理。  
Implication: データの見え方・生存期間を変更する修正では、全ての下流消費者が新状態を参照できることを検証せよ。具体例: deferred flush→下流DB query空(`cmd_1474`), session-bound preload→commit後expire(`cmd_1479`), AC上書きスキップ→忍者が古AC参照(`cmd_1493`)。  
Source: `cmd_1474,cmd_1479` / verified file `docs/research/fullrecalculate-architecture-2026-03-28.md §2,§6,§7`

### PI-020
Fact: データが信頼境界を越えるとき(GS→本番, SQL直接→ORM, 外部CSV→分析, 上流Phase→下流Phase)、越えた先のルールで検証しなければ汚染が入る。  
Implication: 全てのデータ移動に適用される原理。具体的信頼境界: GS→本番(PI-004/007/009), SQL→ORM(PI-013), 外部→分析(PI-014), Phase境界(PI-019)。新しい境界を発見したらこのPIを参照し、検証パスが存在するか確認せよ。  
Source: `PI-004,PI-007,PI-009,PI-013,PI-014,PI-019の共通根抽出`

### PI-021
Fact: 本番既存の表示・計算の変更は絶対禁止。ユーザーと共有済み。変更ではなく機能追加のみ許可。新PF追加はFE+BE完全連携設計が必須。研究フェーズと本番投入フェーズは分離。  
Implication: 全ての本番変更に適用される原理。既存ユーザー体験を壊す変更は信頼境界違反。研究=自由に実験、本番投入=厳密な設計+連携が必須。  
Source: `殿厳命(2026-04-03)`

## §2. Parity Conditions

1. Output equality is the only acceptance gate. `holding_signal` must match for every period, and `monthly_return` must be within `1e-6`. Partial agreement is failure.  
   Source: PI-009, `context/checklist-shin-v2-registration.md` Step 1, `projects/dm-signal/naming-portfolios.yaml` `parity_validation_rule`

2. Both sides of a parity test must declare and use the same provenance chain. Current SSOT is production PostgreSQL via `DATABASE_URL`; GS-side local verification may use `experiments.db` only when it is an explicit sync from production. CSV-to-production comparison is invalid as parity evidence.  
   Source: PI-002, PI-014, `projects/dm-signal/naming-portfolios.yaml` `parity_validation_rule`

3. Compare the correct return column for the path under test. GS open-based series align with `monthly_return_open`; close-based series align with `monthly_return`. Open/Close mixing is forbidden.  
   Source: PI-008, `context/dm-signal-core.md` L420, trade rules RULE09-RULE10

4. Non-market tickers such as `^VIX` and `DTB3` must stay on their native path and must not be mixed into `price_by_symbol` or stock-grid style caches.  
   Source: PI-010, `context/dm-signal-research.md` L488

5. Judge parity on outputs, not on internal architecture. Even when a FoF uses `selection_pipeline + EqualWeight terminal`, pass/fail is determined by output equality, not by whether the internal block stack “looks equivalent.”  
   Source: PI-011

6. Production selection behavior must be mirrored exactly. This includes `cutoff_score` full inclusion vs `strict slice`, `1e-12` tolerance for float ties, `cumulative_return` ratio momentum, the 504-day warm-up rule for long lookbacks, and use of trading month-end rather than calendar month-end.  
   Source: `context/dm-signal-core.md` L086, L087, L091, L094, L427

7. `valid_start_date` and comparison windows must include every required symbol in the structure: relative, absolute, safe haven, and any native special series such as `DTB3`.  
   Source: `context/dm-signal-core.md` L428

8. Initialization months are part of the truth unless a rule explicitly says otherwise. FoF parity must not silently skip component initialization months, and first-month anomalies such as `monthly_returns.holding_signal=None` must be recorded and treated explicitly rather than hand-waved away.  
   Source: `projects/dm-signal/lessons.yaml` L073, `context/dm-signal-research.md` L485

9. Every GS→production promotion crosses a trust boundary. Before registration, parity must be proven, Pydantic constraints must be pre-validated, and any mismatch is a block, not a warning.  
   Source: PI-004, PI-007, PI-013, PI-020

10. Existing production calculations and displays are immutable. Even a parity-clean research result cannot justify altering an already shared production behavior; promotion means additive rollout with FE+BE integration, not silent replacement.  
   Source: PI-021

## §3. GS Training Rules

1. Use the DM-Signal GS vocabulary consistently. Narrow GS means `shin_shijin_l1_gs.py`, ninpo scripts mean `run_077_*.py`, and broad GS means the whole `scripts/analysis/grid_search/` stack. The flow is fixed: narrow GS → shin shijin components → ninpo scripts → shin ninpo outputs.  
   Source: `projects/dm-signal.yaml` `gs_terminology`, `context/checklist-shin-v2-registration.md`

2. Ninpo GS uses `monthly` rebalance only. Do not search alternate `rebalance_trigger` values; that space is treated as overfitting bait.  
   Source: `projects/dm-signal/naming-portfolios.yaml` `rebalance_rule`

3. Exploration and parity are different phases. For shin shijin creation, the numpy-fast exploration path is allowed because it is the search engine; for promotion, parity must still be checked against production outputs. Do not force the production pipeline engine into the exploration loop and then claim the search is valid.  
   Source: `context/checklist-shin-v2-registration.md` Step 1 and Step 3

4. Prefer full-sample champions over IS-only winners. Short-lookback or IS-only champions are treated as overfitting risk unless they survive OOS review.  
   Source: `projects/dm-signal/lessons.yaml` L117, `context/dm-signal-research.md` §21

5. Candidate→`pipeline_config` construction must match production registration code exactly. Rebuild configs using the same structure as `register_shijin_portfolios.py`; do not invent a GS-only payload shape.  
   Source: `projects/dm-signal/lessons.yaml` L069, L033

6. Enforce block and portfolio constraints before long GS runs. BB config freedom without validation produces invalid pattern floods, and delayed validation is not acceptable.  
   Source: PI-012, PI-013, `projects/dm-signal/lessons.yaml` L105

7. Use production data and production code paths whenever the goal is promotion-quality evidence. Mathematical equivalence is not enough; drift between GS and production paths has already caused false confidence.  
   Source: PI-002, PI-007, `projects/dm-signal/lessons.yaml` L065

8. Reuse deployed config and result metadata when extending prior work. When a champion or deployed PF already exists, its production config is the truth. When consuming GS outputs, consult `DATA_CATALOG.md` and `meta.yaml` before trusting the artifact.  
   Source: `projects/dm-signal/lessons.yaml` L341, L134

9. Respect operational design constraints discovered by prior GS rounds. Non-monthly rebalance champions degrade under monthly production operation, and special-series handling such as `^VIX` native caches cannot be approximated away.  
   Source: PI-010, `projects/dm-signal/lessons.yaml` L060

10. Research and production are separate phases. GS is allowed to explore, but promotion is blocked until parity passes, FE+BE linkage is designed, and the rollout is additive rather than destructive.  
   Source: PI-021
