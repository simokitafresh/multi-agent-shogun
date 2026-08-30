# queue/tasks の mutation 残骸(2026-08-31 03:10 将軍一次)

- 集計: `ls queue/tasks | wc -l` → 4852。内訳(`ls queue/tasks | grep -c "^<ninja>.yaml.mutation.*bak$"` / `...lock$` / `^<ninja>.yaml.tmp`):
  hayate bak=412 lock=472 / kagemaru 412/463(tmp1) / hanzo 386/442 / saizo 380/425(tmp9) / kotaro 348/401(tmp9) / tobisaru 281/332(tmp9)
- 1件の定義: `queue/tasks/<ninja>.yaml.mutation.XXXXXX.{bak,lock}` と `<ninja>.yaml.tmp.XXXXXX` の 1 ファイル。
- 増分: `ls -la --time-style=+%m-%d queue/tasks | grep saizo.yaml.mutation | 日別 uniq -c` → 08-28 19 / 08-29 16 / 08-30 18(才蔵のみ)。毎日全忍者で 100 件前後増える負の複利。
- writer: `scripts/ninja_monitor.sh:10659 mutation_candidate=$(mktemp "${task_file}.mutation.XXXXXX")`。同ブロックに候補ファイル・.bak・.lock の後始末が無い(`sed -n 10655,10720p | grep -E 'rm |\.bak'` → 0 行)。
- 既知 insight: `grep -c mutation queue/insights.yaml` → 0(未登録)。壁の所有者なし。
- 期待する構造修正(家老 hotfix 1 unit): (1)writer が成功/失敗の両経路で候補・bak・lock を trap で回収 (2)起動時 sweep で holder pid 死亡かつ age>10 分の残骸を回収し件数を log に 1 行 (3)contract bats: 1 回の mutation 後に `ls queue/tasks/<n>.yaml.mutation.*` が 0。
- 既存残骸 4,852 件の一括回収は Tier2(>10 files)につき殿裁可待ち。hotfix の sweep が入れば自然回収される。
