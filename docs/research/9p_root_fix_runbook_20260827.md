<!-- gist-master: 407d51465e18f5a941d9f45478fafbd0 9p_root_fix_runbook_20260827.md -->
# 9p 根治ランブック — /mnt/c(drvfs 9p) から ext4 へのリポジトリ移設と全軍ダウン時のトラブルシューティング

- 作成: 2026-08-27 17:45 JST(将軍)。殿指示 17:41「走行中のものが完了したら、新規に手を出さずに 9p 根治をやろう」「また全軍落ちる可能性があるから 9p に関するまとめを gist に共有。トラブルシューティングも事前に検討」
- 正本: `docs/research/9p_root_fix_runbook_20260827.md`(本ファイル)。cmd_4408 成果物=`queue/reports/hayate_report_cmd_4408.yaml`(AC1-5 実測)+cutover/rollback script(元ツリー b487c998f、origin 到達済)
- **改訂 20:50 JST(殿指示『覚醒してアップデート』)**: cmd_4408 GATE CLEAR(19:29)後の実態で全面更新。§2 は実測値へ、§3 は「cutover script の欠陥(最終 rsync がパス置換 commit を巻き戻す)」を発見し是正 hotfix を前提に組み替えた
- **改訂 23:10 JST(殿指示『runbook もアップデート』)**: cutover 実行済(22:00:15)。§3 に実行結果(7)、§5 を残件 23:10 へ、§6 に効果(ext4 実測)と cutover 後に顕在化した副作用 4 件を追加。以後 §1 の 9p 数値は歴史値。
- origin: `[[殿裁定_ext4移設やれ_20260827_1422]] -> [[9p_git_flock_RPC待ち_本日停滞3系統]] -> [[cmd_4408_ext4移設]] -> [[殿指示_走行完了後9p根治集中_20260827_1741]]`

## §1 何が起きているか(一次計測)

| 時刻 | 事象 | 一次証跡 |
|---|---|---|
| 08-27 13:38 | D-state(`p9_client_rpc`)9 プロセス、`git status` 60-120s、push timeout 3 回(外側 180s < lock 待ち 1200s) | ps wchan / defense_overhead.jsonl / 家老 pane |
| 13:4x | 疾風 compat bats 30 分で TAP 0 行(receipt writer が D-state) | ninja_monitor.log |
| 14:47 | `RENDER-LIVE-WATCH: origin repo unavailable` → `PANE-CHECK: Failed to list panes` → 全 agent を CLI-DEAD 判定 → respawn 3/3 失敗 | ninja_monitor.log 14:47:20-14:48 |
| 14:54 | **WSL 再起動**(`uptime` 8 min @15:02)。将軍・家老・軍師・忍者6・watcher・monitor が 14:54:48 に一斉起動=全 agent の記憶消失 | ps lstart / SINGLETON-TAKEOVER 14:54:30 |
| 14:54 | `/tmp/shogun-task-worktrees/*` 全消失(疾風3・才蔵3・飛猿5 prunable)。才蔵 T63 の主実装 commit bcfbc5e2d は object のみ残り main 不在(偽 CLEAR→cherry-pick 2360a18a7 で回収) | git worktree list / merge-base |
| 16:50 | `git status` **34.9s**、D-state 3、load 6.9/7.6/8.3 — 症状継続 | 将軍計測 |
| 17:38 | 将軍 `ninja_scope_commit` 2 分 timeout→`.git/index.lock` 競合 2 回 | 将軍計測 |

**構造**: `/mnt/c` は drvfs(9p, cache=5)。git/flock/stat が全て RPC。同時 git が重なると D-state で待ち、watcher/monitor の pane 列挙まで失敗 → 「全軍落ち」に見える。`/` は ext4(/dev/sdd、863G 空き)。

## §2 根治=場所を変える(cmd_4408、機構は足さない)

