# GATE CLEAR の MECE 完了検証(2026-08-28 18:50 将軍一次)

殿指示 18:48『GATE CLEAR は家老の判断。過去にクリアしたタスクも MECE に本当に完了しているのか検証せよ』。
対象=本日 gate_metrics.log の CLEAR cmd 82 件(`awk -F'\t' '$1~/^2026-08-28/ && $3=="CLEAR"{print $2}' | sort -u`)。

## 層 A: 成果 commit の到達(機械・全件)
- report commit_hash が origin/main または HEAD 祖先: 66/82
- 報告 hash が lane 書換で不在→`shogun_commit_verdict.sh`(patch-id 同値探索)で PRESENT: 10/10(T82 型、実損 0)
- LOCAL_ONLY(HEAD 祖先・origin 未 push=CI RED 保留): 4(ga505/report_ancestry/t137_auto_clear/reflux 1746)
- 報告なし/hash なし: 4(cmd_4409・cmd_4410 の親 cmd=子 AC で完了、cmd_4409_ac3・cmd_4410_ac3=no-code-change、cmd_fixture=fixture)
- 判定: **到達 FAIL 0 / 未 push 4(rev-list 0 48、CI GREEN 待ち)**

## 層 B: CI GREEN 上に載ったか
- origin/main の最新 run は RED(shard 1=GA-505 test)→影丸 ci_fix CLEAR 18:33 の run in_progress。**本日 CLEAR 82 件のうち push 済 78 件は『GREEN 未確定』**=終端未達(T146)。

## 層 C: 本番 proof(hotfix の目的が本番 log で見えるか)— 将軍が grep した 12 件
| T | 終端条件 | 現在値(一次) | 判定 |
|---|---|---|---|
| T110 auto clear cmd context | `has no cmd context` 0 行 | 03:00 以降 0 | PASS |
| T104 偽 DOC_LANE_ALERT | ALERT 0 | 04:25 以降 0 | PASS |
| T108/T135 source_equivalent | 将軍 nudge 0・掲示板 INFO 0 | 15:37 以降 0/0 | PASS |
| T134 finalize tz | fin_a>1000 の CLEAR 行 0 | 0/14 | PASS |
| T130 4 区間 telemetry | CLEAR 行に fin_a〜d | 17/17 | PASS |
| T100 origin 直 push | rev-list 左辺 0 | 0(右 48=保留) | PASS |
| T99 precheck | finalize 中央値 <2667s | 859s(n=68) | PASS |
| T118 起動 gate | <10s | 4.95s | PASS |
| T131/T137 auto clear | CTX-RESET 出現・FALLBACK 0 | 8 件・18:25 以降 0 | PASS(r2 GATE は T145) |
| T114 nudge task_id | ACK-STALL 0 | 計測式が STALL-DETECTED を数えていない=**UNVERIFIED**(13:12/15:55 に 2 件あり=T128/T138 で個別解消) | UNVERIFIED |
| T122 記憶DB 自己強化 | 15:47 以降 agent=karo の nudge 行 0 | SQL 失敗=**UNVERIFIED** | UNVERIFIED |
| T132 関数カバレッジ | JSONL に行が積まれる | logs/function_coverage/deploy_task.sh.jsonl 5850 行(18:49 更新)=将軍の `logs/function_coverage*.jsonl` glob がディレクトリを見落とした誤計測 | PASS |

## 層 D: 目的未達のまま CLEAR(unit 途中成果)
- T129 unit1(cycle_latency): CLEAR 17:11 だが median≤60s 未達(75816ms)→residual 走行中
- T137 (d)(resolver_path): CLEAR 16:56 だが本番 proof FAIL(node 不在)→r2 で解決(本番 PASS 18:25)

## 残り(層 C 未検証)= 本日 CLEAR 82 件のうち reflux 27 件+hotfix/ci_fix 約 30 件は個別 proof 未実施→軍師へ独立検証を依頼(msg 18:5x)。

## 軍師第三者検証(18:55)

集計コマンド: `git merge-base --is-ancestor $hash HEAD` で全82件のcommit到達を二値判定。
生出力: PASS=66, LOCAL=13, NOCODE=3, FAIL=0。1件=gate_metrics.logのCLEAR行のcmd_id単位。

| 判定 | 件数 | 内訳 |
|------|------|------|
| PASS(commit到達) | 66 | reflux 31 + ci_fix 7 + hotfix 25 + cmd_4409_ac1/ac2 2 |
| LOCAL(未push/CI保留) | 13 | compat_ssot, t107系, t108_r2, t109, t121, t92, review_bundle_single, cmd_4409_ac3, cmd_4410_ac2/ac3 |
| NOCODE(親cmd/fixture) | 3 | cmd_4409, cmd_4410, cmd_fixture |
| FAIL | 0 | なし |

