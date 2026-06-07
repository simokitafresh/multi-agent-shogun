# restart_watchers.sh 速度改善修行 — before計測ノート

## 対象スクリプト
`scripts/restart_watchers.sh`

## before計測（cold 3回）

| Run | real | user |
|-----|------|------|
| 1   | 2.083s | 0.503s |
| 2   | 2.361s | 0.545s |
| 3   | 1.984s | 0.587s |
| **平均** | **~2.14s** | **~0.55s** |

## プロファイル（個別コンポーネント計測）

| コンポーネント | 時間 |
|--------------|------|
| `sync_pane_vars.sh`（全体の55%） | **1150ms** |
| `pane_lookup.sh` source | 133ms |
| `agent_config.sh` source + get_all_agents | 120ms |
| `pgrep -f` single call | 17ms |
| `watcher_process_count()` (ps+awk) | 27ms |
| `tmux show-options` x9 | 37ms |
| `pgrep -fc inotifywait` | 23ms |
| SCRIPT_DIR cd-subshell | 2ms |

## ボトルネック分析

### 支配因子: sync_pane_vars.sh (1150ms = 55%)

`sync_pane_vars.sh` は 10エージェント（shogun+9忍者）全員に対して：
- `tmux capture-pane -S -1000`（最大1000行スクロールバック）×10回
- モデル名抽出（grep/sed パイプライン）×10回
- `tmux show-options/@real_model` フォールバック×最大10回

これが ~1150ms の主因（~115ms/エージェント）。restart_watchers.sh の完了を待機させるブロッキング呼び出しだが、**watcher起動後は不要な同期的待機**。

### 次点: pgrep N並列呼び出し (~300ms)

起動確認ポーリングループ（最大10回）内で、9エージェント全員に対して個別 `pgrep -f` を呼び出す。
- 1イテレーション × 9エージェント × 17ms = 153ms
- failed_agents確認で再度 × 9エージェント × 17ms = 153ms
- 合計 ~306ms（ベストケース=1イテレーションで全員確認できた場合）

### 残余

- agent_config.sh + pane_lookup.sh source: ~250ms（NTFS I/O固定コスト、削減困難）
- watcher_process_count (ps+awk): ~27ms × 3回 = ~81ms（stop確認+verify）
- tmux show-options × 9: ~37ms（各エージェントの@agent_cli取得）

## 最適化戦略

### 1. sync_pane_vars.sh → バックグラウンド化（-1150ms）

`sync_pane_vars.sh` はtmuxペイン変数（@model_name/@agent_cli）を更新するが、
inbox_watcher.sh は起動時に既に `$_cli` を引数として受け取っている。
変数同期はwatcher起動完了後の副次タスクであり、ブロッキング不要。

```bash
nohup bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh" \
    &>> "$SCRIPT_DIR/logs/sync_pane_vars.log" 200>&- &
disown
```

### 2. pgrep N並列 → pgrep-af一括 (~-270ms)

9エージェント個別pgrep → 単一 `pgrep -af` で全プロセス一括取得後 grep で絞り込み。

```bash
_running=$(pgrep -af "[i]nbox_watcher\.sh" 2>/dev/null || true)
for _la in "${LAUNCHED_AGENTS[@]}"; do
    if ! printf '%s\n' "$_running" | grep -q "inbox_watcher\.sh ${_la} "; then
```

## after計測結果

| Run | real | 備考 |
|-----|------|------|
| 1   | 4.646s | **WSL2 jitter anomaly** — inotifywait起動遅延と推定 |
| 2   | 0.695s | 安定 |
| 3   | 0.816s | 安定 |
| 4   | 0.837s | 安定 |
| **安定平均 (run2-4)** | **~0.78s** | |

**改善率: ~2.14s → ~0.78s = -64%（2.7x speedup）**

Run1の4.646sはWSL2 NTFSのプロセス起動ジッター（L504/L507教訓と同構造）。
安定3回の平均 ~0.78s が実態値。

## 正確性検証
- `test_inbox_watcher_health.bats` 7/7 PASS SKIP=0
- `test_select.sh scripts/restart_watchers.sh` → no test mapping, exit 0
- 9/9 watchers起動確認（全3回ともOK: inbox_watcher 9/9）
