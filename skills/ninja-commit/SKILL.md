---
<!-- script_refs_checked_at: 2026-07-31T05:36:00+09:00 -->
<!-- 2026-07-31 cmd_karo_skill_ref_ninja_commit_20260731検分: report_field_set.sh d878d5096/6e33bdbb2をgit show。hook_failures親mappingのpost_verification_result canonical化とreport_publish generationのreview_report_fingerprint統一であり、ninja-commitが使う単一field commit_hash setter、completed前記録順序、CLI契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T14:08:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_batch_b検分: ninja_scope_commit.sh afd88ea1/2fed7545/c909aa60をgit log/show。receipt再利用時scope収束検証、HEAD+shared-index世代原子確認、`maintenance.auto=false`分離を追加。scope限定CLI、fail-closed、成功時40桁hash stdout、report commit_hash記録契約は不変で本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T04:48:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_final_pair_202607180446検分: ninja_scope_commit.sh afd88ea13はsingle-flight receipt再利用時にcommit存在・HEAD祖先・対象scopeのHEAD差分/unstaged/stagedが全て収束していることを再検証するfail-closed強化。CLI、対象path限定、成功時40桁hash出力、report commit_hash記録契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T03:18:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_freshness_batch検分: ninja_scope_commit.sh 2f7805b8/85d83497/5f63ad8eはphase telemetry、immutable snapshot、single-flight receiptを追加。CLIとstdoutの40桁hash契約は維持し、同一run再実行はreceipt hashを返す。report_field_set.sh 7c2a802e/cebb4ba2/4dafc13fのbatch/atomic serializerはcommit_hash単一setter契約に影響なし。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: ninja_scope_commit.sh ef9c8849/22a14d07/ea11789a/b3716c04はignored owned path/retry/terminal index整合追加。CLI不変、残差はfail-closed。report_field_set batchとも整合。 -->
<!-- script_refs_checked_at: 2026-07-17T09:45:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: ninja_scope_commit.sh 0919291b7/3d7a74505/138332265はprivate index競合保護とlive task YAML分離、report_field_set.sh ab05776afは非terminal status scan省略。scope限定commit CLI・report commit_hash記録契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900
<!-- 2026-07-16 cmd_karo_hotfix_parallel_commit_race検分: ninja_scope_commit.shは専用indexに加えgit common-dir単位のflockでCOMMIT_EDITMSG/hooks/HEAD更新を含むcommit transactionを直列化。CLI契約は不変で、並列呼出しでも件名・path scope非混線と親shell復帰を保証する。 -->
<!-- 2026-07-15将軍検分: report_field_set.sh aa75598cf(lesson_candidate型チェック dict→(dict,list)緩和=内部バリデーション)。呼び出し契約不変。 -->
name: ninja-commit
argument-hint: ""
description: |
  【忍者専用】作業完了後のcommit手順を標準化するスキル。
  scope検証+pre-commit+commit+家老報告を1コマンド化し、
  scope外ファイル混入・uncommitted変更残存・commit漏れを防止する。
  TRIGGER: /ninja-commit、コミット、commit、作業完了コミット
  DO NOT TRIGGER: push（忍者はpush禁止）、報告YAML作成（→/report-write）、verdict判定（→/verdict-check）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにcommit漏れ・scope外混入・未commit残存起因のworkaroundが記録されない割合）"
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900
<!-- cmd_3948検分: report_field_set.sh直近差分はsummary placeholder入口BLOCK。commit_hash記録契約不変。 -->
<!-- 検分: report_field_set.sh cd0411247d(書込み入口でresult.summary placeholderをBLOCK)。CLI引数、commit_hash記録、completed前記録順、出口契約は不変 -->

Script refs verified: 2026-07-13 将軍検分. `report_field_set.sh` checked_at以降の変更(08f9440fb/69ace96dc/5dfec6b28)をgit showで確認。completed/done報告のfail-closed BLOCK+normalize異常終了時byte不変中断=内部堅牢化で、ninja-commit手順の呼出し契約不変。書き換え不要。
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
git --no-optional-locks status --short
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

新規testに有効な`test_necessity`がない場合はtransientである。commit前に
`NINJA_SCOPE_TASK_FILE`と、`status: complete`・`pass: true`・`fail: 0`・
`skip: 0`・対象`test_paths`を持つ`NINJA_TEST_RECEIPT`を渡す。helperは削除候補diffを
表示し、未追跡transient testだけを削除してproduction scopeをcommitする。receipt
欠落/FAIL/SKIP、tracked test、production scope不在は削除前にBLOCKする。
receiptには検証時の40桁`source_head`を必須記録する。helperは任意envに依存せず
receipt（またはtaskの配備HEAD証跡）から検証基点を導出し、commit開始時HEADまでに
別commit由来のtest変更/削除があれば自動BLOCKする。HEAD証跡欠落時は削除しない。
production-onlyの並行commitはtest証拠を無効化しないため許可する。

