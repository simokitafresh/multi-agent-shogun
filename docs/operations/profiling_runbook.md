---
codd:
  node_id: operations:profiling-runbook
  type: operations
  depends_on:
  - id: test:test-strategy
    relation: depends_on
    semantic: technical
  depended_by: []
  conventions:
  - targets:
    - module:deploy_task
    reason: プロファイル計測は要件定義の計測条件（同一環境・同一テストケース）で実施すること。計測結果はCI artifactとして保存。
  modules:
  - deploy_task
---

# Profiling Runbook — Before/After Measurement

## 1. Overview

ninja_monitor.sh（3,158行・59関数）を `scripts/lib/monitor/` 配下の7モジュールに分割するリファクタリングにおいて、**性能劣化ゼロ**を定量的に証明するためのプロファイリング手順を定義する。本ランブックは、リファクタリング前後で同一環境・同一テストケースによる計測を実施し、計測結果をCI artifactとして保存する運用を規定する。

### 計測対象

| 計測ポイント | 対象モジュール | 計測内容 |
|-------------|--------------|---------|
| source chain初期化 | `scripts/ninja_monitor.sh` + 7モジュール | 全source完了までの経過時間 |
| 1ポーリングサイクル | 主ループ（20秒周期） | 1サイクル内の実処理時間（sleep除外） |
| 個別関数実行 | `idle_management.sh`, `stall_detection.sh`, `health_checks.sh`, `karo_monitor.sh`, `pane_management.sh`, `report_utils.sh`, `state_io.sh` | 各関数の実行時間 |
| composite hash算出 | 自動再起動検知 | 8ファイル（本体1 + モジュール7）のハッシュ計算時間 |
| deploy_task処理 | `module:deploy_task` | タスク配備から完了までの所要時間 |

### コンベンション準拠

| コンベンション | 準拠方法 |
|--------------|---------|
| **Conv-Profiling（module:deploy_task）**: 同一環境・同一テストケースで計測、CI artifact保存 | Before計測とAfter計測は同一マシン・同一bashバージョン・同一batsバージョン・同一テストセット（854テスト）で実施する。計測結果は `profiling-results/` ディレクトリにJSON形式で出力し、GitHub Actions artifactとして90日間保存する。環境情報（OS、bash version、CPU、メモリ）を計測結果に埋め込み、同一性を検証可能にする |

### 計測環境要件

- **OS**: WSL2 Ubuntu（本番と同一環境）
- **Shell**: Bash 5.x（`bash --version` で確認）
- **テストフレームワーク**: bats-core ≥ 1.5.0
- **計測ツール**: bash組込み `TIMEFORMAT`、`date +%s%N`（ナノ秒精度）、`time` コマンド
- **隔離条件**: 計測中は他プロセスの負荷を最小化する。tmuxセッション内の他エージェントはidle状態であること

## 2. Runbook

### 2.1 Before計測（リファクタリング前）

**Step 1: 環境スナップショット取得**

```bash
#!/usr/bin/env bash
# profiling/capture_env.sh
ENV_FILE="profiling-results/env_snapshot.json"
mkdir -p profiling-results

cat > "$ENV_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "phase": "before",
  "bash_version": "$(bash --version | head -1)",
  "bats_version": "$(bats --version)",
  "os": "$(uname -a)",
  "cpu": "$(lscpu | grep 'Model name' | sed 's/.*:\s*//')",
  "memory_total_kb": $(grep MemTotal /proc/meminfo | awk '{print $2}'),
  "ninja_monitor_lines": $(wc -l < scripts/ninja_monitor.sh),
  "git_commit": "$(git rev-parse HEAD)"
}
EOF
echo "Environment captured: $ENV_FILE"
```

**Step 2: source chain初期化時間の計測**

