# cmd_2553 DM-Signal 用語多義スキャン / MECE定義辞書案

date: 2026-05-04
worker: hayate
scope: multi-agent-shogun側のみ。`context/dm-signal*.md`, `projects/dm-signal.yaml`, `projects/dm-signal/*.yaml`, `context/gs-speedup-knowledge.md`, `context/gstack-knowledge.md`, `queue/cmd_2553_mcp_polysemy_extract.txt`

## 0. 調査方法

3層で確認した。

| 層 | 方法 | 対象 |
|---|---|---|
| 全文Read | 対象ファイルの全文または行数確認後の要点Read。80行以下は全文、長文は対象§と先頭/末尾を確認 | `projects/dm-signal.yaml`, `projects/dm-signal/*.yaml`, `context/dm-signal*.md`, `context/gs-speedup-knowledge.md`, `context/gstack-knowledge.md` |
| セマンティック分類 | MCP抽出済み9カテゴリを正本候補として突合 | `queue/cmd_2553_mcp_polysemy_extract.txt:6-49` |
| 変数名逆引き | `rg`で語の実出現を逆引きし、DB列/設定キー/運用語の衝突を確認 | `component`, `block`, `tier`, `type`, `mode`, `family`, `signal`, `weight`, `L0-L3` |

## 1. 結論

同一語多義として実害が出やすい用語は13群。

| # | 旧語 | 多義の型 | 衝突度 | 改名優先度 |
|---|---|---|---|---|
| 1 | L0/L1/L2/Layer | 研究レイヤー / SSOT階層 / 命名階層 / sync階層 / visibility階層 | HIGH: 同一ファイル内 + 複数ファイル横断 | P0 |
| 2 | signal / holding_signal / signal_date / as_of | 生シグナル / 保有シグナル / 参照日 / 表示基準日 | HIGH: 計算・表示・パリティに直結 | P0 |
| 3 | monthly_return | 本番Close系列 / GS Open-to-Open系列 / CSV列名 / API表示語 | HIGH: パリティ誤判定に直結 | P0 |
| 4 | FoF | portfolio type / 旧四神FoF / シン忍法FoF / 奥義 / nested FoF / pipeline FoF | HIGH: 登録・削除・検証範囲に直結 | P0 |
| 5 | top_n | Portfolio直下UI制約 / pipeline_config内側の選抜数 / GS探索軸 | MEDIUM: 登録事故の既知教訓あり | P1 |
| 6 | mode / モード | 運用モード名 / CLI実行mode / recalculate mode / GS目的軸 | MEDIUM: 文脈依存が大きい | P1 |
| 7 | DB / CSV / source | 本番PostgreSQL / experiments.db / dm_signal.db / GS CSV | MEDIUM: パリティ入力ソースに直結 | P1 |
| 8 | weight / weights | final_weights / momentum_data weights / component target/actual weight / ticker weight | MEDIUM: FoF表示・健全性チェックに直結 | P1 |
| 9 | component | FoF component / pipeline component / UI masking component | MEDIUM: FoF展開・表示制御で衝突 | P1 |
| 10 | block | selection block / concrete Block class / GATE BLOCK動詞 | MEDIUM: pipelineと運用gateで衝突 | P1 |
| 11 | tier | viewer tier / visibility tier / 計算層の改名候補 | MEDIUM: 改名候補として危険 | P2 |
| 12 | type | portfolios.type / block.type / task_type / service type | MEDIUM: YAML・DB・taskで横断 | P2 |
| 13 | family | DM family / font-family等一般語 | LOW: DM固有では安全。ただし正規名化推奨 | P3 |

## 2. インスタンス一覧

