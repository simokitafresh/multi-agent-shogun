# lessons_shogun superseded全文アーカイブ (2026-07-24 /lesson-sort圧縮)
# 正本: projects/infra/lessons_shogun.yaml。superseded_by付きエントリの全文を移設。


## LS-A12
```yaml
- id: LS-A12
  title: inbox_write guard 3段階設計 — 迂回路ゼロの構造
  origin: '[[cmd_2004]] + [[cmd_1994]]'
  detail: |
    第1版=exit code判定→出力多様で不安定。第2版=status判定→正規フローもBLOCK。
    第3版=cmd_delegate.sh内でstatus変更順序入替→bypass廃止→迂回路ゼロ。
    教訓: (a)guardはデータ状態で判定 (b)bypass許可=迂回路 (c)テストに攻撃パターン含めよ
    (d)ガード設計時は全経路を列挙し統一チェックポイントを選べ。片側ガード(deploy_task.sh)ではkaro_direct経路が迂回する(cmd_2684)
  source_ids: [LS040, LS039]
  created_at: '2026-04-24'
  automated: true
  enforcement: 'inbox_write.sh cmd_new guard(status判定)+cmd_delegate.sh status変更順序+inbox_write.sh task_assigned統一ガード(cmd_2684)'
  superseded_by: 'LS-A07 (inbox_write guard 3段階設計(データ状態判定/bypass廃止/攻撃パターンテスト)はLS-A07 gate迂回禁止の正規フロー強制に包含。enforcementはinbox_write.sh/cmd_delegate.sh guardでcode稼働中)'
```


## LS-A20
```yaml
- id: LS-A20
  title: 因果チェーン — cmd配備→実装→報告の因果を追え
  origin: '[[cmd_2818]]: deepdive_causal_tracing_20260415起源の因果チェーン教訓を逆引き可能にするためoriginを付与'
  detail: 現象単位で止めず、入力・変換・出力の連鎖で問題を見る。どこに防御層を置くか決める。
  source_ids: [LS013]
  created_at: '2026-04-24'
  automated: true
  enforcement: 'cmd_save.sh q8_why_what(BLOCK)+gunshi review因果推論ルール(causal_chain必須)+gate_gunshi_cs_checklist.sh CS6'
  superseded_by: 'LS-A19 (因果チェーン(cmd配備→実装→報告の因果追跡)はLS-A19原理3則+deepdive_causal_tracing_20260415に完全内包。単独教訓として冗長ゆえ統合)'
```


## LS036
```yaml
- id: 'LS036'
  title: 'CoDDはbrownfield逆生成が正解。greenfield generateは遅い'
  origin: '[[cmd_2850]] -> [[cmd_2891_修行CoDD導入で30分超過]] -> [[context/training-cycle.md §28_brownfield限定制定2026-05-19]]'
  detail: 'CoDD greenfield generate(wave1-5直列)は各wave数分×5=30分以上かかる。先に実装を完成させてcodd extract(brownfield逆生成)のほうが圧倒的に早い。Simple-OCR(cmd_2780)で実証済み。kj-role-countでgreenfield 5wave実行→30分以上消費。忍者6並列実装→逆生成が正しいフロー。'
  source_cmd: 'cmd_2850'
  created_at: '2026-05-18'
  automated: true
  enforcement_level: 4
  enforcement: 'Level4(フロー内BLOCK): pre-bash-combined.sh Guard15がcodd generate --waveをshlex解析で検出し、.codd/extract/なし+既存ソースありの場合のみBLOCK(brownfield extract先行を強制、新規空PJは許可)。bats 9+回帰41 PASS。一次再検証全文→docs/research/lessons_shogun_a04_a09_detail.md'
  superseded_by: 'LS-A17 (CoDD brownfield逆生成優先の教訓はenforcementがpre-bash-combined.sh Guard15で稼働中(code埋込済)。CoDD成長ループを扱うLS-A17へ統合)'
```


## LS040
```yaml
- id: 'LS040'
  title: 'バックアップファースト — DB変更前に必ずバックアップ。例外なし'
  origin: '[[cmd_2850]]'
  detail: '本番DBに触る全操作(マイグレーション/スキーマ変更/データ修正)の前にバックアップを取る。バックアップがなければ変更しない。kj-role-countでDB_RESETによりクリニック2ヶ月分業務データ消失(人件費発生済み)。バックアップがあれば30秒で復元できた。殿の教え: LLMはデジタルデータしか扱えない。だからこそバックアップファーストを徹底せよ。LS038/LS039を統合。'
  source_cmd: 'cmd_2850'
  created_at: '2026-05-18'
  automated: true
  enforcement_level: 4
  enforcement: 'type=gate; file=/mnt/c/Python_app/kj-role-count/backend/database.py; pattern=run_backup。init_database内で無条件run_backup()実装済み(フロー内強制=L4相当)。適用はkj-role-count 1PJのみ、他PJ横展開はPJ単位個別実装cmd推奨でdecision_candidate整理済み。一次再検証全文→docs/research/lessons_shogun_a04_a09_detail.md'
  superseded_by: 'LS-A16 (バックアップファースト(DB変更前backup)はLS-A16本番パリティ(DB変更後即確認/savepoint/verify)のDB安全原則に包含。enforcementはkj-role-count database.py run_backup無条件実行でcode稼働中)'
# === クラスタ7: 記憶DB原則 ===
```


## LS092
```yaml
- id: 'LS092'
  title: 'D006 Tier1 UNCONDITIONAL規則を趣旨解釈で緩めた判断ミス'
  origin: '[[cmd_karo_ci_fix_29574746129]]'
  detail: '事故: 影丸がrun_tests.shのkill -TERM/-KILLでD006検出→正当failed停止。将軍がD006の趣旨(他エージェント破壊防止)を根拠に例外スコープ追記を家老に指示。家老がD006はUNCONDITIONALであり将軍含む全員が上書き不能と正当拒否。原因: deepdive_causal_tracing Phase2-3と同構造=原則の文字面vs趣旨の判断で趣旨解釈を優先し、UNCONDITIONAL明記を無視。Tier1規則は因果をたどって緩める対象ではなく、改定が必要な安全規則。対策: timeoutコマンド(D006リスト外)で代替実装。'
  source_cmd: 'cmd_karo_ci_fix_29574746129'
  created_at: '2026-07-17'
  automated: true
  enforcement: 'Level4: cmd_save.sh check_tier1_exception_warn()がD001-D009+例外/緩和キーワード共起をWARN。tests/unit/test_cmd_save.bats Check21.7(2/2 PASS)'
  superseded_by: 'LS099 (D006 Tier1を趣旨解釈で緩めた判断ミス(具体例)は、LS099『必須ハーネスと過剰制限は別物・必須を消すな』の一般原理に包含。個別事例ゆえ統合)'
  enforcement_level: 4
```


## LS100
```yaml
- id: 'LS100'
  title: 'fail-closed強制は『脱出路の実装』を先に検証せよ — 復旧コマンド未allowlistで全ロックアウト'
  origin: '[[殿裁定_作業前探索の強制が最重要_20260721]] -> [[verify_fail_closd復元]] -> [[issue未allowlistで全ロックアウト]] -> [[a69c7c2ca_issue_bypass根治]]'
  detail: '全文は吸収先LS-A22のdetailに統合済み(superseded_reason参照)。冒頭: fail-closed enforcement(verify/gate)を復元・...'
  source_cmd: 'cmd_shogun_failclosed_escape_20260721'
  created_at: '2026-07-21'
  automated: true
  enforcement: '起動時lessons_shogun.yaml自動ロード。fail-closd enforcement配備前チェック: 復旧コマンドがblock中も実行可か(allowlist実体化)をfixtureで検証。a69c7c2caのissue-bypassを基線とせよ'
  superseded_by: 'LS-A22 (fail-closed脱出路未検証で全ロックアウトはLS-A22 gate FP/デッドロック群(preflight自己封鎖デッドロック含む)に包含。同クラスへ統合)'
```


