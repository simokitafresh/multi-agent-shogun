# cmd_training_L4_codd_c3_kagemaru: cmd_delegate.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/cmd_delegate.sh`
pipeline: spec -> elicit/lexicon -> validate -> measure

## 1. Spec

### Purpose

`scripts/cmd_delegate.sh` は、将軍が作成した `queue/shogun_to_karo.yaml` のcmdを家老へ委任する原子的な境界スクリプトである。cmdが `pending` であることを確認し、`cmd_save.sh` gateを通した後、`status=delegated` と `delegated_at` を先に永続化してから `inbox_write.sh karo ... cmd_new shogun` を実行する。これにより、`inbox_write.sh` 側の `cmd_new` gateが「pending直送」をBLOCKしつつ、正規委任だけ通る。

### Scope

- CLI引数 `<cmd_id> "<message>"` を受け取り、不足時はusageで終了する。
- `queue/shogun_to_karo.yaml` の対象cmdが存在し、`status=pending` であることを検証する。
- `delegated_at` が既にある場合は `ALREADY_DELEGATED` として冪等に成功終了する。
- 初回委任では `scripts/cmd_save.sh <cmd_id>` を実行し、exit 0以外を委任前に止める。
- 他の `pending + delegated_at` cmdをWARNし、家老未配備の兆候を可視化する。
- 家老inboxに同じcmd_idの `cmd_new` が既にある場合は重複送信をBLOCKする。
- dashboard掲載済みはsecondary dataとしてWARNのみ、archive済みcmdはBLOCKする。
- `status=delegated` と `delegated_at` を `yaml_field_set` で書いた後、`inbox_write.sh` で家老に通知する。

### Non-scope

- cmd品質検査の詳細は `scripts/cmd_save.sh` の責務。
- 家老による忍者配備とdashboard更新は委任後の別責務。
- `inbox_write.sh` の配送・nudge・cmd_new guardは別スクリプトの責務。
- 本taskでは実装変更を行わず、CoDD L4修行としてspec/要件穴/品質評価のみ記録する。

### Current Evidence

