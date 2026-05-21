# 隠れたインフラバグ なぜなぜ7回: STALL-GHOST + assumption_invalidation MISSING
<!-- generated: 2026-05-21T18:54:00+09:00 by gunshi idle analysis -->

## バグ1: STALL-GHOST 172件

### なぜなぜ7回

| # | なぜ | 答え |
|---|------|------|
| 1 | STALL-GHOSTが172件発生 | status=in_progress/assignedだがtask_id空と判定 |
| 2 | task_idが空 | task YAMLにtask_idフィールドが存在しない |
| 3 | task_idがない | karo_direct配備がcmd_idのみ設定 |
| 4 | cmd_idしかない | deploy_task.shのkaro_direct経路がtask_idを生成しない |
| 5 | ninja_monitorがcmd_idを検索しない | L2105-2107でsubtask_id→task_id→_ac_task_idのみ |
| 6 | cmd_idが対象外 | 設計時にkaro_direct配備のフィールド名を想定外 |
| 7 | karo_directとninja_monitorの契約不整合 | 通常配備=task_id、karo_direct=cmd_id。インターフェース未統一 |

### 影響
- 修行中・CI修正中の忍者のstall検出が完全に無効化
- hayate 130件、saizo 22件、kagemaru 20件（修行期間に集中）

### 修正案
ninja_monitor.sh L2107の後に1行追加:
```awk
/^[ \t]*cmd_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
```

## バグ2: assumption_invalidation MISSING (karo_direct系)

### 根因
karo_direct配備の報告テンプレート生成にassumption_invalidationフィールドが含まれない。
通常配備(deploy_task.sh)ではテンプレートに自動挿入されるが、karo_direct経路は独自テンプレート。

### 影響
- gate_report_format FAIL→家老がworkaround（assumption_invalidation追記）
- 直近5件全てkaro_direct系(修行3件+CI修正2件)

### 修正案
karo_direct配備時の報告テンプレートにassumption_invalidationセクションを追加。

## 共通根因

karo_direct配備と通常配備(deploy_task.sh)のインターフェース不一致。
- フィールド名: task_id vs cmd_id
- テンプレート: assumption_invalidation有無
- 原理: 2つの配備経路が独立に進化し、共通契約が定義されていない

## 因果リンク
- → [[karo_direct]] 家老自立配備の設計
- → [[daemon_supervision]] ninja_monitorのstall検出
- → [[report_quality_protocol]] 報告テンプレート品質
