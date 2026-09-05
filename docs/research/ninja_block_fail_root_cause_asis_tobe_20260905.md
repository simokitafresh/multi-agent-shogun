<!-- gist-master: 70b946c022cd5f6f81195ab837b7a7eb ninja_block_fail_root_cause_asis_tobe_20260905.md -->
# 忍者の BLOCK/FAIL はインフラバグか — AsIs/ToBe 設計書 v2.1(2026-09-05 16:30。v2 16:25 に家老 条件付き APPROVE 4 補正を統合。v1 16:15 に軍師 APPROVE 5 観点+家老 REJECT 7 点) / v2.2 19:00 loop 更新: §2 数値を 18:57 再集計(軍師 blt_185706)、§6.2 実装進捗台帳を新設

## §0.0 前提条件と我らのスタイル
- 殿の問い(16:03): 忍者が AC の品質不備・前提情報の不足・ルーチン作業の試行錯誤で BLOCK/FAIL になるのはインフラバグではないか。修正速度が遅くなっている。調査→設計書→家老・軍師レビュー。
- 対象: multi-agent-shogun の忍者 6 名(Codex gpt-5.6-luna 4+Claude 2)。忍者は毎 task で記憶ゼロから始まる(/clear)。知識は task YAML への注入(deploy_task: assumptions/related_lessons/semantic_concepts)と report テンプレートだけで届く。
- 判定基準: 「忍者が知り得ない情報を要求して止めた」なら発注側・環境側のバグ。「忍者が知り得た情報を使わなかった」なら忍者の品質。両者を数で分ける。
- スタイル: 既存機構(deploy_task の注入 3 種、cmd_save の check 群、gate_report_autofix、run_tests.sh、report_field_set)の拡張だけで解く。新しい gate/hook を積まない(07-21 殿裁定: 削るな速くしろ、ただし表示型を増やさない)。可逆に 1 cmd ずつ。推測は「(未計測)」。
- 数値の出所: 2026-09-05 00:00〜16:05 の `queue/reports`(+archive、mtime 本日 74 本)、`logs/gunshi_review_log.yaml`(本日 60 entry)、`logs/deploy_task.log`、`logs/gate_metrics.log`、`logs/karo_workarounds.yaml`。集計コマンドは §2 末尾。

## §1 結論(先に)
- **はい、大半はインフラバグ**。本日の軍師 review 60 件中 FAIL 22 件(37%)、FAIL を経た cmd は 12/32。その FAIL 22 回を原因で分けると、忍者が知り得た情報を使わなかったものは **2 回**(LG043 保留語。『実装前後で』を『後で』と部分一致した偽 BLOCK 1 WA が同一 phrase の再提出 2 event(rpt-692596e2/rpt-dc37a672)へ波及=偽陽性 2 event は D。WA=logs/karo_workarounds.yaml cmd_id=cmd_karo_hotfix_agent_respawn_preserve_active timestamp=2026-09-05T00:29:55Z)。残り 20 回は発注(AC)・環境(前提)・ルーチン(正規コマンドの案内不在)・gate 偽陽性のいずれか=**忍者側では防げない**。
- **コスト**: FAIL を経た cmd の deploy→CLEAR は p50 94 分、経なかった cmd は p50 49 分(本日 n=4/17)。1 回の FAIL ループで所要が約 2 倍。
- **真因は 1 つ**: 忍者に届く情報が「task YAML に書かれたもの」だけなのに、AC を書く側(将軍・家老)と環境(隔離 DB・clone path・正規コマンド)が **書く前提を持たない**。Level5(事前コンテキスト提供)の欠落。

## §2 一次データ
### §2.1 本日の報告 74 本
| 終端 | 件数 |
|---|---|
| completed/PASS | 63 |
| failed/FAIL | 4(才蔵 ci_fix midx_lock、疾風 hanzo_failed_inventory、疾風 4477(honest FAIL)、疾風 dirty_ownership_audit) |
| revision_requested | 3(飛猿 ci_fix 33945636960、疾風 ga580、半蔵 cpu_repro_guard) |
| completed/FAIL | 1 |
| pending | 3 |
| hook_failures>0 | 5/74 |

