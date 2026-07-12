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

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
<!-- 検分: report_field_set.sh b86ddd6f5。active report欠落かつ同basenameのarchive存在時は残骸YAML再生成をBLOCKする契約へ変更。commit_hash記録先がarchive済みならactive pathを再生成せずcanonical archive pathを明示して更新する -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `report_field_set.sh` checked_at以降の変更(edb26ea1)をgit showで確認。`verified_existing_dependency`フィールド(list of {path, reason, checked_not_modified: true})に対する型/必須値BLOCKバリデーションを新規追加(LG037除外宣言の構造保証)。commit_hash記録手順、`bash scripts/report_field_set.sh "$REPORT" <field> <value>`の呼び出し契約、status completed前後のガード前提には影響なし。ninja-commitはcommit_hash記録のみを行うため本変更の影響を受けない。

Script refs verified: 2026-07-07 cmd_3743. `report_field_set.sh` checked_at以降の変更はgit log上なし、mtimeのみ22:12:18へ更新されていることを確認。現行契約 `bash scripts/report_field_set.sh "$REPORT" <field> <value>`、commit_hash記録手順、status completed前後のガード前提は変更なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

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
scope外の変更ファイルがあれば**触らず、commitに含めるな**。他者ファイルのcheckout/restore/unstageは禁止。scope外であることを報告する。

### Step 2: 差分確認
```bash
git diff --cached --stat  # ステージ済み
git diff --stat           # 未ステージ
```
意図した変更のみがステージされていることを確認。

### Step 3: scope限定helperでcommit（必須）
```bash
bash scripts/ninja_scope_commit.sh \
  -m "<cmd_id>: <変更内容の1行要約>" -- \
  <file1> <file2> ...
```

helperは指定pathだけをaddし、`git commit --only -- <paths>`でcommitする。共有indexにある他者stageは変更もcommitもしない。空scope・存在しないpathはBLOCKし、pre-commit hookは通常どおり実行する。

忍者の直接`git commit`はGuard GA-231がfail-closedでBLOCKする。commitは必ずこのhelper経由にする。これにより別忍者が先にstageしたファイルを同じcommitへ吸収する経路を入口で閉じる。

同一ファイル内に他者hunkが混在する場合は、HEAD基準で自分のhunkだけを表すpatchを用意し、非対話patch入口を使う。手動`git add -p`や他者差分のstashは不要。`--base-blob`不一致、空patch、適用不能、scope外pathはcommit前にBLOCKされる。

```bash
BASE_BLOB=$(git rev-parse HEAD:path/to/shared-file)
bash scripts/ninja_scope_commit.sh -m "<message>" \
  --patch /tmp/own.patch --base-blob "$BASE_BLOB" -- path/to/shared-file
```

**通常の `git commit` 直書きは禁止** — commit前から他者stageが存在すると、後から自分のpathだけ`git add`しても両方がcommitされる。

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

`status: completed` / `done` への最終遷移**前**に、この `commit_hash` を記録せよ。`report_field_set.sh` は完了済みの現行報告を不変として扱い、内容変更をfail-closedでBLOCKする。完了後に訂正が必要になった場合は、正規経路で先に `status` を `revision_requested` へ遷移し、修正・再検証を行う。

Script refs verified: 2026-07-12 working-tree inspection. `report_field_set.sh` のcompleted-report immutability guardは、完了済み現行報告への非冪等書込みをBLOCKし、`revision_requested` への明示遷移と同値の冪等書込みだけを許可する。`commit_hash`記録順序を上記へ明文化し、scope限定commit・報告YAML helper経由の契約を維持する。

`report_field_set.sh`は`self_gate_check`トップレベル書込みをBLOCKする。報告修正が必要な場合は `self_gate_check.lesson_ref PASS` のようにdot notationで個別fieldだけを更新する。
Script refs verified: 2026-05-22 cmd_2959 (cmd_2841: assumption_invalidation.*書込み時にfound/affected_cmds/detailを自動初期化。cmd_2883: `report_field_set.sh <report> origin [value]` は `lesson_candidate.origin` へ書く。value省略時はtask/reportからcmdを特定し、queue/archive内のcmd originを自動継承する。cmd_2899: report_field_set.sh binary checks処理の高速化。cmd_2941: `binary_checks.*.*.result` は `yes/no` のみ許可し、`true/PASS/OK` 等をBLOCK。cmd_training_L7_v3_saizo_6/9: `assumption_invalidation` のscalar/boolean書込みをdictへ正規化し、`found: true` は `detail` と `affected_cmds` 記入後にのみ許可。cmd_training_L7_v3_saizo_6: `self_gate_check.*` は `lesson_ref` / `lesson_candidate` / `status_valid` / `purpose_fit` の既知キーのみ許可し、値はPASS/FAILのみ)。`report_field_set.sh` は空文字値を許可し、構造体/複数行/stdin YAMLをPython fallbackで保持する。commit後のreport追記も同helper経由で行い、直接Editしない。`verdict` は `gate_report_format.sh` が自動導出するため手動記入禁止。

