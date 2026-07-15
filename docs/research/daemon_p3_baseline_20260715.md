# デーモンP3ベースライン計測 (cmd_3969, 2026-07-15)

計測実行: tobisaru | 計測日時: 2026-07-15 20:40〜20:50 JST | scope: **計測のみ**(改善実装は本cmd範囲外、軍師レビューでも確認済み)

対象4項目: (1) inbox_watcher.sh配達レイテンシ (2) CTX:?%発生率と原因 (3) /tmp orphanプロセス・stale lock (4) ディスク/メモリ現況

---

## §1 配達レイテンシ(inbox_write書込み→nudge送達)

**計測方法**: inbox_watcher.shは`send_wakeup()`成功時に`[DELIVERY-LATENCY] <agent>: <N>s from first-unread to delivery (<count> unread)`を既にstderr(→daemon log)に記録している(L987)。`first_unread_seen`はinbox書込み検知直後に即記録される一次時刻のため、このログ値は「書込み→nudge送達」レイテンシの妥当な近似値として使える。

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

### orphanプロセス(実測 2026-07-15 20:29〜20:50)

**ninja_monitor.sh重複(daemon_supervisor.shが自動検知・kill中)**: 本日ログで直近6サイクル(20:29:41〜20:45:33、実質16分間)中**5回(83%)**で`DUPLICATE: ninja_monitor.sh count=2`を検知しTERM送信。恒常的に発生している既知パターン。supervisorが毎回自動収束させるため実害は限定的だが、「起動→即重複→kill」のサイクルが3-5分間隔で繰り返されている。

**inbox_watcher.sh重複(未検知)**: 9エージェント全員について、本来の長時間稼働プロセス(起動: 本日09:11、PPID=265)に加え、20:46:0x台に新規PIDの子プロセス(PPID=元プロセスPID)が出現し**重複稼働中**(実測時点で継続生存、singleton flockで即終了しない=別ロックファイルパスを取得しているか環境変数差異の可能性)。`daemon_supervisor.log`は20:45:33時点で全員`count=1/1`を記録しており、直後(20:46台)に一斉出現。同時間帯に別プロセス(PID 1198039、`restart_all_daemons.sh`関連コマンド実行中のbash、PPID=759077)が稼働していたことと時間的に一致するが、原因は未特定。`daemon_supervisor.sh`にはninja_monitor.sh同様の重複検知・自動killロジックが**inbox_watcherには存在しない**(ログ上、本日"DUPLICATE: inbox_watcher"の記録は0件)ため、放置されると気付かれずに累積する可能性がある。本タスクは計測のみのためkill等の是正は行っていない。

**ゾンビプロセス(状態Z)**: 0件

**PPID=1(孤立親)の常駐プロセス**: 17件、うち本システム関連は`ntfy_listener.sh`(1件、起動から11h35m)と`ninja_monitor.sh`(1件、直近の重複kill後の生存側)。他15件はOS標準デーモン(systemd/sshd等)で無関係。

### stale lockファイル
- `/tmp`直下`*lock*`命名ファイル: **201件**(合計24KB、flock用ゼロバイトファイルが大半)
- 9エージェント分の`inbox_watcher_singleton_*.lock`/`inbox_watcher_state_*.lock`は現行ロスター(shogun/karo/gunshi/hayate/kagemaru/hanzo/saizo/kotaro/tobisaru)と完全一致——過去ログに見つかった廃止済みエージェント名(例: kirimaru)の残存ロックは**0件**
- WSL2は本日08:10(起動/再起動時刻)に`/tmp`内容がリセットされており(最古ファイルが08:10:45)、複数日にまたがる長期滞留orphanは構造的に存在しない(tmpfs的リセット挙動)

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
| `*lock*`ファイル | 201件, 24KB | 前述§3参照 |

---

## §5 まとめ(改善cmd入力データ)

計測のみのため実装判断はしない。将来の改善cmd起票時の入力候補(判断は将軍/家老に委ねる):

1. **inbox_watcher.sh重複プロセス** — 本日20:46台に9エージェント全員で同時発生。原因未特定。`daemon_supervisor.sh`にinbox_watcher重複検知・自動killロジックがない(ninja_monitor.shにはある)ため、放置されると累積する可能性
2. **inbox_watcher.sh clear_command検証のfail-open**(`post_ctx="?"`を成功扱いでログ) — 誤検証の温床。ただし直近発生頻度は低下傾向
3. **`shogun-bats.*`ファイルの自動クリーンアップ機構なし**(157件/12h蓄積、要クリーンアップcron検討)
4. **ninja_monitor.sh重複起動が3-5分毎に高頻度発生**(直近16分で83%のサイクルで検出) — 起動トリガー側の根治要調査
5. **task.assumptions等の事前調査でのgrep大文字小文字ミス** — `grep -c latency`(小文字限定)で「未実装」と誤判定した前例(§1)。事前調査grepは`-i`併用または`grep -i`で再確認する運用を推奨

---
以上、計測ベースライン。改善実装は本cmd範囲外。
