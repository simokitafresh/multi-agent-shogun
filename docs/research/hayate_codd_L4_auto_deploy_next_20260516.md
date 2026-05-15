# CoDD修行L4: auto_deploy_next.sh 設計書品質検証

- 実施者: hayate
- 対象: `scripts/auto_deploy_next.sh`
- 実施日: 2026-05-16
- task_id: `cmd_training_L4_codd_c3_hayate`
- CoDD version: 2.18.0

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/auto_deploy_next.sh` は、あるsubtask完了後に同じ親cmdの次subtaskを自動判定し、条件を満たす場合に忍者へ配備する。`ninja_monitor.sh` が報告YAML gate PASS後に30秒timeoutで呼び出す。

| 入力 | 契約 |
|---|---|
| `cmd_id` | `cmd_*` 形式の親cmd ID |
| `completed_subtask_id` | 完了済みsubtaskの `task_id` |
| `queue/tasks/*.yaml` | 親cmd一致subtask、status、blocked_by、auto_deploy、assigned_toを取得 |
| `queue/reports/*.yaml` | 完了忍者の報告存在・statusを非blocking確認 |
| `logs/ninja_states.yaml` | idle忍者とctx_pctを取得 |
| `config/settings.yaml` | ninja一覧とround-robin順序を取得 |
| tmux pane options | 完了忍者のcontext_pct取得 |

### 出力とexit

| exit | 出力 | 意味 |
|---:|---|---|
| 0 | `AUTO_DEPLOY_OK` / `AUTO_DEPLOY_DONE` | 次subtask配備成功、または全subtask完了 |
| 1 | `ERROR` | 入力不正、解析失敗、YAML書込み失敗、deploy_task失敗 |
| 2 | `AUTO_DEPLOY_SKIP` | 次subtaskの `auto_deploy=false`。家老判断待ち |
| 3 | `AUTO_DEPLOY_BLOCKED` | blocked_by未解消、全忍者busy、二重配備lock |

### 主要フロー

1. 引数を検証し、`/tmp/auto_deploy_<cmd_id>.lock` を `flock -n` で取得する。
2. Pythonで `queue/tasks/*.yaml` をscanし、親cmd一致subtaskを収集する。
3. `task_id` 重複をstatus rankでdedupし、completed subtaskが `done` であることを検証する。
4. 完了忍者の報告YAMLを非blockingで確認する。
5. undone subtaskから `blocked_by` が全てdone済みの最初のtaskを選ぶ。
6. `auto_deploy=false` ならexit 2。
7. 事前assignedがあればそれを採用し、なければ完了忍者CTX<50、次に `ninja_states.yaml` idle+CTX<50をround-robin順で選ぶ。
8. 選定忍者のtask YAMLへsource taskをcopyし、`assigned_to` と `status=assigned` を `yaml_field_set.sh` で更新する。
9. source fileとtarget fileが異なる場合、target内容をsourceへ戻してstale duplicateを防ぐ。
10. `deploy_task.sh <ninja>` を呼び、家老へinbox通知する。

### 制約

- `yaml.dump` は使わず、書込みはcopy + `yaml_field_set.sh`。
- 全忍者busy時は家老へ `inbox_write.sh` で手動配備要請する。
- 報告YAML確認はWARNのみで、auto_deployのblock条件ではない。
- 完了忍者のCTXが50%以上なら連続配備しない。
- `deploy_task.sh` 失敗はexit 1と家老通知。
- `assigned_to` が既にあるtaskは、その指定を尊重する。

### 対象範囲外

- subtask群の生成。
- 報告YAML gateそのもの。
- ninja状態ファイルの生成。
- deploy_task.sh内部の配備品質保証。

## AC2: elicit/lexicon観点の要件穴・coverage軸

### CoDD/lexicon実行結果

| コマンド | 結果 | 解釈 |
|---|---|---|
| `codd lexicon list --all --path .` | installed: `shogun_core` 1件、3 axes | lexicon自体は認識されている |
| `codd coverage report --path . --format md` | `Totals: 0 axes, 0 covered signals (0.00%)` | installed lexiconの3 axesがcoverage matrixへ反映されていない |
| `codd elicit --format md --path . --lexicon shogun_core` | `LexiconLoadError: manifest missing required string field 'prompt_extension'` | `shogun_core` はelicit用manifestとして壊れている |
| `codd brownfield scripts/auto_deploy_next.sh ...` | `Directory ... is a file` | brownfieldはファイル単体を対象にできない |
| `codd extract --path . --language bash --source-dirs scripts ...` | `Extracted: 0 modules from 0 files` | 現行設定ではbash scriptsを実質抽出できていない |

### Coverage軸

| 軸 | 評価 | 根拠 |
|---|---|---|
| 状態遷移安全性 | 中 | blocked_by、done検証、auto_deploy flag、lockはある |
| 配備先選定 | 中 | pre-assigned優先、完了忍者継続、idle round-robinの3段階 |
| 競合防止 | 中 | cmd単位lockとtarget YAML flockあり。ただしsource task copy-backは別lockなし |
| 報告整合 | 低 | report verificationはWARNのみで、報告欠落でも進む |
| テスト網羅 | 低 | `auto_deploy_next.sh` 専用Batsが見当たらない |
| 障害可視性 | 中 | exit codeとlogはあるが、Python解析結果のTAB契約が暗黙 |
| YAML形式耐性 | 中 | yaml.safe_load読取 + yaml_field_set書込。ただしtask schema揺れの契約は不足 |

### 要件穴

| ID | severity | 穴 | リスク |
|---|---|---|---|
| GAP-1 | HIGH | 専用回帰テストがない | blocked_by、auto_deploy=false、all busy、pre-assigned、duplicate task_idなどの安全弁が退化しても検知しづらい |
| GAP-2 | HIGH | report verificationが非blockingでよい条件が仕様化されていない | 報告欠落・status不一致でも次subtask配備が進み、未レビュー成果を前提に後続が動く可能性 |
| GAP-3 | MEDIUM | source taskへのcopy-backがtarget lock内のみで、source側lockを取らない | source/targetが異なる場合、別プロセスがsourceを読む/書く競合余地がある |
| GAP-4 | MEDIUM | `STATUS_RANK` に `completed/success/failed` がない | 完了扱いの語彙が他スクリプトとずれ、dedupで古いstatusが勝つ可能性 |
| GAP-5 | MEDIUM | TAB区切り `ANALYSIS` 出力契約がテストされていない | task_idやfile pathに想定外文字が入るとshell側parseが壊れる |
| GAP-6 | LOW | lock file pathがcmd_id直結で、古いlock fileの掃除方針が別スクリプト依存 | lock蓄積や権限異常時の診断が分散する |

## AC3: validate/measure品質採点と改善点

### CoDD実行結果

| コマンド | 結果 |
|---|---|
| `codd validate --path .` | `OK: validated 16 Markdown files under configured doc_dirs` |
| `codd measure --path . --json` | `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16` |
| `codd coverage report --path . --format md` | 0 axes。coverage設定またはlexicon manifest側に穴 |
| `codd elicit --format md --path . --lexicon shogun_core` | `prompt_extension` 欠落で失敗 |
| `codd brownfield scripts/auto_deploy_next.sh ...` | ファイル単体を拒否 |
| `codd extract --path . --language bash --source-dirs scripts ...` | `0 modules from 0 files` |

### 手動採点

| 観点 | 点 | 根拠 |
|---|---:|---|
| 目的明確性 | 8 | ヘッダーとexit codeが明確 |
| 入出力契約 | 6 | 引数/exitは明確だがtask/report schema契約が分散 |
| 状態遷移安全性 | 7 | blocked_byとauto_deploy flagはある |
| 配備先選定 | 7 | CTX/idle/round-robinを使うが、pre-assignedの妥当性検証は薄い |
| 排他/原子性 | 6 | cmd lockとtarget YAML flockあり。source copy-backが弱い |
| エラー可視性 | 7 | exit codeとlogがある |
| テスト容易性 | 4 | 専用Bats不在。deploy_task/tmux/ninja_states依存が重い |
| 保守性 | 6 | 405行で責務は絞られているがPython heredocとshell parseが結合している |
| 総合 | 6.4/10 | 中核安全弁はあるが、報告整合とテスト網羅が不足 |

### 改善点

1. 専用Batsを追加し、少なくとも `ALL_DONE`、`BLOCKED`、`SKIP`、`DEPLOY pre-assigned`、`all busy` をfixture化する。
   - 対応GAP: GAP-1
   - 期待効果: 自動配備の安全弁退化を早期検出する。

2. report verificationをblockingにする条件を明文化する。
   - 対応GAP: GAP-2
   - 例: parent_cmd一致 + status completed/done/success + gate_report_format PASS済みでなければ後続配備しない、またはninja_monitor側のgate PASSを唯一の前提とする。

3. source task copy-backの排他を再設計する。
   - 対応GAP: GAP-3
   - 期待効果: source/target二重YAML更新時のlost updateを防ぐ。

4. status語彙を共通ヘルパー化する。
   - 対応GAP: GAP-4
   - 期待効果: `done/completed/success/failed` の扱いをdeploy/monitor/archive/reportで揃える。

5. Python解析結果をTAB文字列でなくJSONで返す。
   - 対応GAP: GAP-5
   - 期待効果: shell `cut -f` 依存を減らし、フィールド増減に強くする。

6. lock cleanup契約をこのscriptのspecにも記載する。
   - 対応GAP: GAP-6
   - 期待効果: `/tmp/auto_deploy_*.lock` 蓄積や権限異常の診断先を明確化する。

## CoDD側の発見

- `shogun_core` はinstalled扱いだが、`elicit` では `prompt_extension` 欠落でロードできない。
- `coverage report` は0 axesとなり、installed lexiconの3 axesがcoverage matrixへ入っていない。
- `brownfield` はファイル単体を拒否するため、bash単体スクリプトのbrownfield評価には使いづらい。
- `extract` はbash scriptsに対して `0 modules from 0 files` となり、現行設定では対象抽出の入口として機能しない。

## 結論

`auto_deploy_next.sh` は自動配備の中核として、cmd lock、blocked_by、auto_deploy flag、CTX閾値、round-robinを備えている。一方で専用テストが見当たらず、報告整合がWARN止まりで、解析結果のTAB契約も脆い。次改善は専用Batsとreport verificationのblocking条件整理が最優先である。