### §2.2 軍師 FAIL 22 回の理由(fail_reasons 生値)
| 理由 | 回数 | 分類(§3) |
|---|---|---|
| AC1/AC2/AC3 bc:no(AC 未達申告) | 13 | A(AC 不備)5 / B(前提不足)5 / D(gate 待ち)3 ※§3 で個別に振分 |
| LG043 保留語(後で/未達語)残存 | 3 | E(忍者品質) |
| task-mode 既存 suite FAIL/timeout | 2 | B/D(baseline 赤・環境) |
| lessons_useful 契約外 | 1 | C(ルーチン) |
| marker 未 publish/receipt 不在 | 1 | C |
| task_attribution bc:no | 1 | C |
| gate_vercel_phase FAIL: context 参照切れ | 1 | D(偽陽性、軍師が D0 根治 feb6ea91e) |

### §2.3 FAIL ループの実例(同一 cmd の verdict 列)
| cmd | 列 | 何で止まったか |
|---|---|---|
| recon2_4449_u2_revalidate | FAIL→FAIL→FAIL→LGTM→LGTM | fixture の非決定性(PD-142)が根治されるまで 3 回 FAIL |
| recon2_4448_u1_revalidate | FAIL→FAIL→FAIL→LGTM | 同上 |
| ci_fix 33939652526(才蔵 初代) | FAIL→… | case135 は D(gate)より B(worktree が古い)寄り(軍師 (1)) |
| hotfix_deploy_external_worktree_timeout | FAIL→FAIL→FAIL→LGTM→LGTM | 外部 repo worktree 準備 312〜420 s の環境問題 |
| hotfix_agent_respawn_preserve_active | FAIL→FAIL→LGTM | (未分類) |
| cmd_4475 | FAIL→FAIL→LGTM | AC2 の lint 不可能(lint script 不在)→将軍が AC を訂正 |
| cmd_4476 | FAIL→LGTM | task YAML 重複 field(deploy_task 側バグ)+precheck cache 偽 FAIL |
| recon2_dirty_ownership_audit | FAIL→FAIL→FAIL | 監査範囲が下知で 2 回変わった(将軍の追補) |

### §2.4 report の unclear_points/discretion_fills(忍者が「無かった」と書いた情報)
| 忍者/cmd | 無かった情報 |
|---|---|
| 疾風 4477 | 隔離 DB の名前・場所・接続法(localpg)。AC3『隔離 DB』だけ |
| 疾風 dirty_ownership_audit | clone の絶対 path(task に明記なし、branch 名から推定) |
| 疾風 ga580 | artifact の実体 path と 43 秒計測の一次出力 |
| 才蔵 ci_fix midx_lock | clean-repro recipe の相対 task path が worktree に無い |
| 飛猿 deploy_target_smoke | AC2『明示 deployment target』の field 名・許容値が task に無く独自定義 |
| 飛猿 ci_fix 33945636960 | AC2『公開済み』の判定基準(origin push か報告提出か) |
| 小太郎 4476 | task YAML の purpose/AC/planned_paths/lesson_set が cmd と不一致(重複 field) |
| 半蔵 cpu_repro_guard | AC1 の『現行許可』が実 loop か quoted fixture かの解釈 |

### §2.5 hook_failures(忍者がルーチンで踏んだ BLOCK)
| 内容 | 回数 |
|---|---|
| bats 直接実行→heavy-job-admission BLOCK(正規=run_tests.sh file) | 3 |
| db_capability_launcher --capability readonly_query→Guard14 BLOCK(正規=/db-check 2 段) | 2 |
| ci_clean_repro single-flight selection 解決不能(絶対 path 再試行でも同一) | 2 |
| 4476: report status 遷移で 2 gate(gate_report_format vs report_field_set)が矛盾し 3 回再提出 | 1 cmd/3 回 |

