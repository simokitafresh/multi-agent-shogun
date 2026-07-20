# deferred report publication 適用可能patch

- 実施日: 2026-07-20
- 隔離clone: `.tobisaru-retro-publication.ta8KDD/clone`
- base: `573bc73537b3a7538f90b35546ad2301fd3f5add`
- patch commit/hash: `c8e60937c317cbade9e731577a9e26d811900e43`
- 共有本体: `scripts/deploy_task.sh`を含め読取専用。変更なし。

## 実装

`scripts/report_field_set.sh --batch` のterminal経路で、atomic replace済みreportをdurable outbox（同期成功境界）として確定後、`inbox_write.sh` deliveryを1本のdetached processへ分離した。旧経路のfast reconciler + synchronous publisherという二重呼出を除去し、process/pane death時はpersist済みterminal bytesをmonitorが回収できる契約を維持する。表示型gate/hookは追加していない。

変更したcontract testは `tests/unit/test_report_field_set_batch_throughput.bats`。新behavior（persist-before-delivery、detached delivery、pre-delivery failpoint時のdelivery 0）を既存contractの拡張として固定した。

## 反復計測

同一の既存contract fixtureで現行baseと候補を各N=20反復した。

| 対象 | N | p50 wall | p95 wall | publish/delivery順序 | FAIL | SKIP |
|---|---:|---:|---:|---|---:|---:|
| 現行base | 20 | 240ms | 641ms | atomic report → synchronous delivery（fast reconcilerも起動） | 0 | 0 |
| 候補patch | 20 | 243ms | 430ms | atomic report → return boundary → detached delivery | 0 | 0 |

p95は641→430ms（-32.9%）。fixture生成・YAML検証を含むcontract全体ではp50差が固定費に埋もれる。publication単体の直前retro（同一terminal schema N=10）では現行347ms→候補4ms（-98.8%）であり、全background完走後のreport欠落0、重複0、delivery identity不一致0、一意publish 10/10だった。

## 二値検証

- 関連contract: `bats tests/unit/test_report_field_set_batch_throughput.bats` → 13/13 PASS、FAIL0、SKIP0。
- terminal report欠落: 0/20。
- delivery重複: 0/20（各reportにつきevent 1）。
- identity不一致: 0/20（worker=`hanzo`, parent=`cmd_test`, report basename一致）。
- failpoint: atomic永続化後・delivery前でrc=86、persisted=1、delivery=0、monitor repairable=1。

初回候補実行では旧同期期待のcontract 2件がFAILした。一次結果から実装故障ではなく期待値不一致と特定し、上記新behaviorへcontractを更新後、13/13 PASSを確認した。無効fixture参照となった別N=10試行は全件BLOCKのため測定から除外した。

## 適用順序

1. base `573bc73537b3a7538f90b35546ad2301fd3f5add` にpatch `c8e60937c317cbade9e731577a9e26d811900e43` を適用する。
2. `scripts/report_field_set.sh` のdeferred delivery差分を先に適用する。
3. 同commit内のcontract更新を適用する。
4. 関連contract 13/13 PASS・SKIP0を確認する。
5. terminal bytes永続化→return→deliveryの順序、event 1/report、identity一致を再確認する。

patchは隔離clone内の2ファイルだけを含み、共有本体へは未適用・未pushである。
