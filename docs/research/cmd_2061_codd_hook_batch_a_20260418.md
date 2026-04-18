# cmd_2061 CoDD Hook Batch A

日付: 2026-04-18
担当: saizo
対象:
- `.claude/hooks/stop-lint-gate.sh`
- `.claude/hooks/pre-bash-combined.sh`
- `.claude/hooks/post-bash-combined.sh`

## 背景

殿指示に従い、忍者体感に直結する hook 3本を正規 CoDD フローで再検証した。
今回は `spec → Before → 改善試行 → After → revert判定` を行い、悪化した変更は retained diff に残さない。

## Before

| 対象 | 計測条件 | Before |
|------|----------|--------|
| `.claude/hooks/stop-lint-gate.sh` | isolated repo fixture, tracked `a.sh b.sh c.py` modified, lint pass | `34.0ms` median |
| `.claude/hooks/pre-bash-combined.sh` | wf_runner block payload fixture | `20.6ms` median |
| `.claude/hooks/post-bash-combined.sh` | `report_received` commit-reminder fixture | `1082.8ms` median |

## ボトルネック仮説

### `.claude/hooks/stop-lint-gate.sh`

- `SHOGUN_ROOT` 解決が `$(cd dirname)` 依存。
- lint 実行ごとに `cd "$SHOGUN_ROOT" && ...` サブシェルが3本走る。

### `.claude/hooks/pre-bash-combined.sh`

- 同一 payload に対して `.tool_input.command` を guard ごとに `jq` で再抽出している。
- destructive guard の `SCRIPT_DIR` 解決が `$(cd dirname)` 依存。

### `.claude/hooks/post-bash-combined.sh`

- commit-reminder が Python で `task → projects → git diff×2` を辿っており、demo fixture でも 1s 超。
- `report_received` 系 payload は task 完了ごとに頻出するため、ここが体感遅延の主因。

## 改善試行

### `.claude/hooks/stop-lint-gate.sh`

- `SHOGUN_ROOT` を string ops 化。
- `cd "$SHOGUN_ROOT"` を1回だけ行い、shellcheck / ruff / biome の subshell `cd` を削減。

### `.claude/hooks/pre-bash-combined.sh`

- payload 冒頭で `command` を1回だけ `jq` 抽出し、各 guard の再抽出を削減。
- destructive guard の `SCRIPT_DIR` を string ops 化。

### `.claude/hooks/post-bash-combined.sh`

- commit-reminder を bash/awk + single `git status --porcelain` へ置換する試行を実装。
- 追加で `tests/unit/test_post_bash_combined.bats` を作成し、skip guidance と commit-reminder の dirty/clean 分岐を固定化。

## After / 判定

| 対象 | 試行After | 判定 |
|------|-----------|------|
| `.claude/hooks/stop-lint-gate.sh` | `35.7ms` | 悪化。revert |
| `.claude/hooks/pre-bash-combined.sh` | `24.6ms` | 悪化。revert |
| `.claude/hooks/post-bash-combined.sh` | `1296.0ms` | 悪化。revert |

### revert後確認

- `.claude/hooks/post-bash-combined.sh` reverted baseline fixture: `921.2ms` median
- `stop-lint` / `pre-bash` は current HEAD へ戻し、working tree diff なしを確認

## retained 変更

- `tests/unit/test_post_bash_combined.bats`
  - commit-reminder の dirty/clean 分岐と test-result guidance を固定化
- 本体 hook 3本には retained code change を残していない

## 検証

- `bash -n .claude/hooks/stop-lint-gate.sh .claude/hooks/pre-bash-combined.sh .claude/hooks/post-bash-combined.sh`
- `bats tests/unit/test_stop_lint_gate.bats tests/unit/test_pre_bash_wf_runner_block.bats tests/unit/test_post_bash_combined.bats`
- `bash scripts/hooks/test_hooks.sh`

全PASS。

## 結論

- 3本とも「思いつきの局所最適化」は悪化した。
- 特に `post-bash-combined.sh` は commit-reminder の repo 状態確認コストが支配的で、bash 化の試行はむしろ悪化した。
- 今回は「悪化を残さず戻す」こと自体が正しい CoDD 運用であり、retained change は回帰防止 test と記録に限定した。
