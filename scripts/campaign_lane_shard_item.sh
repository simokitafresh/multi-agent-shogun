#!/usr/bin/env bash
set -uo pipefail

# campaign_lane_shard_item.sh — universal shard と忍者 lifecycle の bridge。
# deploy の終了は配備完了に過ぎない。report YAML の終端 PASS だけを shard success にする。

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="${CAMPAIGN_LANE_SOURCE_REPO:-$ROOT}"
FIXED_SHA="${CAMPAIGN_LANE_FIXED_SHA:-9192bf61ada7bb3c44ceecf5cf86599df0b8ec81}"
WAIT_SEC="${CAMPAIGN_LANE_WAIT_SEC:-1800}"
POLL_SEC="${CAMPAIGN_LANE_POLL_SEC:-2}"

item_id="${1:-}"
item_path="${2:-}"
worker_id="${3:-}"
workdir="${4:-}"
output_dir="${5:-}"
result_path="${output_dir:-/nonexistent}/result.json"
started_epoch="$(date +%s)"
declare -A stage_started stage_duration

stage_start() { stage_started["$1"]="$(date +%s)"; }
stage_stop() {
    local name="$1" now
    now="$(date +%s)"
    stage_duration["$name"]=$(( now - ${stage_started[$name]:-$now} ))
}

write_result() {
    local status="$1" reason="$2" report_path="${3:-}" commit_sha="${4:-}"
    local files_json="${5:-[]}" test_count="${6:-0}" fail_count="${7:-1}" skip_count="${8:-0}"
    mkdir -p "$output_dir" 2>/dev/null || true
    RESULT_STATUS="$status" RESULT_REASON="$reason" RESULT_REPORT="$report_path" \
      RESULT_COMMIT="$commit_sha" RESULT_PATH="$result_path" RESULT_ITEM="$item_id" \
      RESULT_WORKER="$worker_id" RESULT_STARTED="$started_epoch" RESULT_FIXED_SHA="$FIXED_SHA" \
      RESULT_FILES="$files_json" RESULT_TESTS="$test_count" RESULT_FAIL="$fail_count" RESULT_SKIP="$skip_count" \
      RESULT_STAGES="${stage_duration_json:-}" RESULT_ESTIMATED_SEC="${estimated_sec:-600}" python3 - <<'PY'
import json, os, time
payload = {
    "item_id": os.environ["RESULT_ITEM"],
    "worker_id": os.environ["RESULT_WORKER"],
    "status": os.environ["RESULT_STATUS"],
    "reason_code": os.environ["RESULT_REASON"],
    "fixed_sha": os.environ["RESULT_FIXED_SHA"],
    "commit_sha": os.environ["RESULT_COMMIT"],
    "files": json.loads(os.environ["RESULT_FILES"]),
    "test_count": int(os.environ["RESULT_TESTS"]),
    "fail_count": int(os.environ["RESULT_FAIL"]),
    "skip_count": int(os.environ["RESULT_SKIP"]),
    "report_path": os.environ["RESULT_REPORT"],
    "elapsed_sec": max(0, int(time.time()) - int(os.environ["RESULT_STARTED"])),
    "stage_duration_sec": json.loads(os.environ["RESULT_STAGES"] or "{}"),
}
payload["estimated_sec"] = int(os.environ["RESULT_ESTIMATED_SEC"])
payload["estimated_exceeded"] = payload["elapsed_sec"] > payload["estimated_sec"]
path = os.environ["RESULT_PATH"]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, path)
PY
}

fail() {
    write_result fail "$1" "${2:-}" "${3:-}"
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

if [[ -z "$item_id" || -z "$item_path" || -z "$worker_id" || -z "$workdir" || -z "$output_dir" ]]; then
    printf 'Usage: %s item_id item_path worker_id workdir output_dir\n' "$0" >&2
    exit 2
fi
case "$item_path" in
    /*|../*|*/../*|*/..|.|..) fail invalid_item_path ;;
esac
item_top="${item_path%%/*}"
if [[ "$item_top" == "$item_path" || ! -d "$SOURCE_REPO/$item_top" ]]; then
    fail invalid_item_path
fi
item_contract_json="$(SHARD_ITEM_JSON="${SHARD_ITEM_JSON:-}" ITEM_PATH="$item_path" WORKDIR="$workdir" SOURCE_REPO="$SOURCE_REPO" python3 - 2>/dev/null <<'PY'
import json, os
item = json.loads(os.environ["SHARD_ITEM_JSON"])
paths = item.get("owned_paths")
if not isinstance(paths, list) or len(paths) != 2 or len(paths) != len(set(paths)) or os.environ["ITEM_PATH"] not in paths:
    raise SystemExit(2)
