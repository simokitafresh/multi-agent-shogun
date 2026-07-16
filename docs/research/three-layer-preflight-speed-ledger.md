# Three-layer preflight speed ledger

| 巡 | p50 ms | p95 ms | 支配区間 | 変更 | 判定 |
|---|---:|---:|---|---|---|
| before | 1621 | 4504 | memory/semantic CLI | なし | baseline |
| 1 | 981.5 | 1794 | memory+semantic process/index初期化 | 一括Python read | 採用 |
| 2 | 225.5 | 254 | `git grep -- docs` | 正規causal index cache | 採用 |
| 3 | 139 | 167 | semantic 77 / memory 75.5 / Obsidian 43ms | hot-path subprocessと二重temp除去 | 採用（ABAB交互） |

gen3同一環境ABAB交互20回/版: 旧`00bc9be22`=154/188ms、現`098fa5a6f`=139/167ms。両群timeout=0、superseded=0、三層一致=20/20。Bats=33/33 PASS、FAIL=0、SKIP=0。

計測command: `THREE_LAYER_PREACTION_EVIDENCE_DIR=<isolated> THREE_LAYER_AGENT_ID=tobisaru TMUX_PANE=%8 timeout 12s bash scripts/hooks/three_layer_preflight.sh issue 'three layer preflight speed'`。

origin: [[UserPromptSubmit-p95-254ms]] -> [[hot-path-subprocess-and-double-temp]] -> [[UserPromptSubmit-p95-160ms]]
