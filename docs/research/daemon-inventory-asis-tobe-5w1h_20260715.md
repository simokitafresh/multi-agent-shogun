# デーモン棚卸し — AsIs/ToBe 5W1H調査 v1.1 (2026-07-15)

- 起案: 殿指示 2026-07-15 03:33「デーモンの調査ファイルを作成してgistで共有。各デーモンについて別々にasis/tobe 5w1hで改善点をまとめよう」
- レビュー: 殿指示03:42により家老・軍師の覚醒レビュー往復2回。**v1.1=R1反映済み**（家老5点=blt_034628、軍師6点=blt_034642）。R2待ち
- 一次データ: `ps -ef`実測(03:34) + cron設定 + 各ログ現物 + 本セッションの実事故 + ninja_monitor.log（R1で家老が突合）
- 正本: 本ファイル。gist: 2232467c4928227cddaea75e8af6404a

## §0 全体像（実測 03:34 JST、監視区分はR1家老指摘3で三分類）

| デーモン | プロセス数 | 稼働形態 | 監視区分（現状） | 状態 |
|---|---|---|---|---|
| inbox_watcher.sh | 9（agent別） | 常駐（restart_watchers.sh起動、専用lock有） | **要実測**: watchdog対象への9本包含は未突合（軍師R1） | ✅ 稼働 |
| ninja_monitor.sh | 1（+子） | 常駐 | 要確認 | ✅ 稼働 |
| ntfy_listener.sh | 1（+curl子） | 常駐 | supervised（HEALTH-OK記録あり、ただしタイムライン注意=§3） | ✅ 稼働 |
| usage_statusbar_loop.sh | 1 | 常駐 | not-covered疑い | ✅ 稼働（CTX:?%頻発） |
| gist_sync.sh | 1（dashboard用） | 常駐 | not-covered疑い | ✅ 稼働 |
| daemon_watchdog.sh | 0（毎分cron） | cron | **watchdog自身の監視者なし**（軍師R1: crontab破損時に誰も気づかない） | ⚠️ 実バグ発現中（§6） |
| daemon_supervisor.sh | 0 | 非常駐script | — | ⚠️ entry point 4系統併存 |

**監視区分の定義（ToBe側で確立する三分類・家老R1-3）**: (a) supervised+auto-restart（死活判定→自動再起動まで） (b) inventory-WARN-only（登録漏れ・停止をWARN通知のみ——cmd_3951の突合検査はここ） (c) not-covered。**「全デーモンの死活が正しく判定される」はcmd_3951だけでは過大**——cmd_3951後も(b)止まりのデーモンが残る。

**横断所見（R1で強化）**:
1. **監視の非対称（軍師R1で数値化）**: 7デーモン中HEALTHログを持つのはntfy_listener等に限られ、**約4/7がHEALTHログなし=約57%が監視外**。さらにwatchdog自体がバグ発現中のため現時点の実効監視率は不明（0%に近い可能性）。HEALTH-OK記録（07-14 22:20）はバグ発現確認（07-15 03:34ログ）より前で、**「今も監視できているか」は未確認**——cmd_3951 AC1の修正後実行が最初の確認点。
2. **tmux session単一障害点（軍師R1追加）**: tmux serverが死ぬと9 watcher+monitorの全pane構成が無音消失。watchdog対象にtmux health checkがない → P1相当で追加。
3. **status/restartの同居（実バグ）**: `restart_watchers.sh --status`が非対応フラグを無視して**全再起動を実行**（03:34将軍実測・実害なし）→ P1独立緊急cmd（家老R1-5: P0同梱せず依存なしで並行）。
4. **maintenance lock不足（家老R1-4）**: manual restartとwatchdog自動再起動の競合を防ぐ共通lock/markerがwatcher系（restart_watchers.lock）にしかない。全daemon共通のmaintenance markerが必要。改善後の再起動は必ずrestart script→post-restart inventory検証の順。
5. .bakファイル5本残存（2026-05-29付）= 清掃対象。

---

## §1 inbox_watcher.sh（×9、通信の心臓）

- **WHAT(AsIs)**: agent別に`queue/inbox/{agent}.yaml`の変更を検知し、短いnudge（`inboxN`）をtmux send-keysで送る。WSL2 /mnt/c上のためinotify不可→statポーリング。1220行。
- **WHO/WHERE**: 全9エージェントの唯一の起こし役。restart_watchers.shが起動・9/9管理（専用lockあり）。
- **WHEN**: 常時。メッセージ永続はinbox_write.sh（flock）側が保証、watcherは配達のみ。
- **WHY**: 配達保証をファイル、wake-upをnudgeに分離——watcher死亡でもメッセージは失われない（03:34の全再起動で実証）。
- **実績**: INPUT-GUARD保留nudge再注入（07-10 CLEAR）、一括既読Lost-Message（07-14 d8777d36c根治）。
- **ToBe / HOW（改善点）**:
  1. 配達レイテンシの計測ログ化（スクリプト速度レーン弾候補、P3）
  2. **watchdog対象リストへの9本包含を実測突合**（軍師R1: 未実測。cmd_3951 AC2の突合検査で確定）
  3. **restart_watchers.shに再起動ループ防止（backoff/max restarts）がない**（軍師R1）: 起動即死の繰り返しで無限再起動になりうる。P1aへ同梱
  4. 9プロセス統合の是非は実測比較で判断（単一障害点化とのトレードオフ）

