---
name: codd-refactor
description: |
  CoDDパイプラインでbashスクリプトの設計書を生成し、リファクタリング+速度改善を実行するスキル。
  プロファイリング→ボトルネック特定→CoDD spec作成→設計書生成→実装→before/after計測の全工程。
  TRIGGER: /codd-refactor、リファクタリング設計、速度改善、テスト高速化、batch化設計、CoDD設計書からリファクタ
  DO NOT TRIGGER: テスト実行のみ(bats直接実行)、
  新規スクリプト作成(CoDDは既存コードのリファクタ向き)、DM-Signal Python(別ワークフロー)
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

<!-- script_refs_checked_at: 2026-07-29T20:15:22+09:00 -->
<!-- 2026-07-29検分: run_tests.sh b3a8be4a4..f762b84c1の全45 commitをgit log/showで一次確認。task mode、durable receipt/identity、失敗exitのfail-closed化を追加。task modeは明示test_path/report files_modifiedのtestだけを直接実行し、推論planned_paths/files_to_modifyは所有境界としてproduction pathの依存選択にのみ使う。 -->
<!-- script_refs_checked_at: 2026-07-19T02:13:00+09:00 -->
<!-- 2026-07-19 GA-298修正後再検分: 直前検分2026-07-19T01:26:00+09:00以降のrun_tests.sh commitは0件（最新b3a8be4a4、2026-07-19T00:17:38+09:00）。現HEAD同期でmtimeのみ進んだため、公開mode/receipt/all cache/aggregate再入/失敗exit/14列台帳の契約変更なし。 -->
<!-- script_refs_checked_at: 2026-07-19T01:26:00+09:00 -->
<!-- 2026-07-19 cmd_karo_hotfix_skill_refs_codd_refactor_202607190121検分: run_tests.sh 108451a3f..b3a8be4a4の全7差分をgit log/showで確認。公開実行は耐久receiptを生成・検証し、allは明示指定なしならcacheを無効化、集約runnerの再入はexit 2でBLOCKして子実行をfile modeへ限定する。公開mode引数(all/unit/affected/file)、test選択、失敗exit、14列台帳契約は維持され、Phase 1/5の通常runner再利用・専用計測run禁止方針に本文変更は不要。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: run_tests.sh ad583f31はparallel cooperative fail-fast化。mode/選択は不変、失敗後の未投入queueを閉じ、投入済みlightのみ完走する。 -->
<!-- script_refs_checked_at: 2026-07-17T09:45:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: run_tests.sh f24b0747bはcached queue枯渇時処理、test_select.sh 68bda0869/fa403eb51はreport contract selector共通化。mode引数・test選択・終了status契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T19:17:45+0900 -->
<!-- 2026-07-16再検分: run_tests.sh 71ce264b0。file別timingに加えsuite wall/sum_file_secをtest_suite_timing_ledger.tsvへ記録する副作用を追加。mode引数・test選択・終了status契約は不変。 -->
<!-- cmd_karo_hotfix_shogun_startup_four_blocks検分: run_tests.shの現行差分はstateful Bats 5本のfile-isolated scheduling追加、test_select.shは.githooks明示mapping追加。mode/exit/計測契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T19:17:45+0900 -->
<!-- GA-263後検分: run_tests.sh 8a80ad7fc/4850af9a9をgit showと83回帰で確認。source時のrepo rootはBASH_SOURCE基準、affected/fullはfile単位aggregate budget=8・file内部jobs=1へ統一。mode引数・exit契約・14列台帳契約は不変。 -->
<!-- cmd_karo_hotfix_skill_refs_202607151824検分: run_tests.sh 275d22bafをgit showで確認。LPT cohort空時にも対象fileをscheduleするCI内部配分修正で、run_tests.shの引数・exit・実行対象副作用契約は不変。 -->
<!-- 2026-07-15将軍検分: run_tests.sh b0c6112a9(INNER_JOBS 4→1+HEAVY_INNER_JOBS fallback=CI concurrency fix)。内部並列度調整のみ、呼び出し契約不変。 -->
<!-- quality_metric: 当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにCoDDリファクタ手順起因のworkaroundが記録されない割合） -->
<!-- argument-hint: [target_script or spec_path] -->

# CoDD Refactor Skill

bashスクリプトのリファクタリングを、データ駆動で設計→実装→検証する。
感覚ではなく計測から始め、計測で終わる。

