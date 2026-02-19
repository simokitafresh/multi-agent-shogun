# インフラコンテキスト

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

最終更新: 2026-02-11

## コンテキスト管理

コンテキスト管理は**全て外部インフラが自動処理する。エージェントは何もするな。**

| エージェント | 外部トリガー | 方法 |
|-------------|-------------|------|
| 忍者 | ninja_monitor.sh | idle+CTX>50% → /clear送信 |
| 家老 | ninja_monitor.sh | idle+CTX>50% → /clear送信（陣形図付き） |
| 将軍 | 殿の手動操作 | CTX>50%でntfyアラート → 殿が判断 |

- ソフト閾値: 50%（外部トリガー発動条件）
- ハード閾値: 90%（CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90、最後の安全弁）
- 忍者=/clear（コンテキスト汚染防止。hayate v1→v4事件が教訓）
- 家老=/clear（陣形図snapshotで状態保全。/compactの5-8分停止を解消）
- CLI種別により/compact挙動が異なるため、実際の動作は`config/settings.yaml`を参照
- 設定: settings.json → env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE。全エージェントに自動適用
- statusline.sh: イベント駆動。JSON入力にcontext_window.used_percentage含む

## ninja_monitor.sh

- idle検知+CTX>50%で忍者に/clear、家老に/clearを自動送信
- is_task_deployed(): YAML status + capture-pane + @current_task空チェックの二重チェック（cmd_049で修正）
- STALE-TASK検出: YAML上作業中だがペインidle → ログ出力して対処
- CLEAR_DEBOUNCE=300（5分）でループ防止
- get_context_pct(): capture-pane出力から「CTX:XX%」を直接パース（tmux変数は不安定）
- write_karo_snapshot(): 毎サイクルqueue/karo_snapshot.txtを自動生成（家老/clear復帰用の圧縮陣形図）
- KARO_CLEAR_DEBOUNCE=120（2分）— /clear復帰~30秒のため大幅短縮

## inbox_watcher.sh

- inotifywaitでqueue/inbox/{agent}.yaml変更検知 → send-keysで短いナッジ送信
- ナッジ形式: `inboxN`（例: inbox3=未読3件）。内容は送らない
- エージェントリネーム後はsymlink必要（旧名→新名、Pythonのopen()がsymlinkを辿る）
- watcher欠落時の手動起動: `nohup bash inbox_watcher.sh {agent} {pane} claude`

## ntfy.sh

- Usage: `bash scripts/ntfy.sh "メッセージ"` **のみ。引数追加厳禁。**
- トピック: shogun-simokitafresh
- インターフェース変更で全通知が無言で壊れた事故あり（--sendフラグガード事件）
- shutsujin_departure.shにスモークテスト組み込み済み

## tmux設定

- prefix: Ctrl+A（.tmux.conf設定済み。デフォルトのCtrl+Bではない）
- レイアウト文字列: `1a7c,167x49,0,0{...}`（shutsujin_departure.shで適用）
- セッション: shogun | Window 1: main（将軍） | Window 2: agents（家老+忍者9ペイン）
- 形式: shogun:2.{pane_index}

| pane | 名前 | pane | 名前 | pane | 名前 |
|------|------|------|------|------|------|
| 1 | karo | 4 | hayate | 7 | saizo |
| 2 | sasuke | 5 | kagemaru | 8 | kotaro |
| 3 | kirimaru | 6 | hanzo | 9 | tobisaru |

- karo.mdのpanes設定(shogun:0.{N})は不正確。実際はshogun:2.{N}。`tmux list-panes -t shogun:2`で確認せよ

## 編成

| 階級 | CLI | 名前 |
|------|-----|------|
| 上忍(jonin) — CLI設定はsettings.yaml参照 | settings.yaml参照 | 半蔵(hanzo) 才蔵(saizo) 小太郎(kotaro) 飛猿(tobisaru) 疾風(hayate) 影丸(kagemaru) |
| 下忍(genin) — CLI設定はsettings.yaml参照 | settings.yaml参照 | 佐助(sasuke) 霧丸(kirimaru) |

- `config/settings.yaml`の`cli.agents`をSSOTとして参照
- 個別CLI設定（種別・モデル・effort）は`config/settings.yaml`を参照
- 利用クライアント種別は`config/settings.yaml`に従う（手元設定値を前提にしない）

## WSL2固有

- /mnt/c/上ではinotifywait不可。statポーリング(15-30秒)を標準パターンとして使え
- .wslconfigのネットワーク設定ミスで全エージェント凍死の事例あり
