<!-- gist-master: 12cb3fc496e1ce991b1b70480a7b43ce dm-unified-tobe-flow_20260815.md -->
# DM-Signal 統合ToBeフロー（キャッシュ一本化 × provenance）

## 原則（この文書の読み書きを支配する。殿裁定 2026-08-15）

- **ToBeは、構造的に不可能でない限り妥協しない。現実の関数名・行番号・今の実測値で理想を縛らない。理想は磨く。**
- **AsIsは現実のコードそのもの。間違いがあれば現実に合わせて直す。**

---

統合元: `dm-fullrecalculate-cache-reuse-asis_20260813` / `cmd_4296_momentum-window-recon_20260813` / `dm-decision-provenance-asis-tobe-5w1h_20260813` / `dm-weight-expansion-first-principles-asis-tobe_20260815`

## AsIs **v1.2** — 2026-08-15T15:20+09:00 / 対象 `origin/main = 5da7f107`

変更: v1.0=初版(15:05) → v1.1=軍師指摘3件反映(15:10) → **v1.2=家老指摘 code_mismatch 5件反映**。全ノードは現物grepの行番号。

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

  ADB2 -.->|"確定月は素通り"| LEDG["ledger guard = detect-only（c13a56fe）<br/>台帳値ではなく計算値を返す<br/>signal_decision_ledger = 0行"]:::skip

  ANOTE["<b>AsIsの帰結</b><br/>① cacheが3系統に分裂し、層の受渡しがDB経由（赤ノードが流れの途中にある）<br/>② 入力fingerprintが無く、確定月をskipする判断ができない<br/>③ 規則1/規則2の合成結果を保存する器はあるが、一致証明なしには使えない<br/>現物grep: opt6=6件 / fof_shared=4件 / payload_cache=2件<br/>signal_valid_dates_cache=0件 / validate_signal_snapshot=0件（T5/T6の削除は生存）"]:::rule
