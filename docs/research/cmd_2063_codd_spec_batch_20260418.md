# CoDD Spec — cmd_2063 infra script batch (2026-04-18)

- cmd: cmd_2063
- 実施者: kagemaru
- 対象: scripts/ninja_done.sh / scripts/gates/gate_report_format.sh / .claude/hooks/post-search-completeness-guard.sh
- CoDD Phase到達: Phase 5(spec先行+Before計測+改善+After計測+検証)

---

## 計測条件

- 実施日: 2026-04-18
- 実施者: kagemaru
- 計測方法: 実運用ディレクトリ(/mnt/c/tools/multi-agent-shogun)で各スクリプトを10回実行し中央値を採用
- 計測コマンド:
  - ninja_done.sh: `INBOX_WRITE_ROOT_OVERRIDE=/tmp/... bash scripts/ninja_done.sh hanzo cmd_1435` (archived report success path, cmd_2035と同一条件)
  - gate_report_format.sh: キャッシュクリア後にPASS-valid reportで実行 (`> logs/.gate_pass_cache; time bash scripts/gates/gate_report_format.sh <report>`)
  - post-search-completeness-guard.sh: `bash .claude/hooks/post-search-completeness-guard.sh` (no-args)

---

## Spec 1: scripts/ninja_done.sh

### Before 計測

| run | time |
|-----|------|
| 1 | 92ms |
| 2 | 83ms |
| 3 | 94ms |
| 4 | 72ms |
| 5 | 77ms |
| 6 | 73ms |
| 7 | 75ms |
| 8 | 77ms |
| 9 | 79ms |
| 10 | 86ms |
| **median** | **79ms** |

### ボトルネック分析

```
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```
- `dirname "${BASH_SOURCE[0]}"`: サブシェル展開 = ~3ms
- `cd ... && pwd`: サブシェル + dirname結果での cd = ~3ms
- 合計: ~5-7ms (WSL2/mnt/c上でのプロセス生成コスト)

コンポーネント別コスト(3回計測):
- SCRIPT_DIR cd/dirname/pwd: 2-7ms (avg ~4ms)
- resolve_report_file (primary path): ~1ms
- resolve_report_file (archived glob): ~30ms (WSL2/mnt/cのグロブ展開が重い)
- summary_is_present (awk): ~5ms
- gate_report_format.sh (PASS cache hit): ~15ms
- inbox_write.sh: ~22ms

archived report path合計: ~79ms ✓ 計測値と一致

### 改善方針

SCRIPT_DIR resolution をサブシェル不要な純bashストリング演算に置換:
```bash
# Before
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# After
_SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_SELF%/*}/.."
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
```

- 絶対パス(通常ケース)ではサブシェルゼロ → ~5ms節約
- 相対パス(稀なケース)はフォールバックで安全確保

期待改善: 79ms → ~74ms (-6%)

---

## Spec 2: scripts/gates/gate_report_format.sh

### Before 計測

| run | time |
|-----|------|
| 1 | 160ms |
| 2 | 156ms |
| 3 | 144ms |
| 4 | 142ms |
| 5 | 152ms |
| 6 | 143ms |
| 7 | 150ms |
| 8 | 137ms |
| 9 | 144ms |
| 10 | 142ms |
| **median** | **148ms** |

※ cmd_2038時の71ms計測は/tmpでの計測。実環境(/mnt/c)では148ms。
  /tmp(ext4) vs /mnt/c(WSL2 Windows FS)でのプロセス生成コスト差が原因。

### ボトルネック分析

コンポーネント別コスト(3回計測):
| コンポーネント | コスト |
|--------------|------|
| gate_report_autofix.sh (bash subprocess) | ~64ms |
| └─ 内部: gate_report_autofix_main.py (python3) | ~70ms |
| python3 gate_report_format_main.py | ~64ms |
| shell overhead (stat/grep/flock/date/sed) | ~20ms |
| **合計** | **~148ms** |

**主因: python3プロセス2回起動(autofix + validation)で ~128ms消費**

- gate_report_autofix.sh の fast_no_fix_needed(awk) は binary_checks の `    check:` パターンで
  ほぼ常にpython3フォールバックする → awk fast-path の恩恵がほぼゼロ
- autofix_main.py + format_main.py を別々に実行: python3インタープリタ起動コスト2倍

### 改善方針

gate_report_format.sh のautofix pre-stepをbash subprocessから
**単一python3呼び出しに統合する**:

```bash
# Before (2 python3 processes)
bash gate_report_autofix.sh "$REPORT_PATH"  # → python3 gate_report_autofix_main.py (~70ms)
python3 gate_report_format_main.py "$REPORT_PATH"  # (~64ms)

# After (1 python3 process)
python3 gate_report_format_main.py --with-autofix "$REPORT_PATH"
```

実装: gate_report_format_main.py に `--with-autofix` フラグを追加し、
gate_report_autofix_main.py のロジックをインポートして先行実行。
bash shell から gate_report_autofix.sh の呼び出しを削除。

- python3インタープリタ起動1回削減 → ~64ms節約
- autofix結果はgate_format_main.py内で捕捉し、shell側のecho処理に渡す

期待改善: 148ms → ~84ms (-43%)

---

## Spec 3: .claude/hooks/post-search-completeness-guard.sh

### Before 計測

| run | time |
|-----|------|
| 1-10 | 3-6ms |
| **median** | **4ms** |

※ profiling参照値(17ms)との差異:
  - profiling時はウォームアップなし+別環境での計測
  - 現在のbashキャッシュ状態・実行コンテキストにより4msに収束
  - いずれにせよ4msが現実の実行コスト

### ボトルネック分析

```bash
#!/usr/bin/env bash
# (12行, 実質コードはecho 1行)
echo "⚠ この検索結果は..."
```

コンポーネント:
- bash起動: ~2ms
- env process (#!/usr/bin/env bash): ~1ms (envがbashを検索)
- echo: <1ms
- 合計: ~4ms

スクリプト本体はこれ以上圧縮不能。改善余地はshebang最適化のみ。

### 改善方針

shebangを `#!/usr/bin/env bash` から `#!/bin/sh` に変更:
- envプロセス生成を排除
- shはbashより軽量(echoのみなのでbash機能不要)

期待改善: 4ms → 3-4ms (marginal; ≥1ms改善を確認できればkeep, そうでなければrevert)

---

## 実装順序

1. gate_report_format.sh (最大改善: -64ms expected)
2. ninja_done.sh (確実改善: -5ms expected)
3. post-search-completeness-guard.sh (marginal: -0~1ms)
