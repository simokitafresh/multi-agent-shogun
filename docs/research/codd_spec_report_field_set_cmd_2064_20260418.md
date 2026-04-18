# report_field_set.sh CoDD Spec (cmd_2064)

- cmd: cmd_2064
- 実施者: hanzo
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)
- 作成: 2026-04-18

## 対象

- `scripts/report_field_set.sh`

## before 計測

- 条件:
  - /tmp上の隔離 YAML fixture
  - scalar hot path: `bash scripts/report_field_set.sh <report> status acknowledged`
  - scalar nested: `bash scripts/report_field_set.sh <report> result.summary "test text"`
- 実測 (10回):
  - status: 16, 15, 13, 15, 15, 13, 15, 16, 18, 17 ms
  - result.summary: 15, 17, 18, 17, 15, 15, 14, 13, 15, 13 ms
- median: status ~15ms, result.summary ~15ms

参考:
- cmd_1966(saizo 2026-04-16): 66-70ms → 11ms(`-83%`, scalar hot path). 現環境では15ms
- 測定値は先行specsより高め(WSL2環境差/clock jitter)

## ボトルネック

### B1: SCRIPT_DIR サブシェル(1.2ms)

現在のコード:
```bash
_script_path="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_script_path%/*}/.."
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)"
```

`$(cd ... && pwd -P)` で subshell fork + exec = 1.2ms/100回計測で確認。
同パターンの他スクリプト(task_deploy.sh, cmd_quality_log.sh等)では既に string ops 化済み。

修正: `[[ ... != /* ]] && ... "$PWD/$_rfs_self"` + `${...%/scripts/report_field_set.sh}`

## リファクタ方針

1. SCRIPT_DIR をstring ops化(B1)。
2. yaml_field_set.sh の遅延ロードはそのまま維持(fast path で不要)。
3. fast path / slow path の分岐は変更しない。

## 実装

```bash
# Before
_script_path="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_script_path%/*}/.."
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)"

# After
_rfs_self="${BASH_SOURCE[0]:-$0}"
[[ "$_rfs_self" != /* ]] && _rfs_self="$PWD/$_rfs_self"
SCRIPT_DIR="${_rfs_self%/scripts/report_field_set.sh}"
```

## after 計測(実装後)

- 実測 (10回):
  - status: 13, 16, 14, 11, 11, 13, 14, 12, 13, 11 ms → median ~13ms
  - result.summary: 13, 12, 12, 12, 11, 11, 13, 17, 12, 12 ms → median ~12ms

## 結果

- status: `~15ms → ~13ms` (`-13%`, median)
- result.summary: `~15ms → ~12ms` (`-20%`, median)
- 悪化なし。全テストPASS(22/22)

## 検証

- `bash -n scripts/report_field_set.sh`
- `bats tests/unit/test_report_field_set_validation.bats tests/unit/test_report_field_set_multiline.bats tests/unit/test_report_field_set_bc_validation.bats`
- `bats tests/test_gate_report_format.bats`
