# 隠れたインフラバグ・Gate/Hook品質 — As-Is / To-Be 5W1H修正設計書

| 項目 | 値 |
|---|---|
| 作成 | 2026-07-30 家老 |
| 再構築 | 2026-07-31 家老 |
| 進捗更新 | 2026-08-01 13:50 将軍 (殿下知「ドキュメントも覚醒して再構築」→本文を現在地+有効契約のみへ再構築) |
| 版 | v5.0 = v4.0の751行を本文538行(現在地+契約+残Wave)へ再構築。歴史・監査経緯259行は `hidden-infrastructure-design-history-20260801.md` へ分離(削除0行・旧全§到達可能・§-2.H参照)。リンク先なき圧縮禁止を遵守 |
| 最終レビュー | v3.9将軍APPROVE(実測spot check: manifest331/py788/sh106/bats421行 全一致・fail-close境界維持確認)。v3.8はRC2 LGTM。旧正本=`docs/research/shogun-adversarial-review-hidden-infra-design-20260801.md` |
| 対象 | `multi-agent-shogun` 制御面、gate、hook、配備、完了、CI、知識還流。Codex専用設計ではなく、全configured CLI/model/effort/service-tier/OS-filesystem tupleを対象とする |
| code baseline | `55b3df6d4d937c7683ef1ca9a83393760d593e47` |
| canonical manifest | `docs/research/hidden-infrastructure-gate-hook-canonical-manifest-20260731.yaml` |
| Wave 0 receipt | `docs/research/hidden-infrastructure-gate-hook-wave0-receipts-20260731.yaml` |
| Gist | `c18ce89c63d6d7beef7a0fd252fe8d9f` |
| 親cmd | `cmd_4200`(Gate0A〜Wave1A、完遂済み)。**Wave 1B以降=cmdなし家老自走**(殿裁定2026-08-01 09:14: ホットスクリプト方式。本設計書+canonical manifestが唯一のmandate。台帳駆動campaign laneで直進し、進捗はmanifest phase遷移+掲示板GATEで将軍が検分) |

## §-2 現在地（最初に読め）

### §-2.P 全体進捗ダッシュボード (2026-08-01 11:40 将軍更新)

```text
全体進捗(工数加重):  █████████████░░░░░░░░░░░░  ≈50%
経過: 2.5日(07-30着手)  /  残り見込み: 6〜7日  /  完了見込み: 2026-08-07〜08
  楽観(独立unit並列化が効く場合): 08-06
  悲観(R03級のRC反復が2件以上再発): 08-10
```

対象は17 canonical findings(probe段でSUPERSEDED 4件除外→実装対象13 unit + Final checkpoint)。完了度はunit終端(terminal receipt)基準、部分値は先行実装分。

| # | 段階 | 対象unit | 状態 | 完了度 | 実績/見込み |
|---|---|---|---|---:|---|
| 1 | Gate 0A contract | 17 findings契約化 | ✅ 終端 | 100% | 実績 07-31 |
| 2 | Wave 0 runtime probe | 17/17実行 | ✅ 終端 | 100% | 実績 07-31 |
| 3 | Gate 0B closure | 13 OPEN→実装unit写像 | ✅ 終端 | 100% | 実績 07-31 |
| 4 | Foundation (durable_state) | WAL/fence/receipt基盤 | ✅ 終端 | 100% | 実績 07-31 |
| 5 | Wave 1A identity | R01, R06 | ✅ R01終端・R06 review path済(残=caller横展開) | 90% | 実績 07-31〜08-01 |
| 6 | **Wave 1B ownership** | R03✅, **R04, R05** (+V03) | 🔄 **現在地**。R03=障壁表方式でRC反復5回の末**GATE CLEAR終端(08-01 11:31)**。R04/R05が次unit | 45% | 残り1日 |
| 7 | Wave 2A terminal receipt | R07, R08 | ⏳ archive再承認レーンで大半先行実装済み。残=汎用WAL/reconciler適用 | 40% | 残り0.5日 |
| 8 | Wave 2B safe delivery | V02, V04 | ⏳ V04部分先行(PARTIALLY_SUPERSEDED) | 25% | 1日 |
| 9 | Wave 3 CI/test SSOT | R09, R10, R13 | ⏳ 未着手。**最大工数**(CI未所属97 testの再採番+inventory生成) | 0% | 2〜3日 |
| 10 | Wave 4A hook ownership | R14 | ⏳ 未着手 | 0% | 0.5日 |
| 11 | Wave 4B knowledge provenance | R11, R15, V01 | ⏳ R15はinsight resolve運用が部分先行 | 10% | 1日 |
| 12 | Final checkpoint | 固定SHAで全receipt+全量test照合 | ⏳ | 0% | 0.5日 |

