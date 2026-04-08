# 計算データ管理の原則（運用手順詳細）
<!-- cmd_286 | 2026-02-23 | ops.mdから移動 -->
<!-- 結論: 命名規則+上書き禁止+meta必須+テンプレGS+CSVローダ(cmd_160) -->

## 殿の5原則

再現性100%、データ+インデックス、第三者可読、上書き禁止、過剰設計回避。

## 命名規則

```
{cmd番号}_{ブロック名}_{説明}.csv      — GS結果
{cmd番号}_{ブロック名}_{説明}.meta.yaml — CSVと同名・同ディレクトリ
```

ブロック号名: bunshin(分身) / oikaze(追い風) / nukimi(抜き身) / monban(門番) / kasoku(加速) / kawarimi(変わり身)

## 運用ルール

| # | ルール | 詳細 |
|---|--------|------|
| 1 | 上書き禁止 | 再実行は`_v2`サフィックスで区別 |
| 2 | meta.yaml必須 | 入力/パラメータ/実行日時/スクリプトパス/MD5 |
| 3 | カタログ追記必須 | `DATA_CATALOG.md`「Active Catalog」に行追加 |
| 4 | 旧データ参照禁止 | 035-070は歴史的参考のみ |

## テンプレートスクリプト

パス: `scripts/analysis/grid_search/template_gs_runner.py` — コピー&リネーム即使用

| セクション | 書換 | 内容 |
|-----------|------|------|
| PARAMETERS | 必須 | CMD_ID, BLOCK_NAME, PARAM_GRID等 |
| Utilities | 不要 | load_monthly_returns, calc_metrics, write_meta_yaml, append_data_catalog |
| Block Logic | 必須 | simulate_pattern, build_grid, pattern_to_row |
| Main | 不要 | 上書き防止+進捗表示+CSV→meta→カタログ3段出力 |

## 共通CSVローダー (cmd_160)

パス: `scripts/analysis/grid_search/gs_csv_loader.py` — 全GSスクリプト(monban除く6本)がCSV直接読込

| 関数 | 戻り値 |
|------|--------|
| `load_monthly_returns_from_csv(component_spec, return_kind, drop_latest)` | `Dict[str, pd.Series]` |
| `load_monthly_returns_dual_from_csv(spec_open, spec_close, close_fallback)` | `Tuple[Dict, Dict]` |
| `build_wide_component_spec(csv_path, column_names, year_month_col)` | `Dict` |
| `get_csv_provenance(csv_paths)` | `Dict` (meta.yaml用) |

データソース: `outputs/grid_search/064_champion_monthly_returns.csv` (12パターン×143ヶ月)
DM_IDS→COMPONENT_SOURCES置換済み | meta.yaml: csv_provenance+source_type:csv_direct | GS高速化: `context/gs-speedup-knowledge.md`

## ブロック別GSスクリプト

全6ブロック: `scripts/analysis/grid_search/run_077_{block}.py` | 詳細: `DATA_CATALOG.md` C-7

PD-028裁定(2026-02-23): GS制約同期は仕組み化しない。BBカタログにPydantic制約明記+PARAM_GRIDを制約範囲修正で運用。

## データカタログ

パス: `outputs/grid_search/DATA_CATALOG.md` — 4層(Active/Existing/Historical/Legacy) + System Definition C-1〜C-7

## 堅牢性検証ツール（承認済み・未実装）

構造的SUSPECT検出+自動Ban: `docs/skills/structural-suspect-ban.md` | Ban履歴ログ必須+誤Ban防止安全機構必須
