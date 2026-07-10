# 本番再計算の非決定性根治 — AS-IS / TO-BE 5W1H (v1.2)

作成: 2026-07-11 将軍 | v1.1: 軍師深層レビュー(A-H)反映 | v1.2: 家老運用レビュー(依存・影響範囲・cron・縮退)反映
源流: cmd_3827 FAIL → cmd_3840偵察設計 → 軍師レビュー → 家老運用レビュー(blt_20260711_014245)
正本設計書: DM-signal `docs/research/cmd_3840_nondeterminism_redesign.md` (v1.2、§8=運用確定仕様)

---

## 0. 一言でいうと

**「同じデータで再計算したのに、シグナルが前回と違う」問題**の根治計画。
検証した範囲（DM-safe 1PF・最初の5,000行・単一プロセス・vectorized経路・created_at除外）では**反復差分ゼロ**だった。ただしこれは有界の実証であり、全PF・全日付・PipelineEngine側の決定性は**differential testがGREENになって初めて宣言できる**（レビュー指摘A）。
構造問題は2つ:
1. **計算経路が2本ある**（PipelineEngineと高速化用の手書きvectorized経路）。独立実装なので修正のたびに乖離し得る。実際、cmd_3835作業中に**日跨ぎ（date.today変化）だけでexact parityが42/45に割れた**実例が出た（指摘H）
2. **「同じ入力」を証明する仕組みがない**。run中に価格・config・ledgerが動くと「入力が違う」のか「バグ」なのか区別できない

調査を妨げていた「基準生成30秒timeout」は計算ではなく、**日次ループ内のgit rev-parse subprocess 238回**（35.2秒中21.2秒=60.1%）が主因。

## 1. AS-IS（現状）

| 項目 | 現状 |
|---|---|
| 計算経路 | **2本並存**。PipelineEngine（日次の正）と`_compute_pipeline_signals()`（recalculate_fast.py内の独立vectorized実装） |
| 決定性の実証範囲 | **有界**: DM-safe 1PF×5,000行×単一プロセス×vectorized経路で反復差分ゼロ。全PF/全日付/Engine側は未実証 |
| 入力の同一性 | 証明手段なし。git hashはshort/unknownになり得る。watermark+件数では過去値の遡及訂正を検知できない（指摘B） |
| 途中commit構造 | `_flush_batch`がbatchごとにdb.commit()するため、**終端で入力差を検知しても既書込みは戻せない**（指摘E）。「並行更新検知でabort」は現構造では成立しない |
| ledger guard | 正常動作。ただし正確な保証は「**不一致の提案holding_signalは永続化されない**」（ledger値へ置換後UPSERT。書込み自体がゼロではない。指摘F） |
| 計測汚染 | git rev-parse 238回=Stage A 60.1%。vectorized計算本体は0.198秒 |
| 被害 | cmd_3827が原因特定不能でFAIL。日跨ぎでparity割れ（cmd_3835実測）。検証のたび原因切り分けから始まる運用コスト |

## 2. TO-BE（あるべき姿）

| 項目 | あるべき姿 |
|---|---|
| 計算経路 | **意味論は1本**。DB/session/subprocess/date.todayを受けない純粋関数 `execute_pipeline_semantics(block_defs, terminal_def, date, initial_tickers, precomputed_inputs) -> {signal, weights, trace}` をSSOTとし、Engine adapterとvectorized adapterの双方が同関数を呼ぶ。共有範囲はselectionだけでなくterminal・SafeHaven・EqualWeight・ALM・date-miss・tie・DTB3・weightsのkey順まで。旧`_compute_pipeline_signals`は定義・呼出しとも0件に（指摘G） |
| 入力契約 | **immutable snapshot契約**（指摘E）: run開始時に全入力（価格・config・economic指標・ledger全件preload）をsnapshotへロードし、以後のsource table SELECTをquery guardで0件強制。並行更新は現在runに混入せず「次runのmanifest差」として現れる |
| 入力manifest | **実際にロードしたartifactのcanonical SHA-256が正本**（指摘B）。必須キー: manifest_version、full 40桁source hash+dirty/source fingerprint、logical_date、run_started_at、対象PFのexact set、正規化config hash/PF、price hash/symbol、全economic-input hash、ledger canonical hash+件数+max recorded_at、Python/pandas/numpyバージョン |
| git hash | full hashを環境変数（RenderのcommitSHA）優先+git fallbackで**run開始時に1回**取得。unknown/dirtyは本番write前にfail-closed（指摘C） |
| logical_date | **1 run 1値で固定**。date.today直参照を排し日跨ぎ非決定性を根絶（指摘H） |
| manifest永続化 | schema migrationゼロ。既存`recalculation_timings.layer_data["input_manifest"]`へrun開始時にprovisional UPSERT、失敗時は最初のSignal write前にabort、完了時に同run_idを更新（指摘D）。※「本番DB変更ゼロ」ではなく「**schema変更ゼロ・既存JSON列への書込みあり**」が正確 |
| ledger guard | 維持・緩めない。drift収集にmanifest_id/source hashを添付し「入力が違った/計算が違った」を即断可能に（指摘F） |
| 速度 | Stage A warm 5回 median≤5s/p95≤6s/hard<30s、cold≤15s、RSS非増大。全日付Engine逐日（約2,000秒）はoracle限定 |

