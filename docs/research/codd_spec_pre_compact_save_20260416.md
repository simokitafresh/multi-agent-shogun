# CoDD Spec: pre_compact_save.sh 高速化

- **作成者**: kotaro
- **日付**: 2026-04-16
- **対象**: `scripts/hooks/pre_compact_save.sh`
- **cmd**: cmd_1969

---

## §1 Before実測値

| 環境 | 計測方法 | 値 |
|------|----------|-----|
| cmd_1951プロファイリング | hyperfine相当(10run) | 141ms |
| kotaro実測(非TMUX) | Python subprocess 10run | 46ms median (40-51ms range) |

非TMUX環境では46msだが、実運用環境(TMUX起動中)では2×tmux呼び出しが加わり141ms。

---

## §2 ボトルネック分析

```
pre_compact_save.sh 実行フロー:
1. set -euo pipefail        ~0ms (bash内部)
2. ROOT_DIR解決             ~0ms
3. cat (stdin読み取り)      ~1ms
4. jq × 2 (trigger/session) ~10ms (各5-7ms × 2)
5. tmux × 2 (agent_id/task) ~60ms (各25-30ms × 2, TMUX時)
6. mkdir -p × 2             ~5ms
7. date                     ~1ms
8. cat > state_file         ~1ms
合計(TMUX時):               ~78ms + bash起動~4ms + その他 = 141ms
```

**ボトルネック rank:**
1. **tmux × 2呼び出し**: ~60ms (42%)
2. **jq × 2呼び出し**: ~10ms (7%)
3. **mkdir -p × 2**: ~5ms (3%)

---

## §3 リファクタ方針

### 最適化1: bash regex でjq廃止 (saves ~10ms)

`jq` 2呼び出し → bash `[[ =~ ]]` 正規表現マッチング。
JSONは`{"trigger":"...","session_id":"..."}` の単純構造。サブプロセス不要。

```bash
# Before:
compact_trigger="$(printf '%s' "$payload" | jq -r '.trigger // "manual"' 2>/dev/null || echo "manual")"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || echo "")"

# After:
if [[ "$payload" =~ \"trigger\":\"([^\"]+)\" ]]; then
    compact_trigger="${BASH_REMATCH[1]}"
else
    compact_trigger="manual"
fi
if [[ "$payload" =~ \"session_id\":\"([^\"]+)\" ]]; then
    session_id="${BASH_REMATCH[1]}"
else
    session_id=""
fi
```

### 最適化2: tmux 2→1 呼び出し (saves ~25-30ms)

2つの`display-message`を1回のカスタムフォーマット呼び出しに統合。

```bash
# Before:
agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
current_task="$(tmux display-message -t "$TMUX_PANE" -p '#{@current_task}' 2>/dev/null || true)"

# After:
tmux_out="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}	#{@current_task}' 2>/dev/null || true)"
agent_id="${tmux_out%%	*}"
current_task="${tmux_out##*	}"
```

### 最適化3: 冗長mkdir削除 (saves ~2ms)

`mkdir -p "$ROOT_DIR/scripts/hooks"` は不要。
- このファイル自体が `scripts/hooks/` 内に存在するため、ディレクトリは常に存在する

---

## §4 期待改善値

| 最適化 | 削減量 |
|--------|--------|
| jq廃止 | -10ms |
| tmux 1回化 | -25~30ms |
| mkdir削除 | -2ms |
| **合計** | **-37~42ms** |

- Before(TMUX): 141ms → After推定: ~99-104ms (29-30%削減)
- Before(非TMUX): 46ms → After推定: ~34ms (26%削減)

目標: 40ms (TMUX時は100ms以下を達成目標)

---

## §5 機能変更なし確認

- 入力: stdin JSON (`trigger`, `session_id` フィールド)
- 出力: `queue/compact_state/{agent_id}.yaml` (同一フォーマット)
- agent_id sanitization: 変更なし (`tr -cd '[:alnum:]_.-'`)
- fallback値: trigger="manual", session_id="", agent_id="unknown" — 変更なし
