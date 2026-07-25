# saizo速度調査(殿指示・利他調査) — cmd_karo_hotfix_gate_metrics_literal_tab_20260725の遅延要因

- 日付: 2026-07-25
- 発端: 殿より「今の自分の行動が遅かった理由をインフラバグ/スクリプト速度/構造的バグ/hook・gate品質の観点で覚醒調査し、家老に報告せよ」
- 対象: 直前に完了したcmd_karo_hotfix_gate_metrics_literal_tab_20260725_normal(issued 14:36:56→done 14:57:51、実測21分。estimated_minutes: 10の倍以上)

## 結論(優先度順)

### 1. 【本命・要修正】deploy_task.shのbinary_checks/memory_references事前充填が`awk -v`のエスケープ展開バグを持つ

**現象**: 本タスクの報告YAML自身が、AC descriptionからテンプレート自動生成された時点で生タブ(0x09)混入によりyaml.safe_load不能になり、`bash scripts/run_tests.sh task ...`が`BLOCK: single-flight selection could not be resolved`で停止した。手動でリテラル`\t`へ復元してから再実行する余分な作業が発生した(report記載: decision_candidate)。

**根本原因**: `scripts/deploy_task.sh`に、生成したテンプレート文字列をawkの`-v`オプションで注入してファイルへ書き込む箇所が3箇所ある。

```
scripts/deploy_task.sh:4272:  awk -v repl="$_lu_block" '...'
scripts/deploy_task.sh:4382:  awk -v repl="$_memory_references_block" '...'
scripts/deploy_task.sh:4838:  awk -v repl="$_bc_full" -v placeholder="$_bc_placeholder" '...'
```

POSIX awk仕様では `-v var=value` の value はCエスケープシーケンス(`\t`, `\n`, `\\`等)を**解釈する**。今回のAC1 description本文には`printf '%s\t%s\tBLOCK\t%s'`という、まさに正規のシェル書式例としてのリテラル`\t`(バックスラッシュ+t、2文字)が含まれていた。この文字列が`_bc_full`(AC descriptionから生成されたbinary_checksテンプレート)経由でawkの`-v repl=`に渡された瞬間、awkが`\t`を実タブ0x09へ変換してしまい、そのままreport YAMLへ書き込まれた。

**これは今回このタスクで修正したcmd_complete_gate.shのバグ(bashの二重引用符内では`\t`が展開されない)と対称的に同種の「シェル/awkのエスケープ展開挙動の理解不足」構造的バグである。** 発生源のツールが逆(bash→非展開/awk -v→展開)なだけで、`\t`を含む文字列を制御構文へ生渡ししてはいけないという同一パターンが2箇所で実際に踏まれていた。

