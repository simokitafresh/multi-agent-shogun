# cmd_2079 CoDD Spec: `scripts/shutsujin_departure.sh`

- cmd: `cmd_2079`
- worker: `hayate`
- target: `scripts/shutsujin_departure.sh`
- date: `2026-04-18`

## Phase 1: Baseline

- measurement command: ``/usr/bin/time -f "%e" bash scripts/shutsujin_departure.sh --dry-run``
- samples: `0.15s`, `0.14s`, `0.13s`, `0.12s`, `0.12s`
- median: `0.13s`
- target: `0.05s` 以下

## Phase 2: Bottleneck Hypothesis

- `tmux` 単発呼出しは各 `~0.01s`。`list-windows` / `list-panes` / `show-options` を足しても `~0.03s`
- 支配的なのは起動直後の source 群
  - `scripts/lib/agent_config.sh`: median `0.03s`
  - `lib/cli_adapter.sh`: median `0.04s`
  - `scripts/lib/model_colors.sh`: median `0.02s`
  - `scripts/lib/model_detect.sh`: median `0.02s`
  - `scripts/lib/model_resolve.sh`: median `0.02s`
  - `scripts/lib/pane_format.sh`: median `0.01s`
  - `scripts/lib/layout_string.sh`: median `0.02s`
- 合計で `~0.14-0.16s`。現行 dry-run 全体 `0.12-0.15s` と整合

## Phase 3: Constraint

- `layout_is_normalized()` は `get_all_agents()` のみ必要
- dry-run では実 CLI 起動も `detect_real_model` も不要
- dry-run の `pane-border-format` preview は厳密な色文字列再構築でなく、内容説明の placeholder で足りる
- non-dry-run の動作は維持必須

## Phase 4: Plan

1. `agent_config.sh` のみ先読みし、他ライブラリは必要時に遅延読込する helper を追加
2. `DRY_RUN=true` のときは以下を source しない
   - `lib/cli_adapter.sh`
   - `scripts/lib/model_colors.sh`
   - `scripts/lib/model_detect.sh`
   - `scripts/lib/model_resolve.sh`
   - `scripts/lib/pane_format.sh`
   - `scripts/lib/layout_string.sh`
3. dry-run で参照していた値は軽量 fallback に置換
   - `AGENTS_PANE_BORDER_FORMAT` → placeholder string
   - `shogun_model` → `Unknown`
4. after 計測を同条件 5回で取り、関連 bats を通す

## Risk

- dry-run preview 文字列が簡略化されるため、正確な tmux format 文字列は非 dry-run 時のみ担保する
- `reset_layout.sh` など非 dry-run 経路の依存 source を落とすと本番 regress するため、分岐は dry-run 限定に閉じる

## Phase 5: After

- implementation:
  - dry-run 時は `agent_config.sh` 以外の source を遅延
  - dry-run では window existence check を省略し、`shogun:main` / `shogun:agents` を直接使用
  - healthy fast-path (`layout_is_normalized=true`) では idle flag per-agent preview と二重 layout check を省略
- after samples:
  - `0.04s`
  - `0.05s`
  - `0.05s`
  - `0.04s`
  - `0.04s`
- after median: `0.04s`
- delta: `0.13s → 0.04s` (`-69.2%`)

## Validation

- `bash -n scripts/shutsujin_departure.sh`
- `bash scripts/shutsujin_departure.sh --dry-run`
- `bats tests/unit/test_switch_cli.bats tests/unit/test_cli_adapter.bats`
