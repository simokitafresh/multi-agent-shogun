<!-- gist-master: 70b946c022cd5f6f81195ab837b7a7eb ninja_block_fail_root_cause_asis_tobe_20260905.md -->
# 忍者の BLOCK/FAIL はインフラバグか — AsIs/ToBe 設計書 v3.0(2026-09-05 23:05 殿『覚醒して再構築。全てに整合性。どこまで完了して次は何かを明確に』で全文再構築。数値を 22:59 現在値へ更新、§6 を状態機械の台帳に置換)

版履歴(記録のみ): v1 16:15 軍師 APPROVE 5 観点+家老 REJECT 7 点 / v2 16:25 7 点採用、家老 条件付き APPROVE 4 補正 / v2.1 16:30 4 補正採用=**設計閉** / v2.2 19:00 §2 再集計・§6.2 台帳新設 / v2.3 20:50 台帳追記 / **v3.0 23:05 再構築**。v2.x の本文は git 履歴(e343ccfdd 以前)。

## §0 前提とスタイル
- 殿の問い(16:03): 忍者が AC の品質不備・前提情報の不足・ルーチンの試行錯誤で BLOCK/FAIL になるのはインフラバグではないか。
- 対象: 忍者 6 名(Codex gpt-5.6-luna 4+Claude 2)。忍者は毎 task で記憶ゼロ。届く知識は task YAML への注入(deploy_task の assumptions/related_lessons/semantic_concepts)と report テンプレートだけ。
- 判定基準: 「忍者が知り得ない情報を要求して止めた」=発注側・環境側のバグ。「知り得た情報を使わなかった」=忍者の品質。数で分ける。
- スタイル: 既存機構の拡張のみ。新 gate/hook は 0。可逆に 1 cmd ずつ。実装は殿の go の後(殿 22:25『慌てて実装するな』)。本番(DM-Signal)には触れない設計(殿 22:27)。未計測は「(未計測)」。
- 数値の出所: `queue/reports`+`queue/archive/reports`(mtime 本日)、`logs/gunshi_review_log.yaml`、`logs/gate_metrics.log`、`logs/deploy_task.log`、`logs/karo_workarounds.yaml`。**2 時点**を併記する: T0=16:05(v2.1 の根拠)、T1=22:59(v3.0)。

## §1 結論(先に。T1=22:59 現在値)
1. **はい、大半はインフラバグ。** 本日の軍師 review 79 件中 FAIL 22 件(28%)。その 22 回のうち忍者が知り得た情報を使わなかったもの(E)は **2 回(9%)**。残り 20 回は発注(A)・環境(B)・ルーチン(C)・検出器偽陽性(D)=忍者側では防げない。T0 からの増分 19 件は全て LGTM/APPROVE で、FAIL は 22 で不変。
2. **コスト**: FAIL を経た cmd の deploy→CLEAR は p50 94 分、経なかった cmd は p50 49 分(T0 実測 n=4/17。T1 未再計測)。1 回の FAIL ループで所要が約 2 倍。
3. **真因は 1 つ**: 忍者に届く情報が task YAML だけなのに、AC を書く側と環境が「書く前提」を持たない。Level5(事前コンテキスト提供)の欠落。
4. **今日直したものは全て C/D(インフラ側)**: 5 件(§6 台帳 F-1〜F-5)。E を直す作業は 0 件で正しい。
5. **ToBe の本体(T1 注入・T2 validator・T3 routine・T5 構造記録)は実装 0**(grep: environment_refs 0 / routine_refs 0 / preconditions_validate 0 / failure_origin_code 0、22:59)。設計は閉じている。次の一手は §6.3。

## §2 一次データ(T0=16:05 / T1=22:59)

### §2.1 本日の報告
| 終端 | T0(74 本) | T1(88 本) |
|---|---|---|
| completed/PASS | 63 | 79 |
| failed/FAIL | 4 | 7(才蔵 midx_lock、疾風 hanzo_failed_inventory・4477(honest FAIL)・dirty_ownership_audit、小太郎 inbox_priority(honest FAIL)、+2) |
| completed/FAIL | 1 | 1 |
| revision_requested | 3 | 0(飛猿 ci_fix は終端) |
| pending | 3 | 1 |
| hook_failures>0 | 5 | 4 |

