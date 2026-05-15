# CoDD修行R2: karo_workaround_log.sh 設計書品質検証

- 実施者: saizo
- 対象: `scripts/karo_workaround_log.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_codd_r2_saizo`
- CoDD version: 2.18.0
- pipeline: spec -> elicit/lexicon -> generate/extract -> validate -> measure

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/karo_workaround_log.sh` は、家老が行った手動補正/消火/clean確認を `logs/karo_workarounds.yaml` に排他付きで記録し、同一カテゴリの蓄積をWARN/ALERT/insight/pending decisionへ接続する運用学習ループの入口スクリプトである。

### 入力契約

| mode | 入力 | 契約 |
|---|---|---|
| normal | `<cmd_id> <ninja_name> <issue> <fix> [category] [missed_sg]` | WAを記録。category省略時はissueから分類 |
| `--wa` | `<cmd_id> <ninja_name> <issue> <fix> [category] [missed_sg] [environment_change]` | environment_change必須。構造化形式とgrep検証を要求 |
| `--clean` | `<cmd_id> <ninja_name>` | workaround=false/category=cleanを記録 |
| `--reclassify` | `<cmd_id_pattern> <new_category>` | 既存entryのcategoryを置換 |
| `--normalize` | なし | legacy `cmd:` keyを `cmd_id:` に正規化 |

### 出力契約

| 出力 | 契約 |
|---|---|
| `logs/karo_workarounds.yaml` | flat list形式で `cmd_id/timestamp/ninja/workaround/category/detail/root_cause/resolved_by_cmd` をappend |
| stdout/stderr | validation WARN、category蓄積WARN/ALERT、environment_change検証結果を表示 |
| `ntfy.sh` | 同一category 3件以上で家老ALERTを通知 |
| `insight_write.sh` | 同一category 3件以上を高優先度insight化 |
| `pending_decision_write.sh` | 構造対策cmd起票/裁定を促すPDを作成 |

### 主要フロー

1. modeを判定し、引数数と必須値を検証する。
2. `--wa` では `environment_change` を `type=...; file=...; pattern=...` としてparseし、対象fileをgrepで検証する。
3. `cmd_id` と `ninja_name` が逆順なら自動swapする。
4. `validate_ninja_id` で `config/settings.yaml` のagentsに存在するかWARNする。
5. issueからcategoryを自動分類し、明示categoryがあれば優先する。
6. root_cause/fixの空・null・短すぎをWARNする。
7. `flock` 内でlog fileを初期化し、cleanまたはWA entryをappendする。
8. 同一categoryのresolved未済WA件数を数え、2件目WARN、3件目以上ALERT/ntfy/insight/PDを発火する。

### 制約

- log更新は `flock -w 10` で行う。
- 運用YAMLは既存形式を壊さず、flat list形式にappendする。
- `--wa` は「消火を環境に埋め込んだ証拠」を必須化し、非構造・未実装ならBLOCKする。
- category=cleanをnormal modeで書いた場合はWARNし、clean記録は `--clean` modeを正とする。
- alert副作用は `KARO_WORKAROUND_DISABLE_ALERTS=true` でテスト/計測時に抑止できる。
- resolved_by_cmdがあるentryはcategory蓄積カウントから除外する。

### 対象範囲外

- 家老が実際に構造対策cmdを設計・配備する判断。
- `ntfy.sh`, `insight_write.sh`, `pending_decision_write.sh` の内部成功保証。
- `logs/karo_workarounds.yaml` の長期ローテーション/圧縮。
- WA分類taxonomy全体の設計。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexicon自体は認識されている |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals | coverage matrixにlexicon axesが出ていない |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 | elicitは現状使えないため手動穴出しが必要 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_karo_workaround_log_codd_extract_20260516` | 0 modules from 0 files | bash script抽出が実質機能していない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| mode別入力検証 | 高 | normal/wa/clean/reclassify/normalizeのusage検証あり |
| environment_change強制 | 高 | `--wa` で構造化形式とgrep実在をBLOCK検証 |
| WA分類 | 中 | report_yaml_format/file_disappearance/commit_missing等は分類。未知はuncategorized WARN |
| ninja_id検証 | 中 | settings.yaml agentsを権威にWARN。invalidでも記録は継続 |
| alert接続 | 中 | 2件WARN、3件ALERT/ntfy/insight/PDあり。ただし副作用失敗は握る |
| resolved除外 | 中 | resolved_by_cmdありをcategory countから除外 |
| YAML安全性 | 中 | single quote escapeあり。値はsingle-quotedだがcategory/cmd/ninjaは裸値 |
| 既存形式互換 | 中 | category-first legacy entry、cmd key normalize、reclassify対応 |
| テスト網羅 | 高 | category/validation Bats 37件PASS、SKIP 0 |
| CoDD可視性 | 低 | codd source coverage 0、extract 0 modules、専用nodeなし |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | 現行 `karo_workaround_log.sh` 専用のCoDD requirement/design nodeがない | WA記録からPD起票までの運用契約がDAGで追跡されない |
| GAP-2 | HIGH | alert副作用の失敗を `|| true` で握る条件が設計書化されていない | ntfy/insight/PDが失敗してもlogだけ成功し、構造対策への接続が切れる |
| GAP-3 | MEDIUM | `ninja_id` invalidはWARNのみ | typoのままWA記録され、忍者別WA率や統計を汚す可能性 |
| GAP-4 | MEDIUM | category taxonomyがshell regex直書き | 新しいWA型が増えるたびに分類漏れがuncategorizedへ流れる |
| GAP-5 | MEDIUM | environment_changeのgrep patternは正規表現として実行される | patternのescapeや過剰matchで未実装を誤検知する余地 |
| GAP-6 | MEDIUM | log file肥大化時のcount_category_entriesは毎回全量scan | WA蓄積が増えるほど記録コストが増える |
| GAP-7 | LOW | category/cmd_id/ninja_nameのYAML scalar escapeはdetail/root_causeより弱い | 特殊文字を含む明示category等でYAML破損リスクが残る |
| GAP-8 | LOW | cleanとWAの意味論が同一logに混在 | downstream集計がworkaround=true/falseを見落とすとcleanがノイズになる |

