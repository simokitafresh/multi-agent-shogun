# DM-Signal CoDD適用 方針設計書

<!-- created: 2026-04-16 -->
<!-- author: shogun -->
<!-- status: approved (gunshi review APPROVE 2026-04-16 19:16) -->

## §0 前提条件(忍者含む全員必読)

### CoDDとは
おしお殿(@shio_shoppaize)作の設計書パイプラインツール。既存コードから構造を抽出し、設計書を生成し、設計書に基づいて実装する。設計整合性を人手でなくツールで強制する。

### 環境(venv使い分けルール — 同時activate不可)

| 操作 | 使うvenv | activateコマンド |
|------|---------|----------------|
| coddコマンド(extract/measure) | codd-venv | `source /home/simokitafresh/.codd-venv/bin/activate` |
| スクリプト実行(cProfile/time/python) | DM-Signal venv | Windows: `.venv/Scripts/python.exe` / WSL: `backend/.venv/bin/activate` |

**注意:** Phase 1で`backend/.venv`前提が不正確と判明。実際の検証実行系は`.venv/Scripts/python.exe`(cmd_1986 assumption_invalidation)。WSLからの実行は`backend/.venv`で可。

**Step内で切り替える場合は`deactivate`してから次のvenvをactivate。**

```bash
cd /mnt/c/Python_app/DM-signal

# coddコマンド(extract/measure)実行時
source /home/simokitafresh/.codd-venv/bin/activate
codd --version  # 1.8.0

# スクリプト実行時(切り替え)
deactivate
source /mnt/c/Python_app/DM-signal/backend/.venv/bin/activate
```

### codd.yaml(DM-Signal側に配置。Phase 1 Step 0で作成)
```yaml
# /mnt/c/Python_app/DM-signal/codd.yaml
project:
  name: dm-signal
  language: python
ai_command:
  generate: claude-opus-4-6
  implement: codex
```

### 参照先
- CoDDの詳細: `context/codd.md`
- CoDDスキル: `~/.claude/skills/codd/SKILL.md`
- インフラ改善実績: `docs/research/codd_refactor_registry.md`

### CoDDの利用範囲(Phase 1で確定)
- **使用可能(OSS版1.8.0):** `extract`(構造抽出), `measure`(健全性計測)
- **使用不可(codd-pro依存):** `review`, `implement`
- **不安定(手動介入要):** `plan`(AI出力XML混入), `generate`, `validate`(warning出る場合あり)
- **方式:** ハイブリッド = codd extract → 手動spec(cProfile) → 手動実装 → codd measure

### 各Stepの成功条件
- `codd extract`: `docs/` 配下に抽出ファイルが生成される
- `codd measure`: 0-100のスコアが出力される
- 手動spec: docs/research/にボトルネック分析+改善方針を記録
- 手動実装: コード変更+出力同一性(diff)確認
- before/after計測: time pythonで数値比較

## §0.5 進捗管理(Phase単位)

| Phase | 内容 | cmd | status | 結果 |
|-------|------|-----|--------|------|
| 1 | CoDDのPython適用検証(compare_snapshots.py, 224行) | cmd_1986 | **完了** | review/implementがcodd-pro依存で不可。extract→generate→validate→measureは使用可。**フォールバック: CoDDで設計書生成+手動実装** |
| 2 | レベルA全量cProfileプロファイリング | cmd_1987 | **完了** | Top3=simulate_pattern系(yotsume 5.3s/nukimi 3.4s/oikaze 2.2s per 100pat)。本番影響確認済み: GS研究用と本番は別実装→レベルA安全 |
| 3 | レベルA上位5本改善(cmd_1988-1992) | cmd_1988-1992 | **完了** | yotsume -99%/oikaze -99%/nukimi -63%/l1_alm_wf -81%/bunshin -78% |
| 4a | Phase 4準備(cProfile+ツール修正) | cmd_1994/1995/1996/karo_1995_fix | **完了** | cProfile計測完了(1527s,DB I/O 75%)。compare_snapshots修正+exclude-months追加 |
| 4b | Phase 4偵察(cache miss実測) | — | **次** | 軍師分析3点の計測(下記§4) |
| 4c | Phase 4実装(fullrecalculate改善) | — | 待機 | 偵察結果に基づきimpl cmd設計 |
| 5 | 結果評価+次の判断 | — | 待機 | — |

### §3.5 Phase 3知見 + Phase 4準備(2026-04-16軍師助言)

**Phase 3で確立した2パターン:**
- **パターンA(100x級):** precomputed masks直接利用(yotsume/oikaze)。monthly-onlyスクリプト限定。MomentumFilter.executeを排除
- **パターンB(3-5x):** キャッシュ+再利用(nukimi/l1_alm_wf/bunshin)。汎用。Phase 4はこちらが主適用先