**読み方**: ゴール=13 unit全終端+Final checkpoint 1回。前半4段(契約・probe・写像・基盤)は工数の約1/3を占め完了済み。ボトルネック候補は現在進行のR03(fence/authority domain設計、軍師FAIL 2回で再設計中)とWave 3(物量最大)。見込みの根拠: Wave 1A実績=1日/2unit、archive先行レーン実績=1日、R03実績=RC反復込み1日/unit — これを残unit数に外挿し、§5.0の独立unit並列化(直列はserialization key共有時のみ)で楽観側へ寄せる。

**進捗の一次確認先**: canonical manifest `current_phase`/`phase_state`(現在=`WAVE_1A_IDENTITY:ACCEPTED`→`next=WAVE_1B_OWNERSHIP`) + findings別 `remediation_status`(SUPERSEDED=終端済み、ACTIVE=未了)。本表は将軍が掲示板GATE報告とmanifestから集計した二次情報であり、乖離時はmanifestが正。

結論: **Gate 0B、durable-state foundation、Wave 1A R01は受入済み。親AC基準3/3完了。** archive再承認レーンでWave 1A/2A/3の一部が先行実装されたため、canonical manifestのreceiptを照合して残作業だけを後続Waveで実装する。

| 段階 | 状態 | 一次証跡 | 数値 |
|---|---|---|---:|
| Gate 0A contract | `ACCEPTED` | `9e5f8a382` | canonical 17/17、caller 44/44、Gist/local SHA一致 |
| Wave 0 runtime probe | `ACCEPTED` | `ce54074be` | executed 17/17、OPEN 13、SUPERSEDED 4、未実行0 |
| Gate 0B evidence prerequisite | `ACCEPTED` | `f37a4365a` | SHA不一致0、未来時刻0、未分類0 |
| Gate 0B wave map | `ACCEPTED` | `2e1090bb7`、foundation map | OPEN 13/13、未割当0、owner重複0、循環0、serialization key欠落0 |
| AC2 durable-state foundation | `ACCEPTED` | `4c89d38ca` | focused 17/17 PASS、SKIP 0、hard-crash時 effect 2→1 |
| AC3 Wave 1A R01 | `ACCEPTED` | `6f4e4b77b`、`queue/archive/reports/tobisaru_report_cmd_4200_20260731.yaml` | post-commit 10反復 submitted 160/160、marked 80/80、lost/duplicate/parse 0。task selector 287/287、SKIP 0、軍師LGTM・家老ACCEPT |
| 親cmd completion gate | `COMPLETED` | `queue/gates/cmd_4200/completion_checkpoint.json` | Step群8/8、terminal review 6/6、notify marker 6/6、`archive.done` 1/1、同一completion generationのntfy receipt 1件 |

現manifest: `current_phase=WAVE_1A_IDENTITY`、`phase_state=ACCEPTED`、`next_phase=WAVE_1B_OWNERSHIP`。後続はfoundation mapの依存順・serialization keyに従い直列進行し、先行receiptと重なる実装を再作成しない。


