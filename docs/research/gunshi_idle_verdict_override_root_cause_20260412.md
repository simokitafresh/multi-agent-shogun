# verdict_override根因分析 — 5件の共通パターン特定

## 結論
verdict_override 5件の共通根因: **AC binary_checkが構造的例外のない絶対条件として設計されている**。
忍者は正しくno判定→FAIL→家老がoverride=負の複利(10回繰返し=10回override)。

## 5件内訳

| # | cmd | 根因 | 対処状況 |
|---|-----|------|---------|
| 1 | (L855) | AC推奨/必須混入 | GP-173 ★implemented |
| 2 | (L967) | gitignore対象commit | review_log header |
| 3 | cmd_1817 | 当月データ差(取得日差6日) | **未対処→原理追加** |
| 4 | cmd_1821 | 研究output commit(outputs/) | review_log header |
| 5 | cmd_1855 | 全期間+進行中月 | **未対処→原理追加** |

## 因果鎖

```
AC文面が絶対条件(「全期間」「100%」「全ファイル」)
  → 構造的例外(gitignore/outputs/進行中月/推奨vs必須)未考慮
  → 忍者がyes/noで二値判定 → 正しくno
  → FAIL
  → 家老override
  → workaround記録
  → 負の複利
```

## 対処

### 既実施 (3/5件カバー)
- GP-173: cmd_save.shにAC推奨/必須混在検出WARN (Level 3)
- review_log header: "AC commit check → gitignore/outputs/除外設計確認" (Level 2)

### 本分析で追加 (残2/5件カバー)
- review_log header: "AC絶対条件→構造的例外の有無を確認。例外あれば除外条件をAC文面に明示" (Level 2)
- cmd_1860 LG001違反: "既実装判定→git show HEAD~1で変更前状態確認" (Level 2)

### 未対処の深層
残り2件(#3,#5)はDM-Signal固有の「進行中月」パターン:
- GS CSV作成日と本番更新日の差異で進行中月のデータが異なる
- 「全期間」=完了月+進行中月だが、進行中月は構造的に不一致
- 対策: パリティ/研究cmdで「monthly_return差」AC使用時は「完了月のみ」除外条件をデフォルト化
- これはcmd設計者(将軍)の知識。checklist等に追記候補

## 設計書作成日
2026-04-12T00:30:00+09:00 — gunshi idle self_study S166
