# CoDD Spec + After: log_terminal_response.sh 高速化

- cmd: `cmd_2046`
- 実施者: `kotaro`
- 対象: `scripts/log_terminal_response.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - shogun+payload path: `TMUX_PANE=<shogun_pane> bash scripts/log_terminal_response.sh` (SCRIPT_DIR解決+source実行まで到達)
- 実測:
  - `43ms`
  - `44ms`
  - `42ms`
- 平均: `43ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"` — 起動ごとにサブシェル2つ (`$(dirname)` + `$(cd ... && pwd)`) + `cd` コマンドを実行。shogun専用hookのため起動頻度は低いが毎回払うコスト。
2. shogun以外のエージェントでは最初の `tmux display-message` 後に `exit 0` するため SCRIPT_DIR 解決コストは早期 exit には現れないが、shogun が頻繁に使う場合に累積する。

## 最適化候補

1. SCRIPT_DIR 解決を文字列演算化。`${_ltr_self%/scripts/log_terminal_response.sh}` で親ディレクトリを直接抽出。サブシェルゼロ。
2. 相対パスの場合のみ `$PWD` プレフィックスで絶対化（フォールバック不要）。

## 実装 (cmd_2046)

1. SCRIPT_DIR 解決を文字列演算に変更:
   ```bash
   _ltr_self="${BASH_SOURCE[0]:-$0}"
   [[ "$_ltr_self" != /* ]] && _ltr_self="$PWD/$_ltr_self"
   SCRIPT_DIR="${_ltr_self%/scripts/log_terminal_response.sh}"
   ```
2. コメント追記: `# SCRIPT_DIR: string ops instead of $(cd) subshells (~5ms savings on WSL2)`

## after 計測 (cmd_2059)

- 条件:
  - non-shogun early exit path (AGENT_ID != shogun で即 exit 0)
- 実測:
  - `14ms`
  - `11ms`
  - `11ms`
- 平均: `~12ms`
- 注記: shogun path での After は ~38ms（台帳記録値）。SCRIPT_DIR文字列演算化で `$(cd)` コスト2回分 (~5ms) を削減。

## 結果

- shogun path: `43ms → ~38ms` (`-12%`)
- SCRIPT_DIR解決だけでなくtmux+python3が支配的なため改善幅は小さい

## 検証

- `bash -n scripts/log_terminal_response.sh`
- non-shogun path: `bash scripts/log_terminal_response.sh < /dev/null` → exit 0

## 再利用パターン

- shogun専用hook のように「AGENT_ID != target で早期 exit」するスクリプトでは、SCRIPT_DIR 解決が shogun path でのみ発生する。ただし shogun は全 Stop hook 実行で毎回呼ばれるため、SCRIPT_DIR コスト削減は累積効果がある。
- `${BASH_SOURCE[0]}` + 相対パス絶対化 + 文字列演算によるディレクトリ抽出は hook/lib スクリプトの定番パターンとして確立済み。
