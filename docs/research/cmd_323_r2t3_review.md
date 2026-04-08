# cmd_323 R2-Task3 ブラインドレビュー用 — deploy_task.sh コードレビュー

> 3モデルが同一対象(scripts/deploy_task.sh)をコードレビュー。
> 各Outputの指摘内容・深さ・正確性を比較評価せよ。

---

## Output A

**summary**: deploy_task.sh全文(874行+依存lib cli_lookup.sh 187行)のコードレビュー完了。

### Findings: HIGH (3件)
- **H-1 security/injection** [L57-66,L203-373,L384-481,L492-582,L606-617,L641-648,L670-696,L718-799]
  python3 -c ブロック全8箇所でシェル変数直接展開。Python文字列境界破壊→任意コード実行可能。
  推奨: 環境変数経由(os.environ)に改修。
- **H-2 security/path-traversal** [L22,L164-165,L828,L833,L869-870]
  NINJA_NAMEバリデーション不十分。パストラバーサル入力可能。
  推奨: ホワイトリスト `^[a-z]+$` で検証。
- **H-3 data-integrity** [L175]
  generate_report_template()が既存報告を無条件上書き。アーカイブ未退避で消失リスク。
  推奨: 上書き前にarchiveディレクトリへバックアップ。

### Findings: MEDIUM (4件)
- **M-1 robustness/parsing** [L593,L828,L869-870] grep/sedが固定2スペースインデント依存。L034教訓パターン。
- **M-2 error-handling** [L63-65,L228-230等] bare except多用。KeyboardInterrupt等も捕捉。
- **M-3 robustness** [L171-172] ac_countの算出がgrep -A 60固定行数依存。ログ用途のみで実害小。
- **M-4 concurrency** [L357-365,L466-474,L567-575] atomic writeにflock不使用。同時実行でlast-writer-wins。

### Findings: LOW (5件)
- L-1: exit code方針不統一（gate系=0、inject系=1）
- L-2: ログローテーションなし
- L-3: resolve_pane()にハードコード"shogun:agents"
- L-4: stdout/stderr分離が2>&1で無効化
- L-5: メイン3分岐が全て同じ処理(inbox_write呼出し)。分岐の意味が薄い

### Good Points
1. atomic writeパターンの一貫適用(6箇所)
2. yaml.safe_load()の徹底(10箇所以上)
3. gate architecture — 仕組みが強制する設計思想
4. graceful degradation — inject系の失敗耐性(|| true)
5. 2段階状態検知(tmux変数→capture-pane fallback)

lesson_candidate: deploy_task.sh python3 -c内シェル変数直接埋込が全8箇所で未修正(L047/L043未対応)

---

## Output B

**summary**: deploy_task.sh の構造把握とセキュリティ/堅牢性レビューを完了。

### Findings: HIGH (2件)
- **H-1 security** [L57] python3 -cの文字列へシェル変数を直接埋め込み。シングルクォートでPythonコード注入可能。同型箇所がL203/384/492/606/670/718にも存在。推奨: 環境変数経由またはexternal .py
- **H-2 security** [L22] NINJA_NAME厳格検証なし。パストラバーサルやファイル操作余地あり。推奨: allowlist `^[a-z_]+$` で検証。

### Findings: MEDIUM (2件)
- **M-1 reliability** [L94] set -euo pipefail下でgrepパイプラインが0件でスクリプト終了。推奨: `|| true`付与。
- **M-2 robustness** [L828] YAML抽出がgrep `^  status:`の固定インデント依存。推奨: パターン柔軟化。

### Findings: LOW (1件)
- **L-1 maintainability** [L175] generate_report_templateが常にcat>で上書き。既存レビュー消失。推奨: タイムスタンプ付きバックアップ。

### Good Points
1. Python処理のatomic write(tempfile+os.replace)採用(L223-227,L358-363等)

lesson_candidate: なし

---

## Output C

**summary**: deploy_task.shのコードレビュー完了。最重要問題はpython3 -c内でのシェル変数直接展開。

### Findings: HIGH (1件)
- **H-1 security/injection** [L206-207,L387-388,L495-498,L607-616,L671,L719]
  python3 -c文字列内で$task_file/$SCRIPT_DIR/$name等のシェル変数を直接展開。6関数に同一パターン。
  推奨: 環境変数経由。$NINJA_NAMEホワイトリスト追加で攻撃面縮小可能。

### Findings: MEDIUM (3件)
- **M-1 security/validation** [L22-43] NINJA_NAMEバリデーション不十分。cmd_*プレフィックスのみ。推奨: `^[a-z_]+$`
- **M-2 security/code-injection** [L175-190] heredocで$ninja_name等が展開。YAMLファイル由来の悪意ある値でコマンド実行可能。推奨: `<<'EOF'`+sed置換。
- **M-3 observability** [L799] result=$(python3 -c "..." 2>&1)でstdout/stderr混在。BLOCKとPASSの区別困難。

### Findings: LOW (4件)
- L-1: [L95] `if [ -n "$ctx_num" ] 2>/dev/null` の2>/dev/nullが無意味
- L-2: [L828] grep `^  status:`の固定2スペース依存(L034教訓再現)
- L-3: [L222-263] atomic writeロジックが3箇所で完全重複(DRY違反)
- L-4: [L120] CTX取得失敗時echo "0"で0%扱い→ペイン不存在でもCTX:0%と誤判定

### Good Points (overall assessment内)
- Atomic write・set -euo pipefail・フォールバック多段設計
- inject系失敗でもデプロイ継続(|| true)
- L034教訓再現(L828)は教訓注入が正しく機能した例

lesson_candidate: なし
