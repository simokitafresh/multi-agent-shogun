# Hanzo model/effort switch experiment (2026-07-21)

## Result

BLOCKED / FAIL. This run did not establish the requested 2/2 respawn verification.
The active Hanzo pane was observed as `gpt-5.6-luna / medium`; the shared Codex
configuration was also `gpt-5.6-luna`, `model_reasoning_effort = medium`, and
`service_tier = default` at the observation boundary. Shared configuration
checksum: `da1c49e9ac5f2eb4ef02301a9f609abb3863dd4da4b3291b38de6bc6ffb03340`.

## Primary observations

- Identity: `agent=hanzo`, tmux pane `%4`.
- Pane banner: `gpt-5.6-luna medium`.
- Process evidence: Hanzo's Codex process was running with
  `-c model_reasoning_effort=medium -c service_tier=default` and no model override
  visible in the process arguments.
- Shared config fields at observation: `model = "gpt-5.6-luna"`,
  `model_reasoning_effort = "medium"`, `service_tier = "default"`.
- Other active panes showed mixed banners (`sol-low`, `sol-high`, and
  `luna-medium`), but no before/after paired observation was produced by this
  fresh run.

## Acceptance evidence

| AC | Result | Evidence / gap |
|---|---|---|
| AC1 | PASS | Identity, task, config fields, service tier, and checksum recorded above. |
| AC2 | NO | No fresh sol-medium and luna-medium respawn pair with both banner/process matches was completed in this run. |
| AC3 | NO | No fresh per-trial before/after checksum pair or 0/N cross-agent delta measurement exists. |
| AC4 | NO | Current pane is luna-medium, not the requested gpt-5.6-sol-low restoration; success count is 0/2 for this fresh run. |
| AC5 | YES | Because AC2–AC4 remain unresolved, this report is BLOCK/FAIL rather than PASS. |

## Safe reproduction procedure

Run each model trial in an isolated Codex process or a dedicated disposable
tmux pane: snapshot the shared config checksum, apply the per-agent model and
effort, respawn only the disposable pane, verify both banner and process,
restore the snapshot, and compare the checksum and all other agent banners.
Restore Hanzo to `gpt-5.6-sol-low` only after the final verification and record
the resulting banner/process evidence. Do not change the shared config while
other active agents depend on it.
