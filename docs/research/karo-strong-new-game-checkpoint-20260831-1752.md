# 家老 強くてニューゲーム復帰点 — 2026-08-31 17:52 JST

## 0. 正本宣言

- role: `karo`
- status: `active_work_owned_checkpointed`
- created_at: `2026-08-31T17:52:00+09:00`
- source: 殿指示 2026-08-31 17:46「いまクリアされても今より強くてニューゲームできるようにせよ」
- predecessor: `docs/research/karo-strong-new-game-checkpoint-20260831-1322.md`（歴史記録のため変更禁止）
- origin: `[[殿指示_強くてニューゲーム_20260831_1746]] -> [[review世代連携根治]] -> [[external_package_runner一般化]] -> [[LP_SVGキャッシュ不一致]] -> [[karo_checkpoint_20260831_1752]]`
- 復帰後は保存値を未来の事実として使わず、inbox・task・pane・Git・Render・本番curlを一次再測定する。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全手順完走する。
2. 本ファイルのSHA-256をcommit内blobと照合する。
3. `queue/inbox/karo.yaml` の `read:false` をID単位で処理する。
4. `queue/karo_snapshot.txt` と全paneを突合する。snapshotだけで判断しない。
5. 最優先は `cmd_4438`。影丸の実装→receipt fixture→軍師review→家老ACCEPT→GATE CLEARまで閉じる。
6. `cmd_4438` CLEAR後、`cmd_4434` を再配備しexact Ninja receipt取得→再review/GATE。CLEAR直後に `cmd_4437`、次に `cmd_4436` をLP直列で配備する。
7. 半蔵のreview世代連携根治をcommit/report/review/GATEし、read:true/no-terminalがterminalまで高優先再提示されることを実運用で確認する。
8. hayate reflux、saizo `cmd_4435`、tobisaru lock residue、kotaro refluxをcurrent-generation review→ACCEPT→GATE→archiveで終端する。
9. LP SVG欠落はRender origin・custom domain・cache-bustの三点を再測定し、custom-domain旧本文をpurge/恒久修正する。

## 2. 17:50時点の一次状態

- Karo inbox unread: `0`（17:49 snapshotの `UNREAD:1` は生成時差。ファイル再計測を正とする）
- Gunshi inbox unread: `0`
- MAS HEAD: `2b39552ec5766cbf0534425ebc7e62386eef33a1`
- MAS origin/main: `cfb6a673de025cbbcc59df70870b7b8b5fdc369b`
- MAS relation HEAD...origin/main: `9 0`、dirty paths: `29`。他者変更を含むため広域reset/stash禁止。
- DM origin/main: `1589085a7d91287a8ecb02eaffa992753edd3716`
- Backend live: `cab3d5b80e97b46eecceda40b45a62af91a49168`、deploy `dep-daai3nm7bikc73bo7s3g`、status live。
- LP live: `1589085a7d91287a8ecb02eaffa992753edd3716`、clear-cache deploy `dep-daajtqdg1s2s73ddfip0`、status live。

## 3. 稼働中・未終端task

1. `cmd_4438_full` — 影丸、acknowledged/busy
   - 目的: `run_tests.sh` のexternal scopeを `frontend/` 固定から任意package rootへ一般化し、typecheck/build/testのexact Ninja receiptを出す。
   - worktree: `/home/simokitafresh/shogun-task-worktrees/kagemaru_096f7013fc45809c`
   - AC: LP型fixture receipt 1件、既存frontend不変、FAIL0/SKIP0、cmd_4434同型の形式検証PASS。
2. `cmd_karo_hotfix_review_generation_coordination_202608311641_normal` — 半蔵、in_progress/busy
   - current-generation単一選択、旧SG7不採用、read:true/no-terminal再提示、LP/critical優先。
   - 追加契約: consumerが3回連続で既読化してもterminalまで再提示を継続し、固定回数で消失させない。
   - 最終fixtureをplanned testへ移設して全量再検証中。
3. `cmd_4434` — RC中断（実装commit `1589085a...` はDM origin/live済み）
   - code/typecheck/build/diff/EN・JA文言はPASS。GATE BLOCK理由は `ninja_test_receipt_missing` のみ。
   - A=package.json rc2、B=LP root selection0、C=frontend入力契約 selection0。`cmd_4438` CLEAR後に再配備してreceipt取得。
