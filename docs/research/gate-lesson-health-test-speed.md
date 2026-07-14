# gate_lesson_health test speed

## 結論

21ケースの契約を維持し、caseごとのfixture逐次生成を `setup_file` の共有base fixtureへ集約する。実行台帳は [[run_timed_bats.sh]]、被テスト契約は [[gate_lesson_health.sh]] を正本とする。

## 2026-07-15 実測

- baseline: 21 PASS / 0 FAIL / 0 SKIP、10.540秒。
- 支配項: `bash scripts/gates/gate_lesson_health.sh infra` 単体0.85秒。21回のprocess起動は契約分離のため維持。
- 改善点1（実装）: `tests/unit/test_gate_lesson_health.bats` 13-70行相当で毎case 7ディレクトリ・6 fixtureを生成していたため、共有base作成＋copyへ集約。
- 改善点2: 各caseのgate process起動は約0.5秒/件を占める。将来は被テストscript側の全project走査・global health計算をprofileし、契約を保った内部cache候補を検証する。
- 改善点3: mutable fixtureのheredocが各testへ散在する。fixture builderを導入すれば重複を減らせるが、今回は最高インパクトのbase fixture共有を優先した。

## 直接参照

- [[run_timed_bats.sh]] 15-19行: Batsの開始・終了時刻をnanosecondで採取する。
- [[gate_lesson_health.sh]] 217-218行: role lesson origin検査は3ファイルを1回のawkへ統合済みである。
