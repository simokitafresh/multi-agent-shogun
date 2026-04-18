# cmd_2038 CoDD Batch

対象:
- `scripts/gates/gate_report_format.sh`
- `scripts/lib/yaml_field_set.sh`
- `scripts/gates/gate_pd_sync.sh`

## 計測条件

- 実施日: 2026-04-18
- 実施者: hayate
- 計測方法: before/after の複製ツリーを `/tmp` に用意し、同一 fixture で 15-20 回反復して median を採用
- 目的: 高頻度の infra hot path から bash 解析コスト、Python 起動、汎用 awk 経路の無駄を削る

## 変更要約

### `scripts/gates/gate_report_format.sh`

- 大型の `python3 -c "..."` を `gate_report_format_main.py` へ外出し
- bash 側は orchestration のみへ縮小し、起動時の script parse 負荷を削減
- `PASS/FAIL` 判定の後段は shell 内分岐に寄せ、`grep/head/sed` の常時起動を削減

結果:
- `76.0ms -> 71.2ms` (`-6.3%`, valid report / cache miss median)

### `scripts/lib/yaml_field_set.sh`

- `lock_path.sh` の source をやめ、hot path 用に lock helper を内蔵
- `task.status` のような common case 向けに `map block + scalar` 専用の軽量 awk path を追加
- list item / root fallback / post-write verification は既存の安全経路を維持

結果:
- `14.9ms -> 13.7ms` (`-8.1%`, `task status done` median)

### `scripts/gates/gate_pd_sync.sh`

- `pending_decisions.yaml` 走査を Python から awk へ置換
- 結果分解の `sed -n` を廃止し、`mapfile` で 2 行結果を受ける形へ簡素化
- `context_synced: false` の全件 BLOCK と target PD の `SYNCED/NOT_SYNCED/NOT_FOUND` 判定を既存仕様のまま維持

結果:
- `35.3ms -> 7.2ms` (`-79.6%`, synced fixture median)

## 検証

- `bats tests/test_gate_report_format.bats`
- `bats tests/unit/test_report_template_gate_compat.bats`
- `bats tests/unit/test_session_state.bats`
- `bats tests/unit/test_yaml_field_set.bats`
- `bats tests/unit/test_pending_decision_write.bats`
- `bats tests/unit/test_gate_pd_sync.bats`
