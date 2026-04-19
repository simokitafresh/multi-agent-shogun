# Android SSH Input Loss Investigation

- date: `2026-04-19`
- task: `cmd_2104_recon`
- scope: Android/SSH経路で「送信後に入力が消える」現象の切り分け

## 結論

直接SSH入力の現象としては、`inbox_watcher.sh` の通常nudge競合が主因である可能性は低い。最優先で疑うべきは、`Claude Code` 側の busy→idle 遷移時再描画と、将軍ペイン専用 hook 群が Enter 後に追加出力を差し込む経路である。

Androidコンパニオンアプリ経路は別に脆い。実装は `tmux send-keys` を本文と `Enter` に分けて別SSH execで送っており、`paste-buffer` も排他ロックも使っていないため、アプリ経由ならこちらも有力候補になる。

## 5観点の調査結果

| 観点 | 事実 | 判定 |
|------|------|------|
| tmuxログ設置 | 調査開始時点の `shogun:main` は `#{pane_pipe}=0` で raw trace 不在。既存の `scripts/log_terminal_input.sh` は `UserPromptSubmit` 後しか記録せず、「送信したのに消えた」瞬間の生データを残せない。今回 `scripts/tmux_pipe_logger.py` + `scripts/enable_pane_trace.sh` を追加し、`shogun:main` に `tmux pipe-pane` を有効化した。 | **改善済み** |
| watcher競合分析 | `scripts/inbox_watcher.sh` の通常nudgeは `paste-buffer + Enter`、かつ flock排他つき。本文を `send-keys` で流す旧方式ではない。さらに direct SSH入力なら watcher は主経路ではない。例外は `clear_command` / `model_switch` のCLI直送時のみ。 | **主因は低確率** |
| フック再描画確認 | 将軍は `.claude/settings.json` により `UserPromptSubmit` / `PostToolUse` / `Stop` の各hookが常時発火する。`prompt_state_inject.sh` は送信時に context を注入し、`post-shogun-inbox-check.sh` は未読inboxがあれば追加警告を返す。busy完了直後にこれらが重なると、モバイル端末側では「送信後に行が消えた」見え方になりうる。 | **最優先候補** |
| escape-time確認 | 実機 tmux server 設定は `escape-time 10`、`focus-events off`。`escape-time` は ESC/Meta 系の遅延には効くが、通常テキスト+Enterが消える説明力は低い。 | **低優先** |
| Androidアプリsend実装確認 | `android/app/src/main/java/com/shogun/android/viewmodel/ShogunViewModel.kt` と `AgentsViewModel.kt` は、`tmux send-keys -t <target> '<text>'` 実行後に `300ms` 待って `tmux send-keys -t <target> Enter` を別SSH execで送る。`-l` なし、`paste-buffer` なし、tmux側lockなし。Androidアプリ経路なら race を作りやすい。 | **アプリ経路では有力** |

## 根拠

### 1. watcher/send-keys競合は主因ではない

- `scripts/inbox_watcher.sh:384-523`
  - 通常nudgeは `paste-buffer` で本文注入し、`send-keys` は `Enter` のみ。
  - flock lock (`tmux_sendkeys_*`) あり。
  - direct SSHでの手入力そのものとは別経路。

### 2. 将軍hookは入力送信直後の再描画候補になる

- `.claude/settings.json:40-127`
  - `PostToolUse` で `post-shogun-inbox-check.sh`
  - `Stop` で `log_terminal_response.sh`
  - `UserPromptSubmit` で `log_terminal_input.sh` + `prompt_state_inject.sh`
- `.claude/hooks/post-shogun-inbox-check.sh:1-28`
  - unread inbox があると追加Contextを返す。
- `scripts/hooks/prompt_state_inject.sh:1-117`
  - `UserPromptSubmit` ごとに将軍向け追加Contextを注入する。

### 3. 既存ログは「送信前後の生ストリーム」を残していない

