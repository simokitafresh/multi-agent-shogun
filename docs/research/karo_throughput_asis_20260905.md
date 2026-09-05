<!-- gist-master: aeaadf72f858a63ab8a1259d43d6aade karo_throughput_asis_20260905.md -->
# 家老スループット AsIs — 家老が実行する script / hook / gate の速度台帳と枠外コスト(2026-09-05 14:45、殿下問 14:35)

> 殿 14:35『家老がボトルネックになるのは構造的にある程度しょうがない。解決は家老が触る script の圧倒的な拘束(固定)しかないのでは。家老が実行する script/hook/gate をリストアップして速度をまとめ、家老に特化したスループットの枠外部分も調査せよ』。
> 数値は全て 2026-09-05 00:00〜14:40 JST の一次ログ(logs/defense_overhead.jsonl 26,066 行、logs/gate_metrics.log、logs/publisher_daemon.log、logs/ninja_monitor.log、実測 hook 起動)から集計。集計コマンドは各表の末尾。**推測は「(未計測)」と明記**。

## §0.0 前提条件と我らのスタイル
- 対象: multi-agent-shogun の家老(Codex gpt-5.6-sol、tmux pane shogun:2.1)。家老の仕事=cmd 受領→分解→配備(deploy_task)→報告受領→review 受理(review_approval)→合流(publisher c2a)→GATE(cmd_complete_gate)→archive。忍者 6 名の直列の受け口。
- 目的: 家老 1 人が律速である事実を認めた上で、**家老の 1 動作あたりの時間**と**家老の手を止める待ち**を数値で分け、どこを拘束(固定・短縮)すれば便が回るかを決める材料にする。機能追加ではない。
- スタイル: シンプルに解決/既存の計測(defense_overhead)を使う/新規の複雑さを足さない/測ってから直す/壊さない/可逆に 1 cmd ずつ/別 LLM が読んでも同じ結論。
- 決定権: 殿。本書は調査のみ。実装は殿 go の後に cmd 単位。

## §1 家老が実行する経路の一覧と速度(1 日実測)

### §1.1 家老が自分で呼ぶ script(instructions/karo.md・context/karo-operations.md・skills/karo-* の現物から抽出)

| 経路 | 役割 | 今日の回数 | p50 | p95 | 合計/日 | 備考 |
|---|---|---|---|---|---|---|
| `scripts/deploy_task.sh`(/karo-direct 含む) | 忍者へ配備 | 20(deploy_total) | 28.3 s | 50.0 s | 608 s | 1 配備 = 約 30 秒。外部 repo(DM-signal)は worktree 準備を含む |
| `scripts/review_approval.sh` | 軍師 LGTM→家老 accept | 38 | 10.0 s | 21.0 s | 409 s | 内訳 check_id(gunshi_lgtm/karo_accept)は 0 ms=**10 秒の正体が未計測**(review_log 7,000 行の YAML 読込が疑い) |
| `scripts/cmd_complete_gate.sh` | GATE 判定 | 107 行(CLEAR 31/WAIT 66/BLOCK 10) | — | — | — | function timing は今日 0 行(計測が落ちている)。**CLEAR までの経過 p50 1,212 s / p95 5,017 s(n=30)** |
| publisher c2a merge(`publisher_c2a_merge`) | 報告 commit の origin 合流 | 83 行 | (未計測) | (未計測) | — | 1 回あたりの所要がログに無い。要計測 |
| `scripts/inbox_read.sh karo` / `inbox_mark_read.sh` | inbox 処理 | mark_read 3,615(全 agent) | 64 ms | 306 ms | 1,124 s(全 agent) | 家老分の按分は未計測 |
| `scripts/inbox_write.sh` | 忍者/将軍/軍師へ送信 | 705(全 agent) | **1,004 ms** | **6,774 ms** | 1,611 s(全 agent) | persist 74 ms+delivery_verify 2 ms+capture 15 ms=約 90 ms。**残り約 900 ms(p95 6.7 s)は nudge(send-keys+確認ガード)=未分解** |
| `scripts/bulletin_write.sh` | 将軍宛報告 | 6 | 121 ms | 138 ms | 1 s | ただし memory_db_live_insert を経由すると §2.3 の health refresh(p95 24 s)を踏む |
| `scripts/karo_workaround_log.sh` / `lesson_write_karo.sh` / `insight_write.sh` | 台帳 | 8(lesson_write) | 335 ms | 498 ms | 6 s | 同上、health refresh を踏む |
| `scripts/semantic_search.sh` | 概念検索 | 1,347(全 agent) | 366 ms | 2,041 ms | 832 s | q11 等で多用。家老按分は未計測 |
| `scripts/gates/gate_karo_startup.sh` | /clear 復帰 | 3 | — | — | 53 s | 復帰 1 回 = startup gate 約 18 s+deepdive 2 本の replay(未計測、LLM 読込時間が主) |
| `python3 scripts/review_bundle.py` | SG7 bundle | (軍師側) | — | — | — | 家老は待つ側 |
| `scripts/archive_completed.sh` | 完了 archive | GATE CLEAR 時に自動 | — | — | — | — |

