<!-- gist-master: 12cb3fc496e1ce991b1b70480a7b43ce dm-unified-tobe-flow_20260815.md -->
# DM-Signal 統合ToBeフロー（キャッシュ一本化 × provenance）

統合元: `dm-fullrecalculate-cache-reuse-asis_20260813` / `cmd_4296_momentum-window-recon_20260813` / `dm-decision-provenance-asis-tobe-5w1h_20260813` / `dm-weight-expansion-first-principles-asis-tobe_20260815`

## AsIs（確認日 2026-08-15 / 対象 `origin/main = 5da7f107`。全ノードは現物grepの行番号）

```mermaid
flowchart TB
  classDef bad fill:#3d0b1e,stroke:#d94a6a,color:#ffffff,stroke-width:2px
  classDef ok fill:#0b3d2e,stroke:#19a974,color:#ffffff
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef sink fill:#2a2a2a,stroke:#888888,color:#ffffff

  subgraph AL2["L2 standard（recalculate_fast.py）"]
    A1["日次ループ計算 → signals（メモリ）"]:::calc
    A1 --> A2["_flush_batch<br/>:2999 / :3020<br/>DBへ書込み"]:::bad
  end

  A2 --> ADB[("DB: signals")]:::sink

  ADB --> A3["<b>OPT-4: db.query(Signal)...all()</b><br/>:3170-3187<br/>全signalsをDBから再クエリ"]:::bad
  A3 --> A4["signal_cache_opt6 を空dictから再構築<br/>:3202-3206<br/><b>= cache系統①</b>"]:::bad

  subgraph AL3["L3 FoF（recalculate_fof.py / recalculate_fast.py）"]
    A5["fof_shared_signal_cache = {}<br/>:3197 空dictから開始<br/><b>= cache系統②</b>"]:::bad
    A4 --> A6["Phase 4.5 monthly_returns 生成<br/>signal_cache=opt6 を引数供給<br/>:3228 / :3299"]:::calc
    A5 --> A6
    A6 --> A7["_reload_signal_cache_entries<br/>:3291<br/>DBから再ロード"]:::bad
    A7 --> A8["FoF deferred flush"]:::bad
  end

  A8 --> ADB2[("DB: signals / monthly_returns")]:::sink

  subgraph AL5["L5 precompute（precompute_raw.py）"]
    ADB2 --> A9["signal_preload（DBロード）"]:::bad
    A9 --> A10["<b>LazySignalArtifactCache を L5内で新規生成</b><br/>:245<br/>L2/L3からの受渡しではない"]:::bad
    A10 --> A11["artifact_signal_cache として builder へ供給<br/>:246 / :281<br/><b>この供給自体はT4の成果で残存</b>"]:::ok
    A11 --> A12["MonthlyTradeCalculator.calculate<br/>:321"]:::calc
    A12 --> A13["precompute_signal_payload_cache 経路<br/>price_ratio_impl.py:1116-1120<br/><b>= cache系統③</b>"]:::bad
  end

  A2 -.-> ALERT["<b>SIGNAL CHANGE ALERT / signal_change_log</b><br/>signal_flush.py:431 / :565<br/>2026-08-12に撤去裁定 → 08-13 rollback 233c2303 で復活し現存"]:::bad

  NOTE["<b>確認できた残存/消失（現物grep）</b><br/>残存: signal_cache_opt6=6件 / fof_shared_signal_cache=4件 / precompute_signal_payload_cache=2件<br/>消失(T5/T6の成果が生存): signal_valid_dates_cache=0件 / validate_signal_snapshot=0件<br/>ledger guard は detect-only（c13a56fe。台帳値ではなく計算値を返す）<br/>signal_decision_ledger = 0行"]:::sink
```

## ToBe

