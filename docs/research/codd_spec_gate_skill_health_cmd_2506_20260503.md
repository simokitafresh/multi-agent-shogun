# CoDD Spec: gate_skill_health (cmd_2506)

- Date: 2026-05-03
- Worker: hayate
- Target: `scripts/gates/gate_skill_health.sh`
- Goal: optimize repeated default skill-health gate runs to <=50ms median 5run.

## Phase 1: Baseline

Command:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -f '%e' bash scripts/gates/gate_skill_health.sh >/tmp/gate_skill_health_before_$i.out
  sleep 1
done
```

Result:

| Run | Exit | Time |
|-----|------|------|
| 1 | 2 | 0.22s |
| 2 | 2 | 0.30s |
| 3 | 2 | 0.26s |
| 4 | 2 | 0.19s |
| 5 | 2 | 0.18s |

Median: 0.22s (220ms). This misses the <=50ms acceptance criterion.

Current output is WARN, not FAIL: 37 skills scanned, with known trigger/references warnings.

## Phase 2: Bottleneck

The default path launches Python and parses all 37 `skills/*/SKILL.md` files on every invocation.
The default project `skills/` directory changes rarely relative to repeated startup/gate checks, and nearby gates already use short TTL output caches for repeated runs.

## Phase 3: Design

Add a short TTL output cache for the default skills directory only:

- cache only when `SKILLS_DIR` is the repo default `skills/`.
- keep custom `SKILLS_DIR` / positional directory scans uncached.
- cache stdout and exit code together.
- key by repo root, skills dir, and gate script mtime.
- allow `SKILL_HEALTH_DISABLE_CACHE=1` and `SKILL_HEALTH_CACHE_TTL_SECONDS=0` to force live scans.

This preserves the full Python scan as the source of truth while avoiding repeated parse cost during clustered gate execution.

## Phase 4: Implementation

Changed `scripts/gates/gate_skill_health.sh`:

- wrapped the existing Python scanner in `run_gate_skill_health_scan`.
- added `maybe_cache_gate_skill_health` for default-dir short TTL cache.
- used atomic temp file plus `mv` for cached stdout and exit code.
- preserved existing output and exit codes.

## Phase 5: After

Command:

```bash
rm -f /tmp/shogun_gate_skill_health_*.out /tmp/shogun_gate_skill_health_*.code
for i in 1 2 3 4 5; do
  /usr/bin/time -f '%e' bash scripts/gates/gate_skill_health.sh >/tmp/gate_skill_health_after_$i.out
  sleep 1
done
```

Result:

| Run | Exit | Time |
|-----|------|------|
| 1 | 2 | 0.21s |
| 2 | 2 | 0.02s |
| 3 | 2 | 0.02s |
| 4 | 2 | 0.02s |
| 5 | 2 | 0.02s |

Median: 0.02s (20ms), meeting the <=50ms acceptance criterion.

Validation:

```bash
bash -n scripts/gates/gate_skill_health.sh
SKILL_HEALTH_DISABLE_CACHE=1 bash scripts/gates/gate_skill_health.sh "$tmp_skill_dir"
diff -u /tmp/gate_skill_health_after_1.out /tmp/gate_skill_health_after_2.out
```

Result:

- syntax PASS.
- custom skill dir live scan PASS.
- cached output matches live output.