4. review終端在庫
   - hayate `cmd_reflux_insight_202608311234_hayate`: current request既読、SG7は旧generation。
   - saizo `cmd_4435`: current bundle/terminal欠落。source `855f77e0...` は未統合。
   - tobisaru `cmd_karo_hotfix_report_unit_lock_residue_20260831135838`: current bundle/terminal欠落。
   - kotaro `cmd_reflux_insight_202608311442_kotaro`: report completedだがtask/paneはin_progress。

## 4. LPレーン依存順

`cmd_4432 CLEAR` → `cmd_4433 CLEAR` → `cmd_4434 RC(receipt依存)` → `cmd_4437`（数値全太字・閲覧列太字・Basic-DM Free）→ `cmd_4436`（月次signals EN/JA）。

- `cmd_4432`/`cmd_4433`/`cmd_4434` のsourceはLP liveへ先行反映済み。
- `cmd_4437` はCurrent signals同一表を触るため `cmd_4434` 直後。
- `cmd_4436` は新規route中心だがLP lane直列規約により最後尾。

## 5. LP SVG欠落の一次証拠と次手

- 本番API `https://dm-signal-backend.onrender.com/api/public/showcase`: `hero.series` list 276点、先頭 `2003-09`、末尾 `2026-08`。
- 隔離build（commit `1589085a...`、同API env）: SVG 1、chart-card 1、year_month 276。
- Render LP origin `https://dm-signal-lp.onrender.com/ja/`: SVG 1、year_month 276、最新 calculated_at。
- custom domain通常URL `https://dm-signal.com/ja/`: SVG 0、year_month 0、旧 calculated_at。
- custom domain cache-bust query: SVG 1、year_month 276。
- clear-cache Render再buildだけでは通常URLの旧本文は消えなかった。真因境界はbuild/APIではなくcustom-domain path cache。
- 次手: Cloudflareの `/`・`/ja/` exact URL cacheをpurgeし、通常URLでSVG 1を確認。再発防止はdeploy後purgeまたはHTML cache versioningを仕組みに埋め込む。

## 6. 連携バグの根因と到達設計

- report metadata更新後、旧SG7 fingerprintとcurrent report generationが不一致になった。
- dedupeが「read:true request」をterminal証拠と誤認し、軍師が既読化してもLGTMが無い報告を落とした。
- 軍師D0 `c891ac00` は通知markerをfingerprint-aware化済み。
- 半蔵taskはrequest/dedupe/priority側を補完し、未terminal generationを各monitor cycleで高優先再提示する。unread同一generationだけを重複抑止し、read:trueは抑止根拠にしない。
- 完了条件はunit PASSだけでなく、滞留3報告がcurrent-generation terminalへ進み、loss=0・duplicate terminal=0を実運用で確認すること。

## 7. 禁則

- 家老が通常実装を抱えない。実装は忍者へ配備する。
- polling loop禁止。event/inboxで再開する。
- 運用YAMLへ `yaml.dump` / `yaml.safe_dump` 禁止。正規helperを使う。
- `git reset --hard`、`git checkout -- .`、`git restore .`、`git clean -f`、kill系、force push禁止。
- GATE receiptを別task・別generation・家老再走で代用しない。
- report requestの `read:true` をterminalとみなさない。
- Render deploy liveとcustom-domain live本文を同一視しない。両方curlする。
- checkpointの過去 `created_at` を変更しない。新版は新規ファイルで作る。

## 8. 二値復帰条件

- [x] role、禁則、一次状態、全未終端task、依存順を記録。
- [x] MAS/DM GitとRender backend/LP live identityを記録。
- [x] review世代連携バグの根因・補完修正・実運用完了条件を記録。
- [x] external package runner欠陥と `cmd_4438` の再開点を記録。
- [x] SVG欠落をAPI/build/origin/custom-domain/cache-bustへ分解し、次手を記録。
- [ ] 本ファイルのSHA-256とscope限定commitを追記せず外部証跡として固定する（自己参照ハッシュを避ける）。
