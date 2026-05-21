<!-- last_updated: 2026-04-09 -->
# Silent Fallback残存分析 — cmd_1483偵察後アクション (軍師)
# 2026-03-29T17:12 | **HIGH 11/11修正完了** | 本番検証PASS(signal=453,663) | Medium注目SF-026修正済

## 修正済み

| ID | 内容 | cmd | commit |
|----|------|-----|--------|
| SF-001 | Pipeline例外→Cash差替え廃止 | cmd_1484(才蔵) | ba121710 |
| SF-003 | advisory lock fail-open→fail-closed | cmd_1484(飛猿) | f3bbb325 |
| SF-002 | MDD→0.0廃止→None返却+logger.error | cmd_1485(疾風) | 0c2a808b |
| SF-025 | cumulative_return or 1.0廃止→None透過 | cmd_1485(影丸) | 996b014b |
| SF-023 | FoF月中prev_signal or Cash廃止 | cmd_1487(才蔵) | 3454b123 |
| SF-024/035 | price_ratio Cash 4箇所廃止 | cmd_1487(小太郎) | 3454b123 |
| PI-018 | Silent Fallback免疫系構築 | cmd_1486(半蔵) | 25cc852 |

## 残存HIGH — cmd-sized 4グループ

### Group A: Cash chain残存 (SF-023 + SF-024 + SF-035) — 現物確認済み
- **影響**: シグナル欠損→全レイヤーCash汚染
- SF-023: `recalculate_fof.py L766` prev_signal or Cash
- SF-024/SF-035: `price_ratio_calculator.py` 4箇所の3段fallback:
  - L1236: `get_signal_changes_in_period()` — initial_sig.holding_signal or signal or "Cash"
  - L1244: 同関数 — sig.holding_signal or signal or "Cash"
  - L1316: `calculate_segmented_return()` → `resolve_holding_to_tickers()` 内
  - L1668: `_resolve_holding_to_allocation()` → `resolve_holding()` 内
- **cmd_1481の影響範囲**: forward-fill除去(L991-998)のみ。上記4箇所は未修正。
  L1009(`expand_portfolio_to_tickers`)はCash fallbackなし(None返却)→正しい設計。
- **⚠️ 設計判断ポイント**: 4箇所はDB上のsignal=NULLケースへの防御。SF-001(計算エラーのCash偽装)とは性質が異なる。
  missing signal→Cash保有は**安全側の合理的デフォルト**とも言える。ただし嘘(実態不明なのにCash表示)。
  修正方針は「ERROR+skip」vs「Cash維持+ログ強化」の二択で将軍/殿判断が必要。
- **推奨**: 1cmd、忍者2名(fof側+prc側)。修正前にDB実態確認(signal=NULLのレコードが存在するか)

### Group B: SPY SSOT (SF-022) — 現物確認済み(軍師偵察 15:30)
- **影響**: benchmark_ticker未設定PFが無言でSPY基準に
- **実際は7箇所**(当初4→偵察で3追加):
  - L261: `recalculate_fof.py` `_recalculate_fof_history()` — if bench else "SPY"（all_tickers_for_monthly収集）
  - L305: `recalculate_fof.py` — `Price.symbol == "SPY"`（月末営業日カレンダー。固定値として正当。コメント追加のみ）
  - L315: `recalculate_fof.py` — `config.get("benchmark_ticker") or "SPY"`（all_benchmarks収集）
  - L495: `recalculate_fof.py` — 3段チェーン `or "SPY"`（ベンチマーク価格取得）
  - L1063: `recalculate_fof.py` — `or "SPY"`（MonthlyReturn生成時）
  - L68: `monthly_returns.py` — `config.get("benchmark_ticker") or "SPY"`（MonthlyReturn生成内部）
  - L1061: `metrics_calculator.py` — `or "SPY"`（APIレスポンスのbenchmark_ticker値）★新発見
- **DB**: `PortfolioConfigSnapshot.benchmark_ticker = Column(String(20), nullable=True)`。DEFAULT_BENCHMARK定数は**未定義**
- **修正方針**: `constants.py`に`DEFAULT_BENCHMARK_TICKER = "SPY"`定義→6箇所統一(L305はコメントのみ)
- **推奨**: 1cmd、忍者1名。定数化+6箇所or除去+L305コメント。テストは既存test_benchmark_unification_057.pyを拡張

### Group C: メトリクス偽装 (SF-002 + SF-025) — 現物確認済み
- **影響**: ユーザーにリスク0%/リターン0%と誤表示
- SF-002: `metrics_calculator.py L503-505` 関数`calculate_metrics()`
  - コード: `except Exception: p_mdd = 0.0; p_mdd_open = 0.0`
  - 4関数失敗(calculate_mdd_from_price×2, calculate_drawdowns_from_price×2)を一括catch
  - 消費先: L536 `add_metric("Maximum Drawdown", p_mdd, ...)` → API応答
  - 二次影響: L541-551 MDD日付解決で`mdd_val == 0`→"N/A"判定(0.0だとNone区別不能)
  - 修正案: `p_mdd = None` + add_metric/APIでnull返却
- SF-025: `performance.py L125` 関数`get_portfolio_performance()`
  - コード: `sanitize_float(row.cumulative_return) or 1.0`
  - sanitize_float: NaN/Inf→None, 正常値→float
  - **致命的バグ**: `sanitize_float(0.0)→0.0`(falsy)→`0.0 or 1.0→1.0`。100%損失が0%表示に
  - DB定義: `cumulative_return = Column(Float, nullable=False)` — NaN/Infが到達可能
  - テスト: fallbackケースのテスト一切なし
  - 修正案: `v = sanitize_float(row.cumulative_return); ... v if v is not None else None` — null返却してfrontendで"N/A"表示