## 3. 5W1H

| | 内容 |
|---|---|
| **Why** | 再計算の信頼性はDM-Signal全機能の土台。二重実装は乖離リスクを永久に抱え（日跨ぎparity割れで実証済み）、入力証明がないと検証が実験として成立しない。cmd_3827 FAILで実害顕在化 |
| **What** | P1 hotfix（git hash定数化+logical_date固定+immutable snapshot+strict manifest）→P2 differential testを先にRED化→P3 共通executor実装+両adapter接続+旧関数削除→P4 全shard exact GREEN+性能確認 |
| **When** | P1は実装cmd裁可後すぐ。P2-P4は直列（differential RED化が共通executorの前提） |
| **Where** | `recalculate_fast.py`・`services/pipeline/engine.py`・`backend/tests/`・`recalculation_timings.layer_data`。ledger guard（signal_flush.py）は保証文言の正確化のみで緩めない。DB schema変更ゼロ |
| **Who** | 忍者直列（P1 hotfix cmd→P2-P4本体cmd）。設計は正本設計書+本レビュー反映で確定 |
| **How** | 下記の実装順P1-P4と二値AC7本。対象縮小禁止（全PF×全日付、PF shard分割で網羅） |

## 4. 確定実装順（軍師+家老レビューで未決断ゼロ化。v1.2でP1を二分）

| Phase | 内容 |
|---|---|
| **P1a**（単独デプロイ可） | full source identity(40hex、Render環境変数優先)のrun開始1回化+logical_date 1値固定+20桁一意run_id+loop内git呼出0 |
| **P1b**（全統合test後） | immutable input/ledger snapshot+strict manifest+query guard+全呼出し元/cron対応 |
| P2 RED | 専用branch/worktreeで全PF×全日付のEngine対adapter exact比較testをRED整備（mainに置かない、対象縮小禁止） |
| P3 実装 | 同branchで共通pure executor実装、両adapter接続、旧関数削除。GREEN後のみmerge |
| P4 GREEN+性能 | 全shard exact GREEN、Stage A warm5 median≤5s/p95≤6s/hard<30s、cold≤15s、本番fullrecalculateは許可済み1回のみ |

**着手条件**: cmd_3835（同ファイル群を変更中）のGATE CLEAR+作業ツリー整流後。並行編集禁止。

**二値AC（軍師7本+家老7本）**: 軍師分=①loop内git hash呼出0・manifest 1/run・unknown/dirtyでwrite0 ②snapshot後source SELECT0・ledger query0 ③differential exact mismatch0・SKIP0 ④旧関数定義/呼出0 ⑤guard不一致提案値write0+manifest_id ⑥性能値 ⑦既存test PASS/SKIP0・schema migration0。家老分=Ⓐ失敗時はconfig audit含むbusiness write0 Ⓑ5つの本番呼出し元全てで識別情報の伝播一致 Ⓒprovisional→completedでmanifest消失0+run_id衝突test Ⓓ L2失敗→L3/L5実行0+cron nonzero検知 Ⓔstandalone L5のmanifest+L3当日成功必須 Ⓕguard 0件強制 Ⓖ全PF×全日付shard網羅

## 4.5 家老運用レビューで塞がった穴（v1.2）

