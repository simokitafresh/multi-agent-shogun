# cmd_4123 self-retro signal preservation

- verified_at: 2026-07-24 (N=345 records, updated from N=188)
- SSOT: `logs/self_retro.jsonl` (345 JSON records as of 2026-07-24)
- change boundary: JSONL recording and validation remain unchanged; only known zero-signal `INSIGHT_FIX_KNOWN` delivery is suppressed

## 発火経路全数列挙 (grep self_retro/INSIGHT_FIX_KNOWN scripts/)

| ファイル | 行 | 用途 |
|---|---|---|
| `scripts/lib/defense_overhead_writer.sh:130` | INSIGHT_FIX_KNOWN=true | self_retro_write 内、抑止ガードあり |
| `scripts/throughput_scan.sh:515` | INSIGHT_FIX_KNOWN=1 | throughput scan内（別経路） |
| `scripts/insight_write.sh:442` | bulletin投稿 | 上流がINSIGHT_FIX_KNOWNの場合のみ |

抑止ガード実装: `_self_retro_should_emit_insight` (lines 68-91)
```
known_template = seen >= threshold (default 3)
zero_signal = wall_ms==0 OR max(phase_ms)==0
suppress if: known_template AND zero_signal → exit 1 (bash: false → no insight_write.sh call)
```

## Production-ledger reconciliation (N=345)

| cause_class | count | wall_ms=0 | wall_ms>0 | 判定 |
|---|---:|---:|---:|---|
| gate_clear | 128 | 128 (100%) | 0 | ゼロ信号 → 抑止対象 |
| report_completion | 5 | 5 (100%) | 0 | ゼロ信号 → 抑止対象 |
| completion_pipeline | 117 | 0 | 117 (100%) | 実信号 → 発火継続 |
| review_notify | 95 | 0 | 95 (100%) | 実信号 → 発火継続 |

## 是正前→是正後 3数値

| 指標 | 是正前 (simulated) | 是正後 | 差分 |
|---|---:|---:|---:|
| (a) INSIGHT発火件数 | 4 | **2** | **-2件** |
| (b) 定型文比率 | 2/4 = 50% | 0/2 = **0%** | **-50pt** |
| (c) completion_total中央値 | 16,379ms | 16,379ms | 0ms |

- 是正前 4件: gate_clear:1 + report_completion:1 + completion_pipeline:1 + review_notify:1
- 是正後 2件: completion_pipeline:1 + review_notify:1 (実信号のみ)

## Completion pipeline signal (N=117)

| 必須4項目 | 値 |
|---|---:|
| dashboard 構成比 (中央値ベース) | **68.5%** (11,224ms) |
| ntfy 構成比 | 11.5% (1,878ms) |
| inbox_archive 構成比 | 1.4% (232ms) |
| completion_total 中央値 | **16,379ms** |

dashboard が支配フェーズ。速度改善ターゲット = dashboard最適化。

## Binary evidence

- Emitter inventory: `INSIGHT_FIX_KNOWN` in scripts/ → 3箇所、self_retro経路はdefense_overhead_writer.sh:130のみ
- 境界fixture: test 10/11 "production ledger canonical" — gate_clear(wall_ms=0, seen=128)→suppress, completion_pipeline(wall_ms>0)→emit
- 境界fixture: test 11/11 "known zero-signal template" — 合成データ二値固定検証
- `bats tests/unit/test_defense_overhead_writer.bats` = 11/11 PASS, FAIL 0, SKIP 0
- `bash -n scripts/lib/defense_overhead_writer.sh` = exit 0
- `bash -n scripts/insight_write.sh` = exit 0
