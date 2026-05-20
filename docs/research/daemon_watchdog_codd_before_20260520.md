# daemon_watchdog.sh CoDD Before計測

- 実施者: tobisaru
- 日付: 2026-05-20
- cmd: cmd_training_speed_tobisaru_4

## Before計測 (cold, 4回)

| Run | Time |
|-----|------|
| 1   | 424ms |
| 2   | 388ms |
| 3   | 405ms |
| 4   | 455ms |

**Median: ~415ms**

## プロファイリング結果

| フェーズ | 時間 |
|---------|------|
| rotate_log (stat) | 7ms |
| crontab -l | 10ms |
| pgrep ninja_monitor | 19ms |
| pgrep ntfy_listener | 24ms |
| source agent_config.sh | 18ms |
| get_all_agents | 15ms |
| **pgrep per agent (9回)** | **207ms** (最大ボトルネック) |
| hang_check per agent (9回) | 144ms (NTFS grep) |
| tmux list-panes | 10ms |
| **TOTAL** | **~454ms** |

## ボトルネック仮説

### B1: pgrep per agent ループ（207ms, ~50%）
- 現状: `check_inbox_watchers`が9エージェント×`pgrep -f "[i]nbox_watcher\.sh.*${agent}"`を順番に実行
- WSL2上でpgrep起動コスト ~23ms × 9 = 207ms
- 最適化案: `pgrep -f "inbox_watcher\.sh"` 1回でPID一覧取得 → `/proc/PID/cmdline`でエージェント照合
  - 期待: 1×23ms + N×/proc読み込み(< 1ms) ≈ 30ms

### B2: hang_check per agent (144ms)
- 現状: 9エージェント × (cat heartbeat + grep -c inbox.yaml)
- heartbeatファイルは/tmp（速い）だが inbox.yaml は/mnt/c（NTFS、遅い）
- `grep -c` → `grep -q -m1`に変更（first match で停止）
- または: heartbeat age確認してOKなら inbox grep をスキップ（関数内の早期returnを利用）

### B3: 合計 pgrep 呼び出し数
- ninja_monitor: find_live_daemon_pid内でpgrep（19ms）
- ntfy_listener: find_live_daemon_pid内でpgrep（24ms）
- inbox_watchers: 9×pgrep（207ms）
- 合計: 11+ subprocess起動 = WSL2のプロセス起動コストが支配的

## 最適化方針
B1が最優先: pgrep 9回 → 1回（+/proc解析）で 207ms → 30ms程度に圧縮可能
B2は副次的: grep -c → grep -q -m1 で軽量化