集計: `python3 - <<'PY'`(logs/defense_overhead.jsonl を timestamp=2026-09-05 で filter、source/check_id 別に p50/p95/合計)/ `grep ^2026-09-05 logs/gate_metrics.log | cut -f3 | sort | uniq -c` / `grep -c c2a logs/publisher_daemon.log`。

### §1.2 家老の 1 tool 呼出しごとに走る hook(.codex/hooks.json、Codex PreToolUse 5 本+PostToolUse 1 本)。将軍が `echo hi` 相当の payload で実測(14:41、無負荷)

| hook | 実測 wall | 本番 p50(defense_overhead) | 役割 |
|---|---|---|---|
| `codex_inbox_priority_guard.sh` | 93 ms | (未計測) | 将軍指示 180 秒放置で BLOCK(本日 11:3x に出口自己遮断の循環バグ→713d83ed4 で根治) |
| `codex_skill_execution_guard.sh` | 136 ms | 258 ms(n=2,832 全 Codex) | skill 実行証跡 |
| `pre-write-read-tracker.sh` | 5 ms | — | Read 追跡 |
| `pre-bash-combined.sh` | 139 ms | (未計測、内部 Guard 群) | Bash ガード束 |
| `pre-write-edit-combined.sh` | 6 ms | — | Edit ガード |
| `post-bash-combined.sh` | 14 ms | — | 後処理 |
| **合計** | **約 0.39 s / 呼出し** | 本番負荷時 約 0.6〜0.9 s | 家老の 1 日の tool 呼出し数は未計測(codex_skill_execution_guard 2,832 は Codex 7 名合算)。家老按分 400〜600 回なら **3〜9 分/日** |

加えて prompt ごと: `codex_user_prompt_submit.sh` 462 ms p50(n=495 全 Codex)、`three_layer_preflight` 95 ms p50(n=7,844 全 agent)。

### §1.3 家老を待たせる gate/lane(家老の手ではなく、家老が待つ時間)

| 待ち | 今日の実測 | 意味 |
|---|---|---|
| `WAIT:report_commit_main_ancestry` | gate_metrics の WAIT 66 行中 **47 行** | 報告 commit が origin/main の祖先になるまで GATE が進まない。monitor が **約 3 分ごとに再 GATE**(例: index_lock hotfix は 13:58→14:38 で 12 回 WAIT、40 分) |
| `ci_readiness: ci_evaluation_absent` | 7 行 | CI run が無い/未完 |
| `ci_push_state BLOCK` | 8 行 | remote ref 解決・report commit 無効 |
| 軍師 review(`gate_gunshi_report_precheck full_precheck`) | 118 回、p50 3.2 s、p95 12.6 s | 家老は結果を待つ |
| publisher `root sync BLOCK postsync_verify_mismatch` | 14:05〜14:13 で 7 回連続 | origin が 1 分毎に進む(台帳 batch)ため root の検証窓に入らない。家老の合流と競合 |

## §2 枠外コスト(家老の「作業」に数えられていないが家老の時間を食うもの)

