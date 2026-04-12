---
codd:
  node_id: test:acceptance-criteria
  type: test
  depends_on:
  - id: req:shogun-monitor-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  - id: test:test-strategy
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:ninja_monitor
    - module:idle_management
    - module:stall_detection
    - module:health_checks
    - module:karo_monitor
    - module:pane_management
    - module:report_utils
    - module:state_io
    reason: 'FR-4/Constraint: All 854 bats tests must pass with zero SKIP. SKIP counts
      as FAIL. This is the primary release gate.'
  - targets:
    - module:idle_management
    - module:stall_detection
    - module:health_checks
    - module:karo_monitor
    - module:pane_management
    - module:report_utils
    - module:state_io
    reason: 'NFR-3: Each extracted module must be independently sourceable in test
      fixtures with appropriate mocks.'
  modules:
  - ninja_monitor
  - idle_management
  - stall_detection
  - health_checks
  - karo_monitor
  - pane_management
  - report_utils
  - state_io
---

# Acceptance Criteria

## 1. Overview

This document defines acceptance criteria, failure criteria, and test generation instructions for the **ninja_monitor.sh modular refactoring** — a pure structural split of a 3,158-line, 59-function bash daemon into 7 focused modules under `scripts/lib/monitor/`. The refactoring targets zero behavior change; the sole measure of success is that all existing 854 bats tests pass with zero SKIP, and each extracted module is independently sourceable in test fixtures.

**Scope**: The refactoring extracts functions from `scripts/ninja_monitor.sh` into these modules:

| Module | Functions | Responsibility |
|--------|-----------|---------------|
| `idle_management.sh` | 10 | idle detection, clear orchestration, deploy-stall handling |
| `stall_detection.sh` | 5 | task stall detection, cmd monitoring |
| `health_checks.sh` | 10 | infrastructure health monitoring |
| `karo_monitor.sh` | 5 | karo-specific monitoring |
| `pane_management.sh` | 9 | tmux pane operations, context tracking |
| `report_utils.sh` | 6 | report file resolution |
| `state_io.sh` | 2 | state file I/O, snapshot generation |

The main loop (dispatcher) remains in `ninja_monitor.sh`, which shrinks from 3,158 to ~500 lines containing global variable declarations, source statements, and the 20-second poll cycle.

**Runtime environment**: Bash 5.x on WSL2 (Ubuntu), NTFS-mounted `/mnt/c` paths, tmux pane variables for shared state.

### Convention Compliance

| Convention | How Addressed |
|------------|--------------|
| **Conv-1**: All 854 bats tests PASS, zero SKIP (FR-4 release gate) | AC-01 through AC-03 enforce full test suite passage. FC-01 treats any SKIP as release-blocking failure. Every test scenario includes explicit SKIP=0 assertion. |
| **Conv-2**: Each module independently sourceable with mocks (NFR-3) | AC-08 requires isolated sourcing of each of the 7 modules. Test fixtures must demonstrate mock injection for every external dependency (global vars, associative arrays, library functions). |

## 2. Acceptance Criteria

### 2.1 Verifiable Behaviors Enumeration

Every verifiable behavior from the requirements document is listed below with traceability to test scenarios.

