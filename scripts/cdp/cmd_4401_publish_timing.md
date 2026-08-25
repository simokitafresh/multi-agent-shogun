# cmd_4401 publish外側経路計測

計測日: 2026-08-25
計測対象: `scripts/cmd_publish.sh`
台帳: `logs/defense_overhead.jsonl`（fixtureでは一時ledgerへ出力）

## AC1: 段別wall時間

`cmd_publish.sh` に `preflight` / `save_gate` / `promotion` / `delegate` / `publish_total` を追加し、成功・失敗の両方で既存 `defense_overhead` writerへ記録する。

成功fixture（save/delegateはbash stub、queueは隔離YAML）の1回実測:

| phase | wall_ms | verdict |
|---|---:|---|
| preflight | 2359 | PASS |
| save_gate | 147 | PASS |
| promotion | 1055 | PASS |
| delegate | 194 | PASS |
| publish_total | 3770 | PASS |

この条件では `preflight` が最大段（2359ms、publish_totalの62.6%）だった。計測は `ledger5` の `source=cmd_publish` 行を一次集計した。

## AC2: 支配段の短縮

支配段の内訳を確認すると、missing `depends_on` / `origin` の2項目を2回のsetterで更新していた。既存の正規 `yaml_field_set_batch`（flock・atomic publish・事後検証）へ1回のbatch更新として統合した。

同一fixture・同一条件のpreflight比較:

| 実装 | preflight_ms | 差分 |
|---|---:|---:|
| before（旧2回setter、ledger2） | 2573 | — |
| after（1回batch setter、ledger5） | 2359 | -214ms (-8.3%) |

検査項目・判定・YAML書込みの安全経路は削除していない。対象batsは4/4 PASS、SKIP0。
