# cmd_3875 `/mnt/c` disk watch

## 結論

`scripts/lib/disk_space_watch.sh`をdf計測と閾値判定のSSOTとし、将軍・家老startup gateと`ninja_monitor.sh`へ接続した。既定値は警告50GB、危険20GB。`DISK_WATCH_WARN_GB` / `DISK_WATCH_DANGER_GB` / `DISK_WATCH_MOUNT_PATH`で調整できる。

危険域はstartup総合判定をBLOCKへ固定し、通常作業開始を止める。常駐監視はWARN/BLOCK遷移を家老inboxの`disk_space_alert`へ変換し、30分の重複抑止後に再通知する。発報は`logs/gate_fire_log.yaml`へ`gate: "disk_space_watch"`として記録され、`scripts/detector_fp_rate.sh`の既存gate_fire_log入力へ接続される。

## 二値証跡

| 検証 | 結果 |
|---|---|
| 60GB（警告50GB超） | `OK` |
| 40GB（警告50GB未満、危険20GB以上） | `WARN` |
| 10GB（危険20GB未満） | `BLOCK` |
| startup gate 2本が共通SSOTをsource | PASS（2/2） |
| monitorが家老通知後にgate_fire_logへBLOCK記録 | PASS |
| `bats tests/unit/test_disk_space_watch.bats` | 5 tests, FAIL 0, SKIP 0 |
| 4 shell filesの`bash -n` | PASS |

テスト正本: `tests/unit/test_disk_space_watch.bats`。

## 因果

`[[C_drive満杯20260712_2307]] -> [[事前検知層の不在]] -> [[startup_gate+ninja_monitorへdf監視組込み]]`
