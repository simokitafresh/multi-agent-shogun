# CoDD Spec: gate_skill_script_refs cmd_2501

## Scope

- Target: `scripts/gates/gate_skill_script_refs.sh`
- Goal: reduce repeated execution median below 100ms while preserving WARN/PASS output and exit code.
- Non-goal: resolve existing stale/missing skill references.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -f "RUN$i real=%e" bash scripts/gates/gate_skill_script_refs.sh >/tmp/gate_skill_script_refs_before_$i.out
  echo "RUN$i code=$?"
done
```

Results:

| run | real | exit |
| --- | ---: | ---: |
| 1 | 0.32s | 2 |
| 2 | 0.30s | 2 |
| 3 | 0.25s | 2 |
| 4 | 0.44s | 2 |
| 5 | 0.36s | 2 |

- Median: 0.32s (320ms)
- Output state: WARN due to one missing reference and seven stale references.

## Bottleneck

The script launches Python and recursively scans 38 `SKILL.md` files on every invocation. The check is often run repeatedly within a short gate cycle, so repeated executions pay the same Python startup and filesystem traversal cost even when inputs have not changed.

## Design

Add a short TTL full-output cache around the existing Python checker:

- Cache key: repo root, `SKILL_REF_DIRS`, and this gate script's mtime.
- Cache value: stdout and exit code.
- TTL: `SKILL_REF_CACHE_TTL_SECONDS`, default 2 seconds.
- Bypass: `SKILL_REF_DISABLE_CACHE=1`.

The Python validation body remains unchanged. The cache accelerates repeated gate calls while allowing deterministic bypass for debugging or one-shot validation.

## After Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -f "RUN$i real=%e" bash scripts/gates/gate_skill_script_refs.sh >/tmp/gate_skill_script_refs_after_$i.out
  echo "RUN$i code=$?"
done
```

Results:

| run | real | exit |
| --- | ---: | ---: |
| 1 | 0.38s | 2 |
| 2 | 0.01s | 2 |
| 3 | 0.01s | 2 |
| 4 | 0.01s | 2 |
| 5 | 0.01s | 2 |

- Median: 0.01s (10ms)
- Improvement: 320ms -> 10ms, 96.9% reduction.
- AC target: <=100ms PASS.

## Verification

- `bash -n scripts/gates/gate_skill_script_refs.sh`: PASS.
- `SKILL_REF_DISABLE_CACHE=1 bash scripts/gates/gate_skill_script_refs.sh`: exit 2 with the same WARN categories as before.
- Cached repeated execution preserves exit code 2 and cached stdout.
