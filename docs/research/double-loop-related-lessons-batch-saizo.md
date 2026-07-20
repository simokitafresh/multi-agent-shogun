# related_lessons batch double-loop experiment (saizo)

- Base: `b715cab59de647b45d8f6d3c7db7b8d23a6dfa13`
- Isolated clone: `.saizo4106.hOyUE6/repo`
- Fixture: current `queue/tasks/saizo.yaml`, 12,561 bytes before injection.
- Each candidate used three fresh copies. The existing `inject_related_lessons` implementation was executed without production edits.

## Candidates and phase wall time

| candidate | cache/task placement | run wall_ms | median wall_ms | all rc |
|---|---|---:|---:|---:|
| sequential | separate cold ext4 cache per call; task on 9p | 5234, 2967, 2596 | 2967 | 0 |
| batch | one shared ext4 lesson snapshot/cache across the three-call batch; task on 9p | 2867, 2772, 2492 | 2772 | 0 |
| ext4 snapshot | shared ext4 lesson cache and task working snapshot on ext4, then one copy to isolated 9p clone | 2680, 2810, 2992 | 2810 | 0 |

The batch candidate is fastest by median: 2,967→2,772ms, a 195ms (6.6%) reduction. Its fastest observed run was 2,492ms versus sequential's fastest 2,596ms. Moving the task working copy to ext4 did not improve the median beyond batch alone (2,810ms).

## Output contract

The sequential run 1 output is the reference. It contains three lessons: `L147`, `L548`, and `L088`.

| candidate/runs | output bytes | byte differences | parsed task semantic differences | lesson missing | lesson extra |
|---|---:|---:|---:|---:|---:|
| sequential 1-3 | 12,675 each | 0 | 0 | 0 | 0 |
| batch 1-3 | 12,675 each | 0 | 0 | 0 | 0 |
| ext4 snapshot 1-3 | 12,675 each | 0 | 0 | 0 | 0 |

All nine outputs have SHA-256 prefix `37c8cf753b0a`. Comparison includes lesson ID, summary, and detail, not only counts.

## Adoption disposition

- **Propose batch/shared immutable lesson snapshot**: fastest median and all output contract deltas are zero. The implementation checkpoint must preserve source fingerprint invalidation and one final same-filesystem atomic task publication.
- **Reject ext4 task snapshot as the primary optimization**: output is correct, but median 2,810ms is 38ms slower than batch and copying the live task away from its SSOT adds no measured benefit.
- **Keep sequential as baseline only**: correct output, but 195ms slower median and a 5,234ms cold outlier.

The improvement is smaller than the earlier 4,340ms single observation because the current base already contains lesson snapshot caching. This experiment therefore supports reuse/batching of that snapshot, not a replacement of queue task atomicity.
