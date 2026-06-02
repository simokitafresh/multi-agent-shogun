# 教訓注入 universal bypass 根因分析
<!-- generated: 2026-06-02T20:44:00+09:00 by gunshi idle analysis -->

## 問題

startup gate WARN: 教訓有効率34.6% (37/107件)。LG027: referenced率≠useful率。

## 計測データ

| 指標 | 値 |
|------|-----|
| USEFUL | 49件 (25 unique lesson IDs) |
| NOT_USEFUL | 95件 (41 unique lesson IDs) |
| USEFUL率 | 34.0% (49/144) |
| task_type | 全件 exact |
| Top NOT_USEFUL | L506(5), L499(5), L507(4), L505(4), L503(4), L495(4) |

## なぜなぜ分析

| # | なぜ | 答え |
|---|------|------|
| 1 | 有効率が34.6%と低い | NOT_USEFUL 95件がUSEFUL 49件の約2倍 |
| 2 | NOT_USEFUL教訓が大量に注入される | Top NOT_USEFUL教訓はすべてtags:[universal]+target_files指定あり |
| 3 | target_files指定があるのに無関係タスクに注入される | `_universal_without_target_files_is_relevant()`がtarget_files存在時に無条件True |
| 4 | なぜ無条件Trueか | L4556: `if any(str(p).strip() for p in lesson_target_files): return True` |
| 5 | この関数の意図は | target_filesなしuniversalの全cmdへの漏れ防止。target_filesあり=関連性ありと仮定 |
| 6 | その仮定は正しいか | **NO**。target_files存在≠タスクファイルとマッチ。L506(report_merge.sh)がcmd_3124(exact)に注入 |
| 7 | **根因** | **L4556がtarget_filesの存在チェックのみでマッチングを行っていない** |

## 根因コード (deploy_task.sh L4551-4566)

```python
def _universal_without_target_files_is_relevant(lesson, l_tags):
    lesson_target_files = lesson.get('target_files', [])
    if isinstance(lesson_target_files, str):
        lesson_target_files = [lesson_target_files]
    if any(str(p).strip() for p in lesson_target_files):
        return True  # ← ★ここが根因: 存在チェックのみ、マッチングなし
    # ... (以降はtarget_filesなしの場合の語彙関連チェック)
```

## 影響パス

1. universal教訓(tags:[universal])がL4620-4622で`universal_lessons`に追加される
2. `_tf_excluded_ids`はtag_candidatesにのみ適用(L4646-4654)、universal_lessonsには未適用
3. universal_lessonsはMAX_UNIVERSAL=1で1件注入(L4794-4798)
4. target_filesフィルタをバイパスした無関係教訓が毎タスク1件注入される

## Top NOT_USEFUL教訓の内容

| Lesson | target_files | 内容 |
|--------|-------------|------|
| L506 | report_merge.sh | WSL2短命YAML走査はmawk優先 |
| L499 | gate_ninja_workaround_rate.sh | /tmp固定パスのキャッシュファイルがbats並列で混在 |
| L507 | archive_completed.sh | gate_statusキャッシュはreportファイル数安定時のみ有効 |
| L505 | cli_profiles.yaml | line-based YAML scannerのsibling section空行問題 |
| L503 | dashboard_auto_section.sh | knowledge_metrics.shのキャッシュミス問題 |
| L495 | scripts/xxx.sh | SCRIPT_DIR string ops化パターン |

全てinfra/universal + 特定スクリプト限定。タスクが別スクリプト対象でも注入される。

## 修正案

```python
# L4556: 存在チェック → マッチングチェックに変更
if any(str(p).strip() for p in lesson_target_files):
    return _target_files_match(lesson_target_files, _all_task_files)
```

1ファイル・1行変更。deploy_task.shはscripts/配下でD0適用可能だが影響範囲が大きいためcmd起票を推奨。

## 推定効果

NOT_USEFUL 95件のうち、universal bypass経路が大半を占める。修正後の推定有効率:
- 現行: 34.0% (49/144)
- 修正後: universal bypass除去で NOT_USEFUL が大幅減少 → 推定 60-70%+

## 追加成果(同セッション)

- D0修正: speed_bottleneck設計書の数値計算エラー(99.1%→39.4%) commit a60f8a0f
- セマンティック監査: 7スクリプト×5カテゴリ = P0 0件。hot path invariant系変更は適切

## 因果リンク

- → [[LG027]] referenced率≠useful率の具体的根因
- → [[cmd_2685]] useful率閾値設定(baseline確立)
- → [[deploy_task.sh]] 教訓注入エンジン