## 使い方（3パターン）

```bash
# パターン1: スクリプト指定 — そのスクリプトのプロファイリングから開始
/codd-refactor scripts/deploy_task.sh

# パターン2: spec指定 — 既に書いたspecからCoDD実行+実装
/codd-refactor docs/research/my_refactor_spec.md

# パターン3: 引数なし — 14列時間台帳から未改善ボトルネック候補を表示
/codd-refactor
```

## /codd との違い

| | /codd | /codd-refactor |
|---|------|----------------|
| 目的 | 設計書を生成 | 設計書+実装+検証 |
| 入力 | spec.md必須 | スクリプト名 or spec or なし |
| 出力 | docs/配下の設計書 | 設計書+改修コード+before/after比較表 |
| Phase | init→plan→generate | 計測→spec→CoDD→実装→再計測 |
| 計測 | しない | **必ずする（Phase 1+5）** |

## やってはいけないこと

| NG | なぜダメか | 正しいやり方 |
|----|-----------|-------------|
| 計測せずにspecを書く | 数値なしの設計書は推測。改善幅が不明 | Phase 1で実測してからPhase 2 |
| Phase 5をスキップ | 改善したか証明不能 | before/after比較表を必ず出力 |
| `codd implement`を実行 | bashに非対応。TypeScriptが生成される | Phase 4で手動実装 |
| 全体を一気にリファクタ | テスト壊れた時に原因不明 | R1→テスト→R2→テスト の1つずつ |
| 凍結ロジックを変更 | 設計書で凍結指定した部分はI/O層のみ置換 | awkロジック/hash計算には触らない |

## Phase 0: 依存チェック（最初に実行）

```bash
_fail=0
export PATH="$HOME/.codd-venv/bin:$PATH"
command -v codd >/dev/null 2>&1 || { echo "BLOCK: codd未インストール。export PATH=$HOME/.codd-venv/bin:$PATH"; _fail=1; }
codd --version | grep -qE '^codd, version 2\.(18|19)\.' || { echo "BLOCK: codd v2.18.x以上が必要。pip install --upgrade codd-dev"; _fail=1; }
command -v bats >/dev/null 2>&1 || { echo "BLOCK: bats未インストール。npm i -g bats"; _fail=1; }
command -v parallel >/dev/null 2>&1 || { echo "BLOCK: parallel未インストール。apt install parallel"; _fail=1; }
[ "$_fail" -eq 1 ] && return 1
```

## Phase 0.5: 並列安全+残骸クリーンアップ

並列呼出しで`codd.yaml`や`docs/`が競合しないよう、作業ディレクトリを分離する。

```bash
# 作業ディレクトリ分離（並列安全）
_CODD_WORKDIR="/tmp/codd_refactor_$$_$(date +%s)"
mkdir -p "$_CODD_WORKDIR"
echo "CoDD作業ディレクトリ: $_CODD_WORKDIR"

# プロジェクトルートにcodd.yamlが残っていたら退避
[ -f codd.yaml ] && mv codd.yaml "codd.yaml.bak.$(date +%s)"

# CoDD生成物の出力先をワークディレクトリに設定
export CODD_OUTPUT_DIR="$_CODD_WORKDIR"
```

Phase 3のcoddコマンドは`$_CODD_WORKDIR`内で実行。完了後に必要な設計書のみ`docs/research/`にコピー。
func cacheは`/tmp/_func_cache_$$_*.sh`（PID分離）で並列安全。

## Phase 1: プロファイリング（計測が全て）

**引数がスクリプトパスの場合**: そのスクリプトの関数レベル分解に直行。候補選定には既存14列台帳を利用する。
**引数がspec.mdの場合**: Phase 3に直行（計測は済んでいる前提）。候補選定には既存14列台帳を利用する。
**引数なしの場合**: `logs/test_timing_ledger.tsv` の最新の完走runを入力にする。専用の `bats` loop、`scripts/run_tests.sh`、`scripts/gates/gate_test_health.sh --timing` は起動しない。

