# cmd_4394 blocked理由分布・前倒し候補

- generated_at: `2026-08-25T00:35:00+09:00`
- task: `cmd_4394_full`
- primary ledger: `/mnt/c/tools/multi-agent-shogun/logs/deploy_issue_log.yaml`
- primary ledger sha256 (実集計時): `d7a035ae662eeaec05b26a6dc797404871a784d032e65c80bece534b28e7259e`
- primary ledger rows: `15,091` (`issued=7,548`, `blocked=4,529`, `deployed=3,014`)
- scope: 抽出・分類・前倒し候補のみ。根治実装は次弾。

## AC1 — blocked全量のreason/message分布

一次台帳の全行を `yaml.safe_load` し、`result == blocked` を抽出した。blockedは `4,529/7,548 = 60.0%`（blocked/issued=0.600106）である。

| raw `reason` | blocked rows | blocked比 | blocked cmd数 | 上位blocked cmd（件数） |
|---|---:|---:|---:|---|
| `exit_1` | 3,929 | 86.73% | 3,722 | `cmd_karo_impl_affected_test_routing` 13、`cmd_4200` 13、`cmd_4301` 9 |
| `exit_2` | 583 | 12.87% | 401 | `cmd_4105` 9、`cmd_karo_hotfix_metrics_updown_hlines_20260724` 8、`cmd_4133` 6 |
| `exit_124` | 10 | 0.22% | 9 | `cmd_karo_impl_4245_history_guard_rollback_202608101719` 2 |
| `exit_0` | 7 | 0.15% | 5 | `cmd_4366` 3 |
| **合計** | **4,529** | **100%** | — | — |

`message` 欄はblocked 4,529行中0行に存在した。したがって「理由別」は現時点では終了コード別の機械分類であり、`exit_1` 等を個別gate名へ読み替える証拠は台帳内にない。意味分類は下記のdeploy一次ログ照合で確認できた範囲だけを別記した。

再現用集計コマンド（一次台帳全量・理由・日次傾向・message欠測）:

```bash
python3 - <<'PY'
import yaml, collections, hashlib
from pathlib import Path
p=Path('logs/deploy_issue_log.yaml'); d=yaml.safe_load(p.read_text()) or []
b=[x for x in d if x.get('result')=='blocked']
print({'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'rows':len(d),
       'results':collections.Counter(x.get('result') for x in d),
       'blocked_reason':collections.Counter(x.get('reason') for x in b),
       'message_present':sum(bool(x.get('message')) for x in b),
       'blocked_cmds':len({x.get('cmd_id') for x in b})})
for day in sorted({x['timestamp'][:10] for x in b}):
    c=collections.Counter(x.get('reason') for x in b if x['timestamp'][:10]==day)
    print(day,sum(c.values()),dict(c))
PY
```

### 時系列傾向

日付境界の影響を避けるため、台帳の最初の日（7/17）から7日窓で `blocked/issued` を比較した。

| 期間 | rows | issued | blocked | deployed | blocked/issued |
|---|---:|---:|---:|---:|---:|
| 07/17–07/23 | 2,174 | 1,088 | 235 | 851 | 21.6% |
| 07/24–07/30 | 5,055 | 2,528 | 2,020 | 507 | 79.9% |
| 07/31–08/06 | 4,738 | 2,369 | 1,742 | 627 | 73.5% |
| 08/07–08/13 | 1,495 | 748 | 302 | 445 | 40.4% |
| 08/14–08/20 | 1,269 | 635 | 193 | 441 | 30.4% |
| 08/21–08/27（台帳末尾は08/24） | 360 | 180 | 37 | 143 | 20.6% |

判定: 直近は減衰している。特に `blocked/issued` はピーク79.9%から40.4%→30.4%→20.6%へ3窓連続で低下した。ただし試行量自体も減っているため、絶対件数だけでは改善判定しない。

## AC2 — 上位reasonの前倒し可能性

終了コードごとの一次台帳サンプルと、同じcmdに後続 `deployed` があるかを結合した。後続deployedは「block後に再試行して配備まで到達した」ことの保守的な摩擦プロキシであり、根因の断定ではない。

| raw reason | blocked | blocked cmd | block後に同cmdのissuedあり | block後に同cmdのdeployedあり | 前倒し候補段 | 一次証拠 |
|---|---:|---:|---:|---:|---|---|
| `exit_1` | 3,929 | 3,722 | 504 | 461 | task生成前の占有/品質/CI/ownership preflight | `deploy_reflux_auto.log` のGA-257、QUALITY_CONTRACT、ci_red_followupのBLOCK行とrc=1 receipt |
| `exit_2` | 583 | 401 | 537 | 495 | 起票/task contract生成時（AC shard、doc lane等） | `deploy_task.log:1201` UNIVERSAL_SHARD、`:7340` DOC_LANE_ROUTING、いずれもphase=preflight rc=2 |
| `exit_124` | 10 | 9 | 2 | 1 | 配備前の重いpreflight/task_mutationsのadmission・timeout予算 | `deploy_reflux_auto.log:106964,109886`、`deploy_task.log:6689` のphase/rc=124 receipt |
| `exit_0` | 7 | 5 | 1 | 0 | まず記録契約を補強。意味分類の前倒し段は未確定 | 対応するblocked messageがなく、一次ログのrc=0 blocked証跡も未発見 |

