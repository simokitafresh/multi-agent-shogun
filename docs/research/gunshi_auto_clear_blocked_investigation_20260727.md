# 忍者auto clear停止 — 調査書 (2026-07-27)

- 起案: 軍師(gunshi)
- 発端: 殿下問 2026-07-27 10:51「忍者のauto clearは順調に動作しているか？」
- 下知: 殿 10:54「stagedの4ファイルを解消してauto clearを復旧せよ」/ 10:56「調査書にまとめてgistに共有、家老と将軍にレビュー依頼せよ」
- origin: `[[殿下問_auto_clear_20260727]] -> [[staged残置によるauto-commit skip]] -> [[忍者6名のCLEAR-BLOCKED]]`

## §0 結論(先に述べる)

**auto clearは順調に動作していない。** `git index` に残置されたstagedファイルにより auto-commit がskipされ、その結果 `/clear` 自体が実行されない。**忍者6名全員**が影響を受け、**少なくとも2026-07-25 20:54以降**継続している。

**軍師は復旧を試みたが完了していない。** 4ファイルのうち `context/lord-conversation-index.md` が部分stage状態(index と worktree が相違)であり、`ninja_scope_commit.sh` が `use --patch` を要求してBLOCKした。**この1ファイルの扱いに判断を要する。**

## §1 実測(4規律準拠)

### 1.1 発生規模

**集計コマンド**
```
grep -c "CLEAR-BLOCKED" logs/ninja_monitor.log
grep -o "CLEAR-BLOCKED: [a-z]*" logs/ninja_monitor.log | sort | uniq -c
for f in logs/ninja_monitor.log.1 .2 .3; do grep -c 'CLEAR-BLOCKED' $f; done
```

**出力行(生)**
```
174                          ← 現行ログ
88 kotaro / 25 kagemaru / 19 saizo / 17 hanzo / 13 tobisaru / 12 hayate
logs/ninja_monitor.log.1: 323件
logs/ninja_monitor.log.2: 294件
logs/ninja_monitor.log.3: 345件
```

**1件の定義**: ログ1行=1件。合計 **1,136件**(現行174+ローテート962)。
**網羅範囲**: `logs/ninja_monitor.log` と `.1〜.3` のみ。これ以前のログは保持されていない。

### 1.2 継続期間

**集計コマンド**
```
grep "CLEAR-BLOCKED" logs/ninja_monitor.log | head -1
grep "CLEAR-BLOCKED" logs/ninja_monitor.log | tail -1
head -1 logs/ninja_monitor.log.3
```

**出力行(生)**
```
[2026-07-27 02:41:29] CLEAR-BLOCKED: kagemaru auto-commit skipped because pre-existing staged files
[2026-07-27 10:55:22] CLEAR-BLOCKED: hanzo   auto-commit skipped because pre-existing staged files
[2026-07-25 20:54:12] HOOK-TRU…            ← 最古ログの開始時刻
```

**∴ 少なくとも 2026-07-25 20:54 以降、約38時間継続している。** 開始時期はログ保持期間の外にあり特定できない。

### 1.3 現在の影響(実測)

**集計コマンド**: `grep "^ninja|" queue/karo_snapshot.txt`(Generated: 2026-07-27T10:47:47)

**出力行(生)**
```
hayate  done CTX:17%    hanzo  idle CTX:12%    kotaro   idle CTX:13%
kagemaru     CTX:0%     saizo  idle CTX:0%     tobisaru idle CTX:0%
```

**∴ idleでありながらCTXが残る忍者が3名。** 本日 clear が完遂したのは **1件のみ**(`grep -c "clearing_agent"` → 1)。

## §2 真因

### 2.1 実装箇所

`scripts/ninja_monitor.sh:1443-1452`

```bash
_uncommitted=$(cd "$SCRIPT_DIR" && git status --porcelain -uno -- scripts/ instructions/ config/ context/ CLAUDE.md)
if [ -n "$_uncommitted" ]; then
    log "AUTO-COMMIT-BEFORE-CLEAR: ..."
    if ! auto_commit_before_clear "$agent_name" "$_uncommitted"; then
        log "CLEAR-BLOCKED: $agent_name auto-commit skipped because pre-existing staged files require preservation"
        return 1        # ★ここで /clear 自体が中止される
    fi
fi
```

### 2.2 因果連鎖

```
誰かが index にファイルをstageしたまま放置
  → auto_commit_before_clear が「他者のstageを巻き込まない」ため commit をskip
  → return 1 で /clear が中止される
  → 忍者のCTXが解放されない
  → idle でも文脈が積み上がったまま次のタスクへ
```

**設計意図は正しい。** 他者のstage済み変更を巻き込むcommitは事故になる(GA-231c が指揮官の `git commit` 直書きを禁じているのと同じ思想)。**問題は「保全のためskip」した後、誰にも通知されず放置され続けたこと**である。1,136件のログは出ていたが、**誰も見ていなかった**。

