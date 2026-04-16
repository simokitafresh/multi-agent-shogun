# DM-Signal CoDD適用 方針設計書

<!-- created: 2026-04-16 -->
<!-- author: shogun -->
<!-- status: draft → gunshi review待ち -->

## §1 目的

DM-Signal(Python)の計算重スクリプトをCoDDパイプラインで高速化する。
本番稼働中のため安全性最優先。インフラbash改善(32本)で得た知見を活かす。

### 背景
- CoDDのbash implementは不適合(実証済み: memory/tool_codd_lessons.md)
- Pythonは全工程(spec→plan→generate→validate→implement)が使える見込み
- DM-Signalのfullrecalculate: 3566s→480s(86.5%改善済み)だがまだ8分
- GSエンジン等の研究スクリプトも計算量が大きい

## §2 対象分類(安全度)

| レベル | 対象 | 本番影響 | リスク | 例 |
|--------|------|---------|--------|-----|
| A(安全) | 研究スクリプト | なし | 自由に改善可 | GS, oneshot/*, alm_research/, cmd_1934系 |
| B(中) | バッチ処理 | あり(スケジュール実行) | パリティ確認必須 | fullrecalculate, recalculate_fof |
| C(高) | 本番API | 直接影響 | ステージング検証必須 | backend/app/ |

### 対象外(当面)
- レベルC(本番API): リスクが高く、速度改善の複利効果も限定的(Renderのレスポンス時間がボトルネック)
- フロントエンド: Next.js。CoDDのPython適用対象外

## §3 CoDDのPython適用可否

### 検証項目
1. `codd extract` がPythonプロジェクト構造を正しく抽出できるか
2. `codd plan` → `generate` で設計書が生成されるか
3. `codd implement` がPythonコードの修正を正しく行えるか
4. `codd validate` が変更の整合性を検証できるか

### 検証方法
- レベルAの小スクリプト(100行以下)で1本通す
- 全工程が通れば本格適用。通らなければ手動spec+手動実装(インフラと同方式)にフォールバック

## §4 段階的適用計画

| Phase | 内容 | 成功条件 | 判断ポイント |
|-------|------|---------|-------------|
| 1 | CoDDのPython適用を1本検証(レベルA小スクリプト) | 全工程が通り、実測で速度改善を確認 | CoDDが使えるか/フォールバックか |
| 2 | レベルA全量プロファイリング+改善(cProfile) | 対象一覧+優先順位リスト作成 | インフラbashと同じ流れ |
| 3 | レベルA上位スクリプトをCoDD改善(6並列) | before/after計測で改善確認 | 改善率の実績蓄積 |
| 4 | レベルB(fullrecalculate)に適用 | パリティ確認PASS+速度改善 | 本番影響の安全性確認 |
| 5 | 結果評価+次の判断 | — | 殿の裁定 |

### Phase間の依存
- Phase 1→2: CoDDが使えると確認してからプロファイリング
- Phase 2→3: プロファイリング結果で優先順位を決めてから改善
- Phase 3→4: レベルAで十分な実績を積んでからレベルBに進む
- **Phase間を飛ばさない**(1ステップずつ確認してから次へ。shogun.md §2 無知の知)

## §5 本番防御層

| 防御 | レベルA | レベルB |
|------|---------|---------|
| PI整合確認 | AC推奨 | AC必須 |
| 既存テスト全PASS | AC必須 | AC必須 |
| パリティチェック(parity_check.sh) | 不要 | AC必須(before/after) |
| fullrecalculate後の再確認 | 不要 | AC必須 |
| 本番deploy | 不要 | 直列配備(DB排他ルール) |
| ロールバック手順 | git revert | git revert + 再deploy + fullrecalculate |

### ロールバック手順(レベルB)
1. `git revert <commit>` で変更を戻す
2. `git push` → Render自動deploy
3. fullrecalculate実行で本番データを再計算
4. parity_check.shで正常復帰を確認

## §6 ACテンプレート(レベル別)

### レベルA(研究スクリプト)
```yaml
acceptance_criteria:
  - id: AC1
    description: "cProfileでボトルネック特定。候補2つ以上→spec記録"
  - id: AC2
    description: "実装。機能変更なし。出力の同一性を確認(diff)"
  - id: AC3
    description: "after計測。before比で改善を数値で示す"
  - id: AC4
    description: "既存テスト全PASS。codd_refactor_registry.mdに結果追記"
```

### レベルB(バッチ処理)
```yaml
acceptance_criteria:
  - id: AC1
    description: "cProfileでボトルネック特定。候補2つ以上→spec記録"
  - id: AC2
    description: "実装。機能変更なし"
  - id: AC3
    description: "既存テスト全PASS+出力同一性確認(diff)"
  - id: AC4
    description: "after計測。before比で改善を数値で示す"
  - id: AC5
    description: "parity_check.sh実行。本番パリティ確認PASS"
  - id: AC6
    description: "codd_refactor_registry.mdに結果追記"
```

## §7 計測方法

| 手法 | 用途 | コマンド例 |
|------|------|-----------|
| cProfile | 関数レベルのホットスポット | `python -m cProfile -s cumtime script.py` |
| line_profiler | 行レベルのボトルネック | `@profile` デコレータ + `kernprof` |
| time | 全体実行時間のbefore/after | `time python script.py` |
| memory_profiler | メモリ使用量 | `@profile` + `mprof run` |

### 注意
- DM-Signalのvenv(backend/.venv)を使用すること
- DB接続が必要なスクリプトは本番DBへの読み取りのみ(書き込み禁止)
- 研究スクリプトはローカルCSV/キャッシュで実行可能なものを優先

## §8 知見の活用(インフラbash改善からの移管)

| インフラでの学び | DM-Signal適用 |
|----------------|---------------|
| LS035: 事前100%は怠慢。3層防御 | 事前(cProfile)+事後(パリティ)+診断(教訓化) |
| LS036: 道具の目的と作業性質を照合 | CoDDの各ステップが対象スクリプトに合うか判断 |
| Check 22: ステップ数vsAC数 | 同様に適用 |
| サブシェル→awk化パターン | Python版: subprocess→in-process, pandas→numpy |

## §9 リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| CoDDがPythonで動かない | Phase 1で判明 | 手動spec+手動実装にフォールバック |
| 速度改善が出力を変える | データ汚染 | 出力同一性のdiff確認をAC必須化 |
| fullrecalculate改善で本番データ不整合 | 重大 | パリティ確認+ロールバック手順 |
| venv/依存の不整合 | 実行不能 | backend/.venvを使用。pip freeze確認 |