| ID | Verifiable Behavior | Source | Test Scenario(s) |
|----|---------------------|--------|-------------------|
| VB-01 | All 854 bats tests pass after refactoring | FR-4 | AC-01 |
| VB-02 | Zero tests report SKIP status | FR-4, Conv-1 | AC-01, AC-02 |
| VB-03 | ninja_monitor.sh sources all 7 modules | FR-2 | AC-03 |
| VB-04 | ninja_monitor.sh line count ≤ 500 after extraction | FR-2 | AC-04 |
| VB-05 | All 59 original functions remain callable from main loop | FR-1, FR-3 | AC-05 |
| VB-06 | idle_management.sh contains exactly: check_idle, safe_send_clear, handle_confirmed_idle, handle_busy, _handle_post_clear_pending, _handle_deploy_stall, _handle_idle_notify, _handle_auto_clear, notify_idle_batch, _cleanup_stale_keys | FR-1 | AC-06a |
| VB-07 | stall_detection.sh contains exactly: check_stall, check_report_done_idle_mismatch, list_pending_cmds, check_stale_cmds, check_undeployed_cmds | FR-1 | AC-06b |
| VB-08 | health_checks.sh contains exactly: check_ntfy_listener_health, check_inbox_watcher_health, check_lesson_health, check_loop_health, check_workaround_pattern, check_gate_improvement, check_yaml_size, run_cdp_cleanup, run_lock_cleanup, check_auto_archive | FR-1 | AC-06c |
| VB-09 | karo_monitor.sh contains exactly: check_karo_pending_cmd, check_karo_pending, check_karo_clear, send_karo_clear, check_karo_idle_cycle | FR-1 | AC-06d |
| VB-10 | pane_management.sh contains exactly: discover_panes, check_pane_survival, check_ninja_cli_dead, update_context_pct, update_all_context_pct, get_context_pct, check_model_names, update_inbox_counts, check_shogun_ctx | FR-1 | AC-06e |
| VB-11 | report_utils.sh contains exactly: get_latest_report_file, find_matching_report_file, resolve_expected_report_file, can_send_clear_with_report_gate, check_and_update_done_task, is_task_deployed | FR-1 | AC-06f |
| VB-12 | state_io.sh contains exactly: write_state_file, write_karo_snapshot | FR-1 | AC-06g |
| VB-13 | Modules sourced after external libraries (cli_lookup.sh, etc.) | NFR-1 | AC-07 |
| VB-14 | Each module independently sourceable with mocks in test fixtures | NFR-3, Conv-2 | AC-08 |
| VB-15 | No new external dependencies introduced | NFR-2 | AC-09 |
| VB-16 | No Python/Node.js in the monitor daemon | Constraint | AC-09 |
| VB-17 | Auto-restart detects module file changes (script hash) | Constraint | AC-10 |
| VB-18 | Global variables (NINJA_NAMES[], PANE_TARGETS[], STATE_DIR, etc.) accessible from all modules | FR-3 | AC-11 |
| VB-19 | Associative arrays (STALL_FIRST_SEEN[], STALL_NOTIFIED[], STALL_COUNT[]) accessible from all modules | FR-3 | AC-11 |
| VB-20 | External library functions (yaml_field_get, log, send_inbox_message) callable from all modules | FR-3 | AC-12 |
| VB-21 | Works on WSL2 with NTFS-mounted /mnt/c paths | Constraint | AC-13 |
| VB-22 | Module files exist at scripts/lib/monitor/*.sh | FR-1 | AC-14 |
| VB-23 | No function defined in more than one module (no duplication) | FR-1 | AC-15 |
| VB-24 | No function removed (all 59 original functions present across modules + main) | FR-1, FR-4 | AC-05 |

### 2.2 Acceptance Criteria Definitions

**AC-01: Full Test Suite Green**
Run the complete bats test suite. All 854 tests report PASS. Zero tests report FAIL. Zero tests report SKIP. Exit code 0. This is the primary release gate.

```bash
bats tests/ --recursive --formatter tap
# Assert: 854 tests, 854 passed, 0 failed, 0 skipped
```

**AC-02: SKIP-as-FAIL Enforcement**
Parse bats TAP output. If any line matches `^ok .* # skip`, the run is FAIL regardless of exit code. Automated CI check must grep for skip markers independently of bats exit status.

**AC-03: Module Source Chain**
`ninja_monitor.sh` contains `source` statements for all 7 modules:
- `scripts/lib/monitor/idle_management.sh`
- `scripts/lib/monitor/stall_detection.sh`
- `scripts/lib/monitor/health_checks.sh`
- `scripts/lib/monitor/karo_monitor.sh`
- `scripts/lib/monitor/pane_management.sh`
- `scripts/lib/monitor/report_utils.sh`
- `scripts/lib/monitor/state_io.sh`

Verify with: `grep -c 'source.*scripts/lib/monitor/' scripts/ninja_monitor.sh` → 7.

**AC-04: Main File Size Reduction**
`wc -l scripts/ninja_monitor.sh` ≤ 500 lines (down from 3,158). The main file retains only global variable declarations, source statements, and the main loop dispatcher.

**AC-05: Function Completeness**
All 59 original functions remain callable. Extract function names from the pre-refactoring `ninja_monitor.sh` via `grep -E '^\s*function\s+|^[a-zA-Z_]+\(\)' scripts/ninja_monitor.sh` on the `main` branch before refactoring, then verify each exists in exactly one of the 7 modules or in the post-refactoring `ninja_monitor.sh`.

**AC-06a–g: Per-Module Function Assignment**
Each module contains exactly the functions specified in FR-1 (see VB-06 through VB-12). Verify by grepping each module file for function definitions and asserting the exact set matches.

**AC-07: Source Order Correctness**
In `ninja_monitor.sh`, all `source scripts/lib/monitor/*.sh` lines appear after all `source scripts/lib/*.sh` and `source lib/*.sh` lines. Verify by extracting line numbers of external library sources vs. module sources and asserting all module line numbers are strictly greater.

**AC-08: Independent Sourcing**
For each of the 7 modules, create a minimal test fixture that:
1. Declares required global variables as stubs (NINJA_NAMES, PANE_TARGETS, STATE_DIR, SCRIPT_DIR, LOG, STALL_FIRST_SEEN, STALL_NOTIFIED, STALL_COUNT, etc.)
2. Defines mock functions for external dependencies (yaml_field_get, log, send_inbox_message, etc.)
3. Sources only the single module file
4. Asserts: source exits 0, all functions defined in that module are callable, no unresolved function errors

**AC-09: No New Dependencies**
- `diff` the external tool invocations (commands called via `$()` or backticks) between pre- and post-refactoring. No new commands introduced.
- No `python`, `python3`, `node`, `npm`, `npx` invocations exist in any module file.
- No new `apt`, `pip`, or `npm install` required.

**AC-10: Auto-Restart Hash Detection**
The existing auto-restart mechanism computes a hash of the monitor script to detect changes. After refactoring, this hash must incorporate module files. Verify:
1. Modify a single line in `scripts/lib/monitor/idle_management.sh`
2. The running daemon detects the hash change and triggers restart within one poll cycle (20 seconds)
3. Revert the modification. Verify hash returns to original value.

**AC-11: Shared State Accessibility**
From within each module's functions, global variables and associative arrays are readable and writable. Verify by:
1. Sourcing all modules in sequence
2. Setting `NINJA_NAMES[0]="test_ninja"` before module source
3. Calling a function from `idle_management.sh` that reads `NINJA_NAMES[0]`
4. Asserting the function received `"test_ninja"`
5. Repeat for associative arrays: set `STALL_COUNT["test"]=5`, call `check_stall` (or equivalent), verify access.

**AC-12: External Library Function Access**
Functions from `scripts/lib/*.sh` (yaml_field_get, log, send_inbox_message, etc.) are callable from within module functions after the full source chain executes. Verify by calling one function from each module that invokes an external library function and asserting no "command not found" errors.

**AC-13: WSL2 /mnt/c Path Compatibility**
All file I/O operations in modules correctly handle NTFS-mounted paths under `/mnt/c`. Verify existing tests that exercise file operations under `/mnt/c`-style paths continue to pass (covered by AC-01).

**AC-14: Module File Existence**
All 7 files exist at the specified paths under `scripts/lib/monitor/`:
```bash
for m in idle_management stall_detection health_checks karo_monitor pane_management report_utils state_io; do
  test -f "scripts/lib/monitor/${m}.sh"
done
```

**AC-15: No Function Duplication**
No function name appears in more than one file (across all 7 modules + `ninja_monitor.sh`). Verify by extracting all function definitions and asserting uniqueness:
```bash
grep -rhE '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' scripts/lib/monitor/ scripts/ninja_monitor.sh \
  | sed 's/().*//' | sort | uniq -d | wc -l
