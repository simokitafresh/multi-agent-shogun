# 品質合格スループット根治 — AsIs/ToBe 5W1H設計書

作成: 将軍(覚醒統合) 2026-07-18 13:10 | version: **v1.1**(軍師レビュー統合+覚醒アップデート)
家老敵対監査: `docs/research/infra-throughput-outcome-design-20260718.md` (C1-C6, 26件台帳)
軍師独立レビュー: blt_20260718_123619(3指摘: MECE穴1/目標値根拠不在2/攻略順序反証1)

### v1.1変更点(覚醒アップデート — 家老+軍師を超える)
1. **MECE穴修正**: monitor逐次loop構造をC4-07から独立させC4サブカテゴリ「C4b: monitor loop fairness」に昇格。根拠: done認識15m09s遅延はtransaction正確性(C4)の一部だが、逐次loop構造は他C4件と修正手段が異なる(ninja_monitor.shのループ公平化)。家老台帳C4-07と紐付け
2. **baseline計測義務化**: §8 HowのStep 1を「Wave開始"前"にN≧5 baseline計測必須。before値なしにWave開始禁止」に強化。軍師指摘(C4/C5 before値不在)の根治。家老のn=1単発値も将軍の(要計測)もbaselineとして不十分
3. **Wave順序最適化**: Wave 1(C4)とWave 2(C1 ext4 probe)の間にWave 1.5(C2 prompt replay)を挿入。根拠: ext4 probeは殿の明示許可が必要(家老報告blt_111806)で待ちが発生する。その待ち時間にC2(殿の時間を直接奪うバグ)を並行処理。待ちの合理性テスト(LS-A08(8)): ext4許可待ちは殿の判断を買う正当な待ち。C2はその間に処理可能な独立カテゴリ
4. **覚醒なぜなぜ(家老を超える点)**: 家老の分類規則「最初に破れた不変量をprimary」は正しいが、**不変量自体の定義が暗黙**。§2に各カテゴリの不変量を明示追記(例: C1=「git操作p95<Ns」、C4=「transaction exactly-once+atomic」)。不変量が明示されていなければ「破れた」の判定が属人的になる
5. **覚醒なぜなぜ(軍師を超える点)**: 軍師の評価式マッピング(試行回数=C1+C3、PASS率=C4+C2、還流率=C5)は静的。**各Waveの完了が他要素にも波及する動的効果**を追記(例: C4修正→AUTO_DONE短縮→試行回数↑+PASS率↑の両方に寄与)
gist: 94145c4564055baa3f543028a69e948b

## §0 発端 — 殿の言葉

> 「家老が全体のスループット向上に取り組んでいるが、いつのまにか近視眼的な対応をしているように思える」(12:25)
> 「忍者から大量のインフラバグ疑いが届いているはずだ。それをMECEにまとめ、ジャンルごとに集中して解決していくやり方がよい。今のやり方にはアウトカムがないので測定もできていないのでは？」(12:28)
> 「すべては品質を向上させながらスループット速度向上のためだ。目的にフォーカスしよう」(12:36)

殿の評価式: **自動成長速度 = 正しい試行回数 × 一発PASS率 × 知見還流率**
横断不変量: FAIL=0 / SKIP=0 / FP=0 / FN=0 / duplicate=0 / 通知喪失=0 / 安全境界低下=0

## §1 Why — なぜ今これが必要か

**品質と速度は一体**(殿原則2026-07-08)。サイクルが速い→反復が増える→学習が増える→品質が上がる→手戻りが減ってさらに速くなる。

今日の実態: 15件以上のhotfixを個別投入したが、全体のスループットが改善したか計測不能。各hotfixはPASS/FAILだが「何のために」「いくら改善したか」の目的とアウトカムが未定義。モグラ叩きは速度を上げず、CTXを消費する。

なぜなぜ: 個別バグ→個別hotfix→PASS→次のバグ→... このループに「全体目標との距離」の計器がない → 近視眼化 → 同じ根因の別症状を何度も修正 → 正しい試行回数が増えない。

## §2 What — 何を達成するか

**品質を維持・向上しながらスループット速度を上げ、自動成長速度を加速する。**