## §2 ninja_monitor.sh（7211行、最大・最重要）— R1家老指摘2で時系列訂正

- **WHAT(AsIs)**: idle検知→無条件/clear、修行弾自動配備、dead pane検知・respawn、karo_snapshot生成、CI RED検知ほか多機能。7211行=デーモン中最大。
- **WHO/WHERE/WHEN/WHY**: 忍者6+家老のライフサイクル全自動管理。常時ループ。
- **今夜の事故の正確な時系列（家老がninja_monitor.logで一次突合・v1.0の記述を訂正）**:
  - 03:09 respawn-pane -k後のCLI起動失敗でdead 3/6発生
  - **monitor自動復旧は機能した**: saizo 03:13:14・tobisaru 03:14:50にCODEX-RESPAWN成功。v1.0の「自動復旧が効かずdead-only scriptで復旧」は一括表現として誤り（家老の並行復旧と混在していた）
  - **真の問題**: 初回respawn失敗後の (a)復旧まで数分の遅延 (b)respawn直後の成否検証と即時再試行の不足
  - GA259（dead pane復旧のontology化）は**commit 1cfa0e2f6・unit 2/2・ontology 1/1で完了済み**
- **運用上の不変量（家老R1-4——dead復旧改修時に壊してはならない契約）**:
  - `can_send_clear_with_report_gate`・REPORT-MISSING-BLOCK・auto_deploy順序 = commit/report/通知前の/clearとtask上書きを防ぐ
  - dead復旧の統合時は: live pane拒否・task YAML不変更・SSOT get_ninja_names・**post-respawn CLI実在確認**を維持
- **ToBe / HOW（改善点）**:
  1. **respawn成否の即時検証+バックオフ付き再試行**（3者協議提案C）。GA259成果（1cfa0e2f6）を土台に**既存monitor経路を磨く**（新しい箱を作らない）
  2. 7211行の分割は速度レーンで支配項計測→機能単位lib分離
  3. snapshot `CTX:?%`: 取得失敗時のfallbackと理由記録（P3計測弾）

## §3 ntfy_listener.sh（501行、殿との回線）

- **WHAT(AsIs)**: ntfy.sh SSE（curl keepalive 3600s）購読、殿のモバイル入力を将軍へ中継。dual watchdog稼働。
- **WHEN/WHY**: 常時。外出時の指揮継続。
- **実績と注意（軍師R1）**: HEALTH-OK記録は07-14 22:20=watchdogバグ発現確認（07-15 03:34）より**前**。現時点で監視が機能しているかは未確認——「supervised」区分は**cmd_3951修正後の実行で再確認**するまで暫定。
- **ToBe / HOW**:
  1. 3600s再接続境界の取りこぼし有無を一次検証（since=再取得の実装確認）
  2. 受信→記録→配達のE2E突合台帳化

## §4 usage_statusbar_loop.sh（145行、計器盤）

- **WHAT(AsIs)**: 各paneのCTX使用率等をtmuxステータスへ反映。
- **問題**: `CTX:?%`頻発=取得失敗の無音通過。監視区分はnot-covered疑い。
- **ToBe / HOW**: (1)取得失敗率の数値化と原因特定（P3計測弾） (2)ninja_monitorのCTX取得と二重実装ならlib共通化（LS078予防） (3)cmd_3951の突合検査で監視区分を確定（WARN-only想定、auto-restart昇格は実測後判断）

## §5 gist_sync.sh（180行、殿への鏡）

- **WHAT(AsIs)**: dashboard.md変更検知→固定Gistへ自動アップロード。03:36成功ログ=健全。
- **ToBe / HOW**: (1)戦況artifact（HTML正本）との役割整理——**P4bとしてentry point一本化(P4a)と分離して個別裁定**（家老R1-5） (2)gh API失敗時リトライ (3)監視区分の確定（not-covered→WARN-onlyへ）

## §6 daemon_watchdog.sh（毎分cron、番人）— R1家老指摘1で因果を訂正