### 2.1 L0/L1/L2/Layer

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| L0/L1/L2 | `context/dm-signal-core.md:10-14` | 研究レイヤー。L0=四神、L1=忍法、L2=奥義 | HIGH |
| L0/L1/L2/L3 | `context/dm-signal-core.md:72-79` | SSOT階層。L0=Price/trade-rule、L1=計算関数、L2=MonthlyReturn table、L3=UI | HIGH |
| L1/L2 | `context/dm-signal-core.md:145-166` | 旧命名/構造説明。L1 standard PF、L1四神FoF、L2忍法FoFが同居 | HIGH |
| L0/L1/L2 | `projects/dm-signal.yaml:36-49` | naming_convention。L0=四神名、L1=忍法名、L2=奥義名 | HIGH |
| L1/L2 | `projects/dm-signal/naming-portfolios.yaml:11-22` | 旧命名規則。L1_shijin_fof / L2_ninpou_fof | HIGH |
| L0/L1/L2 | `projects/dm-signal/naming-portfolios.yaml:117-120` | 登録実態。L0_L1_standard=12, L2_fof=21 | HIGH |
| L1/L2/L3 | `projects/dm-signal/recalculate-phases.yaml:11-12`, `:63-79` | recalculate処理階層。L2=個別PF、L3=FoF | HIGH |
| L1/L2/L3/L4 | `context/dm-signal-frontend.md:115` | visibility階層。L1=ページ、L2=PF、L3=シグナル、L4=コンポーネント | HIGH |
| L2/L3 | `context/gs-speedup-knowledge.md:127` | GS実行/キャッシュ所在の作業分類 | MEDIUM |

問題: 同じ `L2` が奥義、MonthlyReturn cache、忍法FoF、FoF再計算、PF visibilityを指す。

### 2.2 signal / holding_signal / signal_date / as_of

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| signal | `projects/dm-signal.yaml:66` | `signals.signal` DB列。パイプライン生出力 | HIGH |
| holding_signal | `projects/dm-signal.yaml:66-67` | `signals` と `monthly_returns` の保有列 | HIGH |
| signal / holding_signal | `context/dm-signal-core.md:269-271` | `signal`=パイプライン生出力、`holding_signal`=リバランス月以外は前月維持 | HIGH |
| DM-Signal | `queue/cmd_2553_mcp_polysemy_extract.txt:12-16`, `projects/dm-signal.yaml:1-8` | プロダクト名。`signal`列/概念とは別 | MEDIUM |
| signal_date | `context/dm-signal-core.md:168` | FoF request-scope cache keyのシグナル参照日 | MEDIUM |
| as_of | `context/dm-signal-core.md:84` | pending判定基準。DB最新日 vs `date.today()` の2系統 | HIGH |
| Signalページ current signal | `context/dm-signal-frontend.md:226-232` | UI表示上の current signal / pending projection | MEDIUM |
| L020 | `context/dm-signal-core.md:474` | signal vs holding_signal差分はリバランスタイミング差 | HIGH |

問題: UIの「current signal」とDBの`signal`、月次計算の`holding_signal`、FoF component参照日の`signal_date`が混ざる。

### 2.3 monthly_return / cumulative_return / Open/Close

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| monthly_return | `projects/dm-signal.yaml:67` | `monthly_returns.monthly_return` DB列 | HIGH |
| monthly_return_open | `projects/dm-signal.yaml:67` | `monthly_returns.monthly_return_open` DB列 | HIGH |
| monthly_return | `context/dm-signal-core.md:89` | 本番Close列。GSはOpen-to-Openなので`monthly_return_open`使用 | HIGH |
| monthly_return | `context/dm-signal-core.md:416` | GS `monthly_return` はopen-to-open系列 | HIGH |
| cumulative_return | `context/dm-signal-core.md:421,431-432` | 本番・GS選抜で参照する累積系列 | MEDIUM |
| month CSV | `context/gs-speedup-knowledge.md:94-97` | GS wide CSVの値=月次リターン | MEDIUM |
| Return | `context/dm-signal-core.md:303` | ローカル分析の月次価格比 | MEDIUM |

問題: `monthly_return` という名前が本番DBではClose系列、GS文脈ではOpen-to-Open系列を指す。

