<!-- gist-master: 20bd7f137665f0badedb7241035732c3 commit-reservation-ledger-asis-tobe-5w1h_20260805.md -->
# commit予約台帳 — 共有git indexの直列化 AsIs/ToBe 5W1H設計書 v1.1

> v1.1(2026-08-05 04:30 殿指示): §ファイル&フォルダ構造(AsIs/ToBe)、ロック階層図、AsIs vs ToBeフロー比較を追加

> v1.0(2026-08-05 03:58 殿発案): commit競合で将軍が20分以上浪費した実事例から。殿『コミットの予約台帳みたいなものを共有して順番を予約する仕組みにすればいいのでは？』

> 発端: 将軍のcommit(deepdive指示修正4ファイル)がpre-commitフック内のtest_ninja_scope_commit.batsと共有index.lockで自己デッドロック→132秒timeout×5回失敗→20分浪費。並行して家老worktreeのshard-4テストも同indexを要求し合成デッドロック

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | 9並列CLI(忍者6+家老+軍師+将軍)が共有git indexを争奪。現行のflock+retryでは(1)自己デッドロック(pre-commit→テスト→index要求)と(2)長時間ロック保持(テスト実行中)が解消不能。agent-hoursで毎日数十分〜数時間の浪費(本セッションで実証) |
| WHAT | 共有ファイルベースの予約台帳でcommitを直列化し、競合をゼロ待ちのFIFOキューに変える |
| WHO | 実装=忍者(家老配備)。全CLIが利用 |
| WHEN | 殿裁可後 |
| WHERE | `scripts/ninja_scope_commit.sh`(既存commitパス)+新規`scripts/commit_queue.sh`(台帳管理) |
| HOW | 下記§ToBe |

## §ファイル&フォルダ構造(AsIs)

```
multi-agent-shogun/
├── .git/
│   ├── index                        ← 共有git index(全9 CLIが争奪)
│   ├── index.lock                   ← git操作中に自動生成(排他ロック)
│   └── hooks/
│       └── pre-commit               ← commit時に自動実行(run_tests.sh affected呼出し)
├── .karo_worktrees/                 ← 家老が作成するshard用worktree
│   └── round8-shard-N/              ← 各shardの独立worktree(ただし.git/indexは共有)
├── scripts/
│   ├── ninja_scope_commit.sh        ← 全agentのcommit入口(owned-scope lock+pre-commit)
│   ├── run_tests.sh                 ← テストランナー(pre-commitから呼出される)
│   └── lib/
│       └── lock_path.sh             ← WSL2 ext4へのlock写像SSOT
├── tests/unit/
│   └── test_ninja_scope_commit.bats ← ★デッドロック源(pre-commit→このテスト→index.lock要求)
└── /tmp/ (ext4)
    ├── shogun_lock_<hash>.lock/     ← 将軍のowned-scope lock
    │   ├── <run_key>.ledger         ← commit実行ログ
    │   ├── <run_key>.git-exit       ← git終了コード記録
    │   └── <run_key>.receipt        ← commit成功受領証
    ├── <agent>_lock_<hash>.lock/    ← 各agentのowned-scope lock(同構造)
    └── shogun_commit_queue.tsv      ← ★新設: 予約台帳(ToBe)
```

### ロック階層(AsIs — 3段)

```
L1: owned-scope lock (/tmp/<agent>_lock_<hash>.lock/)
    │  flock -n → 取得失敗="BLOCK: cannot acquire ninja owned-scope lock"
    │  目的: 同一agentの二重commit防止
    │
    └─ L2: commit lock (/tmp/ext4側 lock_path写像)
        │  flock -w 120 → 120秒timeout
        │  目的: 全agentの直列化(gitの排他要求)
        │
        └─ L3: git index.lock (.git/index.lock)
            │  git内部が自動管理
            │  目的: index操作の原子性
            │  ★問題: pre-commitテスト中ずっと保持(数分〜34分)
            │
            └─ L4(再帰): テスト内のninja_scope_commit.sh → L3要求 → デッドロック
```

## §AsIs — 3つの構造問題(2026-08-05実証)

### 問題1: 自己デッドロック(本セッション実証)

