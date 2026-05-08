# インフラバグ3パターン分析(殿指示: 忍者ミスの裏にインフラバグ)

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-02
- 起源: 殿「他にインフラバグはないか？忍者のミスの裏にはインフラバグがある」
- 手法: karo_workarounds.yaml 102件WA全数分析 + LG014適用

## パターン1: yaml_field_set.sh binary_checks list構造破壊

| 項目 | 値 |
|------|-----|
| WA件数 | 2件 |
| 最終発生 | 2026-04-26 hanzo cmd_karo_ci_fix_env_change |
| 修正状況 | **未修正**(2026-04-26以降変更なし) |

### 根因
yaml_field_set.shがbinary_checks内のlist item(`- check: ...`)に対して、mapping block形式でresultを挿入。YAML構造が壊れ、report_field_set.shでのパースが不可能になる。

### 影響
- 報告YAML→GATE BLOCK→家老がsed手動修正

### 修正方針
yaml_field_set.shのlist item内フィールド書込みロジック見直し。binary_checksの`- check:`/`result:`構造を正しく認識する必要。

## パターン2: commit禁止cmdにcommit check自動注入

| 項目 | 値 |
|------|-----|
| WA件数 | 5件 |
| 最終発生 | 2026-04-17 hayate cmd_1997 |
| 修正状況 | **未修正** |

### 根因
deploy_task.sh L1534: `task_type != scout && != recon`の場合はcommit checkを注入。しかし:
- cmd制約で「commit禁止(将軍がpushする)」のケース
- outputs/配下のみ変更でcommit不要のケース
- DM-Signal repoにworkflowsなしのケース

これらでは`task_type=normal`だがcommit checkが不適切。

### 影響
- bc commit:no → GATE BLOCK → 家老がverdictオーバーライド(5件)

### 修正方針
deploy_task.shのcommit check注入部(L1534)でcmd制約(constraints/waive_ac)を参照し、commit関連制約がある場合はcommit_bc生成をスキップ。

## パターン3: 分割配備で全AC binary_checks注入

| 項目 | 値 |
|------|-----|
| WA件数 | 2件 |
| 最終発生 | 2026-04-19 hanzo cmd_2153 |
| 修正状況 | 部分修正(ac_filterは実装済み) |

### 根因
`ac_assigned`フィールドがtask YAMLに未設定→ac_filter空→全ACのbinary_checksがtemplate注入。分割配備で忍者が担当しないACもbc templateに入り、result:noでGATE BLOCK。

### 修正方針
分割配備(chunk task_id)時、deploy_task.shがac_assignedを自動設定する。chunk task_idからAC IDを推定し、未設定の場合はWARN+自動補完。

## 優先度

| 順位 | パターン | 理由 |
|------|---------|------|
| 1 | commit check誤注入(5件) | 発生頻度最高。家老のverdict_override WA 9件中5件がこの原因 |
| 2 | yaml_field_set list破壊(2件) | 報告YAML破壊→パース不可。影響が大きい |
| 3 | 分割配備全AC注入(2件) | ac_filter部分実装済み。残件は自動補完のみ |

generated: 2026-05-02T22:11:00+09:00
trigger: 殿直接指示
