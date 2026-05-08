# スキル自動成長 4段階監査結果

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-06
- 殿指示: 「スキルの自動成長は順調か確認せよ」

## 4段階+監査 稼働状況

| 段階 | 名称 | 稼働 | データ | 判定 |
|------|------|------|--------|------|
| 0 | 依存先定期監査 | **未検出** | gate_skill_quality.shに依存先チェックなし | 要確認 |
| 2 | 帰属精度 | 部分 | skill_execution_log.yaml 192件 | **誤帰属問題あり** |
| 3 | 手順自動改善 | 健全 | preflight_autolearn.txt 109件 | TOP: ac_param_sufficiency(65回) |
| 4 | 品質計測+gate | 健全 | 38スキル PASS 17(45%) | FAIL4+WARN24 |

## 段階2 誤帰属問題（最重要発見）

### 現象
- report-write: 33回全FAIL(100%)
- verdict-check: 8回全FAIL(100%)
- cmd-complete: 5回全FAIL(100%)

### 真因
gate FAIL → 当該スキルに自動帰属。しかし実際は**忍者がスキルを使わずに手動作成→フォーマット不備**がFAILの原因。

### stumbling_points例
```
files_modified: MISSING; lessons_useful: MISSING; purpose_validation: MISSING
```
= report_field_set.sh(report-writeスキルのコア)を経由していない

### 影響
quality_metricの計測値が汚染。report-writeスキルの品質は実際にはPASS(使えば動く)だが、未使用FAILが帰属されて100%FAILに見える。

### 修正案
skill_execution_log記録時に2段階帰属:
1. **スキル使用FAIL**: スキルが実際に呼び出された後のFAIL → スキルの手順改善対象
2. **スキル未使用FAIL**: gate FAIL + スキル未使用 → 忍者の行動改善対象（スキル使用を強制するgate化）

## 段階4 FAIL/WARN詳細

### FAIL 4件
| スキル | 原因 |
|--------|------|
| cdp-browse | フロントマターに`<>`検出(argument-hintの`<url>`) |
| shogun-all-codex-switch | What/NOT_When不足 |
| shogun-peacetime-rollback | What/When/NOT_When全不足 |
| weekly-report-writer | What/When/NOT_When全不足 |

### WARN 24件（主要パターン）
- allowed-tools未定義: 16件（最小権限原則未設定）
- What不足: 5件（description内にWhat記載なし）

## 段階3 autolearn TOP5

| チェック名 | 回数 | 意味 |
|-----------|------|------|
| ac_param_sufficiency | 65 | AC内のパラメータ不足 |
| ac_phase_mixing | 9 | AC内にimpl動詞混入 |
| q11_existing_alternative | 8 | 既存代替の確認不足 |
| new_file_structure | 8 | 新規ファイル構造警告 |
| command_steps_vs_ac | 3 | commandステップ>AC数 |

→ 将軍のcmd設計が累計昇格で学習中。ac_param_sufficiency 65回は頻出だが最近の出現率を確認すべき。
