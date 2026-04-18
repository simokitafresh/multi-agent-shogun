# cmd_2053 CoDD Spec Recovery Batch

日付: 2026-04-18
担当: saizo
対象:
- `.claude/hooks/stop-lint-gate.sh`
- `scripts/gates/gate_recalculate_completeness.sh`
- `scripts/hooks/git-pre-commit.sh`

## 背景

cmd_2039 / cmd_2052 で after は記録済みだが、registry で spec パスが省略されている。殿指示に従い、正規 CoDD フロー `spec → Before → 実装 → After → revert判定` を再実施する。

## Before

| 対象 | 計測条件 | Before |
|------|----------|--------|
| `.claude/hooks/stop-lint-gate.sh` | isolated repo fixture, tracked `a.sh b.sh c.py` modified, lint pass | `32.3ms` median |
| `scripts/gates/gate_recalculate_completeness.sh` | `resolve_hostaddr` cached path fixture | `13.9ms` median |
| `scripts/hooks/git-pre-commit.sh` | instructions sync pass fixture | `18.6ms` median |

## ボトルネック仮説

### `.claude/hooks/stop-lint-gate.sh`

- reverted baseline は `git diff-index --cached` と `git ls-files -m` の両方で全変更ファイルを列挙しており、非対象拡張子も毎回走査する。
- fail hash 読込は `cat` を使っており builtin に置換できる。

### `scripts/gates/gate_recalculate_completeness.sh`

- cached path でも `command -v getent` 判定と無条件 `mkdir -p` が残る。
- `/tmp` の既存ディレクトリに対する `mkdir -p` は無駄 fork になっている。

### `scripts/hooks/git-pre-commit.sh`

- `REPO_ROOT` 解決が `cd "$(dirname ...)"` 依存で subshell を含む。
- failure recording の timestamp が `date -Iseconds` 外部呼出し。

## 改善方針

### `.claude/hooks/stop-lint-gate.sh`

- `git diff-index --cached` / `git ls-files -m` に pathspec (`*.sh` `*.bash` `*.py` `*.ts` `*.tsx` `*.js` `*.jsx`) を付与し、対象外拡張子の列挙を避ける。
- fail hash 読込を `$(< file)` に置換。
- `STOP_LINT_HASH_FILE` / `MOCK_AGENT_ID` 互換は維持する。

### `scripts/gates/gate_recalculate_completeness.sh`

- `write_cached_hostaddr` は parent dir が無い時だけ `mkdir -p`。
- `resolve_hostaddr` は `command -v getent` をやめ、`getent ... 2>/dev/null` の直接呼出しで判定を兼ねる。
- DB query / output 契約は変更しない。

### `scripts/hooks/git-pre-commit.sh`

- `REPO_ROOT` を string ops で解決。
- failure recording の timestamp を `printf -v '%(%Y-%m-%dT%H:%M:%S%z)T'` に置換し、ISO8601 形式を維持。
- 既存の block 条件・ログ構造・stderr tee 契約は維持。

## 検証計画

- `bash -n .claude/hooks/stop-lint-gate.sh scripts/gates/gate_recalculate_completeness.sh scripts/hooks/git-pre-commit.sh`
- `bats tests/unit/test_stop_lint_gate.bats`
- `bats tests/unit/test_gate_recalculate_completeness.bats`
- `bats tests/unit/test_git_pre_commit.bats`

## Revert判定

- 各対象で After が Before 以上(悪化 or 同等悪化傾向)なら、その変更は revert する。
- 3本のうち悪化したものは個別に戻し、悪化0件でのみ commit する。

## 実施結果

### `.claude/hooks/stop-lint-gate.sh`

- pre-`cmd_2039` の基準を `0ef2fba` と確定し、まずその内容へ戻した。
- pathspec 付き `git diff-index` / `git ls-files -m` を試したが、同一 fixture 比較で
  `29.4ms → 34.0ms` と悪化したため即 revert。
- 最終状態は revert baseline を維持。AC1 の revert は満たし、AC3 の「悪化0件」も満たす。

### `scripts/gates/gate_recalculate_completeness.sh`

- cached path で `mkdir -p` を存在時スキップ、`command -v getent` を直接呼出しへ統合。
- representative cached-path benchmark:
  - Before: `13.9ms`
  - After: `12.3ms`

### `scripts/hooks/git-pre-commit.sh`

- `REPO_ROOT` string ops 化と hook failure timestamp の `printf -v` 化はすでに HEAD に反映済みであることを確認。
- current HEAD の representative fixture benchmark:
  - Before reference: `18.6ms`
  - After(current HEAD): `17.5ms`
- 本 cmd では spec/registry 補完と再計測を担当し、追加変更は不要と判断。

## 最終採用値

| 対象 | Before | After | 判定 |
|------|--------|-------|------|
| `.claude/hooks/stop-lint-gate.sh` | `32.3ms` (revert baseline fixture) | `32.3ms` | revert維持 |
| `scripts/gates/gate_recalculate_completeness.sh` | `13.9ms` | `12.3ms` | 採用 |
| `scripts/hooks/git-pre-commit.sh` | `18.6ms` | `17.5ms` | HEAD採用(追加変更不要) |

## 検証結果

- `bats tests/unit/test_stop_lint_gate.bats`
- `bats tests/unit/test_gate_recalculate_completeness.bats`
- `bats tests/unit/test_git_pre_commit.bats`

全PASS。
