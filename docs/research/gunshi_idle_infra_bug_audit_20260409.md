# インフラバグ監査 — 2026-04-09 軍師分析

## 調査手法
karo_workarounds.yaml全127件のcategory集計 → パターン分析 → 現物コード照合

## 現存バグ（未修正）

### ~~Bug 1: gate_report_format.sh — assigned_acs未対応~~ (修正済み)
- **状態**: 修正済み。gate_report_format.sh L127-131, L234-269, L309-310でassigned_acs対応実装済み
- **確認**: 2026-04-09 grep assigned_acs gate_report_format.sh → 11箇所で対応済み

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
