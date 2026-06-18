# 教訓useful_rate タグ精度改善分析
<!-- generated: 2026-06-16T11:40:00+09:00 by gunshi idle analysis -->

## 問題

gate_lesson_health.sh ALERT: useful_rate=16.7% (12/72, 直近30cmd)。ALERT閾値30%未満。
全体TSV: useful=51/327 = 15.6%。
cmd_3396(NEVER_USEFUL 8件タグ固有化)実施後も改善なし。

## 根因分析

### 1次分析: NEVER_USEFUL教訓(feedback>=3, useful=0)
- L625(8件NOT_USEFUL): GS dir旧ファイル混在。tags: [gs] — 既にGS固有だがwhen句が汎用
- L617(3件NOT_USEFUL): gate_artifact_map。tags: [universal] → **[gs]に修正済み(本セッション)**

### 2次分析: NOT_USEFUL 2件以上の教訓(47件)
universalタグの教訓が9件: L621, L619, L616, L615, L614, L602, L580, L507, L454
→ タグ固有化をバッチ実行中

### 3次分析: cmd別useful率
| cmd | feedback数 | useful | rate |
|-----|-----------|--------|------|
| 平均 | 10件/cmd | 1.0件 | ~10% |

1cmd当たり10件注入→useful平均1件。S/N比=1:9。

### 構造的根因
**universalタグ教訓190件が全cmdに無差別注入**。task_type/target_pathとの関連性が低い教訓が大量にS/N比を下げている。

## 実施した改善

| 教訓ID | 旧tags | 新tags | NOT_USEFUL件数 | 理由 |
|--------|--------|--------|---------------|------|
| L617 | universal | gs | 3 | gate_artifact_map=GS固有 |
| L634 | universal | db,migration | 4 | マイグレーションバグ=DB固有 |
| L618 | universal | gs,fullrecalculate,long_computation | 4 | Agent禁止=長時間計算固有 |
| L324 | testing | p_bar,testing | 4 | p̄計算=p_bar固有 |
| L621-L454 | universal | (各固有タグ) | 2各 | バッチ処理中(9件) |

## 効果検証(シミュレーション)

修正対象14件の過去30cmd窓でのNOT_USEFUL合計: **33件**。
- 修正前: useful=12/72 = **16.7%** (ALERT)
- 修正後(シミュレーション): useful=12/39 = **30.8%** (ALERT閾値30%突破)
- 改善幅: **+14.1pp**

初回予測(+1.9pp)は過小評価だった。lesson_impact.tsvの直近窓で実測したところ、修正対象教訓が33件NOT_USEFULを占めており、除去効果が想定の7倍大きかった。

注: 効果は次回配備以降に実データに反映。シミュレーションは過去データから修正教訓のfeedbackを除外して計算。

## 構造的提案(次ステップ) — cmd_3405で対処中

1. **deploy_task.shの注入数削減(cmd_3405)**: MAX_INJECT 10→3。S/N比3倍改善。将軍起票済み
2. **残存universalタグ181件**: 本来固有タグであるべき教訓を段階的に再分類(優先=NOT_USEFUL頻度順)
3. **複合効果予測**: タグ精度(+14.1pp) + MAX_INJECT削減(さらに改善) → 30%超安定化

## 追跡計測(2026-06-16T13:00 セッション2)

### MAX_INJECT=3 効果検証
- cmd_3405(MAX_INJECT 10→3): GATE CLEAR 2026-06-16T11:49
- cmd_3406以降(MAX_INJECT=3適用確認):
  - 将軍cmd(cmd_3406-3411): 3件/cmd注入 → useful 3/15 = 20.0%
  - 最新karo_direct(cmd_karo_skill_refs_update): 2件/cmd注入 → MAX_INJECT効果あり
  - 古いkaro_hotfix(2026-06-14/15): 10件/cmd注入(修正前deploy) → 窓に残存しALERT維持
- **全体(直近30cmd窓)**: useful=11/55 = **20.0%** (前セッション16.7%から+3.3pp)
- **予測**: 古い10件/cmd cmdが窓から外れれば30%到達見込み

### 残存問題: target_pathフォールバックによる教訓漏出
- L577(gs_monthly)がinfra cmdに注入されNOT_USEFUL
- 経路: has_target_path=trueの場合、タグ不一致でもtag_candidatesに追加(L5011-5012)
- 構造: target_pathがある限りタグフィルタが効かず全教訓がフォールバック候補
- **これは別根因。タグ固有化+MAX_INJECT削減とは独立した問題**

### 次アクション
1. 古いcmdが窓から外れるのを待つ(受動) → 洗脳#5にならないよう計測を継続
2. target_pathフォールバック問題の根因修正検討(能動) → cmd提案が必要

## 因果リンク

- -> [[LG027]] referenced率≠useful率
- -> [[cmd_3396]] NEVER_USEFUL 8件タグ固有化(前セッション)
- -> [[cmd_3405]] MAX_INJECT 10→3削減
- -> [[gunshi_idle_useful_rate_measurement_fix_20260615]] 計測バグ修正
