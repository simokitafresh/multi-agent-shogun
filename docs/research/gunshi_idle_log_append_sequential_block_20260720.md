# gunshi_log_append.sh 逐次BLOCK分析

## 発見日
2026-07-20 retro_prompt分析

## 現象
cmd_4098 draft reviewのreview_log追記で5回連続BLOCKが発生。
1回目: `finding_categoriesにadversarialが未記載`
2回目: `finding_categoriesにambiguityが未記載`
3回目: `ambiguity_pointsが未記入`
4回目: `brainwash_checkに8パターン番号なし`
5回目: `operational_simulation未記入`

## 根因
scripts/gunshi_log_append.sh L64-130の各チェックが独立に`exit 2`で即停止する逐次設計。
N個の不備がある場合にN回の再投入(全YAML再構築+bash起動+gate判定)が必要。

## 影響計測
- 5回×(YAML構築+bash起動+gate判定) ≈ 25秒
- 集約方式なら1回 ≈ 5秒で80%削減
- 本セッションで2エントリ(cmd_4098 draft + retro_prompt_dedup report)で計6回BLOCK

## 改善案
全チェックを通して不備リストをERRORS変数に集約し、最後にまとめてexit 2する。
```bash
ERRORS=""
# check 1
if ...; then ERRORS+="BLOCK: adversarial未記載\n"; fi
# check 2
if ...; then ERRORS+="BLOCK: ambiguity未記載\n"; fi
# ... all checks ...
if [[ -n "$ERRORS" ]]; then
    printf '%b' "$ERRORS" >&2
    exit 2
fi
```
1回で全修正可能になりラウンドトリップがN→1に削減。

## 因果リンク
origin: [[gunshi_log_append逐次exit2]] -> [[N回再投入]] -> [[レビュー完了時間膨張]]
