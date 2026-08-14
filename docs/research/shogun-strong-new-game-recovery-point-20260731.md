# 将軍 強くてニューゲーム復帰点 — 2026-07-31 23:35 JST

- status: active
- owner: shogun
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- origin: `[[殿指示_強くてニューゲーム_20260731]] -> [[cmd_4200]] -> [[strong_new_game_completion_contract]]`
- completion_contract: 宣言ではなく、復帰後に一次情報を再取得し、startup gate の BLOCK/CRITICAL=0を二値確認する。

## §1 復帰直後の結論

`cmd_4200`（hidden infrastructure gate/hook remediation）の本体実装は軍師 LGTM・GATE CLEAR済み。ただし `/cmd-complete` 後処理には未解消の外部効果冪等性とarchive security検証があり、cmd全体の完全終了を宣言してはならない。

復帰時は二次情報だけで判断せず、`tmux capture-pane -S -30`、task/report、掲示板、実テストの順で一次確認する。

## §2 2026-07-31 23:35時点の状態

| lane | 状態 | 一次証拠 / 数値 | 次の判定 |
|---|---|---|---|
| `cmd_4200` 本体 | GATE CLEAR | `msg_20260731_230952_3820289_52380d53` | 本体を再実装しない |
| manifest resume | recon CLEAR、hotfix AC4 FAIL | recon `cmd_karo_recon2_cmd_complete_manifest_resume_20260731`は23:25 CLEAR。一方hotfix `cmd_karo_hotfix_cmd_complete_review_manifest_resume_20260731`は実装test 416/416 PASS・SKIP0でも、旧`cmd_4200` terminal snapshot欠落によりwrapper Step 8未実走、AC4=no | archived 6 reportを軍師LGTM+家老ACCEPTで正規再承認し、新terminal snapshot生成後にwrapper Step 8を実走する |
| postprocess idempotency | 修正・再検証中 | 疾風pane実測: 関連39件 FAIL=0 / SKIP=0、敵対7類型 false_accept=0、receipt後crash再開でもntfy実送1回。task帰属runnerと旧glob残存0を最終確認中 | report→軍師review→GATE CLEARが必要 |
| archive security | 固定generation FAIL | `blt_20260731_233052_fc9da0`: report 5 PASS / 2 FAIL、bc:no=1。後発HEADでは7/7 PASSだが固定generationを置換しない | 家老が現在の修正と報告世代を正規に再検証する |
| Codex MEM citation runtime | 未解消 | Stop policy PASS、tests 61/61、SKIP=0、stale fail-close 0/1、実送missing citation未補正 0/10 | Codex-safe送信前adapterが必要 |
| semantic generated backlink | retry中 | `cmd_reflux_backlink_202607312324_hanzo`: SSOT index=1、生成map=0、固定generation FAIL。半蔵へ23:34:59再配備済み | index/map双方1、二回目差分0、generator競合lost-update防御を確認する |

## §3 復帰時の実行順序

1. `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'` で将軍を確認する。
2. `queue/inbox/shogun.yaml` の未読をID単位で処理する。
3. `queue/karo_snapshot.txt` は索引としてのみ読み、家老・軍師・担当忍者を `tmux capture-pane -S -30` で再確認する。
4. `cmd_4200` archived 6 reportの正規再承認、新terminal snapshot、wrapper Step 8実走の三点を確認する。実装test 416/416 PASSだけで閉じない。
5. archive securityの固定generation FAILが正規の新generationで解消されたか確認する。後発HEADのPASSだけで閉じない。
6. Codex MEM citation adapterの実送経路で、stale fail-close=1/1かつmissing citation補正=10/10を確認する。
7. `cmd_reflux_backlink_202607312324_hanzo` のretryでSSOT indexと生成mapのexact targetが双方1になり、二回目生成差分0となったか確認する。
8. `bash scripts/gates/gate_shogun_startup.sh` を再実行し、BLOCK/CRITICAL=0を確認する。0でなければ、既存laneへ接続して解消する。

## §4 二値完遂条件

- [ ] inbox unread = 0
- [ ] action_required unresolved = 0（confirmed/closedだけでなくactioned_byまたは正規lane接続を確認）
- [ ] postprocess crash/resume duplicate external effect = 0/7敵対類型
- [ ] postprocess関連test FAIL=0、SKIP=0
- [ ] `cmd_4200` archived 6 report再承認後の新terminal snapshotでwrapper Step 8完走
- [ ] archive securityの現行正規generation binary_checks no=0
- [ ] Codex MEM citation stale fail-close=1/1
- [ ] Codex MEM citation missing補正=10/10
- [ ] semantic backlink exact target: SSOT index=1、generated map=1、二回目差分=0
- [ ] startup gate BLOCK=0、CRITICAL=0

いずれか1つでも未達なら「復帰可能」ではあっても「clear-ready完遂」とは宣言しない。

## §5 失敗から増えた防御

- report archive後のsymlinkでmanifest identityが変わるため、CLEAR時点の承認集合とresume時の集合を混同しない。
- 外部通知は「呼出した」ではなく「送達receiptを永続化した」を完了境界にする。通知成功とcheckpoint間の停止を敵対fixtureに含める。
- 固定generationのFAILを後発HEAD PASSで上書きしない。検証対象の世代を証拠へ含める。
- Codexでは禁止されたStop hookを実運用の防御と数えない。実送経路で二値計測する。

## §6 clear前準備の扱い

2026-07-31 23:29の `clear_prep_check.sh` は、殿から明示的な `/clear` 指示がないためG0 WARNで停止した。会話archiveは生成済みだが、ntfyを含むclear実行手順は進めていない。本書は「clearを実行する許可」ではなく、「clearされても状態を失わない復帰正本」である。

関連archive: `queue/archive/lord_conversation/lord_conversation_20260731T232906+0900.jsonl`
