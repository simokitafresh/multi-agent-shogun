<!-- gist-master: pending -->
# commit予約台帳 — 共有git indexの直列化 AsIs/ToBe 5W1H設計書 v1.0

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