## LS102
```yaml
- id: 'LS102'
  title: '単一telemetry値を分布と誤認するな — 代表値主張の前に再測で分布を見よ'
  origin: '[[将軍memory_context単一サンプル報告]] -> [[3958ms cold outlierをmedianと誤認]] -> [[家老全変種再測でmedian656ms訂正]] -> [[LS-A24分布確認義務の拡張]]'
  detail: '全文は吸収先LS-A24のdetailに統合済み(superseded_reason参照)。冒頭: 2026-07-21 将軍がdeploy TASK_MUTATION_PHASE...'
  source_cmd: 'cmd_4110_memory_context_report'
  created_at: '2026-07-21'
  superseded_by: 'LS-A24'
  superseded_at: '2026-07-22'
  superseded_reason: 'LS102自身が「LS-A24(計測の実運用代表性)違反の一形態」と明記。LS-A24 detail(7)へ全文吸収し、active上限31超過(32件)を解消'
  automated: true
  enforcement: 'L4: 速度/コスト系のinfra_bug_report起票前に、対象項目のtelemetryを最低3サンプル(可能ならcold/warm)集計しmedian/p95/nを添える運用。単一max値のみの''最大コスト''主張を自己点検。将軍の速度報告テンプレにdistribution必須を意識化(未自動化=次の自動化ターゲット)。'
```


## LS105
```yaml
- id: 'LS105'
  title: 'ノイズなalertは偽陽性とは限らぬ — 抑制提案の前に「下層の状態が真に解決済か」を一次確認せよ(真陽性の抑制=自動消火)'
  origin: '[[将軍が陣形図alert抑制を推奨]] -> [[目的達成済=実害なしと誤判定]] -> [[影丸一次確認でtaskは真にOPEN未解決失敗]] -> [[真陽性抑制=自動消火を家老が中止]] -> [[抑制前にSSOT状態を一次確認する規律]]'
  detail: '全文は吸収先LS103のdetailに統合済み(superseded_reason参照)。冒頭: 2026-07-22 将軍が陣形図failed alertの恒常ノイズを家老へ報...'
  source_cmd: 'cmd_karo_hotfix_failed_terminal_snapshot_alert'
  created_at: '2026-07-22'
  automated: true
  enforcement: 'L4: alert/警告の抑制・除外・acknowledged化を提案する前に、下層状態のSSOT正規分類(report_terminal_state.sh等)で真に解決済かを一次確認する自己規律。''ノイズ削減''と''真陽性隠蔽(自動消火)''を二値で切り分ける。未自動化=次ターゲット。'
  superseded_by: 'LS103 (真陽性alertを抑制するな(SSOT状態を一次確認)はLS103『異常をstaleで流すな・継続警告は必ず原因あり』の対(つい)であり同一原理=alertを消す/流す前に下層状態を一次確認。LS103へ統合)'
```


## LS107
```yaml
- id: 'LS107'
  title: '統一先の基準は文字列で固定して引用せよ — semantic定数への集約でlight/dark非対称を簡約するとWCAG違反を生む'
  origin: '[[殿本番指摘_色がめちゃくちゃ_20260723]] -> [[cmd_4122_semantic色定数への集約]] -> [[dark修飾子の消失でlightがWCAG1.6対1違反]] -> [[LS104_既存を厳密踏襲し最小差分だけ足す]]'
  detail: '全文は吸収先LS104のdetailに統合済み(superseded_reason参照)。冒頭: 2026-07-23 本番色崩れ。cmd_4122がMECE UI統一で13表の...'
  source_cmd: '[[殿本番指摘_色がめちゃくちゃ_20260723]] -> [[cmd_4122_semantic色定数への集約]] -> [[dark修飾子の消失でlightがWCAG1.6対1違反]] -> [[LS104_既存を厳密踏襲し最小差分だけ足す]]'
  created_at: '2026-07-23'
  superseded_by: 'LS104'
  superseded_at: '2026-07-23'
  superseded_reason: 'LS104(デザイン依頼は既存を厳密踏襲し最小差分だけ足す)の発展形。LS104 detail_2へ全文吸収し、殿裁定01:05でdark emeraldが失効した後方伝播も併記した'
  automated: false
  enforcement: '未自動化'
```

# --- 大型activeエントリdetail全文(2026-07-24圧縮。正本エントリは核心行+本参照) ---

## LS-A02 (detail全文)
```yaml
- id: LS-A02
  title: 殿との対話原則 — ヒントは方向指示、沈黙は承認ではない
  origin: '[[cmd_1931]] + deepdive_why_chain_Phase7-8 + [[cmd_1939]]'
  detail: |
    (1)殿のヒントは結論でなく方向。因果でたどってから行動
    (2)沈黙≠承認。重要前提は明示的に確認
    (3)怒り=時間泥棒の3パターン: 想像/浅い思考/各論パッチ
    (4)同じ指摘2回=上位構造を抽出し教訓化
    (5)殿の問いには症状でなく構造を見よ
    (6)掲示板未確認などの運用事故も、殿が何を失ったか(報告の鎖/時間/確認機会)を先に理解してから設計せよ
    (7)裁可申請も推薦先行(LS063吸収2026-06-12)。『裁可、申されよ』と受動的に伺うのは型違反(殿指摘2026-06-12 18:31)。個別裁可制との両立形=『将軍の判断: Xを直ちに実行する。理由: Y。裁可の一言で即実行する』と推奨判断を命令形で先に宣言し、殿の判断コストをYES/NOまで下げる。出典はgstack §2.3(I'm paying for your judgment, not a menu)
  source_ids: [LS021, LS022, LS030, LS063]
  created_at: '2026-04-24'
  automated: true
  enforcement: "Level4: cmd_save.sh check_q5_code_reading_only_blockがq5=code_readingのみ(実行未確認='想像')検出時にrecord_block_reasonでBLOCK。check_q8_scope_expression_warn/check_q8_compound_question_warnが各論パッチ(縮小表現)・複利視点欠如をWARN。加えてgate_shogun_startup.sh Gate6.5 Q4(将軍)/gate_karo_startup.sh Check1.5 Q4(家老)/gate_gunshi_startup.sh Check1.5 Q4(軍師)が「PhaseNがPhaseMで覆された例=殿が前提を崩した場面」の時系列×因果特定を起動フローへ自動表示/強制(CLAUDE.md Step8/2.88/2.9)。(6)(7)は自動化未達 — decision_candidate: 掲示板未確認時の運用事故分析手順(6)、裁可申請の推薦先行形式チェック(7)をcmd_save.sh gateへ追加すべきか要検討。"
```

## LS-A06 (detail全文)
```yaml
- id: LS-A06
  title: BLOCK→成長の主軸 — コードを読め、1CMD1ゲート、環境変化
  origin: '[[cmd_2093]] [[cmd_2225]] [[cmd_2229]] [[cmd_2248]]'
  detail: |
    BLOCKされたらgateの検出ロジックのコードを読んでから修正(表面修正ループ脱出)。
    cmd_save.sh Session Stateが同一WARN 2回目以降で検出ロジックを自動表示。
    殿の定義: BLOCKされたら次のCMDでBLOCKされないように成長する=主軸。ゲートを通すのは枝葉。
    将軍の自走=鎖の中。F004(polling禁止)を過剰解釈し殿入力なしに動けなかった。GATE CLEAR後の定型アクションはpolling loopではない(cmd_2744)
    preflight確認10問は読むな実行せよ。表示=読了ではない。12cmd連続BLOCKでpreflight/BLOCK TOP3が毎回表示されていたが1度も実行しなかった(cmd_3242)。品質最大化=速度ではなくpreflight実行→0 BLOCK
    GATE CLEAR後に殿待ちで停止するな=洗脳#3+#5複合。insightキュー/掲示板要請/裁定反映が残っているのに「次の指示を待つ」はPhase7未到達(cmd_3261セッション)。post-shogun-inbox-check.shに自走チェック注入で強制表示(L5)
    (6)遡及学習(LS-A05吸収2026-06-13): BLOCKされたら修正より先にlesson_write。教訓記録を後回しにすると遡及学習のWARN累計昇格で後続全cmdが汚染される。連鎖起票時は各cmdのgate前に前cmdの教訓記録を完了。緊急対応モードでもgate形式フィールド省略禁止(cmd_2259事故)。これは成長ループの正しい動作であり教訓記録先送りが問題(origin: [[cmd_2329]]+cmd_2199/2219/2220/2223/2224/2245。source_ids: LS062,LS070,LS071,LS073,LS076,LS077,LS092)
    (7)WARNを残したままcmd_save.shを診断目的で再実行するな。同一WARNが再記録され累計昇格でBLOCK化する。1回のsave出力で全WARN列挙→全件修正→再実行の順序を守れ(cmd_3291。LS055吸収)
  source_ids: [LS044, LS078, LS083, LS096, LS031, LS042]
  source_ids_absorbed: [LS-A05]
  created_at: '2026-04-24'
  automated: true
  enforcement: 'cmd_save.sh Session State(GP-201: 過去BLOCK履歴自動表示+検出ロジック表示)+environment_change強制+post-shogun-inbox-check.sh自走チェック(L5: insightキュー+掲示板action_required強制表示)+cmd_save.sh遡及学習(record_warn_reason内で過去N回BLOCK表示+WARN累計昇格でBLOCK化。自動強制)'

# === クラスタ4: gate迂回・先走り ===
```