Recommended lexicon axes:

- `workaround_environment_change_evidence`: WA記録時に環境埋込み証拠を検証する。
- `workaround_alert_delivery_contract`: ALERT副作用失敗時の扱いを定義する。
- `workaround_category_taxonomy`: category分類規則と未分類処理の契約。
- `workaround_agent_identity_integrity`: ninja_id typoを統計汚染させない。
- `workaround_resolved_exclusion`: resolved_by_cmd済みentryを再発件数から除外する。
- `workaround_log_yaml_integrity`: flat list YAMLを壊さず追記・再分類・正規化する。

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `bash -n scripts/karo_workaround_log.sh` | PASS |
| `bats tests/unit/test_karo_workaround_category.bats tests/unit/test_karo_workaround_validation.bats` | PASS: 37/37, SKIP 0 |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: 16 Markdown files |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4 |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS。`depends_on_consistency` は propagation output未生成でskip警告 |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md` | 0 axes / 0 covered signals |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL: `prompt_extension` 欠落 |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/saizo_karo_workaround_log_codd_extract_20260516` | 0 modules from 0 files |

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 8 | usageとmodeが冒頭に明記され、WA学習ループの入口として明確 |
| 入力契約 | 8 | mode別引数検証とenvironment_change BLOCKがある |
| 排他/原子性 | 7 | append/reclassify/normalizeはflockあり。alert副作用は別境界 |
| 学習ループ接続 | 7 | 2件WARN、3件ALERT/ntfy/insight/PDで構造対策へ接続 |
| 統計品質 | 6 | resolved除外はあるがinvalid ninja/category clean misuseはWARN継続 |
| テスト網羅 | 8 | 専用Bats 37件PASS。category-first legacyなども覆う |
| CoDD可視性 | 3 | source coverage 0、extract 0 modules、専用nodeなし |
| 保守性 | 6 | shell regex分類と複数mode同居で増改築時の影響範囲が広い |
| 総合 | 6.6/10 | 実運用の防御は厚いが、CoDD DAG化と副作用失敗契約が弱い |

### 改善点

1. `codd/requirements/karo_workaround_log_requirements.md` と `codd/design/karo_workaround_log_design.md` を追加し、WA記録、clean、reclassify、normalize、alert副作用をDAG化する。
2. alert副作用のdelivery contractを定義する。ntfy/insight/PDのどれを必須・WARN・非blockingにするかを明記し、必要なら失敗flagをlogへ残す。
3. invalid ninja_idをWARN継続にする条件を設計書化するか、統計汚染を防ぐため `ninja: unknown` + `original_ninja` へ分離する。
4. category taxonomyを設定ファイルまたは専用テーブルへ分離し、分類規則とテストfixtureを同時更新できる形にする。
5. environment_change pattern検証をliteral grep optionまたは明示regex modeに分け、escapeミスと過剰matchを減らす。
6. log肥大化に備え、category countを直近N件または集計cacheにする。ただしL507のcacheミス教訓に従い、本番フローでのcache invalidation条件を先に設計する。
7. 明示category/cmd_id/ninja_nameにもYAML scalar validationを追加し、特殊文字で運用YAMLを壊さないようにする。

## Binary Checks

| AC | Check | Result |
|---|---|---|
| AC1 | `karo_workaround_log.sh` を読み、codd spec相当の目的・制約・対象範囲を本ファイルに記録した | yes |
| AC2 | elicit/lexicon観点で要件穴とcoverage軸を洗い出した | yes |
| AC3 | validate/measureを実行し、設計書品質採点と改善点3件以上を記録した | yes |