| AC | 内容 | 状態(17:45) |
|---|---|---|
| AC1 | `rsync -a /mnt/c/tools/multi-agent-shogun/ /home/simokitafresh/multi-agent-shogun/`(.git・data/・queue/・logs/・projects/ 含む)。複製先で git fsck/status/worktree prune+repair exit 0、HEAD・ls-files 一致 | **PASS**(19:03 report): rsync 完了、fsck/status/worktree prune+repair exit 0、HEAD 9880b4dbe・ls-files 2241=2241 一致。/home 側 41G |
| AC2 | 絶対パス `/mnt/c/tools/multi-agent-shogun` 93 ファイル(.claude/settings.json 10・.codex/hooks.json 8・scripts/config/hooks 24・crontab 2 行)を新パスへ置換する 1 commit を**複製先に**作る。旧パス残存 rg 0(logs/・queue/archive/・docs/research/・memory/ 除く)。auto-memory 鍵 `~/.claude/projects/-mnt-c-tools-multi-agent-shogun/` → `-home-simokitafresh-multi-agent-shogun` の複製手順を cutover に含める | **PASS だが要注意**: 置換 commit **5f6fa7569**(43 ファイル 103 箇所)は **/home clone にのみ存在**(origin/main・/mnt/c HEAD とも NOT_IN)。§3 の欠陥参照 |
| AC3 | `scripts/migrate_to_ext4_cutover.sh` / `migrate_to_ext4_rollback.sh`。cutover=(1)全忍者 task idle かつ家老・軍師 pane 入力待ちを capture で確認、満たさねば exit 2 (2)最終差分 rsync (3)crontab を新パスへ(旧行退避) (4)auto-memory 鍵複製 (5)/mnt/c 側 root に `MIGRATED_TO_EXT4.txt`。tmux 再起動はしない。rollback=crontab を戻し印を外すだけ(/mnt/c 側は無変更)。両方 `--dry-run` 副作用 0 | **PASS**(元ツリー b487c998f、origin 到達)。実装の現物: preflight=old/new root 実在・marker 不在・`queue/tasks/*.yaml` 全 idle・家老/軍師 pane 入力待ち・crontab に旧パス有。本体=最終 `rsync -a OLD/ NEW/`→crontab 置換(backup を `NEW/.migrate_to_ext4_crontab.backup`)→auto-memory 鍵複製→marker。rollback=crontab backup 復元+marker 削除のみ。**tmux 再起動・agent 起動はしない** |
| AC4 | /home 側で代表 bats 3 本以上 FAIL0/SKIP0、/mnt/c vs /home の wall 秒 before/after | **PASS**: 3 本 14/14・79/79・60/60 SKIP0。wall /mnt/c→/home = **16.91→9.03s / 71.44→54.86s / 76.27→40.22s**(−47%/−23%/−47%) |
| AC5 | cutover/rollback の bats(dry-run・idle 前提 exit 2・rollback 冪等)を元ツリーへ commit | **PASS**: `tests/unit/test_migrate_to_ext4.bats` 3/3 SKIP0(b487c998f)。副作用: この新 bats が timing ledger 未登録で CI 全 shard RED(『tests/unit not found』は表面)→小太郎 ci_fix 73f6c7a83 で GREEN(run 33067975881 success 20:44) |

## §3 いつ・どう切り替えるか(時系列)