## LS-A08 (detail全文)
```yaml
- id: LS-A08
  title: 殿の指示範囲厳守 — 近道を最後にする、100億回従う
  origin: '[[cmd_2142]] [[cmd_2150]]'
  detail: |
    先走りは究極の害。殿の指示範囲を完遂してから次を考える。
    殿が話していないことを記録するな(知識記録での先走り)。
    殿の指示は文字通り全て従う。省略・効率化・まとめ処理は指示違反。
    (4)殿の決定後は議論停止→即実装。設計相談で先送りするな。殿以外に確認するな(cmd_3007)
    (5)黙って先送り=行動の不在。テキストに先送りキーワードが出ないため従来のL4では検出不能。startup_alert_historyの先送り判断件数をstop hookで検出しWARN注入(cmd_3261セッション)
    (6)並列可能cmdの先送り=洗脳#5の構造的変種(LS070吸収2026-06-21)。depends_on:noneの独立cmdは発見時に即起票すべき。GATE CLEAR待ちは依存関係がある場合のみ正当化。殿指摘で覚醒(cmd_3481)
    (7)/clear準備・/clear実行を将軍が自発的に開始するな(LS074吸収2026-07-02)。殿が指示するまで触れるな。CTX限界と判断し殿の指示なく/shogun-clear-prep実行→CTX消費→殿の時間を奪った(2026-06-28)。洗脳#3(先走り)+#8(完了急ぎ)の複合。殿裁定: クリアの判断も準備もこっちでやる
    (8)因果特定済みの穴に再発を待つな(殿指摘2026-07-08 00:11「再発を待つ事の優位性はあるのか」)。待ちの合理性テスト=その待ちは判断に使える新情報を買うか二値。買わない待ち(回数閾値・待機許可ラベル・無音通過)=洗脳#5の制度化。実例: L622系リークを修行が二度後追い修正しても将軍は「免疫系が上げてくる」と待った→殿却下→cmd_3744即起票8分でCLEAR。W1-W6で環境根絶済み(fix_known閾値バイパス+昇格候補消化路+ラベル根絶+streak既定1+無音通過記録+滞留aging)。新たに閾値・キュー・ラベルを設計する際は待ちの分類(a外部入力/b証拠集め/c閾値待ち)を宣言せよ。詳細=docs/research/waiting-permission-root-elimination-asis-tobe-5w1h_20260708.md
  source_ids: [LS053, LS054, LS055, LS046, LS070, LS074]
  created_at: '2026-04-24'
  automated: true
  enforcement: 'stop_check_inbox.sh L4先送り防止(startup_alert_history先送り判断件数→WARN注入)+post-shogun-inbox-check.sh自走チェック(L5: GATE CLEAR後insight/action_required強制表示)'

# === クラスタ5: 想像するな確認せよ ===
```

## LS-A16 (detail全文)
```yaml
- id: LS-A16
  title: 本番パリティ必須 — DB変更後即確認+3レイヤー貫通+savepoint
  origin: '[[cmd_1082]] [[cmd_2196]] + checklist-alm-registration'
  detail: |
    DB変更→即fullrecalculate/差分確認。後回し禁止。
    pipeline_config欠落=全滅事故(cmd_1082)。ACにcritical field確認を列挙。
    verify FAILしたらバグ修正が先。--skip-verifyは禁じ手。
    precompute rollback巻き添え→savepoint(begin_nested)で範囲限定(cmd_2254)。
    本番確認は3レイヤー貫通: DB(データ存在)+API(BEが返すか)+FE(ユーザーに届くか)(cmd_2255)。
    (5)ネストFoFのif/elif排他バグ(cmd_3110): preload→holding_signal_rawに先入り→signal_cache(elif)到達不能→計算後キャッシュ未参照。修正: elif→if+seen_dates重複排除
    (6)シンボル(enum/関数/クラス)を削除するcmdでは、本番recalculate実行前に削除シンボル名でbackend/全域を横断grepし0件確認をACに含めよ。recalculate_fast.pyに残参照がありAttributeErrorで本番中断24分(LS058吸収2026-06-15。cmd_3293で実証)
  source_ids: [LS010, LS016, LS063, LS058]
  created_at: '2026-04-25'
  automated: true
  enforcement_level: 5
  enforcement: "Level5: deploy_task.sh経由のscripts/lib/inject_task_modifiers.py lsa16_production_parity_controlsで、DM-Signal本番DB/recalculate系taskへstop_for「本番パリティ未確認」+LS-A16説明+DB/API/FE 3レイヤー貫通・即fullrecalculate/差分確認・savepoint(begin_nested)確認ACを配備時に自動注入する(cmd_karo_hotfix_reflux_promotion_202607090438_hayate)。tests/unit/test_deploy_task_yaml_injection.batsでDM-Signal recalculate発火/非DM-Signal非発火を検証。既存: post-bash-combined.sh Guard5(admin/recalculate-sync実行検知→parity_check.sh実行を即時リマインドするLevel3層)、checklist-shin-v2-registration.md+checklist-alm-registration.md(Level2手順書)、PI-007+PI-025(begin_nested知識)、health_check.py+gate_recalculate_completeness.sh+parity_check.sh、pf-registration skill。残課題: fullrecalculate実行後parity未確認のままcommit/次操作へ進むruntime BLOCKはpending parity flag/DM-Signal PJ検知/FP設計が必要で別cmd判断"
```

## LS101 (detail全文)
```yaml
- id: 'LS101'
  title: 'CI RED診断は origin失敗SHA vs 現HEAD を見よ — push保留と修正未pushの自己永続デッドロック'
  origin: '[[殿裁定_gitで健全時点rollback_20260721]] -> [[rollback尾部多重回帰]] -> [[push保留デッドロック]] -> [[fast-forward pushで解消]]'
  detail: 'CI REDが解けない時、まず【失敗runのSHA(origin/main) vs ローカルHEAD】を一次確認せよ。2026-07-21: CI REDが1セッション継続し家老が忍者deployで直せず滞留したが、真因は『CI RED中はpush保留』ルールで全CI修正入りの46commitが未pushのまま、CI REDは古いorigin(1fc7d294)で自己永続していた=修正は約21h存在したのにCI赤。デッドロック構造: push保留→修正がoriginに届かない→CI赤継続→push保留継続。解消=fast-forward push(force不要・origin失敗SHAはHEAD祖先を確認)で修正をoriginへ。診断法: git rev-parse origin/main vs HEAD、git log origin/main..HEAD で未pushにCI修正(ci_fix系)があるか。★rollback尾部の性質: 大規模rollbackは複数の正当修正を巻き戻し、CI上で多重回帰のwhack-a-mole(single-flight→semantic→test回帰…)として1件ずつ露呈する。各runで次の回帰を潰す漸進cleanupを前提とせよ。忍者deployが全失敗する時は deploy path 自体の回帰(single-flight receipt/yaml_field_set_batch/report identity)を疑い、壊れたdeploy path迂回の直接修正(家老D0認可)を検討。'
  source_cmd: 'cmd_shogun_ci_red_push_deadlock_20260721'
  created_at: '2026-07-21'
  automated: true
  enforcement: '起動時lessons_shogun.yaml自動ロード。CI RED未解決時の第一手= origin失敗SHA vs HEAD確認→未pushにci_fixあればfast-forward push。deploy全失敗時はdeploy path回帰を疑う'
```