### §-2.H 経緯アーカイブ
進捗更新・殿下問監査(旧§-2.0〜§-2.3)・As-Is監査(旧§1)・Gap分析(旧§2)・軍師9反証(旧§7.1)・review history(旧§9.1)は `docs/research/hidden-infrastructure-design-history-20260801.md` へ分離した。経緯を追体験する時だけ読め。


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


### §0.0 旧系の成立因果 (→ アーカイブ)
旧Claude主系がなぜ成立していたか・保存を優先する因果は history §B を読め。結論だけ残す: **全tuple純便益が未証明の共通層はNO-CHANGE。Claude悪化1件でrollback。**


### §0.1 実行基盤の大前提 — multi CLI / model / effort / OS

**本書はCodex単体の設計書ではない。主編成はClaudeであり、Codexは補完・検証・一時配置のCLIである。** 正本はCLI固有hook設定ではなく、共通event・durable state・gate契約である。Claude CodeとCodexは能力差をadapterで吸収し、model/effort/service tierは実行条件、OS/filesystemは永続化・監視・性能条件として明示的に検証する。現在のactive paneがCodex寄りでも、それを主編成変更・Claude support縮小・Claude経路撤去の根拠にしない。

| 軸 | 現在の実体・正本 | 設計契約 |
|---|---|---|
| CLI | event意味論=`config/cli_events.yaml`、能力profile=`config/cli_profiles.yaml`、配置=`config/settings.yaml` | CLI固有hookをSSOTにしない。共通eventを各CLIのcapability adapterへ写像し、未対応eventはdaemon/gate/scriptで等価保証する |
| model | Claude Opus/Sonnet/Fable系（現configured例=`claude-fable-5-low`）、GPT系を含むconfigured `model_name` | model名で安全性を分岐しない。全configured model tupleで同一binary invariantを満たす |
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

As-Isの2026-08-01 00:10将軍実測では、単一`cli_profiles.yaml`内混在は2 rowだが、本書resolver precedenceを全agentへ適用した**resolved tuple不整合は3 agent**（saizo/tobisaru/gunshi）であった。gunshiは`settings type=codex`+`launch_cmd`欠落にprofileのClaude binaryがfallbackするcross-file矛盾である。generatorは単一file内の固定`2`をfixture正解にせず、resolved全agent N/Nを走査する。未修正期間は観測NをそのままBLOCK receiptへ記録し、終端は`type_binary_mismatch=0/N`だけを要求する。

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

baseline artifactは`queue/gates/cmd_4200/claude_primary_baseline/` に固定する。`source_commit` / `git_blob` / file SHA-256 / `git_mode` / `fs_mode_observed` / `fs_capability` / mount identity / handler graph / child SHA-256 / fixture receiptを持つ。現行起点の`.claude/settings.json` blobは`be93a9ff5706a7d79eebedfeb52a668310bc1e8b`、working content SHA-256は`4b1945c8477afdba71d6fe7fdf7a10b8a49a0e6f43e3a5c6476a1b0bae79ca52`である。最終実装checkpointでは開始時HEADを改めて固定し、古い設計書記載値を流用しない。

modeは単一値に正規化しない。現WSL2 DrvFs実測は`git_mode=100644`、`fs_mode_observed=0777`、`fstype=9p`、mount option=`aname=drvfs`であり、両者は矛盾ではない。restore時はGit tree/indexと`git_mode`を比較し、filesystem側は`fs_capability` contractに応じてexec-bit保存可否・`bash <script>`起動可否・mount identityを別検証する。`stat` modeとGit modeの直接一致は求めない。

