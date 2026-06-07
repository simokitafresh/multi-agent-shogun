---
codd:
  node_id: doc:script:agent-status-brownfield
  type: brownfield_report
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/agent_status.sh
---

# Brownfield Report: agent_status.sh

## Summary

- extract_output: manual analysis (codd extract --ai scan in progress)
- requirements_path: `skipped` (speed optimization — requirements = before→after perf target)
- lexicon_path: `discovery mode`
- diff_findings: 0
- elicit_findings: 3
- merged_findings: 3

## Brownfield Source Context

- Primary implementation: [[agent_status.sh]]
- Dependencies: [[pane_lookup.sh]], [[agent_config.sh]]
- Speed training task: cmd_training_speed_agent_status_20260607181500_normal
- Before (round2): 20-run loop avg ~2120ms | After target: minimize tmux call count

## Performance Profile

### Current Execution Model (Round 2 baseline)
```
1. source pane_lookup.sh → source agent_config.sh (NTFS file reads, /tmp cache after first)
2. tmux list-panes -F '#{pane_index} #{@agent_id}' → build CURRENT_PANES map (1 tmux call)
3. for each agent (N=8):
   tmux display-message -t "$pane" -p '#{pane_id}|...' (8 tmux calls)
Total: 9 tmux subprocess spawns per run
```

### Bottleneck
WSL2 tmux subprocess spawning: ~10-20ms × 9 = ~90-180ms per run
20-run loop: ~1800-3600ms (measured: 1810-2300ms)

<!-- codd:finding
{"details": {"current": "tmux list-panes(1) + tmux display-message×N(8) = 9 calls/run", "optimized": "tmux list-panes with all fields in format string = 1 call/run", "expected_savings": "88% reduction in tmux calls"}, "id": "tmux_call_batching", "kind": "performance_gap", "name": "tmux calls can be batched into single list-panes call", "question": "tmux list-panesのformat文字列に全エージェント変数(@agent_state/@last_active/@context_pct)を含めることで、display-message個別呼出しを廃止できるか？", "rationale": "WSL2のsubprocess spawningが主ボトルネック。9回→1回に削減することで88%のtmux overhead削減が期待される。", "related_requirement_ids": [], "severity": "high", "source": "brownfield"}
-->
## tmux_call_batching - tmux呼出しを1回のlist-panesに集約

- approval: [x] `tmux_call_batching`
- id: `tmux_call_batching`
- kind: `performance_gap`
- severity: `high`
- name: tmux calls can be batched into single list-panes call
- question: tmux list-panesのformat文字列に全エージェント変数を含めて、display-message個別呼出しを廃止できるか？
- rationale: WSL2のsubprocess spawningが主ボトルネック。9回→1回で88%削減期待。

```yaml
implementation_design: >
  Replace:
    tmux list-panes (pass1) + tmux display-message×8 (pass2)
  With:
    tmux list-panes -t shogun:agents -F '#{pane_index}|#{@agent_id}|#{@agent_state}|#{@last_active}|#{@context_pct}'
  Then: build PANE_DATA associative array keyed by agent_id
  Result: 1 tmux call/run instead of 9
```

<!-- codd:finding
{"details": {"concern": "pane_lookup() fallback in main loop also calls tmux list-panes internally"}, "id": "pane_lookup_redundancy", "kind": "performance_gap", "name": "pane_lookup() fallback spawns additional tmux calls", "question": "CURRENT_PANESにないエージェントへのpane_lookup()フォールバックを廃止できるか？", "rationale": "1回のtmux list-panesで全ペインデータを取得すれば、フォールバック自体が不要になる。", "related_requirement_ids": [], "severity": "medium", "source": "brownfield"}
-->
## pane_lookup_redundancy - pane_lookup()フォールバック廃止

- approval: [x] `pane_lookup_redundancy`
- id: `pane_lookup_redundancy`
- kind: `performance_gap`
- severity: `medium`
- name: pane_lookup() fallback spawns additional tmux calls
- question: フォールバック廃止可能か？
- rationale: 1回のlist-panesで全データ取得すれば不要。

<!-- codd:finding
{"details": {"current": "CURRENT_PANES map (target only) → PANE_DATA (all fields pre-loaded)"}, "id": "data_model_simplification", "kind": "design_improvement", "name": "Two-pass data model can be replaced with single-pass", "question": "現在の2パス設計(1:ペインマップ構築 2:個別クエリ)を1パス設計に変更できるか？", "rationale": "1回のtmux呼出しで全データをPANE_DATA連想配列に格納し、forループでは配列参照のみにする。", "related_requirement_ids": [], "severity": "medium", "source": "brownfield"}
-->
## data_model_simplification - 2パス→1パス設計

- approval: [x] `data_model_simplification`
- id: `data_model_simplification`
- kind: `design_improvement`
- severity: `medium`
- name: Two-pass data model to single-pass
- rationale: 1回tmux呼出しでPANE_DATA構築、forループは配列参照のみ。
