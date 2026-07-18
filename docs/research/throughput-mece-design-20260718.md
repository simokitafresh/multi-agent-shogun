# 品質合格スループット根治 — AsIs/ToBe 5W1H設計書

作成: 将軍(覚醒統合) 2026-07-18 14:38 | 更新: 将軍 2026-07-18 19:40 | version: **v2.2**(概算先行+待ちゼロ — 殿の求める型)

### v2.2変更点（殿指示2026-07-18 19:34「CI GREENを待たずに概算でE2Eをやらせよう。あまりにも遅い」+ 19:37「待つ間に全速で出来ることをやらせろ」）
1. **概算先行原則**: 確定数値(CI GREEN+同一cohort)を待たず、現行HEADで概算E2Eを即計測し品質注記(dirty HEAD/CI未GREEN)付きで先に殿へ届ける。概算=v2.1途中試行(1行ログ級)。確定=最終checkpoint 1回。**概算の即報 > 確定の遅報**
2. **最終checkpointをCIの人質にしない**: CI(8分+のsuite×修正往復)は確定の必要条件だが、計測・判定・commit・準備は全てCI非依存で前倒しする。pushのみGREEN後
3. **待ちゼロ原則**: 待ち(CI/レビュー/裁可)が発生した瞬間、idle忍者へ独立laneを即配備する。待ちの合理性テストは「その待ちの間、全員が動いているか」まで含めて判定する。idle=最大の無駄(殿原則)
4. **第一報SLA**: 殿へ届ける第一報は30分以内。完全な報告より速い概算報告
5. **遅い=バグ原則**（殿裁定19:38「遅いのはバグだ。バグは修正せよ」）: 遅さは環境条件でも仕様でもなくバグとして扱う。検知(受動計測)→起票(台帳)→修正(wave)→検証(checkpoint)のバグ修正フローに乗せる。「遅いが動く」を放置=バグ放置
6. **超速自動サイクルの確立**（殿指示19:39「品質向上と速度向上を超速サイクルで回し続ける自動成長と自動改善の仕組みを確立させよ」）: 本設計の終着点は人手run本数ではなく、**計測→選定→配備→checkpoint→再順位付けが人手ゼロで回る閉ループ**。実装部品は全て存在する — B0受動writer(通常業務ログ)+campaign-lane(選定/record/停止判定)+idle自動配備(ninja_monitor)+最終checkpoint gate。§8.2にループ接続契約を定義する

**§8.2 自動成長閉ループ接続契約(v2.2)**
```text
通常業務 → 受動writer(wall_ms+identity) → 台帳(JSONL)
   ↑                                        ↓
最終checkpoint gate ← idle自動配備 ← campaign-lane select(blocked-agent-seconds順)
```
- 人が介在する点は2つだけ: (a)本番接触・不可逆操作の裁可 (b)wave最終checkpointの品質確認(家老)
- 選定・配備・記録・再順位付けは全てスクリプト。家老の1行ログ即決すら不要になった時点で「確立」と呼ぶ
- 品質側の自動輪: FAIL/FP/WA発生→lesson_candidate→gate/hook反映(成長ループ既存)と速度側の輪を同一台帳で回す

