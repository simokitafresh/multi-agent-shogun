# cmd_2090 CoDD Spec: `scripts/gates/gate_vercel_phase.sh`

- cmd: `cmd_2090`
- worker: `hayate`
- target: `scripts/gates/gate_vercel_phase.sh`
- date: `2026-04-18`

## Baseline

- command:
  - `bash scripts/gates/gate_vercel_phase.sh`
- current real-world output:
  - exits `1`
  - broken refs:
    - `context/cmd-chronicle.md:679 -> docs/research/gunshi_phase4_im`
    - `context/doc-style-guide.md:36 -> docs/research/cmd_XXX_*.md`
- before samples:
  - `3.05s`, `0.81s`, `0.83s`, `0.87s`, `0.88s`
- before median:
  - `0.87s`

## Bottleneck

- prior optimization already removed `resolve_context_bases` process substitution
- trace in current code showed remaining heavy work:
  - `find docs/research -type f` cache build on local repo: `~0.15s`
  - `find docs/research -type f` cache build on external DM-signal repo: `~0.40s`
  - `awk` ref extraction still ran once per context file (`43` files)
- direct `rg -n -o` benchmark over all context files:
  - `~0.11s`
- equivalent per-file `awk` loop benchmark:
  - `~0.39-0.41s`

## Plan

1. keep `FILE_CACHE` because `[[ -e ]]` per-ref lookups regressed
2. replace per-file `awk` extraction with one `rg -n -o --with-filename` pass
3. normalize ripgrep output to `file\tline\tref`
4. feed each extracted ref into the existing duplicate/broken-ref logic

## Implementation

- restored `build_file_cache()` and cached existence lookups
- replaced:
  - `while read context_file; check_context_file "$context_file"` + inner `awk`
- with:
  - `mapfile` context list once
  - single `rg -n -o --with-filename --no-heading 'docs/research/[A-Za-z0-9_./*-]+' "${context_files[@]}"`
  - single `awk -F:` rewrite to `file\tline\tref`
  - `check_ref_record()` for per-ref validation

## After

- after samples:
  - `0.61s`, `0.58s`, `0.56s`, `0.57s`, `0.55s`
- after median:
  - `0.57s`
- delta:
  - `0.87s -> 0.57s` (`-34.5%`)

## Validation

- `bash -n scripts/gates/gate_vercel_phase.sh`
- `bats tests/unit/test_gate_vercel_phase.bats`
- `bash scripts/gates/gate_vercel_phase.sh`
