# inbox_write.sh CoDD Spec (cmd_2064)

- cmd: cmd_2064
- 実施者: hanzo
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)
- 作成: 2026-04-18

## 対象

- `scripts/inbox_write.sh`

## before 計測

- 条件:
  - test mode (INBOX_WRITE_ROOT_OVERRIDE=/tmp/xxx): `bash scripts/inbox_write.sh karo "bench" wake_up hanzo bench`
  - production mode (no override, real cwd): same command without env
- 実測 (10回):
  - test mode: 22, 22, 19, 19, 19, 18, 18, 18, 17, 19 ms → median ~19ms
  - production mode: 31, 30, 29, 28, 28 ms → median ~29ms

参考:
- cmd_2036(hayate 2026-04-18): 29ms → 26ms(`-10.3%`, /tmp fixture average)
- cmd_1979(hayate 2026-04-16): 50ms → 22ms(`-56%`, isolated)
- cmd_1960(saizo 2026-04-16): 78ms → 50ms(`-35.9%`, write path)

## ボトルネック

### B1: SELF_SCRIPT_PATH サブシェル3本 (3.1ms/call, 常時発生)

現在:
```bash
SELF_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
```

3 subshells: `dirname`, `cd+pwd`, `basename`。100回計測で306ms = 3.1ms/call。
INBOX_WRITE_ROOT_OVERRIDE 設定時も常に実行される無駄なコスト。

### B2: SCRIPT_DIR フォールバックのサブシェル2本 (1.85ms/call, production only)

現在:
```bash
SCRIPT_DIR="${INBOX_WRITE_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
```

INBOX_WRITE_ROOT_OVERRIDE 未設定時のみ実行。100回計測で185ms = 1.85ms/call。

合計: test mode -3.1ms、production mode -4.95ms の改善見込み。

## リファクタ方針

1. SELF_SCRIPT_PATH を string ops 化(B1): 全経路で3.1ms削減
2. SCRIPT_DIR フォールバックを string ops 化(B2): production で追加1.85ms削減
3. SELF_SCRIPT_PATH の用途は recursive call (`bash "$SELF_SCRIPT_PATH"`) → 絶対パスが必要。`$PWD` で解決。

## 実装

```bash
# Before
SCRIPT_DIR="${INBOX_WRITE_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SELF_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# After
_iw_self="${BASH_SOURCE[0]:-$0}"
[[ "$_iw_self" != /* ]] && _iw_self="$PWD/$_iw_self"
SCRIPT_DIR="${INBOX_WRITE_ROOT_OVERRIDE:-${_iw_self%/scripts/inbox_write.sh}}"
SELF_SCRIPT_PATH="$_iw_self"
```

## after 計測(実装後)

- test mode (10回): 21, 19, 17, 16, 17, 15, 16, 15, 15, 16 ms → median ~16ms
- production mode (5回): 22, 24, 27, 26, 22 ms → median ~24ms

## 結果

- test mode: `~19ms → ~16ms` (`-16%`, median)
- production mode: `~29ms → ~24ms` (`-17%`, median)
- 悪化なし。全テストPASS(22/22)

## 検証

- `bash -n scripts/inbox_write.sh`
- `bats tests/unit/test_inbox_write.bats`
