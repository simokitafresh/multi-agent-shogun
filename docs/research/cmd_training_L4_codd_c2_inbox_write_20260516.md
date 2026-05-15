# cmd_training_L4_codd_c2_kagemaru: inbox_write.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/inbox_write.sh`
pipeline: spec -> elicit/lexicon -> validate -> measure

## 1. Spec

### Purpose

`scripts/inbox_write.sh` は、将軍・家老・軍師・忍者間のinboxメッセージを `queue/inbox/{agent}.yaml` に排他制御付きで永続化し、task配備、報告受領、レビュー結果、CLI nudgeなどの下流副作用を連鎖させる通信境界である。YAML永続化が正本で、tmux nudgeやreview gate起動は派生動作である。

### Scope

- CLI引数 `<target_agent> <content> [type] [from] [action]` を受け取り、不足・cmd_id誤指定・未知targetを拒否する。
- ninjaからshogunへの直接送信、ninja_monitorの送信先など、指揮系統の送信制約を検査する。
- message id/timestampを生成し、content/from/type/read/actionをYAML blockとして安全にescapeする。
- `queue/inbox/{target}.yaml` をflockで保護し、既存inboxへ追記する。50件超過時は未読と直近既読を残す。
- `task_assigned` では同一parent_cmdのactive重複配備をBLOCKし、関連教訓の安全網注入を試みる。
- `cmd_new` では `queue/shogun_to_karo.yaml` のstatusを確認し、gate未通過cmdの直送をBLOCKする。
- `report_received` / `task_done` では報告YAML format gate、未commit gate、gunshi review通知、task done遷移を連鎖する。
- `review_result` / `report_review_result` / `report_review` では、軍師レビュー補足転送やgate flag作成を行う。
- Codex task配備ではnudge deliveryを検証し、未読が残る場合はretryする。

### Non-scope

- inboxの既読化は `scripts/inbox_mark_read.sh` の責務。
- watcherによる常時監視と実際のCLI送信は `scripts/inbox_watcher.sh` の責務。
- report YAMLの内容作成は忍者と `report_field_set.sh` の責務。
- 本taskでは実装変更を行わず、CoDD L4修行としてspec/要件穴/品質評価のみ記録する。

### Current Evidence

