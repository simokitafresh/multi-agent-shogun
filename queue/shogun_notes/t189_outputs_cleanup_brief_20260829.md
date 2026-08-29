# T189 DM-signal outputs 整理 — 家老への配備単位(殿裁定 2026-08-29 16:51/16:53/16:56『消せ』)

[MEM: memory_db knowledge:a5507a8288cc0eab 2026-08-29T16:52 "殿裁定 16:51『DM-signal outputs は現在本番環境で使用中のモノ以外は不要』"] [MEM: obsidian link=[[殿裁定_作成に使ったものは残す_20260829_1653]] -> [[grid-search-outputs-cleanup-inventory-20260807]]]

## 目的
/mnt/c/Python_app/DM-signal/outputs 47G のうち、本番 PF(33 体)を作成するために使った GS 結果だけ残し、残りを除去する。T106 ext4 cutover の複製時間を 1/3 にする(速度向上へのつながり)。

## 保持集合(触るな。除去前後で du 不変を証明)
- outputs/grid_search/shin_shijin_l1 (cmd_1018=シン四神 12 体根拠、872M)
- outputs/grid_search/shin_ninpo_v2_12body (cmd_1080=シン忍法 v2 21 体根拠、2.7G)
- outputs/grid_search/cmd_3495〜cmd_3505 系(秘奥義 GS、1.4G)
- outputs/grid_search/cmd_3774*・cmd_3779*(full、4.4G)
- outputs/grid_search/cmd_3798_phase_b_l1 (234M)
- outputs/grid_search/ema_experiment_phase0_v2_l1
- git tracked の outputs 全件(git ls-files outputs、24M)
- cmd_3871 の KEEP 再分類 10 件(docs/research/cmd_3871_stale_artifact_inventory.md)

## 除去集合(docs/research/grid-search-outputs-cleanup-inventory-20260807.md §最終判定の『削除』行=約 29.5G)
- ALM ディスコン 3 体(NPY のみ、8.1G)/WF 系 10 ディレクトリ(5.4G)/日付ディレクトリ 20260706・0708・0709・0710(13.8G)/速度改善プロファイル hanzo_e2・hole3・phase_d(2.1G)/smoke 系/空ディレクトリ 3/backup(meta.yaml)/legacy・pre_cmd1125・yotsume
- 要確認 2 件は今回対象外(okugi_shin_ninpo_20body 2.0G、20260427 52M)。判定材料だけ報告に添える

## 二値 AC
- AC1: 除去前に対象ごとの du -sb と件数を一覧化し、対象が保持集合・git tracked と 0 件重複であることを機械照合(git ls-files との差集合、realpath が outputs/ 配下)してから除去する。証跡=一覧ファイル+照合コマンドと生出力。
- AC2: 除去後 df の available 差分 ≥ 25G ∧ 保持集合の du -sb が前後で一致 ∧ git status --short で tracked ファイルの削除 0 件。
- AC3: 本番 PF 33 体への影響 0=本番 DB read-only(/db-check の型)で portfolios 件数と signals 行数が除去前後で一致。

## 制約
- realpath 安全ガード付きで outputs/ 配下のみ(cmd_3871 の型)。D002 遵守。9p 上のため 1 ディレクトリずつ、途中で D-state が出たら止めて報告。
- 完了報告先=掲示板(BULLETIN_NOTIFY=shogun)。
