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
- round2 correction: 自作期待値だけのfixtureは禁止。固定SHAの現行 `inject_related_lessons` を同一入力で実行し、hit/hit0/曖昧語/target_files/semantic boostの全fixtureで実出力を比較する。現行比較を実行しないtestはFAIL。

## F1-report-publication-fast

- owned implementation: `scripts/lib/deploy_task_report_publication_fast.py`
- owned contract test: `tests/unit/test_deploy_task_report_publication_fast.py`
- input: task YAML bytes、既存report bytes、report template source。入力はread-only。
- output: 現行 `generate_report_template` と同じ必須field・report identity・lessons_useful・binary_checksを持つreport YAML bytesとtask metadata patch。
- invariant: 新規report、同一identity pending report、異identity stale reportのfixtureでfalse reuse 0、欠落field 0、YAML parse error 0。
- performance: 生成はext4一時file上で1 parse/1 atomic publishとし、9反復medianをisolated baseline 1,579ms未満にする。計測値をtest出力へ記録する。
- implementation boundary: 表示型gate/WARN/BLOCKや追加scanを作らず、既存atomic publication契約を再利用する。
- YAML safety: 運用report bytesの生成に `yaml.dump` / `yaml.safe_dump` を使わない。既存template bytesを保持し、対象sectionだけをtextual mutationする。
- integration: 本itemはhelperと固有testだけを作る。`scripts/deploy_task.sh`への接続はS1でID順に行う。

## F1-semantic-context-fast

- owned implementation: `scripts/lib/deploy_task_semantic_context_fast.py`
- owned contract test: `tests/unit/test_deploy_task_semantic_context_fast.py`
- input/output: 固定SHAの `inject_semantic_concepts` と同一task bytes・同一semantic indexから、同一concept順序・同一task sectionを返す。
- invariant: hit/hit0/曖昧alias/target pathの4 fixtureでmissing 0 / extra 0 / field差分0。
- performance: 9反復medianを自然receipt baseline 4,307ms未満。index parseは1回、追加gate/WARN/BLOCKなし。

## F1-preflight-fast

- owned implementation: `scripts/lib/deploy_task_preflight_fast.py`
- owned contract test: `tests/unit/test_deploy_task_preflight_fast.py`
- input/output: 固定SHApreflightの検査集合とrcを保持し、同一source taskに同一PASS/FAIL集合を返す。
- invariant: valid/malformed/missing path/duplicate activeの4 fixtureでFP0/FN0、検査削除0。
- performance: 9反復medianを自然receipt baseline 8,686ms未満。read/parseをbatch化し、表示型検査の新設なし。

## F1-post-delivery-fast

- owned implementation: `scripts/lib/deploy_task_post_delivery_fast.py`
- owned contract test: `tests/unit/test_deploy_task_post_delivery_fast.py`
- input/output: 固定SHApost-deliveryの通知対象・message ID・成功/失敗分類を保持する。
- invariant: normal/duplicate/watcher delay/failed sendの4 fixtureで通知喪失0・duplicate0・分類差分0。
- performance: 9反復medianを自然receipt baseline 7,213ms未満。待機直列化を除き、配送契約は弱めない。

## F1-cold-memory-boost-fast

- owned implementation: `scripts/lib/deploy_task_lesson_memory_boost_fast.py`
- owned contract test: `tests/unit/test_deploy_task_lesson_memory_boost_fast.py`
- input/output: `event_concepts`/`events`から得るconcept・lesson boostをwarm/coldで同一順序・同一scoreにする。
- invariant: ext4 cache warm/cold、source newer、並列2 readerでmissing0/extra0/score差分0。正本9pへの重いGROUP BY fallbackは禁止。
- performance: coldを自然receipt 157,474ms未満かつ60,000ms未満、warm 9反復median 1,000ms未満。追加gate/WARN/BLOCKなし。

## 共通終端契約

- owned paths外diff 0、commit 1本、固有test `TOTAL=N FAIL=0 SKIP=0`。
- 実装用testではなく、上記入出力不変量を守るcontract testとして各test先頭に非空 `test_necessity` を宣言する。
- fixed SHAの `scripts/deploy_task.sh` と本書だけをread-only参照し、他item成果へ依存しない。
