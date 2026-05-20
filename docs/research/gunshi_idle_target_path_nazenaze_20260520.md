# target_path_warning偽陽性 なぜなぜ7回

## 発端
cmd_training_L4_auto_202605201330_kotaro draftレビュー時にtarget_path_warning偽陽性を発見。
scripts/ninja_monitor.sh(201KB存在)に対し「存在しない」と表示。

## なぜなぜ7回

| Why | 問い | 答え |
|-----|------|------|
| 1 | なぜ検出されなかった | WARNは配備を止めない。チェックされていなかった |
| 2 | なぜチェックしていない | WARN=存在しないのと同じ(殿裁定: WARNも環境変更必須) |
| 3 | なぜBLOCKでない | 段階的導入→昇格判断が未実施 |
| 4 | なぜ昇格未実施 | WARN発火の監視/集計が未整備 |
| 5 | なぜ集計されない | gate_fire_logに記録されるがstartup gate集計対象外 |
| 6 | なぜ別リポが不在判定 | 単一リポジトリ前提。project情報未参照 |
| **7** | **根因** | **target_pathチェックがproject.pathを参照していない** |

## 定量データ
- gate_fire_log.yaml: inject_target_path_check WARN **90件** (2026-04-20〜2026-05-20)
- 偽陽性内訳: infra相対パス(4件) + DM-Signal相対パス(86件)
- DM-Signal側パスは全て実在(backend/app/api/signals.py等)

## 修正

### Phase 1: 相対パスのSCRIPT_DIR基準解決 (commit 00c8e900)
- `[ ! -e "$p" ]` → `[[ "$p" != /* ]] && resolved="$SCRIPT_DIR/$p"`
- infra相対パス4件の偽陽性を解消

### Phase 2: project_path 2段解決 (commit 9e26bc44)
- SCRIPT_DIR基準で不在→projects/{id}.yamlのpath基準で再試行
- DM-Signal相対パス86件の偽陽性を解消
- 4パターン検証: infra相対/DM-Signal相対/絶対/本当の不在 全PASS

## 因果リンク
- → [[LG034]] 低ROI/対応不要は作業量縮小の隠語。90件WARNを「WARNだから」で放置=同構造
- → [[成長ループ]] WARNも環境変更必須(殿裁定)。WARN放置=BLOCK前の予兆を無視
- → [[deepdive_why_chain Phase 4]] 計測されないものは改善されない→startup gateのWARN集計対象拡大が残課題
