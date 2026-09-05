# 忍者の BLOCK/FAIL はインフラバグか — AsIs/ToBe 設計書 v1(2026-09-05 16:15、殿下問 16:03)

## §0.0 前提条件と我らのスタイル
- 殿の問い(16:03): 忍者が AC の品質不備・前提情報の不足・ルーチン作業の試行錯誤で BLOCK/FAIL になるのはインフラバグではないか。修正速度が遅くなっている。調査→設計書→家老・軍師レビュー。
- 対象: multi-agent-shogun の忍者 6 名(Codex gpt-5.6-luna 4+Claude 2)。忍者は毎 task で記憶ゼロから始まる(/clear)。知識は task YAML への注入(deploy_task: assumptions/related_lessons/semantic_concepts)と report テンプレートだけで届く。
- 判定基準: 「忍者が知り得ない情報を要求して止めた」なら発注側・環境側のバグ。「忍者が知り得た情報を使わなかった」なら忍者の品質。両者を数で分ける。
- スタイル: 既存機構(deploy_task の注入 3 種、cmd_save の check 群、gate_report_autofix、run_tests.sh、report_field_set)の拡張だけで解く。新しい gate/hook を積まない(07-21 殿裁定: 削るな速くしろ、ただし表示型を増やさない)。可逆に 1 cmd ずつ。推測は「(未計測)」。
- 数値の出所: 2026-09-05 00:00〜16:05 の `queue/reports`(+archive、mtime 本日 74 本)、`logs/gunshi_review_log.yaml`(本日 60 entry)、`logs/deploy_task.log`、`logs/gate_metrics.log`、`logs/karo_workarounds.yaml`。集計コマンドは §2 末尾。

## §1 結論(先に)
- **はい、大半はインフラバグ**。本日の軍師 review 60 件中 FAIL 22 件(37%)、FAIL を経た cmd は 12/32。その FAIL 22 回を原因で分けると、忍者が知り得た情報を使わなかったものは **3 回**(LG043 保留語 3)。残り 19 回は発注(AC)・環境(前提)・ルーチン(正規コマンドの案内不在)・gate 偽陽性のいずれか=**忍者側では防げない**。
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
| 分類 | 定義 | 本日の件数(概算) | 判定 | 例 |
|---|---|---|---|---|
| A. AC 品質不備(発注側) | 忍者が満たせない/判定できない AC | FAIL 5+deploy 3 | **インフラバグ(発注の型)** | 4477 AC2『全量 FAIL 0』(baseline が赤)、4475 AC2 lint(script 不在)、飛猿『明示 deployment target』(field 未定義)、『公開済み』(基準未定義)、AC 3 本で shard BLOCK |
| B. 前提情報不足(環境側) | 存在する環境・path・入口が task に無い | FAIL 5+suite 2 | **インフラバグ(注入の欠落)** | localpg、clone 絶対 path、artifact 実体 path、clean-repro recipe path、外部 repo worktree 時間 |
| C. ルーチン試行錯誤 | 正規コマンド/契約を忍者が毎回探す | hook 8+FAIL 3 | **インフラバグ(案内の欠落)** | bats 直実行、db launcher 2 段、single-flight、lessons_useful 契約、receipt/marker、status setter 遷移 |
| D. gate/環境の偽陽性・構造 | 忍者の成果と無関係に止まる | FAIL 4+gate 10+WAIT 47 | **インフラバグ(検出器)** | fixture 非決定(PD-142)、precheck cache、prod smoke 一律比較、task YAML 重複 field、ancestry 合流待ち |
| E. 忍者品質 | 知り得た情報を使わなかった | FAIL 3 | 忍者側 | LG043 保留語(後で/未達語)残存 |

- **E は 3/22=14%**。残り 86% は忍者の外にある。殿の仮説は数で裏付けられる。
- 波及: A/B は「FAIL→家老 RC→忍者再提出→軍師再 review→家老受理」の 1 ループ(本日実測 p50 +45 分)を生み、C は忍者の 1 task 内で数分〜十数分、D は家老 lane の待ち(別書 karo_throughput §2、CLEAR 経過 p50 20 分)。

## §4 なぜ起きるか(構造)
1. 忍者の入力は task YAML のみ。deploy_task は `assumptions`(cmd から複製)、`related_lessons`(教訓)、`semantic_concepts`(概念索引)を注入するが、**環境の実体(隔離 DB・clone・artifact・正規コマンド)は誰も書かない**。書く責任が cmd 作者(将軍/家老)にあるが、cmd_save の check にその観点が無い(本日 cmd_save は語彙・数値・AC 数を見て、環境名の有無は見ない)。
2. AC の「充足可能性」を検証する場所が無い。『全量 FAIL 0』は baseline が赤なら不可能、『lint』は script が無ければ不可能、『公開済み』『deployment target』は定義が無ければ判定不能。cmd_save は文字列の形を見るだけで、**対象 repo の現物(baseline の状態・script の有無・field の定義)を見ない**。
3. ルーチンの正規経路は hook の BLOCK メッセージで初めて忍者に伝わる(=踏んでから知る)。CLAUDE.md の忍者 Recovery には run_tests.sh / db-check / setter の一覧が無い。
4. gate の偽陽性は個別に根治されている(本日: precheck cache、prod smoke、重複 field、index.lock)が、発火するたび忍者と家老の 1 ループを消費する。

