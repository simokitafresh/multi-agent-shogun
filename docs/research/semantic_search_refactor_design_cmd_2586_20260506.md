# semantic_search.sh CoDD Design

cmd: cmd_2586
date: 2026-05-06
source spec: `docs/research/codd_spec_semantic_search_cmd_2586_20260506.md`

## Design Goal

`scripts/semantic_search.sh` のMarkdown index parserを単一化し、alias検索とLLM結果resources解決の出力互換を保つ。

## Components

| Component | Responsibility |
|-----------|----------------|
| argument parser | `--llm`, `--help`, query組立、unknown optionの既存挙動を維持 |
| `semantic_index_python` | index Markdownを1回のPython heredoc定義でparseし、mode別に出力 |
| `first_layer_search` | Bash wrapper。`semantic_index_python first-layer "$no_match_mode"` を呼ぶ |
| `render_llm_resources` | Bash wrapper。`semantic_index_python render-llm-resources "$llm_output_file"` を呼ぶ |
| `llm_search` | prompt生成、LLM command実行、exit status伝播、resources解決の既存挙動を維持 |

## Data Contract

Parsed concept:

| Field | Source |
|-------|--------|
| `id` | table row `id`, fallback heading id |
| `label` | table row `label`, fallback heading label |
| `aliases` | comma-separated table row `aliases` |
| `resources` | non-empty non-attribute table rows |

## Mode Contract

| Mode | Input | Success | No match |
|------|-------|---------|----------|
| `first-layer` | query + no_match_mode | prints existing alias-match block | rc=1, optionally `NO_MATCH: <query>` |
| `render-llm-resources` | LLM output file | prints up to 3 resolved concept resource blocks | rc=0 with diagnostic line |

## Compatibility Constraints

- Existing stdout snippets asserted by `tests/unit/test_semantic_search.bats` must remain unchanged.
- LLM command failure must preserve the original exit status.
- `--llm` must bypass first-layer matching.
- Missing query remains rc=2.

## Measurement Baseline

| Metric | Before | Target |
|--------|--------|--------|
| script lines | 289 | fewer lines while preserving tests |
| parser instances | 2 | 1 |
| alias 5run avg | 53ms | no regression |
| LLM mock 5run avg | 109ms | no regression |
| Bats | 4 PASS / 583ms | 4 PASS / SKIP 0 |

## Implementation Plan

1. Add `semantic_index_python` with shared parser and explicit mode dispatch.
2. Replace duplicated Python blocks in `first_layer_search` and `render_llm_resources` with wrappers.
3. Run `bash -n`, semantic search Bats, and before/after timing.
4. Save After design so future index format changes update one parser path only.
