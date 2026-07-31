# 隠れたインフラバグ・Gate/Hook品質 — As-Is / To-Be 5W1H修正設計書

| 項目 | 値 |
|---|---|
| 作成 | 2026-07-30 家老 |
| 再構築 | 2026-07-31 家老 |
| 進捗更新 | 2026-07-31 23:59 家老 |
| 版 | v3.4 As-Is / To-Be 5W1H + causal-preservation / universal-benefit contract |
| 対象 | `multi-agent-shogun` 制御面、gate、hook、配備、完了、CI、知識還流。Codex専用設計ではなく、全configured CLI/model/effort/service-tier/OS-filesystem tupleを対象とする |
| code baseline | `55b3df6d4d937c7683ef1ca9a83393760d593e47` |
| canonical manifest | `docs/research/hidden-infrastructure-gate-hook-canonical-manifest-20260731.yaml` |
| Wave 0 receipt | `docs/research/hidden-infrastructure-gate-hook-wave0-receipts-20260731.yaml` |
| Gist | `c18ce89c63d6d7beef7a0fd252fe8d9f` |
| 親cmd | `cmd_4200` |

## §-2 現在地（最初に読め）

結論: **Gate 0Bとdurable-state foundationは受入済み。親AC基準2/3完了。** 残るAC3はWave 1Aから順次実装中であり、現在はR01 lock identityを実測している。

| 段階 | 状態 | 一次証跡 | 数値 |
|---|---|---|---:|
| Gate 0A contract | `ACCEPTED` | `9e5f8a382` | canonical 17/17、caller 44/44、Gist/local SHA一致 |
| Wave 0 runtime probe | `ACCEPTED` | `ce54074be` | executed 17/17、OPEN 13、SUPERSEDED 4、未実行0 |
| Gate 0B evidence prerequisite | `ACCEPTED` | `f37a4365a` | SHA不一致0、未来時刻0、未分類0 |
| Gate 0B wave map | `ACCEPTED` | `2e1090bb7`、foundation map | OPEN 13/13、未割当0、owner重複0、循環0、serialization key欠落0 |
| AC2 durable-state foundation | `ACCEPTED` | `4c89d38ca` | focused 17/17 PASS、SKIP 0、hard-crash時 effect 2→1 |
| AC3 Wave 1A R01 | `IN_PROGRESS` | `6f4e4b77b`、`queue/tasks/tobisaru.yaml` | post-commit 10反復もsubmitted 160/160、marked 80/80、lost/duplicate/parse 0。task-scope 10 test実行中 |
| 親cmd completion gate | `BLOCK_EXPECTED` | `cmd_complete_gate.sh cmd_4200` | 未充足は `parent_ac_uncovered:AC3` 1件のみ |

現manifest: `current_phase=WAVE_1A_IDENTITY`、`phase_state=IN_PROGRESS`、`next_phase=WAVE_1B_OWNERSHIP`。AC3はfoundation mapの依存順・serialization keyに従い直列進行する。

### §-2.1 Foundation敵対検証の修正前→修正後

| 不変量 | 修正前 | 修正後 |
|---|---:|---:|
| 空artifact/ledgerの偽terminal | rc 0 | fail-close |
| subject path traversal root escape | 1 | 0 |
| symlink state-dir root escape | 1 | 0 |
| ack-loss retryのeffect count | 2 | 1（`outcome_unknown`） |
| hard process crash後のnaive retry | rc 0、effect 2 | rc 10、effect 1、provider reconcile限定 |
| test内の明示的破壊コマンド | 3 | 0 |
| focused contract | 未確定 | 17/17 PASS、SKIP 0 |

## §-1 スコープ・SSOT・境界

### §-1.1 SSOT

| 情報 | 正本 | 本書の役割 |
|---|---|---|
| finding ID、caller、runtime分類、receipt | canonical manifest | 設計意図・進行順を示す |
| Wave 0実出力 | Wave 0 receipt | 結果の要約のみ持つ |
| 実装コード | 対象script/hook | 変更境界を規定する |
| レビュー | `queue/gates/cmd_4200/sg7_bundle.json`、掲示板 | dispositionと履歴を残す |

### §-1.2 In / Out

| In scope | Out of scope |
|---|---|
| lock identity、owner transaction、WAL/reconciler、terminal receipt、outbox、hook ownership、CI inventory、knowledge provenance | 設計にない新機能 |
| 隔離root/fake境界でのfault injection | 本番queue/tmux/ntfy/networkへのfault injection |
| focused testと固定SHA最終checkpoint | timeout増加、SKIP容認、母集団縮小による見かけのPASS |
| 既存防御を維持したcaller移行 | gate/hookの緩和・迂回 |

### §-1.3 維持する既存防御

- 二段review順序、cmd単位flock、FAIL_CLOSE時のgate非起動、archive再実行checkpointを維持する。
- curated manual aliasの即時採用意図を維持し、例外削除ではなくprovenanceを型にする。
- CI RED時cache無効化を維持し、local dirty source identityだけを補う。
- default-delete test policyを維持し、一時testを最終diffへ残さない。

## §0 Executive Decision

旧設計の方向は正しいが、個別hook追加から開始してはならない。17 findingは4根因へ収束するため、**共通durable primitive → shadow → caller単位canary → 旧経路撤去**の順で直す。

### §0.0 旧系が成り立っていた因果と、保存を優先する理由

新しい抽象化は、旧系の結論だけを上書きしない。まず「なぜその仕組みで長期運用が成立したか」を歴史・現物・実績から復元する。

| 因果の段階 | 一次・準一次証跡 | 成り立っていた理由 | 今回保存する不変量 |
|---|---|---|---|
| Claude主編成の成立 | `context/infrastructure.md` tmux編成、`config/settings.yaml`、Claude実機pane | Claude native hookと既存手順が同じlifecycleで長期に運用され、ロールと復帰手順がそれを前提に蓄積した | Claudeをprimaryとし、event・prompt・reset・inbox・report・completeの使い勝手を不変とする |
| native hookが優先された因果 | `.claude/settings.json`、`.claude/hooks/*`、`config/cli_events.yaml` | `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Stop`がターンlifecycleの正規境界で動き、早期検出と追加contextを小さい運用税で与えた | Claude native hookを等価性未証明のdaemon/polling/wrapperで置換しない |
| CLI外共通層が必要になった因果 | `docs/research/multi-cli-hook-event-commonization-design_20260602.md`、`context/infrastructure.md` §Codex multi-CLI統合 | CodexにClaude Stop blockを単純移植すると再生成loopが起き、同eventでも実行意味論が異なった | 共通化は「同じhook実装」ではなく「同じ軍規event」。CLIごとのcapability adapterを維持する |
| 環境強制がモデルより優先された因果 | `context/training-cycle.md` §24-§25 | Opus 4.6は2条件で2/2安定、GPTはテンプレート有無で0/2→2/2、Sonnetは失敗箇所が移動した。モデル性質で回避すると別モデルで破綻する | 安全性はモデル非依存のgate/template/stateへ置くが、CLI nativeの有利な境界は消さない |
| Codex補完が許された因果 | `.codex/hooks.json`、Codex adapter、daemon/gate receipts | Claudeの主系を変更せず、Claude非対応時・一時配置時の穴をCLI別に埋められた | Codexの便益は補完範囲に限定し、Claude主系へ運用税・遅延・手順増を逆流させない |