### §2.6 deploy/gate 側 BLOCK(家老 lane、忍者は待つ)
| 箇所 | 回数 | 性質 |
|---|---|---|
| deploy UNIVERSAL_SHARD: AC 3 本以上は shard 必須 | 3 | 発注形式(AC 数) |
| deploy DOC_LANE_ROUTING: target が doc 所有 | 3 | 経路判定(正) |
| deploy pending own report | 2 | 前 report 未終端 |
| gate report_commit_main_ancestry | 7 BLOCK+47 WAIT | 合流待ち(家老 c2a 直列。別書 karo_throughput §2) |
| gate dm_signal_production_smoke_failed | 2 | 偽陽性(LP/backend 一律比較→飛猿 hotfix) |
| gate parent_cmd_contract | 1 | 契約不一致 |

集計: `python3 -c` で reports の status/verdict/hook_failures/task_clarity を集約、`gunshi_review_log` の本日 entry を cmd 別に verdict 列化、deploy_task.log の BLOCK 行を uniq -c、gate_metrics の BLOCK を 4 列目で集計、deploy→CLEAR の分差。

## §3 分類と判定(FAIL 22 回+hook 失敗 8 回+deploy/gate BLOCK 18 回を 5 種へ)
### §3.0 分類規則(家老②: A/B は相互排他でないため primary を一意化する)
- 1 event に **primary 原因 1 つ+secondary 原因 list** を持つ(家老①)。
- primary の優先順: **D(検出器/環境の偽陽性・非決定) → B(環境事実が task に無い) → A(環境事実を全て与えても判定不能な未定義語・不可能条件) → C(正規経路の案内なし) → E(知り得た情報を使わなかった)**。
- 例: 4477 AC2『全量 FAIL 0』は「baseline が赤という環境事実があれば AC を直せた」→ **primary=B**、secondary=A。4475 AC2 lint も同じく B(lint script 不在という事実)。『公開済み』『明示 deployment target』の定義なしは環境を全て与えても判定不能→ A。
- E は LG043 の各 event で原文と検出 span を再照合し、『後で/未達』の部分一致(『実装前後で』等)は D(検出器偽陽性)へ移す。本日 4 event(3 cmd: release_idle_redone_race 03:45、agent_respawn_preserve_active 09:26/09:29、4475 11:17)のうち agent_respawn の 2 event は 1 WA(部分一致偽陽性)の波及→ D。**E=2**(release_idle_redone_race、4475)。
| 分類 | 定義 | 本日の件数(概算) | 判定 | 例 |
|---|---|---|---|---|
| A. AC 品質不備(発注側) | 環境事実を全て与えても判定不能な AC(未定義語・不可能条件) | FAIL 3+deploy 3 | **インフラバグ(発注の型)** | 飛猿『明示 deployment target』(field 未定義)、『公開済み』(基準未定義)、AC 3 本で shard BLOCK |
| B. 前提情報不足(環境側) | 存在する環境事実(path・入口・baseline の状態・script の有無)が task に無い | FAIL 7+suite 2 | **インフラバグ(注入の欠落)** | 4477 AC2『全量 FAIL 0』(baseline が赤という事実)、4475 AC2 lint(script 不在という事実)、localpg、clone 絶対 path、artifact 実体 path、clean-repro recipe path、外部 repo worktree 時間 |
| C. ルーチン試行錯誤 | 正規コマンド/契約を忍者が毎回探す | hook 8+FAIL 3 | **インフラバグ(案内の欠落)** | bats 直実行、db launcher 2 段、single-flight、lessons_useful 契約、receipt/marker、status setter 遷移 |
| D. gate/環境の偽陽性・構造 | 忍者の成果と無関係に止まる | FAIL 6(LG043 部分一致 2 含む)+gate 10+WAIT 47 | **インフラバグ(検出器)** | fixture 非決定(PD-142)、precheck cache、prod smoke 一律比較、task YAML 重複 field、ancestry 合流待ち |
| E. 忍者品質 | 知り得た情報を使わなかった | FAIL 2(4 event 中 偽陽性波及 2 は D) | 忍者側 | LG043 保留語(後で/未達語)の真正残存(release_idle_redone_race、4475) |

