# cmd_2554 hanzo scout: DM-Signal 多義語第2波調査 — knowledge-base/research領域

date: 2026-05-04
worker: hanzo
scope: 第1波(cmd_2553)未カバー領域
  - context/dm-signal.md, context/dm-signal-research.md, context/dm-signal-ops.md
  - context/l3-robustness.md, context/robustness-verification-catalog.md, context/database.md
  - context/gunshi-interpretation-layer-design.md, context/gunshi-opt12-analysis.md
  - docs/research/knowledge-base/index.md, docs/research/knowledge-base/guide.md
first_wave_reference:
  - docs/research/cmd_2553_dm_signal_term_collision_mece.md (hayate)
  - docs/research/cmd_2553_saizo_dm_signal_polysemy_code_crosscheck.md (saizo)

---

## 0. 調査方法

| 層 | 方法 | 対象 |
|---|---|---|
| 全文Read | 80行以下の全ファイルは全文。大ファイルは先頭40行+末尾40行+grep | 上記scopeファイル |
| セマンティック分類 | 第1波13群と比較して新義を特定 | 全対象 |
| grep確認 | 語の実出現を逆引きし文脈を確認 | 主要候補語 |

---

## 1. 結論（第2波新発見）

第1波で未検出だった5つの新多義衝突を確認。最重要はknowledge-base固有のL1/L2/L3/L4体系。

| # | 旧語 | 多義の型 | 衝突度 | 改名優先度 |
|---|---|---|---|---|
| 1 | **L1/L2/L3/L4 (KB)** | knowledge-base method複雑度ティア / PFレイヤー / SSOT層 / recalculate層 | HIGH: 同一記法で4独立体系 | P0 |
| 2 | **L1 (ML正則化)** | LASSO/L1ノルム / PF忍法レイヤー / KB複雑度ティア | HIGH: 研究文書内で混在 | P0 |
| 3 | **Phase (KB)** | KB適用準備フェーズ(1/2/3) / recalculate Phase(1-6) / 研究サイクルPhase | MEDIUM: 文脈依存 | P1 |
| 4 | **config** | pipeline_config / universe config(YAML) / ALM config UI / claude config.toml | MEDIUM: ファイル横断 | P1 |
| 5 | **Layer (KB分類語)** | 一次知識層/解釈層(KBタクソノミー) / 計算層 / PF命名層 | LOW-MEDIUM: 日本語「層」は区別しやすい | P2 |

---

## 2. 詳細インスタンス一覧

### 2.1 L1/L2/L3/L4 — knowledge-base method複雑度ティア（**最重要新発見**）

`docs/research/knowledge-base/index.md` のすべてのmethod entryに `Layer` 列がある。
この `Layer` の値(L1/L2/L3/L4)は「そのメソッドをDM-Signalに実装するための複雑度/準備コスト」を表す。

| Layer値 | KB文脈の意味 | 例 |
|---------|------------|---|
| L1 | 基礎/低複雑度。既存パイプラインへの追加が容易 | M13 Denoising, M43 Ward Clustering, M51 TSMOM |
| L2 | 中程度。状態モデルやレジーム判別を含む | M01 Bayesian, M05 HMM, M31 DMS-TVP |
| L3 | 高度。深層学習・複雑なアンサンブル | M09 PSR, M49 CVaR |
| L4 | メタ分析レベル | M03 Rank Persistence, M04 OOS R² |
| L1-L2 | 両境界 | M21 L1トレンドフィルタ, M51 TSMOM |
| L2-L3 | 両境界 | M77 X-Trend Few-Shot, M78 Momentum Transformer |

