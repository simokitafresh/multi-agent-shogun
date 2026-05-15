# 学習ループ自動成長の構造的穴 — なぜなぜ7回
<!-- generated: 2026-05-15T10:35:00+09:00 by gunshi なぜなぜ7回 (殿指示) -->

## 問い

「学習ループの自動成長に構造的な穴はないか？」

## 発見: 3つの構造的断裂

### 断裂1: auto_failure_lesson.sh が孤立（最重要）

**現物**: `grep -rn 'auto_failure_lesson' scripts/ | grep -v 'auto_failure_lesson.sh:'` → 0件
**意味**: FAIL記録(gate_fire_log)は自動だが、FAIL→教訓生成のスクリプトを誰も呼ばない
**対比**: auto_draft_lesson.shはcmd_complete_gate.sh L3545で呼ばれている。auto_failureだけ未接続

パイプラインの現状:
```
gate_fire_log.yaml ← FAIL記録 (自動 ✓)
       ↓
auto_failure_lesson.sh ← 呼出元なし (断裂 ✗)
       ↓ (到達しない)
lesson_write.sh ← 登録されない
```

### 断裂2: 修行サイクルに自動トリガーなし

**現物**: `grep -n 'training' scripts/ninja_monitor.sh` → 0件
**意味**: idle忍者への修行配備は家老の手動判断依存
**設計書**: context/training-cycle.md に手順記載あるが自動実行なし

### 断裂3: FAIL→PASS遷移の定期計測なし

**現物**: gate_shogun_startup.shのL6セクションが起動時のみ計測
**意味**: 将軍が/clearしないと遷移率が更新されない。将軍の/clear間隔に依存

## なぜなぜ7回（断裂1を深堀り）

| 回 | なぜ | 現物証拠 |
|----|------|---------|
| 1 | auto_failure_lesson.shは存在するのに呼ばれないのはなぜか | grep確認: 呼出元0件。スクリプトは241行(実測)あり機能する |
| 2 | なぜ呼出元が実装されていないのか | cmd_2667(confirm)で「動作確認」は完了したが「統合」は別ステップ |
| 3 | なぜ「確認」で止まり「統合」に進まなかったのか | ACが「スクリプトが正しく動作すること」で完結。「パイプラインで自動呼出されること」がACに不在 |
| 4 | なぜACに「統合」が含まれなかったのか | 将軍がcmd設計時に「作る」と「接続する」を分離し、後者のcmdを起票し忘れた |
| 5 | なぜ起票し忘れたのか | cmd完了時に「このスクリプトの呼出元は？」を検証するgateがない |
| 6 | なぜパイプライン接続検証gateがないのか | 個々のスクリプト品質はgate保証(bats/format/commit)されるが、スクリプト間接続は検証対象外 |
| 7 | **根因**: なぜスクリプト間接続が検証されないのか | **growth-loop.mdにパイプラインの「接続仕様」が定義されていない。設計図はあるが接続テストがない。** |

## 根因

**学習ループのパイプライン設計図(growth-loop.md §10)は「何が存在すべきか」を定義しているが、「何が何を呼ぶか」の接続仕様を定義していない。**

個々のスクリプトは:
- コードが正しい(batsテスト) ✓
- フォーマットが正しい(gate_report_format) ✓
- commitされている(PRE3) ✓

しかし**パイプラインとして繋がっている**ことを検証するgateがない。
結果: スクリプトは作られるが呼ばれない「孤立スクリプト」が発生する。

## 対比: 接続が成功しているケース

| スクリプト | 呼出元 | 統合時期 |
|-----------|--------|---------|
| auto_draft_lesson.sh | cmd_complete_gate.sh L3545 | cmd_2613で統合 |
| skill_auto_improve.sh | ninja_monitor.sh L3678 | check_skill_auto_improve()で統合 |
| gate_report_format.sh | cmd_complete_gate.sh L1337 | 初期から統合 |

成功ケースは「呼出元が明示的に実装」されている。失敗ケース(auto_failure_lesson)は呼出元が実装されていない。

## 因果鎖

```
パイプライン接続仕様の不在(根因)
  → スクリプト単体で完結するACが設計される
  → cmdは「作る→テスト→CLEAR」で完了する
  → 「呼ばれるか？」は誰も検証しない
  → 孤立スクリプトが放置される
  → 学習ループの一部が途切れる
  → FAIL→教訓生成が回らない
  → 同じFAILが繰り返される（免疫応答の断裂）
```

## 提案: 自動化ターゲット3つ

### 提案1: パイプライン接続テスト(最優先)

growth-loop.md §10の各ステップについて「呼出元が存在するか」をgrepで検証するgateを追加。
検証対象: auto_failure_lesson.sh / skill_auto_improve.sh / lesson_write.sh 等、パイプライン上のスクリプト。
存在しない呼出元 → ALERT。

### 提案2: auto_failure_lesson.shの統合

cmd_complete_gate.shまたはninja_monitorにauto_failure_lesson.shの呼出しを追加。
トリガー: gate_report_format.sh FAIL時 or FAIL報告受信時。

### 提案3: 修行サイクル自動トリガー

ninja_monitorにidle忍者検出→修行タスク自動配備のロジック追加。
家老の手動判断依存を排除。

## 複利の問い

パイプライン接続テストを10回実行したら？ → 毎回、新規スクリプトの孤立を検出。孤立スクリプト0件が持続 = 正の複利。
auto_failure_lesson統合を10回実行したら？ → FAIL1件ごとに教訓1件自動生成。教訓蓄積速度が加速 = 正の複利。
