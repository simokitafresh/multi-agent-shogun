# Guard14 DB trust-boundary Unit 高速化

対象: [[test_pre_bash_guard14_db_trust_boundary.bats]] / fast-filter同期: [[test_pre_bash_guard14_fast_filter_sync.bats]] / 分類器: [[guard14_db_trust_classify.py]] / shell正本: [[guard14_db_trust_classify.sh]]

## 改善候補

| 優先 | 改善点 | 根拠 |
|---|---|---|
| 1 | classifier単体testの中間bash processを除去 | `_classify`全呼出しが`bash -c`を経由してからPythonを起動していた |
| 2 | hook経由testとclassifier単体testの重複fixtureを表形式化 | 同一commandを別testで再分類する組が多数ある |
| 3 | 不変のclassifier compile/cacheを共有 | 全caseで同一Python sourceをparseするがprocessごとに再実行される |
| 4 | fast-filter正本関数をfile fixtureで一度だけsource/export | 同期test 24件が同じ抽出済み関数を使うのに、各assertionで`bash -c`を再起動していた。実測4.220→4.344秒で短縮せず不採用 |

## 守る契約

- `COMMAND`は環境変数で同値に渡し、分類器のcanonical root判定を変更しない。
- hook経由とclassifier単体の二層検証、FAIL 0、SKIP 0を維持する。
