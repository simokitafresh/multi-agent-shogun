<!-- gist-master: 12cb3fc496e1ce991b1b70480a7b43ce dm-unified-tobe-flow_20260815.md -->
# DM-Signal 統合ToBeフロー（キャッシュ一本化 × provenance）

統合元: `dm-fullrecalculate-cache-reuse-asis_20260813` / `cmd_4296_momentum-window-recon_20260813` / `dm-decision-provenance-asis-tobe-5w1h_20260813` / `dm-weight-expansion-first-principles-asis-tobe_20260815`

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
