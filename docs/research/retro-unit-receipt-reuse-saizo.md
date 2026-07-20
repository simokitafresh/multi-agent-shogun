# unit receipt再利用・最終checkpoint短縮実験

日時: 2026-07-20  
対象: `scripts/run_tests.sh`（偵察のみ。本体変更なし）  
基準値: unit全量 `559195ms`

## 結論

最速の安全候補は、`integration generation + HEAD + test-tree snapshot + runner hash`をkeyにしたsingle-flight terminal receipt共有である。同一keyの2 workerは1回だけunitを実行し、後続はPASS/FAIL/SKIPを含む同じterminal receiptを受け取る。HEADまたはsnapshotが変われば必ず再実行する。

単なる「統合時1回」は変更HEADを見逃したため不採用。同一HEADの成功receipt再利用は直列では速いが、排他なしでは並行2 workerが2回実行したため単独採用不可。現行single-flightの境界を、同一integration generation内の最終checkpointまで拡張する組合せだけを推奨する。任意の過去receiptや別integrationへの跨ぎ再利用は禁止する。

## 隔離fixture実測

120msのunit代替workloadを用い、4候補×4状況=16件を同じfixtureで実行した。`exec_count`は実workload回数、`reuse`はreceipt採用数、`bad`はstale採用またはFAIL見逃し件数である。一次結果: `/tmp/saizo-receipt-exp3.BeL8Bb/results.tsv`。

|候補|同一HEAD wall/exec/reuse/bad|変更HEAD wall/exec/reuse/bad|失敗receipt wall/exec/reuse/bad|並行2worker wall/exec/reuse/bad|
|---|---:|---:|---:|---:|
|現行相当（毎回実行）|270ms / 2 / 0 / 0|285ms / 2 / 0 / 0|311ms / 2 / 0 / 0|151ms / 2 / 0 / 0|
|同一HEAD成功receipt|174ms / 1 / 1 / 0|306ms / 2 / 0 / 0|330ms / 2 / 0 / 0|170ms / 2 / 0 / 0|
|統合時1回（keyなし）|194ms / 1 / 1 / 0|186ms / 1 / 1 / **1**|170ms / 1 / 1 / 0|190ms / 2 / 0 / 0|
|HEAD-keyed single-flight|219ms / 1 / 1 / 0|322ms / 2 / 0 / 0|164ms / 1 / 1 / 0|157ms / 1 / 1 / 0|

全16件でFAIL見逃し0。stale receipt採用はkeyなし統合時1回の変更HEADだけ1件、他候補0件。失敗receipt共有はrc=1を維持しておりFAIL見逃しではない。

初回fixtureはBash動的スコープ衝突で16件中12件のcandidate keyが破損したため棄却し、局所変数化後に全16件を再実行した。再実行では候補名16/16、scenario 4種×各4件、bad集計1件を確認した。

## 現行実装との対応

- `scripts/run_tests.sh:660-727`: `all|unit`をmode別flockでsingle-flight化し、leader receiptと固定snapshotをstateへ公開する。
- `scripts/run_tests.sh:694-718`: followerはreceiptを検証し、同じrc・test count・skip countを伝播する。失敗を成功へ変換しない。
- `scripts/run_tests.sh:734-745`: 子孫へlock FDを継承させず、leaderのterminal receipt公開まで親がlockを保持する。
- 現行は待機中follower共有に限定され、lock取得後の独立した同一HEAD呼出しは再実行する。このため品質境界は強いが、同一integration内で最終checkpoint要求が重複すると最大約559秒を再消費しうる。

## 適用境界（二値）

receipt再利用を許すのは次を全て満たす場合だけとする。

1. integration generationが一致する。
2. `HEAD`、unit test-tree snapshot、`run_tests.sh`、`run_with_receipt.sh`、test selection inventoryのhashが一致する。
3. receiptがatomic publish済みで、`complete=true`、declared=observed、SKIP=0。PASSだけでなくFAILも同じrcで伝播する。
4. single-flight lock内でleader選出とreceipt再検証を行い、2 workerの実workload回数が1である。
5. HEAD/worktree/test-tree変更、receipt欠損・破損、別generationでは再利用せずunitを再実行する。

この境界ならFAIL/SKIP見逃し0、stale receipt採用0を維持しつつ、同一integrationの重複unit checkpointを2回から1回へ削減できる。基準値からの理論削減は重複1回あたり`559195ms`、2 worker同時要求時の実行回数は2→1である。
