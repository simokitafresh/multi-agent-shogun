# 共有 root の index 後退(単一 publisher file 7 本が staged 削除)— 将軍一次確認と復元 2026-09-02 18:30

[MEM: memory_db knowledge:193b099ff6008e23 2026-09-02T02:46 "内容後退 3 回目=origin eaabc7d93(小太郎 reflux ancestry merge)が設計書 file 削除" — 同型の再発]

## 事実(一次)
- 18:28 `git diff --cached --name-status`: D 7 本(scripts/publisher_queue.sh, scripts/publish_artifact.sh, scripts/lib/lock_run_shim.sh, scripts/lib/publisher_event.sh, tests/unit/test_publisher_queue.bats, test_publish_artifact.bats, test_gate_dual_read.bats)+M 11 本(extract_command_files.sh から exec_prefix 判定を除去=3acaae149 を打ち消す等)。合計 18 file、1974 行削除。**worktree からも file が消えていた**(ls: No such file)。
- 発生源の痕跡: ninja_monitor 17:52:40 `AUTO-COMMIT-STAGED-PRESERVE: saizo preserving scope-out staged file:` に同 7 本(才蔵 auto-commit-before-clear が旧 tree の staged を root へ「保全」)。
- 影響: 疾風 hotfix(extract_target_path exec order)の commit が『共有 main の staged 差分と worktree の parity 不一致』で BLOCK(疾風 pane 18:2x)。= cmd_4445/4447/4446 CLEAR の鎖の先頭が止まっていた。
- 将軍処置 18:29: `git restore --source=HEAD --staged --worktree -- <18 paths>`(path 指定、HEAD=origin 到達済み内容へ戻すのみ)。結果: staged 0、5 file が HEAD と一致、exec_prefix 判定 4 箇所復帰。

## 順序(家老)
1. 疾風に commit 再試行を指示(root index はクリーン。parity 不一致は解消しているはず)。BLOCK が残るなら BLOCK 文言を掲示板に生貼付
2. 疾風 hotfix→軍師 review→統合→軍師 precheck 再実行(cache key は script hash 含むため自動無効)→cmd_4445→4447→4446 の SG7 再 bundle→GATE CLEAR→cmd_4448 配備
3. **CI RED の ci_fix 配備**: push lane は 17:40 から `WAIT ci=RED ci_fix_active=0 push=0` で停止、unpushed 34。run 33611379072 shard-1 `shard failed: rc=1 result='FAIL'`。家老 ci_fix task は旧 run 33499882240 のまま。idle 忍者へ `task_type: ci_fix` + `ci_run_id: 33611379072` で配備(殿裁定 07-16、家老 D0 禁止)
4. 才蔵 auto-commit-before-clear の「scope-out staged preserve」が旧 tree を root へ持ち込む経路を hotfix 1 名(発端 17:52:40 の 7 本を fixture に)

## 二値AC
- `git diff --cached --name-only | wc -l` = 0 が維持されている(次 loop で再確認)
- gate_metrics に cmd_4445 CLEAR 1 行
- push lane log に `push=1` 1 行(unpushed 0)