- **E は 2/22=9%**。残り 91% は忍者の外にある。殿の仮説は数で裏付けられる。primary の一意化は T5 の構造記録(failure_origin_code)が入るまで将軍の読み=事後分類であることを明記(家老⑦)。
- 波及: A/B は「FAIL→家老 RC→忍者再提出→軍師再 review→家老受理」の 1 ループ(本日実測 p50 +45 分)を生み、C は忍者の 1 task 内で数分〜十数分、D は家老 lane の待ち(別書 karo_throughput §2、CLEAR 経過 p50 20 分)。

## §4 なぜ起きるか(構造)
1. 忍者の入力は task YAML のみ。deploy_task は `assumptions`(cmd から複製)、`related_lessons`(教訓)、`semantic_concepts`(概念索引)を注入するが、**環境の実体(隔離 DB・clone・artifact・正規コマンド)は誰も書かない**。書く責任が cmd 作者(将軍/家老)にあるが、cmd_save の check にその観点が無い(本日 cmd_save は語彙・数値・AC 数を見て、環境名の有無は見ない)。
2. AC の「充足可能性」を検証する場所が無い。『全量 FAIL 0』は baseline が赤なら不可能、『lint』は script が無ければ不可能、『公開済み』『deployment target』は定義が無ければ判定不能。cmd_save は文字列の形を見るだけで、**対象 repo の現物(baseline の状態・script の有無・field の定義)を見ない**。
3. ルーチンの正規経路は hook の BLOCK メッセージで初めて忍者に伝わる(=踏んでから知る)。CLAUDE.md の忍者 Recovery には run_tests.sh / db-check / setter の一覧が無い。
4. gate の偽陽性は個別に根治されている(本日: precheck cache、prod smoke、重複 field、index.lock)が、発火するたび忍者と家老の 1 ループを消費する。

## §5 ToBe(最小。既存機構の拡張のみ、新 gate/hook は 0)
| # | 何を | どこ(既存) | 何が消えるか | 大きさ |
|---|---|---|---|---|
| T1 | **environment_refs(ID 参照)注入**: cmd schema に `environment_refs: [localpg, dm_signal_clone, artifact_store, clean_repro_recipe]` の **明示 ID** を持たせ(自然言語の環境語一致はしない。家老③=キーワード誤注入型)、`projects/infra.yaml environments:` の registry は **値の複製でなく canonical path / probe_id / verified_at / TTL への参照**(秘密値は入れない)。probe は任意 shell を保存しない: **probe_id だけを保存し、追跡済み allowlist script(scripts/probes/<id>.sh)へ解決、引数は schema 検証**(家老 v2 補正③: trusted data→実行の新境界を作らない)。`inject_cmd_assumptions` が ID を解決して task YAML `environment:` に card を複製、未解決 ID は deploy BLOCK(発注側に返る) | deploy_task.sh の既存注入 3 種の隣に 4 つ目。projects/infra.yaml(家老管理) | B の 5〜7 件/日 | registry 1 表+注入関数 1 本 |
| T2 | **preconditions 構造 schema+1 validator**: cmd に `preconditions: {baseline: {command, source_sha, executed_at, pass, fail, skip}, definitions: {<AC 内の語>: <判定式>}}` を持たせ、validator は **baseline を実行せず** source_sha の一致(対象 repo の HEAD)と executed_at の鮮度だけを 1 秒未満で検証、AC に『全量/lint/typecheck/公開済み/明示』等が出たら対応 key の存在を要求。**cmd_save と deploy_task --yaml(/karo-direct)の両入口から同じ validator を呼ぶ**(家老④: cmd_save だけでは --yaml が素通り。自由文の『未定義語』検出はせず、schema の key 有無で二値) | cmd_save.sh と deploy_task.sh が共有する `scripts/lib/cmd_preconditions_validate.sh` 1 本 | A の 5 件/日+B の一部 | validator 1 本+schema 2 key |
| T3 | **routine_refs(最小 ID 集合)注入**: task_type(full/hotfix/scout/ci_fix)と CLI(Claude/Codex)で決まる routine ID(`tests_run`=run_tests.sh file/task、`db_readonly`=/db-check 2 段、`report_status`=report_field_set 遷移順、`inbox`=inbox_read→mark_read、`commit`=ninja_scope_commit)だけを task YAML `routine_refs:` に注入し、本文は canonical registry(`context/karo-operations.md` §routine か skills)への参照(家老⑤: 固定 5 行の全 task 複製は肥大化+CLI 差混在) | deploy_task の注入+registry 1 表 | C の 8 件/日 | registry 1 表 |
| T4(T1-T3 の効果計測後に要否判断。軍師 (5)) | **FAIL 理由の再注入**: 軍師 FAIL の fail_reasons を、家老 RC で同 task へ `review_feedback:` として自動複製(既存 inject_task_modifiers の経路) | deploy_task/review_approval の既存経路 | ループ 2 回目以降の同じ FAIL | 既存 field の再利用 |
| T5 | **failure_origin_code の発生時構造記録**: report の `failure_origin: {primary, secondary}` は忍者の **自己申告 candidate**、gunshi_review_log の FAIL entry の `failure_origin_code: {primary, secondary, ninja_candidate_agreed: true|false, correction: ..}` を **canonical** とし(家老 v2 補正④)、日次表(cmd_4478)は canonical を集計、忍者候補との一致率も列に出す。事後の prose 分類はしない(家老⑦) | report template+review_bundle の既存 field 追加、karo_throughput_report の列 | 分類が毎日二値で出る | field 2 つ+列 |
| T6 | D(偽陽性)は個別 hotfix 継続(本日 4 件根治済み)。合流待ちは別書(karo_throughput §7) | — | — | — |

