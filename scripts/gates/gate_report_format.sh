#!/bin/bash
# semantic-links: [[gate迂回防止]], [[忍者報告品質プロトコル]]
# gate_report_format.sh — 忍者報告YAMLのフォーマット検証
# 目的: 家老の手動フォーマット修正作業を根絶（karo_workarounds 5件連続同一問題）
# 知性の外部化原則: 正しいフォーマットを忍者の記憶に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_report_format.sh <report_yaml_path>
# Exit: 0=PASS, 1=FAIL(修正必要)

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "FAIL: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

_gate_mono_ms() {
    local _up _whole _frac
    read -r _up _ </proc/uptime
    _whole="${_up%%.*}"
    _frac="${_up#*.}000"; _frac="${_frac:0:3}"
    printf '%s\n' "$((10#${_whole} * 1000 + 10#${_frac}))"
}
_GATE_MONO_START_MS="$(_gate_mono_ms)"
_GATE_RECEIPT="${GATE_PHASE_RECEIPT:-}"
_gate_receipt_phase() {
    [ -n "$_GATE_RECEIPT" ] || return 0
    local _phase="$1" _started="$2" _now _wall _fp
    _now="$(_gate_mono_ms)"
    _wall=$((_now - _started))
    _fp="$(sha256sum "$REPORT_PATH" 2>/dev/null | awk '{print $1}')"
    printf '%s\twall_ms=%s\tcaller=%s\towner_pid=%s\tfingerprint=%s\n' \
        "$_phase" "$_wall" "${GATE_CALLER:-gate_report_format}" "${GATE_OWNER_PID:-$$}" "${_fp:-missing}" >>"$_GATE_RECEIPT"
}

_GATE_FP_CACHE="${GATE_FINGERPRINT_CACHE_FILE:-${REPORT_PATH}.validated_fingerprints}"

# Materialize the stable lock path even when a validated generation can return
# before flock. Reusers must not wait for the active leader, but callers and
# diagnostics may rely on the per-report lock artifact existing.
_GATE_SINGLEFLIGHT_LOCK="${REPORT_PATH}.gate.lock"
: >>"$_GATE_SINGLEFLIGHT_LOCK"
# cmd_karo_hotfix_throughput_t3b_fingerprint_hit_corrected_20260728:
# fingerprintキャッシュのhit/miss計装。既存台帳(logs/defense_overhead.jsonl)へ1回限りの
# 非加算行を追加するのみで、判定結果・stdout/stderr・exit code・fingerprint契約は変更しない。
# GATE_VALIDATED_FINGERPRINT未設定(呼出元がreuseを試みていない)の場合は分母に含めない
# (重複検査の実効抑止率はreuse試行時のhit/missでのみ意味を持つ)。
_gate_fp_instrument() {
    local _check_id="$1" _started="$2" _lib _ms
    _lib="$(dirname "${BASH_SOURCE[0]}")/../lib/defense_overhead_writer.sh"
    [ -f "$_lib" ] || return 0
    # shellcheck source=/dev/null
    . "$_lib" 2>/dev/null || return 0
    _ms=$(( $(_gate_mono_ms) - _started ))
    defense_overhead_write_async gate_report_format "$_check_id" "$_ms" PASS \
        "gate_report_format:${_check_id}:$$:${_started}" || true
}

_gate_try_fingerprint_reuse() {
    [ -n "${GATE_VALIDATED_FINGERPRINT:-}" ] || return 1
    _gate_current_fingerprint="$(sha256sum "$REPORT_PATH" | awk '{print $1}')"
    if [ "$_gate_current_fingerprint" = "$GATE_VALIDATED_FINGERPRINT" ] &&
       [ -f "$_GATE_FP_CACHE" ] && grep -qxF "$GATE_VALIDATED_FINGERPRINT" "$_GATE_FP_CACHE"; then
        _gate_receipt_phase fingerprint_reuse "$_GATE_MONO_START_MS"
        _gate_fp_instrument fingerprint_hit "$_GATE_MONO_START_MS"
        echo "PASS (fingerprint reuse)"
        return 0
    fi
    return 1
}

if _gate_try_fingerprint_reuse; then
    exit 0
fi
if [ -n "${GATE_VALIDATED_FINGERPRINT:-}" ]; then
    _gate_fp_instrument fingerprint_miss "$_GATE_MONO_START_MS"
fi

# One report has one validation leader. Concurrent callers join before cache
# inspection instead of launching duplicate autofix/git processes.
_GATE_WAIT_STARTED="$(_gate_mono_ms)"
if [ "${GATE_SINGLEFLIGHT_OWNER:-0}" != "1" ]; then
    exec 199>"$_GATE_SINGLEFLIGHT_LOCK"
    # cmd_karo_hotfix_singleflight_fail_misattribution_20260725:
    # AC3: 待ち上限を実測ロック保持時間(inbox_write phase実測max 45,700ms)に
    # 安全マージンを載せた60秒へ引上げ(旧30秒では保持側の最大実測値を82.7%しかカバーできず
    # 並行2呼出しで確定的にtimeoutしていた)。チェック内容は一切削除・緩和していない。
    # AC1: timeoutは品質FAIL(exit 1, "FAIL:"接頭辞)と機械的に区別できるよう、
    # 専用exit code(2)+専用接頭辞(INFRA_TIMEOUT:)で報告する。呼出元は文字列prefixではなく
    # 終了コードで判定せよ(scripts/lib/gate_report_format_classify.sh)。
    # provenance: 本変更の実体は118dc5ff8で導入済み。
    flock -w "${GATE_SINGLEFLIGHT_TIMEOUT:-60}" 199 || {
        _gate_receipt_phase singleflight_wait "$_GATE_WAIT_STARTED"
        echo "INFRA_TIMEOUT: report gate single-flight timeout: $REPORT_PATH" >&2
        exit 2
    }
fi
_gate_receipt_phase singleflight_wait "$_GATE_WAIT_STARTED"

# A caller can miss the fingerprint cache while the current leader is still
# validating. Recheck after joining the single-flight lock: the leader may
# have published the exact validated generation while this caller waited.
# This preserves the report lock as the correctness boundary while avoiding a
# duplicate validation that would otherwise extend aggregate lock hold time.
if [ "${GATE_SINGLEFLIGHT_OWNER:-0}" != "1" ] && _gate_try_fingerprint_reuse; then
    exec 199>&- 2>/dev/null || true
    exit 0
fi

# cmd_karo_impl_singleflight_hold_instrumentation_20260725 AC1:
# ロック保持区間(flock取得成功→プロセス終了によるfd 199解放)を既存台帳
# logs/defense_overhead.jsonl へ check_id=singleflight_hold で記録する。
# 待ち側(singleflight_wait)と対を成し、GATE_SINGLEFLIGHT_TIMEOUTの妥当性を
# 外挿ではなく実測分布(p95/max)で判定できるようにする。新台帳は作らない。
# 記録はdetached subshell(1 fork)で行い、本番経路の待ち時間を増やさない(AC3)。
if [ "${GATE_SINGLEFLIGHT_OWNER:-0}" != "1" ]; then
    _GATE_HOLD_STARTED="$(_gate_mono_ms)"
    _GATE_HOLD_FINALIZED=0
    # shellcheck disable=SC2317  # EXIT trap経由の間接呼出し(SC2317は到達不能と誤検知する)
    _gate_record_singleflight_hold() {
        local _rc="${1:-$?}" _verdict _hold_ms _lib
        [ -n "${_GATE_HOLD_STARTED:-}" ] || return 0
        [ "${_GATE_HOLD_FINALIZED:-0}" = "1" ] && return 0
        _hold_ms=$(( $(_gate_mono_ms) - _GATE_HOLD_STARTED ))
        case "$_rc" in
            0) _verdict="PASS" ;;
            1) _verdict="FAIL" ;;
            *) _verdict="BLOCK" ;;
        esac
        _GATE_HOLD_FINALIZED=1
        # The report lock must be released even if the optional telemetry
        # library is unavailable or cannot be sourced.
        exec 199>&- 2>/dev/null || true
        _lib="$(dirname "${BASH_SOURCE[0]}")/../lib/defense_overhead_writer.sh"
        [ -f "$_lib" ] || return 0
        # shellcheck source=/dev/null
        . "$_lib" 2>/dev/null || return 0
        # 軍師レビュー指摘(cmd_karo_impl_singleflight_hold_instrumentation_20260725):
        # writerのdetached subshellは親のfdを継承するため、fd 199を開いたままforkすると
        # 子がgate.lockを保持したままledger.lockと低速FS書込みを待つ。計装自体が
        # ロック保持区間を延ばし、本cmdの目的(timeout削減)に反する。∴fork前に必ず閉じる。
        # ここでの解放は保持区間の終端そのものであり、計測値(_hold_ms算出済み)にも影響しない。
        defense_overhead_write_async gate_report_format singleflight_hold \
            "$_hold_ms" "$_verdict" "gate_report_format:hold:$$:${_GATE_HOLD_STARTED}" || true
        return 0
    }
    _gate_record_singleflight_hold_on_exit() {
        local _exit_rc="$?"
        _gate_record_singleflight_hold "$_exit_rc"
        return "$_exit_rc"
    }
    trap '_gate_record_singleflight_hold_on_exit' EXIT
fi

