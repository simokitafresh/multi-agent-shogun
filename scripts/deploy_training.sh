#!/usr/bin/env bash
# deploy_training.sh — 修行配備ラッパー
# Usage: bash scripts/deploy_training.sh <round> <ninja1:target1> [ninja2:target2] ...
# Example: bash scripts/deploy_training.sh R22 hayate:tests/unit/test_foo.bats saizo:tests/unit/test_bar.bats

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ROUND="${1:?Usage: deploy_training.sh <round> <ninja:target> ...}"
shift

if [ $# -eq 0 ]; then
    echo "ERROR: ninja:target pairs required" >&2
    exit 1
fi

STK="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
SUCCESS=0
TOTAL=0

for pair in "$@"; do
    ninja="${pair%%:*}"
    target="${pair#*:}"
    cmd_id="cmd_training_L4_${ROUND}_${ninja}"
    basename_target="$(basename "$target")"
    TOTAL=$((TOTAL + 1))

    # shogun_to_karo.yamlにエントリ追加
    cat >> "$STK" << YAML_EOF
  ${cmd_id}:
    title: "修行L4 ${ROUND} ${ninja}"
    project: infra
    scope_mode: IMPL
    command: |
      ${basename_target}を高速化せよ。ボトルネック1-2箇所改善。長引くなら途中commit終了。
      AC1: 計測+ボトルネック特定  AC2: 改善+commit  AC3: PASS+LC+BC+verdict
      ★ bc構造維持。bats全量禁止。
    acceptance_criteria:
      - ac: "AC1: 計測+ボトルネック特定"
      - ac: "AC2: 改善+commit"
      - ac: "AC3: 全テストPASS(SKIP=0)+LC+BC+verdict"
    status: delegated
    scout_exempt: true
    created_at: "$(date -Is)"
YAML_EOF

    # target_path設定
    bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" task target_path "$target" 2>/dev/null || true

    # deploy_task.sh --cmdで配備
    result=$(bash "$SCRIPT_DIR/scripts/deploy_task.sh" "$ninja" --cmd "$cmd_id" 2>&1)
    if echo "$result" | grep -q "deployment complete"; then
        echo "OK: $ninja → $basename_target (template generated)"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "FAIL: $ninja → $(echo "$result" | grep -E "BLOCK|ERROR" | head -1)"
    fi
done

echo "--- deploy_training.sh: ${SUCCESS}/${TOTAL} deployed (round=${ROUND}) ---"
