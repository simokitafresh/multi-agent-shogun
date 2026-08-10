# cmd_4289 throughput trace reconstruction

- task: `cmd_4289_full` / parent: `cmd_4289`
- track: A（固定base `1a948adf73a9fcc6f8e13005ea00bf09d824cf76`）
- measured_at: `2026-08-10T13:14:00+09:00`
- scope: 既存ログ・queue履歴の読み取りと隔離コピー上の再計測のみ。実装・本番接触なし。
- exclusion: `cmd_4290` および配備後の共有contextは参照・変更していない。現行 `cmd_4289` は未完了のためcompleted分布から除外した。

## Definition and source boundary

品質合格スループットは、品質2原則を満たしてGATE CLEARに至ったcmdを単位時間で処理する量と定義する。completed lifecycleの区間は既存 `logs/gate_metrics.log` のCLEAR行にある実測値を採用した。

| 区間 | 定義 | 一次ソース |
|---|---|---|
| `deploy_sec` | 起票から配備まで | `logs/gate_metrics.log` のCLEAR行、deploy receiptの照合 |
| `work_sec` | acknowledgedからdoneまで | 同上。`missing` markerを別集計 |
| `finalize_sec` | doneからGATE CLEARまで | 同上。`invalid_finalize_sec`を別集計 |
| `e2e_sec` | 起票からGATE CLEARまで | 同上 |

現在cmdのqueue履歴による境界確認（未完了なので分布には算入しない）:

| event | timestamp | source |
|---|---|---|
| issued | `2026-08-10T13:07:22` | `queue/tasks/hayate.yaml:39` |
| deployed_at | `2026-08-10T13:07:46` | `queue/tasks/hayate.yaml:25` |
| acknowledged_at | `2026-08-10T13:08:56` | `queue/tasks/hayate.yaml` |
| deploy receipt issued | `2026-08-10T13:07:21` | `logs/deploy_task.log` |
| deploy receipt deployed | `2026-08-10T13:07:51` | `logs/deploy_task.log` |

queueのtask mutation時刻とdeploy receiptには非同期処理による最大5秒差があるため、completed分布では既に正規化済みの `gate_metrics.log` の数値を正本とした。

## Mechanical aggregation

実行コマンド（`logs/gate_metrics.log` は変更しない）:

```bash
python3 - <<'PY'
from pathlib import Path
from statistics import mean, median
import math, re
rows=[]
for line in Path('logs/gate_metrics.log').read_text().splitlines():
    p=line.split('\t')
    if len(p) >= 4 and p[2] == 'CLEAR':
        row={'ts':p[0], 'cmd_id':p[1]}
        row.update(dict(re.findall(r'(deploy_sec|work_sec|finalize_sec|e2e_sec|missing)=([^ ]+)', line)))
        rows.append(row)
def values(key):
    return [float(r[key]) for r in rows if r.get(key,'').replace('.','',1).isdigit()]
def p95(xs):
    xs=sorted(xs)
    return xs[max(0, math.ceil(.95*len(xs))-1)]
for key in ('deploy_sec','work_sec','finalize_sec','e2e_sec'):
    xs=values(key)
    print(key, len(xs), sum(xs), mean(xs), median(xs), p95(xs), min(xs), max(xs))
PY
```

生出力（2026-08-10実行）:

```text
clear_rows=303
date_range=2026-08-03T13:44:48 .. 2026-08-10T12:28:37
deploy_sec: n=303 sum=12551 mean=41.422 p50=35.0 p95=82.0 min=12.0 max=272.0
work_sec: n=303 sum=400055 mean=1320.314 p50=758.0 p95=2798.0 min=10.0 max=77249.0
finalize_sec: n=298 sum=412508 mean=1384.255 p50=328.0 p95=5145.0 min=8.0 max=52951.0
e2e_sec: n=303 sum=984075 mean=3247.772 p50=1338.0 p95=10154.0 min=364.0 max=82981.0
missing_markers: none=288 missing_ack_ts=10 invalid_finalize_sec=5
```

