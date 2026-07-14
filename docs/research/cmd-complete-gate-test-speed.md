# cmd_complete_gate Unit 高速化

対象: [[test_cmd_complete_gate.bats]] / 被テスト: [[cmd_complete_gate.sh]]

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | 111 testのmaster project複製をreflink優先にする | `setup`が毎回tree全体を`cp -a`しており、反復I/Oの支配項候補 |
| 2 | helper抽出の40回超の`sed`を単一process化する | `setup_file`で一度だけだがprocess起動が連続する |
| 3 | 実gate起動testの共通script依存をmaster fixtureへ移す | test内個別`cp`が残りfixture責務が分散 |

## 守る契約

- testごとの書込み隔離を維持し、hardlink共有は使わない。
- `scripts/cmd_complete_gate.sh` の判定条件と111 testの期待値は変更しない。
