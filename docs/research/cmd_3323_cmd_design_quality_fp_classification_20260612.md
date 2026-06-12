# cmd_3323 起票検査差戻し分類

## 1. Scope

- Source: `logs/cmd_design_quality.yaml`
- Window: current file, latest 41 distinct cmd IDs / 201 entries (file has fewer than 50 distinct cmd IDs)
- Detailed classification: 2026-06-12 `cmd_save` / `cmd_save_warn` WARN+BLOCK entries
- Excluded from detailed FP rate: `command_files_modified_mismatch` from cmd_complete/report scope, because it is not a cmd design quality check

## 2. Aggregate

| Scope | Entries | WARN | BLOCK | PASS | CLEAR |
|---|---:|---:|---:|---:|---:|
| Latest distinct cmd window | 201 | 46 | 40 | 64 | 51 |
| 2026-06-12 cmd_save focus | 27 | 15 | 12 | 0 | 0 |

2026-06-12 cmd_save focus classification:

| Class | Count | Rate |
|---|---:|---:|
| True quality issue | 9 | 33.3% |
| False positive / over-broad machine reaction | 18 | 66.7% |

By check:

| Check | Total | True issue | False positive | FP rate | Main cause |
|---|---:|---:|---:|---:|---|
| `quality_gate_q8_scope_expression` | 8 | 1 | 7 | 87.5% | Japanese particles/ordinary scope language treated as shrinkage |
| `cmd_text_deferral_language` | 4 | 1 | 3 | 75.0% | Substring hit inside ordinary comparison wording such as `前後で` |
| `check_ac_param_sufficiency` | 2 | 0 | 2 | 100.0% | Reference numbering and cited section numbers treated as quantity requirements |
| `check_causal_verification_requirement` | 2 | 1 | 1 | 50.0% | Missing causal proof is valid once; repeated escalation hit after wording avoidance |
| `measurement_env_info` | 1 | 1 | 0 | 0.0% | Measurement environment field really missing |
| `check_ac_phase_mixing` | 1 | 1 | 0 | 0.0% | AC mixed investigation/implementation phase language |
| `cmd_save_main` aggregate BLOCK | 9 | 4 | 5 | 55.6% | Escalation magnifies upstream FP into repeated BLOCK |

## 3. Detailed Classification

| Time UTC | cmd | Check / reason | Classification | Basis |
|---|---|---|---|---|
| 02:41:48 | cmd_3316 | `ac_phase_mixing` | True issue | Diagnosis later says AC had phase-mixing wording; check target is AC text. |
| 02:41:48 | cmd_3316 | `cmd_text_deferral_language` | True issue | Diagnosis says later wording changed to independent cmd expression and AC phase terms removed. |
| 02:41:48 | cmd_3316 | `quality_gate_q8_scope_expression` | False positive | q8 shrinkage detector only knows particles such as `のみ/だけ/一部/代表`; task used bounded search/query wording rather than parameter-space reduction. |
| 02:41:48 | cmd_3316 | `WARNが3件...environment_change` | True issue | Multiple WARNs with no environment_change; this is process quality, not lexical FP. |
| 02:44:15 | cmd_3316 | `cmd_text_deferral_language` | True issue | Diagnosis says WARN3件 were still unresolved before environment_change was added. |
| 02:44:15 | cmd_3316 | `WARN累計昇格: 先送り表現` | True issue | Same unresolved WARN pattern repeated once. |
| 02:45:41 | cmd_3316 | `cmd_text_deferral_language` | False positive | Diagnosis explicitly says `前後で` substring hit. |
| 02:45:41 | cmd_3316 | `同一チェック(cmd_save_main)3回目` | False positive | Escalation came from the `前後で` substring FP. |
| 03:02:59 | cmd_3318 | `measurement_env_info` | True issue | Missing measurement environment proposal is not lexical FP. |
| 03:02:59 | cmd_3318 | `WARN累計昇格: measurement_env_info` | True issue | Same missing field pattern had prior occurrence (`cmd_3302`). |
| 03:22:33 | cmd_3319 | `causal_verification_missing` | True issue | Infra gate/semantic scope requires git log/blame/design-intent proof. |
| 04:26:47 | cmd_3321 | `q8_縮小表現` | False positive | Diagnosis says current cmd already avoided trigger-string quotation and measurement_env; no concrete shrinkage was recorded. |
| 04:26:47 | cmd_3321 | `WARN累計昇格: q8_縮小表現` | False positive | Escalation inherited earlier q8 lexical FPs. |
| 04:30:33 | cmd_3322 | `q8_縮小表現` | False positive | Later diagnosis identifies section-number/reference wording, not real scope reduction. |
| 04:30:33 | cmd_3322 | `ac_param_sufficiency` | False positive | Diagnosis says cited reply section number + numeric reference matched quantity regex. |
| 04:30:33 | cmd_3322 | `WARN累計昇格: ac_param_sufficiency` | False positive | Escalation inherited numeric-reference FP. |
| 04:31:29 | cmd_3322 | `ac_param_sufficiency` | False positive | Same reference-number issue repeated. |
| 04:31:29 | cmd_3322 | `q8_縮小表現` | False positive | Same q8 lexical issue repeated. |
| 04:31:29 | cmd_3322 | `WARN累計昇格: ac_param_sufficiency` | False positive | Same numeric-reference FP. |
| 04:33:17 | cmd_3322 | `q8_縮小表現` | False positive | Later diagnosis says AC reference notation caused the real blocker; no scope shrinkage evidence. |
| 04:33:17 | cmd_3322 | `同一チェック(cmd_save_main)3回目` | False positive | Diagnosis explicitly: reply section number + numeric combination matched quantity regex. |
| 04:35:34 | cmd_3322 | `q8_縮小表現` | False positive | q8 detector kept firing while the stated root cause was reference notation. |
| 04:35:34 | cmd_3322 | `同一チェック(cmd_save_main)3回目` | False positive | Diagnosis explicitly: purpose/q7/origin reference notation triggered fallback to whole cmd text. |
| 04:36:21 | cmd_3322 | `q8_縮小表現` | False positive | Same reference-notation context, no true shrinkage evidence. |
| 04:36:21 | cmd_3322 | `同一チェック(cmd_save_main)3回目` | False positive | Same as 04:35:34; whole-cmd fallback amplified FP. |
| 04:42:26 | cmd_3323 | `causal_verification_missing` | False positive | The cmd purpose was to classify gate FPs; wording avoided check vocabulary but omitted explicit causal tokens, so the detector did not recognize the actual cause context. |
| 04:42:27 | cmd_3323 | `WARN累計昇格: causal_verification_missing` | False positive | Escalation from a detector that requires magic words rather than structured evidence fields. |