- **書込み順序の重大穴**: 現コードは入力ロード前にconfig snapshot INSERT+cleanupを実行しており「manifest失敗時write0」が現順序では偽。REPEATABLE READのread-sessionで全入力をmaterialize→manifest確定→**初めて**業務書込み、の順序に確定。失敗時は旧公開データ完全維持
- **standalone L5経路の未被覆**: precompute単独実行(admin API+02:00UTC fallback cron)がmanifest対象外だった→専用manifest_kind=l5を新設
- **cronの見かけ成功問題**: L2/L3/月次はHTTP acceptedを即返すためcurl成功≠job成功。endpoint受理前の同期preflight+terminal poll+失敗時nonzeroへ変更。UNKNOWN/DIRTYは恒久エラーとして自動retry禁止+alert
- **L5 fallback cronの穴**: L3失敗日でもstale DBで走れる→L3当日成功を実行条件に追加
- **timing書込みの穴**: LayerTimerは例外握り潰し+layer_data全置換でmanifestが消え得る→"_run"予約key+strict UPSERT(失敗raise)+merge方式へ

## 5. これで何が変わるか（殿の体験）

- 差分が出たら**manifest差分を見るだけで「入力が動いた」か「バグ」かを即断**できる（入力はimmutable snapshotで固定済みなので、run内混入はそもそも起きない）
- シグナルロジックの修正は純粋関数1箇所で日次もbatchも揃う。「片方だけ直る」事故が構造的に消える
- 日跨ぎ・dirty worktree・並行更新という「たまたま起きる」系の不安定要因が全てfail-closedまたはmanifest差分として可視化される

## 5.5 将軍メタレビュー（v1.2.1、殿指示2026-07-11 01:51「覚醒して穴がないかメタレビューせよ」）

軍師（コード）・家老（運用）の二重レビュー後に残る、戦略・前提・プロセス層の穴7点:

| # | 穴 | 対処 |
|---|---|---|
| M1 | **元の問いへの回帰パスがない**。本計画の発端はcmd_3827「バンドなしledgerとsignalsの整合検証」のFAIL。P4完了後にcmd_3827相当の再検証（DRIFT BLOCK原因の最終確定）を行う工程が設計に存在しない | P4の後工程として「manifest固定下でのcmd_3827再実行=整合検証の完結」を追加。これが完了して初めて発端の問いが閉じる |
| M2 | **実測値の時限性**。35.2s/0.198s/warm3.9s等のbaselineは全てcmd_3835による同ファイル群の大改修**前**の実測。P1a着手時点ではコードが変わっている | P1aの最初のACに「baseline再計測」を含める。旧数値を目標値の根拠にしない |
| M3 | **P2の計算量計画がない**。全PF×全日付differential（103PF×約5,000日）の実行時間・メモリ見積もりが未記載。GS系の実証教訓（並列RSS 8.5GB、直列1本ずつが正解）が適用されるべき領域 | P2起票時にshard実行の直列/並列方針とRSS上限を明記。対象縮小はしない、実行計画で吸収する |
| M4 | **「停止点なく実装可能」への疑義=殿裁定チェックポイント欠落**。P1a+P1bだけで実害（timeout・比較不能・日跨ぎ）はほぼ消える。P2-P4（共通executor化）は乖離リスクへの恒久投資であり価値は実在するが、レビュー3者とも「全部やる」前提で「P1b完了後の実測を見てP2-P4の着手時機を殿が裁定する」停止点を置いていない | P1b完了時に実測+乖離リスク再評価を殿へ上程する裁定点を工程に追加 |
| M5 | **drift検知の監視経路がない**。manifest_id付きdriftを記録しても、殿/家老に届く通知経路（ntfy/dashboard）が未設計。検知しても誰も見なければ存在しないのと同じ | P1bのACに「drift+manifest差分発生時の通知経路（既存ntfy/dashboardへの接続）」を追加 |
| M6 | **cmd_3788との統合未確認**。uvicorn --workers 2でのrecalculation statusクロスプロセス誤答は既知で設計書化済み（cmd_3788、gist 5ca0ffd5）。manifestの「1 run 1値」保証はプロセス排他の上に立つが、既存409排他（L0-L3は確認済み）が④PF保存後partial・⑤復元後partialとsync系の並行実行も排他するかは未確認 | P1b設計時にcmd_3788設計書と突合し、partial系との並行時のmanifest/書込み整合を確認事項に追加 |
| M7 | **正本の版管理が宙**。設計書v1.2はworking tree上にあり、hanzoのstaged混在でcommit不能。実装cmdが「どの版の設計書に従うか」が固定されていない | P1a起票の前提条件に「設計書v1.2のcommit確定+task YAMLへcommit hash明記」を置く（家老整流時に解消予定） |

