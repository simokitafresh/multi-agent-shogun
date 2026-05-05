# semantic_index_update.sh After設計書（2026-05-06）

## 現在の構造

| 層 | 責務 | 実装 |
|----|------|------|
| CLI | `source_type` と `payload_json` の検証 | bash |
| 排他 | semantic index 更新と map 再生成の直列化 | `flock -w 10` |
| 判定 | payload と aliases の照合、index追記、insight投入 | Python heredoc |
| sentinel処理 | Python出力から `__SEMANTIC_INDEX_CHANGED__` を除去し、map再生成要否を判定 | bash `while IFS= read -r line` |
| map再生成 | index更新時だけ semantic map を再生成 | `bash "$map_generate"` |

## 最適化パターン

- Python判定出力のsentinel除去と検出は、外部`grep` 2回ではなくbash組み込みの1パスループで処理する。
- `SEMANTIC_MAP_GENERATE` は実行権限なしファイルでも動くよう、直接実行せず `bash "$map_generate"` を維持する。
- `flock`範囲はPython判定、sentinel処理、map再生成を含む。変更判定後にロック外でmap再生成しない。

## 禁止パターン

- sentinel処理へ `grep -v` / `grep -qx` を戻すな。固定文字列の完全一致なのでbash比較で足りる。
- Pythonの概念matchingロジックを速度改善ついでに変更するな。今回のR1はsentinel後処理だけが対象。
- `"$map_generate"` の直接実行へ変えるな。実行権限なしgeneratorを許容する既存テスト契約がある。

## 計測値

| 段階 | 関連Bats 5回実測 | 中央値 | 判定 |
|------|------------------|--------|------|
| Before | `0.91s`, `0.99s`, `1.01s`, `0.97s`, `0.98s` | `0.98s` | baseline |
| After | `1.30s`, `1.11s`, `1.06s`, `0.97s`, `0.93s` | `1.06s` | 機能PASS、速度はmap再生成/Python起動の変動が支配的で改善確認なし |

## 検証

- `bash -n scripts/semantic_index_update.sh`: PASS
- `bats tests/unit/test_semantic_index_update.bats`: 8/8 PASS, SKIP=0
- `rg -n "grep" scripts/semantic_index_update.sh`: matchなし

## CoDD実行結果

- `codd init`, `codd plan --init`, `codd generate` Wave 1-3 は完了。
- Wave 4 は `You've hit your org's monthly usage limit` で停止。
- 生成済み設計書:
  - `docs/research/semantic_index_update_codd_design_20260506.md`
  - `docs/research/semantic_index_update_codd_adr_20260506.md`
