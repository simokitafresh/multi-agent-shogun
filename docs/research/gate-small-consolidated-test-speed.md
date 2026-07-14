# gate-small-consolidated-test-speed

origin: [[cmd_training_test_speed_test_gate_small_consolidated__20260715001204]] -> [[repeated-nested-bats-startup]] -> [[gate-small-consolidated-test-speed]]

## 結論

[[test_gate_small_consolidated.bats]] は27 wrapperごとではなく、9 embedded sourceごとにnested Batsを一度だけ実行する。flock single-flight内でTAPを生成し、tmp→mvで公開後、各wrapperが自身の正確なtest名の`ok`行を検証する。

## 契約

- outer 27件とembedded test本文・期待値を維持する。
- cache生成はcontent function単位のflockで直列化し、不完全TAPを公開しない。
- 通常実行と`bats -j 8`の双方でFAIL 0 / SKIP 0を要求する。

## 未採用の改善候補

1. base64 embedded sourceを生成時に圧縮し、decode I/Oを削減する。
2. consolidation generatorに本cache runnerを組み込み、生成物の後付け修正を不要にする。
