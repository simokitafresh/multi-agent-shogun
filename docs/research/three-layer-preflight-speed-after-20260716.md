# three_layer_preflight.sh CoDD After設計書

## 現在の構造

- `batch_index_search`: 実checkoutでmemory ext4 atomic snapshotとsemantic indexを1 Python processで一括readする。custom DB・cache欠落・破損は非0rc。
- `obsidian_cached_search`: 正規 `scripts/lib/causal_index.sh` の全 `[[link]]` 逆索引を利用する。
- `issue`: 上記2laneを並列実行し、三層rcを個別回収後、nonce一致時だけatomic publishする。
- isolated rootは従来の `memory_db_query.sh` / `semantic_search.sh` / rg経路を維持する。

## 二巡計測

| 巡 | baseline | after | p50 | p95 | timeout | superseded | 三層一致 |
|---|---|---|---:|---:|---:|---:|---:|
| 1 | 旧3 CLI | memory+semantic batch | 1621→981.5ms | 4504→1794ms | 0 | 0 | 20/20 |
| 2 | 巡1 after | causal index cache | 981.5→225.5ms | 1794→254ms | 0 | 0 | 20/20 |

第2巡20回raw: 206, 209, 212, 214, 216, 216, 220, 222, 223, 224, 227, 229, 235, 235, 239, 239, 244, 246, 254, 354ms。

## 層別SLO

- warm総wall: p50 < 500ms、p95 < 1000ms。
- global hard deadline: 9500ms未満。
- timeout=0、逐次run superseded=0、成功証跡の三層rc一致=100%。
- 関連Bats: FAIL=0、SKIP=0。

## cache invalidation

- memory: `memory_db_cache.sh` のsingle-flight生成、private temp検証、`os.replace` atomic snapshotを読む。cache不在時はcanonical/legacy laneへfail-safeする。
- semantic: canonical `docs/semantic-index/index.md` を毎回openするためquery-result cacheを持たない。
- Obsidian: `causal_index.sh build` のTTL（既定300秒）で再生成し、temp→mvで公開する。`THREE_LAYER_CAUSAL_INDEX_CACHE`でfixture隔離可能。
- cache生成失敗・deadline超過時は既存fallbackへ進み、成功へ偽正規化しない。

## generation競合と再劣化試験

- `同一paneの並行issueは固有tempで世代整合しverify可能`: 成功1、superseded3、旧証跡復活0。
- `slow A is superseded by fast B and cannot resurrect old proof`: A=75、B=0、old proof PASS=0。
- timeout fixture、DB/index欠落・破損、一層失敗、空promptをfail-closedで固定。
- `tests/unit/test_three_layer_preflight.bats`: 33/33 PASS、FAIL=0、SKIP=0。

origin: [[per-prompt-process-and-index-reload]] -> [[batch-index-and-causal-cache]] -> [[UserPromptSubmit-p95-254ms]]
