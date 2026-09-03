## つまり第3回 領域(c) monitor/watchdog/inbox_watcher（kotaro担当）

- 抽出窓: 2026-09-03T04:37:00 〜 2026-09-03T11:01:44（PUBLISHER_SINGLE ON 04:37〜配備時刻）
- 分類軸: ①偽陽性 ②過剰BLOCK ③構造バグ ④循環拘束 ⑤遅いscript・test ⑥Claude↔Codex仕組み差 ⑦サンクコスト過剰複雑化 ⑧影響範囲・依存未解明の浅い対応

### AC1: log source確認と抽出コマンド・件数

`logs/ninja_monitor.log` は07:50:09開始のためwindow前半(04:37〜07:50)は`logs/ninja_monitor.log.2`(〜05:15:17)・`logs/ninja_monitor.log.1`(05:15:19〜07:50:06)を連結して補完した。

```
cat logs/ninja_monitor.log.2 logs/ninja_monitor.log.1 logs/ninja_monitor.log \
  | awk -v s="2026-09-03 04:37:00" -v e="2026-09-03 11:01:44" '{ts=substr($0,2,19); if (ts>=s && ts<=e) print}' \
  > nm_window_full.log
grep -c -- "WAKE-DEFER" nm_window_full.log        # → 0（ninja_monitor.logにこのtagは存在しない。inbox_watcher_*.logにのみ存在）
grep -c -- "HOOK-TRUST" nm_window_full.log        # → 381
grep -c -- "CLEAR-LOOP" nm_window_full.log        # → 111 (CLEAR-LOOP-BLOCK-REOPEN 83 + CLEAR-LOOP-BLOCK-GUARD 28)
grep -c -- "STALL" nm_window_full.log             # → 483 (GATE-STALL-BACKGROUND-SKIP 178 + -START 99 + -DONE 99 rc=0全件 + DEPLOY-STALL-WATCH 5)
grep -c -- "REFLUX-AUTO-SKIP" nm_window_full.log  # → 435
grep "REFLUX-AUTO-BLOCK" nm_window_full.log | grep -c "dirty_fingerprint"   # → 36 (「dirty dispatch blocked」に該当。対のREFLUX-AUTO-DIRTY-NOTIFYも36)
```

```
awk -v s="2026-09-03 04:37:00" -v e="2026-09-03 11:01:44" '{ts=substr($0,2,19); if (ts>=s && ts<=e) print}' logs/daemon_watchdog.log > dw_window.log
grep -ic "restart" dw_window.log     # → 385 ("unhealthy; restart suppressed" 205 + "failed to notify karo..." 内restart言及含む文字列一致。タグ単体ではRESTART=1)
grep -c "RESTART:" dw_window.log     # → 1
grep -ic "reload" dw_window.log      # → 0
grep -ic "unhealthy" dw_window.log   # → 205 ("publisher.sh unhealthy; restart suppressed")
```

```
cat logs/inbox_watcher_*.log | grep "^\[Thu Sep  3" | awk '{t=$4; if (t>="04:37:00" && t<="11:01:44") print}' > iw_window.log
grep -c "\[WAKE-DEFER\]" iw_window.log          # → 752（全件 reason="(busy gating)"）
grep -c "\[OUTSTANDING-LEASE\]" iw_window.log   # → 2（nudge抑止の別tag）
grep -c "\[CONFIRMATION-GUARD\]" iw_window.log  # → 3
grep -c "\[BUSY\]" iw_window.log                # → 711
```
→ nudge抑止 = WAKE-DEFER 752 + OUTSTANDING-LEASE 2 = 754件。confirmation guard = 3件。busy gating = 711件(BUSYタグ)、WAKE-DEFER 752件全てのreasonも"(busy gating)"。

```
wc -l logs/inbox_info_digest.jsonl                                            # → 2290 (全期間)
jq -c 'select(.timestamp >= "2026-09-03T04:37:00" and .timestamp <= "2026-09-03T11:01:44")' logs/inbox_info_digest.jsonl | wc -l   # → 0
jq -r '.timestamp' logs/inbox_info_digest.jsonl | sort -r | head -1                                                                # → 2026-09-02T21:52:23
```
→ window内0件。ファイル自体は非空(2290行)だが最終追記は2026-09-02T21:52:23でwindow開始より約6時間45分前。

### AC2: 事例表