## §5 ToBe(最小。既存機構の拡張のみ、新 gate/hook は 0)
| # | 何を | どこ(既存) | 何が消えるか | 大きさ |
|---|---|---|---|---|
| T1 | **環境カード注入**: `projects/infra.yaml` に `environments:`(localpg: path/起動/接続 URL/schema 分離の型、DM-signal clone: 絶対 path/branch 規約、artifact 保存先、clean-repro recipe の絶対 path)を 1 度書き、`inject_cmd_assumptions` が cmd の target_path/文中の環境語に一致する card を task YAML `environment:` へ複製 | deploy_task.sh の既存注入 3 種の隣に 4 つ目。projects/infra.yaml(家老管理) | B の 5〜7 件/日 | yaml 1 表+注入関数 1 本(既存の inject_semantic_concepts と同型) |
| T2 | **AC 充足可能性 check(cmd_save)**: (a)『全量 FAIL 0』『lint』『typecheck』を AC に書く時は対象 repo で baseline を 1 回実行した結果(赤なら『baseline 一致』条件)を assumptions に必須 (b) AC 内の未定義語(field 名・『公開済み』『明示』)は定義行を要求 | cmd_save.sh の既存 check 群に 2 check 追加(表示型だが WARN ではなく **cmd 作者=将軍/家老の側で止める**=忍者には届かない) | A の 5 件/日 | check 2 本 |
| T3 | **正規コマンド表の pre-injection**: 忍者 task YAML に `routine:` として run_tests.sh file/task、db-check 2 段、report_field_set の status 遷移順、inbox_read→mark_read、ninja_scope_commit を deploy 時に複製(1 表、テンプレート固定) | deploy_task の注入+CLAUDE.md 忍者 Recovery に 5 行 | C の 8 件/日 | template 1 表 |
| T4 | **FAIL 理由の再注入**: 軍師 FAIL の fail_reasons を、家老 RC で同 task へ `review_feedback:` として自動複製(既存 inject_task_modifiers の経路) | deploy_task/review_approval の既存経路 | ループ 2 回目以降の同じ FAIL | 既存 field の再利用 |
| T5 | **計測**: karo_throughput_report(cmd_4478)に『FAIL ループ数/cmd、rework 率、deploy→CLEAR p50(FAIL 有無別)、hook_failures 件数、分類 A〜E』の列を足す | cmd_4478 の日次表 | 効果が毎日見える | 列追加 |
| T6 | D(偽陽性)は個別 hotfix 継続(本日 4 件根治済み)。合流待ちは別書(karo_throughput §7) | — | — | — |

### §5.1 やらないこと
新 gate/hook の追加、AC の全文 LLM 判定、忍者への追加チェックリスト、レビュー回数の上限化。

### §5.2 順序と二値
1. T1+T3(注入の拡張、忍者の入力を増やす)→ 二値: 次の 20 task で unclear_points に「path/環境/正規コマンドが無い」が 0。
2. T2(発注側 check)→ 二値: 『全量 FAIL 0』『lint』を含む cmd に baseline 行が 100%。
3. T4→ 二値: 同一 fail_reason での 2 回目 FAIL が 0。
4. T5→ 二値: 日次表に分類 A〜E 列。

## §6 レビュー依頼(忖度なし)
- 家老: §3 の分類と件数は現場感と合うか(特に A と B の線引き)。T1 の environments 表を projects/infra.yaml に置くことの運用負荷。T2 が家老の /karo-direct 起票を遅くしないか。T4 の再注入で task YAML が肥大しないか。
- 軍師: §2.2 の fail_reasons 分類の妥当性(bc:no 13 の内訳 5/5/3 は将軍の読み)。T3 の routine 表が既存 SG 観点と矛盾しないか。E(忍者品質 3 件)の見落とし。

## §7 因果リンク
- ← [[殿下問_忍者BLOCK_FAILはインフラバグか_20260905_1603]] / ← [[karo_throughput_asis_20260905]](家老側の待ち) / ← [[cmd_4477_AC3_隔離DB名なし]](LS 候補) / ← [[PD-142]](fixture 非決定)
- → [[Level5_事前コンテキスト提供]](context/growth-loop.md §11) → [[environment_card_injection]] → [[ac_feasibility_check]] → [[routine_preinjection]]
