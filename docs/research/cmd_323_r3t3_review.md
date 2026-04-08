# cmd_323 R3-Task3 ブラインドレビュー: ninja_monitor.shコードレビュー3出力比較

- **対象**: scripts/ninja_monitor.sh (1524行)
- **タスク**: コードレビュー（問題点の指摘 + 良い点の評価）

---

## Output A

### 指摘事項

| # | Severity | Category | Line | Description | Recommendation |
|---|----------|----------|------|-------------|----------------|
| 1 | HIGH | security | 739 | rm -rf検知が固定パスに限定。/mnt/d/*, /tmp/*, /var/*等を見逃す。D002/DWSL2保護として不十分 | rmコマンド引数をrealpath正規化後にproject root prefix判定。prefix外は一律WARN |
| 2 | MEDIUM | reliability | 328 | auto-done更新のsed置換が非アンカー。意図しないstatus行まで変更される可能性 | yq利用 or `^  status:`で先頭アンカー+最初の1件のみ更新 |
| 3 | MEDIUM | correctness | 545 | stall判定のstatus取得が`grep -m1 'status:'`でインデント未考慮。別階層statusへ誤マッチ余地 | `^  status:`に限定 or YAMLパーサで`.task.status`直接取得 |
| 4 | LOW | robustness | 198 | fallback busy patternに`Running|Streaming|thinking`等の一般語含有。通常出力への誤反応リスク | CLI別ステータス行フォーマットに絞った正規表現に変更 |

### 良い点
（記載なし）

### サマリー
HIGH 1 / MEDIUM 2 / LOW 1 / Good 0
「監視基盤として有用だが、検知漏れを生むセキュリティ判定とgrep/sedベースのYAML操作を優先的に是正すべき」

---

## Output B

### 構造概要
メインループ(L1376-1523)が20秒ポーリング。Phase1高速スキャン→Phase2二段階確認→バッチ通知→停滞検知→破壊コマンド検知→renudge→stale/pending cmd→家老/clear→将軍CTX→context_pct更新→inbox未読数→lesson健全性→archive→状態ファイル→スクリプト更新検知。依存: cli_lookup.sh, model_detect.sh

### 指摘事項

| # | Severity | Category | Line | Description | Recommendation |
|---|----------|----------|------|-------------|----------------|
| 1 | HIGH | 機能欠陥(実証済みバグ) | 1097-1122 | send_karo_clear()が/clear後に復帰トリガー(inbox_write type:recovery)未送信。家老永久idle化バグ。殿のshogun_lessonsに記録済み | sleep 5後にinbox_write karo recovery追加 |
| 2 | HIGH | ロジックバグ(L034) | 328 | check_and_update_done_task()のsedがグローバル置換。ネストされた構造のstatus:も誤変更リスク | sed範囲を`/^task:/,/^[^ ]/`に限定 or YAMLパーサ使用 |
| 3 | HIGH | パターンマッチ不備(L010) | 302, 545 | L545でgrep -m1 'status:'がインデント未考慮。L302/L321はOK('^status:')だがL545はNG | L545を`grep -m1 '^  status:'`に修正 |
| 4 | MEDIUM | セキュリティ(regex injection) | 653 | cmd_idをrgのregexパターンに直接interpolate。regex特殊文字含有時に構文エラー | rg --fixed-strings使用 or cmd_id形式バリデーション |
| 5 | MEDIUM | 算術エラー | 1449-1450 | codex_confirm_wait空or負値時のextra_wait計算でbash arithmetic error | デフォルト値設定+三項演算子で最小値保証 |
| 6 | MEDIUM | 保守性(暗黙変数依存) | 885 | check_inbox_renudge()がメインループのcycle変数を暗黙参照。カプセル化違反 | cycle変数を引数として渡す |
| 7 | MEDIUM | データ品質 | 990, 1006 | CTX未取得と0%の区別不可。get_context_pct()検出失敗時に"0"返却 | 空の場合はnullまたは"--"を使用 |
| 8 | LOW | セキュリティ(自動実行) | 1266 | check_script_update()がexecで自己置換。ファイル置換攻撃面 | ファイルパーミッション・オーナー確認追加 |
| 9 | LOW | デッドコード | 399-409 | notify_idle()定義済みだが未使用。実際はnotify_idle_batch()が担当 | 関数削除 or コメント明記 |
| 10 | LOW | コード一貫性 | 496, 501 | handle_confirmed_idle()でagent_id/name混在使用。不一致リスク | nameに統一 |

### 良い点

| # | Title | Line | Description |
|---|-------|------|-------------|
| G1 | 二段階idle確認 | 1397-1465 | Phase1+Phase2+Codex追加待機。false positive排除 |
| G2 | @agent_state+capture-paneフォールバック | 166-216 | 多重ソース設計+grace period |
| G3 | fingerprintベース再nudge | 784-898 | sort後md5hashで状態遷移検知。二重経路増幅抑止 |
| G4 | flock排他制御の一貫使用 | 326,975,1019,1354 | 並列実行競合防止 |

### サマリー
HIGH 3 / MEDIUM 4 / LOW 3 / Good 4
「最重要はsend_karo_clear()復帰トリガー欠如(H1:実証済みバグ)とYAML操作のsed/grepパターン(H2/H3:L034/L010教訓直結)」

### lesson_candidate
「send_karo_clear()復帰トリガー欠如は構造的問題 — /clear後に必ずrecovery inbox_writeを送れ」

---

## Output C

### 構造概要
1524行のバックグラウンドデーモン。20秒周期メインループ。
主要関数: discover_panes(L96-116), check_idle(L162-217), get_context_pct(L222-287), check_and_update_done_task(L292-340), is_task_deployed(L343-396), handle_confirmed_idle(L441-516), check_stall(L533-587), check_stale_cmds(L625-668), check_karo_pending_cmd(L673-716), check_destructive_commands(L726-778), check_inbox_renudge(L819-898), write_state_file(L969-1011), write_karo_snapshot(L1014-1091), send_karo_clear(L1097-1122), check_model_names(L1175-1209), update_inbox_counts(L1215-1253), check_lesson_health(L1277-1314), check_auto_archive(L1321-1368), check_script_update(L1256-1268)
依存: cli_lookup.sh, model_detect.sh, inbox_write.sh, ntfy.sh, gate_lesson_health.sh, archive_completed.sh, inbox_prune.sh

### 指摘事項

| # | Severity | Category | Line | Description | Recommendation |
|---|----------|----------|------|-------------|----------------|
| 1 | HIGH | security | cli_lookup.sh L41-69 (呼出: L195,206,241,460,497,501) | 依存ライブラリのpython3 -c内に変数直接補間。L047教訓同根。任意文字列受付API | 環境変数経由 or python3スクリプト+引数渡し |
| 2 | MEDIUM | reliability | 1448-1449 | extra_wait負値時のsleep失敗。Phase 2b無効化 | extra_wait > 0の最小値保証追加 |
| 3 | MEDIUM | maintainability | L361-362,563-564,678,859,1130 | check_idle呼出後に$?判定パターンが8箇所以上。間にコマンド挿入で$?上書き | if check_idle ...形式 or rc=$?即キャプチャ |
| 4 | MEDIUM | reliability | L1-1523 | SIGTERM/SIGINT/SIGHUPのtrapハンドラなし。kill時にflockファイル中途半端 | trap 'log ...; exit 0' SIGTERM SIGINT追加 |
| 5 | MEDIUM | robustness | 327-330 | flock取得失敗時のサブシェル内return。他シェル(dash等)で未定義動作 | return 1 → exit 1に変更 |
| 6 | MEDIUM | robustness | 545, 347, 1059 | タスクYAMLのstatus取得にgrep -m1 'status:'非アンカー使用。報告YAML(L321)とは対照的 | L010教訓適用: インデント考慮のgrep or awk |
| 7 | LOW | maintainability | 485 | CLEAR-SKIPログ抑制閾値15がマジックナンバー | POLL_INTERVALから計算する定数定義 |
| 8 | LOW | observability | 972, 1017 | タイムスタンプにタイムゾーン情報なし。他YAMLとISO 8601不整合 | date '+%Y-%m-%dT%H:%M:%S%:z' |
| 9 | LOW | reliability | 30-31, 52 | ログローテーション機構なし。長期稼働で無限膨張 | logrotate or スクリプト内サイズチェック |
| 10 | LOW | robustness | 1266 | exec自己再起動時の状態ロスログなし | exec前に状態ダンプログ追加 |
| 11 | LOW | robustness | 885 | cycle変数をグローバル参照。関数引数渡しなし | 引数渡し or グローバル明記 |

### 良い点

| # | Title | Line | Description |
|---|-------|------|-------------|
| 1 | 二段階idle検知(Phase 1/2) | 1397-1465 | 高速スキャン+確認+Codex追加待機。false positive排除 |
| 2 | fingerprint(L029)ベース再nudge | 780-898 | MD5ハッシュ遷移判定。inbox_watcher二重経路抑止 |
| 3 | CLI非依存プロファイルシステム | L31,195-211 | cli_profiles.yaml+cli_lookup.shでCLI差異を設定吸収 |
| 4 | flock排他制御の一貫適用 | 325-329,975-1010,1019-1091,1355-1359 | 並列競合防止の一貫設計 |
| 5 | 遷移駆動通知(cmd_255) | 670-716 | PREV_PENDING_SET比較で新規pending出現時のみ通知。noise削減 |

### サマリー
HIGH 1 / MEDIUM 5 / LOW 5 / Good 5
「二段階idle検知、fingerprint重複排除、遷移駆動通知など実運用対策が層を重ねて実装。HIGH1件は依存ライブラリのPython injection(L047同根)。$?パターン脆弱性(8箇所)とtrapハンドラ未設定を優先対処推奨」
