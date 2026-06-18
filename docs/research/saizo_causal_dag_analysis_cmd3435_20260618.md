# 因果辺DAG構造 完全分析レポート
<!-- cmd_3435 Phase1 AC1 | saizo | 2026-06-18 -->
<!-- parent: [[殿指示_オントロジー記事_20260618]] | origin: [[操作的オントロジーPhase1設計]] -->

## 分析対象

`docs/semantic-index/index.md` (3915行, 458KB)
分析実行: 2026-06-18

---

## 1. ノード構造

| 指標 | 値 |
|------|---|
| 宣言conceptノード (`## id — label`) | **79** |
| `[[link]]`参照のみの未宣言ノード | **669** |
| グラフ上の全ノード数 | **748** |

### 宣言conceptノード一覧(79件)

カテゴリ別分類:

| カテゴリ | 件数 | 代表concept_id |
|---------|------|---------------|
| インフラ/運用 | 18 | infrastructure_ops, growth_loop, gate_quality_framework, lesson_lifecycle |
| 記憶/セマンティクス | 8 | local_memory_db, three_layer_memory_system, semantic_causal_automation, semantic_dictionary_design |
| DM-Signal | 10 | dmsignal_operations, shin_shijin_design, gs_ninpo_research, alpha_6_metrics |
| エージェント運用 | 7 | agent_formation_management, chain_principle, training_cycle_quality, report_quality_protocol |
| 原則・哲学 | 9 | known_unknowns_principle, no_auto_extinguish, verify_dont_imagine, creator_brainwashing_defense |
| プロジェクト | 12 | project_dividend_tracker, google_classroom, kj_series, external_project_registry |
| 因果・品質 | 8 | causal_traversal_pipeline, causal_verification_l0_l7, codd_methodology, production_parity |
| その他 | 7 | various |

---

## 2. エッジ構造

| エッジ種別 | 行数 | 抽出エッジ数 |
|-----------|------|------------|
| `\| causal \|` (origin/depends_on/raw) | 303 | **496** |
| `\| related_concepts \|` (無向) | 80 | **358** |
| **合計** | 383 | **854** |

### causalエッジ内訳

| 種別 | 行数 |
|------|------|
| `origin:` (因果チェーン) | 239 |
| `depends_on:` (依存関係) | 54 |
| その他 (raw因果) | 10 |

---

## 3. 連結性分析

| 指標 | 値 |
|------|---|
| 連結成分数 | **191** |
| 最大成分サイズ | **87ノード** (宣言79 + 未宣言8) |
| 孤立ノード(size=1) | **0** |
| size=2成分 | **4** |
| size=3〜5成分 | **179** |
| size>5成分 | **8** |

### 重要な発見: 宣言conceptは全て連結

全79宣言conceptノードは**最大連結成分(87)に属する**。
`related_concepts`エッジが79個全てをブリッジしているため、宣言レベルでの孤立は存在しない。

---

## 4. 孤立点の実体: [[link]]参照の到達率

| 指標 | 値 |
|------|---|
| causal行内の`[[link]]`参照延べ数 | **747** |
| ユニーク`[[link]]`参照数 | **669** |
| 宣言conceptにマッチした参照 | **1 (0.1%)** |
| **未宣言(浮遊ノード)** | **668 (99.9%)** |

### 浮遊ノードのパターン分類

| パターン | 件数 | 例 |
|---------|------|---|
| `cmd_XXX`系 | 107 | `[[cmd_3058]]`, `[[cmd_3063]]` |
| 殿指示/裁定系 | 72 | `[[殿裁定2026-05-22]]`, `[[殿指示_オントロジー記事_20260618]]` |
| `LS-`/`L-`教訓系 | 35 | `[[LS045]]`, `[[LS-A19]]` |
| `blt_`掲示板系 | 23 | `[[blt_20260601_133054_d4ac36]]` |
| spec/Phase系 | 23 | `[[spec_Phase5c]]`, `[[phase_5core_layer1_layer3]]` |
| その他 (日本語/事象名) | 411 | `[[Goodhart過剰適合]]`, `[[三層記憶根幹バグ]]` |