## 4. Check Design Intent From Git

| Check | Git evidence | Intent |
|---|---|---|
| `quality_gate_q8_scope_expression` | `a990a5c39 cmd_2250 warn check context` | Detect forbidden scope reduction words in q8 WHAT so commands do not shrink parameter/search space by accident. |
| `check_ac_param_sufficiency` | `e73c9f97a feat: cmd_save.sh Check 13追加 — ACパラメータ充足度チェック(cmd_1685)` | When AC says `N conditions/items/methods`, force concrete enumeration so workers do not invent missing parameters. |
| `check_causal_verification_requirement` | `d05873c00 cmd_karo_impl_causal_verification_l0_l7_20260602` | For infra hook/gate/semantic/search/memory/deploy changes, force git log/blame/design-intent/causal proof before implementation. |
| WARN escalation | `scripts/cmd_save.sh` `WARN累計昇格` block | Prevent repeated WARNs from being ignored; repeated WARN means previous environment change failed. |

## 5. False Positive Vocabulary Catalog

| Check | FP vocabulary/context | Why it is valid text | Proposed fix |
|---|---|---|---|
| q8 shrinkage | `のみ`, `だけ`, `一部`, `代表` inside ordinary explanation or exact target statement | Exact target/scoped gate improvement is not the same as parameter-space reduction | Limit to `quality_gate.q8_why_what` WHAT segment and require a shrinkage object: `対象/範囲/探索/パラメータ/件数/サンプル` within a short window. |
| deferral language | `前後で` | Means before/after comparison, not postponement | Add word boundary/context rule: do not match `前後`, `直後`, `以後` as deferral unless accompanied by `後で/後続/次回/あとで/将来`. |
| AC parameter sufficiency | Reply/document section numbers, e.g. `節番号+数値` | A cited section number is a reference, not a required item count | Exclude quoted references and labels: `第N`, `N章`, `N節`, `Q7`, `AC2`, `cmd_3322`, and lines under `origin/q7/q8` when AC extraction falls back. |
| causal verification | Evidence exists semantically but lacks magic words | LLMs may write proof without exact token `git log/blame/causal` | Prefer structured fields: pass if `quality_gate.q5_verified_source`, `origin`, or AC contains at least two of `path`, `commit/id`, `lesson`, `design doc`, not just token regex. |
| WARN escalation | Repeats after upstream FP | Escalation is correct only if base WARN is true | Store base check classification or make escalation inherit severity only after base check passes a confidence threshold. |

## 6. Recommended Fix Plan

1. `cmd_text_deferral_language`: add explicit exclusions for `前後`, `直後`, `以後`, `以前`, `以降` unless paired with real deferral verbs.
2. `check_ac_param_sufficiency`: restrict fallback to command text. If `acceptance_criteria:` exists but extraction is empty, fail with extraction diagnostic instead of scanning purpose/q7/origin.
3. `quality_gate_q8_scope_expression`: require shrinkage vocabulary plus shrinkage object in the WHAT segment; allow exact/focused scope when `scope_mode=exact/focused`.
4. `check_causal_verification_requirement`: evaluate structured evidence fields and not only magic words.
5. `WARN累計昇格`: record `base_check` and `base_confidence`; do not escalate low-confidence lexical checks to BLOCK.

## 7. Report Metrics

- Latest cmd window: 41 distinct cmds, 201 log entries.
- Latest cmd window gate_result: WARN 46, BLOCK 40, PASS 64, CLEAR 51.
- 2026-06-12 cmd_save focus: 27 WARN/BLOCK entries.
- False positives: 18/27 = 66.7%.
- True quality issues: 9/27 = 33.3%.
- Worst FP checks: `check_ac_param_sufficiency` 100%, `quality_gate_q8_scope_expression` 87.5%, `cmd_text_deferral_language` 75.0%.
