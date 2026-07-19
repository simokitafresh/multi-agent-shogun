# cmd_4086 自立改善ループ候補・全PJ横断偵察

日時: 2026-07-19 / 担当: hayate / 範囲: `config/projects.yaml` 15 path + カタログ§3

## §1 結論

- 15/15 path実在、15/15 Git管理。tracked testあり9/15、GitHub Actionsあり3/15、test/CIとも不在6/15。
- 即ループ化候補は database（cron/health/36 tests）、rebalancer（CI/6 tests/health）、Simple-OCR（backup/restore/17 tests）、kj-role-count（daily backup/health/8 tests）。
- 計器づくり先行は DM-Fusion、milk、google-classroom、mcas、clinic-expense-tracker、dividend-tracker。build/lintや生成logはあるが、before→afterを継続記録する一次台帳がない。

## §2 全PJのループ成立3条件（現物確認）

| PJ | 一次計器（現物） | 可逆性 | 検証手段 | 状態・着手前提 |
|---|---|---|---|---|
| dm-signal | `.github/workflows/pytest.yml`、tracked test 332、metrics/ledger群 | Git revert + DB非変更の隔離実行 | pytest、parity/Lighthouse/各ledger再計測 | 計器完備。既存D1-D4を正本とし新規重複なし |
| dm-fusion | `npm run build`、`npm run lint`のみ | Git revert + preview build | build/lint | 計器先行。CIと実行時間台帳を作る |
| infra | `.github/workflows/test.yml`、tracked test 150、`logs/loop_ledger.jsonl`等 | scope限定commit/revert | Bats/Python gate + ledger再計測 | 計器完備。S1-S7を正本とする |
| database | `render.yaml` cron 2件、`/healthz`、tracked test 36 | Git revert、cron/API再実行 | cron endpoint/health/tests | 即候補。cron成功率・鮮度・欠損率の台帳化から開始 |
| rebalancer | CI、tracked test 6、`/healthz` | Git revert + Render preview | pytest/Vitest/Playwright/build/audit | 即候補。CI時間と価格更新成功率を一次台帳へ |
| milk | test/CI/計器なし | Git revert | 未設 | planned PJ。実装開始後に最小CI計器を同時導入 |
| auto-ops | tracked test 8（receipt/expense/CDP等） | Git revert + fixture | pytest | 候補。receipt処理の成功/重複/再実行率台帳を先行 |
| google-classroom | `generated/scrape_log_*.json`、Playwright scraper、Render内蔵cron | Git revert + fixture HTML | scrape結果件数/ログ、将来Playwright contract | 計器半備。ログschema固定と成功率・selector失敗分類が先 |
| mcas | README上lint workflow記述のみ（tracked CI/test 0） | Git revert +隔離HOME fixture | ShellCheck/Python lintをCI化 | 計器先行。switch成功/rollback/設定整合のcontractが必要 |
| simple-ocr | `backup_manager.py`、`tests/test_backup_restore.py`、tracked test 17、`ocr_logs.db` | backup/restore + Git revert | pytest、復元fixture照合 | 即候補。復元成功率・所要時間・件数一致を台帳化 |
| kj-partshift | tracked test 13、`/health`、logger | Git revert + SQLite fixture | pytest/health | 候補。シフト取込・closure計算の件数/不変量台帳を先行 |
| kj-toilet | tracked test 9、scheduled check test | Git revert + DB fixture | pytest/build | 候補。定期判定の遅延/重複/未処理数計器を先行 |
| kj-role-count | daily backup cron、`backend/backup.py`、`/api/health`、tracked test 8 | backup restore + Git revert | pytest/health/復元件数照合 | 即候補。backup作成だけでなく定期復元検証へ拡張 |
| clinic-expense-tracker | `/health`のみ、test/CI 0 | Git revert + DB backup | healthのみ（証票突合なし） | 計器先行。CSV入力件数・重複・金額総和・未突合数の台帳を作る |
| dividend-tracker | build/lintのみ、test/CI 0 | Git revert + preview build | build/lint | 計器先行。配当取込fixtureと銘柄別/期間別総額contractを作る |

## §3 計器不在候補の先行タスク案（偵察5要件）

| 候補 | 対象ファイル | 波及先 | 関連test | エッジケース | 依存順序 |
|---|---|---|---|---|---|
| google-classroom scraper台帳 | `scripts/scrape_classroom.py`, `server.py`, `generated/scrape_log_*.json` | dashboard生成、Render cron | 現在0。固定HTML fixtureのcontractを新設 | login切れ、0件正常、selector変更、部分course失敗 | log schema→fixture→cron adapter→成功率再計測 |
| clinic-expense証票突合 | importer/API実装（現物特定は次cmd）、`render.yaml` | DB schema、集計画面 | 現在0。CSV fixture contractを新設 | 同一証票再投入、負額、文字コード、端数、途中失敗 | backup→台帳schema→dry-run importer→総和/重複照合 |
| dividend取込品質 | `package.json`、取込/data層（次cmdで特定） | 集計UI、保存層 | 現在0。配当fixture contractを新設 | 通貨、税引前後、分割、同日重複、期間境界 | fixture→集計contract→CI→時間/誤差台帳 |
| dm-fusion FE品質 | `package.json`, `.github/workflows/ci.yml`（新設候補） | Next build、migration、Render | 現在0。build/lint contractから開始 | migration失敗、env欠落、API不達、SSR/build差 | preview DB隔離→CI→build時間台帳→失敗分類 |
| mcas切替整合 | `scripts/switch.sh`、workflow（README記載とtracked不一致） | account設定、CLI起動 | 現在0。隔離HOME fixtureが必要 | 中断、同時切替、壊れた設定、rollback | 隔離fixture→dry-run→整合check→CI |
| milk開始時計器 | PJ骨格（現状tracked test/CI 0） | 全実装 | 現在0 | 未確定要件をcontract化しすぎない | 境界確定→最小contract→CI→実装 |

## §4 根拠と計測

- `config/projects.yaml` parse: path存在 15/15、`.git`存在 15/15。
- `git ls-files` のtest path集計: 9/15 PJ、合計579 tracked test files（dm-signal 332、infra 150、database 36、rebalancer 6、auto-ops 8、Simple-OCR 17、kj-partshift 13、kj-toilet 9、kj-role-count 8）。
- `.github/workflows/*`: 3/15 PJ（dm-signal、infra、rebalancer）。
- 読み取りのみの偵察で外部repoは無変更。数値は2026-07-19時点のtracked現物であり、README記述だけを一次計器扱いしていない。

## §5 因果・次サイクル

`[[候補在庫の不在]] -> [[横断偵察cmd_4086]] -> [[15PJ計器成熟度カタログ]]`

次は「test/CIなし6PJ」を一括実装せず、計器の価値が高い順に google-classroom（既存cron/logあり）→clinic-expense（証票突合）→dividend（集計contract）と、1 PJずつ before→after を閉じる。