したがって採否順序は次で固定する。

1. 旧Claude主系の導入理由・事故回避・成功実績を対象fileの`git log` / `git blame`、教訓、運用文書から復元する。
2. 変更がその因果辺のどれを切るかを、`old_reason -> changed_boundary -> user/runtime effect`で3行記録する。
3. 切る因果辺が0、または同一fixtureで等価性と純便益を証明した場合だけ採用する。
4. Claudeを含む任意のsupport tupleで1件でも使い勝手・latency・安全性・復帰性が悪化する、または純便益が未証明なら**NO-CHANGE CLOSE**とする。既にcanaryを入れた場合は保存したold-pathへrollbackする。
5. 「CodexでPASSした」「共通化できる」「新しい方が整っている」は単独で採用根拠にならない。旧系の成立因果を保存した上で、全対象に純便益があることを要する。

1. identityを`subject_id + generation + phase + terminal_receipt`へ統一する。
2. 複数file mutationを原子的と称さず、WALとstartup reconcilerで旧/新いずれかへ収束させる。
3. 受付・親exit・markerを完了とみなさず、artifact hashとside-effect ledgerを持つterminal receiptだけを完了とする。
4. retry可能な外部副作用をtransactional outboxとidempotency keyで収束させる。
5. 共通primitiveを一括置換せず、read-only shadowとcaller単位canaryを通す。
6. 品質だけでなくwall/lock-wait/recoveryを測定し、スループット退行を停止条件にする。

### §0.1 実行基盤の大前提 — multi CLI / model / effort / OS

**本書はCodex単体の設計書ではない。主編成はClaudeであり、Codexは補完・検証・一時配置のCLIである。** 正本はCLI固有hook設定ではなく、共通event・durable state・gate契約である。Claude CodeとCodexは能力差をadapterで吸収し、model/effort/service tierは実行条件、OS/filesystemは永続化・監視・性能条件として明示的に検証する。現在のactive paneがCodex寄りでも、それを主編成変更・Claude support縮小・Claude経路撤去の根拠にしない。

| 軸 | 現在の実体・正本 | 設計契約 |
|---|---|---|
| CLI | event意味論=`config/cli_events.yaml`、能力profile=`config/cli_profiles.yaml`、配置=`config/settings.yaml` | CLI固有hookをSSOTにしない。共通eventを各CLIのcapability adapterへ写像し、未対応eventはdaemon/gate/scriptで等価保証する |
| model | Claude Opus/Sonnet系、GPT系を含むconfigured `model_name` | model名で安全性を分岐しない。全configured model tupleで同一binary invariantを満たす |
| effort / tier | low/medium/high等のeffort、default/fast等のservice tier | latency・timeout・出力特性を計測条件へ含める。高effort 1件を他tupleの代理にしない |
| OS / filesystem | WSL2+DrvFs(`/mnt/c`)、Linux filesystem、Windows host境界。追加OSはmanifestで明示 | flock、atomic replace、fsync、symlink、mtime、inotify/stat、実行bit、改行をOS/filesystem別に検証する。未検証OSをportableと称さない |
| shell / process | bash、tmux、CLI child process | PID/PGID、signal、prompt、TTY挙動をCLI×OS tupleで検証する |

軍師敵対レビューで、active-only母集団は9/9 Codex・3 distinct tupleとなり、inactive supported Claudeを0件のまま`executed == discovered`にできると実証された。よって母集団を次の3層へ分離する。

| matrix | 生成元 | 用途 | terminal条件 |
|---|---|---|---|
| `support_matrix` | To-Be `config/runtime_support_matrix.yaml`の明示rowとvalid constraint | release可能と宣言する全runtime。inactiveも含む | **release terminalの正本**。全row executed、FAIL 0、SKIP 0、receipt欠落0 |
| `configured_matrix` | `config/settings.yaml`を下記resolverで解決 | 現在配置する全agent tuple | support rowとの対応N/N、type/binary矛盾0。unsupported配置はBLOCK |
| `active_matrix` | tmux/process banner、実binary、mount/OS probe | 実際に稼働したtupleの観測 | configuredとの一致N/N。support母集団の代替には使わない |

検証母集団は`support_matrix ∪ configured_matrix`の全distinct **valid tuple**とする。activeは観測値であり、inactive rowを除外する根拠にしない。

`support_matrix`はClaude primary rowを必須とし、Claude row 0件ではschema validation自体をBLOCKする。Codex rowの増加・active比率・一時的な全Codex配置はClaude primary rowを置換しない。

```text
(cli_type, model_name, effort, service_tier, os_family, filesystem_type, hook_capability_set)
```

同一modelでもeffort/tier/OS/filesystemが異なれば別tupleである。`selected / discovered / executed`を別計数し、`executed == discovered`、FAIL 0、SKIP 0をterminal条件とする。未対応tupleは黙って除外せず`UNSUPPORTED`として根拠・代替保証・ownerをmanifestへ残す。

`UNSUPPORTED`は全直積の後処理に使わない。`runtime_support_matrix.yaml`は許可rowまたはvalid constraintを先に列挙し、generatorはその集合だけを展開する。configured tupleがvalid集合外なら`UNSUPPORTED`へ逃がさず配置エラーとしてBLOCKする。

### §0.2 Runtime matrix artifact・resolver・identity契約

To-Be artifact:

| artifact | owner | 必須内容 |
|---|---|---|
| `config/runtime_support_matrix.yaml` | platform owner | schema version、CLI capability、許可model/effort/tier、OS/filesystem/runner、valid constraint、support status |
| `scripts/runtime_matrix_generate.py` | Wave 0/4A | support/configured/activeの3 manifest生成、tuple ID採番、矛盾検出 |
| `queue/gates/cmd_4200/runtime_matrix_manifest.json` | generator | fixed source SHA、3 matrix全row、selected/discovered/executed、runner owner、receipt path |
| `queue/gates/cmd_4200/runtime_matrix_receipts/<tuple_id>.json` | 各runner | tuple identity、binary/banner、event coverage、fault/test結果、artifact SHA、開始/終了時刻 |
| `scripts/gates/gate_runtime_compatibility.sh` | final checkpoint | support全row、configured対応、active一致、receipt N/N、FAIL/SKIP/未分類0を強制 |

