# cmd_2049 CoDD Infra Hook Batch

日付: 2026-04-18
担当: saizo
対象: `scripts/hooks/session_start_inject.sh`, `scripts/hooks/prompt_state_inject.sh`, `scripts/hooks/session_end_clear_check.sh`

## 変更要約

- `scripts/hooks/session_start_inject.sh`
  - path 解決を string ops 化。
  - payload parse を `jq -e` + `jq -r` の2段から `jq -r` 1回へ集約。
  - timestamp を `date` から `printf -v` に置換。
  - snapshot / compact_state 読込を `cat` から shell builtin に変更。
  - `additionalContext` JSON 化の `printf | jq` を here-string 化。
- `scripts/hooks/prompt_state_inject.sh`
  - path 解決を string ops 化。
  - payload parse を `jq` 1回へ集約。
  - timestamp を `printf -v` 化。
  - snapshot 読込を shell builtin に変更。
  - `additionalContext` JSON 化を here-string 化。
- `scripts/hooks/session_end_clear_check.sh`
  - payload 読み取り/JSON検証を削除（値未使用のため）。
  - path 解決を string ops 化。
  - inbound count を `grep -c` から `awk` に変更。
  - `clear_prep_check.sh` 呼出を `bash script` から直接実行に変更。
  - ALERT 判定を `grep` から shell pattern match に変更。

## ベンチ手法

- `session_start_inject.sh`
  - `tmux display-message` を `saizo` 返却 stub に差し替え。
  - `queue/inbox/saizo.yaml`, `queue/karo_snapshot.txt`, `queue/compact_state/saizo.yaml` を fixture 化。
  - `{"type":"startup"}` を stdin へ与え、12回実行の中央値。
- `prompt_state_inject.sh`
  - `tmux display-message` を `shogun` 返却 stub に差し替え。
  - `queue/inbox/shogun.yaml`, `queue/karo_snapshot.txt` を fixture 化。
  - `{"prompt":"通常入力"}` を stdin へ与え、12回実行の中央値。
- `session_end_clear_check.sh`
  - `tmux display-message` を `shogun` 返却 stub に差し替え。
  - `lord_conversation.jsonl`, `clear_prep_check.sh`, `ntfy.sh` を fixture/stub 化。
  - 12回実行の中央値。

## ベンチ結果

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/hooks/session_start_inject.sh` | `61.7ms` | `44.3ms` | `-28.2%` |
| `scripts/hooks/prompt_state_inject.sh` | `49.0ms` | `30.5ms` | `-37.8%` |
| `scripts/hooks/session_end_clear_check.sh` | `49.2ms` | `29.4ms` | `-40.2%` |

## 検証

- `bats tests/unit/test_session_state_hooks.bats`

全PASS。