1. **走行 3 件は全て CLEAR 済**(cmd_4408 19:29 / T76 半蔵 19:14 / T71 才蔵 19:43)。以後の新規 cmd・karo_hotfix・reflux 自動配備は停止中(殿裁定 17:41、家老 blt_174711 で reflux は可逆 marker で fail-closed)。忍者 6/6 idle(小太郎は ci_fix task の failed 残置を家老が終端中)。
2. **★cutover script の欠陥(20:48 将軍が現物確認、是正 hotfix を家老へ msg_204816)**: `migrate_to_ext4_cutover.sh:89` の最終 `rsync -a OLD/ NEW/` は `.git` も同期するため、/home clone の **パス置換 commit 5f6fa7569 は refs/heads/main が OLD の hash で上書きされ dangling になり、43 ファイル(`.claude/settings.json` 10 箇所等)も OLD 内容へ戻る**。そのまま切り替えると hook/gate/crontab の一部が `/mnt/c` を指したまま起動する。是正=最終 rsync の直後に冪等な relocate(旧→新パス置換+残存 rg 0 検証+NEW で 1 commit)を呼ぶ hotfix(`scripts/migrate_to_ext4_relocate.sh` 新設+bats)。**この hotfix の GATE CLEAR 前に cutover を打つな。**
3. **★21:45 全前提成立=`--dry-run` が `DRY_RUN: preflight PASS`(将軍一次)。** relocate hotfix f6348f9fa は 21:10 CLEAR→家老 converge e8c603e91 で local 0 0。途中で第 2 の欠陥: `pane_is_input_waiting` が最終非空行に `›`/`❯` を要求→Codex(status 行が末尾)/Claude(`❯` の後 NBSP+`⏵⏵` 行)で**現編成では常に BLOCK**=将軍 D0 5f8aea006(末尾 8 行内の prompt marker+busy marker 拒否、bats 7/7)。一般則: 「入力待ち」判定は CLI ごとの末尾形状で壊れる=fixture に両 CLI の実プロンプトを置け。
3'. **cutover 前提の確認(将軍、hotfix CLEAR 後)**: `bash scripts/migrate_to_ext4_cutover.sh --dry-run` が `DRY_RUN: preflight PASS` を出す(=全 task idle・家老/軍師 pane 待機・marker なし・crontab 旧パス有)。加えて `rev-list origin/main...HEAD` 0 0、origin tip CI success、`git worktree list` prunable 0。20:00 の実測: 6 月の stale `_cmd_1782_ready.yaml`/`_cmd_wf_speedup_ready.yaml`(untracked)が idle 判定を塞いでいた→`queue/archive/stale_ready_20260827/` へ退避済。
4. **cutover(殿の 1 行、可逆)**:
   ```
   cd /mnt/c/tools/multi-agent-shogun && bash scripts/migrate_to_ext4_cutover.sh --dry-run   # 手順表示・副作用 0
   cd /mnt/c/tools/multi-agent-shogun && bash scripts/migrate_to_ext4_cutover.sh             # idle 前提を満たさねば exit 2
   ```
   終了時に次の 1 行が表示される:
   ```
   cd /home/simokitafresh/multi-agent-shogun && ./shutsujin_departure.sh
   ```
   これが**日次起動と同じ 1 行**で、tmux セッションと全 agent が ext4 上で立ち上がる。旧 `/mnt/c` 側は無変更(印ファイルのみ)。
5. **cutover 後の一次確認(将軍)**: まず `grep -rl /mnt/c/tools/multi-agent-shogun /home/simokitafresh/multi-agent-shogun --exclude-dir=logs --exclude-dir=archive --exclude-dir=research --exclude-dir=memory --exclude-dir=.git | wc -l` = 0(relocate が効いた証拠)。次に `git status` の wall(目標 <2s)、`ps -eo stat | grep -c ^D` = 0、`defense_overhead.jsonl` の pre_push wall、watcher/monitor の起動ログ、Android アプリの Project Path を `/home/simokitafresh/multi-agent-shogun` へ変更(殿の手作業 1 箇所)。
6. **rollback(問題時)**: `bash scripts/migrate_to_ext4_rollback.sh` → crontab を旧行へ戻し印を外す → `cd /mnt/c/tools/multi-agent-shogun && ./shutsujin_departure.sh`。/mnt/c 側は cutover 中も無変更なので戻すだけ。