- **推奨**: 1cmd、忍者1名。None返却+frontend null handling。テスト2-3件追加

### Group D: MonthlyReturn生成耐障害性 (SF-004 + SF-005 + SF-006) — 現物確認済み(軍師偵察 15:30)
- **影響**: PF個別障害の静かなデータ欠損
- SF-004: `recalculate_fast.py L1697-1700` MonthlyReturn生成fail→skip
  - `except Exception as e: logger.warning(...)` — **ログあり**。正当なcontinueパターン（個別PF障害で全体を止めない）
  - 改善: 失敗PFカウント集計(`failed_pfs`リスト)→Phase5 FoF依存チェックに伝播
- SF-005: `recalculate_fof.py L1086-1088` FoF MonthlyReturn fail→skip
  - `except Exception as e: logger.warning(...)` — **ログあり**。条件付き正当（FoF of FoF依存関係で連鎖失敗リスク）
  - 改善: 後続FoF依存関係の明示的管理（失敗FoFのIDを伝播→依存FoFをスキップ）
- **SF-006**: `monthly_trade_calculator.py L273-279` bulk load fail→empty — **★最危険: ログなし**
  - `except Exception:` — 裸のexcept、logger出力なし、変数リセットしてper-iteration fallback
  - 5操作(business_days/signal_dates/signals/prices/cache)が一括catchで全滅→原因特定不可
  - fallback時: N倍遅延(120ヶ月×個別query)→API timeout可能性
  - **修正必須**: `logger.warning(f"Bulk load failed: {e}")` + `bulk_load_failed`統計
- **推奨**: 1cmd、忍者1名。SF-006のログ追加が最優先。SF-004/005は失敗カウント集計追加

## 優先順位 (2026-03-29 15:30更新)

1. ~~**Group A** (Cash chain)~~ → **修正済み** (cmd_1484+1487) GATE CLEAR
2. ~~**Group C** (メトリクス偽装)~~ → **修正済み** (cmd_1485) GATE CLEAR
3. ~~**Group B** (SPY SSOT 7箇所)~~ → **修正済み** (cmd_1488 疾風) commit ab039ff1。KC: L168は別パターン(直接add)
4. ~~**Group D** (MonthlyReturn耐障害性)~~ → **修正済み** (cmd_1489 半蔵) commit 1283f24e。本番検証PASS

**全HIGH修正完了 + 本番検証PASS**。cmd_1484-1489の6cmd、忍者延べ10名で38箇所中11 HIGH全完了。残りはrecalculate_fast.py:1541(新発見Cash fallback)とMedium/Low。

## ~~Medium注目: SF-026 rebalance_trigger SSOT~~ → **修正済み** (cmd_1488 飛猿) commit 1a57eb0e

Group Bと同一パターン。**8箇所以上**の`or "monthly"`フォールバック:
- `monthly_trade_calculator.py L619-632` `_get_rebalance_trigger()` — or "monthly" + 無効値catch→"monthly"（★既にヘルパー関数化済み。これをutils化して全箇所統一が最善）
- `recalculate_fof.py L381` — `get('rebalance_trigger', 'monthly') or 'monthly'`（二重fallback、冗長）
- `recalculate_fof.py L559` — 同上パターン
- `recalculate_fast.py L1476` — `portfolio.rebalance_trigger or "monthly"`
- `monthly_returns.py L70` — `config.get("rebalance_trigger") or "monthly"`
- `trade_performance.py L19` — `config.get("rebalance_trigger", "monthly")`
- `canonical_as_of.py` — `config.get("rebalance_trigger", "monthly")`
- `db_admin.py` / `debug.py` — API表示用（影響低だが統一対象）
- `maintenance.py` — NULL時にconfig直接書込み（マイグレーション的修正）
- DB: `PortfolioConfigSnapshot.rebalance_trigger = Column(String(30), nullable=True)`、デフォルト値なし
- Pydantic: `default="monthly"` あり。`ALLOWED_REBALANCE_TRIGGERS`セット定義済み(`api/portfolios.py L43-50`)
- **修正方針**: `_get_rebalance_trigger()`をutils化→8箇所以上統一。DB NULLはPydanticデフォルトと一致するため実害低

## ★新発見: recalculate_fast.py:1541 signal = "Cash" (gate_silent_fallback.sh検出)

- **軍師PI-018自動検出ゲートが発見**（cmd_1483の38箇所リストにない可能性）
- `recalculate_fast.py L1541`: OPT-E date miss fallback失敗時 → `signal = "Cash"` + `pm_data = {"error": str(e)}`
- logger.errorあり、だが**signal = "Cash"代入はSF-001と同一パターン**（例外→Cash偽装）
- **影響**: OPT-E最適化のfallbackのfallback（二重fallback）。発動頻度は低いが構造的にNG
- **推奨**: Group D修正cmdに含める（+1箇所追加）。None代入+skipが妥当

## PI-018自動検出ゲート (gate_silent_fallback.sh)

軍師が自走サイクルで構築。89箇所のexcept Exceptionから正当パターンを除外し、6 SUSPECTを検出。
うち真のPI-018違反は2件（recalculate_fast.py:1541 + monthly_trade_calculator.py:274）。
diffモード(`--diff <commit>`)で新規コードのみの検査も可能。

## 残りMedium (9件) / Low (17件)

HIGH消化完了後に分析予定。
