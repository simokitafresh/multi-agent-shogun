# cmd_4108 retro pane無制限再送の根治

- 実装日: 2026-07-21
- 真因: `retro_pane_prompt_seen`の折返し全文grep失敗を未配送と誤分類し、claim解放後に同一eventを再送していた。
- 結論: **seen誤分類を配送正本から外し、送信事実の永続化で無制限再送を根治した。**

## 変更

1. 本文をtmux bufferへloadし、`show-buffer`の送出payload SHAが`RETRO_PANE_PROMPT_SHA256`と一致した場合だけ`paste-buffer`する。payload送出成功→sleep 0.5秒→Enter rcの順序を固定し、capture-pane表示は配送判定に使わない。
2. Enter rc=0後、claim内の`sent` markerをatomic renameで公開する。seen失敗は`delivered_unverified`として終端しclaimを保持する。
3. payload SHA不一致はpane変更前に安全retryする。paste成功後のEnter失敗はclaimをquarantineし、次回は本文を再pasteせずEnterだけexactly-once回復する。
4. 同一targetのpending+awaiting outstandingを最大1件に抑止する。
5. `report_received` terminal、または`report_id → parent_cmd → gunshi_review_log`でreport review terminalを確認できたeventは、pending/awaitingから`verbatim_reconciled`へ正規終端する。

## 一次計測

| 指標 | 修正前 | 修正後 |
|---|---:|---:|
| 同一event `failed_prompt_unseen` | hayate 17 / kotaro 14 / saizo 12（計43） | 13:19:27以降 0 |
| 同一eventのfixture本文送出 | 2回 | 1回 |
| 現役terminal staleの正規reconciliation | 0件 | 3/3件 |
| 対象3paneの新規prompt断片 | 複数スタック | capture-pane 0/3pane |

13:27のmonitor旧cycleでは対象3eventが各1回`delivered_unverified`になったが、13:35にreview/report証跡で3/3件を`verbatim_reconciled`へ移動した。以後の`failed_prompt_unseen`増分は0である。未reviewのkagemaru 2件と、非report terminalのgunshi 1件は根拠なく消さず、pending/awaitingに保持した。

13:43の初回実E2Eはcapture-pane SHAを成立条件にしたため、本文貼付済みにもかかわらず`failed_input_sha=missing`となった（偽陰性1件）。成立条件を送出payload SHAへ修正し、三層記憶の既知契約どおりsleep 0.5秒をEnter前へ復元。13:49:05、影丸の既貼付claimを本文再paste 0回・Enter 1回で`recovered_enter`→sentへ回復した。影丸はpromptを受領し、13:50:06に家老へ分析回答`msg_20260721_135006_1988510_718719c6`を永続化した。

## テスト

- `tests/unit/test_retro_pane_prompt.bats`: 8/8 PASS
- `tests/unit/test_retro_verbatim_prompt_identity.bats`: 5/5 PASS
- `tests/unit/test_deploy_task_retro_hold.bats`: 3/3 PASS
- `tests/unit/test_retro_write.bats`: 12/12 PASS
- `tests/unit/test_inbox_write.bats`: 85/85 PASS
- FAIL 0 / SKIP 0

最終task-scope receipt: `run_tests_20260721T045245_2016961.json` = 8/8 PASS、FAIL 0、SKIP 0。全量unitの先行runは1147件・SKIP0だが、並行中のscope外deploy_task変更によりFAIL（receipt `run_tests_20260721T044116_1852605.json`）であり、最終checkpointで再実行する。

既存contract testを新契約へ更新した。新規testファイル・一時fixtureの永続化は0件。
