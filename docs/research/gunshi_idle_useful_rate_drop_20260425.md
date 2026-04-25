# 教訓有用率低下の根因分析

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-25
- トリガー: idle自走 — 直近30報告のlessons_useful計測

## §1 観測

| 計測時点 | 有用率 | ソース |
|---------|--------|--------|
| GP-218前 | 9.9% | S230 |
| GP-218後(掲示板) | 55.3% | blt_20260425_032903 (2002件全体) |
| **直近30報告** | **7.7%** | 本計測 (142件) |

## §2 根因

直近30報告はsaizo(10.6%)とtobisaru(0.0%)のみ。tobisaruが38件全NOT_USEFUL。

### tobisaru NOT_USEFULの内訳

| 注入教訓ID | tobisaruのタスク | 関連性 |
|-----------|----------------|--------|
| L229 | batsテスト速度 | Stop Hook設計 → 無関係 |
| L283 | batsテスト速度 | PostToolUse skip誤検知 → 無関係 |
| L512 | karo_workaround_log引数追加 | gate_loop_health insight dedup → 無関係 |
| L636 | daily_etl構造調査 | recalculate MR/FoF → 無関係 |

tobisaruの評価は正確。reasonは具体的で根拠あり。問題は注入ロジック。

### 注入ロジックの構造

deploy_task.sh L2290-2292:
```python
_tag_fallback = [(helpful_count, id, summary) for l in tag_candidates]
_tag_fallback.sort(key=lambda x: -x[0])
scored = [(1, lid, summ) for hc, lid, summ in _tag_fallback[:MAX_INJECT]]
```

tag_fallbackはhelpful_count降順で上位3件を注入。**タスク内容との関連性を考慮しない**。
521教訓中target_filesなし290件(56%)が全タスクに均等に注入される構造。

## §3 因果鎖

target_filesなし教訓290件→tag_fallback(helpful_count降順)→タスク無関係な教訓がtop3に入る→忍者がNOT_USEFUL→有用率低下→教訓注入の信頼性低下→忍者が教訓を読まなくなる=負の複利

## §4 改善案

| # | 案 | 複利効果 | 実装規模 |
|---|---|---------|---------|
| 1 | tag_fallbackにコマンド/target_pathキーワードマッチスコア加重 | 高 | 中(20行) |
| 2 | target_filesなし教訓のfallback注入を廃止(target_filesマッチのみ注入) | 高 | 小(5行) |
| 3 | 注入上限をMAX_INJECT=3→1に削減(品質重視) | 中 | 小(1行) |

**推奨: 案2**。理由: 関連性のない教訓を注入しないことが最もシンプルで効果的。target_filesなし教訓はuniversal教訓(全タスクに適用)として別枠で注入するか、target_files追加を促進する。
