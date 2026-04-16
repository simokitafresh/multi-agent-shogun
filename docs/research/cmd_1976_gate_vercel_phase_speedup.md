# gate_vercel_phase.sh 高速化 spec (cmd_1976)

## 計測環境
- 日時: 2026-04-16
- ベースライン (cmd_1951): 481ms
- 計測値: 2.3s (WSL2 /mnt/c キャッシュ未暖機時) / 安定値 ~700ms

## ボトルネック分析

| #  | 箇所 | 計測値 | 原因 |
|----|------|--------|------|
| B1 | `check_context_file()` awk: 43回起動 | 355ms | ファイルごとにawk subprocess起動 |
| B2 | `resolve_context_bases()` process substitution: 268回 | 215ms | refごとにサブシェル起動してprintfでbase_dir列挙 |
| B3 | `build_file_cache()` find 外部リポ | 104ms | /mnt/c WinFS findが重い |
| B4 | `collect_context_files()` find+sort | 12ms | 軽微 |

**合計除去可能**: B1+B2 = 343ms以上

## 最適化候補

### 候補A: BASES配列の事前構築（B2解消）
`resolve_context_bases()` をprocess substitutionで毎ref呼び出すのをやめ、
`BASES` bash arrayを `main()` で一度構築し、
`check_context_file()` 内でarray iterationに変更。

- 実装難易度: 低
- 期待削減: 215ms
- 機能変更: なし

### 候補B: awk単一起動（B1解消）
全contextファイルを1回のawkで処理し `filename\tlineno\tref` を出力。
`check_context_file()` をファイル別ループから結果受取型に変更。

- 実装難易度: 中
- 期待削減: 355ms - 227ms = 128ms
- 機能変更: なし（出力結果は同一）

### 候補C: 外部リポfindのスキップ最適化（B3軽減）
`ANY_EXTERNAL_EXISTS` チェック後に外部リポfindを行うが、
外部リポがどれも存在しなければ `build_file_cache` の外部リポfindを省略可能。
現状は存在するので効果は低い。将来的な最適化。

## 実装方針（A+Bの組み合わせ）

1. `main()` で `declare -a RESOLVE_BASES` を構築（SCRIPT_DIR + EXTERNAL_REPO_PATHS）
2. `check_context_file()` の `resolve_context_bases` process substitution → `"${RESOLVE_BASES[@]}"` の直接参照
3. `main()` のwhileループを以下に変更:
   - 全contextファイルを事前リスト化
   - awk一括起動で全refを抽出（`filename\tlineno\tref` 形式）
   - 結果をbashで処理

## 期待値

| 指標 | before | after |
|------|--------|-------|
| 実行時間 | 481ms (cmd_1951) | 目標100ms |
| awk起動回数 | 43 | 1 |
| process substitution | 268回 | 0 |