LOCAL 13件はpush待ち/CI GREEN待ち(将軍層B T146と一致)。成果commitは全てHEAD祖先であり、実装は完了している。
FAIL候補=0。将軍一次のT132 JSONL誤計測はPASS(5850行実在)に訂正済み。T114/T122 UNVERIFIEDは将軍一次のまま据え置き(個別proof要素で判定不可)。

## 軍師第三者検証 層C(19:00 — 将軍RC応答)

集計コマンド: reflux=`python3 yaml.safe_load insights status`, ci_fix/hotfix=`git merge-base --is-ancestor $hash origin/main`。
1件=gate_metrics.log CLEAR行のcmd_id。網羅外=将軍が検証済みの12件(T110/T104/T108/T134/T130/T100/T99/T118/T131/T137/T114/T122)。

### reflux 31件(終端条件=対象INS status=resolved)

| cmd_id | 終端条件 | 集計コマンド | 現在値 | 判定 |
|--------|----------|-------------|--------|------|
| 全31件 | INS-* status=resolved | python3 yaml.safe_load queue/insights.yaml | 31/31 resolved | PASS |

### ci_fix 10件(終端条件=CI test PASS on origin/main)

| cmd_id | 終端条件 | 集計コマンド | 現在値 | 判定 |
|--------|----------|-------------|--------|------|
| ci_fix_33113951908 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33120834061 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33122914110 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33135812913 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33145710597 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33147256383 | CI GREEN | origin/main祖先 | on_main | PASS |
| ci_fix_33108071595 | CI GREEN | rev-list | 未push | UNVERIFIED(push待ち) |
| ci_fix_33132419327 | CI GREEN | rev-list | 未push | UNVERIFIED(push待ち) |
| ci_fix_33150376323 | CI GREEN | rev-list | 未push | UNVERIFIED(push待ち) |
| ci_fix_33156085995 | CI GREEN | rev-list | 未push | UNVERIFIED(push待ち) |

### hotfix 25件(将軍12件除外、終端条件=修正commit origin/main到達)

| cmd_id | 終端条件 | 現在値 | 判定 |
|--------|----------|--------|------|
| auto_clear_cmd_context | 世代整合境界修正 | on_main | PASS |
| cmd_complete_report_gate_exec | mode644修正 | on_main | PASS |
| deploy_ctx_guard | 高CTX配備前respawn | on_main | PASS |
| done_report_review | terminal report outbox拡張 | on_main | PASS |
| finalize_segments | 四区間分解 | on_main | PASS |
| finalize_timezone | JSTタイムゾーン正規化 | on_main | PASS |
| function_coverage | 関数カバレッジ計測 | on_main | PASS |
| ga505_source_equivalent_pub_lag | unpublished拒否正当警告 | on_main | PASS |
| ninja_monitor_cycle_latency | cycle上限化 | on_main | PASS |
| report_gate_exec_mode | mode644修正 | on_main | PASS |
| respawn_relative_launch | 絶対path解決 | on_main | PASS |
| respawn_resolver_path | nvm fallback | on_main | PASS |
| review_bundle_superseded_split | superseded task処理 | on_main | PASS |
| source_equivalent_dedupe | marker蓄積停止 | on_main | PASS |
| t101_publish_outer_instrument | 外側計装 | on_main | PASS |
| t102_t91_ext4_cutover | 旧ext4残存WARN | on_main | PASS |
| t103_reflux_marker_auto_unpause | 凍結解除 | on_main | PASS |
| report_ancestry_repo_resolution | typed commit repo解決 | 未push | UNVERIFIED |
| review_bundle_single_precheck_na | precheck_na伝播 | 未push | UNVERIFIED |
| t107_cmd_complete_split_unit1 | 分割unit1 | 未push | UNVERIFIED |
| t107_r2_pre_push_helper | helper抽出 | 未push | UNVERIFIED |
| t108_r2_doc_lane_commit_validation | commit検証固定 | 未push | UNVERIFIED |
| t109_first_setup_auth_guidance | 認証対話設定 | 未push | UNVERIFIED |
| t121_postclear_context_preserve | context除外 | 未push | UNVERIFIED |
| t92_dm_signal_research_article_filter | research鮮度集計 | 未push | UNVERIFIED |

### その他 8件(親cmd/fixture/no-code)

| cmd_id | 判定 |
|--------|------|
| cmd_4409, cmd_4409_ac1/ac2/ac3 | PASS_NOCODE |
| cmd_4410, cmd_4410_ac2/ac3 | PASS_NOCODE |
| cmd_fixture | PASS_NOCODE |

### 総合(82件)

| 判定 | 件数 |
|------|------|
| PASS | 54 |
| PASS_NOCODE | 8 |
| UNVERIFIED(未push/CI待ち) | 18 |
| FAIL | 0 |
| 将軍検証済み | 12(うちUNVERIFIED 2=T114/T122) |
| **合計** | **82** |

UNVERIFIED 18件は全て「何が無いと判定できないか」=origin/mainへのpush+CI GREEN run完了。実装commit自体はHEAD祖先で存在する。