```bash
# 最新の非cache完走 all/unit runから遅い順に候補を得る。
# 14列: run_id repo commit_sha suite_root runner test_file test_id_count
#       wall_sec status skip_count cache_hit source_fingerprint measured_at resource_tags
LEDGER="${TEST_TIMING_LEDGER:-logs/test_timing_ledger.tsv}"
LATEST_RUN="$(awk -F '\t' 'NR>1 && $9=="pass" && $11==0 && ($4=="all" || $4=="unit") {run=$1} END{print run}' "$LEDGER")"
[ -n "$LATEST_RUN" ] || { echo "UNVERIFIED: completed cache_hit=0 mode=all/unit timing run missing" >&2; return 1; }
awk -F '\t' -v run="$LATEST_RUN" 'NR>1 && $1==run && $9=="pass" && $11==0 && ($4=="all" || $4=="unit") {print $8 "\t" $6}' "$LEDGER" \
  | sort -t $'\t' -k1,1nr | head -10
```

各 `test_file` から被テストtarget候補を `scripts/test_select.sh` で照合し、`docs/research/codd_refactor_registry.md` の改善済み対象を除外して表示する。候補表示は既存runner・selector・`scripts/test_timing_ledger_write.sh` の成果を再利用し、新たな計測runを作らない。

### 関数レベル分解

```bash
# 1テスト内の各操作の時間をms単位で計測
local s=$(date +%s%N)
<operation>
echo "operation: $(( ($(date +%s%N) - s) / 1000000 ))ms"
```

### I/Oパターン（batch化候補の発見）

```bash
echo -n "field_get: " && grep -c 'field_get' <script>
echo -n "yaml_field_set: " && grep -c 'yaml_field_set' <script>
```

同一ファイルへのN回逐次I/O = batch化で1回に。

## Phase 2: CoDD Spec作成

保存先: `docs/research/`。**必ずPhase 1の実測値を含めること。**

```markdown
# <Script名> リファクタリング CoDD Spec
## 問題（ボトルネック関数+計測値）
## 定量プロファイル(実測)
## リファクタリング対象（R1, R2, ...各改善内容+期待効果）
## 実施順序（ユーティリティ→書替え→テスト→計測）
## 制約（テスト全PASS/API互換/凍結ロジック）
```

## Phase 3: CoDD パイプライン実行

```bash
codd init --project-name "<name>" --language bash --requirements <spec_path>
echo "y" | codd plan --init
waves=$(codd plan --waves)
for wave in $(seq 1 $waves); do
  codd generate --wave $wave || codd generate --wave $wave
done
codd validate 2>/dev/null || true
```

v2.18.0+で`codd implement run --language`オプションをローカル確認済み(v2.19.0動作確認済)。bashリファクタでも`codd implement run --language bash --enable-typecheck-loop`で実装生成を試みよ。失敗時はCoDDを設計書・依存グラフ・伝播に使い、Phase 4の実装は手動で行う。

## Phase 4: 実装（1つずつ→テスト→次）

### 実績ベース高速化パターン

**A. yaml_field_set_batch**: 1 flock + 1 awk pass で複数フィールド同時更新
**B. field_get_multi**: 1 awk pass で複数フィールド一括読取
**C. func cache**: setup_file()で全関数キャッシュ。source 137ms→数ms
**D. file単位aggregate budget 8 / file内部jobs 1**: 共有fixtureを直列化しつつ、`run_tests.sh`がfile間を最大8並列で配分

<!-- 2026-07-15 cmd_karo_hotfix_skill_refs_ops検分: run_tests.sh dab19eacfをgit showで確認。共有fixture 3 suiteをfile_inner_jobs=1かつexclusive weightへ固定する内部scheduler修正。引数・exit status・通常suite実行契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T19:17:45+0900 -->

**鉄則: R1実装→テスト全PASS確認→R2実装→テスト全PASS確認。一気にやるな。**

各反復と報告直前は `bash scripts/run_tests.sh task <task_yaml>` を使う。直接実行する
contract testは明示 `test_path`（または確定済みreportのtest `files_modified`）に限る。
自動注入された `commit_contract.planned_paths` / `files_to_modify` は所有境界であり、
production pathから `test_select.sh` で依存testを選ぶ入力としてのみ扱う。完走receiptの
FAIL 0・SKIP 0を確認し、失敗時はreceiptのexit statusをそのまま採用する。

## Phase 5: 検証（14列台帳のbefore/after比較表を出力して初めて完了）