上記は区間ごとの生値集計であり、`finalize_sec`だけは5件が `na` のため n=298。`missing_ack_ts` 10件は除外せず、数値が存在する区間へは算入し、markerを併記した。

## Maximum bottleneck from raw values

`e2e_sec`は合計指標であり律速区間ではない。区間の最大生値を比較すると最大律速は `work_sec=77249`、対象は `cmd_karo_gist_reorder_remaining_20260807` だった。

対象行の現物（`logs/gate_metrics.log:336`）:

```text
2026-08-08T17:33:30  cmd_karo_gist_reorder_remaining_20260807  CLEAR
duration_sec=77249 deploy_sec=23 work_sec=77249 finalize_sec=857 e2e_sec=78140 missing=none
```

区間別最大値の生値上位（同じ集計コマンドの出力）:

```text
work_sec: 77249 cmd_karo_gist_reorder_remaining_20260807
           20475 cmd_karo_recon2_disk_recovery_20260806
           10304 cmd_4234
           9807  cmd_karo_hotfix_done_unarchive_self_heal_20260805
finalize_sec: 52951 cmd_reflux_backlink_202608032243_tobisaru
              39236 cmd_karo_hotfix_speed_ninja_scope_commit_r2_20260809
              31777 cmd_4246
e2e_sec: 82981 cmd_karo_gist_reorder_20260807
         78140 cmd_karo_gist_reorder_remaining_20260807
         53596 cmd_reflux_backlink_202608032243_tobisaru
```

## Independent isolated recheck (AC2)

検証方法は、対象3ログを `mktemp -d` の隔離ディレクトリへコピーし、別の読み取り専用parserで対象cmdの行・異常値警告・inbox履歴を突合することとした。コピー先以外のrepoファイルは変更していない。

再計測コマンドの要点:

```bash
tmp=$(mktemp -d)
cp --reflink=auto logs/gate_metrics.log "$tmp/gate_metrics.log"
cp --reflink=auto logs/cmd_complete_gate_async.log "$tmp/cmd_complete_gate_async.log"
cp --reflink=auto logs/inbox_info_digest.jsonl "$tmp/inbox_info_digest.jsonl"
# 独立parserで対象行、duration=77249s警告、GATE CLEAR通知を再計数
```

隔離再計測の生出力:

```text
isolated_copy_files=3
gate_metrics_exact_rows=1 clear_ts=2026-08-08T17:33:30 work_sec=77249 e2e_sec=78140
async_duration_warning_exact_count=20
inbox_digest_matches=2
digest=2026-08-08T17:33:45 GATE CLEAR — cmd_karo_gist_reorder_remaining_20260807 完了
digest=2026-08-08T17:34:09 cmd_karo_gist_reorder_remaining_20260807 gate_result: CLEAR
independent_recheck=PASS
```

さらに、同対象のreportは `2026-08-08 17:18:34+09:00` にcompleted、`gate_report_format` PASSは `17:19:06+09:00` であり、GATE CLEAR通知（17:33:45）と時系列が整合する。したがって `77249s` はparserの単発誤読ではなく、gate_metrics・async warning・queue/inboxの3系統に現れる実測外れ値として確証した。原因を単一機構へ帰す追加実装・本番接触は行っていない。

品質2原則への影響:

```text
品質契約の変更=0
対象縮小=0（CLEAR 303件を集計。区間欠損はmarker付きで明示）
実装変更=0
本番接触=0
独立再計測の結果=PASS
```

## AC1 context還流候補（家老release待ち）

共有 `context/infrastructure.md` へはまだ書き込んでいない。release後に次の候補文を還流する:

> `logs/gate_metrics.log` のCLEAR 303件（2026-08-03〜08-10）では、work_secの中央値758秒に対し最大77249秒（約101.9倍）を観測した。隔離コピー上の独立再計測で同一行・別async warning 20件・inbox GATE CLEAR 2件を再現したため、最大律速は計測アーティファクトではなく実ログ横断の外れ値である。root causeの機構特定は別実装cmdへ分離する。

origin: `[[殿直接下知_スループット改善高速回転_20260810]] -> [[cmd_4289_実測トレース]] -> [[work_sec最大外れ値77249秒]]`
