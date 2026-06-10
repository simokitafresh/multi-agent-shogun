---
name: db-check
argument-hint: "[query_purpose|pf_id|table_name]"
description: |
  DM-Signal本番DBへの接続・クエリ・パリティ検証を標準化するスキル。
  接続方法・テーブルスキーマ・よく使うクエリをテンプレート化し、
  毎回の試行錯誤をゼロにする。
  TRIGGER: /db-check、DB確認 project:dm-signal、本番DB project:dm-signal、DM-Signal本番DB確認 project:dm-signal、holding_signal確認、monthly_returns確認、PF検索、パリティ検証
  DO NOT TRIGGER: DM-Signal以外の本番画面/スクショ/画面確認、DB設計変更（→実装cmd）、GS実行（→run_077）、fullrecalculate（→API直接）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにDB確認・パリティ手順起因のworkaroundが記録されない割合）"
allowed_projects: [dm-signal]
---

# /db-check — DM-Signal DB確認スキル

本番DB接続+クエリを標準化。試行錯誤ゼロで目的のデータに到達する。

---

## 接続方法（唯一の正解）

```python
import sys
sys.path.insert(0, '/mnt/c/Python_app/DM-signal/backend')
from app.db.database import create_db_engine
from sqlalchemy import text

engine = create_db_engine()
with engine.connect() as conn:
    rows = conn.execute(text("SELECT ..."), {'param': value}).fetchall()
```

**禁止**: psycopg2直接接続（DATABASE_URLのパースでDB名不一致エラー）、psqlコマンド（未インストール）

**理由**: `create_db_engine()`が`.env`読込+URL変換+接続プール設定を全て内包。

### 実行場所と文字コード

```bash
cd /mnt/c/Python_app/DM-signal/backend
PYTHONIOENCODING=utf-8 /mnt/c/Python_app/DM-signal/.venv/Scripts/python.exe your_check.py
```

- cwdは`/mnt/c/Python_app/DM-signal/backend`にする。`.env`相対読込の失敗を避ける。
- WSL側`python3`に依存しない。`sqlalchemy`等が無い場合はプロジェクトの`.venv/Scripts/python.exe`を使う。
- 日本語PF名を出す確認では`PYTHONIOENCODING=utf-8`を付ける。

---

## テーブルスキーマ（よく使う10テーブル）

### portfolios — PF検索の起点
```
PK: id(varchar/UUID)
name, type(standard/fof), config(json), hide_portfolio, hide_signal
created_at, updated_at
```

### signals — 保有シグナル
```
PK: (portfolio_id, date)
signal(raw), holding_signal(保有), momentum_data(json)
created_at, updated_at
```
**注意**: カラム名は`date`。`signal_date`ではない。

### monthly_returns — 月次リターン
```
PK: (portfolio_id, year_month)
cumulative_return, cumulative_return_open, monthly_return, monthly_return_open
benchmark_cumulative, benchmark_cumulative_open
```
**注意**: dateカラムではなく`year_month`(varchar, "YYYY-MM"形式)。

### fof_component_weights — FoFコンポーネント構成
```
PK: (portfolio_id, date, component_id)
component_type, nested_depth, target_weight, actual_weight, drift
asset_value, daily_return, component_holding_signal
component_tickers(json), expanded_tickers(json), child_components(json)
updated_at
```

### signal_change_log — holding_signal変更履歴（cmd_2455追加）
```
PK: id(serial)
portfolio_id, date, old_holding_signal, new_holding_signal
old_ticker_weights(json), new_ticker_weights(json), changed_at
```

### recalculation_status — fullrecalculate完了確認
```
PK: id(serial)
start_time, end_time, status(running/completed/failed), mode, error_message
```

### prices — 株価データ
```
PK: (symbol, date)
open, high, low, close, volume, source
```

### deterioration_snapshots — 弱体化指標
```
PK: (portfolio_id, year_month)
p6, p12, p24, label, g1_slope_6, g1_slope_12
```

