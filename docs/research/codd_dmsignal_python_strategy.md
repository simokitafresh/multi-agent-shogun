# DM-Signal CoDD適用 方針設計書

<!-- created: 2026-04-16 -->
<!-- author: shogun -->
<!-- status: approved (gunshi review APPROVE 2026-04-16 19:16) -->

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
| B(中) | バッチ処理 | あり(スケジュール実行) | パリティ確認必須 | fullrecalculate, recalculate_fof(※FoFパリティ確認AC必須) |
| C(高) | 本番API | 直接影響 | ステージング検証必須 | backend/app/ |

### 対象外(当面)
- レベルC(本番API): リスクが高く、速度改善の複利効果も限定的(Renderのレスポンス時間がボトルネック)
- フロントエンド: Next.js。CoDDのPython適用対象外

### 具体的対象ファイル(2026-04-16確認)

**レベルA(研究) — 高速化対象候補(行数順)**

| 優先 | ファイル | 行数 | 用途 | 備考 |
|------|---------|------|------|------|
| A-1 | `scripts/analysis/grid_search/grid_search_metrics_v2.py` | 2300 | GS共通エンジン | 全GS実行のボトルネック |
| A-2 | `outputs/scripts/l1_alm_wf_engine.py` | 2546 | ALM WFエンジン | 56ブロックで使用 |
| A-3 | `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py` | 2645 | 研究エンジン | 4メトリクス計算 |
| A-4 | `scripts/analysis/grid_search/run_077_*.py` | 1352-1880 | 忍法別GS | 7本。共通部分が多い |
| A-5 | `scripts/analysis/grid_search/gs_benchmark.py` | 1045 | GSベンチマーク | 速度計測用 |
| A-6 | `outputs/scripts/champion_selector.py` | — | チャンピオン選出 | 選出ロジック |

**レベルB(バッチ) — 本番影響あり。慎重対応**

| 優先 | ファイル | 行数 | 用途 | 備考 |
|------|---------|------|------|------|
| B-1 | `backend/app/jobs/recalculate_fast.py` | 2960 | fullrecalculate本体 | 480s。最大改善対象 |
| B-2 | `backend/app/jobs/recalculate_fof.py` | 1187 | FoF再計算 | FoFパリティ必須 |
| B-3 | `backend/app/jobs/generators/trade_performance.py` | 633 | トレード計算 | fullrecalc内部 |
| B-4 | `backend/app/jobs/generators/monthly_returns.py` | 412 | 月次リターン | fullrecalc内部 |

**Phase 1検証対象(100行以下のレベルA)**

| ファイル | 行数 | 用途 |
|---------|------|------|
| `outputs/scripts/cmd_1847_neighbor_analysis.py` | ~100 | パラメータ近傍分析 |
| `outputs/scripts/cmd_1869_2x2_factor_analysis.py` | ~100 | 2×2因子分析 |
| `backend/scripts/compare_snapshots.py` | ~100 | スナップショット比較 |

### 実行順序

```
Phase 1: Phase1検証対象(上記3本から1本)でcodd extract→implement通す
Phase 2: レベルA全量cProfile計測 → 優先順位リスト
Phase 3: A-1(GS共通エンジン)から着手 → 全GSの速度に効く
Phase 4: B-1(fullrecalculate)に慎重適用
```

## §3 CoDDワークフロー(各Phaseの具体的手順)

DM-Signalは既存コードの改善 = **ブラウンフィールド**系統を使用。

### Phase 1: CoDDのPython適用検証(1本)

```
Step 0: codd.yaml作成(DM-Signal側に配置。ai_command: generate=Opus, implement=Codex)
        → CoDDがプロジェクト設定を認識するための前提条件(軍師指摘2026-04-16)
Step 1: codd extract <対象.py>
        → 既存コードから構造・依存を抽出。Pythonで動くか確認
Step 2: codd require "速度改善: ボトルネックを特定し高速化する"
        → 改善要件を定義
Step 3: codd plan
        → 要件+抽出結果から改善計画を生成
Step 4: codd generate
        → 計画に基づき設計書群を生成
Step 5: codd validate
        → 設計書の整合性を検証
Step 5.5: codd review --feedback
        → 設計書品質を確認(軍師指摘: validate→implement間に必要)
Step 6: codd implement
        → 設計書に基づきコード変更を実装
Step 7: codd measure
        → 健全性スコアを計測
Step 8: 手動計測 — time python <対象.py> でbefore/after比較
Step 9: 出力同一性確認 — diff before_output after_output
```

