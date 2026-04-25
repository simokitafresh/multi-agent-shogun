# inbox_watcher サイレントサイクル根因分析

**日時**: 2026-04-25
**トリガー**: 家老consultation — saizo/kotaro/tobisaru watcher「ログ出力なし」
**結論**: watcherは正常稼働。ログ出力がないだけ。

## 症状

- 10:09:36に全watcher restart
- saizo/kotaro/tobisaru: 12:23まで約2h13mログ出力なし
- hayate: 11:39まで約1h30mログ出力なし
- 家老がログ出力なしを「ハング」と判断

## 根因

inbox_watcher.shのメインループは60sタイムアウトサイクルで動作するが、
`process_unread()`は未読メッセージがない場合にログを一切出力しない。

```
inotifywait timeout(60s) → process_unread(未読0→沈黙) → loop → 沈黙が永続
```

**「正常稼働中で何もすることがない」と「ハングしている」が外部から区別不能。**

## 証拠

1. **全watcher同一パターン**: hayateも1.5h沈黙。メッセージ到着で初めてログ出力
2. **inotifywaitプロセス正常**: ps確認で60sサイクル回転を実測（12:56→12:59で新PID生成）
3. **メッセージ到着後は正常動作**: saizo 12:23/12:28、kotaro 12:23にnudge送信成功

## 「動いている」vs「動いていない」の誤判定

| 忍者 | 最初のメッセージ到着 | 家老判定(12:22時点) | 実態 |
|------|-------------------|-------------------|------|
| hayate | 11:39 | 動いている | 正常(メッセージが先に来た) |
| saizo | 12:23 | 停止 | 正常(メッセージ未着で沈黙) |
| kotaro | 12:23 | 停止 | 正常(メッセージ未着で沈黙) |
| tobisaru | 12:24 | 停止 | 正常(メッセージ未着で沈黙) |

## 修正提案

### 案1: heartbeatファイル（推奨、LG016と同パターン）

メインループ毎サイクルで `/tmp/inbox_watcher_heartbeat_{agent_id}` にtouchする。
ninja_monitor.shがこのファイルのmtimeを参照して生存判定。

```bash
# メインループ内、process_unread後に追加
touch "/tmp/inbox_watcher_heartbeat_${AGENT_ID}"
```

ninja_monitor側: heartbeat mtime > 120s → STALL判定

**利点**: ログ肥大化なし。ext4上で高速。既存パターン(ntfy_listener)と統一。
**コスト**: 1行追加。

### 案2: 周期的ログ出力（補助）

5サイクル(5分)おきにheartbeatログを出力。

```bash
CYCLE_COUNT=$((CYCLE_COUNT + 1))
if (( CYCLE_COUNT % 5 == 0 )); then
    echo "[$(date)] [HEARTBEAT] $AGENT_ID: alive, no unread" >&2
fi
```

**注意**: ログのみでは判定用途に不十分（NTFS mtime遅延あり）。案1と併用推奨。

## 因果鎖

ログ出力なし(症状) ← process_unread()が未読0時に沈黙(設計) ← heartbeat機構の不在(根因) ← ntfy_listener(LG016)で同問題を解決済みだがinbox_watcherに横展開していなかった(メタ根因)
