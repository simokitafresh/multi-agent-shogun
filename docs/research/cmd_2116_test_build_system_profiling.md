# test_build_system.bats 高速化プロファイリング
# cmd_2116 — tobisaru, 2026-04-19

## Before 計測 (最適化前)

WSL2高負荷時（5回計測）:

| Run | Time (ms) |
|-----|-----------|
| 1   | 15062     |
| 2   | 13994     |
| 3   | 14914     |
| 4   | 14241     |
| 5   | 14552     |

**中央値: 14552ms**
- テスト数: 40
- 平均 per test: ~364ms

## Setup プロファイリング

### bats フレームワーク構成
- BATS_TMPDIR: `/tmp` (Linux ext4)
- bats --version: 1.13.0
- テスト数: 40

### per-test 時間内訳 (最適化前)

| コンポーネント | 時間 | 備考 |
|--------------|------|------|
| bats per-test overhead | ~121ms | bats subprocess + TAP管理 |
| setup() subshell × 40 | ~1700ms | $(cd ...&& pwd) × 3変数 × 40テスト |
| bats overhead × 40 | ~4840ms | 不可分 |

### ボトルネック特定 (setup_file処理)

| ボトルネック | 時間 | 割合 |
|------------|------|------|
| build_instructions.sh × 3回 (逐次) | ~5100ms | 35% |
| setup() per-test subshell × 40 | ~1700ms | 12% |
| find -exec md5sum (16プロセス) × 2 | ~500ms | 3% |
| bats framework overhead × 40 | ~4840ms | 33% |
| その他 (grep/cat/mkdir等) | ~1700ms | 12% |

**3回のbuild_instructions.sh実行が最大ボトルネック:**
1. setup_file()でのメイン1回目ビルド
2. idempotentテスト内での2回目ビルド
3. agentsテスト内でのtemp_repo向けビルド

**setup()のサブシェルが第2ボトルネック:**
setup()が毎テスト `$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)` を3回実行。
setup_file()でexport済みの変数を再計算していた（冗長）。

## 最適化内容

### 1. setup()の空化 (第2ボトルネック除去)

setup_file()でexportした変数(PROJECT_ROOT/BUILD_SCRIPT/OUTPUT_DIR)を
setup()で再計算していたサブシェルを削除。

```bash
# Before: 毎テストsubshell実行(40 × 3subshell)
setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_instructions.sh"
    OUTPUT_DIR="$PROJECT_ROOT/instructions/generated"
}

# After: exportされた変数を継承(subshellゼロ)
setup() { :; }
```

削減: ~1700ms

### 2. agentsビルドの並列化 (最大効果)

agentsテストのtemp_repo構築+ビルドをsetup_file()に移動し、
メイン1回目ビルドと並列実行。

- agents buildは/tmp(ext4)、メインbuildは/mnt/c(NTFS)で異なるファイルシステム
- I/O競合なし → 純粋に並列化できる

```bash
# cmd_2116: agents buildをバックグラウンドで並列実行
(
    out=$(bash "$AGENTS_TMPDIR/scripts/build_instructions.sh" 2>&1)
    st=$?
    printf '%s\n' "$st"  > "$AGENTS_BUILD_STATUS_FILE"
    printf '%s\n' "$out" > "$AGENTS_BUILD_OUTPUT_FILE"
) &
_agents_pid=$!

# main build 1 と並列実行
bash "$BUILD_SCRIPT" > /dev/null 2>&1
...
wait "$_agents_pid" || true
```

削減: ~1700ms (3回逐次→2回逐次+1回並列)

### 3. find -exec md5sum → md5sum glob (サブプロセス削減)

`find -exec md5sum {} \;` は対象ファイル数(16)分のサブプロセスを起動。
`md5sum *.md` は1回のサブプロセスで全ファイルを処理。

```bash
# Before: 16サブプロセス呼び出し
find "$OUTPUT_DIR" -name "*.md" -type f -exec md5sum {} \; | sort

# After: 1サブプロセス呼び出し
md5sum "$OUTPUT_DIR"/*.md 2>/dev/null | sort
```

削減: ~450ms (15プロセス × 30ms/process)

### 4. 冪等性テストの2回目ビルドをsetup_file()に移動

idempotentテスト内の2回目ビルド+ハッシュ計算をsetup_file()に移動。
テスト本体はBUILD_HASH_FILE vs BUILD_HASH2_FILEの比較のみに簡略化。

```bash
# setup_file()で事前計算
bash "$BUILD_SCRIPT" > /dev/null 2>&1
md5sum "$OUTPUT_DIR"/*.md 2>/dev/null | sort > "$BUILD_HASH2_FILE"

# idempotentテスト本体: ハッシュファイル比較のみ
@test "idempotent: second build produces identical output" {
    if ! cmp -s "$BUILD_HASH_FILE" "$BUILD_HASH2_FILE"; then
        diff -u "$BUILD_HASH_FILE" "$BUILD_HASH2_FILE" >&2 || true
        false
    fi
}
```

## After 計測 (最適化後、同一負荷環境)

| Run | Time (ms) |
|-----|-----------|
| 1   | 7646      |
| 2   | 9096      |
| 3   | 10343     |
| 4   | 8279      |
| 5   | 9080      |

**中央値: 9080ms**

## 結果サマリ

| 項目 | Before | After | 削減率 |
|------|--------|-------|--------|
| テスト実行時間 | 14552ms | 9080ms | **37.6%** |
| テスト数 | 40 | 40 | 変化なし |
| テスト結果 | 全PASS | 全PASS | - |

### WSL2負荷変動について

WSL2は負荷変動(±50%)が大きく、afterの計測値も7646-10343msと変動している。
Before/After比較は同一セッション内の連続計測(beforeはcompaction前に実施済み)。

削減率 = (14552 - 9080) / 14552 = **37.6%** (目標30%を達成)

### 不可分ボトルネック

bats framework overhead (4840ms) + 2回のbuild_instructions.sh (3400ms) が残存。
これ以上の削減には build_instructions.sh 自体の高速化が必要。

### 変更ファイル
1. `tests/unit/test_build_system.bats`: setup()空化+agents並列化+md5sum glob+idempotent移動
