# cmd_training_L4_codd_c1_kagemaru: bulletin_write.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/bulletin_write.sh`
pipeline: spec -> elicit/lexicon -> validate -> measure

## 1. Spec

### Purpose

`scripts/bulletin_write.sh` は、家老・軍師・将軍向けの掲示板投稿を `queue/bulletin_board.yaml` に永続化し、必要な相手へ `inbox_write.sh` 経由で通知する境界スクリプトである。掲示板が正本、inbox通知は読む行動を起こすための派生出力である。

### Scope

- CLI引数を `posted_by`, `content`, `requires_confirmation`, `action_type` に正規化する。
- 投稿者は明示引数を優先し、不足時はtmux pane変数から推定する。
- `requires_confirmation` と `BULLETIN_NOTIFY` は既知エージェントCSVへ正規化し、未知エージェントを拒否する。
- `queue/bulletin_board.yaml` はflock取得後にPythonで読み、tmpファイルへ全件再描画して `os.replace` で置換する。
- 同一 `posted_by` + 同一 `content` の重複投稿は既存entryを返してDEDUP終了する。
- 投稿成功後、投稿者以外の通知対象へ `scripts/inbox_write.sh` で全文通知する。

### Non-scope

- 掲示板entryのclose/confirm/archive操作は `bulletin_close.sh`, `bulletin_confirm.sh`, `bulletin_archive.sh` の責務。
- inboxの永続化・nudge配送・report gate連鎖は `inbox_write.sh` の責務。
- CoDD L4修行のため、本taskでは `bulletin_write.sh` の実装変更を行わない。

### Current Evidence

| Evidence | Result |
| --- | --- |
| `bash -n scripts/bulletin_write.sh` | PASS |
| `bash scripts/bulletin_write.sh --help` | usageを出してrc=1。no-args/help fast pathは投稿副作用なし |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd generate --path . --wave 1` | PASS: wave_config generated from 11 requirements; 0 generated; `docs/test/acceptance_criteria.md` and `docs/governance/adr_batch_yaml_io.md` skipped |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals。lexicon coverage未設定 |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path .` | FAIL: installed `shogun_core` lexicon manifest lacks required `prompt_extension` |

## 2. Elicit / Lexicon Findings

`codd elicit` はlexicon manifest不備で失敗したため、コード読解と既存 `shogun_core` coverage不在結果から、CoDD elicit相当の穴を手動で列挙する。

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | bulletin専用のCoDD requirement/design nodeがない | `find codd ... bulletin` で未検出。`inbox_write` は既存nodeあり | `validate/measure` は通るが、掲示板の要求・設計・実装のDAG追跡ができない |
| GAP-2 | `queue/bulletin_board.yaml` のwriter contractが設計書化されていない | flock + tmp + `os.replace` は実装にのみ存在 | 同じ掲示板YAMLを触るclose/confirm/archiveとの整合要件が暗黙知になる |
| GAP-3 | notification fanoutの失敗許容ポリシーが要求化されていない | inbox_write失敗とwatcher不在はWARN継続 | 掲示板永続化成功と通知失敗の境界がレビュー時に見落とされやすい |
| GAP-4 | `requires_confirmation` の型が bool/list の二形態で、消費側契約が明文化されていない | writerはbool/listを出力、startup gate/confirm側が解釈 | action_requiredや確認対象CSVの仕様変更時に下流破壊リスクがある |
| GAP-5 | DEDUP条件が `posted_by + content` のみで、action_type/requires_confirmationを無視する理由が未記録 | lines 185-190 | 同文だが確認対象だけ違う投稿を抑止する仕様か不具合か判断できない |
| GAP-6 | `BULLETIN_NOTIFY` の空CSV正規化時の期待挙動がテスト軸化されていない | `normalize_csv_agents` は空行を返す | 通知対象ゼロを許容するのか、全員通知へfallbackするのかが曖昧 |

Recommended lexicon axes for this script:

- `durable_primary_record`: 永続正本の書込みが通知より先に成功し、通知失敗で正本を巻き戻さない。
- `recipient_scope_control`: 通知対象CSVは既知エージェントへ正規化し、未知・空・重複の期待値をテストする。
- `shared_yaml_atomicity`: 共有YAMLはflock + tmp + atomic replaceで更新し、直接Editや非排他書込みを禁止する。
- `derived_notification_full_content`: 正本を読みに行かせず、通知本文に掲示板全文を含める。

## 3. Validate / Measure Score

### Generate Result

追完F1で `codd generate --path . --wave 1` を実行した。結果は `wave_config generated from 11 requirement(s)`、`Wave 1: 0 generated, 2 skipped`。既存の `docs/test/acceptance_criteria.md` と `docs/governance/adr_batch_yaml_io.md` がskipされ、`bulletin_write.sh` 固有の設計書は生成されなかった。原因は §2 GAP-1 の通り、`bulletin_write` 専用 requirement/design node が未登録であること。

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

### Design Quality Score for `bulletin_write.sh`

Overall: 7/10.

Rationale:

- +2: 実装は単一責務に近く、掲示板永続化と通知派生が明確に分離されている。
- +2: 共有YAML書込みはflock + tmp + `os.replace` でLost Update対策がある。
- +1: agent正規化、action_type正規化、content=agent名BLOCKなど運用ミス防止が実装済み。
- +1: `BULLETIN_NOTIFY` により通知先を限定でき、不要通知を減らせる。
- +1: help/no-args fast pathにより誤投稿副作用を避けられる。
- -1: CoDD requirement/design nodeが未整備で、DAG上はbulletin_writeが追跡対象外。
- -1: DEDUP、WARN継続、bool/list混在などの重要仕様がコードコメント止まり。
- -1: lexicon coverageが0で、要件穴を機械検出できない。

## 4. Improvement Candidates

1. `codd/requirements/bulletin_write_requirements.md` と `codd/design/bulletin_write_design.md` を追加し、`scripts/bulletin_write.sh` を `implementation` に紐づける。
2. `requires_confirmation` の正規形を要求化する。bool/list混在を維持するなら消費側ごとの期待値を設計書に明記し、将来変更時のDAG検知対象にする。
3. DEDUP仕様を要求化する。同文・同投稿者ならaction_typeや確認対象が違っても1件扱いでよいのか、keyへ含めるべきかを決める。
4. `BULLETIN_NOTIFY=""` や空CSVの挙動をテスト化する。通知なしを許可するなら意図的なsilent modeとして文書化する。
5. `shogun_core` lexicon manifestに `prompt_extension` を追加し、`codd elicit` が失敗せず要件穴を自動抽出できる状態に戻す。
6. 掲示板系スクリプト4本の共有YAML schemaを1つのCoDD requirementにまとめ、write/close/confirm/archiveの相互契約をDAG化する。

## 5. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `bulletin_write.sh` を読み、spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