resolver precedenceは次で固定し、暗黙fallbackを禁止する。

1. `config/settings.yaml:cli.agents.<agent>`の`type/model_name/service_tier`をconfigured値とする。
2. 欠落fieldだけを`config/cli_profiles.yaml:defaults.agents.<agent>`、次に`defaults`から補う。
3. `profiles.<cli>`は能力と既定launch templateだけを与え、agentの明示値を上書きしない。
4. `model_name`接尾辞からeffortを正規化し、明示effortとの不一致はBLOCKする。
5. launch commandの実binary basename、tmux `@agent_cli`、process bannerがresolved `type`と全一致した時だけactive rowを有効化する。

As-Isでは`cli_profiles.yaml`に`type: codex`とClaude起動binaryが混在するrowが2件ある。generatorはこれを自動補正せず`type_binary_mismatch=2`としてBLOCKし、正本修正後に0を要求する。

### §0.2.1 編成変更と互換性検証の分離

- cmd_4200はCLI/model/effortの**配備変更を行わない**。`config/settings.yaml`更新、pane respawn、default切替はscope外。
- matrix生成・fixture・probeは実paneの編成を変えず、isolated root/fake paneまたは明示的な検証runnerで実行する。
- mismatch検出は自動switchや自動respawnを起こさずBLOCK receiptだけを出す。編成変更は殿の明示指示とCLI switch正規手順に限定する。
- primary Claudeの既存event/prompt/reset/inbox/report/complete挙動をbefore baselineとして保存し、Codex adapter追加後も同じfixtureがPASSしなければrollbackする。
- Codexでしか再現しない問題をClaude共通実装へ無条件に持ち込まない。共通primitive変更が必要ならClaude before/after parityを同一commitで証明する。

### §0.3 OS / filesystem support境界

| runtime | 現在の証跡 | release扱い |
|---|---|---|
| WSL2 + DrvFs/9p (`/mnt/c`) | 実host・workspaceで観測済み | support row。flock/replace/symlink/mtime/inotify-stat/exec-bit/CRLFを実走 |
| WSL2 + native ext4 | 同hostのnative mountを観測済み | support row候補。専用runner receipt完了までBLOCK |
| native Linux host | runner証跡0 | `PLANNED`。portable PASSへ算入禁止 |
| Windows-native | host境界のみ観測、runner証跡0 | `PLANNED`。tmux/bash前提を満たすrunner定義まで算入禁止 |

各support rowは`runner_id + os build/kernel + filesystem/mount options + shell + CLI version`をidentityとする。WSL上のWindows host観測をWindows-native実行証跡に数えない。

### §0.4 Claude primary非退行契約

Claude primary baselineは抽象event 6 cellではなく、**現行`.claude/settings.json`から再帰展開した実event/action graph全数**とする。現行直接manifestは6 event type / 12 top-level handlerであり、`SessionEnd`、Stop 5 handler、UserPromptSubmit 3 handlerを含む。`pretool-dispatch.sh` / `posttool-dispatch.sh`、その先のcombined/child hookもleaf actionまで展開し、すべてをbaselineに入れる。`config/cli_events.yaml`の抽象cellは意味論の索引であり、現行Claude actionを消す根拠にしない。

| discovery layer | As-Is最小数 | terminal契約 |
|---|---:|---|
| `.claude/settings.json` event type | 6 | `SessionStart` / `PreToolUse` / `PostToolUse` / `Stop` / `SessionEnd` / `UserPromptSubmit` 全数 |
| top-level handler | 12 | command、matcher、timeout、順序、出力意味論をhash化し12/12 receipt |
| dispatcher / combined child | generated N | shell構文と実fixtureの両方からleaf actionを展開。discovered=selected=executed=N、未展開0 |
| lifecycle side effect | generated N | state/last_active、log、lint、alert、inbox、clear-checkを独立actionとし、合成済みの1 handlerで帳消ししない |

baseline artifactは`queue/gates/cmd_4200/claude_primary_baseline/` に固定する。`source_commit` / `git_blob` / file SHA-256 / mode / handler graph / child SHA-256 / fixture receiptを持つ。現行起点の`.claude/settings.json` blobは`be93a9ff5706a7d79eebedfeb52a668310bc1e8b`、working content SHA-256は`4b1945c8477afdba71d6fe7fdf7a10b8a49a0e6f43e3a5c6476a1b0bae79ca52`である。最終実装checkpointでは開始時HEADを改めて固定し、古い設計書記載値を流用しない。

| invariant | binary check |
|---|---|
| event reachability | matcher fixtureとisolated interactive probeが6/6到達 |
| payload/decision | additional context、deny/warn、Stop decisionのschema差分0 |
| lifecycle | `/clear`、idle flag、inbox nudge、report handoff、cmd completionがbefore/after同結果 |
| latency | event別p95が既定budget以内。Codex都合のtimeout増加をClaudeへ波及させない |
| ownership | Claude hook ownerは各action 1。Codex daemon追加で二重owner 0 |
| rollback | `scripts/runtime_compatibility_restore.sh --receipt <baseline.json> --dry-run`でpath/mode/SHA/ownerを照合し、`--apply`はcanary所有pathのみatomic restoreする。他者dirty path、hash不一致、scope外はBLOCK |

Claude primaryのexpanded action N/N receiptがないcommitは、Codex側が全PASSでもrelease不可とする。rollbackは「adapter pointerを戻す」という散文ではなく、実在script、baseline artifact、dry-run、apply後再fixtureの4点をそろえる。

### §0.5 編成mutation journal

`queue/gates/cmd_4200/runtime_mutations.jsonl`に、検証窓内の全pane spawn/respawn/switchを`event_id` / `timestamp` / `owner` / `cause` / `cmd_id` / before-after pane PID+starttime / CLI / model / effort / service tierで記録する。

- 全体respawn数0を要求しない。idle recovery等の正常別owner動作をcmd_4200に誤帰属させないためである。
- cmd_4200起因のsettings変更、pane respawn、CLI/model/effort switchはそれぞれ0を要求する。owner/cause不明は0と数えずBLOCKする。
- journalなしのmtime・pane birth時刻のみで「cmd起因0」と判定しない。今回の再レビュでcommit後pane birth 1/9を観測したがowner receiptがないため、AC22は未判定とする。