root = os.path.realpath(os.environ["SOURCE_REPO"])
# Ownership is expressed through the durable logical workdir.  The checkout
# may be materialized behind that path on ext4 after this contract is parsed.
work = os.path.abspath(os.environ["WORKDIR"])
out = []
for value in paths:
    if not isinstance(value, str) or not value or os.path.isabs(value) or value in {".", ".."} or value.startswith("../") or "/../" in value or value.endswith("/.."):
        raise SystemExit(2)
    top = value.split("/", 1)[0]
    if not os.path.isdir(os.path.join(root, top)):
        raise SystemExit(2)
    absolute = os.path.abspath(os.path.join(work, value))
    if os.path.commonpath([work, absolute]) != work:
        raise SystemExit(1)
    out.append(absolute)
read_only = item.get("read_only_paths")
if not isinstance(read_only, list) or not read_only or len(read_only) != len(set(read_only)):
    raise SystemExit(3)
for value in read_only:
    if not isinstance(value, str) or not value or os.path.isabs(value) or value in {".", ".."} or value.startswith("../") or "/../" in value or value.endswith("/.."):
        raise SystemExit(3)
    if value in paths:
        raise SystemExit(3)
test_command = item.get("test_command")
fingerprint = item.get("contract_fingerprint")
purpose = item.get("purpose")
description = item.get("description")
if not isinstance(purpose, str) or not purpose.strip() or not isinstance(description, str) or not description.strip():
    raise SystemExit(3)
if not isinstance(test_command, str) or not test_command.strip() or not isinstance(fingerprint, str) or len(fingerprint) != 64 or any(c not in "0123456789abcdef" for c in fingerprint):
    raise SystemExit(3)
print(json.dumps({"owned": out, "read_only": read_only, "test_command": test_command, "fingerprint": fingerprint, "purpose": purpose, "description": description}, separators=(",", ":")))
PY
)"
contract_parse_rc=$?
if (( contract_parse_rc != 0 )); then
    (( contract_parse_rc == 2 )) && fail invalid_owned_paths
    fail invalid_item_contract
fi
owned_abs_json="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.dumps(json.loads(os.environ["ITEM_CONTRACT_JSON"])["owned"], separators=(",",":")))')"
if ! [[ "$WAIT_SEC" =~ ^[0-9]+$ ]] || (( WAIT_SEC < 1 )); then
    fail invalid_timeout
