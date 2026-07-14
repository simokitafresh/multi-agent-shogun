# デーモン棚卸し — AsIs/ToBe 5W1H調査 v1.0 (2026-07-15)

- 起案: 殿指示 2026-07-15 03:33「デーモンの調査ファイルを作成してgistで共有。各デーモンについて別々にasis/tobe 5w1hで改善点をまとめよう」
- 一次データ: `ps -ef`実測(03:34) + cron設定 + 各ログ現物 + 本セッションの実事故4件
- 正本: 本ファイル。gist共有。

## §0 全体像（実測 03:34 JST）

| デーモン | プロセス数 | 稼働形態 | 状態 |
|---|---|---|---|
| inbox_watcher.sh | 9（agent別）+親子 | 常駐（restart_watchers.sh起動） | ✅ 稼働 |
| ninja_monitor.sh | 1（+子） | 常駐 | ✅ 稼働（今夜respawn失敗事故あり） |
| ntfy_listener.sh | 1（+curl keepalive子） | 常駐 | ✅ 稼働 |
| usage_statusbar_loop.sh | 1 | 常駐 | ✅ 稼働（CTX:?%頻発） |
| gist_sync.sh | 1（dashboard用 6eb495d9） | 常駐 | ✅ 稼働（03:36 sync成功ログ） |
| daemon_watchdog.sh | 0（毎分cron） | cron | ⚠️ **稼働するがバグ発現中** |
| daemon_supervisor.sh | 0 | 非常駐（管理層script） | ⚠️ 役割がwatchdog/restart系と重複疑い |

**横断所見（全デーモン共通の構造問題）**:
1. **監視の非対称**: watchdogの監視対象確認が必要（ntfy_listenerはHEALTH-OK記録あり、他デーモンのHEALTH記録は要確認）。監視されないデーモンは死んでも発覚が遅れる（テスト時間台帳writer停止と同型=「計測が止まっても検出されない」）。
2. **status/restartの同居**: `restart_watchers.sh --status`が非対応フラグを無視して**全再起動を実行**（03:34将軍が実測・実害なしだが、確認のつもりの操作が状態変更になる構造は危険）。
3. **.bakファイル5本残存**（daemon_supervisor×2・inbox_watcher×1・restart_watchers×2・ninja_monitor×1、2026-05-29付）= 清掃対象。

---

## §1 inbox_watcher.sh（×9、通信の心臓）

- **WHAT(AsIs)**: agent別に`queue/inbox/{agent}.yaml`の変更を検知し、短いnudge（`inboxN`）をtmux send-keysで送る。WSL2 /mnt/c上のためinotify不可→statポーリング。1220行。
- **WHO/WHERE**: 全9エージェントの唯一の起こし役。restart_watchers.shが起動・9/9管理。
- **WHEN**: 常時。メッセージ永続はinbox_write.sh（flock）側が保証、watcherは配達のみ。
- **WHY(現行設計の理由)**: 配達保証をファイル、wake-upをnudgeに分離——watcher死亡でもメッセージは失われない（03:34の全再起動で実証）。
- **実績(今週の事故と根治)**: INPUT-GUARD保留nudge再注入（07-10 CLEAR済み）、一括既読Lost-Message（07-14 d8777d36cで個別msg_id必須化）。
- **ToBe / HOW（改善点）**:
  1. statポーリング間隔と実測遅延の計測データが台帳にない → 配達レイテンシを計測ログ化（スクリプト速度レーンの弾候補）
  2. 9プロセスが同一コードを並走 → 単一プロセスで9 inboxを監視する統合の是非を実測比較（プロセス数1/9、ただし単一障害点化とのトレードオフを数値で判断）
  3. watchdogの監視対象に9本全部が入っているかの検査を追加

## §2 ninja_monitor.sh（7211行、最大・最重要）

