# cmd_1973: model_switch_preflight.sh 高速化 spec

## 計測環境
- 日時: 2026-04-16
- WSL2 Linux 6.6.87 / /mnt/c/ (NTFS経由)

## Before (ベースライン)
- cmd_1951実測: 5483ms (timeout判定)
- 本セッション実測: 13183ms

## ボトルネック分析

| Check | Before | 割合 | 根因 |
|-------|--------|------|------|
| check_hardcodes | 9434ms | 73% | 11パターンを別々にgrep → ファイル290件を11回読む |
| check_cli_lookup_usage | 653ms | 5% | grep -rl → WSL2 I/O 204ファイル |
| check_task_status | 462ms | 4% | python3を忍者ごと(6回)起動 → 起動コスト×6 |
| check_settings_schema | 74ms | 1% | python3 1回 (許容範囲) |
| startup/overhead | ~560ms | 4% | bash起動+lib source |

## 最適化候補

### 候補1 (最重要): check_hardcodes — 単一正規表現grep
- **Before**: `for pattern in "${patterns[@]}"; do grep ... "$pattern" ...; done` (11回ループ)
- **After**: 全パターンを `(pat1|pat2|...|patN)` に結合して1回のgrep
- **測定値**: 9434ms → 760ms (**12.4x speedup**)
- **根拠**: WSL2上でのgrep I/Oコストはファイル読み込み回数に比例。11パターン→1パターンでファイル読み込みを1/11に削減

### 候補2: check_task_status — awk置換
- **Before**: `python3 - "$task_file" <<'PYEOF'` を忍者ごと実行 (6回)
- **After**: `awk '/^task:/{in_t=1} in_t && /^  status:/{print $2; exit}' "$task_file"`
- **測定値**: 462ms → 44ms (**10.5x speedup**)
- **根拠**: python3起動コスト(~70ms/回)×6 → awkはforkのみで起動コスト無視できる

### 候補3: check_cli_lookup_usage — git grep
- **Before**: `grep -rl 'source.*cli_lookup\.sh' "$SCRIPT_DIR/scripts/" "$SCRIPT_DIR/lib/"`
- **After**: `git grep -rl 'source.*cli_lookup\.sh' -- '*.sh'`
- **測定値**: 653ms → 189ms (**3.5x speedup**)
- **根拠**: git grepはgit indexを利用してWSL2 NTFS I/Oを部分的に回避

## 期待される合計After

| Check | After |
|-------|-------|
| check_hardcodes | 760ms |
| check_settings_schema | 74ms |
| check_task_status | 44ms |
| check_cli_lookup_usage | 189ms |
| startup/overhead | ~200ms |
| **合計** | **~1270ms** |

- cmd_1951ベース(5483ms)比: **約4.3x speedup**
- 本セッション実測(13183ms)比: **約10x speedup**
- 目標500msとのギャップ: WSL2 NTFS filesystem I/Oが根本限界 (check_hardcodes単体で760ms)

## 機能変更なし確認
- 検出するパターン: 同一 (is_codex, gpt-5., claude-(opus|sonnet|haiku)-[0-9], agent.*codex)
- 除外フィルタ: 同一
- PASS/FAIL/WARNロジック: 同一
- 終了コード: 同一