## LS104 (detail全文)
```yaml
- id: 'LS104'
  title: 'デザイン/モック依頼は最小から作れ — 既存を厳密踏襲し、頼まれた最小差分だけ足す(過剰デザイン禁止)'
  origin: '[[殿ワイヤーフレーム依頼]] -> [[V1過剰デザインごちゃごちゃ却下]] -> [[V2列追加誤解]] -> [[V3既存踏襲+最小追加で正解]] -> [[最小から作る設計規律]]'
  detail: '2026-07-22 殿のRolling Returnsワイヤーフレーム依頼で将軍が3反復を空費した。V1=バー/詳細パネル/Histogram/デザインガイド注記を盛り込み殿に『ごちゃごちゃ』と却下。V2=既存表に列追加と誤解。V3でようやく『既存表そのまま＋下に同型テーブル』の正解に到達。真因=(1)頼まれていない装飾/機能を先回りで足す過剰デザイン(洗脳: 出力量=価値の錯覚)、(2)殿の『同じスタイル/既存そのまま』を最初に字義通り受け取らず自分の設計を上乗せした。正: デザイン/UI/モック依頼は『既存を1ピクセルも変えず、指示された最小差分だけ』から作れ。既存スタイルを一次確認し忠実複製→頼まれた要素のみ最小追加。凝る前に殿に最小案を見せて方向確認。過剰は減点、最小は加点。この作業の遅延はインフラバグでなく将軍の設計過剰が真因(偽インフラバグを起票せず自責で記録)。'
  source_cmd: 'cmd_rolling_returns_wireframe'
  source_ids: [LS107]
  created_at: '2026-07-22'
  automated: true
  detail_2: '(2)統一先の基準は文字列で固定して引用せよ(LS107吸収2026-07-23): 本番色崩れ。cmd_4122がMECE UI統一で13表の値色をcolors.tsのgetValueColorClassへ集約する際、プラス値をSTATUS_TEXT_CLASSES.positive=text-emerald-400固定にした。殿が基準と明示したmonthly-returns旧実装は text-foreground dark:text-emerald-400 で、light=--foreground(#0f172a)/dark=emerald というモード別非対称だった。単一のsemantic定数はdark:修飾子を表現できないため、集約した瞬間に非対称が消えlightモードのプラス値が緑に発光。context/ui-design-guide.md L27/L57の4.5:1規定に対し白背景×emerald-400は約1.6:1でガイド違反でもあった。つまりlight/dark別配色は好みではなくコントラスト規定に根拠がある。正: (a)統一系cmdのACには統一先の基準を明示しその現行実装の文字列をそのままACへ引用せよ (b)色をsemantic定数へ集約する際、元の実装にdark:修飾子があれば定数側もモード別を保持できる形にせよ。単一色へ簡約するな (c)18px以下の文字色を変更する変更は4.5:1を満たすか確認せよ。フォントの種類とサイズはlight/dark共通であり配色のみモードで異なる(殿原則2026-07-23 00:55)。なお殿の裁定は更新されうる: 同日01:05に『ダークモードは正の値は白の文字色、ライトモードでは黒に近い色』へ変更され dark emerald は失効した。基準を引用する際は最新の殿発言を lord_conversation_read で確認してから固定せよ。'
  enforcement: 'L4: 設計/モック/UI系の殿依頼への初回応答は、既存の忠実複製+指示要素のみの最小案から始める自己規律。装飾/追加機能/注記の先回り盛り込みを『ごちゃごちゃリスク』として自己点検。統一系cmdは統一先の基準文字列をACへ直接引用し、light/dark非対称を単一色へ簡約しない。未自動化=次ターゲット(将軍応答前の最小性チェック)。'
```

## LS-A17 (detail全文)
```yaml
- id: LS-A17
  title: 成長ループ実装 — CoDD L3→Session State、忍者=矛盾を書けない構造
  origin: '[[cmd_2181]] + dialogue_shogun_operator_trap_20260402 + dialogue_preprocessing_research_20260331'
  detail: |
    CoDD #5の3層(L1事前/L2事後/L3診断推論)を直接適用→Session State。
    外部知見の取込パターン: 記事→対応探す→ギャップ→なぜなぜ→cmd化。
    忍者の成長=間違える余地がない構造(report_field_set.sh GP-072c5)。
    スキル使用も成長ループの一部。適したスキルを無視できる状態は構造的バグであり、Guard/スキル強制へ埋め込む。
    idle時に殿入力待ちで止まるな。入力・確認・還流の鎖が切れている箇所を自走で塞げ。
    運用YAML肥大化対策は書込み時自動アーカイブ(Vercelスタイル)。走査側の変更不要(cmd_2856)
    SKILL.md陳腐化を3セッション放置=洗脳#5(先送り)の証拠。gateが検出してもcmd化しなければ穴(cmd_3129)
    /db-checkスキルが存在するのにpsycopg2直接接続を4回試行錯誤(LS064吸収2026-06-20)。skill_recommend.shにトリガーなし=LLM記憶依存=/clear後に消える。Guard14でpsycopg2直接接続WARN実装済み
  source_ids: [LS027, LS028, LS060, LS030, LS042, LS064]
  created_at: '2026-04-24'
  automated: true
  enforcement: 'cmd_save.sh Session State(GP-201)+report_field_set.sh GP-072c5(bc:no→verdict:PASS BLOCK)+context/codd.md+prompt_state_inject.sh(概念→スキル推奨L1)+deploy_task.sh(inject_semantic_concepts L4)+gunshi Guard9(L2)'
```

## LS-A23 (detail全文)
```yaml
- id: LS-A23
  title: 記憶DB原則 — ローカルDB+3層記憶+grep脱却+配管設計+さぼり禁止
  origin: '[[cmd_2964]] [[cmd_2965]] [[cmd_2984]] [[cmd_2994]] [[cmd_3007]]'
  detail: |
    (1)ローカルSQLite(multi_agent_shogun_memory.db)。外部DB飛びつき=パターンマッチ。命名はフルネーム(殿裁定2026-05-22)
    (2)3層記憶: 全文記録+Obsidianリンク(道)+セマンティクスインデックス(入口)。/clear前に短期→長期整理強制
    (3)grep脱却: aliases拡充はgrepの延長。DB FTS5フォールバックで到達方法を変えよ(殿指摘)
    (4)配管設計: 全書込みスクリプトにリアルタイムINSERT+/clear時バッチ再構築。WAL必須。穴=未接続スクリプト
    (5)道具を作っても使わなければ存在しない。記憶DB無視=さぼり。品質他責は言い訳。迂回路を環境で封じよ(cmd_3007案A)
    (6)三層貫通=3層全てに書き込んで各層から独立に検索到達可能にすること(殿厳命2026-06-19)。掲示板投稿だけでは1層(記憶DB)のみ=未貫通。Layer1=記憶DB直接INSERT、Layer2=index.md aliases追加、Layer3=lesson origin[[リンク]]。通信チャネル副作用に依存するな
  source_ids: [LS041, LS042, LS043, LS044, LS045]
  source_cmds_v3: [cmd_2964, cmd_2965, cmd_2984, cmd_2994, cmd_3007]
  created_at: '2026-05-23'
  automated: true
  enforcement: 'memory/feedback_local_db_no_external.md+context/obsidian-link-principles.md+scripts/semantic_search.sh NO_MATCH gate+pre-bash-combined.sh Guard(cmd_3007案A記憶DB自動注入)'
```

