---
codd:
  node_id: governance:adr-parser-consolidation
  type: governance
  depends_on:
  - id: req:semantic-search-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - function:semantic_index_python
    - script:semantic_search
    reason: LLMコマンド実行経路とexit status伝播の変更は禁止。parser統合の方式選定はこのADRで確定しコード実装前に承認必須。
  modules:
  - semantic_search
---

# ADR: Python Index Parser一元化方針

## 1. Overview

`scripts/semantic_search.sh` 内部に存在する2箇所の Python index parse ロジック（`first_layer_search` L65-L155 / `render_llm_resources` L157-L233）を、単一の Bash 関数 `semantic_index_python()` に統合する方針を決定する ADR である。

現状、`re.split(r"(?m)^##\s+")` によるセクション分割、table row parse、`id,label,aliases,resources` 構造体の構築が二重化されており、将来の index 形式変更時に片側だけ更新されるリスクが顕在化している。定量的には `re.split` 出現が2箇所、`concepts = []` 初期化が2箇所に分散している（script 全体289行、2026-05-06実測）。

本 ADR は以下の対象に直接影響する。

| 対象 | 識別子 | 役割 |
|------|--------|------|
| 統合先関数 | `function:semantic_index_python` | Python heredoc 内で mode 分岐し、index parse を一元的に実行する |
| 呼び出し元スクリプト | `script:semantic_search` | Bash 側は I/O orchestration のみに縮小される |

**コンベンション準拠宣言:** 本 ADR で確定した parser 統合方式は、コード実装着手前に承認を必須とする。`function:semantic_index_python` および `script:semantic_search` において、LLM コマンド実行経路と exit status 伝播の変更は禁止する。この禁止事項は Decision Log 内の各決定項目に対してもゲート条件として適用される。

## 2. Decision Log

### D1: 統合方式 — Python heredoc 内の mode 分岐採用

**決定:** `semantic_index_python()` という単一の Bash 関数を新設し、内部の Python heredoc に `first-layer` と `render-llm-resources` の2つの mode を持たせる。mode は第1引数で切り替える。

**根拠:** 既存の2箇所（`first_layer_search` / `render_llm_resources`）はいずれも同一の Markdown テーブル parse パイプライン（`re.split` → row parse → `id,label,aliases,resources` dict 構築）を共有しており、parse ロジックの差分はゼロである。異なるのは parse 後の照合・出力フェーズのみであるため、parse 部分を1回だけ記述し、mode 分岐で後段処理を切り替えるのが最小変更かつ最大効果となる。

**呼び出しインターフェース:**

```bash
semantic_index_python first-layer "$no_match_mode"
semantic_index_python render-llm-resources "$llm_output_file"
```

**制約チェック:** `semantic_index_python` は Python 部分で parse と照合を完結させ、stdout へ結果を出力する。LLM コマンドの起動（`$SEMANTIC_LLM_CMD` の実行）は Bash 側の orchestration に残すため、LLM コマンド実行経路には一切手を加えない。exit status は Python heredoc の終了コードをそのまま Bash に伝播させ、既存の `set -euo pipefail` チェーンを壊さない。

### D2: Bash 関数の責務縮小

**決定:** `first_layer_search()` と `render_llm_resources()` の関数本体から Markdown parse ロジックを全面削除し、`semantic_index_python` への mode 呼び出し1行に置き換える。

**根拠:** Bash 関数は I/O orchestration（引数の受け渡し、LLM コマンド起動、一時ファイル管理、exit status 制御）だけを担う。parse ロジックを持たないことで、index 形式変更時の修正箇所が `semantic_index_python` 内部の1箇所に限定される（2箇所→1箇所）。

**制約チェック:** CLI 互換性（`--llm`、`--help`、unknown option、no query、missing index の各挙動）は Bash 側の引数処理に閉じており、本決定の影響を受けない。

### D3: 出力互換性の検証基準

**決定:** 既存の `tests/unit/test_semantic_search.bats` 4テストケース（583ms / PASS、2026-05-06実測）をリファクタリング前後で全件 PASS させることを出力互換性の合格基準とする。

**根拠:** Bats テストは alias hit パス・LLM fallback パス・エラーパスの出力文字列を期待値として検証しており、parse ロジックの統合が出力に影響しないことを確認するのに十分である。

**速度基準:** alias hit 5run avg 53ms、LLM fallback（mock）5run avg 109ms を before 基準値とする。統合後に同一測定で ±20% を超える劣化が観測された場合は原因調査を行う。速度改善は副次効果扱いとし、目標値は設定しない。

**LLM mock 方針:** 実 LLM 計測は外部 API の揺らぎが大きいため、before/after 比較には以下の mock を使用する。

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
env SEMANTIC_LLM_CMD="$mock" bash scripts/semantic_search.sh 品質を伸ばす輪
```

### D4: 実施順序の確定

**決定:** 以下の6ステップを順守し、各ステップ完了後に次ステップへ進む。

| Step | 内容 | 完了条件 |
|------|------|----------|
| 1 | `semantic_index_python()` 関数を `scripts/semantic_search.sh` 内に追加 | `bash -n scripts/semantic_search.sh` が exit 0 |
| 2 | `first_layer_search()` を `semantic_index_python first-layer "$no_match_mode"` 呼び出しに差替え | `bash -n` pass かつ `bats` 4/4 pass |
| 3 | `render_llm_resources()` を `semantic_index_python render-llm-resources "$llm_output_file"` 呼び出しに差替え | `bash -n` pass かつ `bats` 4/4 pass |
| 4 | `bash -n scripts/semantic_search.sh` による構文チェック | exit 0 |
| 5 | `bats tests/unit/test_semantic_search.bats` による回帰テスト | 4 tests pass |
| 6 | before/after 再計測（alias hit / LLM mock 各5run avg） | 結果を記録、±20% 超劣化なし |

**制約チェック:** Step 2・3 において、LLM コマンド実行経路（`$SEMANTIC_LLM_CMD` の fork/exec）と exit status 伝播（Python heredoc → Bash 関数 → スクリプト終了コード）が変更されていないことを、既存 Bats テストの LLM fallback ケースで検証する。

## 3. Follow-ups

| ID | 内容 | トリガー | 担当判定基準 |
|----|------|----------|-------------|
| F1 | index 形式変更（カラム追加・セクション構造変更）時の `semantic_index_python` 内 parse ロジック更新手順の文書化 | index スキーマに変更が入った時点 | 統合後の parse ロジックが1箇所に集約されていることを前提とし、変更箇所の特定コスト削減を確認する |
| F2 | `semantic_index_python` の Python 部分を外部 `.py` ファイルに分離するかの判断 | heredoc 内の Python コードが100行を超えた時点 | 可読性・テスト容易性・シェルとの引数受け渡しコストを比較し ADR を起票する |
| F3 | Bats テストケース拡充（境界値：空 index、セクション0件、alias 重複、不正 Markdown） | 本 ADR の実装完了後 | 統合済み parse ロジックに対するカバレッジ向上として追加する。既存4テストの出力期待値は変更しない |
| F4 | before/after 計測結果の恒久記録 | Step 6 完了時 | alias hit 5run avg（before: 53ms）、LLM mock 5run avg（before: 109ms）を基準に、after 値を `docs/benchmarks/` に記録する |
