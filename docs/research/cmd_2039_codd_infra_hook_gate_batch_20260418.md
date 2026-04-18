# cmd_2039 CoDD hook/gate batch after (2026-04-18)

## 対象

- `.claude/hooks/stop-lint-gate.sh`
- `scripts/gates/gate_recalculate_completeness.sh`
- `scripts/hooks/git-pre-commit.sh`

## 要約

- `stop-lint-gate.sh`: tracked changed-file列挙を `git status --porcelain=v2 -z` + `awk` 抽出へ置換し、lint実行前の repo root 移動を1回化した。full-repo隔離worktree benchmark median `0.84s`。
- `gate_recalculate_completeness.sh`: 相関 `EXISTS` 3本を distinct `portfolio_id` CTE + join に置換し、Python側sortを削除した。実DB benchmark median `1.76s`。
- `git-pre-commit.sh`: staged file一覧を1回だけ取得し、yaml.dump検査を単一 `git diff --cached -U0` 解析に置換した。current repo staged benchmark median `0.16s`。

## 実装詳細

### `.claude/hooks/stop-lint-gate.sh`

- `git status --porcelain=v2 -z --untracked-files=no | awk` で tracked changed files を一括抽出。
- rename entry(`2`) は新パスを採用し、旧パス側の NUL レコードは読み飛ばす。
- shellcheck / ruff / biome 実行前に `cd "$SHOGUN_ROOT"` を1回だけ実行し、各lint呼び出しの subshell `cd` を除去。
- fail hash 読込を bash builtin 化。

### `scripts/gates/gate_recalculate_completeness.sh`

- `signals` / `monthly_returns` / `fof_component_weights` をそれぞれ distinct `portfolio_id` CTE へ集約。
- active portfolioへの `LEFT JOIN` + `ORDER BY` で DB側判定を終え、Python側は単純なリスト走査だけにした。

### `scripts/hooks/git-pre-commit.sh`

- `list_staged_files` で staged file一覧を1回だけ取得し、instructions変更検出と yaml dump対象判定を同じ走査で処理。
- yaml dump検査を `git diff --cached --unified=0 --no-color` の単一出力解析へ変更し、ファイルごとの `git diff` / `grep` 多重起動を除去。
- `tests/unit/test_git_pre_commit.bats` を追加し、yaml dump block / test-comment除外 / instructions sync pass/fail を固定化。

## 計測

### `stop-lint-gate.sh`

- baseline(from task): `650ms`
- after:
  - isolated full-repo worktree runs: `0.84s`, `0.86s`, `0.82s`, `1.01s`, `0.84s`
  - median: `0.84s`
- 備考: live worktreeは他未整理変更の影響が大きいため、隔離worktree値を採用。

### `gate_recalculate_completeness.sh`

- baseline(from task): `2170ms`
- after:
  - real DB runs: `1.76s`, `2.34s`, `1.33s`
  - median: `1.76s`
  - verdict: `FAIL — 28 gaps detected`
- 備考: スクリプト自体は動作。FAILは現行データ完全性の問題であり、unit testは全PASS。

### `git-pre-commit.sh`

- baseline(from task): `736ms`
- after:
  - current repo staged runs: `0.17s`, `0.14s`, `0.13s`, `0.16s`, `0.16s`
  - median: `0.16s`

## テスト

- `bash -n .claude/hooks/stop-lint-gate.sh scripts/gates/gate_recalculate_completeness.sh scripts/hooks/git-pre-commit.sh`
- `bats tests/unit/test_stop_lint_gate.bats`
- `bats tests/unit/test_gate_recalculate_completeness.bats`
- `bats tests/unit/test_git_pre_commit.bats`
