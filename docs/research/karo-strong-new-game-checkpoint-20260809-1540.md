# 家老 強くてニューゲーム復帰点 — 2026-08-09 15:40 JST

- status: active
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- current_goal: 実際の本番環境改善を、高速回転を損なわず完遂する
- updated_at: 2026-08-09 16:05 JST
- origin: `[[殿指示_強くてニューゲーム_20260809_1540]] -> [[忍者枠ボトルネック]] -> [[terminal_idle即時再利用]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

設計書の粗探しは目的ではない。DM-Signal本番障害を直す実装を高速に前進させることが目的である。

家老が一人の忍者へ固執した真因は、`done/PASS + report未archive` をruntime状態に関係なく配備不能とした共通guardだった。commit `04c67b170` で単一原理へ是正済み:

- terminal (`done/PASS`) かつ runtime idle なら即再利用する。
- 旧報告はcmd固有ファイル名と `task_contract_snapshot` で保存し、再配備で変更しない。
- runtime busyは従来どおりfail-closeする。
- 忍者名・cmd番号による例外は作らない。

軍師レビューは `APPROVE / HIGH`。実運用でも疾風をcmd_4251、半蔵をcmd_4249_recon4へ手動status変更なしで再利用し、両ペインの着手を確認済み。

## 現在の実行レーン

| 忍者 | task | 状態 | 復帰後の扱い |
|---|---|---|---|
| 疾風 | `cmd_4251_full` | 実装中 | escalation契約を実装。検査対象は `type=escalation` のみ。他typeのBLOCK/FAIL文言は対象外。補足到達・適用をペイン確認済み |
| 影丸 | `cmd_4250_full` | RC後の実装継続中 | 初回報告はAC3のみPASS、AC1/2/4とcommit未完で正直FAIL。formal RC後、同一cmdを継続。家老が検証を奪わない |
| 半蔵 | `cmd_4249_recon4_normal` | 完了・軍師LGTM | FoF=78、nested親=53、直接FoF子参照辺=189、最大深度=4、判断日=332、歴史キー=8,951、dual replay母集団=17,902。format/verdict PASS。将軍へ掲示済み `blt_20260809_154815_9054dc` |
| 才蔵 | idle | idle | cmd_4250別忍者再配備はRC済みpeer report誤BLOCKでrollback。現taskなし |
| 小太郎 | `cmd_karo_hotfix_rc_peer_report_redeploy_20260809_normal` | 構造hotfix実装中 | 殿裁定14:05へ全task typeを統一。事前LGTM BLOCK、RC peer誤BLOCK、旧契約test、AGENTS/context/軍師手順の残骸を一括是正。改訂版は軍師APPROVE/HIGH、着手をpane確認済み |
| 飛猿 | `cmd_4249_recon5_normal` | done/idle | 報告LGTM。飛猿だけを追わず、全idle枠から選ぶ |

陣形は必ず `queue/karo_snapshot.txt` と対象paneの一次状態で更新確認する。この表は2026-08-09 15:40時点の復帰起点であり、実態より優先しない。

## 今セッションで環境へ埋め込んだもの

1. `d71b46fdc448c47eebf1a6cc0d1704d5ecb2f636`: readonly偵察を発見数ではなく「指定手法完遂+一次証拠」で判定するoutcome-neutral契約。
2. `137579d736167a88fc8f6c76fa661f7245861724`: typed `commit_contract` をreportへ構造のまま射影する。
3. `04c67b170`: terminal+idle workerの即時再利用。旧報告hash不変をcontract testで証明。
4. 殿裁定14:05の正本: 全task typeで「忍者配備」と「軍師draft review」を並列実行し、APPROVEを配備前提にしない。REQUEST_CHANGESだけを既存task_supplementで稼働中忍者へ還流する。

## 未解決の構造穴

1. cmd_4249のsplit taskでは、assigned AC ancestry不一致により `review_bundle` がBLOCKする経路が残る。偵察結果そのものと閉鎖機構を混同せず、結果を失わないこと。
2. GPT忍者が自主的なloadavg待機を挟むと、軽量な完了通知まで遅れる事例があった。個体監視へ戻らず、通知経路の契約として扱う。
3. cmd_4251の将軍cmd原文は検出条件のANDが曖昧と軍師が指摘。疾風へ `type=escalation` 限定の確定補足を送信済み。実装・テストがこの限定を守るか確認する。
4. 撤回済みの事前LGTM必須契約が4層に残存: `deploy_task.sh`、旧契約test 2系統、`AGENTS.md`+`context/karo-operations.md`、軍師手順正本+生成物。小太郎hotfixが全層を同一原理で是正中。完了前に「根治済み」と扱わない。
5. formal RC済みFAIL peer reportを完了済みpeerと誤認し、別idle忍者への同一cmd再配備をBLOCKする。小太郎hotfixの同一scopeで是正中。

## /new後の再開順

1. 家老Recoveryを完遂し、inbox未読をID単位で処理する。
2. `queue/karo_snapshot.txt` とactive 3忍者（疾風・影丸・小太郎）のpaneを一次確認する。二次情報だけでreset・再配備しない。
3. 完了報告が来たレーンから即レビューする。別レーンを待つbarrierを作らない。
4. 新cmdはterminal+idleの全忍者を候補にし、特定忍者へ固執しない。`deploy_task.sh` の `TERMINAL_IDLE_REUSE` を正規経路として使う。
5. cmd_4249観点四が揃ったら、5観点の実装上クリティカルな差だけを統合する。文章の粗探しへ逸れない。
6. cmd_4250/cmd_4251は報告到着順にレビュー・必要最小限の検証・閉鎖を進める。
7. 小太郎hotfix完了時は、事前LGTM BLOCKが全task typeで0件、draft review通知が存続、RC peer許可と拒否4系統、旧文書残存0件を確認してから軍師事後レビューへ送る。

## clear-ready二値条件

- [x] 現在のactive task 3本、担当、次行動を外部化
- [x] terminal-idle再利用の原理・commit・軍師判定を外部化
- [x] 未解決穴を「解消済み」と偽らず保存
- [x] 復帰時に必読されるcompact stateのpointerを本書へ更新
- [x] 復帰後の最初の行動を一次確認から始める形で固定
- [x] 撤回済み契約の4層残存と小太郎hotfixの再開条件を保存
- [x] 三層記憶へ貫通 `knowledge:31fb3ed01f1d12e0`。`gate_three_layer_health.sh` は未貫通0・stale pending 0・failed 0・STATUS PASS

未完了taskがあることは状態保存の失敗ではない。/new後は本書を起点に、現物の新しい状態へ即追従する。
