# CoDD修行L4: archive_completed.sh 設計書品質検証

- 実施者: hayate
- 対象: `scripts/archive_completed.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_L4_codd_c2_hayate`
- CoDD version: 2.18.0

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/archive_completed.sh` は家老のcmd完了判定後に呼ばれ、完了済みcmd、報告YAML、dashboard戦果、KARO更新、cmd-chronicle、resolved pending decisionsを退避し、現役queueを軽量化する。

| 領域 | 入力 | 出力/副作用 |
|---|---|---|
| cmd queue | `queue/shogun_to_karo.yaml`, `queue/completed_changelog.yaml` | 完了cmdを `queue/archive/cmds/` へ退避し、active queueを更新 |
| report | `queue/reports/*.yaml`, `queue/tasks/*.yaml`, `queue/gates/*` | 完了報告を `queue/archive/reports/` へ移動し、元pathへsymlinkを作成 |
| dashboard | `dashboard.md` | 最新更新と戦果の古い行をarchiveへ移動 |
| chronicle | `context/cmd-chronicle.md` | cmd履歴を同期し、30日超を `archive/cmd-chronicle/` へ退避 |
| pending decisions | `queue/pending_decisions.yaml` | `resolved_by=<cmd_id>` のresolved裁定を `queue/archive/pending_decisions_archive.yaml` へ退避 |
| gate flag | `queue/gates/<cmd_id>/archive.done` | `cmd_id` 指定時にarchive完了フラグを作成 |

### 主要フロー

1. 引数を `keep_results` / `cmd_id` として解釈する。`cmd_*` が第1引数ならcmd指定モード。
2. `_REPORT_CACHE` を実行内一時TSVとして生成し、報告status/parent_cmdを共有する。
3. `archive_cmds` がSTKをflock下で単一gawk分類し、完了cmdをarchive候補へ出す。
4. `sync_stk_status_from_archive` がdict形式STKのdelegated完了同期と古いentry退避を行う。
5. `trim_cmd_chronicle` が30日超のchronicle行を月別archiveへ移す。
6. `archive_reports` がreview_gate/archive.done/active childを確認し、完了報告だけを退避する。
7. `archive_karo_section` と `archive_dashboard` がdashboardの古い表示行を退避する。
8. postconditionで完了cmd数とarchive数の不整合をWARN/INFO通知する。

### 制約

- `set -euo pipefail` 前提。
- STK、chronicle、dashboard、pending_decisionsはflockで排他する。
- training/cycle/selfimprovement cmdはGATEフロー外としてreview_gate/archive.doneチェックを緩和する。
- `review_gate.done` がmissing/placeholderの場合、原則として報告を退避しない。ただしgate_metrics CLEARや14日超staleで補完/退避する。
- `archive.done` がmissingの通常cmd報告はsweep退避しない。ただしgate_metrics CLEARや14日超staleで補完/退避する。
- `_REPORT_CACHE` は永続化せず、実行内一時キャッシュに限定する。
- `queue/reports` のsymlinkは掃除し、退避後は元pathへsymlinkを作る。

### 対象範囲外

- cmd完了判定そのもの。
- レビュー/GATEの合否判定。
- 忍者報告YAMLの内容修正。
- dashboard全体生成。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexicon自体は認識されている |
| `codd coverage report --path . --format md` | `Totals: 0 axes, 0 covered signals (0.00%)` | installed lexiconの3 axesがcoverage matrixへ反映されていない |
| `codd elicit --format md --path . --lexicon shogun_core` | `LexiconLoadError: manifest missing required string field 'prompt_extension'` | `shogun_core` はelicit用manifestとして壊れている |
| `codd brownfield scripts/archive_completed.sh ...` | `Directory ... is a file` | brownfieldはファイル単体を対象にできない |
| `codd extract --path . --language bash --source-dirs scripts ...` | `Extracted: 0 modules from 0 files` | 現行設定ではbash scriptsを実質抽出できていない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| 状態遷移安全性 | 中 | review_gate/archive.done/active child保護は厚いが、分岐が多く契約が分散している |
| 排他制御 | 中 | 主要共有ファイルはflockあり。ただしreport移動・gate backfill・symlink生成は分散I/O |
| 失敗可視性 | 中 | WARN/STALE/BACKFILLログはあるが、戻り値は `|| true` で握る箇所がある |
| データ形式耐性 | 中 | flat/list/dict STKを扱うが、gawk text parserとPython yaml parserが混在している |
| 性能 | 高 | 単一gawk、実行内cache、早期returnなど過去CoDD改善が入っている |
| テスト網羅 | 高 | `tests/unit/test_archive_completed.bats` に23本の専用テストがある |
| CoDD文書化 | 中 | 過去specは性能改善中心。現行1,686行全体の契約文書は不足 |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | 「報告をarchiveしてよい条件」の決定表が設計書に存在しない | review_gate/archive.done/active child/stale/training例外が増え、将来変更で報告消失や永久残存を起こす |
| GAP-2 | HIGH | `gate_metrics_has_clear` 依存がgate_metrics.logローテーション後にどうなるか未契約 | CLEAR backfillが効かず、古い報告が残存またはstale退避へ流れる |
| GAP-3 | MEDIUM | `yaml.dump` 使用箇所と「運用YAML上書き禁止」の例外境界が不明確 | STK/pending_decisions/archive YAMLのどこでdumpが許容されるか判断が割れる |
| GAP-4 | MEDIUM | report退避後symlink生成失敗時の復旧契約がない | 元path参照中の忍者/家老が報告を見失う可能性 |
| GAP-5 | MEDIUM | dashboard/KARO sectionのarchiveはflock前に退避対象行を読んでいる | 読み取りからflock取得までにdashboardが変わると別行を消すTOCTOU余地 |
| GAP-6 | LOW | `keep_results=0` を仕様として許すか不明 | 全戦果退避が意図か誤操作か判断不能 |

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `codd validate --path .` | `OK: validated 16 Markdown files under configured doc_dirs` |
| `codd measure --path . --json` | `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16` |
| `codd coverage report --path . --format md` | 0 axes。coverage設定またはlexicon manifest側に穴 |
| `codd elicit --format md --path . --lexicon shogun_core` | `prompt_extension` 欠落で失敗 |
| `codd brownfield scripts/archive_completed.sh ...` | ファイル単体を拒否 |
| `codd extract --path . --language bash --source-dirs scripts ...` | `0 modules from 0 files` |

### 既存テスト範囲

`tests/unit/test_archive_completed.bats` は23本の専用テストを持つ。主なcoverageは、completed_changelog fallback、chronicle同期、flock timeout、pending decisions、training cmd例外、deploy_preflight placeholder保護、gate_metrics CLEAR backfill、14日超stale退避、overflow cap、regular cmd review_gate必須である。

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 8 | ヘッダーと関数分割で目的は追える |
| 入出力契約 | 6 | 入出力が多く、設計書としての決定表が不足 |
| 状態遷移安全性 | 7 | active child、review_gate、archive.done保護がある |
| 排他/原子性 | 7 | 主要ファイルはflockあり。ただし一部読み取りはflock外 |
| エラー可視性 | 6 | WARNは多いが `|| true` と補完処理が混じり、失敗の重みが読みづらい |
| 性能 | 8 | 過去CoDD改善でgawk/cache/early returnが入っている |
| テスト容易性 | 8 | 専用Bats 23本がある |
| 保守性 | 5 | 1,686行単一ファイルで責務が多い |
| 総合 | 6.9/10 | 防御は厚いが、アーカイブ可否の仕様がコード内分岐に埋もれている |

### 改善点

1. report archive可否の決定表を `codd/requirements` または `docs/research` に正本化する。
   - 対応GAP: GAP-1
   - 期待効果: review_gate/archive.done/stale/training/active childの追加変更時に仕様差分を検出しやすくする。

2. gate_metrics backfillの前提を「ローテーション後は使えない可能性あり」として契約化し、代替sourceを明示する。
   - 対応GAP: GAP-2
   - 期待効果: CLEAR証跡が消えた場合の残存/退避判断を設計段階で扱える。

3. `yaml.dump` 許容箇所を分類する。
   - 対応GAP: GAP-3
   - 期待効果: 運用YAML上書き禁止とarchiveファイル生成の例外境界を明確にする。

4. dashboard/KARO section archiveの行番号取得をflock内へ寄せる。
   - 対応GAP: GAP-5
   - 期待効果: 読み取りから削除までのTOCTOUを減らす。

5. symlink生成失敗時のfallbackをログだけでなく検出可能なpostconditionへ上げる。
   - 対応GAP: GAP-4
   - 期待効果: 元report path参照保護の失敗を家老/monitorが検知できる。

6. `keep_results=0` の仕様を明文化する。
   - 対応GAP: GAP-6
   - 期待効果: 全戦果退避を意図的操作として許すか、誤操作として拒否するかを固定できる。

## CoDD側の発見

- `shogun_core` はinstalled扱いだが、`elicit` では `prompt_extension` 欠落でロードできない。
- `coverage report` は0 axesとなり、installed lexiconの3 axesがcoverage matrixへ入っていない。
- `brownfield` はファイル単体を拒否するため、bash単体スクリプトのbrownfield評価には使いづらい。
- `extract` はbash scriptsに対して `0 modules from 0 files` となり、現行設定では対象抽出の入口として機能しない。

## 結論

`archive_completed.sh` は過去CoDD改善と専用Batsにより、防御・性能・回帰テストは厚い。一方で、1,686行の単一スクリプトに「archiveしてよい条件」が分散しており、次の品質改善は実装最適化よりも決定表の正本化が最優先である。

## CoDD Generate Results

- 実施者: kagemaru
- 実施日: 2026-05-16
- task_id: `cmd_training_codd_h1_kagemaru`
- 対象: `scripts/archive_completed.sh`
- 実行補足: 追加指示どおり、validate/measureは `timeout 600` 付きで実行した。

### codd generate

実行コマンド:

```bash
codd generate --wave 1 --path .
```

結果:

```text
wave_config not found. Auto-generating from requirements...
wave_config generated from 11 requirement(s)
Skipped: docs/test/acceptance_criteria.md (test:acceptance-criteria)
Skipped: docs/governance/adr_batch_yaml_io.md (governance:adr-batch-yaml-io)
Wave 1: 0 generated, 2 skipped
```

解釈: 既存の `docs/research/hayate_codd_L4_archive_completed_20260516.md` は `codd generate` の入力requirements/wave_configに接続されていないため、`archive_completed.sh` 固有の新規生成物は出なかった。`generate` は既存repo requirementsからwave_configを自動生成し、2件を既存出力としてskipした。

### codd validate

`generate` 直後の `codd/codd.yaml` はCoDD側で広域docs走査設定へ書き換わり、`timeout 600 codd validate --path .` は以下で失敗した。

```text
ERROR: 652 error(s), 11 blocked issue(s), 382 warning(s), 627 Markdown files checked
```

これは `archive_completed.sh` の設計品質ではなく、`generate` が `scan.doc_dirs` を `docs/` へ拡張した副作用である。さらに同時実行した `measure` では一時的に `codd/codd.yaml` が削除状態となり、`CoDD config dir not found` で失敗したため、この値は正式計測として採用しない。

`codd/codd.yaml` を追完前の設定へ戻した後、再実行した正式結果:

```bash
timeout 600 codd validate --path .
```

```text
OK: validated 16 Markdown files under configured doc_dirs
```

### codd measure

復元後の正式結果:

```bash
timeout 600 codd measure --path . --json
```

```json
{
  "health_score": 95,
  "graph": {
    "total_nodes": 16,
    "total_edges": 12,
    "orphan_nodes": 4,
    "max_depth": 1,
    "avg_out_degree": 0.75,
    "connectivity": 0.05
  },
  "coverage": {
    "tracked_files": 0,
    "source_files": 0,
    "design_documents": 627,
    "coverage_ratio": 0.0
  },
  "quality": {
    "validation_errors": 0,
    "validation_warnings": 0,
    "policy_critical": 0,
    "policy_warnings": 0,
    "documents_checked": 16,
    "files_policy_checked": 0,
    "rules_applied": 0
  }
}
```

health_score: `95`

### 追完結論

`codd generate` は実行済みだが、既存研究メモはCoDD requirements/wave_configへ接続されていないため、`archive_completed.sh` 固有の設計書生成には至らなかった。`validate` と `measure` は、`generate` 副作用の設定変更を戻した状態でPASSし、正式なhealth_scoreは `95` である。
