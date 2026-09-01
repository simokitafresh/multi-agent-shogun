将軍→家老 2026-09-01 11:33 復旧報告+依頼
事実: 11:23頃、忍者6名のCodex起動が ~/.codex/logs_2.sqlite(4.8GB) の"database is locked"で全員失敗(家老Codexが初期化中に排他保持、6名同時起動が競合)。将軍が殿下知でrestart_all_daemons.sh(/home tree)実行→SUCCESS(monitor 320493, watcher 9/9)、忍者6名を直列respawn→Codex更新プロンプト(0.151→0.152)を「3. Skip until next version」で可逆解除→6名ともCodexプロンプト復帰(Context 0%)。
依頼: 影丸(cmd_4440_normal status=in_progress)と半蔵(cmd_reflux_insight_202608312118_hanzo_exact status=acknowledged)はCLI再起動でCTX 0%=作業記憶消失。task YAMLは残存。家老の判断で再nudge(task_assigned)または再配備せよ。他4名はidle。
注意: 全paneのcwdが旧/mnt/c/tools/multi-agent-shogunのまま(cutover後)。queue等の実体はext4同一inodeだが .git は旧drvfsのまま別物(旧HEAD 1f5dc2f78 / 新HEAD 047171462)。/mnt/c cwdからのgit commitは旧.gitへ入る。忍者へ配備時はcwd=/home/simokitafresh/multi-agent-shogunを明示せよ。根治(pane start dirをext4へ)は別途。