fi
if [[ ! "$FIXED_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    fail invalid_fixed_sha
fi
mkdir -p "$output_dir" || exit 1

retry_failed=0
if [[ -f "$result_path" ]] && python3 - "$result_path" <<'PY' 2>/dev/null
import json, sys
raise SystemExit(0 if json.load(open(sys.argv[1], encoding="utf-8")).get("status") == "fail" else 1)
PY
then
    retry_failed=1
fi

# Each retry is a new immutable attempt.  The coordinator-facing result.json
# remains the latest SSOT, while the previous result/report/task evidence is
# retained under attempts/ before a new deploy can observe it.
attempt=1
if (( retry_failed )); then
    attempts_dir="$output_dir/attempts"
    mkdir -p "$attempts_dir" || fail attempt_archive_failed
    attempt=$(( $(find "$attempts_dir" -mindepth 1 -maxdepth 1 -type d -name 'attempt-*' 2>/dev/null | wc -l) + 2 ))
    previous_dir="$(printf '%s/attempt-%03d' "$attempts_dir" $((attempt - 1)))"
    mkdir -p "$previous_dir" || fail attempt_archive_failed
    for evidence in result.json task.yaml report.yaml; do
        [[ -f "$output_dir/$evidence" ]] && cp -p "$output_dir/$evidence" "$previous_dir/$evidence"
    done
fi

# A retry may be launched with the failed workdir as the coordinator's cwd.
# Quarantining that directory while it is our cwd leaves later Python imports
# attached to the renamed DrvFs inode (Errno 95).  Move control execution to
# the immutable coordinator root before materialize can rename the workdir.
cd "$ROOT" || fail coordinator_cwd_unavailable

# universal_shard creates workdir beforehand. materialize accepts an existing empty dir.
stage_start materialize
if ! CAMPAIGN_ROOT="$ROOT" CAMPAIGN_SOURCE="$SOURCE_REPO" CAMPAIGN_WORKDIR="$workdir" CAMPAIGN_SHA="$FIXED_SHA" CAMPAIGN_RETRY_FAILED="$retry_failed" python3 - <<'PY'
import os, sys
from pathlib import Path
root = Path(os.environ["CAMPAIGN_ROOT"])
sys.path.insert(0, str(root / "skills/campaign-lane"))
from scripts.materialize import materialize
materialize(
    os.environ["CAMPAIGN_SOURCE"],
    os.environ["CAMPAIGN_WORKDIR"],
    os.environ["CAMPAIGN_SHA"],
    os.environ.get("CAMPAIGN_LANE_CHECKOUT_ROOT", "/tmp/multi-agent-shogun-campaign-checkouts"),
    retry_failed=os.environ.get("CAMPAIGN_RETRY_FAILED") == "1",
)
PY
then
    fail source_materialize_failed
fi
stage_stop materialize

observed_sha="$(git -C "$workdir" rev-parse HEAD 2>/dev/null || true)"
[[ "$observed_sha" == "$FIXED_SHA" ]] || fail wrong_sha
[[ -z "$(git -C "$workdir" status --porcelain 2>/dev/null)" ]] || fail dirty_worktree
if ! ITEM_CONTRACT_JSON="$item_contract_json" WORKDIR="$workdir" python3 - <<'PY'
import json, os
item = json.loads(os.environ["ITEM_CONTRACT_JSON"])
work = os.path.realpath(os.environ["WORKDIR"])
for value in item["read_only"]:
    path = os.path.realpath(os.path.join(work, value))
    if os.path.commonpath([work, path]) != work or not os.path.isfile(path):
        raise SystemExit(1)
PY
then
    fail read_only_path_missing
fi
observed_fingerprint="$(PYTHONDONTWRITEBYTECODE=1 CAMPAIGN_WORKDIR="$workdir" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["CAMPAIGN_WORKDIR"], "skills/campaign-lane"))
from scripts.contracts import contract_fingerprint
print(contract_fingerprint())
PY
)" || fail contract_fingerprint_unavailable
expected_fingerprint="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.loads(os.environ["ITEM_CONTRACT_JSON"])["fingerprint"])')"
[[ "$expected_fingerprint" =~ ^[0-9a-f]{64}$ && "$observed_fingerprint" == "$expected_fingerprint" ]] || fail contract_fingerprint_mismatch
task_path="$output_dir/task.yaml"
report_path="${CAMPAIGN_LANE_REPORT_PATH:-$output_dir/report.yaml}"
cp "$ROOT/templates/campaign_lane_shard_task.yaml" "$task_path" || fail task_template_copy_failed
field_set="$ROOT/scripts/lib/yaml_field_set.sh"
task_key="campaign_lane_${item_id}_attempt_${attempt}"
read_only_json="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.dumps(json.loads(os.environ["ITEM_CONTRACT_JSON"])["read_only"], separators=(",",":")))')"
test_command="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.loads(os.environ["ITEM_CONTRACT_JSON"])["test_command"])')"
item_purpose="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.loads(os.environ["ITEM_CONTRACT_JSON"])["purpose"])')"
item_description="$(ITEM_CONTRACT_JSON="$item_contract_json" python3 -c 'import json,os; print(json.loads(os.environ["ITEM_CONTRACT_JSON"])["description"])')"
test_path="$(OWNED_ABS_JSON="$owned_abs_json" ITEM_ABS="$workdir/$item_path" python3 - <<'PY'
import json, os
print(next(path for path in json.loads(os.environ["OWNED_ABS_JSON"]) if path != os.path.abspath(os.environ["ITEM_ABS"])))
PY
)" || fail invalid_owned_paths
# One lock/parse/atomic replace for the generated task.  The former 19 CLI
# invocations dominated the 28-case fixture and multiplied YAML subprocesses.
if ! source "$field_set"; then
    fail task_yaml_write_failed
fi
# yaml_field_set_batch's generic verifier starts one YAML parser per field.
# This task has a fixed schema, so defer those scalar checks and verify the
# complete generated task in one parse immediately after the atomic write.
_yaml_field_set_verify_parsed() { return 0; }
if ! yaml_field_set_batch "$task_path" task \
    "task_id=$task_key" \
    "_ac_task_id=$task_key" \
    "parent_cmd=$task_key" \
    "cmd_id=$task_key" \
    "task_type=full" \
    "project=infra" \
    "assigned_to=$worker_id" \
    "status=assigned" \
    "purpose=$item_purpose" \
    "description=${item_description} ${workdir}内だけを編集・commitし、owned path外diff 0を確認する。owned_paths_json/read_only_paths_jsonはcanonical JSON listとしてparseする。報告operational_simulation.actualへ厳密形式 TOTAL=N FAIL=0 SKIP=0、resultへPASSを記録する" \
    "target_path=$workdir/$item_path" \
    "owned_paths_json=$owned_abs_json" \
    "contract_fingerprint=$expected_fingerprint" \
    "read_only_paths_json=$read_only_json" \
    "test_command=$test_command" \
    "implementation_path=$workdir/$item_path" \
    "test_path=$test_path" \
    "workdir=$workdir" \
    "fixed_sha=$FIXED_SHA" \
    "report_path=$report_path" \
    "report_filename=$(basename "$report_path")" \
    "estimated_minutes=10" \
    "campaign_attempt=$attempt" \
    "canonical_root=${SHOGUN_ROOT:-$ROOT}"