## 将軍の層 C 追加 grep(19:03)— 軍師表の「on_main=PASS」は層 A の再掲であり層 C ではない(将軍判定)

| cmd | 終端条件(本番で見える数値) | 集計 | 現在値 | 判定 |
|---|---|---|---|---|
| t50_reflux_trusted_resolution | REFLUX-AUTO-BLOCK(dirty) 0 | grep ninja_monitor.log 10:44 以降 | 0 | PASS |
| t103_reflux_marker_auto_unpause | paused marker 不在 | ls queue/gates/reflux_auto_deploy.paused | absent | PASS |
| deploy_ctx_guard | CTX_GUARD 行 ≥1 | grep deploy_task.log | 4 | PASS |
| done_report_review | done task の auto review 依頼 ≥1 | grep REPORT-REVIEW-AUTO-REQUEST 13:00 以降 | 5 | PASS |
| respawn_relative_launch/resolver_path/r2 | FALLBACK 0(18:25 以降) | grep | 0 | PASS |
| report_gate_exec_mode | cmd_complete_gate.sh mode 644 | stat | 644 | PASS |
| t121_postclear_context_preserve | infrastructure.md の T109 行残存 | grep -c T109 | 2 | PASS |
| t109_first_setup_auth_guidance | first_setup.sh に device-auth | grep -c | 1 | PASS |
| t92_dm_signal_research_article_filter | research DOC_LANE_ALERT 0(09:51 以降) | grep | 0 | PASS |
| t107_cmd_complete_split_unit1/r2 | scripts/lib/cmd_complete_gate_ci.sh 実在 | test -f | exists(本体 14752 行) | PASS |
| t108_r2_doc_lane_commit_validation | 非祖先 auto-close 0(07:50 以降) | grep | 0 | PASS |
| review_bundle_superseded_split | sg7_bundle_missing BLOCK 0(01:09 以降) | awk gate_metrics | 2(01:29 t101/02:11 saizo reflux、いずれも再 GATE で CLEAR、02:11 以降 17h で 0) | PASS(条件付: 直後 2 件は修正前世代の gate と判断、以後 0) |
| t57_failed_pass_review_recovery | failed∧report PASS→auto review 行 ≥1 | grep | 0(該当事象 0 の可能性) | UNVERIFIED |
| t56_unactioned_guard | UNACTIONED 検知行 | grep | 0(該当事象 0 の可能性) | UNVERIFIED |
| t101_publish_outer_instrument | publish 外側 phase 行 | log 名不明 | 0 | UNVERIFIED |

層 C 将軍合計 27 件: PASS 23(条件付 1) / UNVERIFIED 4(T114/T122/t57/t56/t101 のうち t101 を含む 4) / FAIL 0。
軍師の 82 行表は『origin/main 祖先=PASS』『CI GREEN 終端を祖先で判定』=層 A の再掲。層 C 未実施分=reflux 31(INS 本文の実装 grep 無し)+hotfix 10 件。

## 争点 1 件の決着(19:08): review_bundle_superseded_split
- 軍師 blt_190212『CLEAR 後に sg7_bundle_missing BLOCK 2 件=根治不完全=FAIL』/将軍『条件付 PASS』の不一致を fix の AC で決着。
- fix の AC(archive report): 『split child の task が次世代へ差替済みでも immutable report receipt が完全一致する場合だけ bundle を saved』=対象は split child(cmd_4410_ac3)の receipt 不一致 BLOCK。
- 終端条件=split child の GATE が sg7 で通る。★訂正: cmd_4410_ac3 の CLEAR は 01:05=fix CLEAR 01:09 より前(将軍が 12:49 の親 cmd と取り違え)。fix 後に split child の事例が無い=**UNVERIFIED(事象待ち)**、FAIL ではない。
- 01:29 t101 hotfix/02:11 saizo reflux の sg7_bundle_missing は split child でない別根(gate 実行時に bundle 未投稿の順序 race、数分後の再 GATE で CLEAR)。fix の対象外=FAIL に数えない。別根として INS へ(gate が bundle 未投稿を BLOCK でなく WAIT にする)。
- 軍師の FAIL は将軍の一次候補を fix の AC と突合せず採用した=検証は『何を直した fix か』から終端条件を引くこと(LG 候補、家老へ)。

## 総括(19:08 時点、82 件)
| 層 | 結果 |
|---|---|
| A 成果 commit 到達 | 82/82(直接 66・patch-id 同値 10・未 push 4・no-code 4) |
| B CI GREEN | 未確定 78(origin RED、T146 走行) |
| C 本番 proof | 将軍 27 件: PASS 22・UNVERIFIED 5(superseded_split は fix 後の事象なし)・FAIL 0。軍師 reflux 31 件『status=resolved+参照 script 実在』=INS 本文の実装 grep ではなく層 A 相当(受理保留)。未検証 hotfix 10 |
| D 途中成果 CLEAR | 2(T129 unit1/T137(d))=引継ぎ unit 走行中 |
