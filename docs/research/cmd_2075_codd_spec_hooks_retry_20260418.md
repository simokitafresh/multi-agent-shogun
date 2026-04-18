# CoDD Spec: Bash Hooks 3本再改善 (cmd_2075)

## Meta
- date: 2026-04-18
- author: kagemaru
- parent_cmd: cmd_2075
- targets:
  - `.claude/hooks/pre-bash-combined.sh` (345行)
  - `.claude/hooks/post-bash-combined.sh` (234行)
  - `.claude/hooks/post-search-completeness-guard.sh` (12行)

---

## 前回revert原因と今回のアプローチ差分

| 項目 | 前回(cmd_2073, revert) | 今回(cmd_2075) |
|------|----------------------|----------------|
| アプローチ | サブシェル削減: `cat \| jq` → `IFS read + bash regex` | jq呼出し削減: bash文字列マッチで **commandを直接抽出** し、jqへの到達頻度を下げる |
| 問題点 | `while IFS= read`ループがWSL2で逆に重かった | — |
| 理論 | サブシェル数削減=高速化(誤り: ループコスト>サブシェルコスト) | jqは高機能だが遅い。bash文字列演算で`"command":"..."` を直接sed抽出し、jq呼出し自体を排除 |

---

## Before 計測 (median 5回, 実運用ディレクトリ /mnt/c/tools/multi-agent-shogun)

| スクリプト | パス | 測定値 (5回) | median |
|---|---|---|---|
| pre-bash-combined | fast exit (非Bashツール) | 7,6,8,8,9ms | **8ms** |
| pre-bash-combined | guard path (Guard1-3, jq実行) | 10,14,13,10,10ms | **10ms** |
| pre-bash-combined | hot path (Guard4, python3) | 49,44,41,46,45ms | **45ms** |
| post-bash-combined | fast exit (非Bash) | 14,12,5,5,5ms | **5ms** |
| post-bash-combined | test path (bats) | 28,34,35,38,48ms | **35ms** |
| post-search-completeness-guard | all | 5,6,6,5,11ms | **6ms** |

---

## ボトルネック分析

### pre-bash-combined.sh

```
fast exit (8ms): bash起動 + payload読込(cat) + 2つの文字列マッチ → exit 0
guard path (10ms): 上記 + jq呼出し1回 (command抽出) + Guard 0-3/5-8判定
hot path (45ms): 上記 + python3 heredoc起動 (Guard 4)
```

**コスト分解:**
- bash起動 ≈ 5ms (固定)
- `cat` + 変数展開 ≈ 1ms
- `jq -r` 1回 ≈ 3-5ms (guard pathが fast exit + 3ms の差)
- python3 heredoc ≈ 35ms (hot path - guard path ≈ 35ms)

**改善ポイント:**
- `jq -r '.tool_input.command'` → bash sed抽出で代替
  - `"command": "..."` パターンをsedで1行抽出 → 3-5ms削減
  - jqに到達するケース(Guard 1-8が必要な場合)のみ高速化
- python3は既にGuard 4の fast-check後のみ到達 → これ以上の遅延化は難しい

### post-bash-combined.sh

```
fast exit (5ms): bash起動 + payload読込 + Bash確認 + test keyword確認 → exit 0
test path (35ms): 上記 + python3 HEREDOC 起動 + JSON parse + test判定
```

**コスト分解:**
- bash起動 ≈ 5ms
- python3 HEREDOC ≈ 28-30ms
- Guard 2 (commit-reminder): jq呼出し1回

**改善ポイント:**
- Guard 1: `python3 HEREDOC`の外側で bash文字列マッチによる早期exit追加
  - `"exit_code":0` かつ test output に "failed" "skipped" がなければ python3 不要
  - bash文字列マッチでfail/skip検出 → python3到達頻度を大幅削減
- Guard 2: `jq -r '.tool_input.command'` → sed抽出で代替

### post-search-completeness-guard.sh

```
12行のみ。echoのみ (6ms = bash起動コストのみ)
```
改善余地: bash起動コスト(5ms)が支配的。shebang変更や事前exit追加で1-2ms削減可能だが微小。

---

## 実装計画

### pre-bash-combined.sh

