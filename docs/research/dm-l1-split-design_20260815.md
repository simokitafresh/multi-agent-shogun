<!-- gist-master: 4e64d25bfbca1b3a33803546cd2145d4 dm-l1-split-design_20260815.md -->
# L1分割設計 — AsIs L1 を ToBe の L1 / L1.1 / L1.2 / run identity へ

## 原則（親文書と同じ。殿裁定 2026-08-15）

- **ToBeは、構造的に不可能でない限り妥協しない。現実の関数名・行番号・今の実測値で理想を縛らない。理想は磨く。**
- **AsIsは現実のコードそのもの。間違いがあれば現実に合わせて直す。**

親文書: `dm-unified-tobe-flow_20260815`（gist 12cb3fc4・ToBe v3.11）。本書はその ToBe の最上段5行（L0 / L1.1 / L1.2 / L1 / L1.3）だけを対象にする。

**スタート**: `origin/main = 5da7f107` の現物（AsIs）。**ゴール**: 5層が独立し直列に並び、業務値が1件も変わらないこと（二値の合否）。この2点から逸脱しない。

---

## AsIs **v1.5** — 2026-08-15T21:25+09:00 / 対象 `origin/main = 925b8338`（L0 f0194282 / #1 b3156fb5 / #2 5e307731 / #3 fbcc8be0 / #4 2268592d / #5 925b8338 の全6手が本番 live。各手 full 1回→業務値突合 差分0＝**ゴール到達**）

**現状、L0 → L1.1 → L1.2 → L1 → L1.3 が独立した層として直列に並び、業務値は1件も変わっていない（run405〜412、各 monthly 16,976行 / metrics 204行 差分0）。**

| ToBeでの居場所 | 現状の実体 | 位置 |
|---|---|---|
| **L0 config snapshot** | `snapshot_portfolio_configs(payload.portfolios)` → `db.info["portfolio_config_snapshot"]`、ledger 全行 → `db.info["signal_decision_ledger_snapshot"]`。以後 Portfolio 行を再読しない | `recalculate_fast.py:1985` / `:2006`。定義 `input_manifest.py:28` / `:62` / `:67` |
| **L1.1 ticker解決（config-only）** | `resolve_price_consumer_dependencies(...)` → `PriceConsumerDependencySnapshot`（`stock_symbols` / `consumer_symbols` / `economic_symbols`）。価格を読まない | 呼出 `recalculate_fast.py:2100`、定義 `input_manifest.py:63` / `:83` / `:90` / `:95` |
| **L1.2 深度解決（config-only）** | `_resolve_fof_dependency_plan(config_snapshot)` → PFごとの `depth_by_id`（1値=最深）・`max_depth`・依存順 `execution_order`。未知の子・重複id・循環は `ValueError` で run 停止 | 呼出 `recalculate_fast.py:2107`、定義 `:165` |
| **L1 入力materialize** | 範囲は L1.1 の出力で決まる。`stock_symbols = list(price_consumer_dependencies.stock_symbols)` → `load_prices_as_df`、経済系列は `economic_symbols` から | `:2115` → `:2124` 以降 |
| **L1.3 run identity（1つ）** | `ImmutableInputManifest.build` が `run_identity`（C0+C1 の入力一式）を1つ算出し `manifest_id = run_identity`。`stats["run_identity"]` に記録 | 呼出 `recalculate_fast.py:2203` / `:2226`、定義 `input_manifest.py:425-438` |
| **直列固定** | L0(:1985) → L1.1(:2100) → L1.2(:2107) → L1(:2115) → L1.3(:2203) の順に呼び出される | `925b8338` |

**確認できた事実（現物grep・2026-08-15 21:25）**: 上表の全行番号は origin/main=925b8338 の現物。二値の合否表は全項目PASS（値=run405〜412 差分0 / 範囲=L1.1 出力が materialize 範囲 / 深度=depth 1値 / 独立性=価格を読まない / 順序=直列 / identity=1つ）。

---

## ToBe **v1.2** — 2026-08-15T20:45+09:00

**5つを、それぞれ独立した層にし、直列に並べる。順序と依存だけを固定し、計算そのものは変えない。**（親文書 ToBe v3.11 の最上段5行と同一）