### 2.4 FoF

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| FoF | `projects/dm-signal.yaml:8` | 乗り換え戦略全般 | MEDIUM |
| L1四神FoF / L2忍法FoF | `context/dm-signal-core.md:158-162` | 旧命名体系のFoF | HIGH |
| L1 standard PF | `context/dm-signal-core.md:145-151` | シン四神v2はFoFではなくstandard PF | HIGH |
| FoF材料 / 完成品 | `projects/dm-signal/shijin-design.yaml:25-36` | 設計哲学上の素材と完成品 | MEDIUM |
| FoF再計算 | `projects/dm-signal/recalculate-phases.yaml:76-79` | recalculate Phase5 / L3 | HIGH |
| FoF holding_signal | `context/dm-signal-core.md:420` | 展開後ticker×weightで同一判定すべき対象 | HIGH |
| protected FoF | `projects/dm-signal.yaml:51` | 殿の個人PF保護対象 | HIGH |

問題: `FoF` がDB type、設計哲学、旧PF名、再計算処理、保護対象をまたぐ。

### 2.5 top_n

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| top_n | `projects/dm-signal/pipeline-blocks.yaml:63-65` | MomentumFilterBlockがrelative_assetsから選ぶ数 | MEDIUM |
| top_n | `projects/dm-signal/naming-portfolios.yaml:70,79,88,97` | シン四神チャンピオンのパラメータ軸 | MEDIUM |
| top_n | `context/dm-signal-core.md:418-419` | Portfolio直下top_nとpipeline_config内側top_nは別経路 | HIGH |
| top_n | `context/gs-speedup-knowledge.md:223` | 忍法GSの配分方式・選抜ルール | MEDIUM |

問題: Portfolio直下の制約値とselection block内の探索/実行値が同名。

### 2.6 mode / モード

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| モード | `context/dm-signal-core.md:158-160` | 激攻/鉄壁/常勝。目的関数名 | MEDIUM |
| mode | `projects/dm-signal.yaml:45-49` | 命名コード内の方式・モード | MEDIUM |
| mode | `projects/dm-signal/naming-portfolios.yaml:145-147` | 同一config時の命名省略ルール | MEDIUM |
| mode | `context/gstack-knowledge.md:8,15,31` | gstackの作業モード | LOW |
| mode | `projects/dm-signal/recalculate-phases.yaml:11-12` | recalculate実行モードと処理階層 | MEDIUM |

問題: 投資目的軸の「モード」とCLI/実行設定のmodeが混ざる。

### 2.7 DB / CSV / source

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| DB | `context/dm-signal-core.md:31-32` | 本番PostgreSQL、dm_signal.db、experiments.dbが併記 | HIGH |
| DB | `projects/dm-signal/database-detail.yaml:10-24` | 本番PostgreSQL接続・テーブル定義 | HIGH |
| DB | `projects/dm-signal/database-detail.yaml:55-60` | dm_signal.db書込禁止、experiments.db使用などの正誤 | HIGH |
| DB / CSV | `projects/dm-signal/naming-portfolios.yaml:221-227` | パリティ検証データソース。CSVは無効、DBは明示必須 | HIGH |
| CSV | `context/gs-speedup-knowledge.md:94-97,120-132` | GS成果物・巨大CSV・キャッシュ | MEDIUM |

問題: 「DB」とだけ書くと本番PostgreSQL、experiments.db、dm_signal.dbのどれか判別不能。

### 2.8 weight / weights

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| weights | `context/dm-signal-core.md:269-270` | PipelineEngine戻り値`weights` / PipelineContext`final_weights` | MEDIUM |
| weight | `context/dm-signal-core.md:420` | FoF holding_signal同一判定の展開後ticker×weight | HIGH |
| weights | `projects/dm-signal/database-detail.yaml:16` | `signals.momentum_data(JSON)` 内に入りうる重み | MEDIUM |
| target_weight / actual_weight | `projects/dm-signal/lessons.yaml` L709系, `projects/dm-signal.yaml` detail参照 | `fof_component_weights`の構成重み | MEDIUM |

問題: final allocation、表示用precomputed weights、component table weightsが同じ「weight」で呼ばれる。

### 2.9 component

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| component | `queue/cmd_2553_mcp_polysemy_extract.txt:18-21` | MCP抽出。FoF component、pipeline component、masking component | MEDIUM |
| component | `context/dm-signal.md:114,131,201` | FoF component_weights / component_weights commit / FoF weights正本 | MEDIUM |
| component | `context/dm-signal-core.md:272,392,420` | `fof_component_weights`、target/actual weight、ticker×weight判定 | HIGH |
| component | `projects/dm-signal/pipeline-blocks.yaml:32-34` | ComponentPriceBlock。FoF用に構成PFの累積リターンを価格として読込 | MEDIUM |
| component | `context/dm-signal-frontend.md:115` | UI visibility L4=コンポーネント | MEDIUM |

