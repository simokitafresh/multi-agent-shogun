<!-- last_updated: 2026-04-09 -->
# Infrastructure Performance Audit — 索引

> 殿指示(2026-04-02): hook/script/testの未着手最適化領域調査。詳細 → `docs/research/gunshi-infra-perf-audit-20260402.md`

## P1（最優先）

| 対象 | 問題 | 効果 | 詳細 |
|------|------|------|------|
| deploy_task.sh | yaml.safe_load 7箇所残存 | 40-60%高速化(毎配備) | §1.1 |
| bats teardown | 空関数→tmpdir未削除→OOM 4.3GB | 1行修正でOOM解消 | §3.1 |

## P2

| 対象 | 問題 | 効果 | 詳細 |
|------|------|------|------|
| archive_completed.sh | Python glob+yaml.safe_load loop | 50-70%高速化 | §1.2 |
| cmd_complete_gate.sh | 二重grep 4箇所 | 30-40%高速化 | §1.3 |
| gate_gunshi_report_precheck.sh | 13個python3 -c | 90%削減 | §3.2 |
| pre-bash hook | project+user二重発火 | 120ms/bash削除 | §2.1 |

## P3

| 対象 | 問題 | 詳細 |
|------|------|------|
| pre-bash Python guard | 80%はpure bashで判定可能 | §2.2 |
| search guard | 無条件出力（条件分岐未実装） | §2.3 |
| startup gate重複読み | 3 gate合計68 file ops | §3.3 |

## 解消済み

- PostToolUse Hook: 4個実装済み（過去の「最大ギャップ」解消）

## 手法テンプレート

inbox_mark_read.sh: yaml.safe_load除去+1パス統合で28%高速化(57ms→41ms)。全P1/P2対策の基本パターン。
