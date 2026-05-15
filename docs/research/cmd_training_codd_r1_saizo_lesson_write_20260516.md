# CoDD修行R1: lesson_write.sh 設計書品質検証

- 実施者: saizo
- 対象: `scripts/lesson_write.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_codd_r1_saizo`
- CoDD version: 2.18.0
- pipeline: spec -> elicit/lexicon -> generate/extract -> validate -> measure

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/lesson_write.sh` は、PJ別の教訓SSOTである `<project_path>/tasks/lessons.md` に新規教訓を排他付きで追記し、必要に応じてcontext索引・sync・pending decision・cmd gate flagへ波及させる境界スクリプトである。

### 入力契約

| 入力 | 契約 |
|---|---|
| `project_id` | `config/projects.yaml` に存在するPJ ID。`cmd_*` は誤用として拒否 |
| `title` | 教訓タイトル。完全重複は `--force` なしでは拒否 |
| `detail` | 10文字以上の具体的な教訓本文 |
| `source_cmd` | 任意。target_path/files_modified自動推定、context索引、lesson.doneに使う |
| `author` | 任意。未指定時は `karo` |
| `cmd_id` | 任意。指定時は `queue/gates/<cmd_id>/lesson.done` を作る |
| options | `--status`, `--tags`, `--subdomain`, `--target-files`, `--when`, `--how`, `--if`, `--then`, `--because`, `--strategic`, `--retire`, `--retag` |

### 出力契約

| 出力 | 契約 |
|---|---|
| `<project_path>/tasks/lessons.md` | `flock` 付きで `### LNNN: title` 形式の教訓をappend |
| `context/*.md` | route解決後、lesson索引と `last_synced_lesson` markerを更新 |
| `scripts/sync_lessons.sh` | 教訓syncを非blocking実行 |
| `queue/gates/<cmd_id>/lesson.done` | `cmd_id` 指定時のみ生成 |
| pending decision | `--strategic` 指定時のみMCP昇格候補を登録 |
| stdout/stderr | new lesson ID、WARN、REFLUX_CHECKを表示 |

### 主要フロー

1. `LESSON_WRITE_SCRIPT_DIR` または自身のパスから `SCRIPT_DIR` を決める。
2. project metadataを `config/projects.yaml` から解決し、対象 `tasks/lessons.md` を決める。
3. optionを1-passでparseし、`--status` と `--subdomain` を検証する。
4. `--retag` / `--retire` の専用modeなら対象lessonだけ更新して終了する。
5. 必須引数、`project_id`, detail長、lessons.md存在を検証する。
6. `source_cmd` やreportから `target_files` を推定する。
7. `flock` 内で最大lesson ID、完全重複、類似title WARN、tagを処理し、new lessonをappendする。
8. sync/context/pending decision/lesson.done/reflux checkを後続処理する。

### 制約

- 運用YAMLへの `yaml.dump` は使わない。status変更やreport更新は専用helperの責務。
- lesson appendは `flock -w 10`、最大3回retry。
- `sync_lessons.sh` とcontext追記失敗はWARNまたは非blockingで、lesson本体のappendを優先する。
- title完全一致はBLOCK、Jaccard類似はWARN継続。
- `--subdomain` は `fe|be|gs|infra` に正規化し、それ以外は拒否する。
- `--retire` / `--retag` は通常appendと別mode。

### 対象範囲外

