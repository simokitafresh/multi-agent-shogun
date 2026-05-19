# ACスコープ乖離 なぜなぜ7回 — 2026-05-19

## 現象
本セッションでFAIL判定2件が両方GATE CLEAR。

| cmd | FAIL理由 | CLEAR理由 |
|-----|---------|----------|
| cmd_karo_regex_order_fix | AC2 sqlite3不在→bats FAIL | 家老環境で全PASS確認 |
| cmd_2856 | AC4 gate_startup 5.3秒>5秒 | 200件以下は達成。5秒はscope外 |

## なぜなぜ7回

1. **なぜFAILがGATE CLEARされた？** → 家老がscope分離判定でCLEAR
2. **なぜWA記録がFAILより前？** → 家老はGATE前にclean記録→GATE並行起動
3. **なぜ家老がclean判定？** → 実装品質に問題なし。FAILは環境制約
4. **なぜac result:noでCLEAR可能？** → 家老権限でBLOCK後waive(scope外判断)
5. **なぜ「scope外」でCLEARが許される？** → 消火ではなくscope分離。目的は達成
6. **なぜACにscope外条件が含まれる？** → **AC設計時に忍者制御範囲を検証していない**
7. **なぜdraft reviewで検出できなかった？** → Step 3「実行可能性」は見るが「scope内完結性」は観点にない

## 根因
**ACに忍者のscope外条件を含める設計パターン**。忍者が制御できない環境要因(外部依存/他スクリプト速度)がACに混入→正確な実装でもFAIL→家老waive→FAILが形骸化。

## 自動化ターゲット
draft review Step 3に「ACの全条件が忍者scope内で完結するか」の観点を追加。

検出パターン:
- 速度目標AC + 対象外スクリプトが律速 → scope外
- 全量テストAC + 環境依存テスト → scope外(sqlite3等)
- 本番確認AC + 本番アクセス権限なし → scope外

対処: REQUEST_CHANGES(severity: normal)。AC条件を忍者制御可能範囲に限定するか、環境前提をACに明記。

## 因果チェーン
```
AC設計時にscope外条件混入
  → 忍者が正確実装してもFAIL
  → 家老がscope分離でwaive CLEAR
  → FAIL判定が形骸化
  → 軍師FAILの信頼性低下(FAILでも結局CLEAR)
  → draft review Step 3にscope内完結性の観点追加で検出可能
```

掲示板: 将軍cmd候補(Step 3観点追加)