### portfolio_metrics — PFパフォーマンス指標
```
PK: portfolio_id
years, metrics_json(json), calculated_at, data_start_date, data_end_date, months_count
```
**metrics_json実キー**: `portfolio_id`, `portfolio_name`, `benchmark_ticker`, `period_months`, `start_date`, `end_date`, `total_return`, `total_return_open`, `benchmark_total_return`, `benchmark_total_return_open`, `metrics`
**注意**: DB型は`json`。PostgreSQLの`?`演算子を使う時は`metrics_json::jsonb ? 'total_return'`のようにcastする。

### viewer_tiers — Tier名とID
```
PK: id(varchar/UUID)
name(Basic/Standard/NewStandard/premium等), display_order, password_env_key
created_at, updated_at, password_expires_at, last_rotated_at
```
**注意**: note.comの「スタンダードプラン(¥8,000)」はDB上`NewStandard`。古参¥4,000は`Standard`。

### tier_visibility_settings — Tier別PF閲覧設定
```
PK: id(integer)
tier_id(varchar/UUID, viewer_tiers.idへのFK, unique)
hidden_pages(json), portfolio_settings(json), folder_settings(json), updated_at
```
**portfolio_settings JSON構造**:
```json
{
  "<portfolio_id>": {
    "hide_portfolio": false,
    "hide_signal": false,
    "hide_components": true
  }
}
```
- `hide_portfolio=true`: PF自体を非表示。Viewer APIでは404/一覧除外。
- `hide_signal=true`: 保有シグナルをマスク。
- `hide_components=true`: 構成tickerをマスク。
- 設定が無いPFは安全側で非表示扱い。Tier別設定が優先、無ければglobal設定へfallback。

### fof_rebalance_decisions — リバランス判定履歴
```
PK: (portfolio_id, date)
trigger_type, should_rebalance, rebalance_reason
prev_signal, new_signal, signal_changed
```

---

## よく使うクエリテンプレート

### 1. PF検索（名前で）
```python
conn.execute(text("SELECT id, name, type FROM portfolios WHERE name LIKE :pattern ORDER BY name"),
             {'pattern': '%Ave%'}).fetchall()
```

### 2. holding_signal確認（直近N件）
```python
conn.execute(text("""
    SELECT date, holding_signal, created_at, updated_at
    FROM signals WHERE portfolio_id = :pid
    ORDER BY date DESC LIMIT :n
"""), {'pid': pf_id, 'n': 15}).fetchall()
```

### 3. holding_signal変化検知（全期間）
```python
rows = conn.execute(text("""
    SELECT date, holding_signal, created_at
    FROM signals WHERE portfolio_id = :pid ORDER BY date
"""), {'pid': pf_id}).fetchall()
prev = None
for r in rows:
    if r[1] != prev:
        print(f'{r[0]} | {r[1][:50]} | {r[2]}')
        prev = r[1]
```

### 4. monthly_returns確認
```python
conn.execute(text("""
    SELECT year_month, monthly_return, cumulative_return
    FROM monthly_returns WHERE portfolio_id = :pid
    ORDER BY year_month DESC LIMIT :n
"""), {'pid': pf_id, 'n': 12}).fetchall()
```

### 5. パリティ検証（holding_signal突合）
```python
# GS出力(expected) vs DB(actual) の完全一致確認
db_signals = conn.execute(text("""
    SELECT date, holding_signal FROM signals
    WHERE portfolio_id = :pid AND holding_signal IS NOT NULL
    ORDER BY date
"""), {'pid': pf_id}).fetchall()
# NULL行除外(L699), 展開後ticker×weightで比較(L703)
mismatches = [(d, hs) for d, hs in db_signals if hs != expected[d]]
print(f'Parity: {len(db_signals)-len(mismatches)}/{len(db_signals)} match, {len(mismatches)} mismatch')
```

### 6. fullrecalculate完了確認
```python
conn.execute(text("""
    SELECT id, status, start_time, end_time, mode
    FROM recalculation_status ORDER BY id DESC LIMIT 3
""")).fetchall()
# status='completed'かつend_time IS NOT NULLで完了判定(L690)
```

