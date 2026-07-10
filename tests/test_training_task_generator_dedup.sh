#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/scripts" "$ROOT/queue/training" "$ROOT/queue/tasks" "$ROOT/queue/reports"
cp scripts/training_task_generator.sh "$ROOT/scripts/"
cat > "$ROOT/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$ROOT/scripts/inbox_write.sh"

run() { SHOGUN_REPO_ROOT="$ROOT" bash "$ROOT/scripts/training_task_generator.sh" "$@"; }
count() { find "$ROOT/queue/training" -name '*.yaml' | wc -l; }
base=(--skill report-write --gate gate_report_format --reason 'verdict missing' --streak 2)

run "${base[@]}" --failure-at 2026-07-10T19:50:00+09:00 >/dev/null
[ "$(count)" -eq 1 ] || { echo 'FAIL initial generation'; exit 1; }
first=$(find "$ROOT/queue/training" -name '*.yaml')
cmd=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["task"]["parent_cmd"])' "$first")

out=$(run "${base[@]}" --failure-at 2026-07-10T19:50:00+09:00)
grep -q 'SKIPPED_DUPLICATE: active:' <<<"$out"
[ "$(count)" -eq 1 ] || { echo 'FAIL active duplicate'; exit 1; }

python3 - "$first" <<'PY'
import sys,yaml
p=sys.argv[1]; d=yaml.safe_load(open(p)); d['training_proposal']['status']='deployed'; open(p,'w').write(yaml.safe_dump(d,sort_keys=False))
PY
cat > "$ROOT/queue/reports/report.yaml" <<YAML
parent_cmd: $cmd
status: completed
verdict: PASS
timestamp: 2026-07-10T20:03:00+09:00
YAML
out=$(run "${base[@]}" --failure-at 2026-07-10T19:50:00+09:00)
grep -q 'SKIPPED_DUPLICATE: completed:' <<<"$out"
[ "$(count)" -eq 1 ] || { echo 'FAIL completed duplicate'; exit 1; }

run "${base[@]}" --failure-at 2026-07-10T20:04:00+09:00 >/dev/null
[ "$(count)" -eq 2 ] || { echo 'FAIL new failure'; exit 1; }
run --skill report-write --gate gate_report_format --reason 'binary_checks missing' --streak 2 --failure-at 2026-07-10T20:04:00+09:00 >/dev/null
[ "$(count)" -eq 3 ] || { echo 'FAIL different reason'; exit 1; }
run --skill report-write --gate gate_report_format --reason 'lessons_useful missing' --streak 2 --failure-at 2026-07-10T20:04:00+09:00 >/dev/null
[ "$(count)" -eq 4 ] || { echo 'FAIL different level'; exit 1; }
echo 'PASS 5/5 FAIL0 SKIP0 before=1 after=0'
