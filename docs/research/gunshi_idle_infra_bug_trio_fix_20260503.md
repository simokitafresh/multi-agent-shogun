# インフラバグ3件検出→修正 — 軍師D0直接実装

- 実施者: 軍師 (gunshi)
- 日付: 2026-05-03
- 殿裁定: 検出した本人が修正せよ

## 1. bulletin_write.sh $2 --helpバイパス

- **現象**: `bulletin_write.sh saizo "--help"` が掲示板に`--help`を投稿(blt_20260503_194800)
- **原因**: L9のfast-pathが`$1`のみチェック。2引数構文(`posted_by content`)で`$2=--help`が通過
- **修正**: `$2`の`-h`/`--help`チェック追加(L9)
- **検証**: bats 8/8 PASS + 手動2パターン(both exit 1) + bash -n PASS
- **commit**: bc53ce1c

## 2. cmd_complete_gate.sh draft_lessonsプロジェクト全体BLOCK

- **現象**: tasks/lessons.md L555(cmd_2482由来)+L556(cmd_2483由来)のdraft教訓2件が、無関係なcmd_2525/2526/2527/2528の4件を連続BLOCK
- **原因**: L3987で`grep -c 'status: draft'`がプロジェクト全体のdraft数をカウント→全cmdをBLOCK
- **修正**: cmd固有(出典フィールドにCMD_IDを含む)draftのみBLOCK、他はWARN降格。awk末尾処理(空行なしファイル)も追加
- **検証**: awk 3パターン(自cmd末尾/他cmd末尾/混在)全PASS + bash -n PASS
- **commit**: bc53ce1c
- **設計判断**: draft教訓の処理催促はstartup gateの三層学習ループ健全性チェックがカバー済み

## 3. kotaro task YAML stale残骸

- **現象**: cmd_2525配備後もtask_id=cmd_2482_kotaro、report_filename=kotaro_report_cmd_2482.yamlのまま
- **原因**: deploy_task.sh外の配備経路(karo_direct方式)ではtask YAMLが上書きされない
- **修正**: status:completed→idle(yaml_field_set.sh経由)
- **根本対策提案**: karo_direct配備時にもtask YAMLのフィールド更新(lesson_candidateとして家老に送信済み)
- **commit**: 92cf21ae

## 因果鎖

idle自走(karo_workarounds/review_log分析)→異常パターン検出(才蔵--help掲示板/4cmd連続BLOCK/report名不一致)→現物確認(grep/Read/git log)→3件バグ確定→D0直接実装→S0セルフレビュー→家老LGTM

## 学び

- idle自走の価値: レビュー依頼なしの時間でインフラバグ3件を発見→修正。分析→記録で止めず修正→検証→commitまで回した
- fast-pathの穴: 引数構文が複数ある場合、全引数位置のhelpチェックが必要
- gate BLOCKスコープ: 安全側(全cmdBLOCK)は過剰→cmd固有スコープが適切。催促は別経路(startup gate)がカバー

generated: 2026-05-03T20:15:00+09:00
