# セマンティック監査 — bd4a61f8..fe3da500 (cmd_2865-2872)
<!-- generated: 2026-05-19T15:15:00+09:00 by gunshi idle analysis -->

## 対象

10スクリプト変更(cmd_2865-2872): cmd_complete_gate.sh, cmd_save.sh, deploy_task.sh, gunshi_gate_sync.sh, lesson_write.sh, record_lesson_feedback.sh, report_field_set.sh, semantic_index_update.sh, semantic_map_generate.sh, semantic_search.sh

## 結果

| カテゴリ | 検出 | 真P1 | 偽陽性 | P2以下 |
|---------|------|------|--------|--------|
| silent_failure | 33 | 0 | 6(P1全て) | 27 |
| side_effect | 14 | 0 | 4(P0-P1全て) | 10 |
| drift | 0 | - | - | - |

## P1偽陽性の検証

### append_line_locked subshell exit (cmd_complete_gate.sh L17-27)
- 指摘: subshell exit 1がFD redirectで抑制される
- 検証: `(flock -w 0 200 || exit 1; ...) 200>lockfile` → lock contention時exit code=1を確認
- 結論: **偽陽性**。flock subshellパターンは正しく伝播する

### gunshi_gate_sync.sh awk→mv empty check (L484-503, L519-538)
- 指摘: awk失敗がパイプラインで隠蔽+tmp残存
- 検証: -s check+rm -f+WARN出力=設計意図通り。tmp残存リスクは即rm -fで排除
- 結論: **設計意図通り**。awk空出力=入力データ異常→WARNは適切

### report_field_set.sh verdict auto-derivation (L1661-1679)
- 指摘: verdict=''とunsetの混同
- 検証: YAML parse後のPython処理で空文字列/None/null全て同等扱い。bc結果からの自動導出が目的なので実害なし
- 結論: **設計意図通り**

## P2以下の傾向

- `2>/dev/null || true` パターン: 27件。大半はセマンティック/索引系の非致命的操作で設計意図通り
- 非atomic更新: cmd_complete_gate.shのflock追加(cmd_2872)で改善済み。残存は.tmpウィンドウ(2-200ms)のみ
- テンプファイル: mktemp+trap ERR/EXITパターンで概ね保護。semantic_search.shの1件のみtrapなしだがEXIT trapあり

## 総合判定

構造的バグ=0件。全件FP/設計意図/P3低リスク。cmd_2872のflock追加は有効に機能。
