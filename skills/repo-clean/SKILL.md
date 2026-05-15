# /repo-clean — 全リポジトリクリーンネス検査+修復

【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
config/projects.yamlの全プロジェクトリポジトリを検査し、
untracked/modified/unpushed/stashを検出→修復する。

TRIGGER: /repo-clean、リポジトリ掃除、未コミット確認、全PJクリーン
DO NOT TRIGGER: 個別リポジトリのgit操作、commit（→/ninja-commit）

## 手順

### Step 1: 全リポジトリ検査

```bash
for repo in $(grep 'path:' config/projects.yaml | sed 's/.*path: *"//;s/"//'); do
  cd "$repo" 2>/dev/null || continue
  name=$(basename "$repo")
  untracked=$(git ls-files --others --exclude-standard | wc -l)
  modified=$(git diff --name-only | wc -l)
  unpushed=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l)
  stash=$(git stash list | wc -l)
  total=$((untracked + modified + unpushed + stash))
  if [ "$total" -gt 0 ]; then
    echo "DIRTY $name: untracked=$untracked modified=$modified unpushed=$unpushed stash=$stash"
  else
    echo "CLEAN $name"
  fi
done
```

### Step 2: DIRTY判定されたリポジトリごとに修復

各リポジトリに対して以下の順序で実行:

1. **stash**: `git stash list`で内容確認。不要なら`git stash drop`。必要ならapply+commit
2. **untracked**:
   - `__pycache__/`等のビルド成果物 → `.gitignore`に追加
   - 意味のあるファイル → `git add` + commit
3. **modified**: 内容確認して`git add` + commit
4. **unpushed**: `git push origin main`

### Step 3: 再検査

Step 1を再実行し全リポジトリCLEANを確認。
稼働中の忍者がファイルを書き換え続ける場合はmodifiedが残る（正常）。

## 判断基準

- stashは原則不要。古いWIPは削除
- `__pycache__/`, `.codex_tmp/`, `tmp/`は.gitignoreに追加
- 記事/レポート等のコンテンツファイルはcommit対象
- validation CSV等の一時データは.gitignoreに追加