**衝突一覧:**

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| L1 | `knowledge-base/index.md` (M13/M29/M43等) | method複雑度ティア = 基礎レベル | HIGH |
| L1 | `context/dm-signal-core.md:12-16` | PFレイヤー = 忍法20体 | HIGH |
| L1 | `context/dm-signal-core.md:72-79` | SSOT計算層 = return計算関数 | HIGH |
| L2 | `knowledge-base/index.md` (M01/M05等) | method複雑度ティア = 中程度 | HIGH |
| L2 | `context/dm-signal-core.md:12-16` | PFレイヤー = 奥義21体 | HIGH |
| L2 | `context/gunshi-opt12-analysis.md:6,142` | recalculate実行段階 = Standard PF処理(109.47s) | HIGH |
| L3 | `knowledge-base/index.md` (M09等) | method複雑度ティア = 高度 | HIGH |
| L3 | `context/dm-signal-core.md:72-79` | SSOT層 = UI表示層 | HIGH |
| L3 | `context/gunshi-opt12-analysis.md:7,148` | recalculate実行段階 = FoF処理(214.01s) | HIGH |
| L4 | `knowledge-base/index.md` (M03/M04等) | method複雑度ティア = メタ分析 | MEDIUM |
| L4 | `context/dm-signal-frontend.md:115` | visibility layer = コンポーネント | HIGH |

**問題**: 同じ `L2` が「奥義」「MonthlyReturn cache」「Standard PF recalculate処理」「KB method中程度」を指す。
knowledge-baseを読む研究者と運用担当者で全く異なる意味になる。

### 2.2 L1 — ML正則化 / method名

`L1` が数学的表記(ノルム、正則化パラメータ)として登場する文脈がある。

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| L1 | `knowledge-base/index.md` M21 | `L1トレンドフィルタ` = メソッド名。L1ノルム正則化+2階差分でトレンド推定 | HIGH |
| L1 lam=10 | `context/gunshi-interpretation-layer-design.md:36` | LASSO正則化パラメータ λ=10 での前処理研究 | HIGH |
| L1 train/test差 | `context/gunshi-interpretation-layer-design.md:38` | L1正則化モデルのIS/OOS差 41.5pp | HIGH |
| L1 | `context/dm-signal-core.md:12-16` | PFレイヤー = 忍法 | HIGH |

**問題**: 研究文書で `L1 lam=10` を読んだとき、「忍法(PFレイヤー)のλパラメータ」と誤読するリスクがある。

### 2.3 Phase — knowledge-base適用準備フェーズ

`knowledge-base/index.md` の `Phase` 列は「そのメソッドをDM-Signalのどの段階で使うか」を表す。

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| Phase 1 | `knowledge-base/index.md` | KB適用準備 = 基礎分析段階 | MEDIUM |
| Phase 2 | `knowledge-base/index.md` | KB適用準備 = 検証段階 | MEDIUM |
| Phase 3 | `knowledge-base/index.md` | KB適用準備 = 実装/高度化段階 | MEDIUM |
| Phase 1-6 | `context/dm-signal-ops.md §6` | recalculate_fast.py処理段階 | HIGH |
| Phase 3(gs_data_loader v2) | `context/dm-signal-ops.md §30` | 開発リファクタリング段階名 | MEDIUM |
| C1/C2/C3/C4 | `context/dm-signal-research.md §19` | エッジ検知研究サイクル | LOW(記法異なる) |

**問題**: `Phase 2` とだけ書くと、knowledge-base文脈(検証段階)か recalculate文脈(特定処理)か、
あるいは開発段階名(gs_data_loader v2 Phase 3等)か区別がつかない。

### 2.4 config — 多文脈設定語

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| pipeline_config | `context/dm-signal-core.md`, `projects/dm-signal/pipeline-blocks.yaml` | portfolioのselection pipeline設定オブジェクト | MEDIUM |
| universe config | `context/dm-signal-ops.md §30` | GS探索対象PFを列挙するYAML (`config/portfolio_universes/*.yaml`) | MEDIUM |
| ALM config UI | `context/dm-signal-ops.md §31` | FE AdminのALM設定入力UI(未実装) | MEDIUM |
| claude config.toml | `context/dm-signal-ops.md §misc` | CodexのCLI設定ファイル | LOW |
| portfolio_configs | BE API | portfolio-levelの設定束 | MEDIUM |

