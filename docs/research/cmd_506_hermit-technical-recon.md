# cmd_506 仙人heartbeat実装方式 + OpenClaw調査（sasuke）

- fetched_at: 2026-03-04 01:03 JST
- scope: OpenClaw heartbeat実装の実地調査 + 我ら(WSL2 + tmux + mailbox)への適用可否判定
- independence: 他忍者報告は未参照

## 1) OpenClaw heartbeat実装の要点

### 観測A: 起床トリガーは「coalescing queue + retry」
- `requestHeartbeatNow()` は wake理由をキュー投入し、短いcoalesce待機後に実行。
- 同一target(agent/session)は優先度で上書き（ACTION > DEFAULT > INTERVAL > RETRY）。
- 実行中または main lane busy (`requests-in-flight`) 時は再キューして retry。

根拠:
- https://github.com/openclaw/openclaw/blob/main/src/infra/heartbeat-wake.ts

### 観測B: 定期起床は setTimeout ベースの nextDue 管理
- heartbeat runnerは各agentの `nextDueMs` を持ち、最短nextDueへ `setTimeout`。
- タイマー満了時に `requestHeartbeatNow({ reason: "interval", coalesceMs: 0 })`。
- disabled/quiet-hours/busy時は `skipped` として戻し、次スケジュールへ進む。

根拠:
- https://github.com/openclaw/openclaw/blob/main/src/infra/heartbeat-runner.ts

### 観測C: 「起床→処理→眠る」サイクル
1. wake理由キュー投入
2. 実行可否判定（enabled, activeHours, queue busy）
3. heartbeat prompt実行
4. `HEARTBEAT_OK` の場合は外部通知抑制 + transcript prune
5. schedule更新して次回待機

根拠:
- https://github.com/openclaw/openclaw/blob/main/src/infra/heartbeat-runner.ts

### 観測D: 記憶の永続化は「セッション/トランスクリプト永続 + system eventは揮発」
- セッションストア/トランスクリプトはファイルに保持し、heartbeatで更新。
- 一方 `system-events` は in-memory queue（意図的に非永続）。

根拠:
- https://github.com/openclaw/openclaw/blob/main/src/infra/heartbeat-runner.ts
- https://github.com/openclaw/openclaw/blob/main/src/infra/system-events.ts

## 2) 我ら環境での実装候補比較（WSL2 + tmux）

環境実測:
- `systemd` 稼働中（PID1=systemd, `systemctl is-system-running` = running）
- `cron` active/enabled
- `codex`/`claude` CLIともに非対話実行オプションあり（`codex exec`, `claude -p`）

| 方式 | 実装像 | Pros | Cons | 実現性 |
|---|---|---|---|---|
| cron + CLI起動 | `cron` で `codex exec` / `claude -p` を定期起動 | 正確時刻・OS標準・復帰容易 | 毎回新規プロセスで文脈連続性が弱い。重複起動制御が必要 | Medium |
| tmuxタイマー(send-keys + sleep loop) | 専用paneで `while true; sleep N; send-keys` | 実装最短、tmux内で完結 | send-keys誤注入リスク。pane崩壊に弱い。既存監視との責務衝突 | Low-Medium |
| bashデーモン(既存ninja_monitor方式) | 常駐スクリプトで状態判定し `inbox_write` 連携 | 既存設計と親和。flock/queue運用を踏襲可 | ポーリング負荷・実装責務が増える | High |
| systemd timer | `systemd --user` timer + oneshot service | 再起動耐性・ログ/監視容易・OS管理下 | WSL設定依存。timer/service作法の初期学習コスト | High |

## 3) OpenClaw方式の適用可否判定

結論: **部分適用が有効（そのまま移植は非推奨）**

- そのまま移植NGの理由:
- OpenClawはGateway中心アーキテクチャで、我らはtmux/mailbox中心。
- OpenClaw `system-events` は揮発設計だが、我らはYAML永続をSSOTにしている。

- 適用価値が高い要素:
- wake理由のcoalescing（同一対象で多重wake抑止）
- busy時retry（`requests-in-flight`相当）
- `HEARTBEAT_OK` 相当のノイズ抑制

## 4) 既存infraとの共存・干渉リスク

既存観測:
- `ninja_monitor.sh` は20秒ポーリング常駐 + idle/STALL監視。
- `inbox_watcher.sh` はinotify event-driven + WSL2 timeout安全網。

根拠:
- `/mnt/c/tools/multi-agent-shogun/scripts/ninja_monitor.sh`
- `/mnt/c/tools/multi-agent-shogun/scripts/inbox_watcher.sh`

| リスク | 具体像 | 対策 |
|---|---|---|
| 二重nudge | heartbeat側と既存watcherが同時再通知 | wake理由fingerprint導入、同一reasonは抑止 |
| send-keys競合 | tmuxタイマー方式で他pane誤注入 | send-keys直叩きを避け、`inbox_write.sh` 経由固定 |
| 監視責務衝突 | ninja_monitorのidle判定とheartbeat起床判定が二重化 | heartbeatは「独立window + 独立state」で分離 |
| 再起動時の欠落 | デーモン停止時に未処理wake喪失 | wake queueをYAML保存（揮発回避） |

## 5) 別window隔離設計（鎖の中と混ざらない）

推奨:
- 新規 `shogun:hermit` window を作成（`shogun:1(main)`, `shogun:2(agents)` とは分離）
- hermit専用stateを `queue/hermit_*` に分離
- 通信は mailboxのみ（`inbox_write.sh`）で実施
- `ninja_monitor` 対象名リストへ hermit を入れない（現状も固定NINJA_NAMESで非対象）

最小I/F:
- in: `queue/hermit_wake.yaml`（reason, requested_at, dedupe_key）
- out: `queue/inbox/karo.yaml` への通知（要約のみ）
- log: `logs/hermit_heartbeat.log`

## 6) 推奨実装方針（段階導入）

1. Phase 1: bashデーモン最小版
- 既存 `inbox_write.sh` を使い、reason coalescing + busy retryのみ実装。

2. Phase 2: systemd timer/service化
- デーモンの生存監視をOS委譲。WSL再起動耐性を確保。

3. Phase 3: ノイズ抑制
- `HEARTBEAT_OK` 相当判定と重複通知抑制を追加。

最終判定:
- OpenClawの「wake queue + retry + interval scheduler」思想は我らへ**適用可能**。
- ただし実体は Gateway前提を捨て、**mailbox/queue中心へ再設計**するのが最適。
