---
name: campaign-lane
description: Run deterministic, model-independent campaigns over numeric measurements. Use when selecting independent candidates across two or three rounds, preserving best-so-far, rejecting regressions, and stopping on target, budget, or saturation. Do not use for subjective evaluation, dependent candidates, production SEALED work, or fewer than two eligible idle workers.
---

# Campaign Lane

## What

Coordinate selection and measurement state; delegate parallel execution to the existing `shard-work` skill. This skill never deploys workers, monitors panes, or executes candidate commands.

## When / NOT When

Use only for a normalized numeric objective (`minimize`, `maximize`, or `target`) with independent candidates. Do not use when evaluation is subjective, production is `SEALED`, candidates depend on one another, or fewer than two capability-compatible idle workers exist; return an explicit `BLOCK` instead.

## Read

Read a catalog YAML and measurement JSONL. Validate both before selection. Catalog fields are `objective`, optional `target`, `min_rounds` (must be 2), `max_rounds` (must be 3), positive `budget`, `candidates`, and `workers`. Each candidate needs unique `id`, numeric `cost`, `capability`, and `independent: true`. Each worker needs unique `id`, `idle: true`, and `capabilities`.

## Judge

Run `python3 skills/campaign-lane/scripts/campaign_lane.py validate CATALOG MEASUREMENTS`, then `select`. Preserve the global best accepted value across all rounds. A later value is an improvement only against that best, never merely against the previous round. Reject measurements older than catalog `measurement_not_before`, duplicate `(target, round)` keys, same-round in-flight targets, and `quality_fail` results. Stop only after the minimum rounds, except explicit target or budget exhaustion; never exceed three rounds.

## Write

Use `record` to append one normalized result atomically. Use `status` for the current best and terminal reason. Measurements are append-only JSONL; never rewrite history.

## Handoff

`select` emits a `handoff` object only when at least two independent candidates and two eligible idle workers exist. Invoke `shard-work` with those items and `N = min(eligible candidates, eligible workers)`; do not hard-code worker identities or model names. `campaign-lane` owns campaign state and selection. `shard-work` owns deterministic planning, reservation, isolated execution, retry, and merge.

## Stop

Honor `TARGET_REACHED`, `BUDGET_EXHAUSTED`, `SATURATED`, and `MAX_ROUNDS`. Treat every `BLOCK` as terminal until its stated precondition changes. Never silently fall back to serial execution.
