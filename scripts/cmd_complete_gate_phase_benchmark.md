# cmd_4379 phase benchmark

測定日時: 2026-08-23 22:23–22:25 JST

## 条件

- 対象: `cmd_complete_gate.sh cmd_nonexistent_benchmark`
- 隔離fixture: task 0件、cmd entry 0件、parent report 0件、同一の`queue/`・`config/`・`scripts/lib/`構成
- 比較: `git show HEAD:scripts/cmd_complete_gate.sh`（before）と修正版（after）
- 計測: `/usr/bin/time`（壁時間）および`CMD_COMPLETE_GATE_PHASE_LOG`（EPOCHREALTIME差分）
- 検査契約: no-task fast pathのみを早期終了。task/parent-report経路のreview・report・gate検査は変更なし

## 実測

| 条件 | wall | user | sys |
|---|---:|---:|---:|
| before cold | 0.39 s | — | — |
| after cold | 0.21 s | 0.17 s | 0.06 s |
| after warm 1 | 0.02 s | 0.00 s | 0.01 s |
| after warm 2 | 0.02 s | 0.01 s | 0.01 s |

冷起動の短縮は`0.39 → 0.21 s`、`0.18 s`（46.2%）である。warm実行はbefore/afterとも`0.02–0.03 s`で、キャッシュ支配の差はない。

## after 1実行のフェーズ内訳

`logs/phases.log`の一次出力:

```text
2026-08-23T22:25:44 cmd_phase_measure startup 0.136
2026-08-23T22:25:45 cmd_phase_measure task_snapshot 0.064
2026-08-23T22:25:45 cmd_phase_measure no_task_detection 0.021
```

支配的ボトルネックはstartup（0.136 s）、次点はtask_snapshot（0.064 s）、no-task判定（0.021 s）だった。修正はtask snapshot直後にno-taskを確定し、normalize・auto-draft・preflight・review/report依存走査を実行しない経路へ移した。通常taskでは同処理を従来どおり実行する。

## 計測バグ確認

reportの`timestamp`が空でも`completed_at`/`done_at`を完了時刻として採用するよう修正した。追加回帰fixtureで`work_sec=300`、`invalid_work_sec`なしを確認し、従来の欠損fixtureでは`work_sec=na`と欠損理由を維持した。