## §1 As-Is — 現状5W1H

### §1.1 As-Is 5W1H

| 軸 | 現状 |
|---|---|
| Why | 局所hotfixがraceを消しても、identity・owner・completion・SSOTの分裂が別callerで再発する |
| What | marker、文字列grep、独自lock、親process rc、複数file copyを各scriptが独自解釈する |
| Who | deploy/review/complete/watcher/test/semanticの各callerが状態ownerを部分的に持つ |
| When | crash、respawn、並行writer、retry、stale cache、prompt遷移の境界で破綻する |
| Where | `scripts/auto_deploy_next.sh`、`deploy_task.sh`、`cmd_complete_gate.sh`、`review_approval.sh`、`run_tests.sh`、`inbox_watcher.sh`、semantic/hook群 |
| How | denylist、部分一致、marker先行公開、非durable async tail、分裂したCI inventoryで進行する |

### §1.2 監査方法

独立6レーンは兄弟報告を参照せず、固定commitと自作probeで検証した。

| lane | 対象 | 問い |
|---|---|---|
| A | gate / hook | FP、FN、fail-open、exit code、責務重複 |
| B | inbox / watcher / lock | Lost Update、重複配送、prompt誤入力、無駄待機 |
| C | deploy / lifecycle | ghost、stale、再配備、auto-clear、状態乖離 |
| D | report / review / complete | 偽CLEAR、永久BLOCK、lock競合、非同期tail |
| E | tests / CI / metrics | focused漏れ、SKIP隠蔽、local/CI非対称、fixture汚染 |
| F | insight / lesson / memory | 未resolve、誤dedupe、三層未貫通、観測盲点 |

各findingは再現yes/no、FP/FN分子分母、fail-open、変更file/line、波及先、focused test、Level 5防御、rollback方式を記録する。

### §1.3 As-Is baseline

| 指標 | 実測 |
|---|---:|
| 直近2,000行のgate BLOCK | 166 |
| `review_two_phase_pending` | 77（46.4%） |
| `context_freshness_own_commit_unreflected` | 35（21.1%） |
| `sg7_bundle_missing_or_invalid` | 14（8.4%） |
| CI関連 | 17（10.2%） |
| その他 | 23（13.9%） |
| gate scripts | 56 |
| test files | 205 |
| gate名と直接一致testなし | 33 |
| pending insights（監査時） | 30 |

名称不一致は未テストの証明ではない。caller経由の間接coverageを追跡してから判定する。

### §1.4 Canonical findings（17件）

| ID | Sev | As-Is / evidence | To-Be primitive・invariant |
|---|---|---|---|
| R01 | CRITICAL | appendとmark-readのlock pathが別。Lost Update 1/1 | `lock_identity`; 同一inboxは1 lock identity |
| R03 | HIGH | source/target双方active 2/2 | `owner_transaction`; executable owner `<=1` |
| R04 | HIGH | deploy rc=7後もghost assigned 2/2 | `deploy_receipt`; terminalまでrollback armed |
| R05 | HIGH | `in_progress`をauto-deploy再選択 1/1 | `deploy_selector`; pending/idle allowlist |
| R06 | HIGH | `cmd_12`が`cmd_123` CLEARを誤認 1/1 | `exact_correlation`; typed完全一致 |
| R07 | HIGH | dispatch即死後もmarker公開、retry不能 | `durable_dispatch`; terminal receipt後だけmarker |
| R08 | HIGH | 親exit0後のtail失敗が不可視 | `completion_job`; queuedとcompletedを分離 |
| R09 | HIGH | 永続contract 177中97がpush CI未所属。別parserと+2差 | `contract_inventory`; canonical CI membership N/N |
| R10 | HIGH | terminal rc publicationとidentityが競合 | `immutable_rc_receipt`; 1 identity 1 rc |
| R11 | HIGH | unsigned manual aliasがpolicy前に自動昇格 | `provenance_policy`; signed curatedだけ即時昇格 |
| R13 | MEDIUM | dirty tracked sourceでも古いcache PASSを再利用可能 | `cache_identity`; worktree hashをkeyへ含める |
| R14 | MEDIUM | hook branch到達不能、Codex単体rc=1 | `hook_owner`; 1 reachable owner、BLOCK exit=2 |
| R15 | MEDIUM | artifact無変更でもinsightをresolved化 | `insight_state`; resolvedはartifact receipt必須 |
| V01 | HIGH | insight同時writeは1/2 FAIL、隔離1/1 PASS | `insight_writer`; atomic write、lost update 0 |
| V02 | HIGH | nudge表示と実体のcorrelation欠落 | `delivery_trace`; eventごとに1 durable trace |
| V03 | CRITICAL候補 | auto-deploy外lockと内lockが別domain | `lock_domain`; false success/lost update 0 |
| V04 | HIGH | idle確認後からsend直前にprompt再確認なし | `prompt_safe_send`; confirmation送信0/30、idle 30/30 |

Wave 0結果: `selected=17`、`discovered=17`、`executed=17`、`OPEN_CONFIRMED=13`、`SUPERSEDED_WITH_EVIDENCE=4`、`NEEDS_NEW_PROBE=0`。詳細はmanifest/receiptを読め。推測するな。

### §1.5 旧設計自身の欠陥

| ID | As-Is gap | To-Be |
|---|---|---|
| N01 | 複数file変更を「1 transaction」と誤称 | WAL + generation + step receipt + reconciler |
| N02 | crash後rollback owner不在 | startup reconcilerを唯一owner化 |
| N03 | retry副作用の重複境界なし | idempotency key + side-effect ledger |
| N04 | 共通primitive一括置換が新SPOF | shadow→canary→段階移行→撤去 |
| N05 | receiptがrc中心 | artifact hash + terminal phase + side-effect IDs |
| N06 | FP/FN母集団未定義 | 正例・反例・境界例の固定corpus |
| N07 | probabilistic raceへ正常反復だけ | mutation point全数のfault matrix |
| N08 | 性能退行の停止条件なし | wall/lock wait/recovery budget |
| N09 | severity語彙が混在 | CRITICAL/HIGH/MEDIUMへ統一 |
| N10 | remote ahead/behindが共有作業依存 | fixed SHA isolated checkpoint限定 |

## §2 Gap — なぜ現状の延長では直らないか

### §2.1 4共通根因