### §2.2 軍師 review と FAIL 理由
| 項目 | T0 | T1 |
|---|---|---|
| review 件数 | 60 | 79(LGTM 53 / FAIL 22 / APPROVE 4) |
| FAIL | 22(37%) | 22(28%) |
| FAIL 理由 上位 | AC bc:no 13 / LG043 保留語 3 / suite FAIL・timeout 2 / lessons_useful 1 / marker 1 / attribution 1 / vercel_phase 1 | 同じ 22 件(増分 0)。生値上位: `AC1 bc:no` 6、`reporting bc:no` 3、`AC2 bc:no。suite FAIL/timeout` 2、`LG043→LG106→FAIL` 1、`marker未publish/receipt不在` 1 |

### §2.3 FAIL ループの実例(同一 cmd の verdict 列。T0 と同じ、追加なし)
| cmd | 列 | 何で止まったか |
|---|---|---|
| recon2_4449_u2_revalidate / 4448_u1 | FAIL×3→LGTM | fixture 非決定(PD-142)が根治されるまで |
| ci_fix 33939652526(才蔵) | FAIL→… | worktree が古い(B) |
| hotfix_deploy_external_worktree_timeout | FAIL×3→LGTM | 外部 repo worktree 準備 312〜420 s(B) |
| cmd_4475 | FAIL×2→LGTM | AC2 の lint が不可能(script 不在)→将軍が AC 訂正(B) |
| cmd_4476 | FAIL→LGTM | task YAML 重複 field(deploy_task バグ)+precheck cache 偽 FAIL(D) |
| recon2_dirty_ownership_audit | FAIL×3 | 監査範囲が下知で 2 回変わった(A、将軍の追補) |

### §2.4 忍者が「無かった」と書いた情報(unclear_points / discretion_fills。T0 と同じ)
隔離 DB の名前・接続法(疾風 4477)/ clone 絶対 path(疾風 audit)/ artifact 実体 path(疾風 ga580)/ clean-repro recipe path(才蔵)/ 『明示 deployment target』の field 定義(飛猿)/ 『公開済み』の判定基準(飛猿)/ task YAML と cmd の不一致(小太郎 4476)/ 『現行許可』の解釈(半蔵)。

