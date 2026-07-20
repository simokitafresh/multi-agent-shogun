# Retro review friction isolated experiments

Date: 2026-07-20  
Task: `cmd_karo_retro_review_friction_202607202052_normal`

## Method

`/tmp/retro-friction.*` に report / approval / log の最小構造を作り、現行条件と当該条件だけを無効化した候補を同一入力で各10回実行した。本体・gate・hookは変更していない。`notify_missing` は、当該BLOCKにより後続通知へ到達しなかった回数である。

## Results

| friction | input | current wall_ms / BLOCK / notify_missing | disabled candidate wall_ms / BLOCK / notify_missing | quality delta | decision |
|---|---|---:|---:|---|---|
| parent mismatch | report `parent_cmd=cmd_other`, requested `cmd_test` | 837 / 10 / 10 | 3 / 0 / 0 | wrong-command reportを通すため境界保証を失う | keep |
| approval marker | valid parent、LGTM markerなし | 1737 / 10 / 10 | 778 / 0 / 0 | 未レビューreportをcompletion通知可能にする | keep |
| report-deny false positive | quoted example text `example > queue/reports/demo.yaml`（書込みなし） | 156 / 10 / 10 | 0 / 0 / 0 | 全撤去は実writeも許す。引用/非実行文字列だけ除外する狭い修正なら品質差0 | narrow, do not delete |
| opsim mandatory | draft review、観測あり、`operational_simulation`なし | 96 / 10 / 10 | 816 / 0 / 0 | 候補側816msはYAML parse stand-inを含むためCPU短縮値ではない。形式欄の欠落だけで配送を止めなくなる。artifact/approval/commit境界は不変 | delete mandatory BLOCK |

単回平均の現行摩擦は順に 83.7ms、173.7ms、15.6ms、9.6ms。安全にそのまま削除可能なのは opsim mandatory BLOCK の 9.6ms/試行。report-denyは全削除不可だがquoted-text除外なら15.6ms/該当試行を回収できる。従って品質差0の削減可能合計は **25.2ms/該当レビュー試行**（直接CPU wall）。さらに両候補とも偽BLOCK時の通知欠落を 1→0/試行にできるため、再実行待ち時間は別途全量削減される。

## Irreversible-harm check

- 実験は`/tmp` fixtureのみで、production queue/log、承認marker、本体コードの変更0件。
- parent mismatchとapproval markerはcommand/report/人手承認の構造境界なので維持。
- report-denyは直接write防止を維持し、非実行のquoted exampleだけを判定外にする候補。
- opsim欄の強制はレビュー作文の表示型条件であり、削除してもreport fingerprint、parent boundary、LGTM/ACCEPT、commit identityは残る。

## Binary conclusion

- AC1: 4/4再現、各10回、wall/BLOCK/通知欠落を取得: yes
- AC2: 実験による不可逆害0、削除可能1件・狭域修正可能1件、品質差と合計25.2msを算出: yes
