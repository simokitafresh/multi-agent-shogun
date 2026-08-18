# 家老 強くてニューゲーム復帰点 — 2026-08-17 00:05 JST

- created_at: 2026-08-17 00:05 JST
- status: stable
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- project: dm-signal
- origin: `[[殿指示_強くてニューゲーム_20260817_0000]] -> [[DM本番PITR_20260816]] -> [[run397中断_run398自己復元]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

本番復旧は完了している。次の家老は新規実装・配備・旧FAIL報告の完了処理を始めず、まず本書と最新inbox／掲示板を読む。殿の次指示がなければ待機する。

本番の正は共有DM作業木HEADではない。**Render Liveと`origin/main=131e5dbbac2830a75fecc06c61b305ba09d4edd3`**を正とする。共有DM作業木HEADは別系統で大幅に分岐しているため、reset・merge・push・「ローカルHEAD=本番」の推定を禁止する。

## 2026-08-17 00:03 JSTの一次状態

`db-check`の正規readonly capability launcherで新本番DBを実測した。DB write 0、資格情報file cleanup PASS。

| 対象 | 確定値 |
|---|---|
| Render code | `131e5dbbac2830a75fecc06c61b305ba09d4edd3` Live |
| runtime baseline | backend treeは既知正常点`3e28b6172889df3d544cc04ae31567252073ac7b`と差分0 |
| 新本番DB | `dpg-da0qttc9v7es73a0cig0-a` / database identity `dm_signal_4xdu` |
| PITR時刻 | 2026-08-14 14:35 JST |
| 旧DB | `dpg-d542chchg0os73979vg0-a`。切戻し用に残置。勝手に停止・変更しない |
| 最新run | id=398、full、completed、2026-08-16 23:46:52→23:53:42 JST、error NULL |
| PF母集団 | total 102 / standard 24 / FoF 78 |
| signals | total 343,626 / FoF 244,196 / FoF 78/78 |
| legacy残存 | FoF date<2011-04-01 = 0 / standard 2026-08-01,02 = 0 |
| monthly_returns | 16,486 |
| fof_component_weights | 26,613 |
| portfolio_metrics | 204 |
| max date | prices 2026-08-14 / signals 2026-08-14 |

## run396→397→398の復元証拠

run397はprocess restartでinterruptedとなり、一時的にmetrics 0だった。直後のrun398がcompletedし、run396と4業務hashが完全一致した。単なる「最新run completed」ではなく、途中中断後も次runで同一業務状態へ戻ったことを復帰契約とする。

| table | run396 | run397 | run398 | 終端判定 |
|---|---:|---:|---:|---|
| monthly | 16,486 / `73e42944e349c1b9e9d2de67d4ef8f8d` | 同一 | 同一 | exact |
| signals | 343,626 / `acb124d8e02e87bd8c15e924026679d9` | 同一 | 同一 | exact |
| weights | 26,613 / `b757c9110f3f2ae9fc6f76d10817ec04` | 同一 | 同一 | exact |
| metrics | 204 / `7802372c0e32508c368948ff9468464b` | 0 / NULL | 204 / 同一hash | recovered exact |

証跡はDM共有作業木の`outputs/analysis/baseline_hash_run396_20260816.txt`、`baseline_hash_run397_20260816.txt`、`baseline_hash_run398_20260816.txt`。run395 artifactは旧カラム名`weight`参照で失敗しており、hash正本へ使わない。

## 復旧で確定した経緯

1. 無駄なDB writer新設は殿直命で中止。半蔵の対象2ファイル差分0、commit 0、push 0、本番実行0。
2. 将軍が単独でcode rollback commit `131e5dbb`をpushしRender Live化。
3. Render PITRで新DBを作成し、backend・cron・local backend `.env`の接続先を新DBへ切替。旧local接続は`backend/.env.bak_20260816_olddb`へ退避。
4. 窓外旧行を既存capabilityで処理し、FoF旧signals 285,612、monthly 12,239、weights 29,540、standard weekend 48をtransaction commit。
5. run395後にrun396、interrupted run397、recovery run398まで進み、終端hashを上表で確定。
6. 復帰点設計書はgist `0c98ab36`の2026-08-16 23:30版へ更新済み。

## ローカル作業木の罠

- multi-agent-shogun: local HEAD `c60f6a2ba39c`、origin/main `43ddfb1b8cb8`、ahead 27 / behind 1。
- DM-Signal共有作業木: local HEAD `7d3811b74c69`、origin/main `131e5dbbac28`、ahead 51 / behind 88。
- DM共有作業木には既存dirty/untrackedがある（`tasks/lessons.md`、各worktree、旧DB `.env` backup、run395-398 hash artifacts等）。他者の作業として保持し、勝手にcleanup・commit・resetしない。
- 小太郎の隔離rollback worktreeはcommit 0で停止。証跡JSONが残っていても本番正本ではない。

## エージェント状態と旧報告の扱い

2026-08-16 23:58 snapshotでは全pane runtime idle、家老inbox unread 0。

- hayate: failed（旧parity guard baseline task）
- kagemaru: done（infra reflux backlink。commit `dbcdd159`）
- hanzo: failed（中止済みwriter。差分0）
- saizo: failed（旧run437 residual）
- kotaro: failed（対象insight消失で安全停止、変更0）
- tobisaru: failed（旧parity input guard）

これらのfailedを現在の本番復旧BLOCKと解釈しない。殿の次指示なしにレビュー・完了処理・再配備を行わない。ninja_monitorのUN-GATED通知も同様に既読化のみとする。

## /new後の最初の一手

1. 家老Recovery手順を省略せず実行する。
2. `queue/compact_state/karo.yaml`のpointer/hashと本書SHA256を照合する。
3. `queue/inbox/karo.yaml`の未読をID単位で処理し、最新の殿／将軍指示が本書を上書きしていないか確認する。
4. 本番状態が必要なら`db-check` readonly launcherでlatest run・4業務count/hashを再測定する。run398値を無条件に未来へ流用しない。
5. 新指示がなければidle待機。自動reflux・旧FAIL・insight在庫を理由に作業を再開しない。

## 三層記憶の復帰証跡

- Layer 1（記憶DB）: `knowledge:c31669c51691d285`
- Layer 2（セマンティック）: `strong_new_game_completion_contract`。独立検索語`run397中断_run398自己復元`で直接到達。
- Layer 3（因果索引）: 2026-08-17 00:08 JST再構築後、`殿指示_強くてニューゲーム_20260817_0000` 3件、`DM本番PITR_20260816` 3件、`run397中断_run398自己復元` 3件、`strong_new_game_completion_contract` 9件。
- 復帰時は本文だけでなく、この3層のいずれからでも本checkpointへ到達できる。

## 禁則

- DB削除専用writerや復旧用コードを新設しない。
- 共有作業木の分岐を解消しようとしてreset／broad restore／force pushしない。
- 旧DBを勝手に停止・変更しない。
- run397のmetrics 0を終端値と誤認しない。終端はrun398 exact recovery。
- run395以前の件数・hashを最新値として報告しない。
- 「full 1回」の過去指示を、既にrun398まで進んだ現実を隠すために歴史修正しない。

## clear-ready二値条件

- [x] 本番code SHA、baseline SHA、PITR DB ID、PITR時刻が固定されている。
- [x] run398のstatus／時刻／errorと全テーブル件数を本番DBで再測定した。
- [x] run396→run397中断→run398 exact recoveryのhash連鎖がある。
- [x] 旧行残存0、FoF 78/78、metrics 204を測定した。
- [x] 共有作業木と本番正本の分岐を明記した。
- [x] 次の一手と「何もしない条件」が明記されている。
- [x] 古い復帰正本を上書きせず、新しいcreated_atで歴史を保持した。
- [x] originがObsidian因果リンクで接続されている。
- [x] 記憶DB・セマンティック・因果索引の三層から復帰正本へ到達できる。

「今より強い」とは、復帰後に古いRB6・run395・共有HEADへ戻らず、run397の中断まで含む終端事実から一手目を迷わず選べる状態である。
