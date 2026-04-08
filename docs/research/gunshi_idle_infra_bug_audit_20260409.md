# インフラバグ監査 — 2026-04-09 軍師分析

## 調査手法
karo_workarounds.yaml全127件のcategory集計 → パターン分析 → 現物コード照合

## 現存バグ（未修正）

### Bug 1: gate_report_format.sh — assigned_acs未対応
- **症状**: 分割配備で担当外ACのbinary_checks result=no → verdict-BC矛盾チェックがBLOCK
- **根因**: cmd_complete_gate.sh(L2648-2670)はassigned_acs対応済みだが、上流のgate_report_format.sh(L280-301)がassigned_acsを読まない
- **証拠**: cmd_1796 split_deploy_ac_scope 2回WA(kagemaru+tobisaru)
- **修正箇所**: gate_report_format.sh L280-301。task YAMLからassigned_acsを取得 → 担当外ACのresult=noをverdict矛盾チェックから除外
- **因果鎖**: deploy_task.sh全AC注入→gate_report未対応→担当外no→BLOCK→WA。×分割配備回数=負の複利

### Bug 2: recording_error — workaround記録時のシェル構文エラー
- **症状**: detail/root_causeが「(記録欠損: 呼出し構文エラー)」で空
- **証拠**: 127件中6件がrecording_error、うち2件が「構文エラーで未記録」
- **影響**: workaround分析データ品質低下
- **修正方針**: 記録スクリプトの引数quoting/パーサー修正

## 修正済み（再発なし確認）

| バグ | 最終発生 | 累計WA | 修正内容 |
|------|---------|--------|---------|
| ci_gate_mismatch | cmd_1760(04-06) | 13件 | LG015: HEAD~1→git log --grep=CMD_ID |
| stale_ac_contamination | cmd_1764(04-06) | 4件 | cmd_lk021_fix: STALE_FIELDSにAC追加 |
| ac_injection_failure | cmd_1606(03-30) | 2件 | ネスト形式AC変換修正 |

## 全体統計
- 全127件中 WA=true: 70件(55.1%)、WA=false: 57件(44.9%)
- Top3 category: clean(55), report_yaml_format(14), ci_gate_mismatch(13)
- ci_gate_mismatch: 修正済み(04-06以降0件)
- report_yaml_format: autofix対応で減少傾向
