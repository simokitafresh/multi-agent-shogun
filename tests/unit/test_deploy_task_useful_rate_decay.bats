#!/usr/bin/env bats
# test_deploy_task_useful_rate_decay.bats - cmd_1564 useful_rate decay

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/useful_rate_decay.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# Helper: run compute_useful_rates and decay logic with given TSV + scored list
run_decay_test() {
    local tsv_file="$1"
    local scored_json="$2"  # JSON array of [score, lid, summary]
    SCRIPT_DIR="$TEST_TMPDIR" python3 - "$tsv_file" "$scored_json" <<'PY'
import csv
import json
import os
import sys

USEFUL_RATE_THRESHOLD = 0.40  # deploy_task.shと同期: NOT_USEFUL退場加速
USEFUL_RATE_DECAY = 0.3       # deploy_task.shと同期: 忍者成長速度改善3

def compute_useful_rates(script_dir):
    impact_path = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    if not os.path.exists(impact_path):
        return {}
    counts = {}
    try:
        with open(impact_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                lid = (row.get('lesson_id') or '').strip()
                action = (row.get('action') or '').strip().lower()
                result = (row.get('result') or '').strip().upper()
                if not lid or action != 'injected' or result == 'PENDING':
                    continue
                if lid not in counts:
                    counts[lid] = [0, 0]
                counts[lid][1] += 1
                ref = (row.get('referenced') or '').strip().lower()
                if ref in ('yes', 'true', '1', 'y'):
                    counts[lid][0] += 1
    except Exception:
        return {}
    return {lid: vals[0] / vals[1] if vals[1] > 0 else 0.0 for lid, vals in counts.items()}

script_dir = os.environ['SCRIPT_DIR']
scored_json = sys.argv[2]
scored = [(s, lid, summ) for s, lid, summ in json.loads(scored_json)]

useful_rates = compute_useful_rates(script_dir)

new_scored = []
for score, lid, summary in scored:
    rate = useful_rates.get(lid)
    if rate is not None and rate < USEFUL_RATE_THRESHOLD:
        new_scored.append((score * USEFUL_RATE_DECAY, lid, summary))
    else:
        new_scored.append((score, lid, summary))
scored = new_scored

for score, lid, summary in scored:
    print(f'{score}\t{lid}\t{summary}')
PY
}

@test "useful_rate >= 40% lessons keep original score" {
    # L001: 20 injections, 8 referenced = 40% useful_rate (at 40% threshold)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'TSV'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-01T00:00:00	cmd_001	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_006	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_007	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_008	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_009	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_010	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_011	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_012	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_013	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_014	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_015	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_016	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_017	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_018	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_019	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_020	hanzo	L001	injected	CLEAR	no	infra	impl	None
TSV

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L001", "test lesson"]]'
    [ "$status" -eq 0 ]
    # 40% useful_rate (8/20) >= 40% threshold → score unchanged (6)
    [[ "${lines[0]}" == 6*L001* ]]
}

@test "useful_rate < 40% lessons get score decayed" {
    # L002: 20 injections, 2 referenced = 10% useful_rate (below threshold)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'TSV'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-01T00:00:00	cmd_001	hanzo	L002	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L002	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_006	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_007	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_008	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_009	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_010	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_011	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_012	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_013	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_014	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_015	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_016	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_017	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_018	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_019	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_020	hanzo	L002	injected	CLEAR	no	infra	impl	None
TSV

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L002", "test lesson"]]'
    [ "$status" -eq 0 ]
    # 10% useful_rate < 40% threshold → score decayed (6 * 0.3 = 1.8)
    [[ "${lines[0]}" == 1.7*L002* ]]
}

@test "mixed: high useful_rate unchanged, low useful_rate decayed" {
    # L001: 10 injections, 4 referenced = 40% (at threshold)
    # L002: 10 injections, 1 referenced = 10% (below threshold)
    # L003: no data in TSV (new lesson, no decay)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'TSV'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-01T00:00:00	cmd_001	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_006	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_007	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_008	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_009	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_010	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_001	hanzo	L002	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_006	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_007	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_008	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_009	hanzo	L002	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_010	hanzo	L002	injected	CLEAR	no	infra	impl	None
TSV

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L001", "high rate"], [6, "L002", "low rate"], [6, "L003", "new lesson"]]'
    [ "$status" -eq 0 ]
    # L001: 40% >= 40% → unchanged (6)
    [[ "${lines[0]}" == 6*L001* ]]
    # L002: 10% < 30% → decayed (6 * 0.3 = 1.8)
    [[ "${lines[1]}" == 1.7*L002* ]]
    # L003: no TSV data → unchanged (6)
    [[ "${lines[2]}" == 6*L003* ]]
}

@test "pending rows are excluded from useful_rate calculation" {
    # L001: 2 resolved (1 ref), 3 pending → only resolved count (useful_rate = 1/2 = 50%)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'TSV'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-01T00:00:00	cmd_001	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L001	injected	pending	pending	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L001	injected	pending	pending	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L001	injected	pending	pending	infra	impl	None
TSV

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L001", "test"]]'
    [ "$status" -eq 0 ]
    # 50% useful_rate >= 40% → unchanged (6)
    [[ "${lines[0]}" == 6*L001* ]]
}

@test "no lesson_impact.tsv file → no decay applied" {
    rm -f "$TEST_TMPDIR/logs/lesson_impact.tsv"

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L001", "test"]]'
    [ "$status" -eq 0 ]
    # No TSV → no decay, score unchanged (6)
    [[ "${lines[0]}" == 6*L001* ]]
}

@test "exactly 40% useful_rate is NOT decayed (boundary)" {
    # L001: 20 injections, 8 referenced = 40% (exactly at threshold, NOT below)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'TSV'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-01T00:00:00	cmd_001	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_002	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_003	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_004	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_005	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_006	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_007	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_008	hanzo	L001	injected	CLEAR	yes	infra	impl	None
2026-03-01T00:00:00	cmd_009	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_010	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_011	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_012	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_013	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_014	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_015	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_016	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_017	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_018	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_019	hanzo	L001	injected	CLEAR	no	infra	impl	None
2026-03-01T00:00:00	cmd_020	hanzo	L001	injected	CLEAR	no	infra	impl	None
TSV

    run run_decay_test "$TEST_TMPDIR/logs/lesson_impact.tsv" '[[6, "L001", "test"]]'
    [ "$status" -eq 0 ]
    # 40% useful_rate (8/20) == threshold → NOT decayed (score stays 6)
    [[ "${lines[0]}" == 6*L001* ]]
}