問題: `component` がFoFの子PF、pipeline block構成要素、UI表示単位を指す。

### 2.10 block

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| block | `queue/cmd_2553_mcp_polysemy_extract.txt:28-31` | selection_block、PBarSelectionBlock、GATE BLOCK動詞 | MEDIUM |
| selection_blocks / terminal_blocks | `projects/dm-signal/pipeline-blocks.yaml:12-57` | Pipelineのフィルタ/終端ブロック型 | MEDIUM |
| blocks | `projects/dm-signal/pipeline-blocks.yaml:62-80` | `selection_pipeline.blocks`配列 | MEDIUM |
| PBarSelectionBlock | `context/dm-signal.md:113`, `context/dm-signal-core.md:221` | p̄フィルタ特化block | MEDIUM |
| BLOCK | 運用語 | gate/reportの停止判定 | LOW |

問題: コード構造としてのblockと運用判定としてのBLOCKが同じ表記で混ざる。

### 2.11 tier

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| tier | `queue/cmd_2553_mcp_polysemy_extract.txt:33-35` | viewer_tiers、計算層Tier改名候補 | MEDIUM |
| tier | `context/dm-signal-frontend.md:115,207` | visibility/課金ティア文脈 | MEDIUM |
| tier | `projects/dm-signal/lessons_archive.yaml`多数 | admin/viewer tier関連の過去教訓 | LOW |

問題: `L0/L1/L2`の代替語として`tier`を使うと、viewer tierと衝突する。

### 2.12 type

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| type | `queue/cmd_2553_mcp_polysemy_extract.txt:37-40` | portfolios.type、block.type、task_type | MEDIUM |
| portfolios.type | `projects/dm-signal.yaml:65`, `projects/dm-signal/api-endpoints.yaml:16` | standard/fof | MEDIUM |
| block.type | `projects/dm-signal/pipeline-blocks.yaml:14-55` | MomentumFilterBlock等のPipeline Block型 | MEDIUM |
| task_type | `queue/tasks/hayate.yaml` | scout/normal/exact等の任務種別 | MEDIUM |
| service type | `context/dm-signal-ops.md:40-50` | Render serviceのweb/static/postgres/cron | LOW |

問題: YAML横断で`type`だけを見るとDB種別、block種別、task種別、Render種別が混ざる。

### 2.13 family

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| family | `queue/cmd_2553_mcp_polysemy_extract.txt:47-49` | DM2/DM6/DM7+など資産ペアグループ。font-familyとは衝突低 | LOW |
| family | `projects/dm-signal.yaml:40-43` | 四神memberのfamily | LOW |
| family_dna | `projects/dm-signal/shijin-design.yaml:38-85` | DM familyのDNA定義 | LOW |
| family | `context/dm-signal-research.md:131` | `unit_naming` format変数としては不可 | MEDIUM |

問題: DM固有では比較的安全。ただし一般CSS語の`font-family`やformat変数`family`と混ざる可能性があるため、正規名は`dm_family`が望ましい。

## 3. MECE定義辞書案