**核心問題**: 因果辺の99.9%が「浮遊[[link]]」で終端。宣言conceptに辿り着けないため、
グラフトラバーサルが1ホップで孤立島に落ちる。これが「197(≈191)連結成分/最大5」の実体。

---

## 5. ファイル→Concept カバレッジ

| 指標 | 値 |
|------|---|
| `\| file \|`エントリの総ファイル数 | 340 |
| `\| cmd \|`エントリ内のファイル数 | 196 |
| 合計ユニークファイル | **477** |
| conceptへのマルチマップファイル | 49 (10%超) |

### gitトラッキングファイル vs concept対応率

| スコープ | 総数 | concept対応有 | concept対応なし(NO_MATCH) |
|---------|------|-------------|--------------------------|
| scripts/ + context/ + docs/ + tests/ | 1205 | 331 (27.5%) | **874 (72.5%)** |

**72.5%のgitファイルがconcept未登録** → NO_MATCH自動生成の対象母集団

### 主要NO_MATCHファイル群(未登録ファイルの例)

```
context/karo-operations.md        → karo_ops相当conceptなし
context/obsidian-link-principles.md → obsidian_links相当なし
context/gunshi-*.md (分析レポート群) → 各分析レポートのconcept未登録
docs/design/*.md                  → 設計書群のconcept未登録
tests/unit/test_*.bats            → 多くがtest_quality_framework未接続
```

---

## 6. 概念到達率(Concept Reachability)

定義: 「任意のcausal `[[link]]`から最大K跳で宣言conceptに辿り着ける割合」

| K跳 | 到達率 |
|-----|-------|
| 0 (直接) | **0.1%** (1/669) |
| 1 | 推定 < 5% (浮遊ノードに隣接する宣言conceptへの経路が稀) |
| ∞ | 宣言concept79個は全連結だが浮遊ノード側から辿る経路が未設計 |

---

## 7. 殿の指摘との照合

> 「235エッジ/422ノード/197連結成分(最大5)でほぼ孤立点の集合」(task_yaml purpose)

| 殿指摘値 | 本分析値 | 差異説明 |
|---------|---------|---------|
| 235エッジ | 496 causal + 358 rc = 854 | related_concepts除外 or 古いsnapshotの可能性 |
| 422ノード | 748 (79+669) | 解析スコープ・バージョン差 |
| 197連結成分 | 191 | ほぼ一致。浮遊[[link]]クラスタの数 |
| 最大=5 | 87 | 宣言conceptをグラフに含めるか否かの差 |

**解釈**: 殿の数値は「宣言conceptを除いた浮遊ノードのみのグラフ」を想定。
浮遊ノード669個のサブグラフは最大成分8ノード(cmd_XXX依存チェーン)で、
ほぼ全てが孤立点=殿の観察と一致する。

---

## 8. 結論: 断片化の根因

```
根因: [[link]]参照 ⊅ 宣言conceptノード空間
         ↓
浮遊ノード668/669(99.9%)が孤立島を形成
         ↓
グラフトラバーサル不能 → セマンティック検索が因果辺をたどれない
         ↓
操作的波及(1変更→全連鎖更新)が機能しない
```

**修正方向**:
1. [[link]]参照を宣言conceptにマッピングする自動推論ロジック(AC2設計)
2. マッピング不能時に仮conceptを自動生成(AC3設計)
3. 結果として「浮遊ノード→宣言concept空間」への橋渡しが完成し、グラフが有機的に成長する

---

## 参照

- `docs/semantic-index/index.md` (分析対象)
- `scripts/semantic_index_update.sh` (既存インフラ)
- `queue/bulletin_board.yaml` blt_20260618_183654 (殿指示)
- → AC2設計: `docs/research/saizo_files_modified_concept_inference_design_cmd3435_20260618.md`
- → AC3設計: `docs/research/saizo_provisional_concept_autogen_design_cmd3435_20260618.md`
