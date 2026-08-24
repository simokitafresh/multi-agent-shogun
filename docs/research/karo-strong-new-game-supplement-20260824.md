# 家老 strong-new-game 追補 — 2026-08-24

## 起動スループット

`gate_queue_yaml_parse.sh` は完了済みreport群の再parseをやめ、live taskが指すreportだけを検査する。
本番実測は44.24秒から4.14秒へ短縮（90.6%）。remote `89769bcdd`、CI `32699598385` GREEN。

origin: [[karo_strong_new_game_20260824]] -> [[startup_gate_throughput]] -> [[live_report_only_parse_90_6pct]]

## insights pending保持

`queue/insights.yaml` はstatusを持つため、件数だけで先頭を退避する汎用rotationへ渡さない。
設定対象から除外し、`yaml_auto_archive.sh` でも明示拒否する。339件・pending 82件・重複0へ復元済み。
remote `8c3f0dc53`、CI `32702169406` GREEN。

origin: [[pending_insight_eviction]] -> [[generic_count_rotation_forbidden]] -> [[status_aware_reflux_SSOT]]
