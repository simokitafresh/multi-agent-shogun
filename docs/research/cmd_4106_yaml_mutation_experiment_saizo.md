# cmd_4106 YAML mutation independent experiment (saizo)

- Fixed base: `75f7c530f59093db4562fbf0a21fbad3b2e75893`
- Isolation: `/tmp/saizo4106.khIBxS/repo` (ext4) and `.saizo4106.hOyUE6/repo` (WSL 9p), both detached clones.
- Fixture: `queue/tasks/saizo.yaml`, 6,945 bytes. Production scripts/gates/hooks were not modified.

## 1. `yaml_field_set` sequential calls versus batch

The same 14 scalar fields were written from a fresh fixture for every run.

| filesystem | candidate | run wall_ms | median wall_ms | rc |
|---|---:|---:|---:|---:|
| ext4 | 14 sequential calls | 2053, 4457, 2086 | 2086 | 0,0,0 |
| ext4 | 1 batch call | 1142, 1201, 1235 | 1201 | 0,0,0 |
| 9p | 14 sequential calls | 3260, 3169, 3553 | 3260 | 0,0,0 |
| 9p | 1 batch call | 1583, 1506, 1732 | 1583 | 0,0,0 |

- Batch saving: ext4 885ms (42.4%); 9p 1,677ms (51.4%).
- Generated task comparison, sequential versus batch: byte differences 0; semantic differences 0; byte equality true; parsed YAML equality true on both filesystems.
- One rejected probe attempted scalar `target_path`; the helper correctly blocked because this field must be a YAML list. It is excluded from the valid 14-field timing above.

## 2. Task-mutation phases, independently executed

Every phase started from a fresh fixture. `rc=0` for all 14 phase/filesystem experiments.

| phase | ext4 wall_ms | 9p wall_ms | 9p/ext4 | task semantic differences from fixture |
|---|---:|---:|---:|---:|
| entrance_gates | 65 | 298 | 4.58x | 0 |
| scout_gate | 79 | 287 | 3.63x | 0 |
| task_modifiers | 250 | 568 | 2.27x | 0 |
| related_lessons | 2463 | 4340 | 1.76x | 0 |
| semantic_context | 635 | 747 | 1.18x | 0 (NO_MATCH) |
| memory_context | 418 | 609 | 1.46x | 0 (no hits) |
| report_publication | 943 | 2389 | 2.53x | report artifact generated; task path already canonical |

`related_lessons` rewrote formatting (6,945→6,957 bytes) while parsed content remained identical: semantic difference count 0. This is needless task-file byte churn in the measured no-new-lesson case.

## 3. Dominant term and candidate disposition

1. **Adopt/retain batch mutation**: output is byte- and semantic-identical and cuts valid 9p scalar mutation by 1,677ms median.
2. **Optimize `related_lessons` first**: it is the dominant isolated phase at 4,340ms on 9p and performs a byte rewrite despite semantic delta 0 in this fixture. Candidate: detect unchanged parsed section/output and skip atomic publication. Adoption requires a focused implementation task because this reconnaissance may not edit production code.
3. **Optimize report publication second**: 2,389ms on 9p, 2.53x ext4. Candidate: generate/validate off-9p and publish once, while preserving same-filesystem atomic replacement for the final target. Requires implementation validation.
4. **Reject moving the live task YAML itself to ext4**: atomic replacement must remain on the target filesystem and queue YAML is the shared SSOT. Ext4 is suitable for bounded temporary computation, not as a replacement SSOT.
5. **Defer semantic/memory optimization**: both were measured, but together cost 1,356ms on 9p and are not the dominant term. Their outputs were no-op for this fixture.
6. **Do not optimize entrance/scout gates first**: combined 585ms on 9p; measured but lower leverage than mutation/publication.

All candidates were measured. No generated-task semantic differences were found; the valid sequential/batch candidate also had zero byte differences.
