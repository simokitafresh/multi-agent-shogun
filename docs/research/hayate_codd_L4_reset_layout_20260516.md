# reset_layout.sh CoDD L4 Spec / Elicit / Measure

## Saizo Follow-up G3: Spec Completion

Task: `cmd_training_codd_g3_saizo`

`/home/simokitafresh/.codd-venv/bin/codd spec --path . scripts/reset_layout.sh` was executed on 2026-05-16 02:49 JST. Local CoDD v2.18.0 has no `spec` subcommand, returning `Error: No such command 'spec'.` This section records the missing target-specific spec as the durable spec-equivalent artifact for `scripts/reset_layout.sh`.

### Target-Specific Functional Requirements

| ID | Requirement | Evidence / Current implementation |
|----|-------------|-----------------------------------|
| FR-G3-1 | Derive the expected agent list from `scripts/lib/agent_config.sh` instead of hard-coding pane membership. | `get_all_agents`, `get_agent_role` |
| FR-G3-2 | Ensure `shogun:agents` has exactly the expected pane count, adding missing panes but stopping on surplus panes. | Step 1 pane-count branch |
| FR-G3-3 | Restore pane order by matching expected `@agent_id` values and swapping panes into canonical positions. | Step 2 forward scan and `tmux swap-pane` |
| FR-G3-4 | Respawn dead panes and start the configured CLI for panes that are alive but lack a CLI child process. | Step 3 / Step 3.5 |
| FR-G3-5 | Reapply pane metadata, prompt colors, model display, group, background, title, border format, and layout. | Step 4 / Step 5 |
| FR-G3-6 | Preserve live pane task/context state while initializing only respawned panes. | `RESPAWNED` tracking and conditional reset |
| FR-G3-7 | Keep `--dry-run` non-mutating across pane creation, swaps, respawn, CLI start, option writes, layout, and watcher restart. | `DRY_RUN` guards |
| FR-G3-8 | Restart watchers after a real restoration run so inbox and pane variables are synchronized. | Step 6 `scripts/restart_watchers.sh` |

### Required CoDD Graph Nodes

| Node | Purpose |
|------|---------|
| `codd/requirements/reset_layout_requirements.md` | Canonical requirements for pane count, pane identity, liveness recovery, CLI startup, metadata restore, layout restore, dry-run safety, and watcher synchronization. |
| `codd/design/reset_layout_design.md` | Design contract for tmux mutations, helper dependencies, dry-run boundaries, respawn state handling, and final summary output. |
| coverage axis: `pane_topology` | Expected, missing, surplus, swapped, duplicate, and unknown pane states. |
| coverage axis: `process_recovery` | Dead panes, alive panes without CLI, CLI direct-child assumptions, and post-start verification. |
| coverage axis: `non_mutating_dry_run` | No split, swap, respawn, CLI start, option write, layout change, or watcher restart under `--dry-run`. |
| coverage axis: `watcher_sync` | Watcher restart success, failure, and partial synchronization after layout restore. |

### Spec Gaps To Close Before Future Generate

1. Add fake-tmux fixture tests that assert `--dry-run` emits intended actions without mutating panes/options/processes.
2. Replace direct-child-only CLI detection with process-tree detection, or document direct-child CLI as an invariant.
3. Define watcher restart failure semantics: full failure, partial success, or retry policy.
4. Add a machine-readable summary mode for pane_add, swap, respawn, cli_start, var_fix, layout, and watcher counts.
5. Emit duplicate/unknown `@agent_id` diagnostics when pane count is greater than expected instead of only returning a generic surplus-pane error.

cmd: cmd_training_L4_codd_202605160001_hayate
date: 2026-05-16
author: hayate
target: `scripts/reset_layout.sh`

---

## Purpose

`scripts/reset_layout.sh` は、`shogun:agents` window のペイン数、配置、死亡状態、CLI起動状態、tmux pane variables、pane border format、layout、inbox watcher を一括復元する運用復旧スクリプトである。
通常実行は状態を変更し、`--dry-run` は診断のみを行う。

## Scope

### In Scope

