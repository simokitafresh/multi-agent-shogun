# 家老 強くてニューゲーム復帰点 — 2026-08-17 15:20 JST

- created_at: 2026-08-17 15:20 JST
- status: clear_ready
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- project: infra + dm-signal
- origin: `[[殿指示_強くてニューゲーム_20260817_1507]] -> [[restore_point_v2_2_baseline_20260817_1510]] -> [[cmd_4331_4332_4333_terminal]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

DM-Signalの本番復帰正本は `docs/research/dm-production-code-rollback-plan_20260813.md` §-1（2026-08-17 15:10更新）である。backend復帰点はcommit `46a1f213` / tree `412cb833...`、frontend復帰点はcommit `55b81b43` / tree `84770fb6...`。Render一次確認ではbackend deploy `dep-da17hubncjis73979lhg` がcommit `46a1f213`でlive、frontend deploy `dep-da19j9ad0e5s73b60h00` がcommit `55b81b43`でlive。origin/mainも `55b81b43e00f0bd89d345c6082efce0be71b00a1` である。

第0段の3cmdは実装・統合・本番反映済み。cmd_4333は本セッションでSG7 LGTM＋家老ACCEPTから正規GATE CLEARを再実行し、`cmd-complete` tailの `COMPLETE cmd_4333`、archive marker、半蔵task idle、家老inbox unread 0まで閉じた。cmd_4331/4332もarchive markerが存在する。再配備・再push・再deployは不要。

## 2026-08-17 15:20 JSTの一次状態

| 対象 | 確定値 |
|---|---|
| 家老inbox | unread 0 |
| cmd_4331 | report completed/PASS、成果はorigin/mainへ統合済み、`queue/gates/cmd_4331/archive.done`あり |
| cmd_4332 | report completed/PASS、ログイン文言を統合・FE live、`queue/gates/cmd_4332/archive.done`あり |
| cmd_4333 | report completed/PASS、commit `5b4e27eb...`を統合、GATE CLEAR、`cmd-complete COMPLETE`、archiveあり、hanzo idle |
| DM origin/main | `55b81b43e00f0bd89d345c6082efce0be71b00a1` |
| Render backend | live deploy `dep-da17hubncjis73979lhg`、commit `46a1f21343cdd8b2ed3b7f307a22f1d6dec03cb4` |
| Render frontend | live deploy `dep-da19j9ad0e5s73b60h00`、commit `55b81b43e00f0bd89d345c6082efce0be71b00a1` |
| 本番DB baseline | 復帰正本§-1.1の15:10 readonly値: current_database=`dm_signal_4xdu`、PF 98（FoF 74）、run400 completed、4表hash=`c3331388/e03c0a2c/dab5148e/cda1b38a` |
| 旧DB | cmd_4331完了により削除条件は満たしたが、削除は不可逆寄りの別作業。今回削除せず残置。復帰後も無断削除しない |
| infra local HEAD | `03881ef92fb327a06fd6dab59a3ed316d036edd6` |
| infra origin/main | `0d4229781a608775a2100a00f4e702c089840860`、localはleft/right=`18/47` |
| infra tracked dirty | 36件。外部writer・他agent差分を含む。reset/restore/一括stage/push禁止 |
| DM shared checkout | HEAD `5b4e27eb...`、origin/mainに対してleft/right=`100/64`、dirty 10件。公開正本ではない。reset/cleanup/push禁止 |
| 忍者terminal状態 | hayate done、kagemaru done、hanzo idle、saizo failed、kotaro done、tobisaru failed。assigned/in_progressなし |

## 今セッションで環境へ残した強化

1. 本番rollback正本を15:10 baselineへ更新済み。backend/frontend/DBを別々の復元対象として固定し、復帰時に片側だけ戻して完了扱いしない。
2. cmd_4333の歴史的`busy`ログを現在ロック保持と誤認せず、`fuser/lsof`で保持者0を確認後に正規GATEを実行した。rc=75/busyは終端結果ではない。
3. FoF 6段tie-breakの実装前落とし穴を一次コードでレビューし、掲示板 `blt_20260817_151253_7a988a` として将軍へ還流した。
4. FoFレビューの確定境界: FoFは標準PF executorと別経路、key⑤previous holdingは現在PipelineContextへ未接続、ComponentPrice既定730日は設定来CAGR/MaxDD/最初月を保証しない、relative epsilonはゼロ近傍のabsolute toleranceではない、既存tie expansionとTrendReversal枝極性を保存する必要がある。
5. `cmd-complete`は起動成功でなく非同期tailの `COMPLETE`、archive、task idle、inbox archiveまで確認した。

FoF因果: `[[FoF_tie_break_ToBe_v0_3]] -> [[previous_holding_input_gap]] -> [[full_history_asof_contract]] -> [[branch_view_semantics_preservation]]`

## /new後の最初の一手

1. 家老Recoveryを全手順完走し、startup gateのALERTを処理する。
2. `queue/compact_state/karo.yaml`のpointerとSHA-256を本書に照合する。
3. inboxを読み、未読をID単位で処理する。
4. DM本番判断では先に `docs/research/dm-production-code-rollback-plan_20260813.md` §-1を読む。旧08-16 hashや旧credentialを現在値として使わない。
5. DB照会前に `SELECT current_database()` が `dm_signal_4xdu` であることを確認する。`/tmp/dm-signal-db-check.env`の旧DB credential罠を踏まえ、接続先未確認の集計を採用しない。
6. FoF tie-break実装へ進む場合は掲示板 `blt_20260817_151253_7a988a` の5境界を設計入力にする。家老が勝手に実装・配備しない。
7. cmd_4331/4332/4333を再配備・再review・再deployしない。
8. 共有infra mainとDM shared checkoutはどちらも分岐・dirtyである。公開作業はremote基点の隔離worktreeで行い、既存差分を消さない。

## 禁則

- 旧checkpoint、rollback正本のcreated_at、過去baselineを遡及修正しない。
- 旧DBを本指示のついでに削除しない。
- infra shared mainまたはDM shared checkoutからpushしない。
- dirty差分をreset、restore、cleanup、一括stageしない。
- Render backend live commit `46a1f213`とorigin/main `55b81b43`の相違をdeploy遅延と誤診しない。backend treeは55b81b43でも46a1f213から不変である。
- cmd_4333の過去`busy`ログを現在のロック保持とみなさない。
- FoFのprevious holdingを「既にblockへ渡っている」と仮定しない。
- 相対`1e-9`をゼロ近傍の絶対誤差許容と呼ばない。

## clear-ready二値条件

- [x] 家老inbox unread 0。
- [x] assigned/in_progress忍者 0。
- [x] cmd_4333 GATE CLEAR・archive・task idle・`cmd-complete COMPLETE`。
- [x] cmd_4331/4332 archive marker確認。
- [x] DM origin/main、Render backend、Render frontendのSHA/statusを一次確認。
- [x] 本番DBの最新readonly baselineを復帰正本へ固定。
- [x] infra/DM両shared checkoutの分岐とdirtyを数値固定。
- [x] FoF設計pitfallをコード行番号付きで将軍へ還流。
- [x] 次の一手と禁止事項を固定。
- [x] 旧checkpointを上書きせず新規作成。

「今より強い」とは、/new後に本番復帰のbackend/frontend/DB三境界を混同せず、完了cmdを二重実行せず、dirty共有checkoutを壊さず、FoF tie-breakの未接続入力と履歴契約を知った状態から再開できることである。