- **WHAT(AsIs)**: idle検知→無条件/clear、修行弾自動配備（速度レーンの駆動装置）、dead pane検知・respawn、karo_snapshot生成、CI RED検知ほか多機能。7211行=デーモン中最大。
- **WHO/WHERE**: 忍者6+家老のライフサイクル管理。tmux paneが作業対象。
- **WHEN**: 常時ループ。
- **WHY**: CTX管理・配備の全自動化（エージェントは何もするな原則）の実装本体。
- **実績(今夜の事故)**: 03:09 respawn-pane -k実行後のCLI起動失敗で**dead pane 3/6**が発生、monitorの自動復旧が効かず家老の新規dead-only復旧スクリプトで復旧（GA259としてontology cmd進行中）。
- **ToBe / HOW（改善点）**:
  1. **respawn失敗のリトライ経路**（3者協議・提案C、殿裁定待ち）: respawn後のCLI起動成否を確認し、失敗ならバックオフ付き再試行+家老へエスカレーション
  2. **7211行の分割**: idle検知・配備・snapshot・dead復旧は責務が別。速度レーン（cmd_3920系）で支配項計測→機能単位のlib分離が筋
  3. snapshot鮮度: `CTX:?%`表示が頻発（今夜のsnapshotで多数実測）→ CTX取得失敗時のfallbackと「?の理由」記録
  4. dead-only復旧scriptがmonitor本体と別立てになった → monitorの正規経路へ統合（新しい箱を作らない）

## §3 ntfy_listener.sh（501行、殿との回線）

- **WHAT(AsIs)**: ntfy.sh SSE（curl keepalive 3600s）を購読し、殿のモバイル入力を将軍へ中継。dual watchdog稼働（MEMORY.md記録済み）。
- **WHO/WHERE**: 殿→将軍の外出時唯一の入力経路。
- **WHEN**: 常時。curl max-time 3600で1時間ごと再接続。
- **WHY**: 外出時の指揮継続。dual watchdogは過去の無音死対策。
- **実績**: daemon_watchdog_cron.logに`HEALTH-OK: ntfy_listener.sh count=1/1`（07-14 22:20）=死活監視は機能。
- **ToBe / HOW（改善点）**:
  1. 再接続の隙間（3600s境界）のメッセージ取りこぼし有無を一次検証（since=パラメータでの再取得が実装済みかコード確認→なければ追加）
  2. 受信→lord_conversation記録→将軍nudgeの配達確認をE2Eで台帳化（受信件数と配達件数の突合）

## §4 usage_statusbar_loop.sh（145行、計器盤）

- **WHAT(AsIs)**: 各paneのCTX使用率等をtmuxステータス表示へ反映するループ。
- **WHO/WHERE**: 殿と将軍の目視計器。ninja_monitorのCTX判断とは別系統。
- **WHEN**: 常時ループ。
- **WHY**: CTX枯渇（今夜の家老83%等）の早期視認。
- **実績(問題)**: snapshotに`CTX:?%`が頻発——取得失敗が無音で通過し、計器として信頼を落としている。
- **ToBe / HOW（改善点）**:
  1. `?%`の発生原因（CLI出力パース失敗か、タイミングか）を計測ログで特定し、取得失敗率を数値化
  2. ninja_monitorのCTX取得と二重実装なら共通lib化（真実の在処不一致=LS078の予防）

## §5 gist_sync.sh（180行、殿への鏡）

- **WHAT(AsIs)**: dashboard.mdの変更検知→固定Gist(6eb495d9)へ自動アップロード。`--once`と常駐の2モード。
- **WHO/WHERE**: 殿がモバイルで戦況を見る経路の一つ。
- **WHEN**: 変更検知時（03:36成功ログ確認済み=健全）。
- **WHY**: dashboard=殿が自分で見るもの、の外出版。
- **ToBe / HOW（改善点）**:
  1. 対象がdashboard.md 1本に固定 → 戦況artifact（HTML正本）との二重管理になっていないか整理（役割が重複するなら片方へ寄せる、殿の閲覧動線に合わせて裁定事項）
  2. gh API失敗時のリトライとwatchdog監視対象化の確認