| Evidence | Result |
| --- | --- |
| `bash -n scripts/inbox_write.sh` | PASS |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals。lexicon coverage未設定 |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path .` | FAIL: installed `shogun_core` lexicon manifest lacks required `prompt_extension` |
| Existing CoDD docs | `codd/requirements/inbox_write_requirements.md`, `codd/design/inbox_write_design.md`, `codd/brownfield/inbox_write_brownfield.md` |

## 2. Elicit / Lexicon Findings

`codd elicit` はlexicon manifest不備で実行不能だったため、既存brownfield findings 10件と現コード読解を統合してCoDD elicit相当の穴を列挙する。

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | 既存requirement/designが抽象的で、type別副作用契約を十分に分解していない | FR-1〜FR-8は高レベル。コードはtask/report/review/cmd_newで大きく分岐 | 変更時に特定typeだけ壊れてもDAG上で検出しにくい |
| GAP-2 | message schema enumがコードコメントと分岐に散在 | header Supported types、report gate、review gate、watcher特殊typeが分散 | typo typeや新type追加時の下流対応漏れが起きやすい |
| GAP-3 | inbox retention policyがrequirements未記載 | 50件超過で未読全件+直近既読30件へ圧縮 | 監査ログ保持要件と衝突する可能性がある |
| GAP-4 | report_receivedの副作用が多く、順序契約が未設計書化 | autofix -> format gate -> gunshi monitor -> git gate -> message persist -> notify -> task done | 途中FAIL時にどこまで副作用済みか追跡しづらい |
| GAP-5 | lock/atomicityの実装方式が複数あり、要求側に区別がない | append fast path、collect/rewrite path、mv retry、task YAML separate lock | 共有YAMLの安全性レビューが実装読解依存になる |
| GAP-6 | delivery verificationはCodex task_assigned限定だが、理由とSLOが未記録 | `maybe_verify_codex_delivery` はCodex + task_assignedのみ | Claudeやreview通知の配送保証との差が暗黙知になる |
| GAP-7 | duplicate deployment gateはactive status集合固定だが要求化されていない | active_statuses = assigned/acknowledged/in_progress | blocked/failed/doneなど状態追加時の再検討漏れリスク |
| GAP-8 | `report_path` と `report_filename` のfallback探索が設計書化されていない | report format gateとauto-doneで別々のfallback | archive移動後やテンプレート欠落時の挙動差が出やすい |
| GAP-9 | `yaml.dump`禁止との整合性は実装で満たすが、designに明記が薄い | `inbox_yaml_emit_field` で手書きemit、PyYAMLはtask scan中心 | 将来の簡単なPyYAML dump化をgateで止めにくい |
| GAP-10 | CoDD graph上のsource coverageが0 | `measure` tracked_files/source_files=0 | scripts/inbox_write.sh自体の実装coverageが数値上は見えていない |

Recommended lexicon axes for this script:

- `mailbox_durable_before_nudge`: inbox永続化がCLI nudgeやgate起動より先に成功する。
- `message_type_contract`: typeごとの入力、許可sender/target、副作用、失敗時挙動を列挙する。
- `shared_yaml_retention_policy`: retention閾値、未読優先、既読保持数、監査用途との関係を明示する。
- `report_received_side_effect_order`: report gate、git gate、review通知、task done遷移の順序とBLOCK境界を固定する。
- `codex_delivery_slo`: Codex task配備で何秒待ち、何回retryし、何をverifiedと見なすかを定義する。
- `no_yaml_dump_for_ops_yaml`: 運用YAMLの再描画・追記は専用emitterまたはfield helperに限定する。

## 3. Validate / Measure Score

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

### Design Quality Score for `inbox_write.sh`

Overall: 8/10.

Rationale:

- +2: requirements/design/brownfieldの3層CoDD文書が既に存在し、実装との紐づけもある。
- +2: target/sender制約、duplicate deploy gate、cmd_new gate、report format gateが入口で強制されている。
- +2: flock付き永続化、message block emitter、50件超過時の未読優先保持がある。
- +1: Codex task配備にdelivery verification/retryがあり、nudge欠落を検出する。
- +1: report_receivedがformat gate、未commit gate、gunshi review、task doneまで連鎖し、完了報告の品質を局所で止める。
- -1: type別の副作用と失敗時境界が文書上は粗く、実装読解が必要。
- -1: lexicon coverageとsource coverageが0で、要件穴の機械検出が機能していない。

## 4. Improvement Candidates

1. `codd/requirements/inbox_write_requirements.md` をtype別要求へ分解し、`task_assigned`, `report_received`, `review_result`, `cmd_new`, `clear_command`, `model_switch` の副作用契約を個別FRにする。
2. `codd/design/inbox_write_design.md` にreport_receivedの順序図を追加する。autofix、format gate、quality monitor、git gate、message persist、gunshi notify、task doneのBLOCK境界を明示する。
3. type enumをCoDD設計書または専用data modelへ集約し、headerコメント・watcher特殊type・gate分岐が同じ正本を参照する形にする。
4. inbox retention policyを要求化する。50件閾値、未読全保持、既読30件保持が監査要件を満たすかを決める。
5. `shogun_core` lexicon manifestの `prompt_extension` 欠落を修正し、CoDD elicitを全L4修行で自動実行可能に戻す。
6. `codd.yaml` のscan/source coverage設定を見直し、`scripts/inbox_write.sh` がtracked sourceとしてmeasureに反映されるようにする。

## 5. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `inbox_write.sh` と既存CoDD文書を読み、spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