then
    fail task_yaml_write_failed
fi
if ! TASK_PATH="$task_path" TASK_KEY="$task_key" WORKER_ID="$worker_id" \
    WORKDIR="$workdir" ITEM_PATH="$item_path" OWNED_JSON="$owned_abs_json" \
    FINGERPRINT="$expected_fingerprint" READ_ONLY_JSON="$read_only_json" \
    TEST_COMMAND="$test_command" TEST_PATH="$test_path" FIXED_SHA_ENV="$FIXED_SHA" \
    REPORT_PATH_ENV="$report_path" ATTEMPT_ENV="$attempt" CANONICAL_ROOT="${SHOGUN_ROOT:-$ROOT}" \
    python3 - <<'PY'
import json, os, yaml
t = (yaml.safe_load(open(os.environ["TASK_PATH"], encoding="utf-8")) or {}).get("task") or {}
key = os.environ["TASK_KEY"]
expected = {
    "task_id": key, "_ac_task_id": key, "parent_cmd": key, "cmd_id": key,
    "task_type": "full", "project": "infra", "assigned_to": os.environ["WORKER_ID"],
    "status": "assigned", "target_path": os.path.join(os.environ["WORKDIR"], os.environ["ITEM_PATH"]),
    "owned_paths_json": os.environ["OWNED_JSON"], "contract_fingerprint": os.environ["FINGERPRINT"],
    "read_only_paths_json": os.environ["READ_ONLY_JSON"], "test_command": os.environ["TEST_COMMAND"],
    "implementation_path": os.path.join(os.environ["WORKDIR"], os.environ["ITEM_PATH"]),
    "test_path": os.environ["TEST_PATH"], "workdir": os.environ["WORKDIR"],
    "fixed_sha": os.environ["FIXED_SHA_ENV"], "report_path": os.environ["REPORT_PATH_ENV"],
    "report_filename": os.path.basename(os.environ["REPORT_PATH_ENV"]),
    "estimated_minutes": 10, "campaign_attempt": int(os.environ["ATTEMPT_ENV"]),
    "canonical_root": os.environ["CANONICAL_ROOT"],
}
if any(t.get(field) != value for field, value in expected.items()):
    raise SystemExit(1)
PY
then
    fail task_yaml_write_failed
fi

deploy_cmd="${CAMPAIGN_LANE_DEPLOY_CMD:-bash $ROOT/scripts/deploy_task.sh --yaml}"
stage_start deploy
if ! SHOGUN_ROOT="${SHOGUN_ROOT:-$ROOT}" bash -c 'exec "$@"' _ $deploy_cmd "$task_path" "$worker_id"; then
    fail deploy_failed "$report_path"
fi
stage_stop deploy

# deploy_task owns the durable ninja report naming contract and may rewrite
# task.report_path from the campaign-local placeholder to queue/reports/....
# Resolve that canonical path after deployment; otherwise a successful shard
# can sit for the full timeout while this bridge watches the stale placeholder.
durable_task_path="${CAMPAIGN_LANE_DURABLE_TASK_PATH:-$ROOT/queue/tasks/${worker_id}.yaml}"
canonical_report_path="$(CAMPAIGN_ROOT="$ROOT" TASK_KEY="$task_key" python3 - "$durable_task_path" <<'PY' 2>/dev/null
import os, sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task") or {}
if task.get("parent_cmd") != os.environ["TASK_KEY"]:
    raise SystemExit(1)
path = task.get("report_path")
if not isinstance(path, str) or not path.strip():
    raise SystemExit(1)
print(path if os.path.isabs(path) else os.path.join(os.environ["CAMPAIGN_ROOT"], path))
PY
)" || fail canonical_report_path_missing "$report_path"
report_path="$canonical_report_path"