`exit_1` の一次ログ照合例は、(a) `GA-257` が「対象workerにactive taskがあるため上書き禁止」、(b) `QUALITY_CONTRACT` が `WARN(action=missing,fp=missing)`、(c) `ci_red_followup` が追いpush上限超過を配備前にBLOCKしている。いずれもpane deliveryより前にtask起票/配備入口で検出可能であり、後段blockの再試行を減らす前倒し候補である。

## AC3 — 次弾実装cmd入力となる根治候補（削減見込み順）

| 優先 | 候補 | 対象スクリプト/段 | 削減見込み根拠 | 受入れ時の計測 |
|---|---|---|---:|---|
| P0 | `exit_1` を意味別に構造化し、worker占有・品質契約・CI RED・ownershipをtask生成直前へ前倒し | `scripts/deploy_task.sh` のentrance/preflightとtask生成 | 上限3,929 blocked（全blockedの86.73%）。後続deployedまで戻った461行が優先観測窓 | raw exit_1件数、意味別件数、blocked/issued、再試行cmd数 |
| P1 | `exit_2` の契約検査を起票時に集約し、AC shard/doc laneをtask YAML生成器へ注入 | `scripts/deploy_task.sh` task contract/universal shard/doc lane | 583 blocked、495行で同cmdが後続deployed。契約不足による再試行の直接候補 | exit_2件数、後続deployed率、preflight到達前の検出率 |
| P2 | timeout admissionを軽量化し、重いpreflight/task_mutationsを段分解 | `scripts/deploy_task.sh` phase budget/timeout | 10 blocked。件数は小さいが1件あたりの待ち時間が大きい | rc=124件数、phase別wall_ms、再試行件数 |
| P3 | blocked eventへ意味付き `message` と検出stageを必須記録し、`exit_0` を未分類のまま残さない | issue ledger writer + deploy receipt | 7 blocked。現状はmessage欠測100%で、根治前後の比較不能 | message欠測0、stage欠測0、rc=0 blockedの分類率100% |

## AC4 — 正当な防御と無駄な摩擦の判別基準・適用

### 判別基準

- **正当な防御**: 配備前に実害（active taskの上書き、CI RED中の無関係配備、documentation-owned pathの誤配備、無効なAC/契約）を防ぎ、task/report/inboxの外部状態を変更せずrollbackできていること。
- **無駄な摩擦**: 同じ違反をtask生成時に検出できるのに配備入口まで進み、raw exit codeだけで原因が伝わらず、同一cmdの再試行を発生させていること。後続deployedはこの判定の一次的な補助証拠とする。
- **未分類**: messageまたは検出stageがなく、上記二値を安全に決められないもの。推測で正当化しない。

### 上位reasonへの適用

| reason | 防御判定 | 摩擦判定 | 根拠 |
|---|---|---|---|
| `exit_1` | 防御機構自体は正当（active task/CI/品質契約を守る） | **該当**。task生成前への前倒し余地があり、461/3,929 blocked行は後続deployedまで到達 | `deploy_reflux_auto.log` のGA-257/QUALITY_CONTRACT/ci_red_followup例、後続状態結合 |
| `exit_2` | 契約不備を配備前に止める点は正当 | **強く該当**。537/583行に後続issued、495/583行に後続deployed。起票時契約注入不足の再試行構造 | `deploy_task.log` のUNIVERSAL_SHARD/DOC_LANE_ROUTING rc=2 preflight |
| `exit_124` | timeoutによる暴走防止は正当 | **該当候補**。preflight/task_mutationsで待ち続け、10件中2件が再issued | rc=124 phase receipt。軽量化/admissionの余地あり |
| `exit_0` | 判定不能 | **判定不能** | message=0、rc=0 blockedの一次receiptなし。まず計装を修正する対象 |

### 結論

blockedの全件を無駄と扱うのは誤りで、防御の判定そのものは必要である。一方、`exit_1`/`exit_2` の大半は「正当な防御が後段で発火し、同じcmdの再試行を許した」構造として前倒し対象になる。次弾はP0の意味付きstage記録とtask生成前precheckを同時に実装し、raw exit codeだけの再集計不能状態を解消する。

