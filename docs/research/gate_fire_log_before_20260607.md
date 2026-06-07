# gate_fire_log.sh 速度改善修行2回目 — before計測

- 作成: kotaro / 2026-06-07
- cmd: cmd_training_speed_gate_fire_log_20260607181500_normal
- 前回: cmd_training_speed_gate_fire_log_20260607001500 (cksum→bash文字列化, mktemp除去)

## 計測環境

- ファイル: scripts/gate_fire_log.sh (75行)
- 入力: logs/gate_fire_log.yaml (1005行, 232KB)
- 計測方式: cold(キャッシュ削除+sleep 2s後 `time bash`)

## cold計測結果（5回）

| run | real(ms) |
|-----|----------|
| 1 | 215 |
| 2 | 96 |
| 3 | 108 |
| 4 | 177 |
| 5 | 149 |

**平均: 149ms / 中央値: 149ms / 最小: 96ms / 最大: 215ms**

高変動(σ≒45ms) → WSL2 /mnt/c NTFSのI/O変動特性

## ボトルネック分解

| 処理 | 計測値 | 比率 |
|------|--------|------|
| awk 1パス (1005行) | 46ms | 31% |
| fail_live stat()ループ (5パス) | 66ms | 44% |
| stat cache_sig取得 | 4ms | 3% |
| rm -f /tmp glob | 21ms | 14% |
| bash起動・その他 | 12ms | 8% |
| **合計** | **149ms** | 100% |

## 出力

```
healed=145 fail_total=112 fail_live=5
```

## ボトルネック仮説

### H1: fail_live stat()ループ (優先度: 高)
- 現状: 5パス × ~13ms/stat = 65ms (WSL2 /mnt/cシリアライズ)
- ログ増大時: 100パス × 13ms = 1300ms (将来ボトルネック)
- 改善: 1 Python subprocess で全pathoを一括チェック → プロセス起動1回に削減

### H2: live_paths に healed ファイルも含む (最適化機会)
- 現awk: FAIL → live_paths追加、PASS時でも削除しない
- healed(145件)のうち多くはarchive済みで stat不要 だが全パス分ループ
- `delete live_paths[fname]` 追加でPASS→削除 → stat対象を未解決FAILのみに限定
- 副作用: fail_live の語義が「現存するFAIL報告(未解決のみ)」に変化

### H3: rm -f /tmp glob (軽微)
- /tmpに他のshogun_*ファイルがある場合は高コスト
- 現在0ファイル = 21ms (glob評価のみ)

### H4: task says "after:2523ms" の出所
- 現在のcold計測は96-215ms。2523msは再現できず
- 仮説: 月631s = 250回/月 × 2523ms/回 → 過去の大きなYAMLでの計測値
  or gate_gunshi_startup.sh Check 11の inline Python実行時間(並行I/O競合)
- ログが10,000行・100 live fail pathsになった場合: 100×13ms = 1300ms + awk ~460ms ≒ 1760ms
- H1対策(batch stat)はスケール時の2523ms防止になる

## 次ステップ

- AC2: codd extract → elicit → dag verify
- 主要改善: H1(batch stat) + H2(healed削除) を最小変更で実装
