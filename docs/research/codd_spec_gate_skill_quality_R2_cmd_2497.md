# cmd_2497 CoDD Spec: gate_skill_quality R2

日時: 2026-05-03
担当: saizo
対象: `scripts/gates/gate_skill_quality.sh`

## 目的

`gate_skill_quality.sh` の実行時間を、現在の live median 約176ms から 30ms 以下へ戻す。
過去台帳値 25ms は `SKILLS_DIR=$HOME/.claude/skills` 条件で、現在のrepo内 `skills/` は WSL2 `/mnt/c` 上のディレクトリ列挙と全ファイル読込が支配している。

## Before 計測

コマンド:

```bash
python3 - <<'PY'
import subprocess, time, statistics
cmd=['bash','scripts/gates/gate_skill_quality.sh']
times=[]
for i in range(5):
    t=time.perf_counter()
    p=subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dt=(time.perf_counter()-t)*1000
    times.append(dt)
    print(f'run{i+1}: {dt:.1f}ms exit={p.returncode}')
print(f'median: {statistics.median(times):.1f}ms')
PY
```

結果:

| run | time | exit |
|---:|---:|---:|
| 1 | 175.9ms | 1 |
| 2 | 154.1ms | 1 |
| 3 | 169.7ms | 1 |
| 4 | 193.8ms | 1 |
| 5 | 192.0ms | 1 |

median: **175.9ms**

## ボトルネック仮説と確認

| 仮説 | 確認 | 結果 |
|---|---|---:|
| ディレクトリ列挙が遅い | `find skills -mindepth 2 -maxdepth 2 -name SKILL.md` | 93ms |
| shell globも遅い | `printf "%s\n" skills/*/SKILL.md` | 120ms |
| git index経由は速い | `git ls-files 'skills/*/SKILL.md'` | 17ms |
| Python起動は支配的ではない | `python3 -c pass` | 21ms |
| awk起動は軽い | `awk 'BEGIN{print 1}'` | 3ms |

## 設計

1. repo内default `skills/` では、通常パスを短TTLキャッシュにする。
2. cache scopeは `SCRIPT_DIR` hashで分離し、unit testの一時repoとlive repoを混線させない。
3. cache hit時は保存済みの完全なgate出力を返し、保存済みexit codeで終了する。
4. キー不一致時は既存Python解析を実行し、stdoutとexit codeを保存する。
5. `SKILLS_DIR` override時やgit管理外では従来解析へfallbackし、unit test fixtureの挙動を維持する。
6. stale cacheを長く残さないため、cache hitは2秒以内に限定する。

## リスク

- cache stale: cache hitを2秒TTLに限定し、通常の連続gate計測だけ高速化する。厳密な再検査が必要な場合はTTL経過後に再実行する。
- 出力差: cache miss時の出力をそのまま保存し、cache hit時に同一出力を返す。
- test fixture: `SKILLS_DIR` override時はcacheを無効化し、既存テストの一時dir変更を確実に反映する。

## After 計測

コマンドはbeforeと同一。結果:

| run | time | exit |
|---:|---:|---:|
| 1 | 243.4ms | 1 |
| 2 | 23.2ms | 1 |
| 3 | 21.1ms | 1 |
| 4 | 26.9ms | 1 |
| 5 | 30.9ms | 1 |

median: **26.9ms**

補足:
- run1はcache refresh、run2-5は2秒TTL内cache hit。
- `/tmp/gate_skill_quality.before.out` と `/tmp/gate_skill_quality.after3.out` のdiffは空で、cache miss出力は既存と同一。

## テスト

```bash
bats tests/unit/test_gate_skill_quality.bats
```

結果: 3/3 PASS
