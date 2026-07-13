# cmd_3871 陳腐化中間成果物 全38件棚卸し(analysis4+grid27+CDP7)

- 計測時刻: 2026-07-13T10:45頃(JST)
- 対象: `/mnt/c/Python_app/DM-signal/outputs/` 配下の3群(outputs/analysis配下の完了済みcmd成果物4件、cdp_profile_cmd695系旧世代7件、grid_search直下の旧CSVバックアップ27件)
- 対象総数: 38件 / 合計 9,271,145,559 bytes (約8.64GiB)
- 引継ぎ元(半蔵STALL差し替え): 38件全てDELETE候補として特定済み。ただしAC2の必須検証(rg参照件数確認)は半蔵未完了のまま差し替え。本inventoryはその検証を完遂した結果、**38件中10件をKEEPへ再分類**した(analysis 2件: cmd_3819/cmd_3825 + grid_search 8件: 1026_yotsume DM{2,3,6,7P}系monthly/results .bak_cmd1186)。

## 二分結果(検証後・削除実行済み)

- KEEP: 38件中10件を再分類 / 4,422,657,136 bytes(既存保全対象のcmd_3854 golden baseline・cmd_3859 shadow artifactsは元々DELETE候補外のため下記「既存保全対象」参照)
- DELETE確定: 28件 / 予測4,848,488,423 bytes(約4.52GiB) — **削除実行済み、28/28件成功**
- 二分検証: 38 = 10(KEEP再分類) + 28(DELETE確定) ✓
- 削除実行: 完了(2026-07-13、realpath安全ガード付きrm -rf、28/28成功、STILL EXISTS残存0件)
- df実測差分: 削除前 available=302,243,565,568B → 削除後 available=307,048,386,560B、**実測回収量=4,804,820,992 bytes(約4.47GiB)**。予測値4,848,488,423Bとの差43,667,431B(0.9%)はNTFSブロック丸め+他忍者の同時ディスク活動(kagemaru cmd_3868等が同一C:ドライブで並行稼働中)による誤差範囲
- KEEP対象6件(cmd_3819/cmd_3825/cmd_3859+DM系4ファイル代表)の無傷確認: 全件`ls`現物確認OK

### 再分類の内訳(重要: 半蔵引継ぎからの逸脱)

| 分類 | 元区分(半蔵) | 件数 | bytes | 理由 |
|---|---|---:|---:|---|
| analysis: cmd_2143_verify | DELETE候補 | 1 | 380,220,420 | 確定DELETE(参照は完了済み研究レポートのみ) |
| analysis: cmd_3775_profiles | DELETE候補 | 1 | 1,708,170,398 | 確定DELETE(参照は完了済み研究レポートのみ) |
| analysis: cmd_3819 | DELETE候補 | 1 | 3,614,416,434 | **KEEPへ再分類**。正本設計書`docs/design/precompute-zero-recompute-implementation-design.md`+現役scripts(`cmd_3854_fof_golden_capture.py`, `cmd_3819_baseline_provision.py`等)が`outputs/analysis/cmd_3819/baseline_dump/`を直接参照。26ファイルから参照。MEMORY.md記載の非決定性根治P4 AC2(本番1run未実行)の前提データに直結 |
| analysis: cmd_3825 | DELETE候補 | 1 | 774,782,457 | **KEEPへ再分類**。同設計書+`scripts/oneshot/cmd_3825_fixture_provision.py`等20ファイルが`outputs/analysis/cmd_3825/`配下パスを参照 |
| grid_search: 1026_yotsume DM{2,3,6,7P}系 monthly/results .bak_cmd1186 | DELETE候補 | 8 | 33,458,245 | **KEEPへ再分類**。`tasks/lessons.md:9210`が「DM家系別split版が必要な分析ではこのファイル群を使う必要がある」と明記 |
| CDP7全件 | DELETE候補 | 7 | 1,229,549,545 | 確定DELETE(参照0件) |
| grid_search: 残り19件 | DELETE候補 | 19 | 1,530,548,060 | 確定DELETE(参照0件、または殿裁定2026-03-19「GSはlocal SQL化済みで過去CSV不要」で明示的にクリア済み) |

