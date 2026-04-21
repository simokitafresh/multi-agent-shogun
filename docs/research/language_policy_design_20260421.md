# Language Policy Design — Agent-Internal English Migration
<!-- cmd: session_20260421, author: shogun, reviewed_by: gunshi -->

## §1. Purpose

Reduce token consumption and improve LLM accuracy by writing agent-internal files in English.
Lord-facing outputs remain Japanese.

## §2. Rationale (with evidence)

| Factor | Japanese | English | Source |
|--------|:---:|:---:|--------|
| Tokens per YAML line | ~30 | ~12 | Measured: bulletin_board.yaml |
| Tokens per md line | ~52 | ~20 | Measured: context/infrastructure.md |
| Lost-in-the-Middle onset | ~87 JP lines | ~217 EN lines | Liu et al. 2024 TACL (2,600 tok threshold) |
| 80-line rule budget | 2,400 tok (near limit) | 960 tok (37% of limit) | 80 × 30 vs 80 × 12 |
| LLM reasoning accuracy | Lower (non-primary training language) | Higher (primary training language) | General LLM literature |

## §3. Language Boundary

### Lord-facing (Japanese — no change)
- `dashboard.md` — Lord reads directly
- `ntfy` notifications — Lord's mobile
- `gist` / `note.com` articles — Public content
- `lord_conversation.jsonl` — Lord's words verbatim
- `pending_decisions.yaml` — Lord's rulings verbatim
- `bulletin_board.yaml` — Visible through Shogun pane
- Shogun ↔ Lord dialogue — Direct conversation

### Agent-internal (migrate to English)

| Priority | Files | Current tok/line | Frequency | Impact |
|:---:|--------|:---:|----------|--------|
| 1 | `context/*.md` | 52 | Every session, multiple reads | **Highest ROI** |
| 2 | `instructions/*.md` | ~45 | Every session startup | High (compounding) |
| 3 | `CLAUDE.md` | ~40 | Every session auto-load | High (largest single file) |
| 4 | `projects/*.yaml` | ~35 | Per-project load | Medium |
| 5 | `lessons*.yaml` | ~30 | New entries from English | Medium |
| 6 | `queue/` internal YAML | ~30 | Auto-generated | Low (script changes needed) |
| 7 | `logs/` | ~25 | Append-only | Low (new entries only) |

### Complete file list (MECE)

**Phase 2 — High-impact (1 file)**
1. `CLAUDE.md`

**Phase 2 — Instructions (8 files)**
2. `instructions/shogun.md`
3. `instructions/shogun-procedures.md`
4. `instructions/karo.md`
5. `instructions/karo-procedures.md`
6. `instructions/gunshi.md`
7. `instructions/ashigaru.md`
8. `instructions/ashigaru-procedures.md`
9. `instructions/ashigaru-recon.md`

**Phase 3 — Context (30 files)**
10. `context/infrastructure.md`
11. `context/dm-signal.md`
12. `context/dm-signal-core.md`
13. `context/dm-signal-frontend.md`
14. `context/dm-signal-ops.md`
15. `context/dm-signal-research.md`
16. `context/growth-loop.md`
17. `context/karo-operations.md`
18. `context/training-cycle.md`
19. `context/gs-speedup-knowledge.md`
20. `context/gstack-knowledge.md`
21. `context/l2-okugi-progress.md`
22. `context/l3-robustness.md`
23. `context/robustness-verification-catalog.md`
24. `context/skill-design-rules.md`
25. `context/codd.md`
26. `context/database.md`
27. `context/auto-ops.md`
28. `context/google-classroom.md`
29. `context/milk.md`
30. `context/cmd-chronicle.md`
31. `context/senkyoku-log.md`
32. `context/checklist-shin-v2-registration.md`
33. `context/checklist-alm-registration.md`
34. `context/checklist-ward-fof-production.md`
35. `context/doc-style-guide.md`
36. `context/neo-design-exploration.md`
37. `context/oshio-comparison.md`
38. `context/ui-design-guide.md`
39. `context/gunshi-*.md` (15 files — updated by gunshi, migrate when naturally updated)

**Phase 3 — Projects (10 core + 16 sub-files)**
40. `projects/infra.yaml`, `projects/dm-signal.yaml`, `projects/auto-ops.yaml`, `projects/database.yaml`, `projects/mcas.yaml`
41. `projects/dm-signal/*.yaml` (7 files: api-endpoints, asset-inventory, database-detail, key-files, naming-portfolios, pipeline-blocks, recalculate-phases, shijin-design)
42. `projects/*/lessons.yaml` (6 PJ × lessons + 3 archive + 3 role-lessons = 16 files)

**Excluded (Japanese maintained)**
- `dashboard.md` — Lord reads directly
- `queue/bulletin_board.yaml` — Visible to Lord
- `queue/lord_conversation.jsonl` — Lord's words
- `queue/pending_decisions.yaml` — Lord's rulings
- `context/lord-conversation-index.md` — Lord conversation reference
- `memory/deepdive_*.md`, `memory/dialogue_*.md` — Lord quotes preserved in original

**Total: ~65 files for English migration**