| 根因 | As-Is | 失敗 | To-Be |
|---|---|---|---|
| identity曖昧 | 部分一致、独自lock、singleflight別identity | 誤相関・Lost Update | typed subject + generation + canonical lock |
| owner移転非原子 | source/target、review/dispatch、parent/tailを別更新 | 二重owner・ghost | WAL + fenced active pointer + reconciler |
| 受付=完了 | marker、親rc0、queuedをterminal扱い | 偽完了・retry不能 | terminal receipt + artifact + side-effect ledger |
| SSOT分裂 | contract/CI、matcher/handler、manual/promotionが別 | 未実行・到達不能・誤昇格 | generated inventory + single owner + provenance type |

### §2.2 失敗連鎖

```text
曖昧identity
  → writer/readerが別状態を見る
  → markerまたはrcだけが先にterminal化
  → retryが抑止される、または副作用が二重化
  → gate追加で局所検出
  → caller固有例外が増え、次のidentity分裂を作る
```

局所gate追加では連鎖を止めない。正しい入力・identity・ownerを事前生成するLevel 5へ移す。

## §3 To-Be — 目標5W1H

### §3.1 To-Be 5W1H

| 軸 | 目標 |
|---|---|
| Why | crash・retry・並行実行後も状態を旧/新いずれかへ決定的に収束させ、同型事故を構造的に消す |
| What | durable-state foundation（WAL、generation、fence、receipt、outbox、reconciler）と共通identity helper |
| Who | WAL writerはprimitive、recoveryはfenced reconciler、外部副作用はoutbox worker、callerはtyped APIのみ使用 |
| When | mutation intent前、各step後、terminal公開前、retry/restart時に契約を強制する |
| Where | 隔離可能な単一WAL root、canonical helper、manifestで所有fileとserialization keyを固定する |
| How | Gate0B map→foundation→shadow→1 caller canary→全caller移行→rollback window→旧path撤去 |

### §3.2 必須状態スキーマ

| field | 契約 |
|---|---|
| `schema_version` | 未知versionはquarantine。activeに使わない |
| `subject_type` / `subject_id` | cmd/task/review/completion/delivery + 完全一致ID |
| `generation` | WAL lock内compare-and-incrementのみ |
| `fence_token` | mutation直前・実行直前にcurrent一致を再確認 |
| `phase` | intended/prepared/published/terminal/rolled_back |
| `attempt_id` | 試行一意ID |
| `payload_hash` / `artifact_hash` | intentと成果物identity |
| `checksum` | record corruption検出 |
| `idempotency_key` | `subject+generation+action+target+payload_hash` |
| `terminal_result` | CLEAR/BLOCK/FAILED。queuedは禁止 |
| `side_effect_ledger` | 外部副作用receipt集合 |
| `recorded_at` | receipt記録時刻。未来時刻禁止 |

### §3.3 WAL / reconciliation契約

1. 同一filesystem tempへ全体writeする。
2. file `fsync` → atomic rename → directory `fsync`の順でpublishする。
3. checksum/schema不一致はquarantineへ移し、activeに使わない。
4. generationはWAL lock内でのみ採番する。
5. lease付きfenceを持つ単一reconcilerだけがmutationする。
6. lease失効後`2 * lease_ttl`以内に新ownerが開始し、`3 * lease_ttl`以内にterminalまたは明示BLOCKへ収束する。
7. commit pointは同一generationの`terminal receipt + artifact hash + side-effect ledger + current fence`一致時のみ。
8. terminal/rolled_backからの再実行は新generationを必須とする。

遷移:

```text
intended → prepared → published → terminal
    └──────────────→ rolled_back
```

`intended/prepared`は取消または再開する。`published`はartifact/owner一致時だけroll-forwardし、不一致はrollbackする。

### §3.4 Delivery / ownership契約

- local side effectはWAL transactionに包含可能なものだけとする。
- external deliveryはoutboxへ先に永続化し、`reserved/inflight/applied/failed`で管理する。
- provider receiptなしをexactly-onceと称さない。provider別にat-least-once/at-most-onceをmanifestへ明記する。
- safetyは常に`executable_owner_count <= 1`、livenessは終端で`eventually executable_owner_count == 1`。
- active pointerはCAS + fencing readを実行直前に必須化する。文字列statusだけでowner判定しない。
- live mutationをdual-runしない。shadowはimmutable snapshotまたはsandbox WALのread-only計算だけとする。
- comparator差分0/N後、副作用なしreader→1 caller→低影響callerの順でcanaryする。差分1件またはbudget超過で旧pointerへ戻す。
- 全caller移行、rollback window終了、旧path reachable=0の3条件後だけ旧経路を撤去する。

### §3.5 Isolation / corpus / performance契約

| 項目 | 契約 |
|---|---|
| isolation | queue/log/WALをredirect。tmux/ntfy/networkはfake。real/fake同一ならBLOCK |
| real-state | 実行前後fingerprint差分0。不一致成果は不採用 |
| corpus | 各findingにprimitive/caller/edge/failpoint/expected prefix/invariantを持たせる |
| count | selected/discovered/executedを別計数。最終17/17。縮小禁止 |
| detector | 検知後action（fail-closedまたは自動実行）必須 |
| FP/FN | 固定corpusで`FP/negative total`、`FN/positive total`を記録 |
| performance | fixed SHA、同一load/concurrency、warm/cold、`n>=30`、p50/p95/p99/max/timeout |
| runtime matrix | support/configured/activeを分離し、`support ∪ configured`のvalid tupleを生成。active-only代用禁止、未実行0 |
| stop budget | wall/lock-wait p95 `max(5%,20ms)`、recovery p95 `max(10%,1s)`超過でrollback |

timeout増加、sample減少、load縮小による通過は禁止する。

## §4 故障注入5W1H

| 軸 | 契約 |
|---|---|
| Why | 正常系PASSではcrash/race耐性を証明できない |
| What | 全mutation pointの直前・直後、stale generation、並行writer、二重watcher |
| Who | isolated runnerが実行し、reconciler/primitiveのreceiptを検証する |
| When | caller移行前のfocused test、最終checkpointの全量test |
| Where | redirect queue/log/WAL root + fake tmux/ntfy/network |
| How | deterministic barrierでedgeを全選択し、未実行0を集計する |

各faultは`runtime_support_matrix.yaml`のvalid constraintに従って該当tupleへ展開する。無効なCartesian productは生成しない。CLI固有fault（hook return、Stop、prompt、reset）は該当CLIの全valid tuple、filesystem固有fault（rename、fsync、symlink、mtime、watch）は該当OS/filesystemの全valid tupleで実行する。別CLI・別effort・別OSのPASSを代理証拠にしない。

