<!-- gist-master: 12cb3fc496e1ce991b1b70480a7b43ce dm-unified-tobe-flow_20260815.md -->
# DM-Signal 統合ToBeフロー（キャッシュ一本化 × provenance）

## 原則（この文書の読み書きを支配する。殿裁定 2026-08-15）

- **ToBeは、構造的に不可能でない限り妥協しない。現実の関数名・行番号・今の実測値で理想を縛らない。理想は磨く。**
- **AsIsは現実のコードそのもの。間違いがあれば現実に合わせて直す。**

---

統合元: `dm-fullrecalculate-cache-reuse-asis_20260813` / `cmd_4296_momentum-window-recon_20260813` / `dm-decision-provenance-asis-tobe-5w1h_20260813` / `dm-weight-expansion-first-principles-asis-tobe_20260815`

## AsIs **v1.3** — 2026-08-15T16:35+09:00 / 対象 `origin/main = 5da7f107`（code固定。DB実測は observed_at 付きで別記）

```mermaid
flowchart TB
  classDef cache fill:#0b3d2e,stroke:#19a974,color:#ffffff,stroke-width:2px
  classDef skip fill:#3d2b0b,stroke:#f5a623,color:#ffffff
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef sink fill:#3d0b1e,stroke:#d94a6a,color:#ffffff
  classDef rule fill:#2a2a2a,stroke:#888888,color:#ffffff

  subgraph AL1["L1 入力層 — run冒頭に materialize"]
    APR[("prices")] --> ASNAP
    AEC[("economic / DTB3")] --> ASNAP
    ACF[("PF config")] --> ASNAP
    ASNAP["ImmutableInputManifest<br/>input_manifest.py:228<br/>+ 用途別view（df_dtb3_raw / df_dtb3_signal）<br/>recalculate_fast.py:1989-2012"]:::cache
  end

  subgraph AL2["L2 standard（recalculate_fast.py）"]
    ASNAP --> A1["日次ループ計算 → signals（メモリ）"]:::calc
    A1 --> A2["_flush_batch<br/>:2999 / :3020<br/>:3006 でクリアするのは <b>signals_batch のみ</b><br/>（cache全体を手放すわけではない）"]:::calc
  end

  A2 --> ADB[("DB: signals")]:::sink

  ADB --> A3["<b>OPT-4: db.query(Signal)...all()</b><br/>:3176（同型が :1236 / :3452 にも存在）<br/>全signalsをDBから再クエリ"]:::calc
  A3 --> A4["signal_cache_opt6 を空dictから再構築<br/>:3202-3206<br/><b>cache系統①</b>"]:::cache

  subgraph AL3["L3 FoF（recalculate_fast.py / recalculate_fof.py）"]
    A5["fof_shared_signal_cache = {}<br/>:3197<br/><b>cache系統② — 空dictから開始</b><br/>渡り先は :3559 の precompute trade_perf 側"]:::cache
    A4 --> A6["Phase 4.5 monthly_returns 生成<br/>引数は <b>signal_cache_opt6</b>（fof_sharedではない）<br/>:3228 / :3299"]:::calc
    A6 --> A7["_reload_signal_cache_entries<br/>:3291<br/><b>一般経路ではなく ALM second-pass 条件内のみ</b>"]:::calc
    A7 --> A8["FoF deferred flush"]:::calc
  end

  A8 --> ADB2[("DB: signals / monthly_returns")]:::sink

  subgraph AL5["L5 precompute（precompute_raw.py）"]
    ADB2 --> A9["signal_preload（DBロード）"]:::calc
    A9 --> A10["LazySignalArtifactCache を <b>L5内で新規生成</b><br/>:245<br/><b>cache系統③ — L2/L3からの受渡しではない</b>"]:::cache
    A10 --> A11["artifact_signal_cache を builder へ引数供給<br/>:246 / :281"]:::calc
    A11 --> A12["MonthlyTradeCalculator.calculate<br/>:321"]:::calc
    A12 --> A13["precompute_signal_payload_cache 経路<br/>price_ratio_impl.py:1116-1120"]:::cache
  end

  A2 -.->|"確定月の書換えを事後検知して発報"| ALERT["SIGNAL CHANGE ALERT / signal_change_log<br/>backend/app/jobs/flush/signal_flush.py:431 / :565<br/>2026-08-12撤去裁定 → 08-13 rollback 233c2303 で復活し現存"]:::skip

  A2 -.->|"台帳行あり かつ 不一致なら"| LEDG["ledger guard = <b>freeze（台帳値へ置換）</b><br/>reconcile_signal_batch_with_ledger<br/>signal_decision_ledger.py:409-447 — signals batch の holding_signal を台帳値で上書き<br/>resolve_confirmed_holding_signal :450-484 — monthly の holding_signal を台帳値で返す<br/>drift は log_signal_decision_drift で記録<br/>台帳行なし（pending）は素通り"]:::skip
  A6 -.->|"同上"| LEDG
  LEDGDB["<b>DB実測（codeではない）</b><br/>signal_decision_ledger = 0行<br/>observed_at=2026-08-13 run 355 input manifest 3ced522a…（`dm-fullrecalculate-cache-reuse-asis_20260813` §5.1）/ source=本番 recalculation_status 台帳の manifest 固定入力<br/>∴ 現時点では guard は全行素通り（行が入れば freeze が効く）"]:::rule

  ANOTE["<b>AsIsの帰結</b><br/>① cacheが3系統に分裂し、層の受渡しがDB経由（赤ノードが流れの途中にある）<br/>② run単位の fingerprint は在る（input_manifest.py:228 ImmutableInputManifest.build :235 → input_snapshot_id :251 / execution_fingerprint :256）。<b>無いのは PF×月 の依存fingerprint</b>。∴ run全体の同一性は判るが、確定月を PF×月 単位で skip する判断はできない<br/>③ 規則1/規則2の合成結果を保存する器はあるが、一致証明なしには使えない<br/>現物grep: opt6=6件 / fof_shared=4件 / payload_cache=2件<br/>signal_valid_dates_cache=0件 / validate_signal_snapshot=0件（T5/T6の削除は生存）"]:::rule
```