7. **★実行結果(2026-08-27 21:52-22:03)**: 殿が 21:52 に 4 の 1 行を実行→最終 rsync は D-state で約 8 分(9p 読出し律速。**端末に進捗が出ない**ため殿から 21:56『何も変わらないが待機していればいいのか？』=script 側の設計欠陥、T91 で N 秒毎の進捗 1 行を追加予定)→22:00:15 印 `MIGRATED_TO_EXT4.txt`→殿が shutsujin→22:02 新将軍が `/home` 上で復帰。5 の一次確認は全て成立: 全 pane cwd `/home`、crontab 新 2/旧 0、`git status` 0.08s、D-state 0、watcher/monitor 稼働、CI 1f5dc2f78 GREEN、auto-memory ロード可、Codex trust `/home` 実在。旧パス残存は migrate script 3 本と `config/settings.yaml.bak.*`・`config/cli_events.yaml`(消費者 0)のみ。relocate 置換 47 ファイルは NEW_ROOT で未 commit だった→家老が 1 commit `e644881f5` で push(0 0)。rollback は不要だった。

**タイミングの判断基準**: 全忍者 idle は cutover script が機械判定(exit 2)。殿が実行するのは「忍者が全員 idle と将軍が報告した直後」または翌朝の日次起動時。深夜 cron(ETL 4 本など)が走る時間帯は避け、cutover→shutsujin まで 5 分以内に連続実行する(その間 crontab は新パスを指すが tmux は旧、というねじれを短くする)。

## §4 事前トラブルシューティング(全軍ダウン時)

### 4.1 症状→原因→復旧

| 症状 | 一次確認 | 原因 | 復旧 |
|---|---|---|---|
| 全 pane が起動プロンプト(Context 0%)、陣形図は busy | `uptime`、`ps -eo lstart,args \| grep -E 'codex\|claude'` の起動時刻が揃う | WSL 再起動 or tmux server 死亡 | `y` で将軍復帰 → 家老が assigned/in_progress task を再配備(15:08 の型: 1通1単位で疾風/飛猿/才蔵)。**task worktree(/tmp)は消えている前提**で redeploy |
| ninja_monitor が全 agent を CLI-DEAD 判定して respawn 連発(成功 0/N) | ninja_monitor.log `PANE-CHECK: Failed to list panes` / `origin repo unavailable` | /mnt/c 9p stall(RPC 応答なし) | 何もしない(respawn は失敗し続ける)。**stall が解ける or WSL 再起動を待ち**、復帰後に CLI-DEAD-RESPAWN の cumulative_total を確認 |
| `Input/output error` on /mnt/c | `ls /mnt/c` がエラー | drvfs 切断 | 殿: `! echo pw \| sudo -S bash ~/mntc_remount.sh`(umount -l → mount drvfs)。07-05/08-19/08-27 再発 |
| `git status` 30s 超、D-state 複数 | `ps -eo stat,wchan:20,args \| awk '$1~/^D/'` が p9_client_rpc | 同時 git/flock の RPC 待ち | バースト待ち(13:38→13:48 で 9→0)。将軍は commit を再試行するだけ。**根治=ext4 移設** |
| commit が `.git/index.lock: File exists` | `ls .git/index.lock`、`ps -ef \| grep git` | 他 lane(runtime autopush/家老 converge)の git 実行中 | 待って再試行。lock を手で消すな(他プロセスの index を壊す) |
| 忍者の実装が commit 後に main 不在(偽 CLEAR) | `git merge-base --is-ancestor <hash> origin/main` | worktree 消失で dangling | `git cherry-pick <hash>` を shared main へ(家老レーン)。CLEAR 検分に merge-base を必ず入れる(LS-A09(45)) |
| 全 pane composer に同じ文字列が流入 | `tmux capture-pane` で `cd … && export PS1=` | 検証用 shutsujin が本番 session へ send-keys(shutsujin_departure.sh:584 `shogun:` 固定) | composer 行のみ消去(送信しない)、検証は別 socket/session で。900a6e204 で isolated session を尊重 |
| 軍師/家老が nudge を受け取らない | `logs/inbox_watcher_<agent>.log` に `INPUT-GUARD … not empty` | composer に未送信テキスト | composer を消去(家老が実施) |

