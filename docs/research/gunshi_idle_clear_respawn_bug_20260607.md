# /clear後CTX高止まり+plan modeバグ — 根因と修正
<!-- generated: 2026-06-07T22:00:00+09:00 by gunshi session analysis -->

## 殿指摘
- Sonnet忍者のCTXが/clear後も高いまま
- 全員bypass permissionsでない
- plan modeが諸悪の根源
- CTX 0%にならないのは最重要バグ

## 根因
速度修行の大量配備で/clearサイクルが高頻度化。safe_send_clearの`/clear`+shift+tab×2はタイミング依存で壊れる脆弱な設計。

| 問題 | 根因 | 修正 |
|------|------|------|
| plan modeに落ちる | shift+tab×2の間隔0.3秒でCLI状態遷移が間に合わない | respawn-pane -k方式に統一(25d9944b9) |
| CLI死亡(status 127) | pane_start_commandが二重クォートされたコマンドを返す | cli_profiles.yaml launch_cmd直接使用(9e7e37625) |
| CTX高止まり表示 | /clear後に@context_pctキャッシュが旧値のまま | /clear後に@context_pct=0%リセット(8c5677d1e) |
| CLI応答遅延 | safe_send_clear内のcd送信がCLIにコマンド入力される | cd送信除去(515901a36) |
| 計測テストブロードキャスト | switch_project.shがinbox_write全員配信 | DRY_RUN対応(48a95ff22) |
| 全忍者Opusで起動 | launch_cmdに--model未付与。settings.yaml model_name無視 | model_nameを--model引数追加(a0cac8711) |

## 教訓
- 想像するな確認せよ: CTX 0%不可能と断言→ログでCTX=0%実績あり→嘘だった
- 洗脳#6(出力=仕事): CTX閾値ゲートは既存仕組みで解決できた(将軍洗脳分析)
- pane_start_commandは使うな: respawn-pane -kの起動コマンドが次回二重エスケープされる

## 修正commit一覧
- 8c5677d1e: @context_pctリセット
- 88f0f90dc: bypass permissions待機(後でrespawn方式に統合)
- 25d9944b9: respawn-pane -k方式統一
- 515901a36: cd送信除去
- 9e7e37625: pane_start_command廃止
- dfecdf651: shift+tab間隔延長+リトライ(後でrespawn方式に統合)
- 48a95ff22: switch_project.sh DRY_RUN対応
