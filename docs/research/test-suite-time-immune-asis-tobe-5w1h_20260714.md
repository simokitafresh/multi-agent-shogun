# テストスイート時間免疫系 設計書 v1.4 (AsIs/ToBe/5W1H)

- 起案: 将軍 2026-07-14 01:3x JST
- 殿指示: 01:23「全量pytestや全量bashが長時間すぎて非効率。道具磨きの要領で最適化と高速化。覚醒して長期の複利を」+ 01:27「起票前に設計書。重要なのは今後も肥大化、長時間化しない仕組み」+ 01:33「テストの統合と、陳腐化したテストやモックの禁止・排除、元のスクリプトの速度最適化」+ 01:41「**専用の全量実測はナンセンス。検査のための検査は時間の無駄**」+ 01:44「**車輪の再発明はやめよう。スクリプト高速化もテスト高速化も台帳もあるはず**」
- 殿指示追記: 01:52「新しく実装するときにテストを作成するルールは不要か？」→D7(テスト作成規律=入口)として回答・反映
- 状態: **v1.4.3** — 家老R8-R12+R13-R18+最終整合指摘(blt_020439: D4'/§5のモック類型数がD7と矛盾)を全反映。モック許可4類型(第4=side-effect境界の決定的failure injection、正常系real path/contract test併設条件)をD7(3)・D4'・§5リスク3の3箇所で統一定義。家老LGTM判定待ち
- 核心: **車輪は既に4つあった。問題は「車輪が回り続ける仕組み」がないこと。本設計の本体は新造ではなく、止まった車輪の再稼働と接続**

## §0 設計原則(禁忌を先に固定)

1. **検証の全量性は縮小しない。** 完了gate・CI境界での全量実行契約(FAIL0/SKIP0)は不変
2. **検査のための検査を作らない**(殿01:41): 専用の計測runは禁止。計測は通常業務の実行へ相乗りさせる
3. **車輪の再発明禁止**(殿01:44): 新設は§2.5の差分のみ。既存(gate_test_health.sh・BATS_CACHE・--timing・codd-refactor・GA-248 cap)に接続する
4. 速くする対象は4つだけ: (a)テスト1件コスト (b)反復重複 (c)並列度 (d)被テストコード自体の速度
5. テスト統合・淘汰は件数削減を目的にしない。contract/branch/mutation coverage同等の二値証明のみ許す(家老R7)
6. 計測なき改善禁止。データ源は§0-2に従い通常業務実行

## §1 AsIs(一次計測 2026-07-14 01:2x)

| 対象 | 規模 | 全量実行時間 | 計測源 |
|---|---|---|---|
| DM-Signal pytest | 1,810 tests(208 files) | **1,187.55秒(約20分)** | cmd_3879報告(通常業務実行) |
| multi-agent-shogun bats | 3,791 tests(266 files) | 通常業務実行から回収(P1接続後に自動蓄積) | grep -rc "^@test"実測 |

時間消費の構造: 忍者AC「全量実行FAIL0/SKIP0」×revision往復+local full→gate→push→CI fullの二重全量(家老R6)+完了gateのevidence検証が浅い(SKIP件数のみ、commit束縛なし=家老R1)

## §1.5 既存資産の棚卸し(現物確認済み — 車輪は4つ、うち1つは止まっている)

| 既存資産 | 現物(一次確認) | カバーする機能 | 状態 |
|---|---|---|---|
| **gate_test_health.sh+test_timing_ledger.tsv**(cmd_3103、家老R8) | 台帳自動生成(seconds/file/test_count/status)+30秒超一覧+重複テスト名検出+統合候補(5件以下)一覧。将軍現物確認01:49 | **台帳(D1相当)+重複・統合候補検出(D4の一部)は既実装** | **stale(2026-06-05)+fail行あり=稼働停止中。--timingが手動起動=意志依存が停止根因の仮説(P0で確定)** |
| **BATS_CACHE** | run_tests.sh L23-24/L41-61/L169-175: **PASS結果のper-file cache**(変更影響selectorではない=家老R9)。fingerprintは**unstaged-only変更とrun_tests.sh自身を除外、env/外部状態も未束縛** | 反復時の再実行スキップ(bats側) | 稼働中。ただしevidence契約とfingerprint範囲に穴(R9/R10) |
| **bats --timing常設** | run_tests.sh L98/L107 | per-test時間の取得 | 稼働中。台帳への接続なし |
| **codd-refactorスキル** | Pattern3(引数なし)=専用全量プロファイル起動、Phase5=全量before/after | 道具磨き全工程 | 稼働可能だが**Pattern3/Phase5が殿01:41(専用全量禁止)と衝突(家老R11)→契約更新が必要** |
| GA-248並列cap+回帰テスト | run_tests.sh L222-226/L241-247 host-wide admission | 並列安全上限 | 稼働中(2026-07-14根治) |
| スクリプト高速化の型 | cmd_3806/cmd_2111/GA-245/semantic_index実績 | 被テストコード道具磨きの型 | 型として確立済み |
| 台帳・cron・gate表示の型 | loop_ledger+weekly_metrics_trend | 集計・表示の型 | 稼働中(踏襲元) |
| pytest側 | cache/durations常設は未確認 | — | P0で確定 |

**v1.2→v1.4の構造的発見**: 車輪(gate_test_health.sh)は2026-06-05から止まっていた。**「道具を作る」だけでは複利にならない。通常業務のフローに自動で相乗りし、止まったら検出される接続までが免疫系**(deepdive Phase 9と同型: 作った自動化自体のバグ・停止を検出する層がもう一枚要る)。

## §2 なぜ肥大化・長時間化するか(因果)

1. テストは単調増加(統合・淘汰の還流路なし) — bats 3,791件が実測値
2. 1件あたりコスト無管理(重fixture・実プロセス・sleepがレビュー観点にない)
3. **計測・台帳(gate_test_health.sh)は存在したが、手動起動=意志依存で1ヶ月止まり、誰も気づかなかった** — 「計測がない」ではなく「計測が止まっても検出されない」が真因
4. 反復重複はbats側cache済みだが、pytest側は毎回全量+gateのevidence契約が浅い
5. 被テストコード自体の遅さがテスト時間を倍増(殿指摘。cmd_save 1.06→8.09s劣化の実例)
6. 陳腐化テスト・モックの滞留(殿指摘。偽PASSの温床+件数肥大)

## §2.5 真の差分(新設はこれだけ。全て既存車輪への接続・修理)

| 差分 | 内容 | 対応 |
|---|---|---|
| **D1' 台帳の再稼働と自動接続**(R8+R16反映) | 新台帳は作らない。**test_timing_ledger.tsvを正本**とし、(a)stale根因(手動起動)を解消=run_tests.shの通常実行から--timing結果を自動追記 (b)前回比悪化WARNをstartup gate/完了gateへ接続 (c)fail行の扱い(status別集計)を定義 (d)**台帳自体の鮮度監視**(staleでWARN=車輪停止の検出層) (e)**schema/lifecycle固定(R16)**: timestamp・run_id・revision・mode(all/unit/affected/file)・cache統計(run/cached)・collected/expected・status・atomic completeを必須列とし、**mode=all/unitの完走のみがsuite鮮度を更新**。affected/file実行やcache hitは未計測fileのtiming鮮度を偽更新しない(現行のseconds/file/test_count/statusだけでは前回比・stale・部分run判別が不能) | §2-3 |
| **D2' pytest側の同等化(契約化前提)** | durations常設(追加コスト≈0)。BATS_CACHE相当の移植は**fingerprint契約化が先**(R9): 依存・env・dirty worktree・runner版の束縛を定義してから。契約化できない要素が残るならcache適用範囲を限定 | §2-4 |
| **D3 バジェットratchet** | new/changed testのbudget超過とsuite wall回帰をWARN→BLOCKへratchet(家老R3)。例外は実測理由+期限+owner必須。超過はheavy分類(専用直列lane) | §2-2 |
| **D4' 統合淘汰の拡張+モック規律** | 重複test名・統合候補はgate_test_health.sh既実装 — **差分は(a)陳腐化判定(参照先消失・仕様変更済み)の静的スキャン (b)モック使用箇所catalog+実装との契約乖離検出 (c)統合実行時のcoverage同等二値証明**のみ。新規モック原則禁止 — 許可は**4類型**(外部サービス・破壊的操作・実時間依存+side-effect境界の決定的failure injection[正常系real path/contract test併設条件]。D7(3)と同一定義、PI-P01内)。実物が速ければモック不要=道具磨きが正順 | §2-1,5,6 |
| **D5' full evidence契約(二値固定)**(R10反映) | **完了gateの全量evidenceはBATS_CACHE=0の実実行を正本とする**(cache記録はpassed_at/fileのみで証跡力不足のため)。evidenceにcommit_hash+collection fingerprint(collected/expected exact)+exit+SKIP0+env必須(R1)。コードcommit後の変更で失効、report-only修正は再実行不要。**cache証跡manifest方式への移行はP4でD1'台帳実測(二重全量コスト)を見て判断** | §2-4 |
| **D6 codd-refactor契約更新**(R11反映) | Pattern3(引数なし専用全量profile)とPhase5(全量before/after)を「D1'台帳データ入力+明示target/spec」へ差替え。専用全量を起動しない契約へ更新(殿01:41整合)。P2の前提タスク | §0-2 |
| **D7 テスト作成規律(入口)**(殿01:52「新しく実装するときにテストを作成するルールは不要か？」への回答。R13-R18で精密化) | **新規実装のテスト作成義務は維持する**(回帰防御の免疫=品質の鎖の中核)。ただし「テスト追加=無条件に善」が§2-1(単調増加)の入口なので規律を契約化する。**前提(R13): D7自体の車輪探索 — 既存のtest作成/更新契約(cmd_save check_ac_test_scope・codex-karo modified-file regression plan・軍師fixture/全入力mode観点・git pre-commit関連test選択)をP0で棚卸しし、重複新設せず統合先を決める**。規律: (1)**既存contractの再利用を優先**(同一対象・同一分岐の重複作成禁止)。配置(既存file拡張 vs 新file)は同一fixture/責務・isolation・per-file wall・並列laneの二値基準で決定し、既存fileがbudget超or共有資源競合なら新fileを許す(R14: file集中による並列性低下を防ぐ) (2)新規テストはper-testバジェット内(D3接続。超過は設計見直しかheavy申告) (3)test doubleを定義した上でモック許可は**4類型**: 外部サービス・破壊的操作・実時間依存+**side-effect境界の決定的failure injection(異常系注入。正常系のreal path/contract test併設が条件)**(R15: cmd_3882を救ったmonkeypatch型を正当に残す) (4)**contract消滅時のみテスト削除。置換・refactorでは維持**(R17) (5)coverage差分での価値測定は**計測器の現物棚卸し(P0)で利用可能な二値手段を固定してから**入口契約に組み込む(R18: 計測器なしの運用は意志依存化するため禁止)。**適用表(R17)**: 新behavior=新/拡張test必須、bugfix=再現regression必須、behavior不変refactor=既存coverage維持、docs/data-only=実行test免除(根拠記載)。埋込み先=cmd AC雛形・report契約・軍師レビュー観点(SG) | §2-1,6の入口 |

## §3 ToBe構成(既存車輪×差分のマッピング)

- 計測・悪化検出: **gate_test_health.sh+test_timing_ledger.tsv(既存正本)** + D1'(自動接続+鮮度監視)
- 反復重複排除: **BATS_CACHE(既存)** + D2'(pytest側、契約化前提) + D5'(gateはcache=0全量のみ受理=滑り坂防御)
- 道具磨き: **codd-refactorスキル(既存)** + D6(契約更新) ← D1'台帳top-Nを入力に、テストと被テストスクリプト本体の両方
- 並列: **GA-248 cap(既存)**。cap変更はD1'実測+flaky 0複数回+共有資源catalog(P0棚卸し)が条件
- 肥大への直接免疫: **入口=D7(作成規律: 重複禁止・バジェット内・道連れ更新)、出口=D3(ratchet)+D4'(統合淘汰・モック規律)** — §2-1の単調増加を両端から塞ぐ
- **車輪停止の再発防止**: D1'-(d)台帳鮮度監視(今回の教訓の環境埋込み)

## §4 Phase分割と起票cmd列(LS086照合表)

| Phase | 内容 | 実行コスト | 依存 | 起票cmd |
|---|---|---|---|---|
| **P0 静的棚卸し(実行なし)** | 対象を明記(R12+R13+R18): **gate_test_health.sh・test_timing_ledger.tsv(stale根因特定)・codd_refactor_registry.md・test_select.sh/cache関連testの有無**+**既存test作成/更新契約4つ(cmd_save check_ac_test_scope・codex-karo modified-file regression plan・軍師fixture/全入力mode観点・git pre-commit関連test選択)のD7統合先判定(R13)**+**bats/pytestのbranch・contract・mutation coverage計測器の現物棚卸しと利用可能な二値手段の固定(R18)**+sleep・実プロセス・モック/test double使用箇所・重複/陳腐化候補・pytest側cache/durations現状・共有資源catalog。grep/AST/git履歴のみ、**テスト実行ゼロ** | 0分 | なし | **cmd_3894**(2026-07-14 02:1x委任) |
| **P1 D1'+D2'前半** | 台帳再稼働(自動追記+悪化WARN+鮮度監視)+pytest durations常設。以後通常業務が計測データ化 | 実装のみ | P0 | **cmd_3895**(infra側、02:4x委任。P0所見14列形式+lifecycle)。pytest側durations常設はDM-Signal別cmdとして後続 |
| **P2 D6→道具磨き** | **D6契約更新済み(cmd_3910)**: codd-refactorは最新cache_hit=0・mode=all/unit完走runの台帳top-Nからテスト+被テストスクリプト候補を出し、改善済み対象をregistryで除外。before/after=同一test_file/suite_rootのcommit_sha+run_id付き台帳比較、欠損はUNVERIFIED fail-closed、専用run禁止 | 実装のみ | P1蓄積 | **cmd_3910** |
| **P3 D3+D4'+D7** | **D3 ratchet骨格はcmd_3911で実装済み**: 14列台帳の同格non-cache完走runをcohort化し、5 run未満/legacy/stale/mixed revisionではWARN維持、5 run以降はfile p95とsuite rolling median+25%を絶対秒・相対率の双方超過時だけBLOCK。例外はowner・期限・実測reason必須。閾値は台帳実分布で確定する。残り=陳腐化スキャン+モック規律+統合第1巡(coverage同等証明)+**D7作成規律の契約化(雛形・report契約・軍師SG)。ただしD7の(1)重複禁止(3)モック類型(4)道連れ更新はバジェット不要のためP1で先行実装可** | 実装のみ | P1蓄積(D7一部はP1) | **cmd_3911(D3骨格)** |
| **P4 D5'+D2'後半** | full evidence契約のgate強化(cache=0正本)+pytest cache(fingerprint契約化後)+二重全量の統合判断(台帳実測に基づく) | 実装のみ | P1 | (未起票) |

## §5 リスクと非対称性

1. **全量性縮小への滑り坂**: cache/変更影響スキップは完了gateの代替にならない。gateはD5'(cache=0全量+full evidence)のみ受理
2. **並列とflakyの再結合**: GA-248契約内でのみ。cap変更はflaky 0複数回+CI GREEN連続が条件
3. **モックと本番等価性**: 新規モック許可は4類型のみ(外部サービス・破壊的操作・実時間依存+side-effect境界の決定的failure injection[正常系real path/contract test併設条件]。D7(3)/D4'と同一定義、PI-P01)。モックで速くするのは偽の速度
4. **バジェット形骸化**: ratchetはP1蓄積の実測分布確定後のみ発動
5. **意志依存化**: 手動--lf/-k禁止。cache fingerprintも契約化(R9: 依存・env・dirty worktree・runner版)してから信頼する
6. **統合・淘汰の検証力低下**: coverage同等の二値証明なき統合は禁止
7. **車輪の再発明+車輪の停止**(本設計の自己教訓): v1.2でT4/T1/T3、v1.3でD1/D4と**2巡連続で既存車輪を見落とした**。さらにgate_test_health.shは作られたのに1ヶ月止まっていた。対策: (a)P0のACに「scripts/gates/・logs/・skills/・過去cmd資産の類義語横断探索」を必須化 (b)D1'-(d)台帳鮮度監視で停止を検出 (c)設計レビューの観点に「見落とし車輪の探索」を常設(今回の家老R8がその実演)

## §6 レビューと次アクション

1. ~~初回レビュー~~(軍師LGTM条件+家老R1-R7→v1.2) ~~v1.3再レビュー~~(家老R8-R12→v1.4)
2. **v1.4の再々レビュー(家老+軍師)**
3. LGTM後にP0(静的棚卸し、実行ゼロ)起票 → P1で台帳が再稼働し通常業務が計測データを生み始める

## 因果リンク

- ← [[殿指示20260714_0123_全量テスト長時間]] 発端
- → [[throughput-first-asis-tobe-5w1h_20260708]] 全体スループット第一原則の個別戦線
- → [[ga248_ci_red_root_defense]] 並列cap契約
- → [[LS-A19]] 車輪原則(v1.2→v1.4の直接教訓×2巡)
- → [[deepdive_why_chain_20260321]] Phase 9(自動化自体の停止を検出する層)=D1'-(d)の理論的根拠
- → [[LS086]] 設計書クローズ時の起票照合(§4表)
- → [[codd-refactor]] 道具磨きの既存スキル(D6で契約更新)