合計検算: 1(1) + 1(1) + 1(1) + 1(1) + 8 + 7 + 19 = 38件 ✓
KEEP新規4区分合計bytes: 3,614,416,434 + 774,782,457 + 33,458,245 = 4,422,657,136
DELETE確定合計bytes: 380,220,420 + 1,708,170,398 + 1,229,549,545 + 1,530,548,060 = 4,848,488,423

## 既存保全対象(KEEPの前提、削除候補には元々含まれない)

| 名前 | 実際の所在 | 現物確認 |
|---|---|---|
| cmd_3854 golden baseline | `/mnt/c/Python_app/DM-signal/backend/tests/golden_data/cmd_3854_fof_golden_baseline.json`(git管理下、outputs/配下ではない) | `rg -l cmd_3854` で存在確認済み。outputs/配下の38候補との重複なし |
| cmd_3859 shadow artifacts | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3859/`(analysis4の4件とは別ディレクトリ) | `ls`で現物確認済み(`cmd_3859_ac1_shadow_exact.json`等) |

## 完全一覧(38件)

| # | 絶対パス | bytes | mtime | 区分 | 参照件数(rg, outputs/.git/worktree除外) | 根拠 |
|---|---|---:|---|---|---:|---|
| 1 | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_2143_verify` | 380,220,420 | 2026-04-20T00:15:25+0900 | DELETE | 1(研究レポートのみ) | docs/research/codd_spec_cmd_2143_run_077_kasoku_diff_20260420.mdのみ参照。進行中スクリプト/設計書なし |
| 2 | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3775_profiles` | 1,708,170,398 | 2026-07-08T19:50:28+0900 | DELETE | 1(研究レポートのみ) | docs/research/cmd_3775_run077_profile_recon.mdのみ参照。進行中スクリプト/設計書なし |
| 3 | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3819` | 3,614,416,434 | 2026-07-10T09:24:38+0900 | **KEEP** | 26 | 正本設計書+現役golden baseline captureスクリプトが参照。P4 AC2前提データ |
| 4 | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3825` | 774,782,457 | 2026-07-11T02:07:16+0900 | **KEEP** | 20 | 正本設計書+cmd_3825_fixture_provision.py等が参照 |
| 5 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695` | 117,155,977 | 2026-03-09T13:51:03+0900 | DELETE | 0 | 参照なし |
| 6 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_ac5` | 105,765,433 | 2026-03-09T13:51:08+0900 | DELETE | 0 | 参照なし |
| 7 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_final` | 118,887,868 | 2026-03-09T13:51:19+0900 | DELETE | 0 | 参照なし |
| 8 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_retry` | 116,376,174 | 2026-03-09T13:51:26+0900 | DELETE | 0 | 参照なし |
| 9 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review` | 565,263,618 | 2026-03-12T02:18:42+0900 | DELETE | 0 | 参照なし |
| 10 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_success` | 102,481,234 | 2026-03-09T13:51:12+0900 | DELETE | 0 | 参照なし |
| 11 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_verify` | 103,619,241 | 2026-03-09T13:51:30+0900 | DELETE | 0 | 参照なし |
| 12 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM2_grid_monthly_fast.csv.bak_cmd1186` | 14,707,565 | 2026-03-19T03:25:29+0900 | **KEEP** | 1(lessons.md) | tasks/lessons.md:9210がDM家系別split分析用途で明記 |
| 13 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM2_grid_results_fast.csv.bak_cmd1186` | 1,774,870 | 2026-03-19T03:25:27+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 14 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM3_grid_monthly_fast.csv.bak_cmd1186` | 206,485 | 2026-03-19T03:25:44+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 15 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM3_grid_results_fast.csv.bak_cmd1186` | 22,745 | 2026-03-19T03:25:44+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 16 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM6_grid_monthly_fast.csv.bak_cmd1186` | 14,740,153 | 2026-03-19T03:26:01+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 17 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM6_grid_results_fast.csv.bak_cmd1186` | 1,778,565 | 2026-03-19T03:26:00+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 18 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM7P_grid_monthly_fast.csv.bak_cmd1186` | 205,009 | 2026-03-19T03:26:20+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 19 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_DM7P_grid_results_fast.csv.bak_cmd1186` | 22,853 | 2026-03-19T03:26:20+0900 | **KEEP** | 1(lessons.md) | 同上 |
| 20 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_grid_monthly_fast.csv.bak_cmd1057` | 787,030,546 | 2026-03-19T02:50:56+0900 | DELETE | 0 | 殿裁定2026-03-19「GSはlocal SQL化済みで過去CSV不要」で明示クリア済み(task assumptions記載) |
| 21 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_grid_monthly_fast.csv.bak_cmd1186` | 29,098,042 | 2026-03-19T04:35:10+0900 | DELETE | 0 | DM非split(12体結合ユニバース)の旧世代バックアップ。lessons.md記載対象外 |
| 22 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_grid_results_fast.csv.bak_cmd1057` | 97,260,657 | 2026-03-19T02:47:58+0900 | DELETE | 0 | 同上(殿裁定対象) |
| 23 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_grid_results_fast.csv.bak_cmd1186` | 3,598,196 | 2026-03-19T03:51:57+0900 | DELETE | 0 | DM非split旧世代 |
| 24 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/1026_yotsume_grid_results_fast.meta.yaml.bak_cmd1186` | 2,388 | 2026-03-19T03:26:21+0900 | DELETE | 0 | 同上メタデータ |
| 25 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kasoku_grid_monthly_fast.csv.bak` | 2,251,930 | 2026-03-19T00:56:42+0900 | DELETE | 0 | 参照なし |
| 26 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kasoku_grid_results_fast.csv.bak` | 248,966 | 2026-03-19T00:56:42+0900 | DELETE | 0 | 参照なし |
| 27 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kasoku_grid_results_fast.meta.yaml.bak` | 2,415 | 2026-03-19T00:56:42+0900 | DELETE | 0 | 参照なし |
| 28 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_monthly_fast.csv.bak` | 2,597,293 | 2026-03-19T00:55:15+0900 | DELETE | 0 | 参照なし |
| 29 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_monthly_fast.csv.bak_20260321` | 176,000,889 | 2026-03-19T04:31:48+0900 | DELETE | 0 | 参照なし |
| 30 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_results_fast.csv.bak` | 272,042 | 2026-03-19T00:55:15+0900 | DELETE | 0 | 参照なし |
| 31 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_results_fast.csv.bak_20260321` | 17,948,844 | 2026-03-19T03:51:54+0900 | DELETE | 0 | 参照なし |
| 32 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_results_fast.meta.yaml.bak` | 2,422 | 2026-03-19T00:55:15+0900 | DELETE | 0 | 参照なし |
| 33 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_kawarimi_grid_results_fast.meta.yaml.bak_20260321` | 2,493 | 2026-03-19T03:27:11+0900 | DELETE | 0 | 参照なし |
| 34 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_nukimi_grid_monthly_fast.csv.bak_20260319` | 376,197,501 | 2026-03-19T04:28:04+0900 | DELETE | 0 | 参照なし |
| 35 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_nukimi_grid_results_fast.csv.bak_20260319` | 35,353,552 | 2026-03-19T03:51:53+0900 | DELETE | 0 | 参照なし |
| 36 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_oikaze_grid_monthly_fast.csv.bak` | 2,375,909 | 2026-03-19T00:53:29+0900 | DELETE | 0 | 参照なし |
| 37 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_oikaze_grid_results_fast.csv.bak` | 301,638 | 2026-03-19T00:53:29+0900 | DELETE | 0 | 参照なし |
| 38 | `/mnt/c/Python_app/DM-signal/outputs/grid_search/246_oikaze_grid_results_fast.meta.yaml.bak` | 2,337 | 2026-03-19T00:53:30+0900 | DELETE | 0 | 参照なし |

## 事前安全確認

- 全38件は`.gitignore`パターン(`outputs/analysis/cmd_*/`, `outputs/cdp_*/`, `outputs/grid_search/`)によりgit管理外を確認済み(削除はgit履歴に影響しない)
- `lsof +D`でcmd_3819/cmd_3825にプロセスロックなしを確認
- cmd_3819/cmd_3825配下ファイルの本日(2026-07-13)書込みなし(`find -newermt`で確認、稼働中プロセスなし)
- realpath全件がシンボリックリンクでなく`/mnt/c/Python_app/DM-signal/outputs/`配下に実在することを確認済み
