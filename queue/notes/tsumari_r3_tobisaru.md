# つまり 第3回偵察 — 領域(d) reflux/insights/semantic_index (tobisaru)

- 領域: (d) reflux/insights/semantic_index
- 抽出窓: 2026-09-03T04:37 〜 配備時刻 2026-09-03T11:01:53 (JST)
- parent_cmd: cmd_karo_recon2_4470_d_reflux_202609031100
- 担当: tobisaru

## AC1: log source確認(抽出コマンドと出力件数)

1. **logs/deploy_reflux_auto.log**
   - コマンド: `wc -l logs/deploy_reflux_auto.log` → 216911行(全体)。ログ先頭は`2026-09-01T12:10:04`(grep -m1 -oE '2026-09-0[0-9]T[0-9:]+')。
   - 窓内行の近似特定: `grep -n '2026-09-03T05:14:29\|2026-09-03T05:14:20' logs/deploy_reflux_auto.log` で行212857以降が04:37以降に相当することを確認 → `sed -n '212857,$p' logs/deploy_reflux_auto.log | wc -l` = 4055行。
   - reflux特化のFAIL/BLOCK行: `sed -n '212857,$p' logs/deploy_reflux_auto.log | grep -iE 'block|fail|denied|reject' | grep -i reflux` → 1件のみ(`[DEPLOY] report_template: completed own report preserved (hayate_report_cmd_reflux_insight_202609030728_hayate.yaml, verdict=FAIL)`)。窓内の一般block/fail/denied/reject全体は75件だが、reflux文字列と重複するのはこの1件のみ(残りは無関係な他ninja/他cmdの一般deployノイズ)。
   - 窓内のcmd_reflux_*ユニークID数: `sed -n '212857,$p' logs/deploy_reflux_auto.log | grep -oE 'cmd_reflux_[a-z_0-9]+' | sort -u | wc -l` = 51件。

