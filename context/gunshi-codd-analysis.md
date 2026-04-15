<!-- Vercel圧縮: 2026-04-13 295行→索引化 -->
# CoDD (Coherence-Driven Development) vs 将軍システム分析 (索引)

> 詳細設計書 → `docs/research/gunshi-codd-analysis.md` (295行)
> 軍師分析 2026-03-29（v4: 実コード比較+定量データ検証済み）

## 結論

| 項目 | 結論 |
|------|------|
| 依存グラフ | 解くべき問題(context整合性破壊)がゼロ件。ROI不成立 |
| AIプロンプト設計 | 現時点で我が軍が上(deploy_task.sh 99関数 vs generator.py 単機能) |
| 出力サニタイゼーション | 問題ドメインが異なる(CoDD=メタ解説汚染 / 我が軍=YAML整合性) |
| 吸収済みパターン | `@generated-from`トレーサビリティ(§4)。CS観点プロトコル(§8.8→LG013) |

## +1改善候補(未着手・旧)

| 改善 | 優先度 | 参照 |
|------|--------|------|
| hook出自コメント追加(追跡率11%→100%) | 低 | → §8.3 |
| gate_fire_log.yamlにgate_script名追加 | 中 | → §8.3 |

## #3-#5 SWE-bench知見の適用分析 (2026-04-16)

→ `docs/research/gunshi_codd_swebench_application_20260416.md` (全文)

### 核心発見
- **情報注入=退化、思考構造の強制=退化しない**(#3-#5)。殿の「原理だけが無限の事象に対抗できる」と同根
- related_lessons有用率16%(84%無用)。10件注入は量過剰。IF-THEN形式13%のみ(86%が直接指示=情報注入)
- 忍者レベルでL3(診断推論)が不在。gate BLOCK時のFIX hintは「答え」を教えている

### 改善4案(優先順)
1. **Diagnose Step**: gate BLOCK時に「なぜBLOCKされたか1行書け」を強制(原理1行、複利最大)
2. **lessons絞り込み**: 10→3件、IF-THEN形式変換(有用率16%→40%+予測)
3. **DIVERGENT**: 同一理由2回連続BLOCK→仮説転換強制
4. **Session State**: タスクレベル失敗履歴(/clear跨ぎカルテ)

## 軍師教訓(7サイクル)

→ `docs/research/gunshi-codd-analysis.md` §7-§8.8
- CS観点プロトコル(LG013)の起源。殿指導下7サイクル。自己検出率0%→gate化
