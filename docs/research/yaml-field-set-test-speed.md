# yaml_field_set Unit 高速化

対象: [[test_yaml_field_set.bats]] / 被テスト: [[yaml_field_set.sh]]

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | BATS既定のtest固有directoryを直接使う | 各testで`mktemp`し、teardownで再帰削除する二重ライフサイクルがある |
| 2 | 検証用Python heredocを共通helperへ集約 | `yaml.safe_load`検証processとコードが多数testに分散する |
| 3 | CLI契約testと内部関数testをfixture単位で整理 | `bash yaml_field_set.sh`と`source`検証の重複起動がある |

## 守る契約

- `BATS_TEST_TMPDIR`によるtest単位の書込み隔離を維持する。
- YAML parse検証、flock競合検証、FAIL 0、SKIP 0を縮小しない。