```
将軍 ninja_scope_commit.sh
  → git commit (index.lock取得)
    → pre-commit hook
      → run_tests.sh affected
        → bats test_ninja_scope_commit.bats
          → テスト内でninja_scope_commit.sh呼出し
            → git read-tree (index.lock要求)
              → BLOCKED (自分のcommitがindex.lock保持中)
                → 132秒timeout → FAIL
```

pre-commitフックが「commitに使うツールのテスト」を実行し、そのテストが同じgit indexを要求する再帰的デッドロック。

### 問題2: 長時間ロック保持

pre-commitフック内のテスト実行が数分〜15分かかる。その間、全他エージェントのcommitがブロックされる。9並列CLIで1エージェントのcommitに15分かかると、他8エージェントが平均7.5分待つ = 60 agent-minutes/commit。

### 問題3: リトライストーム

ロック取得失敗→即リトライ→また失敗→バックグラウンドプロセスが蓄積。本セッションで5回のcommit試行が同時に残存し、最初のプロセスが20分間ゾンビ化した。

## §ToBe — 予約台帳方式(殿発案)

### 原理

**commit意思の宣言と実行を分離する。** 宣言(予約)はflock 1行追記で瞬時。実行は自分の順番が来た時だけ。

### 台帳ファイル

```
# /tmp/shogun_commit_queue.tsv (flock保護・TSV)
# timestamp  agent_id  status    files                                          message
2026-08-05T03:34:12  shogun   waiting   scripts/gates/gate_shogun_startup.sh,...  fix: deepdive...
2026-08-05T03:35:01  hayate   waiting   scripts/ninja_scope_commit.sh            fix: snapshot...
2026-08-05T03:36:15  saizo    waiting   tests/unit/test_foo.bats                 test: add...
```

### フロー

```
Agent: commit したい
  │
  ├─ Step 1: 予約(瞬時)
  │    flock → 台帳末尾に1行追記(status=waiting) → flock解放
  │    所要: <100ms
  │
  ├─ Step 2: 順番待ち
  │    while true:
  │      flock → 台帳読込 → 自分がwaiting最古か確認 → flock解放
  │      最古なら → Step 3へ
  │      最古でないなら → sleep 3 → 再確認
  │      timeout 300s → 予約取消+FAIL
  │    所要: 0s(先頭) 〜 N×commit時間(後続)
  │
  ├─ Step 3: 実行
  │    flock → status=running に更新 → flock解放
  │    git add → git commit (pre-commit含む) → 結果取得
  │    所要: テスト実行時間
  │
  └─ Step 4: 完了
       flock → 自分の行を削除(またはstatus=done) → flock解放
       後続agentのStep 2が即座に検知して進行
```

### ファイル&フォルダ構造(ToBe)

```
multi-agent-shogun/
├── .git/
│   ├── index                        ← 変更なし
│   ├── index.lock                   ← 変更なし(保持時間が短縮)
│   └── hooks/
│       └── pre-commit               ← 変更: PRECOMMIT=1をexport+timeout 60s
├── scripts/
│   ├── ninja_scope_commit.sh        ← 変更: commit_queue.sh経由に改修
│   ├── commit_queue.sh              ← ★新設: 予約台帳管理
│   │   ├── reserve()                   予約追記(flock <100ms)
│   │   ├── wait_turn()                 FIFO順番待ち(sleep 3ループ)
│   │   ├── mark_running()              status更新
│   │   └── release()                   行削除+後続通知
│   ├── run_tests.sh                 ← 変更: PRECOMMIT=1時にデッドロック源を除外
│   └── lib/
│       └── lock_path.sh             ← 変更なし
├── tests/unit/
│   └── test_ninja_scope_commit.bats ← 変更なし(CI/手動で実行。pre-commit除外)
│   └── test_commit_queue.bats       ← ★新設: 予約台帳テスト
└── /tmp/ (ext4)
    ├── shogun_commit_queue.tsv      ← ★新設: 予約台帳(FIFO。flock保護)
    └── <agent>_lock_<hash>.lock/    ← 変更なし(owned-scope lockは残置)
```

### ロック階層(ToBe — 2段に簡素化)

