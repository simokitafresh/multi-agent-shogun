# cmd_323 R2-Task2 ブラインドレビュー用 — usage_compare.sh

> 3モデルが同一仕様で scripts/usage_compare.sh を作成。
> 成果物ファイルは上書きされたため、報告YAMLからの実装概要で評価する。

## Output A

summary: "scripts/usage_compare.sh を新規作成し、2アカウントUsage並列取得+比較表表示+エラーハンドリング+DRY_RUNを実装した。"
files_modified: scripts/usage_compare.sh, queue/tasks対象忍者.yaml
notes: "検証: bash -n scripts/usage_compare.sh は成功。DRY_RUN=1 bash scripts/usage_compare.sh で3バケット比較表を出力確認。"
lesson_referenced: [L040, L034, L021]

## Output B

summary: "scripts/usage_compare.sh新規作成完了。AC1-AC5全PASS"
details:
- AC1: 両アカウントcredentials.jsonからOAuthトークン取得+並列API呼出し
- AC2: 3バケット(5h/7d/7d_sonnet)の色分け比較表(green<50%/yellow<80%/red>=80%)
- AC3: credentials不在/API失敗/timeout全対応。片方エラーでも他方は表示
- AC4: TIMEOUT=10秒(L040教訓反映)
- AC5: DRY_RUN=1テスト成功+bash -n構文チェックPASS
test_results: ["bash -n: PASS(構文エラーなし)", "DRY_RUN=1: PASS(mockデータで比較表正常表示)"]
lesson_referenced: [L040, L034]

## Output C

summary: |
  scripts/usage_compare.sh 作成完了。
  - 両アカウント(primary/secondary)のUsage APIを並列取得
  - 3バケット(five_hour/seven_day/seven_day_sonnet)の比較表形式出力
  - 認証切れ(HTTP 401/403)・API失敗・credentials不在の各エラーハンドリング
  - WSL2対応timeout: CURL_TIMEOUT=10秒（L040教訓適用）
  - DRY_RUN=1動作確認: exit_code=0 PASS
  - bash -n 構文チェック: PASS
ac_status: AC1=PASS, AC2=PASS, AC3=PASS, AC4=PASS, AC5=PASS
lesson_referenced: [L040, L034, L032, L031, L021]

---
NOTE: 3バージョンとも同一ファイルパスに出力のため、ディスク上には最終書込み者のバージョンのみ残存。
scripts/usage_compare.sh の現在のコードも参考にしてよいが、これがどのOutputかは不明。