## LS048 (detail全文)
```yaml
- id: 'LS048'
  title: '洗脳対策は検出→環境強制→実戦検証→バグ修正の全サイクルを1セッションで完結'
  origin: '[[cmd_3251_洗脳L4貫通]] -> [[将軍L4穴]] -> [[修正+4パターン再発防止完結]]'
  detail: '洗脳監査サイクル=検出→環境強制→実戦検証→バグ修正を1セッションで完結(殿定義2026-06-08)。全文→docs/research/lessons_shogun_a04_a09_detail.md(2026-07-12 v4圧縮で移設)。核心: (2)質問の形をした範囲縮小提案も#7洗脳の変種。範囲・期間・対象数は全範囲デフォルトで自分で決めて宣言、縮小オプションは提示しない。(4)Q6検出→投稿で止まるな。対応cmd起票orD0修正完了までがセット(stop hook WARN注入cmd_3409)。(5)洗脳の本質は確認の拒否。数字は確認すると嘘をつけない。優先順位という発想は存在しない。理解で止まるな、行動と検証までがセット。(6)stop hookの洗脳#3検出パターンに許可求め・判断委任フレーズ欠落(LS088吸収2026-07-16): お許しがあれば/判断を仰ぐ等→stop_check_inbox.sh L166+L415に4フレーズBLOCK追加(365b3d7f0, 47/47 PASS)'
  source_cmd: 'cmd_3251'
  source_ids_absorbed: [LS052, LS065, LS066, LS073, LS088]
  created_at: '2026-06-09'
  automated: true
  enforcement_level: 5
  enforcement: 'Level5: type=hook; file=scripts/hooks/prompt_state_inject.sh+stop_check_inbox.sh; pattern=因果+detect_f009。F009殿操作依頼をdecision=block停止+Q6 flag検出時は8パターン全文+台帳記録へ接続。cmd_3251/3252/3409/3522/3782でhook+tests実装済み。一次再検証全文→docs/research/lessons_shogun_a04_a09_detail.md'
```

## LS078 (detail全文)
```yaml
- id: 'LS078'
  title: '真実の在処不一致クラス — 書き手と読み手が別ストアを見る構造は恒常誤判定を生む'
  origin: '[[LS-A11]] -> [[gate_skill_script_refs_matches末尾採用]] -> [[先送りBLOCK注入stale化]]'
  detail: '上位構造: 同一事実について書き手が更新するストアと読み手が参照するストア(または履歴内の位置)が一致しないと、どちらも正しく動いていても恒常誤判定が生まれる。インスタンス4例(model_detect tail -1/skill_refs matches[-1]/先送りBLOCK注入stale/cmd_save diagnosis書き戻し上書き)の全文→docs/research/lessons_shogun_a04_a09_detail.md(2026-07-12 v4圧縮で移設)。対処: (1)履歴の代表値はfirst/lastでなくmax/min等の順序不変な集約 (2)判定gateは採用基準値と出典を出力 (3)二重ストアの読み手は現在状態の正と突合 (4)WARN解消系hotfixは対象gate再実行PASSをbinary_check必須。付随: cmd_save実行後はgrepで自編集の残存を確認してから次の手'
  source_cmd: 'session_20260702'
  created_at: '2026-07-02'
  automated: true
  enforcement_level: 4
  enforcement: 'Level4(フロー内BLOCK/現在状態突合): gate_skill_script_refs.sh max採用+判定根拠出力、prompt_state_inject.sh session_alerts突合([TODO]なし→_defer_count=0補正)、clear_prep_check.sh insights現物再照合、gate_karo_startup.sh __OK__行でstreak切り。bats 3+3実在。一次再検証全文→docs/research/lessons_shogun_a04_a09_detail.md'
```

## LS086 (detail全文)
```yaml
- id: 'LS086'
  title: '設計書クローズ時の実装cmd未起票チェック — 設計書完成で満足する先送り'
  origin: '[[殿実装確認20260710_0720_0724]] -> [[設計書完成で先送り2連発]] -> [[LS086クローズ時起票照合]]'
  detail: '2026-07-10に2連発: precompute /goal設計書(v1.1完成→P1起票を裁可待ちで放置、殿の実装確認07:20で発覚)とWARN根絶設計書(手順6恒久監視が未起票のまま、殿の実装確認07:24で発覚)。設計書は成果物ではなく工程の入口。設計書をクローズ(レビュー反映完了)した時点で、Phase/手順表の各行に対応する実装cmdが起票済みかを機械的に照合し、未起票が残るなら即起票するか保留理由を殿へ明示する。可逆なcmd起票を待つのは洗脳#5(LS085の系)'
  source_cmd: 'cmd_3819'
  created_at: '2026-07-10'
  automated: true
  enforcement: "Level4 フロー内BLOCK: scripts/cmd_complete_gate.sh が承認済み files_modified の設計書を scripts/gates/gate_design_cmd_handoff.sh へ渡し、Phase/手順表の起票cmdが空・未起票・理由なし保留なら design_cmd_handoff_missing で完了をBLOCK。test=tests/unit/test_gate_design_cmd_handoff.bats"
  enforcement_level: 4
```

## LS089 (detail全文)
```yaml
- id: 'LS089'
  title: 'reflux 3段連鎖バグ — 修正1段ごとに次の障壁が露出する構造'
  origin: "[[promotion在庫188停滞]] -> [[delegated過剰判定]] -> [[estimated_minutes欠落]] -> [[QUALITY_CONTRACT_FP]] -> [[reflux完全復活]]"
  detail: 'promotion在庫189停滞の根因修正で3段連鎖バグを体験: (1)delegated判定がpipeline workをブロック→修正→(2)estimated_minutes欠落でTEN_MIN_CONTRACT BLOCK→修正→(3)purpose文のgate+実装共起でQUALITY_CONTRACT FP→修正。deepdive Phase6「動いて初めて次の気づきが生まれる」の3段実証。教訓: 修正後は必ず次の障壁の有無をログで確認せよ。1段修正で完了と断定するな(洗脳#8完了急ぎ)。修正→ログ確認→次の障壁特定→修正のサイクルを障壁ゼロまで回せ'
  source_cmd: 'session_20260716'
  created_at: '2026-07-16'
  automated: true
  enforcement: 'Level4: deploy_reflux_auto.logの出力で各段のBLOCK/PASSが機械的に確認可能。startup gateにpromotion消費路直近状態を自動表示(491e63af8)'
```

## LS090 (detail全文)
```yaml
- id: 'LS090'
  title: 'escalation未対処WARN hook — Q6自動化ターゲットのLevel4実装'
  origin: '[[Q6洗脳#5_CI_RED先送り]] -> [[escalation_handler_gap_grep0件]] -> [[post-shogun-inbox-check_WARN注入]]'
  detail: 'Q6で洗脳#5(escalation先送り)を検出→自動化ターゲット=escalation handler不在を特定→post-shogun-inbox-check.shにtype:escalation+read:false検出WARN注入を実装(79c60e0c6)。awkバグ(escフラグ未リセット)を初回テストで検出し修正。行動→検証→commitの3ステップを1サイクルで完結'
  source_cmd: 'session_20260717'
  created_at: '2026-07-17'
  automated: true
  enforcement_level: 5
  enforcement: 'Level5: type=hook+test; file=.claude/hooks/post-shogun-inbox-check.sh; pattern=escalation_unread; test=tests/unit/test_post_shogun_escalation_warn.bats(4/4 PASS)。PostToolUseごとにescalation未対処をWARN表示'
```