- `shogun:agents` のペイン数を `get_all_agents()` の期待数へ合わせる。
- `@agent_id` の順序を `agent_config.sh` の期待順へ正規化する。
- 死亡ペインを `tmux respawn-pane` で復活させ、作業ディレクトリ、PS1、CLIを再起動する。
- 生存中だが CLI 子プロセスがないペインへ CLI を起動する。
- `@agent_id`, `@model_name`, `@agent_group`, `@agent_cli`, pane background, pane title を再設定する。
- 死亡復活ペインのみ `@context_pct` と `@current_task` を初期化する。
- `pane-border-format` と 3列レイアウトを再適用する。
- 通常実行時のみ `scripts/restart_watchers.sh` を呼び出す。

### Out of Scope

- 余剰ペインの自動削除。余剰時は ERROR で停止し、手動削除を要求する。
- `shogun:main` window の復元。
- CLI内部状態、会話文脈、タスクYAML内容の復元。
- watcher再起動失敗時の自動リトライ。
- `--dry-run` による状態変更。

## Functional Requirements

| ID | Requirement | Evidence |
|----|-------------|----------|
| FR-1 | `--dry-run` 指定時は状態変更コマンドを実行せず、予定操作を表示する | `DRY_RUN=true` branch, dry-run実行で watcher再起動は「スキップ」 |
| FR-2 | 期待エージェント一覧は `agent_config.sh` の `get_all_agents()` から導出する | `source scripts/lib/agent_config.sh`, `read -ra EXPECTED_AGENTS` |
| FR-3 | ペイン不足時は `tmux split-window` で不足数を追加し、未割当ペインへ不足agent_idを割り当てる | Step 1 |
| FR-4 | ペイン過剰時は自動削除せず exit 1 で停止する | Step 1 `PANE_COUNT > NUM_AGENTS` |
| FR-5 | 期待順と実配置が異なる場合は前方走査で `tmux swap-pane` し、各位置を確定する | Step 2 |
| FR-6 | 死亡ペインは `tmux respawn-pane` 後に `cd`, PS1設定, CLI起動を行う | Step 3 |
| FR-7 | 生存ペインでも CLI 子プロセスがなければ CLI を起動する | Step 3.5 |
| FR-8 | 各ペインのagent/model/group/cli/background/titleを常に再設定する | Step 4 |
| FR-9 | 復活ペインだけ context/current_task を初期化し、生存ペインの状態は維持する | Step 4 |
| FR-10 | layout string は `layout_string.sh` に委譲し、window size と settings から動的生成する | Step 5 |
| FR-11 | 通常実行時は最後に `restart_watchers.sh` を呼び、watcherとpane varsを同期する | Step 6 |
| FR-12 | 最終サマリで pane/agent/dead/group/cli/model/bg を一覧表示する | Step 7 |

## Constraints

| ID | Constraint |
|----|------------|
| C-1 | `set -e` により予期しないコマンド失敗は即停止する |
| C-2 | 実行ルートは `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` で repo root へ固定する |
| C-3 | CLI起動コマンドは `build_cli_command "$agent_id"` に委譲し、settings/cli_profiles準拠にする |
| C-4 | モデル表示名は `resolve_model_display`、背景色は `resolve_bg_color` に委譲する |
| C-5 | prompt color は role に基づき karo=red, gunshi=cyan, others=yellow とする |
| C-6 | `--dry-run` はペイン追加、swap、respawn、CLI起動、変数設定、layout適用、watcher再起動を実行しない |
| C-7 | `tmux` session/window 名 `shogun:agents` に強く依存する |

## Data Boundaries

| Direction | Data |
|-----------|------|
| Read | `config/settings.yaml`, tmux pane/window options, process tree via `pgrep`, `scripts/lib/*.sh` |
| Write | tmux panes/options/titles/background/layout, new panes, respawned panes |
| Execute | agent CLI commands, `scripts/restart_watchers.sh` |
| No Write in dry-run | tmux state and watcher processes |

## Elicit / Lexicon Gaps

