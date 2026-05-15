# CoDD修行R3: semantic_index_update.sh 設計書品質検証

- 実施者: saizo
- 対象: `scripts/semantic_index_update.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_codd_r3_saizo`
- CoDD version: 2.18.0
- pipeline: spec -> elicit/lexicon -> generate/extract -> validate -> measure

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/semantic_index_update.sh` は、cmd完了・教訓・議論などの既知イベントを `docs/semantic-index/index.md` の概念へ紐付け、HIGH/LOW/NONE の信頼度に応じて index row追加、alias拡張、または insight候補化を行うセマンティック索引更新スクリプトである。indexが変わった場合のみ `scripts/semantic_map_generate.sh` を実行し、`context/semantic-map.md` を再生成する。

### 入力契約

| 入力 | 契約 |
|---|---|
| `source_type` | `cmd_complete`, `lesson`, `discussion` のいずれか |
| `payload_json` | source_type別のJSON payload。invalid JSONはexit 2 |
| `SEMANTIC_INDEX_PATH` | 任意。未指定時は `docs/semantic-index/index.md` |
| `SEMANTIC_MAP_GENERATE` | 任意。未指定時は `scripts/semantic_map_generate.sh` |
| `SEMANTIC_INSIGHT_WRITE` | 任意。未指定時は `scripts/insight_write.sh` |
| `SEMANTIC_INDEX_LOCK` | 任意。未指定時はindex file lock |

### 出力契約

| 出力 | 契約 |
|---|---|
| `docs/semantic-index/index.md` | HIGHならresource row追加、LOWならalias候補とrow追加 |
| `context/semantic-map.md` | index_changed sentinel検出時のみ再生成 |
| insight | NONEかつnoise-onlyでないpayloadは新概念候補として `insight_write.sh` へ送る |
| stdout/stderr | HIGH/LOW/NONE判定、dedup、map再生成結果、エラーを表示 |

### 主要フロー

1. CLI引数と `source_type` を検証する。
2. `flock -w 10` で semantic index 更新と map再生成を直列化する。
3. Python heredoc内でJSONをparseし、index markdownから概念blockとaliasesを抽出する。
4. payload内テキストをflattenし、alias exact/partial matchで概念scoreを計算する。
5. HIGHなら既存concept blockへresource rowを追加する。
6. LOWなら候補aliasを追加し、resource rowも追加する。
7. NONEならnoise-only/dedupを確認し、新概念候補insightを起票する。
8. Python出力の `__SEMANTIC_INDEX_CHANGED__` sentinelをbash while-readで除去・検出する。
9. indexが変更された場合のみ `bash "$map_generate"` を実行する。

### 制約

- source_typeは3種だけ。未知値はexit 2。
- index fileが存在しなければexit 1。
- semantic map generatorは実行権限なしでも動くよう `bash "$map_generate"` を維持する。
- sentinel処理は外部grepを使わずbash loopで1-pass処理する。
- NONE候補でもnoise-onlyならinsight化しない。
- pending insightに同じpayload labelがあればdedupする。
- HTML/XML風tagと長すぎるdiscussion summaryはresource row生成時に縮約する。

### 対象範囲外

- 概念taxonomyそのものの設計・レビュー。
- LLMによる概念候補の採否判断。
- `semantic_map_generate.sh` の内部品質保証。
- insight backlogの解決運用。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexicon自体は認識されている |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals | coverage matrixにlexicon axesが出ていない |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 | elicitは現状使えないため手動穴出しが必要 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_semantic_index_update_codd_extract_20260516` | 0 modules from 0 files | bash script抽出が実質機能していない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| CLI入力検証 | 高 | source_type whitelist、JSON parse、index existenceを検証 |
| 概念match | 中 | exact/partial alias scoreあり。aliasの重みは単純 |
| HIGH/LOW/NONE分岐 | 高 | row追加、alias拡張、insight起票を分離 |
| noise/dedup | 中 | ID・日時・cmd等のnoise除去、pending insight重複検知あり |
| 排他/原子性 | 中 | index更新とmap再生成は同一flock内。ただしinsight_writeはPython subprocess |
| sentinel処理 | 高 | grepを使わずbash loopで除去・検出 |
| map再生成 | 中 | index_changed時だけ実行。generator失敗時の復旧契約は薄い |
| テスト網羅 | 中 | `test_semantic_index_update` と `test_cmd_save_semantic_index` 合計12件PASS |
| CoDD可視性 | 低 | codd source coverage 0、extract 0 modules。既存CoDD設計はsentinel改善中心 |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | 現行全体仕様のCoDD requirement/design nodeがない | 2026-05-06の既存CoDD設計はsentinel処理改善中心で、HIGH/LOW/NONE全契約はDAG化されていない |
| GAP-2 | HIGH | alias matchの品質指標が不足 | LOWで追加したaliasがノイズを増やしても定量検知しづらい |
| GAP-3 | MEDIUM | map再生成失敗時の復旧契約が弱い | indexは更新済みだがsemantic-mapが古い状態で残りうる |
| GAP-4 | MEDIUM | insight_write失敗時はPython returncodeで失敗するが、index更新との組合せ契約が薄い | NONE候補処理の途中失敗が運用上どう再実行されるか不明 |
| GAP-5 | MEDIUM | index markdown parserがtable形式に強く依存 | format変更で概念抽出・alias抽出が静かに崩れる可能性 |
| GAP-6 | MEDIUM | source_type別payload schemaがusage文字列だけにある | cmd_complete/lesson/discussionの必須・任意fieldが設計書化されていない |
| GAP-7 | LOW | `summary[:120]` の切り詰め根拠が薄い | 重要語が末尾にあるdiscussionでsemantic signalが落ちる |
| GAP-8 | LOW | pending insight dedupはpayload_label部分一致 | 同一IDを含む別文脈を誤dedupする可能性 |