| 概念ID | 推奨正規名 | 旧語 | 定義 | 主な保存先 |
|---|---|---|---|---|
| ARCH_LAYER | research_arch_layer | L0/L1/L2 | DM-Signal研究構造。L0=四神、L1=忍法、L2=奥義 | `context/dm-signal-core.md` §0 |
| SSOT_LAYER | calc_ssot_layer | L0/L1/L2/L3 | 計算正本階層。Price/trade-rule→関数→MonthlyReturn→UI | `context/dm-signal-core.md` §2 |
| NAME_LAYER | portfolio_name_layer | L0/L1/L2 | PF命名階層。四神/忍法/奥義 | `projects/dm-signal.yaml`, `naming-portfolios.yaml` |
| RECALC_LAYER | recalc_execution_layer | L2/L3 | sync/recalculate処理階層。standard/FoF | `recalculate-phases.yaml` |
| VISIBILITY_LAYER | ui_visibility_layer | L1/L2/L3/L4 | FE visibility階層。page/PF/signal/component | `context/dm-signal-frontend.md` |
| RAW_SIGNAL | raw_pipeline_signal | signal | PipelineEngineの生出力 | `signals.signal` |
| HOLDING_SIGNAL | rebalance_holding_signal | holding_signal | 月次計算に使う実保有。非リバランス月は前月維持 | `signals.holding_signal`, `monthly_returns.holding_signal` |
| SIGNAL_REF_DATE | component_signal_ref_date | signal_date | FoF component signal参照日 | cache key / report |
| API_AS_OF_DATE | api_as_of_date | as_of | API/UI表示基準日 | API / FE |
| RETURN_CLOSE_MONTHLY | monthly_return_close | monthly_return | 本番Close系列月次リターン | `monthly_returns.monthly_return` |
| RETURN_OPEN_MONTHLY | monthly_return_open | monthly_return_open / GS monthly_return | Open-to-Open系列月次リターン | `monthly_returns.monthly_return_open`, GS |
| RETURN_CUM_CLOSE | cumulative_return_close | cumulative_return | Close系列累積リターン | `monthly_returns.cumulative_return` |
| PF_TYPE_FOF | portfolio_type_fof | FoF | DB typeとしてのFoF | `portfolios.type` |
| FOF_DESIGN_LAYER | fof_design_role | FoF material/completed | 素材/完成品という設計哲学 | `shijin-design.yaml` |
| FOF_RECALC_STAGE | fof_recalc_stage | FoF再計算 | recalculate Phase5/L3処理 | `recalculate-phases.yaml` |
| PORTFOLIO_TOP_N | portfolio_schema_top_n | top_n | Portfolio直下のUI/schema由来値 | portfolio config |
| BLOCK_TOP_N | selection_block_top_n | top_n | pipeline_config内selection blockの選抜数 | pipeline_config |
| GS_TOP_N | gs_search_top_n | top_n | GS探索軸 | GS config/output |
| OBJECTIVE_MODE | objective_mode | mode/モード | 激攻/鉄壁/常勝 | naming |
| EXECUTION_MODE | execution_mode | mode | recalculate/API/CLIの実行モード | ops |
| DB_PROD | prod_postgres | DB | 本番PostgreSQL(DATABASE_URL) | Render |
| DB_EXPERIMENTS | experiments_sqlite | DB | 価格・分析用SQLite | local |
| DB_MIRROR | dm_signal_sqlite_mirror | DB | 不完全本番ミラーSQLite | local |
| GS_CSV_ARTIFACT | gs_csv_artifact | CSV | GS中間/成果物CSV | outputs |
| FINAL_WEIGHTS | pipeline_final_weights | weights | Pipeline terminal配分 | PipelineContext |
| DISPLAY_WEIGHTS | display_ticker_weights | weights | UI表示用展開済ticker weight | Signal.momentum_data |
| COMPONENT_WEIGHTS | fof_component_weights | weights | FoF component tableのtarget/actual weight | `fof_component_weights` |
| FOF_COMPONENT | fof_component_portfolio | component | FoFを構成する子PF | `component_portfolios`, `fof_component_weights` |
| PIPELINE_COMPONENT | pipeline_block_component | component | pipelineのblock配列要素 | `selection_pipeline.blocks` |
| UI_MASK_COMPONENT | ui_mask_component | component | UI masking/visibility対象 | FE visibility |
| PIPELINE_BLOCK | pipeline_block | block | Pipelineの処理単位 | `projects/dm-signal/pipeline-blocks.yaml` |
| GATE_BLOCK | gate_block_status | BLOCK | gate/reportの停止判定 | gate/report |
| VIEWER_TIER | viewer_access_tier | tier | viewer/adminのアクセス階層 | FE/API |
| PORTFOLIO_TYPE | portfolio_type | type | `standard` / `fof` | `portfolios.type` |
| BLOCK_TYPE | pipeline_block_type | type | MomentumFilterBlock等 | pipeline config |
| TASK_TYPE | shogun_task_type | task_type | scout/normal/exact | `queue/tasks/*.yaml` |
| DM_FAMILY | dm_family | family | DM2/DM3/DM6/DM7+の資産ペアグループ | `shijin-design.yaml` |

