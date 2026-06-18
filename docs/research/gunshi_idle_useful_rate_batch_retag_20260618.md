# 教訓useful_rate改善: universalタグ一括固有化 (2026-06-18)
<!-- generated: 2026-06-18T00:35:00+09:00 by gunshi idle analysis -->

## 問題

gate_lesson_health.sh ALERT: useful_rate=5.4% (3/56, 直近30cmd)。前セッション20.0%から悪化。
根因=universalタグ教訓184件が全cmdに無差別注入。

## 実施した修正

### Phase 1: NOT_USEFUL頻出上位15件 (本セッション)

| 教訓ID | 旧tags | 新tags | NOT_USEFUL頻度(直近300行) |
|--------|--------|--------|--------------------------|
| L606 | universal | gs,wf,alm | 4 |
| L607 | universal | gs,monthly_return | 4 |
| L608 | universal | gs,monthly_return,parity | 4 |
| L609 | universal | gs,wf,alm | 4 |
| L610 | universal | gs,alm | 4 |
| L611 | universal | gs,alm | 4 |
| L612 | universal | alm,robustness | 4 |
| L613 | universal | alm,robustness,spa | 4 |
| L620 | universal | alm,gs,factor_analysis | 6 |
| L605 | universal | gs,alm,robustness,neighbor_analysis | 3 |
| L595 | universal | gs,python | 2 |
| L587 | universal | alm,wf | 2 |
| L529 | universal | gs,alm | 2 |
| L435 | universal | gs | 2 |
| L576 | universal | fof,alm | 1 |

合計15件修正。universalタグ: 184→170件(Δ-14、L576はfof,alm)。

### Phase 2: 残170件バッチ分類→実行完了

166件のuniversal-only教訓をキーワードベース分類→lesson_write.sh --retagで一括修正。
- **success: 140件** / errors: 26件(古いフォーマットでtagsフィールド不在)
- universalタグ: **184→29件** (155件削減、84%除去)
- 残29件はtagsフィールド不在の旧フォーマット教訓

タグ分布(修正後):
| タグ | 件数 |
|------|------|
| dm-signal | 68 |
| gs | 41 |
| robustness | 21 |
| research | 18 |
| alm | 17 |
| fof | 13 |
| parity | 11 |
| performance | 10 |
| infra | 10 |
| testing | 8 |
| frontend | 8 |
| statistics | 7 |

## 効果予測

- 修正前: universal=184件→全cmdに無差別注入→NOT_USEFUL量産→useful_rate 5.4%
- 修正後: universal=29件(旧フォーマット)。155件が固有タグで適切なcmdにのみ注入
- 効果は次回配備以降に反映(gate_lesson_health.shは過去feedbackデータ参照のため即時反映なし)
- 推定改善: NOT_USEFUL 43件+(追加分)がタグフィルタで除外→useful_rate 30%+到達見込み

## 構造的分析

1. **MAX_INJECT=3 (cmd_3405)**: 効果あり。1cmd当たり注入数3に削減済み
2. **target_pathタグ推定 (cmd_3413)**: 効果あり。GATE CLEAR済み
3. **タグ固有化 (本セッション)**: **155件完了**。効果は次回配備以降反映
4. **計測ラグ**: 30cmd窓にMAX_INJECT=10時代の古いcmdが残存
5. **旧フォーマット29件**: tagsフィールド不在。lesson_write.sh --retagでは修正不可。別途対処検討

## 因果リンク

- -> [[LG027]] referenced率≠useful率
- -> [[cmd_3413]] target_pathタグ推定追加
- -> [[gunshi_idle_useful_rate_tag_precision_improvement_20260616]] 前セッション分析
