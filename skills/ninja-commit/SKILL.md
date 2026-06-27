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

<!-- script_refs_checked_at: 2026-06-02T20:31:22+09:00 -->

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
verdict は `gate_report_format.sh` が binary_checks から自動導出する。commit後の報告追記でも手動記入禁止。

`report_field_set.sh`は`self_gate_check`トップレベル書込みをBLOCKする。報告修正が必要な場合は `self_gate_check.lesson_ref PASS` のようにdot notationで個別fieldだけを更新する。
Script refs verified: 2026-05-22 cmd_2959 (cmd_2841: assumption_invalidation.*書込み時にfound/affected_cmds/detailを自動初期化。cmd_2883: `report_field_set.sh <report> origin [value]` は `lesson_candidate.origin` へ書く。value省略時はtask/reportからcmdを特定し、queue/archive内のcmd originを自動継承する。cmd_2899: report_field_set.sh binary checks処理の高速化。cmd_2941: `binary_checks.*.*.result` は `yes/no` のみ許可し、`true/PASS/OK` 等をBLOCK。cmd_training_L7_v3_saizo_6/9: `assumption_invalidation` のscalar/boolean書込みをdictへ正規化し、`found: true` は `detail` と `affected_cmds` 記入後にのみ許可。cmd_training_L7_v3_saizo_6: `self_gate_check.*` は `lesson_ref` / `lesson_candidate` / `status_valid` / `purpose_fit` の既知キーのみ許可し、値はPASS/FAILのみ)。`report_field_set.sh` は空文字値を許可し、構造体/複数行/stdin YAMLをPython fallbackで保持する。commit後のreport追記も同helper経由で行い、直接Editしない。`verdict` は `gate_report_format.sh` が自動導出するため手動記入禁止。

## 禁止事項

- **`git add .` / `git add -A`** — scope外混入の原因
- **`git push`** — 忍者はcommitまで。pushは家老の責務
- **`--no-verify`** — pre-commitフックをスキップするな
- **`git reset --hard`** — 未commit変更を全て失う。`git stash`を使え
- **scope外ファイルのcommit** — .env、credentials.json、他の忍者のファイルに触れるな

## 注意ポイント
- 2026-06-27: gate=gate_report_format result=FAIL executor=saizo reason=commit_hash: 'b59cb8963b7f2617bfcb0f5d6a5b397ce63c41ebf' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `report_field_set.sh` の現行契約を再確認。binary_checks.resultはyes/noのみ、verdictはgate_report_format.sh自動導出、報告追記はhelper経由に限定する。
Script refs verified: 2026-06-08 9a1c5df09. `report_field_set.sh` のfiles_modified autofixがスペース区切り複数パスを検出し、個別dict変換する。ninja-commitのcommit_hash記録手順への影響なし。
Script refs verified: 2026-06-09 06f5a0856. `report_field_set.sh` にlessons_useful全体上書きBLOCKガード追加(既存件数>新件数で拒否)。ninja-commitはcommit_hash記録のみで影響なし。

<!-- script_refs_checked_at: 2026-06-09T09:25:00+09:00 -->
<!-- script_refs_checked_at: 2026-06-18T23:50:10+09:00 -->

Script refs verified: 2026-06-20 efb4b9c02. `report_field_set.sh` 直近変更はSC2221/SC2222/SC2154 shellcheck警告のdisableコメント追加で、フィールド設定・binary_checks yes/no・commit_hash記録契約は変更なし。

Script refs verified: 2026-06-26 b12637002. `report_field_set.sh` 直近変更はstatus=completed済み報告へのcommit前フィールド書込みをBLOCKするガード追加。ninja-commitはcommit後にcommit_hashを記録するため、commit前にstatus completedになることはなく影響なし。

<!-- script_refs_checked_at: 2026-06-26T07:25:00+09:00 -->
