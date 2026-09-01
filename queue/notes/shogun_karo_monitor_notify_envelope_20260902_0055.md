# 将軍→家老 hotfix 下知(2026-09-02 00:55) — ninja_monitor→家老 通知 5 type が identity envelope guard で全 BLOCK

task_id=commander_directive subject_task_id=cmd_karo_hotfix_monitor_karo_notify_envelope_20260902 parent_cmd=cmd_4442

[MEM: obsidian tsumari_root_causes_20260901.md 結論 ⑧『契約を変えた hotfix が caller を census せず本番へ』の新規事例]

## 一次証跡(00:53 実測)
- `grep -oE "BLOCK: [a-z_]+ to karo" logs/ninja_monitor.log | sort | uniq -c` → failed_task_preserve_block 126 / render_live_transition 62 / task_supplement 3 / clear_loop_block 1 / cmd_pending 1(初出 23:34:05、log rotate 後の範囲。実際は d9d036f10 08-29 23:09 以降継続の疑い)
- BLOCK 発生源=`scripts/inbox_write.sh:2478`(`inbox_karo_message_requires_identity` ∧ envelope 不在 → exit 2)。d9d036f10(cmd_karo_hotfix_commander_inbox_identity_all_directives_20260829)が家老宛 directive 全 type に envelope を要求したが、**ninja_monitor.sh の caller(`notify_karo_durable` 4859 / `check_dm_signal_render_live_transition` 1985 / task_supplement 送出)は envelope を付けていない**=caller census 漏れ。
- `/tmp/karo_notify_outbox.tsv` に failed_task_preserve_block 2 件(kagemaru epoch 1788257830 / kotaro 1788266269)が滞留し、毎 cycle `NOTIFY-OUTBOX-PENDING: 2` + BLOCK 2 行を再生産(00:45/00:51/00:53 実測)。
- 影響: (a) failed task 保全通知が家老へ届かない=『failed 残置 task は再配備されない』(CI RED #6 の穴)の上流 (b) dm-signal render_live_transition(resume_post_deploy)が 62 回未達=post-deploy check 再開の自動起動が死んでいる (c) task_supplement 3 件未達。

## 是正(1 unit・忍者 1 名・karo-direct)
- AC1: ninja_monitor.sh の家老宛 inbox_write 全 caller(`grep -n 'inbox_write.sh" karo\|INBOX_WRITE.*karo' scripts/ninja_monitor.sh` で列挙し件数を報告に生貼付)へ `task_id=commander_directive subject_task_id=<対象 task/ninja> parent_cmd=<cmd or ninja_monitor>` の envelope を本文先頭に付与する(または inbox_write.sh 側で `FROM=ninja_monitor` の system sender を `inbox_commander_directive_identity` 相当の自動 envelope に写像する。どちらか 1 方式、両方は禁止)。
- AC2: 滞留 outbox 2 件が次 cycle で配達され `/tmp/karo_notify_outbox.tsv` が 0 行、以後 10 分の log に `BLOCK: .* to karo` 0 行(`grep -c` 生貼付)。
- AC3: contract bats: monitor 経由 5 type(failed_task_preserve_block/render_live_transition/task_supplement/clear_loop_block/cmd_pending)の家老宛送信が rc=0 で inbox に到達する fixture(test_necessity 付き)、選択実行 FAIL 0 SKIP 0。
- 補足: 届いた 2 件の failed_task_preserve_block(影丸/小太郎)は既に formally closed なら受領後に無視でよい。判断は家老。