通常の `scripts/run_tests.sh` が自動記録した2 runを比較する。専用計測runは禁止。同一 `test_file`・同一 `suite_root`、`cache_hit=0`、`mode=all/unit` の完走行のみを使い、Before/Afterの `commit_sha` と `run_id` を表へ必ず記す。一方でも欠損した場合は `UNVERIFIED` としてfail-closedし、完了を宣言しない。

```
| 段階 | test_file | suite_root | commit_sha | run_id | wall_sec | 改善率 |
|------|-----------|------------|------------|--------|----------|--------|
| Before | tests/unit/X.bats | unit | <sha> | <run_id> | Xs | baseline |
| After | tests/unit/X.bats | unit | <sha> | <run_id> | Ys | -N% |
```

## Phase 6: After設計書（車輪の再発明防止）

**リファクタリング完了後、現在のコード構造を設計書として残す。これがないと将来の開発者が同じ最適化を再発明する。**

### 6.1 CoDD extractで逆生成

```bash
cd "$_CODD_WORKDIR"
codd extract --path "$PROJECT_ROOT" --source-dirs scripts/lib --language bash --ai
```

対象を改修したファイルに絞る（全量extractは重いため）。

### 6.1.5 依存グラフ更新と伝播確認

```bash
codd scan --path "$PROJECT_ROOT"
codd impact --path "$PROJECT_ROOT"
# 下流docsの自動更新が妥当な場合のみ実行
codd propagate --path "$PROJECT_ROOT" --update
```

`codd-skeleton-complete`の知見: after設計書を置くだけでは腐る。frontmatter依存グラフを`scan`し、変更時に`impact`と`propagate --update`で下流docsを追随させる。

### 6.2 手動after設計書（extractが不十分な場合）

保存先: `docs/research/<script>_after_<date>.md`

必須セクション:
```markdown
# <Script名> After設計書（リファクタリング後のas-is）

## 現在の構造
- 関数一覧と責務（変更された関数にマーク）
- 依存関係（どの関数がどのユーティリティを使うか）

## 最適化パターン（再利用すべき仕組み）
- yaml_field_set_batch: いつ使うか、なぜ逐次field_setより速いか
- field_get_multi: いつ使うか
- func cache: いつ使うか、setup_file()の書き方

## 禁止パターン（やってはいけないこと+理由）
- 同一ファイルへのyaml_field_set 3回以上 → batch化必須（flock競合でNx遅延）
- テスト内でdeploy_task.shを毎回source → func cache使え（137ms→数ms）

## 計測値（劣化検知のベースライン）
- 1テスト: Xms（これを超えたらリグレッション）
- 全量: Xs（これを超えたらリグレッション）
```

### 6.3 context索引に登録

`context/infrastructure.md` 等の該当セクションにafter設計書へのリンクを追加:
```
→ docs/research/<script>_after_<date>.md（最適化パターン+禁止パターン）
```

**Phase 6なしにスキル完了を宣言するな。設計書なきリファクタリングは半年後に消える。**

## 実績（2026-04-15 deploy_task.sh）

| 対象 | Before | After | 手法 |
|------|--------|-------|------|
| 1テスト(template_only) | 2639ms | 88ms (-97%) | func cache + batch set/get |
| template_generation 14件 | 17.4s | 2.7s (-84%) | func cache |
| unit全量 888件 | 4:51 | 1:39 (-66%) | --jobs 8 |

<!-- script_refs_checked_at: 2026-07-18T22:08:00+09:00 -->
<!-- 2026-07-18 cmd_karo_ci_fix_skill_refs_run_tests検分: run_tests.sh 108451a3f/5daec7902/07a9ef1c0/1086730b4/a11074b31をgit log/showで照合。公開runはrun_with_receipt.sh経由でdurable terminal receiptをexactly 1件生成し、内部実行を--receipt-innerで識別する。heavy admission再execも--receipt-innerを継承して二重receiptを防止する。file modeは外側Bats transportを隔離し、fixture symlink write-throughを事前BLOCKする。mode引数・test選択・終了status・通常suite実行契約は不変。 -->
<!-- script_refs_checked_at: 2026-08-01T19:18:00+09:00 -->
<!-- 2026-08-01 reflux検分: run_tests.sh 9ab1087c7は外部backend contract testをproject .venvのpytestとproject-root PYTHONPATHで実行する。task mode・明示test選択・FAIL/SKIPの終了契約は不変。 -->
