# 家老 強くてニューゲーム復帰点 — 2026-08-13 16:48 JST

> ★時系列ナビ(2026-08-14 01:58追記): 本書は16:48時点の歴史記録。以後、RB6検算方式は殿裁定22:40-22:44で逆算parity方式へ改訂され、2026-08-14 01:52殿裁定で**月次CLEAR確定**(33748/33748 exact)。本書の目標値・artifact参照は現状ではない。現行正本=`dm-production-code-rollback-plan_20260813.md` v1.6 §7.1-§7.2。残=metrics 47指標×204行の4 shard検算のみ。

- created_at: 2026-08-13 16:48 JST
- status: superseded (歴史参照のみ。現行正本はrollback計画書v1.6)
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- current_goal: RB6をrun 355後の新鮮な本番snapshotで再採点し、metrics修正の効果とFoF残差を数値確定してRB6 CLEAR/BLOCKを判定する
- origin: `[[殿指示_強くてニューゲーム_20260813_1648]] -> [[RB6_metrics修正deploy_full355]] -> [[RB6_post355_prices_oracle再採点]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

最優先は **RB6 post-355再採点** である。`/tmp/rb6_snapshot.json` と `/tmp/rb6_result.json` は修正deploy・full runより前のartifactなので、最終判定へ再利用してはならない。本番DBからprimitive snapshotをread-onlyで再取得し、production計算をimportしないprices oracleを再実行する。

目標値はmetricsの旧 `1338 mismatch → 0`。standardは旧 `4713/4713 exact`を維持すること。FoFは入力契約を混同せず、config+prices selection oracleの残差と、production派生displayを所与にしたreturn RCAを別々に報告する。RB6判定後だけRB8最終checkpointへ進む。`insight/action_required`処理とPD-137実装はその後である。

## 16:48時点の一次状態

| 対象 | 確定値 | 復帰後の扱い |
|---|---|---|
| DM-Signal HEAD | detached `7bd60e96b77a52502fa797453ed7a20a2d20ff41` | branch名を推測せず、push/deploy SHAは都度一次確認 |
| Render deploy | `dep-d9ulqu0ae00c73c9hkv0`、commit `7bd60e96`、Live 15:03:12 JST | metrics修正+oracle runnerを含むdeploy済み |
| full run | id `20260813060436D60609`、DB status id `355`、15:04:36→15:14:29、592.87秒、completed/error NULL | この完走後のDBだけを再採点対象とする |
| full population | PF 102、monthly_returns 16,976、portfolio_metrics 102、ticker monthly 4,795、precomputed_raw 1,650 | snapshot件数と照合する |
| signal integrity | 384,886、zero-signal 0、matched-weight warn 0 | full自体の完全性証拠 |
| old prices oracle | standard exact 4,713、FoF exact 11,170 / mismatch 970 / missing 21、metrics exact 90 / mismatch 1,338 | **pre-deploy比較値のみ**。最終値へ流用禁止 |
| runner | `backend/scripts/analysis/rb6_prices_oracle.py`、SHA256 `52439e59f57fdfa5a7eede35cdcd5ef2a9c79c4f1820780d7ed486662abb633d` | production計算import 0を再確認 |
| cmd_4296 | GATE CLEAR、completion checkpoint 9/9 | 再開しない |
| 家老inbox | `msg_20260813_164854_72622_26126843`をID指定で既読化、unread 0 | 指示正本は本checkpointへ転記済み |

full/deployの詳細正本は `docs/research/dm-fullrecalculate-cache-reuse-asis_20260813.md`。RB6 runnerはDM-Signal commit `7bd60e96`。

## post-355再採点の再現手順

### 1. 新鮮なprimitive snapshotを取得

`/db-check`のreadonly capability launcherを使い、以下5集合を別々に取得する。DB writeは0件でなければならない。

1. `portfolios`: `id,name,type,config`、102件想定。
2. `prices`: `symbol,date,open,close`。
3. `economic_indicators`: `symbol='DTB3'`の`date,value`。
4. `monthly_returns`: `portfolio_id,year_month,monthly_return,monthly_return_open`。比較対象key/valueにだけ使う。
5. `portfolio_metrics`: `years=0`の`portfolio_id,metrics_json`、102件想定。

保存先は旧artifactと分離し、`/tmp/rb6_snapshot_post355.json` とする。`precomputed_raw`、production cumulative/cache、production expand関数はoracle入力へ入れない。

### 2. runnerを実行

DM-Signal rootで次を実行する。

```bash
python3 backend/scripts/analysis/rb6_prices_oracle.py \
  /tmp/rb6_snapshot_post355.json \
  --output /tmp/rb6_result_post355.json