## 4. 改名計画

### Phase 1: ドキュメント注釈だけで事故を止める

1. `context/dm-signal-core.md` 冒頭に「L0/L1/L2は5体系ある」と明示し、各表の見出しを `研究レイヤー`, `SSOT階層`, `命名階層` に変更する。
2. `projects/dm-signal.yaml` の `naming_convention` コメントを `portfolio_name_layer` に変更する。
3. `projects/dm-signal/naming-portfolios.yaml` の旧 `L1_shijin_fof` / `L2_ninpou_fof` に `legacy_name_layer` と注記する。
4. `context/dm-signal-core.md` §4.5 GS用語定義の直後に `monthly_return` 系の正規名表を置く。

### Phase 2: 新規cmd/task/reportの語彙を正規名へ寄せる

1. cmd文では `DB` 単独表記を禁止し、`prod_postgres` / `experiments_sqlite` / `dm_signal_sqlite_mirror` のいずれかを書く。
2. `monthly_return` とだけ書く場合は `monthly_return_close` か `monthly_return_open` を選ばせる。
3. `top_n` とだけ書く場合は `portfolio_schema_top_n` / `selection_block_top_n` / `gs_search_top_n` を選ばせる。
4. `L2` とだけ書く場合は `research_arch_layer:L2`, `calc_ssot_layer:L2`, `portfolio_name_layer:L2`, `recalc_execution_layer:L3` など名前空間を付ける。
5. `component` とだけ書く場合は `fof_component_portfolio` / `pipeline_block_component` / `ui_mask_component` を選ばせる。
6. `type` とだけ書く場合は `portfolio_type` / `pipeline_block_type` / `shogun_task_type` / `render_service_type` を選ばせる。
7. `tier` は計算層の改名候補に使わず、viewer/access文脈に限定する。

### Phase 3: 既存ファイルの置換

| 対象 | 置換方針 |
|---|---|
| `context/dm-signal-core.md` | セクション見出しだけ置換。本文の歴史的用語は旧語維持+注釈 |
| `projects/dm-signal.yaml` | コメント・キー説明を正規名に寄せる。既存キー名は互換維持 |
| `projects/dm-signal/naming-portfolios.yaml` | 新旧命名体系を `legacy_name_layer` / `shin_name_layer` / `wf_name_layer` に分離 |
| `projects/dm-signal/recalculate-phases.yaml` | `L2/L3` を `recalc_standard_stage` / `recalc_fof_stage` と併記 |
| `context/dm-signal-frontend.md` | visibilityのL1-L4を `ui_visibility_layer` と明記 |

## 5. 偵察5要件

| 要件 | 結論 |
|---|---|
| 変更対象ファイル・行番号 | `context/dm-signal-core.md:8-17`, `:70-89`, `:145-166`, `:267-303`, `:415-432`; `projects/dm-signal.yaml:36-67`; `projects/dm-signal/naming-portfolios.yaml:11-22`, `:42-49`, `:105-120`, `:133-147`, `:221-227`; `projects/dm-signal/recalculate-phases.yaml:11-12`, `:63-79`; `context/dm-signal-frontend.md:115` |
| 波及先 | `projects/dm-signal/database-detail.yaml`, `projects/dm-signal/pipeline-blocks.yaml`, `context/gs-speedup-knowledge.md`, task/reportテンプレートのcmd記述 |
| 関連テスト | ドキュメント変更のみならunit不要。gate候補: `rg -n '\\bDB\\b|\\bL[0-4]\\b|monthly_return|top_n' queue/shogun_to_karo.yaml queue/tasks/*.yaml` で曖昧語をWARN |
| エッジケース・副作用 | 歴史資料の旧語を一括置換すると過去cmdの意味が壊れる。本文全置換ではなく見出し/注釈/新規cmd語彙から始める |
| 依存関係・順序制約 | Phase 1注釈→Phase 2新規cmd gate→Phase 3既存docs段階置換。コード変数名変更は最後 |
