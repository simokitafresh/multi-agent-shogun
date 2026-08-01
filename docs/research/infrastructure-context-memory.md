# インフラコンテキスト
<!-- last_updated: 2026-08-01 cmd_karo_hotfix_run_tests_task_python_dispatch_20260801 reviewed source boundary -->
<!-- source_commit:d9c02f170 reason:cmd_karo_hotfix_run_tests_task_python_dispatch_20260801 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=d9c02f170 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`
> CoDDリファクタリング台帳: `docs/research/codd_refactor_registry.md`
> report_field_set as-is: `docs/research/report_field_set_after_20260416.md`
> inbox_write高速化(as-is): `docs/research/inbox_write_after_20260416.md`
> deploy_task --yaml高速化 + recon guard: `docs/research/deploy_task_yaml_speed_recon_guard_spec_20260702.md`

## コンテキスト管理

related_lessonsのmemory boostは独自SQLite snapshotを作らず、`memory_db_cache.sh`のatomic共有ext4 snapshotをSSOTとして直接読む。修正前37.771秒（721MB backup 20.403秒）から共有snapshot query 0.57秒、Python側backup 0件。→ `docs/research/cmd_4111_related_lessons_snapshot.md`（cmd_4111）

死亡agentの局所復旧は`scripts/respawn_dead_agent.sh <ninja> [--dry-run]`を使う。対象paneがdeadでない場合はBLOCKし、復旧後は`@agent_id`・`@context_pct`・active task由来の`@current_task`を同期する。忍者名はハードコードせず`scripts/lib/agent_config.sh`の`get_ninja_names`をSSOTとする。→ `scripts/respawn_dead_agent.sh` / `tests/unit/test_respawn_dead_agent.bats`（commits `76849460f`, `9fe5ec064`, `1cfa0e2f6`）

daemon watchdogは個別health checkに加え、`inbox_watcher.sh>=9`・`ninja_monitor.sh`・`ntfy_listener.sh`・`usage_statusbar_loop.sh`・`gist_sync.sh`のprocess inventoryを1 snapshotで監査し、不足classごとにWARNする。消滅PIDの`/proc/<pid>/cmdline` raceは無音で扱い、inbox unread countは読取異常時も単一整数へ正規化する。P0は本番実走error 0で完了。次段は副作用のある`restart_watchers --status`修正(P1a-1)と全daemon共通maintenance lock(P1a-2)を分離し、既存watchdogの600秒/3回throttleと重複するbackoffは追加しない。→ `scripts/daemon_watchdog.sh` / `tests/unit/test_daemon_watchdog.bats` / `docs/research/daemon-inventory-asis-tobe-5w1h_20260715.md`（cmd_3951、commit `4bf8858c0`、R2最終inventory v1.3 `2afc5d9a1`）

context freshnessの`source_commit`境界はinfra root fallbackにも適用する。境界後commitは、context自身を変更した・lesson-only・本文がhash/cmd IDを明示した場合だけ反映済みと分類し、それ以外は日付をbumpしてもALERTへ残す。ALERTには直近3件のhash・subjectを同梱する。→ `scripts/context_freshness_check.sh` / `tests/unit/test_context_freshness_check.bats`（cmd_karo_hotfix_ga225_context_freshness_infra_202607120124、GA-264、GA-295）

GA-417一次差分: `6e33bdbb2..2eec66892`全14件のうちroot fallback候補は5件。`2eec66892`はX threadを本文+画像の単一知識へ統合する取得skill、`9c90c23ca`は外部repo成果物のscope path正規化、`897c7370d`は自動push前のdirty-overlap fail-closed、`947ce5451`は自動生成semantic indexの正当なdirty除外、`d878d5096`はhook result parent mapping正規化を導入した。`2ce5e9e6f`は既存本文参照済みのため反映済み除外。直接原因は同日`last_updated`がexact source境界を進めないこと、根本判定はregistry 10/10一致・infra登録1/1・未反映5/5検出で既存防御が十分なためgate/registry変更0。→ `skills/x-thread-fetch/SKILL.md` / `scripts/gates/gate_report_format_main.py` / `scripts/cmd_complete_gate.sh` / `scripts/lib/autogen_paths.sh` / `scripts/report_field_set.sh`（cmd_karo_hotfix_ga417_infrastructure_trigger_20260730）

GA-418一次差分: `a3d5858e1..e4744442f`全12件を照合し、実装差分は2件。`8785e78a9`は`lessons_useful` whole-field autofixを数値キーdictだけに限定してID-keyed dictの誤受理をfail-closed化、`e4744442f`はGuard14へ「設定済みproject配下の実在SQLiteをliteral file URI + `mode=ro` + `uri=True`で開く」限定能力を追加した。残り10件はcontext/semantic/DM-Signal refluxでinfra本文の新規不変量なし。完了時refluxは当該cmd自身の未反映commitだけをBLOCKするため、後続の別cmd・direct fixを先行contextへ自動追記しない（非発火は設計通り）。cache無効gateは未反映12/12を1件のALERTとして検出し、registry `context/infrastructure.md` entry 1/1・caller 3箇所(`cmd_complete_gate.sh`/gate action/template)・setter unit 6/6 PASSで既存防御が成立するため追加修正0。→ `scripts/report_field_set.sh` / `scripts/lib/guard14_db_trust_classify.py` / `.claude/hooks/pre-bash-combined.sh`（cmd_karo_hotfix_ga418_infrastructure_freshness_202607311427）

context自己更新commitは、それ自身の除外だけでなく、その祖先にある検出済みsource候補のeffective boundaryとして扱う。GA-414では`b40e11a3c..66cb48be0`の116件を全走査し、除外83・本文反映10・未反映23を検出した後、`c36df4056`のcontext自己更新が23/23を包含していたのに旧gateが候補を残した。直接原因は自己更新commitの単体除外、根本原因は反映証拠を境界へ昇格しない非対称性。新しいsource commitがcontext commitより後なら従来通りALERTする。→ `scripts/gates/gate_context_freshness.sh` / `tests/unit/test_gate_context_freshness.bats`（cmd_karo_hotfix_ga414_context_freshness_20260729）

将軍startup先送りBLOCKのescalation重複判定は通知本文の完全一致ではなく、連続セッション数を除いた未解決判断のsemantic key集合を同一性境界とする。連続数は観測時点ごとに変わるためdomain identityではなく、既存の未読escalationが新規key集合を包含する間は再送しない。直接原因は可変カウンタを含む本文比較で同一未解決判断が別通知扱いになったこと、根本原因は通知文字列とdomain event identityを分離していなかったこと。同カテゴリのretry/dedupeもcontentではなく安定semantic keyをflock内で比較する。防御はstartup送信経路内のLevel4重複抑止であり、未読key集合を消費してから送信を決める。→ `scripts/gates/gate_shogun_startup.sh` / `tests/unit/test_gate_shogun_startup.bats`（cmd_karo_hotfix_startup_escalation_semantic_dedupe_20260728、commit `003f3c411`）

`--cmd-commit-list`の出力cache identityはmode/cmdだけでなく`CFC_PROJECT_OVERRIDE`を含める。同一cmdを複数projectで照合しても先行projectの結果を再利用せず、project固有の未反映source/context対を完了時BLOCKへ渡す。GA-320では修正前に同一cmdのdm-signal結果5件がinfra照合へ誤再利用され、修正後はdm-signal 5件・infra 3件を分離。→ `scripts/context_freshness_check.sh` / `tests/unit/test_context_freshness_check.bats`

直近infra契約: `02ef923b2`はcmd quality append/archive/atomic replaceのlock identityを`lock_path.sh`へ統一しLost Updateを防止、`6fb2dc41a`はCodex hook payloadをshell command文字列へ正規化、`92ffc2728`は隔離profile必須の再利用可能なCDP tier probeを追加した。→ `scripts/cmd_quality_log.sh` / `.claude/hooks/pre-bash-combined.sh` / `scripts/cdp/cdp_tier_probe.py`（GA-320）

pre-commitのCoDD metadata境界は正本metadataが存在する対象だけを検査し、metadata欠落を別契約へ誤分類しない。stall fixtureのprocess-group drainはtest harness後処理のみで本番scheduler挙動を変更しない。→ `scripts/hooks/git-pre-commit.sh` / `tests/unit/test_git_pre_commit.bats` / `tests/unit/test_ninja_monitor_stall.bats`（GA-298、GA-299再分類）
CI fixtureの直近契約は、campaign aggregate再入をBLOCKし、campaign fixture契約を同期し、receipt checkpoint rootをactive boundaryへ隔離する。→ `b3a8be4a4` / `d6a3cc8ca` / `f713cf329`（cmd_karo_ci_fix_29649090790_campaign_reentry_202607190011、cmd_karo_ci_fix_29649090790_campaign_contract_sync_202607190026、cmd_karo_ci_fix_29649090790_receipt_active_boundary_202607190044）

新規testは既定transientとし、PASS・FAIL0・SKIP0の対象別receiptが揃った時だけcommit直前に未追跡testを削除する。永続化は`test_necessity`の防御対象・重複根拠・fixture/deprecated否定を満たす場合に限り、既存重複testは1行の`regression_justification`を必須とする。test path分類は`tests` path component、`.bats/.spec.js/.test.js`、または`test_*.py|sh`だけを対象とし、`contest`・`test-plan`・`test_timing`を誤分類しない。tracked test、receipt欠落/FAIL/SKIP、並行HEAD変化、production scope消失は削除前にBLOCKする。→ `scripts/deploy_task.sh` / `scripts/ninja_scope_commit.sh` / `skills/ninja-commit/SKILL.md`（commits `44fbe59a5`, `89672a069`, `f7602c7fa`）

GA-300再分類: `ff52b26b3` は`codd-refactor`の参照鮮度注記のみでinfra契約変更なし。`44fbe59a5`の新規test必要性入口、`89672a069`のpath境界FP修正、`f7602c7fa`のtransient既定・commit前fail-closed削除は上記へ実内容反映。

cmd完了時のown-commit freshness判定は、未反映commitをBLOCKする前に`CONTEXT_UPDATE_CANDIDATE project=<id> context=<path> source_commit=<hash> reason=own_reviewed_commit`を機械可読出力し、更新対象を自動供給する。承認済み変更がtest-onlyの場合だけ`CONTEXT_NON_REFLECTION_BOUNDARY ... reason=test_only`を出して正当な非反映境界を保持する。→ `scripts/cmd_complete_gate.sh` / `tests/unit/test_cmd_complete_gate_context_freshness_block.bats`（GA-285）

完了フローのcontext境界更新は候補だけでなく、検証済みcontext/hash/reason/evidenceを埋めた`CONTEXT_UPDATE_COMMAND bash scripts/context_source_commit_set.sh ...`を同時出力する。更新者は本文反映をレビューしてこの入力を使い、境界metadataを再発明しない。GA-313では`42e6ea0..fb95d70`の263 commitをroot-fallback契約で全走査し、除外117（auto subject 32、本文参照31、context自己反映7、source pathなし47）・未反映146/146（scripts 105、tests 20、claude 6、instructions 5、CLAUDE.md 4、skills 3、memory 2、github 1）と分類した。直接原因は本文反映とsource境界更新の分離、根本原因は完了時入力が候補止まりでreason/evidence再構成を人へ残したこと。実装証拠はcontext反映`e23c6b36f`・Level5防御`7a93897e5`。→ `scripts/cmd_complete_gate.sh` / `tests/unit/test_cmd_complete_gate_context_freshness_block.bats`（cmd_karo_hotfix_ga313_context_freshness_202607220112）

完了gateのcommit照合repositoryは、報告の明示`commit_contract.repo_root`を最優先してgit実体・canonical path・task/report一致を厳格検証し、未指定時だけproject解決へfallbackする。→ `scripts/cmd_complete_gate.sh` / `tests/unit/test_cmd_complete_gate.bats`（cmd_karo_hotfix_gate_commit_repo_root_20260727、commit `ee1173787`）

`ninja_monitor`のpending_workは、現役報告だけでなくarchive report・`archive.done`・task世代を突合してarchive済みterminal FAIL世代を閉鎖し、active/reopen世代の通知は維持する。→ `scripts/ninja_monitor.sh` / `tests/unit/test_ninja_monitor_stall.bats`（cmd_karo_hotfix_pending_work_archived_fail_20260727、commit `e2b155292`）

8スキル（dashboard-update / idle-persist / review-bundle / verdict-check / karo-direct / ninja-commit / recon-dual / shogun-cli-switch）の対応script参照契約を再同期し、skill-ref gate WARN 8→0、validator 8/8 PASS・SKIP0を確認。→ commits `c4a654742`, `0fd87ed81`（cmd_karo_hotfix_skill_refs_batch_a/b_20260718140219）

## 2026-07-24インフラ修正バッチ(cmd_4154-4164)

`report_ci_push_state`はcross-repo成果物commitをreport YAMLの`cross_repo_commits`から解決する。単一`resolve_task_repo_dir`のみだと別repoのcommitがunresolvable BLOCKになっていた。→ `scripts/cmd_complete_gate.sh`（cmd_4155、commit `28c833505`）

`review_report_fingerprint`の同一性境界を正規化hashに変更し、非内容フィールド(commit_hash/cross_repo_commits等)の修正で承認(gunshi LGTM+karo ACCEPT)が無効化されない。→ `scripts/lib/review_approval.sh`（cmd_4156、commit `3718e7245`）

軍師LGTM記載とsg7_bundle生成を`lgtm_bundle_guard`で不可分化。LGTM記載後にbundle未生成でGATEが進まない反復(LK-A09 v7)を構造根絶。→ `scripts/review_bundle.py` / `scripts/gunshi_log_append.sh`（cmd_4157、commit `0e489017a`）

`stop_check_inbox.sh`はCI RED中にdone忍者へのGATE催促を抑制し「CI RED修正待ち」を表示する。CI REDでGATE CLEARが不可能な状態での反復催促(負の複利)を防止。→ `scripts/hooks/stop_check_inbox.sh`（cmd_4158、commit tobisaru）

`cmd_complete_gate.sh`のgate_block通知dedupをcmd_id単位に粒度修正。reason可変部で既存通知をすり抜け同一cmdの通知が蓄積する問題を解消。→ `scripts/cmd_complete_gate.sh`（cmd_4159、commit hayate）

pane `@model_name`乖離の恒久是正: settings.yaml model_nameを4チョークポイント(cli_launch_cmd/agent_respawn/switch_cli_mode/ninja_monitor)でtmux `@model_name`へ直接焼込み、バナーパース変換関数を全廃。→ `scripts/lib/cli_lookup.sh` / `scripts/agent_respawn.sh` / `scripts/switch_cli_mode.sh` / `scripts/ninja_monitor.sh`（cmd_4160、commit `538dfa251`）

`commit_contract.planned_paths`の正規拡大経路(`declare-scope-expansion`)を追加。実装中にtarget_path外へscope拡大した場合、理由必須の宣言で拡大しBLOCK 5回反復を防止。→ `scripts/deploy_task.sh`（cmd_4161、commit `d626e5774`）

`yaml_field_set.sh`のネストlist添字表記(`field[N]`)を検出し明示FATALでfail-closedする。リテラルキー化による無音失敗を防止。→ `scripts/lib/yaml_field_set.sh`（cmd_4162、commit `6b46ec40c`）

`inbox_write.sh`のreport_received帰属をtask現在値から報告YAML自身のparent_cmdへ切替。task入替race(新task配備後に旧cmd向けreport_receivedが新parent_cmdを使う)を根治。→ `scripts/inbox_write.sh`（cmd_4163、commit `b5590d7d3`）

`cmd_save.sh`の起票gateに三層記憶自動検索(memory_db_fts5 top3)をbackground並走で注入。起票時に三層記憶を検索しなかった全量テスト事故(10cmd影響)の構造再発防止。→ `scripts/cmd_save.sh`（cmd_4164、commit saizo）

`cmd_save.sh`のtest_ci_execution_contractを選択実行(run_tests.sh task/file/affected)要求+unit/all BLOCKへ反転。ACに全量テスト指示を書けない構造化。→ `scripts/cmd_save.sh`（将軍D0、commit `31aaa50d6`）

`review_bundle.py`のbinary_checks result判定でYAML boolean強制(True/False)をyes/no等価扱い。→ `scripts/review_bundle.py`（将軍D0、commit `afff2450e`）

テスト高速化: timing budget ratchet BLOCK対象6ファイルの遅延源を修正。→ `tests/unit/`（cmd_4154、commit `e0e65073e`）

SG7レビュー情報はformal Gunshi LGTM時に`review_approval.sh`が`review_bundle.py generate`を原子的に実行して永続化する。GATE後に報告がarchiveされても、`dashboard_update.sh --bundle`はfingerprint済みbundleをSSOTとして再検証せず消費する。archive済みdirect/training報告の復旧時だけ`review_bundle.py generate --allow-archived`を使う。→ `scripts/review_approval.sh` / `scripts/review_bundle.py` / `scripts/dashboard_update.sh`（cmd_3932根治、commits `d2c108a9f`, `b52d88702`）

家老の完了処理は`scripts/cmd_complete.sh`を単一入口とし、SG7 consume→lesson review→cmd gate→context freshness→品質記録→status証明→dashboard→ntfy→inbox archiveをfail-closedで直列実行する。archive済み番号cmdはarchive・dashboard・gate_metricsのCLEAR三証拠、active/archive statusを持たないdirect cmdは消費済みSG7・formal review gate・gate_metrics CLEARの三証拠が揃う時だけstatus完了扱いとする。将軍startupのQ6実装証拠は現行inboxに加えて自agentの当日/前日archiveを探索し、明示ラベル`Q6追補（自動化ターゲット実装証拠）`を最新回答SSOTとして旧Q6回答を更新する一方、説明文だけの`Q6追補とは`は回答に数えない。CI RED通知はGitHub run ID台帳を単一flock区間で判定・送信・追記して同一run再送を抑止する。→ `scripts/cmd_complete.sh` / `scripts/gates/gate_shogun_startup.sh` / `tests/unit/test_cmd_complete_wrapper.bats` / `tests/unit/test_gate_shogun_startup.bats`（cmd_3956、cmd_karo_hotfix_q6_followup_alias_202607191453、commits `4b696fd5b`, `9b91e40c1`, `96482b4ef`, `9fe3fb9fa`, `e15d1f0cb`, `a409822ea`）

self-retroは記録/checkを維持し、同一`improvement_candidate`が閾値以上の既知定型文かつ`wall_ms=0`または支配phase=0の時だけINSIGHT掲示板配送を抑止する。N=345実測: gate_clear(128件,全wall_ms=0)・report_completion(5件,全wall_ms=0)を抑止、completion_pipeline(117件)・review_notify(95件)は実信号継続発火。INSIGHT発火4→2(-50%)、定型文比率50%→0%。completion_total中央値16,379ms、支配phaseはdashboard 68.5%(11,224ms)。→ `docs/research/cmd_4123_self_retro_signal.md`（cmd_4123）

GATE CLEAR後の因果監査は`semantic_index_update → semantic_map_generate → semantic_causal_traverse`を同一durable workerで直列実行し、`setsid`でpane process groupから分離、cmd別flock、pending/result/logでPASS/WARN/FAILを永続化する。各0.04秒の`gunshi_gate_reflux`とworkaround率は同期維持し、refluxは同一cmd_idの全entryへ`gate_result+gate_synced_at`をlock内atomic置換する。dashboard archive/update/auto publisherも同一lockと同一filesystem renameを使う。→ `scripts/semantic_causal_post_clear.sh` / `scripts/gunshi_gate_reflux.sh` / `scripts/dashboard_update.sh`（commits `91c3bf2dc`, `ab302df7b`, `1616a1eb3`、post-commit 177/177 PASS・SKIP0）

三層知識writeはLayer1成功後、Layer2/3 payloadを先に`logs/three_layer_chain_state/*.pending.json`へatomic永続化し、`setsid+nohup`のworkerがper-event排他でsemantic更新・Obsidianリンク候補・resultを確定する。startup healthは120秒超pending、FAIL result、未解決ERRORをWARNする。Git pre-commitはtracked正本とlive `.git/hooks/pre-commit`をcommit index/HEADから自己同期し、atomic置換後は新live hookを再execするため、`ninja_scope_commit.sh`を通らないdirect commitでもdriftを残さない。→ `scripts/three_layer_knowledge_chain.sh` / `scripts/gates/gate_three_layer_health.sh` / `scripts/hooks/git-pre-commit.sh`（commits `f10a41c28`, `dabd3100c`、関連47/47 PASS・SKIP0）

三層preflightのmemory/semantic読取は、stale検知中も最後にatomic publishされた完全snapshotを返し、refresh childをcommand substitutionの待機対象にしない。`semantic_search.sh`は共有cache helperへ収束する一方、非default DB cacheのsidecar清掃とhelper未同梱時のstandalone alias検索という既存二契約を維持する。修正前は並行writer下10/10 timeout（memory124・semantic124）だったが、修正後は10/10成功、関連Bats 64/64 PASS・SKIP0、実運用のcmd_complete_gate併走中preflightも2.33秒・exit 0。→ `scripts/lib/memory_db_cache.sh` / `scripts/semantic_search.sh` / `tests/unit/test_memory_db_cache_warmup.bats`（cmd_karo_hotfix_preflight_concurrent_writes_202607150705、commits `1c9db0f38`, `b05faaaa5`）

cache refreshは**並列に実行され、公開順序が逆転する**（`os.replace`で先に始まった窓が後に終わる）。B48の2点計測（mkstemp直前+os.replace直後にrowid+時刻を記録）22-23窓の実測: 窓長 median 124.3秒（min 16.5/max 244.6=**定数でなく分布**。理論値75秒は実測の6割）、取りこぼし median 9.5件、**公開順序の逆転2件**（1422610→1422600、1422663→1422652）。ただし逆転は2分46秒/1分47秒で回復し前の高さを超える。**逆転中の検索3件は全件hit>0・no_match=0・exit=0で、各検索の3〜12秒前の書込みが存在した状態で成立** = B45の`rowid水位比較+delta`が並列公開の逆転まで覆っている。∴`memory_db_cache.sh:55-57`/`:153-155`の残存mtime3条件は**是正不要・記録のみ**（PD-134クローズ）。**未確認**: `search_logs`に結果内容の列が無く（id/ts/caller/agent_id/query/hit_count/no_match/elapsed_ms/exit_code/created_at）、返された内容そのものの正しさは**原理的に事後検証できない**。→ `scripts/memory_db_live_insert.py` / `scripts/lib/memory_db_cache.sh` / `logs/defense_overhead.jsonl`（source=three_layer_health, check_id=refresh_window）（cmd_karo_impl_b48_refresh_window_2point_telemetry_20260726、PD-134）

速度台帳の設計書v1.0入力（cmd_4181）: row snapshot=39,070行/cutoff `2026-07-27T11:03:55.717413+00:00`を固定して境界再分類し、親total・実行本体・queue wait・lock holdを非加算で分離。純オーバーヘッド累積上位は `git_pre_commit:self_sync` 1,699,622ms、`cmd_save:checks_main` 1,544,448ms、`git_pre_commit:test_granularity` 1,045,936ms。`affected_tests`は実テスト込み、`refresh_window`はbegin/end混在のため標的順位から除外。→ `docs/research/cmd_4181_overhead_boundary_recon.md`

配備の排他はcmd別lockに加え、同じ忍者のtask/report mutationからdurable task_start通知までを忍者別flockで直列化する。待機後は`assigned|acknowledged|in_progress`の別cmdを再読して上書きBLOCKするため、異なるcmdの同時配備でもtask YAMLを混線させない。破損taskはsame-cmd再利用を禁止してstale reset+atomic `--yaml` publishへ必ず戻す。→ `scripts/deploy_task.sh` / `tests/unit/test_deploy_task_lifecycle.bats`（GA-257/258、commits `e6847f0ab`, `448eba94b`、全量76/76 PASS・SKIP0）

Bats直接実行は`run_timed_bats.sh`へ集約し、既存writerの14列台帳へ必ず追記する。速度修行task生成もwrapperを強制し、`gate_test_health.sh`が完了reportと台帳の対象集合差を検知する。夜戦欠測7件をbackfillし、台帳543→551・coverage 7/7・対象24/24 PASS。→ `scripts/run_timed_bats.sh` / `scripts/test_speed_task_generator.sh` / `scripts/gates/gate_test_health.sh`（cmd_3942、commit `7e11d37c5`）

Bats suiteの共有資源fixtureは、個別実行時間ではなくsuite内の同時実行競合でtiming ratchetを誤発火しうる。`run_tests.sh`の既存full aggregate weight分類へ対象fixtureを登録し、総並列度を保ったまま該当fixtureだけを排他実行する。対象5件のBLOCK 5→0、suite wall 32.416→13.700秒（-57.7%）、54/54 PASS・FAIL0・SKIP0。→ `scripts/run_tests.sh` / `tests/unit/test_run_tests.bats`（cmd_karo_ci_fix_timing_budget_ratchet_5files_202607161327、commit `b91b449d6`）

Timing ratchetのファイル判定は全ファイルp95+最新単発値でなく、ファイル別履歴median+MAD分散マージンと直近5実測medianを使う。一時I/OスパイクはPASS、代表値シフトはBLOCK。仮説3テスト(test_three_layer_preflight/gist_verified_write/gate_yaml_field_set_block_sync)は現在BLOCK無し。現在の起動ゲートBLOCK原因はCase(a)本質遅化4テスト(ninja_scope_commit/cmd_complete_gate_small_consolidated/deploy_task_yaml_injection/inbox_write)。高速化cmd要。→ `docs/research/cmd_4115_timing_ratchet_variance.md`

affected=0はheavy-job admission前にselectorを先行し、terminal receiptを保ったまま即returnする。非空selectionはmanifest固定してadmission後の再選択を防ぐ。248.660→1.81秒（-99.3%）、admission marker 0。→ `docs/research/cmd_4110_admission_affected_zero.md`

CDP孤児=profileパターン自動掃除で意志非依存化。`cleanup_orphan_profiles`が`--user-data-dir`に`cdp-`を含み`--remote-debugging-port`を持つchrome.exeをpidfile有無に関係なく掃除する。殿のdefault Chrome（`cdp-`なし）は除外。→ `scripts/cdp_chrome_cleanup.sh` / `docs/research/cmd_4121_cdp_orphan_cleanup.md`（cmd_4121）

共有worktreeの任務テスト帰属は `run_tests.sh task queue/tasks/<worker>.yaml` を使い、task/report所有pathのみを既存selectorへ渡す。引数なし`affected`や`unit`全量を忍者任務verdictへ混入させず、全量健全性はfixed-SHA統合checkpointで独立判定する。cmd_4108実測は690件中scope外FAIL1→所有4 test files・109/109 PASS・混入0。→ `docs/research/task-test-attribution-after-20260721.md`

`run_tests.sh task` は選択testをsuffix別の正規engineへ一度だけ配送する（`.py`→pytest、`.bats`→Bats）。Python/Bats混在も単一TAP/receiptへ集約し、未知suffix・欠損pathはfail-closeする。実測は非cache 55/55 PASS・SKIP0、Python-only receipt 1/1、mixed receipt 2/2、誤配送0・重複0。→ `scripts/run_tests.sh` / `tests/unit/test_run_tests.bats`（cmd_karo_hotfix_run_tests_task_python_dispatch_20260801、commits `6c3392d74`, `d9c02f170`）

同一CLIが複数入力を受けるBatsでは、互換caseをbatch化してassertionを維持したまま重複初期化だけを減らす。`test_test_select.bats`は`test_select.sh`起動10→5、wall 18.248→8.444秒（53.7%短縮）、5/5 PASS・FAIL0・SKIP0。→ `tests/unit/test_test_select.bats` / `scripts/test_select.sh`（commit `a1ea08648`）

速度修行の連続攻略は`min_rounds=2`・`max_rounds=3`・campaign budget 10分とし、次roundのbaselineは直前値でなく`best_so_far`を継承する。悪化runは採用せず、round別task/commit/reportとledgerの`round_index/best_wall/last_wall/approach/stop_reason`で強くてニューゲームする。→ `docs/research/ledger-driven-campaign-lane-pattern_20260714.md` §6.5（3者合意、v2.1 commit `3f9931302`、実装cmd_3952）

campaign-lane（台帳駆動攻略・応用候補カタログ）の正本は`config/campaign_lane_catalog.yaml`、設計と実行入口は`docs/research/ledger-driven-campaign-lane-pattern_20260714.md` §6/§8。`shard-work`=既知集合の単発分割、`campaign-lane`=台帳実測による反復選定+飽和終端。

pytest-speed adapterは現行task/reportのnodeidだけを高速抽出し、配備時の台帳世代を記録して新計測後に再適格化する。並行deployはnodeid別`flock`で原子reserveし、失敗時は自reservationをrollbackする。→ `docs/research/ledger-driven-campaign-lane-pattern_20260714.md` §6/§8（commits `9c95ecd4a`, `18ab2c7d4`）

1 roundに複数の有効計測がある場合はPASS・FAIL0・SKIP0集合からobjective方向のbestを採用し、`last observation`とは別フィールドで保持する。→ commit `130fa4303`、[[campaign-lane]]

dashboardの`## 🚨要対応`は任意セクションであり、欠落時は同期・postcondition・template検証の全3段でno-op成功にする。存在時の件数照合と破損入力WARNは維持する。→ `scripts/dashboard_update.sh` / `tests/unit/test_skill_feedback_loop.bats`（commit `f2f3f2c48`、関連130/130 PASS・SKIP0）

完了通知欠落監視は、terminal marker後のLGTMだけではcmdを再OPEN扱いにしない。明示RC/revisionまたはactive taskがterminal後に存在する場合だけ新世代と判定し、archive済み同一報告への遅延・重複LGTMによる恒久偽陽性を抑止する。→ `scripts/ninja_monitor.sh` / `tests/unit/test_ninja_monitor_clear_guard.bats`（commit `5efbb3a37`、semantic通知偽陽性3→0、focused 6/6 PASS・SKIP0）

draft-review配備テストは、Bats processでsetup済みの`deploy_task.sh`関数を再sourceせず直接再利用する。独立shellが必要なEXIT trap類型は維持し、20/20 PASS・FAIL0・SKIP0のまま15.982→15.184秒（5.0%短縮）。→ `tests/unit/test_deploy_task_draft_review.bats` / `docs/research/deploy-task-draft-review-test-speed.md`（commit `d47ec43d6`）

contextの`source_commit`置換はevidence内の比較矢印（例: `3->0`）も含む行全体を認識し、既存重複markerを1行へ正規化する。DM-Signal split-context同期も同じ矢印対応regexを使う。→ `scripts/context_source_commit_set.sh` / `scripts/dm_signal_research_reflux_guard.sh` / 対応Unit 33/33 PASS・SKIP0（commit `08e360e53`）

忍者idle時の速度修行は`reflux → 本体scripts/*.sh速度レーン → Bats速度レーン → legacy`の順とする。本体レーンがpendingの間はBatsを先に配備せず、機能痩せ禁止・FAIL 0・SKIP 0の品質契約は維持する。→ `scripts/ninja_monitor.sh` / `tests/unit/test_test_speed_task_generator.bats` / `tests/unit/test_bash_speed_training.bats`（commit `b8a07e061`、事後計測 25/25 PASS・SKIP0）

15分超cmdは保存時点で`execution_env` mappingの具体的`long_runtime_reason`と正の`measured_runtime_sec`を必須とし、配備時TEN_MIN_CONTRACTまで不備を持ち越さない。雛形も同じmapping契約を提示する。→ `scripts/cmd_save.sh` / `scripts/cmd_skeleton.sh`（cmd_3933, commit `daee77f03`）

非対話shellの`rg` PATH解決は`$HOME/.local/bin/rg`までフォールバックし、causal backlinks・Vercel phase gate・lesson harvestのsilent false-negativeを防ぐ。また`cmd_save.sh`はnew-file WARN抽出0件を正常系とし、`pipefail`によるsilent exit 1を防ぐ。→ `scripts/causal_backlinks.sh` / `scripts/gates/gate_vercel_phase.sh` / `scripts/lesson_harvest.sh` / `scripts/cmd_save.sh`

pre-commit Ruff ratchet: `scripts/run_precommit_checks.sh` は変更PythonファイルのRuff診断をHEAD baselineと比較し、新規診断だけをBLOCKする。既存負債は増加させず段階解消する。→ `tests/test_run_precommit_ruff_ratchet.sh`（cmd_karo_hotfix_precommit_ruff_ratchet_202607110002）

context freshnessのinfra root fallbackはinfra実装だけをsource扱いし、project固有の`docs/research/`は各project contextのpathspecへ委譲する。これによりDM-Signal研究文書だけのcommitで`infrastructure.md`を誤ALERTにしない。→ `scripts/context_freshness_check.sh` / `tests/unit/test_context_freshness_check.bats`（cmd_karo_hotfix_ga219_context_freshness_202607110107）

変更系 PreToolUse は `scripts/hooks/three_layer_preflight.sh` の現prompt・agent/pane単位 atomic 証跡を必須とする。`prompt_state_inject.sh` が UserPromptSubmit ごとに記憶DB・semantic・Obsidian因果索引を検索し、`.claude/hooks/pre-write-edit-combined.sh` と `.claude/hooks/pre-bash-combined.sh` が証跡なし/失敗/別promptを exit 2 でBLOCKする。Read・read-only検索・preflight自身は許可する。→ `tests/unit/test_three_layer_preflight.bats`（cmd_karo_hotfix_three_layer_preaction_enforcement_202607101452）

GA-228: `queue/tasks/*.yaml` と実装/context/docs/tests の混在を、GA-408のpre-commit到達前に共通PreToolUse Guard 3.7が一時indexで判定してBLOCKする。task単独・運用YAML同士・実装のみは許可する。→ `docs/research/cmd_ga228_task_yaml_mixed_stage_20260712.md` / `scripts/hooks/git-stage-guard.py` / `tests/unit/test_pre_bash_queue_tasks_guard.bats`

掲示板通知は `scripts/bulletin_write.sh` が通知先ごとに最大3回再送する。一時失敗は成功まで継続し、最終失敗は `logs/bulletin_notify_failures.yaml` に永続記録して投稿者へ非ゼロ終了コードで可視化する（cmd_3829）。詳細は `docs/research/cmd_3829_bulletin_notify_failclose.md`。

context freshnessは複数context fileが同一source commitで同時ALERTした場合、`GROUP: <path1>,<path2> share source commit <hash>`行を追加出力し、家老が重複調査cmdを別々に起票することを防ぐ。設計意図: `min_source_commits`の既定閾値1件はGA-226(L1056)がmerge/squash後のALERT自然消滅を防ぐため意図的に固定した下限であり本機構では変更しない — GROUPはALERT発火条件・タイミングに一切影響しない可視化のみの非破壊追加。発火条件: ALERT確定済み(WARN/check-failedは対象外)の2ファイル以上が`git log`の`details`(直近3件のcommit hash)に同一hashを含む場合のみ出力。root-fallback経路もGA-264以降は同じhash・subject明細を返すためGROUP相関対象となる。ALERT非成立(WARN/timeout)のペアはGROUP化せず、出力は既存の`sorted(dict.fromkeys(...))`のまま追加行として混在するため既存WARN/ALERT行の内容・順序は不変。

context freshnessのDM_SIGNAL_CONTEXT_PATHSは、広域共有ディレクトリ(例: `docs/research`)を二次スコープとして持つcontext fileのpathspecエントリへ`"cited:<dir>"`prefixを付けられる(現状`context/dm-signal-ops.md`の`docs/research`のみ)。`"cited:"`が付いたディレクトリ配下のcommitは、そのcontext file自身が本文で`<dir>/xxx.md`の形で既に名指し引用しているファイルを変更した場合のみ関連commitとして数える(GA-237家老RC、min_source_commitsは不変)。設計意図: `docs/research`のような高頻度共有ディレクトリを丸ごとpathspecに含めると、内容が無関係なcommitでもALERTが発火し続ける(ops.md向けGA-*系10回の大半が境界更新のみの一行修正だった実績と符合)。誤検知境界: (1)`"cited:"`を付けないエントリ(`context/dm-signal-research.md`の`docs/research`等、そのディレクトリを主目的として網羅追跡するcontext file)は従来通り無差別カウント — 新規未引用ファイルの検知能力を落とさないため意図的に対象外、(2)`cited_dirs`が空の全ての既存context fileは判定ロジックが完全にno-opとなり回帰なし、(3)cited判定は`git log --name-only`で変更ファイル一覧を取得しAUTO_COMMIT_SUBJECT_REフィルタ通過後に適用、(4)root-fallback経路は本フィルタも未適用(GROUPと同じ既知ギャップ)。実例: `c84bcd93`はGA-237(commit`c84bcd93`)で`dm-signal-ops.md`が版番号付きで引用済みの`docs/research/cmd_3840_nondeterminism_redesign.md`を変更したため真陽性として引き続きALERTし、初回「境界更新のみで解消」という誤判定を家老RCで訂正させた(§72実質更新)。→ `scripts/context_freshness_check.sh` / `tests/unit/test_context_freshness_check.bats` / `docs/research/ga237_context_freshness_root_cause.md`（cmd_karo_hotfix_ga237_context_freshness_202607131156）

inbox nudge配達保証: `scripts/inbox_watcher.sh` はINPUT-GUARD保留時に `deferred_nudge` 状態を記録し、送信済みfingerprint/debounceをrollbackする。未読が残る限り次回 `DEFERRED-RETRY` で再注入する。Codex active+busyはqueued messageとして即時送達し、idle promptのANSI dim候補文は未送信入力ではないため安全に送達する。通常色の実入力とClaude/非Codexは従来通り保護する（cmd_3830）。詳細は `docs/research/cmd_3830_nudge_delivery_guarantee.md`。

queued wakeの件数は検知時snapshotではなく送信lock内の現行未読snapshotを正本とする。待機中に未読が0件なら旧`inboxN`を破棄し、複数世代は現行count/fingerprintの1送信へcoalesceする。送信結果は`attempted`/`pasted`/`dedup`を分離し、dedupを`Wake-up sent`と記録しない。修正前18/18→修正後20/20 PASS、古い件数送信0・実paste 1（cmd_karo_hotfix_stale_inbox_nudge_consumption_202607161354、commit `321e74760`）。

watcher再起動は全9台の一括停止を禁止し、`get_all_agents`の重複なし9 identityをagent単位でrolling handoffする。各交代中のroot watcher下限は8、終端はroot identity 9/9を3連続sampleで確認する。交代gap中の未読は新watcher起動時の`process_unread`再snapshotで回収し、generation dedupeにより欠落0・重複0・delivery 1回を保証する。`--status`もchild pollerを除くroot identityだけを数える。→ `scripts/restart_watchers.sh` / `tests/unit/test_restart_watchers_handoff.bats`（cmd_karo_hotfix_watcher_restart_stable_handoff_202607161446、commits `50f33da8b`, `70b029602`）

failed taskとcompleted reportは文書完成と作業結果を別軸で扱う。`scripts/lib/report_terminal_state.sh`を判定SSOTとし、`verdict=FAIL`または`status_detail=BLOCKED`は`CLOSED_BLOCKED`、成功系verdictだけを`SUCCESS`とする。startup gateとninja_monitorの再nudge判定は同じ分類を使い、完結済みBLOCKED偵察を乖離ALERT/再通知しない一方、真の成功報告との乖離は検出し続ける。偽陽性1→0、startup72/72+monitor70/70 PASS・SKIP0（cmd_karo_hotfix_failed_completed_blocked_terminal_202607161446、commit `3bb11a0a7`）。

全て外部インフラが自動処理。エージェントは何もするな。Codex忍者=/new、Claude忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

## lord_conversation / 記憶DBデータフロー（cmd_2963〜cmd_3032）

殿との対話はlive JSONL → アーカイブ → SQLite記憶DBの三層で保持する。一次データは`queue/lord_conversation.jsonl`、24h超過/200件超過分は`logs/lord_conversation_archive/*.jsonl`へ退避、検索・概念到達は`data/multi_agent_shogun_memory.db`を使う。

| 層 | 正本/実装 | 役割 | 注意 |
|----|-----------|------|------|
| live | `queue/lord_conversation.jsonl` / `lib/lord_conversation.sh` | 直近対話を原子追記。terminal/ntfy response、terminal inboundを記録 | 消費者はtarget/agentで絞る。全inbound直読み禁止 |
| retention | `scripts/conversation_retention.sh` / `context/lord-conversation-index.md` | liveを24h/200件に保ち、古い行を`logs/lord_conversation_archive/`へ追記退避 | アーカイブが一次データ。DBだけに飛びつくな |
| batch DB | `scripts/memory_db_import.py` | archive/live/掲示板/report/insight/document等を`events`へ再構築 | `/clear`時再構築。WAL+INSERT OR REPLACE |

殿発言の自動注入producerは4系統、target隔離なしは4経路（recon時点4→4）。caller/filter全数表は `docs/research/cmd_4125_lord_utterance_isolation.md`。
| live DB | `scripts/memory_db_live_insert.py` + 各writer | inbox/report/cmd_quality等をリアルタイムINSERT | 失敗しても正本YAML/JSONL成功を優先 |
| query | `scripts/memory_db_query.sh` / `scripts/semantic_search.sh` | SELECT-only SQL、FTS5 fallback、semantic検索補助 | destructive SQLは禁止 |

記憶DB構造: DB pathは`data/multi_agent_shogun_memory.db`。主表は`events(id, ts, event_type, agent, target, direction, summary, detail, session_id, cmd_id, concepts, source_file, parent_event_id, importance)`、全文検索はFTS5仮想表`events_fts(summary, detail)`、概念正規化は`event_concepts(event_id, concept_name)`、因果/Obsidianリンクは`event_links(source_event_id, target_concept, link_type)`。会話ビュー`conversations`は`events`由来。
→ `context/memory-db-schema.md` / `context/memory-db-queries.md` / `context/lord-conversation-index.md`

三層記憶新機能: `update_event_state`でstate遷移を記録し、`memory_recall_control.sh`で想起制御、`obsidian_promote_candidate.sh`でObsidian昇格候補、`append_contradiction_candidate`で矛盾検出候補を扱う。
→ `docs/research/three-layer-memory-l0-l7-penetration-design_20260604.md` §3 / `scripts/memory_db_live_insert.py` / `scripts/memory_recall_control.sh` / `scripts/obsidian_promote_candidate.sh`

想起ファネル台帳: `scripts/loop_ledger_update.sh`のmemoryチャネルは`search_logs`をproduced、将軍回答の`[MEM:]`引用タグをconsumedとして集計し、検索継続・引用ゼロの空転を検知する（cmd_3735, produced=7872/consumed=147実測）。
報告テンプレM3: `deploy_task.sh`は報告YAMLへ`memory_references`欄を自動生成し、`report_field_set.sh`/`gate_report_format_main.py`が欄の記入と条件付き検査を担う（cmd_3739）。
報告実走契約(LG055): 実装報告は`deploy_task.sh`が`operational_simulation` 4項目を入口自動生成し、`gate_report_format_main.py`/`gate_gunshi_report_precheck.sh`が欠落・不正resultをBLOCKする。queue/report-onlyは実装なしのため免除し、実装欠落BLOCK+report-only PASSの境界を97/97+1/1 PASSで固定（cmd_karo_hotfix_report_opsim_contract_202607170003、commits `c3f63bf7e`, `012202ac1`）。因果: [[LG055_8回手戻り]] -> [[テンプレート不在が根因]] -> [[operational_simulation二層防御]]。
引用有効性回収M4: `scripts/loop_ledger_update.sh`のmemoryチャネルは`memory_references.useful`を集計し、`reflux_targets`で無関係引用のsource別還流候補を出力する（cmd_3740, evaluated=8/useful=1/rate=12.5%/reflux_targets=2実測）。

学習ループ台帳のsnapshot更新は、previous読取→差分判定→append→publishの全区間を`OUT_FILE.lock`の同一flockで直列化し、出力先と同じdirectoryの一時fileをfsync後`os.replace`する。書込みだけのlockでは2つのstartup gateが同じpreviousを読みlost updateするため不十分。修正前8反復でsnapshot消失1件、修正後16反復でparse失敗0・消失0・偽ALERT0、実在庫増加の真ALERT/exit 1維持、関連18/18 PASS・SKIP0。→ `scripts/loop_ledger_update.sh` / `tests/unit/test_loop_ledger_update.bats`（cmd_karo_hotfix_loop_ledger_concurrent_snapshot_202607161510、commit `7678bd69b`）
可搬想起M6: `scripts/portable_loop_bootstrap.sh`は`recall_inject.sh`を生成し、hookなしCLIでもイベント文脈からsemantic/memory一致を注入テキスト化できる（cmd_3741, bats 4/4 PASS）。
報告WA構造根絶(PD-056): report_yaml_format系WAの防御突破点3系統を偵察特定(cmd_3749)し、記入層=`deploy_task.sh`/`report_field_set.sh`へ既存依存宣言の記入導線+型検証(cmd_3750)、監視層=`ninja_monitor.sh`へactive+idle滞留のdone前報告評価+報告修正/未commit再通知(cmd_3751, ACTIVE-IDLE-REPORT-EVAL)を実装。家老手動補正へ流れる経路を構造で回収（2026-07-08全CLEAR）。
偵察no-commit契約(PD-125): `deploy_task.sh`はrecon/recon2/scout/コード変更禁止taskでもcommit checkを省略せず、「stage/commit未実行=yes」を報告テンプレへ自動投影する。impl/hotfix/ci_fixはcommit必須を維持。偽BLOCK 1/1→0/1、局所53/53 PASS・SKIP0、commit `880976003cce017170f0db9d19b254e6377dc3b6`、GATE CLEAR（cmd_karo_hotfix_recon_report_commit_contract_202607140443）。
insight解決SSOT・破損復旧(PD-126): `insight_write.sh`の追記前修復器は`action_artifact:`を既知fieldとし、`status=resolved`の必須証跡欠落も不完全entryとして復旧対象にする。`restore_insights_from_corrupt.sh`でentries 33→38・restored 5・unique 38/38・duplicate 0、invalid resolution 2→0、局所30/30+全体136/136 PASS・SKIP0、commit `0086753674ef9bc528cfa0f25c3394f00861029e`、GATE CLEAR（cmd_karo_hotfix_insight_resolver_ssot_rc2_202607140530）。
完了通知gap検出: `ninja_monitor.sh` に `completion_notify_gap` を追加。軍師LGTM後、grace300sを超えても将軍向けbulletin/shogun inbox/cmd_complete_gate CLEARが無い場合に家老へ通知する。cmd_3780でLGTM 22:53:35→手動bulletin 23:05:58まで12分自動通知ゼロだった穴を封じ、実データで景丸hotfix未達1件を検出・補完（cmd_karo_hotfix_completion_notify_gap_202607082310, tests 38/38 PASS, commit 2734ed518）。
将軍prompt洗脳注入縮約: `scripts/hooks/prompt_state_inject.sh` は通常時の将軍向けbrainwash注入を単一自問52文字へ縮約し、`stop_check_inbox.sh`由来のQ6検出flagがある時だけ8パターン全文を再注入する。検出時は`gate_fire_log.yaml`と`detector_fp_rate.yaml`へ台帳記録する（cmd_3782, bats 78/78 PASS, commit 851bd946）。
軍師precheck視点列独立性検証: `gate_gunshi_report_precheck.sh` のSG-PRE32は、報告YAMLのMarkdown成果物を`detect_view_column_degeneracy.py`で走査し、Expanding/WF等の数値列が全データ行で完全一致した場合にWARN(LG049)を出す。cmd_3780のExpanding/WF縮退見逃しを機械検出へ還流（cmd_3781, bats 29/29 PASS, commit 511f226f）。
三層連鎖自己修復: `scripts/memory_db_knowledge_write.sh`はLayer1後にdurable pendingを先書きし、専用workerがLayer2全失敗時に最終エラー要点+payload_b64とFAIL resultを記録する。次回write時は未解決ERRORを自動repairしてOK行+PASS resultへ更新する（cmd_3742契約継承、commit `f10a41c28`, 関連26/26 PASS）。
普遍knowledge自動想起SSOT: target指定visibilityは`scripts/memory_visibility.py`の`target空/NULL OR target=self OR document`へ統一し、knowledge write成功後は主DB→atomic prompt cache→Claude/Codex共通`prompt_state_inject.sh`へ自動反映する。修正前は全agent検索0/9・実異CLI入口0/2、修正後は9/9・private漏洩0/8・実家老Codex+実軍師Claude 2/2、対象summary SHA256一致。単一CLIのenv擬似8役は補助証拠に限定し、異CLI・異役割の独立取得一致を完了条件とする（cmd_karo_hotfix_three_layer_universal_recall_202607160630、commits `8dacb9fbf` / `c2e7352ee`）。因果: [[殿指摘20260716_単一CLI擬似全役は洗脳]] -> [[knowledge_write_to_atomic_prompt_cache]] -> [[家老Codex軍師Claude独立一致]]。→ `docs/research/cmd_karo_hotfix_three_layer_universal_recall_202607160630.md`
軍師precheck git履歴走査統合: `gate_gunshi_report_precheck.sh`はSG-PRE3/SG-PRE13/SG-PRE19が独立にPARENT_CMD全履歴`git log --grep`走査(numstat/name-only)を最大4回実行しており、同一REPO_ROOT/PROJECT_DIRへの重複走査が軍師レビュー実行時間13.4秒の主要因(PS4行別プロファイルで実測)だった。1回のnumstat走査結果を3チェック間で共有し、name-only相当は3列目(path)から導出する構成へ統合。実測(PROJECT_DIR==REPO_ROOTのno-hash分岐): 8.56s→4.06s(-52.6%)、同一report入力での標準出力diff行数0(等価性実証済み)。bats 54/54 PASS(cmd_3807)。
→ `docs/research/cmd_3807_gunshi_precheck_speedup.md`

### 三層記憶×学習ループ接続（cmd_3116〜cmd_3128, 2026-06-02）

殿指示で家老×軍師協議→穴分析→13cmd一気通貫で三層記憶の概念空間を接続。
操作的オントロジー原則（殿裁定2026-06-20）: オントロジーは分類表ではなく自動実行されて初めて効果が出る。概念定義・alias・因果リンクは、`semantic_search.sh`、task文脈注入、gate、startup、配備/レビュー/完了フローなどの自動経路に乗って再利用されることを完了条件にする。因果: [[殿裁定20260620_オントロジー自動実行]] -> [[分類表だけでは再利用されない]] -> [[semantic_search_task注入_gate_startup配備フローへ接続]]
操作的オントロジー復帰時判断（2026-06-20 家老・軍師相談済み）:
- `SKILL.md`全28本のロール制限削除は却下済み。09:10の軍師投稿は09:11に「編成系スキル(shogun-cli-switch)のみ」と撤回済み。全スキル削除は殿裁定の拡大解釈。通常はロール制限を維持し、殿の直接指示だけAGENTSの上位ルールで優先する。
- `shogun-cli-switch --force(active無視)`は通常機能にしない。現行正本はactive/in_progressをskipし設定だけ反映する設計。busy paneのrespawnは未完了作業・報告YAML・CTX破壊リスクが高い。緊急時に作るならemergency専用、事前capture/snapshot、対象pane列挙、dry-run、post復帰確認を必須にする。
- PJパス直書き修正は即起票可能。一次計測で実行系19ファイルに`/mnt/c/Python_app/DM-signal`または`/mnt/c/Python_app/auto-ops`直書きあり。`scripts/lib/project_path.sh`は存在し、`config/projects.yaml`には`auto-ops`登録済みなので「auto-ops登録前提」は古い。登録済みSSOTを使って再計測→変数代入型から置換→インライン/テスト個別判断→Guard16にPJパス概念追加。
- SSOT正本保護は`config/*.yaml`全体BLOCKではなくフィールド単位の保護表で設計する。例: `config/projects.yaml:projects[].path`はproject登録系/`project_path.sh`、`config/cli_profiles.yaml:profiles.*.launch_cmd`は`shogun-cli-switch`/`cli_lookup.sh`、`config/settings.yaml:cli.agents.*`は`shogun-cli-switch`経由。全封鎖は家老の正当運用を詰まらせる。
- `.yaml`/`.md`へのGuard16拡張は一律禁止。SSOT正本・docs/research・archiveにはliteralが正当に存在するためFPが増える。対象はinstructions/generatedやscripts配下の運用yamlなどに限定し、正本ファイルは別ゲートで守る。
- **cmd_3116**: live_insert概念付与(速度2.3ms/一致率100%)
- **cmd_3117**: テキスト品質改善(report充填3/10→10/10)
- **cmd_3118**: 歴史データbackfill(31636件→11531件更新)
- **cmd_3119**: event_concepts→教訓注入boost接続(deploy_task.shが概念横断で教訓候補を動的発見)
- **cmd_3121**: 教訓注入偽陽性71.2%→22.7%根治
- 概念充填率: report 0.4%→49%、lesson 2%→68.6%、gate 0%→97.8%、WA 0%→96.2%

## 直近改善（cmd_181〜cmd_541）

初期インフラ整備+教訓サイクル構築。acknowledged status(181), ペイン消失検知(183), inbox re-nudge(188/189/191), grep -cバグ(192), 裁定伝播遅延検出(PD-016), 知識鮮度警告(PD-017), dashboard_update(337), auto_deploy_next(338), ゲート迂回防止(339), 教訓タグ注入(348/349/350/351), 量→質転換(531), CMD年代記(544)
→ `docs/research/infra-details.md` §2, 各スクリプト: `scripts/` 配下

## 直近改善（cmd_602〜cmd_612）

review品質機械検査(607), ntfy_listener dual watchdog(609), lesson_impact feedback修復(611), 旧terminology一掃(612)
→ `context/cmd-chronicle.md` 03-06 / `scripts/` + `config/settings.yaml`

## 直近改善（cmd_875〜cmd_878）

gstack Tier1-2取込(875/876): 忍者プロンプト強化+家老Two-pass Review+Gate [CRITICAL]/[INFO]分離。CDP daemon化(877): persistent WebSocket+@ref体系。教訓同期修復(878): 淘汰カウント精度向上
→ `docs/research/gstack-analysis.md` (v0.0.2, 2026-03-13)

**GStack v1.11 + GBrain v0.19 + Skillify全分析(2026-04-25更新)**: gstack 6→23スキル、GBrain新登場(29スキル+21cron+17888ページ本番稼働)、Skillify(失敗→永続スキル化10ステップ, 766k views)。将軍の独自強み: 鎖/追体験/なぜなぜ/PI。取り込み候補: check-resolvable(スキル到達可能性)+routing-eval(intent→skillテスト)+ハイブリッド検索(Vector+BM25+Graph)。Minions(決定論的$0実行)=将軍のbashスクリプト群と同設計思想
→ `docs/research/gstack-gbrain-skillify-2026-04.md`

## 直近改善（cmd_1039〜cmd_1120）

| cmd | 改善 | 結論 |
|-----|------|------|
| 1039/1040 | **ninja_monitor三段階/clear** | Stage 1: YAML確認→Stage 2: 再確認→Stage 3: /clear。作業中(acknowledged/in_progress)忍者の誤/clear防止 |
| 1044 | **Read追跡hook** | Write/Edit前の未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| 1053 | **ac_versionハッシュ化** | ACテキスト内容のハッシュでバージョン管理。AC内容差替えを確実に検知 |
| 1054 | **cmd_absorb.sh abort機能** | cmd吸収時に旧cmdで稼働中の忍者を即/clearし無駄な作業時間を防止 |
| 1065 | **タスクYAML hook強制** | queue/tasks/*.yamlへのWrite/Editを無条件deny。deploy_task.sh経由のみ許可 |
| 1067 | **報告YAML hook強制** | queue/reports/*.yamlへのWrite/Editを無条件deny。report_field_set.sh経由のみ許可 |
| 1111 | **家老教訓自動ロード** | /clear Recovery手順にlessons_karo.yaml読込を追加。家老の教訓参照漏れ防止 |
| 1113 | **gate穴検出3問トリガー** | GATE CLEAR時にgate_improvement_trigger.sh自動発火。3問で防御層の穴を検出 |
| 1117 | **hook失敗自動記録+穴検出3問** | 報告テンプレートにhook_failures欄追加。hook失敗→穴検出3問を自動連鎖 |
| 1118 | ラルフループ効果検証 | 学習ループ(clear→知識基盤残存→穴検出→防御層強化)の定量検証スクリプト |
| 1119/1120 | **自動トリム機構** | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive_completed.shで自動トリム |

→ 完了履歴: `context/cmd-chronicle.md` 03-18〜03-20

> **思考の起源（経験的知識。圧縮禁止。過程が本体）**:
> - 免疫系/ラルフループ/自動化×強制の到達過程 → `memory/deepdive_why_chain_20260321.md`
> - System 1(gate自動)/System 2(なぜなぜ検証)の二重ループ → `memory/dialogue_heuristics_system2_20260401.md`
> - 第二層学習ループ（軍師↔家老還流） → `memory/dialogue_second_layer_20260321.md`

## 直近改善（cmd_3300〜GA-050）

CDP production checkはdeploy証跡が必要な場合だけ実行する。readonly ref回帰テストはself-contained化済み。context鮮度gateは10秒cacheを持つため、調査時は `CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1` で一次判定を取る。
→ `scripts/cmd_complete_gate.sh` / `scripts/gates/gate_gunshi_report_precheck.sh` / `tests/unit/test_cmd_complete_gate.bats` / `tests/unit/test_sg_pre25_readonly_ref.bats`
→ SG-PRE30(LG046 lib-only関数参照グローバル機械列挙のgate化)実装記録: [[gunshi_idle_lg046_gate_20260704]]（教訓自動化率97%→100%達成）
- L957: batsテスト内でtrap EXIT/RETURNによる一時ファイルcleanupは機能しない(bats-core 1.13.0実測)（cmd_karo_hotfix_unit_tmp_cleanup_202607041355）
- L959: git ls-files成功0件はfilesystem fallbackへ戻す（cmd_karo_ci_fix_sync_lessons_target_files_ci_red_202607041429）
- L960: repro/検証コマンドをSEMANTIC_STRESS_ABSORB_PENDING=0なしで本番リポジトリに実行すると共有知識ファイルを汚染する（cmd_karo_hotfix_cycle_health_insight_churn_202607041407）
- L964: read-only dirty triageでは自己task/report更新をdirty総量から分離して報告する（cmd_karo_hotfix_dirty_diff_triage_2026070505）
- L965: tool権限制限下のstop hook通過不能は成果物汚染に波及する（cmd_2762）
- L967: CoDD extractペア成果物は同一失敗抽出から生成されるが相互リンクを自動生成しない（cmd_training_L4_idle_202607060047_saizo）

## 軍師品質管理ユニット（cmd_1144〜cmd_1181）

家老+軍師=品質管理ユニット化。軍師が一次レビュー→LGTM→家老スタンプのみ/FAIL→家老介入。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1162 | **忍者報告一次レビュー委譲** | 軍師が忍者報告の一次レビューを担当（report_review）。家老のレビュー負荷消滅→配備+教訓に専念 |
| 1174 | **GSD式6観点+5段階プロトコル** | 軍師レビュー基準体系化: 前提検証/数値再計算/時系列シミュレーション/事前検死/確信度ラベル/North Star整合 |
| 1181 | **git show HEAD検証+証拠必須化** | ドラフトレビュー前提検証でgit show HEAD使用+証拠添付必須。未commit変更の既実装誤判定防止 |

→ `instructions/gunshi.md` §Review Criteria / §5段階思考プロトコル / §Report Review
- L271: gunshi_accuracy_log.sh未作成 — 軍師accuracy計測スクリプト欠落（cmd_1158）
- L281: 軍師基準設計は実例駆動で内面化する（cmd_1174）

## 偵察デフォルト品質5要件（cmd_754+cmd_1476）

偵察は現象特定で止めるな。以下5要件をデフォルト品質として自動化×強制:
1. 変更対象ファイル・行番号
2. 波及先ファイル
3. 関連テスト有無・修正要否
4. エッジケース・副作用
5. **依存関係・順序制約**(flush順序・キャッシュ共有・ネスト読み書き等) ← cmd_1476追加

テンプレート(deploy_task.sh)+ゲートWARN(cmd_design_quality.yaml)で強制。cmd_754で4要件導入、cmd_1476で第5要件追加(DC裁定)。
→ `instructions/ashigaru.md` 偵察テンプレート / `logs/cmd_design_quality.yaml` q4_depth

## 直近改善（cmd_1532〜cmd_1543）

CLEAR率62.7%→84.6%(+21.9pt)。gate品質BLOCK3大原因の構造的解消+新gate2本+autofix拡張+WA記録品質強制。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1532 | **unknown_block_reason修正** | BLOCK_REASONS/MISSING_GATES両方空のelse分岐で個別gate結果を含めるよう修正。直近50BLOCKの17.7%(11件)のRCA不能状態解消 |
| 1533 | **report template FIX hint追加** | Top5 BLOCKパターン(lesson_candidate/binary_checks等)の具体的FIXコマンド例をテンプレートコメントに追記 |
| 1534 | **BLOCKパターン忍者注入** | deploy_task.shにgate_metrics.logのBLOCK集計を追加。忍者別頻出BLOCK原因をtask YAMLのninja_weak_points.gate_blocksに自動注入 |
| 1535 | **autofix 3新パターン(B/C/混合キー)** | lessons_useful dict→list変換にPattern B({0:{},1:{}})/C(混合キー)/混合パターンを網羅追加。WA率Top1のreport_yaml_format 16件対策 |
| 1536 | **report YAML直接編集hookブロック** | PreToolUse hookでreport YAMLへの直接Edit/Writeを検知→ブロック。report_field_set.sh使用を構造的に強制 |
| 1537 | **typeフィールドSTALE_FIELDS追加** | deploy_task.shのSTALE_FIELDS+_CLEAR_FIELDSにtype追加。前cmdからの残留値持ち越しバグ修正 |
| 1538 | **WA記録category必須化+WARN** | karo_workaround_log.shにcategory空チェック+root_cause空チェック追加。uncategorized急増(1→16件)対策 |
| 1539 | **q7_branch_coverage新設** | cmd_save.shに本番分岐カバレッジチェック追加。条件分岐変更cmdで本番データ確認ACをWARN提案 |
| 1541 | **q11_post_deploy新設** | cmd_save.shにpost-deploy検証チェック追加。本番コード変更cmdにデプロイ後検証ACがない場合WARN |
| 1540 | **fullrecalculate baseline自動保存** | 実行前baseline自動保存+実行後差分サマリ出力。変更の正当性を数値証明 |
| 1542 | **WA記録バリデーション強化** | karo_workaround_log.shにninja_id有効性チェック+root_cause最小長(3文字)+null値拒否を追加 |
| 1543 | **計測検証** | CLEAR率62.7%→84.6%(+21.9pt)を実測。学習ループ完結 |

→ 完了履歴: `context/cmd-chronicle.md` 03-30 / `scripts/cmd_save.sh` / `scripts/cmd_complete_gate.sh` / `scripts/deploy_task.sh` / `scripts/karo_workaround_log.sh`

## 直近改善（2026-04-16〜2026-04-30 CoDD波 / GP-198〜240）

| 領域 | 結論 | 参照 |
|------|------|------|
| cmd_publish pre-flight | `cmd_publish.sh` のPython YAML parseをawk block scanへ置換し、`grep -c || echo 0` の0件二重出力を防止。CoDD生成物はwave1-3まで保存、最終計測はafter設計書を正とする | `docs/research/cmd_2585_cmd_publish_after_20260506.md`, `docs/research/codd_refactor_registry.md` |
| CoDD改善32本 | cmd_1951の全量プロファイリングを起点にhot path 32本を改善。代表値: `cmd_save.sh 4.02s→1.06s (-73.6%)`, `deploy_task.sh 2639ms→32ms`, `gate_karo_startup.sh 464ms→190ms` | `docs/research/codd_refactor_registry.md`, `context/cmd-chronicle.md` 04-16 |
| cmd_3801 fork削減 | 軍師分析(blt_20260709_142137: 820ms・479 fork)を受け、`is_gate_or_hook_addition_cmd`(4呼出元)と`collect_primary_cmd_targets`(2呼出元、8段awk/sed/grep/sortパイプライン)を、1プロセス内で不変の`$CMD_BLOCK_NC`をキーにメモ化。fixture計測でfork proxy 168→159(-5.4%)・wall-clock -31〜39%、`collect_primary_cmd_targets`単体では2回目呼出し7fork→0fork(-100%)。tests/unit/test_cmd_save.bats 124/124 PASS+関連6ファイル184/184 PASS | `docs/research/cmd_3801_cmd_save_speedup.md` |
| cmd_save project cache | 82 checks内で不変のproject fieldをinvocation単位のscalar cacheへ統合し、5走の出力SHA・verdictを5/5不変のまま重複parseを除去 | `cmd_karo_hotfix_ready_defense_overhead_cmd_save82_202607191148`, commit `342f4cd90` |
| hidden-infra ready adapter | defense overhead・retro events・bulletin failure・gate fireの4ログを共通候補へ正規化し、頻度×対処コストで優先順位付け、根因SHAでdedupして既存throughput connectorへexactly-once供給する | `scripts/throughput_growth_loop.sh`, `cmd_karo_hotfix_hidden_infra_bug_ready_lane_202607191231`, commit `ba8b533dd` |
| Obsidian traversal ready lane | preflight・semantic search・causal backlinksの着地nodeから実在linkを1hop以上辿ったeventだけを記録し、traversal/発見/行動接続の3率を計測、0hopを優先度付きready候補へexactly-once昇格する | `scripts/throughput_scan.sh`, `cmd_karo_hotfix_obsidian_traversal_ready_lane_202607191235`, commit `53d996d41` |
| GP-198/201 Session State | gate FAIL時の失敗履歴をtask再配備へ注入し、`cmd_save.sh` 側でもDiagnose MANDATORY+Session Stateを強制。/newや再配備を跨いでL3診断を保持 | `context/codd.md` §4, `context/cmd-chronicle.md` `cmd_karo_gp198`/`cmd_1939` |
| GP-199 退化計測 | GP/改善cmdの報告に `before_metrics` / `after_metrics` / `regression` をWARNで強制し、速度改善が退化を隠さない形に変更 | `scripts/gates/gate_report_format.sh`, `context/cmd-chronicle.md` `cmd_1941` |
| GP-202 成果物プレフィックス検査 | `files_modified` に `parent_cmd` プレフィックスが無い場合WARN。cmd_1948事故系の「別cmd成果物上書き」をゲートで検知 | `scripts/gates/gate_report_format.sh`, `tests/unit/test_report_template_gate_compat.bats` |
| GP-204/208 運用耐障害 | `daemon_watchdog.sh` は `set -e` / 二重flockを外して部分失敗で全体停止しない形に修正。`bulletin_write.sh` は掲示板通知を80文字要約でなく全文inbox配信へ変更 | `scripts/daemon_watchdog.sh`, `scripts/bulletin_write.sh` |
| cmd_3577 掲示板action_required追跡 | 軍師の穴発見/改善提案投稿を`action_required`へ自動昇格し、`gate_karo_startup.sh`が`actioned_by`空の未対応掲示板をWARN表示する | `scripts/bulletin_write.sh`, `scripts/gates/gate_karo_startup.sh`, `tests/unit/test_bulletin_board.bats`, `tests/unit/test_gate_karo_startup.bats` |
| f171a817 | `ninja_monitor.sh` のtask `completed_at` 更新をPython全体再出力から `yaml_field_set.sh` へ置換し、運用YAML破壊リスクを除去 | `scripts/ninja_monitor.sh` |
| 1603b5d2 | `inbox_write.sh` のinbox初期化をflock内へ移動し、同時配信時の初期化競合を防止 | `scripts/inbox_write.sh` |
| b7cf7fba | gate群のtask status検出をflat/nested両YAML形式対応へ拡張 | `scripts/gates/*` |
| 6ccea588 | `cmd_complete_gate.sh` 内Python blockをflat task YAML対応に修正 | `scripts/cmd_complete_gate.sh` |
| 2ade4e4e | stale `inotifywait` を親プロセス生存確認で除外し、旧watcherの誤nudgeを防止 | `scripts/inbox_watcher.sh` |
| 8b7f28b3 | `deploy_task.sh` のstale archiveが稼働中peer reportを退避しないよう保護 | `scripts/deploy_task.sh` |
| 64ec3aa5 | karo_direct cmdでもtask YAMLから `scout_exempt` を読むよう修正 | `scripts/deploy_task.sh` |
| 6275f18b | Guard7のread_log不在をCodex互換のためBLOCKからWARNへ降格 | `scripts/hooks/*` |
| 2043181f | 軍師SG-PRE3bで忍者手動記入commit hashの実在検証を追加 | `scripts/gunshi*` |
| 7018b629 | 軍師cs_checklist検出を値付き行にも対応させ、チェックリスト見落としを防止 | `scripts/gunshi*` |
| b079eb73 | `ac_physical_verify` にプロジェクトリポジトリfallback検索を追加し、外部PJ参照の実在確認を強化 | `scripts/ac_physical_verify.sh` |
| d26d6ac6 | `inbox_write.sh` がarchive移動済み報告YAMLをfallback検索できるよう修正 | `scripts/inbox_write.sh` |
| 7513b8da | `inbox_watcher.sh` のCodexナッジ再読指示を `task_assigned` 時のみに限定 | `scripts/inbox_watcher.sh` |
| 6108be73d | `deploy_task.sh` のstale cmd id resetを修正 | `scripts/deploy_task.sh` |
| 8b91a001 | cmd_3715: `memory_db_knowledge_write.sh`にLayer2(semantic_index_update.sh)+Layer3(Obsidian候補ログ)自動連鎖を追加。失敗は`logs/three_layer_chain_async.log`へ記録し`gate_three_layer_health.sh`が未貫通件数として検出 | `scripts/memory_db_knowledge_write.sh`, `scripts/gates/gate_three_layer_health.sh` |
| 39448c96 | `extract_command_files.sh`のread_markersに「から」を追加(cmd_3713/3714 BLOCK根因分析より)。「から」+近接write marker併存時の誤分類は未解消の部分修正 | `scripts/lib/extract_command_files.sh` |