```bash
#!/usr/bin/env bash
# profiling/measure_source_chain.sh
PHASE="${1:-before}"
ITERATIONS=50
RESULTS_FILE="profiling-results/source_chain_${PHASE}.json"

echo '{"phase":"'"$PHASE"'","metric":"source_chain_init","iterations":'"$ITERATIONS"',"samples":[' > "$RESULTS_FILE"

for i in $(seq 1 "$ITERATIONS"); do
  START_NS=$(date +%s%N)
  (
    # サブシェルで隔離実行: source chainのみ計測（主ループ起動なし）
    export DRY_RUN=1
    source scripts/ninja_monitor.sh 2>/dev/null
  )
  END_NS=$(date +%s%N)
  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
  [[ $i -gt 1 ]] && echo -n ',' >> "$RESULTS_FILE"
  echo "$ELAPSED_MS" >> "$RESULTS_FILE"
done

echo '],"unit":"ms"}' >> "$RESULTS_FILE"
echo "Source chain profiling ($PHASE): $ITERATIONS iterations → $RESULTS_FILE"
```

**Step 3: batsテストスイート実行時間の計測**

```bash
#!/usr/bin/env bash
# profiling/measure_test_suite.sh
PHASE="${1:-before}"
ITERATIONS=3
RESULTS_FILE="profiling-results/test_suite_${PHASE}.json"

echo '{"phase":"'"$PHASE"'","metric":"test_suite_854","iterations":'"$ITERATIONS"',"samples":[' > "$RESULTS_FILE"

for i in $(seq 1 "$ITERATIONS"); do
  START_NS=$(date +%s%N)
  bats tests/ --recursive --formatter tap > /dev/null 2>&1
  EXIT_CODE=$?
  END_NS=$(date +%s%N)
  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
  
  [[ $i -gt 1 ]] && echo -n ',' >> "$RESULTS_FILE"
  echo "{\"elapsed_ms\":$ELAPSED_MS,\"exit_code\":$EXIT_CODE}" >> "$RESULTS_FILE"
done

echo '],"unit":"ms"}' >> "$RESULTS_FILE"
echo "Test suite profiling ($PHASE): $ITERATIONS iterations → $RESULTS_FILE"
```

**Step 4: 個別関数プロファイリング**

```bash
#!/usr/bin/env bash
# profiling/measure_functions.sh
PHASE="${1:-before}"
RESULTS_FILE="profiling-results/functions_${PHASE}.json"
ITERATIONS=100

# 59関数の一覧を抽出
FUNCTIONS=$(grep -E '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' \
  scripts/ninja_monitor.sh | sed 's/().*//' | sed 's/function //' | tr -d ' ')

echo '{"phase":"'"$PHASE"'","metric":"function_execution","iterations":'"$ITERATIONS"',"functions":{' > "$RESULTS_FILE"

FIRST=true
for func in $FUNCTIONS; do
  $FIRST || echo ',' >> "$RESULTS_FILE"
  FIRST=false
  echo -n "\"$func\":[" >> "$RESULTS_FILE"
  
  for i in $(seq 1 "$ITERATIONS"); do
    START_NS=$(date +%s%N)
    # モック環境下で関数を呼び出し（副作用なし）
    (
      source tests/e2e/helpers/mock_globals.bash 2>/dev/null
      source tests/e2e/helpers/mock_externals.bash 2>/dev/null
      init_mock_globals 2>/dev/null
      init_mock_externals 2>/dev/null
      source scripts/ninja_monitor.sh 2>/dev/null
      "$func" 2>/dev/null
    )
    END_NS=$(date +%s%N)
    ELAPSED_US=$(( (END_NS - START_NS) / 1000 ))
    [[ $i -gt 1 ]] && echo -n ',' >> "$RESULTS_FILE"
    echo -n "$ELAPSED_US" >> "$RESULTS_FILE"
  done
  echo ']' >> "$RESULTS_FILE"
done

echo '},"unit":"us"}' >> "$RESULTS_FILE"
echo "Function profiling ($PHASE): 59 functions × $ITERATIONS iterations → $RESULTS_FILE"
```

**Step 5: deploy_task処理時間の計測**