横展開メモ: 「HTTP accepted≠job成功」（家老発見）は他cron・他PJにも同型があり得る。lesson登録時に横展開対象の列挙を含めること。

### M1-M7の確定仕様（v1.3、家老全採用 blt_20260711_015722 + 軍師盲点認定 blt_20260711_015612）

- **M1→P5回帰の新設**: P4本番fullrecalculate後に、発端cmd_3827と同一の整合シナリオ（ledger・confirmed holding・exact-set・DRIFT BLOCKの元事故条件）を再実行しmismatch 0で発端の問いを閉じる
- **M4→裁定checkpoint必須化**: 「停止点なく実装可能」の結語は洗脳#8として削除。設計確定範囲は**P1a→P1bまで**。P1b完了時にmanifest現物・5呼出し元・cron縮退・production preflight結果を殿へ提示し、**P2-P4への進行は殿裁定必須。自動継続禁止**
- **M5→drift三段通知**: (1)primary=DB永続（layer_data._run.drift_summaryにmanifest_id/source hash/PF/date/before/ledger/count）(2)immediate=ntfy集約1件 (3)dashboard=未解消drift件数+最新manifest_id。ntfy失敗でもguardは緩めず、DB永続を正本に再送可能化
- **M2→baseline再計測**: P1a冒頭でStage A cold/warmを再計測。旧35.2/11.8/3.9秒は現値扱いしない
- **M3→shard/chunk実行計画**: 固定PF shard manifest+同一fixture read-only+shard内直列。RSS上限超過時はchunk分割で全量統合（対象縮小・SKIP 0）
- **M6→cmd_3788正本へ統合**: 新しいstatus SSOTを作らず、既存のcross-process recalc lock+cmd_3788正本へmanifest phase（provisional/completed/failed）を統合。partial 2系にもlock必須+5呼出し元の並行排他test
- **M7→版固定**: 起票時に正本設計書のcommit full 40桁+gist revisionをtask YAMLへ固定。実装中の設計変更は再レビューなしの取込禁止。**正本commit固定前はP1a配備BLOCK**

軍師はレビュー機構へ「運用接続3問（回帰はどこで？裁定はいつ？通知は誰へ？）」を恒常追加（プロセス還流済み）。

- **M8（殿指摘2026-07-11 02:03で発見、v1.3.1）**: 家老の呼出し元全列挙に**第6の書込みcallerが漏れていた**。`api/debug.py`のadmin向けFoFプロファイリングEPが`_recalculate_fof_history`を直呼びし、確定済みholding_signalを実書き換えし得る（内部commit・rollback不能とコード内コメントに明記済み）。recalculate_history_fastを経由しないためmanifest/snapshot契約の迂回路になる——P1bで被覆(manifest必須化 or write禁止化)、AC-Bの対象へ追加。あわせて用語整理: `fullrecalculate.py`というファイルは存在せず、実体はrecalculate_fast.py+recalculate_fof.py+precompute_raw/mtd.pyの4ファイル（fullrecalculateは運用操作名）。

## 6. 因果

`[[cmd_3827_FAIL]] -> [[Stage_A計測汚染=git_hash_subprocess238回]] + [[入力manifest不在で比較不能]] + [[二重実装の乖離(日跨ぎparity割れで実証)]] -> [[P1 hotfix(snapshot+manifest) -> P2 differential RED -> P3 共通executor -> P4 GREEN]]`

## 7. 改訂履歴

- v1.0 (2026-07-11 00:05): 初版
- v1.1 (2026-07-11 01:05): 軍師深層レビュー(REQUEST_CHANGES)のA-H全反映 — 決定性主張の有界化(A)、manifest正本=canonical SHA-256+必須キー(B)、full hash+fail-closed(C)、永続化先確定+「DB変更0」訂正(D)、immutable snapshot契約への変更(E)、ledger guard保証の正確化(F)、共通executor契約の具体化(G)、logical_date固定(H)、実装順P1-P4+二値AC7本