**Phase 4準備3点(全完了 2026-04-17):**
1. ✅ **fullrecalculateのcProfile計測** — cmd_1994 GATE CLEAR。結果→§4
2. ✅ **snapshot比較ツール修正** — cmd_1995+cmd_karo_1995_fix GATE CLEAR。snapshot_recalc_results.py holding_signal保存+compare_snapshots.py列名統一
3. ✅ **--exclude-monthsオプション** — cmd_1996 GATE CLEAR。compare_recalc_results.pyに実装済み

**更新ルール:** cmd起票時にcmd列を記入。GATE CLEAR時にstatus+結果を更新。Phase間は前Phase完了後に次Phaseへ進む(飛ばさない)。

## §4 Phase 4: fullrecalculate改善(レベルB)

### §4.1 cProfile計測結果(cmd_1994, 2026-04-17)

→ 詳細: `docs/research/codd_fullrecalc_cprofile.md`

**総実行時間: 1527s** (dry-run: commit→flush+rollback)

| 層 | 時間(s) | 割合 | 解釈 |
|----|---------|------|------|
| DB I/O (SQLAlchemy/psycopg2) | 1057-1152 | **69-75%** | クエリ回数削減が最大レバレッジ |
| アプリ層計算 | 375-470 | 25-31% | Phase 3パターンB(キャッシュ+再利用)で対処 |

**アプリ層Top5:**

| # | 関数 | 時間(s) | 呼出回数 | ボトルネック |
|---|------|---------|----------|------------|
| 1 | `_generate_trade_performance` | 508 | 181 | L2/L3 trade計算。最大アプリ層ホットスポット |
| 2 | `expand_portfolio_to_tickers` | 384 | 1,168,384 | FoF展開。117万回呼出。signal_cache miss→DB SELECT |
| 3 | `_recalculate_fof_history` | 382 | 1 | L3 FoF全体。daily_loop/monthly_returns_gen/flush分散 |
| 4 | `calculate_trade_period_return` | 369 | 26,738 | trade-return集約。fallback発火→DB再取得の可能性 |
| 5 | `calculate_monthly_return` | 368 | 436 | 月次リターン計算 |

### §4.2 改善方針(軍師分析 gunshi_phase4_improvement_plan_20260417.md)

**Tier 1(高ROI):**
- **T1-1: signal_cache完全化** — expand_portfolio_to_tickers 117万回のcache miss→DB SELECT を削減。推定-100s
- **T1-2: fallbackゼロ化+NumPy化** — calculate_trade_period_returnのfallback発火をゼロにし、NumPy化。推定-95s

**Tier 2(中ROI):**
- **T2-2: dw_component_weightsバッチ化** — 104 FoF×日数のN+1を解消。推定-13s

**目標:** 480s → 280-320s(T1) → 250-280s(T2) → 150-200s(将来の並列化)

### §4.3 偵察計測項目(Phase 4b, 軍師助言3点)

偵察で計測すべき3点(impl cmdの精度を決定):
1. **signal_cacheのcache miss率** — 117万回のうちDB SELECTに落ちる割合。コード現物確認+プロファイルログから推定
2. **monthly_returns_mapの欠損パターン** — calculate_trade_period_returnのfallback発火率。fallback時にDB再取得か0返却か。コード現物確認
3. **FoF component_weights取得回数** — 104 FoF×日数でN+1発生有無。バッチ化ROI推定

偵察は1忍者で十分(コード読解+grep計測)。並列不要。

## §1 目的

DM-Signal(Python)の計算重スクリプトをCoDDパイプラインで高速化する。
本番稼働中のため安全性最優先。インフラbash改善(32本)で得た知見を活かす。

### 背景
- CoDDのbash implementは不適合(実証済み: memory/tool_codd_lessons.md)
- Python全工程は不可(Phase 1で確定: review/implementがcodd-pro依存)。**ハイブリッド方式**: extract+measure(CoDDが得意な部分)+手動spec+手動実装
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

### 本番影響確認(2026-04-16現物確認)

- GS研究用(run_077系): `simulate_pattern`関数がスクリプト内にインライン定義。依存=`gs_numba_kernels.py`(numba JIT)
- 本番(backend/app/): `MomentumFilterBlock`クラス。依存=`vectorized_momentum.py`(pandas/numpy)
- **共有モジュールなし。別々の実装。** run_077系の改善は本番に影響しない→レベルA安全

### 具体的対象ファイル(2026-04-16確認)

**レベルA(研究) — Phase 2 cProfile結果で優先順位更新**