## ToBe **v3.9** — 2026-08-15T16:52+09:00（v3.9=不変量ノードを3列横並びにして縦長を解消。殿指示16:51 ← v3.8=各レイヤー帯に枠線を付け、左cache縦流/右計算縦流/横のレイヤー区切りを明示。殿指示16:48 ← v3.7=C11→X1 読み出しedgeを撤去。L1.1/L1.2が図上で並列に見えるため。X1はC12(C11を含む一つのcache)だけを読む。殿指摘16:45 ← v3.6=X1がC11(依存集合)も読むedgeを明示(軍師O1を将軍判断で採用) ← v3.5=不変量を図の最上段へ移動(殿指示16:40) ← v3.3=16:26 レビュー12件反映 → v3.4=L1.1→L1.2 を直列へ戻す。殿指摘16:35）

**読み方**: 横の破線枠=1レイヤー(L)。枠の左=cache列(C*)は上から下へ一本、枠の右=計算列(X*)も上から下へ一本。枠の中だけで「計算→合流(cacheへ追記)」と「cache→読み出し」が交わる。枠をまたぐのは縦の一本ずつのみ。上から下へ一度も戻らない。

```mermaid
flowchart TB
  classDef cache fill:#0b3d2e,stroke:#19a974,color:#ffffff,stroke-width:2px
  classDef skip fill:#3d2b0b,stroke:#f5a623,color:#ffffff
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef sink fill:#3d0b1e,stroke:#d94a6a,color:#ffffff
  classDef rule fill:#2a2a2a,stroke:#888888,color:#ffffff

  INV["<b>不変量</b>（3列×横並び）<br/>① W の定義は 規則1 と 規則2 のみ　｜　② 控え（前回確定成果物）を使うのは fingerprint 一致を示せた時だけ。復元元は L1 で read-once した snapshot　｜　③ Σ W = 1.0 を各段で検算<br/>④ 確定した過去は 入力・規則・規則実装の版 が変わらない限り変わらない（fingerprint の入力に rule/source version を含む）　｜　⑤ 深度は浅い順に直列。depth ごとに1行。graph は topological fold を一方向に unroll した形で書く　｜　⑥ 構成PFの深度は混在してよい（standard との同居を含む）<br/>⑦ 計算開始の前提は全構成PFが上段の cache に在ること。欠けたら停止　｜　⑧ config だけで解けるものは計算前の構造解決層で解く。構造解決の入力（config/ledger snapshot）は L0 で先に固定する　｜　⑨ 全経路の最大を採る。循環は invalid graph として run 停止（fail-closed）<br/>⑩ L1.1 → L1.2 も直列。並列にできるが<b>あえて直列</b>にする。混乱を生まない一本道が優先　｜　⑪ 分析派生・表示投影・永続化は別責務。分析結果は判定へ戻さない　｜　⑫ 左=cache は縦に一本、右=計算は縦に一本。例外なし。交わるのは各L内の合流と読み出しだけ<br/>⑬ run identity と PF×月の依存fingerprint は別物。混ぜない　｜　⑭ <b>上から下へ一度も戻らない。</b>後段が必要とするものは必ず前段で確定している　｜　⑮ price consumer の依存集合は L1.1 が全消費者分を列挙する（保有ticker だけではない）<br/>⑯ cache 契約は producer の出力と consumer の入力が同じ語で一致する（monthly と cumulative は別々に列挙）"]:::rule
  INV ~~~ R0

  subgraph R0["L0 run開始 — 構造の入力を固定"]
    direction LR
    C0["<b>cache を1個だけ生成</b><br/>再生成・複製・空初期化は禁止。identity は最後まで不変<br/>+ <b>config snapshot</b>（全PF構成・重み・momentum規則・rule version）<br/>+ <b>ledger snapshot / watermark</b><br/>+ <b>source version</b>（規則実装の版）"]:::cache
    X0["config と ledger を<b>一度だけ</b>読み snapshot 化<br/>以後の全層はこの snapshot だけを見る"]:::calc
    X0 -.->|"合流"| C0
  end

  subgraph R11["L1.1 ticker解決層"]
    direction LR
    C11["+ <b>price consumer 依存集合</b><br/>= 保有しうる ticker ∪ benchmark ∪ canonical calendar 銘柄 ∪ economic / DTB3 系列<br/>（価格・系列を読む全consumerの和集合）"]:::cache
    X11["config snapshot だけで解く<br/>standard PF を構成tickerへ分解 → 保有しうる ticker<br/>+ benchmark / calendar / economic の依存を列挙"]:::calc
    X11 -.->|"合流"| C11
  end

  subgraph R12["L1.2 深度解決層"]
    direction LR
    C12["+ depth 表 と 実行順序<br/>循環検出結果"]:::cache
    X12["config snapshot だけで解く<br/>子・孫・ひ孫まで全経路を辿る<br/>depth(P)=1+max(depth(C_i))、standard は 0<br/>同一PFが複数世代に現れる → 全経路の最大<br/><b>循環を検出したら invalid graph として run 停止（fail-closed）</b><br/>depth と topological 実行順序は停止しない場合のみ確定"]:::calc
    X12 -.->|"合流"| C12
  end

  subgraph R1["L1 入力層 — 不変入力と前回確定成果物を read-once"]
    direction LR
    C1["+ 不変入力snapshot<br/>prices / DTB3 / economic（C11 の依存集合の範囲）<br/>+ <b>前回確定成果物snapshot</b>（PF×月の W / monthly / cumulative / provenance / 依存fingerprint）<br/>= judge 一致時の<b>復元元</b>。ここで一度だけ読み、以後は左列にしか無い"]:::cache
    X1["C11 の依存集合の範囲だけ prices / DTB3 / economic を一度だけ materialize（modeに依存しない）<br/>+ 前回確定成果物を一度だけ materialize<br/>（永続層を読むのは run 全体でここ一回）"]:::calc
    C12 -.->|"読む"| X1
    X1 -.->|"合流"| C1
  end

  subgraph R13["L1.3 run identity"]
    direction LR
    C13["+ <b>run identity</b><br/>入力一式（C0 + C1）の同一性（run単位・O(1)）"]:::cache
    X13["C0 と C1 の入力一式から1回だけ導く"]:::calc
    C1 -.->|"読む"| X13
    X13 -.->|"合流"| C13
  end

  subgraph R2["L2 standard（depth 0）"]
    direction LR
    C2["+ standard の signals / W / monthly / <b>cumulative</b><br/>+ provenance / <b>PF×月の依存fingerprint</b>"]:::cache
    X2["<b>a 現fingerprint</b>　PF×月ごとに 入力(C1) + rule version + source version(C0) から<b>先に</b>作る<br/><b>b judge</b>　現fingerprint と C1 の前回fingerprint が一致 → C1 の前回成果物を<b>復元</b>（計算しない）<br/>不一致 → momentum（日次close・months×21営業日・on-or-before）→ 判定 → <b>規則1</b> W=選定銘柄へ1.0<br/><b>c 価格適用</b>　W と価格から monthly / cumulative<br/><b>d 記録</b>　provenance と現fingerprint を合流"]:::calc
    C13 -.->|"読む"| X2
    X2 -.->|"合流"| C2
  end

  subgraph R3A["L3a leaf FoF（depth 1）"]
    direction LR
    C3A["+ leaf FoF の signals / W / monthly / cumulative<br/>+ provenance / 依存fingerprint"]:::cache
    X3A["a 現fingerprint（子standardの fingerprint ∪ 自PF config ∪ rule/source version）→ b judge（一致=C1から復元）<br/>→ 不一致: momentum（入力=子standardの monthly cumulative・窓=月数の行差分）→ 判定 → <b>規則2</b> W=Σ w_i × W(C_i)<br/>→ c 価格適用 → d 記録"]:::calc
    C2 -.->|"読む"| X3A
    X3A -.->|"合流"| C3A
  end

  subgraph R3B2["L3b-2 nested FoF（depth 2）"]
    direction LR
    C3B2["+ depth 2 FoF の同上"]:::cache
    X3B2["<b>前提</b>: 全構成PFの W / monthly / cumulative が C2 ∪ C3A に在ること。欠けたら停止（永続層へ取りに行かない・空で代替しない）<br/>a 現fingerprint → b judge → 不一致: momentum → 判定 → <b>規則2</b> → c 価格適用 → d 記録"]:::calc
    C3A -.->|"読む"| X3B2
    X3B2 -.->|"合流"| C3B2
  end

  subgraph R3B3["L3b-3 nested FoF（depth 3）"]
    direction LR
    C3B3["+ depth 3 FoF の同上"]:::cache
    X3B3["前提: 全構成PFが C2 ∪ C3A ∪ C3B2 に在ること。欠けたら停止<br/>同じ規則2の再適用（a→b→c→d）"]:::calc
    C3B2 -.->|"読む"| X3B3
    X3B3 -.->|"合流"| C3B3
  end

  subgraph R3B4["L3b-4 nested FoF（depth 4 = 現最大。深度が増えれば行を1つ足す）"]
    direction LR
    C3B4["+ depth 4 FoF の同上"]:::cache
    X3B4["前提: 全構成PFが C2 ∪ C3A ∪ C3B2 ∪ C3B3 に在ること。欠けたら停止<br/>同じ規則2の再適用（a→b→c→d）"]:::calc
    C3B3 -.->|"読む"| X3B4
    X3B4 -.->|"合流"| C3B4
  end

  subgraph R5A["L5a 分析派生層"]
    direction LR
    C5A["+ drawdown / rolling / metrics / risk / trade_perf"]:::cache
    X5A["cache の確定値（monthly / cumulative / W）から導く<br/><b>導出だけ。判定へ戻さない</b>"]:::calc
    C3B4 -.->|"読む"| X5A
    X5A -.->|"合流"| C5A
  end

  subgraph R5B["L5b 表示投影・永続化層"]
    direction LR
    C5B["（cacheへの追記なし）"]:::cache
    X5B["cache から表示成果物を組み立てる<br/><b>永続層を読まない</b>"]:::calc
    C5A -.->|"読む"| X5B
  end

  C0 --> C11 --> C12 --> C1 --> C13 --> C2 --> C3A --> C3B2 --> C3B3 --> C3B4 --> C5A --> C5B
  X0 --> X11 --> X12 --> X1 --> X13 --> X2 --> X3A --> X3B2 --> X3B3 --> X3B4 --> X5A --> X5B

  subgraph RDB["永続化（最下段）"]
    direction LR
    CDB["（cacheへの追記なし）"]:::cache
    DB[("<b>DB</b>　書き切り。run の途中で誰も読み返さない<br/><b>禁止</b>: L2 以降のどの層も永続層を読まない。必要な値は必ず左列の cache に在る<br/>永続層を読むのは L0（config/ledger）と L1（prices/前回確定成果物）の read-once だけ")]:::sink
  end

  C5B --> CDB
  X5B -.->|"書き切り（永続化はここだけ）"| DB


  %% レイヤー帯: 各subgraph=1レイヤー。左=cache列(C*)、右=計算列(X*)。帯の中だけで合流/読み出しが交わる
  style R0 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R11 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R12 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R1 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R13 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R2 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R3A fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R3B2 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R3B3 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R3B4 fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R5A fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style R5B fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3
  style RDB fill:#0d0d0d,stroke:#c9c9c9,stroke-width:1.5px,stroke-dasharray:6 3

```

