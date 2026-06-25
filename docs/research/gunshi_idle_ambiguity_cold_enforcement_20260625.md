# Ambiguity冷え観点 L4強制化 + 遡及適用
<!-- generated: 2026-06-25T16:58:34+09:00 by gunshi idle analysis -->

## 問題

startup gate WARN: 11件のdraft/reportでfinding_categoriesにambiguity(冷え観点)が未反映。
gate_gunshi_cs_checklist.shが検知するがWARNのみ→意志依存→記録漏れが継続。

## 真因分析

| 層 | 状態 | 問題 |
|----|------|------|
| 検知 | gate_gunshi_cs_checklist.sh | WARN出力のみ。BLOCKしない |
| 記録 | gunshi_log_append.sh | adversarial必須チェックあり。**ambiguity必須チェックなし** |
| 行動 | レビュー時 | ambiguity確認は実施するが記録が意志依存 |

根因: adversarialはL4(BLOCK)で強制されていたが、ambiguityはL2(WARN)に留まっていた。
deepdive Phase 4「理解だけでは行動は変わらない。自動化×強制」の再発構造。

## 修正内容

### D0-1: gunshi_log_append.sh ambiguity必須BLOCK追加
- L55後にambiguityチェック追加(adversarialと同構造)
- draft/reportでambiguityがfinding_categoriesに含まれない場合exit 2(BLOCK)
- 修正規模: 4行追加

### D0-2: テスト更新(test_gunshi_log_append_obs.bats)
- 既存OKテスト2件にambiguity追加(BLOCKされないように)
- 新規テスト1件追加: ambiguityなし→BLOCK exit 2
- テスト結果: 10/10 PASS

### 遡及適用: review_log finding_categories修正
- 対象: 直近11件(冷えWARN検出分)のfinding_categoriesにambiguity追加
- 修正前: WARN 11件 → 修正後: WARN 0件

## 計測

| 指標 | 修正前 | 修正後 |
|------|--------|--------|
| 冷え観点WARN件数 | 11 | 0 |
| テストPASS率 | 8/8 | 10/10 |
| ambiguity L4強制 | なし(意志依存) | あり(BLOCK) |

## 因果リンク

- → [[LG013]] CS観点プロトコル不在の系譜
- → [[deepdive Phase 4]] 自動化×強制の適用
- → [[finding_categories回帰テスト]] 2026-06-24 D0でadversarial強制+テスト追加済み。今回ambiguityを同構造で追加