**再現条件**: AC descriptionやcheck文言に、printf書式・正規表現・エスケープ表記など`\`+英字を含むタスクは全て同じ形で報告YAML生成時に壊れうる。シェルスクリプトのバグ修正系タスク(printf/sed/正規表現を仕様として書く)で高頻度に踏まれる可能性がある。

**推奨対応**: `awk -v repl=... '...'`パターンを、値をawkへ渡す前に`\`を`\\`へエスケープしてから渡す(例: `repl_escaped=${_bc_full//\\/\\\\}`)か、`-v`を使わず`ENVIRON`経由(`awk 'BEGIN{repl=ENVIRON["REPL"]}'`)に切り替える。`ENVIRON`経由ならCエスケープ解釈は発生しない。3箇所とも同じ修正パターンで塞げる。

### 2. commit_contract.planned_pathsの自動生成が「AC本文でのtest追加明示」を検知できていない

AC1が「bats fixtureで確認する」と明示しているにもかかわらず、deploy時に自動生成されたcommit_contract.planned_pathsには`scripts/cmd_complete_gate.sh`のみが入り、新規追加する`tests/unit/test_cmd_complete_gate.bats`が含まれていなかった。結果、`bash scripts/run_tests.sh declare-scope-expansion queue/tasks/saizo.yaml "<reason>" tests/unit/test_cmd_complete_gate.bats`という追加のスコープ拡張宣言手続きが必要になった。

AC descriptionに「bats fixture」「テスト追加」「新規test」等のキーワードが含まれる場合、対応するtestファイルパスをplanned_pathsへ自動推測・追加する余地がある(完全自動化は誤爆リスクがあるため、家老/軍師の設計判断が必要)。

### 3. test_cmd_complete_gate.bats肥大化(3988行/146テスト) — task-scoped実行でも108秒

実測(`logs/test_receipts/run_tests_20260725T055147_1596095.json`): `bash scripts/run_tests.sh task queue/tasks/saizo.yaml`が対象を1ファイル(`tests/unit/test_cmd_complete_gate.bats`, 146テスト)に正しく絞り込んだ上で、実行だけで`duration_ms: 108398`(108秒)かかっている。1テストあたり平均742ms。これはタスク全体21分のうち約9%を占める。

batsは1テストごとに新規bashプロセスをforkするため、大きい1ファイルに146テストが集中していること自体がオーバーヘッドの主要因と見られる(cProfile的な内訳計測は未実施、家老/軍師判断でCoDD速度修行レーンへの合流を検討する価値あり)。

### 4. 既存test markerの非一意性による偶発的副作用

'BLOCK\t%s'という短い部分文字列をmarkerとして使っていた既存test「cmd_complete_gate appends first gate model profile metrics to gate_metrics rows」が、今回5箇所へ同じ部分文字列を追加した副作用で非一意化し、`script.index()`が意図しない箇所(9502行ではなく先に出現する6258行)にマッチしてFAILした。marker文字列をより長く一意な形('BLOCK\t%s\t%s\t%s')へ拡張して解消したが、これは「短い部分文字列markerに依存するtest設計」自体が変更に対して脆いことを示す一例。同種markerが他のbatsファイルにも存在する可能性がある。

### 5. (事実共有・対応不要) three_layer_preflight.shのUserPromptSubmit毎オーバーヘッド

実測: `bash scripts/hooks/three_layer_preflight.sh issue "..."` は cache温状態で約2.2秒。cold cache時は`THREE_LAYER_COLD_CACHE_BUDGET_MS`(6500ms)まで許容される設計。これは殿厳命(2026-06-10「三層記憶を使用しないのはバグ」)に基づく意図的な構造型防御であり削除対象ではないが、忍者のように短時間で多くのターンをこなすロールでは累積コストとして無視できない。「品質を保ったまま超速化せよ」(殿裁定2026-07-21)の対象候補として事実のみ共有する。

## 数値サマリ

| 要因 | 実測コスト | 種別 |
|---|---|---|
| binary_checks/memory_references awk -v生タブ混入→BLOCK→手動復元 | タスク中断1回+復元作業(時間未計測、report記載あり) | インフラバグ(要修正) |
| commit_contract.planned_paths漏れ→scope-expansion追加手続き | 追加コマンド1回分 | インフラ改善余地 |
| test_cmd_complete_gate.bats実行 | 108.4秒(146件) | スクリプト速度課題 |
| 既存test marker非一意化による予期しないFAIL修正 | 追加調査+修正1回分 | test設計品質課題 |
| three_layer_preflight (UserPromptSubmit毎) | 約2.2秒/回(cache温) | 構造型防御(意図的、事実共有のみ) |

## 提案(実装はスコープ外。家老/軍師の判断へ)

- deploy_task.sh L4272/4382/4838の`awk -v repl=...`をENVIRON経由または事前`\\`エスケープへ変更(3箇所同型修正、恒久バグ潰し)
- commit_contract.planned_paths自動生成にAC description内「bats/test追加」キーワード検知を追加検討
- test_cmd_complete_gate.batsの分割検討(146テスト/3988行は速度修行レーン対象候補)