```

runner exit 0だけで結論せず、次の集合をJSONから数値で掲示板へ報告する。

- `population`
- `monthly.status`
- `monthly.status_by_type`
- `metrics.status`
- `fail_closed`

### 3. RB6二値判定

- metrics: 102 PF × close/open × 7指標 = 1,428比較、mismatch 0、missing 0。
- standard monthly: 4,713比較、mismatch 0、missing 0。
- fail-closed: production計算import 0、production expand/cache/cumulative/monthly value入力 0。
- FoF: config+prices selection oracleのmismatch/missingを確定し、契約差を理由に数を消さない。
- いずれか非0ならRB6 BLOCK。0を確認できた契約だけCLEARと書く。

## FoFの入力契約を混同しない

1. **selection oracle**: config+raw pricesから信号選択まで再生成する。旧値はFoF mismatch 970 / missing 21。RB6の上流独立性を採点する本線。
2. **holding/display所与のreturn RCA**: production派生の親displayを所与にし、pricesからreturnだけ独立計算する。coherent window補正後は12,161/12,161 exactだったが、selection独立性の証明ではない。
3. **equal-weight baseline**: 非均等weight意味論を失うため正式oracleに採用しない。

この3値は母集団・入力契約が違う。`970→0`や`645→0`を同じ改善系列として報告してはならない。

## metrics修正の確定履歴

- `fa04abf1`: 生monthly returnを保持し、初月を0へ潰さない。
- `5f61f805`: 初期wealth=1をMDDへ含める。
- `c0e43989`: metricsだけMTD/未来月を除外し、drawdownをanchor。
- `191ba83b`: confirmed monthly close/open/benchmark系列からMDDを直接算出し、open独自troughを採用。
- `c92c9360`: nullable research returnsをcumulative pct_changeで補完。
- adversarial review最終判定: APPROVE。対象回帰は34 PASS / FAIL 0 / SKIP 0。効果の最終証明はpost-355 oracle再採点で行う。

## 封印と順序

1. 復帰→inbox ID処理→本checkpoint hash照合。
2. post-355 DB snapshotをread-only取得。
3. runner実行、旧値と新値を同一schemaで比較。
4. metrics、standard、FoF、fail-closedの数値を掲示板へ投稿。
5. RB6 CLEAR/BLOCKを判定。BLOCKなら残差keyを保存し、最小原因集合を実験する。
6. RB6 CLEAR後だけRB8最終checkpointへ進む。
7. PD-137（momentum scalar永続化）はRB6収束前に実装しない。
8. insights/action_required処理はRB6/RB8の後。最優先laneを奪わせない。

## 今回の閉鎖事故から環境へ残す教訓

`cmd_4296`閉鎖では、artifactの`files_modified`漏れ、archive/live同一report_id、旧generation worker reservation、親cmdのgeneric directory tokenが順にgateを阻害した。再発防止原則は次の通り。

- formal review前にcommand refsと具体artifact coverageを機械比較する。
- archive後にlive reportを改訂するなら新report_idを採番する。
- generation-bound worker markerは履歴を残して現generationへ整合させる。
- generic destination directoryはconcrete modified fileでなくcontainer referenceとして分類する。

報告を通すために履歴や失敗を消してはならない。FAILは原因とgenerationを保存して次のgateへ還流する。

## clear-ready二値条件

- [x] 次の唯一の行動がpost-355新鮮snapshot取得と明記されている。
- [x] pre-deploy `/tmp` artifactの再利用禁止が明記されている。
- [x] deploy SHA、run id、status id、完走時刻、母集団が固定されている。
- [x] metrics `1338→0`、standard `0維持`、FoF契約分離の判定基準がある。
- [x] production write 0とfail-closed項目がある。
- [x] PD-137・insight処理・RB8との順序が固定されている。
- [x] originがObsidian因果リンクで記録されている。
- [x] 三層記憶L1/L2/L3の独立検索が成功（L1=`knowledge:50395546a6526b2e`/`knowledge:12567b71a437cfaa`、L2=`RB6再採点復帰点20260813`直撃、L3=origin 4-linkをcheckpoint/index/mapから再取得）。
- [x] `queue/compact_state/karo.yaml`が本書pointer/hashへ更新され、YAML parse PASS。

未完であることを隠すのではなく、復帰した次の自分が一手目を迷わず、古いartifactで誤判定せず、同じ数値契約から再開できることを「今より強い」と定義する。

## 2026-08-13 17:04増分 — post-355再採点実測、RB6 BLOCK

`db-check` readonly capability launcherでrun 355後の本番DBを新規抽出し、旧`/tmp` artifactを使わずrunnerを再実行した。DB write 0、credential cleanup PASS。

### artifact

- snapshot: `/tmp/rb6_snapshot_post355.json`
- snapshot SHA256: `87b31e886001bf1dbd859ebd66cb4385bb8dd62067ac829a39efc7afdffc9873`
- result: `/tmp/rb6_result_post355.json`
- result SHA256: `a86fc943c9aeedb1a079d58d2607cfc3801be8207dc6dd57393fa9c456412a6d`
- primitive counts: portfolios 102 / prices 100,196 / economic DTB3 15,156 / monthly_returns 16,976 / years=0 metrics 102

### 結果

| 契約 | 修正前 | post-355 | 判定 |
|---|---:|---:|---|
| standard monthly mismatch | 0 / 4,713 | 0 / 4,713 | CLEAR維持 |
| FoF selection monthly mismatch | 970 | 970 | BLOCK |
| FoF selection missing_expected | 21 | 21 | BLOCK |
| metrics mismatch | 1,338 / 1,428 | 980 / 1,428 | 358改善、なおBLOCK |
| metrics exact | 90 / 1,428 | 448 / 1,428 | 改善 |

metrics残980は排他的に次へ分解できる。

1. risk-free契約差: Sharpe/Sortinoのclose/openが全102 PFで不一致、`102×4=408`件。productionの月末1点DTB3 samplingと、RB6 oracleの営業日複利月次RFが異なる。
2. FoF selection月次差の伝播: monthly mismatchを持つ69 FoFでtotal/CAGR/annual mean/volatilityのclose/openが不一致、`69×8=552`件。
3. FoF MDD差: close 10 + open 10 = 20件。

`408+552+20=980`で残差を全件説明した。standard metricsは14値×24 PF=336比較のうち240 exact / 96 mismatchで、96はSharpe/Sortino `24×4`だけ。従って初月return・confirmed boundary・open MDD修正は数値上効いているが、RB6全体はCLEARではない。

### 復帰後の次の一手（17:04版）

1. 掲示板へ上記数値を報告し、RB6をBLOCKとして固定する。
2. RF 408件はproduction側を営業日複利月次RFへ合わせるか、RB6契約を変えるかの判断を勝手に混ぜず、現ACどおりならproduction修正対象とする。
3. FoFはselection oracleの970+21を残差keyで原因分類する。display所与12,161 exactをselection CLEARとして代用しない。
4. RB6 CLEAR前にRB8、PD-137、insight/action_requiredへ進まない。