| fault | 必須結果 |
|---|---|
| lock取得前/後に停止 | owner不明で進まず、再起動後に収束 |
| WAL後・最初のmutation前に停止 | intentから安全に再開または取消 |
| source更新後・target公開前に停止 | active owner二重0 |
| target公開後・source tombstone前に停止 | generation比較で一方だけ実行可能 |
| terminal receipt前に親exit | completed非公開 |
| receipt後・通知前に停止 | 同一keyで通知1回へ収束 |
| stale cache/usage/marker注入 | latest valid generation以外をterminal扱いしない |
| watcher二重起動 | 同一eventの永続副作用1回 |

## §5 実装Wave（When / Who / Where / How）

### §5.0 必須順序

```text
Gate0A contract [DONE]
  → Wave0 probe [DONE]
  → Gate0B closure [DONE]
  → durable-state foundation [DONE]
  → Wave1A identity [IN PROGRESS: R01]
  → Wave1B ownership
  → Wave2A terminal receipt
  → Wave2B safe delivery
  → Wave3 CI/test SSOT
  → Wave4A hook ownership
  → Wave4B knowledge provenance
  → Final checkpoint
```

同一file/callerを変更するWaveは`serialization_key`一致として直列化する。先行terminal receiptなしに後続を開始しない。

### §5.1 Gate 0B closure（完了）

| What | Who | Where | How | Done |
|---|---|---|---|---|
| 17 findingをimplementation unitへ写像 | 家老分解→忍者実測→軍師レビュー | canonical manifest | primitive/file/owner/dependency/serialization key/focused test/rollbackを全数記録 | 未割当0、owner重複0、循環0 |
| phase遷移 | 同上 | manifest | `current_phase=GATE_0B_CLOSURE`→terminal | `next_phase=DURABLE_STATE_FOUNDATION` |

実績: OPEN_CONFIRMED 13/13を実装unitへ写像し、SUPERSEDED 4件を二重実装対象から除外した。受入commitは`2e1090bb7`。

### §5.2 Foundation（完了）

- 隔離可能なWAL root、schema/checksum、atomic publish、generation/fence、reconciler、terminal receipt、outboxを作る。
- primitive単体PASSだけで採用しない。既存readerとのshadow差分0を先に証明する。
- parse/write/corruption/stale fenceをfail-closeする。

実績: `scripts/lib/durable_state.py`、`scripts/lib/durable_state.sh`、`tests/unit/test_durable_state.bats`を実装した。focused 17/17 PASS・SKIP 0、path traversal/symlink escape各0、ack-lossとhard-crashのeffect countを1へ収束させた。受入commitは`4c89d38ca`。

### §5.3 Wave 1A — identity（進行中）

- `lock_path.sh`を唯一のlock identity生成器にしR01を閉じる。
- typed exact-match helperでR06を閉じる。
- immutable rc receipt primitiveを作る。`run_tests.sh` caller置換はWave 3で行う。

進捗: R01を飛猿へ配備済み。対象は`lock_path.sh`、`inbox_write.sh`、`inbox_mark_read.sh`、focused testは`test_lock_path.bats`。初回およびcommit `6f4e4b77b`後の敵対計測は各10反復でsubmitted 160/160、marked 80/80、lost update 0、duplicate 0、parse error 0。task-scope 10 test・報告・軍師reviewが未完了のためterminal扱いしない。

### §5.4 Wave 1B — ownership（R03-R05、採用時V03）

- `auto_deploy_next.sh`のmutationをowner transactionへ置換する。
- commit条件はmutation rc全0、target receipt一致、source tombstone、active count=1、terminal WAL receipt一致。
- crash recovery ownerはstartup reconciler。終了processへ自動復元を期待しない。

### §5.5 Wave 2A — terminal receipt（R07-R08）

- review marker/completion checkpointをterminal receipt後だけ公開する。
- async tailをdurable job化し、supervisorがterminalまで再駆動する。
- dashboard/archive/品質記録/通知を同一idempotency keyで収束させる。

### §5.6 Wave 2B — safe delivery（V02/V04）

- pane送信を中央関数一択にし、送信直前のconfirmation prompt再検出を必須化する。
- watcher event ID→nudge→unreadのcorrelationを永続化し、重複と遅延を別計数する。

### §5.7 Wave 3 — CI/test SSOT（R09/R10/R13）

- `test_necessity`付き永続contractだけからrunner別inventoryを生成する。
- canonical parserでCI所属N/N、未所属0。監査時80/177・未所属97は再採番して置換する。
- leader/joiner/issuerをimmutable rc receiptへ移行する。
- SKIPはFAIL。cache keyへworktree source/runner/fixture/env identityを含める。

### §5.8 Wave 4A — multi-CLI hook ownership（R14）

- `config/cli_events.yaml`の6 eventを唯一の意味論ownerとし、Claude Code / Codex adapterは能力写像だけを持つ。
- 同一event内の順序依存処理はCLIごとに単一adapterへ合成する。CLI固有hook設定の二重ownerを禁止する。
- manifest generatorで、support CLI×6 eventの全cellについてmatcher到達性、実体存在、event coverage、代替daemon/gate coverageを強制する。
- Codexは意図的BLOCKをexit 2、hook errorを別分類し、exit 1によるCLI停止を0件にする。
- Claude CodeはPreToolUse/PostToolUse/Stopのpayload・exit・permissionDecision意味論をfixtureとinteractive probeで固定する。
- Stopは共通実装を押し付けない。Claudeのturn停止とCodexの再生成挙動を別adapterで扱い、再実行loop・silent allow・stale flag・retry capを各CLIで測る。
- Codex Stopを0 hookのまま維持する期間も、`mark_idle`、`log_terminal_response`、`stop_check_inbox`各actionにdaemon/gate/script ownerを1つ割当て、`event_id/action_id/owner/mode/test/receipt`を記録する。代替receipt欠落1件でもrelease BLOCK。

### §5.8.1 Runtime compatibility実装順序

1. `runtime_support_matrix.yaml` schemaとvalid constraintを定義し、Claude primary row必須をschemaで強制する。
2. resolver/generatorを実装し、現状のtype/binary mismatch 2件を検出するfixtureを固定する。
3. mismatchを正本で0へ直し、support/configured/active 3 manifestを生成する。
4. `cli_events.yaml` 6 event×support CLIのcoverage receiptを生成する。先にClaude primary 6/6のbefore/after parityを確定し、その後Codex hookなしcellの代替owner N/Nを証明する。
5. WSL2 DrvFS/native ext4、native Linux、Windows-nativeの各support rowへrunnerを割当てる。runnerなしrowは`PLANNED`のままrelease集合へ入れない。
6. final checkpointでmanifestと全receiptをfixed SHAへ束縛する。

### §5.9 Wave 4B — knowledge provenance（R11/R15/V01）