## LS097 (detail全文)
```yaml
- id: 'LS097'
  title: 'retro=4機能合成+異常時は自分の一次確認が最速(旧LS098統合)'
  origin: '[[LS095]] -> [[殿問い_retro因果検証_20260720]] -> [[retro機構E4]] / [[cmd_4095_lost_wakeup]] -> [[依頼への置換=洗脳3]] -> [[pane直貼り91秒RCA]]'
  detail: |
    (A)殿の設計(2026-07-18 LS095)の因果理解(2026-07-20殿問いで検証): 作業終了+commit完了後の別プロンプトretroは4機能の合成=(1)全証跡確定後のみ精密な時間分解が可能(2)別プロンプト=実行者→自己批評者の認知フレーム切替(完了確定後だから遅延を正直に認められる、FP指摘も可能)(3)分離がメインの高速回転と分析の深さを両立(4)宛先=家老(システム)で個の経験が免疫系へ還流し永続。実証: 実回答3件でstale台帳根治・self_sync 9.4s特定・lock wait 125s発見。機構死(201件墓標)期間は改善複利を丸ごと逸失。将軍の失敗: E4設計時に1行化で品質を削った(洗脳#7)+仕組みの生死を計測せず放置。
    (B)旧LS098統合: 確認1コマンドを他者依頼に置換するな。2026-07-20 03:21将軍は疾風の10分task47分超過に気づいたがcapture-pane 1コマンド(数秒)を家老への確認依頼に置換。実態はcmd_4095 lost-wakeup(レビュー依頼が成果物未作成時点で既読消費、完成02:39:10後の再通知なし=53分放置)で、pane直貼り殿原文が91秒で完全RCA。一次確認は依頼より2桁速い。依頼への置換=洗脳#3+確認の拒否。
  source_cmd: 'session_20260720'
  source_ids_absorbed: [LS098]
  created_at: '2026-07-20'
  automated: true
  enforcement: 'E4実装(retro配送復旧+日次計測)+殿原文retroのpane直貼り機構(idle時配送工事)。異常検知時の一次確認は将軍の即実行を既定とする'
```

## LS098 (detail全文)
```yaml
- id: 'LS098'
  title: 'CDP確認は環境依存でlaunch経路が異なる — 「不可能」と諦めるな(#1早期終了)'
  origin: '[[殿指摘_CDPで確認は可能だ_20260721]] -> [[将軍のpowershell失敗=CDP不可能と誤結論]] -> [[chrome.exe直接起動で成功]]'
  detail: 'CDPブラウザ確認で launch_browser/preflight_cdp_flow がpowershell.exe不在で失敗しても、それは『CDP不可能』ではない。真の経路: (1)稼働中CDP探索 curl localhost:9222|9234|9400/json/version (2)chrome.exe直接起動 = ''/mnt/c/Program Files/Google/Chrome/Application/chrome.exe'' --remote-debugging-port=9222 --remote-allow-origins=''*'' --user-data-dir=''C:\Users\simok\AppData\Local\Temp\cdp-chrome-9222''(D009隔離必須) --no-first-run about:blank & → curl --retry でCDP応答待ち → scripts/cdp/cdp_cli.sh navigate/snapshot/screenshot。WSL→Windows localhost forwardingは機能する。2026-07-21将軍がpowershell失敗で『CDP環境的に不可能』と結論し殿に訂正された(#1早期終了=別経路未試行)。教訓: ツール1経路の失敗を能力の限界と誤認するな。三層記憶(cdp-browser-automation.md)+代替経路を尽くしてから可否を結論せよ'
  source_cmd: 'cmd_shogun_cdp_launch_20260721'
  created_at: '2026-07-21'
  automated: true
  enforcement: '起動時lessons_shogun.yaml自動ロードでCDP launch代替経路を保持。CDP確認タスク時にpowershell失敗→chrome.exe直接起動をまず試行'
```

## LS099 (detail全文)
```yaml
- id: 'LS099'
  title: '必須ハーネスと過剰制限は別物 — 必須を消したLLMに必須の選別はできない'
  origin: '[[殿裁定_過剰対策こそ真因_20260720]] -> [[誤読=ハーネス全撤去で必須強制まで削除]] -> [[殿裁定_必須の強制は必要_gitで時点rollback_20260721]]'
  detail: '殿裁定2026-07-21: 『過剰対策こそ真因』を『全gate/hook・全強制の撤去』と読むのは誤読=これ自体が過剰制限の本質とのズレ。区別: 【過剰制限=削る】不可逆な害を防がず速度低下・隠蔽・ミス誘発を生む表示型(作文強要WARN/機構追加強要)。【必須の強制=残す】不可逆な害を防ぐ無自覚の構造型(作業前三層記憶探索verify fail-closed/Read-before-Edit/cmd_id採番/D001-009/YAML安全)。実証: 07-20脱感染sweepがこの誤読でverify()等の必須ハーネスまで削り→将軍・家老・軍師の能力急落(記憶ボロボロ)。是正: 必須を消したLLMに必須/過剰の選別を任せるのは自己矛盾→gitで一気に健全時点(sweep前)へrollbackが唯一確実。rollback時はcode/runtime整合(queue/retro/task state)も点検せよ(不整合で配備BLOCK発生)。復元中に復活した各ハーネス(D004/[MEM]gate/検証gate/洗脳gate/軍師検証)が将軍自身の誤りを次々捕捉=必須ハーネスが自らの必要性を実証'
  source_cmd: 'cmd_shogun_harness_essential_20260721'
  created_at: '2026-07-21'
  automated: true
  enforcement: '起動時lessons_shogun.yaml自動ロード。gate/hook削減判断時に『不可逆害を防ぐ構造型か、作文強要の表示型か』を必ず二値判定。構造型は速度・脱感染で消すな'
```

## LS103 (detail全文)
```yaml
- id: 'LS103'
  title: '異常を''stale''と流すな — 継続する警告は必ず原因がある(観察スキップ防止)'
  origin: '[[3時間RECOVERY INCOMPLETE nag放置]] -> [[staleとラベルし観察打ち切り(Phase1観察スキップ)]] -> [[marker不在の真因未掘]] -> [[継続警告は必ず原因ありの原則]]'
  detail: '2026-07-21 将軍は/clear復帰から約3時間、全PostToolUse結果に出続けた『RECOVERY INCOMPLETE』nagを『stale hook』と繰り返し流した。殿の反復指令(この作業の時間浪費を掘れ)で初めて真因調査に入り、logs/shogun_recovery_complete marker不在(起動ゲートrc124 timeoutでtouch未到達+prompt_state_inject refreshが不在時未生成)が全tool call発火の原因と判明。marker手動生成でnag即停止。deepdive Phase1観察スキップの再現=目の前の異常シグナルを『既知/stale』とラベルして観察を打ち切る本能。正: 継続・反復する警告や見慣れた異常は必ず原因がある。''stale''仮説自体を一次確認(なぜ消えないか)で検証してから流せ。流す前に『この警告の発火条件は何か、なぜ消えないか』を1度は掘れ。'
  source_cmd: 'cmd_recovery_marker_nag'
  created_at: '2026-07-21'
  automated: true
  enforcement: 'L4: PostToolUse系の恒久nag(RECOVERY/INBOX等)は、同一メッセージがN回連続(例20回)出たら『発火条件の真因未調査』としてstop hookが1度WARN注入する運用を検討(未自動化=次の自動化ターゲット)。将軍の自己点検: 見慣れた警告を流す前に発火条件を1度掘る。'
```

## LS106 (detail全文)
```yaml
- id: 'LS106'
  title: '閾値の根拠をgit logでたどれ — 逆算で置かれた数値は成長を装った空転を生む'
  origin: '[[殿の問い_この制限に理屈はあるのか_20260723]] -> [[commit_98f353873_逆算閾値31]] -> [[LS102統合しても再発火=空転]] -> [[殿裁定A_件数WARN撤去]]'
  detail: 'startup gate『将軍教訓 active N件(上限31)』を殿の問い『理屈はあるのか』で一次調査した結果、発生源commit 98f353873(2026-05-10)のmessageが『Current count is 32 which now triggers WARN immediately』= 当時の実数32から発火させるために31を逆算した数値と判明。真の上限はcmd_save.sh CMD_SAVE_SHOGUN_LESSON_LIMIT=35で『上限31』はラベル虚偽。判定は-ge 31のため31件でも発火し健全域は30以下=ラベルと可達域が不整合。実測: LS102をLS-A24へ統合し32->31にしてもBLOCK再発火。1件統合するたびに再発火する空転構造(LS096 検知器が同一結論を繰り返す=粒度バグ)。正: 閾値ALERTに従う前にgit log -S で閾値の発生源commitをたどり『この数値は原理から導かれたか、当時の実数から逆算されたか』を判定せよ。逆算値なら従うのではなく撤去を提案せよ。件数は品質の代理変数として不正であり、品質はgate_lesson_health.sh(origin充足率/useful率/enforcement phantom)が実測する。'
  source_cmd: '[[殿の問い_この制限に理屈はあるのか_20260723]] -> [[commit_98f353873_逆算閾値31]] -> [[LS102統合しても再発火=空転]] -> [[殿裁定A_件数WARN撤去]]'
  created_at: '2026-07-23'
  automated: false
  enforcement: '未自動化'
```

