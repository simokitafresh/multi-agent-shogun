# 教訓注入有効率分析 — useful率18.2%の根因と改善案

## 計測データ (2026-06-08)

| 指標 | 値 | ソース |
|------|-----|--------|
| referenced率 | 100% (16/16) | gate_lesson_health.sh |
| useful率 | 18.2% (2/11) | gate_lesson_health.sh |
| NOT_USEFUL累計 | 68件 | lesson_impact.tsv |
| USEFUL累計 | 5件 | lesson_impact.tsv |
| 全体useful率 | 6.8% (5/73) | lesson_impact.tsv算出 |

## NOT_USEFULワースト教訓

| 教訓ID | NOT_USEFUL回数 | 内容 | 真の適用範囲 |
|--------|---------------|------|------------|
| L489 | 6 | bats並列/tmp競合 | bats変更cmdのみ |
| L088 | 6 | deploy_task.shタグ推定 | deploy_task.sh変更cmdのみ |
| L690 | 4 | cwd非依存パス | CI/スクリプト系 |
| L633 | 4 | verdict自動導出waive | gate系のみ |
| L548 | 4 | yaml.dump残存検出 | 偵察系のみ |
| L504 | 4 | WSL2 find -mmin不安定 | パフォーマンス系 |
| L491 | 4 | git status awk高速化 | パフォーマンス系 |
| L668 | 3 | insight_write.sh最適化 | insight_write.sh変更のみ |

## 根因分析 (なぜなぜ)

1. なぜuseful率が18.2%か？ → 無関係な教訓が注入されている
2. なぜ無関係な教訓が注入されるか？ → キーワードマッチが「scripts」「gate」「bash」等の広いキーワードに引っかかる
3. なぜ広いキーワードに引っかかるか？ → infraプロジェクトの教訓(656件active)が全て同一プールにあり、サブドメイン分離がない
4. なぜサブドメイン分離がないか？ → tagsがuniversal等の粗い粒度で、bats/deploy_task/gate等の細粒度分類がない
5. **根因**: infraプロジェクトの教訓タグ粒度が粗すぎて、キーワードマッチの選択性が低い

## 追加根因: NOT_USEFULの淘汰遅延

- apply_zero_useful_deprecationは条件を満たす(total >= 1, useful == 0)が、**deploy_task.sh実行タイミングでしか発火しない**
- L489は3回NOT_USEFUL(impact.tsv)だが、全て2026-06-08 22:13-22:29。次のdeploy_task.sh実行まで淘汰されない
- 淘汰は設計通り動いているが、フィードバック即時反映ではなく次回配備時の遅延がある

## 改善案

### 案1: タグ粒度向上 (推奨・効果大)
NOT_USEFULワースト8教訓のtagsを`universal`からサブドメインタグに変更:
- L489: `bats-parallel` → bats変更cmdのみにマッチ
- L088: `deploy-task-internal` → deploy_task.sh変更cmdのみ
- L690: `ci-path-resolution` → CI/パス系のみ
- 他も同様に細粒度化

**効果予測**: ワースト8教訓(累計33件NOT_USEFUL)が無関係cmdに注入されなくなり、useful率が大幅改善

### 案2: USEFUL_RATE_MIN_SAMPLES引き下げ
現行: `ZERO_USEFUL_DEPRECATE_MIN_SAMPLES=1`は既にmin。問題はフィードバックのタイミング。
→ 既に最適。追加改善不要。

### 案3: キーワードスコア閾値の動的調整
NO_TARGET_PATH_MIN_SCORE=8は実装済み(cmd_3231)。
→ 効いているが、infraの教訓プールが大きすぎて閾値だけでは不十分。案1と併用が必要。

## 複利の問い

教訓タグ粒度向上(案1)を10回繰り返したら？ → 正の複利。各改善で無関係注入が減り、忍者の読み時間が削減され、useful率フィードバックの質も向上する。

## 推奨行動

1. 家老にlesson_candidate送信: ワースト8教訓のタグ変更を依頼
2. タグ変更は家老のlesson_write.sh経由(軍師はlessons.yaml直接編集不可)

## causal_chain

教訓タグ粗粒度→キーワードマッチ選択性低→無関係教訓注入→忍者NOT_USEFUL判定→useful率18.2%→ALERT。タグ細粒度化が根因対処。
