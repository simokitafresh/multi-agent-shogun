# cmd_1755 偵察A: stop-hook quoting脆弱性の検証

## 目的
大元リポジトリ(yohey-w/multi-agent-shogun) commit d108517 の修正内容を確認し、
我が軍の同等実装に同じ脆弱性が存在するか検証する。

---

## 大元 d108517 の修正内容

**修正ファイル**: `scripts/stop_hook_inbox.sh`

### 修正前（脆弱パターン）

```python
SUMMARY=$(python3 -c "
import yaml, sys, json
try:
    with open('$INBOX', 'r') as f:
        data = yaml.safe_load(f)
    ...
    print(' | '.join(parts))
except Exception as e:
    print(f'inbox parse error: {e}')
" 2>/dev/null || echo "inbox未読${UNREAD_COUNT}件あり")

python3 -c "
import json
count = $UNREAD_COUNT
summary = '''$SUMMARY'''           # ← 脆弱点
reason = f'inbox未読{count}件...'
print(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))
"
```

**問題**: `summary = '''$SUMMARY'''` でシェル変数をPythonのトリプルクォート内に埋め込み。
inbox contentにシングルクォートが含まれるとPython構文エラー → クラッシュ。

### 修正後（安全パターン）

```bash
__STOP_HOOK_INBOX="$INBOX" __STOP_HOOK_AGENT_ID_OUT="$AGENT_ID" \
__STOP_HOOK_UNREAD_COUNT="$UNREAD_COUNT" \
python3 -c "
import json, os, yaml
inbox = os.environ['__STOP_HOOK_INBOX']        # 環境変数経由
agent_id = os.environ['__STOP_HOOK_AGENT_ID_OUT']
count = int(os.environ['__STOP_HOOK_UNREAD_COUNT'])
...
print(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))
"
```

**修正方針**: シェル変数をPythonコードに埋め込まず、環境変数経由で渡す。

---

## 我が軍の実装調査

### 大元の修正対象ファイルに対応するファイル

我が軍に `scripts/stop_hook_inbox.sh` は**存在しない**。
対応するのは **`scripts/hooks/stop_check_inbox.sh`**（settings.json Stop hookに登録済み）。

### stop_check_inbox.sh の実装確認

#### inbox要約構築部分（L73-98）

```bash
unread_summary="$(
  INBOX_FILE="$inbox_file" SUMMARY_LIMIT_ENV="$SUMMARY_LIMIT" SUMMARY_SNIPPET_LEN_ENV="$SUMMARY_SNIPPET_LEN" python3 - <<'PY'
import os
import yaml
inbox_path = os.environ["INBOX_FILE"]          # 環境変数経由
limit = int(os.environ["SUMMARY_LIMIT_ENV"])
snippet_len = int(os.environ["SUMMARY_SNIPPET_LEN_ENV"])
...
print(" | ".join(parts))
PY
)"
```

- **`<<'PY'`（シングルクォートヒアドキュメント）**: 変数展開なし
- **環境変数経由**: ファイルパスを安全に渡す
- → 大元の旧パターンは**最初から採用していない**

#### JSON出力部分（L105-110）

```bash
REASON_TEXT="$reason_text" python3 - <<'PY'
import json
import os
print(json.dumps({"decision": "block", "reason": os.environ["REASON_TEXT"]}, ensure_ascii=False))
PY
```

- `reason_text` → 環境変数 `REASON_TEXT` で渡す
- Python内では `os.environ["REASON_TEXT"]` で取得
- `json.dumps` が適切にエスケープ
- → **安全**

### stop-lint-gate.sh L102-103 の確認

```bash
if [ -x "${SHOGUN_ROOT}/scripts/inbox_write.sh" ]; then
    bash "${SHOGUN_ROOT}/scripts/inbox_write.sh" karo \
        "${AGENT_ID}: Stop Hook lint違反同一繰り返し。修正不能と判断しstop許可。要対応。" \
        error_report "$AGENT_ID" 2>/dev/null || true
fi
```

- メッセージは固定文字列 + `${AGENT_ID}`（tmux属性値: kagemaru等）
- 動的コンテンツ（ユーザー入力・ファイル内容）を引数に使用していない
- inbox_write.sh の `inbox_yaml_emit_field` がシングルクォートをエスケープしてYAML書き込み
- → **脆弱性なし**

---

## テスト実施

### テスト条件

特殊文字を含むinboxを用いて stop_check_inbox.sh の処理パスを検証。

```yaml
content: "特殊文字テスト: シングルクォート' + ダブルクォート\" + バックスラッシュ\\ + $HOME変数 + `バックティック`"
```

### テスト結果

| テストケース | 結果 |
|---|---|
| Python heredoc + 環境変数でinbox要約構築 | 正常出力（クラッシュなし） |
| 環境変数REASON_TEXT → json.dumps | 正常エスケープ（クラッシュなし） |

出力例:
```
[karo/wake_up] 特殊文字テスト: シングルクォート' + ダブルクォート" + バックスラッシュ\ + $HOME変数 + `バックティック`
```
```json
{"decision": "block", "reason": "inbox未読1件あり。内容: [karo/wake_up] 特殊文字テスト: シングルクォート' ..."}
```

---

## 判定

| 対象 | 脆弱性 | 理由 |
|---|---|---|
| `scripts/hooks/stop_check_inbox.sh` | **なし** | `<<'PY'`+環境変数経由を最初から採用。大元の旧パターン不在 |
| `.claude/hooks/stop-lint-gate.sh` L102-103 | **なし** | 固定文字列のみ。動的コンテンツなし |

**d108517相当の修正は不要。**

---

## 参照

- 大元commit: `gh api repos/yohey-w/multi-agent-shogun/commits/d108517`
- 対応ファイル: `scripts/hooks/stop_check_inbox.sh`
- lint gate: `.claude/hooks/stop-lint-gate.sh`