- signed curated manualだけを即時昇格する。
- pendingを実装待ち/裁定待ち/resolved/discarded_noiseへ型付けする。
- resolvedと三層貫通はartifact receiptで完了判定する。

### §5.10 Final checkpoint

- 各Wave途中はfocused testのみ。固定SHAで全量testを共有1回実行する。
- FAIL=0、SKIP=0、fault edge未実行0、実状態変更0。
- 修正前FAIL→修正後PASSを全件再計測する。
- 固定corpusでFP/FN before/afterを分子/分母付き記録する。
- wall/lock wait/recoveryに未承認退行0。
- fixed SHA isolated checkpointでCI GREENを確認する。共有tree ahead/behindを成果判定へ混ぜない。

## §6 共通二値Acceptance Criteria

| # | Binary check |
|---:|---|
| 1 | canonical 17/17が現HEADで分類済み、receipt欠落0、未分類0 |
| 2 | CRITICAL/HIGHの該当fault edge実行N/N、二重active・二重副作用・偽terminal 0 |
| 3 | gate/hook固定corpusのFP=0、FN=0を分子/分母付きで証明 |
| 4 | state変更がidentity/generation/lock/WAL/receipt/idempotency/reconciliationを全て持つ |
| 5 | focused test FAIL=0、SKIP=0。永続test `test_necessity`宣言N/N |
| 6 | 全量testは最終固定SHA checkpointの共有1回、FAIL=0、SKIP=0 |
| 7 | finding→primitive→file→owner→test→rollbackの未割当0 |
| 8 | CI inventory N/N、未所属0 |
| 9 | owner countは全fault点で`<=1`、終端で`eventually 1` |
| 10 | queued/completedが別状態、terminal未達jobは再駆動される |
| 11 | retry可能な全副作用が同一keyで一度へ収束 |
| 12 | shadow差分0→caller canary→旧path reachable=0の順を厳守 |
| 13 | fixed SHA isolated checkpointを用い共有tree状態を混ぜない |
| 14 | wall/lock wait/recovery budget超過0。超過時rollback済み |
| 15 | lesson/insight/gate metricsへ新checkを還流し、次回起動時に受動注入される |
| 16 | `support_matrix ∪ configured_matrix`のvalid tupleでdiscovered=selected=executed、FAIL=0、SKIP=0、未分類0。active-only母集団は禁止 |
| 17 | `config/cli_events.yaml` 6 event×support CLIの全cellがhookまたは代替ownerへN/N写像され、action単位receipt欠落0 |
| 18 | configured全agentでresolver結果、launch binary、tmux CLI tag、process bannerがN/N一致し、type/binary mismatch 0 |
| 19 | runtime manifestとtuple receiptがfixed source SHA、runner ID、OS/filesystem identityへ束縛され、欠落0・重複0 |
| 20 | native Linux/Windows-nativeをportable保証に含める場合は専用runner executed N/N。証跡0の間は`PLANNED`表示でrelease claim 0 |
| 21 | Claude primary rowがsupport matrixに必ず存在し、`.claude/settings.json`の6 event type / 12 top handler / dispatcher展開leaf Nがbefore/after全数receipt、behavior差分0、二重owner0 |
| 22 | owner/cause付きmutation journal上、cmd_4200起因のsettings変更0、pane respawn0、CLI/model/effort切替0。owner/cause不明0。別ownerの正常respawnは分離計数 |
| 23 | 各変更unitがold design reason、根拠commit/file/line、cut edge、影響、保存方法をN/N記録し、不明0 |
| 24 | support全valid tupleで安全性非退行、Claude primary使い勝手差分0、既定budget内、追加手順税0。1件でも未証明/悪化ならNO-CHANGE CLOSE |
| 25 | canary採用時は旧Claude pathのhash/mode/owner付き保存、実在restore scriptのdry-run PASS、apply後expanded action N/N再現を同一receiptで証明 |

## §7 Decision Ledger

### §7.1 軍師9反証 disposition

| # | 決定 | 反映 | 二値検証 |
|---:|---|---|---|
| 1 | ACCEPTED | WAL/state contract | 必須field、atomicity、recovery、liveness全存在 |
| 2 | ACCEPTED | delivery contract | local/external分離、outbox 4状態、provider semantics全存在 |
| 3 | ACCEPTED | ownership contract | safety `<=1`とliveness `eventually 1`を分離 |
| 4 | ACCEPTED | shadow contract | live dual mutation禁止、canary/rollback/撤去条件全存在 |
| 5 | ACCEPTED | canonical manifest | canonical 17/17、legacy map 2/2、caller未分類0 |
| 6 | ACCEPTED | isolation contract | redirect/fake/preflight/real-state fingerprint全存在 |
| 7 | ACCEPTED | corpus contract | edge全数、selected/discovered/executedを分離 |
| 8 | ACCEPTED | performance contract | SHA/load/n/warm-cold/percentile/budget/rollback全存在 |
| 9 | ACCEPTED | dependency contract | foundation先行、2A/2B依存、serialization key全存在 |

### §7.2 未決事項

| ID | 決めること | 判定方法 | 現在 |
|---|---|---|---|
| D01 | V01を独立findingとして実装するか | Wave 0のsupersession receiptと現行writer契約を照合 | `SUPERSEDED_WITH_EVIDENCE`。独立unitを作らず再発時のみ再開 |
| D02 | V03 lock-domainをR03-R05と同時修正するか | `/mnt/c`隔離競合30回のreceipt | 採用。Wave 1B slot 3、R03/R05後 |
| D03 | V04 prompt-safe sendの採用境界 | confirmation 0/30、idle 30/30 | 採用。Wave 2B slot 2、V02後 |
| D04 | CLI別の限定Stop adapterを使うか | Claude/Codex各configured tupleのinteractive実機でblock後挙動、silent allow、stale、retry capを全確認 | Codexのblock再生成は実測済み。allow JSONはinvalidのため、無出力allowと上限検証までCodex Stop禁止を維持。Claudeは別adapterとして既存Stop意味論を再検証する |
| D05 | runtime母集団の正本 | support/configured/activeを別生成し、active-only誤PASSを再現 | `support_matrix`をrelease terminal、configuredを配置整合、activeを実態観測に固定 |
| D06 | OS portability claim | runner receiptの有無をOS/filesystem rowごとに確認 | WSL2 DrvFSのみ現行実証。native Linux/Windows-nativeはrunner証跡まで`PLANNED` |
| D07 | 主編成の定義 | active pane比率ではなく殿の編成方針とsupport matrix primary fieldで判定 | **Claude primary**。Codex active増加・一時配置でも主編成を変更しない |
| D08 | 新共通層の採用判定 | 旧系の成立因果とsupport全tupleの純便益をbefore/after比較 | 純便益が全数証明されるまで`NO-CHANGE`。Claude悪化1件でrollback |

