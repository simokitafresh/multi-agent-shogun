# デーモンP3ベースライン計測 (cmd_3969, 2026-07-15)

計測実行: tobisaru | 計測日時: 2026-07-15 20:40〜21:10 JST(家老RC反映のため再検証・訂正含む) | scope: **計測のみ**(改善実装は本cmd範囲外、軍師レビューでも確認済み)

> **改訂履歴**: 初稿(20:50)提出後、家老レビューで5点の事実誤認(§1配達レイテンシの名称解釈、§3 inbox_watcher重複説、daemon_supervisor未検知説、ninja_monitor重複83%の一般化、stale lock 201件の単純カウント)を指摘され、コード再読・プロセス再検証の上で訂正した。訂正箇所は本文中に明記。

対象4項目: (1) inbox_watcher.sh配達レイテンシ (2) CTX:?%発生率と原因 (3) /tmp orphanプロセス・stale lock (4) ディスク/メモリ現況

---

## §1 配達レイテンシ(初回未読検知→nudge送達、busy-gating込み)

**【2026-07-15 21:xx 訂正】** 当初「inbox_write書込み→nudge送達の経過秒」の近似値としてこの指標を扱ったが、家老指摘により不正確と判明。`[DELIVERY-LATENCY]`は`first_unread_seen`(初回未読検知時刻)から`send_wakeup()`成功(nudge送達)までの経過秒であり、その内訳の大半は**busy gatingによる意図的な待機時間**(受信側がbusyなら優先度別デッドラインまで送信を保留する設計、L781-813)である。「inbox_write実行→検知」自体の遅延ではなく、「検知→配達」の遅延(うち大半はbusy-gating待機)を表す指標として正しく解釈すべき。「配達レイテンシ」という呼称も、単純な処理遅延ではなくbusy-gating込みの設計上の待機を含む点に注意。

**計測方法**: inbox_watcher.shは`send_wakeup()`成功時に`[DELIVERY-LATENCY] <agent>: <N>s from first-unread to delivery (<count> unread)`を既にstderr(→daemon log)に記録している(L987)。`first_unread_seen`はinbox書込み検知直後に記録される一次時刻。

**サンプル**: 本日(2026-07-15)分の全ログエントリ **n=1015**(9エージェント合算、`logs/inbox_watcher_*.log`のJul 15分、WARN行除外)

### 全体統計
| min | median(p50) | p90 | p95 | p99 | max | mean |
|---|---|---|---|---|---|---|
| 0s | 4s | 2237s | 4502s | 6294s | 6788s | 611.6s |

60s(DELIVERY_LATENCY_WARN_SEC閾値)以上を要した配達: 1015件中479件(47.2%)

### エージェント別内訳
| agent | n | median | p95 | max | mean |
|---|---|---|---|---|---|
| karo | 335 | 646s | 6025s | 6788s | 1680.5s |
| gunshi | 282 | 62s | 702s | 1850s | 146.6s |
| shogun | 116 | 1s | 266s | 5704s | 87.6s |
| saizo | 71 | 1s | 104s | 195s | 20.5s |
| hayate | 60 | 1s | 265s | 461s | 46.6s |
| kotaro | 52 | 1s | 140s | 259s | 26.7s |
| kagemaru | 51 | 1s | 5s | 86s | 3.7s |
| tobisaru | 31 | 1s | 73s | 140s | 14.9s |
| hanzo | 18 | 1s | 5s | 6s | 1.7s |

### 解釈
全体p95が4502s(約75分)と長いのはkaro/gunshiの「busy gating」による意図的deferralが支配的。`send_wakeup()`は受信側がbusyの場合、優先度別デッドライン(HIGH=60s/NORMAL=120s/LOW=600s、`inbox_watcher.sh` L91-94)に達するまで送信を保留する設計。karo/gunshiは長時間busyになりやすいロールのため統計上のレイテンシの大半はこの設計上の待機であり、単純な配達バグではない。忍者6名はmedian=1sで、idle復帰が速いため配達も速い。

### 訂正: task.assumptionsの記載は不正確
`task.assumptions.claim`「inbox_watcher.shに配達レイテンシの計測ログは未実装(`grep -c latency scripts/inbox_watcher.sh` → 0件)」は誤り。`grep -c latency`は小文字検索のため、実装済みの`[DELIVERY-LATENCY]`(大文字)を検出できなかっただけ。実際には行987に計測ログが実装済み・稼働中で、本日だけで9エージェント合算1015件を記録している。`grep -ci latency`であれば存在を確認できた——大文字小文字を区別しない事前確認の欠如がこの誤assumptionの原因。lesson candidate化。

