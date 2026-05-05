# semantic_search.sh リファクタリング CoDD Spec

## 問題

`scripts/semantic_search.sh` はセマンティックインデックスのMarkdownテーブルを読むPython処理を2箇所に重複して持つ。

- `first_layer_search`: `scripts/semantic_search.sh` L65-L155
- `render_llm_resources`: `scripts/semantic_search.sh` L157-L233

同じ `re.split` / table row parse / `id,label,aliases,resources` 構築が二重化しており、将来のindex形式変更時に片側だけ更新されるリスクがある。

## 定量プロファイル(before実測)

実行日: 2026-05-06

| 指標 | Before |
|------|--------|
| script lines | 289行 |
| `re.split(r"(?m)^##\s+")` 出現 | 2箇所 |
| `concepts = []` 出現 | 2箇所 |
| alias hit 5run avg | 53ms |
| LLM fallback(mock) 5run avg | 109ms |
| `tests/unit/test_semantic_search.bats` | 4 tests / 583ms / PASS |

測定コマンド:

```bash
tmpdir=$(mktemp -d)
mock="$tmpdir/mock_llm.sh"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "MATCH: growth_loop"
echo "reason: mock semantic match"
EOF
chmod +x "$mock"

measure alias bash scripts/semantic_search.sh 意味検索
measure llm_mock env SEMANTIC_LLM_CMD="$mock" bash scripts/semantic_search.sh 品質を伸ばす輪
bats tests/unit/test_semantic_search.bats
```

## リファクタリング対象

### R1: Python index parserの一元化

`semantic_index_python()` を追加し、以下を同じPython heredoc内のmode分岐に統合する。

- `first-layer`: queryとalias/labelを照合して既存出力を返す
- `render-llm-resources`: LLM出力内のconcept idを既存出力形式でresourcesへ解決する

### R2: Bash関数はI/O orchestrationのみへ縮小

`first_layer_search()` と `render_llm_resources()` はmode呼び出しだけにし、重複したMarkdown parserを持たない。

## 実施順序

1. `semantic_index_python()` を追加
2. `first_layer_search()` を `semantic_index_python first-layer "$no_match_mode"` に差替え
3. `render_llm_resources()` を `semantic_index_python render-llm-resources "$llm_output_file"` に差替え
4. `bash -n scripts/semantic_search.sh`
5. `bats tests/unit/test_semantic_search.bats`
6. before/after再計測

## 制約

- CLI互換: `--llm`, `--help`, unknown option, no query, missing indexの挙動を変えない
- 出力互換: 既存Batsが期待する文字列を維持する
- LLM command実行経路とexit status伝播は変更しない
- 実LLM計測は外部API揺らぎが大きいため、mock LLMで比較する

## 期待効果

| 観点 | 期待 |
|------|------|
| 保守性 | index parseロジック2箇所 -> 1箇所 |
| 速度 | 同一処理回数は維持。速度改善は副次効果扱い |
| 安全性 | 既存Bats 4件で出力互換を検証 |
