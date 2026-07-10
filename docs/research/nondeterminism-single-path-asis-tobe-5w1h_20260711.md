# 本番再計算の非決定性根治 — AS-IS / TO-BE 5W1H (v1.1)

作成: 2026-07-11 将軍 | v1.1: 軍師深層レビュー(blt_20260711_005845、A-H全指摘)反映
源流: cmd_3827 FAIL → cmd_3840偵察設計(GATE CLEAR 2026-07-10 23:03) → 深層レビューREQUEST_CHANGES反映
正本設計書: DM-signal `docs/research/cmd_3840_nondeterminism_redesign.md`

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

## 4. 確定実装順（軍師レビューで未決断ゼロ化）

| Phase | 内容 |
|---|---|
| P1 hotfix | full source hash定数化+logical_date 1値固定+immutable input/ledger snapshot+strict manifest provisional保存 |
| P2 RED | frozen fixtureで全PF×全日付をPF shard分割し、Engine対adapterのsignal/weights/exceptionのexact比較testを先にRED状態で整備（対象縮小禁止） |
| P3 実装 | 共通pure executor実装、両adapter接続、旧`_compute_pipeline_signals`削除 |
| P4 GREEN+性能 | 全shard exact GREEN、Stage A warm5 median≤5s/p95≤6s/hard<30s、cold≤15s、RSS非増大、本番fullrecalculateは許可済み1回のみ |

**二値AC**: ①loop内git hash呼出0・manifest 1/run・unknown/dirtyでwrite0 ②snapshot後のsource SELECT0・ledger query0 ③differential全PF×全日付でsignal/weights exact mismatch0・SKIP0 ④旧関数の定義/呼出0 ⑤ledger guardの不一致提案値write0+manifest_id付与 ⑥性能値達成 ⑦全既存test PASS/SKIP0・schema migration0

## 5. これで何が変わるか（殿の体験）

- 差分が出たら**manifest差分を見るだけで「入力が動いた」か「バグ」かを即断**できる（入力はimmutable snapshotで固定済みなので、run内混入はそもそも起きない）
- シグナルロジックの修正は純粋関数1箇所で日次もbatchも揃う。「片方だけ直る」事故が構造的に消える
- 日跨ぎ・dirty worktree・並行更新という「たまたま起きる」系の不安定要因が全てfail-closedまたはmanifest差分として可視化される

## 6. 因果

`[[cmd_3827_FAIL]] -> [[Stage_A計測汚染=git_hash_subprocess238回]] + [[入力manifest不在で比較不能]] + [[二重実装の乖離(日跨ぎparity割れで実証)]] -> [[P1 hotfix(snapshot+manifest) -> P2 differential RED -> P3 共通executor -> P4 GREEN]]`

## 7. 改訂履歴

- v1.0 (2026-07-11 00:05): 初版
- v1.1 (2026-07-11 01:05): 軍師深層レビュー(REQUEST_CHANGES)のA-H全反映 — 決定性主張の有界化(A)、manifest正本=canonical SHA-256+必須キー(B)、full hash+fail-closed(C)、永続化先確定+「DB変更0」訂正(D)、immutable snapshot契約への変更(E)、ledger guard保証の正確化(F)、共通executor契約の具体化(G)、logical_date固定(H)、実装順P1-P4+二値AC7本
