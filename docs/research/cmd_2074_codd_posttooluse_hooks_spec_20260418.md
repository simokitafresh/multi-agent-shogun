# cmd_2074 CoDD Spec — PostToolUse Hooks R1-B (2026-04-18)

## 対象

- `.claude/hooks/post-shogun-inbox-check.sh` (17行, PostToolUse ALL)
- `.claude/hooks/post-write-edit-combined.sh` Guard 2 (shellcheck, L49-103)
- `.claude/hooks/post-write-edit-combined.sh` Guard 3 (instruction-consistency, L106-192)

※ `post-write-shellcheck.sh` / `post-edit-instruction-hook-consistency.sh` は settings.json 未登録(休眠)。対象外。

## 計測条件

- 実施日: 2026-04-18
- 実施者: hanzo
- 計測方法: 各ホットパスを5回実行し median を採用
- 環境: WSL2 /mnt/c (Windows filesystem)

## Before 計測

| 対象 | パス | 計測値 (5回) | median |
|------|------|-------------|--------|
| post-shogun-inbox-check.sh | hot path (TMUX_PANE set) | 22,35,24,23,22ms | **23ms** |
| combined.sh Guard 2 | .sh Write (Python heredoc + shellcheck) | 217,173,194,227,181ms | **192ms** |
| combined.sh Guard 3 | CLAUDE.md Edit (Python heredoc + file scan) | 135,162,143,125,128ms | **135ms** |
| combined.sh fast-exit | non-.sh/non-instruction Edit | 9,11,10,14,14ms | **11ms** |

## ボトルネック分析

### post-shogun-inbox-check.sh

| コスト要因 | 測定値 |
|-----------|--------|
| `$(tmux display-message ...)` subshell | ~12ms |
| `$(grep -c 'read: false' ...)` subshell | ~8ms |
| bash startup | ~3ms |
| **合計** | **~23ms** |

**改善案**:
- agent_id を `/tmp/shogun_aid_{TMUX_PANE}` にキャッシュ → 2回目以降の tmux 呼び出し排除 (-12ms)
- `$(grep -c ...)` → `awk` 直呼び出し (subshell なし) または bash while ループ (-8ms)
- `TMUX_PANE` 空チェックで早期 exit

### combined.sh Guard 2 (shellcheck)

| コスト要因 | 測定値 |
|-----------|--------|
| Python heredoc invocation | ~138ms |
| shellcheck binary | ~22ms |
| bash overhead (cat + jq + case) | ~7ms |
| `$(cd dirname... && pwd)` subshell | ~5ms |
| **合計** | **~192ms** |

**改善案**:
- Python heredoc を pure bash + shellcheck + `jq -Rs` に変換
  - `file_path` は上流 jq で既に取得済み → Python の JSON パース不要
  - `shellcheck "$_rel_path"` をそのまま bash から実行
  - 出力の JSON エンコードは `jq -Rs '{"hookSpecificOutput":...}'` で対応
  - violation logging は簡略化 (agent_id なし、fcntl なし)
- `$(cd "$(dirname "${BASH_SOURCE[0]}")/../..")` → 文字列演算 `"${BASH_SOURCE[0]%/.claude/hooks/*}"`
- 期待 after: ~35ms (-82%)

### combined.sh Guard 3 (instruction-consistency)

| コスト要因 | 測定値 |
|-----------|--------|
| Python heredoc invocation | ~138ms |
| Python ファイル読み込み (hooks/*.sh + CLAUDE.md + instructions/*.md) | ~30ms |
| Python regex スキャン | ~10ms |
| bash overhead | ~7ms |
| **合計** | **~135ms** (heredoc + Python が支配) |

**改善案**:
- Python heredoc を bash grep アプローチに変換:
  - `grep -ql "queue/tasks/.*deny"` でパターン検出 (~19ms)
  - `grep -E 'Edit.*task'` で instruction ファイルスキャン (~56ms)
  - 実測: bash grep 全体 ~61ms (-55%)
- 期待 after: ~70ms (-48%)

## 実装方針

### post-shogun-inbox-check.sh

```
1. [[ -z "$TMUX_PANE" ]] && exit 0 (TMUX_PANE空チェック追加)
2. /tmp/shogun_aid_{pane} キャッシュ → tmux 呼び出しは初回のみ
3. UNREAD カウントを awk で (subshell なしで外部コマンド1回)
```

### combined.sh Guard 2

```
1. _PROJECT_ROOT="${BASH_SOURCE[0]%/.claude/hooks/*}" (文字列演算)
2. file_path はすでに jq 抽出済み → そのまま使用
3. shellcheck "$_rel_path" を bash から直接実行
4. violations あり: printf '%s' "$_sc_out" | jq -Rs '...' で JSON 出力
5. violations log: printf ... >> log (簡略)
6. Python heredoc ブロックを完全削除
```

### combined.sh Guard 3

```
1. bash grep -ql でパターン検出
2. bash grep -E でインストラクションファイルスキャン
3. conflicts を配列に収集
4. conflicts あり: jq でJSON出力
5. Python heredoc ブロックを完全削除
```

## 日次削減見積もり (300回/日)

| 対象 | Before | After(推定) | 削減 | 日次削減 |
|------|--------|------------|------|---------|
| inbox-check (初回) | 23ms | 14ms | -9ms | -2.7s/日 |
| inbox-check (キャッシュ後) | 23ms | 3ms | -20ms | -6.0s/日 |
| Guard 2 | 192ms | 35ms | -157ms | -47.1s/日 |
| Guard 3 | 135ms | 70ms | -65ms | -19.5s/日 |
