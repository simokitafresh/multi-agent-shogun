#!/usr/bin/env bash
# run_consumer_focused.sh — T5 AC12 consumer-by-consumer focused runner.
#
# The task selector operates in this repository, while one CDP consumer lives
# in the external auto-ops repository.  Keep ownership and the command used
# for each check explicit so a cross-repository selection cannot disappear
# silently.  This runner performs read-only inspections or fixture-mode
# entrypoint checks; it never runs a production browser or business workflow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly AUTO_OPS_ROOT="${AUTO_OPS_ROOT:-/mnt/c/Python_app/auto-ops}"

usage() {
    cat >&2 <<'USAGE'
Usage: bash scripts/cdp/run_consumer_focused.sh [--evidence PATH]

Run the ten T5 AC12 consumers individually and emit one JSONL result per
consumer.  PATH is written atomically and defaults to a file under /tmp.
USAGE
}

evidence_path="${CDP_CONSUMER_EVIDENCE:-/tmp/cdp-ac12-consumer-evidence.$$.jsonl}"
while (($#)); do
    case "$1" in
        --evidence)
            (($# >= 2)) || { echo "ERROR: --evidence requires a path" >&2; exit 2; }
            evidence_path="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

evidence_dir="${evidence_path%/*}"
if [[ "$evidence_dir" == "$evidence_path" ]]; then
    evidence_dir="."
fi
mkdir -p "$evidence_dir"
tmp_evidence="$(mktemp "${evidence_path}.tmp.XXXXXX")"
cleanup_tmp() { rm -f "$tmp_evidence"; }
trap cleanup_tmp EXIT

emit_result() {
    local consumer="$1" repo_root="$2" target="$3" command="$4" result="$5" rc="$6" detail="$7"
    python3 - "$consumer" "$repo_root" "$target" "$command" "$result" "$rc" "$detail" >>"$tmp_evidence" <<'PY'
import json
import sys

consumer, repo_root, target, command, result, rc, detail = sys.argv[1:]
print(json.dumps({
    "schema": "t5-ac12-consumer-result-v1",
    "consumer": consumer,
    "repo_root": repo_root,
    "target": target,
    "command": command,
    "result": result,
    "rc": int(rc),
    "skip": False,
    "detail": detail,
}, ensure_ascii=False, sort_keys=True))
PY
}

run_readonly_source_check() {
    local target="$1"
    python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "receipt" not in text:
    raise SystemExit("focused contract inspection: receipt marker missing")
forbidden = ("preflight_cdp_flow", "cleanup_chrome", "--remote-debugging-port")
bad = [token for token in forbidden if token in text]
if bad:
    raise SystemExit("focused contract inspection: forbidden direct-launch marker: " + ",".join(bad))
print("receipt=present direct_launch=0")
PY
}

run_python_syntax_check() {
    local target="$1"
    python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
print("syntax=valid bytecode_write=0")
PY
}

run_fixture_entrypoint() {
    local entrypoint="$1" expected_consumer="$2" expected_port="$3"
    local fixture_dir establisher output
    fixture_dir="$(mktemp -d /tmp/cdp-ac12-fixture.XXXXXX)"
    establisher="${fixture_dir}/establish"
    # The generated establisher receives the receipt path from the entrypoint.
    # It writes only to this isolated temporary fixture directory.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'consumer=""; port=""; receipt=""' \
        'while (($#)); do case "$1" in --consumer) consumer="$2"; shift 2;; --ports) port="$2"; shift 2;; --receipt) receipt="$2"; shift 2;; *) shift;; esac; done' \
        'printf '\''{"receipt_id":"fixture","issuer":"cdp_session_foundation","consumer":"%s","issued_at":0,"expires_at":9999999999,"endpoint":"http://127.0.0.1:%s","chrome_pid":null,"profile_path":"","capabilities":{},"owned":false}\n'\'' "$consumer" "$port" > "$receipt"' \
        >"$establisher"
    chmod +x "$establisher"

    if [[ "$expected_consumer" == "measurement" ]]; then
        output="$(CDP_CONSUMER_FIXTURE_ONLY=1 CDP_SESSION_ESTABLISHER="$establisher" \
            bash "$entrypoint" ac12_fixture --baseline fixture.json)"
    else
        local markdown="${fixture_dir}/article.md"
        printf '%s\n' '# fixture' >"$markdown"
        output="$(CDP_CONSUMER_FIXTURE_ONLY=1 CDP_SESSION_ESTABLISHER="$establisher" \
            CDP_PORT="$expected_port" bash "$entrypoint" "$markdown")"
    fi
    [[ "$output" == *"consumer=${expected_consumer}"* ]] || {
        echo "fixture consumer mismatch: $output" >&2
        return 1
    }
    [[ "$output" == *"port=${expected_port}"* ]] || {
        echo "fixture port mismatch: $output" >&2
        return 1
    }
    rm -f "$fixture_dir"/*
    rmdir "$fixture_dir"
    printf 'fixture_consumer=%s port=%s\n' "$expected_consumer" "$expected_port"
}

run_one() {
    local consumer="$1" repo_root="$2" target="$3" mode="$4" command output rc
    local absolute_target="${repo_root}/${target}"
    [[ -d "$repo_root" ]] || {
        emit_result "$consumer" "$repo_root" "$target" "path check" FAIL 1 "repo_root_missing"
        return 1
    }
    [[ -f "$absolute_target" ]] || {
        emit_result "$consumer" "$repo_root" "$target" "path check" FAIL 1 "target_missing"
        return 1
    }

    case "$mode" in
        source)
            command="python3 focused receipt inspection ${target}"
            if output="$(run_readonly_source_check "$absolute_target" 2>&1)"; then
                emit_result "$consumer" "$repo_root" "$target" "$command" PASS 0 "$output"
                return 0
            fi
            rc=$?
            emit_result "$consumer" "$repo_root" "$target" "$command" FAIL "$rc" "$output"
            return 1
            ;;
        measurement)
            command="CDP_CONSUMER_FIXTURE_ONLY=1 bash scripts/cdp/cdp_measure.sh ac12_fixture --baseline fixture.json"
            if output="$(run_fixture_entrypoint "$absolute_target" measurement 9222)"; then
                emit_result "$consumer" "$repo_root" "$target" "$command" PASS 0 "$output"
                return 0
            fi
            rc=$?
            emit_result "$consumer" "$repo_root" "$target" "$command" FAIL "$rc" "$output"
            return 1
            ;;
        note)
            command="CDP_CONSUMER_FIXTURE_ONLY=1 CDP_PORT=9234 bash scripts/note_draft.sh <fixture.md>"
            if output="$(run_fixture_entrypoint "$absolute_target" note 9234)"; then
                emit_result "$consumer" "$repo_root" "$target" "$command" PASS 0 "$output"
                return 0
            fi
            rc=$?
            emit_result "$consumer" "$repo_root" "$target" "$command" FAIL "$rc" "$output"
            return 1
            ;;
        syntax)
            command="PYTHONDONTWRITEBYTECODE=1 python3 compile(${target})"
            if output="$(run_python_syntax_check "$absolute_target" 2>&1)"; then
                emit_result "$consumer" "$repo_root" "$target" "$command" PASS 0 "$output"
                return 0
            fi
            rc=$?
            emit_result "$consumer" "$repo_root" "$target" "$command" FAIL "$rc" "$output"
            return 1
            ;;
        *)
            emit_result "$consumer" "$repo_root" "$target" "unknown mode" FAIL 2 "unknown_mode=${mode}"
            return 1
            ;;
    esac
}

failures=0
run_one cdp_server "$REPO_ROOT" scripts/cdp/cdp_server.py source || failures=$((failures + 1))
run_one cdp_tier_probe "$REPO_ROOT" scripts/cdp/cdp_tier_probe.py source || failures=$((failures + 1))
run_one cdp_maxdisplay_probe "$REPO_ROOT" scripts/cdp/cdp_maxdisplay_probe.py source || failures=$((failures + 1))
run_one cdp_font_probe "$REPO_ROOT" scripts/cdp/cdp_font_probe.py source || failures=$((failures + 1))
run_one cdp_ed_probe "$REPO_ROOT" scripts/cdp/cdp_ed_probe.py source || failures=$((failures + 1))
run_one cdp_contrast_probe "$REPO_ROOT" scripts/cdp/cdp_contrast_probe.py source || failures=$((failures + 1))
run_one cdp_card_probe "$REPO_ROOT" scripts/cdp/cdp_card_probe.py source || failures=$((failures + 1))
run_one cdp_measure "$REPO_ROOT" scripts/cdp/cdp_measure.sh measurement || failures=$((failures + 1))
run_one note_draft "$REPO_ROOT" scripts/note_draft.sh note || failures=$((failures + 1))
run_one perf_measure "$AUTO_OPS_ROOT" workflows/perf_measure.py syntax || failures=$((failures + 1))

mv -f "$tmp_evidence" "$evidence_path"
trap - EXIT
count="$(wc -l <"$evidence_path")"
read -r pass_count fail_count < <(python3 - "$evidence_path" <<'PY'
import json
import sys

passes = failures = 0
for line in open(sys.argv[1], encoding="utf-8"):
    result = json.loads(line)["result"]
    if result == "PASS":
        passes += 1
    elif result == "FAIL":
        failures += 1
print(passes, failures)
PY
)
printf 'evidence=%s consumers=%s pass=%s fail=%s skip=0 selection_true_positive=%s selection_false_positive=0\n' \
    "$evidence_path" "$count" "$pass_count" "$fail_count" "$pass_count"
[[ "$count" -eq 10 && "$pass_count" -eq 10 && "$fail_count" -eq 0 && "$failures" -eq 0 ]]
