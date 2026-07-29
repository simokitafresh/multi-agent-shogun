# 【✅弾#0=live着地済み(schema移行事故は喪失受理+再発防止hotfix稼働でクローズ)。wave-final発射条件充足 — 本体はwave-final後に序列確定→裁可】ホットスクリプト集中高速化 第七弾(テスト速度) — AsIs/ToBe 5W1H設計書 v1.5 (2026-07-30 01:20 将軍覚醒更新。殿発案22:06)

## §-2.5 弾#0実行結果(2026-07-30 01:20時点 — 掲示板+才蔵全数走査+gate_metrics一次確認)

| 事象 | 時刻 | 状態 |
|---|---|---|
| 弾#0発射+殿裁可 | 07-29 23:28/23:29 | ✅第一段解禁正式成立(可逆自走発射と裁定整合) |
| 実装着地 | 07-29 23:57報 | ✅新4識別子契約=task選択223/223 PASS・SKIP0、commit e80b5884。**tap/output本文不変・原子publishの契約どおり** |
| ★schema移行事故 | 07-29 23:57検知 | 初回移行が旧ledger履歴を置換: per-file 20,731行/per-suite 1,637行→数行。live treeはbefore/after一致(本番非汚染) |
| 復元調査確定 | 07-30 00:09 | 才蔵全数走査(候補8,518ファイル: test_receipts json/output・tmp/cache/log埋込)で旧schema完全復元行**0**=復元不能確定。教訓L1461登録 |
| 将軍裁定 | 07-30 00:10 | **喪失受理**。wave-final停止事由を『復元待ち』から解除 |
| 再発防止hotfix | 07-30 00:49 | ✅GATE CLEAR(cmd_karo_hotfix_ledger_schema_snapshot_guard: snapshot hash+行数一致+復元dry-runをpublish前強制、飛猿) |
| 第六弾影響照合 | 07-30 00:13 | ✅旧test ledger依存**0件**(第六弾v1.8+独立レビュー報告)=第六弾の代替蓄積期間0日 |
| 殿優先裁定 | 07-30 00:37 | 『第五〜第七弾が優先だ』 |

