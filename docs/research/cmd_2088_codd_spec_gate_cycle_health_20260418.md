# CoDD Spec: gate_cycle_health.sh 正規再改善
# cmd_2088 / tobisaru / 2026-04-18

## 対象
- File: `scripts/gates/gate_cycle_health.sh`
- Lines: 201
- Before median: 192ms (5run, /mnt/c WSL2 NTFS)

## ボトルネック分析

| セクション | 内容 | 計測 |
|---|---|---|
| S1 insights check | grep -c × 2 | ~10ms |
| S2 idle check | grep, cut, grep -c | ~9ms |
| S3 GATE未処理 check | stat(100files)+awk getline | **~219ms** (stat単体) |
| S4 PI原理率 | awk dm-signal.yaml | ~5ms |
| overhead | 起動・出力・date等 | ~39ms |

**真のボトルネック**: S3の `stat -c '%Y %n' "${_REPORT_FILES[@]}"` で100ファイルをstatするWSL2 NTFS I/O。

詳細:
- reportファイル全100件に対してstat一括実行: ~219ms
- 実際にgetlineで読むのは「24h内かつcleared_ids外」= 11件のみ
- getline 11件: ~56ms
- CLEARED_IDS取得(grep+grep-oE+sort): ~10ms
- 24h以内のファイルは100件中44件

## 改善設計 (B1)

**stat対象ファイルを100→44に削減**: `find -mmin -1440` で先に24h以内ファイルをフィルタ

```
Before:
  glob(100files) → stat(100files, ~219ms) → awk cutoff+cleared → getline(11files)

After:
  find -mmin -1440(~63ms) → mapfile(44files) → stat(44files, ~57ms) → awk cleared → getline(11files)
```

変更箇所:
- `shopt -s nullglob / _REPORT_FILES=( queue/reports/*_report_*.yaml )` を削除
- `mapfile -t _RECENT < <(find queue/reports/ -name "*_report_*.yaml" -mmin -1440 2>/dev/null || true)` に置換
- `stat -c '%Y %n' "${_REPORT_FILES[@]}"` → `stat -c '%Y %n' "${_RECENT[@]}"`
- awk内の `cutoff` チェックは廃止(findで既にフィルタ済み)、`mtime` フィールドも不要
  - ただし `mtime` はcutoffチェックに使っていたのでfindでフィルタ済みなら不要
  - stat の `%Y` と awk の `cutoff` チェックを廃止できる

実際の変更:
```bash
# Before
shopt -s nullglob
_REPORT_FILES=( queue/reports/*_report_*.yaml )
shopt -u nullglob
if [ ${#_REPORT_FILES[@]} -gt 0 ]; then
    PENDING_REPORTS=$(stat -c '%Y %n' "${_REPORT_FILES[@]}" 2>/dev/null \
        | awk -v cids="$_CLEARED_IDS" -v cutoff="$_CUTOFF" '
            BEGIN{n=split(cids,c,"\n");for(i=1;i<=n;i++)clr[c[i]]=1}
            {
                mtime=$1; path=$2
                fname=path; sub(".*/","",fname)
                sub(".*_report_","",fname); sub("\\.yaml$","",fname); sub("_[a-z]*$","",fname)
                if(clr[fname]) next
                if(mtime+0 <= cutoff+0) next
                while ((getline line < path) > 0) {
                    if(line ~ /^status: completed/) { count++; break }
                }
                close(path)
            }
            END{print count+0}
        ')
fi

# After
mapfile -t _RECENT_REPORTS < <(find queue/reports/ -name "*_report_*.yaml" -mmin -1440 2>/dev/null || true)
if [ ${#_RECENT_REPORTS[@]} -gt 0 ]; then
    PENDING_REPORTS=$(printf '%s\n' "${_RECENT_REPORTS[@]}" \
        | awk -v cids="$_CLEARED_IDS" '
            BEGIN{n=split(cids,c,"\n");for(i=1;i<=n;i++)clr[c[i]]=1}
            {
                path=$0
                fname=path; sub(".*/","",fname)
                sub(".*_report_","",fname); sub("\\.yaml$","",fname); sub("_[a-z]*$","",fname)
                if(clr[fname]) next
                while ((getline line < path) > 0) {
                    if(line ~ /^status: completed/) { count++; break }
                }
                close(path)
            }
            END{print count+0}
        ')
fi
```

stat廃止: pathリストのみawkに渡す→awk内でgetlineのみ
cutoffチェック廃止: findの-mmin -1440が代替

## 期待改善
- stat(100files, 219ms) → find(44files, 63ms) + stat廃止
- S3削減: ~156ms節約(stat廃止) - find追加(63ms) = ~93ms節約
- 全体: 192ms → ~100ms (理論値。実測で確認)

## リスク
- find -mmin は「分」単位。-mmin -1440 = 1440分 = 24h。等価。
- findのWSL2コスト: 63ms(実測)。stat節約219-57=162msより小さい。ネット節約≈99ms
- 既存テスト: batsで確認

## 変更不要箇所
- S1, S2, S4: 高速のまま
- CLEARED_IDS取得: 既に最適(grep+sort)
- cooldown, inbox_write, ntfy部分: ロジック不変
