# cmd_4108 retro pane prompt 無限再送の根治

- 真因: `send-keys` 本文+Enter成功後の折返しpane全文照合失敗を未送信と誤分類し、claimを解放していた。
- 修正: 送信成功を不可逆境界とし、seen失敗は `delivered_unverified` で終端する。同一targetの未終端promptは最大1件に制限する。
- 境界fixture: 変更前契約は同一eventを2回送出。変更後は初回1回、2回目はdeduplicated（本文送出 2→1）。
- 反復検証: `bats tests/unit/test_retro_pane_prompt.bats` = 6/6 PASS、FAIL 0、SKIP 0。
- 既存台帳baseline: delivered 26 / failed_prompt_unseen 19 / deduplicated 8 / failed_busy 3。修正後fixtureの同一event再送回数は 1→0。
- reconciliation: 成功returnにより `ninja_monitor.sh` の既存正規経路が `mark-delivered` を記録し、pendingを `verbatim_awaiting_answer` へ移す。回答済みholdの終端は既存 `deploy_task.sh` が担う。

結論: seen誤分類によるclaim解放を、送信事実の永続化へ改めて無限再送を根治した。