---

## §2 CTX:?%発生率と原因

### 訂正: 発生源はusage_statusbar_loop.shではない
task purposeの前提「usage_statusbar_loop.shのCTX:?%頻発」は誤帰属。`usage_statusbar_loop.sh`はtmux status-right(画面下部の`[PJ] | 5H:...% | 7D:...% | 日時`バー)を600秒間隔で更新するデーモンで、出力フォーマットは`5H:...% 7D:...%`のみであり`CTX:`文字列を一切出力しない。本日ログ(`logs/usage_statusbar_loop.log`)のWARN発生は1件のみ(約140サイクル中)、失敗時は"usage_status.sh failed"/"empty output"でスキップするだけで、CTX:?%とは無関係と実測確認した。

実際の"CTX:?%"発生源は以下2箇所:

### (A) karo_snapshot生成 — `scripts/ninja_monitor.sh` `get_context_pct()` (L1227-1315)
**取得コマンド(優先順)**:
1. `tmux show-options -p -t <pane> -v @context_pct`(キャッシュ変数。値が0より大きければ信頼)
2. `tmux capture-pane -t <pane> -p -J -S -30`(直近30行)→ `cli_profiles.yaml`の`ctx_pattern`/`ctx_mode`(usage/remaining/bar)で正規表現抽出
3. フォールバック: `CTX:[0-9]+%` → `Context [0-9]+% used` → `[0-9]+% context left` の順に総当たり

**失敗条件**: 上記(1)(2)(3)すべてで数値抽出できない場合、関数はrc=1で"0"を返し、呼出元(L5516-5521)の`_ctx="?%"`初期値がそのまま残る。

**現況実測(本日20:46、9エージェント全ペイン)**: 全員CTX抽出成功、"?%"発生 **0/9**。ただしkaroで`@context_pct`キャッシュ値(45%)とcapture-pane実値(Context 36% used)に乖離を確認(キャッシュstaleは別問題、本タスク範囲外として記録のみ)。karo_snapshotのCTX:?%はリアルタイム表示のみでログに残らないため、過去の発生率はログからは測定不能(既存インフラのログ化ギャップ)。

### (B) /clear検証 — `scripts/inbox_watcher.sh` L1063-1071(clear_command処理後の検証)
**取得コマンド**: `tmux capture-pane -t <pane> -p -S -5 | grep -oP 'CTX:\K[0-9]+' | tail -1`(直近5行のみ、単一パターン、フォールバックなし)

**失敗条件**: `/clear`送信後8秒待機(`sleep 8`)した時点で直近5行に`CTX:NNN`パターンが出現しない場合、`post_ctx="?"`。

**既知の設計ギャップ(コード実読で確認)**: 分岐は`post_ctx != "0" && post_ctx != "?"`の場合のみWARNを出す。つまり`post_ctx="?"`(抽出失敗=未検証)はWARN対象外となり、`[OK] clear_command verified: <agent> CTX:?%`として「検証成功」扱いでログされる。実際には検証できていないのに成功ログになる、fail-open寄りの分岐。

**過去実測**: `logs/`配下で"CTX:?%"を伴う`[OK] clear_command verified`パターンは今回のgrep該当で約30件(2026-04-12〜2026-06-06、hayate/saizo/kagemaru/hanzo/shogunに分布)。直近(2026-06-06以降)の新規発生は本日調査時点で1件のみ確認(kagemaru 2026-07-09)——発生自体はここ数週間減少傾向(具体的な修正commitは本baseline調査の対象外につき未特定)。

---

## §3 /tmp orphanプロセス・stale lock 棚卸し

### orphanプロセス(実測 2026-07-15 20:29〜21:0x)

**【2026-07-15 21:xx 訂正】** 初稿の「inbox_watcher.sh 9/9重複」「daemon_supervisor.shに検知ロジックなし」は誤りだったため撤回する。「ninja_monitor.sh重複83%」も本番の定常頻度としては使えないため訂正する。以下は再検証後の記述。