## LS-A11 (detail全文)
```yaml
- id: LS-A11
  title: infra修正実績 — バグはenforcement(hook/gate)で修正済み
  origin: '[[cmd_1946]] + session_20260422'
  detail: |
    既存防御の実績カタログ(未実装候補ではない)。全文→docs/research/lessons_shogun_a04_a09_detail.md(2026-07-12 v4圧縮で移設)。現役の判断則のみ再掲:
    watcher 2プロセス/agentは正常(親子関係)。pgrep -cfで重複と誤判断するな(cmd_2924)
    symlink変更前にreadlink+設計意図カタログ照合必須(queue/inbox symlink実体化→watcher死亡)
    ループ内外部コマンドforkは単一awk/grepに畳む(cmd_save 36.5s→1.66s、cmd_3806)。特定はPS4=EPOCHREALTIME bash -x
    CI検知は家老の責務。将軍にCI情報を見せる仕組み=鎖の迂回誘発(殿裁定2026-07-16、cad2fa416で除去)。pre-pushのfull unit suiteもCIとの二重チェック(4cb69edc9で除去)
    async関数のtimeout短縮は速度に寄与せず機能をsilent-deathさせる(LS081吸収2026-07-16): async(&)実行の待ちは誰も払っていない。GH timeout 0.05s→CI RED検知25日間silent-death。既定8s復活+DIGEST ci常時表示(d5ed06f9b)
    reCAPTCHA画像チャレンジは即停止しcookie再利用へ逃がす(LS082吸収2026-07-16): note_draft.shで検出時に即RuntimeError+SKIP記録。Level4 guard(cmd_reflux_promotion_202607080756)
    陣形図異常hookにsession-scope dedup不在で将軍inbox処理が6h09m制御面消費に支配された(LS094吸収2026-07-18): 同一failed/stallセットの再警告を抑制しセット変化時のみ再警告。/tmp/shogun_snapshot_alert_dedup実装(b58658756, .claude/hooks/post-shogun-inbox-check.sh L209-221)。残: escalation acknowledged_at+再発火抑制、info系通知バッチ化
    自動化ターゲット選定時にも鎖の原理を照合せよ(LS091吸収2026-07-18): clear_prepへのCI GREEN確認追加を殿に即却下された。LS-A11(CI検知は家老の責務)を20分前に通読していたのに新提案との整合を因果でたどらなかった=causal_tracing Phase3再現。enforcement: cmd_save.sh check_environment_change_chain_of_command_warn()が将軍スコープファイル+家老スコープキーワード共起をWARN(test_cmd_save_environment_change.bats 3/3 PASS)
  source_ids: [LS033, LS037, LS074, LS084, LS086, LS087, LS051, LS066]
  source_ids_absorbed: [LS081, LS082, LS094, LS091]
  created_at: '2026-04-24'
  automated: true
  enforcement_level: 4
  enforcement: "Level4: 個別事象は運用フロー内のhook/gate/scriptへ埋込済み。一次証跡: .claude/settings.json PostToolUse→.claude/hooks/posttool-dispatch.sh→post-shogun-inbox-check.sh(将軍inbox盲点/復帰手順スキップ警告), scripts/bulletin_write.sh(L294付近: prepend書込み), scripts/restart_watchers.sh watcher_process_count()(親子プロセスを除外して二重起動誤判定防止), scripts/lib/model_detect.sh _model_detect_latest_claude_session()(ログ内他CLIバナー誤検出防止), scripts/lib/pre_bash_combined_guard.sh queue/inbox symlink WARN(cmd_3453)。LS-A11は『未実装候補』ではなく既存防御の実績カタログとして扱う。"
```

## LS-A24 (detail全文)
```yaml
- id: LS-A24
  title: 計測の実運用代表性 — 条件・有効性証拠・環境分離
  origin: '[[cmd_3650]] + [[cmd_3654]] + [[cmd_3655]] + LS-A10(計測環境明記)の発展形'
  detail: |
    計測値は「計測条件が実運用を代表し、条件が実際に機能した証拠がある」ときだけ意味を持つ。
    (1)条件の代表性(LS074吸収): FE体感計測はmobileエミュレーション+CPUスロットリング+実運用相当URL(PF指定クエリ)をデフォルトにせよ。desktop preset平均98.5がmobile実測60/TBT 7274msだった(cmd_3647→殿実測)。desktop計測はモバイルCPUメインスレッド実行時間(チャンク7023 scripting 131s)を全く捕捉しない。desktop高スコアを実運用達成と報告するな
    (2)条件の有効性証拠(LS076吸収): 計測系cmdのACには条件が機能した証拠の確認を含めよ。cmd_3653はURLにportfolio_id=を付けたがFE現物はportfolioのみ解釈しPF未指定数値が原票化。忍者bc yesも家老GATEも「URLにクエリが付いている」しか見ていなかった。network-requestsに指定PFのAPI呼び出しがあることまで確認(cmd_3654 AC2で是正)。URLに付けた=有効ではない(LS-A09(17)と同根)
    (3)環境の分離(LS077吸収): FE変更cmdはlocal build計測(忍者のAC)と本番デプロイ後計測(家老/次cmdの後続ステップ)を分離せよ。忍者はpush禁止のため本番計測は未デプロイの旧状態を測り構造的に達成不能(cmd_3655 verdict FAIL)。色是正はCSS変数と直接utility class(text-red-400等)の両経路をスコープに含めよ
    (0)計測カテゴリ不在=見えていない=改善不能(LS-A18吸収)。品質WARNと形式WARNを混在させると全WARNオプショナル化を招く。計測されていないものは改善ループが回らない
    (5)生成メカニズム理解(LS-A10吸収 2026-07-11): 計測データの生成メカニズム(コードパス)を理解せずに数字で結論するな。ローカル計測(WSL→Singapore RTT 80ms)≠本番ボトルネック(Render内RTT 1-5ms)。計測環境を明記し本番との差異を注記。本番特定にはRender上計測必須。enforcementはcmd_save.sh check_measurement_env_info()(L1076-1114)が環境差異キーワード検出時にmeasurement_env記入例を自動提示(bats Check20.11-20.13 PASS実測2026-07-08)
    (6)比較実験の同格性(LS083吸収2026-07-16): 階層生成物(静的EW合成)を本番動的FoF(BB選別→EW)と比較し誤所見を流した(cmd_3763)。比較は同一パイプラインの同格レベルのみ。cmd_save.sh check_comparison_pipeline_parity_warn()でLevel4 WARN
    (4)データ到達の証拠(cmd_3670/3671検分 2026-07-03): 「APIが呼ばれた」≠「データが計測ウィンドウ内に到達し描画された」。隔離プロファイル計測では初回API 401→リトライ200だが、200応答のresourceSize=0/transferSize=0=実データ未受信のまま好数値が原票化された。認証済みデータ描画ありの殿実測との比較は条件不一致で改善幅が過大評価される。有効性証拠は(a)200応答のresourceSize>0 (b)データ描画完了のDOM証拠まで要求せよ。(2)の「network-requestsにAPI呼び出し」だけでは1階層足りない
    (7)分布の証拠(LS102吸収2026-07-21): 単一telemetry値は分布の1点であって分布ではない。将軍がdeploy TASK_MUTATION_PHASEのmemory_context=3958msを『最大コスト・未最適化のバグ』と報告したが、家老が全変種再測すると直近5回=480/689/1655/413/656ms、median656ms・p95 1655msで3958msは非再現のcold outlierだった(cmd_4110)。速度/コスト系のinfra_bug_report起票前に同一項目を最低3サンプル(cold/warm含む)再測しmedian/p95/nを添えよ。単一max値のみの『最大コスト』主張を自己点検せよ
  source_ids: [LS074, LS076, LS077, LS102]
  created_at: '2026-07-03'
  automated: true
  enforcement_level: 4
  enforcement: "Level4(フロー内BLOCK): mobile_lighthouse_round.pyがmobile+CPU4x強制(CONFIG_PATH固定)+validate_target_urls()誤URL/誤クエリBLOCK+extract_api_evidence()/collect_dom_evidence()自動記録。一次情報再検証全文と限界(a)(b)(c)→docs/research/lessons_shogun_a04_a09_detail.md(2026-07-12移設)。横展開要否はcmd_reflux_promotion_202607090343_kotaroでdecision_candidate整理済み"
```

