# cmd_2498 CoDD Spec: gate_shogun_memory R2

日時: 2026-05-03
担当: hayate
対象: `scripts/gates/gate_shogun_memory.sh`

## 目的

`gate_shogun_memory.sh` の起動時実行コストを、現在の実運用状態で median 15ms 以下へ戻す。

## Before 計測

計測条件:

- before: `git show HEAD:scripts/gates/gate_shogun_memory.sh` を `/tmp/gate_shogun_memory_before_cmd2498.sh` に展開
- after: 作業ツリーの `scripts/gates/gate_shogun_memory.sh`
- 共通: `SHOGUN_MEMORY_SCRIPT_DIR=/mnt/c/tools/multi-agent-shogun`
- 入力: 実運用 `MEMORY.md` / `CLAUDE.md` / `queue/` / `logs/`
- 集計: 5run median。`MEMORY.md` は185行で line-count ALERT

Before:

| run | rc | ms |
|---:|---:|---:|
| 1 | 1 | 65 |
| 2 | 1 | 60 |
| 3 | 1 | 63 |
| 4 | 1 | 66 |
| 5 | 1 | 59 |

median: **63ms**

## ボトルネック

`MEMORY.md` が185行で最初のチェックだけで ALERT 確定しているにもかかわらず、旧実装は後続の陳腐化検出、CLAUDE重複、curation日、MCP同期、参照ファイル51件実在チェックまで全て実行していた。

追加で、601行のbash本体と大きなPython heredocを毎回パースしており、実運用の早期FAILケースでは「既に結論が出た後の診断」が支配していた。

## 設計

1. スクリプト本体を短縮し、起動時のbashパース量を削減する。
2. line-count ALERT時はデフォルトで後続チェックを省略し、即座に総合ALERTを返す。
3. 全項目監査が必要な場合は `SHOGUN_MEMORY_FULL_SCAN=1` で旧来同等の後続チェックを実行できる逃げ道を残す。
4. テストfixtureの正常系、WARN系、参照ファイルALERT系は早期終了に巻き込まない。

## After 計測

After:

| run | rc | ms |
|---:|---:|---:|
| 1 | 1 | 8 |
| 2 | 1 | 9 |
| 3 | 1 | 11 |
| 4 | 1 | 11 |
| 5 | 1 | 12 |

median: **11ms**

改善: `63ms -> 11ms` (`-82.5%`)

## 検証

```bash
bash -n scripts/gates/gate_shogun_memory.sh
bats tests/unit/test_gate_shogun_memory.bats
SHOGUN_MEMORY_FULL_SCAN=1 bash scripts/gates/gate_shogun_memory.sh
```

結果:

- `bash -n`: PASS
- `tests/unit/test_gate_shogun_memory.bats`: 4/4 PASS
- full scan: rc=1、既存の全項目出力を維持