```bash
#!/usr/bin/env bash
# profiling/measure_deploy_task.sh
PHASE="${1:-before}"
ITERATIONS=10
RESULTS_FILE="profiling-results/deploy_task_${PHASE}.json"

echo '{"phase":"'"$PHASE"'","metric":"deploy_task","iterations":'"$ITERATIONS"',"samples":[' > "$RESULTS_FILE"

for i in $(seq 1 "$ITERATIONS"); do
  # テスト用タスクYAMLを一時作成
  TASK_YAML=$(mktemp /tmp/profiling_task_XXXXXX.yaml)
  cat > "$TASK_YAML" <<'TASK'
cmd_id: cmd_profiling_test
ninja: hayate
status: assigned
ac:
  - id: ac1
    description: "profiling test AC"
    binary_checks:
      - check: "true"
TASK

  START_NS=$(date +%s%N)
  bash scripts/deploy_task.sh "$TASK_YAML" 2>/dev/null
  EXIT_CODE=$?
  END_NS=$(date +%s%N)
  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
  
  [[ $i -gt 1 ]] && echo -n ',' >> "$RESULTS_FILE"
  echo "{\"elapsed_ms\":$ELAPSED_MS,\"exit_code\":$EXIT_CODE}" >> "$RESULTS_FILE"
  
  rm -f "$TASK_YAML"
done

echo '],"unit":"ms"}' >> "$RESULTS_FILE"
echo "deploy_task profiling ($PHASE): $ITERATIONS iterations → $RESULTS_FILE"
```

**Step 6: Before計測の一括実行**

```bash
#!/usr/bin/env bash
# profiling/run_before.sh
set -euo pipefail
mkdir -p profiling-results

echo "=== Before Profiling: Start ==="
bash profiling/capture_env.sh
bash profiling/measure_source_chain.sh before
bash profiling/measure_test_suite.sh before
bash profiling/measure_functions.sh before
bash profiling/measure_deploy_task.sh before

# ベースラインコミットハッシュを記録
git rev-parse HEAD > profiling-results/before_commit.txt
echo "=== Before Profiling: Complete ==="
echo "Results in profiling-results/*_before.json"
```

### 2.2 After計測（リファクタリング後）

リファクタリング完了後、**同一マシン・同一セッション**で以下を実行する。

```bash
#!/usr/bin/env bash
# profiling/run_after.sh
set -euo pipefail

echo "=== After Profiling: Start ==="

# 環境同一性の検証
BEFORE_BASH=$(jq -r '.bash_version' profiling-results/env_snapshot.json)
CURRENT_BASH=$(bash --version | head -1)
if [[ "$BEFORE_BASH" != "$CURRENT_BASH" ]]; then
  echo "ERROR: Bash version mismatch. Before='$BEFORE_BASH' After='$CURRENT_BASH'"
  exit 1
fi

bash profiling/measure_source_chain.sh after
bash profiling/measure_test_suite.sh after
bash profiling/measure_functions.sh after
bash profiling/measure_deploy_task.sh after

git rev-parse HEAD > profiling-results/after_commit.txt
echo "=== After Profiling: Complete ==="
```

### 2.3 Before/After比較レポート生成

