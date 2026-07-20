# Atomic integration latency retro (2026-07-20)

## 結論

対象commitの親/結果blobから最小fixtureを作り、3候補×3反復をisolated cloneで全実験した。品質差分は全9件0。最速はcherry-pick平均97.7ms（93/99/101ms）であり、単一LGTM commit・競合なしの統合境界では現行方式を維持する。

| 候補 | 平均wall_ms | subprocess/回 | retry | scope外 | blob不一致 | 親不一致 |
|---|---:|---:|---:|---:|---:|---:|
| cherry-pick | 97.7 | 1 | 0 | 0/3 | 0/3 | 0/3 |
| blob + private index | 148.3 | 7 | 0 | 0/3 | 0/3 | 0/3 |
| patch + private index | 228.3 | 8 | 0 | 0/3 | 0/3 | 0/3 |

raw receipt: `/tmp/hanzo-integration-fixture.D86mbI/results.tsv`。driverの列投入でrawの`retries`列にpaths=1、`paths`列にretries=0が入ったため、表では意味を補正した。tree_match/parent_okはrc表現で0=一致。

## Phase分解

| phase | 実測/観測 | subprocess | retry |
|---|---:|---:|---:|
| 前提確認（object/ancestor/operation state） | 完了 | 7 | 0 |
| 統合cherry-pick | 97.7ms平均 | 1 | 0 |
| wave probe | 1.3s（cold/warm/change/race/missing一括） | producer cold/warm=1、race=1 | 0 |
| deploy contract | 26.2s | bats 44 cases | 0 |
| report gate | 6.0s | batch setter+gate | 0 |
| scope commit | 本retroで別計測 | helper 1回 | 0 |

未計測phaseは0。全体の支配項は44件contract（約26.2s）で、統合方式差（最大約131ms）は小さい。品質検証を削らず速度を上げる候補はcontract内部の重複fixture削減であり、本retroのscopeでは実装しない。

## 適用境界

- 単一LGTM commit・競合なし: cherry-pickが最速。
- hunk選別が必要: patch + private index。ただし本計測では約2.34倍。
- 既知blobを単一pathへ配置する生成系: blob + private index。ただし通常統合ではcommitの意味を失うため採用しない。
- 競合時は自動解決せず停止する既存契約を維持する。