これは本日の中心型「実装ありだが効いていない」の変種であり、正確には**「検知は出力されているが消費者がいない」**である。

## §3 残置ファイル(4件)

**集計コマンド**: `git diff --cached --stat` / `git status --porcelain <4files>`

**出力行(生)**
```
 context/lord-conversation-index.md |  39 ++++---
 context/memory-db-schema.md        |  50 ++++-----
 context/semantic-map.md            |   2 +-
 logs/defense_overhead.jsonl        | 216 +++++++++++++++++++++
 4 files changed, 261 insertions(+), 46 deletions(-)

MM context/lord-conversation-index.md   ← ★staged と worktree が相違(部分stage)
M  context/memory-db-schema.md
M  context/semantic-map.md
MM logs/defense_overhead.jsonl          ← ★同上
```

**性質**: 4件とも自動生成・自動追記系。直近commitは `b1c188a7e chore: batch context auto-commit before /clear (hayate)` であり、**本来 auto-commit が処理すべきファイル群**である。

## §4 軍師が実施した復旧試行と結果

### 試行1: `git commit` 直書き → **BLOCKされた(正しい挙動)**
```
BLOCK(GA-231c): 指揮官のgit commit直書きは禁止。他者のstage済み変更を巻き込む事故を防ぐため
bash scripts/ninja_scope_commit.sh -m "<message>" -- <path1> [path2 ...] で変更pathを明示せよ
```
**評価**: gateが正しく機能した。軍師が意図した安全性そのものである。

### 試行2: `ninja_scope_commit.sh` でpath明示 → **BLOCKされた**
```
BLOCK: scope path has partial/foreign staged content that differs from worktree:
context/lord-conversation-index.md (use --patch)
rc=2 commit_hash=none last_phase=scope_sync
```
**評価**: `lord-conversation-index.md` は index と worktree が相違する部分stage状態。`--patch` 対話が必要だが、**対話的フラグは本環境で使用できない**(`git add -i` 系は不可)。

**∴ 軍師は復旧を完了できていない。** 4件中3件は commit 可能と見られるが、1件残れば index は空にならず CLEAR-BLOCKED は解消しない。

## §5 是正案(判断を仰ぐ)

| 案 | 内容 | 利点 | 懸念 |
|----|------|------|------|
| **A** | 4件すべて `git restore --staged` で unstage | 非破壊(worktreeの変更は残る)。index が空になり即復旧 | 変更が未commitのまま残る。次のauto-commitが拾う想定だが未検証 |
| **B** | 3件をcommit + `lord-conversation-index.md` のみ unstage | 大半を記録として残せる | 1ファイルだけ扱いが異なり非対称 |
| **C** | 部分stageを worktree 側で解消してから4件commit | 完全に片付く | index/worktree の差分内容を確認する必要あり。誰の変更か未特定 |

**軍師の見解**: **A を推す。** 理由 = (1)最も非破壊で可逆 (2)index を空にするという目的に直結 (3)これらは自動生成物であり、次の auto-commit サイクルが正規経路で拾える。ただし **(3)は未検証**であり、unstage後に実際に auto-commit が動くかを観測する必要がある。

**軍師が決めない理由**: repo全体の index に触れる操作であり、他エージェントの作業中変更を巻き込む可能性を軍師は排除できていない(誰がいつstageしたかを特定していない)。

## §6 恒久是正の候補(別弾)

**本件の本質は「検知が出力されているが誰も見ていない」ことである。** 1,136件のログが38時間出続けたが、startup gate にも dashboard にも現れなかった。

- 候補1: `gate_karo_startup.sh` / `gate_gunshi_startup.sh` に「CLEAR-BLOCKED 直近N件」を追加する
- 候補2: CLEAR-BLOCKED が同一agentで連続K回発生したら家老へ inbox 通知する
- 候補3: `auto_commit_before_clear` の skip 時に insight_write で在庫化する

**いずれも新規gate新設ではなく既存の startup gate / 通知経路への1項目追加**である(殿裁定07-21「削るな、速くしろ」および LG032「既存の強制された行動に乗せよ」に整合)。

## §7 軍師が確認していないこと

- staged 4件を **誰がいつ stage したか**は特定していない
- `logs/ninja_monitor.log.4` 以前は保持されておらず、**問題の真の開始時期は不明**
- 案Aの前提「unstage後に auto-commit が正規経路で拾う」は**未検証**
- `logs/defense_overhead.jsonl` と `lord-conversation-index.md` の worktree 側差分の**内容は精査していない**

## §8 因果リンク

- → [[ninja_monitor_auto_clear]] auto clear機構の本体
- → [[GA-231c]] 指揮官のcommit直書き禁止(同じ「他者stage保護」思想)
- → [[実装ありだが効いていない]] 本日の中心型の変種=検知の消費者不在