pre-commitはPASS直後、canonical receiptを変更せず同名
`.precommit-identity.json` sidecarへtask_id、source_head、選択test集合SHA-256、
`git write-tree`、staged shellの`path=blob`一覧をatomic記録する。同一identityの再試行
だけが再利用され、欠損・FAIL・SKIP・HEAD/選択/blob/tree不一致は従来どおりtestと
shell syntaxを再実行する。
分類対象の正本はtaskの`planned_paths`ではなくhelperへ渡した実CLI scopeである。
複数の新規testを永続化する場合、`test_necessity`をpath付きentryのlistとし、各pathに
具体的不変量・overlap evidence・fixture/deprecated判定を個別宣言する。未宣言pathは
別pathの宣言を流用せずtransientとして扱い、報告の`transient_tests_deleted`へ記録する。

helperは指定pathだけをaddし、`git commit --only -- <paths>`でcommitする。共有indexにある他者stageは変更もcommitもしない。空scope・存在しないpathはBLOCKし、pre-commit hookは通常どおり実行する。

DM-Signalの`docs/research`成果は、外部の`prepare`を先に実行してはならない。並行忍者の共有indexを読んでscope fingerprintがずれるため、helperの同一private index内で証跡生成と検査を連続実行する。

```bash
bash scripts/ninja_scope_commit.sh -m "<message>" \
  --reflux-mode non-target --reflux-evidence "<研究索引へ反映しない具体的根拠>" \
  -- docs/research/<owned-file-1> docs/research/<owned-file-2>
```

研究索引へ同期済みなら`--reflux-mode synced`を使う。`--reflux-mode`と`--reflux-evidence`は必ず対で指定し、helperがscope限定addを終えた後のprivate indexを正本としてfingerprintを作る。

commit hash公開後に同一scopeへ到着したdirty差分は別eventとしてWARNし、公開済みcommitを失敗へ戻さない。追加差分の整合は最終report/checkpointで確認する。

同一run・message・mode・scope・worktree bytesで再実行した場合、helperはsingle-flight receiptを検証し、重複commitを作らず既存の40桁commit hashをstdoutへ返す。別タスクで同じmessage/pathを意図的に使うオーケストレータは `NINJA_SCOPE_COMMIT_RUN_ID` をタスク固有値にする。不正・消失receiptはfail-closedでBLOCKされる。

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
git --no-optional-locks status --short    # 共有index refreshを書かずに確認
```

### Step 6: 報告YAMLにcommit hash記録 + cross_repo_commits自動生成
```bash
COMMIT_HASH=$(git log --format="%H" -1)
bash scripts/report_field_set.sh "$REPORT" "commit_hash" "$COMMIT_HASH"
```

cross_repo_commitsはcommitのpath帰属を正確に記録する。**手動記入禁止** — 以下の自動生成を使え:
```bash
python3 -c "
import yaml, sys; sys.path.insert(0, '.')
from scripts.lib.cross_repo_commit_contract import auto_generate_cross_repo_entries
# 全commitのhashをgit logから取得(task scope内のcommit群)
import subprocess
hashes = subprocess.run(['git', 'log', '--format=%H', 'origin/main..HEAD'],
    capture_output=True, text=True, check=True).stdout.strip().splitlines()