| 優先 | ファイル | 行数 | cProfile結果(100pat) | ホットスポット |
|------|---------|------|-------------------|-------------|
| **1** | `run_077_yotsume.py` | 1566 | **5.3s** | simulate_pattern→MultiViewMomentumFilter.execute(83%) |
| **2** | `run_077_nukimi.py` | 1731 | **3.4s** | simulate_pattern→SingleViewMomentumFilter.execute |
| **3** | `run_077_oikaze.py` | 1352 | **2.2s** | simulate_pattern→MomentumFilter.execute+numpy.isclose |
| 4 | `l1_alm_wf_engine.py` | 2546 | 0.5s(2列subset) | reconstruct_alm_returns+metric再計算 |
| 5 | `run_077_bunshin.py` | 809 | 2.9s(full) | simulate_pattern |
| 6 | `compare_snapshots.py` | 251 | 4.4s | compare_records(補助ツール) |
| 7-9 | `run_077_kasoku_*/kawarimi.py` | 1537-1880 | 0.006-0.008s | 既に高速。後回し |
| 10 | `champion_selector.py` | 278 | 0.17s | CSV fallback load。後回し |
| 計測不能 | `grid_search_metrics_v2.py`, `gs_benchmark.py`, `metrics_research_engine.py` | 1045-2645 | DB fixture/adapter不足 | Phase 3完了後に再挑戦 |

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

## §3 ハイブリッドワークフロー(各Phaseの具体的手順)

Phase 1検証結果: CoDDのOSS版(1.8.0)ではreview/implementがcodd-pro依存で不可。
**方式: codd extract(構造抽出) → 手動spec(cProfile) → 手動実装 → codd measure(健全性計測)**

### Phase 1: 完了(cmd_1986)

CoDDのPython適用を検証。extract/measure=使用可、review/implement=codd-pro依存で不可と確定。
health_score 88。詳細: `docs/research/cmd_1986_codd_phase1_report.md`

### Phase 2: 全量プロファイリング

```
Step 1: 対象スクリプト一覧(§2のレベルA全量)
Step 2: 各スクリプトを cProfile -s cumtime で計測
Step 3: ホットスポット(上位5関数)を記録
Step 4: 優先順位リスト作成(実行時間×使用頻度)
        → docs/research/に成果物保存
```

### Phase 3: レベルA改善(6並列) — ハイブリッド方式

```
各スクリプトに対して:
Step 1: cProfile でbefore計測+ホットスポット特定
Step 2: codd extract <対象.py>(codd-venvで実行。構造・依存関係を自動抽出)
Step 3: 手動spec作成(cProfile結果+extract出力を参考にボトルネック分析+改善方針をdocs/research/に記録)
Step 4: 手動実装(specに基づく。機能変更なし)
Step 5: 出力同一性確認(diff)
Step 6: time計測でafter確認
Step 7: codd measure(codd-venvで実行。変更後の健全性スコア確認)
Step 8: codd_refactor_registry.mdに結果追記
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
          対策: compare時にMTD月(当月)+初期月を除外して比較する。
          MTD定義: date >= 当月1日の行(軍師推奨: is_mtdフラグまたはdate基準)
          初期月: PFごとに運用開始月が異なる。PF別のfirst_monthを特定して除外

          手順:
            (i) fullrecalculateスケジュールを一時停止(軍師指摘: before→after間に走ると結果が変わる)
            (ii) before snapshot取得: python3 scripts/snapshot_tables.py --label before --skip-recalc
            (iii) コード修正+deploy
            (iv) after snapshot取得: python3 scripts/snapshot_tables.py --label after
            (v) compare: python3 scripts/compare_recalc_results.py snapshots/before snapshots/after --exclude-months YYYY-MM,...
                → --exclude-monthsオプション追加が必要(未実装。Phase 4前に実装。MTD+初期月の両方に対応する汎用オプション)
            (vi) fullrecalculateスケジュール再開

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
| 1 | CoDDのPython適用検証(compare_snapshots.py) | extract/measure=可、review/implement=codd-pro依存で不可 | ハイブリッド方式確定(cmd_1986) |
| 2 | レベルA全量プロファイリング+改善(cProfile) | 対象一覧+優先順位リスト作成 | インフラbashと同じ流れ |
| 3 | レベルA上位スクリプトをCoDD改善(6並列) | before/after計測で改善確認 | 改善率の実績蓄積 |
| 4 | レベルB(fullrecalculate)に適用 | パリティ確認PASS+速度改善 | 本番影響の安全性確認 |
| 5 | 結果評価+次の判断 | — | 殿の裁定 |

### Phase間の依存
- Phase 1→2: Phase 1完了(ハイブリッド方式確定)。Phase 2に進む
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
| review/implementはcodd-pro依存 | Phase 1で確認済み(cmd_1986) | ハイブリッド方式: extract+measure(CoDD)+手動spec+手動実装 |
| 速度改善が出力を変える | データ汚染 | 出力同一性のdiff確認をAC必須化 |
| fullrecalculate改善で本番データ不整合 | 重大 | パリティ確認+ロールバック手順 |
| venv/依存の不整合 | 実行不能 | backend/.venvを使用。pip freeze確認 |