**問題**: `config` とだけ書くと pipeline設定か GS universalか FE UIかが区別不能。

### 2.5 Layer — knowledge-base タクソノミー用語

| 旧語 | 使用箇所 | 文脈ごとの意味 | 衝突度 |
|---|---|---|---|
| 一次知識層 | `knowledge-base/guide.md` | methods/等の外部知識ディレクトリ | LOW |
| 解釈層 | `knowledge-base/guide.md` | dm-signal/のDM-Signal固有解釈 | LOW |
| Layer(KB列名) | `knowledge-base/index.md` header | method complexityの分類列 | MEDIUM |
| 層 | `context/gunshi-interpretation-layer-design.md` | 一次知識層/解釈層の略称 | MEDIUM |

**問題**: 「解釈層」という日本語は他の計算層/PF層と区別しやすいが、英語表記 `Layer` の KB列と
数値付き `L1/L2/L3` がくると衝突が生じる。

---

## 3. 第1波との差分（第2波固有の発見）

第1波ではカバーされていなかったknowledge-base固有の多義衝突:

| 第1波未検出 | 第2波確認 |
|-----------|---------|
| KB-LAYER (L1-L4が複雑度ティア) | ✅ 確認。knowledge-base/index.mdに全method entryで使用 |
| ML正則化としてのL1 | ✅ 確認。M21名称+前処理研究でlam=10表記 |
| Phase (KB適用準備フェーズ) | ✅ 確認。Phase 1-3が3段階 |
| config 4種 | ✅ 確認。pipeline/universe/ALM UI/claude config |
| L3(KB) vs L3(recalc FoF処理) | ✅ 確認。gunshi-opt12-analysis.mdで計測値併記 |

第1波確認済み語が第2波で追加義を持っていた:

| 語 | 第1波義 | 第2波追加義 |
|---|---------|-----------|
| L2 | 奥義, MonthlyReturn cache, PF命名層, recalculate layer | **KB method中程度ティア** (index.md M01等) |
| L3 | SSOT UI層, recalculate FoF処理 | **KB method高度ティア** (index.md M09等) |
| L1 | 忍法, return関数, SSOT層 | **KB method基礎ティア + ML正則化** (index.md, 前処理研究) |

---

## 4. MECE定義辞書 — 第2波追加エントリ

第1波辞書(cmd_2553)に追加すべきエントリ:

| 概念ID | 推奨正規名 | 旧語 | 定義 | 主な保存先 |
|---|---|---|---|---|
| KB_METHOD_TIER | kb_method_tier | L1/L2/L3/L4 (KB) | knowledge-base methodの実装複雑度ティア。L1=基礎, L2=中程度, L3=高度, L4=メタ分析 | `knowledge-base/index.md` Layer列 |
| ML_L1_NORM | ml_l1_regularization | L1 (ML) | L1ノルム正則化(LASSO)。パラメータλ(lam)で強度調整 | 前処理研究文書, M21 |
| ML_L1_TREND | ml_l1_trend_filter | L1トレンドフィルタ | L1正則化+2階差分によるトレンド推定手法(M21) | `knowledge-base/methods/l1-trend-filter.md` |
| KB_PHASE | kb_application_phase | Phase (KB) | knowledge-base methodのDM-Signal適用準備段階。Phase 1=基礎, Phase 2=検証, Phase 3=実装 | `knowledge-base/index.md` Phase列 |
| CONFIG_PIPELINE | pipeline_config | config (pipeline) | portfolioのselection pipeline設定オブジェクト | `projects/dm-signal/pipeline-blocks.yaml` |
| CONFIG_UNIVERSE | gs_universe_config | universe config | GS探索対象PFをリストするYAML | `config/portfolio_universes/*.yaml` |
| CONFIG_ALM_UI | alm_config_ui | ALM config UI | FE AdminのALM設定入力UI | `context/dm-signal-ops.md §31` |
| KB_PRIMARY_LAYER | kb_primary_knowledge_layer | 一次知識層 | knowledge-base外部知識ディレクトリ(methods/等) | `knowledge-base/guide.md` |
| KB_INTERP_LAYER | kb_interpretation_layer | 解釈層 | DM-Signal固有適用解釈ディレクトリ(dm-signal/) | `knowledge-base/guide.md` |

