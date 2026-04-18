# gate_artifact_map.sh リファクタリング CoDD Spec (cmd_2089)

## cmd: cmd_2089 (CoDD再改善)
## 実施者: kotaro
## 日付: 2026-04-18

## 前回改善(cmd_1957)サマリ
967ms → 99ms (-90%, 9.8x): ループ内echo|awk x168サブシェル → awk 1パスTSV + pure bash展開

## 問題（ボトルネック関数+計測値）

前回改善後 99ms → 94ms(ホットパス)。残存ボトルネック:
**49回の `/mnt/c/` NTFS per-file stat呼び出し = 146ms**
(before: 94ms full script、file checkだけで146ms → process substitutionやechoと並列実行されるため full scriptは94ms)

## 定量プロファイル(実測 before)

| 処理 | 時間 | 根因 |
|------|------|------|
| bash startup | 9ms | — |
| awk 1パス | 9ms | — |
| 49 × `[[ -f /mnt/c/.../$path ]]` | 146ms | NTFS per-file stat (WSL2/mnt/c遅延) |
| **full script** | **94ms** (5回: 99,94,103,91,94) | file check並列実行で部分相殺 |

### ファイルチェック計測
- 49回 × stat on /mnt/c/ = 146ms (独立計測)
- 4サブディレクトリ × ls = 29ms (独立計測)
- 代替: bash文字列照合 = ~0ms (in-memory)

## リファクタリング対象

### R1: 49 × `[[ -f /mnt/c/ ]]` → ls 4サブディレクトリ一括 + bash文字列照合

**現状**:
- GS完了ブロック49件ごとに`[[ ! -f "$full_path" ]]` → 49回のNTFS stat
- 3ms/check × 49 = 146ms

**改善後**:
- 事前にユニークサブディレクトリ(4件)をls一括取得 → 29ms
- 取得したファイルリスト文字列に対してbash `[[ "$all_files" == *"$gs_path"* ]]` → 0ms/check
- フォールバック: サブディレクトリ未収録パスは引き続き`[[ -f ]]`で確認

**アプローチ詳細**:
1. `mapfile`でawk出力を配列に取込み(1パス)
2. GS: パスからサブディレクトリを抽出・重複排除
3. 対象サブディレクトリのみ`ls`(4回のNTFSアクセス)
4. メインループではbash文字列照合でファイル存在確認

## 期待値

| 指標 | Before | After(推定) |
|------|--------|-------------|
| full script | 94ms | ~52ms |
| file check部 | 146ms | ~29ms(ls)+0ms |
| 速度向上 | — | ~1.8x |

## 注意事項
- L503: 計測中にgate_metrics.logが更新される可能性 → 計測は連続5回median
- L496: /tmpでの計測は実運用(~/mnt/c/)より速い → 実運用ディレクトリで計測
- 動的サブディレクトリ対応: awk出力から自動抽出(ハードコード禁止)