### §5.1 やらないこと
新 gate/hook の追加、AC の全文 LLM 判定、忍者への追加チェックリスト、レビュー回数の上限化。

### §5.2 順序と二値(家老⑥: 『unclear_points=0』は空欄で達成できる Goodhart 指標のため不採用)
1. T1+T3(注入の拡張)→ 二値: 次の 20 task で `environment_refs`/`routine_refs` の **解決率 N/N=100%**(未解決 0)、report の missing-premise 起因 RC(家老 RC 理由に『path/環境/正規コマンド不在』)=0、軍師抜取 5 件で false-negative(前提不足なのに unclear_points 空欄)=0。
2. T2(発注側 validator)→ 二値: 『全量/lint/typecheck/公開済み/明示』を含む cmd の preconditions key 充足率 100%、cmd_save と deploy_task --yaml の両入口で同じ validator が呼ばれる test。
3. T5→ 二値: 次の 20 FAIL event 全てに failure_origin_code(primary+secondary)がある。
4. T4→ T1-T3 の効果計測後に要否判断(軍師 (5)・家老 賛成)。

## §6 レビュー判定の記録
- 軍師 16:13: APPROVE。(1) bc:no 13 の A5/B5/D3 は実体と合致、才蔵 case135 は B 寄り (2) E 見落としなし、14% 妥当 (3) T3 は SG と矛盾なし (4) T2 は cmd_save で baseline を走らせると数十秒→記載義務のみに(採用) (5) T4 は T1-T3 の効果後に判断、T5 は cmd_4478 に統合(採用)。
- 家老 16:15: REJECT 7 点。①E=3 の根拠不足(LG043 部分一致偽陽性 1 件 WA 済)→§3.0 primary/secondary+E を 2〜3 に ②A/B 非排他→優先順 D→B→A→C→E で primary 一意化 ③T1 自然言語一致は誤注入型→environment_refs ID+registry 参照(canonical path/probe/verified_at/TTL、秘密値なし) ④T2 が cmd_save のみだと --yaml 素通り、自由文検出は二値不能→preconditions 構造 schema+1 validator を両入口から ⑤T3 固定 5 行は肥大化→routine_refs 最小 ID 集合+registry 参照 ⑥『unclear_points=0』は Goodhart→解決率 N/N・missing-premise RC=0・抜取 FN=0 ⑦T5 事後 prose 分類は曖昧→failure_origin_code を発生時に構造記録。**7 点すべて採用(v2)**。
- 家老 16:21(v2 差分): 条件付き APPROVE、4 補正。①WA id=karo_workarounds cmd_karo_hotfix_agent_respawn_preserve_active 2026-09-05T00:29:55Z、波及 FAIL 2 event→E=2/22=9%、D へ 2 ②§3 表 A の 4477/lint を B へ移動(§3.0 と整合) ③T1 probe は probe_id→allowlist script、引数 schema 検証 ④T5 report は忍者候補、軍師 review_log が canonical で一致/訂正を記録。T2 両入口・T3 最小 ID・§5.2 指標は PASS。**4 補正すべて採用(v2.1)**。