具体的には: cmd input→task→execution→report→gate→doneの全体パイプラインwall timeを短縮し、同じ壁時計時間内の正しい試行回数を増やす。品質(一発PASS率)と知見還流率は維持または向上。

## §3 AsIs — 2026-07-18の実測が示す構造

### 全体パイプライン実測

| 区間 | 実測値 | 含意 |
|------|--------|------|
| deploy(配備) | 74-305s (p50未計測) | 9P I/Oが支配。忍者が手をつける前に5分待つ |
| git commit | 82-150s (pre-hook前73s) | 1925 tracked files全lstat。D-state 41-63s |
| report→GATE | 133-212s | 固定費。忍者完了から成果確定まで3分 |
| AUTO_DONE | 679s | PASS→完了まで11分。即時ではない |
| 将軍CTX | 86%制御面消費 | 5h20m/6h09m。戦略的作業に到達不能 |
| prompt replay | 60回以上/session | 殿の時間を直接奪う |
| promotion在庫 | 176-199停滞 | 知見還流率が低い |

### 根因MECE 6分類(家老敵対監査済み)

分類規則: **最初に破れた不変量をprimary category**。下流影響はtagに留め二重計上しない。

| ID | カテゴリ | 境界 | 件数(修/部/未) |
|----|---------|------|---------------|
| C1 | Storage/worktree substrate | 9P, Git metadata, index, worktree | 5 (1/3/1) |
| C2 | Lord input identity/routing | prompt生成, turn identity, exactly-once配信 | 2 (1/0/1) |
| C3 | Internal event transport | event dedup, priority, outbox, hook | 2 (2/0/0) |
| C4 | Cmd/task/report lifecycle transaction | deploy, task mutation, report, gate, AUTO_DONE | 9 (4/0/5) |
| C5 | Knowledge reflux lifecycle | lesson/insight/promotion予約・昇格・消化 | 6 (1/1/4) |
| C6 | Verification/readiness semantics | target/global判定, fixture安全 | 2 (0/0/2) |
| **計** | | | **26 (9/4/13)** |

全件台帳(ID・状態・一次値): → `docs/research/infra-throughput-outcome-design-20260718.md` §3

## §4 ToBe — 達成後の世界

| 指標 | AsIs | ToBe | 自動成長速度への寄与 |
|------|------|------|-------------------|
| deploy p50 | 74-305s | **<30s** | 正しい試行回数↑(配備待ち解消) |
| commit p50 | 82-150s | **<10s** | 正しい試行回数↑(commit待ち解消) |
| report→GATE p95 | 133-212s | **<60s** | 正しい試行回数↑(確定待ち解消) |
| AUTO_DONE p95 | 679s | **<5s** | 正しい試行回数↑(完了遷移即時化) |
| prompt replay/wrong-pane | 60回/session | **0回** | 正しい試行回数↑(殿の時間回復) |
| 将軍CTX制御面消費率 | 86% | **<20%** | 正しい試行回数↑(将軍の戦略時間回復) |
| promotion週次消化率 | 未計測(停滞) | **>50%/週** | 知見還流率↑ |
| FAIL/SKIP/FP/FN | 発生あり | **全0** | 一発PASS率維持 |
| duplicate/通知喪失 | 発生あり | **全0** | 一発PASS率維持 |

ToBe達成時の自動成長速度: 同じ壁時計時間で試行回数3-5倍(deploy+commit+GATE短縮)、PASS率維持、還流率2倍(promotion消化)。**複利効果で指数関数的加速**。

## §5 Who — 誰が

| 役割 | 責任 |
|------|------|
| 殿 | 目的定義・方向裁定・ext4 probe等の安全判断 |
| 将軍 | 設計書管理・アウトカム計測・Wave進捗の殿への報告 |
| 家老 | Wave分解・忍者配備・GATE判定・before/after計測実行 |
| 軍師 | 設計レビュー・品質不変量の第三者検証 |
| 忍者 | 実装・テスト・報告 |

## §6 When — いつ・どの順序で

カテゴリを混ぜず、各WaveのToBe指標が満たされてから次へ進む。