- 教訓内容の最終レビューと正式採否判断。
- `sync_lessons.sh` 内部の同期品質保証。
- `pending_decision_write.sh` の解決フロー。
- context索引の設計そのもの。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexicon自体は認識されている |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals | coverage matrixにlexicon axesが出ていない |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 | elicitは現状使えないため手動穴出しが必要 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_lesson_write_codd_extract_20260516` | 0 modules from 0 files | bash script抽出が実質機能していない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| 入力妥当性 | 高 | 必須引数、cmd誤用、detail長、project存在、status/subdomainを拒否 |
| SSOT追記の排他 | 高 | lessons.md lock + retry + append |
| 重複防止 | 中 | 完全一致はBLOCK、類似はWARNのみ |
| context同期 | 中 | route解決 + marker更新あり。ただしPython heredocで失敗時はWARN寄り |
| source_cmd波及 | 中 | target_path/report files_modified自動推定があるがYAML近似awkに依存 |
| mode分離 | 中 | append/retire/retagが1ファイル内で分岐し、契約が散らばる |
| Reflux還流 | 中 | PI/RUNBOOK/INSTRUCTIONS grepはあるが日本語のみではSKIPPEDになる |
| テスト網羅 | 中 | `tests/unit/test_lesson_write.bats` 28件PASS。ただしcontext更新失敗、sync失敗、strategic、source_cmd推定の負例は薄い |
| CoDD可視性 | 低 | codd source coverageが0で、script本体がDAGに載っていない |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | `lesson_write.sh` 専用の現行CoDD requirement/design nodeがない | lesson append、context sync、reflux、strategicの契約がDAGで追跡できない |
| GAP-2 | HIGH | append成功後のcontext/sync/pending decision失敗時の状態契約が弱い | lesson本体だけ書かれ、索引・sync・MCP候補が欠落した状態を後で検知しづらい |
| GAP-3 | MEDIUM | `source_cmd` からtarget_filesを推定するawkがqueue/archive/report schemaに依存 | queue形式変更でtarget_filesが静かに空になる |
| GAP-4 | MEDIUM | `--retag` / `--retire` modeと通常append modeの責務が同居 | regression時に別modeへ副作用が及びやすい |
| GAP-5 | MEDIUM | context更新のPython heredocはcontext fileを直接writeする | 書込みhelper統一の観点では特別扱いで、失敗・競合の設計書が必要 |
| GAP-6 | MEDIUM | Reflux checkのkeyword抽出が英数字token中心 | 日本語教訓ではSKIPPEDになり、還流漏れを検出できない |
| GAP-7 | LOW | `sync_lessons.sh` 失敗を非blockingにする条件が設計書化されていない | sync必須なcmdでもWARNで進んだように見える可能性 |
| GAP-8 | LOW | `--strategic` のpending decision登録とMCP昇格候補の運用境界が薄い | 教訓と裁定候補の二重管理が起きやすい |

Recommended lexicon axes:

- `lesson_ssot_atomic_append`: lesson ID採番とappendの排他境界。
- `lesson_context_sync_contract`: append後にcontext markerをどう更新し、失敗時にどう復旧するか。
- `lesson_source_cmd_target_files`: source_cmdからtarget_filesを推定するschema契約。
- `lesson_mode_isolation`: append/retire/retagの副作用分離。
- `lesson_reflux_japanese_coverage`: 日本語教訓でも還流漏れを検出する軸。
- `lesson_sync_nonblocking_policy`: sync失敗をWARNにできる条件。

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `bash -n scripts/lesson_write.sh` | PASS |
| `bats tests/unit/test_lesson_write.bats` | PASS: 28/28, SKIP 0 |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_lesson_write_codd_extract_20260516` | 0 modules from 0 files |

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 8 | usageと出力先が明確 |
| 入力契約 | 8 | project/status/subdomain/detail長などの検証がある |
| 排他/原子性 | 7 | appendはflockで堅いが後続sync/contextは別境界 |
| 状態復旧性 | 5 | append後の部分失敗を検知する専用gateが薄い |
| mode分離 | 5 | append/retire/retag/strategic/refluxが単一scriptに集中 |
| テスト網羅 | 7 | 専用Bats 28件PASS。ただしsync/context/strategicのfailure pathは不足 |
| CoDD可視性 | 3 | source coverage 0、extract 0 modules、専用nodeなし |
| 保守性 | 6 | bash native最適化はあるがPython heredocとawk schema推定が混在 |
| 総合 | 6.1/10 | core appendは堅いが、周辺波及の契約とCoDD可視性が弱い |

### 改善点

1. `codd/requirements/lesson_write_requirements.md` と `codd/design/lesson_write_design.md` を追加し、append、context sync、reflux、strategic、retire/retagをDAG化する。
2. append成功後のpartial failure gateを追加する。例: lesson IDが追加されたのにcontext marker、sync result、lesson.doneが欠ける状態を検知する。
3. `source_cmd` -> `target_files` 推定をschema-aware helperに切り出す。queue/archive/reportのYAML近似awkを単体テスト可能にする。
4. `--retire` / `--retag` を別scriptまたは明示subcommandへ分離し、通常appendのregression surfaceを縮小する。
5. Reflux checkを日本語tokenでも動くように、英数字grepだけでなくfile path/source_cmd/tag/subdomainをfallback keywordに使う。
6. `sync_lessons.sh` 非blockingの条件をrequirements化し、cmd_complete_gate側でsync欠落を検知する。
7. `codd.yaml` のsource scanning設定を見直し、bash scriptsがtracked sourceとしてmeasure/extractに反映されるようにする。

## Binary Checks

| AC | Check | Result |
|---|---|---|
| AC1 | `lesson_write.sh` を読み、spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
