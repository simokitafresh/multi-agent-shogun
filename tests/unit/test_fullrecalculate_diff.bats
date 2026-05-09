#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT_PATH="$PROJECT_ROOT/scripts/fullrecalculate.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/fullrecalculate_diff.XXXXXX")"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

extract_diff_python() {
    awk '
        /python3 -u - "\$baseline_file"/ { in_block = 1; next }
        in_block && /^PYEOF$/ { exit }
        in_block { print }
    ' "$SCRIPT_PATH" > "$TEST_TMPDIR/diff.py"
}

@test "diff reports portfolios added after baseline capture" {
    extract_diff_python

    cat > "$TEST_TMPDIR/psycopg2.py" <<'PY'
from datetime import date


class Cursor:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, query, params=None):
        self.query = " ".join(query.split())
        self.params = params

    def fetchone(self):
        if "COUNT(*), MAX(date) FROM signals" in self.query:
            return (3, date(2026, 5, 9))
        if "COUNT(*), MAX(year_month) FROM monthly_returns" in self.query:
            return (2, "2026-05")
        if "COUNT(*) FROM trade_performance WHERE portfolio_id" in self.query:
            return (1,)
        if "COUNT(*) FROM signals" in self.query:
            return (0,)
        if "COUNT(*) FROM monthly_returns" in self.query:
            return (0,)
        if "COUNT(*) FROM portfolio_metrics" in self.query:
            return (0,)
        if "COUNT(*) FROM trade_performance" in self.query:
            return (0,)
        raise AssertionError(f"unexpected fetchone query: {self.query}")

    def fetchall(self):
        if "SELECT id::text, name, type, is_active FROM portfolios" in self.query:
            return [("new-pf", "New PF", "standard", True)]
        raise AssertionError(f"unexpected fetchall query: {self.query}")


class Connection:
    def cursor(self):
        return Cursor()

    def close(self):
        pass


def connect(database_url):
    assert database_url == "postgresql://example/db"
    return Connection()
PY
    cat > "$TEST_TMPDIR/baseline.json" <<'JSON'
{
  "timestamp": "2026-05-09T00:00:00",
  "portfolios": {},
  "total_signals": 0,
  "total_monthly_returns": 0,
  "total_metrics": 0,
  "total_trade_performance": 0
}
JSON

    run env PYTHONPATH="$TEST_TMPDIR" DATABASE_URL="postgresql://example/db" \
        python3 "$TEST_TMPDIR/diff.py" "$TEST_TMPDIR/baseline.json"

    [ "$status" -eq 0 ]
    [[ "$output" == *"--- Portfolio Changes: 1/1 portfolios changed ---"* ]]
    [[ "$output" == *"--- New Portfolios ---"* ]]
    [[ "$output" == *"New PF (standard, active=True): signals=3"* ]]
    [[ "$output" == *"RESULT: 1 portfolios changed (100.0%), max global count delta = 0"* ]]
}
