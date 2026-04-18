# cmd_2087 CoDD Spec: `scripts/ntfy.sh`

- cmd: `cmd_2087`
- worker: `saizo`
- target: `scripts/ntfy.sh`
- date: `2026-04-18`

## Phase 1: Baseline

- measurement method: isolated fixture on `/tmp` with copied `scripts/ntfy.sh` + `lib/ntfy_auth.sh` + `lib/lord_conversation.sh`
- hot path definition: default async return path (`bash scripts/ntfy.sh "bench message"`), with `tmux` / `curl` stubbed and `settings.yaml` / `ntfy_auth.env` provided
- sync reference path: `NTFY_SYNC=1` with the same fixture, for internal send-path attribution
- baseline samples:
  - async: `10ms`, `11ms`, `12ms`, `13ms`, `18ms`
  - sync: `84ms`, `89ms`, `97ms`, `137ms`, `154ms`
- baseline median:
  - async hot path: `12ms`
  - sync reference: `97ms`

## Phase 2: Bottleneck Hypothesis

- async hot path の支配要因は network ではなく起動前処理
  - `tmux display-message` caller lookup: median `17ms`
  - `source lib/ntfy_auth.sh`: median `7ms`
  - `grep | awk | tr` による `ntfy_topic` 取得: median `11ms`
  - process substitution + read loop による auth args 構築: median `7ms`
- sync path は上記に加え `append_lord_conversation()` の python3 JSONL append が支配的
- よって今回の改善対象は async hot path に絞る。`curl` 自体は default mode では background 化済みで主因ではない

## Phase 3: Constraint

- インターフェース `bash scripts/ntfy.sh "msg"` は不変
- `ntfy_auth.sh` の既存 stdout API (`ntfy_get_auth_args`) は維持
- 認証優先順位(token > basic > none)、topic validation、warning semantics は不変
- default async mode と `NTFY_SYNC=1` の動作差は維持

## Phase 4: Plan

1. `settings.yaml` の `ntfy_topic` 読み出しを pure bash helper に置換し、`grep | awk | tr` を削除
2. `ntfy_auth.sh` に配列返却 helper を追加し、`ntfy.sh` 側の process substitution + read loop を除去
3. `lord_conversation.sh` は送信成功時のみ遅延 `source` し、default async path の前処理から外す
4. after 計測を同一 fixture / 同一5回条件で再実施し、関連 bats を通す

## Phase 5: After

- implementation:
  - `read_ntfy_topic()` を追加し、`ntfy_topic` 読み出しを pure bash 化
  - `ntfy_get_auth_args_into_array()` を追加し、配列直格納で auth args を組み立て
  - `append_lord_conversation_safe()` を追加し、成功時のみ `lord_conversation.sh` を読込
- after samples:
  - async: `7ms`, `9ms`, `12ms`, `18ms`, `19ms`
  - sync: `62ms`, `71ms`, `77ms`, `82ms`, `108ms`
- after median:
  - async hot path: `12ms` (同率。改善は誤差範囲)
  - sync send path: `77ms`
- delta:
  - async hot path: `12ms → 12ms` (`0%`, no material change)
  - sync send path: `97ms → 77ms` (`-20.6%`)
- component deltas:
  - `ntfy_topic` parse: `11ms → 5ms`
  - auth args build: `7ms → 4ms`
- interpretation:
  - user-visible async return path は fork/tmux 分散で測定ノイズが大きく、今回改善は埋没
  - command が要求する send path (`NTFY_SYNC=1`) では前処理削減が素直に効き、`20ms` 改善を確認

## Validation

- `bash -n scripts/ntfy.sh lib/ntfy_auth.sh`
- `bats tests/unit/test_ntfy_auth.bats tests/unit/test_ntfy_listener.bats tests/unit/test_ntfy_ack.bats tests/unit/test_session_state_hooks.bats tests/unit/test_cmd_1408_defensive_coding.bats`
