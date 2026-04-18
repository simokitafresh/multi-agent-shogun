# cmd_2034 CoDD gate batch speedup

日付: 2026-04-18  
担当: hayate

## 対象

- `scripts/gates/gate_enforcement_audit.sh`
- `scripts/gates/gate_wa_data_quality.sh`
- `scripts/gates/gate_context_freshness.sh`

## 結論

- `gate_enforcement_audit.sh`: shell 多段パイプ + settingsごとの Python 起動を、単一 Python パスへ統合。
- `gate_wa_data_quality.sh`: shell での出力捕捉を廃止し、`yaml.CSafeLoader` 優先 + wrapper dict 保持修復を追加。
- `gate_context_freshness.sh`: env override で隔離テスト可能にしつつ、ヘッダ解析を shell builtins 化して微速改善。

## Before / After

同一 fixture 上で `git show HEAD:...` の旧版と現作業ツリー版を各12回実行し、中央値で比較。

| script | Before median | After median | 差分 |
|---|---:|---:|---:|
| `gate_enforcement_audit.sh` | `73.1ms` | `36.1ms` | `-50.6%` |
| `gate_wa_data_quality.sh` | `106.6ms` | `52.9ms` | `-50.4%` |
| `gate_context_freshness.sh` | `67.1ms` | `64.8ms` | `-3.4%` |

## 変更詳細

### 1. `gate_enforcement_audit.sh`

- `CLAUDE.md` 抽出、hook JSON 走査、allowlist 照合を単一 Python 起動に集約。
- `ENFORCEMENT_AUDIT_*` override を追加し、隔離fixtureでの unit test/benchmark を可能化。
- basename 判定は従来どおり維持し、出力文面も互換維持。

### 2. `gate_wa_data_quality.sh`

- shell 変数への全出力捕捉を廃止し、Python をそのまま実行して余計な copy/grep を削除。
- `yaml.CSafeLoader` がある環境では C 実装を優先し、同一データでも parse 固定費を圧縮。
- `workarounds:` / `entries:` wrapper 付き YAML を `--fix` 時も保持するよう修正。
- `WA_FILE` override を追加し、実ログを壊さず unit test 可能化。

### 3. `gate_context_freshness.sh`

- `CONTEXT_FRESHNESS_ROOT` / `...CHECK_SCRIPT` / `...NTFY_SCRIPT` / `...TODAY` override を追加。
- ヘッダ10行走査を `head|grep|head|grep` から bash read loop + regex に置換。
- alert ntfy の宛先スクリプトも override 化し、通知有無を unit test 化。

## 検証

- `bash -n scripts/gates/gate_enforcement_audit.sh scripts/gates/gate_wa_data_quality.sh scripts/gates/gate_context_freshness.sh`
- `bats tests/unit/test_gate_meta_quality.bats`
- 実データ確認:
  - `bash scripts/gates/gate_enforcement_audit.sh` → `exit 0`
  - `bash scripts/gates/gate_wa_data_quality.sh` → `exit 1` / issue count維持
  - `bash scripts/gates/gate_context_freshness.sh` → `exit 2` / `dm-signal-ops.md` WARN維持