### 4.2 ext4 移設後に想定される新しい失敗と手当

| 想定 | 手当 |
|---|---|
| 旧パスがどこかに残り hook/gate が旧ツリーを叩く | AC2 の rg 0 件。cutover 後に `grep -rl /mnt/c/tools/multi-agent-shogun` を logs/queue/archive/docs/memory 除外で再実行し 0 を確認 |
| auto-memory(MEMORY.md)が読めない | 鍵ディレクトリ複製(`~/.claude/projects/-home-simokitafresh-multi-agent-shogun/`)。将軍復帰時に MEMORY.md の自動ロード有無で判定 |
| crontab が新パスを指すが tmux が旧のまま | cutover→shutsujin を 5 分以内に連続実行。ねじれ中に走った cron は logs で確認 |
| DM-signal(/mnt/c/Python_app/DM-signal)は 9p のまま | 対象外(別 repo)。DM-signal 側の git 遅延は残る。次の候補として同じ手順で移設可 |
| Windows 側エディタ/Android アプリが旧パスを見る | Android: Project Path を新パスへ(殿 1 箇所)。Windows からは `\\wsl$\Ubuntu\home\simokitafresh\multi-agent-shogun` |
| /tmp の task worktree は再起動で消える(9p と無関係) | T70: `DEPLOY_TASK_WORKTREE_ROOT` 既定 `/tmp/shogun-task-worktrees` → `/home/simokitafresh/shogun-task-worktrees`(cutover 後の hotfix 1 本) |
| CDP(Chrome)の user-data-dir | `/mnt/c/temp` のまま(repo 外、UNC 拒否回避)=変更不要 |
| 最終 rsync が clone 側の commit を巻き戻す(§3-2) | relocate hotfix で rsync 後に置換を再適用。cutover 後の一次確認で旧パス grep 0 を必ず取る。一般則: **clone 側にだけ commit を作る設計は、後段の rsync で消える**=置換は rsync の後段に置く |
| runtime lane(autopush)が origin へ直接 push して shared main と再分岐 | cutover 前に converge(ours)+ff 単位で 1 本ずつ push し `0 0` にする(本日 3 回発生: T68/T81/20:36)。cutover 後も同構造は残る(INS 登録済) |

### 4.3 全軍ダウンからの復帰手順(将軍の型、本日実証)

1. `y` → 記憶DB `session_save_*` 最新を検索 → 手順どおり復帰(deepdive は receipt 行数で到達確認)
2. **陣形図を信じず** capture-pane 全 pane + `uptime` + ninja_monitor.log 14:4x-15:0x を読む
3. `git worktree list` で prunable を数え、in_progress/assigned task の忍者を家老へ 1通1単位で再配備
4. 各忍者の主実装 commit を `merge-base --is-ancestor` で main 祖先か確認(偽 CLEAR 検出)
5. `rev-list origin/main...HEAD` で分岐を測り家老へ converge+1 本ずつ push
6. artifact/todo_map を md 正本から再生成して公開、30 分 loop を再設定(cron は session 限り)

## §5 残件(23:10)

- ~~cutover~~ → 22:00 完了(§3-7)。~~T87~~ → 22:56 CLEAR(§6)。~~T83~~ → 22:57 CLEAR(分割設計書 `docs/design/cmd_complete_gate_split_design_20260827.md`)。~~T88~~ → 22:11/22:19 CLEAR。~~T93 ci_fix~~ → 23:03 CLEAR(shard7 quality-lock のパス依存、c6e823181)。
- T70(影丸 done、GATE 待ち): `DEPLOY_TASK_WORKTREE_ROOT` 既定を `/home/simokitafresh/shogun-task-worktrees` へ。
- T91(未): `config/cli_events.yaml` 旧パス 8 件・`~/.codex/config.toml` hooks.state 旧キー 7 件の掃除+起動 gate に旧パス残存 grep+cutover script の進捗出力。
- origin 直接 push レーンと shared main の再分岐(rev-list 2 21、本日 5 回目)=家老 converge 1 回/h。構造根治は INS 登録済。
- DM-signal(`/mnt/c/Python_app/DM-signal`)は 9p のまま=次の移設候補(同じ手順。DM-signal 側の `git` 遅延と偽 DOC_LANE_ALERT の一因)。

