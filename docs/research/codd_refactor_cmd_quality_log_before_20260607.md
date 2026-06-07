# CoDD Refactor: cmd_quality_log.sh — Before 計測 (2026-06-07)

## 計測条件
- 対象: `scripts/cmd_quality_log.sh`
- 計測環境: WSL2 /mnt/c NTFS
- Cold測定方法: 同一bashセッション内での連続実行（OSページキャッシュ: 部分的にwarm）

## Before 計測結果 (full metadata経路)

| 回 | 実行時間 |
|----|---------|
| 1 | 509 ms |
| 2 | 503 ms |
| 3 | 719 ms |
| 4 | 578 ms |
| 5 | 649 ms |

**中央値: 578 ms / 平均: 592 ms**

> 前セッション(2026-06-06 hayate)のafter: 3160ms/100回 = 31.6ms/回 (FAST_METADATA=1環境)
> 本セッションは FAST_METADATA=0 (full metadata) での計測のため値が異なる

## ボトルネック分析

### 各関数の個別計測

| 関数 | 計測時間 |
|------|---------|
| fetch_gunshi_verdict | 11-17 ms |
| fetch_ninja_blockers | 585-784 ms |
| fetch_ac_count | <20 ms (推定, 83行ファイル) |
| flock + write | <10 ms |

**支配的ボトルネック: `fetch_ninja_blockers` (全体の ~85%)**

### fetch_ninja_blockers の問題

```bash
# 現行実装: 全102ファイルをawk処理
for report in "$reports_dir"/*_report_*.yaml; do
    [[ -f "$report" ]] || continue
    report_files+=("$report")
done
awk -v cid="$CMD_ID" '...' "${report_files[@]}"
```

- レポートファイル総数: 102個 (平均 5447 bytes, 合計 543 KB)
- WSL2のNTFS bridgeでは1ファイルあたり約5-8ms のopen overhead
- 102ファイル × ~6ms = ~600ms
- 現在のblocked reports数: **0件** (全102ファイルで blocked=0)

### 最適化案: filename-based glob

ファイル命名規則: `{ninja}_report_{cmd_id}[_{timestamp}].yaml`

特定のCMD_IDに関係するファイルは、ファイル名で直接絞り込める:
```bash
# 最適化後: CMD_ID一致ファイルのみをglobで開く
for r in "$reports_dir"/*_report_${CMD_ID}*.yaml; do
    [[ -f "$r" ]] || continue
    grep -q "status: blocked" "$r" 2>/dev/null && count=$((count+1))
done
```

### 速度比較

| アプローチ | 時間 |
|-----------|------|
| 現行 (全102ファイルawk) | 585-784 ms |
| grep -rl (全102ファイル) | 659-750 ms |
| filename-glob (マッチ0件) | 9-13 ms |
| filename-glob (実ファイル1件) | 10 ms |

**改善期待値: 585ms → 10ms (-98%)**

## 仮説まとめ

1. **主因**: `fetch_ninja_blockers`が全reportファイルを無差別にスキャンしている
2. **WSL2固有の増幅**: NTFS bridgeのfile open overheadが支配的
3. **根本的無駄**: cmd_idはファイル名に含まれており、glob絞り込みで大幅削減可能
4. **現在の blocked=0**: ほぼ常に0なのに全ファイルをスキャンしている