| invariant | binary check |
|---|---|
| event reachability | matcher fixtureとisolated interactive probeが6/6到達 |
| payload/decision | additional context、deny/warn、Stop decisionのschema差分0 |
| lifecycle | `/clear`、idle flag、inbox nudge、report handoff、cmd completionがbefore/after同結果 |
| latency | event別p95が既定budget以内。Codex都合のtimeout増加をClaudeへ波及させない |
| ownership | Claude hook ownerは各action 1。Codex daemon追加で二重owner 0 |
| rollback | `scripts/runtime_compatibility_restore.sh --receipt <baseline.json> --dry-run`でpath/git_mode/fs_capability/mount/SHA/ownerを照合し、`--apply`はcanary所有pathのみatomic restoreする。他者dirty path、hash不一致、scope外はBLOCK |

Claude primaryのexpanded action N/N receiptがないcommitは、Codex側が全PASSでもrelease不可とする。rollbackは「adapter pointerを戻す」という散文ではなく、実在script、baseline artifact、dry-run、apply後再fixtureの4点をそろえる。

### §0.5 編成mutation journal

`queue/gates/cmd_4200/runtime_mutations.jsonl`に、検証窓内の全settings/profile/config writeとpane spawn/respawn/switchを`event_id` / `timestamp` / `owner` / `cause` / `cmd_id` / changed paths+before-after SHA-256 / before-after pane PID+starttime / CLI / model / effort / service tierで記録する。

窓開始時に`config/settings.yaml`、`config/cli_profiles.yaml`、`config/cli_events.yaml`、`.claude/settings.json`、`.codex/hooks.json`のSHA-256+git blob+mtimeと、全paneのPID/starttime/CLI/model/effort/tierを`runtime_state_before.json`へ固定する。窓終了時の`runtime_state_after.json`と比較し、全observed deltaにjournal eventがexactly one対応することを要求する。

- 全体respawn数0を要求しない。idle recovery等の正常別owner動作をcmd_4200に誤帰属させないためである。
- cmd_4200起因のsettings変更、pane respawn、CLI/model/effort switchはそれぞれ0を要求する。owner/cause不明は0と数えずBLOCKする。
- `observed_delta_count == journal_event_count == attributed_event_count`を強制する。snapshot差分に対するjournal欠落、journalに対するsnapshot差分欠落、owner/cause不明はすべて`UNKNOWN_MUTATION`としrelease BLOCK。0とみなさない。
- journalなしのmtime・pane birth時刻のみで「cmd起因0」と判定しない。今回の再レビュでcommit後pane birth 1/9を観測したがowner receiptがないため、AC22は未判定とする。


## §1 As-Is / §2 Gap (→ アーカイブ)
現状5W1H・監査方法・canonical findings 17件の全表は history §C、4共通根因・失敗連鎖は history §D を読め。結論だけ残す: **17 findings(SUPERSEDED 4を除くOPEN 13)が実装対象。共通根因=identity曖昧・受付=完了の混同・後置き検査依存・単一runtime前提。**


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
  → Wave1A identity [R01 ACCEPTED / R06 review-path先行実装済(§-2.0)。残=typed exact helper横展開]
  → Wave1B ownership
  → Wave2A terminal receipt
  → Wave2B safe delivery
  → Wave3 CI/test SSOT
  → Wave4A hook ownership
  → Wave4B knowledge provenance
  → Final checkpoint
