---
<!-- script_refs_checked_at: 2026-07-18T03:18:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_freshness_batch検分: cmd_complete_gate.sh 89ebc48a3はcontext更新候補の機械可読出力を追加。単一cmd_id引数、CLEAR/BLOCK出口、codd-fix手順の契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-17T09:45:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: cmd_complete_gate.sh 567c8710cはcontext freshnessをreport commit hashでも相関するfail-closed強化、test_select.sh 68bda0869/fa403eb51はreport contract対象を共有8-file selectorへ集約。codd-fixのCLI/完了gate呼出契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 2026-07-16再検分: cmd_complete_gate.sh da6641aeb。CMD_ID lock競合時の偽成功exit 0を廃止し、terminal CLEAR/BLOCK未確定としてEX_TEMPFAIL(exit 75)へ変更。単一cmd_id引数とterminal CLEAR/BLOCK契約は不変。 -->
<!-- cmd_karo_hotfix_shogun_startup_four_blocks検分: cmd_complete_gate.sh/test_select.sh直近差分は証拠結合と.githooks選択の内部強化。単一phenomenon入力とfix workflow契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- GA-263後検分: cmd_complete_gate.sh fed0fd5e5をgit showで確認。SG7 project/spec/scopeの直接証拠結合、report files_modified YAML-safe抽出、report commit anchor、tracked docs wiringを追加した内部fail-closed強化。`bash scripts/cmd_complete_gate.sh <cmd_id>`単一引数・CLEAR/BLOCK exit契約は不変。 -->
<!-- cmd_karo_hotfix_skill_refs_core_202607152126検分: cmd_complete_gate.sh 22609351d/3cf5486fd/d85d3cb2bをgit showで確認。report summaryのLevel5事前供給、archive command coverage fallback、exact review manifest再検証はいずれも完了gate内部の生成・判定強化。`bash scripts/cmd_complete_gate.sh <cmd_id>`の単一引数、CLEAR/BLOCK exit、codd-fix本文の呼出し順序は不変。 -->
name: codd-fix
argument-hint: "[phenomenon]"
description: |
  CoDD fix PHENOMENONで、観測した事象から設計書・実装・テストを一貫更新するスキル。
  忍者が自然言語で「何が起きているか」を渡し、CoDDが関連設計書を特定して修正案を進める。
  TRIGGER: /codd-fix、codd fix、事象修正、現象修正、PHENOMENON修正
  DO NOT TRIGGER: 設計書の新規生成のみ（→/codd）、性能リファクタ（→/codd-refactor）、テスト実行のみ、運用YAMLの自動修復
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにcodd-fix手順起因のworkaroundが記録されない割合）"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- cmd_karo_hotfix_skill_refs_202607151824検分: cmd_complete_gate.sh 6fc2e2957/ab302df7b/1616a1eb3/26dd9b29c/81162392b/d42c0bcf2をgit showで確認。完了証跡race防止、post-clear監査、専用test認識、Karo CTX計測、lesson feedback集合厳密化/null fallbackはいずれもgate内部強化。単一cmd_id引数・CLEAR/BLOCK exit・後処理副作用順序は不変。 -->
<!-- 2026-07-15検分: cmd_complete_gate.sh ab302df7b/1616a1eb3はCLEAR後のsemantic auditをdurable worker化し、専用test警告を精密化。`bash scripts/cmd_complete_gate.sh <cmd_id>`の引数・CLEAR/BLOCK exit契約・codd-fix手順は不変。 -->
<!-- cmd_3948検分: cmd_complete_gate.sh直近差分は承認済test-only commitのcontext reflux除外。呼出し契約不変。 -->
<!-- 検分: cmd_complete_gate.sh 9018f5287/0c5f0edcc/dd368dee5/edbdb88bc/a48d80420をgit showで確認。insight消費の証跡付き解決、task/project完全一致、context source境界BLOCK、review rework履歴の単調保存を追加したgate内部強化。`bash scripts/cmd_complete_gate.sh <cmd_id>`の単一CMD_ID引数、CLEAR/BLOCK判定とexit契約、codd-fix本文の呼出し順序は不変。 -->

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900

