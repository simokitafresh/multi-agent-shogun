# Campaign Lane F1 item contracts（2026-07-21）

## F1-related-lessons-fast

- owned implementation: `scripts/lib/deploy_task_related_lessons_fast.py`
- owned contract test: `tests/unit/test_deploy_task_related_lessons_fast.py`
- input: task YAML bytes、lesson YAML群、semantic index。入力はread-only。
- output: 現行 `inject_related_lessons` と同一順序・同一ID・同一summary/detail/descriptionのtask YAML bytes。
- invariant: hitあり・hit0・曖昧語のfixtureで現行出力とのmissing 0 / extra 0 / field差分0。
- performance: 同一fixture 9反復のmedianを現行batch baseline 2,772ms未満にし、wall値をtest出力へ記録する。
- implementation boundary: lesson/indexを各1回だけparseし、1プロセス内で選択とsection置換を完結する。gate/WARN/BLOCKは追加しない。
- integration: 本itemはhelperと固有testだけを作る。`scripts/deploy_task.sh`への接続はS1でID順に行う。

## F1-report-publication-fast

- owned implementation: `scripts/lib/deploy_task_report_publication_fast.py`
- owned contract test: `tests/unit/test_deploy_task_report_publication_fast.py`
- input: task YAML bytes、既存report bytes、report template source。入力はread-only。
- output: 現行 `generate_report_template` と同じ必須field・report identity・lessons_useful・binary_checksを持つreport YAML bytesとtask metadata patch。
- invariant: 新規report、同一identity pending report、異identity stale reportのfixtureでfalse reuse 0、欠落field 0、YAML parse error 0。
- performance: 生成はext4一時file上で1 parse/1 atomic publishとし、9反復medianをisolated baseline 1,579ms未満にする。計測値をtest出力へ記録する。
- implementation boundary: 表示型gate/WARN/BLOCKや追加scanを作らず、既存atomic publication契約を再利用する。
- integration: 本itemはhelperと固有testだけを作る。`scripts/deploy_task.sh`への接続はS1でID順に行う。

## 共通終端契約

- owned paths外diff 0、commit 1本、固有test `TOTAL=N FAIL=0 SKIP=0`。
- 実装用testではなく、上記入出力不変量を守るcontract testとして各test先頭に非空 `test_necessity` を宣言する。
- fixed SHAの `scripts/deploy_task.sh` と本書だけをread-only参照し、他item成果へ依存しない。
