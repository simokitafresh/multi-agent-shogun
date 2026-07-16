# Review approval fingerprint cache — CoDD before/after

## Scope and invariant

- Target: `scripts/lib/review_approval.sh` through `scripts/review_approval.sh`.
- Frozen contract: report bytes + commit identity determine the fingerprint; Gunshi LGTM, Karo ACCEPT, SG7 generation, and manifest must bind to the same value.
- Cause: one Karo/Gunshi transition recomputed the same YAML-derived fingerprint at record, ready, and manifest boundaries (up to three parses).

## Before profile

Fixture: completed speed-report-shaped YAML with a 40-hex implementation commit. Each sample invokes `review_report_fingerprint` three times, matching the approval/ready/manifest path. 15 isolated samples.

| Metric | Before | Top repeated interval |
|---|---:|---|
| total sample wall | 16,723.9 ms | YAML/task scan in fingerprint x3 |
| p50 | 1,212.2 ms | fingerprint recomputation |
| p95 | 1,443.2 ms | fingerprint recomputation |

## After design

The first call computes the report SHA-256 and YAML-derived commit identity. Subshells share an invocation-scoped cache directory. Later calls still hash report bytes, then reuse the parsed fingerprint only for the exact path+content-hash key.

- Invalidation: any byte change creates a different SHA-256 key. No mtime/size shortcut is accepted.
- Lifetime: one `review_approval.sh` invocation; its EXIT trap removes cache files and directory.
- Concurrency: random/BASHPID-scoped directory; atomic temp-file rename publishes entries.
- Fail closed: missing report, invalid commit identity, stale SG7, and incomplete review state retain existing BLOCK behavior.

## After profile and SLO

| Metric | Before | After | Change |
|---|---:|---:|---:|
| total sample wall (n=15) | 16,723.9 ms | 6,798.7 ms | -59.3% |
| p50 | 1,212.2 ms | 492.0 ms | -59.4% |
| p95 | 1,443.2 ms | 598.9 ms | -58.5% |

Karo–Gunshi review-boundary SLO for this three-fingerprint fixture: p95 <= 750 ms on the same host. The regression entry point is `tests/unit/test_report_commit_identity.bats`; the cache test requires unchanged reuse and byte-change invalidation. Pipeline contract tests remain `tests/test_gate_report_format.bats`, `tests/unit/test_sg7_bundle_ssot.bats`, and `tests/unit/test_gate_gunshi_precheck_variation_contract.bats`.

## Causal verification

1. Prior design correctly bound every decision to fresh report content and commit identity.
2. Adding SG7 and manifest checks multiplied identical parsing within one immutable approval transition.
3. Content-hash-keyed, invocation-only reuse removes duplication while preserving the original byte-level invalidation boundary.

Origin: [[review approval repeated YAML parse]] -> [[content hash invocation cache]] -> [[faster Karo Gunshi handoff]]