Script refs verified: 2026-07-11 shogun起動時gate WARN解消。checked_at以降の変更(review two-phase race fix系/inbox gate trigger detach/report discovery偽BLOCK根治/rg grepフォールバック/memory DB cache atomic recovery)をgit logで確認。いずれも内部強化であり呼び出し契約・出口文言・本文手順に変更なし。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: cmd_complete_gate.sh e89307c7c(報告commitと他忍者dirty hunkの非重複判定を共有libraryへSSOT化)。`bash scripts/cmd_complete_gate.sh <cmd_id>`の引数・CLEAR/BLOCK出口・codd-fix本文手順は不変 -->
<!-- 検分: cmd_complete_gate.sh a76572f27(GATE CLEAR時のauto lesson_write.sh呼出しへsubdomain/target_files/origin/when/how自動推定フィールドを追加=lesson_candidate登録内容の内部強化)。`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約・GATE CLEAR/BLOCK出口・codd-fix本文手順は不変 -->

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: cmd_complete_gate.sh b5b751536(reflux/hotfix高速回転でtask YAML上書き時のduration_secフォールバックにper-cmd不変マーカー追加=計測内部強化)+218aa852a(GATE CLEAR時cmd_quality_log呼出しをBLOCK側と同じ同期実行へ統一=品質記録漏れ防止の内部処理変更)。`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約・GATE CLEAR/BLOCK出口・codd-fix本文手順は不変 -->

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: cmd_complete_gate.sh d387255f0(gate metrics benchmarks分離=計測内部変更)+bc8c87bc5(report gateの非重複post-commit dirty hunk許容=FAIL条件緩和)。`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約・GATE CLEAR/BLOCK出口・codd-fix本文手順は不変 -->
<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `cmd_complete_gate.sh` checked_at以降の変更(c4373d06/0c73c7d1)をgit showで確認。c4373d06はGATE CLEAR時のthroughput段階別duration計測(deploy/work/finalize/e2e秒数)をGATE_METRICS_LOGへ追加列として記録する計測強化。0c73c7d1はntfy/将軍/家老通知を`send_clear_notifications_once`へ集約し多重送信を防止した上で、lesson_merge/archive/gunshi_gate_reflux等の後処理をasync化(非同期queued)した内部高速化。いずれも`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約、GATE CLEAR/BLOCK出口の標準出力文言、codd-fix本文手順は変更なし。

Script refs verified: 2026-07-07 cmd_3743. `cmd_complete_gate.sh` checked_at以降の変更(dabcb6144)をgit logで確認。model profile source guardの内部検査強化で、`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約、GATE CLEAR/BLOCK出口、codd-fix本文手順は変更なし。

Script refs verified: 2026-07-05 cmd_karo_hotfix_skill_refs_codd_fix_2026070501. `cmd_complete_gate.sh` checked_at以降の変更(616b469f2)をgit log/showで確認。616b469f2はlesson retirement SSOT path修正で、GATE CLEAR/BLOCK時の自動deprecate/retire処理を`lesson_deprecate.sh`から`lesson_write.sh --retire`へ寄せ、`retired: true`/`status: retired`も既存退役済み扱いに含める内部処理変更。`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約、GATE CLEAR/BLOCKの基本出口、codd-fix本文の実行手順には変更なし。

Script refs verified: 2026-07-04 cmd_training_skill_refs_codd_fix_202607042005. `cmd_complete_gate.sh` checked_at以降の変更(997178ac8/b77e5546a)をgit log/showで確認。997178ac8はno-task fast pathにparent report検証を追加し、既存reportがあるcmdを測定用fast pathで誤CLEARしない内部gate強化。b77e5546aはCoDD registry append失敗をWARN化し、set -e cascadeでidle-transition等の完了後処理が止まる問題を防ぐ非BLOCK化。どちらも`bash scripts/cmd_complete_gate.sh <cmd_id>`の呼び出し契約、GATE CLEAR/BLOCKの基本出口、codd-fix本文の実行手順には変更なし。