---

## 5. 改名計画 — 第2波追加事項

### Phase 1: knowledge-base Layerを明示化

1. `knowledge-base/index.md` の `Layer` 列ヘッダーを `KB_Tier` に変更する(または注釈追加)。
   L1-L4 = DM-Signal実装複雑度ティアであることをガイド冒頭に明記する。
2. `knowledge-base/guide.md` に「KB_Tier ≠ PF研究層(L0=四神/L1=忍法/L2=奥義)」と
   明示する警告ボックスを追加する。

### Phase 2: 新規cmd/report/research内の語彙を正規名へ寄せる

1. `L1` とだけ書く場合は文脈プレフィックスを付ける:
   - KB文脈: `kb_tier:L1`
   - PF文脈: `pf_stage_L1(忍法)` または `pf_stage_ninpo`
   - ML文脈: `ml_l1_norm` または `lasso_lam`
2. `Phase N` とだけ書く場合は文脈プレフィックスを付ける:
   - KB文脈: `kb_phase:N`
   - recalculate文脈: `recalc_phase:N`
   - 開発文脈: `dev_phase:N(説明)`
3. `config` とだけ書く場合は種別を付ける:
   - `pipeline_config`, `gs_universe_config`, `alm_config_ui`

### Phase 3: 既存ファイルの置換

| 対象 | 置換方針 |
|---|---|
| `knowledge-base/index.md` | `Layer` 列ヘッダーを `KB_Tier` に変更 |
| `knowledge-base/guide.md` | 冒頭に「KB_Tier vs PF Layer」の区別注釈を追加 |
| 前処理研究文書 | `L1 lam=10` → `lasso_lam=10` に変更(将来) |

---

## 6. 偵察5要件

| 要件 | 結論 |
|---|---|
| 変更対象ファイル・行番号 | `docs/research/knowledge-base/index.md` ヘッダー行(L33/L63等); `docs/research/knowledge-base/guide.md` 冒頭; `context/gunshi-interpretation-layer-design.md:36-38` |
| 波及先 | 全knowledge-base method entryのLayer列; 前処理研究文書; context/dm-signal-research.md §26以降の前処理参照 |
| 関連テスト | ドキュメント変更のみならunit不要。新規cmd gateで`L1/L2/L3` + `Phase` + `config` の文脈確認WARNを追加可能 |
| エッジケース・副作用 | `L1トレンドフィルタ`(M21)は方法名なので名称変更不要。ただし「L1 = 忍法」と混同しないよう参照時に明示必要 |
| 依存関係・順序制約 | Phase 1(KB index改名)→Phase 2(新規cmd語彙)→Phase 3(既存docs)。M21メソッド名は固有名詞なので変更不要 |

---

## 7. まとめ — 第1波+第2波統合所感

第1波(hayate/saizo)が context/*.md + projects/*.yaml + BE/FEコード を対象とした一方、
第2波(hanzo)では knowledge-base/index.md が最大の新発見場所だった。

**最重要追加知見**:
- knowledge-base の `Layer(L1-L4)` は PF研究層(L0-L3)とは完全に独立した体系
- しかし同じ `L1`/`L2`/`L3` 表記を使うため、研究文書と運用文書を並べて読むと混乱する
- 特に `L2` は 奥義 / MonthlyReturn cache / Standard PF recalculate実行時間 / KB中程度メソッド の4義がある

第1波13群+第2波5群 = 計18の多義衝突群を特定完了。
