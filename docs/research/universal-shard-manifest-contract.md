# Universal shard manifest contract

Stable boundary for the two follow-up adapter tasks from `cmd_karo_hotfix_universal_shard_core_202607161745`.

Required top-level fields are `items`, `workers`, `max_workers`, `command`, and `state_dir`; `timeout` is optional.

- `items[]`: unique stable string `id`, positive numeric `weight`, non-empty `capability`, optional `path` and opaque metadata.
- `workers[]`: unique `id`, boolean `idle`, string-list `capabilities`, optional opaque `adapter` metadata. Adapter metadata may describe Codex, Claude, unknown, or another backend but never controls authorization.
- Planner: `N=min(eligible,max_workers)`, N<2 is BLOCK. Items sort by descending weight then ID and go to the compatible bin with least total weight then worker ID.
- Executor: one coordinator flock, atomic worker reserve, isolated work/TMP/output/cache/timing, atomic merged state. Prior `success` is retained; other terminal states retry. Merge preserves `success`, `fail`, `skip`, `timeout`, `cancel` and rejects missing/duplicate IDs.
- Entry: `scripts/shard_work.sh MANIFEST --plan|--run`.

Command placeholders: `{item_id}`, `{item_path}`, `{worker_id}`, `{workdir}`, `{tmpdir}`, `{output_dir}`, `{cache_dir}`.
