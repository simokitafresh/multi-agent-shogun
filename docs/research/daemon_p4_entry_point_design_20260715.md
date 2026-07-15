# daemon P4 管理層設計（2026-07-15）

## §1 結論

- 正本 entry point は `scripts/daemon_supervisor.sh` とする。通常の定期監視・欠落復旧・重複排除はここへ集約する。
- `scripts/restart_all_daemons.sh` と `scripts/restart_watchers.sh` は、保守作業時に明示的な全停止・全再起動が必要な場合だけ使う thin wrapper とする。task記載の `restart_all.sh` は現物になく、実体は `restart_all_daemons.sh` である。
- 手動の `nohup ...` 起動は禁止入口とし、runbookから supervisor または保守 wrapper を呼ぶ。個別 daemon の start 実装は supervisor の関数へ一本化する。
- `gist_sync.sh` と戦況 artifact は統合しない。前者は運用ビューの配送、後者はHTML正本から生成する説明成果物で、正本・対象・トリガー・失敗影響が異なる。

## §2 entry point の As-Is

| 入口 | 呼出し関係・対象 | 実行頻度/トリガー | 依存・問題 |
|---|---|---|---|
| `daemon_supervisor.sh` | inbox watcher 9本、ninja monitor 1本、ntfy listener 1本を数え、0本を内蔵start関数で起動、重複を最新1本へ収束 | `daemon_watchdog.sh` の監視サイクルから定期実行。`logs/daemon_supervisor.log` の2026-07-15実績は概ね3分間隔 | tmux pane、agent_config、pane_lookup、maintenance lock、ntfy。差分起動で停止時間が最小 |
| `restart_watchers.sh` | 全watcherをTERM/KILL後、shogun+全agentを再生成し9/9とinotifywaitを確認 | reset_layout後、watcherコード更新または明示保守時 | flock、memory DB cache、tmux、agent_config。正常watcherも全停止するため通常復旧には過大 |
| `restart_all_daemons.sh` | restart_monitor、restart_watchers、restart_ntfy_listenerを並列起動 | 全daemonの明示保守時のみ | 3 wrapperの成功に依存。taskの `restart_all.sh` は不存在で名称不一致 |
| 手動起動 | `nohup bash scripts/{inbox_watcher,ninja_monitor,ntfy_listener}.sh ... &` | 障害時の臨時操作 | PID/lock/agent引数/ログ先を操作者が再実装し、重複・設定差・記録欠落を生む |

呼出元の一次証拠: `daemon_watchdog.sh` は inventory と supervisorを持ち、`reset_layout.sh` は `restart_watchers.sh` を呼ぶ。`cmd_complete_gate.sh` は `gist_sync.sh --once` を呼ぶ。daemon supervisor自身はgist_syncを監視対象にしておらず、watchdog inventoryが `gist_sync.sh:1` を別途確認する。

## §3 To-Be

1. `daemon_supervisor.sh` をdaemon lifecycleの唯一の正本にし、`status|ensure|restart <name|all>` の操作契約を持たせる。
2. start/stop/count/verifyを同正本内に置き、`restart_watchers.sh` と `restart_all_daemons.sh` はmaintenance lock取得後に同CLIを呼ぶだけの互換wrapperへ縮退する。
3. `reset_layout.sh`、watchdog、runbookは同CLIだけを呼ぶ。直接nohupはテストfixtureを除き残存0件をgateで検査する。
4. 移行時は `restart_all.sh` という不存在名を正規名 `restart_all_daemons.sh` に訂正し、将来は互換wrapper名を増やさない。

配置二値基準: lifecycle実装は正本1ファイル、運用wrapperは2ファイル、直接起動する本番呼出元は0件。maintenance lock、単体差分復旧、全体再起動、重複収束の既存contractを維持する。

## §4 gist_sync と戦況 artifact

| 項目 | `gist_sync.sh` | 戦況 artifact |
|---|---|---|
| 正本/対象 | `dashboard.md` をproject別Gistの `dashboard.md` へPATCH | HTML正本をClaude artifactとして提示する説明成果物 |
| trigger | WSL2ではmtimeを5秒pollし3秒debounce、Linuxではinotify。cmd完了時は`--once` | HTML正本の明示更新・公開時 |
| 消費者 | 殿が見るリアルタイム運用ビュー | 設計/戦況を読む人向けの固定された表現 |
| 鮮度契約 | 継続同期、配送失敗は運用可視性低下 | 版を明示し再現可能性を優先 |

設計案は分離維持とする。共通化するのは「正本path・生成時刻・配送先・最終成功時刻・失敗理由」という配送manifestだけであり、watch loopやcontent生成は共有しない。dashboard要約をartifactの入力にせず、HTML正本をGist同期へ混入させない。

## §5 実測とSLA/RTO案

一次ログから確認できる値:

- watchdog heartbeat freshness gate: `max_age=300s`。2026-07-15のPASS記録は18:05:00、19:22:30、19:54:44。
- supervisor定期観測: 20:29:40→20:32:43は183秒、20:33:28→20:37:09は221秒、20:37:09→20:40:10は181秒。観測上限は約5分として扱う。
- supervisor内の欠落検出→start: ninja_monitorは21:02:25同秒、ntfy_listenerは22:18:04同秒。ログ秒粒度で0秒、検出後起動RTOは1秒以内。
- dead pane検出→respawn指示: 19:22:24のshogunは同秒、hayateは19:22:24→19:22:25、残りも最大3秒（19:22:24→19:22:27）。観測6件の最大3秒。
- watcher全体再起動のコード上限: TERM待機最大1秒、必要時KILL待機最大1秒、起動確認最大1秒、inotify確認最大2秒で合計5秒（実処理時間を除く）。個別supervisor復旧は同一走査内。

提案SLA:

- heartbeat鮮度: 99.9%の観測で300秒未満。300秒以上は即WARN。
- dead pane: 検出後5秒以内にrespawn指示（実測最大3秒へ2秒margin）。
- daemon process欠落: 検出後2秒以内にstart、次回観測まで含むend-to-end RTOは302秒以下（300秒観測周期+2秒起動）。
- watcher明示全体再起動: 10秒以内に9/9かつinotify 9/9（コード上限5秒へ2倍margin）。
- gist配送: WSL2通常変更は5秒poll+3秒debounce+API時間なので、ローカル変更検知8秒以内、API成功を含むSLA 15秒。`--once` は30秒以内。artifactは継続同期SLAの対象外で版と生成時刻を保証する。

母数上の注意: dead paneの同時障害実測は6 agent、supervisor欠落startはninja_monitor/ntfy_listener各事例であり、長期percentileを断定できる母数ではない。上記は現行timeoutと観測最大値から置く初期SLOで、以後 `detected_at/restart_started_at/healthy_at` を構造化ログ化してp50/p95/p99を更新する。

## §6 検証

- `test -s docs/research/daemon_p4_entry_point_design_20260715.md`
- 4入口、2配送系、SLA/RTO 5項目を本資料で二値確認。
- docs/data-only設計タスクのため実行testは免除。コードbehaviorは変更していない。
