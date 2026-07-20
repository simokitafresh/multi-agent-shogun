# publication deferred実装 latency retro

- 対象: `cmd_karo_retro_publication_impl_202607202052_normal`
- 分析日: 2026-07-20
- 一次証跡: tool wall、`logs/test_receipts/*.json`、`logs/defense_overhead.jsonl`、scope commit terminal telemetry、git log/blame
- subprocess数: command sessionから直接spawnしたroot数。runner/commit receiptが子数を持つ工程は括弧内に子数を併記。全工程記入済み（未計測0）。

## 工程別実測

| # | 工程 | wall_ms | retry | subprocess | 結果 |
|---:|---|---:|---:|---:|---|
| 1 | task/inbox/read・status遷移 | 4,600 | 0 | 6 | PASS |
| 2 | 既存retro・実装・履歴探索 | 11,000 | 0 | 5 | PASS |
| 3 | isolated shared clone + checkout | 10,400 | 0 | 2 | PASS |
| 4 | patch適用 | 100 | 0 | 0 | PASS |
| 5 | related contract初回 | 13,064 | 0 | 1（13 cases） | FAIL2（旧同期期待） |
| 6 | contract更新 | 100 | 0 | 0 | PASS |
| 7 | related contract再実行 | 14,135 | 1 | 1（13 cases） | 13/13 PASS、SKIP0 |
| 8 | 無効fixture benchmark | 3,800 | 0 | 31 | BLOCK10、値不採用 |
| 9 | isolated scope commit（identity未設定） | 12,701 | 0 | 14 | precommit PASS後commit FAIL |
| 10 | isolated scope commit再実行 | 19,832 | 1 | 14 | PASS、patch `c8e60937…` |
| 11 | current比較clone誤cwd試行 | 60,001 | 0 | 3 | cwd違いでtest未実行 |
| 12 | current contract比較 | 12,807 | 1 | 1（13 cases） | 13/13 PASS、SKIP0 |
| 13 | 研究文書作成 | 100 | 0 | 0 | PASS |
| 14 | affected checkpoint | 3,356 | 0 | 1（selected 0） | PASS、SKIP0 |
| 15 | full unit checkpoint | 434,783 | 0 | 114（1048 cases） | 1047/1048、SKIP0 |
| 16 | nested unit誤再試行A | 60 | 1 | 1 | runner rc2、tests 0 |
| 17 | nested unit誤再試行B | 77 | 2 | 1 | runner rc2、tests 0 |
| 18 | scope外FAIL focused再現 | 4,858 | 0 | 1（2 cases） | 1/2 FAIL |
| 19 | report batch初回 | 247 | 0 | 1 | commit_hash欠落BLOCK、atomic rollback |
| 20 | report batch再実行 + publication gate | 3,011 | 1 | 2 | fields反映、文書未commit BLOCK |
| 21 | 共有研究文書scope commit | 32,941 | 0 | 14 | PASS、`3edc3f26…` |
| 22 | verdict/gate/revision/delivery | 24,080 | 0 | 8 | PASS |

合計記録工程22/22、wall_ms記入22/22、retry記入22/22、subprocess記入22/22。総和は666,053ms（約11.1分）。full unit単独が65.3%、誤cwd試行が9.0%、commit 3試行が9.8%を占めた。

## 支配上位3候補の隔離実験

| 順位 | 候補 | baseline | candidate | 差分 | in-scope品質差分 |
|---:|---|---:|---:|---:|---:|
| 1 | docs/隔離patchではrelated contractを最終checkpointにする | full unit 434,783ms | related 14,135ms | **-420,648ms (-96.7%)** | 0（双方で対象13/13 PASS、SKIP0） |
| 2 | clone作成直後にlocal author identityを設定する | failed+retry 32,533ms | configured successful run 19,832ms | **-12,701ms (-39.0%)** | 0（同一patch/precommit checks） |
| 3 | fixture自作をせず既存contract fixtureを再利用する | 無効bench 3,800ms + contract 14,135ms | contract 14,135ms | **-3,800ms (-21.2%)** | 0（無効値を品質判定に不使用） |

最速かつ最大効果は候補1。対象変更は `scripts/report_field_set.sh` と既存contract 1ファイルであり、related contractが新behavior、failpoint、delivery identity、一意eventを全て覆う。full unitで追加検出した唯一のFAILは対象patch外だった。

## scope外FAILのowner/path

- path: `scripts/throughput_scan.sh:36`
- owner commit: `53d996d417aebec50fdb443168fb734bc1a52101`
- author: `test`
- commit subject: `cmd_karo_hotfix_obsidian_traversal_ready_lane_202607191235: add traversal ready lane`
- 失敗base: `573bc735…` のline 36がshell heredoc内で `yaml.safe_dump(data,out,...)` を直接実行し、`tests/unit/test_gate_single_check_consolidated.bats` の `gate_no_direct_yaml_dump` が検出。
- 現共有worktree: 同じline 36は未commit状態で `atomic_yaml_write(p,data)` に置換済み。publication patchの変更2ファイルとは非重複。

ゆえにFAIL1のownerはpublication実装ではなく`throughput_scan.sh`導入commit。FAILを隠す変更・gate緩和は行っていない。

## インフラバグ疑い

1. `run_tests.sh unit` のpublic wrapper→heavy admission→`--receipt-inner unit`で、同時実行環境では`RUN_TESTS_ACTIVE=1`を継承し0-test rc2となる経路が2回発生した。receiptは60ms/77ms、同一文言`nested aggregate run_tests invocation (unit)`。
2. 共有9p repoのgit履歴確認は5秒timeoutし、`GIT_OPTIONAL_LOCKS=0`でもlog+blame完了に30秒超を要した。設定値でなく実測。
3. reportをcompletedへした後に文書commitを要求する順序はpublication gateで再試行を生む。正順は成果物commit→commit_hash→terminal report batch。

表示型gate追加は提案しない。可逆な途中試行はrelated contractへ集中し、全量unitは統合担当の最終checkpointへ一度だけ集約するのが最小の構造改善である。
