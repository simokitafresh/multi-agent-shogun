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

<!-- script_refs_checked_at: 2026-07-13T07:39:17+09:00 -->
<!-- 検分: db_capability_launcher.py 4da46f0e2(cmd_karo_hotfix_guard14_db_capability_launcher: 追跡済みlauncher新規追加)+7ba136462(contract RC強化: git index一致判定をHEAD blob一致判定へ変更/credential env keysをregistry required_credential_keysと完全一致検証/child引数をcontractのallowed_child_flagsで検証/`--execution-root`任意フラグ追加)。本SKILL.mdが例示する`--capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce <nonce> --credential-file <path>`はreadonly_query契約(dependency_toolなし・actionsなし・required_credential_keys=[DATABASE_URL]のみ)のため影響を受けない。SQLはstdin渡しでtool_argsは空のまま。呼び出し契約は不変 -->

# /db-check — DM-Signal DB確認スキル

本番DB接続+クエリを標準化。試行錯誤ゼロで目的のデータに到達する。

---

## 接続方法（共通capability launcherのみ）

直接の `psycopg2.connect`、SQLAlchemy接続、接続文字列をargvへ載せる実行は禁止。
追跡済み `config/db_capabilities.json` を正本とする共通launcherだけを使う。

```bash
printf 'SELECT ...' | python3 scripts/db_capability_launcher.py \
  --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK \
  --nonce "$(date +%s)-readonly" --credential-file /protected/path/dm-signal-db.env
```

**重要**: DATABASE_URLをそのままpsycopg2.connect()に渡すとunix socket fallbackでエラーになる。必ず上記のように個別パラメータで接続せよ。

transactional restoreは `--capability transactional_restore --mode transactional_restore
--confirm TRANSACTIONAL_RESTORE_ROLLBACK_READY --expected-commit "$(git rev-parse HEAD)"` を使う。
credential fileは0600、SQLはstdin、nonceは再利用不可。launcher外接続は禁止。

### 方式選択ガイド

| 条件 | 方式 |
|------|------|
| WSL python3で即実行したい | **方式A**（psycopg2直接） |
| SQLAlchemy ORMが必要 | 方式B（Windows python.exe） |
| psqlコマンド | **使用禁止**（未インストール） |

### 実行場所と文字コード

方式A:
```bash
python3 -c "import psycopg2; ..."  # WSL python3で直接実行
```

方式B:
```bash
cd /mnt/c/Python_app/DM-signal/backend
PYTHONIOENCODING=utf-8 /mnt/c/Python_app/DM-signal/.venv/Scripts/python.exe your_check.py
```

- 方式Bのcwdは`/mnt/c/Python_app/DM-signal/backend`にする。`.env`相対読込の失敗を避ける。
- 日本語PF名を出す確認では`PYTHONIOENCODING=utf-8`を付ける。
- **UTF-8出力強制（必須）**: `PYTHONIOENCODING=utf-8`だけでは日本語PF名が文字化けする場合がある(2026-06-14実証)。Pythonスクリプトのimport直後に以下を追加:
  ```python
  import io, sys
  sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
  ```

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
| admin系 | Basic Auth | backend/.env ADMIN_USER/ADMIN_PASS |
| viewer系 | Bearer Token | /api/viewer-auth で取得 |

### よく使うエンドポイント
```bash
# admin認証取得
ADMIN_USER=$(grep -m1 '^ADMIN_USER=' backend/.env | cut -d= -f2- | tr -d '\r\n')
ADMIN_PASS=$(grep -m1 '^ADMIN_PASS=' backend/.env | cut -d= -f2- | tr -d '\r\n')
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

### 12. PF構成一括確認（名前で全情報を一発取得）
```bash
# スクリプトで実行（推奨）
cd /mnt/c/Python_app/DM-signal/backend
PYTHONIOENCODING=utf-8 /mnt/c/Python_app/DM-signal/.venv/Scripts/python.exe \
    ../scripts/check_pf_config.py "<PF名の一部>"
# 出力: 基本情報 + 全Tier visibility + pipeline_config + コンポーネントPF一覧
```

```python
# SQLクエリ版（単一PF調査時）
# 基本情報 + pipeline_config
row = conn.execute(text("""
    SELECT id, name, type, config, hide_portfolio, hide_signal, folder_id
    FROM portfolios WHERE name ILIKE :pat
"""), {'pat': '%<PF名>%'}).mappings().fetchone()
import json
config = row['config'] if isinstance(row['config'], dict) else json.loads(row['config'])
pc = config.get('pipeline_config', {})
sel = pc.get('selection_pipeline', {}).get('blocks', [])
term = pc.get('terminal_block', {})

# 全Tier別visibility設定
rows = conn.execute(text("""
    SELECT vt.name AS tier_name,
           (tvs.portfolio_settings -> :pid ->> 'hide_portfolio')::boolean AS hide_portfolio,
           (tvs.portfolio_settings -> :pid ->> 'hide_signal')::boolean AS hide_signal,
           (tvs.portfolio_settings -> :pid ->> 'hide_components')::boolean AS hide_components
    FROM tier_visibility_settings tvs
    JOIN viewer_tiers vt ON vt.id = tvs.tier_id
    ORDER BY vt.display_order
"""), {'pid': row['id']}).mappings().all()

# コンポーネントPF一覧（FoF type の場合）
components = conn.execute(text("""
    SELECT fcw.component_id, p.name, fcw.component_type, fcw.target_weight, fcw.nested_depth
    FROM fof_component_weights fcw
    LEFT JOIN portfolios p ON p.id = fcw.component_id
    WHERE fcw.portfolio_id = :pid
      AND fcw.date = (SELECT MAX(date) FROM fof_component_weights WHERE portfolio_id = :pid)
    ORDER BY fcw.nested_depth, fcw.component_id
"""), {'pid': row['id']}).mappings().all()
```
**注意**: `selection_pipeline` は `{"blocks": [...]}` の形式。`terminal_block.config` が空でも `EqualWeight` は正常。全Tier未設定PFはデフォルト非表示(hide_portfolio=True)。

---

## 関連スキル

- [[pf-registration]] — DB確認・パリティ検証完了後の本番PF登録（パリティ確認→登録の流れで使用）