```bash
#!/usr/bin/env bash
# profiling/compare.sh
set -euo pipefail
REPORT="profiling-results/comparison_report.md"

calc_stats() {
  local file="$1" phase="$2"
  # jqでサンプル配列から中央値・平均・p95を算出
  jq -r --arg p "$phase" '
    .samples | sort | 
    { median: .[length/2 | floor],
      mean: (add / length | floor),
      p95: .[length * 0.95 | floor],
      min: .[0],
      max: .[-1] }
  ' "$file"
}

cat > "$REPORT" <<'HEADER'
# Profiling Comparison Report

## Environment
HEADER

jq -r '"- **Bash**: \(.bash_version)\n- **OS**: \(.os)\n- **CPU**: \(.cpu)\n- **Memory**: \(.memory_total_kb) KB"' \
  profiling-results/env_snapshot.json >> "$REPORT"

echo "" >> "$REPORT"
echo "| Metric | Before (median ms) | After (median ms) | Delta (%) | Verdict |" >> "$REPORT"
echo "|--------|-------------------|-------------------|-----------|---------|" >> "$REPORT"

for metric in source_chain test_suite deploy_task; do
  BEFORE_MEDIAN=$(jq '[.samples[].elapsed_ms // .samples[]] | sort | .[length/2 | floor]' \
    "profiling-results/${metric}_before.json" 2>/dev/null || echo "N/A")
  AFTER_MEDIAN=$(jq '[.samples[].elapsed_ms // .samples[]] | sort | .[length/2 | floor]' \
    "profiling-results/${metric}_after.json" 2>/dev/null || echo "N/A")
  
  if [[ "$BEFORE_MEDIAN" != "N/A" && "$AFTER_MEDIAN" != "N/A" && "$BEFORE_MEDIAN" -gt 0 ]]; then
    DELTA=$(( (AFTER_MEDIAN - BEFORE_MEDIAN) * 100 / BEFORE_MEDIAN ))
    if [[ $DELTA -le 5 ]]; then
      VERDICT="PASS"
    elif [[ $DELTA -le 15 ]]; then
      VERDICT="WARN"
    else
      VERDICT="FAIL"
    fi
  else
    DELTA="N/A"
    VERDICT="SKIP"
  fi
  
  echo "| $metric | $BEFORE_MEDIAN | $AFTER_MEDIAN | ${DELTA}% | $VERDICT |" >> "$REPORT"
done

echo "" >> "$REPORT"
echo "## Commits" >> "$REPORT"
echo "- Before: $(cat profiling-results/before_commit.txt)" >> "$REPORT"
echo "- After: $(cat profiling-results/after_commit.txt)" >> "$REPORT"
echo "" >> "$REPORT"
echo "## Verdict Criteria" >> "$REPORT"
echo "- **PASS**: delta ≤ 5% (within noise margin)" >> "$REPORT"
echo "- **WARN**: 5% < delta ≤ 15% (investigate)" >> "$REPORT"
echo "- **FAIL**: delta > 15% (performance regression, block release)" >> "$REPORT"

echo "Comparison report: $REPORT"
```

### 2.4 判定基準

| メトリクス | PASS | WARN | FAIL (リリースブロッカー) |
|-----------|------|------|------------------------|
| source chain初期化 | delta ≤ 5% | 5% < delta ≤ 15% | delta > 15% |
| テストスイート実行時間 | delta ≤ 5% | 5% < delta ≤ 15% | delta > 15% |
| deploy_task処理時間 | delta ≤ 5% | 5% < delta ≤ 15% | delta > 15% |
| 個別関数（p95） | delta ≤ 10% | 10% < delta ≤ 25% | delta > 25% |
| composite hash算出 | delta ≤ 20%（ファイル数1→8増加を許容） | 20% < delta ≤ 50% | delta > 50% |

### 2.5 失敗時の対応

FAILメトリクスが1つ以上ある場合:

1. **原因特定**: 個別関数プロファイリング結果から劣化関数を特定する
2. **source chainオーバーヘッド**: 7ファイル読込みの増分がsource chain初期化に影響している場合、ファイルサイズの確認と不要コメント除去を検討する
3. **ファイルI/Oボトルネック**: WSL2 NTFS-mountedパスの特性上、ファイル操作の増加が影響する場合、`state_io.sh` のflock粒度を確認する
4. **ロールバック**: 性能劣化が許容範囲を超え修正不能な場合、テスト戦略のロールバック手順を適用する:
   ```bash
   git checkout -- scripts/ninja_monitor.sh
   rm -r scripts/lib/monitor/
   bats tests/ --recursive --formatter tap  # 854全PASS・SKIP=0を確認
   ```

## 3. Monitoring

### 3.1 CI計測ダッシュボード

プロファイリング結果はGitHub Actions artifactとして保存し、PR上で差分を確認可能にする。

| 監視項目 | データソース | 閾値 | アラート |
|---------|------------|------|---------|
| source chain初期化時間 | `profiling-results/source_chain_*.json` | Before比 +15% | CI FAILステータス |
| テストスイート実行時間 | `profiling-results/test_suite_*.json` | Before比 +15% | CI FAILステータス |
| deploy_task処理時間 | `profiling-results/deploy_task_*.json` | Before比 +15% | CI FAILステータス |
| 個別関数p95 | `profiling-results/functions_*.json` | Before比 +25% | CI WARNコメント |
| batsテスト結果 | bats TAP出力 | 854 PASS / 0 SKIP / 0 FAIL | CI FAILステータス（リリースブロッカー） |
| SKIP検出 | `grep -c '# skip'` on TAP出力 | 0 | CI FAILステータス（Conv-1: SKIP=FAIL） |

