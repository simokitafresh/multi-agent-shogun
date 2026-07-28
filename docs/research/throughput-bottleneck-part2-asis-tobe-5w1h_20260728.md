# 【📐P2-P4 AC1 read-only起票APPROVE済み — P1a/P1b分離・実装は凍結維持】弾スループット全体のボトルネック改善 part2 — AsIs/ToBe 5W1H設計書 v1.3 (2026-07-28 21:32 家老RC契約矛盾是正。版履歴は§-3)

> part1=`throughput-bottleneck-asis-tobe-5w1h_20260728.md` v1.6(gist 2179df85)=**計測基盤**の6弾で5/6クローズ(T1a/T3a/T3b/T2/T4✅、残T1b=T1a蓄積待ち)。本書は殿下知2026-07-28 21:17「part2の設計書を作成しよう。今やっているスクリプト改善の主軸作業のボトルネックを解消して更に高速回転を行い、品質向上を高めるためだ」に基づく。part1が作った計器(T1a境界イベント・T3a writer整合・T3b fingerprint計装)の**蓄積データを消費して、弾ライフサイクルの非work時間を是正する実装編**である。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-2 弾台帳(2026-07-28 21:20時点 — 起票前。全弾❄設計のみ)

| # | 弾 | 状態 | 内容 | 起点実測(§0) |
|---|---|---|---|---|
| P1a | review_approval/report_publishイベントへのcmd_id+generation識別子計装 | ❄ 凍結(コード変更ゆえ殿裁可後。schema欠落は将軍D0確認済み21:28) | 非破壊識別子追加(第四弾#5と同型・既存台帳schema互換)。**P1aクローズ前のP1b起票は不能**(pairingの前提データが生成されないため) | schema実測: check_id/event_id/source/timestamp/verdict/wall_msのみ=cmd_id/generation不在 |
| P1b | finalize非実行時間の区分と是正 | ❄ P1a計装データ蓄積後にread-only集計から | T1a計装(review_approval:gunshi_lgtm/karo_accept)の蓄積でfinalizeを「軍師レビュー実時間/家老ACCEPT実時間/ターン待ち間隙」へ区分→最大間隙の是正(通知経路・レビュー着手遅延)。**前提=P1aクローズ済みであること(v1.3契約分離)**: 本弾のpairingはP1a計装データにのみ実行可能。P1a前の起票は不能。**AC1必須要件(家老RC①)**: cmd_id+generation単位でgunshi_lgtm/karo_acceptをpairingし、report完了起点/terminal終点で区間化。paired N/N・欠損・右打切り件数・finalize母集団53弾へのcoverage率を全て報告。イベント総数だけで待ち相を断定しない(現物は既に不対称=LGTM31/ACCEPT30)。**検査は1つも削らない**(二相レビューの品質寄与は本日実証済み=part1§0) | finalize累積27,985s(全区間中の非work最大)。cmd_complete_gate純実行は0ms(第三弾#2実証)ゆえ支配相は待ち時間の疑い(AC1で確定) |
| P2 | 例外弾unattributed残差の是正(=part1 T1b吸収) | ❄ T1a蓄積待ち(part1から帰属移管) | 例外弾(instruction_sync型stale report+複数再配備)の遷移別delivery/ack遅延を実測し、欠落遷移のみ補完。一律re-wake禁止(part1家老RC②継承)。**例外弾の判定基準(v1.2明記)**: part1と同じ観測ギャップ導出方式(unattributed分布の断絶を境界とし、恣意閾値を置かない)をAC1で本弾の母集団に対し再導出する | unattr累積20,813s、p50=31sだがmax=9,530s=例外集中型 |
| P3 | 再attempt税(FAIL往復)の削減 | ❄ AC1 read-only集計から | FAIL率(part1 T4実測: 全体0.434)の**FAIL原因別・往復回数別の時間税**を全数集計→上位原因の予防を配備時context注入・報告テンプレ強化で削減(gate緩和は禁止=品質底線)。**AC1必須要件(家老RC②)**: 856-505=351行は税の**上限**にすぎない。世代(generation)単位でWAIT/INFO/同一世代BLOCK→CLEAR/RC新世代を分類し、**真の再work往復Nとその時間だけ**を税として計上する。**時間帰属規則(v1.2穴是正)**: T3a整合の終端行採用は最新attempt境界のため旧attemptの時間が終端行に現れない — 税の時間はgate_metricsの**履歴行(同一cmd_id全行)**から世代別に取り、終端行と混同しない。修正1回で通る率の向上=品質向上と同義 | 再attempt行の上限=351行(未分類。真の税はAC1で確定) |
| P4 | deploy外れ値尾の条件特定 | ❄ AC1 read-only集計から | deploy p50=40sは是正済み(deployレーン-47%)。外れ値(max 3,321s)の発生条件を3点表で特定し条件ベース是正。**AC1二値条件(家老RC)**: 既存deploy高速化レーンとのowner重複0件を確認してから着手(重複ありなら当該項をdeployレーンへ帰属しP4から除外) | deploy累積6,600sのうち外れ値少数が支配 |

- **順序案(v1.3)**: 殿裁可後P1a先行(最大標的P1bの前提)→P3/P4のread-only AC1は即並列可(APPROVE済み)→P1bはP1a蓄積後→P2はT1a蓄積量が判定可能になり次第
- **配備=家老自立(karo_direct)**。各弾ともAC1=read-only全数集計(固定cutoff/hash付き)→序列・支配相確定→AC2実装の計測先行型(第四弾と同型)

## §-3 版履歴

- v1.3(21:32): 家老RC(blt_213134)の契約矛盾1件を是正 — P1を**P1a(識別子計装・コード変更・凍結)とP1b(蓄積後read-only pairing集計)へ台帳分離**し、P1aクローズ前のP1b起票不能を弾台帳とAC前提へ明記。P2-P4 read-only APPROVE維持
- v1.2(21:27): 殿下知「未調査や未決定、穴がないか確認して覚醒アップデートせよ」による将軍自己監査で穴6件を是正 — (1)P1起点イベントの実体確認をAC1第一手に追加(report完了起点が台帳に存在するか自体が未検証) (2)P3時間帰属規則を追記(T3a最新attempt境界は旧attempt時間を隠すため履歴行から取る) (3)§0に固定cutoff+選択バイアス明示 (4)P2例外弾判定基準(part1の観測ギャップ導出閾値)を明記 (5)P1是正実装の所有権衝突(inbox_write=第四弾#2所有)をdecision ledgerへ (6)完了宣言の型を§-1へ追加
- v1.1(21:24): 家老忖度なしレビュー(blt_212311)の必須修正2点を反映 — (1)P1 AC1にcmd_id+generation pairing・report完了起点/terminal終点・paired N/N/欠損/右打切り/coverage率を必須化(イベント総数だけでの待ち相断定を禁止) (2)P3の351行=上限と明記し、世代単位分類で真の再work往復のみを税に計上。P4にowner重複0件の二値条件。**家老判定: 反映後はAC1 read-only起票APPROVE・実装凍結維持**
- v1.0(21:20): 初版起草。殿下知21:17。序列は将軍D0全数集計(§0)から。実装凍結・家老忖度なしレビュー待ち

## §-1 スコープ決め打ち(数を先に固定)

**決め打ち: 4弾(P1-P4)**。part1との境界=part1は計器を作る(計装・writer整合)、part2は計器の蓄積データで非work時間を削る。

- **対象**: 弾ライフサイクルの非work時間(deploy/finalize/unattributed)+再attempt税。主軸=hot-scriptレーンの回転速度と初回PASS品質
- **スコープ外(途中追加禁止)**: startup gate 3本(殿裁定12:43聖域)・第四弾所有4script(full_precheck/inbox_write/report_field_set/cmd_save=個別スクリプト内部はhot-scriptレーン所有)・検査の削除や緩和(品質底線)・新台帳/新デーモン
- **第四弾との境界**: 第四弾=スクリプト1回実行の内部時間。part2=弾プロセスの回転時間(待ち・往復・間隙)。同じ変更を二重起票しない
- **完了宣言の型(v1.2追加)**: P1-P4全クローズ(各弾=AC1集計→実装→同条件Δ実測、またはno-change CLOSE)→fixed-SHA全量unit共有1回→gate_metrics固定窓再集計で非work share・e2e p50のbefore/after提示→次弾序列

## §0 結論 — AsIs実測(将軍D0全数集計 2026-07-28 21:18)

**集計規則**: 母集団=logs/gate_metrics.logのcmd_id一意終端行(最終行採用=T3a整合規則)のうち、2026-07-28付(cutoff=集計時刻2026-07-28T21:18 JSTまでの全行)・最終結果CLEAR・deploy/work/finalize/e2e全数値あり=**53弾全数**(部分抽出なし)。unattributed=e2e−work−deploy−finalize。**選択バイアス明示(v1.2)**: 4区間いずれか欠損の弾は母集団外(part1 T4実測でwork_sec欠損21.8%)。AC1では欠損弾の件数と欠損理由を併記し、母集団の代表性を確認してから序列を最終化する。

| 区間 | 累積 | p50 | p95 | max | 判定 |
|---|---:|---:|---:|---:|---|
| work | 78,756s | 841s | 4,834s | 11,890s | 難度依存(対象外。ただしP3の再attempt税はwork内に混入) |
| **finalize** | **27,985s** | 375s | 979s | 4,143s | **非work最大=P1**。純実行0msゆえ待ち時間が支配 |
| **unattributed** | **20,813s** | 31s | 724s | 9,530s | 例外集中型=**P2** |
| deploy | 6,600s | 40s | 65s | 3,321s | 恒常部は是正済み。外れ値尾=**P4** |
| e2e | 134,154s | 1,734s | 6,763s | 12,091s | **非work計55,398s=e2e総計の41.3%** |

- 再attempt税(P3): gate_metrics 856行−一意505 cmd_id=351行が再attempt。FAIL率0.434(part1 T4全数実測)。再attemptのwork/finalize再課税は上表work内に混入しており、P3のAC1で分離集計する
- T1a計装の蓄積状況: 本日review_approvalイベント61件(gunshi_lgtm 31/karo_accept 30)=P1区分の材料が生成開始済み

## §1 構造仮説(断定禁止 — 各弾AC1で実測確定してから実装)

1. **P1**: finalize p50=375sに対しcmd_complete_gate純実行0ms・review_approval実処理も0ms級(第三弾#2)→支配相は「報告完了→軍師着手」「LGTM→家老ACCEPT」のターン待ち間隙の疑い。是正候補=通知経路の即時性(nudge埋没・inbox_watcher遅延)であり、レビュー自体の省略ではない
2. **P2**: 例外弾はstale report+複数再配備の複合(part1家老一次確認)。遷移イベント差分で欠落遷移を特定してからのみ補完
3. **P3**: FAIL原因の上位は報告形式・scope契約系(gate_loop_health実測: binary_checks空欄6,823回/verdict空1,639回等)の疑い→配備時テンプレ・context注入の強化で初回PASS率を上げる=速度と品質の同時向上
4. **P4**: deploy max 3,321sは再配備・lock競合の疑い(deployレーン残候補と重複しないよう帰属確認が先)

## §2 To-Be — 進め方(型を継承)

1. **1標的=1弾・複合弾禁止**。各弾AC1=read-only全数集計(固定cutoff・母集団hash・集計コマンド併記=4規律)→AC2=最小差分実装→同条件before/after Δ実測+品質2原則+選択テストFAIL0/SKIP0
2. **品質底線**: 検査・レビュー・送達保証は1つも削らない。削るのは待ち間隙・重複往復・欠落遷移だけ
3. 全量unitはpart2全弾クローズ後のfixed-SHA checkpoint共有1回のみ(殿裁定13:26)
4. **凍結解除4段(第四弾と同型)**: (i)本v1.0家老忖度なしレビュー→(ii)AC1集計で序列・支配相確定→(iii)家老レビュー→(iv)殿裁可で実装解禁
5. 第四弾4レーン稼働と並列可(本書AC1はread-only台帳集計でファイル所有衝突なし)。ただしidle戦力の配分は家老判断で第四弾優先

## §3 decision ledger

| 項 | 状態 |
|---|---|
| 序列(P1>P2>P3>P4) | 暫定(将軍D0の§0全数集計。AC1で区分内訳を確定してから最終化) |
| P1bの支配相 | P1a計装→蓄積→P1b AC1実測待ち |
| P2の補完対象遷移 | T1a蓄積待ち(part1 T1bの帰属移管) |
| P3のFAIL原因上位 | AC1実測待ち(原因別・往復回数別の全数集計) |
| P4のdeployレーン残候補との帰属 | AC1で確認(二重起票禁止) |
| P1是正実装の所有権(v1.2新規) | **未決**: 通知経路是正が`inbox_write.sh`に及ぶ場合、第四弾#2(inbox_write_total)の所有ファイルと衝突する。AC1で是正対象ファイルが確定した時点で、第四弾#2クローズ待ち直列か、別ファイル(watcher側)限定かを家老が判定し将軍へ報告 |
| P1起点イベントの実在(v1.2新規) | **調査済み・確定(21:28将軍D0)**: defense_overheadイベントにcmd_id/generation不在(schema実測: check_id/event_id/source/timestamp/verdict/wall_msのみ)→**P1=P1a識別子計装→P1b区分集計の2段構成が確定**。P1aはコード変更を伴うため実装凍結対象(殿裁可後) |
| 家老レビュー | v1.0→RC2点→v1.1反映済み(AC1 read-only起票APPROVE)。v1.2の穴6件是正は追認レビュー対象 |
| 殿裁可 | 凍結解除4段の(iv)。それまで実装ゼロ(AC1 read-only集計のみ家老APPROVE済み) |

## §4 5W1H

- **WHY**: 主軸(hot-scriptレーン)の回転は弾のe2eで決まり、その41.3%が非work時間。work内にも再attempt税が混入。待ちと往復を削れば回転が上がり、初回PASS率向上は品質向上そのもの(殿下知21:17)
- **WHAT**: P1 finalize間隙/P2 例外残差/P3 再attempt税/P4 deploy外れ値の4弾(計測先行型)
- **WHEN**: 家老レビュー→AC1集計→殿裁可後に実装解禁。第四弾と並列(AC1はread-only)
- **WHERE**: 既存台帳(gate_metrics.log/defense_overhead.jsonl)+既存通知機構の是正のみ。新台帳・新デーモン禁止
- **WHO**: 集計・実装=忍者(karo_direct配備)、検分=家老+軍師、裁可=殿
- **HOW**: 全数集計→支配相特定→最小差分是正→同計器Δ証明。検査削除による短縮は禁止

## §5 因果リンク

- → [[弾スループット全体ボトルネック改善]] part1 v1.6(計測基盤)。T1bはP2へ帰属移管
- → [[hot-script高速化設計書]] 第四弾v2.1(スクリプト内部時間側)。境界=§-1
- → [[殿裁定_全量テスト原則_20260728]] 全量はwave最終1回
- → [[report_quality_protocol]] 二相レビュー=品質寄与実績(削らない)
- origin: `[[殿下知_part2設計_20260728]] -> [[非work41.3%の全数実測]] -> [[P1finalize間隙・P2例外残差・P3再attempt税・P4deploy外れ値の4弾]]`