| Wave | カテゴリ | 理由 | ToBe指標 |
|------|---------|------|---------|
| **1** | C4 transaction (+C4b monitor loop) | 機能正確性なしにspeed計測は無意味。session喪失・再入破損が残るとbefore/after比較が信頼不能。C4b: monitor逐次loop公平化(done認識15m→即時) | identity100%, 破損0, AUTO_DONE<5s, child repair100%, report→gate<60s, monitor done検知<30s |
| **1.5** | C2 prompt replay | ext4 probe殿許可待ちの間に並行処理。殿の時間を直接奪うバグ | replay0, wrong-pane0, 外部追加入力0 |
| **2** | C1 substrate | 最大ボトルネック。deploy/commitの9P根治。ext4隔離probeで方式選定→移設(殿許可後) | deploy p50<30s, commit p50<10s, scope逸脱0, stale registry 0 |
| **3** | C5 reflux | foreign dirty収束→一括昇格。知見還流率の直接改善 | duplicate0, reservation conflict0, 週次消化>50% |
| **4** | C6 semantics | target/global型分離。CI判定の信頼性 | conflation0, fixture破壊0 |
| **5** | C3 event transport | C4/C1/C2修正で間接改善される分を差し引いた残件 | CTX<20%, delivery p95<5s |

Wave順序の根拠(将軍覚醒分析v1.1):
- 家老案(C4先行)を採用。transaction正確性なしに速度計測は不可能(壊れた計測→偽改善→洗脳#2)
- **Wave 1.5追加(軍師反証の超越)**: 軍師はC2をext4許可待ち中に処理と提案。将軍判断: Wave 1完了→ext4 probe殿許可申請→許可待ち中にC2並行=待ち時間の有効活用。LS-A08(8)の待ちの合理性テスト: ext4許可は殿の判断を買う正当な待ち
- C3を最後にした理由: C4(AUTO_DONE即時化)+C1(9P解消)+C2(replay解消)がC3のCTX消費を間接改善。Wave動的効果を差し引いた残件のみ

## §7 Where — どこで

| 対象 | パス |
|------|------|
| 設計書(本書) | `docs/research/throughput-mece-design-20260718.md` |
| 家老台帳(26件) | `docs/research/infra-throughput-outcome-design-20260718.md` |
| gist | 94145c4564055baa3f543028a69e948b |
| 計測ログ | `logs/deploy_task.log`, scope receipt, `logs/gate_metrics.log` |
| before/after記録 | 各Wave完了時に本書§9へ追記 |

## §8 How — どうやって

各Wave内の手順:
1. **baseline計測**(N≧5でp50/p95。n=1の単発値をbaselineにしない。**before値なしにWave開始禁止**)
2. **忍者配備**(カテゴリ内の未修正件に集中。他カテゴリに手を出さない)
3. **修正→テスト→GATE**(途中は可逆試行回数最大化、最終checkpointでのみ全契約)
4. **after計測**(同一条件でN≧5)
5. **ToBe指標との比較**(未達なら追加修正、達成なら次Waveへ)
6. **本書§9に記録**(Wave, before p50/p95, after p50/p95, delta, PASS/FAIL)

横断品質保証: 全Waveを通じてFAIL=0/SKIP=0/FP=0/FN=0/duplicate=0/通知喪失=0/安全境界低下=0。速度目標だけでPASSにしない。

## §9 計測記録(Wave完了時に追記)

| Wave | 指標 | before(p50/p95, N) | after(p50/p95, N) | delta | PASS |
|------|------|-------------------|------------------|-------|------|
| | | | | | |

## §10 凍結状態(2026-07-18 12:30時点)

家老が新規実装・追加配備を停止。進行中成果:
- `3d4d670f`: 軍師LGTM, 26/26 PASS, main未統合(C5-04)
- `eb378791f`: 41/41, GATE CLEAR, 完了処理済み(C4-03)
- L901 4回目配備: 即時停止(C5-04)
- 設計再開時はWave 1(C4)から開始し、個別hotfixを先行させない

---

origin: [[殿指示_MECE_throughput_design]] -> [[近視眼的hotfix]] -> [[AsIs/ToBe_5W1H_品質合格スループット根治]]
