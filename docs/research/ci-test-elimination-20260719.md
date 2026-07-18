# CI test elimination — 2026-07-19

## 結論

- 監査母数: 4,922 cases / 365 files。
- test_necessity相当の具体的不変量を持つcanonical push境界: 487 cases / 30 files。
- 宣言なし削除対象: 4,435 cases / 335 files。`36fe2add4`で非衝突331 filesを削除済み。
- 残存4 files / 140 casesは他任務の未commit変更との衝突を検出したため強制削除せず、owner完了後に再監査する。
- 非test削除0、push-maintainとのfile重複0。恒久nightly・30日観察queue・cronは作らない。

一次一覧: `docs/research/ci-test-elimination-inventory-20260719.csv`

## 意図した残余リスク

宣言なしtestの削除により、canonical push境界の内側にあった未宣言の回帰検知網を失うことを意図して受容する。初回事故のコストは払い、事故から具体的不変量を抽出し、`test_necessity`宣言付きcontract testとしてpush境界へ昇格する。形式だけの宣言、対象不明、既存contractとの重複は恒久化しない。

## 自動再発防止

campaign lane `test-hygiene` は次のいずれか一つで棚卸しを発火する（OR条件）。cronではなく計測更新からadapterを起動する。

- push wall > 170秒
- FAIL実績0比率 > 20%
- 新規test純増 > 50件/週
- 新規test宣言率 > 30%

writerはcase identity・source file・result・source SHA・wallを持つ `logs/test_timing_ledger.tsv`、adapterは `scripts/test_speed_task_generator.sh hygiene-evaluate|hygiene-deploy`。
