# cmd_training_L4_codd_c4_kagemaru: chronicle_metrics.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/chronicle_metrics.sh`
pipeline: spec -> elicit/lexicon -> validate -> measure

## 1. Spec

### Purpose

`scripts/chronicle_metrics.sh` は、`context/cmd-chronicle.md` と `archive/cmd-chronicle/*.md` を読み、cmd完了履歴の直近件数、project分布、type分布をMarkdown tableで出力するメトリクス補助スクリプトである。cmd完了量と内訳を一次chronicleから集計し、dashboardや棚卸しの判断材料にする。

### Scope

- `context/cmd-chronicle.md` の存在を確認し、不在なら非0終了する。
- archive chronicleを年月順に読み、最後に現行chronicleを読む。
- ファイル名または `## YYYY-MM` 見出しから年を推定し、`| cmd_... |` 行だけを対象にする。
- 行内の `MM-DD` cellを基準に、直前cellをproject、前方cell群をtitle、後方cell群をkey_resultとして抽出する。
- title/key_resultから `review` / `recon` / `impl` / `other` を正規表現で推定する。
- invalid dateやmalformed rowはstderr WARNINGにし、year context欠落はERRORとして停止する。
- all-timeとlast 30 daysのproject/type分布、last 7/30 daysの完了件数とavg/dayを出力する。

### Non-scope

- chronicleへの書込み・trim・archive移動は `scripts/archive_completed.sh` の責務。
- context鮮度やproject判定の運用判断は `context_freshness_check.sh` などの責務。
- type分類は簡易ヒューリスティックであり、cmd正本のtask_typeやreview結果を参照しない。
- 本taskでは実装変更を行わず、CoDD L4修行としてspec/要件穴/品質評価のみ記録する。

### Current Evidence

| Evidence | Result |
| --- | --- |
| `bash -n scripts/chronicle_metrics.sh` | PASS |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告。実行時間は約96秒 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals。lexicon coverage未設定 |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path .` | FAIL: installed `shogun_core` lexicon manifest lacks required `prompt_extension` |
| Existing CoDD docs | `chronicle_metrics.sh` 専用nodeは未検出 |

## 2. Elicit / Lexicon Findings

`codd elicit` はlexicon manifest不備で失敗したため、コード読解と関連スクリプト検索からCoDD elicit相当の穴を手動で列挙する。

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | `chronicle_metrics.sh` 専用のCoDD requirement/design nodeがない | `find codd ... chronicle` で未検出 | chronicle行schemaや分類規則がDAGで追跡されない |
| GAP-2 | chronicle row schemaが実装内の位置推定に依存している | `MM-DD` cellを探し、直前をproject扱い | 列追加・順序変更時に静かに誤分類しやすい |
| GAP-3 | type分類の正規表現が要求化されていない | review/recon/impl regexがコード内固定 | 日本語語彙追加時に分類FP/FNを評価できない |
| GAP-4 | archive file名から年推定する契約が弱い | `YEAR_RE.search(path.name)` | archive命名変更や複数年混在時の誤年推定リスク |
| GAP-5 | `date.today()` がローカルタイムゾーン依存 | Pythonのdate.today使用 | JST運用前提や日跨ぎ集計基準が明文化されていない |
| GAP-6 | malformed rowはWARNING継続だが品質閾値がない | WARNING出力のみ、exitは継続 | chronicle破損が多くてもメトリクスは成功扱いになる |
| GAP-7 | output table schemaが消費者契約として固定されていない | `print_table` の表題/列名のみ | dashboardや外部集計が依存している場合に壊れやすい |
| GAP-8 | all-time分布はarchive全量を読むため、データ増加時のruntime budgetがない | `archive_dir.glob("*.md")` +全read | chronicle肥大化時にstartup/dashboard補助で遅延する |
| GAP-9 | project欠損を `(missing)` へ畳むが、欠損率の警告がない | `normalize_project` | chronicle schema劣化を見逃す |
| GAP-10 | CoDD graph上のsource coverageが0 | `measure` tracked_files/source_files=0 | scripts/chronicle_metrics.sh自体の実装coverageが数値上見えていない |

Recommended lexicon axes for this script:

- `chronicle_row_schema_contract`: `cmd_id/title/project/MM-DD/key_result` の列位置と許容変化を定義する。
- `chronicle_year_context`: archive名・month heading・row dateの年推定優先順位を定義する。
- `chronicle_type_taxonomy`: review/recon/impl/other分類語彙とFP/FN検証fixtureを持つ。
- `chronicle_metric_window_timezone`: last 7/30 daysの基準日とtimezoneを明記する。
- `chronicle_malformed_threshold`: malformed/invalid/missing projectの許容数とexit方針を定義する。
- `chronicle_runtime_budget`: archive全量読込の想定件数・実行時間・将来のcache/limit方針を定義する。

## 3. Validate / Measure Score

### CoDD Tool Score

| Metric | Score |
| --- | ---: |
| CoDD health_score | 95/100 |
| validation errors | 0 |
| validation warnings | 0 |
| DAG verify | PASS with skipped `depends_on_consistency` warning; runtime about 96s |
| graph nodes | 16 |
| graph edges | 12 |
| orphan nodes | 4 |
| lexicon coverage axes | 0 |

### Design Quality Score for `chronicle_metrics.sh`

Overall: 7/10.

Rationale:

- +2: 入力ファイル、archive、集計window、出力tableが小さくまとまり、単一責務が明確。
- +1: malformed row、invalid date、year context欠落を区別し、致命度を変えている。
- +1: project欠損やkey_result空欄を正規化し、集計を止めずに出力できる。
- +1: archiveと現行chronicleを同じparserで扱うため、履歴全体を一貫集計できる。
- +1: 出力はMarkdown tableで、dashboardや人間レビューに流用しやすい。
- +1: `bash -n` とCoDD validate/measureはPASS。
- -1: 専用CoDD文書がなく、chronicle row schemaが暗黙知。
- -1: type taxonomyとtimezone/window基準が要求化されていない。
- -1: malformed row継続、archive全量scan、source coverage=0の品質境界が弱い。

## 4. Improvement Candidates

1. `codd/requirements/chronicle_metrics_requirements.md` と `codd/design/chronicle_metrics_design.md` を追加し、chronicle row schema、year推定、出力table schemaをDAG化する。
2. type分類語彙を設計書またはfixtureに切り出し、review/recon/impl/otherの期待分類テストを追加する。
3. malformed row / invalid date / missing projectの許容閾値を決め、閾値超過時はnonzeroまたはWARN summaryを出す。
4. timezone/window基準を明記し、JST運用なら `TZ` や基準日注入テストを用意する。
5. archive全量scanのruntime budgetを記録し、件数増加時は期間指定やcacheを検討する。
6. `codd.yaml` のscan/source coverage設定を見直し、`scripts/chronicle_metrics.sh` がtracked sourceとしてmeasureに反映されるようにする。

## 5. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `chronicle_metrics.sh` を読み、spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