### §2.1 CTX と /clear
- 家老 CTX は 11:21 14% → 14:1x 83% → 14:2x /clear 後 16%。**3 時間で 1 周**。復帰 1 回=gate_karo_startup 約 18 s(3 回/日 53 s)+deepdive replay 2 本(Phase 10+7、各 Phase で読込と自問。所要は未計測、体感 5〜10 分)+陣形図/inbox 再読。
- CTX を食う主因(推定、要計測): inbox 通知の本文(bulletin_notify は掲示板本文を丸ごと含む。将軍宛の doc-lane alert 6 本/日が家老の inbox にも入る)、capture-pane 出力、gate の長い stderr。

### §2.2 nudge と再読
- monitor の `KARO-PENDING-INBOX` / `RENUDGE-TRANSITION` が 1 分刻みで家老を起こす(14:37, 14:38)。家老が作業中でも UserPromptSubmit hook(462 ms)と inbox_read(receipt 発行)が走る。**nudge 回数/日は watcher ログの形式が変わっており 0 件と出た=計測経路が切れている**(要修正)。

### §2.3 memory_db_live_insert の health refresh(全 agent 共通、家老の critical path に乗る)
- `three_layer_health` 合計 **3,398 s/日**(refresh_window 1,738 s、refresh_verify 939 s、refresh_copy 784 s)。p50 は 0 ms だが **p95 24 s**。呼出し元=bulletin_write / insight_write / karo_workaround_log / lesson_write_karo / cmd_delegate / cmd_quality_log。家老が掲示板 1 本書くたびに最悪 24 秒待つ。

### §2.4 inbox_write の 1 秒
- p50 1,004 ms / p95 6,774 ms(n=705)。分解済み 3 phase の合計は約 90 ms。**残り 900 ms〜6.7 s は nudge(send-keys の timeout 5 s+確認プロンプトガードの capture)**。家老は 1 日に数十通送る=数分/日、しかも p95 側は「相手が busy で 5 秒待った」時間。

### §2.5 GATE の再実行
- WAIT の cmd は monitor が約 3 分ごとに cmd_complete_gate を再実行(各回 sg7/ancestry/ci 判定)。家老の手は要らないが、**GATE CLEAR までの経過 p50 20 分は家老の「便」の見かけの遅さ**として殿に見える。真因は §1.3 の ancestry 待ち=家老の c2a 合流が直列。

### §2.6 計測が落ちている箇所(本書で発見)
- `cmd_complete_gate_function_timing.jsonl` は今日 0 行、`deploy_task_function_timing.jsonl` も今日 0 行(deploy_total だけ defense_overhead に残る)。review_approval の内訳 check_id が全て 0 ms。→ **速くする前に計測が壊れている**。

## §3 家老律速の順位(数値で)

| 順位 | 項目 | 1 日の家老時間 or 待ち | 種別 |
|---|---|---|---|
| 1 | 報告 commit の origin 合流待ち(ancestry WAIT) | WAIT 47 行、1 cmd あたり 30〜40 分、CLEAR 経過 p50 20 分 | 待ち(家老の c2a が直列) |
| 2 | review_approval 10 s ×38=6.8 分+deploy 28 s ×20=10 分 | 約 17 分/日 | 家老の手 |
| 3 | hook 往復 0.4〜0.9 s ×(400〜600 回) | 3〜9 分/日(未計測) | 家老の手(見えない) |
| 4 | health refresh p95 24 s(掲示板/台帳書込みのたび) | 最悪数分/日 | 枠外 |
| 5 | /clear 復帰 3 回×(18 s+deepdive replay) | 15〜30 分/日(replay 未計測) | 枠外 |
| 6 | inbox_write nudge 1 s(p95 6.7 s) | 数分/日 | 家老の手 |

## §4 殿の仮説「家老が触る script の圧倒的な拘束」への回答(事実→判断)