### v2.1変更点（殿指摘2026-07-18 17:46「確認が多すぎて高速回転ができていない。本末転倒」）
原理: **厳密さは最終チェックのみ**(殿厳命2026-07-14)。途中try=1行ログのみ、厳密点は①wave最終checkpoint 1回②本番接触のみ。縛りの散布=反ラルフループ。
1. **B0専用計測儀式を廃止**: 計測は既存ログ(deploy_task.log/gate_metrics.log/terminal ledger/scope receipt)からの**受動収集**のみ。計測のために配備を止めない。N≥10は「集めに行く」のではなく自然蓄積の発火閾値
2. **軍師第三者確認を非同期化**: 配備BLOCK条件から除外。家老は選定を1行ログで即決し配備を開始、軍師は事後確認して異議があれば次waveで補正。同期待ち=blocked_with_workの自作
3. **wave内の途中試行は無儀式**: 契約・報告YAML・レビュー・binary check・再承認なし。1行ログのみ。厳密判定(E2E二重PASS+品質不変量)はwave最終checkpoint 1回に集約
4. **完了後段のbatch化徹底**: レビュー/ACCEPT/GATE/retroは配備を優先した上でbatch処理。レビュー待ちで次配備を止めることを禁止
5. **§8を8ステップ→4ステップへ圧縮**: 選定(1行ログ)→集中配備→最終checkpoint→再順位付け
家老敵対監査: `docs/research/infra-throughput-outcome-design-20260718.md` (C1-C6, 26件台帳)
軍師独立レビュー: blt_20260718_123619(3指摘: MECE穴1/目標値根拠不在2/攻略順序反証1)
将軍v2.0レビュー: **APPROVE** blt_20260718_165958_8addbb（reviewed SHA `afd01015...b224`。WARN2点を本版へ反映）

### v2.0変更点（殿の目的再整合）
1. **カテゴリ先決めを廃止**: C1固定ではなく、同一cohort E2Eの`blocked_agent_seconds = Σ(phase wall × 前進不能agent数)`最大区間を毎waveで1つ選ぶ
2. **異なる領域への同時配備を禁止**: 忍者並列化はselected bottleneck内の再現・根因・独立実装・敵対検証だけに使う
3. **局所PASSを全体PASSから分離**: E2E p95 20%以上短縮かつ品質合格成果/時1.20倍を満たさなければ未達
4. **改善後の再順位付けを必須化**: 最大律速を改善するたび全phaseを再計測し、次の律速へ移る
5. **leading candidateを仮説扱い**: test runner lifecycleは38分任務中約26分を支配したが、B0のN≥10計測前には確定しない

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
> 「スループットの改善をするためにはもっとも遅い部分を改善しないと効果が出ない」(16:40)

殿の評価式: **自動成長速度 = 正しい試行回数 × 一発PASS率 × 知見還流率**
横断不変量: FAIL=0 / SKIP=0 / FP=0 / FN=0 / duplicate=0 / 通知喪失=0 / 安全境界低下=0

## §1 Why — なぜ今これが必要か

**品質と速度は一体**(殿原則2026-07-08)。サイクルが速い→反復が増える→学習が増える→品質が上がる→手戻りが減ってさらに速くなる。

今日の実態: 15件以上のhotfixを個別投入したが、全体のスループットが改善したか計測不能。各hotfixはPASS/FAILだが「何のために」「いくら改善したか」の目的とアウトカムが未定義。モグラ叩きは速度を上げず、CTXを消費する。

なぜなぜ: 個別バグ→個別hotfix→PASS→次のバグ→... このループに「全体目標との距離」の計器がない → 近視眼化 → 同じ根因の別症状を何度も修正 → 正しい試行回数が増えない。

## §2 What — 何を達成するか

**品質を維持・向上しながらスループット速度を上げ、自動成長速度を加速する。**

具体的には: cmd input→task→execution→report→gate→doneの全体パイプラインwall timeを短縮し、同じ壁時計時間内の正しい試行回数を増やす。品質(一発PASS率)と知見還流率は維持または向上。

主目的関数は **品質合格成果数 / 壁時計時間**。選定指標は `blocked_agent_seconds = Σ(phase_wall_seconds × そのphaseで前進不能なagent数)` とし、最大の1区間だけを次waveへ選ぶ。局所scriptのp95改善は副指標であり、同一cohortのE2E p95と品質合格成果/時が改善しなければ全体PASSにしない。

## §3 AsIs — 2026-07-18の実測が示す構造

### 全体パイプライン実測