```
L1: 予約台帳 (/tmp/shogun_commit_queue.tsv)
    │  flock → 1行write/read → flock解放(<100ms)
    │  目的: FIFO順序の保証+二重予約拒否
    │  ★改善: ロック保持<100ms(AsIsの数分〜34分から99.9%短縮)
    │
    └─ L2: git index.lock (.git/index.lock)
        │  順番が来たagentのみがgit commit実行
        │  pre-commit timeout=60s(AsIs 900s→93%短縮)
        │  ★改善: test_ninja_scope_commit.bats除外でデッドロック消滅
        │
        (L3/L4の再帰デッドロックは構造的に不可能)
```

### AsIs vs ToBe フロー比較

```
=== AsIs(現行) ===
Agent A: commit要求 ──→ flock -w 120(L2) ──→ git commit ──→ pre-commit(900s) ──→ 完了
Agent B: commit要求 ──→ flock -w 120(L2) ──→ 120s timeout FAIL ──→ retry ──→ FAIL...
Agent C: commit要求 ──→ flock -w 120(L2) ──→ 120s timeout FAIL ──→ retry storm...
                                                    ↑
                                              A が34分保持(デッドロック)

=== ToBe(予約台帳) ===
Agent A: 予約(<100ms) → 先頭 → git commit → pre-commit(60s max) → release → 完了
Agent B: 予約(<100ms) → #2 → sleep 3 → sleep 3 → ... → 先頭 → git commit → 完了
Agent C: 予約(<100ms) → #3 → sleep 3 → sleep 3 → ... → 先頭 → git commit → 完了
                                ↑                           ↑
                          予約は瞬時(ブロックなし)    FIFO順で確実に実行
```

### 問題1の根治: 自己デッドロック防止

予約台帳方式では直接的にはデッドロックを防止しない。デッドロックの根因は**pre-commitフック内でcommitツール自体のテストを実行すること**。

根治: `run_tests.sh affected`のpre-commit実行時に、`test_ninja_scope_commit.bats`を除外する(環境変数`PRECOMMIT=1`でスキップ)。このテストはCI/手動実行でカバーする。

### 問題2の根治: 長時間ロック保持の解消

予約台帳方式では、ロック保持時間は台帳の1行read/write(<100ms)のみ。git index.lockの保持はStep 3のcommit実行中だけで、その間も他agentは**予約**できる(待つだけ)。

追加改善: pre-commitフックのテスト実行にtimeout 60sを設定(現行900s → 60sに短縮)。超えたらpre-commit PASS扱いとし、CIで完全検証。

### 問題3の根治: リトライストーム防止

予約台帳により、同一agent_idの二重予約を拒否。既に予約済みならエラーではなく「順番待ち中」を返す。バックグラウンドプロセスの蓄積がゼロになる。

## §実装分解

| # | 内容 | 依存 |
|---|---|---|
| 1 | `scripts/commit_queue.sh` — 台帳管理(reserve/check/run/release) | なし |
| 2 | `scripts/ninja_scope_commit.sh` — commit_queue.sh経由に変更 | 1 |
| 3 | pre-commit hook — test_ninja_scope_commit.bats除外(PRECOMMIT=1) | なし |
| 4 | テスト — commit_queue.shの予約/順番/timeout/二重予約拒否 | 1 |

## §decision ledger

| 項 | 状態 |
|---|---|
| 予約台帳方式の導入 | 殿発案2026-08-05 03:56。裁可待ち |
| pre-commitテスト除外 | 提案(問題1根治)。裁可対象 |
| pre-commit timeout短縮(900s→60s) | 提案(問題2緩和)。裁可対象 |
| 台帳ファイルの配置 | 提案: `/tmp/shogun_commit_queue.tsv`(揮発性・再起動でリセット) |

## §因果リンク

- origin: `[[将軍commit_20分デッドロック_20260805]] -> [[pre-commit自己デッドロック+ロック長時間保持+リトライストーム]] -> [[予約台帳方式(殿発案)]]`
- → [[ninja_scope_commit]] 既存commitパス。本設計書で改修対象
- → [[test_ninja_scope_commit.bats]] デッドロック源。pre-commit除外対象