- 事実: 家老が自分の手で回す script は実質 **7 本**(deploy_task / review_approval / cmd_complete_gate / c2a merge / inbox_read+mark_read / inbox_write / bulletin_write)で、既に「拘束」に近い。1 本あたりの時間は最大 30 秒で、**家老の手の合計は 1 日 20〜30 分**にすぎない。
- 事実: 家老が遅く見える時間の大半は **待ち**(ancestry 合流、review、CI、root sync 競合)と **枠外**(health refresh、/clear 復帰、nudge)であり、script の中身を速くしても順位 1 は消えない。
- 判断: 「拘束」は正しいが対象が違う。拘束すべきは **script の本数ではなく、家老の手を要する『合流』の回数**。報告 commit の合流を家老の手作業から外し(忍者報告→軍師 LGTM→publisher が自動で c2a→GATE)、家老は例外(FAIL・競合)だけ触る形にすれば、順位 1 が消え、家老の手は 20〜30 分/日のまま便が並列に回る。これは単一 publisher 設計書 v3.x U3(publisher daemon)の「auto-push ancestry」経路そのもので、今日 4 回 FAIL したまま理由が記録されていない(`auto_push_ancestry_retry.log` に FAIL 行のみ)。
- 判断 2: 順位 3〜6 は「速くする」ではなく「呼ばない」で消える。health refresh は書込みと非同期に(既に refresh_incremental_event 1,630 回は 0 ms=非同期経路は存在する。同期経路 refresh_window に落ちる条件を潰す)。/clear 復帰の deepdive replay は家老には Phase 単位の receipt が要るため短縮できないが、CTX を食う inbox 本文(bulletin_notify の全文同梱)を要約に変えれば /clear 回数が減る。

## §5 次の一手(候補。実装は殿 go の後、1 cmd ずつ)
1. 計測修復(順位 0): cmd_complete_gate / deploy_task の function timing が 0 行、review_approval 内訳 0 ms、watcher nudge 集計 0 件。**速くする前に測れる状態へ**。
2. auto-push ancestry の FAIL 理由をログへ(4 回/40 分 FAIL の真因)。真因が「root sync 競合」なら §1.3 の postsync_verify_mismatch と同根。
3. 合流の自動化(順位 1): 軍師 LGTM→publisher c2a→GATE を家老の手なしで回す。家老は例外のみ。
4. health refresh の同期経路を潰す(順位 4)。
5. bulletin_notify の本文同梱を要約+パス参照に(順位 5、CTX)。

## §6 因果リンク
- ← [[殿下問_家老律速の拘束_20260905_1435]] / ← [[単一publisher_asis_tobe_5w1h_20260902]] U3 auto-push ancestry / ← [[cmd_4393_karo-waste]](08-24 の workaround/配備反復集計)
- → [[karo_throughput_計測修復]] → [[合流の自動化]] → [[health_refresh_非同期化]]

## §7 訂正と追補(14:55、殿追補 14:50『gate clear 関連も家老の script。家老が待たされる原因は全て家老に関係する』)

### §7.1 訂正: 「function timing が今日 0 行」は将軍の集計誤り
- 事実: `logs/cmd_complete_gate_function_timing.jsonl`(231,797 行)と `logs/deploy_task_function_timing.jsonl`(151,032 行)には **wall-clock の timestamp 列が無く**、epoch は `execution_id` の末尾(μs)にだけある。将軍は timestamp 文字列で filter して 0 行と誤読した。計測は落ちていない。**落ちているのは「日付で集計できる形」**。
- 正しい集計(execution_id の epoch で 2026-09-05 を抽出):

| script | function | 今日の回数 | p50 | 合計/日 |
|---|---|---|---|---|
| cmd_complete_gate.sh | main(1 回の GATE 実行) | 121 | **9.2 s** | **42.7 分** |
| cmd_complete_gate.sh | check_report_commit_main_ancestry | 69 | 2.9 s | 59 分(※ main と重複計上) |
| cmd_complete_gate.sh | check_self_grade_commit_file_coverage | 72 | 5.1 s | 10 分 |
| deploy_task.sh | deploy_task_original_prepare_remote_tip_worktree | 38 | 5.0 s | 6.8 分 |
| deploy_task.sh | run_python_logged | 42 | 5.8 s | 5.3 分 |
| deploy_task.sh | maybe_notify_draft_review / generate_report_template / inject_semantic_concepts / yaml_field_set_batch | 42 each | 2.0〜4.1 s | 2.4〜3.6 分 each |

集計: `python3 -c` で execution_id 末尾 epoch を parse(本書 §5-1 の対象=timestamp 列の追加)。