## §8 Review Checklist

軍師は次を敵対判定せよ。

1. 再現なしの推測を確定問題へ混ぜていないか。
2. gateを弱めてBLOCK率だけ下げていないか。
3. timeout/retry/ignoreによる自動消火がないか。
4. Level 4で止まりLevel 5入力生成へ到達していないか。
5. Wave依存と同一file直列条件に穴がないか。
6. WAL/reconcilerが途中状態を必ず旧/新の一方へ収束させるか。
7. retryがdashboard/通知/archiveを二重化しないか。
8. 共通primitiveが新SPOFになっていないか。
9. superseded findingを再実装していないか。
10. fault corpus・FP/FN母集団を縮めていないか。
11. wall/lock-wait/recoveryを悪化させていないか。
12. 最終checkpointの厳密さを途中tryへ誤適用していないか。
13. configured CLI/model/effort/tier/OS/filesystemのdistinct tupleを全数列挙し、代表1構成で代用していないか。
14. Claudeのhook/Stop意味論をCodex exit codeへ、またはCodexの再生成意味論をClaudeへ誤投影していないか。
15. WSL2/DrvFsのPASSをnative Linux/別filesystemのatomicity・watch・実行bit証拠として流用していないか。
16. support/configured/activeを混同し、active-onlyでinactive Claudeを母集団から消していないか。
17. type文字列だけを信じ、実launch binary・tmux tag・bannerの矛盾を見逃していないか。
18. 全Cartesian productを作って大量の`UNSUPPORTED`で帳尻を合わせていないか。valid constraintは先に定義されているか。
19. hook不在eventを「daemonで代替」と散文だけで済ませず、action別owner/test/receipt N/Nを持つか。
20. active Codex比率を理由にClaude primary row・fixture・rollbackを削っていないか。
21. compatibility検証が実paneのCLI/model/effortを勝手に変更・respawnしていないか。
22. Claude baselineを抽象6 cellに縮小せず、SessionEnd・Stop全5 handler・UserPromptSubmit全3 handler・dispatcher/combinedのleaf actionをN/N展開したか。
23. rollback先は実在artifact/scriptとhash/mode/ownerに束縛され、dry-runとapply後再検証があるか。
24. 検証窓のpane birthはmutation journalでowner/causeを確定したか。時刻相関だけでcmd起因0としていないか。
25. 旧系が優先された導入理由と事故回避の因果辺を、変更unitごとに追ったか。全tuple純便益が未証明ならNO-CHANGEにしたか。

## §9 履歴・因果・検索索引

### §9.1 Review history

| round | reviewer | verdict | 主指摘・反映 |
|---:|---|---|---|
| 0 | 軍師 | LGTM | R10 wave、V03 scope、R02→V03、R12→V04 |
| 1 | 将軍 | REQUEST_CHANGES | Gate 0、WAL/reconciler、idempotency、shadow、fault、性能を追加 |
| 2 | 軍師 | REQUEST_CHANGES | 9反証をGate 0 contract/manifestへ9/9反映 |
| 3-8 | 軍師 | REQUEST_CHANGES | receipt hash、caller全数、phase、Gist自己参照を順次是正 |
| 9 | 軍師 | LGTM | Gate 0A contract確定 `9e5f8a382` |
| Wave0 RC1 | 軍師 | LGTM | 完全再実行command、正時刻、16/16 byte一致 `ce54074be` |
| Gate0B AC1 | 軍師 | LGTM | receipt 17/17、SHA/未来/未分類0 `f37a4365a` |
| Gate0B map | 軍師/家老 | ACCEPTED | OPEN 13/13、未割当/owner重複/循環/serialization欠落すべて0 `2e1090bb7` |
| Foundation RC1-5 | 軍師/家老 | REQUEST_CHANGES→LGTM | 空terminal、path traversal、symlink escape、ack-loss、hard-crash、test安全性を順次是正 |
| Foundation final | 家老 | ACCEPTED | 17/17 PASS、SKIP 0、hard-crash retry rc 10/effect 1 `4c89d38ca` |
| Wave1A R01 | 飛猿 | IN_PROGRESS | 敵対contract `6f4e4b77b`。post-commit 10反復もlost/duplicate/parse各0、task-scope 10 test実行中 |
| Multi-runtime RC1 | 軍師 | REQUEST_CHANGES | Gist/local一致のみPASS。active-only Claude欠落、3 matrix未分離、resolver/manifest欠落、type/binary矛盾2、Codex Stop代替receipt欠落、OS runner証跡0、valid constraint欠落の6 finding |
| Multi-runtime RC1 response | 家老 | UPDATED v3.3 | support/configured/active分離、artifact/resolver、event代替receipt、OS support境界、valid constraint、AC16-20へ反映 |
| 殿訂正 | 殿/家老 | UPDATED v3.3 | 主編成=Claudeを明記。active Codexを主編成へ誤昇格しない。Claude primary 6-event非退行、配備変更0、AC21-22を追加 |
| 因果保存訂正 | 殿/家老 | UPDATED v3.4 | 旧Claude主系の成立因果、native hook優先理由、CLI adapterが必要になった事故、全tuple純便益未証明時NO-CHANGEを追加 |
| Multi-runtime RC2 | 軍師 | REQUEST_CHANGES | 前回6 findingは6/6解消。新規3件: Claude実manifestの6 cell縮小、rollback pointer不存在、post-commit pane birth 1/9のowner/cause未証明 |
| Multi-runtime RC2 response | 家老 | UPDATED v3.4 | 6 event type/12 top handler/dispatcher leaf N全数、baseline hash+restore script、mutation journal、AC21-25へ反映 |

### §9.2 因果リンク

`[[Claude主編成の長期運用]] -> [[Claude_native_hook優先]] -> [[multi_cli_hook_gap]] -> [[codex_stop_block_loop]] -> [[cli_capability_adapter_required]] -> [[durable_state_remediation]] -> [[cmd_4200]]`

`[[旧系の成立因果]] -> [[全runtime純便益検証]] -> [[未証明はNO_CHANGE]] -> [[Claude悪化はrollback]]`

### §9.3 grep索引

| 探すもの | pattern |
|---|---|
| 現在地 | `§-2` |
| As-Is | `§1` |
| To-Be | `§3` |
| 5W1H | `5W1H` |
| finding | `R01` / `V01` |
| fault | `§4` |
| Wave | `§5` |
| AC | `§6` |
| review | `§8` / `§9.1` |