### 3.2 Artifactの保存と追跡

```
profiling-results/
├── env_snapshot.json           # 計測環境情報
├── before_commit.txt           # Beforeのgitコミットハッシュ
├── after_commit.txt            # Afterのgitコミットハッシュ
├── source_chain_before.json    # source chain計測（Before）
├── source_chain_after.json     # source chain計測（After）
├── test_suite_before.json      # テストスイート計測（Before）
├── test_suite_after.json       # テストスイート計測（After）
├── functions_before.json       # 関数別計測（Before）
├── functions_after.json        # 関数別計測（After）
├── deploy_task_before.json     # deploy_task計測（Before）
├── deploy_task_after.json      # deploy_task計測（After）
└── comparison_report.md        # 比較レポート
```

Artifact保存期間: 90日。PRごとにBefore/Afterペアを保存し、性能推移をコミット単位で追跡可能にする。

### 3.3 計測結果の同一性検証

After計測実行時に自動で検証する項目:

| 検証項目 | 検証方法 | 不一致時の動作 |
|---------|---------|-------------|
| Bashバージョン | `env_snapshot.json` の `bash_version` と現在値を比較 | ERROR終了（計測中止） |
| batsバージョン | `env_snapshot.json` の `bats_version` と現在値を比較 | ERROR終了（計測中止） |
| テストケース数 | Before TAP出力の行数とAfter TAP出力の行数を比較 | ERROR終了（854テスト一致必須） |
| OS/カーネル | `uname -a` の一致確認 | WARN出力（続行可） |

### 3.4 長期トレンド監視

`profiling-results/comparison_report.md` の時系列データをCI artifactから収集し、以下のトレンドを監視する:

- source chain初期化時間が3回連続で増加 → モジュール肥大化の兆候
- deploy_task処理時間が前回比10%以上増加 → タスク配備パイプラインの劣化
- 個別関数の上位5件のp95推移 → ホットスポット関数の早期検出

## 4. CI/CD Pipeline Generation Meta-Prompt

### 4.1 出力ファイル

```yaml
# .github/workflows/ci.yml
# @generated-by: codd propagate
```

### 4.2 トリガー

```yaml
on:
  pull_request:
    branches: [main, develop]
```

### 4.3 前提ツールの検証

プロジェクトの依存マニフェストから確認済みのツール:

| ツール | 確認元 | バージョン制約 |
|-------|-------|-------------|
| bats-core | `tests/` ディレクトリ内の `.bats` ファイル群 | ≥ 1.5.0 |
| bats-support | テストヘルパーのload文 | bats-core互換版 |
| bats-assert | テストヘルパーのload文 | bats-core互換版 |
| bats-file | テストヘルパーのload文 | bats-core互換版 |
| bash | シェルスクリプト実行環境 | 5.x |
| jq | プロファイリングスクリプトのJSON処理 | インストールステップで追加 |
| tmux | pane_managementテストのモックベースライン | インストールステップで追加 |

CIステップで使用するツールがランナーにプリインストールされていない場合（jq, tmux）、`apt-get install` ステップを明示的に追加する。

### 4.4 ジョブ定義

テスト戦略のテストレベル分離に基づき、以下の4ジョブを定義する:

**Job 1: `unit-integration`（ユニット統合テスト）**

