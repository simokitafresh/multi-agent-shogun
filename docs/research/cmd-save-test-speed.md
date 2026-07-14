# cmd save test speed

## 改善候補

| 優先 | 対象 | 根拠 |
|---|---|---|
| 1 | `tests/unit/test_cmd_save.bats` の関数抽出 | [[cmd_save.sh]]を80回の`sed`プロセスで読み直しており、抽出対象を1回の走査へ束ねれば反復process起動を除去できる。 |
| 2 | 同ファイルの追加scratch root | setup_fileの共有root導入後も6テストが8回`mktemp`を起動しており、テスト番号付きsubdirで隔離できる。 |
| 3 | 同ファイルのYAML fixture | 類似するquality_gate/assumptionsブロックが反復し、共通builderで生成量を削減できる。 |

最高インパクト候補1を実装し、[[test_cmd_save.bats]] の単純関数抽出を80回から1回の`sed`走査へ統合した。実行対象と抽出元は正本パスのままとし、128件の期待値と異常系契約を維持する。
