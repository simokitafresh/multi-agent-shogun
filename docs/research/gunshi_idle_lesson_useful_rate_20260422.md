# Lesson Useful Rate Analysis — GP-211/GP-212 Effect Measurement

## Summary

GP-211 (useful rate threshold 15%→30%, decay 0.5→0.3) and GP-212 (target_files auto-set + backfill 80/641) were implemented on 2026-04-21. Initial measurement shows useful rate **decreased** from 34.9% to 16.9%.

## Data

| Period | USEFUL | NOT_USEFUL | Total Feedback | Useful Rate |
|--------|--------|------------|----------------|-------------|
| Before 2026-04-21 | 22 | 41 | 63 | 34.9% |
| Since 2026-04-21 | 27 | 133 | 160 | 16.9% |

| Period | Withheld | Injected | Feedback | Total |
|--------|----------|----------|----------|-------|
| Before | 1066 | 69 | 63 | 1198 |
| After | 689 | 118 | 160 | 967 |

Injection rate increased 5.8% → 12.2%. Feedback volume 2.5x. But NOT_USEFUL 3.2x increase.

## Root Cause: target_files absence in top NOT_USEFUL lessons

NOT_USEFUL Top 15 (since 2026-04-21):

| Lesson | NOT_USEFUL count | Has target_files? |
|--------|------------------|-------------------|
| L283 | 16 | NO |
| L481 | 8 | NO |
| L617 | 6 | YES (also 9 USEFUL — mixed) |
| L074 | 6 | YES |
| L229 | 5 | NO |
| L225 | 5 | NO |
| L636 | 4 | YES |
| L635 | 4 | YES |
| L634 | 4 | YES |
| L633 | 4 | YES |
| L632 | 4 | YES |
| L622 | 4 | NO |
| L262 | 4 | NO |
| L626 | 3 | NO |
| L625 | 3 | NO |

9/15 lessons lack target_files → injected via universal slot regardless of task relevance.

## Causal Chain

target_files absent → deploy_task.sh universal slot injection → irrelevant lessons reach ninja → NOT_USEFUL evaluation → useful rate drops

## Proposed Fix

1. Add target_files to top NOT_USEFUL lessons without it (L283, L481, L229, L225, L622, L262, L626, L625)
2. Consider YAML-native backfill (current script targets markdown format)
3. Recheck useful rate after target_files expansion

## Note

GP-211/212 have only 1 day of data. The rate difference may stabilize. But the target_files gap is a structural issue worth fixing regardless.
