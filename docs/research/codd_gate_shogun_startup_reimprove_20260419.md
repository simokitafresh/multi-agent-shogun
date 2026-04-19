# CoDD Spec: gate_shogun_startup.sh Re-improve

Date: 2026-04-19
Target: `scripts/gates/gate_shogun_startup.sh`
Task: `cmd_2102_impl`

## 1. Baseline

- Measurement method: `/usr/bin/time -f '%e' bash scripts/gates/gate_shogun_startup.sh >/dev/null` x5
- Before samples: `1.06`, `1.20`, `1.28`, `1.29`, `1.30`
- Median before: `1.28s`
- Target: `<= 0.50s` or `>= 30%` reduction

## 2. Subprocess Hotspots

### Gate 14: gunshi context listing

Current path:
- `find context -name 'gunshi-*.md'`
- per file: `head -5`
- per file: `grep -m1 '^#'`
- per file: `sed 's/^# *//'`
- per file: `date -r`
- per file: `basename`

Observed comparison:
- Current shell pipeline: `0.27s`
- Single Python pass: `0.13s`

Root cause:
- 15 files x repeated short-lived subprocesses on WSL2 `/mnt/c`

Plan:
- Replace per-file shell pipeline with one Python pass that emits `name / mtime / title`

### Gate 15: orphan context detection

Current path:
- `cat` of knowledge-map sources into temp file
- for each `context/*.md`:
- `basename`
- `grep -q` against temp file
- orphan only: `head -5`, `grep -m1`, `sed`, `date -r`, `git log -1`

Observed comparison:
- Current per-file grep loop: `0.54s`
- Single Python pass: `0.09s`

Root cause:
- 44 context files x per-file `grep`/metadata subprocesses
- repeated short-lived process startup dominates actual work

Plan:
- Read knowledge-map sources in one Python process
- Check filename membership in-memory
- Emit only orphan metadata back to shell
- Keep `git log -1` only for actual orphan files

## 3. Safety Constraints

- Preserve output semantics for Gate 14 / Gate 15
- Preserve orphan threshold (`>= 3` => `ALERT`)
- Preserve `MISSING` source reporting
- Do not widen scope beyond `gate_shogun_startup.sh`
- Validate with existing bats coverage before commit

## 4. Expected Effect

- Gate 14 save: about `0.14s`
- Gate 15 save: about `0.45s`
- Combined expected reduction: about `0.59s`
- Expected after: about `0.69s`

## 5. Changed Call Sites

Reduced subprocess-heavy call sites:
- `find` + `head` + `grep` + `sed` + `date` + `basename` for gunshi listing
- `cat` temp build + per-context `grep -q` + orphan metadata shell pipeline

Retained on purpose:
- `git log -1` for orphan author lookup only
- existing sub-gates (`gate_loop_health.sh`, `gate_lesson_health.sh`, etc.)