```

## ToBe **v3.0** — 2026-08-15T15:25+09:00

変更: v2.0=縦二本へ再構成+家老指摘反映 → **v3.0=左右二軸へ再構成（殿裁定15:20）。行=L、左列=cache、右列=計算。L単位で分離**

**左がcache、右が計算。同じ行が同じL。各Lの中で「計算→合流」と「cache→読み出し」が閉じる。cacheは左を縦に、計算は右を縦に流れる。**

```mermaid
flowchart TB
  classDef cache fill:#0b3d2e,stroke:#19a974,color:#ffffff,stroke-width:2px
  classDef skip fill:#3d2b0b,stroke:#f5a623,color:#ffffff
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef sink fill:#3d0b1e,stroke:#d94a6a,color:#ffffff
  classDef rule fill:#2a2a2a,stroke:#888888,color:#ffffff

  subgraph R0["run開始"]
    direction LR
    C0["<b>cache を1個だけ生成</b><br/>再生成・複製・空初期化は禁止<br/>identity は最後まで不変"]:::cache
  end

  subgraph R1["L1 入力層"]
    direction LR
    C1["+ 不変入力snapshot<br/>prices / DTB3 / config / ledger watermark"]:::cache
    X1["必要な銘柄と期間を<br/>一度だけ materialize"]:::calc
    X1 -.->|"合流"| C1
  end

  subgraph R11["L1.1 ticker解決層"]
    direction LR
    C11["+ 保有しうる ticker 集合"]:::cache
    X11["PF構成だけで解く<br/>standard PF を構成tickerへ分解<br/>保有しうる ticker を出す"]:::calc
    X11 -.->|"合流"| C11
  end

  subgraph R12["L1.2 深度解決層"]
    direction LR
    C12["+ depth 表 と 実行順序"]:::cache
    X12["PF構成だけで解く<br/>子・孫・ひ孫まで全経路を辿る（循環に耐える）<br/>depth(P)=1+max(depth(C_i))、standard は 0<br/><b>同一PFが複数世代に現れる。全経路の最大を採る</b>"]:::calc
    X12 -.->|"合流"| C12
  end

  subgraph R13["run identity"]
    direction LR
    C13["+ <b>run identity</b><br/>入力一式の同一性（run単位・O(1)）"]:::cache
    X13["入力一式から1回だけ導く"]:::calc
    X13 -.->|"合流"| C13
  end

  subgraph R2["L2 standard"]
    direction LR
    C2["+ standard の signals / W / monthly<br/>+ provenance / <b>PF×月の依存fingerprint</b>"]:::cache
    X2["<b>a 判定</b>　judge → 一致なら計算せず復元<br/>不一致なら momentum（日次close・months×21営業日・on-or-before）→ 判定 → <b>規則1</b> W=選定銘柄へ1.0<br/><b>b 価格適用</b>　W と価格から monthly / cumulative を導く<br/><b>c 記録</b>　provenance と依存fingerprint を作る"]:::calc
    C13 -.->|"読む"| X2
    X2 -.->|"合流"| C2
  end

  subgraph R3A["L3a leaf FoF（depth 1）"]
    direction LR
    C3A["+ leaf FoF の signals / W / monthly<br/>+ provenance / 依存fingerprint"]:::cache
    X3A["judge → momentum（入力=子standardの monthly cumulative_return・窓=月数の行差分）<br/>→ 判定 → <b>規則2</b> W=Σ w_i × W(C_i)<br/>→ 価格適用 → 記録"]:::calc
    C2 -.->|"読む"| X3A
    X3A -.->|"合流"| C3A
  end

  subgraph R3B["L3b nested FoF（depth 2→3→4 を浅い順に直列）"]
    direction LR
    C3B["+ nested FoF の同上<br/>depth 昇順に追記されていく"]:::cache
    X3B["<b>前提</b>: 全構成PFの W と monthly が cache に在ること<br/>欠けたら停止（DBへ取りに行かない・空dictで代替しない）<br/>混在深度は最も深い構成PFの確定を待つ。浅い子は cache 済みを使う<br/>judge → momentum → 判定 → <b>規則2</b>（同じ規則の再適用）→ 価格適用 → 記録"]:::calc
    C3A -.->|"読む"| X3B
    X3B -.->|"合流"| C3B
  end

  subgraph R5A["L5a 分析派生層"]
    direction LR
    C5A["+ drawdown / rolling / metrics / risk / trade_perf"]:::cache
    X5A["cache の確定値から導く<br/><b>導出だけ。判定へ戻さない</b>"]:::calc
    C3B -.->|"読む"| X5A
    X5A -.->|"合流"| C5A
  end

  subgraph R5B["L5b 表示投影・永続化層"]
    direction LR
    C5B["（cacheへの追記なし）"]:::cache
    X5B["cache から表示成果物を組み立てる<br/><b>DBを読まない</b>"]:::calc
    C5A -.->|"読む"| X5B
  end

  C0 --> C1 --> C11 --> C12 --> C13 --> C2 --> C3A --> C3B --> C5A --> C5B
  X1 --> X11 --> X12 --> X13 --> X2 --> X3A --> X3B --> X5A --> X5B

  X5B -.->|"書き切り（永続化はここだけ）"| DB[("DB")]:::sink
  DB x--x|"<b>禁止</b>：右列がDBを読み返す"| X2

  INV["<b>不変量</b><br/>① W の定義は 規則1 と 規則2 のみ<br/>② 控えを使うのは fingerprint 一致を示せた時だけ<br/>③ Σ W = 1.0 を各段で検算<br/>④ 確定した過去は 入力か規則が変わらない限り変わらない<br/>⑤ 深度は浅い順に直列<br/>⑥ 構成PFの深度は混在してよい（standard との同居を含む）<br/>⑦ 計算開始の前提は全構成PFが cache に在ること。欠けたら停止<br/>⑧ PF構成だけで解けるものは計算前の独立レイヤーで解く<br/>⑨ 全経路の最大を採る<br/>⑩ L1.1 と L1.2 は並列でよい<br/>⑪ 分析派生・表示投影・永続化は別責務。分析結果は判定へ戻さない<br/>⑫ <b>左=cache は縦に一本、右=計算は縦に一本。交わるのは各L内の合流と読み出しだけ</b><br/>⑬ run identity と PF×月の依存fingerprint は別物。混ぜない"]:::rule
```
