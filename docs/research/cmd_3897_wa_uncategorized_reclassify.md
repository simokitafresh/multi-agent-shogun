# cmd_3897 WA uncategorized再分類

## 結論

`variation_checks`・報告証跡不足を `report_yaml_format::verification_evidence` へcanonical分類し、`uncategorized::general`への流入を防止した。再分類helperは同一cmd内の異根を巻き込まないようdetail条件を受け、root signatureを原子的に更新・追加する。

## 対応表

| cmd_id / 本文根拠 | 変更前 | 変更後 | 判断根拠 |
|---|---|---|---|
| `cmd_reflux_insight_202607080247_hanzo` / staging広域差分混入→scope限定commit | `uncategorized` / 署名なし | `commit_scope_contamination::commit_provenance` | 報告形式ではなくcommit scope/provenanceの破れ |
| `cmd_karo_ci_fix_infra_unit_fullsuite_rc2_202607140015` / commit_hash欠落 | `report_yaml_format::schema_shape` | 同左 | schema証跡の欠落でありvariation根因と分離 |
| 同cmd / variation 0/5→5/5、precheck ERRORS 1→0 | `report_yaml_format::general` | `report_yaml_format::verification_evidence` | 5セル実施証跡の欠落 |

## 計測

- 台帳 `uncategorized`: 1→0件。
- 対象単体suite: 45/45 PASS、FAIL 0、SKIP 0。
- 同一cmdの一括再分類で異根を巻き込む挙動を実測し、detail条件付きhelperへ即時調整した。
- `auto_captured`系は `cmd_complete_gate.sh` が `category: rework_auto_capture` を明示して記録するため、現行経路に分類fallbackは存在しない。手動記録経路の未分類WARNは隔離fixtureで確認する。

## 因果

`[[variation_checks証跡欠落]] -> [[uncategorized受け皿集約]] -> [[偽の復活検出とCRITICAL escalation]]`
