<!-- last_updated: 2026-04-09 -->
<div align="center">

# multi-agent-shogun

**Command your AI army like a feudal warlord.**

Run 9 AI coding agents in parallel through a Sengoku hierarchy: a **mixed Claude Code + Codex formation** coordinated by YAML, tmux, and event-driven mailboxes.

**Talk coding, not vibe coding. Speak from your terminal, phone, or Android companion app.**

[![GitHub Stars](https://img.shields.io/github/stars/simokitafresh/multi-agent-shogun?style=social)](https://github.com/simokitafresh/multi-agent-shogun)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Formation](https://img.shields.io/badge/formation-mixed%20CLI%20from%20config%2Fsettings.yaml-ff6600?style=flat-square)](https://github.com/simokitafresh/multi-agent-shogun)
[![Runtime](https://img.shields.io/badge/runtime-live%20YAML%20%2B%20tmux-2d7d46?style=flat-square)](https://github.com/simokitafresh/multi-agent-shogun)
[![Shell](https://img.shields.io/badge/Shell%2FBash-100%25-green)]()

[English](README.md) | [日本語](README_ja.md)

</div>

<!-- <p align="center">
  <img src="assets/screenshots/tmux_shogun_9panes.png" alt="multi-agent-shogun: 9 panes running in parallel" width="800">
</p> -->

<p align="center"><i>One Karo coordinating 6 ninja + 1 gunshi (military advisor) in the live mixed-CLI formation defined by <code>config/settings.yaml</code> — real session, no mock data.</i></p>

---

## What is this?

**multi-agent-shogun** lets one human (the Lord) command **9 CLI agents** on tmux — 1 Shogun, 1 Karo, 1 Gunshi, 6 Ninja — using nothing but YAML files and file watchers, verify results with binary checks, and feed every failure back into lessons, gates and tests so the system grows by itself. It runs vendor CLIs as they are (Claude Code / Codex CLI) instead of APIs, with per-CLI hooks and gates (multi-CLI).

### Formation (2026-08-27; `config/settings.yaml` is the single source of truth)

| Role | window / pane | CLI · model | What it does |
|---|---|---|---|
| **Lord** (you) | terminal | human | Gives orders and rulings; talks to Shogun; reads dashboard / artifact directly |
| **Shogun** | `main` | Claude Code (Fable 5) | Turns orders into cmds (YAML), passes the quality gates, delegates to Karo. Every 30 min: primary checks, unblocking, battle-status artifact. Never digs into code itself — files recon cmds |
| **Karo** | `agents` pane 1 | Codex (gpt-5.6-sol) | Splits cmds into tasks and deploys Ninja. Receives reports, runs the GATE, converges and pushes one commit at a time. Deploys hotfix / ci_fix without a Shogun cmd |
| **Gunshi** | `agents` pane 2 | Claude Code (Opus 4.6, 1M) | First-pass reviewer of cmd drafts and report YAMLs (SG7 protocol). LGTM → Karo ACCEPT, FAIL → sent back. Persists analyses when idle and independently verifies Shogun's self-checks |
| **Ninja ×6** hayate / kagemaru / hanzo / saizo / kotaro / tobisaru | `agents` pane 3-8 | Codex (gpt-5.6-luna high) | Execute the task YAML's acceptance criteria at top quality, isolated in a task worktree → scoped commit → report YAML. No memory across tasks (/clear every time) |

```
        Lord (you)
          │ orders in plain language
          ▼
   ┌──────────────┐        ┌──────────────┐
   │    SHOGUN     │──cmd──▶│     KARO     │
   │ file, delegate │        │ split, deploy │
   │ 30-min loop    │        │ GATE, push    │
   └──────────────┘        └──────┬───────┘
          ▲                        │ task YAML + inbox nudge
          │ review verdicts         ▼
   ┌──────────────┐     ┌─┬─┬─┬─┬─┬─┐
   │    GUNSHI     │◀────│1│2│3│4│5│6│  NINJA ×6 (isolated task worktrees)
   │  SG7 review   │reports└─┴─┴─┴─┴─┴─┘
   └──────────────┘
   The chain: Lord → Shogun → Karo → Ninja (no branches). Learning flows back along the same chain (lesson_candidate → lesson → gate → test)
```

**Why use it**
- One order moves 9 agents and control returns immediately; report → review → GATE → notification needs no human hands
- Agents talk through **YAML + inotify** — no API orchestration bill (flat-rate CLI subscriptions)
- Built-in **cmd quality gates (82 checks), two-stage review, GATE, reflux and lesson retirement**: every failure gets embedded in the next environment
- **Three-layer memory** (memory DB / semantic index / Obsidian causal links) so a `/clear` restarts stronger than before
- ntfy, the Android app and the battle-status artifact let you command from anywhere

---

## Live State Sources

| Metric | Value (measured 2026-08-27) |
|---|---|
| cmds issued | 4,410 |
| GATE CLEAR | 49 today (`logs/gate_metrics.log`) |
| git history | 16,555 commits since 2026-02-09 |
| `git status` | 84 ms on ext4 (60–120 s on the old 9p mount) |
| one deployment (`deploy_task`) | 23 s (199–397 s before the move) |
| cmd end-to-end (deploy → GATE CLEAR), median | 31 min (4–16 min of it is human-side review round trips) |

Sources: `logs/gate_metrics.log`, `logs/deploy_task.log`, `docs/research/ext4_speed_rebaseline_20260827.md`.

---

## Why Shogun?

Most multi-agent frameworks burn API tokens on coordination. Shogun doesn't.

| | Claude Code `Task` tool | LangGraph | CrewAI | **multi-agent-shogun** |
|---|---|---|---|---|
| **Architecture** | Subagents inside one process | Graph-based state machine | Role-based agents | Feudal hierarchy via tmux |
| **Parallelism** | Sequential (one at a time) | Parallel nodes (v0.2+) | Limited | **6 ninja + 1 gunshi** |
| **Coordination cost** | API calls per Task | API + infra (Postgres/Redis) | API + CrewAI platform | **Zero** (YAML + tmux) |
| **Observability** | Claude logs only | LangSmith integration | OpenTelemetry | **Live tmux panes** + dashboard |
| **Skill discovery** | None | None | None | **Bottom-up auto-proposal** |
| **Setup** | Built into Claude Code | Heavy (infra required) | pip install | Shell scripts |

### What makes this different

**Zero coordination overhead** — Agents talk through YAML files on disk. The only API calls are for actual work, not orchestration. Run 9 agents and pay only for 9 agents' work.

**Full transparency** — Every agent runs in a visible tmux pane. Every instruction, report, and decision is a plain YAML file you can read, diff, and version-control. No black boxes.

**Battle-tested hierarchy** — The Shogun → Karo → Ninja chain of command prevents conflicts by design: clear ownership, dedicated files per agent, event-driven communication, no polling.

---

## What Makes This Fork Different

| Capability | What it means in this repo |
|---|---|
| **7-layer knowledge system** | System rules, role instructions, project core, project lessons, live YAML state, Vercel-style context indexes, and Memory MCP each have a distinct home |
| **Vercel-style context** | `context/*.md` is an index layer; deep investigations move into `docs/research/` and are linked back instead of duplicated |
| **Lesson cycle** | Lessons are injected into tasks, referenced during work, scored after GATE, and auto-deprecated when they stop helping |
| **GATE system** | `cmd_complete_gate.sh`, `gate_cmd_state.sh`, and `gate_lesson_health.sh` block false-done reports and stale operational state |
| **Karo snapshot** | `queue/karo_snapshot.txt` rebuilds real-time formation state after recovery or compaction |
| **Pending decisions** | `queue/pending_decisions.yaml` tracks unresolved rulings that still need a human or Shogun decision |
| **Cmd chronicle** | `context/cmd-chronicle.md` keeps the recent command history cheap to reload |
| **Android companion** | `android/` ships a Kotlin + Jetpack Compose app for SSH control, dashboard viewing, and ntfy-driven mobile workflows |

---

## Why CLI (Not API)?

Most AI coding tools charge per token. Running 9 Opus-grade agents through the API costs **$100+/hour**. CLI subscriptions flip this:

| | API (Per-Token) | CLI (Flat-Rate) |
|---|---|---|
| **9 agents × Opus** | ~$100+/hour | ~$200/month |
| **Cost predictability** | Unpredictable spikes | Fixed monthly bill |
| **Usage anxiety** | Every token counts | Unlimited |
| **Experimentation budget** | Constrained | Deploy freely |

**"Use AI recklessly"** — With flat-rate CLI subscriptions, deploy 9 agents without hesitation. The cost is the same whether they work 1 hour or 24 hours. No more choosing between "good enough" and "thorough" — just run more agents.

### CLI and Instruction Build System

The runtime now supports a **mixed CLI formation**. Claude agents autoload `CLAUDE.md`, Codex agents autoload `AGENTS.md`, and both are generated from the same shared instruction sources:

```
instructions/
├── common/              # Shared rules (all CLIs)
├── cli_specific/        # CLI-specific tool descriptions
│   ├── claude_tools.md  # Claude Code tools & features
│   └── copilot_tools.md # GitHub Copilot CLI tools & features
└── roles/               # Role definitions (shogun, karo, ninja)
    ↓ build
CLAUDE.md / AGENTS.md / copilot-instructions.md  ← Generated per CLI
```

One source of truth, zero sync drift. Change a rule once, then rebuild and both Claude/Codex instruction surfaces stay aligned.

---

## Bottom-Up Skill Discovery

This is the feature no other framework has.

As ninja execute tasks, they **automatically identify reusable patterns** and propose them as skill candidates. The Karo aggregates these proposals in `dashboard.md`, and you — the Lord — decide what gets promoted to a permanent skill.

```
Ninja finishes a task
    ↓
Notices: "I've done this pattern 3 times across different projects"
    ↓
Reports in YAML:  skill_candidate:
                     found: true
                     name: "api-endpoint-scaffold"
                     reason: "Same REST scaffold pattern used in 3 projects"
    ↓
Appears in dashboard.md → You approve → Skill created in .claude/commands/
    ↓
Any agent can now invoke /api-endpoint-scaffold
```

Skills grow organically from real work — not from a predefined template library. Your skill set becomes a reflection of **your** workflow.

---

## Quick Start

> Derived from the actual `first_setup.sh` / `shutsujin_departure.sh` / `config/settings.yaml` as of 2026-08-27. Supported: **WSL2 (Ubuntu) or native Linux**. Put the repository on **ext4** (e.g. under `~/`). A Windows drive (`/mnt/c/...`) goes through the 9p filesystem, where `git status` takes 60–120 s — unusable (see "Speed").

### Step 1: Prerequisites

| Tool | Purpose | Check |
|---|---|---|
| git, tmux, jq, curl, flock, timeout, setsid, crontab | base | `first_setup.sh` checks and tries `apt` for missing ones |
| node/npm (nvm recommended), python3 | Claude Code / Codex CLI, gates | same |
| gh (GitHub CLI), inotify-tools, bats | CI checks, inbox watcher, tests | same |

### Step 2: Get the code (git clone or ZIP)

```bash
# A. git (normal)
git clone https://github.com/<owner>/multi-agent-shogun.git ~/multi-agent-shogun

# B. ZIP (no GitHub access from the box)
#   "Code → Download ZIP", extract on ext4, then inside the folder:
git init && git add -A && git commit -m "import" && git remote add origin https://github.com/<owner>/multi-agent-shogun.git
```

A ZIP has no `.git`; the gates assume git, so route B creates a minimal repository with the line above.

### Step 3: First-time setup

```bash
cd ~/multi-agent-shogun
bash first_setup.sh        # idempotently checks/installs deps, venv, Codex CLI, config, directories, Memory MCP
source ~/.bashrc           # apply PATH
```

- The only prompt is "install the native build? [Y/n]".
- `config/settings.yaml` is generated **only if absent**; an existing one is kept. Set the ntfy topic, CLI and models by editing `config/settings.yaml` (there is no interactive wizard).
- Duration depends on network and what needs installing.

### Step 4: First-time authentication (once, with your own accounts)

```bash
# Claude Code (use the pinned binary ~/bin/claude)
~/bin/claude --dangerously-skip-permissions
#   → browser OAuth login → at "Bypass Permissions" choose "Yes, I accept" → /exit
claude auth status            # expect loggedIn=True

# Codex CLI (device-auth, completed on your phone; enable "device code authentication" on the account first)
codex login --device-auth
codex login status            # expect "Logged in using ChatGPT"
```

Each user (family members included) logs in with their own Anthropic / ChatGPT account. Credentials live in `~/.claude` and `~/.codex/auth.json`, never in the repository.

### Step 5: Launch

```bash
./shutsujin_departure.sh
```

Creates tmux session `shogun` with windows **`main`** (Shogun) and **`agents`** (Karo, Gunshi, 6 Ninja = 8 panes) and starts the daemons (inbox watcher, ninja_monitor, ntfy). Window numbers are 0/1 or 1/2 depending on tmux `base-index`, so switch **by name**. CLI startup is verified for up to 30 s.

```bash
tmux attach -t shogun
# Ctrl+A → w for the window list, or Ctrl+A → :select-window -t main / agents
```

### Step 6: Your first command

Type an instruction in the Shogun pane (e.g. `read the readme and report the current state`). Shogun files a cmd and delegates to Karo; a Ninja works in an isolated task worktree and submits a report YAML; Gunshi reviews → Karo runs the GATE → CLEAR → ntfy notification.

### 📱 Android app (optional)

A companion app under `android/` drives tmux over SSH with voice input. Put your `whoami` / `pwd` values into the app settings. See `android/README.md`.

---

## How It Works

### Step 1: Connect to the Shogun

After running `shutsujin_departure.sh`, all agents automatically load their instructions and are ready.

Open a new terminal and connect:

```bash
tmux attach-session -t shogun
```

### Step 2: Give your first order

The Shogun is already initialized — just give a command:

```
Research the top 5 JavaScript frameworks and create a comparison table
```

The Shogun will:
1. Write the task to a YAML file
2. Notify the Karo (manager)
3. Return control to you immediately — no waiting!

Meanwhile, the Karo distributes tasks to ninja workers for parallel execution.

### Step 3: Check progress

Open `dashboard.md` in your editor for a real-time status view:

```markdown
## In Progress
| Worker | Task | Status |
|--------|------|--------|
| Hanzo | Research React | Running |
| Saizo | Research Vue | Running |
| Hayate | Research Angular | Completed |
```

### Detailed flow

```
You: "Research the top 5 MCP servers and create a comparison table"
```

The Shogun writes the task to `queue/shogun_to_karo.yaml` and wakes the Karo. Control returns to you immediately.

The Karo breaks the task into subtasks:

| Worker | Assignment |
|--------|-----------|
| Hanzo | Research Notion MCP |
| Saizo | Research GitHub MCP |
| Hayate | Research Playwright MCP |
| Kagemaru | Research Memory MCP |
| Kotaro | Research Sequential Thinking MCP |

All 5 ninja research simultaneously. You can watch them work in real time:

<!-- <p align="center">
  <img src="assets/screenshots/tmux_shogun_working.png" alt="Ninja agents working in parallel" width="700">
</p> -->

Results appear in `dashboard.md` as they complete.

---

## 🔗 Chain, Three-Layer Learning Loop, Three-Layer Memory

### The chain (one line of command)

Lord → Shogun → Karo → Ninja. No branches, no bypasses. Shogun decides, Karo organizes, Ninja executes, Gunshi reviews. **The chain is both the path of orders and the return path of learning**: a Ninja's `lesson_candidate` flows through Karo into lessons → gates → test fixtures. Bypass the chain and both the order and the learning are lost (source: top of `CLAUDE.md`, `instructions/*.md`).

### Three-layer learning loop

Every piece of work runs "① execute → ② binary measurement → ③ feed knowledge back → stronger next cycle", at three scopes.

| Layer | Scope | Implementation |
|---|---|---|
| Individual | inside one role | per-AC `binary_checks` (yes/no), self-check against 8 "brainwash" patterns, deepdive replay at startup (phase by phase, with receipts) |
| Pair | Ninja+Karo / Karo+Gunshi | report YAML → Gunshi SG7 review → Karo GATE round trip, rework-rate metrics |
| Whole | the entire chain | reflux (auto-deploying insights from `queue/insights.yaml` to idle Ninja), lesson retirement, daily before/after from `gate_metrics`, keeping CI green |

`/clear` is "New Game+": conversation context drops to zero but the knowledge base (`CLAUDE.md`, `instructions/`, lessons, memory DB, runbooks) survives, so the next session starts stronger. Principle: "don't cut, make it fast" — keep the gates, keep the quality, and make them faster (sources: `context/growth-loop.md`, `docs/research/three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707.md`).

### Three-layer memory

| Layer | What | Entry point |
|---|---|---|
| Memory DB | SQLite `data/multi_agent_shogun_memory.db` (dialogue, rulings, knowledge, restore points `session_save_*`, FTS5) | `bash scripts/memory_db_query.sh --search "<term>"` / write with `scripts/memory_db_knowledge_write.sh` |
| Semantic index | `context/semantic-map.md` + `docs/semantic-index/index.md` (concepts, aliases, discussions) | `bash scripts/semantic_search.sh "<query>"` |
| Obsidian causal network | `[[links]]` and `origin: "[[trigger]] -> [[cause]] -> [[effect]]"` (required in lessons, reports, cmds) | `.cache/causal_index.tsv`, `/three-layer-penetrate` |

Contract: search all three layers before acting (a hook injects the preflight automatically); every answer to the Lord carries a `[MEM: …]` citation tag (a stop hook blocks answers without one); new knowledge is written through to all three layers (sources: `context/memory-db-schema.md`, `docs/research/semantic_index_design.md`).

---

## Key Features

As of 2026-08-27, from the actual code. Everything the old README (2026-02/03) described — "send-keys to instruct", "Claude only", "check results by hand" — has been replaced.

1. **Mailbox messaging** — `scripts/inbox_write.sh <to> "<msg>" <type> <from> <action>`: flock-guarded YAML persistence; `inbox_watcher.sh` (inotify) sends only a short `inboxN` nudge. Agents never call tmux send-keys. Nudges are suppressed while a CLI confirmation prompt is open, Codex delivery is verified, unread messages are re-nudged.
2. **cmd filing gates** — `cmd_skeleton.sh` → `cmd_save.sh --preflight` → `cmd_save.sh` → `cmd_delegate.sh`. 82 check functions (quality questions q1–q12, binary ACs, path existence, test contracts, `environment_change`) BLOCK/WARN. A BLOCK is the entry of the growth loop: embed something in the environment so the next cmd is not blocked.
3. **Deployment with isolation** — `deploy_task.sh` generates the task YAML, push-injects related lessons and concepts, and isolates the Ninja in a **task worktree** (on ext4, survives reboots). One deployment: 23 s.
4. **Report contract** — `gate_report_format.sh` normalizes report YAMLs and derives the verdict (all `binary_checks` yes → PASS). Recon cmds require findings and are exempt from commits. `lesson_candidate` / `decision_candidate` / `origin` are structured.
5. **Two-stage review → GATE** — Gunshi SG7 precheck/LGTM → Karo ACCEPT → `cmd_complete_gate.sh` (commit ancestry, blob parity, CI readiness, context freshness) → CLEAR → archive → Ninja idle. `gate_metrics.log` records e2e/deploy/work/finalize seconds.
6. **Monitoring daemon** — `ninja_monitor.sh`: formation snapshot, STALL/ghost/UNACTIONED detection, context monitoring with auto `/clear`/respawn, reflux auto-deployment, WARN when a Codex pane's model/effort differs from settings. `daemon_watchdog` restarts watcher/monitor.
7. **Multi-CLI** — Claude Code (`.claude/hooks/`, 23 hooks, pinned 2.1.87 = `~/bin/claude`) and Codex (`.codex/hooks.json`, exit 2 = BLOCK) with separate implementations per CLI and one shared outcome standard. `/shogun-cli-switch` changes CLI/model by respawning idle panes only. `config/settings.yaml` is the single source of truth for the formation.
8. **41 skills** — `skills/*/SKILL.md` is canonical and shared by both CLIs; each description must declare TRIGGER / DO NOT TRIGGER.
9. **CoDD** — Coherence-Driven Development (by Oshio): spec → design docs → generate → validate → measure. Bash refactors run through `/codd-refactor` (measure → design → implement → re-measure).
10. **Tests** — 242 bats files. Selective execution via `run_tests.sh task|file|affected` is the rule (full suite 2,454 s vs seconds). CI runs shards with receipts, SKIP=FAIL, a timing ledger assigns shards. Orphan test detection and reaping. Default-delete policy: only contract tests survive.
11. **Instruments always on** — `logs/defense_overhead.jsonl` (wall time of every hook), `gate_metrics.log`, pre-push ledger, deploy receipts, publish phase instrumentation. The spiral: name the instrument → fix → measure one level deeper → leave the instrument in production.
12. **Three-layer memory + deepdive replay** — startup gates check memory health, unread inbox, pending rulings and deepdive receipts. Reading only conclusions leads back to the same mistake, so the full process is replayed phase by phase.
13. **Lord-facing surfaces** — `dashboard.md` (read directly by the Lord), a battle-status artifact republished by Shogun every 30 min, ntfy phone notifications, the Android app, gist sharing (creating a new gist requires an explicit flag — no history rewriting).
14. **Safety valves** — Tier 1 absolute bans (`rm -rf` family, `push --force`, `reset --hard`, `kill`, headless Chrome without a profile, …), Tier 2 stop-and-report, a hook that forbids YAML dump, direct DB connections blocked, no raw `git commit` by commanders (`ninja_scope_commit.sh`), no history rewriting.
15. **External project management** — `config/projects.yaml` + `projects/{id}.yaml` (git-ignored core knowledge) + `context/{project}.md` (index layer) + `docs/research/*.md` (detail layer).
16. **ext4 migration runbook** — `scripts/migrate_to_ext4_{relocate,cutover,rollback}.sh` and `docs/research/9p_root_fix_runbook_20260827.md`: how to move safely off a Windows drive onto ext4, plus the table of side effects observed after the move.

### Speed (measured 2026-08-27, `docs/research/ext4_speed_rebaseline_20260827.md`)

| Metric | 9p (/mnt/c) | ext4 (/home) |
|---|---|---|
| git status | 60–120 s | 84 ms |
| cmd publish | 3,770 ms | 227 ms |
| scope_commit git_commit / scope_sync | 9,487 / 5,846 ms | 173 / 73 ms |
| one deployment | 199–397 s | 23 s |
| median wall of one hook (all hooks) | 183 ms | 90 ms |

---

## 🗣️ SayTask — Task Management for People Who Hate Task Management

### What is SayTask?

**Task management for people who hate task management. Just speak to your phone.**

**Talk Coding, not Vibe Coding.** Speak your tasks, AI organizes them. No typing, no opening apps, no friction.

- **Target audience**: People who installed Todoist but stopped opening it after 3 days
- Your enemy isn't other apps — it's doing nothing. The competition is inaction, not another productivity tool
- Zero UI. Zero typing. Zero app-opening. Just talk

> *"Your enemy isn't other apps — it's doing nothing."*

### How it Works

1. Install the [ntfy app](https://ntfy.sh) (free, no account needed)
2. Speak to your phone: *"dentist tomorrow"*, *"invoice due Friday"*
3. AI auto-organizes → morning notification: *"here's your day"*

```
 🗣️ "Buy milk, dentist tomorrow, invoice due Friday"
       │
       ▼
 ┌──────────────────┐
 │  ntfy → Shogun   │  AI auto-categorize, parse dates, set priorities
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │   tasks.yaml     │  Structured storage (local, never leaves your machine)
 └────────┬─────────┘
          │
          ▼
 📱 Morning notification:
    "Today: 🐸 Invoice due · 🦷 Dentist 3pm · 🛒 Buy milk"
```

### Before / After

| Before (v1) | After (v2) |
|:-----------:|:----------:|
| ![Task list v1](images/screenshots/ntfy_tasklist_v1_before.jpg) | ![Task list v2](images/screenshots/ntfy_tasklist_v2_aligned.jpg) |
| Raw task dump | Clean, organized daily summary |

> *Note: Topic names shown in screenshots are examples. Use your own unique topic name.*

### Use Cases

- 🛏️ **In bed**: *"Gotta submit the report tomorrow"* — captured before you forget, no fumbling for a notebook
- 🚗 **While driving**: *"Don't forget the estimate for client A"* — hands-free, eyes on the road
- 💻 **Mid-work**: *"Oh, need to buy milk"* — dump it instantly and stay in flow
- 🌅 **Wake up**: Today's tasks already waiting in your notifications — no app to open, no inbox to check
- 🐸 **Eat the Frog**: AI picks your hardest task each morning — ignore it or conquer it first

### FAQ

**Q: How is this different from other task apps?**
A: You never open an app. Just speak. Zero friction. Most task apps fail because people stop opening them. SayTask removes that step entirely.

**Q: Can I use SayTask without the full Shogun system?**
A: SayTask is a feature of Shogun. Shogun also works as a standalone multi-agent development platform — you get both capabilities in one system.

**Q: What's the Frog 🐸?**
A: Every morning, AI picks your hardest task — the one you'd rather avoid. Tackle it first (the "Eat the Frog" method) or ignore it. Your call.

**Q: Is it free?**
A: Everything is free and open-source. ntfy is free too. No account, no server, no subscription.

**Q: Where is my data stored?**
A: Local YAML files on your machine. Nothing is sent to the cloud. Your tasks never leave your device.

**Q: What if I say something vague like "that thing for work"?**
A: AI does its best to categorize and schedule it. You can always refine later — but the point is capturing the thought before it disappears.

### SayTask vs cmd Pipeline

Shogun has two complementary task systems:

| Capability | SayTask (Voice Layer) | cmd Pipeline (AI Execution) |
|---|:-:|:-:|
| Voice input → task creation | ✅ | — |
| Morning notification digest | ✅ | — |
| Eat the Frog 🐸 selection | ✅ | — |
| Streak tracking | ✅ | ✅ |
| AI-executed tasks (multi-step) | — | ✅ |
| 8-agent parallel execution | — | ✅ |

SayTask handles personal productivity (capture → schedule → remind). The cmd pipeline handles complex work (research, code, multi-step tasks). Both share streak tracking — completing either type of task counts toward your daily streak.

---

## Model Settings

The formation is defined only by `config/settings.yaml` (CLI, model, effort, launch_cmd) and `config/cli_profiles.yaml`. The table shows the values as of 2026-08-27; switch with `/shogun-cli-switch` (respawns idle panes only, never a working one).

| Agent | CLI / model | effort | Why |
|---|---|---|---|
| Shogun | Claude Code / Fable 5 | low (settings) | dialogue with the Lord, cmd filing, overall judgement; no deep code digging |
| Karo | Codex / gpt-5.6-sol | medium | fast splitting, deployment and GATE decisions |
| Gunshi | Claude Code / Opus 4.6 (1M context) | high | reviews read long inputs (full cmd + report YAML), hence 1M |
| Ninja ×6 | Codex / gpt-5.6-luna | high | implementation, measurement, recon; model is inherited from settings, never pinned in the ninja launch_cmd |

Rules (Lord's rulings, 2026-08-27): never name a model inside a cmd (deployment is Karo's call); never respawn a working pane. For Codex, `codex_config_apply_agent` applies trust and model in `~/.codex/config.toml` on the respawn path, and `ninja_monitor` WARNs when the pane shows a model/effort different from settings.

### How the mix works

- **Claude leads, Codex follows** (multi-CLI principle): only the outcome standard (binary ACs, report contract) is shared; hooks, gates and launch are implemented per CLI. On conflict the Claude-side contract wins.
- **Switch by formation**: "Karo on Claude", "all Ninja on Codex" etc. are one `/shogun-cli-switch` command. Past formations: `context/training-cycle.md`.
- **Usage limits and update prompts**: when a Codex pane stops on a usage limit or an "Update available" prompt, the watcher suppresses nudges; clearing it is a reversible, verified key sequence.

---

## Philosophy

> "Don't execute tasks mindlessly. Always keep 'fastest × best output' in mind."

The Shogun System is built on five core principles:

| Principle | Description |
|-----------|-------------|
| **Autonomous Formation** | Design task formations based on complexity, not templates |
| **Parallelization** | Use subagents to prevent single-point bottlenecks |
| **Research First** | Search for evidence before making decisions |
| **Continuous Learning** | Don't rely solely on model knowledge cutoffs |
| **Triangulation** | Multi-perspective research with integrated authorization |

These principles are documented in detail: **[docs/philosophy.md](docs/philosophy.md)**

---

## Design Philosophy

### Why a hierarchy (Shogun → Karo → Ninja)?

1. **Instant response**: The Shogun delegates immediately, returning control to you
2. **Parallel execution**: The Karo distributes to multiple ninja simultaneously
3. **Single responsibility**: Each role is clearly separated — no confusion
4. **Scalability**: Adding more ninja doesn't break the structure
5. **Fault isolation**: One ninja failing doesn't affect the others
6. **Unified reporting**: Only the Shogun communicates with you, keeping information organized

### Why Mailbox System?

1. **State persistence**: YAML files provide structured communication that survives agent restarts
2. **No polling needed**: `inotifywait` is event-driven (kernel-level), reducing API costs to zero during idle
3. **No interruptions**: Prevents agents from interrupting each other or your input
4. **Easy debugging**: Humans can read inbox YAML files directly to understand message flow
5. **No conflicts**: `flock` (exclusive lock) prevents concurrent writes — multiple agents can send simultaneously without race conditions
6. **Guaranteed delivery**: File write succeeded = message will be delivered. No delivery verification needed, no false negatives, no 1.5h hangs from send-keys failures
7. **Nudge-only delivery**: `send-keys` transmits only a short wake-up signal (timeout 5s), not full message content. Agents read from their inbox files themselves. Eliminates send-keys transmission failures (character corruption, 1.5h hangs) that plagued the old "send full message" approach.

### Agent Identification (@agent_id)

Each pane has a `@agent_id` tmux user option (e.g., `karo`, `hanzo`). While `pane_index` can shift when panes are rearranged, `@agent_id` is set at startup by `shutsujin_departure.sh` and never changes.

Agent self-identification:
```bash
tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'
```
The `-t "$TMUX_PANE"` is required. Omitting it returns the active pane's value (whichever pane you're focused on), causing misidentification.

Model names are stored as `@model_name` and current task summaries as `@current_task` — both displayed in the `pane-border-format`. Even if Claude Code overwrites the pane title, these user options persist.

### Why only the Karo updates dashboard.md

1. **Single writer**: Prevents conflicts by limiting updates to one agent
2. **Information aggregation**: The Karo receives all ninja reports, so it has the full picture
3. **Consistency**: All updates pass through a single quality gate
4. **No interruptions**: If the Shogun updated it, it could interrupt the Lord's input

---

## Skills

Shared skills are included under `skills/`; user-specific skills may also live under `.claude/skills/` or `~/.codex/skills/`. `first_setup.sh` preserves existing skill directories and does not overwrite them.

Invoke skills with `/skill-name`. Just tell the Shogun: "run /skill-name".

### Skill Philosophy

**1. Shared and user-specific skills are separate**

User-specific skills in `.claude/commands/` are excluded from version control by design:
- Every user's workflow is different
- Rather than imposing generic skills, each user grows their own skill set

**2. How skills are discovered**

```
Ninja notices a pattern during work
    ↓
Appears in dashboard.md under "Skill Candidates"
    ↓
You (the Lord) review the proposal
    ↓
If approved, instruct the Karo to create the skill
```

Skills are user-driven. Automatic creation would lead to unmanageable bloat — only keep what you find genuinely useful.

---

## MCP Setup Guide

MCP (Model Context Protocol) servers extend Claude's capabilities. Here's how to set them up:

### What is MCP?

MCP servers give Claude access to external tools:
- **Notion MCP** → Read and write Notion pages
- **GitHub MCP** → Create PRs, manage issues
- **Memory MCP** → Persist memory across sessions

### Installing MCP Servers

Add MCP servers with these commands:

```bash
# 1. Notion - Connect to your Notion workspace
claude mcp add notion -e NOTION_TOKEN=your_token_here -- npx -y @notionhq/notion-mcp-server

# 2. Playwright - Browser automation
claude mcp add playwright -- npx @playwright/mcp@latest
# Note: Run `npx playwright install chromium` first

# 3. GitHub - Repository operations
claude mcp add github -e GITHUB_PERSONAL_ACCESS_TOKEN=your_pat_here -- npx -y @modelcontextprotocol/server-github

# 4. Sequential Thinking - Step-by-step reasoning for complex problems
claude mcp add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking

# 5. Memory - Cross-session long-term memory (recommended!)
# ✅ Auto-configured by first_setup.sh
# To reconfigure manually:
claude mcp add memory -e MEMORY_FILE_PATH="$PWD/memory/shogun_memory.jsonl" -- npx -y @modelcontextprotocol/server-memory
```

### Verify installation

```bash
claude mcp list
```

All servers should show "Connected" status.

---

## Real-World Use Cases

This system manages **all white-collar tasks**, not just code. Projects can live anywhere on your filesystem.

### Example 1: Research sprint

```
You: "Research the top 5 AI coding assistants and compare them"

What happens:
1. Shogun delegates to Karo
2. Karo assigns:
   - Hanzo: Research GitHub Copilot
   - Saizo: Research Cursor
   - Hayate: Research Claude Code
   - Kagemaru: Research Codeium
   - Kotaro: Research Amazon CodeWhisperer
3. All 5 research simultaneously
4. Results compiled in dashboard.md
```

### Example 2: PoC preparation

```
You: "Prepare a PoC for the project on this Notion page: [URL]"

What happens:
1. Karo fetches Notion content via MCP
2. Saizo: Lists items to verify
3. Hayate: Investigates technical feasibility
4. Kagemaru: Drafts a PoC plan
5. All results compiled in dashboard.md — meeting prep done
```

---

## Configuration

### Language

```yaml
# config/settings.yaml
language: ja   # Samurai Japanese only
language: en   # Samurai Japanese + English translation
```

### Screenshot integration

```yaml
# config/settings.yaml
screenshot:
  path: "/mnt/c/Users/YourName/Pictures/Screenshots"
```

Tell the Shogun "check the latest screenshot" and it reads your screen captures for visual context. (`Win+Shift+S` on Windows.)

### ntfy (Phone Notifications)

```yaml
# config/settings.yaml
ntfy_topic: "shogun-yourname"
```

Subscribe to the same topic in the [ntfy app](https://ntfy.sh) on your phone. The listener starts automatically with `shutsujin_departure.sh`.

---

## Advanced

<details>
<summary><b>Script Architecture</b> (click to expand)</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                    First-Time Setup (run once)                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  install.bat (Windows)                                              │
│      │                                                              │
│      ├── Check/guide WSL2 installation                              │
│      └── Check/guide Ubuntu installation                            │
│                                                                     │
│  first_setup.sh (run manually in Ubuntu/WSL)                        │
│      │                                                              │
│      ├── Check/install tmux                                         │
│      ├── Check/install Node.js v20+ (via nvm)                      │
│      ├── Check/install Claude Code CLI (native version)             │
│      │       ※ Proposes migration if npm version detected           │
│      └── Configure Memory MCP server                                │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                    Daily Startup (run every day)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  shutsujin_departure.sh                                             │
│      │                                                              │
│      ├──▶ Create tmux session                                       │
│      │         • "shogun" session                               │
│      │           Window 0: main (Shogun, 1 pane)                    │
│      │           Window 1: agents (Karo + 6 Ninja + 1 Gunshi)      │
│      │                                                              │
│      ├──▶ Reset queue files and dashboard                           │
│      │                                                              │
│      └──▶ Launch the mixed CLI formation                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

<details>
<summary><b>shutsujin_departure.sh Options</b> (click to expand)</summary>

```bash
# Default: Full startup (tmux sessions + mixed CLI launch)
./shutsujin_departure.sh

# Session setup only (no CLI launch)
./shutsujin_departure.sh -s
./shutsujin_departure.sh --setup-only

# Clean task queues (preserves command history)
./shutsujin_departure.sh -c
./shutsujin_departure.sh --clean

# Battle formation: All ninja on Opus (max capability, higher cost)
./shutsujin_departure.sh -k
./shutsujin_departure.sh --kessen

# Silent mode: Disable battle cries (saves API tokens on echo calls)
./shutsujin_departure.sh -S
./shutsujin_departure.sh --silent

# Full startup + open Windows Terminal tabs
./shutsujin_departure.sh -t
./shutsujin_departure.sh --terminal

# Shogun relay-only mode: Disable Shogun's thinking (cost savings)
./shutsujin_departure.sh --shogun-no-thinking

# Show help
./shutsujin_departure.sh -h
./shutsujin_departure.sh --help
```

</details>

<details>
<summary><b>Common Workflows</b> (click to expand)</summary>

**Normal daily use:**
```bash
./shutsujin_departure.sh          # Launch everything
tmux attach-session -t shogun # Connect (Window 0 = Shogun)
# Ctrl+A → 1 to see workers
```

**Debug mode (manual control):**
```bash
./shutsujin_departure.sh -s       # Create session only

# Manually launch the pane's configured CLI
tmux send-keys -t shogun:main 'claude --dangerously-skip-permissions' Enter
tmux send-keys -t shogun:agents.3 'codex' Enter   # example: hayate on Codex
```

**Restart after crash:**
```bash
# Kill existing session
tmux kill-session -t shogun

# Fresh start
./shutsujin_departure.sh
```

</details>

<details>
<summary><b>Convenient Aliases</b> (click to expand)</summary>

Running `first_setup.sh` automatically adds these aliases to `~/.bashrc`:

```bash
alias csst='cd ~/multi-agent-shogun && ./shutsujin_departure.sh'
alias csm='tmux attach-session -t shogun'  # Connect to session (Ctrl+A → 0/1 to switch windows)
```

To apply aliases: run `source ~/.bashrc` or restart your terminal (PowerShell: `wsl --shutdown` then reopen).

</details>

---

## File Structure

<details>
<summary><b>Click to expand file structure</b></summary>

```
multi-agent-shogun/
│
│  ┌──────────────── Setup Scripts ────────────────────┐
├── install.bat               # Windows: First-time setup
├── first_setup.sh            # Ubuntu/Mac: First-time setup
├── shutsujin_departure.sh    # Daily deployment (auto-loads instructions)
│  └──────────────────────────────────────────────────┘
│
├── instructions/             # Agent behavior definitions
│   ├── shogun.md             # Shogun instructions
│   ├── karo.md               # Karo instructions
│   ├── ashigaru.md           # Ninja instructions
│   └── cli_specific/         # CLI-specific tool descriptions
│       ├── claude_tools.md   # Claude Code tools & features
│       └── copilot_tools.md  # GitHub Copilot CLI tools & features
│
├── scripts/                  # Utility scripts
│   ├── inbox_write.sh        # Write messages to agent inbox
│   ├── inbox_watcher.sh      # Watch inbox changes via inotifywait
│   ├── ntfy.sh               # Send push notifications to phone
│   └── ntfy_listener.sh      # Stream incoming messages from phone
│
├── config/
│   ├── settings.yaml         # Language, ntfy, and other settings
│   └── projects.yaml         # Project registry
│
├── projects/                 # Project details (excluded from git, contains confidential info)
│   └── <project_id>.yaml    # Full info per project (clients, tasks, Notion links, etc.)
│
├── queue/                    # Communication files
│   ├── shogun_to_karo.yaml   # Shogun → Karo commands
│   ├── ntfy_inbox.yaml       # Incoming messages from phone (ntfy)
│   ├── inbox/                # Per-agent inbox files
│   │   ├── shogun.yaml       # Messages to Shogun
│   │   ├── karo.yaml         # Messages to Karo
│   │   └── {ninja_name}.yaml  # Messages to each ninja (hayate, kagemaru, hanzo, saizo, kotaro, tobisaru)
│   ├── tasks/                # Per-worker task files
│   └── reports/              # Worker reports
│
├── saytask/                  # Behavioral psychology-driven motivation
│   └── streaks.yaml          # Streak tracking and daily progress
│
├── templates/                # Report and context templates
│   ├── integ_base.md         # Integration: base template
│   ├── integ_fact.md         # Integration: fact-finding
│   ├── integ_proposal.md     # Integration: proposal
│   ├── integ_code.md         # Integration: code review
│   ├── integ_analysis.md     # Integration: analysis
│   └── context_template.md   # Universal 7-section project context
│
├── memory/                   # Memory MCP persistent storage
├── dashboard.md              # Real-time status board
├── CLAUDE.md                 # System instructions for Claude Code
└── AGENTS.md                 # System instructions for Codex
```

</details>

---

## Project Management

This system manages not just its own development, but **all white-collar tasks**. Project folders can be located outside this repository.

### How it works

```
config/projects.yaml          # Project list (ID, name, path, status only)
projects/<project_id>.yaml    # Full details for each project
```

- **`config/projects.yaml`**: A summary list of what projects exist
- **`projects/<id>.yaml`**: Complete details (client info, contracts, tasks, related files, Notion pages, etc.)
- **Project files** (source code, documents, etc.) live in the external folder specified by `path`
- **`projects/` is excluded from git** (contains confidential client information)

### Example

```yaml
# config/projects.yaml
projects:
  - id: client_x
    name: "Client X Consulting"
    path: "/mnt/c/Consulting/client_x"
    status: active

# projects/client_x.yaml
id: client_x
client:
  name: "Client X"
  company: "X Corporation"
contract:
  fee: "monthly"
current_tasks:
  - id: task_001
    name: "System Architecture Review"
    status: in_progress
```

This separation lets the Shogun System coordinate across multiple external projects while keeping project details out of version control.

---

## Troubleshooting

<details>
<summary><b>Using npm version of Claude Code CLI?</b></summary>

The npm version (`npm install -g @anthropic-ai/claude-code`) is officially deprecated. Re-run `first_setup.sh` to detect and migrate to the native version.

```bash
# Re-run first_setup.sh
./first_setup.sh

# If npm version is detected:
# ⚠️ npm version of Claude Code CLI detected (officially deprecated)
# Install native version? [Y/n]:

# After selecting Y, uninstall npm version:
npm uninstall -g @anthropic-ai/claude-code
```

</details>

<details>
<summary><b>MCP tools not loading?</b></summary>

MCP tools are lazy-loaded. Search first, then use:
```
ToolSearch("select:mcp__memory__read_graph")
mcp__memory__read_graph()
```

</details>

<details>
<summary><b>Agents asking for permissions?</b></summary>

Agents should start with `--dangerously-skip-permissions`. This is handled automatically by `shutsujin_departure.sh`.

</details>

<details>
<summary><b>Workers stuck?</b></summary>

```bash
tmux attach-session -t shogun
# Ctrl+A then 1 to open workers, then Ctrl+A + arrow keys / pane selection
```

</details>

<details>
<summary><b>Agent crashed?</b></summary>

**Do NOT use `csm` alias to restart inside an existing tmux session.** This alias attaches to a tmux session, so running it inside an existing tmux pane causes session nesting — your input breaks and the pane becomes unusable.

**Correct restart methods:**

```bash
# Method 1: Run the pane's configured CLI directly
claude --dangerously-skip-permissions   # Claude panes
# codex                                # Codex panes, if that worker uses Codex

# Method 2: respawn the pane with the right launcher
tmux respawn-pane -t shogun:main -k 'claude --dangerously-skip-permissions'
```

**If you accidentally nested tmux:**
1. Press `Ctrl+A` then `d` to detach (exits the inner session)
2. Run the pane's CLI directly (don't use `csm`)
3. If detach doesn't work, use `tmux respawn-pane -k` from another pane to force-reset

</details>

---

## tmux Quick Reference

| Command | Description |
|---------|-------------|
| `tmux attach -t shogun` | Connect to the session |
| `Ctrl+A` then `0` | Switch to Shogun window |
| `Ctrl+A` then `1` | Switch to workers window |
| `Ctrl+A` then `0`–`1` | Switch windows |
| `Ctrl+A` then arrow keys | Move across panes |
| `Ctrl+A` then `d` | Detach (agents keep running) |
| `tmux kill-session -t shogun` | Stop all agents |

### Mouse Support

`first_setup.sh` automatically configures `set -g mouse on` in `~/.tmux.conf`, enabling intuitive mouse control:

| Action | Description |
|--------|-------------|
| Mouse wheel | Scroll within a pane (view output history) |
| Click a pane | Switch focus between panes |
| Drag pane border | Resize panes |

Even if you're not comfortable with keyboard shortcuts, you can switch, scroll, and resize panes using just the mouse.

---

## Current Highlights

- **Config-driven mixed formation** — live assignment comes from `config/settings.yaml` and `config/cli_profiles.yaml`, not hard-coded README tables
- **GATE-first operations** — `cmd_complete_gate.sh`, `gate_cmd_state.sh`, and `gate_lesson_health.sh` protect against false completion, stale delegation, and low-value lessons
- **Knowledge operations** — the 7-layer knowledge map, `queue/karo_snapshot.txt`, `queue/pending_decisions.yaml`, and `context/cmd-chronicle.md` keep recovery and audits cheap
- **Mobile surface** — ntfy push, the Android companion app, and Termux/mosh access let you run the army away from the desk

---

## Contributing

Issues and pull requests are welcome.

- **Bug reports**: Open an issue with reproduction steps
- **Feature ideas**: Open a discussion first
- **Skills**: Shared skills live under `skills/`; personal skills remain outside the repository

## Credits

Based on [Claude-Code-Communication](https://github.com/Akira-Papa/Claude-Code-Communication) by Akira-Papa.

## License

[MIT](LICENSE)

---

<div align="center">

**One command. Nine agents. Zero coordination cost.**

⭐ Star this repo if you find it useful — it helps others discover it.

</div>