entries = auto_generate_cross_repo_entries('$(pwd)', hashes)
print(yaml.dump(entries, default_flow_style=False, allow_unicode=True))
" | bash scripts/report_field_set.sh "$REPORT" "cross_repo_commits" -
```
各commitのchanged pathsをgit diff-treeで自動取得するため、path帰属誤りが構造的に発生しない。

コード変更を伴わず、変更対象がqueue/logsのみで、報告上のcommit不要条件を満たす場合に限り `commit_hash=no-code-change` も許可される。source/config/docsを含む場合や根拠のない指定はBLOCKされる。

<!-- 2026-07-15 cmd_karo_hotfix_skill_refs_ops検分: report_field_set.sh 82d5cac4e/41415be7bをgit showで確認。commit identityを共通validatorへ統合し、40文字hashに加えて厳格なqueue/logs-only no-code-changeを許可する契約変更。上記手順へ反映。 -->
<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900
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
- **`git reset --hard` / `git stash`** — 共有worktree全体を巻き戻し、他忍者の現task generationとreportを破壊する。指定pathだけを`ninja_scope_commit.sh`でscope限定commitせよ
- **scope外ファイルのcommit** — .env、credentials.json、他の忍者のファイルに触れるな

## 注意ポイント
- 2026-08-23: gate=gate_report_format result=FAIL executor=hayate reason=final_checkpoint: ci_fix clean repro evidence source_commit mismatch or invalid; final_checkpoint: ci_fix clean repro evidence push_started_at timestamp invalid; LG051: gate/hoo...
- 2026-08-20: gate=gate_report_format result=FAIL executor=tobisaru reason=commit_contract: commit/task history does not contain owned/planned path: docs/semantic-index/index.md
- 2026-08-18: gate=gate_report_format result=FAIL executor=kotaro reason=commit_contract: commit/task history does not contain owned/planned path: tests/unit/test_inbox_watcher_codex_busy_claim.bats
- 2026-08-18: gate=gate_report_format result=FAIL executor=kagemaru reason=final_checkpoint: ci_fix clean repro evidence pre receipt must be FAIL failures>=1 SKIP0; final_checkpoint: ci_fix clean repro evidence source_commit mismatch or invalid; final_...
- 2026-08-18: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: commit subject does not identify task_id/parent_cmd; final_checkpoint: ci_fix clean repro evidence source_commit mismatch or invalid
- 2026-08-17: gate=gate_report_format result=FAIL executor=tobisaru reason=cross_repo_commits: cross_repo_commits[1].commit_hash is not a resolvable 40-hex commit; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実行して正しいentries...
- 2026-08-17: gate=gate_report_format result=FAIL executor=hanzo reason=cross_repo_commits: primary commit_hash is absent from cross_repo_commits; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実行して正しいentriesを取得し、報告YAMLのcr...
- 2026-08-15: gate=gate_report_format result=FAIL executor=hayate reason=commit_contract: commit subject does not identify task_id/parent_cmd; commit_contract: commit owned/planned scope is missing; commit_contract: commit/task history does not conta...
- 2026-08-15: gate=gate_report_format result=FAIL executor=hayate reason=commit_contract: commit/task history does not contain owned/planned path: scripts/config/context_source_commits.tsv; commit_contract: commit/task history does not contain owned/...
- 2026-08-15: gate=gate_report_format result=FAIL executor=kagemaru reason=cross_repo_commits: cross_repo path appears in multiple entries: backend/tests/test_monthly_returns_signal_cache_preload.py; cross_repo_commits: FIX hint: cross_repo_commitsのpat...
- 2026-08-15: gate=gate_report_format result=FAIL executor=kagemaru reason=cross_repo_commits: cross_repo path appears in multiple entries: backend/app/jobs/recalculate_fof.py; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実...
- 2026-08-14: gate=gate_report_format result=FAIL executor=hayate reason=cross_repo_commits: cross_repo path appears in multiple entries: backend/app/utils/recalc_status.py; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実行...
- 2026-08-14: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: commit subject does not identify task_id/parent_cmd; commit_contract: commit/task history does not contain owned/planned path: config/settings.yaml; commit_cont...
- 2026-08-14: gate=gate_report_format result=FAIL executor=tobisaru reason=cross_repo_commits: cross_repo path appears in multiple entries: context/dm-signal-ops.md; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実行して正しいentri...
- 2026-08-14: gate=gate_report_format result=FAIL executor=kagemaru reason=cross_repo_commits: cross_repo_commits[0].commit_hash is not a resolvable 40-hex commit; operational_simulation: MISSING (command,expected,actual; integration cmd requires comma...
- 2026-08-13: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: commit owned/planned scope is missing; LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須
- 2026-08-12: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: commit subject does not identify task_id/parent_cmd; commit_contract: commit/task history does not contain owned/planned path: logs/cmd_4291_finalize_boundary_r...
- 2026-08-11: gate=gate_report_format result=FAIL executor=saizo reason=cross_repo_commits: cross_repo_commits[0] commit does not change path: backend/app; timestamp: completed/revision_requested report requires a parseable ISO timestamp; operationa...
- 2026-08-11: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: commit subject does not identify task_id/parent_cmd; cross_repo_commits: primary commit_hash is absent from cross_repo_commits
- 2026-08-11: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: task/report commit_contract repo_root mismatch; final_checkpoint: ci_fix clean repro evidence post harness must start before push

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `report_field_set.sh` の現行契約を再確認。binary_checks.resultはyes/noのみ、verdictはgate_report_format.sh自動導出、報告追記はhelper経由に限定する。
Script refs verified: 2026-06-08 9a1c5df09. `report_field_set.sh` のfiles_modified autofixがスペース区切り複数パスを検出し、個別dict変換する。ninja-commitのcommit_hash記録手順への影響なし。
Script refs verified: 2026-06-09 06f5a0856. `report_field_set.sh` にlessons_useful全体上書きBLOCKガード追加(既存件数>新件数で拒否)。ninja-commitはcommit_hash記録のみで影響なし。

<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900
<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `report_field_set.sh` 直近変更(281349be)はresult系書込み高速化で、`bash scripts/report_field_set.sh "$REPORT" <field> <value>` の呼び出し契約と報告YAML構造検証は変更なし。

Script refs verified: 2026-06-20 efb4b9c02. `report_field_set.sh` 直近変更はSC2221/SC2222/SC2154 shellcheck警告のdisableコメント追加で、フィールド設定・binary_checks yes/no・commit_hash記録契約は変更なし。

Script refs verified: 2026-06-26 b12637002. `report_field_set.sh` 直近変更はstatus=completed済み報告へのcommit前フィールド書込みをBLOCKするガード追加。ninja-commitはcommit後にcommit_hashを記録するため、commit前にstatus completedになることはなく影響なし。

<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-16T23:53:10+0900
