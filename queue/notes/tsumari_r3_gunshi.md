# tsumari R3 軍師節 — review/precheck 側の視点
- 領域: review_bundle / gate_gunshi_report_precheck / review_approval / gunshi_log_append / inbox_mark_read
- 抽出窓: 2026-09-03T04:37〜12:14
- 抽出方法: 本セッションのreview処理中に遭遇したBLOCK/偽陽性/構造問題を時系列で記録

## 事例表

| ID | 時刻 | 事象 | 主分類 | 副分類 | 真因 | 根治済/未根治 | 次の一手 |
|---|---|---|---|---|---|---|---|
| T3-G-01 | 06:55 | review_log yaml.dump上書き(3回)。CS観点WARN遡及修正+gate_result更新でyaml.dump使用→HEADエントリ37+32件消失。家老が3回合流commit(5d6116d6b/1c406b1cf/53408f376) | 構造バグ | yaml.dump禁止規則違反 | yaml.dumpがflock外で全件上書きし他プロセスの追記を消失。CLAUDE.md禁止規則を軍師自身が違反 | 未根治(意志依存) | gunshi_log_append/yaml_field_setのみ使用をgate化(軍師paneのpre-bash hookでyaml.dump+gunshi_review_log検出→BLOCK) |
| T3-G-02 | 10:06 | SG-PRE35偽陽性(cmd_4469)。既存test(test_daemon_watchdog.bats、in-file test_necessity宣言あり)を新規test契約のvalidate_entriesに混入→ERROR | 偽陽性 | precheck | gate_gunshi_report_precheck.shのSG-PRE35がshared HEADに既存のtestを新規test扱い | 根治済(9d6050e04) | — |
| T3-G-03 | 10:08 | operational_simulation.actualに「ERRORS=1」文字列を含めたらLG085 BLOCK。実際のprecheck ERRORS=0なのに、review entryの自然言語記述がregex `/ERRORS\s*=\s*[1-9]/` に一致 | 偽陽性 | gunshi_log_append | LG085のregexがoperational_simulation.actualの自然言語を誤検出 | 未根治 | regex対象をprecheck実行結果のみに限定するか、actual欄のERRORS=N記述を禁止ルール化 |
| T3-G-04 | 10:06 | singleflight terminal cache。review_bundle失敗結果がsingle_review_terminal.jsonにキャッシュされ、precheck修正後も再実行不能 | 過剰BLOCK | review_bundle | singleflightが同一cmd_id+fpのterminal failureを永続記録し、前提(precheck)変更を検知しない | 未根治 | terminal.jsonにprecheck hashを含め、precheck変更時に自動invalidate |
| T3-G-05 | 07:12〜 | mark_read timestamp BLOCK(重複メッセージ)。既にLGTM済みだが後着の重複report_reviewでreviewed_at < msg_tsとなりBLOCK。FAILエントリ追加で迂回(計15回以上) | 過剰BLOCK | inbox_mark_read | reviewed_atが最初のメッセージ時刻で固定され、同一fpの後着メッセージを既読化できない | 未根治 | mark_readが同一fpでLGTM approval存在を確認したらtimestamp無関係に許可する設計変更 |
| T3-G-06 | 11:47 | review_approval commit_hash必須BLOCK(tobisaru reflux ledger-resolve)。新ledger resolve-only契約ではcommit不要だがapprovalがcommit_hash必須 | 構造バグ | review_approval | reflux resolve-only taskはcommitを持たないがapproval検証がcommit_hash存在を前提 | 根治済(家老修正: identity=ledger-resolve例外) | — |
| T3-G-07 | 12:12 | report_commit_main_ancestry BLOCK(tobisaru reflux ledger-resolve)。commit不在→ancestry check失敗 | 構造バグ | cmd_complete_gate | ledger resolve-onlyはcommitなし→ancestry checkが成立しない | 未根治 | cmd_complete_gateにledger resolve-only例外(ancestry check skip) |
| T3-G-08 | 07:42 | AC3文言否定形FAIL(recon2 saizo/hayate/kagemaru/hanzo 4件)。「gate/hook未解消条件が存在しない」check→no。check文言が否定形のため「条件不在=正常」をnoと報告しbc:no検出→BLOCK予測 | 偽陽性 | binary_checks | check文言の否定形表現がresult=noを「失敗」と一義解釈させ、実態(正常)と乖離 | 未根治 | AC3 check文言を肯定形に統一(「全gate/hook条件が解消済みである」→yes/no)。deploy_task側のtemplate修正 |
| T3-G-09 | 06:58 | review_bundle内部precheckとbash直接precheckの結果不一致(cmd_4469)。bash直接=ERRORS=0、review_bundle内部=ERRORS=1 | 構造バグ | review_bundle | review_bundleが古いworktree状態でprecheckを実行(家老のSG-PRE35修正がまだreflectされていなかった可能性) | 根治済(lock clear+再実行で通過) | — |
| T3-G-10 | 07:05 | review_log ARCHIVE時に乖離作業樹ベースで分割。yaml.dump後のARCHIVEが汚染を伝搬 | 構造バグ | gunshi_log_append | ARCHIVE対象ファイルがyaml.dumpで汚染された作業樹を正本として分割 | T3-G-01と同根因 | T3-G-01の根治で同時解消 |

## 主分類別集計

| 主分類 | 件数 | 根治済 | 未根治 |
|---|---|---|---|
| 偽陽性 | 3 | 1 | 2 |
| 過剰BLOCK | 2 | 0 | 2 |
| 構造バグ | 5 | 2 | 3 |
| **合計** | **10** | **3** | **7** |

## 所見
- 未根治7件中、T3-G-01(yaml.dump)は意志依存で再発リスク最高。gate化が急務
- T3-G-05(mark_read重複BLOCK)は今セッションで15回以上FAILエントリ迂回。最大のトークン浪費源
- T3-G-07(ancestry check)はledger resolve-only導入の直接帰結。cmd_complete_gate例外追加で根治可能