## §6 daemon_watchdog.sh（毎分cron、番人）— **バグ発現中**

- **WHAT(AsIs)**: 毎分cronでデーモン死活を確認し自動再起動。
- **実測バグ(cron実ログ 2026-07-15)**:
  - `line 251: ((: 0\n0: syntax error in expression` — **カウント変数に複数行値が混入**して算術評価が毎分エラー（判定が正しく機能していない疑い＝監視の空洞化）
  - `line 84: /proc/16740/cmdline: No such file or directory` — プロセス消滅とチェックのrace（無害だがログ汚染）
- **WHY(重大性)**: 番人が病むと全デーモンの死が無音化する。今夜のdead pane 3/6が5分超放置された遠因の可能性もある（要因果確認）。
- **ToBe / HOW（改善点・最優先）**:
  1. **L251の複数行値混入を即修正**（count取得のpgrep出力を`head -1`/`tr -d`で正規化）+ L84のrace を`2>/dev/null`ではなく存在確認付き読み取りへ
  2. 監視対象リストと実デーモン一覧（本書§0）の突合検査を追加——「登録漏れデーモン」を検出
  3. watchdog自身の健全性（エラー行数/日）をstartup gateへ1行表示（番人の番人は人ではなくgateに）
- **改善実績(本調査起点)**: cmd_3951として即時修正を起票する（下記照合表）。

## §7 daemon_supervisor.sh（非常駐・管理層）

- **WHAT(AsIs)**: 「統一デーモン管理層」を名乗るscriptだが常駐プロセス0。restart_all_daemons.sh・restart_watchers.sh・restart_monitor.sh・restart_ntfy_listener.shと役割が重複気味。
- **WHY(疑問)**: 起動entry pointが4系統（supervisor/restart_all/個別restart/手動）あり、「どれが正か」が文書化されていない。
- **ToBe / HOW（改善点）**:
  1. entry pointの一本化裁定（supervisorを正とするか、restart_all_daemonsを正とするか）→ 他はwrapperか削除
  2. **status(読み取り)とrestart(状態変更)の分離**: 全restart系scriptに`--status`(dry)を必須実装。03:34の実事故（status確認のつもりが全watcher再起動）の直接対策
  3. .bakファイル5本の削除（git履歴が正本）

---

## §8 改善実行の照合表（LS086: 設計書クローズ時の実装cmd照合）

| 優先 | 改善項目 | 実行形態 | 状態 |
|---|---|---|---|
| P0 | watchdog L251/L84バグ修正+監視対象突合検査(§6-1,2) | 将軍cmd起票 | cmd_3951（本書クローズ時に起票） |
| P1 | restart系のstatus/restart分離(§7-2) | 同上またはP0に同梱判断は家老 | 未起票（P0のGATE後） |
| P2 | ninja_monitor respawnリトライ(§2-1) | 3者協議・提案C | 殿裁定待ち（GA259と統合可能性） |
| P3 | inbox_watcher配達レイテンシ計測(§1-1)・usage `?%`原因計測(§4-1) | スクリプト速度レーン弾 | レーン台帳へ登録候補 |
| P4 | entry point一本化裁定(§7-1)・gist_sync役割整理(§5-1) | 殿裁定事項 | 本書で言上 |

## 因果リンク

- ← [[殿指示20260715_0333_デーモン調査]]
- → [[ledger-driven-campaign-lane-pattern_20260714]] §5穴7（計測が止まっても検出されない=watchdog空洞化と同型）
- → [[infrastructure]] デーモン一覧の正本更新先
- ← [[cmd_karo_hotfix_ga259_respawn_dead_agent_ontology]] §2 dead pane事故の並行是正
