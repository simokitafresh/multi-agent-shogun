# infra-misc-small consolidated test speed

## 結論

同一embedded suiteをtestごとに再展開せず、run単位の共有cacheへ一度だけ展開する。42 testのfilter・nested Bats・FAIL0/SKIP0契約は維持する。

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | embedded suiteの展開結果を共有cache化 | `run_embedded_test` は同じcontent関数をsuite内のtest数だけbase64 decodeしていた |
| 2 | nested Batsプロセス起動の集約 | timingでは各embedded testが約0.5–1.2秒で、42件中37件がnested Batsを起動する |
| 3 | 直接grep testを単一shellへ集約 | 冒頭5件は各47–83msで、独立した`bash -c`起動が支配的 |

## 設計根拠

[[training-cycle]] §26の「テスト速度最適化」方針に従う。対象文書の記述は「修行ネタをテスト速度最適化に変更」であり、対象縮小ではなく道具を高速化する。

## 計測

- 台帳baseline: 27.442秒、42/42、FAIL 0、SKIP 0、jobs=8
- 変更直前再計測: 8.87秒、42/42、FAIL 0、SKIP 0、jobs=8
- 変更後: 8.17秒、42/42、FAIL 0、SKIP 0、jobs=8（直前8.87秒比7.9%短縮、台帳27.442秒比70.2%短縮）