| Gap | Severity | Question / Coverage Axis |
|-----|----------|--------------------------|
| G-1: `pgrep -P "$pane_pid"` only checks direct child processes | high | CLIがshellの孫プロセスになった場合に未起動と誤判定しないか。coverage: direct child / grandchild / wrapped command |
| G-2: `set -e` plus sourced helper failure boundaries are not specified | medium | `resolve_model_display`, `resolve_bg_color`, `generate_layout_string` 失敗時に全体停止でよいか。coverage: helper failure / missing config / malformed settings |
| G-3: pane-base-index 0/1以外の異常値に対する期待が未定義 | low | tmux設定が想定外の場合も `PANE_BASE + i` でよいか。coverage: base 0 / base 1 / unexpected numeric |
| G-4: dry-runの安全性を機械テストで保証していない | high | dry-run前後で pane count/options/processes が不変であることをテストすべき。coverage: no split / no swap / no respawn / no watcher restart |
| G-5: respawn後CLI起動成功の確認がない | medium | `build_cli_command` 送信後、実際にCLIが起動したかを検証すべきか。coverage: command sent / process exists / prompt ready |
| G-6: `restart_watchers.sh` 失敗時の復旧方針が未定義 | medium | 最後のwatcher再起動が失敗した場合、layout復元は成功扱いか失敗扱いか。coverage: watcher success / watcher failure / partial watcher failure |
| G-7: 余剰ペイン時の人間向け手順が出力されない | low | exit 1だけでなく、対象windowと削除候補確認手順を表示すべきか。coverage: 9 panes / duplicate agent_id / unknown pane |
| G-8: `shogun:agents` 不存在時の要求が明文化されていない | medium | window不存在なら作成すべきか、明示エラーでよいか。coverage: session missing / window missing / pane list failure |

## Coverage Axes

| Axis | Cases |
|------|-------|
| execution mode | normal, dry-run |
| pane count | expected, fewer, greater |
| pane identity | correct, swapped, missing @agent_id, duplicate @agent_id |
| pane liveness | alive, dead, alive without CLI |
| CLI type | claude, codex, copilot, kimi |
| model display | detected, fallback, malformed |
| tmux config | pane-base-index 0, pane-base-index 1 |
| layout dimensions | normal terminal, narrow terminal, low-height terminal |
| watcher restart | success, failure, partial failure |

## Validation / Measure

Commands executed:

```bash
/home/simokitafresh/.codd-venv/bin/codd --version
/home/simokitafresh/.codd-venv/bin/codd validate --path .
/home/simokitafresh/.codd-venv/bin/codd measure --path . --json
bash scripts/reset_layout.sh --dry-run
```

Observed results:

| Check | Result |
|-------|--------|
| CoDD version | `codd, version 2.18.0` |
| validate | PASS: `OK: validated 16 Markdown files under configured doc_dirs` |
| measure.health_score | 95 |
| measure.graph.total_nodes | 16 |
| measure.graph.total_edges | 12 |
| measure.graph.orphan_nodes | 4 |
| measure.quality.validation_errors | 0 |
| measure.quality.validation_warnings | 0 |
| reset_layout dry-run | PASS: no pane add/swap/respawn/CLI start; watcher restart skipped |

Design quality score for this spec: **82/100**.

Rationale:

- Strong: purpose, scope, side effects, dry-run boundary, and dependencies are explicit.
- Strong: actual CoDD `validate` and `measure` were run against the repo.
- Weak: no dedicated test matrix exists for `reset_layout.sh` behavior.
- Weak: runtime process detection and watcher failure semantics are not fully specified.
- Weak: dry-run non-mutability is observed manually, not asserted by an automated test.

## Improvement Candidates

1. Add Bats tests with a fake `tmux` command to verify dry-run produces no mutating tmux/restart calls.
2. Replace direct-child-only CLI detection with a process-tree check or document that CLI must be direct child of the pane shell.
3. Add explicit failure semantics for Step 6 watcher restart: either make layout restore fail if watcher restart fails, or report partial success in a machine-readable summary.
4. Add a `--json` or `--summary-file` output mode for reset results so gates can verify pane_add/swap/respawn/cli_start counts without parsing human logs.
5. Emit actionable remediation when pane count is greater than expected, including current pane list and duplicate/unknown agent_id detection.
6. Add coverage for missing `shogun:agents` window and malformed `config/settings.yaml` before tmux mutation starts.

## AC Mapping

| AC | Status | Evidence |
|----|--------|----------|
| AC1 | PASS | This document records purpose, constraints, scope, data boundaries, and functional requirements derived from `scripts/reset_layout.sh` |
| AC2 | PASS | Elicit/lexicon gaps and coverage axes are listed in dedicated sections |
| AC3 | PASS | CoDD validate/measure results, quality score, and six improvement candidates are recorded |

## Saizo Follow-up G3: Validate / Measure After Spec Completion

Task: `cmd_training_codd_g3_saizo`

