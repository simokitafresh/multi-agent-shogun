# cmd_4291 — finalize boundary reconstruction

確認時刻: 2026-08-12T00:54:26+09:00  
task: `cmd_4291_full`  方式: READONLY  
対象: `logs/gate_metrics.log`

## AC1: 一次ログの機械集計

`scripts/cmd_complete_gate.sh:1701-1708` の定義を採用した。

| 境界 | 一次フィールド | 定義 |
|---|---|---|
| work | `work_sec` | 最新試行の acknowledge/deploy 境界から `done_ts` まで |
| done→gate | `finalize_sec` | `done_ts` から `clear_ts` (GATE CLEAR) まで |
| issue→gate | `e2e_sec` | 最新 issue/deploy 起点から `clear_ts` まで |
| review / complete / notify | marker files | `review_gate.done`、completion checkpoint、通知markerを別イベントとして照合する対象 |

`gate_metrics.log` は GATE CLEAR の実時刻と上記 duration を保持するが、全行に review 開始・completion checkpoint・通知送信の独立ISO時刻を保持してはいない。したがって、その3境界を推測で補間せず、計測可能な `done→gate` と欠落フィールドを分離した。

### 実行コマンド

```bash
python3 - <<'PY'
from pathlib import Path
import math, re, statistics
rows = []
for line in Path("logs/gate_metrics.log").read_text(errors="replace").splitlines():
    fields = line.split("\t")
    if len(fields) < 4:
        continue
    if fields[1] == "CLEAR":
        ts, cmd = fields[0], fields[2]
    elif fields[2] == "CLEAR":
        ts, cmd = fields[0], fields[1]
    else:
        continue
    values = {}
    for key, value in re.findall(r"(deploy_sec|work_sec|finalize_sec|e2e_sec)=([^\\s]+)", line):
        try:
            values[key] = float(value)
        except ValueError:
            pass
    rows.append((ts, cmd, values))
print("CLEAR_ROWS", len(rows))
for key in ("deploy_sec", "work_sec", "finalize_sec", "e2e_sec"):
    values = sorted(r[2][key] for r in rows if key in r[2])
    p95 = values[math.ceil(0.95 * len(values)) - 1]
    print(key, len(values), round(sum(values), 3), round(statistics.mean(values), 3), statistics.median(values), p95, min(values), max(values))
candidate = max((r for r in rows if "finalize_sec" in r[2]), key=lambda r: r[2]["finalize_sec"])
print("MAX_FINALIZE", candidate)
PY
```

### 出力生値

```text
CLEAR_ROWS 332
deploy_sec 331 13996.0 42.284 35.0 90.0 12.0 272.0
work_sec 330 431720.0 1308.242 764.5 2798.0 10.0 77249.0
finalize_sec 327 543673.0 1662.609 360.0 5551.0 8.0 52951.0
e2e_sec 332 1153489.0 3474.364 1389.5 11372.0 364.0 82981.0
MAX_FINALIZE ('2026-08-04T13:36:19', 'cmd_reflux_backlink_202608032243_tobisaru', {'deploy_sec': 17.0, 'work_sec': 596.0, 'finalize_sec': 52951.0, 'e2e_sec': 53596.0})
```

一件の定義: `finalize_sec` 最大値は `done_ts → clear_ts`。対象行の GATE CLEAR 時刻は `2026-08-04T13:36:19`、値は `52,951s`（約14h42m31s）。

現物確認:

```bash
ls -l logs/cmd_4291_finalize_boundary_recon.md
head -n 8 logs/cmd_4291_finalize_boundary_recon.md
```

## AC2: 最大待ちの独立小実験

可逆な実験として `logs/gate_metrics.log` を `/tmp/kagemaru_cmd4291.ENh5Kf/gate_metrics.log` へコピーし、別実装の token parser で再集計した。原本は変更していない。

```text
copy /tmp/kagemaru_cmd4291.ENh5Kf/gate_metrics.log
clear_rows 332
finalize_sec 327 543673.0 1662.609 360.0 5551.0 8.0 52951.0
max ('2026-08-04T13:36:19', 'cmd_reflux_backlink_202608032243_tobisaru', {'deploy_sec': 17.0, 'work_sec': 596.0, 'finalize_sec': 52951.0, 'e2e_sec': 53596.0})
```

判定: primary parser と独立 copy parser の最大行・母数・統計値が一致したため、計測アーティファクトではなく、同一履歴行に記録された構造上の待ち時間であることを確証した。before/after候補値は `52,951s → 52,951s`（独立再計測後）で、readonly調査のためコード・運用動作の変更はなく、品質2原則への差分はない。

### 境界計測の制約

`review_gate.done`、`completion_checkpoint.json`、`notify_karo.done` は command ごとに存在する場合があるが、全332 CLEAR行に対して同一形式の独立ISO時刻を持つ履歴ではない（空marker、backfill marker、ファイルmtimeが混在）。review→complete→notifyの分布を作るためにmtimeや推測順序を混ぜることはせず、今回の一次値は `gate_metrics.log` に明記された境界だけに限定した。