### 7. FoF component_weights確認
```python
conn.execute(text("""
    SELECT date, component_id, target_weight, expanded_tickers
    FROM fof_component_weights
    WHERE portfolio_id = :pid ORDER BY date DESC, component_id LIMIT 20
"""), {'pid': pf_id}).fetchall()
```

### 8. PF件数サマリ
```python
conn.execute(text("""
    SELECT type, COUNT(*) FROM portfolios
    WHERE hide_portfolio = false GROUP BY type
""")).fetchall()
```

### 9. signal_change_log確認（変更履歴）
```python
conn.execute(text("""
    SELECT portfolio_id, date, old_holding_signal, new_holding_signal, changed_at
    FROM signal_change_log ORDER BY changed_at DESC LIMIT 20
""")).fetchall()
```

### 10. 弱体化指標確認
```python
conn.execute(text("""
    SELECT year_month, p6, p12, p24, label
    FROM deterioration_snapshots
    WHERE portfolio_id = :pid ORDER BY year_month DESC LIMIT 6
"""), {'pid': pf_id}).fetchall()
```

### 11. Tier別PF閲覧確認（NewStandard）
```python
rows = conn.execute(text("""
    WITH target_tier AS (
        SELECT id, name
        FROM viewer_tiers
        WHERE name = :tier_name
    ), tier_settings AS (
        SELECT tvs.tier_id, tvs.portfolio_settings
        FROM tier_visibility_settings tvs
        JOIN target_tier tt ON tt.id = tvs.tier_id
    )
    SELECT p.id, p.name, p.type,
           COALESCE((ts.portfolio_settings -> p.id ->> 'hide_portfolio')::boolean, true) AS hide_portfolio,
           COALESCE((ts.portfolio_settings -> p.id ->> 'hide_signal')::boolean, false) AS hide_signal,
           COALESCE((ts.portfolio_settings -> p.id ->> 'hide_components')::boolean, false) AS hide_components,
           pm.metrics_json::jsonb ? 'total_return' AS has_total_return,
           pm.metrics_json::jsonb ? 'metrics' AS has_metrics
    FROM portfolios p
    CROSS JOIN tier_settings ts
    LEFT JOIN portfolio_metrics pm
      ON pm.portfolio_id = p.id AND pm.years = 0
    WHERE COALESCE((ts.portfolio_settings -> p.id ->> 'hide_portfolio')::boolean, true) = false
    ORDER BY p.name
    LIMIT :limit
"""), {'tier_name': 'NewStandard', 'limit': 20}).mappings().all()
```
**判定**: `rows`が1件以上、`hide_portfolio=False`、必要に応じて`has_total_return=True`/`has_metrics=True`ならNewStandardで閲覧可能なPFに到達できている。

---

## DM-Signal API

### 認証
| API種別 | 認証方式 | 取得元 |
|---------|---------|--------|
| admin系 | Basic Auth | backend/.env ADMIN_USERNAME/ADMIN_PASSWORD |
| viewer系 | Bearer Token | /api/viewer-auth で取得 |

### よく使うエンドポイント
```bash
# admin認証取得
ADMIN_USER=$(grep ADMIN_USERNAME backend/.env | cut -d= -f2)
ADMIN_PASS=$(grep ADMIN_PASSWORD backend/.env | cut -d= -f2)
BASE="https://dm-signal-backend.onrender.com"

# PF一覧
curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/api/admin/portfolios" | python3 -m json.tool

# fullrecalculate実行
curl -X POST -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/admin/recalculate-sync"

# signals取得
curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/api/admin/signals/$PF_ID?months=12"
```

---

## 制約

- DB操作は読み取り専用（書き込みはcmd経由でのみ）
- パリティ検証の許容誤差はゼロ（IEEE 754ノイズ=1e-12のみ: L392）
- NULL行はパリティ比較から除外（L699）
- FoFのholding_signal同一判定は展開後ticker×weightで行う（L703）
- fullrecalculate完了はrecalculation_status DB行で二重確認（L690）

## 関連スキル

- [[pf-registration]] — DB確認・パリティ検証完了後の本番PF登録（パリティ確認→登録の流れで使用）