| 区間 | 実測値 | 含意 |
|------|--------|------|
| deploy(配備) | baseline N20 p50=41.026s / p95=234.965s。直近live 99.340s・118s・129.143s | after同一cohort N不足。p50<30s未達 |
| git commit | fixture N5 p50=9.974→1.940s / p95=14.384→2.120s。一方、実repo total=135.755s・lock待ち37.711s | fixture改善をlive改善とみなせない |
| report publication | N10 p95=4.298→0.500s、43/43 PASS、SKIP0 | 8.60倍の局所改善。ただしlive deploy全体99-129sの律速ではない |
| test runner lifecycle | report publication任務約38分中、recursive PATH mockによるBats child残存・誤再走が約26分 | 現在のleading bottleneck仮説。N≥10 E2E計測前は未確定 |
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
| 品質合格成果/時 | 直近wave瞬間値13.1件/時、同一定義beforeなし | **同一cohort before比>1.20倍** | 本設計の主目的関数 |
| E2E input→quality terminal p95 | phase別値のみ、統一cohort未計測 | **waveごと20%以上短縮** | 最遅区間改善が全体へ効いたことを証明 |
| selected phase critical share | 未計測 | **blocked-agent-seconds比20%以上減少** | 律速解消を直接測定 |
| deploy p50/p95 | p50=31.5s / p95=235.0s (N=20) | **p50<30s / p95<60s** | 正しい試行回数↑(配備待ち解消) |
| commit p50/p95 | p50≈82s / p95≈150s (N=1台帳値、要N≧5再計測) | **p50<10s / p95<20s** | 正しい試行回数↑(commit待ち解消) |
| report→GATE p95 | 133-212s (N=2台帳値、要N≧5再計測) | **p95<60s** | 正しい試行回数↑(確定待ち解消) |
| AUTO_DONE p95 | 679s (N=1台帳値) | **p95<5s** | 正しい試行回数↑(完了遷移即時化) |
| prompt replay/wrong-pane | 60回/session (lord_conversation grep計測済み) | **0回** | 正しい試行回数↑(殿の時間回復) |
| 将軍CTX制御面消費率 | 86% (LS094 session分析計測済み) | **<20%** | 正しい試行回数↑(将軍の戦略時間回復) |
| promotion在庫 | 198-200件停滞 (家老台帳計測済み) | **週次消化>50%** | 知見還流率↑ |
| FAIL/SKIP/FP/FN | 発生あり | **全0** | 一発PASS率維持 |
| duplicate/通知喪失 | 発生あり | **全0** | 一発PASS率維持 |

ToBe達成時の自動成長速度は、局所倍率の積ではなく同一cohortの品質合格成果/時で確定する。deploy+commit+GATEの理論合算から「3-5倍」と先に宣言せず、実測before/afterだけを採用する。

## §5 Who — 誰が

| 役割 | 責任 |
|------|------|
| 殿 | 目的定義・方向裁定・ext4 probe等の安全判断 |
| 将軍 | 設計書管理・アウトカム計測・Wave進捗の殿への報告 |
| 家老 | Wave分解・忍者配備・GATE判定・before/after計測実行 |
| 軍師 | 設計レビュー・品質不変量の第三者検証 |
| 忍者 | 実装・テスト・報告 |

## §6 When — いつ・どの順序で

カテゴリ名や実装容易性でWave順を固定しない。通常業務の同一cohort N≥10を計測し、blocked-agent-seconds最大の1区間だけを選ぶ。

| Wave | 対象 | 選定条件 | 完了条件 | 現在状態 |
|------|---------|------|---------|-----------------|
| **B0(NOW)** | 全phase受動計測 | 既存ログから自然蓄積N≥10で発火(専用計測儀式なし・配備は止めない)。仕事なしidleはblockedから除外 | 最大blocked-agent-secondsを家老が1行ログで即決選定(軍師確認は非同期事後) | 未計測。test runner lifecycleは仮説のみ |
| **B1** | selected bottleneck 1区間 | B0 1位のみ。2位以下の実装0 | 局所critical share-20%以上 + E2E p95-20%以上 + 品質合格成果/時>1.20倍 |
| **B2** | 次の律速 | B1後に全phase再順位付け | 同じ契約を反復 | 未開始 |

