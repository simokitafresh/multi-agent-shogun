# test_stop_check_inbox.bats 高速化プロファイリング
# cmd_2111 — tobisaru, 2026-04-19

## Before 計測 (最適化前)

WSL2高負荷時（5回計測）:

| Run | Time (ms) |
|-----|-----------|
| 1   | 7019      |
| 2   | 7122      |
| 3   | 6633      |
| 4   | 6834      |
| 5   | 7075      |

**中央値: 7019ms**
- テスト数: 9
- 平均 per test: ~780ms

## Setup プロファイリング

### bats フレームワーク構成
- BATS_TMPDIR: `/tmp` (Linux ext4 — WSL2 NTFS ではない)
- bats --version: 1.13.0

### per-test 時間内訳 (最適化前)

| コンポーネント | 時間 | 備考 |
|--------------|------|------|
| bats per-test overhead | ~200ms | setup_file export / TAP管理 |
| setup() cp + chmod×4 | ~400ms | WSL2重負荷時。cp+3cat+4chmod |
| hook 実行 | ~100-200ms | payload解析+inbox読込+python3 |
| inotifywait sleep | 200ms (T-SCI-002/006/007) | 0.2s×3テスト = 0.6s合計 |
| inotifywait sleep | 1000ms (T-SCI-005) | 単純sleep mock。変化検知なし |
| teardown() rm-rf | ~20ms | TEST_ROOT削除 |
| **合計** | **~780ms/test** | 9テスト×780ms ≈ 7019ms |

### ボトルネック特定

| ボトルネック | 時間 | 割合 |
|------------|------|------|
| setup() per-test ファイル作成 (cp+cat+chmod×8) | 3600ms | 51% |
| T-SCI-005 inotifywait sleep (simple sleep 1s) | 900ms | 13% |
| T-SCI-002/006/007 inotifywait sleep (0.2s×3) | 570ms | 8% |
| hook 実行 × 9 | ~1000ms | 14% |
| bats framework overhead | ~900ms | 13% |

**per-test ファイル作成コスト(51%)が最大ボトルネック。**
WSL2高負荷時はcp/chmod/catコマンド起動コストが50-100ms/コマンドに膨張。

## 最適化内容

### 1. setup_file() fixture共有 (最大効果)

setup()で毎テスト作成していたmockスクリプト(inbox_write.sh, tmux, inotifywait)を
setup_file()で1回だけ作成し、setup()ではln -sfで参照。

```bash
# Before (毎テストcreate, 9×3スクリプト×cat+chmod):
cat > "$TEST_BIN/tmux" <<'EOF'...EOF
chmod +x "$TEST_BIN/tmux"
cat > "$TEST_BIN/inotifywait" <<'EOF'...EOF
chmod +x "$TEST_BIN/inotifywait"

# After (一度だけ作成、per-testはln-sf):
# setup_file()でSHARED_BIN配下に作成
# setup()では:
ln -sf "$SHARED_BIN/tmux" "$TEST_BIN/tmux"
ln -sf "$SHARED_BIN/inotifywait" "$TEST_BIN/inotifywait"
```

削減: ~400ms × 9テスト = 3600ms → ~20ms × 9 = 180ms (3420ms削減)

### 2. inotifywait mock → タイムアウト比例ポーリング

単純sleep mockをタイムアウト比例ポーリング方式に変更。
- 短タイムアウト(0.01s): sleep 0.01s→即終了(高速)
- 長タイムアウト(1s): 50ms間隔でファイルサイズ変化を検知→早期脱出

```bash
polls=$(awk "BEGIN{n = int($timeout_val / 0.05); print (n < 1) ? 1 : n}")
sleep_per=$(awk "BEGIN{printf \"%.4f\", $timeout_val / $polls}")
for ((i=0; i<polls; i++)); do
    sleep "$sleep_per"
    cur_size=$(wc -c < "$file_to_watch" 2>/dev/null || echo 0)
    [ "$cur_size" != "$init_size" ] && exit 0
done
```

T-SCI-005での効果:
- Before: sleep 1s (変化検知なし) → 1.0s wait
- After: 50ms間隔polling → bg書込み(0.5s後)を検知 → ~0.5s wait
- 削減: ~0.5s

### 3. STOP_HOOK_INOTIFY_TIMEOUT 0.2→0.01s

T-SCI-002/006/007(空inbox待機テスト)のinotifywait timeout短縮。
変化なし→タイムアウト後脱出するパスで0.19s×3 = 0.57s削減。

### 4. cp+chmod → ln -sf (stop_check_inbox.sh)

hookスクリプト自体もln -sfで参照(BASH_SOURCE[0]はsymlink pathを返すため安全)。

## After 計測 (最適化後、同一負荷環境)

| Run | Time (ms) |
|-----|-----------|
| 1   | 6624      |
| 2   | 3890      |
| 3   | 3760      |
| 4   | 3216      |
| 5   | 2630      |

**中央値: 3760ms**

## 結果サマリ

| 項目 | Before | After | 削減率 |
|------|--------|-------|--------|
| テスト実行時間 | 7019ms | 3760ms | **46.4%** |
| テスト数 | 9 | 9 | 変化なし |
| テスト結果 | 全PASS | 全PASS | - |

### WSL2負荷変動について

WSL2は負荷変動(±50%)が大きく、軽負荷時はafter=1.9-2.1s中央値を記録。
Before/After比較は同一重負荷セッション内で計測(git stash/pop方式)。

削減率 = (7019 - 3760) / 7019 = **46.4%** (目標40%を達成)

### 変更ファイル
1. `tests/unit/test_stop_check_inbox.bats`: fixture共有+ln-sf+timeout短縮+polling mock
2. `scripts/hooks/stop_check_inbox.sh` (a347ee4でcommit済み): python3 2→1統合+jq置換