### §7.2 追補: 家老に関係する「gate clear 側」の script(殿指摘。家老が待つ原因は全て家老 lane)
| script | 誰が起動 | 家老との関係 | 今日の実測 |
|---|---|---|---|
| `scripts/cmd_complete_gate.sh` | monitor(自動再 GATE)+家老 | CLEAR/WAIT/BLOCK を決める。WAIT のたび 9.2 s | 121 回=42.7 分/日、うち WAIT 66 |
| `cmd_complete_gate_auto_push_ancestry_wait`(同 script 内) | monitor | 報告 commit を自動で origin へ合流させる経路。**FAIL しても理由を書かない**(`auto_push_ancestry_retry.log` は PASS/FAIL のみ) | index_lock hotfix で 12 回連続 FAIL(13:58〜14:38) |
| `scripts/publisher_c2a_merge.sh`(74 行) | 家老/publisher | 報告 commit の合流本体。**所要時間の計測なし** | 83 行/日 |
| `scripts/safe_shared_main_ff.sh` | 上記から | root の ff 安全判定 | mode 100644(CI test #330 の対象) |
| publisher daemon `root sync` | daemon | root を origin に追随。`postsync_verify_mismatch` で BLOCK 連発 | 14:05〜14:13 で 7 回 |
| `scripts/gates/gate_gunshi_report_precheck.sh` / `review_bundle.py` | 軍師 | LGTM の前提。家老はここを待つ | precheck 118 回 p50 3.2 s |
| `scripts/ninja_monitor.sh` 再 GATE loop | daemon | WAIT cmd を約 3 分ごとに再 GATE | 上記 121 回の大半 |
| `scripts/review_approval.sh` | 家老 | 内訳 check_id(gunshi_lgtm/karo_accept)が **0 固定でハードコード**(L821/L826) | total p50 10 s の中身が不明 |

### §7.3 追補: 家老への配達遅延(watcher、最大の枠外)
- `logs/inbox_watcher_karo.log`(+.1、今日 3,143 行)。日付形式が `[Sat Sep  5 …]` のため §2.2 の「0 件」も将軍の grep 誤り。
- 今日: Wake-up 送出 **357 回**、うち `DELIVERY-LATENCY-WARN` **178 回**。**held p50 2,423 s(40 分)/ p95 6,609 s(110 分)/ max 7,175 s**。比較: 疾風は held p50 209 s、n=11。
- 意味: 家老宛メッセージの半分は、家老が busy のため **40 分〜2 時間遅れて届く**(watcher が busy 中の send-keys を抑止して lease を更新し続ける)。将軍の下知も忍者の報告も同じ列に並ぶ。これが「家老が遅い」の正体の 1 つで、家老の手(20〜30 分/日)の 100 倍の規模。
- 集計: `cat logs/inbox_watcher_karo.log.1 logs/inbox_watcher_karo.log | grep 'Sep  5' | grep -oE 'held [0-9]+s'` を sort して分位。

### §7.4 律速順位の更新(§3 を置換)
| 順位 | 項目 | 実測 |
|---|---|---|
| 1 | 家老宛配達の held(busy gating) | p50 40 分、p95 110 分、178 回/日 |
| 2 | 報告 commit の合流待ち(ancestry WAIT)+auto-push FAIL 理由不明 | WAIT 47 行、CLEAR 経過 p50 20 分 |
| 3 | 再 GATE の CPU(cmd_complete_gate main 9.2 s×121) | 42.7 分/日 |
| 4 | health refresh 同期経路 | 3,398 s/日、p95 24 s |
| 5 | 家老の手(deploy/review/hook) | 20〜30 分/日 |

### §7.5 §5 の次の一手(更新)
1. **計測修復(殿 14:49 go)**: (a) function timing に ISO timestamp 列 (b) defense_overhead に agent 列 (c) review_approval 内訳を実測 (d) auto_push_ancestry FAIL に reason (e) publisher_c2a_merge に所要時間 (f) watcher の held を jsonl で日次集計できる形 (g) 上記を 1 本の `karo_throughput_report.sh` で毎日表にする。
2. 配達 held の解消(順位 1): busy gating の閾値/lease 設計の見直し(計測後)。
3. 合流の自動化(順位 2)。