| ID | 時刻 | 事象 | 主分類 | 副分類 | 真因 | 根治済/未根治 | 次の一手 |
|---|---|---|---|---|---|---|---|
| T3-kotaro-01 | 2026-09-02 22:13:03〜2026-09-03 09:23:03(window内は04:37:08〜08:01:01の205件+09:23:03の1件) | daemon_watchdogがpublisher.shを繰り返し"unhealthy"検出しつつ"restart suppressed"としてhealth起因の再起動を一度も実行せず約9時間48分継続。同時刻に「failed to notify karo about publisher.sh health」も同数(205件)発生。08:02以降は`INFO: publisher.sh pid=2581118 live; events stale only (idle), no restart`へ表示が変わり明示的な"healthy"宣言なし。最終的に09:23:03「RESTART: publisher.sh restarted on current code pid=1615411」で再起動(health判定とは異なる"on current code"起因) | ④循環拘束 | ③構造バグ | 未特定。scripts/daemon_watchdog.shのhealth判定・restart-suppression条件とRESTART("on current code")トリガーの関係を未読(本taskは読取り専用recon) | 未根治 | scripts/daemon_watchdog.shのpublisher.sh health-check/restart-suppression条件を読み、なぜhealth-based restartが9時間48分不発だったか、"on current code"再起動が別トリガーである根拠を確認する偵察cmdを起票 |
| T3-kotaro-02 | 2026-09-03 04:38:44〜11:01:14(window内27件、うちcmd_reflux_insight_202609030728_hayateに対し07:53:01〜09:04:03の間に8回反復) | ninja_monitorのCLEAR-LOOP-BLOCK-REOPENがhayateについて、同一new_cmdに対しold_cmd=unknownのまま複数回連続発火(cmd_karo_hotfix_publisher_single_flag_file_202609030257で4回/cmd_reflux_insight_202609030513_hayateで4回/cmd_reflux_insight_202609030614_hayateで6回/cmd_reflux_insight_202609030728_hayateで8回・71分間/cmd_reflux_insight_202609030920_hayateで4回)。同一cmdに対しold_cmdが一度もunknown以外へ更新されない | ④循環拘束 | ③構造バグ | 未特定。old_cmd記録処理(直前cmd_idのstate保持箇所)を未読 | 未根治 | scripts/ninja_monitor.shのCLEAR-LOOP-BLOCK-REOPENでold_cmdを記録・更新する箇所を読み、hayateで恒常的にunknownのまま再発火する条件を特定する偵察cmdを起票 |
| T3-kotaro-03 | window全体(2026-09-03T04:37:00〜11:01:44)で0件、最終追記2026-09-02T21:52:23 | logs/inbox_info_digest.jsonl(info/gate_clear等の判断不要typeを自動既読化して退避する先)がwindow開始から現在まで一度も追記されていない。ファイル自体は非空(2290行)で過去は機能していた形跡があるが直近約6時間45分は無追記 | ⑧影響範囲・依存未解明の浅い対応 | ③構造バグ候補 | 未特定。window内にinfo/gate_clear/heartbeat/status_update/retro_answer type送信自体が0件だったのか、書込みパスが壊れているのかを未切り分け(各エージェントinbox_watcher_*.logの既読化イベントとの照合が必要だが本taskの担当source外) | 未根治 | 各inbox_watcher_*.logの自動既読化(info系type)イベント有無をwindow内で確認し、「送信0件」か「digest書込み経路の停止」かを切り分ける偵察cmdを起票。領域(c)以外(inbox本文送信元)との合同確認が必要 |

### 確認したが表に含めなかった項目(根治不要と判断)

- REFLUX-AUTO-BLOCK(dirty_fingerprint)36件: 最頻fingerprint(91a0cd09...)でも複数エージェントの検知が05:24:34〜05:27:31の約3分に収束しており、単一fingerprintが長時間ブロックし続けた形跡なし。queue/insights.yamlへの並行dirty書込みを検知してskip/blockする設計どおりの多重防止動作と判断。
- GATE-STALL-BACKGROUND-DONE 99件は全件rc=0(`grep "GATE-STALL-DONE" nm_window_full.log | grep -oE 'rc=[0-9]+' | sort | uniq -c` → 99 rc=0)。GATE-STALL-BACKGROUND-SKIP(178件)は`worker_running`理由のみで正常な重複起動抑止。
- karo/gunshiのWAKE-DEFER(busy gating)がwindow内で最多(karo 419件・gunshi 232件)。karo_snapshotの同時刻状態と突合すると継続的にin_progressで実際に稼働中であり、busy判定自体の誤検知を示す証跡なし(false-busyの確認は本taskのlog sourceのみでは不可)。

### 集計

- 事例数: 3
- 未根治数: 3(根治済0)
- 主分類別件数: ④循環拘束 2(T3-kotaro-01/02) / ⑧影響範囲・依存未解明の浅い対応 1(T3-kotaro-03)
- 推測語(おそらく/と思われる/かもしれない)使用: 0