### Boundary rules
- Lord quotes in lessons/deepdive: **keep original Japanese** (translation distorts intent)
- Section headers in context/*.md: English (§-number navigation unchanged). **§ numbers MUST NOT change** (referenced from other files)
- CLAUDE.md: English body, Japanese comments only where Lord annotation needed
- Lord quotes without 「」: If Lord's words appear without quotes in lessons/yaml, keep original Japanese. Rule: "Lord's direct speech = original JP. Agent's summary of Lord's speech = English OK"

## §4. Migration Plan

### Phase 1: New files only (immediate)
- All new `context/*.md`, `docs/research/*.md` written in English
- All new lesson entries in English
- All new instructions sections in English
- No existing file rewriting

### Phase 2: High-impact rewrites (next 2 weeks)
- `CLAUDE.md` — Full English rewrite (backup: CLAUDE.md.bak.20260421)
- `instructions/shogun.md` — English rewrite
- `instructions/karo.md` — English rewrite
- `instructions/gunshi.md` — English rewrite

### Phase 3: Context files (ongoing)
- Rewrite `context/*.md` to English as they are naturally updated
- No forced bulk migration — each update is an opportunity

### Phase 4: Queue/Logs (low priority)
- Modify scripts to output English where feasible
- Existing entries untouched

## §5. Migration Safety Protocol (mandatory per file)

### Step 1: Backup
```bash
cp {target_file} {target_file}.bak.jp.{YYYYMMDD}
```
Backup MUST exist before any edit. No exception.

### Step 2: English rewrite
Rewrite in English. Lord quotes stay in original Japanese.

### Step 3: 80-line block verification (突合) — MUST be done by a DIFFERENT ninja
The ninja who wrote the English version MUST NOT verify it. Assign a separate ninja.
Reason: Self-review introduces bias ("my translation is correct"). Same principle as testing.
Fallback when only 1 ninja idle: gunshi performs verification (reviewer role = third-party requirement met).
Compare backup (Japanese) vs rewritten (English) in **40-line blocks** (NOT 80):
```
Read backup lines 1-40 → Read rewritten lines 1-40 → verify meaning preserved
Read backup lines 41-80 → Read rewritten lines 41-80 → verify meaning preserved
... repeat until EOF
```
Why 40, not 80: JP 40 lines (≈2,080 tok) + EN 40 lines (≈800 tok) = ≈2,880 tok.
Both in context simultaneously stays near the 2,600 tok onset. 80-line blocks would be 5,760 tok = deep degradation zone.

### Step 3.5: Rollback procedure
If any verification fails or agents malfunction after migration:
```bash
cp CLAUDE.md.bak.jp.20260421 CLAUDE.md
```
One command. Instant rollback. No data loss.

### Step 4: Checklist sign-off
For each file, ALL must be YES before commit:
- [ ] Backup exists at {file}.bak.jp.{date}
- [ ] Every rule/procedure preserved (no omission)
- [ ] Lord quotes in original Japanese
- [ ] No meaning drift (80-line block verification complete)
- [ ] Line count delta < 20% (English should be similar or shorter, not bloated)

## §5.5. Post-Migration Verification

- [ ] Lord-facing outputs still Japanese (dashboard, ntfy, dialogue)
- [ ] 80-line rule + English = ~960 tok (well within 2,600 threshold)
- [ ] All 4 roles can recover from the English files
      (`CLAUDE.md` via `/clear`, generated `AGENTS.md` via `/new`; shogun/karo/gunshi/ninja — 1 each)
- [ ] No agent errors in first session after migration
- [ ] Rollback tested: `cp CLAUDE.md.bak.jp.20260421 CLAUDE.md` restores working state

### Verification Run: 2026-04-21 (`cmd_2224`, verifier = `hayate`)

- Backup presence re-checked: `CLAUDE.md.bak.jp.20260421` exists and is the expected 39 KB Japanese source snapshot.
- 40-line block verification completed from lines 1-563 of the backup against the current `CLAUDE.md`.
- The four role recovery flows in `CLAUDE.md` remained readable in English with no Japanese text left in the role sections:
  shogun Step 1-11, ninja Step 1-5, karo Step 1-7, gunshi Step 1-5.
- The generated Codex auto-load file `AGENTS.md` was also checked:
  `/new Recovery (shogun|ninja|karo|gunshi)` contains no Japanese text in the role sections.
- One additive section, `Bulletin Board Notification Targeting`, exists in the English file but does not replace or remove any section from the Japanese backup.
- Result: no recovery-flow edit was required; verification evidence only.

## §6. Risks

| Risk | Mitigation |
|------|-----------|
| Lord reads CLAUDE.md directly | Low frequency. Backup available. Japanese comments where needed |
| Translation errors in rules | Diff review against backup. Meaning preservation > literal translation |
| Agent confusion during transition | Phase 1 (new files only) has zero disruption. Phase 2+ is controlled |
| Deepdive loses nuance | Lord quotes kept in Japanese. Flow preserved |

## §7. Success Metric

Before: CLAUDE.md ~39KB, context/*.md avg ~52 tok/line
After: CLAUDE.md target ~25KB (-36%), context/*.md avg ~20 tok/line (-62%)

80-line read budget: 4,160 tok (JP) → 1,600 tok (EN) = **2.6x more information within safe zone**
