# セマンティック監査: 直近変更12スクリプトのインフラバグ探索
<!-- generated: 2026-05-25T18:55:00+09:00 by gunshi idle analysis -->

## 対象
直近20コミットで変更された12スクリプト(5カテゴリ並列監査+P0現物検証)

## 監査手法
5カテゴリ並列エージェント→P0候補を軍師が現物検証→偽陽性降格

## P0候補の現物検証結果(全件降格)

| エージェント報告 | 現物検証結果 | 降格先 |
|---------------|------------|--------|
| cmd_complete_gate.sh:74 flock→exit 0で成功詐称 | exec 209>が先行成功。flock -n失敗=正常排他。偽陽性 | P3 |
| cmd_complete_gate.sh:1619 model情報喪失 | 行1768で`model="unknown"`にfallback。非クリティカル | P2 |
| gate_gunshi_cs_checklist.sh:304 YAML形式不一致 | 実データ確認: 1行型`[...]`と空型のみ。複数行型は未使用。正常動作 | P2 |
| prompt_state_inject.sh:101 タイムスタンプ形式 | bash `%z`→regex変換→`+09:00`。fromisoformat正常パース | P3 |
| conversation_retention.sh:189 MAX_ENTRIES超過 | 201行でギリギリだがsession_summaryは最新付近。clear_prepが毎回追記 | P1 |

**★ P0確定=0件。エージェントP0報告5件は全て偽陽性。現物検証が不可欠。**

## 確定バグ一覧(P1-P2のみ。P3省略)

### P1(3件)

| # | カテゴリ | ファイル:行 | 問題 |
|---|--------|-----------|------|
| 1 | race | prompt_state_inject.sh:218 | tmpファイル名がPID依存。mktemp未使用。WSL2でPID予測可能 |
| 2 | race | gate_karo_startup.sh:268 | /tmpキャッシュTOCTOU。stat→cp間に他プロセスが削除可能 |
| 3 | implicit | conversation_retention.sh:189 | MAX_ENTRIES=200超過でsession_summary喪失リスク(現在201行) |

### P2(12件)

| # | カテゴリ | ファイル:行 | 問題 |
|---|--------|-----------|------|
| 1 | silent | cmd_complete_gate.sh:234 | inbox_write.sh flock失敗を2>/dev/nullで隠蔽。gate_clear通知消失 |
| 2 | silent | cmd_complete_gate.sh:483 | awk YAML解析失敗→空文字列。後続undefined変数 |
| 3 | silent | cmd_complete_gate.sh:1434 | Python JSONL解析失敗が|| trueで黙過。教訓抽出欠落 |
| 4 | silent | cmd_save.sh:260 | python3構文エラー→品質チェック項目スキップ |
| 5 | silent | gate_gunshi_cs_checklist.sh:207 | awk失敗→RESULT空→CS観点全項目PASS偽陽性 |
| 6 | silent | gate_karo_startup.sh:268 | WA_RATE_SCRIPT失敗→teeがFAILメッセージを正常値表示 |
| 7 | state | gate_gunshi_startup.sh:153 | exit code 0/1/2の3値想定だが3以上で誤分類 |
| 8 | state | prompt_state_inject.sh:231 | semantic_search rc値の区別なし(1=no_match vs 2=file_not_found) |
| 9 | race | conversation_retention.sh:209 | tmpファイル名一意でない(PID未使用) |
| 10 | race | skill_gate_feedback.sh:156 | flockがlock_pathとlog_pathで独立。log_path直接openで保護外 |
| 11 | side | gate_gunshi_cs_checklist.sh:187 | brainwash_check全confidence必須化→偽陽性リスク |
| 12 | side | gate_karo_startup.sh:596 | 古いWAレコード(brainwash未記入)が偽陽性。現在wa:true=0件で未発火 |

## 横断パターン分析

1. **`2>/dev/null || true`の過多**: 28件中20件がstderr隠蔽。エラー原因の特定を困難にしている
2. **tmpファイル名のPID依存**: 3箇所でmktemp未使用。WSL2で予測可能
3. **Python YAML/JSONL解析のサイレント失敗**: 4箇所で解析失敗→空文字列→後続誤動作
4. **exit code多重判定の不完全**: 2箇所で0/非0の二分法。2と3+を区別しない

## cmd起票提案

| cmd | 内容 | 優先度 |
|-----|------|--------|
| A | P1 3件修正: mktemp化+TOCTOU fix+MAX_ENTRIES拡張(200→500) | 高 |
| B | P2 silent_failure系6件: 2>/dev/null→stderrログ記録に段階移行 | 中 |
| C | P2 race系2件: tmpファイルmktemp統一+flock対象統一 | 中 |