## §6.1 レビュー依頼(忖度なし)
- 家老: §3 の分類と件数は現場感と合うか(特に A と B の線引き)。T1 の environments 表を projects/infra.yaml に置くことの運用負荷。T2 が家老の /karo-direct 起票を遅くしないか。T4 の再注入で task YAML が肥大しないか。
- 軍師: §2.2 の fail_reasons 分類の妥当性(bc:no 13 の内訳 5/5/3 は将軍の読み)。T3 の routine 表が既存 SG 観点と矛盾しないか。E(忍者品質 3 件)の見落とし。

## §6.2 実装進捗台帳(loop ごとに現在値で更新。殿指示 18:57)
| 時刻 | 何が動いたか | 分類(§3.0) | 状態 |
|---|---|---|---|
| 16:30 | v2.1 確定(軍師 APPROVE、家老 条件付き APPROVE 4 補正を全採用) | — | 設計閉 |
| 18:04 | 軍師 D0 バグ#1: report_field_set の revision_requested→completed 自動遷移(忍者が finalize を忘れる) | C ルーチン | origin 公開 499eb209(家老審査) |
| 18:10 | 軍師 D0 バグ#3: review_bundle の allow_archived 自動検出(archive 済み報告が single 処理不能) | D 偽陽性 | 同上 |
| 18:19 | 軍師 バグ#5 根因: files_modified 空の honest FAIL が commit identity で SystemExit(1)→approval 不能循環 | D 偽陽性(前提不成立 honest FAIL を成果物欠落と誤判定) | 将軍 D0 f4dbf1f46(review_approval 構造 no-code 判定、50/50)、軍師検証 PASS 18:45 |
| 18:57 | 軍師 再集計(v2.1→現在): 報告 74→84 本、revision_requested 3→1(飛猿 ci_fix_33945636960 のみ)、failed 4→5、hook_failures 5→4(ci_clean_repro single-flight 2 件は半蔵 ci_fix で構造的に消える)、gate BLOCK: ancestry 7→8、dm_signal_smoke 2→2、**ci_push_state BLOCK 8 件が新規**(v2.1 未記載) | D(gate 側) | §2.6 へ反映 |
| 18:57 | 見落とし: バグ#1 は §3 C(ルーチン)=T3 routine_refs の注入対象、バグ#5 は D=T5 failure_origin_code の記録対象 | — | v2.2 で本表に記録 |
- 判定: 本日 FAIL/BLOCK のうち忍者品質 E は 2/22 で不変。今日の新規根治 3 件(バグ#1/#3/#5)は全て C/D=インフラ側で、殿 16:03 の仮説「BLOCK/FAIL はインフラバグ」を実装で追認。
- 次: T1+T3(environment_refs/routine_refs 注入)の起票は殿 go 待ちのまま。ci_push_state BLOCK 8 件の内訳を日次表(karo_throughput_report.sh の待ち理由別)で追う。

## §7 因果リンク
- ← [[殿下問_忍者BLOCK_FAILはインフラバグか_20260905_1603]] / ← [[karo_throughput_asis_20260905]](家老側の待ち) / ← [[cmd_4477_AC3_隔離DB名なし]](LS 候補) / ← [[PD-142]](fixture 非決定)
- → [[Level5_事前コンテキスト提供]](context/growth-loop.md §11) → [[environment_card_injection]] → [[ac_feasibility_check]] → [[routine_preinjection]]
