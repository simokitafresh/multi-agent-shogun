# semantic_search.sh After設計書

cmd: cmd_2586
date: 2026-05-06
target: `scripts/semantic_search.sh`

## 現在の構造

| Function | Responsibility |
|----------|----------------|
| `usage` | CLI help text |
| argument parse block | `--llm`, `--help`, `--`, query parts, unknown option handling |
| `semantic_index_python` | Markdown semantic index parser and mode dispatcher |
| `first_layer_search` | alias/label first-layer search wrapper |
| `render_llm_resources` | LLM output concept id -> resources wrapper |
| `llm_search` | prompt generation, LLM command execution, output rendering |

## 最適化パターン

The parser for `docs/semantic-index/index.md` is now defined once in `semantic_index_python`.

Before:

- `first_layer_search` parsed concept sections independently.
- `render_llm_resources` repeated the same section/table parser.

After:

- Both wrappers call the same parser with different modes.
- Table row interpretation (`id`, `label`, `aliases`, resources) has a single update point.

## 禁止パターン

Do not add a second Python heredoc that reparses semantic-index concepts. Add a new `mode` inside `semantic_index_python` instead.

Do not change LLM command execution semantics inside the parser helper. `llm_search` owns prompt files, command execution, and exit status propagation.

## 計測値

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| script lines | 289 | 250 | -39 lines |
| parser instances (`re.split`) | 2 | 1 | -50% |
| alias hit 5run avg | 53ms | 41ms | -22.6% |
| LLM fallback mock 5run avg | 109ms | 100ms | -8.3% |
| `tests/unit/test_semantic_search.bats` | 4 PASS / 583ms | 4 PASS / 556ms | PASS maintained |

## Regression Checks

```bash
bash -n scripts/semantic_search.sh
bats tests/unit/test_semantic_search.bats
```

Result: both PASS on 2026-05-06. SKIP count: 0.