## 注釈（レイヤー単位。図で足りない粒度はここに書く）— 2026-08-15T16:37+09:00

### AsIs 注釈
- **L1 入力層**: `ImmutableInputManifest.build`（input_manifest.py:228/235）が prices/economic/config/ledger の artifact hash から `input_snapshot_id`(:251) と `execution_fingerprint`(:256) を作る。run単位の同一性はここで判る。PF×月単位の依存fingerprintは存在しない。DTB3は用途別viewが recalculate_fast.py:1989-2012 で作られる。
- **L2 standard**: 日次ループ→signals をメモリに持ち `_flush_batch`(:2999/:3020) で DB へ書く。:3006 で消すのは signals_batch のみ。flush 直前に `reconcile_signal_batch_with_ledger`(signal_decision_ledger.py:409-447) が台帳行のある (PF,date) の holding_signal を台帳値へ置換し drift を記録する。台帳行なしは素通り。
- **L2→L3 の受渡し**: DB へ書いた signals を OPT-4 `db.query(Signal)...all()`(:3176、同型 :1236/:3452) で再クエリし `signal_cache_opt6` を空dictから再構築(:3202-3206)。cache系統①。
- **L3 FoF**: `fof_shared_signal_cache={}`(:3197、cache系統②)は precompute trade_perf 側(:3559)へ渡る。Phase 4.5 monthly_returns(:3228/:3299) の引数は signal_cache_opt6。monthly の holding_signal は `resolve_confirmed_holding_signal`(:450-484) が台帳値で返す。`_reload_signal_cache_entries`(:3291) は ALM second-pass 条件内のみ。
- **L5 precompute**: `signal_preload` が DB を読み、`LazySignalArtifactCache` を L5 内で新規生成(:245、cache系統③)。builder へ引数供給(:246/:281)→`MonthlyTradeCalculator.calculate`(:321)→`precompute_signal_payload_cache`(price_ratio_impl.py:1116-1120)。
- **事後検知**: 確定月の書換えは SIGNAL CHANGE ALERT / signal_change_log(signal_flush.py:431/:565)が発報。08-12 撤去裁定→08-13 rollback 233c2303 で復活し現存。
- **DB実測（code ではない）**: signal_decision_ledger=0行。observed_at=2026-08-13 run 355 input manifest 3ced522a…（`dm-fullrecalculate-cache-reuse-asis_20260813` §5.1）。∴現時点の ledger guard は全行素通り。行が入れば freeze が効く。
- **帰結**: cache が3系統に分裂し層の受渡しが DB 経由。run単位 fingerprint はあるが PF×月の依存fingerprint が無く確定月を PF×月で skip できない。規則1/規則2 の合成結果を保存する器はあるが一致証明なしには使えない。現物grep: opt6=6 / fof_shared=4 / payload_cache=2 / signal_valid_dates_cache=0 / validate_signal_snapshot=0。