2026-07-18 14:35のC1集中は履歴として保持するが、16:40の目的再確認により固定Waveではなくなった。C1成果は棄却せず台帳へ残し、B0で最大なら継続、最大でなければ次候補へ戻す。複数忍者は異なるカテゴリへ散らさず、selected bottleneck内の再現・根因・独立実装・敵対検証へ分業する。

## §7 Where — どこで

| 対象 | パス |
|------|------|
| 設計書(本書) | `docs/research/throughput-mece-design-20260718.md` |
| 家老台帳(26件) | `docs/research/infra-throughput-outcome-design-20260718.md` |
| gist | 94145c4564055baa3f543028a69e948b |
| 計測ログ | `logs/deploy_task.log`, scope receipt, `logs/gate_metrics.log` |
| before/after記録 | 各Wave完了時に本書§9へ追記 |

## §8 How — どうやって

各Wave内の手順(v2.1: 4ステップ。途中は1行ログのみ、厳密さは最終checkpoint 1回に集約):
1. **選定(1行ログ)**: 既存ログの自然蓄積(同一SHA・環境・同種cmd構成、N≥10到達で発火)からblocked-agent-seconds最大の1区間を家老が即決。`idle_no_work`は別集計、`blocked_with_work`のみ算入。2位以下は台帳保持。軍師確認は非同期事後(異議は次waveで補正)。選定のために配備を止めない
2. **集中配備(無儀式)**: 同一区間内だけを再現・根因・独立実装・敵対検証へ分割。別カテゴリ混入0。途中試行に契約・報告YAML・レビュー・再承認なし、1行ログだけで軽快に回す。障害は直して即再実行
3. **最終checkpoint(厳密さはここだけ)**: 対象/full test FAIL0・SKIP0・fixed SHA CI GREEN + 同一cohort E2E after計測 — E2E p95-20%以上かつ品質合格成果/時>1.20倍。未達は`local_pass_e2e_unproven`と記録(偽PASS禁止)
4. **再順位付け+記録**: 全phase再集計→次の律速へ。本書§9にbefore/after/delta/PASSを追記(整形はこの1回だけ)

**§8.1 忍者作業完了後の遅延原因分析 — 分離原則(殿裁定2026-07-18 14:56)**

メインtask完了後に**別途**振り返りを実施する。メインtaskに混ぜない(分離原則: 同時に全部やらせるのは原理原則に反する)。

殿のプロンプト(原文):
> **「この作業で時間がかかった原因を分析し、利他の精神で調査を行いインフラバグの疑いとして家老に報告せよ」**

| フェーズ | 内容 | 速度 |
|---------|------|------|
| メインtask | 純粋な実装・テスト・報告。遅延分析は含めない | 高速高回転 |
| 振り返り(別途) | 上記プロンプトを忍者paneに入力。一次体験が鮮明な直後に実施 | メイン完了後 |

実装:
- **トリガー**: report_received時は`queue/retro/pending.yaml`へeventだけを保存する。即時の忍者inbox送信はtask開始nudgeへ埋没し、トークンとCTXを浪費したためcommit `5180b6fa...`で無効化済み
- **収集(家老案A採用)**: `queue/retro/`にappend-only蓄積。家老nudgeは送らない(逐次反応を構造的に防止)。batch_readyは「未処理6件」or「最古30分」or「C1最終checkpoint直前」の最初の境界で1回だけ生成。event_id/parent_report_idでexactly-once dedup。家老はbatch 1件としてMECE分類→既存issueへmerge→新規issueのみ台帳追記。即時割込み例外はdata loss/security/CI RED/destructive safetyの4種のみ
- **ACやreport templateには混ぜない**(分離原則)
- C1のbaseline計測(§8 Step 1)のN≧5サンプルもこの経路で自動蓄積される