## §6 効果と副作用(23:10、ext4 稼働 1h10m)

### 6.1 効果(半蔵 T87、同一手順・同一計装で各 3 回。正本 `docs/research/ext4_speed_rebaseline_20260827.md`)

| 指標 | 9p before(§1) | ext4 after | 削減 |
|---|---|---|---|
| publish_total | 3770ms | 227ms | −94% |
| ninja_scope_commit git_commit / scope_sync | 9487 / 5846ms | 173 / 73ms | −98% / −99% |
| git status | 60-120s | 84ms | −99.9% |
| git push(実 push) | timeout 3 回/日 | 1.1s rc=0 | timeout 0 |
| deploy_task 配備 wall | 199-397s | 18.8-43.8s(中央値 23.9s) | −89% |
| D-state | バースト 9-13 | 0 | — |
| cmd e2e(deploy→CLEAR) | 中央値 2416s(13:05) | 1850s(N=3) | −23%。内訳は work 96-895s / **finalize 247-965s**(報告整形→軍師→家老の人手往復)=fs 律速が消えた後の支配項 |

残る律速: 実 push 1132ms(ネットワーク)/publish 外側 604ms(計装外)/finalize の人手直列。旧 T60(git_commit 本質短縮)・T12(publish 13 分分解)は 9p 上の値ゆえ前提消失で終了。

### 6.2 cutover 後に顕在化した副作用(4.2 の想定との突合)

| 事象 | 想定(4.2) | 実際 | 手当 |
|---|---|---|---|
| 旧ツリーの stale `_cmd_*_ready.yaml` が最終 rsync で `/home` に復活し `status: assigned` が再出現 | 未想定(§3-2 と同根: rsync が退避を巻き戻す) | 22:11 発生 | 将軍が再退避(`queue/archive/stale_ready_20260827/`)。一般則: **cutover 前の退避・置換は rsync の後段に置くか、rsync 後に再適用** |
| CI shard7 `missing shard receipt` | 未想定 | e644881f5 で RED(quality-lock test がパス依存) | 小太郎 ci_fix c6e823181「path independent」→CLEAR 23:03 |
| relocate 置換が NEW_ROOT で未 commit(dirty 47) | 4.2 行 8 で「置換は rsync の後段」と記述済 | 発生(commit 手順が script に無い) | 家老 1 commit e644881f5。script 側は relocate 後の commit を追加候補(T91) |
| 旧パス残骸(`cli_events.yaml` 8 件、`~/.codex/config.toml` 7 件) | 4.2 行 1(rg 0) | grep 除外条件外に残存、稼働影響 0 | T91 で掃除+起動 gate |
| auto-memory / crontab / Windows・Android パス | 想定通り | 問題なし(MEMORY.md ロード可、crontab 新 2/旧 0) | — |
| 偽 DOC_LANE_ALERT(research.md 200 件・infrastructure.md 1839 件) | 未想定 | 日付起点計数が移設で再発 | 疾風 GA502 hotfix 23:04 配備 |

### 6.3 一般則(次の移設=DM-signal に持ち越す)

1. 最終 rsync の**後段**に「置換→commit→退避の再適用」を script 内で完結させる(人手で拾ったのは 3 件)。
2. 長時間工程は端末へ進捗を出す(殿の待機判断を script が支える)。
3. cutover 直後の一次確認は §3-5 の 7 点+`grep -c 'read: false'`+`ls queue/tasks/_*ready*`+CI の最初の run 結論まで。
