# cmd_complete_gate Unit 高速化

対象: [[test_cmd_complete_gate_subsystems.bats]] / 被テスト: [[cmd_complete_gate.sh]] / 計測: [[run_timed_bats.sh]]

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | helper抽出を単一awk走査にする | 15関数の抽出に約36回の`awk`/`sed`を起動していた |
| 2 | testごとの一時fixture生成を共有原型+copy-on-writeへ寄せる | 27 testが個別にディレクトリとfixtureを生成している |
| 3 | `grep` assertionをBats組込み比較へ寄せる | test内の短い出力確認でも外部process起動が残る |

## 守る契約

- testごとの書込み隔離を維持し、hardlink共有は使わない。
- `scripts/cmd_complete_gate.sh` の判定条件と27 testの期待値は変更しない。

## 実装

- `setup_file`のhelper抽出を36前後のprocess起動から単一`awk`へ集約した。
- リンク先 [[test_cmd_complete_gate_subsystems.bats]] の `setup_file` は、抽出対象を`wanted`集合として定義し、被テストscriptを1回だけ走査する。
- [[run_timed_bats.sh]] は実行時間を算出し（21行目）、PASS/SKIPを含む結果を台帳へ原子的に渡す（30-33行目）。