```

同一file・同一side effect・同一`serialization_key`を共有するunitだけ直列化する。独立unitはWaveをまたいでも並列実験可。途中unitは依存不変量のfocused PASSを次unitの開始条件とし、文書・共有ledger・全体receiptの終端待ちは課さない。全量のterminal receipt照合はFinal checkpointへ集約する。

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

### §5.3 Wave 1A — identity（R01受入済み・R06 review path先行実装済み）

- `lock_path.sh`を唯一のlock identity生成器にしR01を閉じる。
- typed exact-match helperでR06を閉じる。
- immutable rc receipt primitiveを作る。`run_tests.sh` caller置換はWave 3で行う。

実績: R01はcommit `6f4e4b77b`、報告 `queue/archive/reports/tobisaru_report_cmd_4200_20260731.yaml` で終端した。初回およびcommit後の敵対計測は各10反復でsubmitted 160/160、marked 80/80、lost update 0、duplicate 0、parse error 0。task selector 287/287、SKIP 0、軍師LGTM・家老ACCEPTをterminal manifestで確認した。R06 review pathはarchive再承認レーンで先行実装済み。残るR06 callerはmanifest receipt照合後にのみ実装する。

### §5.4 Wave 1B — ownership（R03-R05、採用時V03）

- `auto_deploy_next.sh`のmutationをowner transactionへ置換する。
- commit条件はmutation rc全0、target receipt一致、source tombstone、active count=1、terminal WAL receipt一致。
- crash recovery ownerはstartup reconciler。終了processへ自動復元を期待しない。

### §5.5 Wave 2A — terminal receipt（R07-R08）

- review marker/completion checkpointをterminal receipt後だけ公開する。
- async tailをdurable job化し、supervisorがterminalまで再駆動する。
- dashboard/archive/品質記録/通知を同一idempotency keyで収束させる。

先行差分: archive再承認レーンはcanonical report identity、二者lineage、atomic terminal review manifest、completion checkpointを実装済み。cmd_4200実走でterminal review 6/6、Step群8/8、notify marker 6/6、archive 1/1、ntfy delivery receipt 1 generation/1件を確認した。残作業は全completion jobへの汎用WAL/reconciler適用であり、この先行範囲を二重実装しない。

### §5.6 Wave 2B — safe delivery（V02/V04）

- pane送信を中央関数一択にし、送信直前のconfirmation prompt再検出を必須化する。
- watcher event ID→nudge→unreadのcorrelationを永続化し、重複と遅延を別計数する。

### §5.7 Wave 3 — CI/test SSOT（R09/R10/R13）

- `test_necessity`付き永続contractだけからrunner別inventoryを生成する。
- canonical parserでCI所属N/N、未所属0。監査時80/177・未所属97は再採番して置換する。
- leader/joiner/issuerをimmutable rc receiptへ移行する。
- SKIPはFAIL。cache keyへworktree source/runner/fixture/env identityを含める。

先行差分: `run_tests.sh task` のPython dispatchとterminal receipt集計はcommit `6c3392d74`、`d9c02f170`で先行実装済み（対象直接21/21、contract 55/55、SKIP 0）。残作業はcanonical CI membership N/N、全runnerのimmutable receipt、worktree identity cache keyであり、既存dispatch/receipt集計を再実装しない。

### §5.8 Wave 4A — multi-CLI hook ownership（R14）

- `config/cli_events.yaml`の6 eventを唯一の意味論ownerとし、Claude Code / Codex adapterは能力写像だけを持つ。
- 同一event内の順序依存処理はCLIごとに単一adapterへ合成する。CLI固有hook設定の二重ownerを禁止する。
- **Claude現行multi-handler構成（Stop 5 / UserPromptSubmit 3 / expanded leaf N）は合成対象外**とする。既にreachable owner 1/actionを満たすClaude native chainはNO-CHANGEが優先する。単一adapter合成はhook欠落CLIの代替ownerまたは二重ownerが実測されたCLI固有経路に限定し、Claudeへの適用は全support tuple純便益が証明された別裁定まで禁止する。
- manifest generatorで、support CLI×6 eventの全cellについてmatcher到達性、実体存在、event coverage、代替daemon/gate coverageを強制する。
- Codexは意図的BLOCKをexit 2、hook errorを別分類し、exit 1によるCLI停止を0件にする。
- Claude CodeはPreToolUse/PostToolUse/Stopのpayload・exit・permissionDecision意味論をfixtureとinteractive probeで固定する。
- Stopは共通実装を押し付けない。Claudeのturn停止とCodexの再生成挙動を別adapterで扱い、再実行loop・silent allow・stale flag・retry capを各CLIで測る。
- Codex Stopを0 hookのまま維持する期間も、`mark_idle`、`log_terminal_response`、`stop_check_inbox`各actionにdaemon/gate/script ownerを1つ割当て、`event_id/action_id/owner/mode/test/receipt`を記録する。代替receipt欠落1件でもrelease BLOCK。

### §5.8.1 Runtime compatibility実装順序

1. `runtime_support_matrix.yaml` schemaとvalid constraintを定義し、Claude primary row必須をschemaで強制する。
2. resolver/generatorを実装する。fixtureは固定件数を正解にせず、resolved全agentのN/N走査で観測されたmismatch全件（As-Is実測=resolved 3 agent: saizo/tobisaru/gunshi）をBLOCK receiptへ記録し、正本修正後の終端条件は`type_binary_mismatch=0/N`のみとする（§0.2と同一契約）。
3. mismatchを正本で0へ直し、support/configured/active 3 manifestを生成する。
4. `cli_events.yaml` 6 event×support CLIのcoverage receiptを生成する。先にClaude primary 6/6のbefore/after parityを確定し、その後Codex hookなしcellの代替owner N/Nを証明する。
5. WSL2 DrvFS/native ext4、native Linux、Windows-nativeの各support rowへrunnerを割当てる。runnerなしrowは`PLANNED`のままrelease集合へ入れない。
6. final checkpointでmanifestと全receiptをfixed SHAへ束縛する。

### §5.9 Wave 4B — knowledge provenance（R11/R15/V01）

- signed curated manualだけを即時昇格する。
- pendingを実装待ち/裁定待ち/resolved/discarded_noiseへ型付けする。
- resolvedと三層貫通はartifact receiptで完了判定する。

### §5.10 Final checkpoint

- 途中laneの正規操作はevent append 1回+focused binary check 1回を上限とし、共有treeの他者差分・manifest時刻・公開Gist同期を途中成果のFAIL条件にしない。
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
| 22 | before/after config hash+pane snapshotのobserved deltaとowner/cause付きmutation journalがN/N exact対応。cmd_4200起因のsettings変更0、pane respawn0、CLI/model/effort切替0、`UNKNOWN_MUTATION=0` |
| 23 | 各変更unitがold design reason、根拠commit/path/line/blob、観測期間、成功/失敗生値、cut edge、影響、保存方法をN/N記録し、不明0 |
| 24 | support全valid tupleで安全性非退行、Claude primary使い勝手差分0、既定budget内、追加手順税0。1件でも未証明/悪化ならNO-CHANGE CLOSE |
| 25 | canary採用時は旧Claude pathのhash/git_mode/fs_capability/mount/owner付き保存、実在restore scriptのdry-run PASS、apply後expanded action N/N再現を同一receiptで証明 |

## §7 Decision Ledger


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
26. DrvFsの`git_mode=100644` / `fs_mode_observed=0777`を矛盾と誤判定せず、Git意味論とfilesystem capability/mountを分離したか。
27. settings/profile/hook差分とpane差分をbefore/after snapshotから全数検出し、journalとN/N対応したか。未journal差分を0と数えていないか。
28. 因果証跡は現行path/節参照ではなく、fixed commit/path/line/blob/観測期間/生値へ束縛されているか。
29. 同じ安全性をより少ないstate/field/path/手順で実現できないか。追加変更なら旧経路の純減が同一diffにあるか。
30. 可逆な途中tryへ最終checkpointのreport freshness・全量receipt・共有tree cleanを誤適用していないか。
31. Wave番号だけを理由に独立unitを直列化していないか。実際のfile/side effect/serialization key競合を示せるか。


## §9 履歴・因果・検索索引


### §9.1 Review history (→ アーカイブ)
全review rounds(Gate0A〜Claude Fable RC1)の詳細表は history §F を読め。


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