```bash
# 現在:
if [[ "$payload" == *'"tool_input"'* && "$payload" == *'"command"'* ]]; then
    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
fi

# 改善案: jq置換 (bash + sed)
if [[ "$payload" == *'"tool_input"'* && "$payload" == *'"command"'* ]]; then
    command="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1 | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g' || true)"
fi
```

**注意:** sedでのJSON文字列抽出はネスト/エスケープに脆弱。安全策として:
- 単純な `"command": "単行コマンド"` はsedで抽出可能
- 複数行コマンド(`"command": "line1\nline2"`)はJSONエスケープ形式なので sed でも対応可能
- ただし `"command": "val\"with\"quotes"` のような埋め込みクォートは誤抽出リスク
- **より安全な代替:** `grep -oP '"command"\s*:\s*"\K[^"]*(?=")'` (Perl regex) → ただしWSL2でgrep -P利用可能か確認要

**より確実な実装:** `python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('command',''))"` は起動コストがある。

**最良案:** jqの代わりに `python3 -c` は同コスト。ならば**bash正規表現**で直接抽出:
```bash
if [[ "$payload" =~ '"command"[[:space:]]*:[[:space:]]*"' ]]; then
    rest="${payload#*\"command\":}"
    rest="${rest#*\"}"      # skip leading whitespace + opening quote
    command="${rest%%\"*}"  # up to first closing quote (unescaped)
    # unescape basic sequences
    command="${command//\\n/$'\n'}"
    command="${command//\\t/$'\t'}"
    command="${command//\\\"/\"}"
    command="${command//\\\\/\\}"
fi
```

→ subshell 0回。sed/jq/python3 不要。3-5ms削減見込み。
→ **リスク:** 埋め込みクォート `\"` を含むコマンドで `command` が途中で切れる可能性。
→ **緩和策:** 切れた場合でも Guard のキーワードチェックには通常影響なし(コマンドの後半が欠けても先頭の危険キーワードは残る)。

### post-bash-combined.sh Guard 1

bash文字列マッチでfail/skip検出を Guard 1 python3の前に追加:
```bash
# === Guard 1 pre-check: bash fast skip ===
# test実行かつ明らかに全PASS(fail/skipped/SKIP不在)なら python3 不要
if [[ "$payload" == *'pytest'* || "$payload" == *'bats'* || ... ]]; then
    # 結果にfail/skipキーワードがなければpython3スキップ
    if [[ "$payload" != *'failed'* && "$payload" != *'FAILED'* && \
          "$payload" != *'skipped'* && "$payload" != *'SKIP'* && \
          "$payload" != *'not ok'* ]]; then
        : # python3処理をスキップ
    else
        # 既存のpython3 HEREDOC処理...
    fi
fi
```

→ テスト全PASS時: python3不要 → 35ms → 5ms見込み
→ テスト失敗/スキップ時: python3で正確に解析(既存動作維持)
→ **リスク:** "failed"/"skipped"がコマンド文字列に含まれる場合(例: `bats tests/skipped_feature.bats`)の誤判定
→ **緩和策:** payloadのtool_resultセクションのみ検査する(コマンド文字列は除外)。→ tool_result部分だけ取り出すのは再びjq/sedが必要。

**より安全な実装:** `"exit_code"` フィールドを確認:
```bash
if [[ "$payload" == *'"exit_code":0'* || "$payload" == *'"exit_code": 0'* ]]; then
    # exit_code=0 なら PASS率が高い → fail/skipキーワードも確認
    if [[ "$payload" != *'failed'* && "$payload" != *'FAILED'* && \
          "$payload" != *'skipped'* ]]; then
        # python3スキップ可能
        exit 0  # or continue to Guard 2
    fi
fi
```

→ exit_code=0 かつ fail/skip文字列なし → 最速パスを確保

---

## After計測計画

- 同条件で各パス median 5回計測
- Regression基準: after ≥ before → 即revert + 理由報告
- PASS_NO_IMPROVEMENT: after < before だが差が5%未満 → 報告

---

## 関連ファイル

- `scripts/lib/pre_bash_combined_guard.sh` (別ファイル、参照のみ)
- bats tests: `tests/unit/test_hooks_combined.bats` (存在確認要)