```mermaid
flowchart TB
  classDef cache fill:#0b3d2e,stroke:#19a974,color:#ffffff,stroke-width:2px
  classDef skip fill:#3d2b0b,stroke:#f5a623,color:#ffffff
  classDef calc fill:#12233d,stroke:#4a90d9,color:#ffffff
  classDef sink fill:#3d0b1e,stroke:#d94a6a,color:#ffffff
  classDef rule fill:#2a2a2a,stroke:#888888,color:#ffffff

  subgraph L1["L1 入力層 — run冒頭に一度だけ materialize"]
    PR[("prices")] --> SNAP
    EC[("economic / DTB3")] --> SNAP
    CF[("PF config")] --> SNAP
    LG[("ledger watermark")] --> SNAP
    SNAP["<b>唯一のcache object</b><br/>不変入力snapshot<br/>+ 用途別view（DTB3完全prefix / signal bounded）"]:::cache
  end

  SNAP --> FPG["<b>入力fingerprint</b>（run単位で1回生成 O(1)）<br/>prices区間hash + config hash + source identity<br/>+ ledger watermark + rebalance trigger + DTB3系列hash"]:::cache

  subgraph L2["L2 standard 24PF"]
    FPG --> Q2{"確定月 かつ<br/>保存fingerprint == 現fingerprint ?"}
    Q2 -- "一致（skip）" --> S2["保存済み判定 と W を cache へ復元<br/><b>計算しない</b>"]:::skip
    Q2 -- "不一致 / 未確定月" --> M2["momentum<br/>入力=日次 close<br/>窓=months × 21営業日<br/>target非取引日は on-or-before"]:::calc
    M2 --> D2["判定 → holding"]:::calc
    D2 --> W2["<b>規則1</b>　W(P,d) = 選定銘柄 → 1.0"]:::rule
    S2 --> W2
  end

  W2 --> CACHE2["cache object へ追記<br/>signals / W / provenance / fingerprint<br/><b>同一オブジェクト・identity不変</b>"]:::cache

  subgraph L3["L3 FoF 78PF — leaf → nested の依存順（深度で定義は不変）"]
    CACHE2 --> Q3{"確定月 かつ<br/>保存fingerprint == 現fingerprint ?<br/>（子のfingerprintを構成要素に含む）"}
    Q3 -- "一致（skip）" --> S3["保存済み判定 と W を cache へ復元<br/><b>計算しない</b>"]:::skip
    Q3 -- "不一致 / 未確定月" --> M3["momentum<br/>入力=子PFの monthly cumulative_return<br/>（close=cumulative_return, open=cumulative_return_open）<br/>窓=月数の行差分"]:::calc
    M3 --> D3["判定 → 構成PFと目標比率 w_i"]:::calc
    D3 --> W3["<b>規則2</b>　W(P,d) = Σ w_i × W(C_i,d)<br/>右辺は同じ関数の再帰<br/>終端は必ず規則1"]:::rule
    S3 --> W3
  end

  W3 --> CACHE3["cache object へ追記<br/>FoF signals / W / monthly / provenance<br/><b>同一オブジェクト・identity不変</b>"]:::cache

  subgraph L5["L5 表示・成果物層"]
    CACHE3 --> B5["builder / precomputed_raw / trade_perf<br/><b>引数で cache を受け取る</b>"]:::calc
    B5 --> OUT["表示成果物"]:::calc
  end

  CACHE3 -.->|"永続化のみ（書き切り）"| DB[("DB<br/>signals / monthly_returns<br/>portfolio_metrics / provenance")]:::sink
  OUT -.->|"永続化のみ（書き切り）"| DB

  DB x--x|"<b>禁止</b>：下流が書いた値を読み返す<br/>（flush→再読込・再構築）"| L3

  INV["<b>不変量</b><br/>① W(P,d) の定義は 規則1 と 規則2 のみ<br/>② 保存値は控え。使うのは fingerprint 一致を示せた時だけ<br/>③ Σ W = 1.0 を各段で検算<br/>④ 確定した過去は 入力か規則が変わらない限り変わらない"]:::rule
```