**判断ポイント**: Step 1-7が全て通れば本格適用。通らなければフォールバック↓

### フォールバック(CoDDが動かない場合)

```
Step 1: 手動spec作成(cProfile結果+ボトルネック分析+改善方針)
Step 2: 手動実装(specに基づく)
Step 3: before/after計測+出力同一性確認
        → インフラbash改善と同じ方式
```

### Phase 2: 全量プロファイリング

```
Step 1: 対象スクリプト一覧(§2のレベルA全量)
Step 2: 各スクリプトを cProfile -s cumtime で計測
Step 3: ホットスポット(上位5関数)を記録
Step 4: 優先順位リスト作成(実行時間×使用頻度)
        → docs/research/に成果物保存
```

### Phase 3: レベルA改善(6並列)

```
各スクリプトに対して:
Step 1: cProfile でbefore計測+ホットスポット特定
Step 2: codd extract <対象.py>
Step 3: codd require "ホットスポットXXを高速化。目標: YYms→ZZms"
Step 4: codd plan → generate → validate → review --feedback
Step 5: codd implement
Step 6: 出力同一性確認(diff)
Step 7: time計測でafter確認
Step 8: codd measure
Step 9: codd_refactor_registry.mdに結果追記
```

### Phase 4: レベルB改善(直列・慎重)

```
Phase 3のStep 1-9に加えて:
Step 10: コード変更パリティ確認 — 現在の本番コードの計算結果と修正後コードの計算結果が一致すること
          一致の定義(殿裁定2026-04-16):
          (a) 全期間の保有ポジションの完全一致(signalsテーブル)
          (b) 全期間のmonthly returnの完全一致(monthly_returnsテーブル)

          ■ MTD/初期月問題(2026-04-16現物確認で発覚):
          snapshot_tables.pyはmonthly_returns/signalsを丸ごとダンプ。
          MTD(当月進行中)の行は日次で変動するため、before/after間で完全一致が構造的に不可能。
          対策: compare時にMTD月(当月)を除外して比較する。
          手順:
            (i) before snapshot取得: python3 scripts/snapshot_tables.py --label before --skip-recalc
            (ii) コード修正+deploy
            (iii) after snapshot取得: python3 scripts/snapshot_tables.py --label after
            (iv) compare時にMTD行を除外: python3 scripts/compare_recalc_results.py snapshots/before snapshots/after
                 → compare_recalc_results.pyにMTD除外オプション追加が必要(未実装。Phase 4前に実装)
          初期月: PF運用開始月も不完全データの可能性。compare時に初期月フラグがある場合は除外検討
          浮動小数点: tolerance=1e-10(compare_recalc_results.py既定値)
Step 10.5: dry run(計算のみ・書込みなし)で出力検証(軍師推奨。dry runフラグの実装有無は要確認)
Step 11: 本番deploy(Render)
Step 12: fullrecalculate実行
Step 13: 本番パリティ再確認
Step 14: 異常時 → git revert + 再deploy + fullrecalculate + parity再確認
```

### CoDDコマンドの実行環境

```bash
# venv
source /home/simokitafresh/.codd-venv/bin/activate

# DM-Signal作業ディレクトリ
cd /mnt/c/Python_app/DM-signal

# codd.yaml設定(ai_command)
# generate=Opus, implement=Codex(大量コード生成向き)
```

## §4 段階的適用計画

| Phase | 内容 | 成功条件 | 判断ポイント |
|-------|------|---------|-------------|
| 1 | CoDDのPython適用を1本検証(レベルA小スクリプト。候補: oneshot/内の100行以下) | 全工程が通り、実測で速度改善を確認 | CoDDが使えるか/フォールバックか |
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
| LG028: スケーラビリティ推定の内部ループ計上 | Python計算スクリプトこそ該当。推定時は関数内部まで追跡(軍師指摘) |
| WSL2 I/Oパターン(Defender逆効果) | PythonのファイルI/Oにも適用。大量CSV読み書き時に影響(軍師指摘) |

## §9 リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| CoDDがPythonで動かない | Phase 1で判明 | 手動spec+手動実装にフォールバック |
| 速度改善が出力を変える | データ汚染 | 出力同一性のdiff確認をAC必須化 |
| fullrecalculate改善で本番データ不整合 | 重大 | パリティ確認+ロールバック手順 |
| venv/依存の不整合 | 実行不能 | backend/.venvを使用。pip freeze確認 |
