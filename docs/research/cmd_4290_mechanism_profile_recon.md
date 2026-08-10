# cmd_4290 mechanism profile recon

- 実施日: 2026-08-10 (JST)
- 固定base: `1a948adf73a9fcc6f8e13005ea00bf09d824cf76`
- 隔離環境: `.hanzo_worktrees/cmd4290_mechanism_profile` (固定base detached worktree)
- 対象: `scripts/deploy_task.sh`, `scripts/cmd_save.sh`, `scripts/cmd_complete_gate.sh`
- 制約: 実装変更・本番DB接触・共有context実書込みなし。Track Bの自作fixture/固定baseのみ使用。

## 1. 計測定義

「実行時間」は各代表入力を起動してから終了するまでの壁時計時間。`user`/`sys` は補助値。`cmd_save` の内部内訳は既存の `DEFENSE_OVERHEAD_LEDGER` に出た `wall_ms` 生値を採用した。SKIPはなく、失敗結果も一次出力として保持した。

| 機構 | 代表入力 | 生値 | 判定 |
|---|---|---:|---|
| deploy_task | 固定baseの `deploy_task_preflight_fast.py`、source/active YAML fixture、9回反復 | cold 0.87s; warm median 259.140ms; 9回テスト全体7.46s | 2関数のRCを保持する read-only preflight |
| cmd_save | `test_cmd_save_phase_instrumentation.bats` のPASS fixtureを1回実走 | 2.95s (user 0.95s, sys 0.65s) | PASS、ledger出力あり |
| cmd_complete_gate | `CMD_COMPLETE_GATE_CLASSIFY_ONLY=1`、WAIT理由の分類入力 | 0.04s | `BLOCK` (副作用なし純分類分岐) |

### 実行コマンドと生出力

```text
(/usr/bin/time -f 'mechanism=deploy_task_preflight elapsed_sec=%e user_sec=%U sys_sec=%S' \
  pytest -q tests/unit/test_deploy_task_preflight_fast.py \
  -k nine_run_median_below_natural_receipt -s) 2>&1
preflight_median_ms=259.140
.
1 passed, 4 deselected in 6.73s
mechanism=deploy_task_preflight elapsed_sec=7.46 user_sec=1.61 sys_sec=0.79

(/usr/bin/time -f 'mechanism=cmd_save elapsed_sec=%e user_sec=%U sys_sec=%S' \
  bats --show-output-of-passing-tests --filter 'AC1: PASSしたcmd' \
  tests/unit/test_cmd_save_phase_instrumentation.bats) 2>&1
checks_main_profile 1204 checks_main.quality_gate=368 \
checks_main.workspace_state=162 checks_main.reference_guards=137 \
checks_main.memory_context=144 checks_main.content_and_ac=9 \
checks_main.parameter_space=49 checks_main.contracts=263 \
checks_main.final_guards=75
1..1
ok 1 AC1: PASSしたcmdはsource:cmd_saveのフェーズ別wall_msがverdict PASSで台帳へ出力される
variant=default elapsed_sec=2.95 user_sec=0.95 sys_sec=0.65

(/usr/bin/time -f 'mechanism=cmd_complete_gate elapsed_sec=%e user_sec=%U sys_sec=%S' \
  env CMD_COMPLETE_GATE_CLASSIFY_ONLY=1 \
  CMD_COMPLETE_GATE_CLASSIFY_REASON='review_two_phase_pending|ci_readiness:WAIT' \
  bash scripts/cmd_complete_gate.sh cmd_4290) 2>&1
BLOCK
mechanism=cmd_complete_gate elapsed_sec=0.04 user_sec=0.00 sys_sec=0.00
```

## 2. 最大律速と独立小実験

### 2.1 最大律速

冷起動の代表1回比較では `cmd_save` が2.95秒で最大だった。`cmd_save` の `checks_main` 内訳では `quality_gate` が368msで最大、次点は `contracts` 263ms、`workspace_state` 162msである。従って、現時点で確証できる支配項は「quality_gateフィールド検査・関連Qチェック群」であり、個別Q関数の内訳まではこの計測から推測しない。

### 2.2 仮説反証: fire-log停止

`quality_gate` の支配項がfire-log出力ではないかを、同一fixture・同一固定baseで `CMD_SAVE_DISABLE_FIRE_LOG=1` にして反証した。両方とも実行結果はPASSで、速度改善は観測されなかった。

| variant | checks_main raw | wall-clock | quality |
|---|---:|---:|---|
| default | 1204ms (`quality_gate=368ms`) | 2.95s | PASS |
| `CMD_SAVE_DISABLE_FIRE_LOG=1` | 1243ms (`quality_gate=390ms`) | 2.96s | PASS |

生出力:

```text
variant=default elapsed_sec=2.95 user_sec=0.95 sys_sec=0.65
checks_main_profile 1204 checks_main.quality_gate=368 ... checks_main.contracts=263 ...
variant=disable_fire_log elapsed_sec=2.96 user_sec=1.02 sys_sec=0.55
checks_main_profile 1243 checks_main.quality_gate=390 ... checks_main.contracts=284 ...
```

before/after候補値は `2.95s -> 2.96s`（-0.34%ではなく+0.34%、改善なし）。品質はPASS/PASSだが、速度改善がないため候補は不採用。品質境界を落としていないことは確認できたが、fire-log停止を改善策として採用する根拠はない。

### 2.3 補助分解: deploy_task preflight

固定baseでsourceを一度だけ読み、既存2関数を同一shellから呼ぶと、9回の関数計時は次の通りだった。

```text
deploy_task_destructive_signal_precheck: mean 63ms (RC=0)
should_skip_same_cmd_resolve: mean 74ms (RC=1; fixtureの重複なしを示す正常な非skip)
```

別shellで毎回sourceする両関数の9回medianは304ms、source-once adapterのwarm medianは259.140msだった。2関数のRC集合を維持したまま約44.9ms短縮する候補は確認できたが、今回の最大律速はcmd_saveであり、deploy_taskへの実装変更は行わない。

## 3. AC1 context還流候補 (家老release後のみ)

`context/infrastructure.md` へ反映する候補文:

> cmd_4290固定base隔離実測では、代表入力の冷起動wallはcmd_save 2.95s、deploy_task preflight warm median 259.140ms、cmd_complete_gate分類分岐0.04s。cmd_save内部はchecks_main.quality_gate=368msが最大で、fire-log停止の独立比較は2.95→2.96sで改善なし。次の計測対象はquality_gate内部の個別Qチェックであり、品質PASSを維持したまま計測を細分化する。

共有contextは `shared_context_embargo=karo_release_required` のため本作業では未変更。
