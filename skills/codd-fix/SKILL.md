---
name: codd-fix
argument-hint: "[phenomenon]"
description: |
  CoDD fix PHENOMENONで、観測した事象から設計書・実装・テストを一貫更新するスキル。
  忍者が自然言語で「何が起きているか」を渡し、CoDDが関連設計書を特定して修正案を進める。
  TRIGGER: /codd-fix、codd fix、事象修正、現象修正、PHENOMENON修正
  DO NOT TRIGGER: 設計書の新規生成のみ（→/codd）、性能リファクタ（→/codd-refactor）、テスト実行のみ、運用YAMLの自動修復
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにcodd-fix手順起因のworkaroundが記録されない割合）"
---

<!-- script_refs_checked_at: 2026-06-28T01:36:00+09:00 -->

Script refs verified: 2026-06-28 cmd_karo_hotfix_skill_script_refs_202606280133. `cmd_complete_gate.sh` 直近変更(8c53fdf4d/cmd_3566)はself-grade commit/files coverageで同一parent_cmd配下の全報告YAMLの`files_modified`を集約してgit show -wと照合する内部検査強化。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。codd-fix手順は現行と矛盾なし。

Script refs verified: 2026-06-26 cmd_3550. `cmd_complete_gate.sh` 直近変更はself-grade commit/files coverageのWARN表示追加。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-06-26T19:38:00+09:00 -->

Script refs verified: 2026-06-20 677d0c7f9+26f565ebc. `cmd_complete_gate.sh` 直近変更はCodd/nodeのhome直書き除去、`test_select.sh` 直近変更はcausal index系テスト対応。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

Script refs verified: 2026-06-21 0f202bd9c. `cmd_complete_gate.sh` 直近変更は`related_lessons: []`のempty_lessons_useful偽陽性修正。`bash scripts/cmd_complete_gate.sh <cmd_id>` と `bash scripts/test_select.sh <changed-file>` の呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-06-23T00:30:00+09:00 -->

Script refs verified: 2026-06-16 cmd_3408. `cmd_complete_gate.sh` 直近変更(6eb86ef61)はcommand_files_modified_mismatch FP解消。(1)`read_markers`に11語追加("同構造","と同一","と同じ","同等","踏襲","に基づ","を参考","突合","比較","一覧","解析","分析","取得","検索","出力","表示","呼び出","呼出")。(2)`exec_prefix`検出: bash/python3等がパス直前の場合は実行のみ参照として除外。(3)`clause_boundary`検出: 読点「、」区切りでread_markerとwrite_markerが別節の場合は除外。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。
Script refs verified: 2026-06-14 cmd_3379. `cmd_complete_gate.sh` 直近変更(23edb564f)はGATE CLEAR後にgunshi_gate_reflux.shを2回実行する修正（通常パス+emergency overrideパス両方）。1回目はGATE CLEAR通知前、2回目はGATE CLEAR通知後の軍師report追記分のgate_result null残存を防止（cmd_3370）。`bash scripts/cmd_complete_gate.sh <cmd_id>` の呼び出し契約は変更なし。
Script refs verified: 2026-06-10. `cmd_complete_gate.sh` 呼び出し契約は `bash scripts/cmd_complete_gate.sh <cmd_id>` のまま。新機能: (1)command/files_modified coverageが報告YAMLの`verified_existing_dependency`欄を参照し実行のみ/既存依存ファイルを照合対象から除外(LG037), (2)`check_safety_pattern_removal`で速度修行cmdのcommitから安全パターン削除をBLOCK検出, (3)軍師verdict事前チェック(GATE判定前にreview_logのFAIL/WARNをWARN表示)。`test_select.sh` は`find`→`git ls-files`/`git grep`に高速化済み。新マッピング: `scripts/hooks/*`変更→hookベース名でテスト検索(`test_{hook_base}*.bats`+`test_hook_dispatchers*.bats`)。(4)lesson_impact.tsv空行混入防御: ensure_impact_headerのCR汚染対策+update_lesson_impact_tsvの空行フィルタ追加+DictWriter lineterminator="\n"明示。(5)CR strip でDictReader restkey(list型)クラッシュ修正(isinstance(v,str)判定追加)。

# codd-fix

自然言語の事象を`codd fix [PHENOMENON]`に渡し、設計書、実装、テスト、DAG検証まで一貫して進める。

## 前提

- CoDD v2.18.0: `/home/simokitafresh/.codd-venv/bin/codd`
- PATH設定: `export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"`
- 対象リポに`codd/codd.yaml`または`codd.yaml`が存在すること
- `codd dag build`済み、またはこの手順内でbuildできること
- 必要lexiconは対象リポにinstall済みであること。未確認なら`codd lexicon list --path .`で確認する

## 手順

1. 対象リポで依存確認する。

```bash
export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"
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

<!-- script_refs_checked_at: 2026-06-28T01:36:00+09:00 -->

<!-- script_refs_checked_at: 2026-06-28T01:36:00+09:00 -->
