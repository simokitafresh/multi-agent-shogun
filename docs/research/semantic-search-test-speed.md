# semantic-search-test-speed

- [[test_semantic_search.bats]] — 31件の独立性を保ちつつ、固定index fixtureとparsed-index cacheをfile scopeで共有する。
- [[semantic_search.sh]] — 被テスト本体。alias、memory DB、LLM、causal expansionの契約は変更しない。
- 因果: [[反復fixture生成]] -> [[index再parse]] -> [[semantic_search Unit遅延]]
