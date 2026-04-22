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

### Complete file list (MECE — translation targets only; Phase 3 script modifications listed in §4)

**Phase 2 — CLAUDE.md (DONE)**
1. `CLAUDE.md`

**Phase 4 — Instructions (8 files)**
2. `instructions/shogun.md`
3. `instructions/shogun-procedures.md`
4. `instructions/karo.md`
5. `instructions/karo-procedures.md`
6. `instructions/gunshi.md`
7. `instructions/ashigaru.md`
8. `instructions/ashigaru-procedures.md`
9. `instructions/ashigaru-recon.md`

**Phase 4 — Context (30 files)**
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

**Phase 4 — Projects (10 core + 16 sub-files)**
40. `projects/infra.yaml`, `projects/dm-signal.yaml`, `projects/auto-ops.yaml`, `projects/database.yaml`, `projects/mcas.yaml`
41. `projects/dm-signal/*.yaml` (10 files: api-endpoints, asset-inventory, database-detail, key-files, lessons, lessons_archive, naming-portfolios, pipeline-blocks, recalculate-phases, shijin-design)
42. `projects/*/lessons*.yaml` (6 PJ lessons + 3 archive + 3 role-lessons = 12 files)

**Excluded (Japanese maintained)**
- `dashboard.md` — Lord reads directly
- `queue/bulletin_board.yaml` — Visible to Lord
- `queue/lord_conversation.jsonl` — Lord's words
- `queue/pending_decisions.yaml` — Lord's rulings
- `context/lord-conversation-index.md` — Lord conversation reference
- `memory/deepdive_*.md`, `memory/dialogue_*.md` — Lord quotes preserved in original
- `memory/*.md` (other 17 project memory files) — Lord's principles/feedback in original Japanese
- `MEMORY.md` (auto-memory index) — Shogun auto-loaded, Japanese maintained (Lord's words preserved)

**Total: ~65 files for English migration**

### Boundary rules
- Lord quotes in lessons/deepdive: **keep original Japanese** (translation distorts intent)
- Section headers in context/*.md: English (§-number navigation unchanged). **§ numbers MUST NOT change** (referenced from other files)
- CLAUDE.md: English body, Japanese comments only where Lord annotation needed
- Lord quotes without 「」: If Lord's words appear without quotes in lessons/yaml, keep original Japanese. Rule: "Lord's direct speech = original JP. Agent's summary of Lord's speech = English OK"

## §4. Migration Plan

### Prioritization Principle (Lord ruling 2026-04-22)

**Visibility-based ordering**: Lord-invisible files first, Lord-visible files last (or never).

Rationale:
1. **Zero risk** — Lord never reads agent-internal files, so English has no UX impact
2. **Script modification = permanent compound interest** — one change makes ALL future outputs English
3. **High frequency** — inbox/task/report are read/written dozens of times per cmd

| Priority | Criterion |
|:---:|----------|
| Highest | Lord-invisible + script output (modify once → all future outputs English) |
| High | Lord-invisible + static files (translate once → read N times per session) |
| Keep JP | Lord-visible (`dashboard.md`, `ntfy`, `bulletin_board`, `lord_conversation`, `pending_decisions`) |

### Phase 1: New files only (immediate)
- All new `context/*.md`, `docs/research/*.md` written in English
- All new lesson entries in English
- All new instructions sections in English
- No existing file rewriting

### Phase 2: CLAUDE.md (DONE)
- `CLAUDE.md` — Full English rewrite (backup: CLAUDE.md.bak.jp.20260421) **DONE 2026-04-21**

### Phase 3: Lord-invisible script outputs (highest compound interest)
Scripts that generate LLM-to-LLM communication. One modification = all future outputs English.

| Sub | Script | Output | Reads/cmd |
|:---:|--------|--------|:---------:|
| 3a | `inbox_write.sh` | `queue/inbox/*.yaml` messages | ~10-20 |
| 3b | `deploy_task.sh` | `queue/tasks/*.yaml` task assignments | ~2-6 |
| 3c | Report YAML templates | `queue/reports/*.yaml` ninja reports | ~2-6 |
| 3d | `karo_workarounds` logging | `logs/karo_workarounds.yaml` | ~1-5 |
| 3e | `gunshi_review_log` / `gp_tracker` | `logs/gunshi_*.yaml` | ~1-3 |

### Phase 4: Lord-invisible static files (high impact)
- `instructions/*.md` (8 files) — read every recovery, ~45 tok/line JP → ~20 tok/line EN
- `projects/*.yaml` (10+ files) — core knowledge, read per-project load
- `context/*.md` (30 files) — rewrite as naturally updated, or batch if idle ninjas available

### Phase 5: Lessons (medium, new entries only)
- `projects/*/lessons.yaml` — new entries in English. Existing entries untouched (push-style delivery limits impact)
- `projects/infra/lessons_{role}.yaml` — new entries in English

### Lord-visible (keep Japanese, no migration)
- `dashboard.md` — Lord reads directly
- `ntfy` notifications — Lord's mobile
- `queue/bulletin_board.yaml` — visible through Shogun pane
- `queue/lord_conversation.jsonl` — Lord's words verbatim
- `queue/pending_decisions.yaml` — Lord's rulings verbatim
- `context/lord-conversation-index.md` — Lord conversation reference
- `gist` / `note.com` articles — public content
- Shogun ↔ Lord dialogue — direct conversation

## §5. Migration Safety Protocol

### Scope: Phase 3 (script modifications) vs Phase 4-5 (file translations) require different protocols.

### §5a. Script modification protocol (Phase 3 — code changes, not translations)
1. `cp {script} {script}.bak.{YYYYMMDD}` — backup before edit
2. Modify script to output English (string literals, templates, format strings)
3. `bats tests/` — ALL tests must pass. Script changes can break gates/hooks (cmd_1975 proven)
4. Run the script once manually and diff output against backup: `diff <(old_output) <(new_output)` — verify only language changed, not structure
5. Commit + push

### §5b. File translation protocol (Phase 4-5 — mandatory per file)

### Step 1: Backup
```bash
cp {target_file} {target_file}.bak.jp.{YYYYMMDD}
```
Backup MUST exist before any edit. No exception.

### Step 2: English rewrite
Rewrite in English. Lord quotes stay in original Japanese.

### Step 3: 40-line block verification (突合) — MUST be done by a DIFFERENT ninja
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
- [ ] No meaning drift (40-line block verification complete)
- [ ] Line count delta < 20% (English should be similar or shorter, not bloated)
- [ ] Internal cross-reference consistency: if file contains rules that reference other sections (e.g., exception lists vs Recovery procedures), verify both sides match
- [ ] bats tests pass (`bats tests/` — CI green). Proven risk: cmd_1975 hook rewrite → CI RED
- [ ] No script grep patterns broken: `grep -rn` for Japanese strings in `scripts/` that reference the migrated file's content

## §5.5. Post-Migration Verification

- [ ] Lord-facing outputs still Japanese (dashboard, ntfy, dialogue)
- [ ] 80-line rule + English = ~960 tok (well within 2,600 threshold)
- [ ] All 4 roles can recover from the English files
      (`CLAUDE.md` via `/clear`, generated `AGENTS.md` via `/new`; shogun/karo/gunshi/ninja — 1 each)
- [ ] No agent errors in first session after migration
- [ ] Rollback tested: `cp CLAUDE.md.bak.jp.20260421 CLAUDE.md` restores working state
- [ ] 80-line exception list covers all files marked mandatory/full-read in Recovery procedures

### Verification Run: 2026-04-21 (`cmd_2224`, verifier = `hayate`)

- Backup presence re-checked: `CLAUDE.md.bak.jp.20260421` exists and is the expected 39 KB Japanese source snapshot.
- 40-line block verification completed from lines 1-563 of the backup against the current `CLAUDE.md`.
- The four role recovery flows in `CLAUDE.md` remained readable in English with no Japanese text left in the role sections:
  shogun Step 1-11, ninja Step 1-5, karo Step 1-7, gunshi Step 1-5.
- The generated Codex auto-load file `AGENTS.md` was also checked:
  `/new Recovery (shogun|ninja|karo|gunshi)` contains no Japanese text in the role sections.
- One additive section, `Bulletin Board Notification Targeting`, exists in the English file but does not replace or remove any section from the Japanese backup.
- Result: no recovery-flow edit was required; verification evidence only.

### Post-Migration Audit: 2026-04-22 (gunshi, Lord-directed)

80-line exception list (CLAUDE.md L389) vs Recovery procedure cross-validation revealed 4 holes:
1. **HIGH**: `projects/{id}.yaml` (482 lines, core knowledge incl. PI) missing from exception list → PI loss risk. **Fixed.**
2. **MED**: `projects/{id}/lessons.yaml` (4,229 lines) missing → push-style delivery (deploy_task.sh embeds details), no full-read needed. No fix required.
3. **LOW**: Exception list reason text assumed Japanese token counts only → updated to cover both JP/EN. **Fixed.**
4. **LOW**: `lessons_{role}.yaml` path pattern ambiguous (missing `projects/infra/` prefix) → clarified. **Fixed.**

Root cause (なぜなぜ7回):
- The exception list and Recovery procedures are two independent manually-maintained lists in CLAUDE.md with no cross-validation.
- Checklist Step 4 lacked "internal cross-reference consistency" check. Now added.
- Gunshi review lacked "declaration (should) vs enforcement (must) gap detection" SG. Identified as automation target.

## §5c. Shogun CMD Creation Guide — Lessons from CLAUDE.md migration (2026-04-22)

These patterns were extracted from actual failures during Phase 2. Apply to all future migration CMDs.

### Principle: One hole found = search the entire class

When the 80-line exception list was missing `projects/{id}.yaml`, the initial fix added only that one file. But the root cause was structural (manually-maintained independent lists). 7 total holes were found by searching the class. **Every migration CMD AC should include: "Are there other instances of the same pattern?"**

### CMD templates by Phase

**Phase 3 CMD (script modification)** — use §5a protocol
```
AC1: Backup {script}.bak.{date}
AC2: Modify script output to English (string literals only, no logic change)
AC3: bats tests/ ALL PASS
AC4: Manual run + diff output vs backup (structure unchanged, only language differs)
AC5: grep -rn for Japanese strings in scripts/ that reference this script's output → 0 matches after migration
AC6: commit+push
```

**Phase 4 CMD (file translation)** — use §5b protocol
```
AC1: Backup {file}.bak.jp.{date} exists
AC2: English rewrite (Lord quotes in original JP)
AC3: 40-line block verification by DIFFERENT ninja (書き手≠検証者)
AC4: Internal cross-reference check: rules in this file match enforcement mechanisms elsewhere
AC5: bats tests/ PASS
AC6: Line count delta < 20%
AC7: commit+push
```

### Pitfall catalog (proven failures, not hypothetical)

| # | Pitfall | How it happened | AC to prevent |
|---|---------|----------------|---------------|
| 1 | **Declaration ≠ enforcement** | Recovery said "mandatory" but 80-line exception list didn't include the file → file actually truncated | AC: "Every mandatory/full-read file in Recovery is in exception list" |
| 2 | **Title ≠ body** | Step 3 title said "80-line block" but body said "40-line block" → ninja followed title | AC: verify section titles match content |
| 3 | **Claimed count ≠ actual count** | "7 files" but 8 listed, "=16" but 6+3+3=12 | AC: `ls \| wc -l` to verify every file count claim |
| 4 | **Filename typo in docs** | `.bak.20260421` written but actual file is `.bak.jp.20260421` → rollback would fail | AC: `ls` the exact filename before writing it in docs |
| 5 | **One protocol for two types** | Translation protocol (40-line block) applied to script modification → wrong verification | AC: check Phase type (§5a vs §5b) before writing ACs |
| 6 | **Pattern ≠ explicit list** | `deepdive` as exception relied on naming convention, not enumeration → new deepdive file could be missed | AC: enumerate files explicitly, not by pattern alone |
| 7 | **Stale cross-reference** | §3 Phase labels stayed "Phase 2/3" after §4 renumbered to "Phase 3/4/5" | AC: after any section renumber, grep all §/Phase references |
| 8 | **Tok/line rate mismatch** | §2 said CLAUDE.md=40tok/line, §7 used 52tok/line (context rate) → wrong multiplier | AC: cite the source row from §2 when using tok/line numbers |

### The meta-lesson

The 80-line exception list had 7 holes because it was reviewed for **translation fidelity** (JP→EN match) but not for **internal consistency** (exception list × Recovery procedures). Translation CMDs must have **two independent verification axes**: (1) content fidelity and (2) cross-reference integrity.

## §6. Risks

| Risk | Mitigation |
|------|-----------|
| Lord reads CLAUDE.md directly | Low frequency. Backup available. Japanese comments where needed |
| Translation errors in rules | Diff review against backup. Meaning preservation > literal translation |
| Agent confusion during transition | Phase 1 (new files only) has zero disruption. Phase 2+ is controlled |
| Deepdive loses nuance | Lord quotes kept in Japanese. Flow preserved |
| Internal rule consistency drift | Step 4 checklist now includes cross-reference check. Proven by 80-line exception list audit (4 holes found post-migration) |
| Script grep patterns break silently | Step 4 now includes Japanese grep audit in `scripts/`. Silent failures = worst pattern (no error, wrong result) |

## §7. Success Metric

Before: CLAUDE.md ~39KB, context/*.md avg ~52 tok/line
After: CLAUDE.md target ~25KB (-36%), context/*.md avg ~20 tok/line (-62%)

80-line read budget (CLAUDE.md): 3,200 tok (JP, ~40 tok/line) → 960 tok (EN, ~12 tok/line) = **3.3x more information within safe zone**
80-line read budget (context/*.md): 4,160 tok (JP, ~52 tok/line) → 1,600 tok (EN, ~20 tok/line) = **2.6x**

Future consideration: when all files are English, the 80-line threshold could safely increase to ~200 lines (200 × 12 = 2,400 tok, within 2,600 threshold). Evaluate after Phase 3 completion.