| Command | Result |
|---------|--------|
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs` |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16`, `coverage_ratio=0.0` |

### G3 Binary Checks

| AC | Check | Result |
|----|-------|--------|
| AC1 | `codd spec` was executed and the local CLI failure plus spec-equivalent requirements were inserted into this existing file near the top. | yes |
| AC2 | `codd validate` was rerun after the spec completion section was added, and this result was appended to this file. | yes |
| AC3 | `codd measure` was rerun after validation, and `health_score=95` is recorded here. | yes |

## CoDD Extract / Generate Results

実行者: kagemaru
日付: 2026-05-16
task_id: `cmd_training_codd_loop3_kagemaru`
対象: `scripts/reset_layout.sh`

### AC1: extract

コマンド:

```bash
timeout 1200 codd extract --path .
```

結果:

```text
Extracted: 0 modules from 0 files (0 lines)
Output: .codd/extract/
  system-context.md
  architecture-overview.md

Next steps:
  1. Review generated docs in .codd/extract/
  2. Promote confirmed docs: mv .codd/extract/*.md docs/design/
  3. Run: codd scan  (to build the dependency graph)
```

観察: extractは正常終了したが、`scripts/reset_layout.sh`専用moduleは抽出されず、0 modules / 0 filesだった。`.codd/extract/`配下に汎用の`system-context.md`と`architecture-overview.md`が生成されたが、task ACは既存md末尾への追記であり、promoteは実施していない。

### AC2: generate

コマンド:

```bash
timeout 1200 codd generate --wave 1 --force --path .
```

結果:

```text
Generated: docs/test/acceptance_criteria.md (test:acceptance-criteria)
Generated: docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)
Wave 1: 2 generated, 0 skipped
```

観察: generateは成功し、2件生成・0件skipだった。ただし生成された2件は既存requirements/wave_config由来の汎用CoDD文書であり、`scripts/reset_layout.sh`専用の追加設計ではなかった。task ACの「別ファイル禁止」に従い、生成物は副作用として記録し、最終成果物には含めない。

### AC3: validate

コマンド:

```bash
timeout 1200 codd validate --path .
```

結果:

```text
ERROR: 658 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked
```

主な失敗:

| 種別 | 例 |
|---|---|
| duplicate node_id | `codd/design/*` と `docs/design/cmd_2762_*` の重複 |
| missing frontmatter | `docs/research/*.md`、`docs/future/*.md` など広範 |
| undefined node | `docs/governance/adr_batch_yaml_io.md` の `design:system-architecture` など |
| wave_config mismatch | `docs/plan/implementation_plan.md`、`docs/research/cmd_2589_codd_acceptance_criteria.md` |
| circular dependency | `docs/research/cmd_1991_codd_extract/modules/*` |

判定: FAIL。現行`codd/codd.yaml`が`docs/`全体をdoc_dirsに含めているため、`reset_layout.sh`単体のvalidateではなく、既存Markdown群全体のCoDD整合性不備を検出している。

### AC4: measure

コマンド:

```bash
timeout 1200 codd measure --path . --json
```

結果:

```json
{
  "health_score": 0,
  "graph": {
    "total_nodes": 16,
    "total_edges": 12,
    "orphan_nodes": 4,
    "max_depth": 1,
    "avg_out_degree": 0.75,
    "connectivity": 0.05
  },
  "coverage": {
    "tracked_files": 0,
    "source_files": 0,
    "design_documents": 628,
    "coverage_ratio": 0.0
  },
  "quality": {
    "validation_errors": 651,
    "validation_warnings": 386,
    "policy_critical": 0,
    "policy_warnings": 0,
    "documents_checked": 628,
    "files_policy_checked": 0,
    "rules_applied": 0
  }
}
```

health_score: 0

### 追完結論

`codd extract --path .`は正常終了したが、`reset_layout.sh`専用moduleは抽出されず、0 modules / 0 filesだった。`codd generate --wave 1 --force`も正常終了し、2件生成・0件skipだったが、生成結果は`reset_layout.sh`専用追補ではなく汎用CoDD文書生成だった。validate/measureは`docs/`全体scanによりFAIL/health_score 0であり、次にやるべきことは`reset_layout.sh`専用requirement nodeとwave_configの接続、またはextract/generate対象を限定するCoDD設定を作ることである。