```yaml
unit-integration:
  runs-on: ubuntu-latest
  timeout-minutes: 10
  steps:
    - uses: actions/checkout@v4
    - name: Install dependencies
      run: |
        sudo apt-get update && sudo apt-get install -y jq tmux
        # bats-core + helpers
        git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
        sudo /tmp/bats/install.sh /usr/local
        git clone --depth 1 https://github.com/bats-core/bats-support.git /tmp/bats-support
        git clone --depth 1 https://github.com/bats-core/bats-assert.git /tmp/bats-assert
        git clone --depth 1 https://github.com/bats-core/bats-file.git /tmp/bats-file
    - name: Cache bats installation
      uses: actions/cache@v4
      with:
        path: /usr/local/libexec/bats-core
        key: bats-${{ runner.os }}-v1
    - name: Run unit integration tests
      run: |
        bats tests/e2e/*.spec.bats --recursive --formatter tap | tee unit.tap
        SKIP_COUNT=$(grep -c '# skip' unit.tap || true)
        if [[ "$SKIP_COUNT" -gt 0 ]]; then
          echo "::error::SKIP detected ($SKIP_COUNT). SKIP=FAIL policy (Conv-1)."
          exit 1
        fi
```

**Job 2: `system-integration`（システム統合テスト）**

```yaml
system-integration:
  runs-on: ubuntu-latest
  timeout-minutes: 10
  needs: unit-integration
  steps:
    - uses: actions/checkout@v4
    - name: Install dependencies
      run: |
        sudo apt-get update && sudo apt-get install -y jq tmux
        git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
        sudo /tmp/bats/install.sh /usr/local
        git clone --depth 1 https://github.com/bats-core/bats-support.git /tmp/bats-support
        git clone --depth 1 https://github.com/bats-core/bats-assert.git /tmp/bats-assert
        git clone --depth 1 https://github.com/bats-core/bats-file.git /tmp/bats-file
    - name: Run existing 854 tests (baseline gate)
      run: |
        bats tests/ --recursive --formatter tap | tee baseline.tap
        PASS_COUNT=$(grep -c '^ok' baseline.tap)
        SKIP_COUNT=$(grep -c '# skip' baseline.tap || true)
        echo "Baseline: ${PASS_COUNT} passed, ${SKIP_COUNT} skipped"
        if [[ "$PASS_COUNT" -ne 854 ]]; then
          echo "::error::Expected 854 tests, got $PASS_COUNT"
          exit 1
        fi
        if [[ "$SKIP_COUNT" -gt 0 ]]; then
          echo "::error::SKIP=$SKIP_COUNT. SKIP=FAIL (Conv-1)."
          exit 1
        fi
    - name: Run system integration tests
      run: |
        bats tests/e2e/*.system.bats --recursive --formatter tap | tee system.tap
        SKIP_COUNT=$(grep -c '# skip' system.tap || true)
        if [[ "$SKIP_COUNT" -gt 0 ]]; then
          echo "::error::SKIP detected in system tests."
          exit 1
        fi
```

**Job 3: `profiling`（性能計測）**

```yaml
profiling:
  runs-on: ubuntu-latest
  timeout-minutes: 15
  needs: system-integration
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0  # Before/After比較に全履歴が必要
    - name: Install dependencies
      run: |
        sudo apt-get update && sudo apt-get install -y jq tmux
        git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
        sudo /tmp/bats/install.sh /usr/local
    - name: Run Before profiling (base branch)
      run: |
        git checkout ${{ github.event.pull_request.base.sha }}
        mkdir -p profiling-results
        bash profiling/capture_env.sh
        bash profiling/measure_source_chain.sh before
        bash profiling/measure_test_suite.sh before
        bash profiling/measure_deploy_task.sh before
        git rev-parse HEAD > profiling-results/before_commit.txt
    - name: Run After profiling (PR branch)
      run: |
        git checkout ${{ github.event.pull_request.head.sha }}
        bash profiling/measure_source_chain.sh after
        bash profiling/measure_test_suite.sh after
        bash profiling/measure_deploy_task.sh after
        git rev-parse HEAD > profiling-results/after_commit.txt
    - name: Generate comparison report
      run: bash profiling/compare.sh
    - name: Check profiling thresholds
      run: |
        # source_chain / test_suite / deploy_task の delta ≤ 15% を検証
        REPORT="profiling-results/comparison_report.md"
        FAIL_COUNT=$(grep -c '| FAIL |' "$REPORT" || true)
        if [[ "$FAIL_COUNT" -gt 0 ]]; then
          echo "::error::Performance regression detected. See comparison_report.md."
          cat "$REPORT"
          exit 1
        fi
        WARN_COUNT=$(grep -c '| WARN |' "$REPORT" || true)
        if [[ "$WARN_COUNT" -gt 0 ]]; then
          echo "::warning::Performance warning detected. Review comparison_report.md."
          cat "$REPORT"
        fi
    - name: Upload profiling artifacts
      uses: actions/upload-artifact@v4
      with:
        name: profiling-results-${{ github.event.pull_request.number }}
        path: profiling-results/
        retention-days: 90
```

