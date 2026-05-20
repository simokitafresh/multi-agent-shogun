# auto_deploy_next.sh CoDD速度改善 Before分析
## 実施日: 2026-05-20
## 実施者: hanzo

## Before計測 (cold, 3回)
| Run | Time |
|-----|------|
| 1   | 240ms |
| 2   | 222ms |
| 3   | 236ms |
| Median | 236ms |

測定パス: `bash scripts/auto_deploy_next.sh cmd_9999 subtask_dummy_1`
(no-subtasks-found path: Python3が全task YAMLをスキャンして0件で終了)

## ボトルネック分析

| コンポーネント | 時間 | 割合 |
|----------------|------|------|
| Bash startup + flock | ~12ms | 5% |
| Python3 ANALYSIS subprocess | ~183ms | 77% |
| ├── Python3 startup | ~41ms | 17% |
| └── yaml.safe_load (10 files) | ~94ms | 40% |
| その他 (log書込み等) | ~40ms | 17% |

## 最大ボトルネック: Python3 ANALYSIS (lines 65-188)
- 全task YAMLファイルをglobで列挙してyaml.safe_loadで解析
- parent_cmd一致でフィルタ → マッチなし時も全ファイル走査
- WSL2 NTFS上でのI/OシリアライズがPython3を支配 (L508)

## 最適化仮説

### H1: grep fast-path (高インパクト)
- Python3呼出し前に`grep -l "parent_cmd: ${CMD_ID}" $TASKS_DIR/*.yaml`
- no-matchなら即exit1 (Python3を完全スキップ)
- 計測: grep no-match = 49ms → 236ms → 61ms = **74%削減**

### H2: matching files only渡し (中インパクト)
- grep matchした1-2ファイルのみPython3に渡す
- 全ファイルload不要 → python3起動+1ファイルload = 87ms
- match case: 183ms → 87ms = **52%削減**

### H3: existing_assigned Python3 → awk (中インパクト)
- WRITE subshell内のPython3呼出し(lines 349-355)をawk 1行に代替
- python3起動87ms削減 (ただしこのパスはDEPLOY時のみ)

### H4: IDLE_NINJA Python3 → awk/bash (低優先)
- round-robinロジック複雑。リスク高め