# executor帰属: 報告YAMLのworker_idを読取り(CLI非依存)
_REPORT_EXECUTOR="${AGENT_ID:-}"
if [ -z "$_REPORT_EXECUTOR" ]; then
    while IFS= read -r _line; do
        case "$_line" in
            worker_id:*)
                _REPORT_EXECUTOR="${_line#worker_id:}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#"${_REPORT_EXECUTOR%%[![:space:]]*}"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%%#*}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%"${_REPORT_EXECUTOR##*[![:space:]]}"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%\'}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#\'}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%\"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#\"}"
                break
                ;;
        esac
    done < "$REPORT_PATH"
fi
_REPORT_EXECUTOR="${_REPORT_EXECUTOR:-unknown}"

# --- PASS cache: skip redundant re-checks on unmodified files (GP-073) ---
_GATE_SOURCE="${BASH_SOURCE[0]}"
case "$_GATE_SOURCE" in
    scripts/gates/gate_report_format.sh)
        # Hot path: the gate is normally invoked from the repository root.
        # Avoid spawning a subshell solely to resolve the already-known root.
        _DEFAULT_REPO_ROOT="$PWD"
        ;;
    /*/scripts/gates/gate_report_format.sh)
        _DEFAULT_REPO_ROOT="${_GATE_SOURCE%/scripts/gates/gate_report_format.sh}"
        ;;
    *)
        # Preserve canonical resolution for unusual relative/symlinked callers.
        _DEFAULT_REPO_ROOT="$(cd "$(dirname "$_GATE_SOURCE")/../.." && pwd)"
        ;;
esac
REPO_ROOT="${GATE_REPO_ROOT_OVERRIDE:-$_DEFAULT_REPO_ROOT}"
PASS_CACHE="${GATE_PASS_CACHE_FILE:-$REPO_ROOT/logs/.gate_pass_cache}"
LEARNING_FILE="${GATE_REPORT_FORMAT_LEARNING_FILE:-$REPO_ROOT/logs/gate_report_format_learning.yaml}"
PREFILL_THRESHOLD="${GATE_REPORT_FORMAT_PREFILL_THRESHOLD:-10}"
_GATE_DIR="${BASH_SOURCE[0]%/*}"
# perf: cache keyはshellで組み立て、realpath起動を避ける。
if [[ "$REPORT_PATH" = /* ]]; then
    _CANON="$REPORT_PATH"
else
    _CANON="$PWD/${REPORT_PATH#./}"
fi
_MTIME=""
_GATE_MTIME=""
_COMBINED_MTIME=""
_AUTOFIX_MTIME=""
_FORMAT_MTIME=""
_IDENTITY_MTIME=""
_EXTRA_GATE_MTIME=""
if [[ "${GATE_NO_LOG:-}" != "1" ]] || [ -f "$PASS_CACHE" ]; then
    {
        read -r _MTIME
        read -r _GATE_MTIME
        read -r _COMBINED_MTIME
        read -r _AUTOFIX_MTIME
        read -r _FORMAT_MTIME
        read -r _IDENTITY_MTIME
    } < <(stat -c '%Y' \
        "$REPORT_PATH" \
        "${BASH_SOURCE[0]}" \
        "$_GATE_DIR/gate_report_format_combined.py" \
        "$_GATE_DIR/gate_report_autofix_main.py" \
        "$_GATE_DIR/gate_report_format_main.py" \
        "$REPO_ROOT/scripts/lib/report_commit_identity.py" 2>/dev/null || printf '\n\n\n\n\n\n')
    if [ -n "${GATE_CACHE_VERSION_FILE_OVERRIDE:-}" ]; then
        _EXTRA_GATE_MTIME=$(stat -c '%Y' "$GATE_CACHE_VERSION_FILE_OVERRIDE" 2>/dev/null || true)
    fi
    _GATE_SIGNATURE="${_GATE_MTIME}:${_COMBINED_MTIME}:${_AUTOFIX_MTIME}:${_FORMAT_MTIME}:${_IDENTITY_MTIME}:${_EXTRA_GATE_MTIME}"
    if [ -n "$_MTIME" ] && [ -n "$_IDENTITY_MTIME" ] && [ -f "$PASS_CACHE" ] && grep -qF "${_CANON} ${_MTIME} ${_GATE_SIGNATURE}" "$PASS_CACHE" 2>/dev/null; then
        echo "PASS"
        exit 0
    fi
fi

# cmd_2063: autofix + format validation を単一 python3 プロセスで実行
# 旧: bash gate_report_autofix.sh (→python3) + python3 gate_report_format_main.py = 2プロセス
# 新: python3 gate_report_format_combined.py (autofix+validation を1プロセス統合) = 1プロセス
# The validator may invoke hooks that schedule their own background cache
# refresh. Do not let those transitive descendants inherit the report lock.
RESULT=$(python3 "$_GATE_DIR/gate_report_format_combined.py" "$REPORT_PATH" 199>&- 2>&1) || true

# A truthful implementation failure has no artifact commit by definition.  Keep
# the ordinary success lane strict, but remove the missing-hash error for the
# exact failed/FAIL/commit=no contract when task and report both require a
# commit.  The report snapshot is the immutable AC generation; a later task
# redeploy must not create a GP-131b warning against an older report.
RESULT=$(GATE_RESULT="$RESULT" GATE_REPORT="$REPORT_PATH" python3 - <<'PY'
import os, pathlib, re, yaml

result = os.environ.get("GATE_RESULT", "")
report_path = pathlib.Path(os.environ["GATE_REPORT"])
try:
    report = yaml.safe_load(report_path.read_text(encoding="utf-8")) or {}
    worker = str(report.get("worker_id") or "").strip()
    task_path = report_path.parent.parent / "tasks" / f"{worker}.yaml"
    task_raw = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
    task = task_raw.get("task", task_raw)
except Exception:
    print(result)
    raise SystemExit(0)

def required(node):
    contract = node.get("commit_contract") if isinstance(node, dict) else None
    return isinstance(contract, dict) and contract.get("required") is True

commit_checks = (report.get("binary_checks") or {}).get("commit")
truthful_failure = (
    str(report.get("status") or "").strip().lower() == "failed"
    and str(report.get("verdict") or "").strip().upper() == "FAIL"
    and required(report) and required(task)
    and isinstance(commit_checks, list) and bool(commit_checks)
    and all(isinstance(item, dict) and str(item.get("result") or "").strip().lower() == "no" for item in commit_checks)
)

snapshot = report.get("task_contract_snapshot")
snapshot_acs = snapshot.get("acceptance_criteria") if isinstance(snapshot, dict) else None
snapshot_ids = {
    str(item.get("id") or f"AC{index}")
    for index, item in enumerate(snapshot_acs or [], 1)
    if isinstance(item, dict)
}
report_ac_ids = {
    str(key) for key in (report.get("binary_checks") or {})
    if str(key).upper().startswith("AC")
}
snapshot_covers_report = bool(snapshot_ids) and report_ac_ids.issuperset(snapshot_ids)

out = []
for line in result.splitlines():
    if truthful_failure and line.startswith("FAIL: "):
        errors = [part.strip() for part in line[6:].split(";") if part.strip()]
        errors = [part for part in errors if part != "commit_contract: required commit_hash is missing or invalid"]
        line = "FAIL: " + "; ".join(errors) if errors else "PASS"
    if snapshot_covers_report and "GP-131b WARN:" in line:
        continue
    out.append(line)
print("\n".join(out))
PY
)

echo "$RESULT"

# --- cmd_3264: auto-commit contamination check (AC2/AC3) ---
# bc:commit=yes時にtarget_path配下の未commit変更・auto-commit巻込みを検出
# Post-CLEAR dashboard reflux may skip only this inspection after independently
# proving that both review approvals still bind to the current report.
CONTAMINATION_BLOCK=0

filter_session_state_only_task_diffs() {
    local repo="$1"
    local uncommitted_raw="$2"
    REPO_ROOT="$repo" CC_UNCOMMITTED_RAW="$uncommitted_raw" python3 - <<'PY'
import os
import subprocess
import yaml

repo = os.environ.get("REPO_ROOT", "")
raw = os.environ.get("CC_UNCOMMITTED_RAW", "").splitlines()

def parse_path(line):
    if len(line) < 4:
        return ""
    path = line[3:].strip()
    if " -> " in path:
        path = path.rsplit(" -> ", 1)[1].strip()
    if len(path) >= 2 and path[0] == path[-1] == '"':
        path = path[1:-1]
    return path

def without_session_state(text):
    data = yaml.safe_load(text) or {}
    if isinstance(data, dict):
        node = data.get("task")
        if isinstance(node, dict):
            node = dict(node)
            node.pop("session_state", None)
            data = dict(data)
            data["task"] = node
        else:
            data = dict(data)
            data.pop("session_state", None)
    return data

def is_session_state_only_task_diff(line):
    xy = line[:2]
    path = parse_path(line)
    if "M" not in xy:
        return False
    if not path.startswith("queue/tasks/") or not path.endswith(".yaml"):
        return False
    worktree_path = os.path.join(repo, path)
    if not os.path.isfile(worktree_path):
        return False
    try:
        head_text = subprocess.check_output(
            ["git", "-C", repo, "show", f"HEAD:{path}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        with open(worktree_path, encoding="utf-8") as f:
            worktree_text = f.read()
        return without_session_state(head_text) == without_session_state(worktree_text)
    except Exception:
        return False

for line in raw:
    if line and not is_session_state_only_task_diff(line):
        print(line)
PY
}

filter_report_commit_nonoverlap_diffs() {
    local repo="$1"
    local report_path="$2"
    local uncommitted_raw="$3"
    # Shared operational log ownership is semantic, not positional. Delegate
    # this exact allowlisted path to the SSOT; retain the legacy range filter
    # below for every ordinary file and for fail-closed results.
    local shared_path="logs/gunshi_review_log.yaml"
    if printf '%s\n' "$uncommitted_raw" | awk 'substr($0,4)=="logs/gunshi_review_log.yaml" {found=1} END {exit !found}'; then
        if [ -f "$repo/scripts/lib/report_commit_nonoverlap_filter.sh" ]; then
            # shellcheck source=scripts/lib/report_commit_nonoverlap_filter.sh
            source "$repo/scripts/lib/report_commit_nonoverlap_filter.sh"
            local shared_kept
            shared_kept=$(filter_report_commit_nonoverlap_uncommitted "$repo" "$report_path" "$shared_path" 2>/dev/null || printf '%s\n' "$shared_path")
            if [ -z "$shared_kept" ]; then
                uncommitted_raw=$(printf '%s\n' "$uncommitted_raw" | awk 'substr($0,4)!="logs/gunshi_review_log.yaml"')
                [ -n "$uncommitted_raw" ] || return 0
            fi
        fi
    fi
    # queue/insights.yaml is a shared bounded queue: later workers may rotate
    # unrelated IDs through the same line range.  Range overlap is therefore
    # not ownership evidence.  Suppress only when every insight ID named by
    # the task snapshot and changed by the report commit is structurally
    # unchanged when still present in the current worktree. Absence is a valid
    # bounded-queue eviction by later IDs; duplicate/ambiguous IDs and malformed
    # YAML deliberately fail closed.
    local insight_path="queue/insights.yaml"
    if printf '%s\n' "$uncommitted_raw" | awk 'substr($0,4)=="queue/insights.yaml" {found=1} END {exit !found}'; then
        if REPO_ROOT="$repo" REPORT_PATH="$report_path" INSIGHT_PATH="$insight_path" python3 - <<'PY'
import os
import json
import re
import subprocess
import sys
import yaml

repo = os.environ["REPO_ROOT"]
report_path = os.environ["REPORT_PATH"]
path = os.environ["INSIGHT_PATH"]

def fail():
    raise SystemExit(1)

try:
    with open(report_path, encoding="utf-8") as stream:
        report = yaml.safe_load(stream)
    commit = str(report.get("commit_hash") or "")
    snapshot = report.get("task_contract_snapshot")
    if not isinstance(report, dict) or not isinstance(snapshot, dict):
        fail()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail()
    snapshot_ids = set(re.findall(r"INS-[0-9A-Za-z-]+", str(snapshot)))
    # When the task does not name specific INS-IDs (e.g. bulk dirty-finish
    # hotfixes that target the entire file), fall back to deriving owned IDs
    # from the commit diff.  This prevents false BLOCK when reflux adds or
    # resolves entries between the worker's commit and the gate run.
    snapshot_ids_empty = not snapshot_ids
    parent_text = subprocess.check_output(
        ["git", "-C", repo, "show", f"{commit}^:{path}"], text=True,
        stderr=subprocess.DEVNULL,
    )
    commit_text = subprocess.check_output(
        ["git", "-C", repo, "show", f"{commit}:{path}"], text=True,
        stderr=subprocess.DEVNULL,
    )
    with open(os.path.join(repo, path), encoding="utf-8") as stream:
        current_text = stream.read()
    with open(os.path.join(repo, "queue/archive/insights_archive.yaml"), encoding="utf-8") as stream:
        archive_text = stream.read()
    documents = [
        yaml.safe_load(text)
        for text in (parent_text, commit_text, current_text, archive_text)
    ]
except Exception:
    fail()

def indexed(document, allow_duplicate_ids=False):
    if not isinstance(document, dict) or set(document) != {"insights"}:
        fail()
    entries = document["insights"]
    if not isinstance(entries, list):
        fail()
    result = {}
    for entry in entries:
        if not isinstance(entry, dict):
            fail()
        identity = entry.get("id")
        if not isinstance(identity, str) or not identity:
            fail()
        if identity in result:
            if not allow_duplicate_ids:
                fail()
            result[identity].append(entry)
        elif allow_duplicate_ids:
            result[identity] = [entry]
        else:
            result[identity] = entry
    return result

before = indexed(documents[0], allow_duplicate_ids=True)
committed, current = map(indexed, documents[1:3])
archive_document = documents[3]
if not isinstance(archive_document, dict) or set(archive_document) != {"insights"}:
    fail()
archive_entries = archive_document["insights"]
if not isinstance(archive_entries, list) or any(not isinstance(entry, dict) for entry in archive_entries):
    fail()
def canonical_entry(entry):
    return json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

def preimage_multiset_changed(before_entries, committed_entry):
    """Compare the preimage as an ID-keyed multiset, not a unique-ID map."""
    before_fingerprints = sorted(canonical_entry(entry) for entry in before_entries)
    committed_fingerprints = [canonical_entry(committed_entry)] if committed_entry is not None else []
    return before_fingerprints != committed_fingerprints

changed_ids = {
    identity for identity in set(before) | set(committed)
    if preimage_multiset_changed(before.get(identity, []), committed.get(identity))
}
if snapshot_ids_empty:
    # Bulk dirty-finish reports do not identify one owned insight.  They still
    # need a fail-closed delta check: only an automatic reflux producer may add
    # a new record, and an existing record may only receive a known lifecycle
    # update.  A bare sys.exit(0) here made every existing-entry edit look like
    # harmless concurrent reflux and allowed the worker's result to be altered.
    auto_source = lambda entry: (
        entry.get("source") == "self_retro"
        or entry.get("source") == "semantic_index_update"
        or entry.get("source") == "gate_loop_health"
        or str(entry.get("source") or "").startswith("cmd_complete_gate:")
    )

    # The bounded queue may only grow/rotate through a producer that is part of
    # the reflux path.  indexed() already fail-closes malformed YAML, duplicate
    # current/commit IDs, non-mapping entries, and missing IDs.
    rotated_ids = set(committed) - set(current)
    for identity in rotated_ids:
        # A bounded queue may evict a committed record after the worker
        # finishes.  Treat that as safe only when the archive contains exactly
        # one byte-for-byte equivalent record; absence, duplication, or any
        # field mutation remains visible as contamination.
        archived = [entry for entry in archive_entries if entry.get("id") == identity]
        if len(archived) != 1 or archived[0] != committed[identity]:
            fail()
    for identity in set(current) - set(committed):
        entry = current[identity]
        if not auto_source(entry) or not str(identity).startswith("INS-"):
            fail()

    allowed_resolution_fields = {"status", "resolved_reason", "action_artifact", "resolved_at"}
    for identity in set(committed) & set(current):
        committed_entry = committed[identity]
        current_entry = current[identity]
        if committed_entry == current_entry:
            continue
        changed = {
            key for key in set(committed_entry) | set(current_entry)
            if committed_entry.get(key) != current_entry.get(key)
        }
        # self_retro may refresh occurrence metadata after the report commit;
        # the identity and producer marker remain stable.
        if (
            committed_entry.get("source") == "self_retro"
            and current_entry.get("source") == "self_retro"
            and changed
            and changed <= {"occurrence_count", "last_seen"}
        ):
            continue
        # Reflux resolution is a lifecycle transition, not permission to edit
        # the insight body or arbitrary metadata.  Keep the source and ID
        # stable and require pending -> resolved with only the four resolution
        # fields changed.
        if (
            auto_source(committed_entry)
            and auto_source(current_entry)
            and committed_entry.get("source") == current_entry.get("source")
            and committed_entry.get("status") == "pending"
            and current_entry.get("status") == "resolved"
            and changed
            and changed <= allowed_resolution_fields
        ):
            continue
        fail()
    sys.exit(0)
owned_ids = snapshot_ids & changed_ids
if not owned_ids:
    fail()

def post_commit_shared_mutation_allowed(before_entry, after_entry):
    """Accept only producer-owned metadata changes, never worker edits.

    Reflux workers publish a resolved insight and the self-retro producer may
    immediately update the same ID's occurrence metadata.  The task/report
    contract is the primary source.  The narrowly-scoped legacy fallback is
    retained for reports created before Level5 injection: it requires the
    stable self_retro producer marker and the exact two metadata fields.
    """
    contract = report.get("reflux_commit_contract")
    if not isinstance(contract, dict):
        snapshot_contract = snapshot.get("reflux_commit_contract")
        contract = snapshot_contract if isinstance(snapshot_contract, dict) else None
    if contract is None:
        contract = {
            "producer": {"field": "source", "value": "self_retro"},
            "stable_id_field": "id",
            "post_commit_allowed_fields": ["occurrence_count", "last_seen"],
        }
    if not isinstance(contract, dict):
        return False
    producer = contract.get("producer")
    if not isinstance(producer, dict):
        return False
    producer_field = str(producer.get("field") or "").strip()
    producer_value = producer.get("value")
    if not producer_field or before_entry.get(producer_field) != producer_value or after_entry.get(producer_field) != producer_value:
        return False
    stable_field = str(contract.get("stable_id_field") or "id").strip()
    if not stable_field or before_entry.get(stable_field) != after_entry.get(stable_field):
        return False
    allowed = contract.get("post_commit_allowed_fields")
    if not isinstance(allowed, list) or not allowed:
        return False
    allowed = {str(field).strip() for field in allowed if str(field).strip()}
    changed = {
        key for key in set(before_entry) | set(after_entry)
        if before_entry.get(key) != after_entry.get(key)
    }
    return bool(changed) and changed <= allowed

for identity in owned_ids:
    if identity in current:
        if committed.get(identity) != current.get(identity) and not post_commit_shared_mutation_allowed(
            committed.get(identity) or {}, current.get(identity) or {}
        ):
            fail()
    elif [entry for entry in archive_entries if entry.get("id") == identity] != [committed.get(identity)]:
        # Absence from the live bounded queue is safe only when the archive
        # contains exactly one copy of the record written by the report commit.
        fail()
# Non-owned IDs may change freely (reflux status transitions, new entries
# added by concurrent workers).  Only owned_ids require identity preservation.
# This prevents false BLOCK when reflux resolves a pending insight or adds
# new entries between the worker's commit and the gate run.
sys.exit(0)
PY
        then
            uncommitted_raw=$(printf '%s\n' "$uncommitted_raw" | awk 'substr($0,4)!="queue/insights.yaml"')
            [ -n "$uncommitted_raw" ] || return 0
        else
            # Semantic comparison is the only safe ownership proof for this
            # bounded queue.  Do not let positional hunks turn parse failure
            # or ambiguous identity into a false suppression.
            printf '%s\n' "$uncommitted_raw"
            return 0
        fi
    fi
    REPO_ROOT="$repo" REPORT_PATH="$report_path" CC_UNCOMMITTED_RAW="$uncommitted_raw" python3 - <<'PY'
import os
import difflib
import re
import subprocess
import sys
import yaml

repo = os.environ.get("REPO_ROOT", "")
report_path = os.environ.get("REPORT_PATH", "")
raw_lines = [line for line in os.environ.get("CC_UNCOMMITTED_RAW", "").splitlines() if line.strip()]

def run_git(args):
    try:
        return subprocess.check_output(["git", "-C", repo, *args], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""

def parse_path(line):
    if len(line) < 4:
        return ""
    path = line[3:].strip()
    if " -> " in path:
        path = path.rsplit(" -> ", 1)[1].strip()
    if len(path) >= 2 and path[0] == path[-1] == '"':
        path = path[1:-1]
    return path

def hunk_ranges(diff_text):
    ranges = []
    for match in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff_text, re.M):
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count <= 0:
            continue
        ranges.append((start, start + count - 1))
    return ranges

def changed_tokens(diff_text):
    tokens = set()
    for line in diff_text.splitlines():
        if not line or line.startswith(("+++", "---", "@@")) or line[0] not in "+-":
            continue
        token = "".join(line[1:].split())
        if token:
            tokens.add(token)
    return tokens

def overlaps(left, right):
    return any(a <= d and c <= b for a, b in left for c, d in right)

def _blob(revision, path):
    try:
        if revision == "WORKTREE":
            with open(os.path.join(repo, path), encoding="utf-8") as stream:
                return stream.read()
        return subprocess.check_output(
            ["git", "-C", repo, "show", f"{revision}:{path}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return None

def _changed_fragments(before, after):
    """Return exact additions/deletions, including edits inside generated lines."""
    before_lines = before.splitlines()
    after_lines = after.splitlines()
    additions = []
    deletions = []
    line_match = difflib.SequenceMatcher(
        None, before_lines, after_lines, autojunk=False
    )
    for tag, i1, i2, j1, j2 in line_match.get_opcodes():
        if tag == "equal":
            continue
        old_lines = before_lines[i1:i2]
        new_lines = after_lines[j1:j2]
        if len(old_lines) == len(new_lines) == 1:
            char_match = difflib.SequenceMatcher(
                None, old_lines[0], new_lines[0], autojunk=False
            )
            for ctag, ci1, ci2, cj1, cj2 in char_match.get_opcodes():
                if ctag in ("insert", "replace") and new_lines[0][cj1:cj2].strip():
                    additions.append(new_lines[0][cj1:cj2])
                if ctag in ("delete", "replace") and old_lines[0][ci1:ci2].strip():
                    deletions.append(old_lines[0][ci1:ci2])
        else:
            additions.extend(line for line in new_lines if line.strip())
            deletions.extend(line for line in old_lines if line.strip())
    return additions, deletions

def commit_effect_preserved(owned_commits, path):
    """Prove the report commit's content survives later generated-file edits.

    Line ranges are too coarse for generated maps: an unrelated producer can
    rewrite another field on the same very long line.  Compare the commit's
    exact changed fragments with the current worktree and fail closed when a
    committed addition disappeared or a committed deletion returned.
    """
    current = _blob("WORKTREE", path)
    if current is None:
        return False
    saw_effect = False
    for owned in owned_commits:
        before = _blob(f"{owned}^", path)
        after = _blob(owned, path)
        if before is None or after is None:
            return False
        additions, deletions = _changed_fragments(before, after)
        for fragment in additions:
            saw_effect = True
            if fragment not in current:
                return False
        for fragment in deletions:
            saw_effect = True
            if fragment in current:
                return False
    return saw_effect

try:
    with open(report_path, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    report = {}

commit_hash = str(report.get("commit_hash") or "").strip()
if not re.fullmatch(r"[0-9a-f]{40}", commit_hash):
    print("\n".join(raw_lines))
    raise SystemExit(0)

# A report may legitimately span several scope-limited commits.  The old code
# compared dirty hunks only with the final commit_hash, so files committed by
# an earlier commit of the same task were reported as dirty/foreign.  Accept
# additional hashes only when their commit subject proves task ownership.
parent_cmd = str(report.get("parent_cmd") or "").strip()
task_id = str(report.get("task_id") or "").strip()
def scalar_texts(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from scalar_texts(child)
    elif isinstance(value, list):
        for child in value:
            yield from scalar_texts(child)
    elif value is not None:
        yield str(value)

identity_text = "\n".join(scalar_texts(report))
owned_commits = [commit_hash]
for candidate in re.findall(r"(?<![0-9a-f])[0-9a-f]{7,40}(?![0-9a-f])", identity_text):
    resolved = run_git(["rev-parse", "--verify", f"{candidate}^{{commit}}"]).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", resolved) or resolved in owned_commits:
        continue
    subject = run_git(["show", "-s", "--format=%s", resolved]).strip()
    if subject and ((parent_cmd and parent_cmd in subject) or (task_id and task_id in subject)):
        owned_commits.append(resolved)

changed_files = set()
for owned in owned_commits:
    changed_files.update(run_git(["diff-tree", "--no-commit-id", "--name-only", "-r", owned]).splitlines())
if not changed_files:
    print("\n".join(raw_lines))
    raise SystemExit(0)

kept = []
suppressed = []
for line in raw_lines:
    path = parse_path(line)
    if not path or path not in changed_files:
        kept.append(line)
        continue
    commit_ranges = []
    for owned in owned_commits:
        commit_ranges.extend(hunk_ranges(run_git(["diff", "--unified=0", f"{owned}^", owned, "--", path])))
    dirty_ranges = hunk_ranges(run_git(["diff", "--unified=0", "--", path]) + "\n" + run_git(["diff", "--cached", "--unified=0", "--", path]))
    commit_diff = "\n".join(run_git(["diff", "--unified=0", f"{owned}^", owned, "--", path]) for owned in owned_commits)
    dirty_diff = run_git(["diff", "--unified=0", "--", path]) + "\n" + run_git(["diff", "--cached", "--unified=0", "--", path])
    semantic_overlap = bool(changed_tokens(commit_diff) & changed_tokens(dirty_diff))
    effect_preserved = commit_effect_preserved(owned_commits, path)
    if commit_ranges and dirty_ranges and effect_preserved:
        suppressed.append(path)
    elif commit_ranges and dirty_ranges and not overlaps(commit_ranges, dirty_ranges) and not semantic_overlap:
        # Keep the legacy non-overlap proof only when the task effect is also
        # present; a missing task effect must remain a BLOCK.
        kept.append(line)
    else:
        kept.append(line)

for path in suppressed:
    print(f"WARN(cmd_3264-AC2): {path} has uncommitted non-overlapping diff after report commit_hash; treating as concurrent unrelated change", file=sys.stderr)
print("\n".join(kept))
PY
}

# Focused contract-test entry point.  It exercises the same shared-queue
# filter used by the production gate without running unrelated report checks.
# The fixture supplies a real commit/report and a porcelain path list through
# GATE_REFLUX_UNCOMMITTED_PATHS.
if [ "${GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST:-0}" = "1" ]; then
    _REFLUX_TEST_ROOT="${GATE_REPO_ROOT_OVERRIDE:-$PWD}"
    filter_report_commit_nonoverlap_diffs \
        "$_REFLUX_TEST_ROOT" "$REPORT_PATH" "${GATE_REFLUX_UNCOMMITTED_PATHS:-}"
    exit $?
fi

# cmd_karo_hotfix_gate_ac3_hunk_provenance: AC3 hunk/commit provenance filter.
# AC2は commit_hash のhunkと未commit差分のhunkを比較して非重複なら黙らせる(上のfilter_report_commit_nonoverlap_diffs)。
# AC3の巻込みWARNは同じ判定原理(commit_hash基準のhunk比較)がなく、file名一致だけで発火していた
# (cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205 AC1: 元コードはcmd_3264-AC3導入コミット
#  6bf403d2c=auto-commit自体に巻き込まれて追加されたまま、AC2だけがbc8c87bc5でhunk化され判定原理が乖離)。
# entries_raw: "<auto_commit_sha> <path>" 一覧（対象target_pathに一致した候補のみで良い）。
# hits_raw: WARN候補としてfile名一致したpath一覧（重複可）。
# 戻り値: 報告commit_hashのhunkと、その pathを触った全auto-commitのhunkが
#         ひとつも重ならないと証明できたpathのみ抑制し、残りをそのまま返す。
filter_autocommit_nonoverlap_hits() {
    local repo="$1"
    local report_path="$2"
    local entries_raw="$3"
    local hits_raw="$4"
    REPO_ROOT="$repo" REPORT_PATH="$report_path" CC_AC_ENTRIES_RAW="$entries_raw" CC_AC_HITS_RAW="$hits_raw" python3 - <<'PY'
import os
import re
import subprocess
import sys
import yaml

repo = os.environ.get("REPO_ROOT", "")
report_path = os.environ.get("REPORT_PATH", "")
entries_raw = [l for l in os.environ.get("CC_AC_ENTRIES_RAW", "").splitlines() if l.strip()]
hits_raw = [l for l in os.environ.get("CC_AC_HITS_RAW", "").splitlines() if l.strip()]

def run_git(args):
    try:
        return subprocess.check_output(["git", "-C", repo, *args], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""

def hunk_ranges(diff_text):
    ranges = []
    for match in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff_text, re.M):
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count <= 0:
            continue
        ranges.append((start, start + count - 1))
    return ranges

def overlaps(left, right):
    return any(a <= d and c <= b for a, b in left for c, d in right)

try:
    with open(report_path, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    report = {}

commit_hash = str(report.get("commit_hash") or "").strip()
report_valid = bool(re.fullmatch(r"[0-9a-f]{40}", commit_hash))

# path -> auto-commit SHAs that touched it (only among the passed candidate entries)
path_shas = {}
for line in entries_raw:
    parts = line.split(" ", 1)
    if len(parts) != 2:
        continue
    sha, path = parts
    path_shas.setdefault(path, []).append(sha)

reporter_cache = {}
def reporter_ranges_for(path):
    if path not in reporter_cache:
        reporter_cache[path] = hunk_ranges(run_git(["diff", "--unified=0", f"{commit_hash}^", commit_hash, "--", path]))
    return reporter_cache[path]

seen = set()
kept = []
suppressed = []
for path in hits_raw:
    if path in seen:
        continue
    seen.add(path)
    if not report_valid:
        kept.append(path)
        continue
    r_ranges = reporter_ranges_for(path)
    shas = path_shas.get(path, [])
    if not r_ranges or not shas:
        # commit_hashがこのpathを触っていない、または対応するauto-commit shaが
        # 不明 -> 重複の有無を証明できないため保守的にWARNを維持する。
        kept.append(path)
        continue
    any_overlap = False
    all_known = True
    for sha in shas:
        a_ranges = hunk_ranges(run_git(["diff", "--unified=0", f"{sha}^", sha, "--", path]))
        if not a_ranges:
            all_known = False
            continue
        if overlaps(r_ranges, a_ranges):
            any_overlap = True
            break
    if any_overlap or not all_known:
        kept.append(path)
    else:
        suppressed.append(path)

for path in suppressed:
    print(f"WARN(cmd_3264-AC3-suppressed): {path} auto-commit hunk does not overlap report commit {commit_hash[:8]}; treating as non-contaminating", file=sys.stderr)
print("\n".join(kept))
PY
}

# Skip truly external scratch reports, but keep checks active when the whole
# repository itself is a detached worktree under /tmp (the CI isolation path).
_REPORT_REAL="$(realpath -m -- "$REPORT_PATH")"
_REPO_REAL="$(realpath -m -- "$REPO_ROOT")"
if [[ "$_REPORT_REAL" == "$_REPO_REAL"/* ]] && [ "${GATE_SKIP_COMMIT_MISSING_CHECK:-0}" != "1" ]; then
    _CC_WORKER="$_REPORT_EXECUTOR"
    _CC_TASK_DIR="${GATE_SESSION_STATE_TASK_DIR:-$REPO_ROOT/queue/tasks}"
    _CC_TASK_FILE="$_CC_TASK_DIR/${_CC_WORKER}.yaml"
    if [ -f "$_CC_TASK_FILE" ]; then
        _CC_CHECK=$(python3 -c "
import os
import pathlib
import yaml, sys
try:
    sys.path.insert(0, sys.argv[4])
    from scripts.gates.gate_report_format_main import commit_owned_paths
    rdata = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    bc = rdata.get('binary_checks') or {}
    commit = bc.get('commit') or []
    if not (isinstance(commit, list) and commit):
        sys.exit(0)
    commit_check_text = ' '.join(str(item.get('check', '') or '') for item in commit if isinstance(item, dict))
    readonly_commit_markers = (
        'read-only',
        'readonly',
        '読み取り専用',
        'commit禁止',
        'コミット禁止',
        'stage/commitを実行していない',
        'stage/commitを実行していないか',
        'stage・commit',
        'stage・commit・revert',
        'stage・commit・revert・削除',
    )
    if any(marker in commit_check_text for marker in readonly_commit_markers):
        sys.exit(0)
    if str(commit[0].get('result', '') or '').strip().lower() not in ('yes', 'true'):
        sys.exit(0)
    tdata = yaml.safe_load(open(sys.argv[2], encoding='utf-8')) or {}
    task = tdata.get('task') or tdata
    repo_root = os.path.realpath(sys.argv[3])
    required_raw = task.get('task_worktree_required')
    required = required_raw is True or str(required_raw).strip().lower() in {
        '1', 'true', 'yes', 'on'
    }
    if required:
        sys.path.insert(0, os.path.join(sys.argv[4], 'scripts', 'lib'))
        from review_source_context import resolve_source_root
        try:
            scope_root = str(resolve_source_root(task, rdata, pathlib.Path(repo_root)))
        except Exception as exc:
            print(f'__SOURCE_SCOPE_BLOCK__:{exc}')
            raise SystemExit(0)
    else:
        scope_root = repo_root

    def add_path(paths, value):
        raw = str(value or '')
        if '\n' in raw or '\r' in raw or '\x00' in raw:
            paths.append('__INVALID_REPORT_PATH__')
            return
        s = raw.strip().lstrip('- ').strip()
        s = s.strip(chr(96)).strip('\"').strip(\"'\")
        if not s or s in ('none', 'null', 'FILL_THIS'):
            return
        normalized = os.path.normpath(s)
        resolved = os.path.realpath(os.path.join(repo_root, normalized))
        if s.startswith('-') or os.path.isabs(s) or not resolved.startswith(repo_root + os.sep):
            paths.append('__INVALID_REPORT_PATH__')
            return
        paths.append(normalized)

    report_paths = []
    fm = rdata.get('files_modified') or []
    if isinstance(fm, list):
        for item in fm:
            if isinstance(item, dict):
                add_path(report_paths, item.get('path') or item.get('file') or item.get('name'))
            else:
                add_path(report_paths, item)
    elif isinstance(fm, str):
        add_path(report_paths, fm)

    paths = []
    if report_paths:
        # Report files_modified is the worker's concrete claim of touched files.
        # Prefer it over task.target_path so broad/shared read scopes do not
        # false-BLOCK on unrelated concurrent changes.
        paths = report_paths
    else:
        for owned in commit_owned_paths(task):
            add_path(paths, owned)

    if required:
        print(f'__SOURCE_ROOT__:{scope_root}')
    for p in paths:
        print(p)
except Exception as exc:
    print(f'__SOURCE_SCOPE_BLOCK__:scope_resolver_unavailable:{exc}')
" "$REPORT_PATH" "$_CC_TASK_FILE" "$REPO_ROOT" "$_DEFAULT_REPO_ROOT" 2>/dev/null || true)
        if [ -n "${_CC_CHECK//[[:space:]]/}" ]; then
            mapfile -t _CC_PATHS <<< "$_CC_CHECK"
            _CC_SCOPE_ROOT="$REPO_ROOT"
            if [[ "${_CC_PATHS[0]:-}" == __SOURCE_SCOPE_BLOCK__:* ]]; then
                _CC_SCOPE_REASON="${_CC_PATHS[0]#__SOURCE_SCOPE_BLOCK__:}"
                echo "FAIL: task source scope validation failed: ${_CC_SCOPE_REASON}"
                CONTAMINATION_BLOCK=1
                RESULT="${RESULT}"$'\n'"FAIL: task source scope validation failed"
                _CC_PATHS=()
            elif [[ "${_CC_PATHS[0]:-}" == __SOURCE_ROOT__:* ]]; then
                _CC_SCOPE_ROOT="${_CC_PATHS[0]#__SOURCE_ROOT__:}"
                _CC_PATHS=("${_CC_PATHS[@]:1}")
            fi
            if printf '%s\n' "${_CC_PATHS[@]}" | grep -qxF '__INVALID_REPORT_PATH__'; then
                echo "FAIL: malformed report path rejected before git status"
                CONTAMINATION_BLOCK=1
                RESULT="${RESULT}"$'\n'"FAIL: malformed report path rejected before git status"
                _CC_PATHS=()
            fi
            # AC2: git status check for uncommitted target_path changes
            _CC_UNCOMMITTED=""
            if [ "${#_CC_PATHS[@]}" -gt 0 ]; then
                _CC_UNCOMMITTED=$(cd "$_CC_SCOPE_ROOT" && git status --porcelain -- "${_CC_PATHS[@]}" 2>/dev/null || true)
            fi
            if [ -n "${_CC_UNCOMMITTED//[[:space:]]/}" ]; then
                _CC_UNCOMMITTED=$(filter_session_state_only_task_diffs "$_CC_SCOPE_ROOT" "$_CC_UNCOMMITTED" 2>/dev/null || printf '%s\n' "$_CC_UNCOMMITTED")
            fi
            if [ -n "${_CC_UNCOMMITTED//[[:space:]]/}" ]; then
                _CC_UNCOMMITTED=$(filter_report_commit_nonoverlap_diffs "$_CC_SCOPE_ROOT" "$REPORT_PATH" "$_CC_UNCOMMITTED" 2>>"$REPO_ROOT/logs/gate_report_format_stderr.log" || printf '%s\n' "$_CC_UNCOMMITTED")
            fi
            if [ -n "${_CC_UNCOMMITTED//[[:space:]]/}" ]; then
                echo ""
                echo "★ BLOCK(cmd_3264-AC2): ${_CC_WORKER} target_path配下に未commit変更あり:"
                # 注: [ -n ]&&形式はループ末尾空行でset -e死亡する同型バグ族(2026-06-11 precheck 2件と同根)。防御的if/fi化
                while IFS= read -r _ccl; do if [ -n "$_ccl" ]; then echo "  $_ccl"; fi; done <<< "$_CC_UNCOMMITTED"
                # WARN→BLOCK昇格(2026-06-26): commit_missing workaround 3件再発。WARNでは止まらない
                CONTAMINATION_BLOCK=1
                RESULT="${RESULT}"$'\n'"FAIL: cmd_3264-AC2 target_path配下に未commit変更あり"
            fi
            # AC3: auto-commit contamination detection (hunk/commit provenance)
            # perf: git log --grep --name-only は7800+コミット履歴走査でNTFS上~500ms(cmd_training実測)。
            # 結果はHEAD不変なら同一のため、HEAD SHAキーでmemo化(GP-073 PASS cacheと同型パターン)。
            # cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205: file名一致だけではAC2
            # (filter_report_commit_nonoverlap_diffs)と判定原理が乖離し、共有fileの非重複hunkを
            # 誤ってWARNしていた。sha付きで巻込み候補を保持し、報告commit_hashのhunkと重複する
            # ものだけWARNへ残す(filter_autocommit_nonoverlap_hits)。
            # cache format v2: 1行目=HEAD, 2行目以降="<auto_commit_sha> <path>"（report非依存＝HEADのみでキー可）。
            _CC_AC_CACHE="${GATE_AUTOCOMMIT_CACHE_FILE:-$_CC_SCOPE_ROOT/logs/.gate_autocommit_hunk_cache}"
            _CC_CUR_HEAD=$(cd "$_CC_SCOPE_ROOT" && git rev-parse HEAD 2>/dev/null) || _CC_CUR_HEAD=""
            _CC_AUTO_ENTRIES=""
            _CC_AC_HIT=0
            if [ -n "$_CC_CUR_HEAD" ] && [ -f "$_CC_AC_CACHE" ]; then
                _CC_AC_CACHED_HEAD=$(head -n 1 "$_CC_AC_CACHE" 2>/dev/null)
                if [ "$_CC_AC_CACHED_HEAD" = "$_CC_CUR_HEAD" ]; then
                    _CC_AUTO_ENTRIES=$(tail -n +2 "$_CC_AC_CACHE" 2>/dev/null)
                    _CC_AC_HIT=1
                fi
            fi
            if [ "$_CC_AC_HIT" -eq 0 ]; then
                _CC_AUTO_ENTRIES=$(cd "$_CC_SCOPE_ROOT" && git log --grep="auto-commit" -10 --format='@@AC_SHA@@%H' --name-only 2>/dev/null | awk '
                    /^@@AC_SHA@@/ { sha=$0; sub(/^@@AC_SHA@@/, "", sha); next }
                    NF { print sha" "$0 }
                ' | sort -u || true)
                if [ -n "$_CC_CUR_HEAD" ]; then
                    _CC_AC_TMP=$(mktemp "${_CC_AC_CACHE}.XXXXXX" 2>/dev/null) || _CC_AC_TMP=""
                    if [ -n "$_CC_AC_TMP" ]; then
                        { printf '%s\n' "$_CC_CUR_HEAD"; printf '%s\n' "$_CC_AUTO_ENTRIES"; } > "$_CC_AC_TMP" 2>/dev/null \
                            && mv -f "$_CC_AC_TMP" "$_CC_AC_CACHE" 2>/dev/null \
                            || rm -f "$_CC_AC_TMP" 2>/dev/null
                    fi
                fi
            fi
            if [ -n "$_CC_AUTO_ENTRIES" ]; then
                _CC_AUTO_FILES=$(printf '%s\n' "$_CC_AUTO_ENTRIES" | cut -d' ' -f2- | sort -u)
                _CC_HITS=""
                while IFS= read -r _tp; do
                    [ -n "$_tp" ] || continue
                    _CC_M=$(printf '%s\n' "$_CC_AUTO_FILES" | grep -E "^${_tp}(/|$)" || true)
                    [ -n "$_CC_M" ] && _CC_HITS="${_CC_HITS}${_CC_M}"$'\n'
                done <<< "$_CC_CHECK"
                _CC_HITS="${_CC_HITS%$'\n'}"
                _CC_HITS=$(printf '%s\n' "$_CC_HITS" | sort -u)
                if [ -n "${_CC_HITS//[[:space:]]/}" ]; then
                    _CC_HIT_ENTRIES=$(printf '%s\n' "$_CC_AUTO_ENTRIES" | awk -v hits="$_CC_HITS" '
                        BEGIN { n = split(hits, h, "\n"); for (i = 1; i <= n; i++) want[h[i]] = 1 }
                        { path = $0; sub(/^[^ ]+ /, "", path); if (path in want) print }
                    ')
                    _CC_HITS=$(filter_autocommit_nonoverlap_hits "$_CC_SCOPE_ROOT" "$REPORT_PATH" "$_CC_HIT_ENTRIES" "$_CC_HITS" 2>>"$REPO_ROOT/logs/gate_report_format_stderr.log" || printf '%s\n' "$_CC_HITS")
                fi
                if [ -n "${_CC_HITS//[[:space:]]/}" ]; then
                    echo ""
                    echo "★ WARN(cmd_3264-AC3): ${_CC_WORKER} target_path配下ファイルがauto-commitに巻き込まれた可能性:"
                    printf '%s\n' "$_CC_HITS" | sort -u | while IFS= read -r _ccl; do
                        [ -n "$_ccl" ] && echo "  $_ccl"
                    done
                fi
            fi
        fi
    fi
fi

# cmd_2130: task_clarity_score WARN (non-blocking)
# perf: moved into gate_report_format_combined.py (Phase 3) to eliminate 2nd python3 subprocess

RESULT_IS_PASS=0
while IFS= read -r _result_line; do
    case "$_result_line" in
        PASS|PASS_NO_IMPROVEMENT)
            RESULT_IS_PASS=1
            break
            ;;
    esac
done <<< "$RESULT"
if [ "$CONTAMINATION_BLOCK" -eq 1 ]; then
    RESULT_IS_PASS=0
fi

# Persist the exact validated content generation before fast/no-log exits.
if [ "$RESULT_IS_PASS" -eq 1 ]; then
    _gate_validated_fp="$(sha256sum "$REPORT_PATH" | awk '{print $1}')"
    (
        flock -w 5 200 2>/dev/null || exit 0
        { grep -vxF "$_gate_validated_fp" "$_GATE_FP_CACHE" 2>/dev/null || true; echo "$_gate_validated_fp"; } > "${_GATE_FP_CACHE}.tmp.$$"
        mv "${_GATE_FP_CACHE}.tmp.$$" "$_GATE_FP_CACHE"
    ) 200>"${_GATE_FP_CACHE}.lock"
    _gate_receipt_phase local_gate "$_GATE_MONO_START_MS"
fi

# The validation/cache critical section ends here.  Release the report lock and
# submit its hold metric before any fire-log, DB, or skill-execution logging.
# Those writes are deliberately outside single-flight so a slow ledger cannot
# make the next validator wait or timeout.  The EXIT trap remains as a
# fail-closed fallback for validation errors and other exits before this point.
if [ "${GATE_SINGLEFLIGHT_OWNER:-0}" != "1" ]; then
    if [ "$RESULT_IS_PASS" -eq 1 ]; then
        _gate_record_singleflight_hold 0
    else
        _gate_record_singleflight_hold 1
    fi
fi

# Test/unit fast path: callers that only need stdout + exit code can bypass cache/log/session-state work.
if [[ "${GATE_FAST_EXIT:-0}" = "1" ]]; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- GATE_NO_LOG guard: skip fire_log writing ---
# cmd_complete_gate.sh等gate呼び出し元スクリプトをベンチマーク/速度計測で反復実行する時はこれを1にせよ。
# 判定(PASS/FAIL)自体は変わらない。付けないと未完成レポートの空欄FAILがgate_fire_log/insightを汚染する
# (cmd_karo_hotfix_bc_result_empty_high_freq_insight_202607020526で確認: kagemaru 3連続実行×6項目=18件)。
if [[ "${GATE_NO_LOG:-}" = "1" ]]; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- Test report guard: external /tmp reports are test artifacts. A detached
# repository rooted under /tmp is still a real CI checkout and must exercise
# logging/learning paths exactly like the primary worktree. ---
if [[ "$_REPORT_REAL" != "$_REPO_REAL"/* ]] && { [[ "$REPORT_PATH" == /tmp/* ]] || [[ "$REPORT_PATH" == *"/tmp/"* ]]; }; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- Gate fire logging (cmd_1279) ---
LOG_FILE="${GATE_FIRE_LOG_FILE:-$REPO_ROOT/logs/gate_fire_log.yaml}"
TS=$(date -Is)

# パス正規化(cmd_karo_hotfix_shogun_startup_loop_memory_202607082152): 呼び出し元(cmd_complete_gate.sh/
# 忍者の直接実行等)によってREPORT_PATHが絶対パス/相対パスで混在すると、gate_loop_health.shの自己修正率・
# FAIL率集計がファイル名の生文字列でグルーピングするため同一ファイルが別ファイル扱いされ、免疫系が
# 正常(自己修正)なのに異常(空転)として計測される。既に算出済みの絶対パス正規形_CANONからREPO_ROOT
# プレフィックスを除去し、常にリポジトリ相対パスでログへ記録する。
_LOG_PATH="$REPORT_PATH"
case "$_CANON" in
    "$REPO_ROOT"/*) _LOG_PATH="${_CANON#"$REPO_ROOT"/}" ;;
esac

if [ "$RESULT_IS_PASS" -eq 1 ]; then
    # WSL2最適化: gate_fire_log書込みをバックグラウンド化（ログは判定に影響しない）
    (
        exec 199>&-
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: PASS\n' "$TS" "$_LOG_PATH" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null &
    # DB INSERT: eventsテーブルへゲート記録（非ブロック）
    _GRF_CMD_ID="$(basename "${REPORT_PATH%.yaml}" | grep -oE 'cmd_[0-9a-zA-Z_]+' | head -1 || true)"
    # WSL2最適化: memory_db_live_insert を非同期化（DB書込みは判定に影響しない）
    (
        exec 199>&-
        python3 "$REPO_ROOT/scripts/memory_db_live_insert_async.py" gate \
            --gate-name "gate_report_format" --result "PASS" \
            --cmd-id "${_GRF_CMD_ID:-}" --ts "$TS" --detail "" \
            --source-file "$REPORT_PATH"
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
    _SKILL_LOG="$REPO_ROOT/scripts/skill_execution_log.sh"
    _REPORT_WRITE_SKILL="$REPO_ROOT/skills/report-write/SKILL.md"
    # queue/配下の実報告のみスキル品質台帳へ記録する。ベンチ・fixture実行
    # (.cache//tmp等)を本番品質として記録すると台帳が汚染されstartup gateが
    # 偽ALERTを出す(2026-08-04実証: round8ベンチのio_with_log_*.yamlがFAIL連投
    # →家老エスカレーション)。gate本来の判定・exit codeは影響を受けない。
    case "$REPORT_PATH" in
        "$REPO_ROOT"/queue/*|queue/*) _GRF_GENUINE_REPORT=1 ;;
        *) _GRF_GENUINE_REPORT=0 ;;
    esac
    if [ "$_GRF_GENUINE_REPORT" = "1" ] && [ "${SKILL_EXECUTION_PASS_LOG_DISABLE:-0}" != "1" ] && [ -x "$_SKILL_LOG" ]; then
        # cmd_karo_hotfix_control_plane_contracts_ga321_20260723:
        # sync loggerもtransitive background子を起動し得るためFD199を先に閉じる。
        # WSL2最適化: skill_execution_log.sh を非同期化。
        # SKILL_LOG_SYNC=1 でテスト時は同期実行(CI並列でポーリング競合を回避)。
        if [ "${SKILL_LOG_SYNC:-0}" = "1" ]; then
            (
                exec 199>&-
                bash "$_SKILL_LOG" \
                    "report-write" \
                    "$_REPORT_EXECUTOR" \
                    "PASS" \
                    "gate_report_format PASS" \
                    "gate_report_format" \
                    "$REPORT_PATH" \
                    "$_REPORT_WRITE_SKILL"
                bash "$_SKILL_LOG" \
                    "verdict-check" \
                    "$_REPORT_EXECUTOR" \
                    "PASS" \
                    "gate_report_format verdict/binary_checks PASS" \
                    "gate_report_format" \
                    "$REPORT_PATH" \
                    "$REPO_ROOT/skills/verdict-check/SKILL.md"
            ) >/dev/null 2>&1 || true
        else
            (
                exec 199>&-
                bash "$_SKILL_LOG" \
                    "report-write" \
                    "$_REPORT_EXECUTOR" \
                    "PASS" \
                    "gate_report_format PASS" \
                    "gate_report_format" \
                    "$REPORT_PATH" \
                    "$_REPORT_WRITE_SKILL"
            ) >/dev/null 2>&1 &
            (
                exec 199>&-
                bash "$_SKILL_LOG" \
                    "verdict-check" \
                    "$_REPORT_EXECUTOR" \
                    "PASS" \
                    "gate_report_format verdict/binary_checks PASS" \
                    "gate_report_format" \
                    "$REPORT_PATH" \
                    "$REPO_ROOT/skills/verdict-check/SKILL.md"
            ) >/dev/null 2>&1 &
        fi
    fi
    # Update PASS cache (GP-073) — WSL2最適化: sed dedup削除、直接append
    # 旧エントリは次回grep時にmtime不一致で自然失効。correctnessに影響なし。
    if [ -n "$_MTIME" ]; then
        echo "${_CANON} ${_MTIME} ${_GATE_SIGNATURE}" >> "$PASS_CACHE" 2>/dev/null || true
    fi
    exit 0
else
    REASONS="$(printf '%s\n' "$RESULT" | awk '/^FAIL: /{sub(/^FAIL: /,""); print; exit}')"
    if [ -z "$REASONS" ]; then
        REASONS="$RESULT"
        REASONS="${REASONS#FAIL: }"
        REASONS="${REASONS%%$'\n'*}"
    fi
    # Traceback: append the actual error line (last non-empty line) for diagnosis
    if [[ "$REASONS" == "Traceback (most recent call last):"* ]]; then
        _LAST_ERR="$(printf '%s\n' "$RESULT" | awk 'NF{line=$0} END{print line}')"
        REASONS="Traceback: ${_LAST_ERR}"
    fi
    REASONS="${REASONS//\"/\\\"}"
    # 中間状態チェック: verdict空/None + binary_checks AC欄0件 → FAILログ記録スキップ
    # 忍者の自己修正後に再度gateが走りPASS記録される（偽陽性FAIL根絶）
    _GATE_FIRE_LOG_SKIP=0
    if python3 -c "
import sys, yaml
try:
    data = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    v = str(data.get('verdict', '') or '').strip().lower()
    bc = data.get('binary_checks') or {}
    ac_count = sum(1 for k in (bc if isinstance(bc, dict) else {}) if str(k).upper().startswith('AC'))
    sys.exit(0 if (v in ('', 'none') and ac_count == 0) else 1)
except Exception:
    sys.exit(1)
" "$REPORT_PATH" 2>/dev/null; then
        _GATE_FIRE_LOG_SKIP=1
        echo "WARN: 中間状態(verdict未設定+AC欄なし) — gate_fire_logへのFAIL記録スキップ" >&2
    fi
    if [ "${GATE_SESSION_STATE_TEST:-0}" != "1" ] && [ "$_GATE_FIRE_LOG_SKIP" = "0" ]; then
        (
            exec 199>&-
            flock -w 5 200 2>/dev/null
            printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: FAIL, reasons: "%s"\n' "$TS" "$_LOG_PATH" "$REASONS" >> "$LOG_FILE"
        ) 200>"$LOG_FILE.lock" 2>/dev/null || true
        # DB INSERT: eventsテーブルへゲート記録（非ブロック）
        _GRF_CMD_ID="$(basename "${REPORT_PATH%.yaml}" | grep -oE 'cmd_[0-9a-zA-Z_]+' | head -1 || true)"
        (
            exec 199>&-
            python3 "$REPO_ROOT/scripts/memory_db_live_insert_async.py" gate \
                --gate-name "gate_report_format" --result "FAIL" \
                --cmd-id "${_GRF_CMD_ID:-}" --ts "$TS" --detail "$REASONS" \
                --source-file "$REPORT_PATH"
        ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    # cmd_2459: Gate FAIL → relevant skill feedback loop.
    # Best-effort only: report gate must remain responsible for the FAIL exit.
    _SKILL_FEEDBACK="$REPO_ROOT/scripts/skill_gate_feedback.sh"
    # queue/配下の実報告のみ(ベンチfixture汚染防止。PASS側L1005-1014と同一ガード)
    case "$REPORT_PATH" in
        "$REPO_ROOT"/queue/*|queue/*) _GRF_GENUINE_REPORT=1 ;;
        *) _GRF_GENUINE_REPORT=0 ;;
    esac
    if [ "$_GRF_GENUINE_REPORT" = "1" ] && [ "${SKILL_GATE_FEEDBACK_DISABLE:-0}" != "1" ] && [ -x "$_SKILL_FEEDBACK" ]; then
        _target_skill=""
        case "$REASONS" in
            *lesson_candidate*|*lessons_useful*|*result.summary*|*files_modified*|*status:\ \"pending\"*|*assumption_invalidation*|*purpose_validation*)
                _target_skill="report-write" ;;
            *binary_checks*|*verdict*)
                _target_skill="verdict-check" ;;
            *commit*)
                _target_skill="ninja-commit" ;;
        esac
        _skill_args=()
        [ -n "$_target_skill" ] && _skill_args=(--skill "$_target_skill")
        bash "$_SKILL_FEEDBACK" \
            --gate "gate_report_format" \
            --result "FAIL" \
            --reason "$REASONS" \
            --executor "$_REPORT_EXECUTOR" \
            --source "$REPORT_PATH" \
            "${_skill_args[@]}" >/dev/null 2>&1 || true
    fi
    if [ "${GATE_SESSION_STATE_TEST:-0}" != "1" ]; then
        GATE_REASONS="$REASONS" \
        GATE_REPORT_PATH="$REPORT_PATH" \
        GATE_LEARNING_FILE="$LEARNING_FILE" \
        GATE_PREFILL_THRESHOLD="$PREFILL_THRESHOLD" \
        python3 - <<'LEARNING_PY' 2>/dev/null || true
import os
import json
import tempfile
from datetime import datetime, timezone

import yaml


PATTERN_DEFS = [
    {
        "name": "lu_reason_empty",
        "prefill_field": "lessons_useful.reason",
        "match": lambda reason: reason.startswith("lessons_useful[") and "reason is empty" in reason,
    },
    {
        "name": "bc_result_empty",
        "prefill_field": "binary_checks.result",
        "match": lambda reason: reason.startswith("binary_checks.") and (".result: 空文字" in reason or '.result: ""' in reason),
    },
    {
        "name": "ac_version_read_missing",
        "match": lambda reason: reason.startswith("ac_version_read: MISSING"),
    },
    {
        "name": "result_summary_empty",
        "prefill_field": "result.summary",
        "match": lambda reason: reason == "result.summary: MISSING or empty",
    },
    {
        "name": "files_modified_missing",
        "prefill_field": "files_modified",
        "match": lambda reason: reason.startswith("files_modified: MISSING"),
    },
]


def extract_patterns(reason_text: str) -> list[dict[str, str]]:
    patterns = {}
    for reason in [r.strip() for r in reason_text.split(";") if r.strip()]:
        for pattern_def in PATTERN_DEFS:
            if pattern_def["match"](reason):
                entry = {"name": pattern_def["name"]}
                prefill_field = pattern_def.get("prefill_field")
                if prefill_field:
                    entry["prefill_field"] = prefill_field
                patterns[pattern_def["name"]] = entry
                break
    return [patterns[name] for name in sorted(patterns)]


reason_text = os.environ.get("GATE_REASONS", "")
patterns = extract_patterns(reason_text)
if not patterns:
    raise SystemExit(0)

learning_file = os.environ["GATE_LEARNING_FILE"]
threshold = int(os.environ.get("GATE_PREFILL_THRESHOLD", "10") or "10")
report_path = os.environ.get("GATE_REPORT_PATH", "")

try:
    with open(learning_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

pattern_map = data.get("patterns")
if not isinstance(pattern_map, dict):
    pattern_map = {}
data["patterns"] = pattern_map
data["threshold"] = threshold
data["updated_at"] = datetime.now(timezone.utc).isoformat()

report_name = os.path.basename(report_path) if report_path else ""
for pattern_meta in patterns:
    pattern = pattern_meta["name"]
    entry = pattern_map.get(pattern)
    if not isinstance(entry, dict):
        entry = {}
    try:
        count = int(entry.get("count", 0) or 0)
    except Exception:
        count = 0
    count += 1
    entry["count"] = count
    entry["prefill_active"] = count >= threshold
    if pattern_meta.get("prefill_field"):
        entry["prefill_field"] = pattern_meta["prefill_field"]
    entry["last_report"] = report_name
    entry["last_seen"] = data["updated_at"]
    pattern_map[pattern] = entry

os.makedirs(os.path.dirname(learning_file), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(learning_file), suffix=".learning.tmp")
os.close(fd)
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
    f.write("\n")
os.replace(tmp, learning_file)
LEARNING_PY
        _DIAGNOSE_GATE="$(dirname "${BASH_SOURCE[0]}")/gate_diagnose_check.sh"
        if [ -f "$_DIAGNOSE_GATE" ]; then
            bash "$_DIAGNOSE_GATE" "$REPORT_PATH" "$REASONS" || true
        fi
    fi
    # --- GP-198: session_state recording on gate FAIL ---
    _SS_REPORT_BASE=$(basename "$REPORT_PATH")
    _SS_NINJA="${_SS_REPORT_BASE%%_report_*}"
    _SS_TASK_DIR="${GATE_SESSION_STATE_TASK_DIR:-$REPO_ROOT/queue/tasks}"
    if [ "${GATE_SESSION_STATE_DISABLE:-0}" = "1" ]; then
        [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
    fi
    _SS_TASK_YAML="$_SS_TASK_DIR/${_SS_NINJA}.yaml"
    _SS_VALID=false
    source "$REPO_ROOT/scripts/lib/agent_config.sh" 2>/dev/null || true
    for _nn in $(get_ninja_names 2>/dev/null); do
        [ "$_nn" = "$_SS_NINJA" ] && { _SS_VALID=true; break; }
    done
    if [ "$_SS_VALID" = "true" ] && [ -f "$_SS_TASK_YAML" ]; then
        python3 - "$_SS_TASK_YAML" "$REPORT_PATH" "$REASONS" "$REPO_ROOT" <<'SESSION_STATE_PY' 2>/dev/null || true
import yaml, sys, re, os, tempfile
sys.path.insert(0, sys.argv[4])
from scripts.lib.yaml_atomic import yaml_text

task_yaml = sys.argv[1]
report_yaml = sys.argv[2]
block_reason = sys.argv[3]

with open(task_yaml, encoding='utf-8') as f:
    raw = f.read()

report_data = {}
try:
    with open(report_yaml, encoding='utf-8') as f:
        report_data = yaml.safe_load(f) or {}
except Exception:
    report_data = {}

diagnose_reason = ""
approach_summary = ""
if isinstance(report_data, dict):
    diagnose_reason = str(report_data.get('diagnose_reason', '') or '').strip()
    result_node = report_data.get('result') or {}
    if isinstance(result_node, dict):
        approach_summary = str(result_node.get('summary', '') or '').strip()

try:
    data = yaml.safe_load(raw) or {}
    task_node = data.get('task') or data
    ss = task_node.get('session_state') or {}
    attempt = int(ss.get('attempt', 0)) + 1
    tried = list(ss.get('tried_approaches', []))
    prior_attempts = list(ss.get('prior_attempts', []))
except Exception:
    attempt = 1
    tried = []
    prior_attempts = []

if block_reason and block_reason not in tried:
    tried.append(block_reason)

new_attempt = {
    'attempt': attempt,
    'block_reason': block_reason,
}
if diagnose_reason:
    new_attempt['diagnose_reason'] = diagnose_reason
if approach_summary:
    new_attempt['approach_summary'] = approach_summary

prior_attempts = [p for p in prior_attempts if isinstance(p, dict)]
prior_attempts.append(new_attempt)
prior_attempts = prior_attempts[-3:]

# 手組みの単一引用(_sq)は禁止。報告本文(diagnose_reason / result.summary)は改行を含みうるが、
# 手組みだと継続行のインデントが常に2になり、(a)値の折り畳みで情報が歪み、(b)次回の
# ブロック置換(_i > 2 のみ skip)で旧継続行が消えずに残り、2度目の書き込みで
# ScannerError を起こす。実測: queue/tasks/saizo.yaml が本日2度破損した。
# ∴ dumper に任せる。改行は正しくエスケープされ、継続行は _i > 2 になるため次回も正しく消える。
ss_node = {
    'attempt': attempt,
    'last_block_reason': block_reason,
    'tried_approaches': list(tried),
}
if diagnose_reason:
    ss_node['diagnose_reason'] = diagnose_reason
if approach_summary:
    ss_node['approach_summary'] = approach_summary
ss_prior = []
for item in prior_attempts:
    entry = {
        'attempt': int(item.get('attempt', 0) or 0),
        'block_reason': str(item.get('block_reason', '') or ''),
    }
    if item.get('diagnose_reason'):
        entry['diagnose_reason'] = str(item.get('diagnose_reason'))
    if item.get('approach_summary'):
        entry['approach_summary'] = str(item.get('approach_summary'))
    ss_prior.append(entry)
ss_node['prior_attempts'] = ss_prior
frag = yaml_text(
    {'session_state': ss_node},
    allow_unicode=True,
    sort_keys=False,
    default_flow_style=False,
    width=10 ** 9,
).rstrip('\n')
indented = '\n'.join('  ' + l for l in frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('session_state:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_yaml), suffix='.ss_tmp')
os.close(fd)
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(raw)
os.replace(tmp, task_yaml)
print(f'[SESSION_STATE] attempt={attempt} block_reason={block_reason[:50]!r} prior_attempts={len(prior_attempts)}', file=sys.stderr)
SESSION_STATE_PY
    fi
    exit 1
fi