## 禁止事項

- **`git add .` / `git add -A`** — scope外混入の原因
- **通常の `git commit` 直書き** — 共有indexの他者stage混入原因。必ず`ninja_scope_commit.sh`を使う
- **他者ファイルのcheckout/restore/unstage** — 他者WIPを破壊する。触らずhelperでscope分離する
- **`git push`** — 忍者はcommitまで。pushは家老の責務
- **`--no-verify`** — pre-commitフックをスキップするな
- **`git reset --hard`** — 未commit変更を全て失う。`git stash`を使え
- **scope外ファイルのcommit** — .env、credentials.json、他の忍者のファイルに触れるな

## 注意ポイント

- 2026-07-12: gate=gate_report_format result=FAIL executor=tobisaru reason=commit_hash: 'no-code-change' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ
- 2026-07-03: gate=gate_report_format result=FAIL executor=tobisaru reason=commit_hash: '67da37c4, ca170887' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

- 2026-07-03: gate=gate_report_format result=FAIL executor=saizo reason=commit_hash: '0f50b1d3 (DM-Signalリポジトリ /mnt/c/Python_app/DM-signal)' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ
- 2026-07-02: gate=gate_report_format result=FAIL executor=hanzo reason=commit_hash: 'd116fa4a2f6d1c1e_additional_db_evidence' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

- 2026-07-02: gate=gate_report_format result=FAIL executor=hayate reason=commit_hash: '97993002' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ
- 2026-07-02: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_hash: 'c1890e0bd49ab676aee78fef4ef2ef31b6d3a90e8' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

- 2026-07-02: gate=gate_report_format result=FAIL executor=tobisaru reason=cmd_3264-AC2 target_path配下に未commit変更あり
- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=commit_hash: 'dfcbb1806' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=commit_hash: 'd439cace6' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ
- 2026-06-30: gate=gate_report_format result=FAIL executor=saizo reason=commit_hash: 'c360719b3' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

- 2026-06-30: gate=gate_report_format result=FAIL executor=saizo reason=commit_hash: '928a3f3e6' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ
- 2026-06-27: gate=gate_report_format result=FAIL executor=saizo reason=commit_hash: 'b59cb8963b7f2617bfcb0f5d6a5b397ce63c41ebf' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `report_field_set.sh` の現行契約を再確認。binary_checks.resultはyes/noのみ、verdictはgate_report_format.sh自動導出、報告追記はhelper経由に限定する。
Script refs verified: 2026-06-08 9a1c5df09. `report_field_set.sh` のfiles_modified autofixがスペース区切り複数パスを検出し、個別dict変換する。ninja-commitのcommit_hash記録手順への影響なし。
Script refs verified: 2026-06-09 06f5a0856. `report_field_set.sh` にlessons_useful全体上書きBLOCKガード追加(既存件数>新件数で拒否)。ninja-commitはcommit_hash記録のみで影響なし。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `report_field_set.sh` 直近変更(281349be)はresult系書込み高速化で、`bash scripts/report_field_set.sh "$REPORT" <field> <value>` の呼び出し契約と報告YAML構造検証は変更なし。

Script refs verified: 2026-06-20 efb4b9c02. `report_field_set.sh` 直近変更はSC2221/SC2222/SC2154 shellcheck警告のdisableコメント追加で、フィールド設定・binary_checks yes/no・commit_hash記録契約は変更なし。

Script refs verified: 2026-06-26 b12637002. `report_field_set.sh` 直近変更はstatus=completed済み報告へのcommit前フィールド書込みをBLOCKするガード追加。ninja-commitはcommit後にcommit_hashを記録するため、commit前にstatus completedになることはなく影響なし。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
