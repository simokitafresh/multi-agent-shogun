# CLI Model & Context Window ガイド
# 調査: 軍師 self_study_S163-S164 | 殿実験+裁定 2026-04-02
# 全エージェント参照可。respawn/起動時に必読。

## §1 結論（3行で全部）

- **Claude CLI**: `--model`なしで起動 → Default(1M context) + `--effort high`で起動せよ。`--model opus`は200K。
- **Codex CLI**: デフォルト272K。`~/.codex/config.toml`に`model_context_window = 1000000`追加で1M。
- **effort**: high（殿裁定）。maxは3-10x消費でレートリミット直撃。

## §2 Claude CLI 詳細

### /model セレクタの罠

| 選択肢 | モデルID | context | effort default |
|--------|---------|---------|---------------|
| **1. Default (recommended)** | Opus 4.6 (1M context) | **1M** | **max** |
| 4. Opus 4.6 | claude-opus-4-6 | **200K** | high |

`/model opus` や `--model opus` は選択肢4 → **200K**。

### 正しい起動コマンド

```bash
# ✓ 正しい（1M + high effort）
claude --dangerously-skip-permissions --effort high

# ✗ 間違い（200K）
claude --model opus --dangerously-skip-permissions
```

### effort設定の優先順位

1. `--effort high`（起動フラグ） — セッションレベル
2. `~/.claude/settings.json` の `effortLevel: "high"` — グローバルデフォルト
3. `/model`セレクタでDefault選択時 → **maxが強制される**（settings.json無視）

→ `--effort high`フラグで起動すれば確実。

### respawn手順

```bash
# 1. CLI終了
/exit

# 2. 再起動（1M + high effort確定）
claude --dangerously-skip-permissions --effort high

# 3. 確認: バナーに "(1M context)" + "high effort" が表示されること
```

### build_cli_command() 修正済み (b3f55d9)

lib/cli_adapter.sh L88: `model != "opus"`の場合のみ`--model`付与。opusはデフォルト起動。
→ **但し`--effort high`は未追加。手動対応 or 追加commit必要。**

## §3 Codex CLI 詳細

### デフォルト設定

| 項目 | 値 | 設定箇所 |
|------|----|---------| 
| モデル | gpt-5.4 | `~/.codex/config.toml` model |
| context | **272K**（デフォルト） | 未設定 = 272K |
| effort | high | `model_reasoning_effort = "high"` |

### 1M有効化（実験的機能）

`~/.codex/config.toml`に追加:
```toml
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

### /hensei mixed注意事項

- モデル名: `gpt-5`は古い → 正しくは`gpt-5.4`
- context: config.toml 1M設定なしでは272Kで稼働
- claude↔codex切替: `/model`不可。respawn必須

## §4 effort別コスト

| effort | 思考トークン制限 | コスト倍率 | 用途 |
|--------|----------------|-----------|------|
| low | 最小 | 0.3x | 単純作業 |
| medium | 制限あり | 0.6x | 軽作業 |
| **high**（殿裁定） | 制限あり | **1x** | **通常運用** |
| max | **無制限** | **3-10x** | 決戦のみ |

## §5 現行プロセス状態（2026-04-02 01:30時点）

| 忍者 | CLI | context | effort | 状態 |
|------|-----|---------|--------|------|
| hayate | claude --model opus | 200K | high | **要respawn** |
| kagemaru | claude（引数なし） | 1M | high | ✓ |
| hanzo | claude --model opus | 200K | high | **要respawn** |
| saizo | claude --effort high | 1M | high | ✓（実験後復元済み） |
| kotaro | claude --model opus | 200K | high | **要respawn** |
| tobisaru | claude --model opus | 200K | high | **要respawn** |
