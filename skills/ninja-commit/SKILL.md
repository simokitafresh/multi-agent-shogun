---
name: ninja-commit
argument-hint: ""
description: |
  【忍者専用】作業完了後のcommit手順を標準化するスキル。
  scope検証+pre-commit+commit+家老報告を1コマンド化し、
  scope外ファイル混入・uncommitted変更残存・commit漏れを防止する。
  TRIGGER: /ninja-commit、コミット、commit、作業完了コミット
  DO NOT TRIGGER: push（忍者はpush禁止）、報告YAML作成（→/report-write）、verdict判定（→/verdict-check）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにcommit漏れ・scope外混入・未commit残存起因のworkaroundが記録されない割合）"
---

# /ninja-commit — 忍者commit手順スキル

作業完了後のcommitをscope検証付きで安全に実行する。

## なぜこのスキルが必要か

- commit_missing WA 4件 + stale_ac_contamination 6件 = 10件(全WA10%)
- /clear後にgit操作手順が消え、scope外ファイル混入やcommit漏れが発生
- 忍者はcommitまで。pushは禁止（CLAUDE.md）

## commit手順


### 自動防止ステップ
- <!-- skill-auto-improve:686ae6519090 --> 自動防止: gate=gate_report_format のTop FAIL理由「lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文...」(count=1, last=2026-05-02T18:41:00+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
### Step 1: scope確認
```bash
# タスクYAMLのtarget_path/files_modifiedからscope内ファイルを特定
git status --short
```
scope外の変更ファイルがあれば**commitに含めるな**。`git checkout -- <file>`で復元するか、scope外であることを報告。

### Step 2: 差分確認
```bash
git diff --cached --stat  # ステージ済み
git diff --stat           # 未ステージ
```
意図した変更のみがステージされていることを確認。

### Step 3: scope内ファイルのみステージ
```bash
# scope内ファイルのみを個別にadd（git add . 禁止）
git add <file1> <file2> ...
```
**`git add .` / `git add -A` は禁止** — scope外ファイル、.env、credentials混入の原因。

### Step 4: commit
```bash
git commit -m "$(cat <<'EOF'
<cmd_id>: <変更内容の1行要約>

Co-Authored-By: <agent_model> <noreply@anthropic.com>
EOF
)"
```

### Step 5: commit後確認
```bash
git log --oneline -1  # commitが作られたか確認
git status --short    # uncommitted変更が残っていないか確認
```

### Step 6: 報告YAMLにcommit hash記録
```bash
COMMIT_HASH=$(git log --format="%H" -1)
bash scripts/report_field_set.sh "$REPORT" "commit_hash" "$COMMIT_HASH"
```

`report_field_set.sh`は`self_gate_check`トップレベル書込みをBLOCKする。報告修正が必要な場合は `self_gate_check.lesson_ref PASS` のようにdot notationで個別fieldだけを更新する。

## 禁止事項

- **`git add .` / `git add -A`** — scope外混入の原因
- **`git push`** — 忍者はcommitまで。pushは家老の責務
- **`--no-verify`** — pre-commitフックをスキップするな
- **`git reset --hard`** — 未commit変更を全て失う。`git stash`を使え
- **scope外ファイルのcommit** — .env、credentials.json、他の忍者のファイルに触れるな

## 注意ポイント