| Evidence | Result |
| --- | --- |
| `bash -n scripts/cmd_delegate.sh` | PASS |
| `/home/simokitafresh/.codd-venv/bin/codd generate --path . --wave 1` | PASS: wave_config generated from 11 requirements; 0 generated; `docs/governance/adr_batch_yaml_io.md` and `docs/test/acceptance_criteria.md` skipped |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals。lexicon coverage未設定 |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path .` | FAIL: installed `shogun_core` lexicon manifest lacks required `prompt_extension` |
| Existing CoDD docs | `cmd_delegate.sh` 専用nodeは未検出。近接文書は `cmd_save` requirements/design/brownfield |

## 2. Elicit / Lexicon Findings

`codd elicit` はlexicon manifest不備で失敗したため、コード読解と近接CoDD文書からCoDD elicit相当の穴を手動で列挙する。

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | `cmd_delegate.sh` 専用のCoDD requirement/design nodeがない | `find codd ... cmd_delegate` は未検出 | 委任境界のDAG追跡ができず、cmd_save/inbox_writeの間にある契約が暗黙知になる |
| GAP-2 | headerのBehaviorが実装順と一部ずれている | headerは「inbox_write成功後delegated_at追加」と書くが、実装はstatus/delegated_atを先に書く | 正規委任がinbox_write cmd_new gateを通るための重要順序が誤読される |
| GAP-3 | `status=delegated` 書込み後に `inbox_write` 失敗した場合の復旧契約が弱い | lines 238-252: status維持、手動inbox_writeで再送可 | 家老未通知のままdelegated状態が残るため、監視・復旧SLOが必要 |
| GAP-4 | `pending + delegated_at` という矛盾状態をWARNするが、なぜ発生するか要求化されていない | `find_undeployed_pending_cmds` | archive/STK同期や過去事故検出の意味がコード読解依存 |
| GAP-5 | `karo inbox` 重複検出はYAML近似awkで、read/archive済みやcontent形式の境界が未仕様 | `inbox_has_cmd_new_for_cmd` | 再委任したい場合の正規復旧手順が不明確 |
| GAP-6 | dashboardはsecondary dataとしてWARN onlyだが、要求化されていない | lines 222-225 | dashboardと一次queueの優先順位が将来変更で崩れる可能性 |
| GAP-7 | `cmd_save.sh` exit code 1だけをGATE未通過として特別扱いする契約が未文書化 | lines 186-201 | cmd_save側のexit code変更で委任判断が壊れる |
| GAP-8 | `yaml_field_set` 経由でstatus/delegated_atを書くが、2 field更新の原子性境界が未記録 | status成功後delegated_at失敗で中途半端になりうる | shared queueの不整合復旧手順が必要 |
| GAP-9 | archive済み検出が filename glob依存 | `queue/archive/cmds/${CMD_ID}_*` | archive命名変更時に再委任BLOCKが抜ける |
| GAP-10 | CoDD graph上のsource coverageが0 | `measure` tracked_files/source_files=0 | scripts/cmd_delegate.sh自体の実装coverageが数値上見えていない |

Recommended lexicon axes for this script:

- `delegate_status_before_notify`: `inbox_write cmd_new` のguardを通すため、通知前に `status=delegated` を永続化する順序を明示する。
- `delegate_recovery_after_notify_fail`: `status=delegated` 後の通知失敗時に誰がどう復旧するかを定義する。
- `cmd_gate_exit_contract`: `cmd_save.sh` exit codeと委任可否の対応を固定する。
- `primary_queue_over_dashboard`: dashboardはsecondary data、`shogun_to_karo.yaml` とinboxを一次データとする。
- `idempotent_delegate`: `delegated_at` 既存時は副作用を増やさず成功終了する。
- `ops_yaml_two_field_atomicity`: shared queueで複数field更新するときの中間状態と復旧方法を設計する。

## 3. Validate / Measure Score

### Generate Result

追完F2で `codd generate --path . --wave 1` を実行した。結果は `wave_config generated from 11 requirement(s)`、`Wave 1: 0 generated, 2 skipped`。既存の `docs/governance/adr_batch_yaml_io.md` と `docs/test/acceptance_criteria.md` がskipされ、`cmd_delegate.sh` 固有の設計書は生成されなかった。原因は §2 GAP-1 の通り、`cmd_delegate.sh` 専用 requirement/design node が未登録であること。

### CoDD Tool Score

| Metric | Score |
| --- | ---: |
| CoDD health_score | 95/100 |
| validation errors | 0 |
| validation warnings | 0 |
| DAG verify | PASS with skipped `depends_on_consistency` warning |
| graph nodes | 16 |
| graph edges | 12 |
| orphan nodes | 4 |
| lexicon coverage axes | 0 |

### Design Quality Score for `cmd_delegate.sh`

Overall: 7/10.

Rationale:

- +2: `cmd_save.sh` gateを委任前に強制し、gate未通過cmdの家老投入を防ぐ。
- +2: `status=delegated` を先に書くことで `inbox_write.sh` のcmd_new guardと整合する。
- +1: `delegated_at` 既存時の冪等終了、archive済みBLOCK、karo inbox重複BLOCKがある。
- +1: dashboardをsecondary dataとしてWARN onlyに留め、一次queueを優先している。
- +1: shared YAML更新に `yaml_field_set` を使い、直接dumpを避けている。
- -1: 専用CoDD文書がなく、委任境界の契約がDAGに載っていない。
- -1: headerが「inbox_write成功後delegated_at」と誤読される順序を書いており、現実の重要順序とズレる。
- -1: status更新後のinbox_write失敗、2 field更新途中失敗の復旧契約が弱い。

## 4. Improvement Candidates

1. `codd/requirements/cmd_delegate_requirements.md` と `codd/design/cmd_delegate_design.md` を追加し、cmd_save -> status/delegated_at -> inbox_write の境界契約をDAG化する。
2. header Behaviorを現実の順序へ修正する。「status=delegated + delegated_atを先に書く」はcmd_new guard通過に必須の契約として明示する。
3. `inbox_write` 失敗後の復旧手順を設計書化する。delegated状態のまま手動再送するのか、自動retry/rollbackするのかを決める。
4. `status` と `delegated_at` の2 field更新をbatch化するか、中間状態検出gateを追加する。
5. `cmd_save.sh` exit code contractをrequirementsに明記し、exit code変更時にcmd_delegate側へ伝播するようDAG edgeを張る。
6. `codd.yaml` のscan/source coverage設定を見直し、`scripts/cmd_delegate.sh` がtracked sourceとしてmeasureに反映されるようにする。

## 5. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `cmd_delegate.sh` を読み、spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
