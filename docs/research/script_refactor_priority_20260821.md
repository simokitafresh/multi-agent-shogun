# scripts閾値超過リファクタ優先度台帳 v1.0 — 2026-08-21T23:23:00+09:00

## 判定対象と計測契約

- 対象: `logs/script_size_trend.log` の同一snapshotで `lines >= 2500 OR complexity >= 3000` を満たす `scripts/` 配下。
- snapshot: `2026-08-21T04:42:39+09:00`。入力台帳の実ファイル行数は `wc -l logs/script_size_trend.log` → `21966 logs/script_size_trend.log`。
- 列定義: `lines`, `functions`, `branches`, `complexity` はsnapshotの4列をそのまま採用。
- `git_commits`: 対象worktree `/tmp/shogun-task-worktrees/hanzo_31a25481592885bb`（HEAD `ee82da47830ebd8ff38760b5f35f3c50e468e726`）で、対象14 pathを一括 `git log --all --name-only` 走査し、各pathを含むcommit数を数えた。
- `workaround_mentions`: `logs/karo_workarounds.yaml` の各スクリプトstem（`.sh`除去）を含む行数。表記揺れを合成せず、実文字列の言及だけを数えた。
- `priority_score`: 各指標を降順1位（大きいほど高負荷）で順位化し、`complexity_rank + lines_rank + git_rank + workaround_rank`。同点はpathの辞書順。小さいほど優先度が高い。

## 優先度台帳

| priority | path | lines | functions | branches | complexity | git commits | workaround mentions | rank(C/L/G/W) |
|---:|---|---:|---:|---:|---:|---:|---:|---|
| 1 | `scripts/deploy_task.sh` | 14613 | 230 | 1829 | 29508 | 647 | 1 | 1/1/1/3 |
| 2 | `scripts/cmd_complete_gate.sh` | 13483 | 168 | 1911 | 27238 | 447 | 93 | 2/2/3/1 |
| 3 | `scripts/ninja_monitor.sh` | 11480 | 291 | 1252 | 25015 | 517 | 6 | 3/3/2/2 |
| 4 | `scripts/cmd_save.sh` | 7890 | 192 | 935 | 17365 | 397 | 0 | 4/4/4/6 |
| 5 | `scripts/inbox_write.sh` | 3208 | 93 | 360 | 7333 | 178 | 0 | 5/6/5/9 |
| 6 | `scripts/archive_completed.sh` | 2452 | 39 | 319 | 5022 | 98 | 0 | 8/8/9/5 |
| 6 | `scripts/report_field_set.sh` | 3288 | 42 | 570 | 7188 | 139 | 0 | 6/5/7/12 |
| 8 | `scripts/.report_field_set_lastgood.sh` | 2526 | 36 | 477 | 5811 | 1 | 0 | 7/7/14/4 |
| 9 | `scripts/context_freshness_check.sh` | 1959 | 11 | 303 | 3749 | 76 | 0 | 10/10/11/7 |
| 10 | `scripts/run_tests.sh` | 2427 | 36 | 297 | 4812 | 108 | 0 | 9/9/8/13 |
| 11 | `scripts/inbox_watcher.sh` | 1468 | 42 | 168 | 3358 | 162 | 0 | 13/14/6/8 |
| 12 | `scripts/ninja_scope_commit.sh` | 1822 | 30 | 189 | 3517 | 80 | 0 | 11/12/10/11 |
| 13 | `scripts/lesson_write.sh` | 1625 | 16 | 197 | 3010 | 61 | 0 | 14/13/12/10 |
| 14 | `scripts/semantic_index_update.sh` | 1856 | 6 | 299 | 3501 | 56 | 0 | 12/11/13/14 |

最優先は `scripts/deploy_task.sh`。複雑度・行数・変更頻度の3軸で1位であり、次のAC2ではこの1本だけを設計対象とする。

## 集計コマンドと生出力

### 超過対象の抽出

実行コマンド（snapshotを固定して抽出）:

```bash
python3 - <<'PY'
from pathlib import Path
for line in Path('logs/script_size_trend.log').read_text().splitlines():
    p=line.split('\t')
    if len(p)==6 and p[0]=='2026-08-21T04:42:39+09:00':
        _, path, lines, functions, branches, complexity=p
        if int(lines)>=2500 or int(complexity)>=3000:
            print(f'{path}\tlines={lines}\tfunctions={functions}\tbranches={branches}\tcomplexity={complexity}')
PY
```

生出力（14件）:

```text
scripts/deploy_task.sh	lines=14613	functions=230	branches=1829	complexity=29508
scripts/cmd_complete_gate.sh	lines=13483	functions=168	branches=1911	complexity=27238
scripts/ninja_monitor.sh	lines=11480	functions=291	branches=1252	complexity=25015
scripts/cmd_save.sh	lines=7890	functions=192	branches=935	complexity=17365
scripts/report_field_set.sh	lines=3288	functions=42	branches=570	complexity=7188
scripts/inbox_write.sh	lines=3208	functions=93	branches=360	complexity=7333
scripts/.report_field_set_lastgood.sh	lines=2526	functions=36	branches=477	complexity=5811
scripts/archive_completed.sh	lines=2452	functions=39	branches=319	complexity=5022
scripts/run_tests.sh	lines=2427	functions=36	branches=297	complexity=4812
scripts/context_freshness_check.sh	lines=1959	functions=11	branches=303	complexity=3749
scripts/semantic_index_update.sh	lines=1856	functions=6	branches=299	complexity=3501
scripts/ninja_scope_commit.sh	lines=1822	functions=30	branches=189	complexity=3517
scripts/lesson_write.sh	lines=1625	functions=16	branches=197	complexity=3010
scripts/inbox_watcher.sh	lines=1468	functions=42	branches=168	complexity=3358
```

### Git commit数

実行コマンド（14 pathを一括走査し、commit block内のpath名を集計）:

```bash
git -C /tmp/shogun-task-worktrees/hanzo_31a25481592885bb \
  log --all --format='COMMIT %H' --name-only -- \
  scripts/deploy_task.sh scripts/cmd_complete_gate.sh scripts/ninja_monitor.sh \
  scripts/cmd_save.sh scripts/report_field_set.sh scripts/inbox_write.sh \
  scripts/.report_field_set_lastgood.sh scripts/archive_completed.sh scripts/run_tests.sh \
  scripts/context_freshness_check.sh scripts/semantic_index_update.sh \
  scripts/ninja_scope_commit.sh scripts/lesson_write.sh scripts/inbox_watcher.sh
```

生出力（path別commit数）:

```text
scripts/deploy_task.sh	647
scripts/cmd_complete_gate.sh	447
scripts/ninja_monitor.sh	517
scripts/cmd_save.sh	397
scripts/report_field_set.sh	139
scripts/inbox_write.sh	178
scripts/.report_field_set_lastgood.sh	1
scripts/archive_completed.sh	98
scripts/run_tests.sh	108
scripts/context_freshness_check.sh	76
scripts/semantic_index_update.sh	56
scripts/ninja_scope_commit.sh	80
scripts/lesson_write.sh	61
scripts/inbox_watcher.sh	162
```

### 障害関与

実行コマンド:

```bash
for stem in deploy_task cmd_complete_gate ninja_monitor cmd_save report_field_set \
  inbox_write .report_field_set_lastgood archive_completed run_tests \
  context_freshness_check semantic_index_update ninja_scope_commit lesson_write inbox_watcher; do
  printf '%s\t' "$stem"
  rg -o -F "$stem" logs/karo_workarounds.yaml | wc -l
done
```

生出力（stemを含む行数）:

```text
deploy_task	1
cmd_complete_gate	93
ninja_monitor	6
cmd_save	0
report_field_set	0
inbox_write	0
.report_field_set_lastgood	0
archive_completed	0
run_tests	0
context_freshness_check	0
semantic_index_update	0
ninja_scope_commit	0
lesson_write	0
inbox_watcher	0
```

## 適用範囲

本台帳は優先順位付けだけを行う。実装・ファイル分割・既存テスト変更は後続cmdへ分離する。
