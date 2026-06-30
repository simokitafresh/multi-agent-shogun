# Sonnet 5 vs Sonnet 4.6 A/B評価レポート

## 概要
- 期間: 2026-07-01
- 被験者: tobisaru(Sonnet 5 xhigh v2.1.197) vs kotaro(Sonnet 4.6 high v2.1.87)
- ラウンド数: 2

## 第1ラウンド(cmd_3620): GA-152 context_freshness偵察
- 注: assigned_scope旧文面混入(contaminated)。両忍者ともGA-152を調査

| 観点 | kotaro (S4.6) | tobisaru (S5) |
|------|--------------|--------------|
| 完了速度 | 3分 | 7分 |
| 根因特定 | タイムライン+root_fallback経路 | +ntfy throttle競合+gate_alerts構造欠落+GP-190検証 |
| knowledge_candidate | なし | あり(2件) |
| decision_candidate | なし | あり(1件: gate_alerts完了マーキング機構) |
| lesson_candidate | なし(L881既存) | あり(assigned_scope残留誤作業誘発) |

## 第2ラウンド(cmd_3621): cmd品質記録漏れALERT根因調査
- クリーンタスクYAML(stale混入防止済み)

| 観点 | kotaro (S4.6) | tobisaru (S5) |
|------|--------------|--------------|
| 根因 | SIGHUP/disown漏れ(実装漏れ) | dual lock race(設計前提崩壊) |
| 深度 | 表層(1行修正) | 構造(ロック統一設計からの逸脱) |
| 証拠精度 | 20件中3件記録→差分17件(1件ずれ) | 20件中0件記録→差分18件(完全一致) |
| task_clarity | 85(補正後に即作業) | 60(家老に確認質問→方針回答) |
| lesson_candidate | あり(disown漏れ) | あり(dual lock race) |

## 累積評価

| 指標 | Sonnet 4.6 | Sonnet 5 |
|------|-----------|---------|
| **速度** | ★★★(平均6.5分) | ★★(平均11分) |
| **深度** | ★★(表層的だが正確) | ★★★(構造的で設計前提まで掘る) |
| **自発的発見** | ★(R1:0件, R2:1件) | ★★★(R1:3件, R2:2件) |
| **証拠精度** | ★★(1件ずれ) | ★★★(完全一致) |
| **コスト(effort)** | high(低コスト) | xhigh(高コスト) |

## 所見

1. **Sonnet 5は「なぜ」を深く掘る**。disown漏れ(S4.6)vs dual lock race(S5)の差が顕著。S5は設計意図(flock統一設計)まで追跡し構造的根因に到達
2. **Sonnet 4.6は速い**。定型的な偵察を短時間で完了。品質は十分だが深掘りしない
3. **S5はtask_clarityが低い時に確認質問を出す**。S4.6は曖昧でも定型的に進む。S5の方が安全だがlatencyが増える
4. **証拠精度はS5が上**。R2でkotaroは17件(1件ずれ)、tobisaruは18件(完全一致)

## 推奨

- **深掘り・偵察・研究cmd**: Sonnet 5が適任(構造的根因到達+自発的発見)
- **定型修正・CI fix・hotfix**: Sonnet 4.6で十分(速度優位+品質良好)
- **次ステップ**: コード実装系cmdでの比較(実装品質・テスト網羅性・gate FAIL率)が必要