### §2.5 hook_failures(忍者がルーチンで踏んだ BLOCK)
| 内容 | T0 | T1 |
|---|---|---|
| bats 直接実行→heavy-job-admission BLOCK(正規=run_tests.sh file) | 3 | 3 |
| db_capability_launcher 直叩き→Guard14(正規=/db-check 2 段) | 2 | 2 |
| ci_clean_repro single-flight 解決不能 | 2 | 0(半蔵 ci_fix で構造的に消滅) |
| 4476: 2 gate 矛盾で status 再提出 3 回 | 1 cmd | 1 cmd(バグ#1 で以後は自動遷移) |

### §2.6 deploy/gate 側 BLOCK(家老 lane、忍者は待つ)
| 箇所 | T0 | T1(gate_metrics 本日 BLOCK 行 70 のうち all_gates_passed 42 を除く 28) | 性質 |
|---|---|---|---|
| gate report_commit_main_ancestry | 7 BLOCK+47 WAIT | 8 | 合流待ち(別書 karo_throughput §4.2、便時間の 66%) |
| gate **ci_push_state** | (未記載) | **10** | push lane の状態不一致。T0 未記載=v2.1 の見落とし。内訳は日次表で追う(§6.3 N-3) |
| gate no_task_parent_report(FAIL_VERDICT) | — | 3(疾風 4477 / hanzo_failed_inventory / dirty_ownership_audit) | honest FAIL の親契約。バグ#5/6 の系 |
| gate sg7_bundle_missing_or_invalid | — | 2 | SG7 bundle 欠落(影丸 v3 系) |
| gate parent_cmd_contract | 1 | 2 | 契約不一致 |
| gate dm_signal_production_smoke_failed | 2 | 2 | 偽陽性(飛猿 hotfix 済み。再発なし) |
| deploy UNIVERSAL_SHARD(AC 3 本以上は shard 必須) | 3 | 4 | 発注形式(A) |
| deploy DOC_LANE_ROUTING | 3 | (本日 log では 0。家老 blt_220246 で GA-587 配備が BLOCK=正) | 経路判定(正) |
| deploy pending own report | 2 | (未再計測) | 前 report 未終端 |

集計コマンド(再現用): reports=`python3` で mtime 本日の YAML の status/verdict/hook_failures.count を Counter、review=`gunshi_review_log.yaml` の timestamp 本日を verdict/fail_reasons で Counter、gate=`grep '^2026-09-05' logs/gate_metrics.log | grep BLOCK | awk -F'\t' '{print $4}' | sed 's/:.*//' | sort | uniq -c`、deploy=`grep 2026-09-05 logs/deploy_task.log | grep -oE 'BLOCK[^:]*: [A-Z_]+' | sort | uniq -c`。

## §3 分類と判定(FAIL 22+hook 8+deploy/gate BLOCK を 5 種へ)
### §3.0 分類規則(家老②: A/B は相互排他でないため primary を一意化)
- 1 event に primary 1 つ+secondary list。primary の優先順: **D(検出器/環境の偽陽性・非決定)→ B(環境事実が task に無い)→ A(環境事実を全て与えても判定不能な未定義語・不可能条件)→ C(正規経路の案内なし)→ E(知り得た情報を使わなかった)**。
- E は LG043 の各 event で原文と検出 span を再照合し、『実装前後で』等の部分一致は D へ。本日 4 event 中 2 event(agent_respawn_preserve_active 09:26/09:29)は 1 WA(部分一致偽陽性、karo_workarounds 2026-09-05T00:29:55Z)の波及→ D。**E=2**(release_idle_redone_race、4475)。
- primary の一意化は T5(failure_origin_code)が入るまで将軍の事後分類(家老⑦)。

| 分類 | 定義 | 本日件数(T0 概算、T1 で不変) | 判定 | 例 |
|---|---|---|---|---|
| A 発注(AC 品質) | 環境事実を全て与えても判定不能な AC | FAIL 3+deploy 4 | インフラバグ(発注の型) | 『明示 deployment target』『公開済み』、AC 3 本で shard BLOCK、下知で範囲が変わる |
| B 環境(前提不足) | 存在する環境事実が task に無い | FAIL 7+suite 2 | インフラバグ(注入の欠落) | 隔離 DB 名、clone path、artifact path、recipe path、baseline が赤、lint script 不在、worktree 準備時間 |
| C ルーチン | 正規コマンド/契約を毎回探す | hook 8(T1: 5)+FAIL 3 | インフラバグ(案内の欠落) | bats 直実行、db launcher 直叩き、single-flight、lessons_useful 契約、receipt/marker、status 遷移 |
| D 検出器/構造 | 忍者の成果と無関係に止まる | FAIL 6+gate 10(T1: 28)+WAIT 47 | インフラバグ(検出器) | fixture 非決定、precheck cache、prod smoke、重複 field、ancestry 合流待ち、ci_push_state、SG7 bundle、honest FAIL の approval 不能(バグ#5/6) |
| E 忍者品質 | 知り得た情報を使わなかった | FAIL 2 | 忍者側 | LG043 保留語の真正残存 2 |

- **E=2/22=9%**。殿の仮説は数で裏付けられ、T1 でも不変。
- 波及: A/B は「FAIL→家老 RC→再提出→再 review→受理」の 1 ループ(p50 +45 分)。C は忍者の 1 task 内で数分〜十数分。D は家老 lane の待ち(CLEAR 経過 p50 20 分、別書)。

## §4 なぜ起きるか(構造)
1. 忍者の入力は task YAML のみ。deploy_task は assumptions/related_lessons/semantic_concepts を注入するが、**環境の実体(隔離 DB・clone・artifact・正規コマンド)は誰も書かない**。cmd_save の check は語彙・数値・AC 数を見て環境名の有無は見ない。
2. AC の「充足可能性」を検証する場所が無い。cmd_save は文字列の形だけを見て、対象 repo の現物(baseline の状態・script の有無・field の定義)を見ない。
3. ルーチンの正規経路は hook の BLOCK メッセージで初めて忍者に伝わる(踏んでから知る)。忍者 Recovery に一覧が無い。
4. gate の偽陽性は個別に根治されている(本日 5 件、§6.1)が、発火のたびに忍者と家老の 1 ループを消費する。

## §5 ToBe(最小。既存機構の拡張のみ、新 gate/hook は 0。v2.1 で設計閉、v3.0 で変更なし)
| # | 何を | どこ(既存) | 消える分類 | 大きさ | 実装状態(22:59) |
|---|---|---|---|---|---|
| T1 | **environment_refs(明示 ID)注入**: cmd に `environment_refs: [localpg, dm_signal_clone, artifact_store, clean_repro_recipe]`、`projects/infra.yaml environments:` は canonical path/probe_id/verified_at/TTL への参照(秘密値なし)。probe は probe_id→追跡済み allowlist script(`scripts/probes/<id>.sh`)へ解決、引数 schema 検証。deploy_task の `inject_cmd_assumptions` が ID を解決し task YAML `environment:` に card を複製、未解決 ID は deploy BLOCK(発注側へ返る) | deploy_task.sh 既存注入 3 種の隣に 4 つ目+projects/infra.yaml | B 5〜7 件/日 | registry 1 表+注入関数 1 本 | **未着手**(grep 0) |
| T2 | **preconditions 構造 schema+1 validator**: cmd `preconditions: {baseline: {command, source_sha, executed_at, pass, fail, skip}, definitions: {<AC 内の語>: <判定式>}}`。validator は baseline を実行せず source_sha 一致と executed_at 鮮度だけ(<1 秒)。AC に『全量/lint/typecheck/公開済み/明示』が出たら対応 key を要求。**cmd_save と deploy_task --yaml の両入口**から同じ validator | `scripts/lib/cmd_preconditions_validate.sh` 1 本 | A 5 件/日+B 一部 | validator 1 本+schema 2 key | **未着手** |
| T3 | **routine_refs(最小 ID 集合)注入**: task_type×CLI で決まる routine ID(`tests_run`/`db_readonly`/`report_status`/`inbox`/`commit`)を task YAML `routine_refs:` に注入、本文は canonical registry(`context/karo-operations.md` §routine か skills)参照 | deploy_task 注入+registry 1 表 | C 8 件/日 | registry 1 表 | **未着手** |
| T4 | FAIL 理由の再注入(review_feedback を家老 RC で自動複製) | 既存 inject_task_modifiers 経路 | ループ 2 回目以降 | 既存 field | **保留**(T1〜T3 の効果計測後に要否判断。軍師 (5)) |
| T5 | **failure_origin_code の発生時構造記録**: report `failure_origin: {primary, secondary}`=忍者候補、gunshi_review_log FAIL entry `failure_origin_code: {primary, secondary, ninja_candidate_agreed, correction}`=canonical。日次表(karo_throughput_report)が集計 | report template+review_bundle field+日次表の列 | 分類が毎日二値で出る | field 2 つ+列 | **未着手** |
| T6 | D(偽陽性)は個別 hotfix 継続。合流待ちは別書 karo_throughput §7 | — | — | — | **継続中**(本日 5 件根治、§6.1) |

### §5.1 やらないこと
新 gate/hook の追加、AC の全文 LLM 判定、忍者への追加チェックリスト、レビュー回数の上限化。

### §5.2 二値(家老⑥: 『unclear_points=0』は Goodhart のため不採用)
- T1+T3: 次の 20 task で `environment_refs`/`routine_refs` の解決率 20/20、missing-premise 起因の家老 RC=0、軍師抜取 5 件で false-negative=0。
- T2: 『全量/lint/typecheck/公開済み/明示』を含む cmd の preconditions key 充足率 100%、両入口で同じ validator が呼ばれる contract test 1 本。
- T5: 次の 20 FAIL event 全てに failure_origin_code。

## §6 進捗台帳(状態機械。loop ごとに更新。殿 18:57/22:59)

状態の定義: **完了**=origin に収載し検証済み / **進行中**=着手済みで未 CLEAR / **未着手**=設計のみ / **保留**=条件付き。

### §6.1 完了(F: Fixed。全て C/D=インフラ側)
| # | 時刻 | 何が動いたか | 分類 | 証跡 |
|---|---|---|---|---|
| F-1 | 18:04 | バグ#1: report_field_set の revision_requested→completed 自動遷移(忍者が finalize を忘れる) | C | 軍師 D0 499eb2099 origin 収載 |
| F-2 | 18:10 | バグ#3: review_bundle の allow_archived 自動検出(archive 済み報告が single 処理不能) | D | 同上 |
| F-3 | 18:19→18:45 | バグ#5: files_modified 空の honest FAIL が approval 不能循環 | D | 将軍 D0(f4dbf1f46 は c2a で f69288720 として origin 収載)+家老 D0 d6842c066(all-no 厳格化)、軍師検証 PASS、20:31 kotaro で実運用初適用 |
| F-4 | 20:20 | fixture 陳腐化 8 FAIL(skill_feedback/publisher_single/SG7 bridge) | D(test 側) | 家老 D0 208df246d、CI run 33963211348 GREEN 14/14 |
| F-5 | 21:56〜22:08 | 家老 lane 残(karo_throughput 日次表・公開追補) | — | CI run 33967524404 GREEN(家老 blt_220833) |

### §6.2 進行中(P: in Progress)
| # | 何 | 分類 | 状態 | 担当 |
|---|---|---|---|---|
| P-1 | バグ#6: report_field_set で field 変更しても deploy_generation の hash が更新されず review_bundle が世代不一致 BLOCK。正規解=terminal publish 時の lifecycle receipt 再発行 | D | 家老 D0 着手(blt 記録)。origin での CLEAR は **(未確認)** — 次 tick で `git log origin/main -- scripts/report_field_set.sh` と gate_metrics の `no_task_parent_report`/`sg7_bundle` 減少で確認 | 家老 |
| P-2 | ci_push_state BLOCK 10 件の内訳 | D | v2.1 未記載の見落とし。日次表(karo_throughput_report.sh 待ち理由別)で内訳を出す | 将軍 loop |
| P-3 | honest FAIL∧LGTM∧approval 無し 20 分超の検知(kotaro 2h24m 放置の再発防止。既存『done∧CLEAR 無し 20 分』の failed 版) | D/運用 | 自動化ターゲットとして掲示板記録(Q6 20:23)。実装は未着手 | 将軍 D0 候補 |

### §6.3 次にやること(N: Next。上から順。実装は殿の go の後)
| # | 何 | 前提 | 二値 |
|---|---|---|---|
| N-1 | **T1+T3 を 1 cmd で起票**(environment_refs+routine_refs の注入。registry 2 表+deploy_task 注入関数 1 本+contract test 2 本)。cmd 番号は skeleton 採番(実在最大+1) | 殿の go(22:25『慌てて実装するな』。設計は v2.1 で閉、レビュー済み) | 次 20 task で解決率 20/20、missing-premise RC 0 |
| N-2 | **T2 validator を 1 cmd で起票**(両入口共有 `cmd_preconditions_validate.sh`) | N-1 の CLEAR(注入の型が固まってから) | 該当 cmd の key 充足率 100%、両入口 test 1 本 |
| N-3 | **T5 構造記録を 1 cmd で起票**(report/review_log field+日次表列) | N-1 と並行可 | 次 20 FAIL 全件に failure_origin_code |
| N-4 | P-1(バグ#6)の origin CLEAR 確認と、P-2(ci_push_state 内訳)を loop tick で | — | gate_metrics の該当 BLOCK が翌日 0 |
| N-5 | T4 の要否判断 | N-1〜N-3 の 20 task 計測後 | ループ 2 回目以降の同一 FAIL 件数 |

### §6.4 変わらないもの(この設計書が正しいことの証拠)
- E=2/22 は T0→T1 で不変。増分 19 review は全て LGTM/APPROVE。
- 今日の根治 5 件は全てインフラ側。忍者側を直した件数は 0。

## §7 レビュー判定の記録(圧縮。全文は v2.1)
- 軍師 16:13 APPROVE 5 観点(bc:no 内訳、E 見落としなし、T3 と SG の整合、T2 は記載義務のみ、T4 は効果後・T5 は cmd_4478 へ統合)。
- 家老 16:15 REJECT 7 点(E の根拠、A/B 非排他、T1 誤注入型、T2 --yaml 素通り、T3 肥大化、Goodhart 指標、T5 事後分類)→ 全採用(v2)。
- 家老 16:21 条件付き APPROVE 4 補正(WA id・E=2、4477/lint を B、probe allowlist、T5 canonical=review_log)→ 全採用(v2.1)。**設計閉**。
- v3.0 は数値更新と台帳の状態機械化のみ。分類規則・ToBe・二値は変更なし。再レビューは N-1 起票時の cmd に対して行う。

## §8 因果リンク
- ← [[殿下問_忍者BLOCK_FAILはインフラバグか_20260905_1603]] / ← [[karo_throughput_asis_20260905]](家老側の待ち、合流待ち 66%) / ← [[cmd_4477_AC3_隔離DB名なし]] / ← [[PD-142]](fixture 非決定)
- → [[Level5_事前コンテキスト提供]](context/growth-loop.md §11) → [[environment_refs_injection]](T1) → [[preconditions_validator]](T2) → [[routine_refs_injection]](T3) → [[failure_origin_code]](T5)
- origin: "[[殿下問_忍者BLOCK_FAILはインフラバグか_20260905_1603]] -> [[E=2/22_忍者品質は9%]] -> [[Level5欠落_注入の拡張T1-T3]] -> [[実装は殿go待ち]]"
