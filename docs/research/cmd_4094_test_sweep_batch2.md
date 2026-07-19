# cmd_4094 テスト在庫sweep — 小batch第2弾・軍師確認checkpoint

作成: hanzo / 2026-07-20  
対象: cmd_4093削除資格層（宣言なし ∧ FAIL実績なし）290 filesのうち現HEAD現存26 files  
origin: [[B2削除batch_cmd_4094]] -> [[削除資格層再検分]] -> [[軍師必須確認checkpoint]]

## §1 停止条件と前提

本書はAC1の候補選定だけを行う。テスト削除、inventory変更、AC2実走は軍師確認前に行わない。

| 前提 | 一次証跡 | 判定 |
|---|---|---|
| cmd_4093分類 | `docs/research/cmd_4093_test_triage_batch1.md`: 365/365 files分類、削除資格層290 files（現存26、不存在264） | PASS |
| GA-304修正 | Git履歴 `92f400b30`（inventory guard）、`110b572b3`（Git portability）、`a577fbd15`（fixture host identity） | GREEN修正commit 3件を確認 |
| tests差分 | `git status --porcelain=v1 -- tests` | **0件** |
| inventory差分 | `git status --porcelain=v1 -- docs/research/ci-test-elimination-inventory-20260719.csv` | **0件** |
| 静穏baseline | 現在は他忍者が稼働中で共有worktreeの静穏を確定できない | **未確定。AC2開始禁止** |

## §2 第2小batch候補

候補は **1/1 file、3 cases、台帳2.588秒**。削除資格層26 filesを対象に、cmd固有名で被テストgateの大改修証跡を直接追えるものを優先した。

| file | 資格・改修証跡 | 被覆/削除証跡 | deletion_justification | fixture非test参照候補 | 削除時の順序制約 |
|---|---|---|---|---|---|
| `tests/unit/test_gate_report_format_cmd_3630_env_info.bats` | `test_necessity`なし、FAIL帰属なし。作成commit `3f188a256` 以後、`gate_report_format.sh` / `gate_report_format_main.py` / `gate_report_format_combined.py` に2026-07-01以降 **19 commits** | ENV INFO実装は現存（`gate_report_format_combined.py:76,117`）。候補の3境界（ENV token表示、通常値は非表示、disable抑止）は他testで同一被覆0件。よって現時点の即時削除は不可で、現行統合testへの移植完了が削除証跡になる | cmd_3630固有の旧report fixtureはgateの19回改修後も独立fileとして残り、統合report contract suiteから分離している。3境界を現行統合testへ移植し同一contract PASSを確認した後は、旧cmd固有fixtureの実装検証価値は消費済みとなるため削除資格あり | `scripts/lib/report_contract_test_selector.sh:12` に1件。削除と同一最終変更でselectorから除去が必要。`tasks/lessons.md` は履歴参照で変更対象外 | (1) `tests/test_gate_report_format.bats` 等の現行統合suiteへ3境界を移植 → (2) 3/3 PASS、全量FAIL0/SKIP0 → (3) selector参照除去 → (4) commit直前tests差分で他commit由来削除0を確認 → (5) 本候補1 fileのみ削除 → (6) 静穏same-condition before/after計測。順序逆転禁止 |

## §3 数値化

| 計測 | 結果 |
|---|---:|
| 候補選定 | **1/1** |
| deletion_justification記載 | **1/1** |
| 被覆/削除証跡記載 | **1/1** |
| fixture非test参照調査 | **1/1**（active caller 1件、履歴文書1件） |
| 削除順序制約記載 | **1/1** |
| 現時点のテスト削除 | **0件** |
| 現時点のtests差分 | **0件** |
| 現時点のinventory差分 | **0件** |
| AC2実走 | **0回** |

## §4 軍師必須確認

- [x] 候補を「即時削除可」ではなく「3境界移植後のみ削除可」とした判定が妥当
- [x] ENV INFOの3境界を現行統合suiteへ移植すればcontract消滅0となる
- [x] selector active参照1件は候補削除と同じ最終変更で除去し、履歴文書は不変でよい
- [x] GA-304 GREENと共有worktree静穏baselineをAC2開始直前に再確認する
- [x] 軍師承認までは削除0・tests差分0・inventory差分0・AC2実走0を維持する

**承認証跡:** 軍師 `msg_20260720_023848_3579518_38dc305d` が5/5 YES、候補1件を承認。AC2は3境界移植3/3 PASSと静穏baseline確定後に限る。

**現在地:** AC1 checkpoint完了。削除0・tests差分0・inventory差分0・AC2実走0のまま停止する。