deadline=$(( $(date +%s) + WAIT_SEC ))
stage_start report_wait
while (( $(date +%s) < deadline )); do
    if [[ -f "$report_path" ]]; then
        terminal="$(OWNED_ABS_JSON="$owned_abs_json" WORKDIR="$workdir" FIXED_SHA="$FIXED_SHA" python3 - "$report_path" <<'PY' 2>/dev/null || true
import json, os, re, subprocess, sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
status = str(data.get("status") or "").lower()
verdict = str(data.get("verdict") or "").upper()
summary = data.get("result") or {}
commit_sha = str(data.get("commit_hash") or (summary.get("commit_sha") if isinstance(summary, dict) else "") or "")
files = data.get("files_modified") or []
files = [x.get("path", "") if isinstance(x, dict) else str(x) for x in files]
owned = {os.path.realpath(path) for path in json.loads(os.environ["OWNED_ABS_JSON"])}
workdir = os.environ["WORKDIR"]
reported_abs = {os.path.realpath(x if os.path.isabs(x) else os.path.join(workdir, x)) for x in files}
head = subprocess.run(["git", "-C", workdir, "rev-parse", "HEAD"], text=True, capture_output=True).stdout.strip()
dirty = subprocess.run(["git", "-C", workdir, "status", "--porcelain"], text=True, capture_output=True).stdout.strip()
diff = subprocess.run(["git", "-C", workdir, "diff", "--name-only", os.environ["FIXED_SHA"] + "..HEAD"], text=True, capture_output=True).stdout.splitlines()
diff_abs = {os.path.realpath(os.path.join(workdir, path)) for path in diff}
commit_ok = bool(re.fullmatch(r"[0-9a-f]{40}", commit_sha)) and commit_sha == head
scope_ok = not dirty and diff_abs == owned and reported_abs == owned
simulation = data.get("operational_simulation") or {}
actual = str(simulation.get("actual") or "") if isinstance(simulation, dict) else ""
sim_result = str(simulation.get("result") or "").upper() if isinstance(simulation, dict) else ""
match = re.fullmatch(r"TOTAL=([1-9][0-9]*) FAIL=([0-9]+) SKIP=([0-9]+)", actual)
tests, fails, skips = (map(int, match.groups()) if match else (None, None, None))
extra = "|".join([commit_sha, json.dumps(files, separators=(",", ":")), str(tests or 0), str(fails or 0), str(skips or 0)])
if status in {"failed", "revision_requested"} or verdict == "FAIL":
    print("FAIL|report_terminal_fail|" + extra)
elif status in {"completed", "done"} and verdict == "PASS" and not (
    sim_result == "PASS" and tests is not None and fails == 0 and skips == 0
):
    print("FAIL|report_metrics_missing|" + extra)
elif status in {"completed", "done"} and verdict == "PASS" and not commit_ok:
    print("FAIL|terminal_commit_mismatch|" + extra)
elif status in {"completed", "done"} and verdict == "PASS" and not scope_ok:
    print("FAIL|terminal_scope_mismatch|" + extra)
elif status in {"completed", "done"} and verdict == "PASS" and sim_result == "PASS" and tests is not None and fails == 0 and skips == 0:
    print("PASS|report_terminal_pass|" + extra)
PY
)"
        if [[ "$terminal" == PASS\|* ]]; then
            IFS='|' read -r _ reason commit_sha files_json test_count fail_count skip_count <<<"$terminal"
            stage_stop report_wait
            stage_duration_json="$(MATERIALIZE="${stage_duration[materialize]:-0}" DEPLOY="${stage_duration[deploy]:-0}" REPORT_WAIT="${stage_duration[report_wait]:-0}" python3 - "$report_path" <<'PY'
import json, os, sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
reported = data.get("stage_duration_sec") or {}
payload = {"materialize": int(os.environ["MATERIALIZE"]), "deploy": int(os.environ["DEPLOY"]), "report_wait": int(os.environ["REPORT_WAIT"])}
for name in ("test", "commit"):
    payload[name] = int(reported.get(name, 0))
print(json.dumps(payload, separators=(",", ":")))
PY
)"
            write_result success "$reason" "$report_path" "$commit_sha" "$files_json" "$test_count" "$fail_count" "$skip_count"
            exit 0
        elif [[ "$terminal" == FAIL\|* ]]; then
            IFS='|' read -r _ reason commit_sha files_json test_count fail_count skip_count <<<"$terminal"
            write_result fail "$reason" "$report_path" "$commit_sha" "$files_json" "$test_count" "${fail_count:-1}" "$skip_count"
            printf 'FAIL: %s\n' "$reason" >&2
            exit 1
        fi
    fi
    sleep "$POLL_SEC"
done

fail report_timeout "$report_path"