### ToBe 注釈
- **L0 run開始**: cache は1個。config（全PF構成・重み・momentum規則・rule version）と ledger（snapshot/watermark）と source version（規則実装の版）を一度だけ読み snapshot 化。以後どの層も生の config/ledger を読まない。構造解決層(L1.1/L1.2)の入力はここで固定される。
- **L1.1 構造解決（依存集合）**: 保有しうる ticker だけでなく、価格・系列を読む全 consumer（benchmark、canonical calendar 銘柄、economic/DTB3 系列）の和集合を列挙する。L1 が materialize する範囲はこの集合。
- **L1.2 構造解決（深度）**: depth(P)=1+max(depth(C_i))、standard=0。同一PFが複数世代に現れたら全経路の最大。循環を検出したら invalid graph として run を停止（fail-closed）。depth 表と topological 実行順序は停止しない場合のみ確定。L1.1 → L1.2 は直列。並列可能でもあえて直列（一本道で混乱を生まない）。
- **L1 入力層**: C11 の範囲で prices/DTB3/economic を一度だけ materialize。加えて前回確定成果物（PF×月の W/monthly/cumulative/provenance/依存fingerprint）を一度だけ read-once。judge 一致時の復元元はここにしか無い。永続層を読むのは L0 と L1 の read-once だけ。
- **L1.3 run identity**: C0+C1 の入力一式から run 単位で1回導く（O(1)）。PF×月の依存fingerprint とは別物。
- **L2 standard**: PF×月ごとに **a** 現fingerprint（入力(C1)+rule version+source version(C0)）を先に作る → **b** judge：C1 の前回fingerprint と一致なら前回成果物を復元し計算しない。不一致なら momentum（日次close・months×21営業日・on-or-before）→判定→規則1（W=選定銘柄へ1.0）→ **c** 価格適用（monthly/cumulative）→ **d** provenance と現fingerprint を合流。cache 契約は signals/W/monthly/cumulative/provenance/依存fingerprint を別々に列挙。
- **L3a leaf FoF（depth1）**: 現fingerprint=子standardの fingerprint ∪ 自PF config ∪ rule/source version。momentum の入力は子standardの monthly cumulative（窓=月数の行差分）。規則2 W=Σ w_i×W(C_i)。
- **L3b nested FoF（depth2/3/4）**: depth ごとに1行。前提=全構成PFの W/monthly/cumulative が上段 cache に在ること。欠けたら停止（永続層へ取りに行かない・空で代替しない）。同じ規則2の再適用。graph は topological fold を一方向に unroll し、上へ戻る edge を持たない。深度が増えたら行を1つ足す。
- **L5a 分析派生**: drawdown/rolling/metrics/risk/trade_perf は cache の確定値から導くだけ。判定へ戻さない。
- **L5b 表示投影・永続化**: cache から表示成果物を組み立て、DB へ書き切る。run の途中で誰も DB を読み返さない。
- **不変量**: 図中 INV ①〜⑯。
