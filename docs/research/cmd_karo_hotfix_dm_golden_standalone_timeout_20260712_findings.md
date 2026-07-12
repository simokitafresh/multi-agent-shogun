# cmd_karo_hotfix_dm_golden_standalone_timeout_202607121325 — golden回帰スタンドアロンtimeout実測とhost-wide admission契約による解決

## 出典注記(multi-agent-shogun側正本)

`context/infrastructure.md:1705`が参照していた本ファイルは、DM-Signal repo側では`.kotaro_worktrees/cmd_3861_resume_v2`等の未マージninja worktree branchにのみ存在し、DM-Signal main HEADには実体がなかった(shogun/DM-Signal両repoで参照リンク切れ、gate_vercel_phase ALERT検出)。本ファイルは、両cmdの一次証跡(queue/reports/配下、commit済み)から、multi-agent-shogun repo側の正本として再構築したものである。

- baseline実測: `cmd_karo_hotfix_dm_golden_standalone_timeout_202607121325`(worker: kotaro)
- 根治実装: `cmd_karo_hotfix_heavy_job_admission_202607121348`(worker: saizo)

正本cmd(baseline実測): `cmd_karo_hotfix_dm_golden_standalone_timeout_202607121325`
実行環境: DM-Signal `.kotaro_worktrees/cmd_3861_resume_v2` (commit 7946aa44, cmd_3861の既存golden原本を保全したまま使用)
テスト対象: `backend/tests/test_cmd_3854_fof_golden_regression.py` / `scripts/oneshot/cmd_3854_fof_golden_regression_check.py`

## AC1: 単独実行の再現・時系列計測(baseline)

`/usr/bin/time -v /usr/bin/python3 scripts/oneshot/cmd_3854_fof_golden_regression_check.py` を単独実行(pgserver=~/dm-signal-cmd3819-localpg、同一WORK_DB/TEMPLATE_DB条件)。

```
Elapsed (wall clock) time: 9:10.82 (550.82s)
User time: 325.16s
System time: 12.68s
Percent of CPU this job got: 61%
Voluntary context switches: 34,101
Involuntary context switches: 306,138
Major page faults: 6
verdict: PASS (missing=0, extra=0, mismatch=0, recomputed_portfolio_count=78, row_count=243,293)
```

比較対象: cmd_3861_resume_v2で実測した全量backend/tests(206ファイル、1776 passed/8 xfailed/6 xpassed)の総時間は455.55秒(このgolden回帰テストを含む)。単独実行550.82秒は全量実行の合計時間すら上回っている。

## AC2: 待機箇所・所有者の特定(baseline)

`pg_stat_activity` + `pg_locks`を4秒間隔で715回サンプリング(実行開始〜完了後まで約700秒間、継続監視)。

- **ブロッキングロック検出: 0件**(`pg_locks`のNOT grantedエントリは全期間を通じて一度も出現せず)
- **最大 idle-in-transaction 継続時間: 23.3秒**(正常範囲。リークしたトランザクションなし)
- 監視期間中、ワーカープロセスは一貫して`state=active`または短時間の`idle`(次クエリ待ち)であり、DBロック待ちで停止している形跡はない

一方、ホストの負荷は監視期間中に急変動した:

```
13:33 (実行開始直後)   load average: 21.54, 23.99, 21.41  (8コアに対し約2.7倍)
13:38 (実行中盤)       load average: 40.05, 28.66, 23.28  (8コアに対し約5倍)
13:45 (実行完了後)     load average: 10.19, 16.56, 19.98  (低下傾向)
```

`ps -ef`で確認した高負荷の原因: 他忍者(hayate/kagemaru/saizo)が並列実行中のCI修正作業(`bats-exec-file -j 8`による並列testファイル実行が複数同時)+ 複数の`claude --effort xhigh`/`codex`プロセスが同一8コアWSL2ホスト上で同時稼働。

**結論**: involuntary context switch(306,138件)がvoluntary(34,101件)の約9倍という極端な比率は、CPUバウンドな単一スレッドPythonプロセスがOSスケジューラによって繰り返し強制プリエンプトされたことを示す。CPU使用率61%(325.16+12.68=337.84秒のCPU時間に対しwall clock 550.82秒)は、DBロック待ちではなく「実行可能状態だがCPUを割り当てられない」時間が全体の約39%を占めたことを意味する。「待機先」はPostgresのロックやfixtureの初期化ではなく、OSスケジューラのランキュー。「所有者」は同一WSL2ホスト上で並列稼働する他忍者のbatsテスト群+複数CLIエージェントプロセスであり、DM-Signalのapp/fixtureコードの外側にある。

前提「app/fixture境界のDB待機・初期化バグ」は実測で無効化された(assumption_invalidation)。真因はホストのCPUオーバーサブスクリプション。

## 解決: host-wide admission契約(fix, cmd_karo_hotfix_heavy_job_admission_202607121348)

baseline実測で判明したホストCPUオーバーサブスクリプションを根治するため、同一8コアWSL2ホスト上で重量テストジョブ(bats全量/pytest全量/DM-Signal golden regression)が無調停で並走しないよう、flock host-wide semaphore(最大同時1)による共通admission wrapper+hook統合を実装した。

設計概要:
- `scripts/lib/heavy_job_classify.{py,sh}`: argv位置ベースの重量/軽量判定器(SSOT)
- `scripts/heavy_job_admission.sh`: flock host-wide単一lock取得。異常終了時はkernel advisory lock特性で自動解放、nested呼出しはself-deadlock防止
- `.claude/hooks/pre-bash-combined.sh` Guard17: heavy判定commandにwrapper経由を強制
- `scripts/run_tests.sh`: self-reexec(wrapper経由)で既存呼び出しを無改変で保護

## 実測結果(修正前→修正後)

| 指標 | baseline(修正前) | 修正後 | 変化 |
|---|---|---|---|
| wall clock | 550.82s | 293.31s | -46.7% |
| involuntary context switch | 306,138 | 44,230 | -85.6% |
| verdict | PASS(78/78 exact, 243,293行) | PASS(78/78 exact, 243,293行) | 維持 |

回帰テスト`tests/unit/test_heavy_job_admission.bats`(23件)全PASS。Guard17/Guard5除外はTobisaru commit `707c68f26`に本設計と完全一致する内容で先に統合された(diff照合で欠落/矛盾0を確認済み)。

## 一次証跡

- kotaro報告(baseline): `queue/reports/kotaro_report_cmd_karo_hotfix_dm_golden_standalone_timeout_202607121325.yaml`(commit `0d3759060eb35ebb08a89ed2f3263586dd74edd7`)
- saizo報告(fix): `queue/reports/saizo_report_cmd_karo_hotfix_heavy_job_admission_202607121348.yaml`(commit `d06b2884f5f3b6802cfd49ae92856a4dc5259a1e`)
- DM-Signal側原本(未マージworktree branch、参考): `.kotaro_worktrees/cmd_3861_resume_v2` commit `0d375906`「golden回帰スタンドアロンtimeoutのAC1/AC2実測結果を文書化」