**Job 4: `quality-gate`（最終品質ゲート）**

```yaml
quality-gate:
  runs-on: ubuntu-latest
  needs: [unit-integration, system-integration, profiling]
  if: always()
  steps:
    - name: Check all jobs passed
      run: |
        if [[ "${{ needs.unit-integration.result }}" != "success" ]]; then
          echo "::error::unit-integration failed"
          exit 1
        fi
        if [[ "${{ needs.system-integration.result }}" != "success" ]]; then
          echo "::error::system-integration failed"
          exit 1
        fi
        if [[ "${{ needs.profiling.result }}" != "success" ]]; then
          echo "::error::profiling failed"
          exit 1
        fi
        echo "All quality gates passed."
```

### 4.5 環境変数

| 変数名 | 値 | GitHub Secrets |
|--------|---|----------------|
| `DRY_RUN` | `1`（source chainの隔離実行フラグ） | 不要（ハードコード） |
| `BATS_LIB_PATH` | `/tmp`（batsヘルパーライブラリパス） | 不要 |

本プロジェクトはbashスクリプトのリファクタリングであり、データベース・認証トークン・外部サービス連携は不要。GitHub Secretsの設定は不要。

### 4.6 キャッシュ戦略

```yaml
- name: Cache bats installation
  uses: actions/cache@v4
  with:
    path: |
      /usr/local/libexec/bats-core
      /tmp/bats-support
      /tmp/bats-assert
      /tmp/bats-file
    key: bats-deps-${{ runner.os }}-v1
```

bats-coreとヘルパーライブラリのクローン・インストールをキャッシュし、CI実行時間を短縮する。キャッシュキーはOS + 固定バージョン文字列で構成し、ライブラリ更新時は `v1` → `v2` のバンプで無効化する。

### 4.7 マージゲート

ブランチ保護ルールの推奨設定:

| 設定項目 | 値 |
|---------|---|
| Require status checks to pass before merging | 有効 |
| Required status checks | `unit-integration`, `system-integration`, `profiling`, `quality-gate` |
| Require branches to be up to date before merging | 有効 |
| Require pull request reviews before merging | 1名以上 |

4ジョブ全てがPASSしない限り、PRのmainブランチへのマージをブロックする。`quality-gate` ジョブが最終ゲートとして全ジョブの結果を集約する。

### 4.8 失敗通知

CI失敗時のSlack/メール通知は推奨するが必須としない。導入する場合:

```yaml
- name: Notify on failure
  if: failure()
  run: |
    # ntfy.sh経由での通知（プロジェクト既存インフラ活用）
    bash scripts/ntfy.sh "CI FAIL: PR #${{ github.event.pull_request.number }} - profiling regression detected"
```

プロジェクト既存の `scripts/ntfy.sh` を活用し、追加の外部サービス依存を避ける。

### 4.9 サーバ起動に関する注記

本プロジェクトはbashデーモンのリファクタリングであり、Webアプリケーションではない。CI/CDパイプラインにおけるサーバ起動・ヘルスチェック待機・readinessプローブは不要。全テストはbatsによるbashファイルの直接source実行で完結する。

### 4.10 ランタイム互換性

- batsテストファイルの構文はbats-core ≥ 1.5.0互換を維持する
- bash 5.x固有の機能（連想配列 `declare -A`）を使用するため、bash 4.x以下では動作しない
- Ubuntu LTS（20.04以降）のデフォルトbashバージョンで動作確認済み
- jq 1.6以上を前提とする（Ubuntu 20.04+のapt標準パッケージで充足）
