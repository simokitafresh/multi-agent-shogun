---
name: shard-work
description: Shard two or more independent manifest items across the currently idle, capability-compatible workers. Use for tests, read-only research, mechanical transforms, or other command-template workloads that need deterministic LPT planning, isolated execution, partial retry, and lossless merge. Do not use for dependent items or when fewer than two eligible workers exist.
---

# Shard Work

1. Write a YAML manifest with `items`, `workers`, `max_workers`, `command`, and `state_dir`.
2. Each item requires stable `id`, positive `weight`, `capability`, and optional `path`/metadata. Each worker requires unique `id`, `idle: true`, and `capabilities`; adapter metadata is opaque.
3. Run `scripts/shard_work.sh MANIFEST --plan` to inspect the deterministic plan.
4. Run `scripts/shard_work.sh MANIFEST --run`. The coordinator locks once, reserves workers atomically, provides isolated work/TMP/output/cache/timing paths, and writes `merged.json`.
5. A later run preserves successful shards and retries only failed, skipped, timed-out, or cancelled shards.

The command supports placeholders `{item_id}`, `{item_path}`, `{worker_id}`, `{workdir}`, `{tmpdir}`, `{output_dir}`, and `{cache_dir}`. `N < 2`, duplicate IDs, missing items, duplicate assignment, or role/CLI/model policy fields are hard errors.