- `scripts/log_terminal_input.sh:1-27`
  - `UserPromptSubmit` 後に `.prompt` を `lord_conversation.jsonl` へ記録。
  - Claudeが prompt submit を受け取れなかったケースは残らない。
- `scripts/log_terminal_response.sh:1-139`
  - `Stop` 時の応答記録であり、入力消失瞬間の raw I/O ではない。

### 4. Androidコンパニオンの送信は2段階 `send-keys`

- `android/app/src/main/java/com/shogun/android/viewmodel/ShogunViewModel.kt:94-117`
- `android/app/src/main/java/com/shogun/android/viewmodel/AgentsViewModel.kt:170-188`
  - 文字列送信と `Enter` が別SSH exec。
  - `safe_send_keys_atomic` 相当の排他なし。
  - `send-keys -l` ではないため、特殊キー解釈や quoting 差分の影響も残る。

### 5. tmux runtime設定

- runtime observation (`2026-04-19`)
  - `tmux show-options -s | rg 'escape-time|focus-events'`
  - 結果: `escape-time 10`, `focus-events off`

## 優先順位付きの原因仮説

### H1. busy完了直後の再描画で、モバイル端末側の送信済み行が消えて見える

- 優先度: `P1`
- 理由:
  - 殿の一次情報は「SSH直接入力」「送信後に消える」。
  - 将軍は送信後に hook 出力が重なる構造。
  - watcher由来ではなく、CLI/hook再描画なら direct SSH 症状と整合する。
- 検証:
  - 再発時刻を `logs/pane_trace/shogun_main.log` で確認。
  - 同時刻の `queue/lord_conversation.jsonl` に inbound が無ければ、Claudeに渡る前に画面上で消えた可能性が高い。
  - inbound はあるが実行されない場合は、Claude側の submit/stop 競合を疑う。

### H2. Androidコンパニオンアプリの2段階 `send-keys` が race している

- 優先度: `P2`
- 理由:
  - アプリ経路だけは `text` と `Enter` が別exec。
  - tmux側排他も `paste-buffer` も無い。
- 検証:
  - Androidアプリのみで再現を試す。
  - 再発時刻の pane trace で「本文だけ出る / Enterだけ出る / 両方出ない」を見る。
  - 再現するなら `safe_send_keys_atomic` 相当へ寄せる価値が高い。

### H3. watcher/他tmux送信との衝突

- 優先度: `P3`
- 理由:
  - direct SSHの主経路ではない。
  - ただし `Enter` 注入は残っているため、同時刻に nudge や special command が来れば干渉余地はゼロではない。
- 検証:
  - `logs/inbox_watcher_shogun.log` と pane trace の時刻突合。
  - 症状時刻に watcher が `Wake-up sent to shogun` / CLI command を出しているか確認。

### H4. `escape-time` や ESC 系キー処理

- 優先度: `P4`
- 理由:
  - plain text + Enter の消失とは整合が弱い。
  - 特殊キー列や Android キーボードの ESC/Alt 系でのみ候補。
- 検証:
  - 通常文と ESC/矢印/Tab を分けて再現確認。

## 今回追加した事後分析用 trace

### 追加ファイル

- `scripts/tmux_pipe_logger.py`
- `scripts/enable_pane_trace.sh`

### 有効化コマンド

```bash
bash scripts/enable_pane_trace.sh shogun:main
```

### 出力先

```text
logs/pane_trace/shogun_main.log
```

### 読み方

1. 症状発生時刻を控える。
2. `logs/pane_trace/shogun_main.log` の同時刻前後を見る。
3. `queue/lord_conversation.jsonl` と突合する。
4. Androidアプリ経路なら端末ログも同時刻で比較する。

## 次に見るべきもの

1. 再発時の `logs/pane_trace/shogun_main.log`
2. 同時刻の `queue/lord_conversation.jsonl`
3. `logs/inbox_watcher_shogun.log`
4. Androidアプリ再現時は `ShogunViewModel.sendCommand()` 呼出しログ