# Assert: 0
```

## 3. Failure Criteria

Any of the following conditions constitutes a release-blocking failure:

| ID | Failure Condition | Severity | Triggered By |
|----|-------------------|----------|-------------|
| FC-01 | Any bats test reports SKIP | BLOCK | AC-01, AC-02 (Conv-1) |
| FC-02 | Any bats test reports FAIL | BLOCK | AC-01 |
| FC-03 | Bats test count ≠ 854 (tests lost or duplicated) | BLOCK | AC-01 |
| FC-04 | A module cannot be sourced independently with mocks (exit ≠ 0 or unresolved function) | BLOCK | AC-08 (Conv-2) |
| FC-05 | Any of the 59 original functions missing from post-refactoring codebase | BLOCK | AC-05 |
| FC-06 | A function defined in more than one file | BLOCK | AC-15 |
| FC-07 | Module source lines appear before external library source lines in ninja_monitor.sh | BLOCK | AC-07 |
| FC-08 | ninja_monitor.sh exceeds 500 lines | WARN | AC-04 |
| FC-09 | Module file count ≠ 7 in scripts/lib/monitor/ | BLOCK | AC-14 |
| FC-10 | Auto-restart fails to detect module file changes | BLOCK | AC-10 |
| FC-11 | New external tool, language, or package dependency introduced | BLOCK | AC-09 |
| FC-12 | python/python3/node invocation found in any module | BLOCK | AC-09 |
| FC-13 | Function from module cannot access global variable or associative array | BLOCK | AC-11 |
| FC-14 | Function from module cannot call external library function | BLOCK | AC-12 |

## 4. E2E Test Generation Meta-Prompt

### 4.1 Context

You are generating integration tests for a **bash daemon refactoring**. The system under test is `scripts/ninja_monitor.sh` and its 7 extracted modules under `scripts/lib/monitor/`. The test framework is **bats-core** (Bash Automated Testing System). There are no web endpoints, no HTTP servers, and no browsers involved. All tests execute in a bash shell environment.

### 4.2 Existing Test Baseline

854 bats tests already exist under `tests/`. These tests MUST NOT be modified, deleted, or skipped. The generated tests are **additive** — they validate the structural refactoring properties that existing tests do not cover.

### 4.3 Test Level Separation

Since this is a bash daemon (not a web application), the two test levels are:

| Level | Analog | Description | File Suffix |
|-------|--------|-------------|-------------|
| **Unit integration** | API integration | Source a single module with mocks, verify function availability and behavior | `.spec.bats` |
| **System integration** | Browser E2E | Source the full chain (ninja_monitor.sh with all modules), verify end-to-end function dispatch and shared state | `.system.bats` |

Unit integration tests verify that each module is independently sourceable (Conv-2/NFR-3). System integration tests verify the assembled daemon behaves identically to the monolith (FR-4).

### 4.4 MECE Domain Decomposition

| Domain | Scope | Output File |
|--------|-------|-------------|
| `module-structure` | File existence, function assignment, no duplication, line count, source order | `tests/e2e/module-structure.spec.bats` |
| `idle-management` | Independent sourcing of idle_management.sh, 10 functions callable, mock injection for globals | `tests/e2e/idle-management.spec.bats` |
| `stall-detection` | Independent sourcing of stall_detection.sh, 5 functions callable, associative array access | `tests/e2e/stall-detection.spec.bats` |
| `health-checks` | Independent sourcing of health_checks.sh, 10 functions callable | `tests/e2e/health-checks.spec.bats` |
| `karo-monitor` | Independent sourcing of karo_monitor.sh, 5 functions callable | `tests/e2e/karo-monitor.spec.bats` |
| `pane-management` | Independent sourcing of pane_management.sh, 9 functions callable, tmux mock | `tests/e2e/pane-management.spec.bats` |
| `report-utils` | Independent sourcing of report_utils.sh, 6 functions callable, file I/O mock | `tests/e2e/report-utils.spec.bats` |
| `state-io` | Independent sourcing of state_io.sh, 2 functions callable, write verification | `tests/e2e/state-io.spec.bats` |
| `full-chain` | Full source chain, shared state propagation, auto-restart hash detection, all 59 functions callable | `tests/e2e/full-chain.system.bats` |

### 4.5 Shared Helpers

All shared test utilities reside in `tests/e2e/helpers/`:

| Helper File | Purpose |
|-------------|---------|
| `tests/e2e/helpers/mock_globals.bash` | Declares all required global variables (NINJA_NAMES[], PANE_TARGETS[], STATE_DIR, SCRIPT_DIR, LOG) and associative arrays (STALL_FIRST_SEEN[], STALL_NOTIFIED[], STALL_COUNT[]) as stubs |
| `tests/e2e/helpers/mock_externals.bash` | Defines mock functions for external library dependencies: yaml_field_get, log, send_inbox_message, tmux, inotifywait, and any other external commands called by module functions |
| `tests/e2e/helpers/assert_functions.bash` | Provides `assert_function_exists()`, `assert_function_count()`, `assert_no_duplicates()`, `assert_source_order()` utilities |
| `tests/e2e/helpers/setup_tmpdir.bash` | Creates isolated temp directories for STATE_DIR, LOG, and queue/ paths, with teardown cleanup |

### 4.6 Scenario Derivation Rules

For each domain:

1. **Positive scenarios** (from acceptance criteria):
   - Source the module → exits 0
   - Each specified function is defined (via `type -t function_name`)
   - Function count matches specification exactly
   - Functions can be invoked without "command not found" errors
   - Global variables and associative arrays are accessible within functions

2. **Negative scenarios** (from failure criteria, inverted):
   - Source module without required globals → produces meaningful error or the function handles gracefully (not silent corruption)
   - Attempt to source a non-existent module path → non-zero exit
   - Introduce a duplicate function name → `assert_no_duplicates` catches it

3. **Structural scenarios** (module-structure domain):
   - 7 files exist in `scripts/lib/monitor/`
   - `ninja_monitor.sh` ≤ 500 lines
   - Source order: all `scripts/lib/*.sh` before `scripts/lib/monitor/*.sh`
   - No function name appears in more than one file
   - All 59 original function names present in post-refactoring codebase
   - No `python`, `python3`, `node` invocations in any module

4. **System scenarios** (full-chain domain):
   - Full source chain completes without error
   - All 59 functions callable after full source
   - Setting a global variable before source → readable inside module function after source
   - Modifying a module file → hash changes (auto-restart detection)

### 4.7 Architecture Adaptation

Before generating tests, scan the actual file structure:

```bash
# Discover actual modules
ls scripts/lib/monitor/*.sh 2>/dev/null

# Discover actual functions per module
for f in scripts/lib/monitor/*.sh; do
  echo "=== $f ==="
  grep -E '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' "$f"
done

# Discover external library sources
grep -E '^\s*source\s' scripts/ninja_monitor.sh
```

If a module file specified in the requirements does not yet exist, generate the test with `bats_test_skipped "module not yet extracted"` using `# @manual` marker so it is preserved on regeneration but flagged as pending implementation.

### 4.8 Runtime Environment

**Prerequisites**:
- bats-core installed (`bats --version` ≥ 1.5.0)
- bats-support, bats-assert, bats-file helper libraries available
- bash 5.x (`bash --version`)
- tmux available (for pane_management mock baseline)
- No running server required — tests source bash files directly

**Execution sequence**:
```bash
# Run existing test suite first (baseline gate)
bats tests/ --recursive --formatter tap | tee baseline.tap
grep -c '^ok' baseline.tap    # must equal 854
grep -c '# skip' baseline.tap  # must equal 0

# Run refactoring acceptance tests
bats tests/e2e/ --recursive --formatter tap | tee refactor.tap
grep -c '# skip' refactor.tap  # must equal 0
```

**CI configuration**: No background server. Tests execute synchronously. Timeout per test file: 60 seconds. Total suite timeout: 300 seconds.

### 4.9 Quality Gate

| Criterion | Threshold | Enforcement |
|-----------|-----------|-------------|
| Existing tests PASS | 854/854 | Release blocker |
| Existing tests SKIP | 0 | Release blocker (SKIP = FAIL per Conv-1) |
| New structural tests PASS | 100% | Release blocker |
| New structural tests SKIP | 0 | Release blocker |
| Function coverage | 59/59 original functions have at least 1 existence assertion | Release blocker |
| Module coverage | 7/7 modules have independent sourcing test | Release blocker (Conv-2) |
| Duplicate function check | 0 duplicates across all files | Release blocker |

### 4.10 Generation Markers

All generated test files must include these headers:

```bash
#!/usr/bin/env bats
# @generated-from: docs/tests/acceptance-criteria.md
# @generated-by: codd propagate
```

Test functions marked with `# @manual` must be preserved during regeneration. The generator must detect existing `# @manual` markers and carry them forward unchanged.

### 4.11 Traceability Matrix

The generated test suite must include a traceability comment block at the top of each domain file mapping test names to VB-IDs:

```bash
# Traceability:
#   test_module_files_exist        → VB-22
#   test_no_duplicate_functions    → VB-23
#   test_function_count_59         → VB-24
#   ...
```

Every VB-ID from section 2.1 (VB-01 through VB-24) must appear in at least one domain file's traceability block. Any VB-ID without coverage must be flagged with a `# COVERAGE-GAP: VB-XX` comment.
