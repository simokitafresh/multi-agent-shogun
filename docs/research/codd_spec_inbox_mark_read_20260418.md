# scripts/inbox_mark_read.sh リファクタリング CoDD Spec (事後作成)

## cmd: cmd_2060 (CoDD改善 infra speedups)
## 実施者: kagemaru (spec事後作成: hanzo)

## 問題（ボトルネック関数+計測値）

inbox_mark_read.sh の早期終了パス実行時間 ~34ms。
ボトルネック1: `SCRIPT_DIR` 計算に `$(cd "$(dirname "$0")" && pwd)` を使用。
  サブシェル起動コスト (~5ms)。
ボトルネック2: 既読化処理 (mark-all / mark-specific) を python3 heredoc で実装。
  python3インタプリタ起動コスト (~25ms) + flock内subshell生成で毎回発生。

## 定量プロファイル(実測 before)

| 処理 | 時間 | 根因 |
|------|------|------|
| `$(cd && pwd)` subshell (SCRIPT_DIR) | ~5ms | サブシェルスポーン |
| python3 heredoc (mark-all / mark-specific) | ~25ms | python3インタプリタ起動コスト |
| **合計(early-exit path)** | **~34ms** | python3起動コスト支配 |

## リファクタリング対象

### R1: SCRIPT_DIR計算を文字列演算化

**現状**:
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

**改善**:
```bash
_imr_self="${BASH_SOURCE[0]}"
[[ "$_imr_self" != /* ]] && _imr_self="$PWD/$_imr_self"
SCRIPT_DIR="${_imr_self%/scripts/inbox_mark_read.sh}"
unset _imr_self
```
- 通常パスは pure bash 文字列演算のみ。`cd && pwd` サブシェル不要
- 期待効果: -5ms

### R2: python3 heredoc → bash+sed (mark-all パス)

**現状**: python3 heredoc でファイル全体を yaml.safe_load → メッセージ走査 → yaml.dump
- python3 起動コスト ~25ms
- yaml.dump でマルチラインフィールドが消失するリスク (cmd_1399 事故と同構造)

**改善**:
```bash
# Mark all: sed single-pass (no python3)
sed 's/^\([[:space:]]*read:[[:space:]]*\)false/\1true/' "$INBOX" > "$_tmp"
```
- sed 1回のパスで全 `read: false` → `read: true` を置換
- python3 起動コスト ~25ms → ほぼ 0ms

### R3: python3 heredoc → stateful awk (mark-specific パス)

**現状**: python3 heredoc で全行走査、対象 msg_id の read: false を true に変更

**改善**:
```bash
# Mark specific msg_id: stateful awk pass (no python3)
awk -v msg_id="$MSG_ID" -v cnt_file="$_cnt_file" '
    BEGIN { changed=0; current_id="" }
    # - id: フィールドで current_id を追跡
    # read: false かつ current_id==msg_id で置換
    { ... print }
    END { print changed > cnt_file }
' "$INBOX" > "$_tmp"
```
- awk で状態管理しながら1パスで処理
- 変更件数を cnt_file 経由で flock サブシェル外に伝達
- python3 起動コスト ~25ms → ほぼ 0ms

## 制約

- API互換（出力形式変更なし）: `[inbox_mark_read] Marked N message(s) as read` 出力不変
- flock アトミック書込み維持: mktemp + mv (os.replace 相当) を bash で再実装
- テスト: 7件 bats テスト全 PASS (`tests/unit/test_inbox_mark_read.bats`)
- 凍結ロジック: agent_id バリデーション (`^[a-z_]+$`)・lockfile パス計算・リトライ 3回

## 結果

- before: ~34ms (early-exit path, median)
- after: ~16ms (-53%, early-exit path, median)
- 改善率: 53%削減 (2.1x高速化)
- テスト: 7/7 PASS
- 対象ファイル: `scripts/inbox_mark_read.sh`
