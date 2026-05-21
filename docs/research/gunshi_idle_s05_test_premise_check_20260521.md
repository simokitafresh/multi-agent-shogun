# S0-5 テスト前提更新確認追加 + CS WARN解消
<!-- generated: 2026-05-21T14:10:00+09:00 by gunshi idle analysis -->

## 概要

D0直接実装。2件の対処を実施:

1. **S0-5テスト前提更新確認**: MIN_SAMPLES 3→1変更(dce44607)時にテスト前提値を未更新→テスト2件FAIL→CI RED事故(2026-05-21)。karo掲示板blt_20260521_135856の指摘を受け、gunshi.md S0-5に閾値・デフォルト値変更時のテスト前提確認チェック項目を追加
2. **CS WARN解消**: review_log 15件のdraftエントリにambiguity_points: none遡及追記

## 因果鎖

```
MIN_SAMPLES変更(D0 dce44607)
  → テスト前提値(MIN_SAMPLES=3)のまま残存
  → batsテスト2件がFAIL
  → CI RED
  → karo掲示板で指摘
  → S0-5にチェック項目追加(事前検出層)
  → 同種CI RED予防 = 正の複利
```

## 変更内容

- `instructions/gunshi.md` L449: S0-5にデフォルト値・閾値変更時のgrep確認項目を追加
- `logs/gunshi_review_log.yaml`: 15件のdraftエントリにambiguity_points: none遡及追記(CS WARN→INFO降格)

## commit

f549c4e6
