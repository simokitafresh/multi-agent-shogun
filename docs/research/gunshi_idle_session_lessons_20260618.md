# 軍師セッション知見 2026-06-18

## 成果1: 教訓universalタグ一括固有化

- **修正前**: universal=184件→全cmdに無差別注入→useful_rate 5.4%
- **修正後**: universal=29件(155件=84%除去)。lesson_write.sh --retagで140件+手動15件
- **残課題**: 29件はtagsフィールド不在の旧フォーマット→cmd_3433で修正済み
- **効果**: 次回配備以降にuseful_rate 30%+到達見込み(シミュレーション)
- **永続化**: docs/research/gunshi_idle_useful_rate_batch_retag_20260618.md
- **origin**: [[LG027]] -> [[universalタグ無差別注入]] -> [[155件固有化]]

## 成果2: インフラバグ発見→即cmd化

- **バグ**: lesson_write.sh --retagがYAML 1行形式(dm-signal旧教訓L007-L118)でFAIL
- **根因**: retagロジック(L568-589)がlessons.md Markdown形式前提
- **修正**: cmd_3433(kotaro)で旧フォーマット対応追加。GATE CLEAR
- **origin**: [[blt_20260618_005912]] -> [[lesson_write_retag_markdown前提]] -> [[cmd_3433_CLEAR]]

## 反省: SG-PRE25 ERROR vs GATE_PREDICTION CLEARの矛盾

- **事象**: cmd_3435/3437/3438/3439の4cmd連続でcommand欄の読取参照がBLOCKを引き起こした
- **学習過程**:
  - cmd_3435: LGTM→BLOCK(command_files_modified_mismatch)→家老WA→CLEAR
  - cmd_3437: LGTM→BLOCK(同)→家老WA→CLEAR
  - cmd_3438: RC(反省適用)→修正→CLEAR(予測的中)
  - cmd_3439: FAIL(反省深化)→BLOCK予測的中→家老WA→CLEAR
- **教訓**: SG-PRE25 ERRORが出たらGATE_PREDICTION CLEARであってもprecheckのFAIL指示を優先
- **根因**: GATE_PREDICTIONはcommand欄のファイル名抽出精度に依存し偽CLEARを出す
- **lesson_candidate送信済み**: 家老に登録依頼
- **origin**: [[cmd_3435_BLOCK]] -> [[4連続学習]] -> [[precheckFAIL優先ルール]]

## レビュー実績

| cmd | type | verdict | gate | 備考 |
|-----|------|---------|------|------|
| cmd_3432 | draft | APPROVE | CLEAR | causal_backlink偽陽性修正 |
| cmd_3432 | report | LGTM | CLEAR | --no-ignoreフラグ追加(忍者独自発見) |
| cmd_3433 | draft | APPROVE | CLEAR | lesson_write.sh retagバグ修正 |
| cmd_3433 | report | LGTM | CLEAR | 4行変更の最小修正 |
| cmd_3434 | draft | APPROVE | CLEAR | context鮮度反映 |
| cmd_3434 | report | LGTM | BLOCK→CLEAR | L107既存参照切れ(scope外)→家老WA |
| cmd_3435 | draft | APPROVE | CLEAR | オントロジーPhase 1偵察 |
| cmd_3435 | report | LGTM | BLOCK→CLEAR | command欄mismatch→家老WA |
| cmd_3437 | draft | APPROVE | CLEAR | Phase 2a推論実装 |
| cmd_3437 | report | LGTM | BLOCK→CLEAR | command欄mismatch→家老WA |
| cmd_3438 | draft | RC | - | command欄設計書参照除外指摘 |
| cmd_3438 | report | LGTM | CLEAR | RC反映済み |
| cmd_3439 | draft | APPROVE | CLEAR | Phase 3 BFSトラバース |
| cmd_3439 | report | FAIL | BLOCK→CLEAR | SG-PRE25 FAIL優先(反省適用) |
| cmd_3441 | draft | APPROVE | 待ち | CDP全ロール開放 |

- draft review: 8件(APPROVE 7+RC 1)
- report review: 7件(LGTM 5+FAIL 1+待ち 1)
- gate予測: BLOCK予測的中2件(cmd_3434/3439)。CLEAR予測外れ2件(cmd_3435/3437)