Recommended lexicon axes:

- `semantic_payload_schema`: source_type別payload schemaと必須field。
- `semantic_match_quality`: HIGH/LOW/NONE判定の品質・false positive管理。
- `semantic_alias_hygiene`: LOWで追加するaliasのノイズ抑制。
- `semantic_index_map_consistency`: index変更とsemantic-map再生成の整合性。
- `semantic_insight_dedup`: NONE候補のinsight重複判定。
- `semantic_markdown_parser_contract`: index markdown formatへの依存契約。

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `bash -n scripts/semantic_index_update.sh` | PASS |
| `bats tests/unit/test_semantic_index_update.bats tests/unit/test_cmd_save_semantic_index.bats` | PASS: 12/12, SKIP 0 |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_semantic_index_update_codd_extract_20260516` | 0 modules from 0 files |

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 8 | semantic index更新、map再生成、insight候補化の責務が明確 |
| 入力契約 | 7 | source_type/JSON/index存在は検証。payload schemaはusage中心 |
| 排他/原子性 | 7 | index更新とmap再生成はflock内。外部insight/map副作用の復旧設計は薄い |
| match品質管理 | 5 | exact/partial ruleはあるがprecision/recall評価軸がない |
| noise/dedup | 6 | noise-only skipとpending insight dedupあり。ただし部分一致dedup |
| テスト網羅 | 7 | HIGH/LOW/NONE、map生成、wiring、alias境界をテスト |
| CoDD可視性 | 4 | 既存CoDD設計あり。ただしsource coverage 0で全体仕様nodeは不足 |
| 保守性 | 6 | Python heredocに責務集中。index markdown format依存が強い |
| 総合 | 6.3/10 | 動作テストはあるが、match品質とindex-map整合の運用契約が弱い |

### 改善点

1. `codd/requirements/semantic_index_update_requirements.md` と `codd/design/semantic_index_update_design.md` を追加し、HIGH/LOW/NONE、payload schema、map再生成、insight dedupをDAG化する。
2. alias追加の品質指標を追加する。例: LOWで追加されたaliasの後続match率、誤match撤回数、insight解決率。
3. index更新後にmap再生成が失敗した場合の復旧flagを設ける。例: `queue/gates/semantic_index/map_regen_failed` またはWARN insight。
4. source_type別payload schemaをJSON Schema相当で文書化し、必須field不足を明示WARNする。
5. index markdown parserのfixtureを増やし、table行順序変更、aliases空欄、重複concept IDを検証する。
6. insight dedupをpayload_label部分一致から `source_type + payload_id + normalized summary hash` へ強化する。
7. `summary[:120]` の切り詰めを語境界・重要語優先にするか、切り詰め前後のsignal lossをテストする。

## Binary Checks

| AC | Check | Result |
|---|---|---|
| AC1 | `semantic_index_update.sh` を読み、codd spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