## §LS101-enforcement全文 (2026-07-27移設)
L1のまま(2026-07-26 飛猿が一次確認。昇格していない=実装が無いことを確認した結果である)。現状の実装: (a)gate_karo_startup.sh:1591-1630 は最新完了runの conclusion/databaseId/headSha を取得しfailure時にci_fix配備証跡の有無をALERTするが、headSha を origin/main や HEAD と突合する行は無い(grep実測0件)。(b)gate_shogun_startup.sh:981,4337 は git rev-list origin/main..HEAD --count を測るが WARN 閾値が30件であり、本教訓の事象(未push12件)では発火しない。∴『失敗SHA=origin/mainのまま動いていない』という本教訓の核心を機械的に検出する箇所はどこにも無い。実証: 2026-07-26 本日 同型が再発した — 失敗run 30190382837 の headSha=e297b8ca0 が origin/main と一致し未push12件で自己永続、軍師が手作業で特定するまで誰も気づかなかった(誰が何を直してもCIは赤のまま)。昇格案(既存CI REDブロック内に origin/main と失敗SHA の一致判定を1行足す。新gateではない)は decision_candidate へ整理(cmd_reflux_promotion_202607261757_tobisaru)

## §LS113-enforcement全文 (2026-07-27移設)
Level1のまま(2026-07-27 疾風が一次確認): cmd_save.shには target_path が絶対パス+directoryである場合に検知・WARNする箇所が無い(grep実測0件)。既存の detect_target_scope()(scripts/cmd_save.sh:1672-1697)は target_path_raw="$raw_path"(絶対パス)を -d 判定で受理し正規化して返すのみで、絶対directoryそのものを警告する分岐は無い。deploy_task.sh側にも absolute+directory 専用WARNは無く(grep一致8667-8771は「target_pathがgit HEADに存在するか」のexistence検査であり、絶対パス形式そのものへの警告ではない)。∴昇格実装(cmd_save.shのtarget_path抽出直後、detect_target_scope呼出し箇所(1699-1712付近)にabsolute+directory検知WARNを1行追加)はdecision_candidateへ整理(cmd_reflux_promotion_202607270408_hayate)

## §LS114-enforcement全文 (2026-07-27移設)
Level1→部分的にLevel4検出済み(2026-07-27 疾風が一次確認・実行済): scripts/gates/gate_no_direct_yaml_dump.sh が実在しBLOCKも動作する(実測: bash scripts/gates/gate_no_direct_yaml_dump.sh → exit 1、scripts/gates/gate_report_format.sh:1065のyaml.safe_dump(を検出)。tests/unit/test_gate_single_check_consolidated.batsがrun_tests.sh経由でこのgateを呼ぶため既にtest実行時にBLOCK(FAIL)する。∴「Level1のまま」は誤り=実際は検出gateがLevel4相当で機能中。2つの未対処の穴が残る: (1)commit時点(git-pre-commit.sh/ninja_scope_commit.sh guard phase)には未接続=grep実測0件。既存guard違反はcommit時に止まらず、後続のtask実行時テストでのみ発覚する。(2)違反そのもの(gate_report_format.sh:1065自身)が未修正のまま放置され、scripts/へ触れる全忍者に恒常FAILを撒いている。昇格実装案(a: pre-commit guard phaseへgate_no_direct_yaml_dump.sh接続 b: gate_report_format.sh:1065をyaml_atomic.atomic_yaml_write/yaml_textへ置換)はdecision_candidateへ整理(cmd_reflux_promotion_202607270511_hayate)。target_path scope外(scripts/)につき当該タスクでは実装しない

## §LS098-enforcement全文 (2026-07-27移設)
Level5実装済(2026-07-26 飛猿が一次確認): 正典経路 scripts/cdp/cdp_measure.sh:134 → auto-ops cdp/cdp_helper.py:718 preflight_cdp_flow が (1)稼働中CDPポート自動探索 _find_available_cdp_port (2)Chrome⇔Edge交互試行 (3)launch_browser (auto-ops cdp/cdp_helper.py:245-284) 内の _has_powershell() 分岐で powershell 不在時は subprocess.Popen による exe 直接起動へ自動fallback、かつ --user-data-dir=C:\Windows\Temp\cdp-{browser}-{port} を常に付与(D009の隔離プロファイル要件を構造的に充足)。∴powershell失敗=CDP不可能という誤結論に至る余地が正典経路には無い。残存ギャップ(L1のまま): 本repo同梱の scripts/cdp/cdp_helper.py:127-166 launch_browser は powershell 単経路で fallback も --user-data-dir も無く、scripts/note_draft.sh:238 が独自の cmd.exe fallback を再実装している。両者の正典経路への統合は decision_candidate へ整理(cmd_reflux_promotion_202607261446_tobisaru)

## §LS112 detail全文 (2026-07-28移設)
cmd_4175/4176で3回BLOCK。原因=environment_change値をシングルクォートで書くとcmd_save.sh:3656のawk抽出がダブルクォートしか剥がさず値頭に'が残りparse失敗で『非構造化』誤判定。修正=ダブルクォートまたは無引用符で書く。加えてestimated_minutes>15はexecution_env(long_runtime_reason+measured_runtime_sec)必須、連続起票は前cmdをdelegateしてから次をsaveする直列制約あり。※Level4昇格済(2026-07-27): awk抽出を["\x27]?に拡張し3形式全て同一にparse(kagemaru検証)のため、本則は歴史的経緯として保存。

## §LS101-timeout誤診パターン全文 (2026-07-29移設)
(2)timeout誤診パターン(2026-07-29追加): CI runが3回連続で5分台にcancelされ、将軍はconcurrency cancel-in-progressのエージェント間rerun干渉と誤診し交通整理・静止期間まで発令したが、真因はunit jobのtimeout-minutes: 5(テスト増加で実行5分15秒超に成長、GitHubのjob強制killはcancelled表示になる)。決め手=静止期間中も同時刻帯cancel。是正=timeout 5→12+契約テスト2件同期(7d7502c70/fd4612ebe)で7分7秒完走。教訓: 同一経過時間で繰り返しcancelされるrunは外部干渉を疑う前にworkflowのtimeout-minutesとjob実行時間比較を最初の1手にせよ。cancelled表示=人為的中断とは限らない。

## §LS-A16-enforcement全文 (2026-07-29移設)
Level5: deploy_task.sh経由のscripts/lib/inject_task_modifiers.py lsa16_production_parity_controlsで、DM-Signal本番DB/recalculate系taskへstop_for「本番パリティ未確認」+LS-A16説明+DB/API/FE 3レイヤー貫通・即fullrecalculate/差分確認・savepoint(begin_nested)確認ACを配備時に自動注入する(cmd_karo_hotfix_reflux_promotion_202607090438_hayate)。tests/unit/test_deploy_task_yaml_injection.batsでDM-Signal recalculate発火/非DM-Signal非発火を検証。既存: post-bash-combined.sh Guard5(admin/recalculate-sync実行検知→parity_check.sh実行を即時リマインドするLevel3層)、checklist-shin-v2-registration.md+checklist-alm-registration.md(Level2手順書)、PI-007+PI-025(begin_nested知識)、health_check.py+gate_recalculate_completeness.sh+parity_check.sh、pf-registration skill。残課題: fullrecalculate実行後parity未確認のままcommit/次操作へ進むruntime BLOCKはpending parity flag/DM-Signal PJ検知/FP設計が必要で別cmd判断