**inbox_watcher.sh「子プロセス」は重複ではない(撤回)**: 初稿でPPID=root watcher PIDの新規PID群を「重複稼働」と報告したが誤り。`inbox_watcher.sh`のメインループは`timeout ... inotifywait ... &`に加え、`( while kill -0 "$INOTIFY_PID"; do sleep "$MTIME_POLL_INTERVAL"; ... done ) &`という**forkのみでexecしないサブシェル**をMTIME_POLLフォールバック用に生成する(L1185-1194)。execを伴わないfork直後のプロセスは`/proc/<pid>/cmdline`が親から継承されるため、`ps`上は親と全く同じ`bash inbox_watcher.sh <agent> <pane> <cli>`に見える。実際に再確認したところ、該当PIDは全て`wchan=do_wait`(自身の子=sleep等の終了待ち)で、pollerサブシェル特有の挙動と一致した。`daemon_supervisor.sh`の`ds_inbox_watcher_pids()`(L67-86)はこの構造を織り込み済みで、「親のcmdlineが同一パターンを含む子」を意図的に除外してカウントしている。よって`daemon_supervisor.log`が終始`count=1/1`(重複なし)と記録していたのは正しい判定であり、私が「9エージェント全員で重複稼働中・daemon_supervisorは未検知」と報告したのは誤りだった。

**daemon_supervisor.shのinbox_watcher重複検知ロジックは実在する(撤回)**: `scripts/daemon_supervisor.sh` L245-271に`ds_supervise_inbox_watcher()`があり、`ds_inbox_watcher_pids()`でcount取得→`count>1`なら`ds_stop_duplicates()`(最新PIDを残し他をTERM、10秒待ってKILL)を呼ぶ実装が存在する。「inbox_watcherには重複検知ロジックがない」という初稿の記述は誤り、撤回する。

**ninja_monitor.sh重複「83%」はBats高負荷時の一時的産物(訂正)**: `daemon_supervisor.log`のDUPLICATE検知時刻(20:29:41/20:32:49/20:37:11/20:40:12/20:45:32/20:49:07)は、`/tmp/bats-run-*`ディレクトリのmtime(18:41,19:12,19:17,19:33,19:44,20:19,20:28,20:49,20:59...)とほぼ連続的に重なっている。この時間帯、hanzo(CI RED修正)・saizo(test_asset_catalog等のCI残存FAIL修正)・kotaro(test_gate_shogun_startup 102件のCI修正)が並行してbatsテストスイートを繰り返し実行しており、システム全体のプロセス生成負荷が高い状態だった。したがって「直近16分で83%のサイクルで重複発生」は**本セッション特有の高負荷状況下のデータ**であり、平常時の本番頻度として一般化できない。恒常パターンかどうかは、テスト非実行時間帯での再計測が必要(本baseline未達成、要フォローアップ)。

**ゾンビプロセス(状態Z)**: 0件

**PPID=1(孤立親)の常駐プロセス**: 17件、うち本システム関連は`ntfy_listener.sh`(1件)と`ninja_monitor.sh`(1件、直近の重複kill後の生存側)。他15件はOS標準デーモン(systemd/sshd等)で無関係。

### stale lockファイル(再計測: /proc/locks照合+生存確認)
**【2026-07-15 21:xx 訂正】** 初稿は`/tmp`直下`*lock*`命名ファイル201件を単純カウントし「stale」と記載したが、ファイルの存在自体はflock設計上の正常な永続マーカー(プロセス終了後も削除されない)であり、staleの根拠にならない。家老指摘を受け、`/proc/locks`との照合と所有プロセスの生存確認を行った:

- `/tmp/*lock*`命名ファイル総数: **183件**(初稿201件は"lock"を含む語幹での粗いカウントで条件が異なる。今回は`glob /tmp/*lock*`で再カウント)
- 現時点で`/proc/locks`にactiveなflockとして出現するもの: **0件**(瞬間値。多くの用途はワンショットでflock取得→即解放するため、この値単独では staleの証拠にならない)
- **確認済み現役(稼働中デーモンが保持するsingletonロック)**: 19件——9エージェント分の`inbox_watcher_singleton_*.lock`(現行watcherプロセス生存を実プロセス一覧で確認済み)+`ntfy_listener.lock`(PID 19354生存確認済み)等。これらはmtimeが12時間以上前(=起動時刻)でも、対応デーモンが生きている限り現役
- **個別生存確認が本タスクの計測時間内では未実施(stale候補、要フォローアップ)**: 164件、合計66B(ほぼ全てゼロバイトのフラグファイル)。mtime分布: <5分=18件、5-30分=31件、30分-2時間=34件、2時間超(=本日08:10の/tmp初期化以降蓄積)=81件。命名パターン別内訳(上位): `mas-three-layer-knowledge_*.lock`48件、`shogun_lock_*.lock`37件、`shogun-build-instructions-*.lock`11件、`tmux_sendkeys_*.lock`8件、他少数
- 9エージェント分の`inbox_watcher_singleton_*.lock`/`inbox_watcher_state_*.lock`は現行ロスター(shogun/karo/gunshi/hayate/kagemaru/hanzo/saizo/kotaro/tobisaru)と完全一致——過去ログに見つかった廃止済みエージェント名(例: kirimaru)の残存ロックは**0件**
- WSL2は本日08:10(起動/再起動時刻)に`/tmp`内容がリセットされており(最古ファイルが08:10:45)、複数日にまたがる長期滞留orphanは構造的に存在しない(tmpfs的リセット挙動)
- **方法論の限界**: 164件の「stale候補」全件について対応する所有プロセス/タスクの個別生存確認は本baseline計測の時間枠(推定10分)を超えるため未実施。真のstale件数の確定には、各命名パターンごとに生成元スクリプトを特定し対応プロセスの生死を突合する追加調査が必要

---

## §4 ディスク・メモリ現況

### df -h (2026-07-15 20:4x実測)
| mount | size | used | avail | use% |
|---|---|---|---|---|
| `/` (`/dev/sdd`) | 1007G | 58G | 898G | 7% |
| `/mnt/c` (drvfs) | 928G | 652G | 277G | 71% |

### free -h
| | total | used | free | buff/cache | available |
|---|---|---|---|---|---|
| Mem | 23Gi | 3.9Gi | 12Gi | 7.4Gi | 19Gi |
| Swap | 8.0Gi | 12Ki | 8.0Gi | - | - |

**判定**: ディスク・メモリともに現時点で逼迫なし(root 7%使用、メモリavailable 19Gi/23Gi)。

### /tmp内訳(合計1.9G, 18695アイテム, maxdepth 1)
| 内容 | サイズ/件数 | 備考 |
|---|---|---|
| `shogun_memory_db_cache/` | 1.5G(79%) | 三層記憶DBの一時キャッシュ(.tmp/.dbファイル)。稼働中プロセスの作業ファイルで大半は現用中 |
| `bats-run-*` | 9ディレクトリ, 計約58M | 全て本日18:41以降(直近2時間)。テスト実行中の一時ディレクトリ、稼働中 |
| `shogun-bats.*` | 157ファイル, 計21M | 本日08:41〜現在まで連続発生。自動クリーンアップcron未確認(蓄積傾向) |
| `*lock*`ファイル | 183件, 24KB(確認済み現役19件含む) | 前述§3参照(stale判定は再計測・訂正済み) |

---

## §5 まとめ(改善cmd入力データ)

計測のみのため実装判断はしない。将来の改善cmd起票時の入力候補(判断は将軍/家老に委ねる):

1. **inbox_watcher.sh clear_command検証のfail-open**(`post_ctx="?"`を成功扱いでログ) — 誤検証の温床。ただし直近発生頻度は低下傾向(§2参照)
2. **`shogun-bats.*`ファイルの自動クリーンアップ機構なし**(157件/12h蓄積、要クリーンアップcron検討)
3. **ninja_monitor.sh重複起動とBatsテスト高負荷の相関** — 本セッションでは複数忍者のCI修正作業(bats高頻度実行)と時間的に重なっていた(§3参照)。テスト非実行時間帯での再計測により、恒常パターンか高負荷時限定の現象かを切り分ける追加baselineが必要
4. **task.assumptions等の事前調査でのgrep大文字小文字ミス** — `grep -c latency`(小文字限定)で「未実装」と誤判定した前例(§1)。事前調査grepは`-i`併用または`grep -i`で再確認する運用を推奨
5. **stale lockの真の件数確定** — 164件の候補について命名パターンごとに生成元スクリプトと対応プロセスの生死を突合する追加調査が必要(§3参照)
6. **忍者の一次計測は「二次情報(ps上のcmdline等)を鵜呑みにせず、コード実読+wchan/子プロセス確認まで行う」を徹底する**——本cmdの初稿はps出力の見た目だけで「重複プロセス」と誤断定した。家老指摘で撤回・訂正(lesson_candidate参照)

---
以上、計測ベースライン。改善実装は本cmd範囲外。