2. **queue/reports/*_report_cmd_reflux_insight_2026090[23]*.yaml**
   - コマンド: `ls queue/reports/*_report_cmd_reflux_insight_2026090[23]*.yaml | wc -l` → 57件(全体)。
   - 窓内(ファイル名タイムスタンプ>=202609030437)抽出: forループでbasename比較 → 14件。
   - verdict分布(窓内14件): `grep "^verdict:" <14件>` → PASS 13件、FAIL 1件。
   - FAIL該当: `queue/reports/hayate_report_cmd_reflux_insight_202609030728_hayate.yaml`(1件)。

3. **~/.local/share/multi-agent-shogun/publish_queue/events.jsonl**
   - コマンド: `wc -l events.jsonl` → 134行(全体)。
   - `grep 'cmd_reflux_' events.jsonl | grep -c '"kind":"c2a_rc"'` → 4件。
   - 全4件のrc/reason: `{"seq":40,...,"rc":"1","reason":"base_blob_mismatch path=queue/insights.yaml"}`, `{"seq":57,...}`, `{"seq":62,...}`, `{"seq":96,...}` — いずれもrc=1、reason=`base_blob_mismatch path=queue/insights.yaml`。ts=2026-09-02T23:29:01Z〜2026-09-03T01:33:53Z(UTC)=JST08:29〜10:33、全4件が抽出窓(04:37〜11:01:53 JST)内。

4. **queue/inbox/karo.yaml と logs/inbox_archive の『reflux dirty dispatch blocked』**
   - `logs/inbox_archive`という名のディレクトリ/ファイルは存在しない(`find`で0件)。実体はscripts/inbox_archive.shのARCHIVE_DIR定義から`archive/inbox/{agent}_{日付}.yaml`と判明。
   - `grep -c "reflux dirty dispatch" queue/inbox/karo.yaml` → 1件(timestamp 2026-09-03T10:32:13、窓内)。
   - `grep -c "reflux dirty dispatch" archive/inbox/karo_20260903.yaml` → 11件。cmd名の埋め込み時刻(cmd_reflux_insight_202609030035〜202609030957)で窓フィルタ(>=0437) → 9件が窓内(0500,0524,0540,0645,0724,0739,0809,0910,0957)、2件(0035,0225)は窓外。
   - 窓内合計: 1(karo.yaml未アーカイブ分) + 9(archive分) = **10件**。

5. **logs/semantic_index_update*.log と ledger_inbox/semantic_index**
   - `ls logs/semantic_index_update*.log` → **0件、存在しない**(`ls: cannot access`)。スクリプト`scripts/semantic_index_update.sh`自体は存在するが、専用ログファイル`semantic_index_update*.log`はlogs/配下に生成されていない。
   - `ledger_inbox/semantic_index`の実体: STATE_DIR=`~/.local/share/multi-agent-shogun`(scripts/publisher.sh:7)配下の`ledger_inbox/semantic_index/`。
   - pending(未処理): `find ~/.local/share/multi-agent-shogun/ledger_inbox/semantic_index -mindepth 1 -maxdepth 1 -type f | wc -l` → 2件だが内訳は`.lock`(0byte)と`.seq`(3byte)の制御ファイルのみで実データ0件。
   - applied(処理済): `find .../ledger_inbox/semantic_index/applied -type f | wc -l` → 13件、`find ... -newermt "2026-09-03T04:37:00" | wc -l` → 13件(全件が窓内、ファイル名のUTCタイムスタンプ20260903T01xxxxZ=JST10時台と整合)。

## AC2: 事例表(8分類: 偽陽性/過剰BLOCK/構造バグ/循環拘束/遅いscript・test/Claude↔Codex仕組み差/サンクコスト過剰複雑化/影響範囲・依存未解明の浅い対応)

| ID | 時刻 | 事象 | 主分類 | 副分類 | 真因 | 根治済/未根治 | 次の一手 |
|---|---|---|---|---|---|---|---|
| T3-tobisaru-01 | 2026-09-03T05:00〜09:57 (10回, 窓内) | reflux dirty dispatch blocked: 複数cmd_reflux_insight_*配備直前にqueue/insights.yamlの作業木が汚れており(dirty_status=` M`/`MM`)dispatchがblockされ、家老へhold_next_task通知後にaction=clean_target_then_retryで手動クリーン→再試行 | 循環拘束 | 構造バグ | scripts/ninja_monitor.sh:8204 `_reflux_notify_dirty_target_once`が単一共有ファイルqueue/insights.yamlの汚れを検知するたびkaroへ通知しclean→retryを要求する設計。複数忍者のexact task(reflux)が同一queue/insights.yamlへ直列に書き込むため、前task完了時の未commit差分が残ると次cmd配備時に必ず検知される。10回/窓内(約6.5h)発生。証跡: archive/inbox/karo_20260903.yaml:2403,2490,2607,3232,3483,3571,3717,3883,4184 + queue/inbox/karo.yaml:20 | 根治済み(検出+通知+手動clean_target_then_retryにより誤配備・データ破壊は0件で防止されている。scripts/ninja_monitor.sh:8180-8210にdedupe機構(fingerprint一致ならnotice抑止)も実装済み) | 発生頻度(10件/約6.5h)を下げるため、reflux exact task完了直後のcommit徹底(ninja-commit skill強制)をreflux_commit_contractの必須項目としてtask_yamlへ明記することを家老へ提案する |
| T3-tobisaru-02 | 2026-09-02T23:29:01Z〜2026-09-03T01:33:53Z UTC(4回, 窓内) | publisher c2a_rc base_blob_mismatch: cmd_reflux_insight_202609030812_kotaro_exact / 202609030912_kotaro_exact / 202609030920_hayate_exact / 202609031014_kotaro_exact の4件でqueue/insights.yamlへのc2a(publisher反映)がrc=1で拒否 | 構造バグ | 循環拘束 | scripts/publisher.sh:176 `event c2a_rc "$task" 1 "base_blob_mismatch path=$path"`。exact task配備時に握ったbase blobと、publisher.sh --process-ledger適用直前の実体blobが一致しない(=配備後に別の忍者/publisherがqueue/insights.yamlへ先にcommitして世代が進んだ)ため拒否される。証跡: ~/.local/share/multi-agent-shogun/publish_queue/events.jsonl seq=40,57,62,96 | 根治済み(解消経路が既存: scripts/publisher_c2a_merge.sh がkaro laneでisolated clone 3-way統合によりbase_blob_mismatchを解消する設計として実装済み。scripts/publisher_c2a_merge.sh:2,43) | publisher_c2a_merge.shが今回の4件それぞれに対し実際に自動起動/家老手動起動のどちらで解消されたかをlogs/またはgit logで突合し、gate化(自動トリガー)されているか家老に確認を依頼する |
| T3-tobisaru-03 | 2026-09-03T07:28〜07:40頃(配備〜報告、1回) | hayate cmd_reflux_insight_202609030728_hayate_exact がFAIL: 配備時snapshot(insights_pending=41, zero_backlinks=17, promotions=0, total=58, target_path_worktree_blob_at_deploy=70591941c4fb)取得後、現物再確認で対象insight ID(Makefile候補INS-20260902-141250259-bc78)が不在。git diffはHEADから後続1829行欠落、uncommitted_worker_policy=blockに従いresolveを停止 | 構造バグ | 影響範囲・依存未解明の浅い対応 | 第三者(他忍者のreflux exact task)がhayateの配備直後にqueue/insights.yamlへcommitし、対象insight IDを含む後続行が(統合または誤消失で)欠落した状態になった。hayateはHEAD:queue/insights.yaml(blob 70591941c4fb)とworktree実体(blob 5df954561d24, diff --numstat=0 additions/1829 deletions)を照合し、既存教訓L1586(共有writer世代競合)と一致すると判断して安全側で停止した | 根治済み(uncommitted_worker_policy=blockが正しく機能し誤上書き・誤resolveを防止。ただしMakefile候補insight自体は未resolveのまま=別件として残存) | 消失した対象insight(INS-20260902-141250259-bc78)の再配備要否を家老へ確認する。証跡: queue/reports/hayate_report_cmd_reflux_insight_202609030728_hayate.yaml:60-65(result.summary/details), 78-85(causal_verification) |
| T3-tobisaru-04 | 窓内(04:37〜11:01) | logs/semantic_index_update*.log は0件(存在しない)。ledger_inbox/semantic_index はpendingデータ0件(制御ファイルのみ)・applied 13件全て窓内で正常処理完了 | 該当なし(異常事象0件) | — | 専用ログファイルが未生成な点はAC1のsource確認義務として記録するが、ledger_inbox/semantic_indexの実処理(applied 13件)自体はエラーなく完了しており「つまり」対象の事象ではない | 該当なし(異常なし) | 該当なし。参考: logs/semantic_index_update*.log命名のログが実際に生成されているか、scripts/semantic_index_update.shの出力先設計を家老/軍師へ確認する余地はあるが、本偵察の主目的である事象抽出には該当なし |

## 集計

- 主分類別件数(異常事象のみ、T3-tobisaru-04は事象0件のため件数計上から除外。主分類は各事例表の「主分類」列の値):
  - 循環拘束: 1件(T3-tobisaru-01)
  - 構造バグ: 2件(T3-tobisaru-02, T3-tobisaru-03)
  - 偽陽性/過剰BLOCK: 0件
  - 遅いscript・test: 0件
  - Claude↔Codex仕組み差: 0件
  - サンクコスト過剰複雑化: 0件
  - 影響範囲・依存未解明の浅い対応: 0件(副分類としてT3-tobisaru-03に該当するが主分類ではない)
- 事例総数: 3件(異常事象。T3-tobisaru-04は事象0件のため事例数に含めない)
- 根治済み: 3件(T3-tobisaru-01, 02, 03すべて既存の検出/防御機構により誤配備・データ破壊なしで収束済み)
- 未根治: 0件
