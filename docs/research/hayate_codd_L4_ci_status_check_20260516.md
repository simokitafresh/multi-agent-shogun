# CoDD修行L4: ci_status_check.sh 設計書品質検証

- 実施者: hayate
- 対象: `scripts/ci_status_check.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_L4_codd_c1_hayate`
- CoDD version: 2.18.0

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/ci_status_check.sh` は GitHub Actions `test.yml` の `main` 最新runを確認し、CI状態を2用途へ提供する。

| モード | 用途 | 出力/副作用 |
|---|---|---|
| default | `ninja_monitor.sh` の5分間隔CI赤検知 | CI赤/緑の変化時のみntfy通知し、`/tmp/last_ci_notify_state`へ通知済みrunを記録 |
| `--status` | `dashboard_auto_section.sh` などの表示用 | `GREEN` / `RED:<run_id>:<failed_jobs>` / `UNKNOWN` をstdoutへ出力 |

### 入力

| 入力 | 取得方法 | 契約 |
|---|---|---|
| GitHub Actions run | `gh run list --repo simokitafresh/multi-agent-shogun --workflow test.yml --branch main --limit 1 --json status,conclusion,databaseId` | 最新1件の `conclusion` と `databaseId` を取得 |
| 失敗job名 | `gh run view <run_id> --json jobs` | failure時のみ `.jobs[].name` を `, ` 結合。空なら `unknown` |
| 通知済み状態 | `/tmp/last_ci_notify_state` | `failure:<run_id>` または `success:<run_id>` |

### 出力

| 条件 | `--status` 出力 | default副作用 | exit |
|---|---|---|---|
| `gh` 不在 | `UNKNOWN` | なし | 1 |
| run取得失敗/空 | `UNKNOWN` | なし | 1 |
| run進行中 | `UNKNOWN` | なし | 0 |
| conclusion=`failure` | `RED:<run_id>:<failed_jobs>` | 未通知runなら `ntfy.sh "CI赤: run ..."` | 0 |
| conclusion=`success` | `GREEN` | 未通知runなら `ntfy_batch.sh "CI緑: run ..."` | 0 |
| その他conclusion | `UNKNOWN` | なし | 0 |

### 制約

- `set -euo pipefail` 前提。
- GitHub API呼び出しは各15秒timeout。
- `jq` を暗黙依存として使うが、事前存在チェックはない。
- `--status` はdashboard表示契約なので、副作用を持ってはならない。
- defaultモードはntfy重複抑止のため、通知済み状態ファイルへ書き込む。

### 対象範囲外

- CI修正そのもの。
- 複数workflow/branchの監視。
- GitHub Actions jobログ本文の解析。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexiconは存在するがcoverageへ反映されていない |
| `codd coverage report --path . --format md` | `Totals: 0 axes, 0 covered signals (0.00%)` | `shogun_core` がcoverage matrix対象として機能していない |
| `codd elicit --format md --path . --lexicon shogun_core` | `LexiconLoadError: manifest missing required string field 'prompt_extension'` | installed lexiconがelicit互換manifestではない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| 外部CLI依存 | 低 | `gh` は確認するが `jq` は未確認。`timeout` も前提化されている |
| 出力契約 | 中 | ヘッダーコメントと実装は一致。ただし下流利用者側の要件文書には単体契約がない |
| 通知冪等性 | 中 | run_id単位で重複抑止するが、状態ファイルがグローバル `/tmp` 固定 |
| 並行安全性 | 低 | `LAST_NOTIFY_FILE` へflockなしで書くため同時実行時に競合し得る |
| 障害可視性 | 低 | `gh`/`jq`失敗が `UNKNOWN` に丸められ、原因種別が失われる |
| テスト容易性 | 低 | `gh`, `jq`, `ntfy.sh`, `/tmp` が直書きで差し替えにくい |
| CI状態の意味論 | 中 | `failure` と `success` は明確だが `cancelled`, `timed_out`, `action_required` 等は全て `UNKNOWN` |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | `jq`/`timeout` の依存確認がない | `jq`不在時、run取得成功でも `conclusion` が空になり `UNKNOWN` 扱い。原因が不可視 |
| GAP-2 | HIGH | `/tmp/last_ci_notify_state` がrepo/projectでスコープ化されていない | 同一ホスト複数MASや別workflow監視があると通知抑止が干渉する |
| GAP-3 | MEDIUM | 通知状態ファイルの書込みにflock/atomic writeがない | `ninja_monitor` と手動実行が重なると状態ファイル競合の余地がある |
| GAP-4 | MEDIUM | `--status` の `UNKNOWN` が原因分類を持たない | dashboard上で「取得失敗」「進行中」「jq不在」「未対応conclusion」を区別できない |
| GAP-5 | MEDIUM | 失敗job名に `:` や改行が含まれる場合の下流パース契約がない | `RED:<run_id>:<failed_jobs>` のコロン区切りが曖昧化する |
| GAP-6 | LOW | `cancelled`/`timed_out` 等の非success/failure結論が未定義 | CI異常が単なる `UNKNOWN` に見え、運用判断が遅れる |

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `codd validate --path .` | `OK: validated 16 Markdown files under configured doc_dirs` |
| `codd measure --path . --json` | `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16` |
| `codd coverage report --path . --format md` | 0 axes。coverage設定またはlexicon manifest側に穴 |
| `codd extract --path . --language bash --source-dirs scripts ...` | `Extracted: 0 modules from 0 files`。bash抽出器は現行設定で `scripts/` を実質抽出できていない |

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 9 | ヘッダーコメントで用途・出力・exitが明示されている |
| 入出力契約 | 7 | `--status` 契約は明確だが、下流文書に単体要件として未収録 |
| 依存管理 | 5 | `gh` 以外の `jq`/`timeout` 依存が暗黙 |
| エラー可視性 | 5 | 失敗原因が `UNKNOWN` に丸め込まれる |
| 冪等性 | 7 | run_id dedupはあるが、状態ファイルのスコープと排他が弱い |
| テスト容易性 | 5 | 外部コマンドと通知副作用を注入しにくい |
| 保守性 | 8 | 89行で分岐は小さい。責務はCI状態取得+通知に限定されている |
| 総合 | 6.6/10 | 小さく明快だが、運用境界の契約化が不足 |

### 改善点

1. `jq`/`timeout` のpreflightを追加し、`--status` では `UNKNOWN` を維持しつつstderr/logに原因を出す。
   - 対応GAP: GAP-1, GAP-4
   - 期待効果: dashboardの不透明な `UNKNOWN` を運用ログで診断可能にする。

2. `LAST_NOTIFY_FILE` をrepo/workflow/branchスコープへ変更する。
   - 例: `/tmp/mas-ci-notify-${repo_hash}-${workflow_hash}-main.state`
   - 対応GAP: GAP-2
   - 期待効果: 複数MAS/複数workflow監視時の通知干渉を防ぐ。

3. 通知状態ファイル更新を `flock` + temp file + `mv` にする。
   - 対応GAP: GAP-3
   - 期待効果: 同時実行時も状態ファイルの部分書込み・競合を避ける。

4. `--status` の内部原因をログに分類する。
   - 例: `UNKNOWN:in_progress`, `UNKNOWN:gh_failed`, `UNKNOWN:jq_failed` は外部契約変更になるためstdoutには出さず、stderrまたはdebug flagで出す。
   - 対応GAP: GAP-4, GAP-6

5. failed_jobsの出力を単一行化し、区切り文字を下流契約に合わせてエスケープする。
   - 対応GAP: GAP-5
   - 期待効果: `dashboard_auto_section.sh` 側の `RED:<run_id>:<failed_jobs>` 解析を安定させる。

## CoDD側の発見

- `shogun_core` lexiconは `lexicon list` ではinstalled扱いだが、`elicit` では `prompt_extension` 欠落でロードできない。
- `coverage report` は0 axesとなり、installed lexiconの3 axesがcoverage matrixへ入っていない。
- `codd extract` はbash対象で `0 modules from 0 files` となり、対象スクリプトの設計品質評価には使えなかった。
- `codd brownfield` はファイル単体を受け付けず、`scripts/ci_status_check.sh` 直接指定では `Directory ... is a file` で終了した。

## 結論

`ci_status_check.sh` は小さく、用途・基本出力は明確である。一方で、CI監視という運用重要度に対して「依存preflight」「通知状態のスコープ/排他」「UNKNOWN原因分類」「failed_jobsの下流契約」が設計書化されていない。最優先改善は `jq`/`timeout` preflight と通知状態ファイルのスコープ化である。

## 追完ループ結果: cmd_training_codd_loop_hayate

### AC1: generate

Command:

```bash
timeout 1200 codd generate --wave 1 --force --path .
```

Result:

```text
wave_config not found. Auto-generating from requirements...
wave_config generated from 11 requirement(s)
Generated: docs/test/acceptance_criteria.md (test:acceptance-criteria)
Generated: docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)
Wave 1: 2 generated, 0 skipped
EXIT_CODE=0
```

Binary check: PASS (exit code 0)

### AC2: validate

Command:

```bash
timeout 1200 codd validate --path .
```

Result summary:

```text
ERROR: 655 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked
[ERROR] codd/design/cmd_save_design.md: node_id 'design:script:cmd-save' is already defined in docs/design/cmd_2762_cmd_save_design.md
[ERROR] codd/design/deploy_task_design.md: node_id 'design:script:deploy-task' is already defined in docs/design/cmd_2762_deploy_task_design.md
[ERROR] codd/design/inbox_write_design.md: node_id 'design:script:inbox-write' is already defined in docs/design/cmd_2762_inbox_write_design.md
[ERROR] codd/design/ninja_monitor_design.md: node_id 'design:script:ninja-monitor' is already defined in docs/design/cmd_2762_ninja_monitor_design.md
[ERROR] docs/archive/mcas.md: missing CoDD YAML frontmatter
[ERROR] docs/governance/adr_batch_yaml_io.md: depended_by references undefined node 'design:system-architecture'
[ERROR] docs/plan/implementation_plan.md: wave_config mismatch for 'plan:implementation-plan'
[ERROR] docs/research/cmd_1991_codd_extract/modules/cmd-1826-memory-analysis.md: circular dependency detected
EXIT_CODE=1
```

Binary check: FAIL (exit code 1; repository-wide CoDD validation currently has pre-existing global errors)

### AC3: measure

Command:

```bash
timeout 1200 codd measure --path .
```

Result:

```text
CoDD Project Metrics — Health Score: 0/100

Graph:   16 nodes, 12 edges, 4 orphans, max depth 1
         avg out-degree 0.75, connectivity 0.050
Coverage: 0/0 source files tracked (N/A), 628 design docs
Quality: 628 docs validated (653 errors, 386 warnings)
         0 files policy-checked (0 critical, 0 warnings), 0 rules
EXIT_CODE=0
```

health_score: 0

Binary check: PASS (exit code 0)
