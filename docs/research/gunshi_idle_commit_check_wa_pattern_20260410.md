# commit対象外ファイルへのcommit binary_check一律適用WA分析

## 日付
2026-04-10

## 発見
直近karo_workarounds 10件中5件がWA=true。うち3件が同一根因:
**commit対象外ファイル(gitignore/研究出力)にcommit binary_checkが一律適用され、構造的にoverride WAが発生**

## 該当WA

| cmd_id | ninja | category | 根因 |
|--------|-------|----------|------|
| cmd_ga017_gs_knowledge | hayate | gitignore_untracked | gitignore対象ファイルにcommit必須AC |
| cmd_root_dashboard_auto | hayate | verdict_override | gitignore対象ファイルにcommit必須AC |
| cmd_1821 | hayate | verdict_override | 研究cmd出力(outputs/analysis/)がcommit対象外だがcommit check一律適用 |

## 因果鎖

```
cmd設計テンプレート(deploy_task.sh)がcommit binary_checkを全cmdに一律含める
  → 対象ファイルがgitignore or outputs/analysis/(commit不可)
  → 忍者がcommitできない → binary_check=no
  → GATE FAIL → 家老がverdict_override WA発生
  → ×10回繰り返し=毎回override=負の複利
```

## 自動化ターゲット

deploy_task.shのbinary_checksテンプレート生成で:
1. target_pathがgitignore対象か`git check-ignore`で判定
2. 研究cmd(task_type: recon or outputs/配下)ではcommit checkを除外 or 注記付き
3. draft review時に軍師が「commit check対象はcommit可能か」を確認(review_logヘッダ1行)

## 推奨アクション

- **最小**: review_logヘッダに「commit check→git check-ignore対象外か確認」1行追加(原理1行)
- **構造的**: deploy_task.shでgitignore判定→commit check自動除外(Level 4: フロー内埋込)
- 家老に構造的修正を提案

## 複利の問い
commit対象外ファイルにcommit check一律×10回 = 10回override = 負の複利。自動除外1回 = 10回の手動修正不要 = 正の複利。