Script refs verified: 2026-07-02T20:45 将軍検証. `cmd_complete_gate.sh` 直近変更(5c3b58b0f/5b555e616/1d363aa7b)はhotfix完全名・短縮名の二重GATE CLEAR通知dedup、登録済みlesson_candidateのWARN抑制、lesson impact追随の非同期化で、いずれも内部処理。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。本日cmd_3661完了時に単発GATE CLEAR通知の実動作を確認済み。codd-fix手順は現行と矛盾なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `cmd_complete_gate.sh` 直近変更(59bdca420/a3a6f8c53/8c53fdf4d)は運用知識保存、gate速度高速化、phase report集約の内部処理で、`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。codd-fix手順は現行と矛盾なし。

Script refs verified: 2026-06-28 cmd_karo_hotfix_skill_script_refs_202606280133. `cmd_complete_gate.sh` 直近変更(8c53fdf4d/cmd_3566)はself-grade commit/files coverageで同一parent_cmd配下の全報告YAMLの`files_modified`を集約してgit show -wと照合する内部検査強化。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。codd-fix手順は現行と矛盾なし。

Script refs verified: 2026-06-26 cmd_3550. `cmd_complete_gate.sh` 直近変更はself-grade commit/files coverageのWARN表示追加。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-06-20 677d0c7f9+26f565ebc. `cmd_complete_gate.sh` 直近変更はCodd/nodeのhome直書き除去、`test_select.sh` 直近変更はcausal index系テスト対応。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

Script refs verified: 2026-06-21 0f202bd9c. `cmd_complete_gate.sh` 直近変更は`related_lessons: []`のempty_lessons_useful偽陽性修正。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-06-16 cmd_3408. `cmd_complete_gate.sh` 直近変更(6eb86ef61)はcommand_files_modified_mismatch FP解消。(1)`read_markers`に11語追加("同構造","と同一","と同じ","同等","踏襲","に基づ","を参考","突合","比較","一覧","解析","分析","取得","検索","出力","表示","呼び出","呼出")。(2)`exec_prefix`検出: bash/python3等がパス直前の場合は実行のみ参照として除外。(3)`clause_boundary`検出: 読点「、」区切りでread_markerとwrite_markerが別節の場合は除外。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。
Script refs verified: 2026-06-14 cmd_3379. `cmd_complete_gate.sh` 直近変更(23edb564f)はGATE CLEAR後にgunshi_gate_reflux.shを2回実行する修正（通常パス+emergency overrideパス両方）。1回目はGATE CLEAR通知前、2回目はGATE CLEAR通知後の軍師report追記分のgate_result null残存を防止（cmd_3370）。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。
Script refs verified: 2026-06-10. `cmd_complete_gate.sh` 呼び出し契約は `bash scripts/cmd_complete_gate.sh <cmd_id>` のまま。新機能: (1)command/files_modified coverageが報告YAMLの`verified_existing_dependency`欄を参照し実行のみ/既存依存ファイルを照合対象から除外(LG037), (2)`check_safety_pattern_removal`で速度修行cmdのcommitから安全パターン削除をBLOCK検出, (3)軍師verdict事前チェック(GATE判定前にreview_logのFAIL/WARNをWARN表示)。`test_select.sh` は`find`→`git ls-files`/`git grep`に高速化済み。新マッピング: `scripts/hooks/*`変更→hookベース名でテスト検索(`test_{hook_base}*.bats`+`test_hook_dispatchers*.bats`)。(4)lesson_impact.tsv空行混入防御: ensure_impact_headerのCR汚染対策+update_lesson_impact_tsvの空行フィルタ追加+DictWriter lineterminator="\n"明示。(5)CR strip でDictReader restkey(list型)クラッシュ修正(isinstance(v,str)判定追加)。

# codd-fix

自然言語の事象を`codd fix [PHENOMENON]`に渡し、設計書、実装、テスト、DAG検証まで一貫して進める。

## 前提

- CoDD v2.18.0: `$HOME/.codd-venv/bin/codd`
- PATH設定: `export PATH="$HOME/.codd-venv/bin:$PATH"`
- 対象リポに`codd/codd.yaml`または`codd.yaml`が存在すること
- `codd dag build`済み、またはこの手順内でbuildできること
- 必要lexiconは対象リポにinstall済みであること。未確認なら`codd lexicon list --path .`で確認する

## 手順

1. 対象リポで依存確認する。

```bash
export PATH="$HOME/.codd-venv/bin:$PATH"
codd --version
codd fix --help
codd dag verify --help
```

2. 事象を1文に絞る。

良い入力は「観測した問題」と「望む状態」を含む。コード変更指示に寄せすぎない。

```bash
PHENOMENON="ログインエラー時の表示が利用者に原因を伝えていない"
```

3. 非対話で計画を確認する。

```bash
codd fix "$PHENOMENON" --path . --non-interactive --on-ambiguity abort --dry-run
```

4. 曖昧性がなければ適用する。

```bash
codd fix "$PHENOMENON" --path . --non-interactive --on-ambiguity abort --no-push
```

5. DAGを再構築し検証する。

```bash
codd dag build --path . --format json --output codd/dag_fix_verify.json
codd dag verify --all --path . --format json
```

CoDD v2.18.0で`--all`が未対応の環境では、同等の全体検証として次を実行する。

```bash
codd dag verify --path . --format json
```

6. 変更内容を確認し、対象テストを実行する。

```bash
git diff --stat
bash scripts/test_select.sh <changed-file>
```

共通基盤やCI gateを触った場合は関連batsを実行する。`scripts/gates/*`を変更した場合、`scripts/test_select.sh`は当該gateの直接テストを選択し、`scripts/cmd_complete_gate.sh`がそのgateを参照している場合のみ`tests/unit/test_cmd_complete_gate*.bats`も選択する。`gate_report_format.sh`・`gate_report_autofix.sh`・`gate_dc_duplicate.sh`・`gate_diagnose_check.sh`変更時は`test_gate_small_consolidated.bats`も選択する。`context/*.md`を変更した場合、`scripts/test_select.sh`は`test_context_freshness_check.bats`・`test_gate_context_freshness.bats`・`test_gate_vercel_phase.bats`を選択する（cmd_2843）。`docs/rule/*.md`を変更した場合、`scripts/test_select.sh`は`test_semantic_index_update.bats`・`test_context_freshness_check.bats`を選択する。`instructions/gunshi.md`を変更した場合、`scripts/test_select.sh`は`test_cli_adapter.bats`・`test_gate_gunshi_cs_checklist.bats`・`test_gunshi_next_action.bats`・`test_semantic_index_update.bats`を選択する。`skills/*/SKILL.md`単独変更は既知のテスト不要対象としてWARNなしでスキップする。`report_field_set.sh`変更はdeploy_task+gate_report_format系テストを選択する。`memory_db_import.py`・`memory_db_query.sh`・`semantic_search.sh`変更はmemory_db/semantic関連テストを選択する（cmd_3026確認: cmd_38aaf66f）。`scripts/hooks/*`変更はhookベース名(`-`→`_`変換)で`test_{hook_base}*.bats`+`test_hook_dispatchers*.bats`を選択する。SKIPはFAILとして扱う。

`scripts/cmd_complete_gate.sh`変更時は、cmd source YAML欠落をdraft lesson check / recon knowledge persistence checkでSKIP扱いにする最新挙動を前提にする。command/files_modified coverageは、偵察等の`files_modified`が「偵察のみ」「コード変更なし」「none」「N/A」などのno-code-change sentinelだけの場合のみSKIPし、通常ファイルパスのtypoはBLOCK継続する。報告YAMLに`verified_existing_dependency`欄がある場合、該当ファイルはcoverage照合から除外される(LG037)。速度修行cmdでは`check_safety_pattern_removal`が安全パターン(`2>/dev/null`/`|| true`/`trap`等)の削除をBLOCK検出する。GATE判定前に軍師verdict事前チェックが`gunshi_review_log.yaml`のFAIL/WARNをWARN表示する。GATE CLEAR後は通常パス・emergency overrideパス両方で`gunshi_gate_reflux.sh`を2回実行する（1回目はGATE CLEAR通知前、2回目はGATE CLEAR通知後のreport追記分のgate_result null残存を防止、cmd_3370）。

## 報告

- `codd fix --dry-run`の結果
- 実行した`codd fix "$PHENOMENON"`コマンド
- `codd dag build`と`codd dag verify`の結果
- 実行したテストとSKIP数
- 変更された設計書、実装、テストのパス

## 禁止

- 運用YAMLに`dag verify --auto-repair --apply`を使うな
- `codd fix`の曖昧性を無視して`--on-ambiguity top1`で進めるな
- `--no-push`なしで実行するな。忍者はpush禁止
- 事象ではなく広すぎる実装指示を渡すな

Script refs verified: 2026-06-21 615d1c2d7 cmd_3476. `cmd_complete_gate.sh` 直近変更は`files_modified`内のchange/statusで`checked_not_modified`を受け付ける追加（「確認したが変更不要」の明示経路として`verified_existing_dependency`と同じ除外ソース）。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。

Script refs verified: 2026-06-26 e658e3c37. `cmd_complete_gate.sh` 直近変更はgate design-doc command scope偽陽性修正。codd-fixの呼び出し契約は変更なし。

Script refs verified: 2026-06-28 8c53fdf4d. `cmd_complete_gate.sh` 直近変更は分割/phase reportを完了ゲートで統合参照する内部集約追加。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-07-16T23:53:24+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
