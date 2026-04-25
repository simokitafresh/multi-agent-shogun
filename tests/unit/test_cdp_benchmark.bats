#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    OUTPUT_DIR="${TMP_DIR}/outputs/cdp-baselines"
    mkdir -p "$OUTPUT_DIR"
}

teardown() {
    rm -rf "$TMP_DIR"
}

write_fixture() {
    local target="$1"
    local generated_at="$2"
    local median_ms="$3"
    local bundle_a="$4"
    local bundle_b="$5"
    local status_a="${6:-200}"
    local status_b="${7:-200}"

    cat > "$target" <<EOF
{
  "generated_at": "${generated_at}",
  "pages": [
    {
      "key": "dashboard",
      "name": "Dashboard",
      "path": "/dashboard",
      "measurements": [
        {
          "baseline_key": "dashboard:page_load:warm-reload",
          "label": "warm-reload",
          "page_key": "dashboard",
          "page_name": "Dashboard",
          "page_path": "/dashboard",
          "threshold_ms": 2500,
          "median_ms": ${median_ms},
          "status": "PASS",
          "runs": [
            {
              "resource_timings": [
                {
                  "name": "https://example.com/api/a",
                  "decodedBodySize": ${bundle_a},
                  "responseStatus": ${status_a}
                },
                {
                  "name": "https://example.com/api/b",
                  "decodedBodySize": ${bundle_b},
                  "responseStatus": ${status_b}
                }
              ],
              "console_error_count": 0
            }
          ]
        }
      ]
    }
  ]
}
EOF
}

@test "cdp_benchmark: --baseline captures pointer and writes snapshot" {
    fixture="${TMP_DIR}/baseline_input.json"
    write_fixture "$fixture" "2026-04-25T20:00:00+09:00" "1000" "1000" "1000"

    run python3 "$PROJECT_ROOT/scripts/cdp/cdp_benchmark.py" \
        --input-json "$fixture" \
        --output-dir "$OUTPUT_DIR" \
        --branch test-branch \
        --baseline

    [ "$status" -eq 0 ]
    [ -f "${OUTPUT_DIR}/test-branch_latest.json" ]
    ls "${OUTPUT_DIR}"/test-branch_*.json >/dev/null
    [[ "$output" == *"Baseline pointer updated"* ]]
    [[ "$output" == *"health=100"* ]]
}

@test "cdp_benchmark: timing delta >20% becomes WARN and trend prints" {
    baseline="${TMP_DIR}/baseline.json"
    current="${TMP_DIR}/current.json"
    write_fixture "$baseline" "2026-04-25T20:00:00+09:00" "1000" "1000" "1000"
    write_fixture "$current" "2026-04-25T20:10:00+09:00" "1300" "1050" "1000"

    python3 "$PROJECT_ROOT/scripts/cdp/cdp_benchmark.py" \
        --input-json "$baseline" \
        --output-dir "$OUTPUT_DIR" \
        --branch test-branch \
        --baseline >/dev/null

    run python3 "$PROJECT_ROOT/scripts/cdp/cdp_benchmark.py" \
        --input-json "$current" \
        --output-dir "$OUTPUT_DIR" \
        --branch test-branch \
        --trend

    [ "$status" -eq 0 ]
    [[ "$output" == *"regression=WARN"* ]]
    [[ "$output" == *"Trend (test-branch"* ]]
}

@test "cdp_benchmark: +500ms timing and bundle +25% become REGRESSION" {
    baseline="${TMP_DIR}/baseline.json"
    current="${TMP_DIR}/current.json"
    write_fixture "$baseline" "2026-04-25T20:00:00+09:00" "1000" "1000" "1000"
    write_fixture "$current" "2026-04-25T20:20:00+09:00" "1600" "1300" "1300" "404" "200"

    python3 "$PROJECT_ROOT/scripts/cdp/cdp_benchmark.py" \
        --input-json "$baseline" \
        --output-dir "$OUTPUT_DIR" \
        --branch test-branch \
        --baseline >/dev/null

    run python3 "$PROJECT_ROOT/scripts/cdp/cdp_benchmark.py" \
        --input-json "$current" \
        --output-dir "$OUTPUT_DIR" \
        --branch test-branch

    [ "$status" -eq 0 ]
    [[ "$output" == *"regression=REGRESSION"* ]]
    [[ "$output" == *"health=60"* ]]
}