```mermaid
flowchart TB
  classDef cache fill:#0b3d2e,stroke:#19a974,color:#ffffff,stroke-width:2px
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef rule fill:#2a2a2a,stroke:#888888,color:#ffffff

  INV1["<b>この分割の不変量</b><br/>① L1.1 と L1.2 は<b>価格を読まない</b>。C0 の config snapshot だけで解ける<br/>② 5層は<b>直列</b>。並列にできても、あえて直列（一本道で混乱を生まない）<br/>③ L1 が materialize する範囲は<b>L1.1 の出力（price consumer 依存集合）が決める</b>（mode に依存しない）"]:::rule
  INV2["④ run identity は<b>1つ</b>。C0+C1 の入力一式の同一性だけを表す。PF×月の依存fingerprint とは別物<br/>⑤ 循環は invalid graph として run 停止（fail-closed）<br/>⑥ この分割で<b>計算結果は1件も変わらない</b>"]:::rule

  subgraph R0["L0 run開始 — 構造の入力を固定"]
    direction LR
    C0["<b>cache を1個だけ生成</b><br/>+ <b>config snapshot</b>（全PF構成・重み・momentum規則・rule version）<br/>+ ledger snapshot / watermark<br/>+ source version"]:::cache
    X0["config と ledger を<b>一度だけ</b>読み snapshot 化<br/>以後の全層はこの snapshot だけを見る"]:::calc
    C0 <-.-|"合流"| X0
  end

  subgraph R11["L1.1 ticker解決層"]
    direction LR
    C11["+ <b>price consumer 依存集合</b><br/>= 保有しうる ticker ∪ benchmark ∪ canonical calendar 銘柄 ∪ economic / DTB3 系列"]:::cache
    X11["config snapshot だけで解く<br/>standard PF を構成tickerへ分解 → 保有しうる ticker<br/>+ benchmark / calendar / economic の依存を列挙<br/><b>価格を1行も読まない</b>"]:::calc
    C11 <-.-|"合流"| X11
  end

  subgraph R12["L1.2 深度解決層"]
    direction LR
    C12["+ depth 表（PF → 最深 depth の1値）"]:::cache
    X12["config snapshot だけで解く<br/><b>PFごとに depth 1値（最も深い経路の値）だけを記録する</b><br/>depth(P)=1+max(depth(C_i))、standard は 0<br/>経路・世代・混在の分析結果は持たない（L3 は depth 順に回すだけ）<br/><b>循環を検出したら invalid graph として run 停止（fail-closed）</b>"]:::calc
    C12 <-.-|"合流"| X12
  end

  subgraph R1["L1 入力層"]
    direction LR
    C1["+ 不変入力snapshot<br/>prices / DTB3 / economic（C11 の依存集合の範囲）"]:::cache
    X1["C11 の依存集合の範囲だけ prices / DTB3 / economic を一度だけ materialize（mode に依存しない）"]:::calc
    C12 -.->|"読む"| X1
    C1 <-.-|"合流"| X1
  end

  subgraph R13["L1.3 run identity"]
    direction LR
    C13["+ <b>run identity</b>（1つ）<br/>入力一式（C0 + C1）の同一性（run単位・O(1)）"]:::cache
    X13["C0 と C1 の入力一式から1回だけ導く<br/><b>PF×月の依存fingerprint とは別物</b>"]:::calc
    C1 -.->|"読む"| X13
    C13 <-.-|"合流"| X13
  end

  INV1 ~~~ R0
  INV2 ~~~ R0
  C0 --> C11 --> C12 --> C1 --> C13
  X0 --> X11 --> X12 --> X1 --> X13
```

（親文書 L1 の「前回確定成果物 snapshot の read-once」は judge/fingerprint の領域なので本書の対象外。次の設計書で扱う）

---

## 差分（AsIs → ToBe）

| # | やること | 種別 |
|---|---|---|
| 0 | ~~L0: config / ledger を run 冒頭で一度だけ読み snapshot 化する~~ **本番 live（f0194282、業務値差分0）** | 完了 |
| 1 | ~~L1.1: ticker解決を独立層へ切り出す~~ **本番 live（b3156fb5、業務値差分0、run408）** | 完了 |
| 2 | ~~L1: materialize する銘柄範囲を、L1.1 の出力から決める形にする~~ **本番 live（5e307731、業務値差分0、run409）** | 完了 |
| 3 | ~~L1.2: 深度解決層を新設する~~ **本番 live（fbcc8be0、業務値差分0、run410）**。PFごとに depth 1値のみ | 完了 |
| 4 | ~~L1.3: run identity を1つに整理し、C0+C1 から導く~~ **本番 live（2268592d、業務値差分0、run411）** | 完了 |
| 5 | ~~5層を **直列** に並べる~~ **本番 live（925b8338、業務値差分0、run412）** | 完了 |

**全6手完了（2026-08-15 17:20 下知 → 21:18 #5 PASS）。**

---

## なぜ単独でできるか

- **計算式に触れない。** momentum も規則1・規則2 も一切変更しない
- **判定に触れない。** holding_signal の決まり方は変わらない
- **保存値を使わない。** cmd_4312の事故（控えを一致証明なしに計算入力へ昇格）とは無関係
- ∴ **業務値は1件も変わらないはず。** それが二値の合否になる

## 二値の合否

| 判定 | 内容 |
|---|---|
| **値** | full 1回で `monthly_returns` / `portfolio_metrics` が基準と完全一致（cmp_rc=0）。1件でも差が出たら不合格 |
| **範囲** | L1.1が出す price consumer 依存集合が、現行 `stock_symbols`（保有＋benchmark＋リスクフリー等の5分類）と**同一集合**であること。1銘柄でも増減したら不合格 |
| **深度** | L1.2が出す depth 表が、本番の樹形図と一致すること。混在深度の親（実測1件）と、同一PFが複数世代に現れる組（実測14件）を正しく扱えること |
| **独立性** | L1.1とL1.2が価格を1行も読まないこと。入力は C0 の config snapshot のみ |
| **順序** | L0→L1.1→L1.2→L1→L1.3 が直列であること（並列枝なし） |
| **identity** | run identity が1つになり、C0+C1 から導かれ、PF×月の依存fingerprintと混ざっていないこと |

## この設計が触れないもの

- L2以降の判定・規則・月次集約
- fingerprint skip（速度の本体）
- cacheの一本化そのもの（L2→L3→L5の受渡し）
- 台帳・guard・ALERT

- 前回確定成果物 snapshot の read-once（judge の復元元）

**それらは次の設計書で扱う。ここは最上段5行だけ。**