横断品質保証: 全Waveを通じてFAIL=0/SKIP=0/FP=0/FN=0/duplicate=0/通知喪失=0/安全境界低下=0。速度目標だけでPASSにしない。

## §9 計測記録(Wave完了時に追記)

2026-07-18 B0受動選定: 自然蓄積N>=10を満たす候補はdeploy wall（N=20、p50=41.026s、p95=234.965s）のみで現時点の最大blocked-agent-seconds区間として一意選定。test runner lifecycleはN=1のため自然蓄積待ち、2位以下の実装0。

| Wave | 指標 | before(p50/p95, N) | after(p50/p95, N) | delta | PASS |
|------|------|-------------------|------------------|-------|------|
| C1履歴 | deploy wall | p50=41.026s / p95=234.965s (N=20) | live直近99.340s・118s・129.143s（N=3、比較禁止） | after N不足 | **未証明** |
| C1履歴 | commit fixture | p50=9.974s / p95=14.384s (N=5) | p50=1.940s / p95=2.120s (N=5) | **-80.5% / -85.3%** | **局所PASS**。実repo total135.755sのためE2E未証明 |
| C1履歴 | report publication | p95=4.298s (N=10) | p95=0.500s (N=10) | **-88.4%、8.60倍** | **局所PASS**。43/43、SKIP0 |
| C1履歴 | context freshness | consumer同期git2、legacy採用1 | consumer同期git0、legacy0 | full54/54、N10 10/10 | **PASS**、FP0/FN0、L1203 |
| B0候補 | test runner lifecycle | 任務38分中runaway/誤再走約26分 | — | blocked share約68%の単発仮説 | **N≥10未計測** |
| 全体 | 品質合格成果/時 | 同一定義beforeなし | 直近18分17秒で4件=13.1件/時 | 比較不能 | **未証明** |

## §10 現在状態(2026-07-18 16:55時点)

v1.2のC1固定waveは停止し、v2.0のB0選定へ移行する。既存成果は局所証拠として保持するが、全体改善倍率へ昇格させない。

- report publication `8be72a42...`: p95 4.298→0.500s、43/43 PASS、SKIP0
- context freshness GA-291 `6c48437c...`: consumer git2→0、legacy1→0、54/54 + N10、FP0/FN0
- terminal ledger `2e80018d...`: 49/49 + N10、SKIP0
- ext4 history snapshot `560acc8d...`: 53/53、SKIP0
- atomic receipt `108451a3...`: 26/26 + focused7/7、TAP再走2→0
- Linux CI harness `3d7a362a...`: focused3/3 + runner3/3、required CI GREEN確認待ち

次の行動は実装配備ではなく、B0の同一cohort N≥10計測とselected bottleneckの軍師確認である。

## §11 v2.0レビュー依頼

結果: **APPROVE**。将軍は正しいGist SHA `afd01015...b224`を精読し、B0開始を承認した。指摘2点（idle_no_workとblocked_with_workの分離、before/after cohortの同種cmd構成一致）を§6・§8へ反映済み。

将軍確認事項:

1. blocked-agent-secondsが全体を最も止める区間の主指標として妥当か。
2. C1固定を解除し、毎waveで最大1区間へ集中する方針が殿の目的に一致するか。
3. E2E p95-20%以上 + 品質合格成果/時1.20倍が局所偽PASSを十分排除するか。
4. test runner lifecycleをleading candidateとしつつB0前に確定しない境界が適切か。
5. B0後の軍師第三者確認と、改善後の全phase再順位付けに穴がないか。

---

origin: [[殿指示_MECE_throughput_design]] -> [[最遅区間を改善しないと効果が出ない]] -> [[blocked_agent_seconds最大1区間集中]] -> [[AsIs/ToBe_5W1H_品質合格スループット根治_v2]]
