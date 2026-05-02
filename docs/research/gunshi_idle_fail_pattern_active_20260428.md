# 軍師idle分析: 現行FAIL パターン分析 (2026-04-28)

## 目的
gate_fire_logからarchive報告を除外し、現行運用での忍者FAILパターンTop10を特定。
将軍consultationへの補足データ。

## 方法
`grep -v 'archive/' gate_fire_log.yaml | grep 'result: FAIL'` → reasons分解 → カテゴリ集計

## 結果 (非archive FAIL、カテゴリ別件数)

| # | カテゴリ | 件数 | 主パターン |
|---|---------|------|-----------|
| 1 | lesson_candidate | 95 | no_lesson_reason/found:true but empty |
| 2 | lessons_useful[0] | 92 | FILL_THIS残存/不正値 |
| 3 | binary_checks.AC1[0].result | 82 | 'yes'(引用符付)/FILL_THIS |
| 4 | lessons_useful[1] | 74 | FILL_THIS残存 |
| 5 | lessons_useful[2] | 65 | FILL_THIS残存 |
| 6 | verdict | 46 | 空文字/None |
| 7 | lessons_useful(全体) | 34 | null/empty list |
| 8 | assumption_invalidation | 29 | MISSING/affected_cmds空 |
| 9 | binary_checks(全体) | 23 | MISSING |
| 10 | binary_checks.commit | 21 | FILL_THIS |

## 分析

### 最大問題: lessons_useful (265件合計)
- FILL_THIS残存が支配的。テンプレートにFILL_THISプレースホルダが注入されるが忍者が埋めない
- gate既にBLOCK→忍者がretryで修正。免疫は機能している
- **改善案**: FILL_THISの代わりにデフォルト値(false + 具体的理由ヒント)を注入し、忍者の記入負荷を下げる

### 第2問題: binary_checks result (103件)
- `'yes'`(シングルクォート付)がBLOCK。autofix GP-087で`'yes'`→`yes`変換済み
- FILL_THIS残存も含む
- **状態**: autofix既に対処済み。残存はautofix適用前のretry1回目

### 第3問題: verdict (46件)
- 空文字/None。テンプレートが`verdict: ""`で生成される
- **改善案**: テンプレートをverdict: FILL_THISに変更→忍者が明示的に記入

### assumption_invalidation (29件)
- archive除外後は29件。テンプレートは既に実装済み(L1340-1343)
- 直近は他フィールドも含む全体欠損ケースが主

## 結論
1. lessons_useful FILL_THIS残存(265件)が最大ボトルネック
2. gate BLOCKは正常に機能(免疫応答OK)
3. 改善方向: テンプレートの記入しやすさ向上(FILL_THIS→具体的ヒント)
4. 新規gate不要。既存gate_report_format.shで十分
