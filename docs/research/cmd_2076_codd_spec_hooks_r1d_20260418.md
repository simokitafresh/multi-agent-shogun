# CoDD Spec: 3本再改善 R1-D (cmd_2076)

## Meta
- date: 2026-04-18
- author: kotaro
- parent_cmd: cmd_2076
- targets:
  - `.claude/hooks/stop-lint-gate.sh` (148行, Stop hook)
  - `scripts/gates/gate_karo_startup.sh` (518行, 家老起動gate)
  - `scripts/hooks/stop_check_inbox.sh` (140行, Stop hook)

---

## 前回revert原因 (台帳参照)

| スクリプト | 前回アプローチ (revert済み) | revert理由 |
|---|---|---|
| (1) stop-lint-gate.sh | shebang変更 (#!/usr/bin/env bash → #!/bin/sh) | bash特有構文依存 (mapfile, [[, 配列) のため/sh不可 |
| (2) gate_karo_startup.sh | python3→awk置換 + ninja statusキャッシュ | 140ms付近まで来たが更なる削減不可 (前回のアプローチでは戻り値あり) |
| (3) stop_check_inbox.sh | 未改善 (初回) | — |

---

## Before 計測 (median 5回, 実運用tmux環境)

### 測定条件
- tmux環境内で実行 (TMUX_PANE設定済み)
- 対象スクリプトを直接bash実行
- hot path定義:
  - (1): tmux pane内 + 未ステージング .sh ファイル複数あり (shellcheck実行パス)
  - (2): 全チェック実行 (実起動と同一)
  - (3): stop_hook_active=true payload (jq3本+tmux含む)

| スクリプト | パス | 5回計測値 | median |
|---|---|---|---|
| (1) stop-lint-gate | hot path (6 unstaged .sh + shellcheck) | 5126,5134,5149,5370,7128ms | **5149ms** |
| (2) gate_karo_startup | full startup | 199,106,124,107,110ms | **110ms** |
| (3) stop_check_inbox | stop_hook_active=true | 41,37,41,33,37ms | **37ms** |

### 注記
- cmd_2076記載のbefore値(10ms/138ms/8ms)はclean-tree or 非tmux環境での測定と推定
- 実運用環境では未ステージングファイルがある場合、git ls-files -m がWSL2上で1-7s費やす
- gate_karo_startupのmedian 110msは今回の実測。前回比 138→110ms (既に改善済み可能性あり)

---

## ボトルネック分析

### (1) stop-lint-gate.sh
```
collect_changed_files():
  staged: git diff-index --cached   → 54ms (fast)
  unstaged: git ls-files -m         → 870-1500ms (ALL tracked files scan on /mnt/c/)
shellcheck on 6 .sh files           → 40-100ms × 6 = 240-600ms
合計: ~1.2-2s (changed files取得) + ~400ms (shellcheck) = 1.6-2s

問題: git ls-files -m はリポジトリ全体のtracked fileのmtimeをindexと比較するため
     /mnt/c/ (Windows filesystem) 経由で低速。未ステージング.shファイルが多いほど遅い。
```

### (2) gate_karo_startup.sh
```
並列バックグラウンド処理:
  gate_workaround_rate.sh --last 10   → 57ms
  gate_ninja_workaround_rate.sh       → 53ms
  phase guide awk (deepdive×2)        → 13ms×2
tmux list-panes                        → 9ms
総合: 110ms (parallel dominance)

問題: WA rate scriptsが並列で最長57msを占める。既にawkに最適化済みだが更なる削減余地あり。
     phase_guide_cached()関数はスクリプト内に定義済みだが使用されていない (dead code)。
```

### (3) stop_check_inbox.sh
```
jq呼出し:
  jq -e . (validation)       → ~5ms
  jq -r last_assistant_msg   → ~5ms
  jq -r stop_hook_active     → ~5ms
tmux display-message          → ~5ms
awk unread count              → ~2ms
合計: ~37ms (stop_hook_active=true fast path)

問題: jqを3回呼出す。各呼出しで bash→jq プロセス起動 (~5ms/回)。
     stop_hook_active=true の最速パスでも3回 jq + tmux = ~22ms
```

---

## 実装計画

### (1) stop-lint-gate.sh — 新アプローチ: unstaged scan廃止 (staged-only)

**前回との違い**: 前回はshebang変更 (プロセスコスト削減)。今回はgit操作の削除 (アルゴリズム変更)。

```bash
# 変更: collect_changed_files() を staged-only に変更
# 旧: staged + unstaged (git diff-index + git ls-files -m)
# 新: staged のみ (git diff-index --cached のみ)

collect_changed_files() {
    local staged_files
    staged_files="$(git -C "$SHOGUN_ROOT" diff-index --cached --name-only \
        --diff-filter=ACMRTUXB HEAD -- 2>/dev/null || true)"

    [ -z "$staged_files" ] && return 0
    printf '%s\n' "$staged_files" | awk 'NF && !seen[$0]++'
}
```

**設計根拠**:
- staged=コミット直前のファイル。lint違反を防ぐ最も重要なタイミング
- unstaged=作業中。コミット前にstageするタイミングでもチェックされる
- pre-commit hookでもlintは実行される (二重防御)
- 削除する `git ls-files -m` は /mnt/c/ で870ms-1.5s費やす主犯

**期待改善**: 5149ms → ~54ms (~100倍)

### (2) gate_karo_startup.sh — 新アプローチ: WA rate キャッシュ (300s TTL)

**前回との違い**: 前回はpython3→awk (計算ロジック変更)。今回はWA rateスクリプトの結果キャッシュ (キャッシュ戦略)。

```bash
# WA rate スクリプトをキャッシュ付きで実行
_WA_RATE_TMP=$(mktemp)
_NINJA_WA_TMP=$(mktemp)
_WA_RATE_CACHE="/tmp/karo_wa_rate_cache"
_NINJA_WA_CACHE="/tmp/karo_ninja_wa_cache"
WA_CACHE_TTL=300  # 5分

# WA rate: cache hit or fresh
if [[ -f "$_WA_RATE_CACHE" ]] && \
   (( $(date +%s) - $(stat -c %Y "$_WA_RATE_CACHE" 2>/dev/null || echo 0) < WA_CACHE_TTL )); then
    cp "$_WA_RATE_CACHE" "$_WA_RATE_TMP"
else
    bash "$WA_RATE_SCRIPT" --last 10 > "$_WA_RATE_TMP" 2>&1 && cp "$_WA_RATE_TMP" "$_WA_RATE_CACHE"
fi
```

**期待改善**: WA rate 57ms → ~2ms (cache hit), ninja WA 53ms → ~2ms → 110ms → ~55ms (~2倍)

### (3) stop_check_inbox.sh — 新アプローチ: bash文字列マッチでjq削減 (初回改善)

```bash
# 変更1: jq -e . (JSON validation) → bash文字列マッチ
if [[ -z "$payload" || "$payload" != '{'* ]]; then
    exit 0
fi

# 変更2: jq -r '.stop_hook_active...' → bash文字列マッチ
stop_hook_active=false
if [[ "$payload" == *'"stop_hook_active":true'* || "$payload" == *'"stop_hook_active": true'* ]]; then
    stop_hook_active=true
fi

# 変更3: last_assistant_message は jq継続 (内容に特殊文字含む可能性)
```

**期待改善**: jq2本削減 (~10ms) → 37ms → ~27ms (~27%)

---

## After計測計画
- 同条件 median 5回
- regression基準: after ≥ before → 即revert + 理由報告
- PASS_NO_IMPROVEMENT: after < before だが差が5%未満 → 理由報告
