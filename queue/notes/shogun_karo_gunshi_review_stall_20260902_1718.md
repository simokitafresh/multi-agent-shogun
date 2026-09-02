# 軍師 review_request 滞留 — 将軍一次確認 2026-09-02 17:18

[MEM: memory_db knowledge:d9a3f414192015db 2026-09-02T03:45 "session_save_20260902_0352" 同系列: 09-01 16:27 復帰点『軍師 idle flag 遅延 74 回/日→hotfix(小太郎)』= cmd_karo_hotfix_gunshi_idle_flag_lifecycle_20260901]

- 事象: cmd_4445(16:56:59)・cmd_4447(16:57:26)の report_review が軍師 inbox で未読 21 分。cmd_4445/4447/4446 の再 GATE は sg7_bundle_missing で BLOCK 中(16:56-16:57)
- 一次: 軍師 pane は `❯` 入力待ち(CTX 46%、1 shell=1800s 超の background)。/tmp/shogun_idle_gunshi 不在、/tmp/shogun_idle_gunshi.lock は 17:15 touch(stop hook は set_idle_flag を呼んだ)
- watcher: logs/inbox_watcher_gunshi.log 17:13:51 再起動以降 [BUSY]『no idle flag』→[WAKE-DEFER] を 17:13:52/17:14:57/17:15:25 の 3 回
- 判定: 昨日の hotfix(idle flag lifecycle)の再発。stop hook が flag を置いた直後に消える or 置けていない。ninja_monitor 17:04 も PSTREE-LONGRUN『treating as IDLE』で RENUDGE を送ったが届いていない

## 順序
1. 軍師を起こし cmd_4445→4447 の SG7 再レビューを回す(家老 lane。send-keys 直叩き禁止、inbox 経路で)
2. idle flag 消失の真因を 1 名の忍者へ hotfix 配備(昨日の cmd_karo_hotfix_gunshi_idle_flag_lifecycle_20260901 の fixture を再現→落ちる条件を追加。1800s 超 background shell との干渉を疑え)
3. 4445 CLEAR→cmd_4448 配備、4447/4446 CLEAR

## 二値AC
- 軍師 inbox の report_review 未読 0
- gate_metrics に cmd_4445/4447 CLEAR 各 1 行
- /tmp/shogun_idle_gunshi が軍師 `❯` 状態で存在(stat で確認)
