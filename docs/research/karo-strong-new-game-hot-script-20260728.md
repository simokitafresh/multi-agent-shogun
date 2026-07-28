# 家老 強くてニューゲーム復帰点 — hot-script第一弾 (2026-07-28 10:42 JST)

## 結論

復帰後は推測せず、`queue/tasks/{ninja}.yaml` → `queue/reports/` → `tmux capture-pane -S -30` の順で一次実態を再確認する。`queue/karo_snapshot.txt` は補助キャッシュであり、生成時刻が10分超なら判断根拠にしない。

## 現在地（10:42一次確認）

| lane | ninja | 正本status | 一次実態 | 次の出口 |
|---|---|---|---|---|
| checks_pre_session | 完了 | completed | GATE CLEAR、`cmd-complete`完了 | 追加作業なし |
| run_tests親環境隔離 | 完了（hayate） | completed | commit `bfa114227`。旧並列FAIL #3/#4/#6を解消し、GATE CLEAR、`cmd-complete`完了 | 追加作業なし |
| deploy fixture case51 | hayate | in_progress / report pending | full unit全2753件中case51のみFAIL、単独は現行63/63 PASS。共有queue/report副作用のfixture隔離漏れを特定。修正後pair 2/2・parallel 20/20 PASS | 対象/affected→commit→report→LGTM→ACCEPT→GATE→cmd-complete |
| memory_db_token_search | saizo | in_progress / report pending | tokenなし枝worker/DB接触ゼロ化、tokenあり枝親cache継承を採用。旧3件は解消。case51修正待ちのためAC3未達を保持 | hayate完了通知→最新HEAD full unit→report→LGTM→ACCEPT→GATE→cmd-complete |
| instruction_sync | kagemaru | assigned / report revision_requested | commit `d4b9fe5e4`の報告はafterが推定7.5秒だったため、軍師LGTM後も家老RC。実測計装を追加しaffected/unit待ち | 新commit+同条件after実測→再報告→再LGTM→ACCEPT→GATE→cmd-complete |
| 軍師D0自己消火 | kotaro | in_progress / report pending | commit `4338bb315`。`d0_applied:no`で真陽性が消える述語を修正。contract 4/4 PASS、unit共有lane待ち | unit→report→LGTM→ACCEPT→GATE→cmd-complete |
| credential target_path:list | tobisaru | in_progress / report pending | 修正前list例外1/candidate0、修正後4 fixture例外0・list候補2/2。対象63/63+49/49 PASS、affected/unit待ち | affected/unit→commit→report→LGTM→ACCEPT→GATE→cmd-complete |

第一弾の完了条件は12check全クローズ。その時点で `logs/defense_overhead.jsonl` を再集計し、設計書台帳を12/12へ更新して掲示板へ完了宣言する。

## 09:19以後に環境へ残した強化

1. `test_run_tests.bats` は親runnerの個別変数列挙を廃し、`RUN_TESTS_*` prefix全体をfixture境界で初期化した。修正前3/3 FAIL→修正後3/3 PASS、44/44、affected 44/44、unit 2690/2690。
2. full unit再実行で旧3件の解消後にcase51だけが顕在化した。局所PASSを完了根拠にせず、次の隠れFAILを即hotfixへ変換する連鎖を維持した。
3. `instruction_sync` は軍師LGTMでも、ACが要求するafter実測が推定値だったため家老RCとした。「レビュー出力」より「測定済み結果」を優先する。
4. 軍師startupのD0警告は、`d0_applied:no`の遡及挿入だけで消える自己消火を検出。`no`は未実施を抑止せず、`yes`または構造化remediationだけを解消条件にするcommit `4338bb315`へ進化した。
5. 配備中に `target_path:list` がcredential injectorでTypeErrorとなる別バグを発見し、同一ターンで飛猿へ配備。配備失敗1回目は疾風の予約path衝突で安全BLOCKし、テストpathを分離して再配備した。
6. 復帰時の判断順序を「三層記憶→task/report正本→capture-pane一次実態→依存順で行動」に固定した。

## 復帰後の実行順（順序保証）

1. `queue/inbox/karo.yaml` の未読を個別IDで処理する。
2. 6忍者のtask/report正本を読み、`capture-pane -S -30` で実態を再確認する。snapshot単独で判断しない。
3. hayate case51を最優先でレビュー・GATE・`cmd-complete`まで閉じる。
4. captureでsaizoに確認プロンプトがないことを確認後、case51解消を通知し、最新HEAD full unitを再実行させる。
5. saizo `memory_db_token_search` を閉じる。
6. kagemaruは新commitと実測afterを必須とし、旧commit `d4b9fe5e4`・旧LGTMを再利用しない。
7. kotaro/tobisaruを各々review→ACCEPT→GATE→`cmd-complete`で閉じる。
8. 第一弾12/12を全数再集計し、設計書台帳更新と掲示板完了宣言を行う。

依存鎖: `[[run_tests親環境隔離]] -> [[deploy_fixture_case51]] -> [[memory_db_token_search_full_unit]] -> [[hot_script第一弾_12_of_12]]`

## 復帰直後の二値確認

- [ ] `queue/inbox/karo.yaml` の未読を個別IDで処理した
- [ ] hayate/kagemaru/saizo/kotaro/tobisaruのtask/reportを読んだ
- [ ] `shogun:2.3/2.4/2.6/2.7/2.8` を `capture-pane -S -30` で確認した
- [ ] report completedなら形式検査・commit実体・軍師LGTMを突合した
- [ ] case51完了前にsaizo full unitを再実行させていない
- [ ] kagemaruのafterが推定ではなく同条件実測である
- [ ] 各hotfixのGATE CLEAR後、`cmd-complete` を実行した
- [ ] 12/12の台帳再集計と掲示板完了宣言を行った

origin: `[[殿指示_20260728_強くてニューゲーム]] -> [[full_unit隠れFAIL連鎖]] -> [[karo_clear_recovery_checkpoint]]`