**現況**: 新schema ledgerは蓄積進行中(01:17時点 per-file 109行+)。**wave-final発射条件=充足済み**(弾#0 liveクローズ+hotfix稼働)。第五弾は全10弾GATE CLEAR済みゆえ、次手=wave-final全量run(本run receiptが第七弾の序列SSOTを兼務)→4識別子結合で序列確定→本体裁可。

## §-2 版履歴
- v1.5(07-30 01:20): §-2.5新設(弾#0実行結果・事故と受理・wave-final発射条件充足の刻印)。旧ledger喪失により§0の序列SSOTは「wave-final以降の新schema計測のみ」で構成することを明確化(過去比較は不能=正直記載)
- v1.4(23:25): 家老実装可能性監査(blt_232122・PASS+最終RC1件)反映 — 弾#0の計装対象を「receipt+per-file/per-suite ledgerへ4識別子値追加、**tap/output本文は不変**(receipt artifact path+basename由来tap pathで所有run関連付け)」へ確定。最小実装像(run_tests.sh+2 ledger writer、outer run_id生成→inner pending→hash確定→原子publish)と敵対3件PASS・現状実測(receipt 3,201件run_id 0/ledger計22,344行output_sha256列0)を§0へ記録。旧v1.1参照表記も整理
- v1.3(23:07): 家老再検分(blt_230515)の時系列自己矛盾を是正 — **二段階解禁へ統一**: 【第一段】弾#0(run_identity計装)のみ独立裁可の対象とし、裁可あれば**第五弾wave-finalより前に**実装+選択検証(これがなければwave-finalが結合不能のままになるため)。【第二段】第七弾本体(序列確定・弾数固定・是正弾)はwave-final成功receipt→4識別子結合で序列確定→本体裁可→起票解禁。§0/§3/§4のWHENを全て本契約へ揃え、表題版もv1.3へ統一
- v1.2(23:00): 家老独立監査(blt_225827)の実行不能指摘を是正 — 現行schemaでは4識別子結合が生成不能(receiptにrun_id/source_fp無し・ledgerにoutput_sha256無し)ため、**弾#0=run_identity計装(非破壊・wave-final前導入必須)を前提弾として新設**。現存キー導出写像は同一commit複数run曖昧性ゆえ不採用。疾風の当該review task FAILは正当(実行不能の正直報告)
- v1.1(22:45): 家老忖度なしレビュー(blt_223951)RC5点反映 — ①序列SSOT結合契約を§0へ追加 ②setup寄与のwall−Σtest算出を撤回(--jobs並列でΣtest>wall可能)→focused serial probe/明示計装へ ③共有層writer=shared先行→固定HEAD再計測→個別writerの直列依存 ④敵対fixtureは変更した独立oracle・副作用境界ごと ⑤序列確定・弾数固定はwave-final receipt後(それまで構造監査のみ)
- v1.0(22:10): 初版起草(殿発案22:06)

> 型元: 第一〜五弾(`hot-script-speedup-*-5w1h_*.md`)。第五弾はv1.4.1確定・稼働中(gist 5259aa640)。本書は**同じ弾スタイルをテスト実行時間へ写像**する。第六弾(実務の間=finalize+待ち間隙、part2統合)とは標的層が異なり独立(§4)。

## §-1 スコープと境界(数と原理を先に固定)

- **標的=テスト実行時間の高速化のみ。検証力は1点も削らない**(品質底線§2)。**淘汰(テスト削除)はスコープ外** — 既存S3レーン+default-delete test policyの領分(境界固定。削除と高速化を同弾に混ぜない)
- **弾数=序列確定後に決め打ち**(第五弾§-1憲法の踏襲: 数を先に固定し途中追加しない。序列snapshotを見て上位N+共有層弾を殿へ提示→裁可で固定)
- **writer構造(スクリプト弾との写像、家老RC③で直列依存確定)**: 1テストファイル(bats)=1弾=1レーン。**共有層(tests/test_helper/・setup/teardown・共有fixture)は独立writerかつ先行** — 順序=shared弾クローズ→**固定HEADで全体再計測(shared是正が全fileのbaselineを変えるため)**→個別writer弾。sharedと個別の並列変更はbaseline・序列を無効化するため禁止
- **スコープ外**: テストの削除・SKIP化・assertion削減(検証力低下)/CI workflow構成の変更(timeout等は済み)/DM-Signal側pytest(別repo・別弾判断)

## §0 序列SSOT(実測待ち — 解禁時の第0手)

**序列snapshotの取得方法(確定)**: 追加の全量実行はしない。**第五弾wave最終のfixed-SHA全量unit checkpoint 1回**(殿裁定2026-07-28全量テスト原則: 全量はwave最終1回)の受領書+bats per-test timingをそのまま第七弾の序列一次データへ転用する。宣言4点(exact境界・row_count・raw hash・採用HEAD)は第五弾v4/v5 snapshotと同型。

- **序列SSOT結合契約(家老RC①・v1.1確定→v1.2で充足経路を確定)**: 計測データは4箇所に分散する — receipt JSON=suite全体のduration/rc/hash、per-file=`logs/test_timing_ledger.tsv`、per-test=receipt `.tap`、file実行順=receipt `.output`のSTART列。序列snapshotは**同一run_id・commit・source_fp・output_shaの4識別子で一意結合**したものだけを正とし、結合できない行は序列から除外して件数を報告する
- **★結合契約の充足経路(家老独立監査22:58で実行不能と確定→v1.2是正)**: 現行schemaは4識別子結合を満たさない — receipt JSONにrun_id/source_fingerprintが無く、ledgerにoutput_sha256が無い(家老一次実測: ledger=run_id,repo,commit_sha,…,source_fingerprint / receipt=…,output_sha256,duration_ms等のみ)ため、同一commit・同一source_fpの複数runを一意対応できない。**充足経路=run_identity計装を第七弾の弾#0(前提弾)とする(v1.4=家老実装可能性監査PASSの実装像へ文言確定)**: **receipt JSONとper-file/per-suite ledgerへ4識別子値を追加する。tap/output本文へは一切identityを追加しない** — tap/outputはreceipt artifact pathとbasename由来tap pathで所有runへ関連付ける(本文不変=既存パーサ・比較の互換維持)。最小実装=run_tests.sh+2 ledger writer: outerで開始前にrun_id生成→inner timing batch pending→receipt/output hash確定→receiptへrun_id/source_fp追加→同hashでledgerを原子publish(家老監査23:21・敵対3件込みPASS: 並行2run交差0/途中失敗のsuccess序列混入0/cache混在時receipt1・suite1・per-file≥1結合)。**wave-final全量runより前に導入**し、wave-final runが結合可能な最初の序列SSOTになるよう順序を固定(導入前の過去receiptは序列に使わない=結合不能行の除外規則で一貫)。現状実測(家老23:21): receipt 3,201件中run_id 0・source_fp 0/per-file ledger 20,711行・per-suite 1,633行ともoutput_sha256列0。計装はコード変更ゆえ殿裁可の対象(第一段)。代替の「現存キーからの導出写像」は同一commit複数runの曖昧性が残るため不採用
- 台帳の実在(2026-07-29 22:09将軍一次確認): `logs/test_receipts/` receipt **3,189件**・`tests/unit/` bats **182本**・receiptにduration_ms実在(例: 652,369ms=約11分の重量受領書を確認)
- AsIsの規模感(既知の一次実測のみ・序列ではない): unit全量≈2,454s(2026-07-24実測)/CI unit job=テスト成長で旧timeout 5分を突破し3連続cancel→12分へ是正(LS101統合教訓)・是正後7分07秒完走/checkpoint全量2,745テスト(第四弾3巡CLEAR)/affected選択実行でも1ファイル33.5s実例(test_semantic_index_update.bats 43件、2026-07-29将軍commit実測)
- **序列確定・弾数固定の時期(家老RC⑤)**: **第五弾wave-final fixed-SHA全量unit receiptの生成後**。それまでは構造監査(結合契約・計測法・writer依存の確定=本設計書v1.1以降の監査工程)のみ行い、序列・弾数を仮確定しない(直近全量receiptはrc=1 FAIL=duration_ms 129,782の失敗runゆえ序列に使えない — 成功runのみが序列SSOT)

## §1 計測境界(憲法)

- 計測=既存台帳のみ(test receipts+bats timing)。**新台帳禁止**
- per-test時間とper-file時間を区別(1件=bats 1 test caseの実行時間。file合計=setup×回数+test本体群)
- **setup寄与の分離が本弾最重要(家老RC②で測定法確定)**: ~~file wall−Σtest本体~~は**不可** — run_tests.shはfile内`--jobs`並列実行のためΣtest durationがwallを超え得る(引き算が負や無意味になる)。shared setup寄与は**focused serial probe**(対象fileを直列1本で実測し差分を取る)または**明示計装**(setup/teardown区間の直接記録)でのみ測る。per-fileだけで見るとsetup支配を「テストが遅い」と誤帰属する
- before/afterは**同一SHA・同一テスト集合・同一環境**(ローカルは同一マシン、CIはrunner世代明記)の対でのみ倍率を語る(§1誤りの型=異run混算禁止を継承)
- run間ノイズ: 受領書の同一ファイル複数実測から変動幅を先に把握し、Δ有意判定はノイズ帯超のみ(fullrecalc第1回の教訓2026-07-29)

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**。恒常課税型(毎回遅いsetup/fixture)=子区分計測→最大寄与是正/外れ値型(特定testのみ秒級)=発火条件特定→条件ベース是正
2. **品質底線(テスト版・品質2原則の写像、家老RC④で強化)**: (a)**検証力不変**=assertion数だけでなく**検証対象・negative oracle・副作用検証・exit code/stdout同値**を全て固定。mock化・fixture縮小で検証を弱める是正は禁止(簡略版コード禁止のテスト版) (b)**PASS/FAIL挙動不変**=是正前後で同一SHAの判定結果完全一致・SKIP=FAIL維持 (c)敵対fixture(意図的バグ注入)は一律1点でなく、**是正で変更した独立oracle・副作用境界ごとに1点**設置し「壊れたコードを検出できる」ことを確認
3. 典型手筋(序列確定前の仮説在庫。序列で裏取りしてから使う): setup共有化(per-test→per-file 1回)/固定sleep・ポーリングのイベント駆動化/重量fixtureの生成→静的資産化/プロセス起動回数削減(bats runの外部コマンド)/tmpfs活用。**事前外挿禁止・実測のみ**
4. **反復サイクル型(殿裁定2026-07-29 13:26)**: ローカル極限化→CI/checkpoint実測→差分再検証→再極限化。停止条件=Δがノイズ帯以内でクローズ(採用またはno-change)
5. **read-only冗長並列(殿裁定13:28)**: 序列抽出・発火条件記録などread-only段のみ冗長2名先着採用。テストファイル是正の実装段は単独所有
6. 個別弾は選択実行(`bash scripts/run_tests.sh file <対象>`)FAIL0・SKIP0のみ。**全量はwave最終fixed-SHA 1回**(殿裁定・全弾共通)
7. 完了宣言=全弾クローズ→fixed-SHA全量unit 1回(これが次弾の序列snapshotを兼ねる)→Δ総括(全量実行時間before/after)

## §3 decision ledger

| 項 | 状態 |
|---|---|
| 弾スタイルのテスト適用 | 殿発案22:06・将軍賛同済み。**採否の正式裁可待ち** |
| 序列snapshot | **wave-final成功receipt待ち(RC⑤)**: 第五弾wave最終fixed-SHA全量unit成功run生成後に4識別子結合で確定。それまで構造監査のみ |
| **弾#0 run_identity計装(前提弾)** | 🚀**発射済み+殿裁可確定(2026-07-29 23:28将軍自走下知→23:29殿『裁可する』で第一段解禁正式成立)**: 実装可能性監査PASS(家老23:21・敵対3件込み)の実装像で配備 — receipt+per-file/per-suite ledgerへ4識別子値追加、**tap/output本文不変**。AC=敵対3件+選択実行FAIL0/SKIP0+revert手順明記。**第五弾wave-final前のliveクローズが絶対条件** |
| 弾数・標的固定 | 序列確定後に殿へ提示→裁可で決め打ち |
| 淘汰との境界 | **確定**: 第七弾=高速化のみ。削除はS3レーン+default-delete policy |
| 共有層writer | **確定(RC③)**: test_helper/setup/fixtureは独立writerかつ**先行** — shared弾クローズ→固定HEAD全体再計測→個別writer弾の直列依存。並列変更禁止 |
| 起票解禁(二段階) | 【第一段】弾#0のみ独立裁可→即実装(wave-final前)。【第二段】本体=wave-final成功receipt→序列確定→本体裁可→起票解禁。優先順位=第五弾実装>第六弾計測>第七弾(idle充填順、2026-07-29将軍下知) |

## §4 5W1H

- **WHY**: テスト実行時間は開発の全周回に課税する(pre-commit affected 33.5s実例・CI unit 7分・全量2,454s)。テスト成長でCI timeoutを突破した実害歴(3連続cancel)あり。速いテスト=試行回数最大化=ラルフループの回転数そのもの
- **WHAT**: 弾スタイル(台帳→序列→1標的1弾→同条件Δ→品質底線)のテスト写像。検証力不変で実行時間のみ削る
- **WHEN(二段階解禁)**: 【第一段】弾#0(run_identity計装)=独立裁可→**第五弾wave-final前に**実装+選択検証。【第二段】本体=wave-final成功receipt生成→序列確定(4識別子結合)→本体裁可→起票解禁。優先順位は第五弾>第六弾>第七弾
- **WHERE**: `tests/unit/*.bats` 182本+`tests/test_helper/`共有層。台帳=`logs/test_receipts/`(3,189件)+bats timing
- **WHO**: 序列抽出=忍者(read-only冗長2名)、是正実装=忍者(1ファイル単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税=setup寄与分離(serial probe/明示計装)→最大寄与是正、外れ値=発火条件→条件ベース是正。敵対fixtureは変更した独立oracle・副作用境界ごとに設置して検証力確認(RC④)

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜五弾。様式・計測憲法・完了条件の型元
- → [[殿裁定_全量テスト原則_20260728]] 全量はwave最終1回=序列snapshot転用の根拠
- → [[殿裁定_fullrecalc作業型_20260729]] 反復サイクル型・read-only冗長並列・報告整形最終集約の運用3裁定
- → S3速度改善レーン(`docs/research/s3-test-speed-asis-tobe-5w1h_20260720.md`) 淘汰側の正本(境界)
- → default-delete test policy(CLAUDE.md) 削除の契約(第七弾はこれに触れない)
- origin: `[[殿発案_第七弾テスト速度_20260729]] -> [[テスト成長がCI timeout突破した実害歴]] -> [[弾スタイルのテスト写像v1.0]]`