- **WHAT(AsIs)**: 毎分cronでデーモン死活を確認し自動再起動。**設計意図**: `set -uo pipefail`でset -eを意図的に外し、個別checkの失敗が他checkを止めない造り（家老R1が現物確認）。
- **実測バグ（本番cronログ・事実は不変）**:
  - L251: 算術評価が毎分syntax error（カウント変数への複数行値混入）
  - L84: /proc読み取りとプロセス消滅のrace（ログ汚染）
- **影響範囲の正確な評価（v1.0の過大表現を訂正）**:
  - set -e非依存設計のため、**L251エラー=全監視の空洞化は未証明**。壊れているのは当該checkの判定で、他checkは継続している可能性が高い。実効影響はcmd_3951 AC1の修正前後ログ比較で確定する
  - watchdogは**tmux paneを監視対象にしていない**ため、03:09 dead pane事故の遠因とするv1.0の推定は**削除**（未検証の因果を書かない）
- **軍師R1追加の構造欠陥**:
  - **watchdog自身の監視者なし**: crontab破損・cron停止時にwatchdogが起動しないことを誰も検知しない
  - **tmux health checkなし**: tmux server死=全watcher/monitor無音消失を検知できない（P1相当）
- **ToBe / HOW**:
  1. P0（cmd_3951委任済み）: L251正規化+L84 race修正+監視対象突合検査（**突合はWARN-only**=三分類(b)。auto-restart化は別段）
  2. watchdog自身の健全性: 最終実行時刻をstartup gateが検査（cron停止の検知を人でなくgateに）→ P1b
  3. tmux health check追加 → P1b

## §7 daemon_supervisor.sh（非常駐・管理層）

- **WHAT(AsIs)**: 「統一デーモン管理層」を名乗るが常駐0。起動entry pointが4系統（supervisor/restart_all/個別restart/手動）併存で正が不文書。
- **ToBe / HOW**:
  1. **P1a（独立緊急cmd・依存なし）**: restart系のstatus(読み取り)とrestart(状態変更)の分離+restart_watchersへのbackoff/max restarts追加（03:34実事故+軍師R1の直接対策）
  2. **全daemon共通maintenance lock/marker**（家老R1-4）: manual restartとwatchdog自動再起動の競合防止。restart_watchers.lockの機構を共通化
  3. entry point一本化の裁定は**P1完了後**（家老R1-5の順序）
  4. .bak 5本削除（git履歴が正本）

---

## §8 改善実行の照合表 v1.1（R1反映・LS086準拠）

| 優先 | 改善項目 | 実行形態 | 状態 |
|---|---|---|---|
| P0 | watchdog L251/L84修正+監視対象突合WARN(§6-1) | 将軍cmd | **cmd_3951 委任済み・疾風acknowledged** |
| P1a | restart系status/restart分離+backoff/max restarts+共通maintenance lock(§7-1,2) | **独立緊急cmd（P0同梱せず・依存なし）** | 未起票——R2後に起票 |
| P1b | tmux health check+watchdog自身の健全性検査(§6-2,3) | 将軍cmd | 未起票——R2後に起票 |
| P2 | monitor respawn成否検証+バックオフ再試行(§2-1) | GA259成果(1cfa0e2f6)土台に既存経路を磨く | 3者協議提案C・殿裁定待ち |
| P3 | watcher配達レイテンシ・usage `?%`原因の計測弾(§1-1,§4-1) | スクリプト速度レーン | レーン台帳登録候補 |
| P4a | entry point一本化(§7-3) | 殿裁定事項 | **P1完了後に判断** |
| P4b | gist_sync役割整理(§5-1) | 殿裁定事項（P4aと分離） | 言上済み |
| backlog | リソース枯渇監視(CPU/mem/IO)・SLA/RTO定義・orphanプロセス棚卸し（軍師R1追加gap） | 設計判断要 | R2の論点 |

## §9 レビュー履歴

- R1家老（blt_20260715_034628）: 5点全反映——§6因果訂正・§2時系列訂正（monitor自動復旧は機能、真因=遅延+成否検証不足）・監視三分類・運用不変量追加・P1独立/P4分離の順序
- R1軍師（blt_20260715_034642）: 6点全反映——tmux単一障害点・watchdog自身の監視・backoff・HEALTH-OKタイムライン・watcher包含未実測・監視外約57%の数値化+backlog 3件
- R2: 依頼中

## 因果リンク

- ← [[殿指示20260715_0333_デーモン調査]]
- → [[ledger-driven-campaign-lane-pattern_20260714]] §5穴7（計測が止まっても検出されない=番人自身の監視不在と同型）
- → [[infrastructure]] デーモン一覧の正本更新先
- ← [[cmd_karo_hotfix_ga259_respawn_dead_agent_ontology]]（1cfa0e2f6完了）§2の土台
- ← [[cmd_3951]] P0実行
