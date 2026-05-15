# hayate CoDD R2: inbox_watcher.sh

metadata:
- task_id: `cmd_training_codd_r2_hayate`
- target: `scripts/inbox_watcher.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline surrogate: spec -> elicit/lexicon -> generate artifact -> validate -> measure

## Spec

`inbox_watcher.sh` is the mailbox wake-up daemon. It watches one agent inbox file and delivers minimal wake-up signals to the agent pane. Message content remains in YAML; tmux receives only CLI commands for special control messages or a short `inboxN` nudge for normal messages.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `AGENT_ID` | CLI arg 1 | Agent whose inbox is monitored. |
| `PANE_TARGET` | CLI arg 2 | tmux pane that receives wake-up signals. |
| inbox YAML | `queue/inbox/{AGENT_ID}.yaml` | Durable message source. |
| CLI profiles | `config/settings.yaml` + `cli_profiles.yaml` via `cli_lookup.sh` | Runtime CLI behavior: clear command, model support, busy defer. |
| tmux pane state | pane options and capture state | Busy/idle detection and safe wake-up routing. |
| state files | `${SHOGUN_STATE_DIR:-/tmp}` | Debounce, fingerprint, retry, first-unread age, heartbeat. |
| dependencies | `cli_lookup.sh`, `tmux_utils.sh`, `agent_state.sh`, `script_update.sh` | CLI routing, tmux safety, busy detection, self-update. |

Required behavior:

| Area | Requirement |
|---|---|
| Startup | Require `agent_id` and `pane_target`, initialize inbox to `messages: []` if absent, require `inotifywait`, initialize empty `@agent_state` to `idle`. |
| Unread extraction | Return unread normal count, special messages, fingerprint, and `task_assigned` presence in one lightweight read path. |
| Special commands | Process `clear_command` and `model_switch` before normal nudges; mark special messages read only after successful send or safe rejection. |
| CLI routing | Resolve effective CLI from pane `@agent_cli` first, then config; map `/clear` to CLI-specific clear command such as Codex `/new`. |
| Normal nudge | Send `inboxN`; for non-Claude task assignments append instruction to reread `queue/tasks/{agent}.yaml` from scratch. |
| Busy safety | Defer nudge when agent is active/busy, with timeout-based force paths to avoid permanent stalls. |
| Debounce/dedup | Use fingerprint, retry count, debounce file, and backoff to avoid duplicate nudge storms while preserving stale-unread recovery. |
| Delivery | Prefer agent self-watch skip, otherwise paste-buffer plus Enter under a tmux send lock; clear idle flag and set `@agent_state=active` after successful nudge. |
| Watch loop | Use `inotifywait` plus outer `timeout` and 60-second safety cycle for WSL2/DrvFs event loss and inode replacement. |
| Heartbeat/update | Write loop heartbeat and call `check_script_update` each cycle. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Sending full message content through tmux | Content belongs in inbox YAML; send-keys payloads caused hangs and context waste. |
| Poll-only implementation | Primary design is event-driven; timeout is a WSL2 safety net. |
| Marking special messages read before execution | Would lose clear/model commands on delivery failure. |
| Killing external watcher processes | Cleanup must only handle this script's child jobs. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| Special message | `clear_command` or `model_switch`, sent as CLI command rather than normal nudge. |
| Normal message | Any unread non-special message; delivered as `inboxN`. |
| Fingerprint | Sorted unread normal message IDs used for dedup and retry decisions. |
| Self-watch | Agent-side active inotify watcher; if present, external nudge can be skipped. |
| Busy defer | Temporary suppression while pane is active or Claude idle flag is absent. |
| Backoff | Recovery interval after retry exhaustion for stale unread messages. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| Lightweight YAML parser assumes constrained inbox shape and uses `split(':', 1)` on indented fields. | `get_unread_info()` line parser. | Fixture with colon in quoted content, block scalar, malformed line, missing id, and multiple unread messages. |
| Special message content security differs by type. | `clear_command` rejects shell metacharacters; `model_switch` uses regex whitelist. | Security fixture matrix for allowed/rejected clear follow-up and model_switch content. |
| `clear_command` sends `send_cli_command "/clear"` and relies on CLI profile mapping. | `send_cli_command()` remaps by effective CLI. | Fixture proving Codex receives `/new`, Claude receives `/clear`, unsupported model switch is skipped but read. |
| Busy recovery uses multiple clocks: `@last_active`, first-unread age, fingerprint mtime, debounce mtime. | `maybe_force_idle_flag()`, `send_wakeup()`, `process_unread()`. | Time-control tests for defer, force, retry, debounce, and backoff transitions. |
| Self-watch detection uses `pgrep -f "inotifywait.*inbox/{agent}.yaml"` and parent checks. | `agent_has_self_watch()`. | Process-detection tests for own child, external live watcher, dead parent, and no watcher. |
| Nudge sends paste-buffer then Enter, but debounce is refreshed before delivery. | `send_wakeup()`. | Failure fixture ensuring failed paste/Enter returns nonzero and does not falsely consume message state beyond debounce. |
| Watch loop comments say rc handled, but actual rc is not stored or logged. | `timeout ... inotifywait` return code is ignored. | Observability axis for rc=0/1/2/124 counters and last-event reason. |
| Startup requires `inotifywait` and exits if absent. | Hard dependency check. | Preflight axis: daemon supervisor should surface missing dependency as infrastructure failure. |

## Generated Design Artifact

Proposed generated design shape for future refactor:

| Component | Responsibility |
|---|---|
| `read_unread_snapshot` | Parse inbox into structured normal/special/task-assigned snapshot and parser diagnostics. |
| `process_special_commands` | Execute special command state machine and read-mark policy. |
| `decide_nudge` | Pure decision function over snapshot, fingerprint, retry, debounce, busy state, self-watch state. |
| `deliver_nudge` | tmux paste-buffer/Enter implementation with lock and delivery result. |
| `update_delivery_state` | Apply fingerprint, retry, debounce, idle flag, first-unread, and agent_state transitions. |
| `watch_loop` | Encapsulate inotify/timeout loop and heartbeat/update behavior. |
| `render_metrics` | Emit machine-readable event/result counters for watcher health. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `no_unread` | Clears fingerprint/retry and sends nothing. |
| `one_task_assigned_codex` | Sends `inbox1 — 前taskの情報は無効...queue/tasks/{agent}.yaml...`. |
| `task_info_codex` | Sends plain `inbox1` without task reread suffix. |
| `clear_command_codex` | Sends CLI profile clear command `/new`, then marks message read. |
| `model_switch_unsupported` | Logs skip/rejection and marks read to prevent retry loop. |
| `busy_under_threshold` | Defers nudge and preserves unread. |
| `busy_over_threshold` | Forces nudge. |
| `same_fingerprint_retry` | Retries up to `RETRY_MAX`, then waits for backoff. |
| `inotify_inode_replace` | Loop reprocesses unread after rc=1/124-style event loss. |

## Validate And Measure

Manual design quality score before CoDD validation: 84/100.

Rationale:

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 19/20 | Durable inbox plus minimal nudge design is explicit. |
| Input/output coverage | 17/20 | Runtime tmux and state-file inputs are mostly explicit. |
| Blocking/safety semantics | 17/20 | Special command read-mark and busy gating are clear. |
| Testability | 15/20 | Existing tests cover some watcher paths, but time/process/tmux state need more fixture isolation. |
| Maintainability | 16/20 | Helpers exist, but parsing, decision, delivery, and state mutation remain tightly coupled. |

Improvement backlog:

1. Extract `read_unread_snapshot` into a lib-only function with fixture tests for quoted colons, block scalar content, missing fields, and malformed YAML fragments.
2. Split nudge decision from tmux delivery so debounce/fingerprint/busy/backoff behavior can be unit-tested without tmux.
3. Add explicit event metrics for inotify rc=0/1/2/124, delivery failures, busy defers, busy forces, self-watch skips, and special-command outcomes.
4. Move special command allowlists into declarative CLI/profile policy so security rules are visible outside the shell case statement.
5. Make delivery-state updates transactional: only consume idle flag and set active after confirmed paste+Enter success.
6. Add tests proving Codex task assignment suffix is only attached to `task_assigned`, not to task_info or generic messages.

Executed command results:

| Command | Result |
|---|---|
| `bash -n scripts/inbox_watcher.sh` | PASS. |
| `codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `codd coverage report --path . --format md --output docs/research/hayate_codd_R2_inbox_watcher_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `codd lexicon list` | PASS: installed `shogun_core` with 3 axes. |
| `codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: bundled `shogun_core` manifest lacks required `prompt_extension`. |
| `codd plan --path .` | FAIL/tooling gap: `codd.yaml` lacks `wave_config`; direct `codd generate` would mutate project generation state, so this document is the generated design artifact for the task. |

This document is the generated spec/design artifact for AC1-AC3. Full CoDD measure/coverage/elicit results are recorded after command execution in the task report.
