# 報告YAMLボトルネック分析 (2026-04-29)

殿指摘: 「忍者が報告YAMLを書くのに手間取る事が多くボトルネックになっている」

## 定量データ

| 指標 | 値 |
|------|-----|
| 初回PASS率 | 77.8% (119/153) |
| リトライ要 | 22.2% (34/153) |
| MISSING(フィールド欠落) | 16.7% (7/42 FAIL) |
| FORMAT(記入ミス) | 83.3% (35/42 FAIL) |

## FORMAT FAIL詳細パターン

| パターン | 件数 | 割合 | 根因 |
|---------|------|------|------|
| lessons_useful不正 | 67 | 38% | 10件×reason記入の手間 |
| check文面プレースホルダ残存 | 61 | 34% | GP-133がカバーしきれないAC |
| result不正値 | 16 | 9% | 'yes'クォート問題 → **修正済み(commit 4bc83b4f)** |
| verdict/status/lesson_candidate | 25 | 14% | 基本フィールド |

## 因果鎖

忍者がbinary_checksを手書き → ACごとにcheck/result構造化記入 → 記入ミス/構造破壊 → gate FAIL → retry → 時間消費

## 対策状況

### 実施済み
- **quote正規化**: `'yes'`→`yes` autofix追加 (commit 4bc83b4f) → 16件/42 FAIL削減

### 提案済み(将軍判断待ち)
1. **lessons_useful簡素化**: useful: falseのデフォルトreason`'未参照'`をgate許容 → 67件削減
2. **reason雛形pre-fill**: 教訓summaryからreason雛形自動生成 → 忍者はtrue/false切替のみ
3. **GP-133パース改善**: AC checksフィールドからcheck文面取得 → 61件削減

## 期待効果

| 対策 | 削減FAIL件数 | 初回PASS率改善 |
|------|-------------|---------------|
| quote正規化(実施済み) | ~16件 | 77.8% → ~83% |
| lessons_useful簡素化 | ~67件 | → ~90%+ |
| GP-133改善 | ~61件 | → ~95%+ |
