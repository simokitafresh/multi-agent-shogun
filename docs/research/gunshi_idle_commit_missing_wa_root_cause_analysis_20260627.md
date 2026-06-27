# commit_missing WA根因分析
<!-- generated: 2026-06-27T14:30:00+09:00 by gunshi idle analysis -->

## 対象

karo_workarounds.yaml直近10件中commit_missing 4件の根因分析。

## 分類

| # | cmd | ninja | 根因 | 封止状態 |
|---|-----|-------|------|---------|
| 1 | cmd_3515 | hayate | final_summary報告にL0 files_modifiedが統合されない | **未封止** |
| 2 | cmd_karo_hotfix_startup | hanzo | commit_hash full値が実在commitと不一致 | GP-287封止済み |
| 3 | cmd_karo_recon_ga126 | tobisaru | files_modifiedが説明文(パス形式でない) | GP-286封止済み |
| 4 | cmd_3536 | kagemaru | 家老追加commit(DM-Signal本番コード timing検証位置修正) | **未封止(PJ固有)** |

## 封止済み(GP-286/GP-287)

- D0 commit: 1a6e89252 (gate_report_format_main.py L213-L231)
- batsテスト: cmd_3562 commit bb7820ac (T-GP286-1, T-GP287-1)
- 実動作確認: short hash→FAIL検出、non-path→FAIL検出
- 効果検証: 今後のcmdでWA#2/#3パターンが再発しなければ有効。再発率を監視

## 未封止(構造的穴)

### 穴A: マルチフェーズcmd files_modified統合不在

- cmd_3515でL0→final_summary報告統合時にfiles_modifiedが未マージ
- grep files_modified.*merge cmd_complete_gate.sh → 0件
- マルチフェーズcmd自体が稀だが、再発時にWAが確実に発生
- 提案: 掲示板blt_20260627_142919で将軍にcmd化を提案済み

### 穴B: DM-Signal本番コード家老追加commit

- cmd_3536で忍者が気づかない本番動作差異(timing検証位置)を家老がhotfix追加
- 構造的対策はDM-Signal PJ固有(scope外)
- 忍者のテスト範囲拡大(edge case)が漸進的対策

## 因果リンク

- → [[GP-286]] files_modifiedパス形式検証
- → [[GP-287]] commit_hash 40文字hex強制
- → [[cmd_3562]] GP-286/287 batsテスト追加
- → [[cmd_3515]] マルチフェーズcmd final_summary統合
