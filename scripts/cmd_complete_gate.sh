#!/bin/bash

# Freeze the complete execution source before parsing the gate body.  Pregate
# convergence may atomically replace the canonical script after a source-only
# publication; without this boundary Bash can continue reading later chunks
# from a different generation and stop on an otherwise-valid mixed program.
if [ -z "${CMD_COMPLETE_GATE_EXECUTION_SNAPSHOT:-}" ]; then
    _cges_source="${BASH_SOURCE[0]}"
    [[ "$_cges_source" != /* ]] && _cges_source="$PWD/$_cges_source"
    _cges_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/cmd-complete-gate.XXXXXXXX") || exit 1
    _cges_snapshot="$_cges_tmpdir/cmd_complete_gate.sh"
    if ! cp -- "$_cges_source" "$_cges_snapshot"; then
        rmdir -- "$_cges_tmpdir" 2>/dev/null || true
        exit 1
    fi
    CMD_COMPLETE_GATE_EXECUTION_SNAPSHOT="$_cges_snapshot" \
    CMD_COMPLETE_GATE_CANONICAL_SOURCE="$_cges_source" \
        bash "$_cges_snapshot" "$@"
    _cges_rc=$?
    rm -f -- "$_cges_snapshot"
    rmdir -- "$_cges_tmpdir" 2>/dev/null || true
    exit "$_cges_rc"
fi

# Bounded contract probe: prove that replacing the canonical source cannot
# change bytes observed by the running snapshot.  Normal gate runs never set
# these paths.
if [ -n "${CMD_COMPLETE_GATE_SNAPSHOT_PROBE_READY:-}" ]; then
    _cges_before=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')
    : > "$CMD_COMPLETE_GATE_SNAPSHOT_PROBE_READY"
    _cges_wait=0
    while [ ! -e "${CMD_COMPLETE_GATE_SNAPSHOT_PROBE_RELEASE:?}" ] && [ "$_cges_wait" -lt 100 ]; do
        sleep 0.05
        _cges_wait=$((_cges_wait + 1))
    done
    [ -e "$CMD_COMPLETE_GATE_SNAPSHOT_PROBE_RELEASE" ] || exit 75
    _cges_after=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')
    [ "$_cges_before" = "$_cges_after" ] || exit 76
    printf 'snapshot_immutable=1 canonical=%s\n' "$CMD_COMPLETE_GATE_CANONICAL_SOURCE"
    exit 0
fi

# C6-02: Keep the result of the command's target checks distinct from the
# repository-wide workflow result.  This small pure evaluator is also exposed
# to fixtures so the fail-closed truth table cannot drift with gh output.
evaluate_ci_readiness_json() {
    python3 -c '
import json, sys
from datetime import datetime, timezone
d=json.load(sys.stdin)
t=d.get("target_result")
w=d.get("workflow_result")
expected=str(d.get("expected_head_sha") or "")
reviewed_at=d.get("reviewed_at")
workflow_started_at=w.get("started_at") if isinstance(w, dict) else None
workflow_freshness_at=workflow_started_at or (w.get("created_at") if isinstance(w, dict) else None)
if not isinstance(t, dict) or not isinstance(w, dict):
    print("BLOCK: typed target_result/workflow_result required")
    raise SystemExit(1)
for name, value in (("target_result", t), ("workflow_result", w)):
    if not isinstance(value.get("conclusion"), str) or not isinstance(value.get("head_sha"), str):
        print(f"BLOCK: {name} conclusion/head_sha type invalid")
        raise SystemExit(1)
workflow_status=w.get("status")
if workflow_status is None:
    # Backward-compatible input for callers predating typed workflow status.
    workflow_status="completed" if w.get("conclusion") else "unknown"
if not isinstance(workflow_status, str):
    print("BLOCK: workflow_result status type invalid")
    raise SystemExit(1)
if not isinstance(reviewed_at, str) or not isinstance(workflow_freshness_at, str):
    print("BLOCK: reviewed_at/workflow_result.started_at type invalid")
    raise SystemExit(1)
def parse_aware(value, name):
    try:
        parsed=datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        print(f"BLOCK: {name} datetime parse failed")
        raise SystemExit(1)
    if parsed.tzinfo is None:
        print(f"BLOCK: {name} timezone missing")
        raise SystemExit(1)
    return parsed.astimezone(timezone.utc)
reviewed=parse_aware(reviewed_at, "reviewed_at")
started=parse_aware(workflow_freshness_at, "workflow_result.started_at")
# push通過+CI後追い方式(殿裁可 2026-07-25 / 軍師REQUEST_CHANGES反映)。
# 判定は3状態のみ: (i)対応する評価がGREEN=PASS (ii)対応する評価がRED=BLOCK
# (iii)このコードに対する評価が存在しない=WAIT(後追い確認。GATEを止めない)。
# 「別commitの評価」「未完了run」「全job cancelled」はいずれも同一の意味であり、
# 分岐を足さずこの1つの状態判定へ集約する。単に条件を削ると stale GREEN で
# 未検証CLEAR、stale RED で誤帰属BLOCKになるため、削除ではなく状態化する。
NO_VERDICT={"cancelled", "canceled", "skipped", "stale", "neutral", "action_required", ""}
jobs=w.get("jobs_conclusions")
absent=[]
if not expected or t["head_sha"] != expected or w["head_sha"] != expected:
    absent.append("head_sha_mismatch")
if workflow_status != "completed":
    absent.append(f"run_pending:{workflow_status}")
if started < reviewed:
    absent.append("run_predates_review")
if str(t["conclusion"]).lower() in NO_VERDICT:
    absent.append("target_no_verdict")
if str(w["conclusion"]).lower() in NO_VERDICT:
    absent.append("workflow_no_verdict")
elif isinstance(jobs, list) and jobs and all(
    str(job or "").lower() in NO_VERDICT for job in jobs
):
    # GitHubは全jobがcancelledのrunにも conclusion=failure を付ける。
    # 「評価が無い」を「赤い評価」と読み違えないための一次情報がjob結論である。
    absent.append("workflow_all_jobs_cancelled")
if absent:
    print("WAIT: ci_evaluation_absent=[" + ",".join(absent) + "] — 後追いで確認せよ(GATEは止めない) head_sha=" + (expected or "unresolved"))
    raise SystemExit(0)
if t["conclusion"] != "success":
    print("BLOCK: target_result is not GREEN")
    raise SystemExit(1)
if w["conclusion"] != "success":
    print("BLOCK: workflow_result is not GREEN")
    raise SystemExit(1)
print("READY: target_result=GREEN workflow_result=GREEN fresh_after_review head_sha=" + expected)
' 
}

# cmd_karo_impl_gate_metrics_record_split_20260725 (設計書v2.4 B20):
# gate_metrics.log の記録カテゴリを3分離する。
#   BLOCK = terminalな失敗(修正しない限り解けない)
#   WAIT  = 評価が存在しない(head SHA mismatch / run未完了 / review前のrun /
#           全job cancelled 等)。後追いで解ける。修正再配備の対象ではない
#   INFO  = 参考情報(記録はするが失敗率の分母/分子に混ぜない)
# 判定ロジックは新設しない。evaluate_ci_readiness_json の absent 集約が出力する
# トークンをそのまま記録カテゴリへ写像する(判定の二重定義を避ける — L563)。
# 実測(2026-07-25): ci_readiness BLOCK 108件のうち terminal は24件(22.2%)のみで、
# 残り84件は評価不在。全件BLOCK記録がBLOCK率を実態の4.5倍に見せていた。
classify_gate_record_category() {
    local reason="$1"
    case "$reason" in
        INFO:*|*"|INFO:"*)
            printf 'INFO\n' ;;
        # absent集約トークン(evaluate_ci_readiness_json由来)と、
        # 同義の旧表記(実測ログに残る文言)を同一カテゴリへ写像する。
        *ci_evaluation_absent=*|*head_sha_mismatch*|*run_pending:*|*run_predates_review*|\
        *target_no_verdict*|*workflow_no_verdict*|*workflow_all_jobs_cancelled*|\
        *"WAIT:"*|*"head SHA mismatch"*|*"predates SG7 review"*|*"pending status="*|\
        *"pending in_progress"*|*"pending queued"*|*cancelled*|*canceled*)
            printf 'WAIT\n' ;;
        *)
            printf 'BLOCK\n' ;;
    esac
}

# '|'区切りの複合理由を1カテゴリへ集約する。terminalが1件でも混ざればBLOCK
# (fail-closed)。全てが評価不在ならWAIT、全てが参考情報ならINFO。
classify_gate_record_reasons() {
    local joined="$1"
    local reason category has_wait=0 has_info=0
    [ -n "$joined" ] || { printf 'BLOCK\n'; return 0; }
    local _old_ifs="$IFS"
    IFS='|'
    # shellcheck disable=SC2086
    set -- $joined
    IFS="$_old_ifs"
    for reason in "$@"; do
        [ -n "$reason" ] || continue
        category=$(classify_gate_record_category "$reason")
        case "$category" in
            BLOCK) printf 'BLOCK\n'; return 0 ;;
            WAIT) has_wait=1 ;;
            INFO) has_info=1 ;;
        esac
    done
    if [ "$has_wait" -eq 1 ]; then
        printf 'WAIT\n'
    elif [ "$has_info" -eq 1 ]; then
        printf 'INFO\n'
    else
        printf 'BLOCK\n'
    fi
}

# B25: ci_readiness記録へ生値(workflow run_id / conclusion)を併記する。
# 既存カラム順は変えず末尾へ追加する(後方互換)。丸めた「is not GREEN」からは
# 「真のfailure」と「cancelled」を事後分解できないため、一次情報を残す。
format_ci_raw_columns() {
    local run_id="${1:-}"
    local conclusion="${2:-}"
    printf 'ci_run_id=%s\tci_conclusion=%s' "${run_id:-none}" "${conclusion:-none}"
}

# 歯止め(a)の一次情報: queue/tasks配下に task_type=ci_fix かつ ci_run_id 一致の
# activeタスクが存在するか。gate_karo_startup.sh Check 0.9と同じ機械証跡を使い、
# 判定基準の二重定義を避ける(新規台帳を作らない)。
ci_fix_task_deployed() {
    local run_id="$1"
    local tasks_dir="${CMD_COMPLETE_GATE_TASKS_DIR:-$SCRIPT_DIR/queue/tasks}"
    [ -n "$run_id" ] || return 1
    [ -d "$tasks_dir" ] || return 1
    python3 - "$tasks_dir" "$run_id" <<'PY'
from pathlib import Path
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

tasks_dir = Path(sys.argv[1])
run_id = sys.argv[2]
active = {"assigned", "acknowledged", "in_progress", "done"}
for path in sorted(tasks_dir.glob("*.yaml")):
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        continue
    task = doc.get("task", doc) if isinstance(doc, dict) else {}
    if not isinstance(task, dict):
        continue
    if str(task.get("task_type", "")) != "ci_fix":
        continue
    if str(task.get("ci_run_id", "")) != run_id:
        continue
    if str(task.get("status", "")) in active:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

format_gate_block_message() {
    local cmd_id="$1"
    local block_reason="$2"
    local missing_list="${3:-}"
    local dedup_key="${cmd_id} gate_result: BLOCK reason=${block_reason}"

    case "$block_reason" in
        *"ci_readiness:BLOCK: workflow_result pending status="*)
            printf '%s missing=[%s]。CI完了通知を待機し、完了後に同じcmdを再ゲートせよ。修正再配備は不要。\n' \
                "$dedup_key" "$missing_list"
            ;;
        *)
            printf '%s missing=[%s]。再配備提案: BLOCK理由を確認し、該当忍者へ修正再配備せよ。\n' \
                "$dedup_key" "$missing_list"
            ;;
    esac
}

# Vercel phase emits a machine-readable reason before returning non-zero.
# Preserve the human output while preventing line-limit debt from being
# misclassified as a broken research reference in the completion ledger.
classify_vercel_phase_output() {
    local output="$1"
    case "$output" in
        *"GATE_REASON=vercel_phase:line_limit_exceeded"*)
            printf 'vercel_phase:line_limit_exceeded\n' ;;
        *"GATE_REASON=vercel_phase:broken_references"*)
            printf 'vercel_phase:broken_references\n' ;;
        *)
            printf 'vercel_phase:unknown_failure\n' ;;
    esac
}

# CI is shared at the pushed branch boundary, not at a dirty/shared
# worktree's local HEAD.  Missing remote refs deliberately resolve to empty;
# evaluate_ci_readiness_json then fails closed on that empty expectation.
resolve_ci_expected_head() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse --verify refs/remotes/origin/main 2>/dev/null \
        || git -C "$repo_dir" rev-parse --verify refs/remotes/origin/master 2>/dev/null \
        || true
}

# Resolve the repository that owns report.commit_hash from the same typed
# commit_contract used by gate_report_format.  project remains the fallback
# only when repo_root is omitted.
resolve_report_commit_repo() {
    local report_file="$1"
    local task_file="${2:-}"
    local fallback_repo="${3:-$SCRIPT_DIR}"

    if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
        printf '%s\n' "$fallback_repo"
        return 0
    fi

    PROJECT_ROOT="$SCRIPT_DIR" python3 - \
        "$report_file" "$task_file" "$SCRIPT_DIR" "$fallback_repo" \
        "${COMMIT_REPO_RESOLVER_MAIN:-$SCRIPT_DIR/scripts/gates/gate_report_format_main.py}" <<'PY'
import importlib.util
import pathlib
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

report_path, task_path, root, fallback_repo, module_file = sys.argv[1:]
try:
    report = yaml.safe_load(pathlib.Path(report_path).read_text(encoding="utf-8")) or {}
    task_raw = yaml.safe_load(pathlib.Path(task_path).read_text(encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    print("BLOCK: commit repository contract input is unreadable")
    raise SystemExit
task = task_raw.get("task", task_raw)

module_path = pathlib.Path(module_file)
spec = importlib.util.spec_from_file_location("gate_report_format_main", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
contract, error = module._resolved_commit_contract(report, task)
if error:
    print("BLOCK: " + error)
    raise SystemExit
if not str((contract or {}).get("repo_root") or "").strip():
    print(pathlib.Path(fallback_repo).resolve())
    raise SystemExit
repo, error = module._resolve_commit_repo(report, task, pathlib.Path(root), contract)
if error:
    print("BLOCK: " + error)
else:
    print(repo)
PY
}

# Decide whether a report crossed the shared remote completion boundary.
# Free text and files_modified describe work, not publication.  The only
# publication proof is a valid report commit contained by origin/main|master.
report_ci_push_state() {
    local report_file="$1"
    local repo_dir="${2:-$SCRIPT_DIR}"
    local task_file="${3:-}"
    local expected_head report_commit report_kind

    expected_head=$(resolve_ci_expected_head "$repo_dir")
    if [ -z "$expected_head" ]; then
        echo "BLOCK: remote main/master boundary missing"
        return 0
    fi

    IFS=$'\t' read -r report_kind report_commit < <(REPORT_FILE="$report_file" TASK_FILE="$task_file" REPO_ROOT="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}" python3 - <<'PY'
import pathlib
import re
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

try:
    with open(os.environ["REPORT_FILE"], encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    print("invalid\t")
    raise SystemExit

task_file = os.environ.get("TASK_FILE", "")
if task_file:
    try:
        with open(task_file, encoding="utf-8") as f:
            task_raw = yaml.safe_load(f) or {}
        task = task_raw.get("task", task_raw)
    except Exception:
        print("invalid\t")
        raise SystemExit
    report_contract = report.get("commit_contract")
    task_contract = task.get("commit_contract") if isinstance(task, dict) else None
    if isinstance(task_contract, str):
        try:
            import json
            decoded_contract = json.loads(task_contract)
        except (TypeError, ValueError):
            decoded_contract = None
        if isinstance(decoded_contract, dict):
            task_contract = decoded_contract
    report_type = str(
        (report_contract or {}).get("task_type") or report.get("task_type") or ""
    ).strip()
    task_type = str(
        (task_contract or {}).get("task_type") or task.get("task_type") or ""
    ).strip()
    files = report.get("files_modified")
    commit = str(report.get("commit_hash") or "").strip()
    no_code_types = {
        "no-code", "no_code", "decision", "decision_candidate",
        "data-readonly", "data_readonly", "readonly", "read_only",
        "recon", "recon2", "scout",
    }
    # A readonly worker legitimately writes its own report artifact even though
    # its project commit contract is no-code.  Compare the resolved path to the
    # report currently being gated; do not allow arbitrary queue/report paths.
    report_path = pathlib.Path(os.environ["REPORT_FILE"]).resolve()
    root_path = pathlib.Path(os.environ.get("REPO_ROOT", ".")).resolve()
    only_self_report = files == []
    if isinstance(files, list) and files:
        resolved_files = []
        for item in files:
            value = item.get("path") if isinstance(item, dict) else item
            value = str(value or "").strip()
            if not value:
                resolved_files = []
                break
            candidate = pathlib.Path(value)
            if not candidate.is_absolute():
                candidate = root_path / candidate
            resolved_files.append(candidate.resolve())
        only_self_report = bool(resolved_files) and all(
            candidate == report_path for candidate in resolved_files
        )
    if (
        isinstance(report_contract, dict)
        and isinstance(task_contract, dict)
        and report_contract.get("required") is False
        and task_contract.get("required") is False
        and report_type in no_code_types
        and task_type in no_code_types
        and report_type == task_type
        and only_self_report
        and commit in {"", "no-code-change"}
    ):
        print("contract-no-code\t")
        raise SystemExit

files = report.get("files_modified") or []
if isinstance(files, str):
    files = [files]
paths = []
for item in files if isinstance(files, list) else []:
    value = item.get("path") if isinstance(item, dict) else item
    paths.append(str(value or "").strip().lower().replace("_", "-"))
if paths and all(value == "no-code-change" for value in paths):
    print("sentinel\t")
    raise SystemExit

commit = str(report.get("commit_hash") or "").strip()
if commit == "no-code-change":
    evidence = report.get("no_code_change_evidence")
    before = str(evidence.get("before_tree") or "").strip().lower() if isinstance(evidence, dict) else ""
    after = str(evidence.get("after_tree") or "").strip().lower() if isinstance(evidence, dict) else ""
    unchanged = evidence.get("tree_unchanged") if isinstance(evidence, dict) else None
    if unchanged is True and before == after and re.fullmatch(r"[0-9a-f]{40}", before):
        print("tree-sentinel\t" + before)
    else:
        print("invalid-no-code-evidence\t\t")
    raise SystemExit
if not commit:
    # 軍師D0(2026-07-27): 同一のno-code報告に対し、review_approval.sh側の
    # permits_no_code_identity(files_modifiedがqueue/logs配下 + no_code_change_evidence
    # + explicit_no_commit)と本gate(files_modifiedが全てliteral "no-code-change"、
    # または commit_hash=="no-code-change")が別契約を要求していた。
    # 前者を満たしてLGTMまで到達した報告が後者で"invalid"となりBLOCKする
    # (才蔵 cmd_karo_recon2_r5_utf8_revalidation_20260727 で実証)。
    # 共有契約 report_commit_identity へ統一する。緩和ではない: 同関数は
    # evidence(tree_unchanged/before==after/40hex)と明示no-commit宣言と
    # 運用パス限定の3条件すべてを要求し、1つでも欠ければ従来どおりinvalidへ落ちる。
    root = pathlib.Path(os.environ.get("REPO_ROOT", ".")).resolve()
    sys.path.insert(0, str(root / "scripts" / "lib"))
    from report_commit_identity import permits_no_code_identity

    if permits_no_code_identity(report, root):
        evidence = report.get("no_code_change_evidence") or {}
        print("tree-sentinel\t" + str(evidence.get("before_tree") or "").strip().lower())
        raise SystemExit
if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
    print("invalid\t" + commit)
else:
    print("commit\t" + commit.lower())
PY
)

    if [ "$report_kind" = "contract-no-code" ]; then
        echo "UNPUSHED: commit_contract no-code task"
    elif [ "$report_kind" = "sentinel" ]; then
        echo "UNPUSHED: no-code-change sentinel"
    elif [ "$report_kind" = "tree-sentinel" ]; then
        if git -C "$repo_dir" cat-file -e "${report_commit}^{tree}" 2>/dev/null; then
            echo "UNPUSHED: no-code-change tree sentinel ($report_commit)"
        else
            echo "BLOCK: no-code-change tree unresolvable ($report_commit)"
        fi
    elif [ "$report_kind" = "invalid-no-code-evidence" ]; then
        echo "BLOCK: no-code-change evidence invalid"
    elif [ "$report_kind" != "commit" ]; then
        echo "BLOCK: report commit invalid or unresolvable${report_commit:+ ($report_commit)}"
    elif git -C "$repo_dir" cat-file -e "${report_commit}^{commit}" 2>/dev/null; then
        if git -C "$repo_dir" merge-base --is-ancestor "$report_commit" "$expected_head" 2>/dev/null; then
            echo "PUSHED: report commit $report_commit contained by $expected_head"
        else
            echo "UNPUSHED: report commit $report_commit not contained by $expected_head"
        fi
    else
        # Primary repo cannot resolve commit; try cross_repo_commits for an alternate repo.
        local cross_repo_dir cross_repo_head
        cross_repo_dir=$(REPORT_FILE="$report_file" COMMIT="$report_commit" python3 - <<'PY'
import os, yaml
try:
    with open(os.environ["REPORT_FILE"], encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit
target = os.environ.get("COMMIT", "").lower()
for entry in report.get("cross_repo_commits") or []:
    if not isinstance(entry, dict):
        continue
    commit = str(entry.get("commit_hash") or "").strip().lower()
    if commit == target:
        print(str(entry.get("repo") or ""))
        raise SystemExit
PY
)
        if [ -n "$cross_repo_dir" ] \
            && git -C "$cross_repo_dir" cat-file -e "${report_commit}^{commit}" 2>/dev/null; then
            cross_repo_head=$(resolve_ci_expected_head "$cross_repo_dir")
            if [ -z "$cross_repo_head" ]; then
                echo "BLOCK: cross-repo remote main/master boundary missing ($cross_repo_dir)"
            elif git -C "$cross_repo_dir" merge-base --is-ancestor "$report_commit" "$cross_repo_head" 2>/dev/null; then
                echo "PUSHED: report commit $report_commit contained by $cross_repo_head"
            else
                echo "UNPUSHED: report commit $report_commit not contained by $cross_repo_head"
            fi
        else
            echo "BLOCK: report commit invalid or unresolvable${report_commit:+ ($report_commit)}"
        fi
    fi
}

# A report's commit identity is the completion artifact.  CI status is only a
# diagnostic follow-up, so an UNPUSHED result there historically did not stop
# CLEAR.  The terminal gate must use the same canonical-repository resolution,
# but fail closed for ordinary PASS reports.  The two no-code contracts remain
# informational because they intentionally have no project commit to publish.
report_commit_main_ancestry_state() {
    local report_file="$1"
    local repo_dir="${2:-$SCRIPT_DIR}"
    local task_file="${3:-}"
    local state

    state=$(report_ci_push_state "$report_file" "$repo_dir" "$task_file")
    case "$state" in
        PUSHED:*)
            printf 'PASS: %s\n' "$state"
            return 0
            ;;
        UNPUSHED:\ commit_contract\ no-code\ task|UNPUSHED:\ no-code-change\ sentinel|UNPUSHED:\ no-code-change\ tree\ sentinel\ *)
            printf 'SKIP: %s\n' "$state"
            return 0
            ;;
        *)
            printf 'BLOCK: report commit main ancestry: %s\n' "$state"
            return 1
            ;;
    esac
}

# Terminal publication must prove the bytes described by a PASS report reached
# the canonical remote tip.  Commit ancestry alone is insufficient: an older
# source commit can be an ancestor while a later publication has reverted or
# otherwise replaced one of the report's ordinary source paths.  Operational
# records are intentionally excluded because their existing field-aware,
# monotonic publication contracts are the source of truth for those paths.
report_blob_parity_mutable_path() {
    case "${1:-}" in
        queue/*|logs/*|tasks/lessons.md|projects/*/lessons.yaml|\
        archive/cmd-chronicle/*|dashboard.md|*.log)
            return 0 ;;
    esac
    return 1
}

report_commit_blob_parity_state() {
    local report_file="$1"
    local repo_dir="${2:-$SCRIPT_DIR}"
    local task_file="${3:-}"
    local source_sha expected_head path source_blob remote_blob
    local normal_count=0 matched_count=0 mutable_count=0 mismatch_count=0
    local raw_path

    source_sha="$(FIELD_GET_NO_LOG=1 field_get "$report_file" commit_hash "")"
    case "$source_sha" in
        no-code-change|"")
            printf 'SKIP: report commit blob parity: no-code report\n'
            return 0 ;;
    esac
    [[ "$source_sha" =~ ^[0-9a-fA-F]{40}$ ]] || {
        printf 'BLOCK: report commit blob parity: invalid source commit %s\n' "$source_sha"
        return 1
    }

    # Resolve the same canonical repository used by the ancestry check.  This
    # keeps cross-repository reports from silently comparing against the
    # platform repository.
    if [ -n "$task_file" ] && [ -f "$task_file" ]; then
        repo_dir="$(resolve_report_commit_repo "$report_file" "$task_file" "$repo_dir")" || {
            printf 'BLOCK: report commit blob parity: repository resolution failed\n'
            return 1
        }
        [[ "$repo_dir" != BLOCK:* ]] || {
            printf 'BLOCK: report commit blob parity: %s\n' "$repo_dir"
            return 1
        }
    fi
    expected_head="$(resolve_ci_expected_head "$repo_dir")"
    [ -n "$expected_head" ] || {
        printf 'BLOCK: report commit blob parity: remote main/master boundary missing\n'
        return 1
    }
    if ! git -C "$repo_dir" cat-file -e "${source_sha}^{commit}" 2>/dev/null; then
        # Taskless archived reports can carry an explicit cross-repository
        # source contract.  Mirror report_ci_push_state's fallback instead of
        # silently treating the platform repository as the source of truth.
        local cross_repo_dir
        cross_repo_dir="$(REPORT_FILE="$report_file" COMMIT="$source_sha" python3 - <<'PY'
import os
import yaml
try:
    report = yaml.safe_load(open(os.environ["REPORT_FILE"], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    raise SystemExit
target = os.environ.get("COMMIT", "").strip().lower()
for entry in report.get("cross_repo_commits") or []:
    if isinstance(entry, dict) and str(entry.get("commit_hash") or "").strip().lower() == target:
        print(str(entry.get("repo") or ""))
        break
PY
        )"
        if [ -n "$cross_repo_dir" ] && git -C "$cross_repo_dir" cat-file -e "${source_sha}^{commit}" 2>/dev/null; then
            repo_dir="$cross_repo_dir"
            expected_head="$(resolve_ci_expected_head "$repo_dir")"
        else
            printf 'BLOCK: report commit blob parity: source commit unavailable %s\n' "$source_sha"
            return 1
        fi
    fi
    git -C "$repo_dir" cat-file -e "${expected_head}^{commit}" 2>/dev/null || {
        printf 'BLOCK: report commit blob parity: expected head unavailable %s\n' "$expected_head"
        return 1
    }

    while IFS= read -r raw_path; do
        [ -n "$raw_path" ] || continue
        path="$raw_path"
        case "$path" in
            "$repo_dir"/*) path="${path#"$repo_dir"/}" ;;
            /*)
                printf 'BLOCK: report commit blob parity: path outside repository %s\n' "$path"
                return 1 ;;
        esac
        if report_blob_parity_mutable_path "$path"; then
            mutable_count=$((mutable_count + 1))
            continue
        fi
        normal_count=$((normal_count + 1))
        source_blob="$(git -C "$repo_dir" rev-parse "${source_sha}:${path}" 2>/dev/null || printf '__ABSENT__')"
        remote_blob="$(git -C "$repo_dir" rev-parse "${expected_head}:${path}" 2>/dev/null || printf '__ABSENT__')"
        if [ "$source_blob" = "$remote_blob" ]; then
            matched_count=$((matched_count + 1))
        else
            mismatch_count=$((mismatch_count + 1))
            printf '  MISMATCH path=%s source_blob=%s remote_blob=%s\n' "$path" "$source_blob" "$remote_blob"
        fi
    done < <(REPORT_FILE="$report_file" python3 - <<'PY'
import os
import yaml
try:
    report = yaml.safe_load(open(os.environ["REPORT_FILE"], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    raise SystemExit
files = report.get("files_modified") or []
if isinstance(files, str):
    files = [files]
if isinstance(files, list):
    for item in files:
        value = item.get("path") if isinstance(item, dict) else item
        value = str(value or "").strip()
        if value and value not in ("no-code-change", "no_code_change"):
            print(value)
PY
    )

    if [ "$mismatch_count" -gt 0 ]; then
        printf 'BLOCK: report commit blob parity: normal_paths=%d matched=%d mismatched=%d mutable_skipped=%d source=%s remote=%s\n' \
            "$normal_count" "$matched_count" "$mismatch_count" "$mutable_count" "$source_sha" "$expected_head"
        return 1
    fi
    if [ "$normal_count" -eq 0 ]; then
        printf 'SKIP: report commit blob parity: normal_paths=0 mutable_skipped=%d\n' "$mutable_count"
    else
        printf 'PASS: report commit blob parity: normal_paths=%d matched=%d mismatched=0 mutable_skipped=%d source=%s remote=%s\n' \
            "$normal_count" "$matched_count" "$mutable_count" "$source_sha" "$expected_head"
    fi
}

check_report_commit_blob_parity() {
    local report_file task_file task_repo report_verdict state
    local checked=false failed=false
    local -A seen_reports=()

    check_one_report() {
        report_file="$1"
        task_file="${2:-}"
        task_repo="${3:-$SCRIPT_DIR}"
        [ -f "$report_file" ] || return 0
        report_file="$(realpath "$report_file")" || return 1
        [ -z "${seen_reports[$report_file]+yes}" ] || return 0
        seen_reports["$report_file"]=1
        report_verdict="$(FIELD_GET_NO_LOG=1 field_get "$report_file" verdict "")"
        case "$report_verdict" in
            PASS|PASS_NO_IMPROVEMENT) ;;
            *) return 0 ;;
        esac
        checked=true
        if state=$(report_commit_blob_parity_state "$report_file" "$task_repo" "$task_file"); then
            printf '  %s: %s\n' "$report_file" "$state"
        else
            printf '  %s: %s\n' "$report_file" "$state"
            failed=true
        fi
    }

    if [ -n "${CMD_COMPLETE_GATE_CI_REPORT:-}" ]; then
        check_one_report "$CMD_COMPLETE_GATE_CI_REPORT" \
            "${CMD_COMPLETE_GATE_TASK_FILE:-}" "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$SCRIPT_DIR}"
    else
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            task_repo="$(resolve_task_repo_dir "$task_file" 2>/dev/null || printf '%s' "$SCRIPT_DIR")"
            report_file="$(resolve_report_file "$(basename "$task_file" .yaml)" "$CMD_ID" "$task_file" 2>/dev/null || true)"
            [ -n "$report_file" ] || continue
            check_one_report "$report_file" "$task_file" "$task_repo" || failed=true
        done
        while IFS= read -r report_file; do
            [ -n "$report_file" ] || continue
            check_one_report "$report_file" "" "$SCRIPT_DIR" || failed=true
        done < <(discover_terminal_reports_for_cmd "$CMD_ID")
    fi

    if [ "$checked" = false ]; then
        echo "  SKIP (no PASS reports requiring a commit blob parity check)"
    fi
    [ "$failed" = false ]
}

discover_terminal_reports_for_cmd() {
    local cmd_id="${1:-$CMD_ID}"
    REPORTS_ROOT="$SCRIPT_DIR" CMD_ID="$cmd_id" python3 - <<'PY'
import glob
import os
import pathlib
import yaml

root = pathlib.Path(os.environ["REPORTS_ROOT"])
cmd_id = os.environ["CMD_ID"]
paths = []
for directory in (root / "queue" / "reports", root / "queue" / "archive" / "reports"):
    paths.extend(glob.glob(str(directory / "**" / "*.yaml"), recursive=True))
seen = set()
for raw_path in sorted(paths):
    path = pathlib.Path(raw_path)
    try:
        resolved = path.resolve()
        if resolved in seen or not resolved.is_file():
            continue
        report = yaml.safe_load(resolved.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        continue
    if not isinstance(report, dict):
        continue
    if (str(report.get("parent_cmd") or "").strip() == cmd_id
            or str(report.get("task_id") or "").strip() == cmd_id):
        seen.add(resolved)
        print(resolved)
PY
}

check_report_commit_main_ancestry() {
    local report_file task_file task_repo report_verdict state
    local checked=false failed=false
    local -A seen_reports=()

    check_one_report() {
        report_file="$1"
        task_file="${2:-}"
        task_repo="${3:-$SCRIPT_DIR}"
        [ -f "$report_file" ] || return 0
        report_file="$(realpath "$report_file")" || return 1
        [ -z "${seen_reports[$report_file]+yes}" ] || return 0
        seen_reports["$report_file"]=1
        report_verdict="$(FIELD_GET_NO_LOG=1 field_get "$report_file" verdict "")"
        case "$report_verdict" in
            PASS|PASS_NO_IMPROVEMENT) ;;
            *) return 0 ;;
        esac
        checked=true
        if state=$(report_commit_main_ancestry_state "$report_file" "$task_repo" "$task_file"); then
            printf '  %s: %s\n' "$report_file" "$state"
        else
            printf '  %s: %s\n' "$report_file" "$state"
            failed=true
        fi
    }

    if [ -n "${CMD_COMPLETE_GATE_CI_REPORT:-}" ]; then
        check_one_report "$CMD_COMPLETE_GATE_CI_REPORT" \
            "${CMD_COMPLETE_GATE_TASK_FILE:-}" "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$SCRIPT_DIR}"
    else
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            task_repo=$(resolve_task_repo_dir "$task_file" 2>/dev/null || printf '%s' "$SCRIPT_DIR")
            report_file=$(resolve_report_file "$(basename "$task_file" .yaml)" "$CMD_ID" "$task_file" 2>/dev/null || true)
            [ -n "$report_file" ] || continue
            check_one_report "$report_file" "$task_file" "$task_repo" || failed=true
        done
        while IFS= read -r report_file; do
            [ -n "$report_file" ] || continue
            check_one_report "$report_file" "" "$SCRIPT_DIR" || failed=true
        done < <(discover_terminal_reports_for_cmd "$CMD_ID")
    fi

    if [ "$checked" = false ]; then
        echo "  SKIP (no PASS reports requiring a commit ancestry check)"
    fi
    [ "$failed" = false ]
}

if [ "${CMD_COMPLETE_GATE_CI_EVAL_ONLY:-0}" = "1" ]; then
    evaluate_ci_readiness_json
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_CLASSIFY_ONLY:-0}" = "1" ]; then
    # 記録カテゴリの純関数をfixtureへ露出する(判定表がgh出力とドリフトしないよう、
    # evaluate_ci_readiness_json と同じ方式で外から検証可能にする)。
    classify_gate_record_reasons "${CMD_COMPLETE_GATE_CLASSIFY_REASON:-}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_BLOCK_MESSAGE_ONLY:-0}" = "1" ]; then
    format_gate_block_message "${CMD_COMPLETE_GATE_BLOCK_CMD_ID:-cmd_test}" \
        "${CMD_COMPLETE_GATE_BLOCK_REASON:-}" "${CMD_COMPLETE_GATE_BLOCK_MISSING:-}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_VERCEL_REASON_ONLY:-0}" = "1" ]; then
    classify_vercel_phase_output "${CMD_COMPLETE_GATE_VERCEL_OUTPUT:-}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_CI_EXPECTED_HEAD_ONLY:-0}" = "1" ]; then
    resolve_ci_expected_head "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$PWD}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_COMMIT_REPO_ONLY:-0}" = "1" ]; then
    resolve_report_commit_repo \
        "${CMD_COMPLETE_GATE_CI_REPORT:?report required}" \
        "${CMD_COMPLETE_GATE_TASK_FILE:-}" \
        "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$PWD}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_CI_PUSH_STATE_ONLY:-0}" = "1" ]; then
    report_ci_push_state "${CMD_COMPLETE_GATE_CI_REPORT:?report required}" \
        "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$PWD}" \
        "${CMD_COMPLETE_GATE_TASK_FILE:-}"
    exit $?
fi
if [ "${CMD_COMPLETE_GATE_REPORT_MAIN_ANCESTRY_ONLY:-0}" = "1" ]; then
    report_commit_main_ancestry_state "${CMD_COMPLETE_GATE_CI_REPORT:?report required}" \
        "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$SCRIPT_DIR}" "${CMD_COMPLETE_GATE_TASK_FILE:-}"
    exit $?
fi
# cmd_complete_gate.sh — cmd完了時の全ゲートフラグ確認スクリプト（ディレクトリ方式）
# Usage: bash scripts/cmd_complete_gate.sh <cmd_id>
# Exit 0: GATE CLEAR (全ゲートdone、または緊急override)
# Exit 1: GATE BLOCK (未完了フラグあり)

set -e

# Read-only git invocations (status/diff/etc.) opportunistically refresh and
# rewrite the index via a transient .git/index.lock unless disabled. That
# optional write can race the runtime-publish writer's required index.lock
# below (cmd_karo_hotfix_git_index_singleflight_202608191445 AC2). Every git
# call in this script inherits this.
export GIT_OPTIONAL_LOCKS=0

CMD_ID="${1:-}"

if [ -z "$CMD_ID" ]; then
    printf 'Usage: cmd_complete_gate.sh <cmd_id>\n受け取った引数: %s\n' "$*" >&2
    exit 1
fi

if [[ "$CMD_ID" != cmd_* ]]; then
    printf 'ERROR: 第1引数はcmd_id（cmd_XXX形式）でなければならない。\nUsage: cmd_complete_gate.sh <cmd_id>\n受け取った引数: %s\n' "$*" >&2
    exit 1
fi

_cmd_complete_script="${CMD_COMPLETE_GATE_CANONICAL_SOURCE:-${BASH_SOURCE[0]}}"
[[ "$_cmd_complete_script" != /* ]] && _cmd_complete_script="$PWD/$_cmd_complete_script"
_cmd_complete_dir="${_cmd_complete_script%/*}"
SCRIPT_DIR="${_cmd_complete_dir%/scripts}"
unset _cmd_complete_dir
unset _cmd_complete_script

# Direct gate callers do not have the wrapper's marker environment, but the
# completion boundary must remain durable for every CLEAR path.  The wrapper
# still supplies the same generation-bound path explicitly.
if [ -z "${CMD_COMPLETE_GATE_CLEAR_MARKER:-}" ]; then
    CMD_COMPLETE_GATE_CLEAR_MARKER="$SCRIPT_DIR/queue/gates/${CMD_ID}/gate_worker.clear.json"
fi

# shellcheck source=scripts/lib/task_cmd_match.sh
source "$SCRIPT_DIR/scripts/lib/task_cmd_match.sh"

# --force フラグ検出
FORCE_MODE=false
for arg in "$@"; do
    if [ "$arg" = "--force" ]; then
        FORCE_MODE=true
    fi
done

# ─── CLEAR済みcmd早期exit（lib source前、GP-026 B案: cmd_1332） ───
# WSL2最適化: source/mkdir/flock前にCLEARチェック。CLEARED cmdsのlib読込コスト削減
LOG_DIR="$SCRIPT_DIR/logs"
GATE_METRICS_LOG="${GATE_METRICS_LOG:-$LOG_DIR/gate_metrics.log}"
if [ "$FORCE_MODE" = false ] && [ -f "$GATE_METRICS_LOG" ] \
   && [ ! -f "$SCRIPT_DIR/queue/reopened_cmds/${CMD_ID}.yaml" ]; then
    if grep -Fq $'\t'"${CMD_ID}"$'\tCLEAR\t' "$GATE_METRICS_LOG"; then
        echo "[gate] ${CMD_ID}: Already CLEARED (gate_metrics.logにCLEAR記録あり。--forceで再検査可能)"
        exit 0
    fi
fi

# WSL2 NTFS最適化: field_getの依存ログ抑制。28回×20ms=0.56s削減
export FIELD_GET_NO_LOG=1
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/task_lifecycle.sh"
source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
source "$SCRIPT_DIR/scripts/lib/autogen_paths.sh"

if [ "${CMD_COMPLETE_GATE_REPORT_BLOB_PARITY_ONLY:-0}" = "1" ]; then
    report_commit_blob_parity_state "${CMD_COMPLETE_GATE_CI_REPORT:?report required}" \
        "${CMD_COMPLETE_GATE_CI_REPO_DIR:-$SCRIPT_DIR}" "${CMD_COMPLETE_GATE_TASK_FILE:-}"
    exit $?
fi

# Resolve the git repository that owns a task.  Reports may describe work in
# an external project; treating every commit as a multi-agent-shogun commit
# makes valid external hashes unresolvable and turns repo-relative report
# paths into false scope drift.  Prefer the actual target_path git root, then
# projects/<id>.yaml project.path, and fail back to the platform repo.
resolve_task_repo_dir() {
    local task_file="$1"
    local task_meta project_id target_path task_worktree_path project_file project_path candidate root
    task_meta=$(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task", data)
target = task.get("target_path", "")
source_paths = task.get("task_worktree_source_paths", "")
if isinstance(source_paths, str):
    try:
        source_paths = yaml.safe_load(source_paths) or []
    except yaml.YAMLError:
        source_paths = []
if isinstance(source_paths, list) and source_paths:
    target = source_paths[0]
if isinstance(target, list):
    target = next((str(x) for x in target if str(x).strip()), "")
print(str(task.get("project") or ""))
print(str(target or ""))
print(str(task.get("task_worktree_path") or ""))
PY
)
    project_id=$(printf '%s\n' "$task_meta" | sed -n '1p')
    target_path=$(printf '%s\n' "$task_meta" | sed -n '2p')
    task_worktree_path=$(printf '%s\n' "$task_meta" | sed -n '3p')

    project_path=""
    project_file="$SCRIPT_DIR/projects/${project_id}.yaml"
    if [ -n "$project_id" ] && [ -f "$project_file" ]; then
        project_path=$(python3 - "$project_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
project = data.get("project", {})
print(str(project.get("path") or data.get("path") or ""))
PY
)
    fi

    for candidate in "$task_worktree_path" "$target_path" "$project_path" "$SCRIPT_DIR"; do
        [ -n "$candidate" ] || continue
        if root=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null); then
            printf '%s\n' "$root"
            return 0
        fi
    done
    printf '%s\n' "$SCRIPT_DIR"
}

# Editing and test attribution deliberately resolve to task_worktree_path, but
# publication must use the canonical repository that owns the remote/upstream.
# A linked worktree commonly has no branch upstream of its own; treating it as
# the push repository makes an already-published task fail at completion.
resolve_task_publish_repo_dir() {
    local task_file="$1" publish_meta task_worktree_repo contract_repo candidate root
    publish_meta=$(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task", data)
contract = task.get("commit_contract") or {}
if not isinstance(contract, dict):
    contract = {}
print(str(task.get("task_worktree_repo") or ""))
print(str(contract.get("repo_root") or ""))
PY
) || return 1
    task_worktree_repo=$(printf '%s\n' "$publish_meta" | sed -n '1p')
    contract_repo=$(printf '%s\n' "$publish_meta" | sed -n '2p')
    for candidate in "$task_worktree_repo" "$contract_repo"; do
        [ -n "$candidate" ] || continue
        if root=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null); then
            printf '%s\n' "$root"
            return 0
        fi
    done
    resolve_task_repo_dir "$task_file"
}

# cmd_karo_hotfix_cmd_complete_autopush_overlap_precheck_20260730:
# GA-PUSH1(.githooks/pre-push のdirty working tree guard)と同一の重複判定を
# git push呼出前に行う。判定は正しい(公開commitと未確定worktreeの不整合を防ぐ)が、
# cmd_complete_gateの自動pushはこれを予見できず、正当BLOCKを毎回git push失敗として
# 再通知していた(2026-07-30実測: hook失敗45件中32件=71%)。
# fail-close方針: 重複を確信を持って検出できた場合のみSKIPし、それ以外(base_sha
# 不明・dirtyなし・重複なし・除外後に重複が消える等)は必ず従来通りgit pushを試みる。
# manual git pushとpre-push GA-PUSH1本体は無改変のため、ここで見逃しても実push側で
# 変わらず守られる。通常source overlapを除外へ追加しない(AUTOGEN_PATH_EXCLUDE_REGEX
# はscripts/lib/autogen_paths.shの既存正本をそのまま使う)。
push_overlap_blocking_paths() {
    local repo="$1" head_sha="$3" upstream_sha="$4"
    local base_sha changed_files dirty_paths overlap overlap_blocking

    if [ -n "$upstream_sha" ]; then
        base_sha="$upstream_sha"
    else
        base_sha=$(git -C "$repo" merge-base "$head_sha" origin/main 2>/dev/null || true)
    fi
    [ -n "$base_sha" ] && [ -n "$head_sha" ] || return 0

    changed_files=$(git -C "$repo" diff --name-only "$base_sha" "$head_sha" 2>/dev/null | sort -u)
    [ -n "$changed_files" ] || return 0

    dirty_paths=$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null | cut -c4- | sort -u)
    [ -n "$dirty_paths" ] || return 0

    overlap=$(comm -12 <(printf '%s\n' "$changed_files") <(printf '%s\n' "$dirty_paths"))
    [ -n "$overlap" ] || return 0

    overlap_blocking="$overlap"
    if [ -n "${AUTOGEN_PATH_EXCLUDE_REGEX:-}" ]; then
        overlap_blocking=$(printf '%s\n' "$overlap" | grep -v -E "$AUTOGEN_PATH_EXCLUDE_REGEX" || true)
    fi
    [ -n "$overlap_blocking" ] || return 0

    printf '%s\n' "$overlap_blocking"
}

# Push a commit whose paths overlap the shared worktree's dirty paths without
# changing, stashing, or resetting that worktree.  The temporary detached
# worktree is intentionally the push execution root so the repository's normal
# pre-push hook still runs against a clean checkout and receives the exact
# commit being published.
resolve_push_source_commit() {
    local task_file="$1" repo="$2" report_file source_sha

    report_file=$(python3 - "$task_file" "$SCRIPT_DIR" <<'PY'
import os
import sys
import yaml

task_file, script_dir = sys.argv[1:]
try:
    with open(task_file, encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
except Exception:
    raise SystemExit(1)
task = data.get("task", data)
report = str(task.get("report_path") or task.get("report_filename") or "").strip()
if report and not os.path.isabs(report):
    report = os.path.join(script_dir, report)
print(report)
PY
    ) || return 1
    [ -n "$report_file" ] && [ -f "$report_file" ] || return 1

    source_sha=$(python3 - "$report_file" <<'PY'
import re
import sys
import yaml

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        report = yaml.safe_load(handle) or {}
except Exception:
    raise SystemExit(1)
value = str(report.get("commit_hash") or "").strip().lower()
if not re.fullmatch(r"[0-9a-f]{40}", value):
    raise SystemExit(1)
print(value)
PY
    ) || return 1
    git -C "$repo" cat-file -e "${source_sha}^{commit}" 2>/dev/null || return 1
    printf '%s\n' "$source_sha"
}

mark_task_worktree_published() {
    local task_file="$1" published_commit="$2" marker
    marker=$(python3 -c 'import sys,yaml; print(str(((yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}).get("task") or {}).get("task_worktree_marker") or "").strip())' "$task_file")
    [ -f "$marker" ] || return 0
    python3 -c 'import json,os,sys,tempfile,time; p,pub=sys.argv[1:]; d=json.load(open(p,encoding="utf-8")); assert d.get("version")==1 and d.get("state")=="active"; d["published_commit"]=pub; d["published_at_ns"]=time.time_ns(); fd,t=tempfile.mkstemp(prefix=".task_worktree_published.",dir=os.path.dirname(p)); f=os.fdopen(fd,"w",encoding="utf-8"); json.dump(d,f,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno()); f.close(); os.replace(t,p)' "$marker" "$published_commit"
}

# A successful source-only push must survive a later retry of the same gate.
# The task-worktree marker above is intentionally not sufficient: it has no
# cmd/report-generation or repository identity and cannot distinguish a stale
# or ambiguous pre-receipt from the current publication. This receipt is local
# operational state (queue/gates is excluded from runtime publication) and is
# written only after remote inclusion has been verified.
source_publish_receipt_path() {
    printf '%s\n' "${CMD_COMPLETE_GATE_SOURCE_PUBLISH_RECEIPT:-$SCRIPT_DIR/queue/gates/${CMD_ID}/source_only_publish.receipt.json}"
}

resolve_publish_report_generation() {
    local task_file="$1" script_dir="$2" report_file
    report_file=$(python3 - "$task_file" "$script_dir" <<'PY'
import os
import sys
import yaml

task_file, script_dir = sys.argv[1:]
task = (yaml.safe_load(open(task_file, encoding="utf-8")) or {}).get("task", {})
report = str(task.get("report_path") or task.get("report_filename") or "").strip()
if report and not os.path.isabs(report):
    report = os.path.join(script_dir, report)
print(report)
PY
    ) || return 1
    [ -n "$report_file" ] && [ -f "$report_file" ] || return 1
    python3 - "$report_file" "$task_file" <<'PY'
import sys
import yaml

report = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = (yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}).get("task", {})
if not isinstance(report, dict) or not isinstance(task, dict):
    raise SystemExit(1)
for value in (
    report.get("report_generation"),
    report.get("report_generation_fingerprint"),
    report.get("report_fingerprint"),
    report.get("report_id"),
    task.get("report_generation"),
    task.get("report_generation_fingerprint"),
    task.get("report_id"),
):
    value = str(value or "").strip()
    if value:
        print(value)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

source_publish_receipt_matches() {
    local receipt="$1" cmd_id="$2" completion_generation="$3" repo="$4"
    shift 4
    [ -f "$receipt" ] || return 1
    [ "$#" -gt 0 ] && [ $(( $# % 2 )) -eq 0 ] || return 1
    python3 - "$receipt" "$cmd_id" "$completion_generation" "$repo" "$@" <<'PY'
import json
import re
import sys

receipt, cmd_id, completion_generation, repo = sys.argv[1:5]
raw = sys.argv[5:]
expected = {(raw[i], raw[i + 1]) for i in range(0, len(raw), 2)}
if not expected or not re.fullmatch(r"[0-9a-f]{64}", completion_generation):
    raise SystemExit(1)
try:
    data = json.load(open(receipt, encoding="utf-8"))
except (OSError, ValueError, TypeError):
    raise SystemExit(1)
if not isinstance(data, dict) or data.get("version") != 1 or data.get("state") != "published":
    raise SystemExit(1)
if data.get("cmd_id") != cmd_id or data.get("completion_generation") != completion_generation:
    raise SystemExit(1)
entries = data.get("entries")
if not isinstance(entries, list):
    raise SystemExit(1)
actual = set()
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit(1)
    if entry.get("repo") != repo:
        continue
    if entry.get("cmd_id") != cmd_id or entry.get("completion_generation") != completion_generation:
        raise SystemExit(1)
    if entry.get("remote_contains_source_rc") != 0:
        raise SystemExit(1)
    source_sha = str(entry.get("source_sha") or "")
    report_generation = str(entry.get("report_generation") or "")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or not report_generation:
        raise SystemExit(1)
    actual.add((source_sha, report_generation))
if actual != expected:
    raise SystemExit(1)
PY
}

# A pre-receipt source-only publication may have been recorded by the old
# trigger logger before the durable receipt was introduced. Evidence is usable
# only when the logger captured the complete publication identity. A marker, a
# successful writer rc, or a report path alone cannot prove that this exact
# source/report generation was the one whose remote inclusion was verified.
source_publish_legacy_evidence_path() {
    local receipt="$1"
    local configured="${CMD_COMPLETE_GATE_SOURCE_PUBLISH_LEGACY_EVIDENCE:-${CMD_COMPLETE_GATE_SOURCE_PUBLISH_LEGACY_LOG:-}}"
    if [ -f "$SCRIPT_DIR/queue/gates/${CMD_ID}/cmd_complete_gate.trigger.log" ]; then
        # The pre-receipt writer recorded the verified source-only push in the
        # standard trigger log. Production re-GATE must prefer this authoritative
        # path whenever it exists; an override cannot bypass its identity checks.
        printf '%s\n' "$SCRIPT_DIR/queue/gates/${CMD_ID}/cmd_complete_gate.trigger.log"
    elif [ -n "$configured" ]; then
        # Isolated callers without a standard trigger log may retain the
        # explicit legacy JSONL fixture path.
        printf '%s\n' "$configured"
    else
        printf '%s\n' "${receipt}.legacy.jsonl"
    fi
}

migrate_legacy_source_publish_receipt() {
    local evidence="$1" receipt="$2" cmd_id="$3" completion_generation="$4" repo="$5" remote_tip="$6" task_file="$7" script_dir="$8"
    shift 8
    [ -f "$evidence" ] || return 1
    [ -f "$task_file" ] || return 1
    [ "$#" -gt 0 ] && [ $(( $# % 2 )) -eq 0 ] || return 1
    if [ "$(basename "$evidence")" = "cmd_complete_gate.trigger.log" ]; then
        python3 - "$script_dir/queue/gates/$cmd_id/terminal_review_manifest.json" "$@" <<'PY'
import json
import re
import sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {(sys.argv[i], sys.argv[i + 1]) for i in range(2, len(sys.argv), 2)}
reports = manifest.get("reports")
if manifest.get("cmd_id") != sys.argv[1].split("/queue/gates/")[-1].split("/")[0] or not isinstance(reports, list):
    raise SystemExit(1)
actual = {(str(item.get("commit_identity") or ""), str(item.get("report_id") or ""))
          for item in reports if isinstance(item, dict)}
if not expected or not expected.issubset(actual):
    raise SystemExit(1)
if any(not re.fullmatch(r"[0-9a-f]{40}", source) or not report for source, report in expected):
    raise SystemExit(1)
PY
    fi
    python3 - "$evidence" "$cmd_id" "$completion_generation" "$repo" "$task_file" "$script_dir" "$@" <<'PY'
import json
import hashlib
import pathlib
import re
import sys
import yaml

evidence, cmd_id, completion_generation, repo, task_file, script_dir = sys.argv[1:7]
raw = sys.argv[7:]
expected = {(raw[i], raw[i + 1]) for i in range(0, len(raw), 2)}
if not expected or not re.fullmatch(r"[0-9a-f]{64}", completion_generation):
    raise SystemExit(1)

try:
    handle = open(evidence, encoding="utf-8")
except OSError:
    raise SystemExit(1)
found = set()
trigger_source_push_verified = False
json_record_seen = False
trigger_attempts = {}
trigger_success_attempts = set()
with handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        if (
            line.startswith("git push: OK (")
            and f"{repo};" in line
            and "source-only" in line
            and "remote_contains_source_rc=0" in line
        ):
            trigger_source_push_verified = True
            trigger_success_attempts.add(trigger_attempts.get("current", 1))
        attempt_match = re.fullmatch(r"attempt=(\d+) rc=(-?\d+) timestamp=.*", line)
        if attempt_match:
            attempt = int(attempt_match.group(1))
            trigger_attempts[attempt] = int(attempt_match.group(2))
            trigger_attempts["current"] = attempt + 1
        try:
            value = json.loads(line)
        except (TypeError, ValueError):
            continue
        json_record_seen = True
        records = value if isinstance(value, list) else [value]
        for entry in records:
            if not isinstance(entry, dict):
                continue
            if entry.get("event") not in (None, "source_only_publication", "source_only_push"):
                continue
            if entry.get("cmd_id") != cmd_id:
                continue
            if (entry.get("completion_generation") or entry.get("generation")) != completion_generation:
                continue
            if entry.get("repo") != repo or entry.get("remote_contains_source_rc") != 0:
                continue
            source_sha = str(entry.get("source_sha") or entry.get("source_commit") or "")
            report_generation = str(entry.get("report_generation") or entry.get("report_id") or "")
            if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or not report_generation:
                continue
            pair = (source_sha, report_generation)
            if pair in expected:
                found.add(pair)

if not json_record_seen and trigger_source_push_verified:
    try:
        task = yaml.safe_load(open(task_file, encoding="utf-8")) or {}
        task = task.get("task", task) if isinstance(task, dict) else {}
        report_ref = str(task.get("report_path") or task.get("report_filename") or "").strip()
        report_path = pathlib.Path(report_ref)
        if not report_path.is_absolute():
            report_path = pathlib.Path(script_dir) / report_path
        report_path = report_path.resolve()
        report = yaml.safe_load(open(report_path, encoding="utf-8")) or {}
        report_id = str(report.get("report_id") or "").strip()
        if len(expected) != 1 or not report_id:
            raise ValueError("report identity missing")
        source_sha, expected_report_id = next(iter(expected))
        if expected_report_id != report_id:
            raise ValueError("report id mismatch")

        review_payload = dict(report)
        for key in ("commit_hash", "cross_repo_commits", "commit", "git_commit",
                    "status", "timestamp", "submitted_at", "completed_at",
                    "done_at", "updated_at", "acknowledged_at"):
            review_payload.pop(key, None)
        result_payload = review_payload.get("result")
        if isinstance(result_payload, dict):
            result_payload = dict(result_payload)
            result_payload.pop("commit_hash", None)
            review_payload["result"] = result_payload
        def json_default(value):
            if hasattr(value, "isoformat"):
                return value.isoformat()
            raise TypeError(type(value))
        review_fingerprint = hashlib.sha256(json.dumps(
            review_payload, default=json_default, ensure_ascii=False,
            sort_keys=True, separators=(",", ":")
        ).encode("utf-8")).hexdigest()
        logical = "queue/reports/" + report_path.name
        gate_dir = pathlib.Path(script_dir) / "queue" / "gates" / cmd_id
        terminal = json.load(open(gate_dir / "terminal_review_manifest.json", encoding="utf-8"))
        if terminal.get("cmd_id") != cmd_id or not isinstance(terminal.get("reports"), list):
            raise ValueError("terminal manifest identity missing")
        matching = [item for item in terminal["reports"]
                    if isinstance(item, dict) and item.get("logical_path") == logical]
        if len(matching) != 1:
            matching = [item for item in terminal["reports"]
                        if isinstance(item, dict) and item.get("report_id") == report_id]
        if len(matching) != 1:
            raise ValueError("terminal report mismatch")
        item = matching[0]
        if (item.get("report_id") != report_id
                or item.get("commit_identity") != source_sha
                or item.get("content_sha") != review_fingerprint):
            raise ValueError("terminal source/report fingerprint mismatch")

        approval_key = hashlib.sha256(logical.encode("utf-8")).hexdigest()
        approval_dir = gate_dir / "review_approvals" / "reports" / approval_key
        for role, result in (("gunshi", "LGTM"), ("karo", "ACCEPT")):
            approval = yaml.safe_load(open(approval_dir / (role + ".yaml"), encoding="utf-8")) or {}
            if (approval.get("role") != role or approval.get("result") != result
                    or approval.get("report") != logical
                    or approval.get("fingerprint") != review_fingerprint
                    or approval.get("generation") != completion_generation):
                raise ValueError("review approval identity mismatch")

        markers = sorted((gate_dir / "review_approvals").glob(".gate_triggered.*"))
        if len(markers) != 1:
            raise ValueError("terminal marker count mismatch")
        marker_name = markers[0].name.rsplit(".", 1)[-1]
        expected_marker = hashlib.sha256(
            (logical + ":" + review_fingerprint + "\n").encode("utf-8")
        ).hexdigest()
        if marker_name != expected_marker:
            raise ValueError("terminal marker identity mismatch")
        marker = yaml.safe_load(open(markers[0], encoding="utf-8")) or {}
        marker_attempt = int(marker.get("attempts", 0))
        marker_result = int(marker.get("result", -99))
        if (marker.get("manifest") != expected_marker
                or marker_attempt <= 0
                or trigger_attempts.get(marker_attempt) != marker_result
                or marker_attempt not in trigger_success_attempts):
            raise ValueError("terminal attempt mismatch")
        found = set(expected)
    except (OSError, TypeError, ValueError, KeyError, json.JSONDecodeError, yaml.YAMLError):
        raise SystemExit(1)

if found != expected:
    raise SystemExit(1)
PY
    write_source_publish_receipt "$receipt" "$cmd_id" "$completion_generation" \
        "$repo" "$remote_tip" "$@"
}

write_source_publish_receipt() {
    local receipt="$1" cmd_id="$2" completion_generation="$3" repo="$4" remote_tip="$5"
    shift 5
    [ "$#" -gt 0 ] && [ $(( $# % 2 )) -eq 0 ] || return 1
    [[ "$completion_generation" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || return 1
    mkdir -p "$(dirname "$receipt")" || return 1
    python3 - "$receipt" "$cmd_id" "$completion_generation" "$repo" "$remote_tip" "$@" <<'PY'
import json
import os
import re
import tempfile
import time
import sys

receipt, cmd_id, completion_generation, repo, remote_tip = sys.argv[1:6]
raw = sys.argv[6:]
if len(raw) == 0 or len(raw) % 2:
    raise SystemExit(1)
entries = []
try:
    current = json.load(open(receipt, encoding="utf-8"))
except (OSError, ValueError, TypeError):
    current = None
if isinstance(current, dict) \
        and current.get("version") == 1 \
        and current.get("state") == "published" \
        and current.get("cmd_id") == cmd_id \
        and current.get("completion_generation") == completion_generation \
        and isinstance(current.get("entries"), list):
    entries = [entry for entry in current["entries"]
               if isinstance(entry, dict) and entry.get("repo") != repo]

for index in range(0, len(raw), 2):
    source_sha, report_generation = raw[index:index + 2]
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or not report_generation:
        raise SystemExit(1)
    entries.append({
        "cmd_id": cmd_id,
        "completion_generation": completion_generation,
        "report_generation": report_generation,
        "repo": repo,
        "source_sha": source_sha,
        "remote_tip": remote_tip,
        "remote_contains_source_rc": 0,
        "published_at_ns": time.time_ns(),
    })

payload = {
    "version": 1,
    "state": "published",
    "cmd_id": cmd_id,
    "completion_generation": completion_generation,
    "entries": entries,
}
os.makedirs(os.path.dirname(receipt), exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=".source_only_publish.", dir=os.path.dirname(receipt))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, receipt)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
}

# A source commit can be published by an equivalent cherry-pick whose hash is
# necessarily different.  Ancestry alone therefore cannot be the publication
# identity.  Prove the immutable final state of every path changed by the
# source commit, including deletions; an empty commit is not accepted as an
# equivalence witness.
source_snapshot_matches_tip() {
    local repo="$1" source_sha="$2" tip_sha="$3" path source_blob tip_blob
    local changed_count=0

    git -C "$repo" cat-file -e "${source_sha}^{commit}" 2>/dev/null || return 1
    git -C "$repo" cat-file -e "${tip_sha}^{commit}" 2>/dev/null || return 1
    while IFS= read -r -d '' path; do
        changed_count=$((changed_count + 1))
        if git -C "$repo" cat-file -e "$source_sha:$path" 2>/dev/null; then
            git -C "$repo" cat-file -e "$tip_sha:$path" 2>/dev/null || return 1
            source_blob="$(git -C "$repo" rev-parse "$source_sha:$path")" || return 1
            tip_blob="$(git -C "$repo" rev-parse "$tip_sha:$path")" || return 1
            [ "$source_blob" = "$tip_blob" ] || return 1
        else
            ! git -C "$repo" cat-file -e "$tip_sha:$path" 2>/dev/null || return 1
        fi
    done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    [ "$changed_count" -gt 0 ]
}

# A PASS_NO_IMPROVEMENT corrective revert can legitimately finish at the exact
# tree recorded when its task worktree was deployed.  If another publication
# has since advanced one of the source paths, replaying that revert would
# overwrite the newer valid state.  Prove all four facts from immutable git
# state and treat the source publication as an already-converged no-op.
pass_no_improvement_base_tree_noop() {
    local task_file="$1" repo="$2" source_sha="$3" remote_tip="$4"
    local report_file verdict base_sha source_tree base_tree path changed=0 later=0
    local base_blob remote_blob base_exists remote_exists

    report_file=$(python3 - "$task_file" "$SCRIPT_DIR" <<'PY'
import os
import sys
import yaml

task_file, script_dir = sys.argv[1:]
try:
    task = (yaml.safe_load(open(task_file, encoding="utf-8")) or {}).get("task", {})
except Exception:
    raise SystemExit(1)
report = str(task.get("report_path") or task.get("report_filename") or "").strip()
if report and not os.path.isabs(report):
    report = os.path.join(script_dir, report)
print(report)
PY
    ) || return 1
    [ -f "$report_file" ] || return 1
    verdict=$(python3 - "$report_file" <<'PY'
import sys
import yaml
try:
    report = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    raise SystemExit(1)
print(str(report.get("verdict") or "").strip())
PY
    ) || return 1
    [ "$verdict" = "PASS_NO_IMPROVEMENT" ] || return 1
    base_sha=$(python3 - "$task_file" <<'PY'
import sys
import yaml
try:
    task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
except Exception:
    raise SystemExit(1)
print(str(task.get("task_worktree_base") or "").strip().lower())
PY
    ) || return 1
    [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
    git -C "$repo" cat-file -e "${source_sha}^{commit}" 2>/dev/null || return 1
    git -C "$repo" cat-file -e "${base_sha}^{commit}" 2>/dev/null || return 1
    git -C "$repo" cat-file -e "${remote_tip}^{commit}" 2>/dev/null || return 1
    source_tree=$(git -C "$repo" rev-parse "${source_sha}^{tree}" 2>/dev/null) || return 1
    base_tree=$(git -C "$repo" rev-parse "${base_sha}^{tree}" 2>/dev/null) || return 1
    [ "$source_tree" = "$base_tree" ] || return 1
    [ "$base_sha" != "$remote_tip" ] || return 1
    git -C "$repo" merge-base --is-ancestor "$base_sha" "$remote_tip" || return 1

    # Require a strict, source-path-scoped later state.  A change to an
    # unrelated path is not enough to suppress the corrective publication.
    while IFS= read -r -d '' path; do
        changed=$((changed + 1))
        base_exists=0
        remote_exists=0
        git -C "$repo" cat-file -e "$base_sha:$path" 2>/dev/null && base_exists=1
        git -C "$repo" cat-file -e "$remote_tip:$path" 2>/dev/null && remote_exists=1
        if [ "$base_exists" -ne "$remote_exists" ]; then
            later=$((later + 1))
            continue
        fi
        if [ "$base_exists" -eq 1 ]; then
            base_blob=$(git -C "$repo" rev-parse "$base_sha:$path" 2>/dev/null) || return 1
            remote_blob=$(git -C "$repo" rev-parse "$remote_tip:$path" 2>/dev/null) || return 1
            [ "$base_blob" != "$remote_blob" ] && later=$((later + 1))
        fi
    done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    [ "$changed" -gt 0 ] && [ "$later" -gt 0 ]
}

# Completed tasks can be absent after a historical premature archive, while
# their submitted report remains the immutable completion record.  Recover
# cross-repository publication contracts from that report instead of silently
# defaulting the source to the platform repository.  NUL framing preserves
# path bytes; malformed records are omitted and the caller consequently
# blocks because it has no proven source.
discover_cmd_report_cross_repo_sources() {
    local cmd_id="$1"
    local report_root="${CMD_COMPLETE_GATE_REPORT_ROOT:-$SCRIPT_DIR}"
    python3 - "$report_root" "$cmd_id" <<'PY'
import glob
import os
import re
import sys
import yaml

root, cmd_id = sys.argv[1:]
seen = set()
for pattern in (
    os.path.join(root, "queue", "reports", "*.yaml"),
    os.path.join(root, "queue", "archive", "reports", "*.yaml"),
):
    matched_report = False
    for report_path in sorted(glob.glob(pattern)):
        try:
            report = yaml.safe_load(open(report_path, encoding="utf-8")) or {}
        except Exception:
            continue
        if not isinstance(report, dict):
            continue
        snapshot = report.get("task_contract_snapshot") or {}
        if not isinstance(snapshot, dict):
            snapshot = {}
        parent = str(report.get("parent_cmd") or snapshot.get("parent_cmd") or "").strip()
        if parent != cmd_id or str(report.get("status") or "").strip() != "completed":
            continue
        matched_report = True
        entries = report.get("cross_repo_commits") or []
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            repo = str(entry.get("repo") or "").strip()
            sha = str(entry.get("commit_hash") or "").strip().lower()
            paths = entry.get("paths") or []
            if not repo or not os.path.isabs(repo) or not re.fullmatch(r"[0-9a-f]{40}", sha):
                continue
            if not isinstance(paths, list) or not paths or any(not isinstance(p, str) or not p or "\x00" in p for p in paths):
                continue
            key = (os.path.realpath(repo), sha, tuple(paths))
            if key in seen:
                continue
            seen.add(key)
            for value in (key[0], sha, str(len(paths)), *paths):
                sys.stdout.buffer.write(value.encode("utf-8") + b"\0")
    # Live reports are the canonical lifecycle slot.  Only consult the large
    # archive when no completed live report exists for this command; otherwise
    # a 10k-report archive scan turns every taskless completion into a minute-
    # scale gate and can mix an obsolete generation into the source contract.
    if matched_report:
        break
PY
}

report_source_paths_match_commit() {
    local repo="$1" source_sha="$2" declared_count="$3"
    shift 3
    local path
    local -A declared=() actual=()

    [ "$declared_count" -eq "$#" ] 2>/dev/null || return 1
    git -C "$repo" cat-file -e "${source_sha}^{commit}" 2>/dev/null || return 1
    for path in "$@"; do
        [ -n "$path" ] || return 1
        [ "${declared[$path]+yes}" != yes ] || return 1
        declared["$path"]=1
    done
    while IFS= read -r -d '' path; do
        actual["$path"]=1
    done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    [ "${#actual[@]}" -eq "${#declared[@]}" ] || return 1
    for path in "${!actual[@]}"; do
        [ "${declared[$path]+yes}" = yes ] || return 1
    done
}

# Build a conflict publication from the source commits' final path snapshots.
# This is deliberately narrower than a three-way merge: only paths changed by
# the source commits may be staged, and a remote path is accepted only when
# its blob (or absence) is a state found in that path's source-side history.
# Generic source-only fallback. The insights ID merge wrapper below is kept
# separate so every other path retains the existing fail-closed proof.
source_only_path_snapshot_generic() {
    local repo="$1" clean_repo="$2" remote_tip="$3" source_sha path first_commit parent published_sha
    local remote_blob source_blob actual_path actual_blob
    local absent_ancestor common_base
    shift 3
    local -A allowed_paths=() source_for_path=() source_blobs=() actual_paths=()
    local -a parents=()

    for source_sha in "$@"; do
        while IFS= read -r -d '' path; do
            allowed_paths["$path"]=1
            source_for_path["$path"]="$source_sha"
            if git -C "$repo" cat-file -e "$source_sha:$path" 2>/dev/null; then
                source_blobs["$path"]="$(git -C "$repo" rev-parse "$source_sha:$path")"
            else
                source_blobs["$path"]="__ABSENT__"
            fi
        done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    [ "${#allowed_paths[@]}" -gt 0 ] || return 1

    # A remote blob must occur in the source commit's path history.  For an
    # absent remote path, prove that absence is also an ancestor state (the
    # path was not yet created, or was deleted) rather than accepting a
    # divergent remote deletion.
    for path in "${!allowed_paths[@]}"; do
        if git -C "$repo" cat-file -e "$remote_tip:$path" 2>/dev/null; then
            remote_blob="$(git -C "$repo" rev-parse "$remote_tip:$path")"
        else
        remote_blob="__ABSENT__"
        fi
        if [ "$remote_blob" = "__ABSENT__" ]; then
            if ! git -C "$repo" cat-file -e "${source_for_path[$path]}:$path" 2>/dev/null; then
                continue
            fi
            common_base="$(git -C "$repo" merge-base "$remote_tip" "${source_for_path[$path]}" 2>/dev/null || true)"
            [ -n "$common_base" ] || return 1
            # An absent remote path is valid only when the source/remote
            # common base also lacked it.  This distinguishes a new source
            # path from a remote-side deletion of an existing path.
            ! git -C "$repo" cat-file -e "$common_base:$path" 2>/dev/null || return 1
            first_commit="$(git -C "$repo" rev-list --reverse "${source_for_path[$path]}" -- "$path" 2>/dev/null | head -n 1)"
            [ -n "$first_commit" ] || return 1
            parents=( $(git -C "$repo" rev-list --parents -n 1 "$first_commit" 2>/dev/null) )
            if [ "${#parents[@]}" -le 1 ]; then
                continue
            fi
            absent_ancestor=false
            for parent in "${parents[@]:1}"; do
                if ! git -C "$repo" cat-file -e "$parent:$path" 2>/dev/null; then
                    absent_ancestor=true
                    break
                fi
            done
            [ "$absent_ancestor" = true ] || return 1
        else
            actual_blob=""
            while IFS= read -r first_commit; do
                [ -n "$first_commit" ] || continue
                actual_blob="$(git -C "$repo" rev-parse "$first_commit:$path" 2>/dev/null || true)"
                [ "$actual_blob" = "$remote_blob" ] && break
                actual_blob=""
            done < <(git -C "$repo" rev-list "${source_for_path[$path]}" -- "$path" 2>/dev/null)
            [ "$actual_blob" = "$remote_blob" ] || return 1
        fi
    done

    # Materialize only the final source blob for each changed path on top of
    # the remote tip.  Remote-only paths are never touched.
    for path in "${!allowed_paths[@]}"; do
        source_sha="${source_for_path[$path]}"
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            if git -C "$clean_repo" cat-file -e "$remote_tip:$path" 2>/dev/null; then
                git -C "$clean_repo" rm -f -- "$path" >/dev/null 2>&1 || return 1
            fi
        else
            git -C "$clean_repo" checkout "$source_sha" -- "$path" >/dev/null 2>&1 || return 1
        fi
    done
    git -C "$clean_repo" add -A -- "${!allowed_paths[@]}" || return 1

    while IFS= read -r -d '' actual_path; do
        actual_paths["$actual_path"]=1
    done < <(git -C "$clean_repo" diff --cached --name-only -z "$remote_tip")
    for actual_path in "${!actual_paths[@]}"; do
        [ "${allowed_paths[$actual_path]+yes}" = yes ] || return 1
    done

    for path in "${!allowed_paths[@]}"; do
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            ! git -C "$clean_repo" cat-file -e ":$path" 2>/dev/null || return 1
        else
            actual_blob="$(git -C "$clean_repo" rev-parse ":$path" 2>/dev/null || true)"
            [ "$actual_blob" = "$source_blob" ] || return 1
        fi
    done

    git -C "$clean_repo" commit --allow-empty -m "autopush: source-only path snapshot" >/dev/null 2>&1 || return 1
    published_sha="$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$published_sha" ] || return 1

    actual_paths=()
    while IFS= read -r -d '' actual_path; do
        actual_paths["$actual_path"]=1
    done < <(git -C "$clean_repo" diff-tree --no-commit-id --name-only -r -z "$published_sha^" "$published_sha")
    for actual_path in "${!actual_paths[@]}"; do
        [ "${allowed_paths[$actual_path]+yes}" = yes ] || return 1
    done
    for path in "${!allowed_paths[@]}"; do
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            ! git -C "$clean_repo" cat-file -e "$published_sha:$path" 2>/dev/null || return 1
        else
            actual_blob="$(git -C "$clean_repo" rev-parse "$published_sha:$path" 2>/dev/null || true)"
            [ "$actual_blob" = "$source_blob" ] || return 1
        fi
    done
    return 0
}

# Prove that every remote-side edit is already accumulated in the source
# final blob. The base->remote delta must be present in source with the same
# multiplicity and order; any missing hunk or path-state conflict fails closed.
source_only_cumulative_equivalence() (
    local repo="$1" clean_repo="$2" remote_tip="$3" source_sha common_base path actual_path
    local base_file source_file remote_file merged_file tmp_dir source_blob actual_blob published_sha
    local base_exists source_exists remote_exists
    shift 3
    local -a source_shas=("$@")
    local -A allowed_paths=() source_blobs=() actual_paths=()

    [ "${#source_shas[@]}" -gt 0 ] || return 1
    for source_sha in "${source_shas[@]}"; do
        while IFS= read -r -d '' path; do
            allowed_paths["$path"]=1
        done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    [ "${#allowed_paths[@]}" -gt 0 ] || return 1
    common_base="$(git -C "$repo" merge-base "$remote_tip" "${source_shas[0]}" 2>/dev/null || true)"
    [ -n "$common_base" ] || return 1
    source_sha="${source_shas[${#source_shas[@]}-1]}"

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shogun-cumulative-equivalence.XXXXXX")" || return 1
    trap 'rm -f "$tmp_dir"/*; rmdir "$tmp_dir" 2>/dev/null || true' EXIT

    local path_index=0
    for path in "${!allowed_paths[@]}"; do
        base_file="$tmp_dir/base_${path_index}"
        source_file="$tmp_dir/source_${path_index}"
        remote_file="$tmp_dir/remote_${path_index}"
        merged_file="$tmp_dir/merged_${path_index}"
        path_index=$((path_index + 1))

        base_exists=false
        source_exists=false
        remote_exists=false
        git -C "$repo" cat-file -e "$common_base:$path" 2>/dev/null && base_exists=true
        git -C "$repo" cat-file -e "$source_sha:$path" 2>/dev/null && source_exists=true
        git -C "$repo" cat-file -e "$remote_tip:$path" 2>/dev/null && remote_exists=true
        if [ "$base_exists" = true ] && [ "$source_exists" = true ] && [ "$remote_exists" = false ]; then
            return 1
        fi
        if [ "$base_exists" = true ] && [ "$source_exists" = false ] && [ "$remote_exists" = true ]; then
            return 1
        fi

        if [ "$base_exists" = true ]; then
            git -C "$repo" show "$common_base:$path" >"$base_file" || return 1
        else
            : >"$base_file"
        fi
        if [ "$source_exists" = true ]; then
            git -C "$repo" show "$source_sha:$path" >"$source_file" || return 1
            source_blobs["$path"]="$(git -C "$repo" rev-parse "$source_sha:$path")"
        else
            : >"$source_file"
            source_blobs["$path"]="__ABSENT__"
        fi
        if [ "$remote_exists" = true ]; then
            git -C "$repo" show "$remote_tip:$path" >"$remote_file" || return 1
        else
            : >"$remote_file"
        fi

        CUMULATIVE_BASE="$base_file" \
        CUMULATIVE_SOURCE="$source_file" \
        CUMULATIVE_REMOTE="$remote_file" \
        python3 - <<'PY' || return 1
import difflib
import os
from collections import Counter
from pathlib import Path

base = Path(os.environ["CUMULATIVE_BASE"]).read_bytes().decode("utf-8")
source = Path(os.environ["CUMULATIVE_SOURCE"]).read_bytes().decode("utf-8")
remote = Path(os.environ["CUMULATIVE_REMOTE"]).read_bytes().decode("utf-8")
base_lines = base.splitlines(keepends=True)
source_counts = Counter(source.splitlines(keepends=True))
base_counts = Counter(base_lines)
source_lines = source.splitlines(keepends=True)
remote_lines = remote.splitlines(keepends=True)
required_additions = Counter()
required_deletions = Counter()
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
    None, base_lines, remote_lines, autojunk=False
).get_opcodes():
    if tag in ("insert", "replace"):
        added = remote_lines[j1:j2]
        required_additions.update(added)
        cursor = 0
        for line in added:
            try:
                cursor = source_lines.index(line, cursor) + 1
            except ValueError:
                raise SystemExit(1)
    if tag in ("delete", "replace"):
        required_deletions.update(base_lines[i1:i2])
for line, count in required_additions.items():
    if source_counts[line] < base_counts[line] + count:
        raise SystemExit(1)
for line, count in required_deletions.items():
    if source_counts[line] > base_counts[line] - count:
        raise SystemExit(1)
PY
    done

    for path in "${!allowed_paths[@]}"; do
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            if git -C "$clean_repo" cat-file -e "$remote_tip:$path" 2>/dev/null; then
                git -C "$clean_repo" rm -f -- "$path" >/dev/null 2>&1 || return 1
            fi
        else
            git -C "$clean_repo" checkout "$source_sha" -- "$path" >/dev/null 2>&1 || return 1
        fi
    done
    git -C "$clean_repo" add -A -- "${!allowed_paths[@]}" || return 1

    while IFS= read -r -d '' actual_path; do
        actual_paths["$actual_path"]=1
    done < <(git -C "$clean_repo" diff --cached --name-only -z "$remote_tip")
    for actual_path in "${!actual_paths[@]}"; do
        [ "${allowed_paths[$actual_path]+yes}" = yes ] || return 1
    done
    for path in "${!allowed_paths[@]}"; do
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            ! git -C "$clean_repo" rev-parse ":$path" >/dev/null 2>&1 || return 1
        else
            actual_blob="$(git -C "$clean_repo" rev-parse ":$path" 2>/dev/null || true)"
            [ "$actual_blob" = "$source_blob" ] || return 1
        fi
    done

    git -C "$clean_repo" commit --allow-empty -m "autopush: source-only cumulative equivalence" >/dev/null 2>&1 || return 1
    published_sha="$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$published_sha" ] || return 1
    actual_paths=()
    while IFS= read -r -d '' actual_path; do
        actual_paths["$actual_path"]=1
    done < <(git -C "$clean_repo" diff-tree --no-commit-id --name-only -r -z "$published_sha^" "$published_sha")
    for actual_path in "${!actual_paths[@]}"; do
        [ "${allowed_paths[$actual_path]+yes}" = yes ] || return 1
    done
    for path in "${!allowed_paths[@]}"; do
        source_blob="${source_blobs[$path]}"
        if [ "$source_blob" = "__ABSENT__" ]; then
            ! git -C "$clean_repo" cat-file -e "$published_sha:$path" 2>/dev/null || return 1
        else
            actual_blob="$(git -C "$clean_repo" rev-parse "$published_sha:$path" 2>/dev/null || true)"
            [ "$actual_blob" = "$source_blob" ] || return 1
        fi
    done
    return 0
)

# Merge queue/insights.yaml without reserializing YAML. Python is used only to
# parse and compare blocks; every selected top-level `- id:` block is emitted
# from its original bytes so comments/formatting remain intact.
source_only_insights_id_merge() (
    local repo="$1" clean_repo="$2" remote_tip="$3" path="$4" source_sha source_base
    local base_file source_file remote_file merged_file tmp_dir
    shift 4
    local -a source_shas=("$@")

    [ "$path" = "queue/insights.yaml" ] || return 1
    [ "${#source_shas[@]}" -gt 0 ] || return 1
    # The merge base may predate unrelated operational checkpoints on the
    # source branch.  Those checkpoints are already part of the source
    # generation and must not be reinterpreted as deletions by this publisher.
    # Only the delta introduced by the supplied source commits is intentional,
    # so compare it with the first source commit's parent.
    source_base="$(git -C "$repo" rev-parse "${source_shas[0]}^" 2>/dev/null || true)"
    [ -n "$source_base" ] || return 1

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shogun-insights-merge.XXXXXX")" || return 1
    trap 'rm -f "$tmp_dir"/*.yaml; rmdir "$tmp_dir" 2>/dev/null || true' EXIT
    base_file="$tmp_dir/base.yaml"
    source_file="$tmp_dir/source.yaml"
    remote_file="$tmp_dir/remote.yaml"
    merged_file="$tmp_dir/merged.yaml"

    if git -C "$repo" cat-file -e "$source_base:$path" 2>/dev/null; then
        git -C "$repo" show "$source_base:$path" >"$base_file" || return 1
    else
        : >"$base_file"
    fi
    source_sha="${source_shas[${#source_shas[@]}-1]}"
    if git -C "$repo" cat-file -e "$source_sha:$path" 2>/dev/null; then
        git -C "$repo" show "$source_sha:$path" >"$source_file" || return 1
    else
        : >"$source_file"
    fi
    if git -C "$repo" cat-file -e "$remote_tip:$path" 2>/dev/null; then
        git -C "$repo" show "$remote_tip:$path" >"$remote_file" || return 1
    else
        : >"$remote_file"
    fi

    SOURCE_ONLY_INSIGHTS_BASE="$base_file" \
    SOURCE_ONLY_INSIGHTS_SOURCE="$source_file" \
    SOURCE_ONLY_INSIGHTS_REMOTE="$remote_file" \
    SOURCE_ONLY_INSIGHTS_OUTPUT="$merged_file" \
    python3 - <<'PY' || return 1
import os
import re
import textwrap
from pathlib import Path

import yaml

base_path = Path(os.environ["SOURCE_ONLY_INSIGHTS_BASE"])
source_path = Path(os.environ["SOURCE_ONLY_INSIGHTS_SOURCE"])
remote_path = Path(os.environ["SOURCE_ONLY_INSIGHTS_REMOTE"])
output_path = Path(os.environ["SOURCE_ONLY_INSIGHTS_OUTPUT"])


def read(path):
    return path.read_text(encoding="utf-8") if path.stat().st_size else ""


def parse_blocks(text, label):
    lines = text.splitlines(keepends=True)
    if not text.strip():
        return "", [], {}, None, ""

    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ValueError(f"{label} YAML parse failed: {exc}") from exc

    if isinstance(document, list):
        root_kind = "list"
        expected_entries = document
        region_start = 0
        region_end = len(lines)
        item_indent = 0
    elif isinstance(document, dict) and (
        isinstance(document.get("insights"), list) or document.get("insights") is None
    ):
        root_kind = "mapping"
        expected_entries = document.get("insights") or []
        key_matches = [
            (i, len(line) - len(line.lstrip(" \t")))
            for i, line in enumerate(lines)
            if re.match(r"^insights\s*:", line)
        ]
        if len(key_matches) != 1:
            raise ValueError(f"{label} mapping root must contain one top-level insights key")
        region_start, key_indent = key_matches[0]
        if key_indent != 0:
            raise ValueError(f"{label} insights key is not top-level")
        region_end = len(lines)
        for i in range(region_start + 1, len(lines)):
            line = lines[i]
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" \t"))
            if indent <= key_indent and not re.match(r"^[ \t]*-\s+id\s*:", line):
                region_end = i
                break
        item_candidates = [
            (i, len(line) - len(line.lstrip(" \t")))
            for i, line in enumerate(lines[region_start + 1:region_end], region_start + 1)
            if re.match(r"^[ \t]*-\s+id\s*:", line)
        ]
        item_indent = item_candidates[0][1] if item_candidates else None
    else:
        raise ValueError(f"{label} root must be a list or mapping with insights list")

    if root_kind == "list":
        starts = [
            i for i, line in enumerate(lines)
            if re.match(r"^-\s+id\s*:", line)
        ]
    elif item_indent is None:
        starts = []
    else:
        starts = [
            i for i, line in enumerate(lines[region_start + 1:region_end], region_start + 1)
            if len(line) - len(line.lstrip(" \t")) == item_indent
            and re.match(r"^[ \t]*-\s+id\s*:", line)
        ]

    if not starts and expected_entries:
        raise ValueError(f"{label} has no top-level - id: blocks")
    if starts:
        prefix = "".join(lines[:starts[0]])
    elif root_kind == "mapping":
        # Normalize both `insights: []` and an empty `insights:` sequence to
        # the same mapping header before appending source blocks. Keeping the
        # inline `[]` bytes would yield `insights: []` followed by `- id:`.
        prefix = (" " * key_indent) + "insights:\n"
    else:
        prefix = ""
    entries = []
    by_id = {}
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else region_end
        raw = "".join(lines[start:end])
        try:
            item = yaml.safe_load(textwrap.dedent(raw))
        except yaml.YAMLError as exc:
            raise ValueError(f"{label} block parse failed: {exc}") from exc
        if isinstance(item, list) and len(item) == 1:
            item = item[0]
        if not isinstance(item, dict) or str(item.get("id", "")).strip() == "":
            raise ValueError(f"{label} block has no stable id")
        item_id = str(item["id"])
        if item_id in by_id:
            raise ValueError(f"{label} duplicate id: {item_id}")
        entry = {"id": item_id, "raw": raw, "value": item}
        entries.append(entry)
        by_id[item_id] = entry
    if len(entries) != len(expected_entries):
        raise ValueError(
            f"{label} entry count mismatch: parsed {len(entries)} expected {len(expected_entries)}"
        )
    suffix = "".join(lines[region_end:])
    if not starts and root_kind == "list":
        suffix = text
    return prefix, entries, by_id, root_kind, suffix


base_prefix, base_list, base, base_root, base_suffix = parse_blocks(read(base_path), "base")
source_prefix, source_list, source, source_root, source_suffix = parse_blocks(read(source_path), "source")
remote_prefix, remote_list, remote, remote_root, remote_suffix = parse_blocks(read(remote_path), "remote")

roots = {root for root in (base_root, source_root, remote_root) if root is not None}
if len(roots) > 1:
    raise ValueError("base/source/remote root structures differ")
root_kind = next(iter(roots), "list")


def equal(left, right):
    return left is not None and right is not None and left["value"] == right["value"]


def monotonic_new_id_lifecycle(left, right):
    """Return the resolved entry for a safe pending -> resolved transition."""
    identity_fields = ("id", "ts", "insight", "priority", "source", "fix_known")
    left_value = left["value"]
    right_value = right["value"]
    if any(left_value.get(field) != right_value.get(field) for field in identity_fields):
        return None
    left_status = left_value.get("status")
    right_status = right_value.get("status")
    if left_status not in {"pending", "resolved"} or right_status not in {"pending", "resolved"}:
        return None
    if {left_status, right_status} != {"pending", "resolved"}:
        return None
    return left if left_status == "resolved" else right


def monotonic_resolved_deletion(base_entry, remote_entry):
    """Allow a resolved SSOT deletion to compact an identity-equal stale pending.

    The durable writer may resolve an insight and then compact that resolved
    block while a remote tip still contains the earlier pending observation.
    This is a monotonic lifecycle transition, not an independent destructive
    remote edit.  Identity and status are intentionally strict so changed
    evidence or non-pending remote states remain fail-closed.
    """
    identity_fields = ("id", "ts", "insight", "priority", "source", "fix_known")
    base_value = base_entry["value"]
    remote_value = remote_entry["value"]
    if any(base_value.get(field) != remote_value.get(field) for field in identity_fields):
        return False
    if base_value.get("status") != "resolved" or remote_value.get("status") != "pending":
        return False
    return True


chosen = {}
order = []
for entry in remote_list + source_list + base_list:
    if entry["id"] not in order:
        order.append(entry["id"])

for item_id in order:
    b = base.get(item_id)
    s = source.get(item_id)
    r = remote.get(item_id)
    if s is None:
        if b is None:
            chosen[item_id] = r
        elif r is None:
            chosen[item_id] = b
        elif monotonic_resolved_deletion(b, r):
            chosen[item_id] = None
        elif equal(r, b):
            # A source snapshot may be stale even when it is the only local
            # change in the publication generation. Treat a missing source ID
            # as an omitted candidate, never as a deletion.
            chosen[item_id] = r or b
        else:
            # Preserve an independently changed remote block as well. A stale
            # candidate must not erase an ID or its newer evidence.
            chosen[item_id] = r
        continue
    if b is None:
        if r is None or equal(r, s):
            chosen[item_id] = s
        elif monotonic_new_id_lifecycle(s, r) is not None:
            chosen[item_id] = monotonic_new_id_lifecycle(s, r)
        else:
            raise ValueError(f"source/remote divergent new id: {item_id}")
        continue
    if equal(s, b):
        chosen[item_id] = r
    elif r is None or equal(r, b):
        chosen[item_id] = s
    elif equal(r, s):
        chosen[item_id] = r
    else:
        raise ValueError(f"source/remote divergent id: {item_id}")

prefix = remote_prefix or source_prefix or base_prefix
suffix = remote_suffix or source_suffix or base_suffix
raw_blocks = [chosen[item_id]["raw"] for item_id in order if chosen.get(item_id) is not None]
merged = prefix + "".join(raw_blocks) + suffix
if raw_blocks and not merged.endswith("\n"):
    merged += "\n"
try:
    parsed = yaml.safe_load(merged) if merged.strip() else []
except yaml.YAMLError as exc:
    raise ValueError(f"merged YAML parse failed: {exc}") from exc
if root_kind == "list" and parsed is not None and not isinstance(parsed, list):
    raise ValueError("merged root is not a list")
if root_kind == "mapping" and (
    not isinstance(parsed, dict)
    or "insights" not in parsed
    or (parsed.get("insights") is not None and not isinstance(parsed.get("insights"), list))
):
    raise ValueError("merged root is not a mapping with insights list")

for item_id, entry in source.items():
    b = base.get(item_id)
    if b is not None and equal(entry, b):
        continue
    if chosen.get(item_id) is None or not equal(chosen[item_id], entry):
        raise ValueError(f"source block not published for id: {item_id}")

output_path.write_text(merged, encoding="utf-8")
PY

    mkdir -p "$(dirname "$clean_repo/$path")" || return 1
    cp "$merged_file" "$clean_repo/$path" || return 1
    git -C "$clean_repo" add -- "$path" || return 1

    local actual_path actual_blob expected_blob published_sha
    while IFS= read -r -d '' actual_path; do
        [ "$actual_path" = "$path" ] || return 1
    done < <(git -C "$clean_repo" diff --cached --name-only -z "$remote_tip")
    expected_blob="$(git -C "$clean_repo" hash-object "$merged_file")"
    actual_blob="$(git -C "$clean_repo" rev-parse ":$path" 2>/dev/null || true)"
    [ "$actual_blob" = "$expected_blob" ] || return 1

    git -C "$clean_repo" commit --allow-empty -m "autopush: source-only insights ID merge" >/dev/null 2>&1 || return 1
    published_sha="$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$published_sha" ] || return 1
    while IFS= read -r -d '' actual_path; do
        [ "$actual_path" = "$path" ] || return 1
    done < <(git -C "$clean_repo" diff-tree --no-commit-id --name-only -r -z "$published_sha^" "$published_sha")
    [ "$(git -C "$clean_repo" rev-parse "$published_sha:$path" 2>/dev/null || true)" = "$expected_blob" ] || return 1
    return 0
)

# Return true only for a source generation containing the lessons SSOT and
# optional generated lesson indexes.  A lessons publication must never widen
# into an arbitrary path snapshot: the SSOT is merged by stable lesson ID and
# the cache is regenerated from that merged SSOT.
source_only_lessons_candidate() {
    local repo="$1" path source_sha
    shift
    local -A paths=()
    for source_sha in "$@"; do
        while IFS= read -r -d '' path; do
            paths["$path"]=1
        done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    [ "${paths[tasks/lessons.md]+yes}" = yes ] || return 1
    for path in "${!paths[@]}"; do
        case "$path" in
            tasks/lessons.md|projects/*/lessons.yaml) ;;
            *) return 1 ;;
        esac
    done
}

# Distinguish an invalid lessons generation from an ordinary generic path
# generation.  Once tasks/lessons.md is present, any unrelated path is a
# fail-closed contamination; generic snapshot publication must not bypass it.
source_only_lessons_scope_violation() {
    local repo="$1" path source_sha saw_ssot=0
    shift
    local -A paths=()
    for source_sha in "$@"; do
        while IFS= read -r -d '' path; do paths["$path"]=1; done \
            < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    [ "${paths[tasks/lessons.md]+yes}" = yes ] || return 1
    for path in "${!paths[@]}"; do
        case "$path" in
            tasks/lessons.md|projects/*/lessons.yaml) ;;
            *) return 0 ;;
        esac
    done
    return 1
}

# Merge Markdown lesson blocks by stable ID, preserving the remote/source
# bytes for every selected block.  The merge is deliberately fail-closed for
# divergent same-ID edits and then regenerates every selected YAML index from
# the merged tasks/lessons.md through sync_lessons.sh.
source_only_lessons_id_merge() (
    local repo="$1" clean_repo="$2" remote_tip="$3" source_sha source_base path
    local base_file source_file remote_file merged_file tmp_dir project_id config_backup
    shift 3
    local -a source_shas=("$@") cache_paths=()
    local -A source_paths=()

    [ "${#source_shas[@]}" -gt 0 ] || return 1
    source_only_lessons_candidate "$repo" "${source_shas[@]}" || return 1
    source_base="$(git -C "$repo" rev-parse "${source_shas[0]}^" 2>/dev/null || true)"
    [ -n "$source_base" ] || return 1
    source_sha="${source_shas[${#source_shas[@]}-1]}"
    for source_sha in "${source_shas[@]}"; do
        while IFS= read -r -d '' path; do source_paths["$path"]=1; done \
            < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    for path in "${!source_paths[@]}"; do
        case "$path" in
            projects/*/lessons.yaml) cache_paths+=("$path") ;;
        esac
    done
    # A source-only SSOT commit from an older writer may omit the generated
    # index from its diff.  Infra is the repository's own SSOT/cache pair.
    if [ "${#cache_paths[@]}" -eq 0 ] && [ -f "$clean_repo/projects/infra/lessons.yaml" ]; then
        cache_paths+=(projects/infra/lessons.yaml)
    fi

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shogun-lessons-merge.XXXXXX")" || return 1
    trap 'rm -f "$tmp_dir"/*.md "$tmp_dir"/*.yaml "$tmp_dir"/projects.yaml; rmdir "$tmp_dir" 2>/dev/null || true' EXIT
    base_file="$tmp_dir/base.md"
    source_file="$tmp_dir/source.md"
    remote_file="$tmp_dir/remote.md"
    merged_file="$tmp_dir/merged.md"
    git -C "$repo" cat-file -e "$source_base:tasks/lessons.md" 2>/dev/null \
        && git -C "$repo" show "$source_base:tasks/lessons.md" >"$base_file" \
        || : >"$base_file"
    git -C "$repo" cat-file -e "$source_sha:tasks/lessons.md" 2>/dev/null \
        && git -C "$repo" show "$source_sha:tasks/lessons.md" >"$source_file" \
        || : >"$source_file"
    git -C "$repo" cat-file -e "$remote_tip:tasks/lessons.md" 2>/dev/null \
        && git -C "$repo" show "$remote_tip:tasks/lessons.md" >"$remote_file" \
        || : >"$remote_file"

    SOURCE_ONLY_LESSONS_BASE="$base_file" \
    SOURCE_ONLY_LESSONS_SOURCE="$source_file" \
    SOURCE_ONLY_LESSONS_REMOTE="$remote_file" \
    SOURCE_ONLY_LESSONS_OUTPUT="$merged_file" \
    python3 - <<'PY' || return 1
import os
import re
from pathlib import Path

base_path = Path(os.environ["SOURCE_ONLY_LESSONS_BASE"])
source_path = Path(os.environ["SOURCE_ONLY_LESSONS_SOURCE"])
remote_path = Path(os.environ["SOURCE_ONLY_LESSONS_REMOTE"])
output_path = Path(os.environ["SOURCE_ONLY_LESSONS_OUTPUT"])
heading = re.compile(r"^###\s+(L[0-9A-Za-z_-]+)\s*[:：]", re.MULTILINE)

def parse(path, label):
    text = path.read_text(encoding="utf-8")
    matches = list(heading.finditer(text))
    entries = []
    by_id = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        item_id = match.group(1)
        if item_id in by_id:
            raise ValueError(f"{label} duplicate lesson ID: {item_id}")
        entry = {"id": item_id, "raw": text[match.start():end]}
        entries.append(entry)
        by_id[item_id] = entry
    prefix = text[:matches[0].start()] if matches else text
    suffix = text[matches[-1].start() + len(entries[-1]["raw"]):] if matches else ""
    return prefix, entries, by_id, suffix

base_prefix, base_list, base, base_suffix = parse(base_path, "base")
source_prefix, source_list, source, source_suffix = parse(source_path, "source")
remote_prefix, remote_list, remote, remote_suffix = parse(remote_path, "remote")

chosen = {}
order = []
for entry in remote_list + source_list + base_list:
    if entry["id"] not in order:
        order.append(entry["id"])

for item_id in order:
    b, s, r = base.get(item_id), source.get(item_id), remote.get(item_id)
    if s is None:
        if b is None:
            chosen[item_id] = r
        elif r is None or r["raw"] == b["raw"]:
            chosen[item_id] = None
        else:
            raise ValueError(f"source deletion conflicts with remote lesson ID: {item_id}")
    elif b is None:
        if r is None or r["raw"] == s["raw"]:
            chosen[item_id] = s
        else:
            raise ValueError(f"source/remote divergent new lesson ID: {item_id}")
    elif s["raw"] == b["raw"]:
        chosen[item_id] = r
    elif r is None or r["raw"] == b["raw"]:
        chosen[item_id] = s
    elif r["raw"] == s["raw"]:
        chosen[item_id] = r
    else:
        raise ValueError(f"source/remote divergent lesson ID: {item_id}")

prefix = remote_prefix or source_prefix or base_prefix
suffix = remote_suffix or source_suffix or base_suffix
merged = prefix + "".join(chosen[item_id]["raw"] for item_id in order if chosen.get(item_id) is not None) + suffix
output_path.write_text(merged, encoding="utf-8")
for item_id, entry in source.items():
    b = base.get(item_id)
    if b is not None and entry["raw"] == b["raw"]:
        continue
    if chosen.get(item_id) is None or chosen[item_id]["raw"] != entry["raw"]:
        raise ValueError(f"source lesson ID not published: {item_id}")
PY

    mkdir -p "$(dirname "$clean_repo/tasks/lessons.md")" || return 1
    cp "$merged_file" "$clean_repo/tasks/lessons.md" || return 1
    for path in "${cache_paths[@]}"; do
        project_id="${path#projects/}"
        project_id="${project_id%%/*}"
        config_backup="$tmp_dir/projects.yaml"
        cp "$clean_repo/config/projects.yaml" "$config_backup" || return 1
        SOURCE_ONLY_CONFIG="$clean_repo/config/projects.yaml" \
        SOURCE_ONLY_PROJECT="$project_id" \
        SOURCE_ONLY_ROOT="$clean_repo" \
        python3 - <<'PY' || return 1
import os
import re
from pathlib import Path

path = Path(os.environ["SOURCE_ONLY_CONFIG"])
project = os.environ["SOURCE_ONLY_PROJECT"]
root = os.environ["SOURCE_ONLY_ROOT"]
lines = path.read_text(encoding="utf-8").splitlines(True)
inside = False
found = False
for index, line in enumerate(lines):
    item = re.match(r"^\s*- id:\s*([\"']?)([^\"'\s]+)\1\s*$", line.rstrip("\n"))
    if item:
        inside = item.group(2) == project
    if inside and re.match(r"^\s+path:\s*", line):
        newline = "\n" if line.endswith("\n") else ""
        indent = line[:len(line) - len(line.lstrip())]
        lines[index] = f'{indent}path: "{root}"{newline}'
        found = True
        inside = False
        break
if not found:
    raise SystemExit(f"project path not found: {project}")
path.write_text("".join(lines), encoding="utf-8")
PY
        if ! FORCE_SYNC=1 bash "$clean_repo/scripts/sync_lessons.sh" "$project_id" >/dev/null 2>&1; then
            cp "$config_backup" "$clean_repo/config/projects.yaml" || true
            return 1
        fi
        cp "$config_backup" "$clean_repo/config/projects.yaml" || return 1
    done

    git -C "$clean_repo" add -- tasks/lessons.md "${cache_paths[@]}" || return 1
    local actual_path
    while IFS= read -r -d '' actual_path; do
        case "$actual_path" in
            tasks/lessons.md|projects/*/lessons.yaml) ;;
            *) return 1 ;;
        esac
    done < <(git -C "$clean_repo" diff --cached --name-only -z "$remote_tip")
    git -C "$clean_repo" commit --allow-empty -m "autopush: source-only lessons ID merge" >/dev/null 2>&1 || return 1
    local published_sha
    published_sha="$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$published_sha" ] || return 1
    [ "$(git -C "$clean_repo" rev-parse "$published_sha:tasks/lessons.md" 2>/dev/null || true)" = \
      "$(git -C "$clean_repo" hash-object "$clean_repo/tasks/lessons.md")" ] || return 1
    return 0
)

# Build a merge commit from the current execution-source tree and the remote
# tip without resolving unrelated history conflicts.  The requested paths are
# the only bytes this lane is allowed to change; each must already match the
# remote blob before the merge commit is created.  This keeps source
# publication fail-closed for a stale target while allowing an unrelated
# runtime-history conflict (for example senkyoku-log) to remain outside the
# convergence contract.
shared_path_merge_commit() (
    local repo="$1" remote_tip="$2" current_head tree temp_index ref path mode blob merge_commit
    shift 2
    [ "$#" -gt 0 ] || return 1
    current_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$current_head" ] || return 1
    for path in "$@"; do
        mode="$(git -C "$repo" ls-tree "$remote_tip" -- "$path" 2>/dev/null | awk 'NR==1 {print $1}')"
        blob="$(git -C "$repo" rev-parse "$remote_tip:$path" 2>/dev/null || true)"
        [ -n "$mode" ] && [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || return 1
        [ "$(git -C "$repo" hash-object "$path" 2>/dev/null || true)" = "$blob" ] || return 1
        [ "$(git -C "$repo" rev-parse "$current_head:$path" 2>/dev/null || true)" = "$blob" ] || return 1
    done
    temp_index="$(mktemp "${TMPDIR:-/tmp}/shogun-converge-index.XXXXXX")" || return 1
    rm -f -- "$temp_index"
    trap 'rm -f -- "$temp_index"' EXIT
    GIT_INDEX_FILE="$temp_index" git -C "$repo" read-tree "$current_head" || return 1
    for path in "$@"; do
        mode="$(git -C "$repo" ls-tree "$remote_tip" -- "$path" | awk 'NR==1 {print $1}')"
        blob="$(git -C "$repo" rev-parse "$remote_tip:$path")"
        GIT_INDEX_FILE="$temp_index" git -C "$repo" update-index --add --cacheinfo "$mode,$blob,$path" || return 1
    done
    tree="$(GIT_INDEX_FILE="$temp_index" git -C "$repo" write-tree 2>/dev/null || true)"
    [[ "$tree" =~ ^[0-9a-f]{40}$ ]] || return 1
    merge_commit="$(printf 'runtime: converge published execution source %s\n' "${CMD_ID:-unknown}" | git -C "$repo" commit-tree "$tree" -p "$current_head" -p "$remote_tip" 2>/dev/null || true)"
    [[ "$merge_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    ref="$(git -C "$repo" symbolic-ref -q HEAD 2>/dev/null || printf 'HEAD')"
    git -C "$repo" update-ref "$ref" "$merge_commit" "$current_head" || return 1
    git -C "$repo" read-tree "$merge_commit" || return 1
    return 0
)

# Return true only when every source commit changes queue/insights.yaml and no
# other path. This gate is shared by the conflict and patch-id fallback lanes.
source_only_insights_candidate() {
    local repo="$1" path source_sha
    shift
    local -A paths=()
    for source_sha in "$@"; do
        while IFS= read -r -d '' path; do
            paths["$path"]=1
        done < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r -z "$source_sha" 2>/dev/null)
    done
    [ "${#paths[@]}" -eq 1 ] && [ "${paths[queue/insights.yaml]+yes}" = yes ]
}

# Insights has a schema-sensitive root and stable-ID contract, so validate and
# merge it before generic path publication. Other paths retain their existing
# generic/cumulative fallback order.
source_only_path_snapshot() {
    local repo="$1" clean_repo="$2" remote_tip="$3"
    shift 3
    if source_only_lessons_scope_violation "$repo" "$@"; then
        return 1
    fi
    if source_only_lessons_candidate "$repo" "$@"; then
        source_only_lessons_id_merge "$repo" "$clean_repo" "$remote_tip" "$@"
        return $?
    fi
    if source_only_insights_candidate "$repo" "$@"; then
        source_only_insights_id_merge "$repo" "$clean_repo" "$remote_tip" "queue/insights.yaml" "$@"
        return $?
    fi
    if source_only_path_snapshot_generic "$repo" "$clean_repo" "$remote_tip" "$@"; then
        return 0
    fi
    source_only_cumulative_equivalence "$repo" "$clean_repo" "$remote_tip" "$@"
}

task_push_allowed() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
task = data.get("task", data)
value = task.get("push_allowed")
print("false" if value is False or str(value).strip().lower() == "false" else "true")
PY
}

push_from_clean_worktree() {
    local repo="$1" upstream_ref="$2" remote="$3" push_ref="$4" remote_tip="$5"
    shift 5
    local source_sha temp_parent clean_repo rc cleanup_rc published_sha remote_sha push_output fallback_used
    local source_patch applied_patch
    local -a applied_shas=()
    fallback_used=0

    temp_parent=$(mktemp -d "${TMPDIR:-/tmp}/shogun-gate-push.XXXXXX") || return 1
    clean_repo="$temp_parent/repo"

    # WSL2 can report a /tmp worktree as dubious ownership relative to /mnt/c.
    # Register only this unique path and remove the registration after cleanup.
    git config --global --add safe.directory "$clean_repo" 2>/dev/null || true
    if ! git -C "$repo" worktree add --detach "$clean_repo" "$remote_tip" >/dev/null 2>&1; then
        git config --global --unset-all safe.directory "^${clean_repo}\$" 2>/dev/null || true
        rmdir "$temp_parent" 2>/dev/null || true
        return 1
    fi

    rc=0
    if source_only_lessons_scope_violation "$repo" "$@"; then
        rc=1
    elif source_only_lessons_candidate "$repo" "$@"; then
        if source_only_lessons_id_merge "$repo" "$clean_repo" "$remote_tip" "$@"; then
            fallback_used=1
            published_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
            echo "  git push: conflict fallback (source-only lessons ID merge)"
        else
            rc=1
        fi
    elif source_only_insights_candidate "$repo" "$@"; then
        if source_only_insights_id_merge "$repo" "$clean_repo" "$remote_tip" "queue/insights.yaml" "$@"; then
            fallback_used=1
            published_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
            echo "  git push: conflict fallback (source-only insights ID merge)"
        else
            rc=1
        fi
    else
        for source_sha in "$@"; do
            if ! git -C "$clean_repo" cherry-pick --no-edit "$source_sha" >/dev/null 2>&1; then
                git -C "$clean_repo" cherry-pick --abort >/dev/null 2>&1 || true
                if source_only_path_snapshot "$repo" "$clean_repo" "$remote_tip" "$@"; then
                    fallback_used=1
                    published_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
                    echo "  git push: conflict fallback (source-only path snapshot)"
                else
                    rc=1
                fi
                break
            fi
            applied_shas+=("$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)")
        done
    fi

    if [ "$rc" -eq 0 ] && [ "$fallback_used" -eq 0 ]; then
        published_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
        if [ -z "$published_sha" ]; then
            rc=1
        fi
    fi

    if [ "$rc" -eq 0 ] && [ "$fallback_used" -eq 0 ]; then
        for source_sha in "$@"; do
            source_patch=$(git -C "$repo" show --format= --no-ext-diff "$source_sha" 2>/dev/null | git patch-id --stable 2>/dev/null | awk 'NR==1 {print $1}')
            applied_patch=""
            for applied_sha in "${applied_shas[@]}"; do
                applied_patch=$(git -C "$clean_repo" show --format= --no-ext-diff "$applied_sha" 2>/dev/null | git patch-id --stable 2>/dev/null | awk 'NR==1 {print $1}')
                [ -n "$source_patch" ] && [ "$source_patch" = "$applied_patch" ] && break
                applied_patch=""
            done
            if [ -z "$source_patch" ] || [ "$source_patch" != "$applied_patch" ]; then
                if source_only_lessons_candidate "$repo" "$@" || source_only_insights_candidate "$repo" "$@"; then
                    timeout "${CMD_COMPLETE_GATE_PUSH_CLEANUP_TIMEOUT:-30}" \
                        git -C "$repo" worktree remove --force "$clean_repo" >/dev/null 2>&1 || rc=1
                    if [ "$rc" -eq 0 ] \
                       && ! git -C "$repo" worktree add --detach "$clean_repo" "$remote_tip" >/dev/null 2>&1; then
                        rc=1
                    fi
                    if [ "$rc" -eq 0 ] \
                       && source_only_path_snapshot "$repo" "$clean_repo" "$remote_tip" "$@"; then
                        fallback_used=1
                        published_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
                        echo "  git push: conflict fallback (source-only path snapshot)"
                    else
                        rc=1
                    fi
                else
                    rc=1
                fi
                break
            fi
        done
    fi

    push_output=$(mktemp "${TMPDIR:-/tmp}/shogun-gate-push-output.XXXXXX") || rc=1
    if [ "$rc" -eq 0 ] && ! git -C "$clean_repo" push "$remote" "HEAD:$push_ref" >"$push_output" 2>&1; then
        cat "$push_output" >&2
        if grep -Eqi 'cannot lock ref|non-fast-forward|fetch first|tip of your current branch is behind' "$push_output"; then
            # 2 means the remote moved while this source-only publication was
            # being assembled.  The caller may rebuild from a fresh tip.
            rc=2
        else
            rc=1
        fi
    fi
    [ -n "$push_output" ] && rm -f "$push_output"

    if [ "$rc" -eq 0 ]; then
        remote_sha=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
        if [ -z "$remote_sha" ] || ! git -C "$repo" merge-base --is-ancestor "$published_sha" "$remote_sha"; then
            rc=1
        fi
    fi

    # Hook-created artifacts are confined to the temporary execution root.
    cleanup_rc=0
    if [ -e "$clean_repo" ]; then
        timeout "${CMD_COMPLETE_GATE_PUSH_CLEANUP_TIMEOUT:-30}" \
            git -C "$repo" worktree remove --force "$clean_repo" >/dev/null 2>&1 || cleanup_rc=1
        [ ! -e "$clean_repo" ] || cleanup_rc=1
    fi
    git config --global --unset-all safe.directory "^${clean_repo}\$" 2>/dev/null || true
    [ ! -d "$temp_parent" ] || rmdir "$temp_parent" 2>/dev/null || cleanup_rc=1
    [ "$cleanup_rc" -eq 0 ] || rc=1
    return "$rc"
}

push_task_repositories() {
    local task_file repo upstream_ref upstream_sha remote push_ref remote_tip source_sha
    local overlap_blocking all_sources_ok push_rc attempt max_retries refreshed_tip
    local source_equivalent_used source_base_tree_noop source_noop_all
    local source_report_generation receipt receipt_expected legacy_evidence legacy_receipt_migrated legacy_task_file
    local -a repos=() eligible_task_files=()
    local -a receipt_pairs=()
    local saw_task_file=0
    local report_repo report_source report_path_count path_index path report_sources_tmp report_sources_fd
    local -a report_paths=()
    local -A seen_repos=() report_sources_by_repo=() receipt_pair_seen=()

    for task_file in "$@"; do
        [ -f "$task_file" ] || continue
        saw_task_file=1
        if [ "$(task_push_allowed "$task_file" 2>/dev/null || printf true)" = false ]; then
            echo "  git push: SKIP ($task_file push_allowed=false)"
            continue
        fi
        eligible_task_files+=("$task_file")
    done

    if [ "$saw_task_file" -eq 1 ] && [ "${#eligible_task_files[@]}" -eq 0 ]; then
        echo "  git push: SKIP (all task sources push_allowed=false)"
        return 0
    fi

    for task_file in "${eligible_task_files[@]}"; do
        repo=$(resolve_task_publish_repo_dir "$task_file") || continue
        [ -n "$repo" ] || continue
        if [[ ! "${seen_repos[$repo]+_}" ]]; then
            seen_repos["$repo"]=1
            repos+=("$repo")
        fi
    done

    # A historical premature archive can remove the task before GATE CLEAR.
    # In that case the completed report's exact cross-repo commit/path
    # contract is the only accepted repository source.  Never guess platform
    # ownership for a report that explicitly records another repository.
    if [ "${#repos[@]}" -eq 0 ]; then
        report_sources_tmp="$(mktemp "${TMPDIR:-/tmp}/cmd-gate-report-sources.XXXXXX")" || return 1
        case "$report_sources_tmp" in
            "${TMPDIR:-/tmp}"/cmd-gate-report-sources.*) ;;
            *) return 1 ;;
        esac
        if ! discover_cmd_report_cross_repo_sources "$CMD_ID" > "$report_sources_tmp"; then
            unlink "$report_sources_tmp" 2>/dev/null || true
            return 1
        fi
        exec {report_sources_fd}< "$report_sources_tmp" || {
            unlink "$report_sources_tmp" 2>/dev/null || true
            return 1
        }
        unlink "$report_sources_tmp" || return 1
        while IFS= read -r -d '' report_repo \
            && IFS= read -r -d '' report_source \
            && IFS= read -r -d '' path_count; do
            [[ "$path_count" =~ ^[0-9]+$ ]] && [ "$path_count" -gt 0 ] || return 1
            report_paths=()
            for ((path_index=0; path_index<path_count; path_index++)); do
                IFS= read -r -d '' path || return 1
                report_paths+=("$path")
            done
            [ -d "$report_repo" ] || return 1
            report_repo="$(realpath "$report_repo")" || return 1
            git -C "$report_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
            report_source_paths_match_commit "$report_repo" "$report_source" "$path_count" "${report_paths[@]}" || return 1
            if [[ ! "${seen_repos[$report_repo]+_}" ]]; then
                seen_repos["$report_repo"]=1
                repos+=("$report_repo")
            fi
            report_sources_by_repo["$report_repo"]+="${report_source}"$'\n'
        done <&"$report_sources_fd"
        exec {report_sources_fd}<&-
        [ "${#repos[@]}" -gt 0 ] || repos=("$SCRIPT_DIR")
    fi

    for repo in "${repos[@]}"; do
        if [ "${CMD_COMPLETE_GATE_PUSH_DRY_RUN:-0}" = "1" ]; then
            echo "  git push: DRY_RUN ($repo)"
            continue
        fi

        upstream_ref=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
        upstream_sha=$(git -C "$repo" rev-parse '@{upstream}' 2>/dev/null || true)
        [ -n "$upstream_ref" ] || { echo "  git push: BLOCK ($repo upstream missing)"; return 1; }
        remote="${upstream_ref%%/*}"
        push_ref="refs/heads/${upstream_ref#*/}"
        remote_tip=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
        [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || { echo "  git push: BLOCK ($repo remote tip unavailable)"; return 1; }

        local -a source_commits=()
        all_sources_ok=true
        if [ "${#eligible_task_files[@]}" -eq 0 ] && [ -n "${report_sources_by_repo[$repo]:-}" ]; then
            while IFS= read -r source_sha; do
                [ -n "$source_sha" ] && source_commits+=("$source_sha")
            done <<< "${report_sources_by_repo[$repo]}"
        else
            for task_file in "${eligible_task_files[@]}"; do
                [ -f "$task_file" ] || continue
            [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                source_sha=$(resolve_push_source_commit "$task_file" "$repo" 2>/dev/null || true)
                if [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]]; then
                    source_commits+=("$source_sha")
                else
                    all_sources_ok=false
                fi
            done
        fi
        if [ "$all_sources_ok" != true ] || [ "${#source_commits[@]}" -eq 0 ]; then
            echo "  git push: BLOCK ($repo report source commit unavailable)"
            return 1
        fi

        # A receipt is eligible only when every source commit has an explicit
        # report generation and the current gate has a valid completion
        # generation. Legacy evidence can be promoted only through the strict
        # identity check below; ambiguous evidence remains on the old path.
        receipt=$(source_publish_receipt_path)
        legacy_evidence=$(source_publish_legacy_evidence_path "$receipt")
        legacy_receipt_migrated=false
        legacy_task_file=""
        receipt_expected=true
        receipt_pairs=()
        receipt_pair_seen=()
        if ! [[ "${SHOGUN_COMPLETION_GENERATION:-}" =~ ^[0-9a-f]{64}$ ]] \
            || [ "${#eligible_task_files[@]}" -eq 0 ]; then
            receipt_expected=false
        else
            for task_file in "${eligible_task_files[@]}"; do
                [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                source_sha=$(resolve_push_source_commit "$task_file" "$repo" 2>/dev/null || true)
                source_report_generation=$(resolve_publish_report_generation "$task_file" "$SCRIPT_DIR" 2>/dev/null || true)
                if ! [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || [ -z "$source_report_generation" ]; then
                    receipt_expected=false
                    continue
                fi
                [ -n "$legacy_task_file" ] || legacy_task_file="$task_file"
                local receipt_pair_key="${source_sha}|${source_report_generation}"
                if [ -z "${receipt_pair_seen[$receipt_pair_key]+yes}" ]; then
                    receipt_pairs+=("$source_sha" "$source_report_generation")
                    receipt_pair_seen["$receipt_pair_key"]=1
                fi
            done
            [ "${#receipt_pairs[@]}" -gt 0 ] || receipt_expected=false
        fi

        max_retries="${CMD_COMPLETE_GATE_PUSH_MAX_RETRIES:-2}"
        [[ "$max_retries" =~ ^[0-9]+$ ]] || max_retries=2
        for ((attempt=0; attempt<=max_retries; attempt++)); do
            source_base_tree_noop=false
            source_noop_all=true
            if [ "$receipt_expected" = true ] && [ ! -f "$receipt" ] \
                && migrate_legacy_source_publish_receipt "$legacy_evidence" "$receipt" \
                    "$CMD_ID" "$SHOGUN_COMPLETION_GENERATION" "$repo" "$remote_tip" \
                    "$legacy_task_file" "$SCRIPT_DIR" \
                    "${receipt_pairs[@]}"; then
                legacy_receipt_migrated=true
            fi
            if [ "$receipt_expected" = true ] \
                && source_publish_receipt_matches "$receipt" "$CMD_ID" \
                    "$SHOGUN_COMPLETION_GENERATION" "$repo" "${receipt_pairs[@]}"; then
                for task_file in "${eligible_task_files[@]}"; do
                    [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                    mark_task_worktree_published "$task_file" "$remote_tip" || return 1
                done
                if [ "$legacy_receipt_migrated" = true ]; then
                    echo "  git push: SKIP ($repo migrated legacy source-only publication evidence exact-match)"
                else
                    echo "  git push: SKIP ($repo durable source-only publication receipt exact-match)"
                fi
                break
            fi
            # This proof is intentionally task-backed.  Archived/report-only
            # source contracts do not carry the deployment base and therefore
            # retain the existing ancestry/equivalence behavior.
            if [ "${#eligible_task_files[@]}" -gt 0 ]; then
                for task_file in "${eligible_task_files[@]}"; do
                    [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                    source_sha=$(resolve_push_source_commit "$task_file" "$repo" 2>/dev/null || true)
                    if ! [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] \
                        || ! pass_no_improvement_base_tree_noop "$task_file" "$repo" "$source_sha" "$remote_tip"; then
                        source_noop_all=false
                        break
                    fi
                done
                if [ "$source_noop_all" = true ]; then
                    source_base_tree_noop=true
                    for task_file in "${eligible_task_files[@]}"; do
                        [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                        mark_task_worktree_published "$task_file" "$remote_tip" || return 1
                    done
                    echo "  git push: SKIP ($repo PASS_NO_IMPROVEMENT source tree equals task base; newer source-path state preserved)"
                    break
                fi
            fi
            local all_remote=true
            source_equivalent_used=false
            for source_sha in "${source_commits[@]}"; do
                if git -C "$repo" merge-base --is-ancestor "$source_sha" "$remote_tip"; then
                    continue
                fi
                if source_snapshot_matches_tip "$repo" "$source_sha" "$remote_tip"; then
                    source_equivalent_used=true
                else
                    all_remote=false
                    break
                fi
            done
            if [ "$all_remote" = true ]; then
                if [ "$receipt_expected" = true ]; then
                    write_source_publish_receipt "$receipt" "$CMD_ID" \
                        "$SHOGUN_COMPLETION_GENERATION" "$repo" "$remote_tip" \
                        "${receipt_pairs[@]}" || {
                        echo "  git push: BLOCK ($repo durable source-only receipt write failed)"
                        return 1
                    }
                fi
                for task_file in "${eligible_task_files[@]}"; do
                    [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                    mark_task_worktree_published "$task_file" "$remote_tip" || return 1
                done
                if [ "$source_equivalent_used" = true ]; then
                    echo "  git push: SKIP ($repo report source commits source-equivalent to remote tip)"
                else
                    echo "  git push: SKIP ($repo report source commits already remote-contained)"
                fi
                break
            fi

            overlap_blocking="$(push_overlap_blocking_paths "$repo" "" "$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)" "$upstream_sha")"
            echo "  git push: isolated clean snapshot ($repo remote-tip source-only push)"
            [ -n "$overlap_blocking" ] && printf '%s\n' "$overlap_blocking" | sed 's/^/    /'
            if push_from_clean_worktree "$repo" "$upstream_ref" "$remote" "$push_ref" "$remote_tip" "${source_commits[@]}"; then
                push_rc=0
            else
                push_rc=$?
            fi
            if [ "$push_rc" -eq 0 ]; then
                published_remote_sha=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
                [[ "$published_remote_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "  git push: BLOCK ($repo published tip verification failed)"; return 1; }
                if [ "$receipt_expected" = true ]; then
                    write_source_publish_receipt "$receipt" "$CMD_ID" \
                        "$SHOGUN_COMPLETION_GENERATION" "$repo" "$published_remote_sha" \
                        "${receipt_pairs[@]}" || {
                        echo "  git push: BLOCK ($repo durable source-only receipt write failed)"
                        return 1
                    }
                fi
                for task_file in "${eligible_task_files[@]}"; do
                    [ "$(resolve_task_publish_repo_dir "$task_file")" = "$repo" ] || continue
                    mark_task_worktree_published "$task_file" "$published_remote_sha" || return 1
                done
                echo "  git push: OK ($repo; source-only fast-forward; remote_contains_source_rc=0)"
                break
            fi
            if [ "$push_rc" -ne 2 ] || [ "$attempt" -ge "$max_retries" ]; then
                echo "  git push: BLOCK ($repo source-only push/verification failed)"
                return 1
            fi

            refreshed_tip=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
            if ! [[ "$refreshed_tip" =~ ^[0-9a-f]{40}$ ]]; then
                echo "  git push: BLOCK ($repo remote tip refresh failed)"
                return 1
            fi
            if [ "$refreshed_tip" = "$remote_tip" ]; then
                echo "  git push: retry $((attempt + 1))/$max_retries (remote tip unchanged; rebuilding source-only snapshot)"
            else
                echo "  git push: retry $((attempt + 1))/$max_retries (remote tip refreshed $remote_tip -> $refreshed_tip)"
            fi
            remote_tip="$refreshed_tip"
            git -C "$repo" fetch -q "$remote" "$push_ref" >/dev/null 2>&1 || {
                echo "  git push: BLOCK ($repo remote tip fetch failed)"
                return 1
            }
        done
    done
    return 0
}

# Reconcile the live shared checkout with the just-published remote without
# discarding its local-only history.  A clean path may be advanced by a small
# local convergence commit; dirty/staged bytes are never overwritten.  The
# subsequent ordinary merge preserves both histories and leaves the shared
# index/worktree clean at the remote execution-source content.
converge_shared_execution_sources() {
    local repo="$1" upstream_ref remote push_ref remote_tip path tmp before_head merge_base
    local conflict_path temp_parent clean_repo merged_sha cleanup_rc
    local -a insight_source_shas=() conflict_paths=()
    shift
    [ "$#" -gt 0 ] || return 0
    upstream_ref=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || return 1
    remote=${upstream_ref%%/*}
    push_ref="refs/heads/${upstream_ref#*/}"
    git -C "$repo" fetch -q "$remote" "$push_ref" || return 1
    remote_tip=$(git -C "$repo" rev-parse FETCH_HEAD 2>/dev/null) || return 1
    before_head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || return 1
    merge_base=$(git -C "$repo" merge-base "$before_head" "$remote_tip" 2>/dev/null) || return 1

    for path in "$@"; do
        git -C "$repo" cat-file -e "${remote_tip}:${path}" 2>/dev/null || return 1
        if ! git -C "$repo" diff --quiet -- "$path" || ! git -C "$repo" diff --cached --quiet -- "$path"; then
            echo "  shared convergence: BLOCK (dirty source path=$path)" >&2
            return 1
        fi
        tmp=$(mktemp "${TMPDIR:-/tmp}/shared-source.XXXXXX") || return 1
        git -C "$repo" show "${remote_tip}:${path}" > "$tmp" || { unlink "$tmp"; return 1; }
        if ! cmp -s "$tmp" "$repo/$path"; then
            cp -- "$tmp" "$repo/$path" || { unlink "$tmp"; return 1; }
            git -C "$repo" add -- "$path" || { unlink "$tmp"; return 1; }
        fi
        unlink "$tmp" || return 1
    done
    if ! git -C "$repo" diff --cached --quiet -- "$@"; then
        git -C "$repo" commit -m "runtime: converge published execution source ${CMD_ID}" -- "$@" >/dev/null 2>&1 || return 1
    fi
    if ! git -C "$repo" merge --no-edit "$remote_tip" >/dev/null 2>&1; then
        mapfile -t conflict_paths < <(git -C "$repo" diff --name-only --diff-filter=U)
        mapfile -t insight_source_shas < <(
            git -C "$repo" rev-list --reverse "${merge_base}..${before_head}" -- queue/insights.yaml
        )
        printf '  shared convergence: conflicts=%s paths=%s insight_sources=%s\n' \
            "${#conflict_paths[@]}" "${conflict_paths[*]:-none}" \
            "${#insight_source_shas[@]}" >&2
        if [ "${#conflict_paths[@]}" -eq 1 ] \
           && [ "${conflict_paths[0]}" = "queue/insights.yaml" ] \
           && [ "${#insight_source_shas[@]}" -gt 0 ]; then
            temp_parent=$(mktemp -d "${TMPDIR:-/tmp}/shogun-shared-insights.XXXXXX") || {
                git -C "$repo" merge --abort >/dev/null 2>&1 || true
                return 1
            }
            clean_repo="$temp_parent/repo"
            cleanup_rc=0
            if git -C "$repo" worktree add --detach "$clean_repo" "$remote_tip" >/dev/null 2>&1 \
               && source_only_insights_id_merge "$repo" "$clean_repo" "$remote_tip" \
                    queue/insights.yaml "${insight_source_shas[@]}"; then
                merged_sha=$(git -C "$clean_repo" rev-parse HEAD 2>/dev/null || true)
                git -C "$clean_repo" show "${merged_sha}:queue/insights.yaml" \
                    > "$repo/queue/insights.yaml" || cleanup_rc=1
                [ "$cleanup_rc" -ne 0 ] || git -C "$repo" add -- queue/insights.yaml || cleanup_rc=1
                [ "$cleanup_rc" -ne 0 ] || git -C "$repo" commit --no-edit >/dev/null 2>&1 || cleanup_rc=1
            else
                cleanup_rc=1
            fi
            if [ -e "$clean_repo" ]; then
                git -C "$repo" worktree remove --force "$clean_repo" >/dev/null 2>&1 || cleanup_rc=1
            fi
            [ ! -d "$temp_parent" ] || rmdir "$temp_parent" 2>/dev/null || cleanup_rc=1
            if [ "$cleanup_rc" -ne 0 ]; then
                git -C "$repo" merge --abort >/dev/null 2>&1 || true
                echo "  shared convergence: BLOCK (insights stable-ID conflict)" >&2
                return 1
            fi
            echo "  shared convergence: conflict fallback (insights stable-ID merge)"
        else
            git -C "$repo" merge --abort >/dev/null 2>&1 || true
            if shared_path_merge_commit "$repo" "$remote_tip" "$@"; then
                echo "  shared convergence: conflict fallback (target paths only; unrelated history preserved)"
            else
                echo "  shared convergence: BLOCK (source history conflict)" >&2
                return 1
            fi
        fi
    fi
    for path in "$@"; do
        [ "$(git -C "$repo" hash-object "$path")" = "$(git -C "$repo" rev-parse "${remote_tip}:${path}")" ] || return 1
    done
    [ -z "$(git -C "$repo" status --porcelain=v1 --untracked-files=no -- "$@")" ] || return 1
    git -C "$repo" merge-base --is-ancestor "$before_head" HEAD || return 1
    echo "  shared convergence: OK (execution sources=$#; local history preserved)"
}

# Publish tracked runtime files written after the ordinary pre-CLEAR source
# push.  The shared checkout is snapshotted into a commit so the existing
# field-aware source-only merge path (including the insights ID merge) remains
# the single publication implementation.  A writer-generation change or any
# non-runtime dirty path is fail-closed: terminal completion must not describe
# a checkout that changed underneath the snapshot.
postclear_runtime_path_is_publishable() {
    case "${1:-}" in
        context/*.md|projects/*/lessons.yaml|tasks/lessons.md|scripts/cmd_complete_gate.sh|archive/cmd-chronicle/*.md|\
        logs/karo_workarounds.yaml|queue/insights.yaml|queue/gunshi_review_log.yaml|\
        queue/completed_changelog.yaml|logs/lesson_impact.tsv|logs/lesson_tracking.tsv|\
        queue/session_alerts_shogun.txt)
            return 0 ;;
    esac
    return 1
}

capture_durable_writer_paths() {
    local mode="$1" snapshot="$2" manifest="$3" cmd_id="$4" generation="$5"
    python3 - "$mode" "$SCRIPT_DIR" "$snapshot" "$manifest" "$cmd_id" "$generation" <<'PY'
import hashlib, json, os, subprocess, sys, tempfile
mode, repo, snapshot, manifest, cmd_id, generation = sys.argv[1:]

def tracked_state():
    paths = subprocess.check_output(
        ["git", "-C", repo, "ls-files", "-z"], stderr=subprocess.DEVNULL
    ).decode("utf-8", "surrogateescape").split("\0")
    state = {}
    for rel in filter(None, paths):
        path = os.path.join(repo, rel)
        if os.path.isfile(path):
            with open(path, "rb") as fh:
                state[rel] = hashlib.sha256(fh.read()).hexdigest()
        else:
            state[rel] = None
    return state

def atomic_json(path, data):
    fd, tmp = tempfile.mkstemp(prefix=".durable-writer.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, sort_keys=True); fh.write("\n")
            fh.flush(); os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

if mode == "start":
    atomic_json(snapshot, {"version": 1, "cmd_id": cmd_id,
                           "completion_generation": generation,
                           "tracked": tracked_state()})
elif mode == "finish":
    before = json.load(open(snapshot, encoding="utf-8"))
    if before.get("cmd_id") != cmd_id or before.get("completion_generation") != generation:
        raise SystemExit(1)
    after = tracked_state()
    changed = sorted(p for p in set(before["tracked"]) | set(after)
                     if before["tracked"].get(p) != after.get(p))
    atomic_json(manifest, {"version": 1, "cmd_id": cmd_id,
                           "completion_generation": generation,
                           "paths": changed})
else:
    raise SystemExit(2)
PY
}
export -f capture_durable_writer_paths

publish_postclear_runtime_deltas() {
    (
    local phase="${1:-postclear}"
    local strict_nonruntime=1
    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 \
        && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        strict_nonruntime=0
    fi
    local repo="$SCRIPT_DIR" upstream_ref remote push_ref remote_tip
    local before_head after_head temp_parent source_repo source_sha path
    local git_common_dir publish_lock publish_lock_fd
    local fresh_upstream_sha working_blob upstream_blob
    local durable_manifest="$GATES_DIR/semantic_causal_audit.paths.json"
    local -a dirty_paths=() runtime_paths=() durable_paths=() source_shas=() lesson_paths=()
    local -A source_blob_by_path=()

    # A tracked-runtime publication is a repository transaction.  Serialize
    # every generation on the shared git common-dir, then deliberately read
    # the manifest, HEAD and dirty set only after admission.  A waiting writer
    # therefore composes on the predecessor's latest checkpoint instead of
    # treating that legitimate HEAD movement as a terminal conflict.  The
    # subshell owns the fd so every fail-closed return releases the lock.
    git_common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    publish_lock="$git_common_dir/shogun-tracked-runtime-publish.lock"
    exec {publish_lock_fd}>"$publish_lock" || return 1
    flock -x "$publish_lock_fd" || return 1

    if [ "$phase" = "postclear" ]; then
    mapfile -t durable_paths < <(python3 - "$durable_manifest" "$CMD_ID" \
        "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, sys
path, cmd_id, generation = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
if data.get("version") != 1 or data.get("cmd_id") != cmd_id or data.get("completion_generation") != generation:
    raise SystemExit(1)
paths = data.get("paths")
if not isinstance(paths, list) or any(not isinstance(p, str) or not p for p in paths):
    raise SystemExit(1)
print("\n".join(paths))
PY
    ) || { echo "  runtime publish: BLOCK (durable writer manifest invalid)" >&2; return 1; }
    elif [ "$phase" != "pregate" ]; then
        return 1
    fi

    before_head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || return 1
    while IFS= read -r -d '' path; do
        dirty_paths+=("$path")
        case "$path" in
            queue/tasks/*.yaml|queue/inbox/*.yaml|queue/gates/*)
                # Per-command/task receipts are intentionally not published.
                ;;
            *)
                if postclear_runtime_path_is_publishable "$path" || \
                    printf '%s\n' "${durable_paths[@]}" | grep -Fqx -- "$path"; then
                    runtime_paths+=("$path")
                elif [ "$strict_nonruntime" -eq 0 ]; then
                    echo "  runtime publish: ignored unrelated dirty path=$path"
                else
                    # An owned non-runtime path still requires the existing
                    # exact upstream-blob proof; only unrelated paths are
                    # ignored by the task scope above.
                    upstream_ref=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || {
                        echo "  runtime publish: BLOCK (nonruntime upstream missing path=$path)" >&2
                        return 1
                    }
                    remote=${upstream_ref%%/*}
                    push_ref="refs/heads/${upstream_ref#*/}"
                    git -C "$repo" fetch -q "$remote" "$push_ref" || {
                        echo "  runtime publish: BLOCK (nonruntime upstream fetch failed path=$path)" >&2
                        return 1
                    }
                    fresh_upstream_sha=$(git -C "$repo" rev-parse FETCH_HEAD 2>/dev/null || true)
                    [[ "$fresh_upstream_sha" =~ ^[0-9a-f]{40}$ ]] || {
                        echo "  runtime publish: BLOCK (nonruntime upstream unavailable path=$path)" >&2
                        return 1
                    }
                    working_blob=$(git -C "$repo" hash-object -- "$path" 2>/dev/null || true)
                    upstream_blob=$(git -C "$repo" rev-parse "${fresh_upstream_sha}:${path}" 2>/dev/null || true)
                    if [ -n "$working_blob" ] && [ -n "$upstream_blob" ] && [ "$working_blob" = "$upstream_blob" ]; then
                        echo "  runtime publish: converged nonruntime path=$path (fresh upstream blob match)"
                    else
                        echo "  runtime publish: BLOCK (nonruntime dirty path=$path blob mismatch)" >&2
                        return 1
                    fi
                fi ;;
        esac
    done < <(git -C "$repo" status --porcelain=v1 -z --untracked-files=no | python3 -c 'import sys; d=sys.stdin.buffer.read().split(b"\0"); [sys.stdout.buffer.write(x[3:]+b"\0") for x in d if len(x)>=4]')

    if [ "${#runtime_paths[@]}" -eq 0 ]; then
        echo "  runtime publish: clean (tracked runtime dirty=0)"
        return 0
    fi

    upstream_ref=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || return 1
    remote=${upstream_ref%%/*}
    push_ref="refs/heads/${upstream_ref#*/}"
    remote_tip=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
    [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || return 1

    temp_parent=$(mktemp -d "${TMPDIR:-/tmp}/shogun-postclear-runtime.XXXXXX") || return 1
    source_repo="$temp_parent/source"
    if ! git -C "$repo" worktree add --detach "$source_repo" "$before_head" >/dev/null 2>&1; then
        rmdir -- "$temp_parent" 2>/dev/null || true
        return 1
    fi
    for path in "${runtime_paths[@]}"; do
        case "$path" in
            tasks/lessons.md|projects/*/lessons.yaml) lesson_paths+=("$path") ;;
        esac
    done
    # The SSOT and its generated indexes form one publication unit.  A single
    # source generation lets the lessons ID merge compose remote/local edits
    # before regenerating caches, instead of publishing a stale cache commit
    # immediately after the merged SSOT.
    if [ "${#lesson_paths[@]}" -gt 0 ]; then
        for path in "${lesson_paths[@]}"; do
            mkdir -p "$source_repo/$(dirname "$path")"
            cp -- "$repo/$path" "$source_repo/$path" || { git -C "$repo" worktree remove --force "$source_repo" >/dev/null 2>&1 || true; rmdir -- "$temp_parent" 2>/dev/null || true; return 1; }
            git -C "$source_repo" add -- "$path" || return 1
        done
        git -C "$source_repo" commit -m "runtime: ${phase} field-aware lessons publish ${CMD_ID}" -- "${lesson_paths[@]}" >/dev/null 2>&1 || return 1
        source_sha=$(git -C "$source_repo" rev-parse HEAD) || return 1
        source_shas+=("$source_sha")
        for path in "${lesson_paths[@]}"; do
            source_blob_by_path["$path"]=$(git -C "$source_repo" rev-parse "${source_sha}:${path}") || return 1
        done
    fi
    for path in "${runtime_paths[@]}"; do
        case "$path" in
            tasks/lessons.md|projects/*/lessons.yaml) continue ;;
        esac
        mkdir -p "$source_repo/$(dirname "$path")"
        cp -- "$repo/$path" "$source_repo/$path" || { git -C "$repo" worktree remove --force "$source_repo" >/dev/null 2>&1 || true; rmdir -- "$temp_parent" 2>/dev/null || true; return 1; }
        git -C "$source_repo" add -- "$path" || return 1
        git -C "$source_repo" commit -m "runtime: ${phase} field-aware publish ${CMD_ID} ${path}" -- "$path" >/dev/null 2>&1 || return 1
        source_sha=$(git -C "$source_repo" rev-parse HEAD) || return 1
        source_shas+=("$source_sha")
        source_blob_by_path["$path"]=$(git -C "$source_repo" rev-parse "${source_sha}:${path}") || return 1
    done

    after_head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
    if [ "$after_head" != "$before_head" ]; then
        echo "  runtime publish: BLOCK (writer generation changed $before_head -> $after_head)" >&2
        return 1
    fi
    # Checkpoint the exact snapshot locally before merging its equivalent
    # remote publication. Local-only history and live runtime bytes survive.
    for path in "${runtime_paths[@]}"; do
        [ "$(git -C "$repo" hash-object "$path")" = "${source_blob_by_path[$path]}" ] || {
            echo "  runtime publish: BLOCK (concurrent writer path=$path)" >&2
            return 1
        }
    done
    # Publish one field at a time.  In particular, an insights-only source
    # commit reaches the existing stable-ID merge lane even when other runtime
    # fields are dirty in the same generation.  Refresh the tip between fields
    # so remote-only history is composed rather than replayed or discarded.
    for source_sha in "${source_shas[@]}"; do
        if ! push_from_clean_worktree "$repo" "$upstream_ref" "$remote" "$push_ref" "$remote_tip" "$source_sha"; then
            echo "  runtime publish: BLOCK (source-only publish failed)" >&2
            return 1
        fi
        remote_tip=$(git -C "$repo" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')
        [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || return 1
    done
    git -C "$repo" fetch -q "$remote" "$push_ref" || return 1
    # The published blob is the authoritative composition (including remote
    # insight IDs).  Bring only owned runtime paths back before checkpointing;
    # unrelated local commits and dirty paths remain untouched.
    # A transient (non-optional) index.lock can still be held briefly by an
    # unrelated writer even with GIT_OPTIONAL_LOCKS=0 above; observed genuine
    # holders self-release within 5s (cmd_karo_hotfix_git_index_singleflight_
    # 202608191445 AC1). Retry this required write across that window instead
    # of failing the whole publish on a momentary collision.
    local _idx_lock_try
    for _idx_lock_try in 1 2 3 4 5 6 7; do
        if git -C "$repo" checkout FETCH_HEAD -- "${runtime_paths[@]}"; then
            break
        fi
        [ "$_idx_lock_try" -lt 7 ] || return 1
        sleep 1
    done
    git -C "$repo" commit -m "runtime: local ${phase} checkpoint ${CMD_ID}" -- "${runtime_paths[@]}" >/dev/null 2>&1 || return 1
    if ! git -C "$repo" merge --no-edit FETCH_HEAD >/dev/null 2>&1; then
        git -C "$repo" merge --abort >/dev/null 2>&1 || true
        if shared_path_merge_commit "$repo" "$remote_tip" "${runtime_paths[@]}"; then
            echo "  runtime publish: conflict fallback (target paths only; unrelated history preserved)"
        else
            echo "  runtime publish: BLOCK (shared HEAD/index convergence failed)" >&2
            return 1
        fi
    fi
    git -C "$repo" worktree remove --force "$source_repo" >/dev/null 2>&1 || true
    rmdir -- "$temp_parent" 2>/dev/null || true
    echo "  runtime publish: OK (tracked runtime dirty ${#runtime_paths[@]} -> 0)"
    )
}

# The semantic index/map writer is detached with setsid, so the shell job table
# cannot prove that its tracked writes are finished.  Bind its pending marker to
# this completion generation and wait for the corresponding fresh result before
# taking the terminal runtime snapshot.  Removing an older result before launch
# prevents a stale receipt from satisfying a redeployed generation.
wait_for_postclear_durable_writers() {
    local pending="$GATES_DIR/semantic_causal_audit.pending"
    local result="$GATES_DIR/semantic_causal_audit.result"
    local generation_marker="$GATES_DIR/semantic_causal_audit.generation.json"
    local path_manifest="$GATES_DIR/semantic_causal_audit.paths.json"
    local timeout_seconds="${CMD_COMPLETE_DURABLE_WRITER_TIMEOUT:-600}"
    local start_uptime_seconds start_uptime_fraction start_uptime_ticks
    local now_uptime_seconds now_uptime_fraction now_uptime_ticks elapsed_ticks timeout_ticks

    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || {
        echo "  durable writers: BLOCK (invalid timeout=$timeout_seconds)" >&2
        return 1
    }
    python3 - "$generation_marker" "$pending" "$CMD_ID" \
        "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, sys
marker, pending, cmd_id, generation = sys.argv[1:]
data = json.load(open(marker, encoding="utf-8"))
if data != {"version": 1, "cmd_id": cmd_id,
            "completion_generation": generation, "pending": pending}:
    raise SystemExit(1)
PY
    # /proc/uptime is monotonic across wall-clock corrections.  Reading it with
    # shell builtins keeps this 50ms loop cheap and prevents an NTP/manual clock
    # jump from turning a fresh worker into an immediate timeout.
    IFS='. ' read -r start_uptime_seconds start_uptime_fraction _ < /proc/uptime || {
        echo "  durable writers: BLOCK (monotonic clock unavailable)" >&2
        return 1
    }
    start_uptime_fraction="${start_uptime_fraction}00"
    start_uptime_ticks=$((10#$start_uptime_seconds * 100 + 10#${start_uptime_fraction:0:2}))
    timeout_ticks=$((timeout_seconds * 100))
    while [[ -e "$pending" || ! -s "$result" ]]; do
        IFS='. ' read -r now_uptime_seconds now_uptime_fraction _ < /proc/uptime || {
            echo "  durable writers: BLOCK (monotonic clock unavailable)" >&2
            return 1
        }
        now_uptime_fraction="${now_uptime_fraction}00"
        now_uptime_ticks=$((10#$now_uptime_seconds * 100 + 10#${now_uptime_fraction:0:2}))
        elapsed_ticks=$((now_uptime_ticks - start_uptime_ticks))
        if (( elapsed_ticks >= timeout_ticks )); then
            echo "  durable writers: BLOCK (semantic worker timeout=${timeout_seconds}s generation=${SHOGUN_COMPLETION_GENERATION})" >&2
            return 1
        fi
        sleep 0.05
    done
    wait || {
        echo "  durable writers: BLOCK (post-CLEAR shell writer failed)" >&2
        return 1
    }
    capture_durable_writer_paths finish \
        "$GATES_DIR/semantic_causal_audit.paths.before.json" "$path_manifest" \
        "$CMD_ID" "$SHOGUN_COMPLETION_GENERATION" || {
        echo "  durable writers: BLOCK (generation manifest finalize failed)" >&2
        return 1
    }
    python3 - "$path_manifest" "$CMD_ID" "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, sys
path, cmd_id, generation = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
if data.get("version") != 1 or data.get("cmd_id") != cmd_id or data.get("completion_generation") != generation:
    raise SystemExit(1)
if not isinstance(data.get("paths"), list):
    raise SystemExit(1)
PY
    echo "  durable writers: drained (semantic generation=${SHOGUN_COMPLETION_GENERATION})"
}

if [ "${CMD_COMPLETE_GATE_TASK_REPO_ONLY:-0}" = "1" ]; then
    resolve_task_repo_dir "${CMD_COMPLETE_GATE_TASK_FILE:?task file required}"
    exit 0
fi
if [ "${CMD_COMPLETE_GATE_PUSH_REPOS_ONLY:-0}" = "1" ]; then
    CMD_COMPLETE_GATE_PUSH_DRY_RUN=1 push_task_repositories "${CMD_COMPLETE_GATE_TASK_FILE:?task file required}"
    exit 0
fi
if [ "${CMD_COMPLETE_GATE_PUSH_OVERLAP_ONLY:-0}" = "1" ]; then
    push_overlap_blocking_paths \
        "${CMD_COMPLETE_GATE_PUSH_OVERLAP_REPO:?repo required}" \
        "" \
        "${CMD_COMPLETE_GATE_PUSH_OVERLAP_HEAD:-}" \
        "${CMD_COMPLETE_GATE_PUSH_OVERLAP_UPSTREAM:-}"
    exit 0
fi
if [ "${CMD_COMPLETE_GATE_PUSH_REPOS_REAL:-0}" = "1" ]; then
    if [ -n "${CMD_COMPLETE_GATE_TASK_FILE:-}" ]; then
        push_task_repositories "$CMD_COMPLETE_GATE_TASK_FILE"
    else
        push_task_repositories
    fi
    exit 0
fi
if [ -f "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh"
else
    model_injection_profile_intensity() {
        case "${1,,}" in
            *gpt*|*codex*|*sonnet*|*haiku*) printf '%s\n' "max" ;;
            *) printf '%s\n' "standard" ;;
        esac
    }
fi

append_line_locked() {
    local target_file="$1"
    local line="$2"
    local target_dir
    target_dir="$(dirname "$target_file")"
    mkdir -p "$target_dir" 2>/dev/null || true

    (
        flock -w 10 200 || exit 1
        printf '%s\n' "$line" >> "$target_file"
    ) 200>"$(lock_path "$target_file")"
}

log_gate_stderr_file() {
    local label="$1"
    local stderr_file="$2"
    local line

    [ -s "$stderr_file" ] || return 0
    while IFS= read -r line; do
        append_line_locked "$LOG_DIR/cmd_complete_gate_stderr.log" "$(date '+%Y-%m-%dT%H:%M:%S') [${CMD_ID}] ${label}: ${line}"
    done < "$stderr_file"
}

queue_lesson_impact_followup() {
    (
        bash "$SCRIPT_DIR/scripts/lesson_impact_rotate.sh" 2>/dev/null || true
        bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1 || true
    ) >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 &
    echo "  lesson_impact follow-up: queued (async)"
}

lesson_done_satisfies_lesson_candidate_registration() {
    local done_file="$1"
    local done_source=""
    local done_note=""

    [ -f "$done_file" ] || return 1

    done_source=$(awk -F: '/^[[:space:]]*source:/{sub(/^[[:space:]]*/, "", $2); print $2; exit}' "$done_file" 2>/dev/null)
    done_note=$(awk -F: '/^[[:space:]]*note:/{sub(/^[[:space:]]*/, "", $2); print $2; exit}' "$done_file" 2>/dev/null)

    [ "$done_source" = "lesson_write" ] && return 0
    printf '%s\n' "$done_note" | grep -Fq "duplicate_existing" && return 0
    return 1
}

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
CMD_PROJECT=""
SG7_SPEC_SOURCE=""
SG7_SPEC_SCOPE=""
SG7_DIRECT_REPORT_SPEC=false
SG7_REVIEWED_AT=""
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
# LOG_DIR/GATE_METRICS_LOG already set above for early CLEAR check
mkdir -p "$GATES_DIR" "$LOG_DIR"

cmd_status_is_canceled() {
    local cmd_id="$1"
    [ -n "$cmd_id" ] || return 1
    python3 - "$YAML_FILE" "$cmd_id" <<'PY'
import sys
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path, cmd_id = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

entry = None
commands = data.get("commands")
if isinstance(commands, dict):
    entry = commands.get(cmd_id)
elif isinstance(commands, list):
    for item in commands:
        if isinstance(item, dict) and str(item.get("id", "")).strip() == cmd_id:
            entry = item
            break

if not isinstance(entry, dict):
    raise SystemExit(1)

status = str(entry.get("status", "")).strip().lower()
raise SystemExit(0 if status in {"canceled", "cancelled"} else 1)
PY
}

# ─── CMD_ID単位ロック（cmd_2119） ───
# 同一cmdに対する並行cmd_complete_gate実行を抑止する。
# 早期exit系の判定より前で確保し、二重GATE CLEAR後処理を防ぐ。
CMD_GATE_LOCK_FILE="$(lock_path "$GATES_DIR/cmd_complete_gate.lock")"
exec 209>"$CMD_GATE_LOCK_FILE"
if ! flock -n 209; then
    echo "[gate] ${CMD_ID}: cmd_complete_gate busy; terminal CLEAR/BLOCK is not established (CMD_ID lock)" >&2
    # A coordinator lock collision is not a terminal gate result.  Returning
    # success here made callers publish quality-log CLEAR/status/dashboard/ntfy
    # while the lock holder was still evaluating the command.  EX_TEMPFAIL
    # keeps wrappers fail-closed; they may retry only after observing a real
    # terminal CLEAR/BLOCK record from the lock holder.
    exit 75
fi

classify_missing_report_status() {
    local status="${1,,}"
    case "$status" in
        assigned|acknowledged|in_progress) printf 'wait\n' ;;
        idle|failed|canceled|cancelled|superseded|skipped) printf 'skip\n' ;;
        *) printf 'missing\n' ;;
    esac
}

resolve_declared_task_report_path() {
    local task_path="$1" root="$2" cmd="$3"
    python3 - "$task_path" "$root" "$cmd" <<'PY'
import os, sys, yaml
task_path, root, cmd = sys.argv[1:]
try:
    raw = yaml.safe_load(open(task_path, encoding="utf-8")) or {}
except Exception:
    raise SystemExit
task = raw.get("task", raw) if isinstance(raw, dict) else {}
if not isinstance(task, dict):
    raise SystemExit
value = str(task.get("report_path") or task.get("report_filename") or "").strip()
if not value:
    raise SystemExit
path = value if os.path.isabs(value) else os.path.join(root, value if "/" in value else "queue/reports/" + value)
try:
    report = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    raise SystemExit
task_id = str(task.get("task_id") or task.get("_ac_task_id") or "").strip()
if (str(report.get("parent_cmd") or "").strip() == cmd and
        (not task_id or str(report.get("task_id") or "").strip() == task_id)):
    print(path)
PY
}

# ─── 報告YAML解決関数（L085: 新命名規則対応、cmd_410: report_filename最優先） ───
# 優先順位: 1. タスクYAMLのreport_filename  2. 新形式  3. 旧形式
resolve_report_file() {
    local ninja="$1"
    local cmd="${2:-$CMD_ID}"
    local task_hint="${3:-}"
    local _rrf_candidate _rrf_name
    local explicit_path
    local report_parent

    # Existing call sites pass the cached task basename.  Recover the exact
    # selected task record so archive timestamp suffixes cannot invent a
    # worker/report name; the task's declared report identity is authoritative.
    if [ -z "$task_hint" ] && declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for _rrf_candidate in "${MATCHING_TASK_FILES[@]}"; do
            _rrf_name="${_rrf_candidate##*/}"
            _rrf_name="${_rrf_name%.yaml}"
            if [ "$_rrf_name" = "$ninja" ]; then
                task_hint="$_rrf_candidate"
                break
            fi
        done
    fi

    auto_unwrap_report_yaml() {
        local report_file="$1"
        local unwrap_result
        local report_lock="${report_file}.lock"
        local line trimmed first_content=""

        [ -f "$report_file" ] || return 0

        # Normal reports are already flat. Avoid flock + Python + full YAML
        # parsing on every resolve_report_file call (dozens per gate run).
        # A wrapped report can only have `report:` as its first significant
        # line; comments and blank lines are preserved by the Python unwrap.
        while IFS= read -r line; do
            trimmed="${line#"${line%%[![:space:]]*}"}"
            case "$trimmed" in
                ""|\#*) continue ;;
                *) first_content="$trimmed"; break ;;
            esac
        done < "$report_file"
        [ "$first_content" = "report:" ] || return 0

        unwrap_result=$(
            (
                flock -w 5 200 || { echo "[auto_unwrap] WARN: flock timeout on report YAML, skipping unwrap" >&2; exit 1; }
                REPORT_FILE="$report_file" python3 - <<'PY'
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

report_file = os.environ["REPORT_FILE"]

try:
    with open(report_file, encoding="utf-8") as f:
        raw = f.read()
    data = yaml.safe_load(raw) or {}
except Exception:
    print("parse_error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("skip")
    raise SystemExit(0)

if len(data) == 1 and "report" in data and isinstance(data.get("report"), dict):
    # yaml.dump禁止(CLAUDE.md): テキストベースでreport:ラッパーを除去
    lines = raw.split('\n')
    out = []
    found = False
    for line in lines:
        s = line.strip()
        if not found:
            if s == '' or s.startswith('#'):
                out.append(line)
                continue
            if s == 'report:':
                found = True
                continue
            print("skip")
            raise SystemExit(0)
        else:
            if line.startswith('  '):
                out.append(line[2:])
            else:
                out.append(line)
    if not found:
        print("skip")
        raise SystemExit(0)
    result = '\n'.join(out)
    if not result.endswith('\n'):
        result += '\n'
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(report_file), suffix=".tmp")
    os.close(tmp_fd)
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(result)
        os.replace(tmp_path, report_file)
        print("unwrapped")
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
else:
    print("skip")
PY
            ) 200>"$report_lock"
        )

        case "$unwrap_result" in
            unwrapped)
                echo "[gate] report YAML auto-unwrapped: ${report_file}" >&2
                ;;
            parse_error)
                echo "[gate] WARN: report YAML parse failed during auto-unwrapping: ${report_file}" >&2
                ;;
            flock_timeout)
                echo "[gate] WARN: report YAML unwrap flock timeout: ${report_file}" >&2
                ;;
            skip)
                # Another process may have unwrapped the report after the
                # Bash precheck but before this process acquired the lock.
                ;;
            *)
                echo "[gate] WARN: report YAML unwrap returned unknown status '${unwrap_result:-<empty>}': ${report_file}" >&2
                ;;
        esac
    }

    # 1. The selected logical task owns report identity.  Archived task file
    # names contain timestamps and must never be reinterpreted as worker IDs.
    # Accept task.report_path/report_filename only when the report itself
    # proves the same task_id and parent_cmd.
    local task_yaml="${task_hint:-$TASKS_DIR/${ninja}.yaml}"
    if [ -f "$task_yaml" ]; then
        local explicit="" explicit_task_path=""
        if [ -n "$task_hint" ]; then
            explicit_task_path=$(resolve_declared_task_report_path "$task_yaml" "$SCRIPT_DIR" "$cmd")
            if [ -n "$explicit_task_path" ] && [ -f "$explicit_task_path" ]; then
                auto_unwrap_report_yaml "$explicit_task_path"
                echo "$explicit_task_path"
                return
            fi
        elif [ "${REPORT_FILENAME_CACHE_READY:-false}" = "true" ]; then
            explicit="${REPORT_FILENAME_CACHE[$ninja]:-}"
        else
            # Unit-source/legacy fallback. Production preloads all task files
            # once below, avoiding this five-process pipeline on every call.
            explicit=$(grep 'report_filename:' "$task_yaml" | head -1 | sed 's/.*report_filename:[[:space:]]*//' | tr -d "'" | tr -d '"')
        fi
        explicit_path="$SCRIPT_DIR/queue/reports/$explicit"
        if [ -n "$explicit" ] && [ -f "$explicit_path" ]; then
            auto_unwrap_report_yaml "$explicit_path"
            echo "$explicit_path"
            return
        fi
    fi
    # 2. 新形式 (既存)
    local new_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report_${cmd}.yaml"
    # 2.5. 分割cmd形式: ninja_report_cmd_XXXX_ninja.yaml — 分割cmdGATE滞留対処(cmd_3449)
    local split_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report_${cmd}_${ninja}.yaml"
    # 3. 旧形式フォールバック（安全化: parent_cmd一致チェック）
    local old_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report.yaml"
    [ -f "$new_fmt" ] && auto_unwrap_report_yaml "$new_fmt"
    [ -f "$split_fmt" ] && auto_unwrap_report_yaml "$split_fmt"
    [ -f "$old_fmt" ] && auto_unwrap_report_yaml "$old_fmt"
    if [ -f "$new_fmt" ]; then
        echo "$new_fmt"
    elif [ -f "$split_fmt" ]; then
        echo "$split_fmt"
    elif [ -f "$old_fmt" ]; then
        # parent_cmd一致チェック（旧報告の誤採用防止）
        report_parent=$(grep -E "^\s*parent_cmd:" "$old_fmt" | head -1 | sed 's/.*parent_cmd:\s*//' | tr -d "'" | tr -d '"')
        if [ "$report_parent" = "$cmd" ]; then
            echo "$old_fmt"  # parent_cmd一致 → 採用
        else
            echo "$new_fmt"  # 不一致 → 新形式パス返却（存在しない=報告なし扱い）
        fi
    else
        echo "$new_fmt"  # デフォルト（存在チェックは呼び出し側）
    fi
}

# Snapshot report_filename for every worker with one awk process. The gate
# already snapshots matching tasks later; this early lookup cache only removes
# repeated parsing and does not decide task membership or completion state.
declare -A REPORT_FILENAME_CACHE=()
REPORT_FILENAME_CACHE_READY=true
_report_cache_task_files=("$TASKS_DIR"/*.yaml)
if [ -e "${_report_cache_task_files[0]:-}" ]; then
    while IFS=$'\t' read -r _report_cache_file _report_cache_name; do
        [ -n "$_report_cache_file" ] || continue
        _report_cache_ninja="${_report_cache_file##*/}"
        _report_cache_ninja="${_report_cache_ninja%.yaml}"
        REPORT_FILENAME_CACHE["$_report_cache_ninja"]="$_report_cache_name"
    done < <(awk '
        /^[[:space:]]*report_filename:/ {
            value=$0
            sub(/^[[:space:]]*report_filename:[[:space:]]*/, "", value)
            gsub(/^["'"'"']|["'"'"']$/, "", value)
            print FILENAME "\t" value
            nextfile
        }
    ' "${_report_cache_task_files[@]}" 2>/dev/null)
fi
unset _report_cache_task_files _report_cache_file _report_cache_name _report_cache_ninja

LAST_GATE_NOTIFY_ROUTE=""
CLEAR_NOTIFICATION_SENT=false

dispatch_gate_notification_async() {
    local route="$1"
    shift
    local log_file="$SCRIPT_DIR/logs/cmd_complete_gate_async.log"

    # Notification delivery is deliberately outside the completion decision.
    # Match deploy_task.sh's fire-and-forget boundary so endpoint retries and
    # ntfy_batch's bounded flock cannot delay or alter the gate result.
    (
        if ! bash "$@" >> "$log_file" 2>&1; then
            printf '%(%Y-%m-%dT%H:%M:%S%z)T notification route=%s status=failed\n' -1 "$route" >> "$log_file"
        fi
    ) </dev/null &
    return 0
}

send_high_notification() {
    local message="$1"
    LAST_GATE_NOTIFY_ROUTE="ntfy.sh"
    dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
        "$SCRIPT_DIR/scripts/ntfy.sh" "$message"
}

send_info_cmd_notification() {
    local cmd_id="$1"
    local message="$2"
    local batch_script="$SCRIPT_DIR/scripts/ntfy_batch.sh"

    if [ -x "$batch_script" ]; then
        LAST_GATE_NOTIFY_ROUTE="ntfy_batch.sh"
        # ntfy_batch.sh accepts the message as its sole argument.
        dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
            "$batch_script" "$message"
    else
        LAST_GATE_NOTIFY_ROUTE="ntfy_cmd.sh"
        dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
            "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message"
    fi
}

gate_clear_notify_dedup_key() {
    local cmd_id="$1"
    if [[ "$cmd_id" =~ ^(cmd_karo_hotfix_ga[0-9]+)(_.+)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$cmd_id" =~ ^(.+)_[0-9]{12,14}$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    printf '%s\n' "$cmd_id"
}

# cmd_karo_hotfix_gate_clear_notify_dedup_20260728: 旧dedupはqueue/inbox/{shogun,karo}.yaml
# (live inboxのみ)をgrep/re-parseする方式だった。karoは完了時手順でinbox_archive.shを高頻度
# 実行するため、1度目の通知が既読化→archiveへ退避された直後に同一cmd(family)が再GATE実行
# (BLOCK→修正→CLEAR)されると、live inboxに見つからず「未送信」と誤判定し重複配送していた
# (実測: cmd_3513/cmd_3869/cmd_4122でkaro skill_hintが2通ずつ配送。archive.doneと同じ
# queue/gates/{key}/配下に永続flagを置き、archiveの影響を受けない冪等境界にする。
# 別プロセスの同時実行に対しては (set -C) のO_EXCL相当でatomicにclaimし、
# check-then-actのレース窓を閉じる。
gate_clear_notify_flag_path() {
    local recipient="$1" cmd_id="$2" key
    key="$(gate_clear_notify_dedup_key "$cmd_id")"
    printf '%s/queue/gates/%s/notify_%s.done\n' "$SCRIPT_DIR" "$key" "$recipient"
}

# 移行backfill (家老差分レビュー2回目でグローバルmarker/lock方式を撤回): 本修正より前に
# queue/inbox(live)またはarchive/inboxへ配送済みのcmdはflagが存在しないため、無対応だと
# 次回の再GATEで1通だけ余計に送られてしまう。グローバルmarkerで「移行済み」を1回だけ判定
# する設計は、(a) marker未確定の間に他プロセスがclaimへ素通りできる競合、(b) 1ファイルの
# parse失敗を握り潰したままmarkerを確定させ欠落を永続化する、という2つの穴を持っていた。
# 対象key(recipient+cmd family)のflagをatomicにclaimできたプロセスだけがそのkeyの
# live+archive履歴を1回走査する設計にすると、claim自体が排他制御を兼ねるため上記2つの
# 穴が構造的に消える: 敗者はflag存在で即SKIP(履歴走査自体を行わない)、勝者はkeyごとに
# 高々1回だけ走査し、parse失敗はそのkeyについてだけ「証跡なし」扱いになる(他keyへ波及しない)。
gate_clear_notify_historical_evidence() {
    local recipient="$1" cmd_id="$2" key type_match f
    key="$(gate_clear_notify_dedup_key "$cmd_id")"
    case "$recipient" in
        shogun) type_match='gate_clear' ;;
        karo) type_match='skill_hint' ;;
        *) return 1 ;;
    esac

    for f in "$SCRIPT_DIR/queue/inbox/${recipient}.yaml" "$SCRIPT_DIR/archive/inbox/${recipient}_"*.yaml; do
        [ -f "$f" ] || continue
        # 高速前置フィルタ: keyが出現しないファイルはpython3起動を払わずに除外する。
        # 該当メッセージのcontentは常にkey(または家族名の元となった長いcmd_id)を
        # 部分文字列として含むため、この前置grepは偽陰性を生まない。
        grep -qF -- "$key" "$f" 2>/dev/null || continue
        if GCN_KEY="$key" GCN_TYPE="$type_match" python3 - "$f" <<'PY' 2>/dev/null
import os
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path = sys.argv[1]
key = os.environ["GCN_KEY"]
type_match = os.environ["GCN_TYPE"]


def dedup_key(cmd_id):
    m = re.match(r"^(cmd_karo_hotfix_ga[0-9]+)(_.+)?$", cmd_id)
    if m:
        return m.group(1)
    m = re.match(r"^(.+)_[0-9]{12,14}$", cmd_id)
    if m:
        return m.group(1)
    return cmd_id


try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    sys.exit(1)

for msg in data.get("messages") or []:
    if not isinstance(msg, dict) or msg.get("type") != type_match:
        continue
    content = str(msg.get("content") or "")
    m = re.search(r"GATE CLEAR\s+—\s+(\S+)\s+完了", content)
    if m and dedup_key(m.group(1)) == key:
        sys.exit(0)
sys.exit(1)
PY
        then
            return 0
        fi
    done
    return 1
}

gate_clear_notify_claim() {
    local recipient="$1" cmd_id="$2" flag_file
    flag_file="$(gate_clear_notify_flag_path "$recipient" "$cmd_id")"
    mkdir -p "$(dirname "$flag_file")" 2>/dev/null

    if ! ( set -C; printf '%s\n' "$cmd_id" > "$flag_file" ) 2>/dev/null; then
        return 1
    fi

    if gate_clear_notify_historical_evidence "$recipient" "$cmd_id"; then
        printf '%s\tbackfill\n' "$cmd_id" > "$flag_file"
        return 1
    fi

    return 0
}

notify_shogun_gate_clear() {
    local cmd_id="$1"
    local message="${2:-GATE CLEAR — ${cmd_id} 完了}"
    local stderr_tmp flag_file
    stderr_tmp="$(mktemp)"
    flag_file="$(gate_clear_notify_flag_path shogun "$cmd_id")"

    if ! gate_clear_notify_claim shogun "$cmd_id"; then
        echo "  shogun inbox: SKIP (gate clear notify dedup)"
        rm -f "$stderr_tmp"
        return 0
    fi

    if timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun "$message" gate_clear cmd_complete_gate 2>"$stderr_tmp"; then
        echo "  shogun inbox: OK (gate clear notify)"
    else
        log_gate_stderr_file "notify_shogun_gate_clear inbox_write" "$stderr_tmp"
        echo "  [INFO] shogun inbox: WARN (gate clear notify failed, non-blocking)"
        # 直前のgate_clear_notify_claimが成功した(=このプロセスが排他的に作成した)flagのみを
        # 対象とするため、他プロセスのclaimを誤って消す競合はない。送信失敗時にflagを残すと
        # 通知が永久に欠落するため、次回の再試行を許可するためロールバックする。
        rm -f "$flag_file"
    fi
    rm -f "$stderr_tmp"
}

notify_karo_cmd_complete_skill_hint() {
    local cmd_id="$1"
    local message="GATE CLEAR — ${cmd_id} 完了。/cmd-complete スキルで完了処理を実行せよ。"
    local flag_file
    flag_file="$(gate_clear_notify_flag_path karo "$cmd_id")"

    if ! gate_clear_notify_claim karo "$cmd_id"; then
        echo "  karo /cmd-complete hint: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" skill_hint cmd_complete_gate 2>/dev/null; then
        echo "  karo /cmd-complete hint: OK"
    else
        echo "  [INFO] karo /cmd-complete hint: WARN (non-blocking)"
        rm -f "$flag_file"
    fi
}

send_clear_notifications_once() {
    local cmd_id="$1"
    local phase="${2:-GATE CLEAR}"

    if [ "${CLEAR_NOTIFICATION_SENT:-false}" = true ]; then
        echo "  clear notification: SKIP (already sent)"
        return 0
    fi

    echo "Auto-notification (${phase}):"
    if send_info_cmd_notification "$cmd_id" "GATE CLEAR — ${cmd_id} 完了" 2>/dev/null; then
        echo "  ${LAST_GATE_NOTIFY_ROUTE}: OK (INFO)"
    else
        echo "  [INFO] ${LAST_GATE_NOTIFY_ROUTE:-notification}: WARN (INFO notification failed, non-blocking)" >&2
    fi
    notify_shogun_gate_clear "$cmd_id" "GATE CLEAR — ${cmd_id} 完了"
    notify_karo_cmd_complete_skill_hint "$cmd_id"
    CLEAR_NOTIFICATION_SENT=true
}

notify_karo_lesson_registration_reminder() {
    local cmd_id="$1"
    local ninja_name="$2"
    local message="lesson_candidate found:trueだがlesson.done未生成: ${cmd_id}/${ninja_name}。lesson_write.shで教訓登録を完了せよ。"

    if grep -q "lesson.done未生成: ${cmd_id}/${ninja_name}" "$SCRIPT_DIR/queue/inbox/karo.yaml" 2>/dev/null; then
        echo "  karo lesson reminder: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" lesson_registration_reminder cmd_complete_gate 2>/dev/null; then
        echo "  karo lesson reminder: OK"
    else
        echo "  [INFO] karo lesson reminder: WARN (non-blocking)"
    fi
}

# Return 0 if there is already an unread type=gate_block message for cmd_id in karo's inbox.
# Used by notify_karo_gate_block() to suppress duplicate BLOCK notifications regardless of reason text.
karo_gate_block_unread_exists() {
    local cmd_id="$1"
    local inbox_file="$SCRIPT_DIR/queue/inbox/karo.yaml"
    [ -f "$inbox_file" ] || return 1

    python3 - "$inbox_file" "$cmd_id" <<'PY'
import sys
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path, cmd_id = sys.argv[1], sys.argv[2]

try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    sys.exit(1)

for msg in data.get("messages") or []:
    if not isinstance(msg, dict):
        continue
    if msg.get("type") != "gate_block":
        continue
    if msg.get("read"):
        continue
    content = str(msg.get("content") or "")
    if re.match(rf"^{re.escape(cmd_id)} gate_result: BLOCK(?:\s|$)", content):
        sys.exit(0)
sys.exit(1)
PY
}

notify_karo_gate_block() {
    local cmd_id="$1"
    local block_reason="$2"
    local missing_list="${3:-}"
    local message
    if declare -F format_gate_block_message >/dev/null 2>&1; then
        message=$(format_gate_block_message "$cmd_id" "$block_reason" "$missing_list")
    else
        # Extracted legacy fixture helpers may source this function alone.
        local dedup_key="${cmd_id} gate_result: BLOCK reason=${block_reason}"
        message="${dedup_key} missing=[${missing_list}]。再配備提案: BLOCK理由を確認し、該当忍者へ修正再配備せよ。"
    fi

    if karo_gate_block_unread_exists "$cmd_id"; then
        echo "  karo gate_block notify: SKIP (dedup — already in inbox)"
        if declare -F append_line_locked >/dev/null 2>&1 && [ -n "${LOG_DIR:-}" ]; then
            append_line_locked "$LOG_DIR/gate_fire_log.yaml" \
                "- ts: \"$(date '+%Y-%m-%dT%H:%M:%S')\", file: \"${cmd_id}\", gate: \"gate_block_dedup\", result: SKIP, checks: \"dedup_suppressed=1 reason=${block_reason} detector_fp_rate=tracked\""
        fi
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_block cmd_complete_gate 2>/dev/null; then
        echo "  karo gate_block notify: OK"
    else
        echo "  [INFO] karo gate_block notify: WARN (non-blocking)"
    fi
}

notify_karo_cmd_fail() {
    local cmd_id="$1"
    local ninja_name="$2"
    local report_file="$3"
    local fail_reason="$4"
    local report_name
    report_name=$(basename "$report_file" 2>/dev/null || printf '%s' "$report_file")
    local dedup_key="${cmd_id} gate_result: FAIL ninja=${ninja_name}"
    local message="${dedup_key} report=${report_name} reason=${fail_reason}。再配備提案: FAIL報告を確認し、修正タスクを再配備せよ。"

    if grep -Fq "$dedup_key" "$SCRIPT_DIR/queue/inbox/karo.yaml" 2>/dev/null; then
        echo "  karo cmd_fail notify: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_fail cmd_complete_gate 2>/dev/null; then
        echo "  karo cmd_fail notify: OK"
    else
        echo "  [INFO] karo cmd_fail notify: WARN (non-blocking)"
    fi
}

log_skill_execution_pass() {
    local skill_name="$1"
    local gate_name="$2"
    local source_id="$3"
    local skill_path="$SCRIPT_DIR/skills/${skill_name}/SKILL.md"
    local log_script="$SCRIPT_DIR/scripts/skill_execution_log.sh"
    # executor帰属: タスクYAMLファイル名からninja名抽出(CLI非依存)
    local _pass_executor="${AGENT_ID:-}"
    if [ -z "$_pass_executor" ] && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        _pass_executor=$(basename "${MATCHING_TASK_FILES[0]}" .yaml)
    fi
    _pass_executor="${_pass_executor:-unknown}"

    [ "${SKILL_EXECUTION_PASS_LOG_DISABLE:-0}" != "1" ] || return 0
    [ -x "$log_script" ] || return 0
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    if [ "${SKILL_EXECUTION_PASS_LOG_ASYNC:-1}" = "0" ]; then
        timeout 10 bash "$log_script" \
            "$skill_name" \
            "$_pass_executor" \
            "PASS" \
            "${gate_name} PASS" \
            "$gate_name" \
            "$source_id" \
            "$skill_path" >/dev/null 2>&1 || true
        return 0
    fi

    (
        timeout 10 bash "$log_script" \
            "$skill_name" \
            "$_pass_executor" \
            "PASS" \
            "${gate_name} PASS" \
            "$gate_name" \
            "$source_id" \
            "$skill_path" >/dev/null 2>&1 || true
    ) >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 &
}

# ─── GATE CLEAR時 task duration記録（cmd_2129） ───
# 上位指示: CTX%ではなく実時間を正本指標とする。
# acknowledged_at/done_at を優先し、既存運用データの deployed_at/completed_at にフォールバックする。
# INS-20260708-232310653-77c5: reflux/hotfix系は高速タスク回転により、GATE CLEAR判定時点で
# queue/tasks/{ninja}.yamlが既に次cmdの配備で上書きされ4フィールド全消失することがある。
# タスクYAML本体に依存しない per-cmd 不変マーカー(dispatch_ntfy_started/report timestamp)を
# 追加フォールバックとして使い、上書きレースでもduration_secを復元する。
build_clear_duration_metric() {
    local task_file
    local duration_sec
    local max_duration=-1
    local resolved=0
    local ninja_name marker_file report_file fallback_start fallback_end

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        [ -f "$task_file" ] || continue

        ninja_name=$(basename "$task_file" .yaml)
        fallback_start=""
        fallback_end=""
        marker_file="$SCRIPT_DIR/queue/dispatch_ntfy_started/${CMD_ID}.started"
        if [ -f "$marker_file" ]; then
            fallback_start=$(awk '/^timestamp:/ { sub(/^timestamp:[ \t]*/, ""); gsub(/["'"'"']/, ""); print; exit }' "$marker_file" 2>/dev/null || true)
        fi
        report_file=$(resolve_report_file "$ninja_name" "$CMD_ID" 2>/dev/null || true)
        if [ -n "$report_file" ] && [ -f "$report_file" ]; then
            fallback_end=$(awk '/^timestamp:/ { sub(/^timestamp:[ \t]*/, ""); gsub(/["'"'"']/, ""); print; exit }' "$report_file" 2>/dev/null || true)
        fi

        duration_sec=$(TASK_FILE_ENV="$task_file" FALLBACK_START_ENV="$fallback_start" FALLBACK_END_ENV="$fallback_end" CMD_ID_ENV="$CMD_ID" python3 - <<'PY'
import os
from datetime import datetime

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

task_file = os.environ["TASK_FILE_ENV"]
fallback_start = os.environ.get("FALLBACK_START_ENV", "")
fallback_end = os.environ.get("FALLBACK_END_ENV", "")
cmd_id_env = os.environ.get("CMD_ID_ENV", "")
try:
    with open(task_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("")
    raise SystemExit(0)

task = data.get("task", data)
if not isinstance(task, dict):
    print("")
    raise SystemExit(0)

# task fileはninja毎に使い回されるため、reflux/hotfix系の高速タスク回転では
# GATE CLEAR判定までに次cmdの配備で上書きされていることがある(INS-20260708-232310653-77c5)。
# parent_cmd/cmd_idが今回のcmdと一致しない場合は上書き後の別cmdのデータなので、
# task file由来の時刻は信用せずper-cmd不変マーカー(fallback_start/fallback_end)のみを使う。
current_cmd = str(task.get("parent_cmd") or task.get("cmd_id") or "").strip()
task_matches_cmd = bool(cmd_id_env) and current_cmd == cmd_id_env

if task_matches_cmd:
    start_raw = task.get("acknowledged_at") or task.get("deployed_at") or fallback_start or ""
    end_raw = task.get("done_at") or task.get("completed_at") or fallback_end or ""
else:
    start_raw = fallback_start or ""
    end_raw = fallback_end or ""

if not start_raw or not end_raw:
    print("")
    raise SystemExit(0)

def parse_iso(raw: str):
    raw = str(raw).strip().strip("'").strip('"')
    dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    # task file(naive)とreport file(`date -Iseconds`でtz付き)が混在するため、
    # tz-awareはnaiveへ正規化してから比較する(offset-naive/aware TypeError防止)。
    return dt.replace(tzinfo=None)

try:
    start_dt = parse_iso(start_raw)
    end_dt = parse_iso(end_raw)
    delta = int((end_dt - start_dt).total_seconds())
except Exception:
    print("")
    raise SystemExit(0)

if delta < 0:
    print("")
else:
    print(delta)
PY
)

        if [ -n "$duration_sec" ] && [ "$duration_sec" -ge 0 ] 2>/dev/null; then
            if [ "$duration_sec" -gt "$max_duration" ]; then
                max_duration="$duration_sec"
            fi
            resolved=$((resolved + 1))
        fi
    done

    if [ "$resolved" -gt 0 ] && [ "$max_duration" -ge 0 ] 2>/dev/null; then
        printf 'duration_sec=%s' "$max_duration"
    else
        printf 'duration_sec=unknown'
    fi
}

# ─── GATE CLEAR時 throughput段階別duration記録（cmd_3764） ───
# cmd 1サイクルの起票→配備→ack→done→CLEARを常時計測する。
# 欠損は unknown ではなく missing=<reason,...> に集約して記録する。
build_clear_throughput_metric() {
    local clear_ts="${1:-$(date +%Y-%m-%dT%H:%M:%S)}"

    CMD_ID_ENV="$CMD_ID" YAML_FILE_ENV="$YAML_FILE" CLEAR_TS_ENV="$clear_ts" \
    python3 - "${MATCHING_TASK_FILES[@]}" <<'PY'
import os
import sys
import glob
from datetime import datetime

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

cmd_id = os.environ["CMD_ID_ENV"]
yaml_file = os.environ["YAML_FILE_ENV"]
clear_ts_raw = os.environ["CLEAR_TS_ENV"]
task_files = sys.argv[1:]
root_dir = os.path.dirname(os.path.dirname(yaml_file))


def parse_iso(raw):
    text = str(raw or "").strip().strip("'").strip('"')
    if not text or text.lower() in {"null", "none", "unknown"}:
        return None
    text = text.replace('\\"', '"').strip('"')
    text = text.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).replace(tzinfo=None)
    except Exception:
        return None


def sec(start, end):
    if start is None or end is None:
        return None
    delta = int((end - start).total_seconds())
    return delta if delta >= 0 else None


def fmt(value):
    return str(value) if value is not None else "na"


issue_ts = None
try:
    with open(yaml_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    commands = data.get("commands")
    entry = None
    if isinstance(commands, dict):
        entry = commands.get(cmd_id)
    elif isinstance(commands, list):
        for item in commands:
            if isinstance(item, dict) and str(item.get("id", "")).strip() == cmd_id:
                entry = item
                break
    if isinstance(entry, dict):
        issue_ts = parse_iso(entry.get("delegated_at") or entry.get("timestamp") or entry.get("created_at"))
except Exception:
    issue_ts = None

if issue_ts is None:
    for rel in ("logs/cmd_design_quality.yaml", "logs/archive/cmd_design_quality.yaml"):
        path = os.path.join(root_dir, rel)
        try:
            with open(path, encoding="utf-8") as f:
                quality_data = yaml.safe_load(f) or []
        except Exception:
            continue
        if isinstance(quality_data, dict):
            quality_data = quality_data.get("entries") or []
        candidates = []
        for item in quality_data if isinstance(quality_data, list) else []:
            if not isinstance(item, dict) or str(item.get("cmd_id", "")).strip() != cmd_id:
                continue
            ts = parse_iso(item.get("timestamp"))
            if ts is not None:
                candidates.append(ts)
        if candidates:
            issue_ts = min(candidates)
            break

deploy_values = []
issued_values = []
ack_values = []
done_values = []
for path in task_files:
    try:
        with open(path, encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
    except Exception:
        continue
    task = raw.get("task", raw) if isinstance(raw, dict) else {}
    if not isinstance(task, dict):
        continue
    issued_values.append(parse_iso(task.get("issued_at")))
    deploy_values.append(parse_iso(task.get("deployed_at")))
    ack_values.append(parse_iso(task.get("acknowledged_at")))
    done_values.append(parse_iso(task.get("done_at") or task.get("completed_at")))

# deploy_sec is deployment machinery latency, not "time until the latest RC
# redeploy".  task.deployed_at is intentionally overwritten on every
# redeployment, while issued_at is preserved for the cmd generation; combining
# those two values misclassified all rework time as deployment wait.  The
# append-only issue log has an immutable attempt id and explicit issued/deployed
# terminal events, so use the latest successful attempt pair together with the
# current task/report timestamps. Keep task fields only as a backward-compatible
# fallback for pre-log commands.
attempt_events = {}
issue_log_path = os.path.join(root_dir, "logs", "deploy_issue_log.yaml")
try:
    current = {}
    with open(issue_log_path, encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n")
            if line.startswith("- attempt_id:"):
                current = {
                    "attempt_id": line.split(":", 1)[1].strip().strip('"').strip("'")
                }
                continue
            if not current or not line.startswith("  ") or ":" not in line:
                continue
            key, value = line.strip().split(":", 1)
            current[key] = value.strip().strip('"').strip("'")
            if key != "timestamp":
                continue
            if current.get("cmd_id") != cmd_id:
                current = {}
                continue
            attempt_id = current.get("attempt_id", "")
            result = current.get("result", "")
            ts = parse_iso(current.get("timestamp"))
            if attempt_id and result in {"issued", "deployed"} and ts is not None:
                attempt_events.setdefault(attempt_id, {})[result] = ts
            current = {}
except (OSError, UnicodeError):
    attempt_events = {}

successful_attempts = []
for attempt_id, events in attempt_events.items():
    start = events.get("issued")
    end = events.get("deployed")
    if sec(start, end) is not None:
        successful_attempts.append((end, start, attempt_id))
successful_attempts.sort()
current_attempt_deploy_ts = successful_attempts[-1][0] if successful_attempts else None
current_attempt_issue_ts = successful_attempts[-1][1] if successful_attempts else None

# Report timestamps are the durable done event. Prefer reports whose filename
# carries this cmd id; only legacy filenames fall back to the full recursive
# scan. This keeps the latest valid completion/revision semantics unchanged
# while avoiding YAML parsing for unrelated historical reports.
report_done_values = []
preferred_patterns = (
    os.path.join(root_dir, "queue/reports", f"*{cmd_id}*.yaml"),
    os.path.join(root_dir, "archive/reports", "**", f"*{cmd_id}*.yaml"),
)
preferred_paths = []
for pattern in preferred_patterns:
    preferred_paths.extend(glob.glob(pattern, recursive=True))

if preferred_paths:
    report_paths = sorted(set(preferred_paths))
    report_scan_mode = "cmd_filename_preferred"
else:
    legacy_patterns = (
        os.path.join(root_dir, "queue/reports/*.yaml"),
        os.path.join(root_dir, "archive/reports/**/*.yaml"),
    )
    report_paths = sorted({
        path
        for pattern in legacy_patterns
        for path in glob.glob(pattern, recursive=True)
    })
    report_scan_mode = "legacy_full_scan"

for path in report_paths:
        try:
            with open(path, encoding="utf-8") as f:
                report = yaml.safe_load(f) or {}
        except Exception:
            continue
        if not isinstance(report, dict) or str(report.get("parent_cmd") or "").strip() != cmd_id:
            continue
        if str(report.get("status") or "").strip() not in {"completed", "done", "revision_requested"}:
            continue
        ts = parse_iso(report.get("timestamp"))
        if ts is not None:
            report_done_values.append(ts)

issued_ts = min((v for v in issued_values if v is not None), default=None)
if issue_ts is None:
    issue_ts = issued_ts
deploy_ts = max((v for v in deploy_values if v is not None), default=None)
ack_ts = min((v for v in ack_values if v is not None), default=None)
done_ts = max((v for v in done_values + report_done_values if v is not None), default=None)
clear_ts = parse_iso(clear_ts_raw)

effective_issue_ts = (
    current_attempt_issue_ts if current_attempt_issue_ts is not None else issue_ts
)
effective_deploy_ts = (
    current_attempt_deploy_ts if current_attempt_deploy_ts is not None else deploy_ts
)
deploy_sec = sec(effective_issue_ts, effective_deploy_ts)
# Retry overwrites the task timestamps. Keep work and e2e on that same latest
# successful attempt: a stale pre-retry ack must not restart work before the
# current deployment boundary.
work_start_ts = ack_ts
if current_attempt_deploy_ts is not None and (
    work_start_ts is None or work_start_ts < current_attempt_deploy_ts
):
    work_start_ts = current_attempt_deploy_ts
work_sec = sec(work_start_ts, done_ts)
finalize_sec = sec(done_ts, clear_ts)
e2e_sec = sec(effective_issue_ts, clear_ts)

missing = []
if effective_issue_ts is None:
    missing.append("missing_issue_ts")
if effective_deploy_ts is None:
    missing.append("missing_deploy_ts")
if ack_ts is None:
    missing.append("missing_ack_ts")
if done_ts is None:
    missing.append("missing_done_ts")
if clear_ts is None:
    missing.append("missing_clear_ts")
for name, value in (
    ("deploy_sec", deploy_sec),
    ("work_sec", work_sec),
    ("finalize_sec", finalize_sec),
    ("e2e_sec", e2e_sec),
):
    if value is None:
        missing.append(f"invalid_{name}")

missing_text = ",".join(dict.fromkeys(missing)) if missing else "none"
print(
    f"deploy_sec={fmt(deploy_sec)} "
    f"work_sec={fmt(work_sec)} "
    f"finalize_sec={fmt(finalize_sec)} "
    f"e2e_sec={fmt(e2e_sec)} "
    f"missing={missing_text}"
)
PY
}

# ─── GATE CLEAR時 CTX%記録（cmd_2129） ───
# MATCHING_TASK_FILES内の各忍者のtmuxペインからCTX%を取得し最大値を返す。
# 取得不可の場合は ctx_pct=unknown を返す。
build_clear_ctx_metric() {
    local max_ctx=-1
    local resolved=0
    local task_file ninja_name pane_target ctx_val ctx_num

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        [ -f "$task_file" ] || continue
        ninja_name=$(basename "$task_file" .yaml)
        pane_target=$(agent_pane_target "$ninja_name" 2>/dev/null || true)
        [ -n "$pane_target" ] || continue
        ctx_val=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null || true)
        ctx_num=$(echo "$ctx_val" | grep -oE '[0-9]+' | tail -1)
        if [ -n "$ctx_num" ] && [ "$ctx_num" -ge 0 ] 2>/dev/null; then
            if [ "$ctx_num" -gt "$max_ctx" ]; then
                max_ctx="$ctx_num"
            fi
            resolved=$((resolved + 1))
        fi
    done

    if [ "$resolved" -gt 0 ] && [ "$max_ctx" -ge 0 ] 2>/dev/null; then
        printf 'ctx_pct=%s' "$max_ctx"
    else
        printf 'ctx_pct=unknown'
    fi
}

# The legacy ctx_pct field is the maximum CTX of matching ninja panes.  It
# cannot answer whether Karo's completion workload is shrinking, even though
# cmd_3931/cmd_3932/cmd_3956 explicitly target Karo CTX.  Record the Karo pane
# independently so future before/after averages do not mislabel ninja CTX.
build_karo_ctx_metric() {
    local pane_target ctx_val ctx_num
    pane_target=$(agent_pane_target "karo" 2>/dev/null || true)
    if [ -n "$pane_target" ]; then
        ctx_val=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null || true)
        ctx_num=$(printf '%s\n' "$ctx_val" | grep -oE '[0-9]+' | tail -1)
    fi

    if [ -n "${ctx_num:-}" ] && [ "$ctx_num" -ge 0 ] 2>/dev/null && [ "$ctx_num" -le 100 ] 2>/dev/null; then
        printf 'karo_ctx_pct=%s' "$ctx_num"
    else
        printf 'karo_ctx_pct=unknown'
    fi
}

build_first_gate_model_metric() {
    local first_gate="true"
    local profile
    if [ -f "$GATE_METRICS_LOG" ] && awk -F '\t' -v cmd="$CMD_ID" '$2 == cmd { found=1; exit } END { exit(found ? 0 : 1) }' "$GATE_METRICS_LOG" 2>/dev/null; then
        first_gate="false"
    fi
    profile="$(model_injection_profile_intensity "${GATE_MODEL:-unknown}" 2>/dev/null || printf '%s' "standard")"
    printf 'first_gate=%s\tmodel_profile=%s' "$first_gate" "$profile"
}

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local current_status
    local stderr_tmp
    stderr_tmp="$(mktemp)"
    current_status=$(CMD_ID_ENV="$cmd_id" YAML_FILE_ENV="$YAML_FILE" python3 -c "
import yaml, os, sys
cmd_id = os.environ['CMD_ID_ENV']
yaml_file = os.environ['YAML_FILE_ENV']
try:
    with open(yaml_file) as f:
        data = yaml.safe_load(f)
    if not data:
        sys.exit(0)
    cmds = data.get('commands', data.get('cmds', data))
    if isinstance(cmds, dict):
        entry = cmds.get(cmd_id, {})
        if isinstance(entry, dict):
            print(entry.get('status', ''))
    elif isinstance(cmds, list):
        for entry in cmds:
            if not isinstance(entry, dict):
                continue
            if entry.get('id') == cmd_id:
                print(entry.get('status', ''))
                break
except Exception as e:
    print(f'parse_error: {e}', file=sys.stderr)
" 2>"$stderr_tmp" || true)
    log_gate_stderr_file "update_status yaml_parse" "$stderr_tmp"
    rm -f "$stderr_tmp"

    case "$current_status" in
        completed|done)
            echo "STATUS ALREADY COMPLETED: ${cmd_id} (skip)"
            return 0
            ;;
        "")
            echo "WARN: status parse returned empty for ${cmd_id} in ${YAML_FILE}" >&2
            echo "ERROR: status not found for ${cmd_id} in ${YAML_FILE}" >&2
            return 1
            ;;
    esac

    if ! yaml_field_set "$YAML_FILE" "$cmd_id" "status" "done"; then
        echo "ERROR: yaml_field_set failed (${cmd_id})" >&2
        return 1
    fi

    echo "STATUS UPDATED: ${cmd_id} → done"
}

# ─── GATE CLEAR後 task YAML を idle 化（cmd_karo_gate_clear_idle） ───
# 報告読取と archive 完了後にのみ実行し、次の配備で stale task を残さない。
set_matching_tasks_idle() {
    local task_file ninja_name current_status verify_status current_parent_cmd
    local updated_count=0 skipped_count=0 warn_count=0

    echo ""
    echo "Task idle transition (post-GATE CLEAR):"

    if [ "${#MATCHING_TASK_FILES[@]}" -eq 0 ]; then
        echo "  (no tasks found for this cmd)"
        return 0
    fi

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        [ -f "$task_file" ] || continue
        ninja_name=$(basename "$task_file" .yaml)
        current_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "")

        if [ "$current_status" = "idle" ]; then
            echo "  ${ninja_name}: already idle"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # cmd_karo_speed_completion_pipeline_20260725: reassignment race guard.
        # MATCHING_TASK_FILES is a stale snapshot from gate-check-loop start; by
        # the time this post-CLEAR job runs, karo may already have redeployed
        # this ninja onto a different cmd (status acknowledged/in_progress on a
        # still-open report). Only a live re-read of parent_cmd==CMD_ID AND
        # status in {done,completed} proves the file still belongs to *this*
        # just-completed cmd, so a mid-report task is never stomped to idle.
        current_parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
        if [ "$current_parent_cmd" != "$CMD_ID" ]; then
            echo "  ${ninja_name}: skip (parent_cmd=${current_parent_cmd:-unknown} != ${CMD_ID}, reassigned)"
            skipped_count=$((skipped_count + 1))
            continue
        fi
        case "$current_status" in
            done|completed) ;;
            *)
                echo "  ${ninja_name}: skip (status=${current_status:-unknown}, task in progress)"
                skipped_count=$((skipped_count + 1))
                continue
                ;;
        esac

        if task_lifecycle_set_idle "$task_file" "gate_clear" >/dev/null 2>&1; then
            verify_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "")
            if [ "$verify_status" = "idle" ]; then
                echo "  ${ninja_name}: ${current_status:-unknown} → idle"
                updated_count=$((updated_count + 1))
            else
                echo "  [INFO] ${ninja_name}: WARN status verification failed (${current_status:-unknown} → ${verify_status:-empty})"
                warn_count=$((warn_count + 1))
            fi
            continue
        fi

        echo "  [INFO] ${ninja_name}: WARN task lifecycle update skipped (${current_status:-unknown})"
        warn_count=$((warn_count + 1))
    done

    echo "  summary: updated=${updated_count} skipped=${skipped_count} warn=${warn_count}"
}

record_finalize_phase_event() {
    local phase="${1:-}" generation="${SHOGUN_COMPLETION_GENERATION:-}"
    [[ "$phase" =~ ^(archive|task_idle)$ ]] || return 2
    [[ "$generation" =~ ^[0-9a-f]{64}$ ]] || return 2
    defense_overhead_write completion_finalize "$phase" 0 PASS \
        "completion-finalize-${phase}-${CMD_ID}-${generation}" \
        "{\"cmd_id\":\"${CMD_ID}\",\"generation\":\"${generation}\"}" || {
        [ "$?" -eq 4 ] && return 0
        return 3
    }
}

# ─── CoDD registry自動追記（cmd_2510） ───
# 共有台帳の並行手編集を避けるため、CoDD改善cmdのCLEAR時にgate側で一元追記する。
append_codd_registry_entry() {
    local cmd_id="$1"
    local registry="$SCRIPT_DIR/docs/research/codd_refactor_registry.md"
    local registry_lock
    local result

    echo ""
    echo "CoDD registry append (GATE CLEAR):"

    if [ ! -f "$registry" ]; then
        echo "  SKIP (registry not found)"
        return 0
    fi

    registry_lock="$(lock_path "$registry")"
    result=$(
        (
            flock -w 10 200 || { echo "WARN: registry lock timeout"; exit 0; }
            local ledger_file="$SCRIPT_DIR/logs/script_speed_training_ledger.yaml"
            python3 - "$cmd_id" "$YAML_FILE" "$registry" "$ledger_file" "${MATCHING_TASK_FILES[@]}" <<'PY'
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)


cmd_id = sys.argv[1]
cmd_yaml = Path(sys.argv[2])
registry = Path(sys.argv[3])
ledger_path = Path(sys.argv[4])
task_paths = [Path(p) for p in sys.argv[5:]]
repo_root = registry.parents[2]


def load_yaml(path):
    try:
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def cmd_entry():
    data = load_yaml(cmd_yaml)
    cmds = data.get("commands", data.get("cmds", data))
    if isinstance(cmds, dict):
        entry = cmds.get(cmd_id, {})
        return entry if isinstance(entry, dict) else {}
    if isinstance(cmds, list):
        for item in cmds:
            if isinstance(item, dict) and item.get("id") == cmd_id:
                return item
    return {}


def unwrap_task(data):
    if isinstance(data, dict) and isinstance(data.get("task"), dict):
        return data["task"]
    return data if isinstance(data, dict) else {}


def report_path_for(task_path, task):
    ninja = task_path.stem
    explicit = str(task.get("report_filename") or "").strip().strip("'\"")
    candidates = []
    if explicit:
        candidates.append(repo_root / "queue" / "reports" / explicit)
    candidates.append(repo_root / "queue" / "reports" / f"{ninja}_report_{cmd_id}.yaml")
    candidates.append(repo_root / "queue" / "reports" / f"{ninja}_report.yaml")
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0] if candidates else None


def flatten_strings(value):
    out = []
    if isinstance(value, dict):
        for k, v in value.items():
            out.append(str(k))
            out.extend(flatten_strings(v))
    elif isinstance(value, list):
        for item in value:
            out.extend(flatten_strings(item))
    elif value is not None:
        out.append(str(value))
    return out


def rel_path(raw):
    s = str(raw).strip().strip("'\"`")
    if not s:
        return ""
    try:
        p = Path(s)
        if p.is_absolute():
            try:
                return str(p.relative_to(repo_root))
            except ValueError:
                return s
    except Exception:
        pass
    return s


def uniq(seq):
    seen = set()
    out = []
    for item in seq:
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


def extract_paths(texts, pattern):
    found = []
    for text in texts:
        for match in re.finditer(pattern, text):
            found.append(rel_path(match.group(0).rstrip(".,;)")))
    return uniq(found)


def first_measurement(text):
    patterns = [
        r"(?i)before[^0-9]{0,40}([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)",
        r"(?i)([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)[^0-9]{0,40}before",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            return f"{m.group(1)}{m.group(2)}"
    return ""


def after_measurement(text):
    patterns = [
        r"(?i)after[^0-9]{0,40}([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)",
        r"(?i)([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)[^0-9]{0,40}after",
        r"~?([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)\s*[→-]\s*~?([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if not m:
            continue
        if len(m.groups()) >= 4:
            return f"{m.group(3)}{m.group(4)}"
        return f"{m.group(1)}{m.group(2)}"
    return ""


def before_after_from_text(text):
    arrow = re.search(
        r"~?([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)\s*[→-]\s*~?([0-9]+(?:\.[0-9]+)?)\s*(ms|msec|s|sec|秒)",
        text,
    )
    before = first_measurement(text)
    after = after_measurement(text)
    if arrow:
        before = before or f"{arrow.group(1)}{arrow.group(2)}"
        after = after or f"{arrow.group(3)}{arrow.group(4)}"
    return before, after


def measurement_from_report(report, keys):
    for key in keys:
        value = report.get(key)
        if value is None or value == "":
            continue
        if key.endswith("_ms"):
            return f"{value}ms"
        return str(value)
    return ""


def script_from_spec(spec_path, fallback_texts):
    candidates = []
    for text in fallback_texts:
        candidates.extend(extract_paths([text], r"(?:scripts|tests)/[A-Za-z0-9_./-]+\.(?:sh|py|bats)"))
    spec_abs = repo_root / spec_path
    if spec_path and spec_abs.exists():
        try:
            spec_text = spec_abs.read_text(encoding="utf-8", errors="ignore")
            candidates.extend(extract_paths([spec_text], r"(?:scripts|tests)/[A-Za-z0-9_./-]+\.(?:sh|py|bats)"))
        except Exception:
            pass
    return uniq(candidates)


entry = cmd_entry()
cmd_texts = flatten_strings(entry)
task_records = []
report_texts = []
spec_paths = []
target_paths = []
before = ""
after = ""

for task_path in task_paths:
    task = unwrap_task(load_yaml(task_path))
    if str(task.get("parent_cmd") or "") != cmd_id and str(task.get("cmd_id") or "") != cmd_id:
        continue
    task_records.append((task_path, task))
    task_texts = flatten_strings(task)
    target_paths.extend(extract_paths(task_texts, r"(?:scripts|tests)/[A-Za-z0-9_./-]+\.(?:sh|py|bats)"))
    report_path = report_path_for(task_path, task)
    report = load_yaml(report_path) if report_path else {}
    report_text = "\n".join(flatten_strings(report))
    report_texts.append(report_text)
    spec_paths.extend(extract_paths([report_text], r"docs/research/[A-Za-z0-9_./-]*codd[A-Za-z0-9_./-]*\.md"))
    before = before or measurement_from_report(report, ("before_real_ms", "before_ms", "before_median_ms", "before_time_ms", "before"))
    after = after or measurement_from_report(report, ("after_real_ms", "after_ms", "after_median_ms", "after_time_ms", "after"))
    if not before or not after:
        b, a = before_after_from_text(report_text)
        before = before or b
        after = after or a

all_text = "\n".join(cmd_texts + report_texts)
is_codd = bool(re.search(r"CoDD|codd_refactor|codd_refactor_registry|codd_spec", all_text, re.IGNORECASE))
# 修行速度改善cmd (type: training) もCoDD台帳対象とする（cmd_3099教訓）
is_training = any(str(t.get("type") or "") == "training" for _, t in task_records)
if not is_codd:
    is_codd = is_training
if not is_codd:
    print("SKIP: not a CoDD cmd")
    raise SystemExit(0)

spec_paths.extend(extract_paths(cmd_texts, r"docs/research/[A-Za-z0-9_./-]*codd[A-Za-z0-9_./-]*\.md"))
spec_paths = uniq(spec_paths)

for spec in spec_paths:
    try:
        spec_text = (repo_root / spec).read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if not before or not after:
        b, a = before_after_from_text(spec_text)
        before = before or b
        after = after or a
    target_paths.extend(script_from_spec(spec, []))

target_paths.extend(script_from_spec(spec_paths[0] if spec_paths else "", cmd_texts + report_texts))
target_paths = uniq(target_paths)

# AC1: 速度改善修行cmdではledgerからbefore_real_ms/after_real_msを優先取得（ワンソース化）
ledger_target_script = ""
if is_training and ledger_path.exists():
    ledger_data = load_yaml(ledger_path)
    for ledger_entry in ledger_data.get("entries", []):
        entry_script = str(ledger_entry.get("script_path", ""))
        if entry_script in target_paths:
            lbefore = ledger_entry.get("before_real_ms")
            lafter = ledger_entry.get("after_real_ms")
            if lbefore not in (None, "", 0):
                before = f"{lbefore}ms"
            if lafter not in (None, "", 0):
                after = f"{lafter}ms"
            ledger_target_script = entry_script
            break

if not task_records:
    print("SKIP: no matching task YAML")
    raise SystemExit(0)
if not target_paths:
    print("SKIP: target script not found")
    raise SystemExit(0)
if not before or not after:
    print("SKIP: before/after measurement not found")
    raise SystemExit(0)

registry_text = registry.read_text(encoding="utf-8")
if re.search(rf"\b{re.escape(cmd_id)}\b", registry_text):
    print(f"SKIP: already registered ({cmd_id})")
    raise SystemExit(0)

date = datetime.now().strftime("%Y-%m-%d")
workers = uniq(str(t.get("assigned_to") or p.stem) for p, t in task_records)
worker = "+".join(workers) if workers else "unknown"
target = ", ".join(f"`{p}`" for p in target_paths[:3])
if len(target_paths) > 3:
    target += f" (+{len(target_paths) - 3})"
spec_cell = ", ".join(f"`{p}`" for p in spec_paths[:2]) if spec_paths else f"`{cmd_id}` report-derived"
if len(spec_paths) > 2:
    spec_cell += f" (+{len(spec_paths) - 2})"
phase = f"Phase 5(auto registry via cmd_complete_gate, {cmd_id})"
row = f"| {date} | {worker} | {target} | {phase} | `{before} → {after}` | {spec_cell} |\n"

lines = registry_text.splitlines(keepends=True)
insert_at = None
for idx, line in enumerate(lines):
    if line.startswith("|------"):
        insert_at = idx + 1
        break
if insert_at is None:
    print("SKIP: registry table header not found")
    raise SystemExit(0)

lines.insert(insert_at, row)
fd, tmp = tempfile.mkstemp(dir=str(registry.parent), suffix=".tmp")
os.close(fd)
try:
    with open(tmp, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.replace(tmp, registry)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)

print(f"OK: appended {cmd_id} target={target_paths[0]} before_after={before}->{after}")

# AC2: ledgerのstatusをcompletedに更新（テキスト操作。yaml.dump不使用）
if is_training and ledger_target_script and ledger_path.exists():
    ledger_text = ledger_path.read_text(encoding="utf-8")
    lines_l = ledger_text.splitlines(keepends=True)
    result_l = []
    in_target = False
    status_done = False
    target_marker = f'- script_path: "{ledger_target_script}"'
    for line_l in lines_l:
        stripped_l = line_l.rstrip()
        if stripped_l.lstrip() == target_marker:
            in_target = True
            status_done = False
        elif in_target and not status_done and stripped_l.lstrip().startswith("- ") and stripped_l.lstrip() != target_marker:
            in_target = False
        if in_target and not status_done and re.match(r"\s+status:\s+\S", stripped_l):
            line_l = re.sub(r"(\s+status:\s+)\S+", r"\1completed", line_l)
            status_done = True
        result_l.append(line_l)
    ld, ltmp = tempfile.mkstemp(dir=str(ledger_path.parent), suffix=".tmp")
    os.close(ld)
    try:
        with open(ltmp, "w", encoding="utf-8") as f:
            f.writelines(result_l)
        os.replace(ltmp, str(ledger_path))
    finally:
        if os.path.exists(ltmp):
            os.unlink(ltmp)
    print(f"  ledger status -> completed ({ledger_target_script})")
PY
        ) 200>"$registry_lock"
    ) || {
        echo "  [WARN] CoDD registry append failed (non-blocking)"
        return 0
    }
    echo "  ${result}"
}

# ─── CoDD propagate自動実行（cmd_2641） ───
# スクリプト変更後の設計書/SKILL.md陳腐化を防ぐため、GATE CLEAR後に
# CoDD依存グラフの下流更新を必ず1回実行する。失敗はCLEAR後処理を止めずWARN化。
run_codd_propagate_update() {
    local codd_bin="${CODD_BIN:-}"
    local codd_path="${CODD_PROPAGATE_PATH:-$SCRIPT_DIR}"
    local timeout_sec="${CODD_PROPAGATE_TIMEOUT:-120}"
    local output
    local rc

    echo ""
    echo "CoDD propagate update (GATE CLEAR):"

    if [ -z "$codd_bin" ]; then
        if [ -x "${HOME}/.codd-venv/bin/codd" ]; then
            codd_bin="${HOME}/.codd-venv/bin/codd"
        elif command -v codd >/dev/null 2>&1; then
            codd_bin="$(command -v codd)"
        fi
    fi

    if [ -z "$codd_bin" ] || [ ! -x "$codd_bin" ]; then
        echo "  [WARN] codd executable not found (skip)"
        return 0
    fi

    output=$(PATH="${HOME}/.codd-venv/bin:$PATH" timeout "$timeout_sec" "$codd_bin" propagate --path "$codd_path" --update 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  OK: codd propagate --path ${codd_path} --update"
    else
        echo "  [WARN] codd propagate failed (rc=${rc}, non-blocking)"
    fi

    if [ -n "$output" ]; then
        printf '%s\n' "$output" | sed 's/^/  /'
    fi
    return 0
}

# ─── SKILL.md script参照鮮度チェック（cmd_2809） ───
# GATE CLEAR後に、変更済み scripts/* を参照するSKILL.mdの追従漏れを可視化する。
# CLEAR済み後処理なので非BLOCKだが、実行自体は毎回強制する。
run_skill_script_refs_check() {
    local gate_script="${SKILL_SCRIPT_REFS_GATE_PATH:-$SCRIPT_DIR/scripts/gates/gate_skill_script_refs.sh}"
    local output
    local rc

    echo ""
    echo "SKILL.md script refs (GATE CLEAR):"

    if [ ! -x "$gate_script" ]; then
        echo "  [WARN] gate_skill_script_refs.sh not executable or not found: ${gate_script}"
        return 0
    fi

    set +e
    output=$(SKILL_REF_DISABLE_CACHE=1 bash "$gate_script" "$SCRIPT_DIR" 2>&1)
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
        printf '%s\n' "$output" | grep -E '^(走査:|OK:|--- 総合判定)' | sed 's/^/  /' || true
        return 0
    fi

    printf '%s\n' "$output" | grep -E '^(走査:|=== 要更新|=== 参照先|  WARN:|--- 総合判定)' | head -40 | sed 's/^/  /' || true
    if [ "$rc" -eq 2 ]; then
        echo "  [WARN] SKILL.md script refs need follow-up (non-blocking after CLEAR)"
        append_line_locked "$LOG_DIR/gate_fire_log.yaml" "$(date '+%Y-%m-%dT%H:%M:%S') [WARN] ${CMD_ID} gate: \"skill_script_refs\" stale_or_missing_refs"
        python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" gate \
            --gate-name "cmd_complete_gate:skill_script_refs" --result "WARN" \
            --cmd-id "${CMD_ID:-}" --ts "$(date -Is)" --detail "stale_or_missing_refs" \
            --source-file "$LOG_DIR/gate_fire_log.yaml" >/dev/null 2>&1 &
        disown 2>/dev/null || true
        # gate_skill_script_refs owns the aggregate follow-up insight when its
        # own writer successfully queued (or found active) the exact review.
        # Do not add a second cmd-specific insight for the same covered review;
        # retain this caller-side path only for queue failure/uncovered output.
        case "$output" in
            *$'FOLLOWUP_COVERS_REVIEW_REQUIRED: yes'*)
                echo "  insight: SKIP (aggregate follow-up already covers review)"
                return 0
                ;;
        esac
        if printf '%s\n' "${CMD_CHANGED_FILES:-}" | grep -qE '^scripts/'; then
            local insight_script="$SCRIPT_DIR/scripts/insight_write.sh"
            local changed_scripts
            local warn_summary
            local insight_msg

            changed_scripts=$(printf '%s\n' "${CMD_CHANGED_FILES:-}" | grep -E '^scripts/' | head -5 | paste -sd, -)
            warn_summary=$(printf '%s\n' "$output" | awk '
                /^  WARN:/ {
                    sub(/^  WARN:[[:space:]]*/, "")
                    if (count > 0) {
                        printf "; "
                    }
                    printf "%s", $0
                    count++
                    if (count >= 5) exit
                }
            ')
            [ -n "$warn_summary" ] || warn_summary="gate_skill_script_refs.sh rc=2"
            insight_msg="SKILL.md追従cmd候補: ${CMD_ID} で scripts変更(${changed_scripts})後にSKILL.md参照鮮度WARN。追従cmdを起票して ${warn_summary} を解消せよ。"

            if [ -x "$insight_script" ]; then
                if bash "$insight_script" "$insight_msg" "medium" "cmd_complete_gate:skill_script_refs:${CMD_ID}" >/dev/null 2>&1; then
                    echo "  insight: queued SKILL.md follow-up candidate"
                else
                    echo "  [WARN] insight_write failed for SKILL.md follow-up candidate"
                fi
            else
                echo "  [WARN] insight_write.sh not executable; SKILL.md follow-up candidate not queued"
            fi
        else
            echo "  insight: SKIP (no scripts/* changes in cmd)"
        fi
    else
        echo "  [WARN] gate_skill_script_refs.sh failed rc=${rc} (non-blocking after CLEAR)"
        append_line_locked "$LOG_DIR/gate_fire_log.yaml" "$(date '+%Y-%m-%dT%H:%M:%S') [WARN] ${CMD_ID} gate: \"skill_script_refs\" execution_failed rc=${rc}"
        python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" gate \
            --gate-name "cmd_complete_gate:skill_script_refs" --result "WARN" \
            --cmd-id "${CMD_ID:-}" --ts "$(date -Is)" --detail "execution_failed rc=${rc}" \
            --source-file "$LOG_DIR/gate_fire_log.yaml" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    return 0
}

# ─── karo_workarounds resolved_by_cmd 自動補完（cmd_2692） ───
# GATE CLEAR時、同一cmdの過去BLOCK理由からworkaroundカテゴリを推定し、
# resolved_by_cmd未記入の同カテゴリエントリを現在cmdで埋める。
# 失敗はCLEAR後処理を止めずWARN化する。
normalize_block_reason_to_workaround_categories() {
    local block_reasons="${1:-}"

    printf '%s\n' "$block_reasons" | tr '|' '\n' | awk '
        function emit(cat) {
            if (cat != "" && !seen[cat]++) print cat
        }
        {
            token = tolower($0)
            if (token ~ /report_format|lessons_useful|lesson_candidate|binary_checks|verdict|purpose_validation/) {
                emit("report_yaml_format")
            }
            if (token ~ /commit_missing|uncommitted|commit/) {
                emit("commit_missing")
            }
            if (token ~ /ac_version/) {
                emit("ac_version_mismatch")
            }
            if (token ~ /stale_report/) {
                emit("stale_report")
            }
            if (token ~ /deploy/) {
                emit("deploy_error")
            }
            if (token ~ /scope/) {
                emit("scope_mismatch")
            }
            if (token ~ /ci_/) {
                emit("ci_fix")
            }
            if (token ~ /missing_gate|lesson_done_missing|draft_lessons|review_gate|archive/) {
                emit("gate_missing")
            }
        }
    '
}

update_karo_workaround_resolutions() {
    local cmd_id="$1"
    local wa_file="${KARO_WORKAROUNDS_FILE:-$LOG_DIR/karo_workarounds.yaml}"
    local wa_lock="${KARO_WORKAROUNDS_LOCK_FILE:-$(lock_path "$wa_file")}"
    local block_reasons
    local categories
    local result

    echo ""
    echo "Karo workaround resolution update (GATE CLEAR):"

    if [ ! -f "$wa_file" ]; then
        echo "  SKIP (karo_workarounds.yaml not found)"
        return 0
    fi
    if [ ! -f "$GATE_METRICS_LOG" ]; then
        echo "  SKIP (gate_metrics.log not found)"
        return 0
    fi

    block_reasons=$(awk -F '\t' -v cmd="$cmd_id" '$2 == cmd && $3 == "BLOCK" && $4 != "" { print $4 }' "$GATE_METRICS_LOG" 2>/dev/null | paste -sd '|' -)
    if [ -z "$block_reasons" ]; then
        echo "  SKIP (no prior BLOCK category for ${cmd_id})"
        return 0
    fi

    categories=$(normalize_block_reason_to_workaround_categories "$block_reasons" | paste -sd ',' -)
    if [ -z "$categories" ]; then
        echo "  SKIP (no matching workaround category for BLOCK reasons: ${block_reasons})"
        return 0
    fi

    result=$(
        (
            flock -w 10 200 || { echo "WARN: lock timeout"; exit 0; }
            python3 - "$wa_file" "$cmd_id" "$categories" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

wa_file = Path(sys.argv[1])
cmd_id = sys.argv[2]
categories = {c for c in sys.argv[3].split(",") if c}

try:
    lines = wa_file.read_text(encoding="utf-8").splitlines(keepends=True)
except Exception as exc:
    print(f"WARN: read failed: {exc}")
    raise SystemExit(0)

entry_start_re = re.compile(r"^\s*-\s+[A-Za-z0-9_]+:")
field_re = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)(\r?\n?)$")


def scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    return value


def yaml_sq(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


entries = []
start = None
for idx, line in enumerate(lines):
    if entry_start_re.match(line):
        if start is not None:
            entries.append((start, idx))
        start = idx
if start is not None:
    entries.append((start, len(lines)))

updated = 0
new_lines = list(lines)
for start, end in entries:
    fields = {}
    field_line = {}
    for idx in range(start, end):
        text = new_lines[idx]
        if idx == start:
            first = re.sub(r"^\s*-\s*", "  ", text, count=1)
            m = field_re.match(first)
        else:
            m = field_re.match(text)
        if not m:
            continue
        key = m.group(2)
        fields[key] = scalar(m.group(3))
        field_line[key] = idx

    if fields.get("workaround") != "true":
        continue
    if fields.get("category") not in categories:
        continue
    if fields.get("resolved_by_cmd"):
        continue
    if "resolved_by_cmd" not in field_line:
        continue

    idx = field_line["resolved_by_cmd"]
    m = field_re.match(new_lines[idx])
    indent = m.group(1) if m else "  "
    newline = m.group(4) if m else "\n"
    new_lines[idx] = f"{indent}resolved_by_cmd: {yaml_sq(cmd_id)}{newline}"
    updated += 1

if updated:
    fd, tmp = tempfile.mkstemp(dir=str(wa_file.parent), suffix=".tmp")
    os.close(fd)
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
        os.replace(tmp, wa_file)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

print(f"updated={updated} categories={','.join(sorted(categories))}")
PY
        ) 200>"$wa_lock"
    ) || result="WARN: update failed"

    if [[ "$result" == WARN:* ]]; then
        echo "  [WARN] ${result#WARN: } (non-blocking)"
    else
        echo "  ${result}"
    fi
    return 0
}

# ─── 改修修正完了の自動観測（cmd_3862 AC2） ───
# 手動WA(workaround:true)とは別イベントとして記録する。これにより既存の
# manual WA率/root_signature閾値を変えず、hotfix/RC/karo_directの完了を漏れなく観測する。
classify_completed_rework_event_kind() {
    local cmd_id="${1:-}"
    local lowered="${cmd_id,,}"
    case "$lowered" in
        *karo_direct*) printf '%s\n' 'karo_direct' ;;
        *hotfix*) printf '%s\n' 'hotfix' ;;
        *_rc_*|*_rc|rc_*) printf '%s\n' 'rc' ;;
    esac
}

capture_completed_rework_event() {
    local cmd_id="${1:-}"
    local event_kind
    event_kind="$(classify_completed_rework_event_kind "$cmd_id")"
    [ -n "$event_kind" ] || return 0

    local wa_file="${KARO_WORKAROUNDS_FILE:-$LOG_DIR/karo_workarounds.yaml}"
    local wa_lock="${KARO_WORKAROUNDS_LOCK_FILE:-$(lock_path "$wa_file")}"
    local result
    if ! result=$( (
        flock -w 10 200 || { echo "ERROR: lock timeout"; exit 1; }
        python3 - "$wa_file" "$cmd_id" "$event_kind" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
cmd_id, event_kind, timestamp = sys.argv[2:]
path.parent.mkdir(parents=True, exist_ok=True)
lines = path.read_text(encoding="utf-8").splitlines(keepends=True) if path.exists() else []
starts = [i for i, line in enumerate(lines) if re.match(r"^-\s+[A-Za-z0-9_]+:\s*", line)]
starts.append(len(lines))
for start, end in zip(starts, starts[1:]):
    fields = {}
    for offset, line in enumerate(lines[start:end]):
        candidate = re.sub(r"^-\s+", "  ", line, count=1) if offset == 0 else line
        match = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", candidate)
        if match:
            fields[match.group(1)] = match.group(2).strip("'\"")
    if (fields.get("cmd_id") == cmd_id and fields.get("event_kind") == event_kind
            and fields.get("auto_captured") == "true"):
        print(f"duplicate=1 event_kind={event_kind}")
        raise SystemExit(0)

entry = (
    f"- cmd_id: {cmd_id}\n"
    f"  timestamp: '{timestamp}'\n"
    "  ninja: system\n"
    "  workaround: false\n"
    f"  event_kind: {event_kind}\n"
    "  auto_captured: true\n"
    "  category: rework_auto_capture\n"
    "  detail: 'cmd_complete_gate completed rework event'\n"
    "  root_cause: 'automatic completion observation'\n"
    "  lesson_required: false\n"
    "  lesson_disposition: not_applicable\n"
    "  lesson_reference: 'not_applicable'\n"
    f"  resolved_by_cmd: '{cmd_id}'\n"
)
fd, temporary = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
os.close(fd)
try:
    Path(temporary).write_text("".join(lines) + entry, encoding="utf-8")
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print(f"captured=1 event_kind={event_kind}")
PY
    ) 200>"$wa_lock" ); then
        echo "  [ERROR] rework event capture failed: ${result:-unknown error}" >&2
        return 1
    fi
    echo "  ${result}"
}

# ─── L6横展開候補自動保存（cmd_2653） ───
# Level5化に成功したcmdの語彙から、同種でLevel5未満の仕組みを探し、
# 次の改善候補としてinsightに保存する。CLEAR後のみ実行し、失敗は非ブロッキング。
write_l6_horizontal_level5_insights() {
    local cmd_id="${1:?cmd_id required}"
    local insight_script="$SCRIPT_DIR/scripts/insight_write.sh"

    echo ""
    echo "L6 horizontal Level5 candidate scan (GATE CLEAR):"

    if [ ! -x "$insight_script" ]; then
        echo "  SKIP (insight_write.sh not executable)"
        return 0
    fi

    local scan_output
    scan_output=$(L6_CMD_ID="$cmd_id" \
        L6_CMD_TITLE="${CMD_TITLE:-}" \
        L6_CMD_PURPOSE="${CMD_PURPOSE:-}" \
        L6_CMD_CHANGED_FILES="${CMD_CHANGED_FILES:-}" \
        L6_REPO_ROOT="$SCRIPT_DIR" \
        python3 <<'PY' 2>/dev/null
import os
import re
import sys
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

repo = Path(os.environ["L6_REPO_ROOT"])
cmd_id = os.environ.get("L6_CMD_ID", "")
title = os.environ.get("L6_CMD_TITLE", "")
purpose = os.environ.get("L6_CMD_PURPOSE", "")
changed_files = os.environ.get("L6_CMD_CHANGED_FILES", "")
signal_text = f"{title}\n{purpose}\n{changed_files}"

# L6: 全CLEARで横展開候補を探す（殿定義2026-05-10: 学習速度の最大化）
# シグナルワードフィルタ撤廃。トークンマッチングの品質で自然に絞る。
# changed_files/titleからトークンを抽出し、defense_level<5の同種候補をスキャン。
# マッチ0件なら自然にno-op。

stopwords = {
    "cmd", "level", "level5", "scripts", "tests", "unit", "bats", "sh",
    "gate", "hook", "自動", "候補", "強化", "実装", "追加", "修正", "確認",
    "cmd_save", "cmd_complete_gate",
}

tokens = []

def add_token(value):
    token = value.strip("_").lower()
    if not token or token in stopwords or token.startswith("cmd_"):
        return
    if re.fullmatch(r"[ぁ-んー]+", token):
        return
    if re.fullmatch(r"[一-龥ぁ-んァ-ンー]+", token) and len(token) < 2:
        return
    if re.fullmatch(r"[A-Za-z0-9_]+", token) and len(token) < 4:
        return
    tokens.append(token)

def add_japanese_tokens(value):
    # Japanese regex ranges otherwise turn whole clauses into one token
    # (e.g. "日本語トークン抽出が長文..." never matches shorter log phrases).
    chunks = re.findall(r"[一-龥]+|[ァ-ンー]+|[ぁ-ん]+", value)
    for chunk in chunks:
        if re.fullmatch(r"[ぁ-んー]+", chunk):
            continue
        add_token(chunk)
        if re.fullmatch(r"[一-龥]{3,}", chunk):
            for size in (2, 3, 4):
                if len(chunk) <= size:
                    continue
                for idx in range(0, len(chunk) - size + 1):
                    add_token(chunk[idx:idx + size])

for part in re.findall(r"[A-Za-z][A-Za-z0-9_]{3,}|[一-龥ぁ-んァ-ンー]+", signal_text):
    if re.search(r"[一-龥ぁ-んァ-ンー]", part):
        add_japanese_tokens(part)
    else:
        add_token(part)

for rel in changed_files.replace(",", "\n").splitlines():
    rel = rel.strip()
    if not rel:
        continue
    stem = Path(rel).stem.lower()
    if len(stem) >= 4 and stem not in stopwords:
        tokens.append(stem)

ordered_tokens = []
seen = set()
for token in tokens:
    if token in seen:
        continue
    seen.add(token)
    ordered_tokens.append(token)

if not ordered_tokens:
    sys.exit(0)

sources = [
    repo / "logs" / "gunshi_review_log.yaml",
    repo / "logs" / "gunshi_gp_tracker.yaml",
    repo / "logs" / "archive" / "gunshi_review_log_20260430b_to_20260501a.yaml",
    repo / "logs" / "archive" / "gunshi_review_log_cmd_2179_to_cmd_2231.yaml",
]

block_start = re.compile(r"^\s*-\s+(?:cmd_id|id|gp_id):")
level_re = re.compile(r"defense_level:\s*['\"]?([0-9]+)")
results = []
seen_keys = set()
existing_candidate_keys = set()

insights_path = repo / "queue" / "insights.yaml"
if insights_path.exists():
    try:
        loaded_insights = yaml.safe_load(insights_path.read_text(encoding="utf-8")) or []
    except (OSError, yaml.YAMLError):
        loaded_insights = []
    if isinstance(loaded_insights, dict):
        loaded_insights = loaded_insights.get("insights", [])
    if isinstance(loaded_insights, list):
        for entry in loaded_insights:
            if not isinstance(entry, dict):
                continue
            previous = str(entry.get("insight") or "")
            match = re.search(r"; candidate=(.*); source=([^;]+)$", previous)
            if match:
                existing_candidate_keys.add((match.group(2), match.group(1)))

def iter_blocks(text):
    current = []
    for line in text.splitlines():
        if block_start.match(line) and current:
            yield "\n".join(current)
            current = [line]
        else:
            current.append(line)
    if current:
        yield "\n".join(current)

def compact(s):
    s = re.sub(r"\s+", " ", s).strip()
    return s[:180]

for source in sources:
    if not source.exists():
        continue
    try:
        text = source.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        continue
    for block in iter_blocks(text):
        if cmd_id and cmd_id in block:
            continue
        lm = level_re.search(block)
        if not lm:
            continue
        level = int(lm.group(1))
        if level >= 5:
            continue
        block_l = block.lower()
        matched = [t for t in ordered_tokens if t in block_l]
        if not matched:
            continue
        summary = ""
        for key in ("findings_summary", "reason", "causal_chain", "description"):
            m = re.search(rf"{key}:\s*[\"']?(.*)", block)
            if m:
                summary = compact(m.group(1).strip("\"'"))
                break
        if not summary:
            summary = compact(block)
        candidate_key = (source.name, summary)
        if candidate_key in existing_candidate_keys:
            continue
        match_key = (level, summary[:90])
        if match_key in seen_keys:
            continue
        seen_keys.add(match_key)
        results.append((len(matched), level, ",".join(matched[:4]), summary, source.name))

results.sort(key=lambda r: (-r[0], r[1], r[3]))
for _score, level, matched, summary, source_name in results[:3]:
    print(f"同パターンLevel5未満候補: source_cmd={cmd_id}; matched={matched}; current_pattern={compact(title or purpose)}; candidate_level={level}; candidate={summary}; source={source_name}")
PY
    ) || {
        echo "  [WARN] scan failed (non-blocking)"
        return 0
    }

    if [ -z "$scan_output" ]; then
        echo "  OK: no Level5-under horizontal candidates"
        return 0
    fi

    local saved_count=0
    while IFS= read -r insight_msg; do
        [ -z "$insight_msg" ] && continue
        if bash "$insight_script" "$insight_msg" "medium" "cmd_complete_gate:l6_horizontal:${cmd_id}" >/dev/null 2>&1; then
            saved_count=$((saved_count + 1))
        else
            echo "  [WARN] insight_write failed for candidate $((saved_count + 1))"
        fi
    done <<< "$scan_output"
    echo "  saved: ${saved_count} horizontal candidate(s)"
    return 0
}

run_report_memory_semantic_scan() {
    local semantic_search="$SCRIPT_DIR/scripts/semantic_search.sh"
    local insight_script="$SCRIPT_DIR/scripts/insight_write.sh"

    echo "Report memory semantic scan (GATE CLEAR):"
    if [ ! -x "$semantic_search" ] || [ ! -x "$insight_script" ]; then
        echo "  SKIP (semantic_search.sh or insight_write.sh not executable)"
        return 0
    fi

    local tmp_queries
    tmp_queries="$(mktemp)"
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        [ -f "$task_file" ] || continue
        local ninja_name report_file
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue
        REPORT_PATH="$report_file" NINJA_NAME="$ninja_name" python3 - >> "$tmp_queries" <<'PY'
import os
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

report_path = os.environ["REPORT_PATH"]
ninja = os.environ["NINJA_NAME"]
try:
    with open(report_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)

def clean(value):
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    return text[:240]

items = []
lc = data.get("lesson_candidate")
if isinstance(lc, dict) and lc.get("found"):
    items.append(("lesson_candidate", clean(" ".join([str(lc.get("title", "")), str(lc.get("detail", ""))]))))

kc = data.get("knowledge_candidate")
if isinstance(kc, dict) and kc.get("found"):
    items.append(("knowledge_candidate", clean(" ".join([str(kc.get("fact", "")), str(kc.get("detail", ""))]))))

dc = data.get("decision_candidate")
if isinstance(dc, dict) and dc.get("found"):
    items.append(("decision_candidate", clean(" ".join([str(dc.get("title", "")), str(dc.get("question", "")), str(dc.get("detail", ""))]))))

for kind, query in items:
    if len(query) >= 12:
        print(f"{ninja}\t{kind}\t{query}")
PY
    done

    local checked=0 matched=0 queued=0 failed=0
    local ninja_name kind query
    while IFS=$'\t' read -r ninja_name kind query; do
        [ -n "$query" ] || continue
        checked=$((checked + 1))
        if SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 "$semantic_search" "$query" >/dev/null 2>&1; then
            matched=$((matched + 1))
        else
            local rc=$?
            if [ "$rc" -eq 1 ]; then
                if "$insight_script" "cmd_complete NO_MATCH aliases候補: ${CMD_ID} ${ninja_name} ${kind}: ${query}" low "cmd_complete_gate:memory_phase" >/dev/null 2>&1; then
                    queued=$((queued + 1))
                else
                    failed=$((failed + 1))
                fi
            else
                failed=$((failed + 1))
            fi
        fi
    done < "$tmp_queries"
    rm -f "$tmp_queries"

    echo "  checked=${checked} matched=${matched} no_match_queued=${queued} failed=${failed}"
    return 0
}

auto_resolve_cmd_related_insights() {
    local cmd_id="$1"
    local insight_script="$SCRIPT_DIR/scripts/insight_resolve.sh"
    local insights_file="${INSIGHTS_FILE:-$SCRIPT_DIR/queue/insights.yaml}"
    local tasks_dir="${INSIGHT_TASKS_DIR:-$SCRIPT_DIR/queue/tasks}"
    local reports_dir="${INSIGHT_REPORTS_DIR:-$SCRIPT_DIR/queue/reports}"

    [ -n "$cmd_id" ] || return 0
    [ -x "$insight_script" ] || return 0
    [ -s "$insights_file" ] || return 0

    local ids
    local stderr_tmp
    stderr_tmp="$(mktemp)"
    local select_rc=0
    if ! ids=$(INSIGHTS_FILE_ENV="$insights_file" CMD_ID_ENV="$cmd_id" TASKS_DIR_ENV="$tasks_dir" REPORTS_DIR_ENV="$reports_dir" python3 - <<'PY' 2>"$stderr_tmp"
import os
import pathlib
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path = os.environ["INSIGHTS_FILE_ENV"]
cmd_id = os.environ["CMD_ID_ENV"]
roots = (os.environ["TASKS_DIR_ENV"], os.environ["REPORTS_DIR_ENV"])
ins_id_re = re.compile(r"\bINS-[A-Za-z0-9][A-Za-z0-9._:-]*\b")

def belongs_to_cmd(obj):
    if not isinstance(obj, dict):
        return False
    task = obj.get("task") if isinstance(obj.get("task"), dict) else obj
    return any(str(task.get(k) or "") == cmd_id for k in ("parent_cmd", "cmd_id", "id"))

def collect_refs(value, refs):
    if isinstance(value, dict):
        explicit = value.get("origin_insight_ids")
        if isinstance(explicit, list):
            refs.update(str(v) for v in explicit if str(v).startswith("INS-"))
        for child in value.values():
            collect_refs(child, refs)
    elif isinstance(value, list):
        for child in value:
            collect_refs(child, refs)
    elif isinstance(value, str):
        refs.update(ins_id_re.findall(value))

declared = set()
for root in roots:
    directory = pathlib.Path(root)
    if not directory.is_dir():
        continue
    for candidate in directory.glob("*.yaml"):
        try:
            doc = yaml.safe_load(candidate.read_text(encoding="utf-8")) or {}
        except Exception as exc:
            # cmd_karo_hotfix_post_clear_fail_open_20260725 (root cause): an unrelated
            # malformed report/task file (e.g. literal-tab corruption from the awk -v
            # Cescape bug) used to abort selection for EVERY cmd via sys.exit(2), even
            # when that file had nothing to do with the cmd currently completing.
            # Skip the broken source and keep collecting from the rest instead.
            print(f"WARN: skipping unparseable declaration source {candidate}: {exc}", file=sys.stderr)
            continue
        if belongs_to_cmd(doc):
            collect_refs(doc, declared)

try:
    entries = (yaml.safe_load(pathlib.Path(path).read_text(encoding="utf-8")) or {}).get("insights") or []
except Exception as exc:
    print(f"ERROR: cannot parse insights: {exc}", file=sys.stderr)
    sys.exit(2)

for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("status") != "pending":
        continue
    entry_id = str(entry.get("id") or "")
    exact_action = any(str(entry.get(k) or "") == cmd_id for k in ("action_cmd", "resolved_by_cmd"))
    if entry_id in declared or exact_action:
        print(entry_id)

known = {str(entry.get("id") or "") for entry in entries if isinstance(entry, dict)}
missing = sorted(declared - known)
if missing:
    print("ERROR: declared origin insight id(s) not found: " + ",".join(missing), file=sys.stderr)
    sys.exit(3)
PY
    ); then
        select_rc=$?
        # `!` normalizes $? to zero; selection failure is represented explicitly.
        select_rc=1
    fi
    log_gate_stderr_file "auto_resolve_cmd_related_insights parse" "$stderr_tmp"
    rm -f "$stderr_tmp"
    if [ "$select_rc" -ne 0 ]; then
        echo "  [WARN] insight declaration selection failed (non-blocking)"
        return 1
    fi

    local count=0 failures=0 id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if INSIGHTS_FILE="$insights_file" bash "$insight_script" "$id" \
            "GATE CLEAR: ${cmd_id} completed declared remediation" \
            "cmd=${cmd_id};gate=cmd_complete_gate;result=CLEAR" >/dev/null 2>&1; then
            count=$((count + 1))
        else
            echo "  [WARN] insight resolve failed: $id (non-blocking)"
            failures=$((failures + 1))
        fi
    done <<< "$ids"

    [ "$failures" -eq 0 ] || return 1

    if [ "$count" -gt 0 ]; then
        echo "  resolved: ${count} cmd-related insight(s)"
    else
        echo "  resolved: 0 cmd-related insight(s)"
    fi
}

# ─── changelog自動記録関数 ───
append_changelog() {
    local cmd_id="$1"
    local changelog="$SCRIPT_DIR/queue/completed_changelog.yaml"
    local completed_at
    completed_at=$(date '+%Y-%m-%dT%H:%M:%S')

    # shogun_to_karo.yamlから該当cmdのpurposeとprojectを抽出 (dict形式: "  cmd_XXXX:")
    local purpose
    purpose=$(awk -v cmd="${cmd_id}" '
        /^  [a-zA-Z_].*:$/ { key=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", key); found=(key==cmd) ? 1 : 0; next }
        found && /^    (title|purpose):/ { sub(/^[[:space:]]*(title|purpose):[[:space:]]*"?/, ""); sub(/"[[:space:]]*$/, ""); print; exit }
    ' "$YAML_FILE")

    local project
    project=$(awk -v cmd="${cmd_id}" '
        /^  [a-zA-Z_].*:$/ { key=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", key); found=(key==cmd) ? 1 : 0; next }
        found && /^    project:/ { sub(/^[[:space:]]*project:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }
    ' "$YAML_FILE")

    if [ -z "$purpose" ]; then
        echo "CHANGELOG WARNING: purpose not found for ${cmd_id}"
        return 0
    fi
    [ -z "$project" ] && project="unknown"

    (
        flock -w 10 200 || exit 1

        # ファイルが無ければヘッダ作成
        if [ ! -f "$changelog" ]; then
            echo "entries:" > "$changelog"
        fi

        # エントリ追記
        cat >> "$changelog" <<EOF
  - id: ${cmd_id}
    project: ${project}
    purpose: "${purpose}"
    completed_at: "${completed_at}"
EOF

        # 20件超なら古い順に剪定（各エントリ=4行、ヘッダ=1行）
        local entry_count
        entry_count=$(awk '/^\s+- id:/{c++} END{print c+0}' "$changelog" 2>/dev/null)
        if [ "$entry_count" -gt 20 ]; then
            { head -1 "$changelog"; tail -n 80 "$changelog"; } > "${changelog}.tmp"
            if [ -s "${changelog}.tmp" ]; then
                mv "${changelog}.tmp" "$changelog"
            else
                rm -f "${changelog}.tmp"
                echo "CHANGELOG WARNING: trim produced empty output, keeping existing file" >&2
            fi
        fi
    ) 200>"$(lock_path "$changelog")" || {
        echo "CHANGELOG WARNING: lock timeout for ${changelog}"
        return 0
    }

    echo "CHANGELOG: ${cmd_id} recorded (project=${project})"
}

# ─── 軍師自動レビュー通知（cmd_1527: L3自動化, cmd_1665: 関数抽出） ───
# source可能な独立関数に抽出済み。PROJECT_ROOT=$SCRIPT_DIR で互換性維持。
export PROJECT_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/scripts/lib/gunshi_notify.sh"

# ─── non-overlap dirty hunk判定（SSOT, cmd_karo_hotfix_shared_dirty_commit_gate_202607101643） ───
# inbox_write.shのgit_uncommitted_gateとも共有する独立関数
source "$SCRIPT_DIR/scripts/lib/report_commit_nonoverlap_filter.sh"

# ─── task_type検出: タスクYAMLからparent_cmd一致のtask_typeを収集 ───
detect_task_types() {
    local cmd_id="$1"
    local has_recon=false
    local has_implement=false
    local task_files=()

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        task_files=("${MATCHING_TASK_FILES[@]}")
    elif declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        echo "${has_recon} ${has_implement}"
        return 0
    else
        task_files=("$TASKS_DIR"/*.yaml)
    fi

    for task_file in "${task_files[@]}"; do
        [ -f "$task_file" ] || continue
        local ttype
        ttype=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
        case "$ttype" in
            recon|recon2|scout) has_recon=true ;;
            implement|impl|full|normal|exact|hotfix|ci_fix|speed_training|skill_training|training|gp|improvement)
                has_implement=true
                ;;
            review|verify) ;; # 既知の非実装種別。条件ゲートには影響しない
            "")
                echo "[WARN] Missing task_type; fail-closed as implementation" >&2
                has_implement=true
                ;;
            *)
                echo "[WARN] Unknown task_type: '$ttype'; fail-closed as implementation" >&2
                has_implement=true
                ;;
        esac
    done

    # 結果を標準出力に返す（スペース区切り）
    echo "${has_recon} ${has_implement}"
}

is_lessons_useful_empty_warn_task_type() {
    local task_type
    task_type=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]"'"'"'')
    case "$task_type" in
        scout|verify|recon) return 0 ;;
        *) return 1 ;;
    esac
}

handle_empty_lessons_useful_check() {
    local ninja_name="$1"
    local task_type="$2"
    local rl_ids="$3"

    if is_lessons_useful_empty_warn_task_type "$task_type"; then
        echo "  [WARN] ${ninja_name}: lessons_useful空。task_type=${task_type:-unknown} のためBLOCK対象外。related_lessons [${rl_ids}]"
    else
        echo "  [CRITICAL] ${ninja_name}: NG ← lessons_useful空。related_lessons [${rl_ids}] のうち実際に役立った教訓を報告に記載せよ"
        record_block_reason "${ninja_name}:empty_lessons_useful:related=[${rl_ids}]"
        ALL_CLEAR=false
    fi
}

validate_lesson_feedback_set() {
    local task_file="$1"
    local report_file="$2"
    python3 "$SCRIPT_DIR/scripts/lib/report_gate_contract.py" \
        lesson-feedback-set "$task_file" "$report_file"
}

# ─── gate_metrics model label helpers ───
agent_pane_target() {
    local agent_name="$1"
    if [[ -f "$SCRIPT_DIR/scripts/lib/pane_lookup.sh" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
        pane_lookup "$agent_name" 2>/dev/null || true
    fi
}

normalize_model_label() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr -s ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$raw" ] && return 1
    echo "$raw"
}

encode_model_label_for_tsv() {
    local raw="$1"
    local normalized

    normalized=$(normalize_model_label "$raw" 2>/dev/null || true)
    [ -n "$normalized" ] || return 1
    echo "${normalized// /_}"
}

fallback_model_label_from_settings() {
    local ninja_name="$1"
    local settings_yaml="$SCRIPT_DIR/config/settings.yaml"
    local profiles_yaml="$SCRIPT_DIR/config/cli_profiles.yaml"

    [ -f "$settings_yaml" ] || return 1
    [ -f "$profiles_yaml" ] || return 1

    python3 - "$settings_yaml" "$profiles_yaml" "$ninja_name" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

settings_yaml, profiles_yaml, ninja_name = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(settings_yaml, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

try:
    with open(profiles_yaml, encoding="utf-8") as f:
        profiles_data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

cli = data.get("cli", {}) if isinstance(data, dict) else {}
agents = cli.get("agents", {}) if isinstance(cli, dict) else {}
agent_cfg = agents.get(ninja_name, {})
default_cli = cli.get("default", "claude") if isinstance(cli, dict) else "claude"
effort = str(data.get("effort", "") or "").strip()
profiles = profiles_data.get("profiles", {}) if isinstance(profiles_data, dict) else {}

cli_type = default_cli
model_label = ""
has_explicit_model = False

if isinstance(agent_cfg, str):
    cli_type = agent_cfg.strip() or default_cli
elif isinstance(agent_cfg, dict):
    cli_type = str(agent_cfg.get("type") or default_cli).strip() or default_cli
    model_label = str(agent_cfg.get("model_name") or "").strip()
    has_explicit_model = bool(model_label)

if not model_label:
    profile = profiles.get(cli_type, {}) if isinstance(profiles, dict) else {}
    model_label = str(profile.get("display_name") or cli_type or "").strip()

parts = [model_label]
if effort and has_explicit_model:
    label_words = model_label.split()
    if effort not in label_words:
        parts.append(effort)

raw = " ".join(part for part in parts if part)
print(" ".join(raw.split()))
PY
}

resolve_agent_model_label() {
    local ninja_name="$1"
    local pane_target raw_model normalized

    pane_target=$(agent_pane_target "$ninja_name" 2>/dev/null || true)
    if [ -n "$pane_target" ]; then
        raw_model=$(tmux display-message -t "$pane_target" -p '#{@model_name}' 2>/dev/null || true)
        if [ -n "$raw_model" ] && [ "$raw_model" != '#{@model_name}' ]; then
            normalized=$(normalize_model_label "$raw_model" 2>/dev/null || true)
            if [ -n "$normalized" ]; then
                echo "$normalized"
                return 0
            fi
        fi
    fi

    raw_model=$(fallback_model_label_from_settings "$ninja_name" 2>/dev/null || true)
    normalized=$(normalize_model_label "$raw_model" 2>/dev/null || true)
    if [ -n "$normalized" ]; then
        echo "$normalized"
        return 0
    fi

    return 1
}

# ─── cmd_407: gate_metrics拡張用 — task_type/model/bloom_levelの収集 ───
collect_gate_metrics_extra() {
    local cmd_id="$1"
    local task_types_csv=""
    local models_csv=""
    local bloom_levels_csv=""
    local _seen_types="" _seen_models="" _seen_bloom_levels=""
    local task_files=()

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        task_files=("${MATCHING_TASK_FILES[@]}")
    elif declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        printf 'unknown\tunknown\tunknown\n'
        return 0
    else
        task_files=("$TASKS_DIR"/*.yaml)
    fi

    for task_file in "${task_files[@]}"; do
        [ -f "$task_file" ] || continue
        # task_type収集
        local ttype
        ttype=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
        if [ -n "$ttype" ] && [[ "$_seen_types" != *"|$ttype|"* ]]; then
            _seen_types="${_seen_types}|${ttype}|"
            task_types_csv="${task_types_csv:+${task_types_csv},}${ttype}"
        fi

        # bloom_level収集（空欄はunknown）
        local bloom_level
        bloom_level=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "bloom_level" "")
        [ -z "$bloom_level" ] && bloom_level="unknown"
        if [[ "$_seen_bloom_levels" != *"|$bloom_level|"* ]]; then
            _seen_bloom_levels="${_seen_bloom_levels}|${bloom_level}|"
            bloom_levels_csv="${bloom_levels_csv:+${bloom_levels_csv},}${bloom_level}"
        fi

        # model収集: assigned_toのtmux @model_name を優先し、不可時はsettings.yamlへフォールバック
        local ninja_name
        ninja_name=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "assigned_to" "")
        if [ -n "$ninja_name" ]; then
            local model
            model=$(resolve_agent_model_label "$ninja_name" 2>/dev/null || true)
            model=$(encode_model_label_for_tsv "$model" 2>/dev/null || true)
            [ -z "$model" ] && model="unknown"
            if [[ "$_seen_models" != *"|$model|"* ]]; then
                _seen_models="${_seen_models}|${model}|"
                models_csv="${models_csv:+${models_csv},}${model}"
            fi
        fi
    done

    [ -z "$task_types_csv" ] && task_types_csv="unknown"
    [ -z "$models_csv" ] && models_csv="unknown"
    [ -z "$bloom_levels_csv" ] && bloom_levels_csv="unknown"

    printf '%s\t%s\t%s\n' "${task_types_csv}" "${models_csv}" "${bloom_levels_csv}"
}

# ─── cmd_466: gate_metrics拡張用 — 注入教訓ID収集 ───
collect_injected_lessons() {
    local cmd_id="$1"
    local injected_lessons

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 && [ "${#MATCHING_TASK_FILES[@]}" -eq 0 ]; then
        echo "none"
        return 0
    fi

    injected_lessons=$(python3 - "$TASKS_DIR" "$cmd_id" <<'PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

tasks_dir = sys.argv[1]
cmd_id = sys.argv[2]
seen = set()
ordered = []

for filename in sorted(os.listdir(tasks_dir)):
    if not filename.endswith(".yaml"):
        continue
    task_path = os.path.join(tasks_dir, filename)
    try:
        with open(task_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    task = data.get("task", data)
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    related_lessons = task.get("related_lessons") or []
    if not isinstance(related_lessons, list):
        continue
    for lesson in related_lessons:
        if isinstance(lesson, dict):
            lid = lesson.get("id")
        else:
            lid = lesson
        if lid is None:
            continue
        lid = str(lid).strip()
        if not lid or lid in seen:
            continue
        seen.add(lid)
        ordered.append(lid)

print(",".join(ordered) if ordered else "none")
PY
    ) || injected_lessons="none"

    [ -z "$injected_lessons" ] && injected_lessons="none"
    echo "$injected_lessons"
}

# ─── cmd_472: gate_metrics拡張用 — cmd title収集（shogun_to_karo.yaml） ───
collect_cmd_title() {
    local cmd_id="$1"
    local cmd_title=""

    if ! cmd_entry_exists "$cmd_id"; then
        echo ""
        return 0
    fi

    cmd_title=$(awk -v cmd="${cmd_id}" '
        /^[[:space:]]*-[[:space:]]*id:[[:space:]]*cmd_[0-9]+/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            gsub(/["[:space:]]/, "", line)
            if (line == cmd) {
                found = 1
                next
            }
            if (found) {
                exit
            }
        }
        found && /^[[:space:]]*title:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*title:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            print line
            exit
        }
    ' "$YAML_FILE" 2>/dev/null || true)

    cmd_title=$(printf '%s' "$cmd_title" | sed "s/^['\"]//; s/['\"]$//")
    cmd_title=${cmd_title//$'\t'/ }
    if [ "${#cmd_title}" -gt 50 ]; then
        cmd_title="${cmd_title:0:47}..."
    fi

    echo "$cmd_title"
}

# Resolve the report-declared source commit before any project-diff inspection.
# A completion gate runs in a shared worktree, so the live index/worktree is not
# an authoritative view of the command being completed.  The report commit is
# already the publication identity used by source-only autopush; reusing it here
# keeps scope inspection on immutable Git objects and avoids scanning unrelated
# local dirty files.
resolve_cmd_report_source_commit() {
    local cmd_id="$1"
    local repo="$2"
    local task_file ninja_name report_file candidate

    if ! declare -F collect_report_commit_hash >/dev/null 2>&1; then
        return 1
    fi

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name" "$cmd_id" 2>/dev/null || true)
            [ -f "$report_file" ] || continue
            candidate=$(collect_report_commit_hash "$report_file")
            if [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] \
                && git -C "$repo" cat-file -e "${candidate}^{commit}" 2>/dev/null; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    fi

    if declare -F discover_reports_for_cmd >/dev/null 2>&1; then
        while IFS= read -r report_file; do
            [ -f "$report_file" ] || continue
            candidate=$(collect_report_commit_hash "$report_file")
            if [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] \
                && git -C "$repo" cat-file -e "${candidate}^{commit}" 2>/dev/null; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done < <(discover_reports_for_cmd "$cmd_id")
    fi

    return 1
}

# ─── project code stub detection（WARN only, report source diff added lines only） ───
# cmd_1387: Python→bash/awk化。yaml.safe_load→awk, subprocess→direct git, regex→awk
check_project_code_stubs() {
    local cmd_id="$1"
    local cmd_project="$2"

    # --- Early exit: no project ---
    if [[ -z "$cmd_project" ]]; then
        printf 'SKIP\tproject not found in cmd\n'
        return 0
    fi
    # Strip quotes
    cmd_project="${cmd_project//\'/}"
    cmd_project="${cmd_project//\"/}"

    # --- resolve_project_path (awk on YAML, no python/yaml.safe_load) ---
    local project_path=""
    local pj_yaml="$SCRIPT_DIR/projects/${cmd_project}.yaml"
    if [[ -f "$pj_yaml" ]]; then
        # Try project.path first, then top-level path
        project_path=$(awk '
            /^project:/ { in_proj=1; next }
            in_proj && /^  path:/ { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
            in_proj && /^[^ ]/ { in_proj=0 }
            !in_proj && /^path:/ { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
        ' "$pj_yaml")
    fi
    if [[ -z "$project_path" ]]; then
        local config_yaml="$SCRIPT_DIR/config/projects.yaml"
        if [[ -f "$config_yaml" ]]; then
            project_path=$(awk -v target="$cmd_project" '
                /^  - id:/ { cur=$3; gsub(/["'"'"']/, "", cur) }
                /^    path:/ && cur == target { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
            ' "$config_yaml")
        fi
    fi

    if [[ -z "$project_path" ]]; then
        printf 'SKIP\tproject path not found for: %s\n' "$cmd_project"
        return 0
    fi
    if [[ ! -d "$project_path" ]]; then
        printf 'SKIP\tproject path missing: %s\n' "$project_path"
        return 0
    fi
    if ! git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'SKIP\tgit repo not found: %s\n' "$project_path"
        return 0
    fi

    # External app cmds can keep the parent project id (e.g. dm-signal) while
    # target_path points at a separate git repo (e.g. DM-Fusion). In that case,
    # inspect the target repo, not the parent repo's unrelated dirty tree.
    local task_dir_for_target="${TASKS_DIR:-$SCRIPT_DIR/queue/tasks}"
    local target_path_raw target_repo_probe target_repo_root current_repo_root
    if [[ -d "$task_dir_for_target" ]]; then
        target_path_raw=$(awk -v cmd="$cmd_id" '
            /^[[:space:]]*parent_cmd:[[:space:]]*/ {
                val = $0
                sub(/.*parent_cmd:[[:space:]]*/, "", val)
                gsub(/^["'"'"']+|["'"'"']+$/, "", val)
                in_target_cmd = (val == cmd)
            }
            in_target_cmd && /^[[:space:]]*target_path:[[:space:]]*/ {
                val = $0
                sub(/.*target_path:[[:space:]]*/, "", val)
                gsub(/^["'"'"']+|["'"'"']+$/, "", val)
                print val
                exit
            }
        ' "$task_dir_for_target"/*.yaml 2>/dev/null | head -1)
    fi
    if [[ "$target_path_raw" == /* ]]; then
        target_repo_probe="$target_path_raw"
        if [[ -f "$target_repo_probe" ]]; then
            target_repo_probe="${target_repo_probe%/*}"
        fi
        if [[ -d "$target_repo_probe" ]]; then
            target_repo_root=$(git -C "$target_repo_probe" rev-parse --show-toplevel 2>/dev/null || true)
            current_repo_root=$(git -C "$project_path" rev-parse --show-toplevel 2>/dev/null || true)
            if [[ -n "$target_repo_root" && "$target_repo_root" != "$current_repo_root" ]]; then
                project_path="$target_repo_root"
            fi
        fi
    fi

    # The live worktree may contain unrelated WIP or local-ahead commits.  Do
    # not inspect it and do not infer scope from HEAD history; a valid report
    # source commit is the only accepted inspection anchor.
    local source_commit source_parent
    source_commit=$(resolve_cmd_report_source_commit "$cmd_id" "$project_path" 2>/dev/null || true)
    if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
        printf 'SKIP\tsource commit unavailable for %s\n' "$cmd_id"
        return 0
    fi
    source_parent=$(git -C "$project_path" rev-parse "${source_commit}^" 2>/dev/null || true)
    if [[ ! "$source_parent" =~ ^[0-9a-f]{40}$ ]]; then
        printf 'SKIP\tsource parent unavailable for %s\n' "$source_commit"
        return 0
    fi

    # --- resolve_extensions (awk on YAML) ---
    local raw_langs=""
    if [[ -f "$pj_yaml" ]]; then
        # Try top-level languages: then project.languages:
        raw_langs=$(awk '
            /^languages:/ { found=1; next }
            found && /^  *- / { val=$2; gsub(/["'"'"']/, "", val); gsub(/^\./, "", val); print tolower(val); next }
            found && /^[^ ]/ { exit }
        ' "$pj_yaml")
        if [[ -z "$raw_langs" ]]; then
            raw_langs=$(awk '
                /^project:/ { in_proj=1; next }
                in_proj && /^[^ ]/ { exit }
                in_proj && /^  languages:/ { found=1; next }
                found && /^    *- / { val=$2; gsub(/["'"'"']/, "", val); gsub(/^\./, "", val); print tolower(val); next }
                found && !/^    / { exit }
            ' "$pj_yaml")
        fi
    fi

    # Map language aliases → file extensions
    local exts_str=""
    if [[ -n "$raw_langs" ]]; then
        exts_str=$(printf '%s\n' "$raw_langs" | while IFS= read -r lang; do
            case "$lang" in
                python)     echo "py" ;;
                typescript) echo "ts"; echo "tsx" ;;
                javascript) echo "js"; echo "jsx" ;;
                kotlin)     echo "kt" ;;
                py|ts|tsx|js|jsx|kt|java) echo "$lang" ;;
                *)          echo "$lang" ;;
            esac
        done | sort -u | paste -sd, -)
    fi
    if [[ -z "$exts_str" ]]; then
        exts_str="java,js,jsx,kt,py,ts,tsx"
    fi

    # --- Diff parsing + stub detection (single awk pass, no python) ---
    local diff_output diff_rc
    diff_output=$(git -C "$project_path" diff --unified=1 --no-color "$source_parent" "$source_commit" -- . 2>&1)
    diff_rc=$?
    if [[ $diff_rc -ne 0 ]]; then
        printf 'ERR\tgit diff failed for %s: %s\n' "$project_path" "$(printf '%s\n' "$diff_output" | head -1)"
        return 0
    fi

    local awk_result
    awk_result=$(printf '%s\n' "$diff_output" | gawk -v exts="$exts_str" -v max_show=10 '
        BEGIN {
            matches = 0; file_count = 0
            n = split(exts, ea, ",")
            for (i = 1; i <= n; i++) ext_set[ea[i]] = 1
        }

        /^\+\+\+ b\// {
            file = substr($0, 7)
            # Extract extension: last dot-delimited segment
            ext = ""
            if (match(file, /\.([^.\/]+)$/, m)) ext = tolower(m[1])
            last_sig = ""
            next
        }

        /^@@/ {
            # Extract +lineno from hunk header
            if (match($0, /\+([0-9]+)/, m))
                lineno = m[1] - 1
            else
                lineno = 0
            last_sig = ""
            next
        }

        # Skip if no file tracked or extension not in allowed set
        file == "" || !(ext in ext_set) { next }

        # Skip deletion lines
        /^-/ && !/^---/ { next }

        # Context lines (space prefix)
        /^ / {
            lineno++
            content = substr($0, 2)
            stripped = content
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", stripped)
            if (stripped != "" && substr(stripped, 1, 1) != "#")
                last_sig = stripped
            next
        }

        # Blank lines in diff (no prefix)
        /^$/ { next }

        # Added lines
        /^\+/ && !/^\+\+\+/ {
            lineno++
            line = substr($0, 2)
            trimmed = line
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)

            # --- return_stub: return null/None/{}/[] ---
            if (match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]+(null|None)([^a-zA-Z0-9_]|$)/) ||
                match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]*\{[[:space:]]*\}/) ||
                match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]*\[[[:space:]]*\]/)) {
                if (matches < max_show)
                    details[matches] = file ":" lineno ": [return_stub] " trimmed
                matches++
                if (!(file in seen)) { seen[file] = 1; file_count++ }
            }

            # --- marker_stub: TODO/FIXME/XXX/HACK/PLACEHOLDER (not in test/spec files) ---
            upper_line = toupper(line)
            if (match(upper_line, /(^|[^A-Z0-9_])(TODO|FIXME|XXX|HACK|PLACEHOLDER)([^A-Z0-9_]|$)/)) {
                lower_file = tolower(file)
                if (index(lower_file, "test") == 0 && index(lower_file, "spec") == 0) {
                    if (matches < max_show)
                        details[matches] = file ":" lineno ": [marker_stub] " trimmed
                    matches++
                    if (!(file in seen)) { seen[file] = 1; file_count++ }
                }
            }

            # --- pass_stub: bare pass in Python (except:pass is allowed) ---
            if (ext == "py" && match(line, /^[[:space:]]*pass([[:space:]]*#.*)?[[:space:]]*$/)) {
                allowed = 0
                # Check if last significant line is an except line
                if (last_sig != "" && match(last_sig, /^except([[:space:]]|[:(])/)) {
                    if (index(last_sig, ":") > 0) allowed = 1
                }
                if (!allowed) {
                    if (matches < max_show)
                        details[matches] = file ":" lineno ": [pass_stub] " trimmed
                    matches++
                    if (!(file in seen)) { seen[file] = 1; file_count++ }
                }
            }

            # Update last significant line for except:pass tracking
            if (trimmed != "" && substr(trimmed, 1, 1) != "#")
                last_sig = trimmed
        }

        END {
            if (matches == 0) {
                print "0"
            } else {
                printf "%d %d\n", matches, file_count
                for (i = 0; i < matches && i < max_show; i++)
                    print details[i]
                if (matches > max_show)
                    printf "... (%d hits across %d file(s), first %d shown)\n", matches, file_count, max_show
            }
        }
    ')

    if [[ "$awk_result" == "0" ]]; then
        printf 'OK\tno stub patterns in report source diff (base=%s, source=%s, ext=%s)\n' \
            "$source_parent" "$source_commit" "$exts_str"
    else
        local match_count file_count_out
        match_count=$(printf '%s\n' "$awk_result" | head -1 | cut -d' ' -f1)
        file_count_out=$(printf '%s\n' "$awk_result" | head -1 | cut -d' ' -f2)
        printf 'WARN\t%d stub-like added line(s) across %d file(s) (base=%s, source=%s)\n' \
            "$match_count" "$file_count_out" "$source_parent" "$source_commit"
        printf '%s\n' "$awk_result" | tail -n +2
    fi
}

# ─── wiring verification（WARN only, existence != integration） ───
check_script_wiring() {
    local cmd_id="$1"

    SCRIPT_DIR_ENV="$SCRIPT_DIR" CMD_ID_ENV="$cmd_id" python3 - <<'PY'
import os
import re
import subprocess

script_dir = os.environ["SCRIPT_DIR_ENV"]
cmd_id = os.environ["CMD_ID_ENV"].strip()
PATH_RE = re.compile(r"(?<![A-Za-z0-9_./-])(scripts/[A-Za-z0-9._/-]+\.sh)(?![A-Za-z0-9_./-])")


def emit(row_type: str, scope: str, status: str, message: str) -> None:
    print(f"{row_type}\t{scope}\t{status}\t{message}")


def git(repo_path: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", repo_path, *args],
        text=True,
        capture_output=True,
        check=False,
    )


def detect_cmd_commit_count(repo_path: str, target_cmd_id: str) -> int:
    log_proc = git(repo_path, "log", "--format=%H%x1f%s%x1f%b%x1e", "-n", "100")
    if log_proc.returncode != 0:
        return -1

    count = 0
    for record in log_proc.stdout.split("\x1e"):
        record = record.strip()
        if not record:
            continue
        parts = record.split("\x1f", 2)
        if len(parts) != 3:
            continue
        _commit_hash, subject, body = parts
        haystack = f"{subject}\n{body}"
        if target_cmd_id in haystack:
            count += 1
        elif count > 0:
            break

    return count


def is_script_target(rel_path: str) -> bool:
    return rel_path.startswith("scripts/") and rel_path.endswith(".sh")


def read_text(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def collect_reference_files() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    import glob as _glob

    forward_candidates: list[tuple[str, str]] = []
    reverse_candidates: list[tuple[str, str]] = []

    # Documentation wiring is a repository contract.  Enumerate the tracked
    # instruction graph instead of ambient filesystem files: ignored local
    # remnants must not create machine-dependent WARNs, while active
    # generated/roles/common/cli_specific documents must be covered.
    tracked_proc = git(
        script_dir,
        "ls-files",
        "--",
        "CLAUDE.md",
        "instructions/*.md",
        "instructions/**/*.md",
    )
    tracked_docs = sorted(dict.fromkeys(
        line.strip().replace(os.sep, "/")
        for line in tracked_proc.stdout.splitlines()
        if line.strip()
    )) if tracked_proc.returncode == 0 else []
    for rel_path in tracked_docs:
        abs_path = os.path.join(script_dir, rel_path)
        if not os.path.isfile(abs_path):
            continue
        forward_candidates.append((rel_path, abs_path))
        reverse_candidates.append((rel_path, abs_path))

    # scripts/**/*.sh (forward only)
    for abs_path in sorted(_glob.glob(os.path.join(script_dir, "scripts", "**", "*.sh"), recursive=True)):
        rel_path = os.path.relpath(abs_path, script_dir).replace(os.sep, "/")
        forward_candidates.append((rel_path, abs_path))

    forward_candidates.sort()
    reverse_candidates.sort()
    return forward_candidates, reverse_candidates


forward_candidates, reverse_candidates = collect_reference_files()
commit_count = detect_cmd_commit_count(script_dir, cmd_id)
if commit_count < 0:
    emit("CHECK", "FORWARD", "WARN", "git log failed while resolving cmd diff")
elif commit_count == 0:
    emit("CHECK", "FORWARD", "SKIP", f"no contiguous HEAD commits mention {cmd_id}")
else:
    base_ref = f"HEAD~{commit_count}"
    base_check = git(script_dir, "rev-parse", "--verify", base_ref)
    if base_check.returncode != 0:
        emit("CHECK", "FORWARD", "SKIP", f"{base_ref} not available")
    else:
        diff_proc = git(script_dir, "diff", "--name-status", "--find-renames", base_ref, "HEAD", "--")
        if diff_proc.returncode != 0:
            emit("CHECK", "FORWARD", "WARN", f"git diff failed: {diff_proc.stderr.strip()}")
        else:
            added_scripts: list[str] = []
            for raw in diff_proc.stdout.splitlines():
                if not raw.strip():
                    continue
                parts = raw.split("\t")
                if len(parts) < 2:
                    continue
                status = parts[0]
                rel_path = parts[-1].strip()
                if not status.startswith("A"):
                    continue
                if is_script_target(rel_path):
                    added_scripts.append(rel_path)

            added_scripts = sorted(dict.fromkeys(added_scripts))
            if not added_scripts:
                emit("CHECK", "FORWARD", "OK", f"no new scripts/*.sh in cmd diff (base={base_ref}, commits={commit_count})")
            else:
                unreferenced: list[str] = []
                for rel_path in added_scripts:
                    references: list[str] = []
                    for candidate_rel, candidate_abs in forward_candidates:
                        if candidate_rel == rel_path:
                            continue
                        try:
                            content = read_text(candidate_abs)
                        except OSError:
                            continue
                        if rel_path in content:
                            references.append(candidate_rel)
                    if not references:
                        unreferenced.append(rel_path)

                if unreferenced:
                    emit(
                        "CHECK",
                        "FORWARD",
                        "WARN",
                        f"{len(unreferenced)} new scripts/*.sh file(s) have no references in tracked instructions/**/*.md, CLAUDE.md, or other scripts/*.sh",
                    )
                    for rel_path in unreferenced:
                        emit("DETAIL", "FORWARD", "-", rel_path)
                else:
                    emit(
                        "CHECK",
                        "FORWARD",
                        "OK",
                        f"all {len(added_scripts)} new scripts/*.sh file(s) are referenced (base={base_ref}, commits={commit_count})",
                    )

references: dict[str, set[str]] = {}
for candidate_rel, candidate_abs in reverse_candidates:
    try:
        content = read_text(candidate_abs)
    except OSError:
        continue
    for match in PATH_RE.findall(content):
        if not is_script_target(match):
            continue
        references.setdefault(match, set()).add(candidate_rel)

missing_refs: list[tuple[str, list[str]]] = []
for rel_path, sources in sorted(references.items()):
    if os.path.isfile(os.path.join(script_dir, rel_path)):
        continue
    missing_refs.append((rel_path, sorted(sources)))

if missing_refs:
    emit("CHECK", "REVERSE", "WARN", f"{len(missing_refs)} referenced scripts/*.sh path(s) do not exist")
    for rel_path, sources in missing_refs:
        emit("DETAIL", "REVERSE", "-", f"{rel_path} <- {', '.join(sources)}")
else:
    emit("CHECK", "REVERSE", "OK", f"all {len(references)} referenced scripts/*.sh path(s) exist")
PY
}

# ─── GS忍法スクリプト変更時ベンチマーク確認（WARNのみ、run_077_*.py変更検出） ───
# cmd_1833: files_modifiedにrun_077_*.pyが含まれる場合、gs-bench-gate未実行をWARN
check_gs_bench_gate_warn() {
    level_heading "[L3]" "GS bench-gate check:"

    # dm-signalのプロジェクトパスを取得（config/projects.yaml参照）
    local dm_signal_path=""
    local config_yaml="$SCRIPT_DIR/config/projects.yaml"
    if [[ -f "$config_yaml" ]]; then
        dm_signal_path=$(awk -v target="dm-signal" '
            /^  - id:/ { cur=$3; gsub(/["'"'"']/, "", cur) }
            /^    path:/ && cur == target { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
        ' "$config_yaml")
    fi

    local found_run077=false
    local warn_count=0
    local task_files=()

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        task_files=("${MATCHING_TASK_FILES[@]}")
    else
        task_files=("$TASKS_DIR"/*.yaml)
    fi

    for task_file in "${task_files[@]}"; do
        [ -f "$task_file" ] || continue

        local ninja_name report_file
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue

        # files_modifiedフィールドからrun_077_*.pyパターンを抽出
        local run077_files
        run077_files=$(grep -oE 'run_077_[a-z_]+\.py' "$report_file" 2>/dev/null | sort -u || true)
        [ -n "$run077_files" ] || continue

        found_run077=true

        while IFS= read -r py_file; do
            local ninjutsu_name gate_json
            ninjutsu_name=$(printf '%s' "$py_file" | sed 's/run_077_\(.*\)\.py/\1/')
            gate_json=""
            if [[ -n "$dm_signal_path" ]]; then
                gate_json="${dm_signal_path}/outputs/analysis/gs_gate_after_${ninjutsu_name}.json"
            fi

            if [[ -n "$gate_json" ]] && [[ -f "$gate_json" ]]; then
                echo "  OK: ${ninja_name}: ${py_file} — gs-bench-gate実行確認 (${ninjutsu_name})"
            else
                echo "  [WARN] ${ninja_name}: ${py_file} 変更あり。gs-bench-gate未実行の可能性。"
                echo "         実行: /gs-bench-gate after --ninjutsu ${ninjutsu_name}"
                warn_count=$((warn_count + 1))
            fi
        done <<< "$run077_files"
    done

    if [[ "$found_run077" = false ]]; then
        echo "  SKIP (run_077_*.py 変更なし)"
    elif [[ "$warn_count" -eq 0 ]]; then
        echo "  OK (gs-bench-gate実行確認済み)"
    fi
}

# ─── cmd_2273: scope drift検出（WARNのみ、target_path外変更を検知） ───
check_scope_drift() {
    level_heading "[L2]" "Scope drift check (cmd_2271事故 再発防止):"
    local sd_checked=false

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        local ninja_name report_file
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ ! -f "$report_file" ]; then
            echo "  ${ninja_name}: SKIP (report not found)"
            continue
        fi

        sd_checked=true

        # target_path を task YAML から取得（単一値またはリスト両対応）
        local target_path
        if [ "${SG7_DIRECT_REPORT_SPEC:-false}" = "true" ] && [ -n "${SG7_SPEC_SCOPE:-}" ]; then
            target_path="$SG7_SPEC_SCOPE"
        else
            target_path=$(awk '
            /^[[:space:]]+target_path:/ {
                val = $0; sub(/.*target_path:[[:space:]]*/, "", val)
                gsub(/^["'"'"']+|["'"'"']+$/, "", val)
                if (val != "" && val !~ /^\[/) { print val; exit }
                in_tp = 1; next
            }
            in_tp && /^[[:space:]]+- / {
                val = $0; sub(/^[[:space:]]+- [[:space:]]*/, "", val)
                gsub(/^["'"'"']+|["'"'"']+$/, "", val); print val; next
            }
            in_tp && /^[[:space:]]+[^ -]/ { exit }
            in_tp && /^[^ ]/ { exit }
            ' "$task_file" 2>/dev/null)
        fi

        if [ -z "$target_path" ]; then
            echo "  ${ninja_name}: SKIP (target_path not set in task)"
            continue
        fi

        # files_modified[].path を抽出
        local modified_paths
        modified_paths=$(collect_report_files_modified "$report_file")

        if [ -z "$modified_paths" ]; then
            echo "  ${ninja_name}: SKIP (files_modified empty or no path entries)"
            continue
        fi

        local task_repo_dir
        task_repo_dir=$(resolve_task_repo_dir "$task_file")
        local drift_count=0 total_count=0 drift_list=""
        while IFS= read -r fp; do
            [ -z "$fp" ] && continue
            total_count=$((total_count + 1))
            local fp_cmp="$fp"
            if [[ "$fp_cmp" == /* ]]; then
                fp_cmp=$(realpath --relative-to="$task_repo_dir" "$fp_cmp" 2>/dev/null || printf '%s' "$fp_cmp")
            fi
            fp_cmp="${fp_cmp#./}"
            local matched=false
            while IFS= read -r tp; do
                [ -z "$tp" ] && continue
                local tp_cmp="$tp"
                if [[ "$tp_cmp" == /* ]]; then
                    tp_cmp=$(realpath --relative-to="$task_repo_dir" "$tp_cmp" 2>/dev/null || printf '%s' "$tp_cmp")
                fi
                tp_cmp="${tp_cmp#./}"
                tp_cmp="${tp_cmp%/}"
                if [ -z "$tp_cmp" ] || [ "$tp_cmp" = "." ] \
                    || [ "$fp_cmp" = "$tp_cmp" ] || [[ "$fp_cmp" == "$tp_cmp/"* ]]; then
                    matched=true
                    break
                fi
            done <<< "$target_path"
            if [ "$matched" = false ]; then
                drift_count=$((drift_count + 1))
                drift_list="${drift_list}    → ${fp}\n"
            fi
        done <<< "$modified_paths"

        if [ "$drift_count" -gt 0 ]; then
            echo "  [WARN] ${ninja_name}: SCOPE DRIFT: ${drift_count}/${total_count} file(s) outside target_path"
            printf '%b' "$drift_list" | head -5
        else
            echo "  ${ninja_name}: OK (全${total_count}件 target_path内)"
        fi
    done

    if [ "$sd_checked" = false ]; then
        echo "  (no reports found for this cmd)"
    fi
}

# ─── cmd_2273: レビュー陳腐化検出（WARNのみ、review_gate.done後のcommitを検知） ───
check_review_staleness() {
    level_heading "[L2]" "Review staleness check:"

    local review_done="$GATES_DIR/review_gate.done"
    if [ ! -f "$review_done" ]; then
        echo "  SKIP (review_gate.done not found)"
        return 0
    fi

    # deploy_preflight placeholderはスキップ（実レビュー前）
    if grep -q 'source: deploy_preflight' "$review_done" 2>/dev/null; then
        echo "  SKIP (review_gate.done is deploy placeholder)"
        return 0
    fi

    local review_ts
    review_ts=$(awk '/^timestamp:/ { print $2; exit }' "$review_done" 2>/dev/null)
    if [ -z "$review_ts" ]; then
        echo "  SKIP (review timestamp not found)"
        return 0
    fi

    local post_review_count=0 post_review_lines=""
    while IFS= read -r commit_hash; do
        [ -z "$commit_hash" ] && continue
        local commit_ts
        commit_ts=$(git -C "$SCRIPT_DIR" log -1 --format='%aI' "$commit_hash" 2>/dev/null || true)
        if [ -n "$commit_ts" ] && [[ "$commit_ts" > "$review_ts" ]]; then
            post_review_count=$((post_review_count + 1))
            local subj
            subj=$(git -C "$SCRIPT_DIR" log -1 --format='%s' "$commit_hash" 2>/dev/null)
            post_review_lines="${post_review_lines}    ${commit_hash:0:8}: ${subj}\n"
        fi
    done < <(get_cmd_head_hashes "$CMD_ID")

    if [ "$post_review_count" -gt 0 ]; then
        echo "  [WARN] ${post_review_count} commit(s) after review (${review_ts}) — review may be stale:"
        printf '%b' "$post_review_lines" | head -5
    else
        echo "  OK (no commits after review ${review_ts})"
    fi
}

# ─── cmd_2273: 部分完了検出（WARNのみ、binary_checks AC部分一致を通知） ───
check_partial_completion() {
    level_heading "[L2]" "Partial completion check:"
    local pc_checked=false

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        local ninja_name report_file
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ ! -f "$report_file" ]; then
            echo "  ${ninja_name}: SKIP (report not found)"
            continue
        fi

        pc_checked=true

        local pc_result
        pc_result=$(python3 - "$report_file" <<'PY'
import sys, re

try:
    with open(sys.argv[1]) as f:
        lines = f.readlines()
except Exception:
    print("skip\tcannot read report")
    sys.exit(0)

in_bc = False
bc_lines = []
for line in lines:
    if re.match(r'^binary_checks:', line):
        in_bc = True
        continue
    if in_bc and line.rstrip() and not line[0].isspace():
        break
    if in_bc:
        bc_lines.append(line.rstrip())

if not bc_lines:
    print("skip\tbinary_checks not found")
    sys.exit(0)

ac_pass, ac_fail, fail_keys = 0, 0, []
cur_key, cur_results = None, []

def flush():
    global ac_pass, ac_fail, fail_keys, cur_key, cur_results
    if cur_key is None or cur_key == 'commit':
        return
    if cur_results and all(r == 'yes' for r in cur_results):
        ac_pass += 1
    else:
        ac_fail += 1
        fail_keys.append(cur_key)

for line in bc_lines:
    km = re.match(r'^  ([A-Z][A-Z0-9_]*):\s*$', line)
    rm = re.match(r"^\s+result:\s*['\"]?(\w+)['\"]?", line)
    if km:
        flush()
        cur_key, cur_results = km.group(1), []
    elif rm and cur_key:
        cur_results.append(rm.group(1))
flush()

total = ac_pass + ac_fail
if total == 0:
    print("skip\tno AC keys in binary_checks")
elif ac_fail == 0:
    print(f"ok\t{ac_pass}/{total}")
else:
    print(f"partial\t{ac_pass}/{total}\t" + ",".join(fail_keys))
PY
)
        local pc_kind pc_nums pc_fails
        pc_kind=$(printf '%s' "$pc_result" | cut -f1)
        pc_nums=$(printf '%s' "$pc_result" | cut -f2)
        pc_fails=$(printf '%s' "$pc_result" | cut -f3-)

        case "$pc_kind" in
            partial)
                echo "  [WARN] ${ninja_name}: PARTIAL: ${pc_nums} ACs passed (未完了: ${pc_fails})"
                (BULLETIN_NOTIFY=karo bash "$SCRIPT_DIR/scripts/bulletin_write.sh" \
                    "check_partial: ${CMD_ID}/${ninja_name} PARTIAL ${pc_nums} ACs (${pc_fails})" false 2>/dev/null || true) &
                ;;
            ok)
                echo "  ${ninja_name}: OK (全AC passed: ${pc_nums})"
                ;;
            skip)
                echo "  ${ninja_name}: SKIP (${pc_nums})"
                ;;
            *)
                echo "  ${ninja_name}: SKIP (parse error)"
                ;;
        esac
    done

    if [ "$pc_checked" = false ]; then
        echo "  (no reports found for this cmd)"
    fi
}

# ─── cmd_2273: 修正暴走リスク検出（WARNのみ、files>15 or revert>=3） ───
check_wtf_likelihood() {
    level_heading "[L2]" "WTF likelihood check (修正暴走リスク):"
    local wtf_checked=false

    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        local ninja_name report_file
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ ! -f "$report_file" ]; then
            echo "  ${ninja_name}: SKIP (report not found)"
            continue
        fi

        wtf_checked=true

        # files_modified のパスエントリ数をカウント
        local file_count
        file_count=$(collect_report_files_modified "$report_file" | awk 'NF { count++ } END { print count+0 }')

        # revert commit数をカウント
        local revert_count=0
        while IFS= read -r h; do
            [ -z "$h" ] && continue
            local subj
            subj=$(git -C "$SCRIPT_DIR" log -1 --format='%s' "$h" 2>/dev/null || true)
            if printf '%s' "$subj" | grep -qiE 'revert|rollback|undo'; then
                revert_count=$((revert_count + 1))
            fi
        done < <(get_cmd_head_hashes "$CMD_ID")

        local warns=()
        if [ "${file_count:-0}" -gt 15 ]; then
            warns+=("files=${file_count} > 15")
        fi
        if [ "${revert_count:-0}" -ge 3 ]; then
            warns+=("revert=${revert_count} >= 3")
        fi

        if [ "${#warns[@]}" -gt 0 ]; then
            local warn_str=""
            for w in "${warns[@]}"; do
                [ -n "$warn_str" ] && warn_str="${warn_str}, "
                warn_str="${warn_str}${w}"
            done
            echo "  [WARN] ${ninja_name}: WTF_LIKELIHOOD: ${warn_str}"
        else
            echo "  ${ninja_name}: OK (files=${file_count:-0}, revert=${revert_count:-0})"
        fi
    done

    if [ "$wtf_checked" = false ]; then
        echo "  (no reports found for this cmd)"
    fi
}

# ─── lesson tracking追記（ベストエフォート） ───
append_lesson_tracking() {
    local cmd_id="$1"
    local gate_result="$2"
    local tracking_file="$LOG_DIR/lesson_tracking.tsv"
    local parsed ninja injected_ids referenced_ids timestamp

    parsed=$(python3 - "$TASKS_DIR" "$SCRIPT_DIR/queue/reports" "$cmd_id" <<'PY'
import glob
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

tasks_dir = sys.argv[1]
reports_dir = sys.argv[2]
cmd_id = sys.argv[3]
archive_reports_dir = os.path.join(os.path.dirname(reports_dir), "archive", "reports")

ninjas = []
injected = []
referenced = []
task_types = []
current_assignees = []

def add_unique(target, value):
    if value is None:
        return
    sval = str(value).strip()
    if not sval:
        return
    if sval not in target:
        target.append(sval)

def detect_task_type(task_id_str):
    tid = str(task_id_str)
    if tid.endswith("_exact"):
        return "exact"
    elif tid.endswith("_normal"):
        return "normal"
    elif "_scout" in tid:
        return "scout"
    elif "_impl" in tid:
        return "impl"
    elif "_review" in tid:
        return "review"
    elif "_design" in tid:
        return "design"
    return "unknown"

# Primary: extract ninja/injected/task_type from task files
for filename in sorted(os.listdir(tasks_dir)):
    if not filename.endswith(".yaml"):
        continue
    task_path = os.path.join(tasks_dir, filename)
    try:
        with open(task_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    task = data.get("task", data)
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    task_worker = task.get("worker_id") or task.get("_ac_worker_id")
    assigned_to = task.get("assigned_to")
    if isinstance(assigned_to, list):
        for ninja in assigned_to:
            add_unique(current_assignees, ninja)
            add_unique(ninjas, ninja)
    else:
        add_unique(current_assignees, assigned_to)
        add_unique(ninjas, assigned_to)
    add_unique(current_assignees, task_worker)

    task_id_val = task.get("task_id", "")
    if task_id_val:
        add_unique(task_types, detect_task_type(task_id_val))

    related_lessons = task.get("related_lessons") or []
    if isinstance(related_lessons, list):
        for lesson in related_lessons:
            if isinstance(lesson, dict):
                add_unique(injected, lesson.get("id"))
            else:
                add_unique(injected, lesson)

def parse_report(rpath):
    try:
        with open(rpath, encoding="utf-8") as rf:
            rdata = yaml.safe_load(rf) or {}
        return rdata if isinstance(rdata, dict) else {}
    except Exception:
        return {}

def fallback_report_allowed(rpath, report_ninja):
    rdata = parse_report(rpath)
    report_parent = str(rdata.get("parent_cmd", "")).strip()
    report_worker = str(rdata.get("worker_id", "")).strip()

    if report_parent:
        return report_parent == cmd_id, rdata

    if current_assignees:
        return (report_ninja in current_assignees or report_worker in current_assignees), rdata

    # No current assignee/worker_id in task YAML: avoid stale glob matches by
    # requiring the report's own parent_cmd to match the cmd being tracked.
    return False, rdata

# Fallback: when task files are already idle/reassigned, extract from report filenames
if not ninjas:
    for search_dir in [reports_dir, archive_reports_dir]:
        if not os.path.isdir(search_dir):
            continue
        for rpath in sorted(glob.glob(os.path.join(search_dir, f"*_report_{cmd_id}*.yaml"))):
            bname = os.path.basename(rpath)
            if bname.endswith(".lock"):
                continue
            idx = bname.find(f"_report_{cmd_id}")
            if idx <= 0:
                continue
            report_ninja = bname[:idx]
            allowed, rdata = fallback_report_allowed(rpath, report_ninja)
            if not allowed:
                continue
            add_unique(ninjas, report_ninja)
            if not task_types:
                rtid = rdata.get("task_id", "")
                if rtid:
                    add_unique(task_types, detect_task_type(rtid))

def find_report(ninja_name):
    """Find report file in reports_dir or archive, return path or None."""
    for candidate in [
        os.path.join(reports_dir, f"{ninja_name}_report_{cmd_id}.yaml"),
        os.path.join(reports_dir, f"{ninja_name}_report.yaml"),
    ]:
        if os.path.exists(candidate):
            return candidate
    if os.path.isdir(archive_reports_dir):
        matches = sorted(glob.glob(
            os.path.join(archive_reports_dir, f"{ninja_name}_report_{cmd_id}*.yaml")))
        for m in matches:
            if not m.endswith(".lock"):
                return m
    return None

for ninja in ninjas:
    report_path = find_report(ninja)
    if not report_path:
        continue
    try:
        with open(report_path, encoding="utf-8") as f:
            report = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(report, dict):
        continue
    lessons_useful = report.get("lessons_useful")
    if lessons_useful is None:
        # Backward compatibility for legacy report field.
        lessons_useful = report.get("lesson_referenced")
    if isinstance(lessons_useful, list):
        for item in lessons_useful:
            if isinstance(item, dict):
                add_unique(referenced, item.get("id"))
            else:
                add_unique(referenced, item)

print(",".join(ninjas) if ninjas else "none")
print(",".join(injected) if injected else "none")
print(",".join(referenced) if referenced else "none")
print(",".join(task_types) if task_types else "unknown")
PY
    ) || return 1

    ninja=$(printf '%s\n' "$parsed" | sed -n '1p')
    injected_ids=$(printf '%s\n' "$parsed" | sed -n '2p')
    referenced_ids=$(printf '%s\n' "$parsed" | sed -n '3p')
    task_type=$(printf '%s\n' "$parsed" | sed -n '4p')

    [ -z "$ninja" ] && ninja="none"
    [ -z "$injected_ids" ] && injected_ids="none"
    [ -z "$referenced_ids" ] && referenced_ids="none"
    [ -z "$task_type" ] && task_type="unknown"
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    (
        flock -w 10 200 || exit 1
        if [ ! -f "$tracking_file" ]; then
            printf 'timestamp\tcmd_id\tninja\tgate_result\tinjected_ids\treferenced_ids\ttask_type\n' > "$tracking_file"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$timestamp" "$cmd_id" "$ninja" "$gate_result" "$injected_ids" "$referenced_ids" "$task_type" >> "$tracking_file"
    ) 200>"$(lock_path "$tracking_file")" || {
        echo "LESSON_TRACKING: WARN lock timeout (${tracking_file})"
        return 0
    }
    echo "LESSON_TRACKING: ${cmd_id} (${gate_result}) appended"
}

# ─── lesson impact更新（ベストエフォート） ───
update_lesson_impact_tsv() {
    local cmd_id="$1"
    local gate_result="$2"
    local impact_file="$LOG_DIR/lesson_impact.tsv"

    if [ ! -f "$impact_file" ]; then
        echo "LESSON_IMPACT: SKIP (file not found: ${impact_file})"
        return 0
    fi

    (
        flock -w 10 200 || exit 1
        IMPACT_FILE="$impact_file" TASKS_DIR="$TASKS_DIR" REPORTS_DIR="$SCRIPT_DIR/queue/reports" CMD_ID="$cmd_id" GATE_RESULT="$gate_result" python3 - <<'PY'
import csv
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

impact_file = os.environ["IMPACT_FILE"]
tasks_dir = os.environ["TASKS_DIR"]
reports_dir = os.environ["REPORTS_DIR"]
cmd_id = os.environ["CMD_ID"]
gate_result = os.environ["GATE_RESULT"]


def parse_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def add_unique(target, value):
    s = str(value).strip()
    if s and s not in target:
        target.append(s)


def resolve_report_file(ninja_name, task):
    explicit = str(task.get("report_filename", "")).strip().strip("'\"")
    if explicit:
        explicit_path = os.path.join(reports_dir, explicit)
        if os.path.exists(explicit_path):
            return explicit_path

    new_fmt = os.path.join(reports_dir, f"{ninja_name}_report_{cmd_id}.yaml")
    if os.path.exists(new_fmt):
        return new_fmt

    # 分割cmd形式: ninja_report_cmd_XXXX_ninja.yaml — 分割cmdGATE滞留対処(cmd_3449)
    split_fmt = os.path.join(reports_dir, f"{ninja_name}_report_{cmd_id}_{ninja_name}.yaml")
    if os.path.exists(split_fmt):
        return split_fmt

    old_fmt = os.path.join(reports_dir, f"{ninja_name}_report.yaml")
    if os.path.exists(old_fmt):
        old_data = parse_yaml(old_fmt)
        if str(old_data.get("parent_cmd", "")).strip() == cmd_id:
            return old_fmt
    return None


ninjas = []
ninja_tasks = {}
tracked_row_ids = []
referenced_ids = []
referenced_by_row_id = {}
usefulness_by_row_id = {}
assigned_by_row_id = {}

try:
    task_files = sorted(
        os.path.join(tasks_dir, name)
        for name in os.listdir(tasks_dir)
        if name.endswith(".yaml")
    )
except Exception:
    task_files = []

for task_path in task_files:
    data = parse_yaml(task_path)
    task = data.get("task", data)
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    task_row_ids = []
    for key in ("task_id", "subtask_id", "parent_cmd"):
        add_unique(task_row_ids, task.get(key))

    for row_id in task_row_ids:
        add_unique(tracked_row_ids, row_id)
        referenced_by_row_id.setdefault(row_id, [])
        values = task.get("assigned_lesson_ids")
        if isinstance(values, list) and values:
            assigned_by_row_id[row_id] = {
                str(value).strip() for value in values if str(value).strip()
            }

    assigned_to = task.get("assigned_to")
    if isinstance(assigned_to, list):
        for ninja in assigned_to:
            add_unique(ninjas, ninja)
            ninja_tasks[str(ninja).strip()] = task
    elif assigned_to:
        add_unique(ninjas, assigned_to)
        ninja_tasks[str(assigned_to).strip()] = task
    else:
        fallback_ninja = os.path.splitext(os.path.basename(task_path))[0]
        add_unique(ninjas, fallback_ninja)
        ninja_tasks[fallback_ninja] = task

for ninja in ninjas:
    report_file = resolve_report_file(ninja, ninja_tasks.get(ninja, {}))
    if not report_file:
        continue
    report = parse_yaml(report_file)
    report_refs = []
    report_usefulness = {}
    lessons_useful = report.get("lessons_useful")
    if lessons_useful is None:
        # Backward compatibility for legacy report field.
        lessons_useful = report.get("lesson_referenced")
    if isinstance(lessons_useful, list):
        for item in lessons_useful:
            if isinstance(item, dict):
                add_unique(report_refs, item.get("id"))
                lesson_id = str(item.get("id", "")).strip()
                useful = item.get("useful")
                if lesson_id and isinstance(useful, bool):
                    report_usefulness[lesson_id] = "USEFUL" if useful else "NOT_USEFUL"
            else:
                add_unique(report_refs, item)

    for ref_id in report_refs:
        add_unique(referenced_ids, ref_id)

    task = ninja_tasks.get(ninja, {})
    task_row_ids = []
    for key in ("task_id", "subtask_id", "parent_cmd"):
        add_unique(task_row_ids, task.get(key))
    for row_id in task_row_ids:
        row_refs = referenced_by_row_id.setdefault(row_id, [])
        for ref_id in report_refs:
            strict_ids = assigned_by_row_id.get(row_id)
            if strict_ids is None or ref_id in strict_ids:
                add_unique(row_refs, ref_id)
        row_usefulness = usefulness_by_row_id.setdefault(row_id, {})
        for lesson_id, useful_result in report_usefulness.items():
            strict_ids = assigned_by_row_id.get(row_id)
            if strict_ids is None or lesson_id in strict_ids:
                row_usefulness[lesson_id] = useful_result

if not tracked_row_ids:
    tracked_row_ids.append(cmd_id)
    referenced_by_row_id.setdefault(cmd_id, [])

rows = []
updated = 0
fieldnames = None
required = {"cmd_id", "lesson_id", "action", "result", "referenced"}

with open(impact_file, "r", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    fieldnames = reader.fieldnames or []
    if not required.issubset(set(fieldnames)):
        print("LESSON_IMPACT: SKIP (required columns missing)")
        raise SystemExit(0)

    for row in reader:
        # Strip CR from all field values and skip empty rows
        for k in list(row.keys()):
            v = row[k]
            if isinstance(v, str):
                row[k] = v.strip("\r")
            elif v is None:
                row[k] = ""
        row_cmd_id = (row.get("cmd_id") or "").strip()
        row_lesson_id = (row.get("lesson_id") or "").strip()
        # Skip empty rows (no cmd_id and no lesson_id)
        if not row_cmd_id and not row_lesson_id:
            continue
        matched = row_cmd_id in tracked_row_ids
        if not matched:
            for tid in tracked_row_ids:
                if row_cmd_id.startswith(tid + "_"):
                    matched = True
                    break
        if matched and row.get("result") == "pending":
            if row.get("action") != "withheld":
                row_refs = referenced_by_row_id.get(row_cmd_id, referenced_ids)
                lesson_id = row.get("lesson_id")
                row_usefulness = usefulness_by_row_id.get(row_cmd_id, usefulness_by_row_id.get("__all__", {}))
                strict_ids = assigned_by_row_id.get(row_cmd_id)
                if strict_ids is not None and lesson_id not in row_usefulness:
                    # An explicit assignment set forbids guessing.  Unassigned
                    # or missing evaluations remain pending rather than being
                    # invented as NOT_USEFUL.
                    rows.append({field: row.get(field, "") for field in fieldnames})
                    continue
                row["referenced"] = "yes" if lesson_id in row_refs else "no"
                if lesson_id in row_usefulness:
                    row["result"] = row_usefulness[lesson_id]
                else:
                    row["result"] = "NOT_USEFUL"
            else:
                row["result"] = gate_result
            updated += 1
        rows.append({field: row.get(field, "") for field in fieldnames})

if updated == 0:
    print(f"LESSON_IMPACT: {cmd_id} no pending rows to update")
    raise SystemExit(0)

tmp_path = None
tmp_dir = os.path.dirname(impact_file) or "."
try:
    tmp_fd, tmp_path = tempfile.mkstemp(dir=tmp_dir, prefix="lesson_impact.", suffix=".tmp")
    with os.fdopen(tmp_fd, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp_path, impact_file)
except Exception:
    if tmp_path and os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f"LESSON_IMPACT: {cmd_id} updated rows={updated} referenced_ids={len(referenced_ids)}")
PY
    ) 200>"$(lock_path "$impact_file")" || {
        echo "LESSON_IMPACT: WARN lock timeout (${impact_file})"
        return 0
    }
}

record_lesson_feedback_for_cmd() {
    local feedback_script="$SCRIPT_DIR/scripts/record_lesson_feedback.sh"
    if [ ! -f "$feedback_script" ]; then
        echo "  SKIP (record_lesson_feedback.sh not found)"
        return 0
    fi

    local recorded=0
    local seen_reports=""
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            continue
        fi
        local ninja_name report_yaml
        ninja_name=$(basename "$task_file" .yaml)
        report_yaml=$(resolve_report_file "$ninja_name")
        if [ -f "$report_yaml" ]; then
            case "$seen_reports" in *"|$report_yaml|"*) continue ;; esac
            seen_reports="${seen_reports}|${report_yaml}|"
            if bash "$feedback_script" "$report_yaml" 2>&1; then
                echo "  feedback: OK ($report_yaml)"
            else
                echo "  [INFO] feedback: WARN ($report_yaml, non-blocking)"
            fi
            recorded=$((recorded + 1))
        fi
    done

    if [ "$recorded" -eq 0 ]; then
        for report_yaml in "$SCRIPT_DIR"/queue/reports/*_report_"${CMD_ID}"*.yaml; do
            if [ -f "$report_yaml" ]; then
                if bash "$feedback_script" "$report_yaml" 2>&1; then
                    echo "  feedback: OK ($report_yaml)"
                else
                    echo "  [INFO] feedback: WARN ($report_yaml, non-blocking)"
                fi
                recorded=$((recorded + 1))
            fi
        done
    fi

    if [ "$recorded" -eq 0 ]; then
        echo "  SKIP (no report YAML found for ${CMD_ID})"
    fi
}

update_lesson_scores_batch() {
    local project_id="$1"
    local score_entries="$2"

    [ -n "$project_id" ] || return 1
    [ -n "$score_entries" ] || {
        echo "  Updated: 0 lesson(s)"
        return 0
    }

    local archive_file="$SCRIPT_DIR/projects/${project_id}/lessons_archive.yaml"
    local fallback_file="$SCRIPT_DIR/projects/${project_id}/lessons.yaml"
    local cache_file
    local result

    if [ -f "$archive_file" ]; then
        cache_file="$archive_file"
    else
        cache_file="$fallback_file"
    fi

    if [ ! -f "$cache_file" ]; then
        echo "  [INFO] lesson score update skipped: ${cache_file} not found"
        return 0
    fi

    result=$(
        (
            flock -w 10 200 || { echo "WARN: lock timeout"; exit 0; }
            SCORE_ENTRIES="$score_entries" CACHE_FILE="$cache_file" python3 - <<'PY'
import os
import tempfile
from collections import Counter
from datetime import datetime

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

cache_file = os.environ["CACHE_FILE"]
entries_raw = os.environ.get("SCORE_ENTRIES", "")

counts = Counter()
sources = {}
for raw in entries_raw.splitlines():
    parts = raw.split("\t")
    if len(parts) < 2:
        continue
    source, lesson_id = parts[0].strip(), parts[1].strip()
    if not lesson_id:
        continue
    counts[lesson_id] += 1
    if lesson_id not in sources or source == "explicit":
        sources[lesson_id] = source or "explicit"

if not counts:
    print("Updated: 0 lesson(s)")
    raise SystemExit(0)

with open(cache_file, encoding="utf-8") as f:
    content = f.read()

data = yaml.safe_load(content) or {}
lessons = data.get("lessons")
if not isinstance(lessons, list):
    print(f"WARN: no lessons found in {cache_file}")
    raise SystemExit(0)

now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
found = set()
updated_total = 0
updates = {}
for lesson in lessons:
    if not isinstance(lesson, dict):
        continue
    lesson_id = str(lesson.get("id", "")).strip()
    increment = counts.get(lesson_id, 0)
    if increment <= 0:
        continue
    current = lesson.get("helpful_count", 0) or 0
    try:
        current = int(current)
    except Exception:
        current = 0
    lesson["helpful_count"] = current + increment
    lesson["last_referenced"] = now
    found.add(lesson_id)
    updated_total += increment
    updates[lesson_id] = current + increment
    suffix = " (auto-detected in report text)" if sources.get(lesson_id) == "auto" else ""
    print(f"{lesson_id}: helpful +{increment}{suffix}")

missing = [lesson_id for lesson_id in counts if lesson_id not in found]
for lesson_id in missing:
    print(f"[INFO] {lesson_id}: score update failed (lesson not found, non-blocking)")

if updates:
    lines = content.splitlines(keepends=True)
    out = []
    current_id = None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- id:"):
            current_id = stripped.split(":", 1)[1].strip().strip("'\"")
            out.append(line)
            continue
        if current_id in updates and stripped.startswith("helpful_count:"):
            indent = line[: len(line) - len(line.lstrip())]
            newline = "\n" if line.endswith("\n") else ""
            out.append(f"{indent}helpful_count: {updates[current_id]}{newline}")
            continue
        if current_id in updates and stripped.startswith("last_referenced:"):
            indent = line[: len(line) - len(line.lstrip())]
            newline = "\n" if line.endswith("\n") else ""
            out.append(f"{indent}last_referenced: '{now}'{newline}")
            continue
        out.append(line)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(cache_file), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.writelines(out)
        os.replace(tmp_path, cache_file)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

print(f"Updated: {updated_total} lesson(s)")
PY
        ) 200>"$(lock_path "$cache_file")"
    )

    while IFS= read -r line; do
        [ -n "$line" ] && echo "  $line"
    done <<< "$result"
}

# ─── BLOCK理由収集 ───
record_block_reason() {
    local reason="$1"
    if [ -n "$reason" ]; then
        BLOCK_REASONS+=("$reason")
    fi
}

# ─── rg解決ヘルパー(cmd_karo_hotfix_review_trigger_gate_datetime_202607111233 AC3) ───
# nohup経由の非対話bashサブプロセスではPATHにrgが載らないCLI環境がある(rg実体は
# $HOME/.local/bin/rgに存在するがPATH外)。command not foundを2>/dev/null+||trueで
# 握り潰し常に0件扱いになるsilent false-negative経路を防ぐため、呼出元でrg解決を
# 試み、失敗時はgrepへ明示フォールバックする(three_layer_preflight.shのresolve_rg
# と同じ考え方。専用SSOTスクリプト化はしない)。
resolve_gate_rg() {
    local rg_cmd
    rg_cmd="$(command -v rg 2>/dev/null || true)"
    if [ -n "$rg_cmd" ]; then
        printf '%s\n' "$rg_cmd"
        return 0
    fi
    if [ -x "$HOME/.local/bin/rg" ]; then
        printf '%s\n' "$HOME/.local/bin/rg"
        return 0
    fi
    return 1
}

level_heading() {
    local level="$1"
    local title="$2"
    echo ""
    echo "${level} ${title}"
}

binary_checks_warn_reason() {
    local report_file="$1"
    local ninja_name="$2"
    local pass_ninjas="$3"
    local test_triage

    test_triage=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "test_triage" "" 2>/dev/null || true)
    if [ "$test_triage" = "pre_existing" ]; then
        echo "test_triage=pre_existingのためWARN降格"
        return 0
    fi

    # GP-221: 二重配備で他忍者がverdict=PASSなら、この忍者のbc_failはWARN止まり
    if [ -n "$pass_ninjas" ] && [[ "$pass_ninjas" != *"$ninja_name "* ]]; then
        echo "他忍者PASS済みのためBLOCK降格"
        return 0
    fi

    return 1
}

report_has_commit_binary_check_yes() {
    local report_file="$1"

    REPORT_FILE="$report_file" python3 - <<'PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path = os.environ["REPORT_FILE"]
try:
    with open(path, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    sys.exit(1)

checks = (report.get("binary_checks") or {}).get("commit", [])
if isinstance(checks, dict):
    checks = [checks]
if not isinstance(checks, list):
    sys.exit(1)

for item in checks:
    if not isinstance(item, dict):
        continue
    result = item.get("result", "")
    if result is True or str(result).strip().lower() == "yes":
        sys.exit(0)
sys.exit(1)
PY
}

collect_report_files_modified() {
    local report_file="$1"

    REPORT_FILE="$report_file" python3 - <<'PY'
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path = os.environ["REPORT_FILE"]
try:
    with open(path, encoding="utf-8") as f:
        report = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(0)

files = report.get("files_modified") or []
if isinstance(files, str):
    files = [files]
if not isinstance(files, list):
    raise SystemExit(0)

for item in files:
    if isinstance(item, dict):
        value = item.get("path") or item.get("file") or item.get("name")
    else:
        value = item
    value = str(value or "").strip()
    if value and value not in ("no-code-change", "no_code_change"):
        print(value)
PY
}

# cmd_karo_hotfix_gate_report_discovery_after_redeploy: 同一忍者への次task配備でtask YAMLが
# 上書きされ(parent_cmdが変わり)MATCHING_TASK_FILESの対象外になっても、report自身のparent_cmd/
# task_idの厳密一致でcmd Aのreportを発見できるようにする共通ヘルパー(cmd_3844型の偽BLOCK根治)。
discover_reports_for_cmd() {
    local cmd_id="${1:-$CMD_ID}"
    local reports_dir="$SCRIPT_DIR/queue/reports"

    REPORTS_DIR="$reports_dir" CMD_ID="$cmd_id" python3 - <<'PY'
import glob
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

reports_dir = os.environ["REPORTS_DIR"]
cmd_id = os.environ["CMD_ID"]

for path in sorted(glob.glob(os.path.join(reports_dir, "*.yaml"))):
    try:
        with open(path, encoding="utf-8") as f:
            report = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(report, dict):
        continue
    parent_cmd = str(report.get("parent_cmd") or "").strip()
    task_id = str(report.get("task_id") or "").strip()
    if parent_cmd == cmd_id or task_id == cmd_id:
        print(path)
PY
}

collect_parent_cmd_report_files_modified() {
    local cmd_id="${1:-$CMD_ID}"
    local report_path

    while IFS= read -r report_path; do
        [ -n "$report_path" ] || continue
        collect_report_files_modified "$report_path"
    done < <(discover_reports_for_cmd "$cmd_id") | awk 'NF && !seen[$0]++'
}

# Close only alerts whose concrete gate/check implementation appears in the
# completed command's report files_modified.  The helper owns flock + atomic
# replace so concurrent alert recording cannot be lost.
close_resolved_gate_alerts() {
    local cmd_id="${1:-$CMD_ID}"
    local alerts_file="${GATE_ALERTS_FILE:-$LOG_DIR/gate_alerts.yaml}"
    local helper="$SCRIPT_DIR/scripts/lib/close_gate_alerts.py"
    local -a changed_files=()

    [ -f "$helper" ] || return 0
    mapfile -t changed_files < <(collect_parent_cmd_report_files_modified "$cmd_id")
    [ "${#changed_files[@]}" -gt 0 ] || return 0

    python3 "$helper" --alerts "$alerts_file" --cmd-id "$cmd_id" -- "${changed_files[@]}"
}

has_parent_cmd_report() {
    local cmd_id="${1:-$CMD_ID}"
    [ -n "$(discover_reports_for_cmd "$cmd_id")" ]
}

collect_git_show_w_files() {
    local git_ref="${1:-HEAD}"

    git -C "$SCRIPT_DIR" show -w --name-only --format= "$git_ref" 2>/dev/null \
        | sed '/^[[:space:]]*$/d' \
        | sort -u
}

collect_report_commit_hash() {
    local report_file="$1"

    REPORT_FILE="$report_file" python3 - <<'PY'
import os
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

try:
    with open(os.environ["REPORT_FILE"], encoding="utf-8") as handle:
        report = yaml.safe_load(handle) or {}
except Exception:
    raise SystemExit(0)

value = str(report.get("commit_hash") or "").strip()
if re.fullmatch(r"[0-9a-fA-F]{40}", value):
    print(value.lower())
PY
}

collect_cmd_phase_git_files() {
    local anchor_hash="$1"
    local cmd_id="${2:-$CMD_ID}"
    local hash subject
    local -A seen_hashes=()

    # The report commit is authoritative even when its subject does not carry
    # the cmd id.  Older phase commits are included only on the anchor's
    # ancestry and only with an exact "${cmd_id}:" subject prefix.  This keeps
    # unrelated HEAD/newer commits and cmd_99/cmd_999 prefix collisions out.
    while IFS=$'\t' read -r hash subject; do
        [ -n "$hash" ] || continue
        if [ "$hash" = "$anchor_hash" ] || [[ "$subject" == "${cmd_id}:"* ]]; then
            seen_hashes["$hash"]=1
        fi
    done < <(git -C "$SCRIPT_DIR" log --format=$'%H\t%s' "$anchor_hash" 2>/dev/null || true)

    for hash in "${!seen_hashes[@]}"; do
        collect_git_show_w_files "$hash"
    done | awk 'NF && !seen[$0]++' | sort -u
}

check_self_grade_commit_file_coverage() {
    local checked=false
    local warned=false
    local ninja_name report_file report_files commit_files missing commit_hash

    while IFS= read -r report_file; do
        [ -f "$report_file" ] || continue
        ninja_name=$(REPORT_FILE="$report_file" python3 - <<'PY'
import os, yaml
try:
    data = yaml.safe_load(open(os.environ["REPORT_FILE"], encoding="utf-8")) or {}
except Exception:
    data = {}
print(str(data.get("worker_id") or os.path.basename(os.environ["REPORT_FILE"]).split("_report_", 1)[0]))
PY
)
        checked=true

        if ! report_has_commit_binary_check_yes "$report_file"; then
            echo "  ${ninja_name}: SKIP (binary_checks.commit is not yes)"
            continue
        fi

        report_files=$(collect_report_files_modified "$report_file" | sort -u)
        if [ -z "$report_files" ]; then
            echo "  [WARN] ${ninja_name}: SELF_GRADE_COMMIT_FILES report files_modified empty while binary_checks.commit=yes"
            warned=true
            continue
        fi

        commit_hash=$(collect_report_commit_hash "$report_file")
        if [ -z "$commit_hash" ] || ! git -C "$SCRIPT_DIR" cat-file -e "${commit_hash}^{commit}" 2>/dev/null; then
            echo "  [WARN] ${ninja_name}: SELF_GRADE_COMMIT_FILES valid report commit_hash not found"
            warned=true
            continue
        fi

        if ! commit_files=$(collect_cmd_phase_git_files "$commit_hash" "$CMD_ID"); then
            echo "  [WARN] ${ninja_name}: SELF_GRADE_COMMIT_FILES git show -w failed (report commit ${commit_hash})"
            warned=true
            continue
        fi

        missing=$(comm -23 <(printf '%s\n' "$report_files") <(printf '%s\n' "$commit_files"))
        if [ -n "$missing" ]; then
            echo "  [WARN] ${ninja_name}: SELF_GRADE_COMMIT_FILES files_modified not in report commit phase union (${commit_hash}):"
            printf '%s\n' "$missing" | sed 's/^/    - /'
            warned=true
        else
            echo "  ${ninja_name}: OK (files_modified covered by report commit phase union ${commit_hash})"
        fi
    done < <(discover_reports_for_cmd "$CMD_ID")

    if [ "$checked" = false ]; then
        echo "  (no reports found for this cmd)"
    elif [ "$warned" = false ]; then
        echo "  OK (self-grade commit file coverage)"
    fi
}

detect_task_role() {
    local task_file="$1"

    local tokens="" val
    for key in task_type type task_id subtask_id; do
        val=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "$key" "")
        [ -n "$val" ] && tokens="$tokens $(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    done

    case "$tokens" in
        *review*) echo "review" ;;
        *implement*|*impl*) echo "implement" ;;
        *recon*|*scout*) echo "recon" ;;
        *) echo "unknown" ;;
    esac
}

# Helper: check lesson_candidate.found=true in report YAML (#3,#4共通関数 cmd_1387)
_check_lc_found() {
    local rfile="$1"
    if awk '/^lesson_candidate:/{p=1;next} p&&/found: true/{found=1;exit} /^[^ ]/{if(p)exit 1} END{if(!found)exit 1}' "$rfile" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Parse lesson_candidate with the same YAML boolean spellings accepted by
# gate_report_format: bare, single-quoted, or double-quoted true/false.
lesson_candidate_status() {
    local report_file="$1"
    awk '
        /^lesson_candidate:/ {
            # inline list check (legacy_list: "lesson_candidate: [...]" or next line is "- ")
            val = $0; sub(/.*lesson_candidate:[[:space:]]*/, "", val)
            if (val == "null" || val == "~" || val == "") { in_lc = 1 }
            else if (val ~ /^\[/) { result = "legacy_list" }
            else { result = "malformed" }
            next
        }
        in_lc && /^[a-zA-Z]/ { in_lc = 0 }
        # list形式の検出 (legacy_list)
        in_lc && /^[[:space:]]*- / && !has_found_key { result = "legacy_list"; in_lc = 0 }
        in_lc && /^[[:space:]]+found:/ {
            has_found_key = 1
            v = $0; sub(/.*found:[[:space:]]*/, "", v)
            gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", v)
            found_val = v
        }
        in_lc && /^[[:space:]]+no_lesson_reason:/ {
            v = $0; sub(/.*no_lesson_reason:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            nlr = v
        }
        in_lc && /^[[:space:]]+title:/ {
            v = $0; sub(/.*title:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            lc_title = v
        }
        in_lc && /^[[:space:]]+detail:/ {
            v = $0; sub(/.*detail:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            lc_detail = v
        }
        END {
            if (result != "") { print result; exit }
            if (!in_lc && !has_found_key) { print "missing"; exit }
            if (!has_found_key) { print "found_missing"; exit }
            if (found_val == "false") {
                if (nlr == "") print "ok_false_no_reason"
                else print "ok_false"
                exit
            }
            if (found_val == "true") {
                miss = ""
                if (lc_title == "") { miss = "title" }
                if (lc_detail == "") { if (miss != "") miss = miss ","; miss = miss "detail" }
                if (miss != "") print "found_true_empty:" miss
                else print "found_true"
                exit
            }
            print "malformed"
        }
    ' "$report_file" 2>/dev/null
}

check_how_it_works_status() {
    local report_file="$1"

    if [ ! -f "$report_file" ]; then
        echo "error"
        return
    fi

    if ! grep -q 'how_it_works' "$report_file" 2>/dev/null; then
        echo "missing"
        return
    fi

    local value
    value=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "how_it_works" "")
    if [ -z "$value" ]; then
        echo "empty"
    else
        echo "ok"
    fi
}

cmd_task_matches() {
    local task_file="$1"
    local cmd_id="${2:-$CMD_ID}"
    task_file_matches_cmd "$task_file" "$cmd_id"
}

evaluate_review_report_status() {
    local report_file="$1"
    local _rv_verdict _rv_verdict_status _rv_gate_status _rv_sg_pass _rv_worker_id

    _rv_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "")
    _rv_verdict_status="ng"
    [ "$_rv_verdict" = "PASS" ] || [ "$_rv_verdict" = "FAIL" ] || [ "$_rv_verdict" = "PASS_NO_IMPROVEMENT" ] && _rv_verdict_status="ok"

    _rv_gate_status="ng"
    if grep -q 'self_gate_check:' "$report_file" 2>/dev/null; then
        _rv_sg_pass=$(awk '
            /self_gate_check:/ { sec=1; next }
            sec && /^[^ ]/ { exit }
            sec && /lesson_ref:.*PASS/ { c++ }
            sec && /lesson_candidate:.*PASS/ { c++ }
            sec && /status_valid:.*PASS/ { c++ }
            sec && /purpose_fit:.*PASS/ { c++ }
            END { print c+0 }
        ' "$report_file" 2>/dev/null)
        [ "${_rv_sg_pass:-0}" -eq 4 ] && _rv_gate_status="ok"
    fi

    _rv_worker_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "worker_id" "")
    printf '%s\t%s\t%s\n' "$_rv_verdict_status" "$_rv_gate_status" "$_rv_worker_id"
}

find_overlapping_workers() {
    local implementer_ids="$1"
    local reviewer_ids="$2"

    comm -12 \
        <(printf '%s\n' "$implementer_ids" | tr '|' '\n' | sed '/^$/d' | sort -u) \
        <(printf '%s\n' "$reviewer_ids" | tr '|' '\n' | sed '/^$/d' | sort -u) \
        | paste -sd, -
}

run_review_quality_check() {
    local review_task_found=false
    local implementer_ids="|"
    local reviewer_ids="|"
    local task_file task_role ninja_name report_file impl_worker_id review_status
    local verdict_status self_gate_status review_worker_id overlapping_workers
    local task_files=()

    level_heading "[L2]" "Review quality check:"

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1 && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        task_files=("${MATCHING_TASK_FILES[@]}")
    else
        task_files=("$TASKS_DIR"/*.yaml)
    fi

    for task_file in "${task_files[@]}"; do
        [ -f "$task_file" ] || continue

        task_role=$(detect_task_role "$task_file")
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        case "$task_role" in
            implement)
                if [ -f "$report_file" ]; then
                    impl_worker_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "worker_id" "")
                    if [ -n "$impl_worker_id" ] && [[ "$implementer_ids" != *"|$impl_worker_id|"* ]]; then
                        implementer_ids="${implementer_ids}${impl_worker_id}|"
                    fi
                fi
                ;;
            review)
                review_task_found=true

                if [ ! -f "$report_file" ]; then
                    echo "  ${ninja_name}: SKIP (review report not found)"
                    continue
                fi

                review_status=$(evaluate_review_report_status "$report_file")
                verdict_status=$(printf '%s\n' "$review_status" | cut -f1)
                self_gate_status=$(printf '%s\n' "$review_status" | cut -f2)
                review_worker_id=$(printf '%s\n' "$review_status" | cut -f3)

                if [ "$verdict_status" = "ok" ]; then
                    echo "  ${ninja_name}: OK (verdict=PASS/FAIL/PASS_NO_IMPROVEMENT)"
                else
                    echo "  [CRITICAL] ${ninja_name}: NG ← verdict欠落または不正値（PASS/FAIL/PASS_NO_IMPROVEMENT必須）"
                    record_block_reason "review report missing verdict field"
                    ALL_CLEAR=false
                fi

                if [ "$self_gate_status" = "ok" ]; then
                    echo "  ${ninja_name}: OK (self_gate_check all PASS)"
                else
                    echo "  [CRITICAL] ${ninja_name}: NG ← self_gate_check 4項目が不足またはPASS以外"
                    record_block_reason "review report self_gate_check incomplete or not all PASS"
                    ALL_CLEAR=false
                fi

                if [ -n "$review_worker_id" ] && [[ "$reviewer_ids" != *"|$review_worker_id|"* ]]; then
                    reviewer_ids="${reviewer_ids}${review_worker_id}|"
                fi
                ;;
        esac
    done

    if [ "$review_task_found" = false ]; then
        echo "  SKIP (no review reports for this cmd)"
    elif [ "$implementer_ids" = "|" ]; then
        echo "  reviewer/implementer split: SKIP (no implementer reports)"
    elif [ "$reviewer_ids" = "|" ]; then
        echo "  reviewer/implementer split: SKIP (no review worker_id)"
    else
        overlapping_workers=$(find_overlapping_workers "$implementer_ids" "$reviewer_ids")
        if [ -n "$overlapping_workers" ]; then
            echo "  [CRITICAL] NG ← reviewer and implementer overlap: ${overlapping_workers}"
            record_block_reason "reviewer is same as implementer"
            ALL_CLEAR=false
        else
            echo "  reviewer/implementer split: OK"
        fi
    fi
}

run_todo_fixme_residual_check() {
    local cmd_id="${1:-$CMD_ID}"
    local cmd_num todo_hits todo_count rg_cmd

    level_heading "[L2]" "TODO/FIXME residual check:"

    cmd_num="${cmd_id#cmd_}"
    if rg_cmd="$(resolve_gate_rg)"; then
        # rg 1-pass scan: grep -rEn より /mnt/c WSL2 上で速い
        todo_hits=$("$rg_cmd" -n -S "(TODO|FIXME).*(${cmd_id}|subtask_${cmd_num})" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/lib" 2>/dev/null | sort -u || true)
    else
        # rg不在時のfallback。パターンは大文字のみなのでsmart-case(rg -S)と
        # 同じ挙動になり、大文字小文字区別ありのgrep -Eで意味が一致する。
        todo_hits=$(grep -rEn "(TODO|FIXME).*(${cmd_id}|subtask_${cmd_num})" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/lib" 2>/dev/null | sort -u || true)
    fi
    todo_count=$(printf '%s\n' "$todo_hits" | awk 'NF{c++} END{print c+0}')

    if [ "$todo_count" -gt 0 ]; then
        echo "  [CRITICAL] NG ← ${todo_count}件のTODO/FIXMEが残存:"
        printf '%s\n' "$todo_hits" | head -10 | while IFS= read -r line; do
            echo "    ${line}"
        done
        if [ "$todo_count" -gt 10 ]; then
            echo "    ... (${todo_count}件中10件表示)"
        fi
        record_block_reason "todo/fixme residual found"
        ALL_CLEAR=false
    else
        echo "  TODO check: OK (0 remaining)"
    fi
}

# ─── context_update freshness check (cmd_543 AC2) ───
# cmdにcontext_updateが定義されている場合のみ、context/* の last_updated を検証。
# last_updated(YYYY-MM-DD) < cmd timestamp/delegated_at の日付 なら BLOCK。
check_context_update() {
    local cmd_id="$1"
    local line kind msg

    level_heading "[L3]" "Context update check:"

    while IFS=$'\t' read -r kind msg; do
        [ -n "$kind" ] || continue
        case "$kind" in
            SKIP)
                echo "  SKIP (${msg})"
                ;;
            INFO)
                echo "  ${msg}"
                ;;
            OK)
                echo "  OK: ${msg}"
                ;;
            WARN)
                echo "  [INFO] ${msg}"
                ;;
            BLOCK)
                echo "  [CRITICAL] NG ← ${msg}"
                record_block_reason "$msg"
                ALL_CLEAR=false
                ;;
            *)
                echo "  [INFO] unexpected check_context_update output: ${kind} ${msg}"
                ;;
        esac
    done < <(
        python3 - "$SCRIPT_DIR" "$cmd_id" "${MATCHING_TASK_FILES[@]}" <<'PY'
import glob
import os
import re
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

root = sys.argv[1]
cmd_id = sys.argv[2]
task_paths = sys.argv[3:]

def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def find_cmd_entry():
    candidates = [os.path.join(root, "queue", "shogun_to_karo.yaml")]
    archived = sorted(
        glob.glob(os.path.join(root, "queue", "archive", "cmds", f"{cmd_id}_*.yaml")),
        reverse=True,
    )
    candidates.extend(archived)

    for path in candidates:
        data = load_yaml(path)
        commands = data.get("commands", [])
        if not isinstance(commands, list):
            continue
        for cmd in commands:
            if isinstance(cmd, dict) and str(cmd.get("id", "")).strip() == cmd_id:
                return cmd, path
    return None, None

cmd, source_path = find_cmd_entry()
if not cmd:
    print("WARN\tcmd entry not found in shogun_to_karo.yaml or queue/archive/cmds")
    sys.exit(0)

context_update = cmd.get("context_update")

if isinstance(context_update, str):
    targets = [context_update]
elif isinstance(context_update, list):
    targets = [str(v).strip() for v in context_update if str(v).strip()]
elif isinstance(context_update, dict):
    targets = [str(context_update.get("path", "")).strip()]
else:
    targets = []

def context_paths(value):
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, list):
        values = value
    else:
        values = []
    result = []
    for item in values:
        if isinstance(item, dict):
            item = item.get("path", item.get("context_path", ""))
        path = str(item or "").strip().lstrip("./")
        if path:
            result.append(path)
    return result

explicit_targets = set(context_paths(context_update))
candidate_count = 0
candidate_blocked = False
for task_path in task_paths:
    if not task_path or not os.path.isfile(task_path):
        continue
    task_data = load_yaml(task_path).get("task", {})
    if not isinstance(task_data, dict):
        continue
    task_explicit = set(context_paths(task_data.get("context_update")))
    task_explicit.update(explicit_targets)
    candidates = task_data.get("context_update_candidates", [])
    if not isinstance(candidates, list):
        print(f"BLOCK\tcontext_update_candidates:{os.path.basename(task_path)}:invalid_type")
        candidate_blocked = True
        continue
    for candidate in candidates:
        if isinstance(candidate, dict):
            rel = str(candidate.get("path", candidate.get("context_path", ""))).strip()
            owner = str(candidate.get("owner", "")).strip()
            trigger = str(candidate.get("update_trigger", "")).strip()
            sources = ",".join(str(v).strip() for v in candidate.get("source_paths", []) if str(v).strip())
        else:
            rel = str(candidate or "").strip()
            owner = trigger = sources = ""
        rel = rel.lstrip("./")
        if not rel:
            print(f"BLOCK\tcontext_update_candidates:{os.path.basename(task_path)}:empty_path")
            candidate_blocked = True
            continue
        candidate_count += 1
        if rel in task_explicit:
            if rel not in targets:
                targets.append(rel)
            print(f"INFO\tcontext_update_candidate:{rel}:explicitly_processed")
            continue
        detail = f"context_update_candidate:{rel}:unprocessed"
        if owner:
            detail += f" owner={owner}"
        if trigger:
            detail += f" update_trigger={trigger}"
        if sources:
            detail += f" source_paths={sources}"
        print(f"BLOCK\t{detail}")
        candidate_blocked = True

if candidate_blocked and not targets:
    sys.exit(0)

if not context_update:
    if not targets:
        if candidate_count:
            sys.exit(0)
        print("SKIP\tcontext_update not set")
        sys.exit(0)
elif not targets:
    print("WARN\tcontext_update has invalid type (expected list/string)")
    sys.exit(0)

if not targets:
    print("SKIP\tcontext_update empty")
    sys.exit(0)

cmd_ts = str(cmd.get("timestamp") or cmd.get("delegated_at") or "").strip()
if not cmd_ts:
    print("WARN\tcmd timestamp/delegated_at not found; skipping")
    sys.exit(0)

m = re.search(r"(\d{4}-\d{2}-\d{2})", cmd_ts)
if not m:
    print(f"WARN\tcmd timestamp format unsupported: {cmd_ts}")
    sys.exit(0)

cmd_date = m.group(1)
print(f"INFO\treference_date={cmd_date} source={os.path.basename(source_path)}")

for rel in targets:
    rel = rel.strip()
    if not rel:
        continue
    abs_path = os.path.join(root, rel)
    if not os.path.isfile(abs_path):
        print(f"WARN\t{rel}: file not found (skip)")
        continue

    try:
        with open(abs_path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        print(f"WARN\t{rel}: cannot read file (skip)")
        continue

    m2 = re.search(r"<!--\s*last_updated:\s*(\d{4}-\d{2}-\d{2})\b", text)
    if not m2:
        print(f"BLOCK\tcontext_update:{rel}:last_updated_missing")
        continue

    last_updated = m2.group(1)
    if last_updated < cmd_date:
        print(
            f"BLOCK\tcontext_update:{rel}:stale (last_updated={last_updated}, cmd={cmd_ts})"
        )
    else:
        print(f"OK\t{rel}: last_updated={last_updated} (cmd={cmd_date})")

    if rel.startswith("context/") and rel.endswith(".md"):
        if "## 因果リンク" not in text:
            print(f"WARN\tcontext_update:{rel}:causal_links_section_missing")
PY
    )
}

# ─── preflight: ゲートフラグ未存在時の自動生成（冪等） ───
# GATE BLOCK率65%の主因=missing_gate(archive/lesson/review_gate)を解消。
# gate本体チェック前に、対応するフラグ生成処理を先行実行する。
# 既にフラグが存在する場合は何もしない(冪等)。品質BLOCKは維持。
preflight_gate_flags() {
    local cmd_id="$1"
    local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"

    echo "[L1] Preflight gate flag generation:"

    # 1. review_gate.done — archiveより先に実行（競合防止: review_gate.done不在時にarchiveがスキップするため）
    local pf_gate pf_needs_review=false
    for pf_gate in "${ALL_GATES[@]}"; do
        [ "$pf_gate" = "review_gate" ] && pf_needs_review=true && break
    done
    if [ "$pf_needs_review" = true ] && [ ! -f "$gates_dir/review_gate.done" ]; then
        echo "  review_gate: generating..."
        if bash "$SCRIPT_DIR/scripts/review_gate.sh" "$cmd_id" 2>&1; then
            echo "  review_gate: preflight OK"
        else
            echo "  [INFO] review_gate: preflight WARN (review may not be complete)"
        fi
    elif [ "$pf_needs_review" = true ]; then
        echo "  review_gate: already exists (skip)"
    fi

    # 2. archive.done — GATE CLEAR後に実行（報告YAMLをGATEが読み終わってからアーカイブ）
    #    cmd_1302: archiveをpreflight→GATE CLEAR後に移動。preflight時点ではスキップ。
    if [ ! -f "$gates_dir/archive.done" ]; then
        echo "  archive: deferred (will run after GATE CLEAR)"
    else
        echo "  archive: already exists (skip)"
    fi

    # 3. lesson.done — found:true候補確認後、適切な方法でフラグ生成
    if [ ! -f "$gates_dir/lesson.done" ]; then
        echo "  lesson: checking lesson_candidates..."
        local has_found_true=false
        local pf_task_file
        for pf_task_file in "${MATCHING_TASK_FILES[@]}"; do
            if [ ! -f "$pf_task_file" ]; then
                echo "  [WARN] matching task file disappeared, skipping: $pf_task_file"
                MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
                continue
            fi
            MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
            local pf_report_file pf_lc_found pf_ninja_name
            pf_ninja_name=$(basename "$pf_task_file" .yaml)
            pf_report_file=$(resolve_report_file "$pf_ninja_name")
            if [ -f "$pf_report_file" ]; then
                pf_lc_found=$(_check_lc_found "$pf_report_file")
                [ "$pf_lc_found" = "true" ] && has_found_true=true
            fi
        done
        if [ "$has_found_true" = true ]; then
            local pf_registered=false
            for pf_task_file in "${MATCHING_TASK_FILES[@]}"; do
                [ -f "$gates_dir/lesson.done" ] && pf_registered=true && break
                if [ ! -f "$pf_task_file" ]; then
                    continue
                fi
                local pf_report_file pf_lc_found pf_ninja_name
                pf_ninja_name=$(basename "$pf_task_file" .yaml)
                pf_report_file=$(resolve_report_file "$pf_ninja_name")
                if [ -f "$pf_report_file" ]; then
                    pf_lc_found=$(_check_lc_found "$pf_report_file")
                    if [ "$pf_lc_found" = "true" ]; then
                        echo "  lesson: auto-registering found:true candidate (${pf_ninja_name})"
                        if bash "$SCRIPT_DIR/scripts/auto_draft_lesson.sh" "$pf_report_file" 2>&1; then
                            if [ -f "$gates_dir/lesson.done" ]; then
                                pf_registered=true
                                break
                            fi
                        else
                            echo "  [INFO] lesson: auto_draft_lesson failed for ${pf_ninja_name} (non-blocking)"
                        fi
                    fi
                fi
            done
            if [ "$pf_registered" = true ]; then
                echo "  lesson: preflight OK (via auto_draft_lesson/lesson_write)"
            else
                echo "  lesson: pending (found:true — waiting for lesson_write-generated flag)"
            fi
        else
            # found:true候補なし → lesson_check.shで「教訓なし」フラグ生成
            if bash "$SCRIPT_DIR/scripts/lesson_check.sh" "$cmd_id" "preflight: no found:true lesson_candidate" 2>&1; then
                echo "  lesson: preflight OK (via lesson_check)"
            else
                echo "  [INFO] lesson: preflight WARN (lesson_check failed, non-blocking)"
            fi
        fi
    else
        # cmd_407: deploy_preflightで生成済みの場合、found:true検出時にsource upgradeする
        # cmd_536 AC2 fix: else分岐でもfound:trueをスキャンする（has_found_trueスコープ不整合修正）
        local has_found_true=false
        local pf_task_file
        for pf_task_file in "${MATCHING_TASK_FILES[@]}"; do
            if [ ! -f "$pf_task_file" ]; then
                echo "  [WARN] matching task file disappeared, skipping: $pf_task_file"
                MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
                continue
            fi
            MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
            local pf_report_file pf_lc_found pf_ninja_name
            pf_ninja_name=$(basename "$pf_task_file" .yaml)
            pf_report_file=$(resolve_report_file "$pf_ninja_name")
            if [ -f "$pf_report_file" ]; then
                pf_lc_found=$(_check_lc_found "$pf_report_file")
                [ "$pf_lc_found" = "true" ] && has_found_true=true
            fi
        done
        local pf_lesson_source
        pf_lesson_source=$(grep -E '^\s*source:' "$gates_dir/lesson.done" 2>/dev/null | sed 's/.*source: *//')
        if [ "$pf_lesson_source" != "lesson_write" ] && [ "$has_found_true" = true ]; then
            echo "  lesson: upgrading source ${pf_lesson_source} → lesson_write (found:true detected)"
            echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S')" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
            echo "note: preflight upgrade (${pf_lesson_source}→lesson_write, found:true)" >> "$gates_dir/lesson.done"
        else
            echo "  lesson: already exists (skip)"
        fi
    fi

    # 4. report_merge.done (conditional — ALL_GATESに含まれる場合のみ)
    local pf_needs_merge=false
    for pf_gate in "${ALL_GATES[@]}"; do
        [ "$pf_gate" = "report_merge" ] && pf_needs_merge=true && break
    done
    if [ "$pf_needs_merge" = true ] && [ ! -f "$gates_dir/report_merge.done" ]; then
        echo "  report_merge: generating..."
        if [ -f "$SCRIPT_DIR/scripts/report_merge.sh" ]; then
            if bash "$SCRIPT_DIR/scripts/report_merge.sh" "$cmd_id" 2>&1; then
                echo "  report_merge: preflight OK"
            else
                echo "  [INFO] report_merge: preflight WARN (merge may not be ready)"
            fi
        else
            echo "  report_merge: SKIP (script not found)"
        fi
    elif [ "$pf_needs_merge" = true ]; then
        echo "  report_merge: already exists (skip)"
    fi

    # 5. GP-027: target_path未commit変更検出（WARN only、BLOCKしない）
    echo "  target_path uncommitted check:"
    local tp_warn_count=0
    local tp_task_file
    for tp_task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$tp_task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $tp_task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        local tp_info
        # task.project と task.target_path を取得
        local _tp_project_id _tp_target_raw _tp_project_path
        _tp_project_id=$(FIELD_GET_NO_LOG=1 field_get "$tp_task_file" "project" "")
        # target_path: string or list
        _tp_target_raw=$(awk '
            /^[[:space:]]+target_path:/ {
                # inline value (string)
                val = $0; sub(/.*target_path:[[:space:]]*/, "", val); gsub(/^["'"'"']+|["'"'"']+$/, "", val)
                if (val != "" && val !~ /^\[/) { print val; exit }
                in_tp = 1; next
            }
            in_tp && /^[[:space:]]+- / { val = $0; sub(/^[[:space:]]+- [[:space:]]*/, "", val); gsub(/^["'"'"']+|["'"'"']+$/, "", val); print val; next }
            in_tp && /^[[:space:]]+[^ -]/ { exit }
            in_tp && /^[^ ]/ { exit }
        ' "$tp_task_file" 2>/dev/null)
        [ -z "$_tp_target_raw" ] && continue
        # resolve project path
        _tp_project_path="$SCRIPT_DIR"
        if [ -n "$_tp_project_id" ] && [ "$_tp_project_id" != "infra" ]; then
            local _tp_pj_file="$SCRIPT_DIR/projects/${_tp_project_id}.yaml"
            if [ -f "$_tp_pj_file" ]; then
                local _tp_resolved
                _tp_resolved=$(awk '
                    /^[[:space:]]*path:/ { v=$0; sub(/.*path:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); if (v != "") { print v; exit } }
                    /project:/ { sec=1; next }
                    sec && /^[[:space:]]+path:/ { v=$0; sub(/.*path:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); if (v != "") { print v; exit } }
                    sec && /^[^ ]/ { sec=0 }
                ' "$_tp_pj_file" 2>/dev/null)
                [ -n "$_tp_resolved" ] && _tp_project_path="$_tp_resolved"
            fi
        fi
        tp_info=""
        while IFS= read -r _tp_one; do
            [ -z "$_tp_one" ] && continue
            tp_info="${tp_info}${_tp_project_path}	${_tp_one}
"
        done <<< "$_tp_target_raw"
        [ -z "$tp_info" ] && continue
        while IFS=$'\t' read -r tp_proj_path tp_file; do
            [ -z "$tp_file" ] && continue
            if [ ! -d "$tp_proj_path" ]; then
                continue
            fi
            # Get uncommitted files under target_path (staged + unstaged, deduplicated)
            local tp_uncommitted
            tp_uncommitted=$(cd "$tp_proj_path" && {
                git diff --name-only -- "$tp_file" 2>/dev/null
                git diff --cached --name-only -- "$tp_file" 2>/dev/null
            } | sort -u)
            [ -z "$tp_uncommitted" ] && continue
            # Exclude operational files: logs/, queue/, dashboard.md, *.log
            local tp_filtered
            tp_filtered=$(echo "$tp_uncommitted" | grep -v -E '^logs/|^queue/|^dashboard\.md$|\.log$' || true)
            [ -z "$tp_filtered" ] && continue
            while IFS= read -r tp_uf; do
                echo "    [WARN] uncommitted: $tp_uf"
                tp_warn_count=$((tp_warn_count + 1))
            done <<< "$tp_filtered"
        done <<< "$tp_info"
    done
    if [ "$tp_warn_count" -gt 0 ]; then
        echo "    -> ${tp_warn_count} file(s) with uncommitted changes (WARN, non-blocking)"
            append_line_locked "$LOG_DIR/gate_fire_log.yaml" "$(date '+%Y-%m-%dT%H:%M:%S') [WARN] ${cmd_id} gate: \"cmd_complete_gate\" target_path_uncommitted: ${tp_warn_count} file(s)"
            python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" gate \
                --gate-name "cmd_complete_gate:target_path_uncommitted" --result "WARN" \
                --cmd-id "${cmd_id:-}" --ts "$(date -Is)" --detail "${tp_warn_count} file(s) uncommitted" \
                --source-file "$LOG_DIR/gate_fire_log.yaml" >/dev/null 2>&1 &
            disown 2>/dev/null || true
    else
        echo "    all target_path committed (OK)"
    fi

    echo ""
}

# ─── DEFERRED_GATES: gate check loopではスキップし、GATE CLEAR後に実行するgate ───
# cmd_1314: archive gateの循環依存修正。archiveはGATE CLEARに報告YAMLを読み終わってから実行する必要がある。
# gate check loop時点でarchive.doneを要求するとGATE CLEARできない→archiveが走れない→永久BLOCK。
# shellcheck disable=SC2034  # Used in gate check loop (L1858)
DEFERRED_GATES=("archive")

# ─── parent_cmd一致タスクファイルのキャッシュ（grep×26回→連想配列O(1)ルックアップ） ───
# WSL2最適化: 個別grep×N回 → grep -l一括スキャン(プロセス1本)
declare -A _CMD_TASK_MAP
MATCHING_TASK_FILES=()
RAW_MATCHING_TASK_FILES=()
dedupe_task_files_by_logical_identity() {
    local live_tasks_dir="$1"
    shift
    python3 - "$live_tasks_dir" "$@" <<'PY'
import datetime as dt, pathlib, sys, yaml
live_dir = pathlib.Path(sys.argv[1]).resolve()
rows = []
def stamp(value):
    if value in (None, ""): return float("-inf")
    text = str(value).strip().replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(text)
        if parsed.tzinfo is None: parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.timestamp()
    except ValueError: return float("-inf")
for raw_path in sys.argv[2:]:
    path = pathlib.Path(raw_path)
    try: raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception: continue
    task = raw.get("task", raw) if isinstance(raw, dict) else {}
    if not isinstance(task, dict): continue
    task_id = str(task.get("task_id") or task.get("_ac_task_id") or "").strip()
    key = task_id or "path:" + str(path)
    is_live = path.parent.resolve() == live_dir
    rows.append((key, is_live, stamp(task.get("deployed_at") or task.get("issued_at")), str(path)))
chosen = {}
for row in rows:
    old = chosen.get(row[0])
    if old is None or (row[1], row[2], row[3]) > (old[1], old[2], old[3]):
        chosen[row[0]] = row
for row in sorted(chosen.values(), key=lambda item: item[3]):
    print(row[3])
PY
}
mapfile -t RAW_MATCHING_TASK_FILES < <(list_task_files_for_cmd "$TASKS_DIR" "$CMD_ID" | sort -u || true)
ARCHIVED_TASKS_DIR="${CMD_COMPLETE_GATE_ARCHIVED_TASKS_DIR:-$SCRIPT_DIR/queue/archive/tasks}"
_ARCHIVED_MATCHING_TASK_FILES=()
if [ -d "$ARCHIVED_TASKS_DIR" ]; then
    mapfile -t _ARCHIVED_MATCHING_TASK_FILES < <(list_task_files_for_cmd "$ARCHIVED_TASKS_DIR" "$CMD_ID" | sort -r || true)
    RAW_MATCHING_TASK_FILES+=("${_ARCHIVED_MATCHING_TASK_FILES[@]}")
fi
while IFS= read -r _cache_tf; do
    [ -f "$_cache_tf" ] || continue
    _CMD_TASK_MAP["$_cache_tf"]=1
    MATCHING_TASK_FILES+=("$_cache_tf")
done < <(dedupe_task_files_by_logical_identity "$TASKS_DIR" "${RAW_MATCHING_TASK_FILES[@]}")
if cmd_status_is_canceled "$CMD_ID"; then
    MATCHING_TASK_FILES=()
    _CMD_TASK_MAP=()
    echo "Canceled cmd detected: ${CMD_ID}; task/report wait checks excluded"
fi
MATCHING_TASK_FILES_INITIAL_COUNT=${#MATCHING_TASK_FILES[@]}
MATCHING_TASK_FILES_SUPERSEDED_COUNT=$((${#RAW_MATCHING_TASK_FILES[@]} - MATCHING_TASK_FILES_INITIAL_COUNT))
MATCHING_TASK_FILES_PROCESSED_COUNT=0
MATCHING_TASK_FILES_SKIPPED_COUNT=0
echo "Matching task files snapshot: ${MATCHING_TASK_FILES_INITIAL_COUNT} (superseded_same_task_id=${MATCHING_TASK_FILES_SUPERSEDED_COUNT})"

print_matching_task_files_summary() {
    echo "Matching task files summary: snapshot=${MATCHING_TASK_FILES_INITIAL_COUNT} processed_refs=${MATCHING_TASK_FILES_PROCESSED_COUNT} skipped_missing=${MATCHING_TASK_FILES_SKIPPED_COUNT}"
}
# O(1) lookup: is_cmd_task "$task_file" → 0 if matching, 1 otherwise
is_cmd_task() { [[ "${_CMD_TASK_MAP["$1"]+_}" ]]; }

cmd_entry_exists() {
    local cmd_id="$1"
    grep -qE "^[[:space:]]*-[[:space:]]*id:[[:space:]]*[\"']?${cmd_id}([\"']?([[:space:]]|$))" "$YAML_FILE" 2>/dev/null
}

get_cmd_head_hashes() {
    local cmd_id="$1"

    git -C "$SCRIPT_DIR" log --format='%H%x1f%s%x1f%b%x1e' -n 100 2>/dev/null | \
    awk -v cmd="$cmd_id" '
        BEGIN { RS="\x1e" }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            if ($0 == "") next
            split($0, parts, "\x1f")
            hash = parts[1]
            subject = parts[2]
            body = parts[3]
            haystack = subject "\n" body
            if (index(haystack, cmd) > 0 && index(subject, " chore:") == 0) {
                print hash
                found = 1
                next
            }
            if (found) exit
        }
    '
}

get_cmd_changed_files() {
    local cmd_id="$1"
    local cmd_hash

    for cmd_hash in $(get_cmd_head_hashes "$cmd_id"); do
        git -C "$SCRIPT_DIR" diff-tree --no-commit-id --name-only -r "$cmd_hash" 2>/dev/null || true
    done | awk 'NF && !seen[$0]++'
}

collect_report_modified_files() {
    local task_file ninja_name report_file
    local -A _crmf_seen_reports=()

    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name")
            [ -f "$report_file" ] || continue
            _crmf_seen_reports["$report_file"]=1
        done
    fi

    # cmd_karo_hotfix_gate_report_discovery_after_redeploy: worker task YAMLが
    # 次cmdへ既に上書きされ(MATCHING_TASK_FILESの対象外/task snapshot=0)ても、
    # report自身のparent_cmd/task_id厳密一致でcmd Aのreportを発見する(cmd_3844型偽BLOCK根治)。
    while IFS= read -r report_file; do
        [ -n "$report_file" ] || continue
        _crmf_seen_reports["$report_file"]=1
    done < <(discover_reports_for_cmd "$CMD_ID")

    for report_file in "${!_crmf_seen_reports[@]}"; do
        [ -f "$report_file" ] || continue
        awk '
            /^files_modified:/ { in_files=1; next }
            in_files && /^[^[:space:]-]/ { in_files=0 }
            in_files && /^[[:space:]-]*(path|file):/ {
                v=$0
                sub(/.*(path|file):[[:space:]]*/, "", v)
                gsub(/^["'"'"']+|["'"'"']+$/, "", v)
                if (v != "") print v
            }
        ' "$report_file" 2>/dev/null || true
    done | awk 'NF && !seen[$0]++'
}

load_validated_sg7_context() {
    local bundle_path="$1"
    local spec_json="$2"
    local -a _sg7_lines

    # cmd_karo_hotfix_speed_cmd_complete_gate_r1_20260809: 4 python3起動を1回へ
    # 統合(interpreter起動コストが支配的)。各フィールドはtry/exceptで独立に
    # 失敗を吸収し、元の4プロセスがそれぞれ独立失敗した場合と同じ挙動(該当
    # フィールドのみ空文字)を維持する。
    mapfile -t _sg7_lines < <(SPEC_JSON="$spec_json" BUNDLE_PATH="$bundle_path" python3 - <<'PY'
import json
import os

spec_json = os.environ.get("SPEC_JSON", "")
bundle_path = os.environ.get("BUNDLE_PATH", "")


def safe(fn):
    try:
        return fn()
    except Exception:
        return ""


def get_project():
    return str(json.loads(spec_json).get("project") or "").strip()


def get_spec_source():
    with open(bundle_path, encoding="utf-8") as f:
        return str(json.load(f)["review"].get("cmd_spec_source") or "").strip()


def get_reviewed_at():
    with open(bundle_path, encoding="utf-8") as f:
        return str(json.load(f)["review"].get("reviewed_at") or "").strip()


def get_scope():
    scope = json.loads(spec_json).get("scope")
    out = []
    if isinstance(scope, list):
        for item in scope:
            value = str(item or "").strip()
            if value:
                out.append(value)
    return out


print(safe(get_project))
print(safe(get_spec_source))
print(safe(get_reviewed_at))
for _value in (safe(get_scope) or []):
    print(_value)
PY
)
    CMD_PROJECT="${_sg7_lines[0]:-}"
    SG7_SPEC_SOURCE="${_sg7_lines[1]:-}"
    SG7_REVIEWED_AT="${_sg7_lines[2]:-}"
    if [ "${#_sg7_lines[@]}" -gt 3 ]; then
        SG7_SPEC_SCOPE=$(printf '%s\n' "${_sg7_lines[@]:3}")
    else
        SG7_SPEC_SCOPE=""
    fi

    case "$SG7_SPEC_SOURCE" in
        queue/reports/*.yaml|queue/archive/reports/*.yaml) SG7_DIRECT_REPORT_SPEC=true ;;
        *) SG7_DIRECT_REPORT_SPEC=false ;;
    esac
}

# cmd_karo_* has no SG7 bundle, but its CI freshness boundary is still the
# exact two-phase review boundary.  Resolve that boundary from the same
# fingerprint-bound approval files used by review_all_reports_ready().  The
# later of Gunshi LGTM and Karo ACCEPT is the first instant at which the
# report is fully reviewed, so a CI run must be compared against that instant.
# Missing, mismatched, or malformed approval evidence is terminal: an empty
# timestamp must never reach evaluate_ci_readiness_json as a misleading
# datetime parse failure.
resolve_karo_reviewed_at() {
    local cmd_id="$1" root="$2" report fingerprint logical key dir role result approval
    local timestamp
    shift 2

    [[ "$cmd_id" == cmd_karo_* ]] || return 1
    [ "$#" -gt 0 ] || {
        echo "BLOCK: ${cmd_id}:two_phase_review_reports_missing" >&2
        return 1
    }

    local -a timestamps=()
    for report in "$@"; do
        fingerprint=$(review_report_fingerprint "$report") || {
            echo "BLOCK: ${cmd_id}:review_fingerprint_unresolvable report=${report}" >&2
            return 1
        }
        logical=$(PROJECT_ROOT="$root" review_report_logical_path "$report") || {
            echo "BLOCK: ${cmd_id}:review_report_logical_path_unresolvable report=${report}" >&2
            return 1
        }
        key=$(review_report_key "$logical") || return 1
        dir="$root/queue/gates/$cmd_id/review_approvals/reports/$key"

        for role in gunshi karo; do
            case "$role" in
                gunshi) result=LGTM ;;
                karo) result=ACCEPT ;;
            esac
            approval="$dir/$role.yaml"
            [ -f "$approval" ] || {
                echo "BLOCK: ${cmd_id}:review_approval_missing role=${role} report=${logical}" >&2
                return 1
            }
            [ "$(review_approval_value "$approval" result 2>/dev/null || true)" = "$result" ] || {
                echo "BLOCK: ${cmd_id}:review_approval_result_mismatch role=${role} report=${logical}" >&2
                return 1
            }
            [ "$(review_approval_value "$approval" fingerprint 2>/dev/null || true)" = "$fingerprint" ] || {
                echo "BLOCK: ${cmd_id}:review_approval_fingerprint_mismatch role=${role} report=${logical}" >&2
                return 1
            }
            timestamp=$(review_approval_value "$approval" timestamp 2>/dev/null || true)
            [ -n "$timestamp" ] || {
                echo "BLOCK: ${cmd_id}:review_approval_timestamp_missing role=${role} report=${logical}" >&2
                return 1
            }
            timestamps+=("$timestamp")
        done
    done

    python3 - "${timestamps[@]}" <<'PY'
from datetime import datetime, timezone
import sys

values = sys.argv[1:]
if not values:
    print("BLOCK: review approval timestamps missing", file=sys.stderr)
    raise SystemExit(1)
parsed = []
for value in values:
    try:
        item = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except (TypeError, ValueError):
        print("BLOCK: review approval timestamp datetime parse failed", file=sys.stderr)
        raise SystemExit(1)
    if item.tzinfo is None:
        print("BLOCK: review approval timestamp timezone missing", file=sys.stderr)
        raise SystemExit(1)
    parsed.append(item.astimezone(timezone.utc))
print(max(parsed).isoformat(timespec="seconds").replace("+00:00", "Z"))
PY
}

resolve_sg7_completion_identity() {
    local bundle_path="$1"
    local bundle_cmd_id bundle_generation
    read -r bundle_cmd_id bundle_generation < <(
        BUNDLE_PATH="$bundle_path" python3 - <<'PY'
import json
import os

review = (json.load(open(os.environ["BUNDLE_PATH"], encoding="utf-8")) or {}).get("review") or {}
print(str(review.get("cmd_id") or "").strip(), str(review.get("report_fingerprint") or "").strip())
PY
    )
    if [ "$bundle_cmd_id" != "$CMD_ID" ] || [[ ! "$bundle_generation" =~ ^[0-9a-f]{64}$ ]]; then
        echo "GATE BLOCK: ${CMD_ID}:completion_bundle_identity_missing_or_invalid" >&2
        return 1
    fi
    if [ -n "${SHOGUN_COMPLETION_GENERATION:-}" ] \
        && [ "$SHOGUN_COMPLETION_GENERATION" != "$bundle_generation" ]; then
        echo "GATE BLOCK: ${CMD_ID}:completion_generation_bundle_mismatch" >&2
        return 1
    fi
    export SHOGUN_COMPLETION_GENERATION="$bundle_generation"
}

collect_cmd_command_file_refs() {
    local cmd_id="$1"
    local verified_deps="${2:-}"

    if [ "${SG7_DIRECT_REPORT_SPEC:-false}" = "true" ] && [ -n "${SG7_SPEC_SCOPE:-}" ]; then
        printf '%s\n' "$SG7_SPEC_SCOPE"
        return 0
    fi

    CMD_ID_ENV="$cmd_id" YAML_FILE_ENV="$YAML_FILE" SCRIPT_DIR_ENV="$SCRIPT_DIR" VERIFIED_EXISTING_DEPS_ENV="$verified_deps" python3 - <<'PY' 2>/dev/null || true
import glob
import os
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

cmd_id = os.environ.get("CMD_ID_ENV", "")
yaml_file = os.environ.get("YAML_FILE_ENV", "")
script_dir = os.environ.get("SCRIPT_DIR_ENV", "")
verified_deps_raw = os.environ.get("VERIFIED_EXISTING_DEPS_ENV", "")
verified_deps = [
    line.strip().strip("`'\"")
    for line in verified_deps_raw.splitlines()
    if line.strip()
]

try:
    with open(yaml_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    data = {}

commands = data.get("commands", data.get("cmds", data))
def find_entry(payload):
    command_rows = payload.get("commands", payload.get("cmds", payload)) if isinstance(payload, dict) else payload
    if isinstance(command_rows, dict):
        return command_rows.get(cmd_id)
    if isinstance(command_rows, list):
        for row in command_rows:
            if isinstance(row, dict) and str(row.get("id", "")) == cmd_id:
                return row
    return None

entry = find_entry(data)
if not isinstance(entry, dict):
    # BLOCK後でもarchive_completed/status遷移が先行する経路がある。
    # active queueだけを見ると再ゲートで元commandが消え、coverage checkが
    # 「参照なし」と偽SKIPしてCLEARし得るため、archive正本へ必ずfallbackする。
    archive_glob = os.path.join(script_dir, "queue", "archive", "cmds", f"*{cmd_id}*.yaml")
    for archived_path in sorted(glob.glob(archive_glob), reverse=True):
        try:
            with open(archived_path, encoding="utf-8") as f:
                archived_data = yaml.safe_load(f) or {}
        except Exception:
            continue
        entry = find_entry(archived_data)
        if isinstance(entry, dict):
            break

if not isinstance(entry, dict):
    raise SystemExit(0)

command = entry.get("command", "")
if isinstance(command, (list, tuple)):
    command = " ".join(str(v) for v in command)
elif not isinstance(command, str):
    command = str(command)

raw_targets = entry.get("target_path", entry.get("target_paths", ""))
if isinstance(raw_targets, str):
    target_paths = [raw_targets]
elif isinstance(raw_targets, (list, tuple)):
    target_paths = [str(v) for v in raw_targets]
else:
    target_paths = []
target_paths = [p.strip().strip("`'\"") for p in target_paths if str(p).strip()]

pattern = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"("
    # Absolute paths are explicit references even when their basename has no
    # extension (for example, /tmp/fixture/README).
    r"/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+"
    r"|(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"
    r"|[A-Za-z0-9_.-]+\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv)"
    r")"
    r"(?![A-Za-z0-9_.-])"
)
read_markers = (
    "読む", "読んで", "読み", "確認", "参照", "調査", "精査", "review", "read", "inspect", "refer",
    "実行", "実行のみ", "変更対象外", "走らせ", "検証", "run", "execute",
    "同構造", "と同一", "と同じ", "同等", "踏襲", "に基づ", "を参考",
    "突合", "比較", "一覧", "解析", "分析", "取得", "検索", "出力", "表示", "呼び出", "呼出",
    "コピー", "copy", "ベース", "由来", "from", "から",
)
write_markers = (
    "修正", "更新", "変更", "編集", "実装", "追加", "削除", "作成", "反映",
    "modify", "update", "edit", "add", "remove", "delete", "create", "write", "implement",
)

def marker_pos(text, markers):
    positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
    return min(positions) if positions else -1

def ref_matches_target(ref, target):
    ref = ref.strip().strip("./")
    target = target.strip().strip("./")
    if not ref or not target:
        return False
    if ref == target or ref.endswith("/" + target) or target.endswith("/" + ref):
        return True
    if ref.startswith(target.rstrip("/") + "/"):
        return True
    return os.path.basename(ref) == os.path.basename(target)

def is_design_spec_instruction_ref(ref, local_text, sentence_tail, match_start):
    # "設計書docs/spec/foo.mdの変更1-4を実装" means implement the changes
    # described in the design document, not edit the design document itself.
    # If docs/spec is the target_path, ref_matches_target() below still keeps it
    # as an actual target before this readonly rule is applied.
    clean_ref = ref.strip().strip("./")
    if not ((clean_ref.startswith("docs/spec/") or clean_ref.startswith("docs/research/")) and clean_ref.endswith(".md")):
        return False
    # docs/research/ is always a readonly reference (recon reports, analysis results)
    # target_path check is done by the caller before invoking this function
    if clean_ref.startswith("docs/research/"):
        return True
    tail = (local_text + " " + sentence_tail)[:160]
    section_ref = (
        re.search(r"^\s*の?(?:§|第?\d+章|変更\d|変更[0-9０-９一二三四五六七八九十]+|実装順序)", local_text)
        is not None
    )
    instruction_words = ("実装" in tail) or ("従い" in tail) or ("通り" in tail) or ("記載" in tail)
    explicit_design_context = ("設計書" in sentence_tail) or ("設計書" in command[max(0, match_start - 40):match_start])
    return (section_ref and instruction_words) or (explicit_design_context and instruction_words)

def ref_matches_verified_dependency(ref):
    ref = ref.strip().strip("./")
    if not ref:
        return False
    ref_base = os.path.basename(ref)
    for dep in verified_deps:
        dep = dep.strip().strip("./")
        if not dep:
            continue
        dep_base = os.path.basename(dep)
        if (
            ref == dep
            or ref.endswith("/" + dep)
            or dep.endswith("/" + ref)
            or ref_base == dep_base
        ):
            return True
    return False

def is_probable_product_token(ref):
    # "Next.js" のようなフレームワーク名をファイル参照として誤検出しない。
    # スラッシュなし・大文字始まりでも、対象dir/リポジトリ直下に実在するならファイルとして扱う。
    clean_ref = ref.strip().strip("`'\".,:;()[]{}")
    if "/" in clean_ref or "\\" in clean_ref:
        return False
    stem = os.path.basename(clean_ref).split(".", 1)[0]
    if not stem[:1].isupper():
        return False
    if stem.upper() == stem:
        return False
    candidates = []
    if script_dir:
        candidates.append(os.path.join(script_dir, clean_ref))
    for target in target_paths:
        clean_target = target.strip().strip("./")
        if not clean_target or not script_dir:
            continue
        target_abs = clean_target if os.path.isabs(clean_target) else os.path.join(script_dir, clean_target)
        if os.path.isdir(target_abs):
            candidates.extend(glob.glob(os.path.join(target_abs, "**", clean_ref), recursive=True))
    return not any(os.path.isfile(path) for path in candidates)

def is_probable_slash_enum(ref):
    # Domain alternatives such as "full/ticker" use a slash but are not file
    # references.  Keep explicit/extension-bearing paths and extensionless
    # paths whose leading directory actually exists in the control repo.
    clean_ref = ref.strip().strip("`'\".,:;()[]{}")
    if clean_ref.startswith("/") or "/" not in clean_ref:
        return False
    basename = os.path.basename(clean_ref)
    if "." in basename:
        return False
    if any(ref_matches_target(clean_ref, target) for target in target_paths):
        return False
    first_component = clean_ref.split("/", 1)[0]
    return not (script_dir and os.path.isdir(os.path.join(script_dir, first_component)))

matches = list(pattern.finditer(command))
seen = set()
refs = []
for idx, match in enumerate(matches):
    ref = match.group(1).strip().strip("`'\".,:;()[]{}")
    if not ref or ref in seen:
        continue
    if is_probable_product_token(ref):
        continue
    if is_probable_slash_enum(ref):
        continue
    seen.add(ref)
    if ref_matches_verified_dependency(ref):
        continue
    sentence_end_candidates = [
        pos for pos in (
            command.find("\n", match.end()),
            command.find("。", match.end()),
            command.find("；", match.end()),
            command.find(";", match.end()),
        )
        if pos >= 0
    ]
    sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(command)
    next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
    local = command[match.end():next_file_start]
    sentence_tail = command[match.end():sentence_end]
    read_pos = marker_pos(local, read_markers)
    if read_pos < 0:
        read_pos = marker_pos(sentence_tail, read_markers)
    write_pos = marker_pos(sentence_tail, write_markers)
    next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (
        write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos
    )
    # 実行前置き動詞検出: bash/python3等がパス直前 → 実行のみ参照として除外
    exec_verbs = {"bash", "python3", "python", "sh", "bats", "node"}
    prefix_text = command[max(0, match.start() - 60):match.start()]
    prefix_tokens = prefix_text.split()
    is_exec_prefix = bool(prefix_tokens) and prefix_tokens[-1].lower() in exec_verbs
    # ロジックパラメータ検出: "{file}上書きロジック" 等、ファイル参照直後に名詞→実際の変更対象はロジックを持つ親ファイル
    logic_nouns = ("ロジック", "処理", "関数", "コード", "スクリプト", "機能", "仕組み")
    post_ref_text = command[match.end():match.end()+20]
    is_logic_param = any(post_ref_text.startswith(n) or post_ref_text.startswith("上書き" + n) or post_ref_text.startswith("復元" + n) or post_ref_text.startswith("読取" + n) for n in logic_nouns)
    if is_logic_param:
        readonly_ref = True
        refs.append((ref, readonly_ref))
        continue
    if target_paths and not any(ref_matches_target(ref, target) for target in target_paths) and is_design_spec_instruction_ref(ref, local, sentence_tail, match.start()):
        refs.append((ref, True))
        continue
    # 読点「、」区切り検出: read_markerとwrite_markerの間に「、」→ 別節のwrite_marker → 除外
    has_clause_boundary = False
    if read_pos >= 0 and write_pos >= 0 and read_pos < write_pos:
        jp_comma = sentence_tail.find("、", read_pos)
        ascii_comma = sentence_tail.find(",", read_pos)
        clause_positions = [p for p in [jp_comma, ascii_comma] if p >= 0]
        if clause_positions:
            has_clause_boundary = min(clause_positions) < write_pos
    readonly_ref = is_exec_prefix or has_clause_boundary or (
        read_pos >= 0 and (write_pos < 0 or read_pos < write_pos) and (
            write_pos < 0 or next_ref_before_write
        )
    )
    refs.append((ref, readonly_ref))

target_refs = []
if target_paths:
    for ref, _readonly_ref in refs:
        if any(ref_matches_target(ref, target) for target in target_paths):
            target_refs.append(ref)

if target_refs:
    for ref in target_refs:
        print(ref)
elif not target_paths:
    for ref, readonly_ref in refs:
        if readonly_ref:
            continue
        print(ref)
else:
    for ref, readonly_ref in refs:
        if readonly_ref:
            continue
        print(ref)
PY
}

collect_report_verified_existing_deps() {
    # 報告YAMLのverified_existing_dependency欄からLG037「実行のみ/既存依存」ファイルを収集。
    # files_modified内のchange/statusでも同じ意思表示を受け付ける。
    # checked_not_modifiedは「確認したが変更不要」の明示経路として同じ除外ソースにする。
    # 加えて、指示ファイルが実在しないため代替記録した旨が報告されているパスは変更漏れ扱いしない。
    local task_file ninja_name report_file
    if ! declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        return 0
    fi
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        [ -f "$task_file" ] || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue
        awk '
            function trim(s) {
                gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", s)
                return s
            }
            function emit_if_dep(path, marker) {
                path=trim(path)
                marker=trim(marker)
                if (path != "" && marker ~ /(verified_existing_dependency|checked_not_modified|not_modified|変更不要|参照のみ|既存依存|実行のみ|read.?only|no.?change)/) {
                    print path
                }
            }
            /^verified_existing_dependency:/ { in_ved=1; next }
            in_ved && /^[^[:space:]-]/ { in_ved=0 }
            in_ved && /^[[:space:]-]*(path|file):/ {
                v=$0
                sub(/.*(path|file):[[:space:]]*/, "", v)
                v=trim(v)
                if (v != "") print v
            }
            in_ved && /^[[:space:]]*-[[:space:]]+[^{]/ {
                v=$0
                sub(/^[[:space:]]*-[[:space:]]*/, "", v)
                v=trim(v)
                if (v != "" && v !~ /^(path|file|reason|category):/) print v
            }
            /^checked_not_modified:/ { in_checked=1; next }
            in_checked && /^[^[:space:]-]/ { in_checked=0 }
            in_checked && /^[[:space:]-]*(path|file):/ {
                v=$0
                sub(/.*(path|file):[[:space:]]*/, "", v)
                v=trim(v)
                if (v != "") print v
            }
            in_checked && /^[[:space:]]*-[[:space:]]+[^{]/ {
                v=$0
                sub(/^[[:space:]]*-[[:space:]]*/, "", v)
                v=trim(v)
                if (v != "" && v !~ /^(path|file|reason|category):/) print v
            }
            /^files_modified:/ {
                in_files=1
                fm_path=""
                fm_marker=""
                next
            }
            in_files && /^[^[:space:]-]/ {
                emit_if_dep(fm_path, fm_marker)
                in_files=0
                fm_path=""
                fm_marker=""
            }
            in_files && /^[[:space:]]*-[[:space:]]*(path|file):/ {
                emit_if_dep(fm_path, fm_marker)
                fm_path=$0
                sub(/.*(path|file):[[:space:]]*/, "", fm_path)
                fm_path=trim(fm_path)
                fm_marker=""
                next
            }
            in_files && /^[[:space:]]*(path|file):/ {
                fm_path=$0
                sub(/.*(path|file):[[:space:]]*/, "", fm_path)
                fm_path=trim(fm_path)
                next
            }
            in_files && /^[[:space:]]*(change|status|category|reason):/ {
                marker=$0
                sub(/.*(change|status|category|reason):[[:space:]]*/, "", marker)
                fm_marker=fm_marker " " marker
                next
            }
            /(存在せず|不存在|実在せず|直接更新不可)/ {
                line=$0
                while (match(line, /([A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+\.(md|yaml|yml|json|toml|sh|py|js|ts|tsx|jsx|css|html|sql|csv)/)) {
                    print substr(line, RSTART, RLENGTH)
                    line=substr(line, RSTART + RLENGTH)
                }
            }
            END {
                if (in_files) emit_if_dep(fm_path, fm_marker)
            }
        ' "$report_file" 2>/dev/null || true
    done | awk 'NF && !seen[$0]++'
}

collect_task_readonly_refs() {
    # deploy_task.shがtask YAMLへ源流注入したreadonly_refを収集する。
    # SG-PRE25/完了gateの除外ソースを同一化し、報告YAMLへの記録忘れでFP化しないようにする。
    local task_file
    if ! declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        return 0
    fi
    {
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            awk '
                /^  readonly_ref:/ { in_rr=1; next }
                in_rr && /^  [A-Za-z0-9_.-]+:/ { in_rr=0 }
                in_rr && /^[[:space:]]*-[[:space:]]*(path|file):/ {
                    v=$0
                    sub(/.*(path|file):[[:space:]]*/, "", v)
                    gsub(/^["'"'"']+|["'"'"']+$/, "", v)
                    if (v != "") print v
                }
                in_rr && /^[[:space:]]*-[[:space:]]+[^{]/ {
                    v=$0
                    sub(/^[[:space:]]*-[[:space:]]*/, "", v)
                    gsub(/^["'"'"']+|["'"'"']+$/, "", v)
                    if (v != "" && v !~ /^(path|file|reason|category):/) print v
                }
            ' "$task_file" 2>/dev/null || true
        done
        # Global readonly refs: speed training infrastructure (measurement tools, not modification targets)
        # LG036 recurrence x4: bash_speed_training.sh誤含→BLOCK。計測ツールは常にreadonly
        echo "tools/bash_speed_training.sh"
        echo "logs/script_speed_training_ledger.yaml"
    } | awk 'NF && !seen[$0]++'
}

check_command_files_modified_coverage() {
    level_heading "[L3]" "Command/files_modified coverage check:"

    local scope_mode
    scope_mode="$(CMD_ID_ENV="$CMD_ID" YAML_FILE_ENV="$YAML_FILE" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'
import glob
import os
import yaml

cmd_id = os.environ.get("CMD_ID_ENV", "")
yaml_file = os.environ.get("YAML_FILE_ENV", "")
script_dir = os.environ.get("SCRIPT_DIR_ENV", "")

def find_entry(payload):
    rows = payload.get("commands", payload.get("cmds", payload)) if isinstance(payload, dict) else payload
    if isinstance(rows, dict):
        return rows.get(cmd_id)
    if isinstance(rows, list):
        for row in rows:
            if isinstance(row, dict) and str(row.get("id", "")) == cmd_id:
                return row
    return None

entry = None
for path in (yaml_file, *sorted(glob.glob(os.path.join(script_dir, "queue", "archive", "cmds", f"*{cmd_id}*.yaml")), reverse=True)):
    try:
        with open(path, encoding="utf-8") as handle:
            entry = find_entry(yaml.safe_load(handle) or {})
    except Exception:
        entry = None
    if isinstance(entry, dict):
        break

print(str((entry or {}).get("scope_mode", "")).strip().upper())
PY
    )"
    if [ "$scope_mode" = "RESEARCH" ]; then
        echo "  SKIP (scope_mode=RESEARCH: command file refs are investigation inputs)"
        return 0
    fi

    # Recon/scout commands cite product files as investigation inputs, not write
    # targets.  Inferring writes from those references makes an honest report
    # (research/context artifacts only) impossible to distinguish from an
    # implementation omission.  Other report/commit gates still verify the
    # actual recon artifacts.  Mixed recon+implementation commands retain the
    # strict coverage check for their implementation phase.
    if [ "${HAS_RECON:-false}" = "true" ] && [ "${HAS_IMPLEMENT:-false}" = "false" ]; then
        echo "  SKIP (recon/scout-only cmd: command file refs are investigation inputs)"
        return 0
    fi

    local command_refs report_paths verified_deps
    verified_deps="$(
        {
            collect_report_verified_existing_deps || true
            collect_task_readonly_refs || true
        } | awk 'NF && !seen[$0]++'
    )"
    command_refs="$(collect_cmd_command_file_refs "$CMD_ID" "$verified_deps" || true)"
    if [ -z "$command_refs" ]; then
        echo "  SKIP (command欄に拡張子付きファイル参照なし)"
        return 0
    fi

    # LG037: verified_existing_dependency (実行のみ/既存依存) を照合対象から除外
    if [ -n "$verified_deps" ]; then
        local filtered_refs="" ref_line dep_line dep_matched ref_base dep_base
        while IFS= read -r ref_line; do
            [ -z "$ref_line" ] && continue
            dep_matched=false
            ref_base="$(basename "$ref_line")"
            while IFS= read -r dep_line; do
                [ -z "$dep_line" ] && continue
                dep_base="$(basename "$dep_line")"
                if [ "$ref_line" = "$dep_line" ] \
                    || [[ "$ref_line" == */"$dep_line" ]] \
                    || [[ "$dep_line" == */"$ref_line" ]] \
                    || [ "$ref_base" = "$dep_base" ]; then
                    dep_matched=true
                    break
                fi
            done <<< "$verified_deps"
            if [ "$dep_matched" = false ]; then
                filtered_refs="${filtered_refs}${ref_line}"$'\n'
            fi
        done <<< "$command_refs"
        command_refs="$(printf '%s' "$filtered_refs" | sed '/^$/d')"
        if [ -z "$command_refs" ]; then
            echo "  OK (command欄ファイル参照は全てverified_existing_dependency — LG037)"
            return 0
        fi
    fi

    report_paths="$(collect_report_modified_files || true)"
    if [ -z "$report_paths" ]; then
        echo "  [CRITICAL] COMMAND_SCOPE_MISSING: command欄ファイル参照あり、files_modified記載なし"
        printf '%s\n' "$command_refs" | sed 's/^/    missing: /'
        record_block_reason "command_files_modified_mismatch"
        ALL_CLEAR=false
        return 0
    fi

    # 偵察cmd等: files_modifiedが明示的no-code-change sentinelのみの場合はSKIP
    local has_sentinel=false has_real_path=false
    while IFS= read -r rp; do
        case "$rp" in
            *偵察のみ*|*コード変更なし*|*変更なし*|*no*change*|none|N/A|"") has_sentinel=true ;;
            *) has_real_path=true ;;
        esac
    done <<< "$report_paths"
    if [ "$has_sentinel" = true ] && [ "$has_real_path" = false ]; then
        echo "  SKIP (files_modified=no-code-change sentinel — 偵察cmd等)"
        return 0
    fi

    local missing_count=0 total_count=0 missing_list=""
    local ref modified matched ref_base modified_base ref_stem modified_stem
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        total_count=$((total_count + 1))
        ref_base="$(basename "$ref")"
        ref_stem="${ref_base%.*}"
        matched=false
        while IFS= read -r modified; do
            [ -z "$modified" ] && continue
            modified_base="$(basename "$modified")"
            modified_stem="${modified_base%.*}"
            if [ "$modified" = "$ref" ] \
                || [[ "$modified" == */"$ref" ]] \
                || [ "$modified_base" = "$ref_base" ] \
                || [[ "$modified_base" == *"$ref_base"* ]] \
                || [[ "$modified_stem" == *"$ref_stem"* ]]; then
                matched=true
                break
            fi
        done <<< "$report_paths"
        if [ "$matched" = false ]; then
            missing_count=$((missing_count + 1))
            missing_list="${missing_list}    missing: ${ref}\n"
        fi
    done <<< "$command_refs"

    if [ "$missing_count" -gt 0 ]; then
        echo "  [CRITICAL] COMMAND_SCOPE_MISSING: ${missing_count}/${total_count} command欄ファイル参照がfiles_modifiedに未記載"
        printf '%b' "$missing_list" | head -10
        echo "    -> report files_modifiedへ不足ファイルを記録してから再実行せよ"
        record_block_reason "command_files_modified_mismatch"
        ALL_CLEAR=false
    else
        echo "  OK (command欄ファイル参照 全${total_count}件がfiles_modifiedに記載済み)"
    fi
}

cmd_requires_cdp_production_check() {
    [ "${CMD_PROJECT:-}" = "dm-signal" ] || return 1

    CDP_SKIP_REASON="project=${CMD_PROJECT:-unknown}, frontend changes not detected"
    {
        printf '%s\n' "${CMD_CHANGED_FILES:-}"
        collect_report_modified_files
    } | awk '
        /^frontend\// || /\/frontend\// { found=1 }
        END { exit found ? 0 : 1 }
    ' || return 1

    CDP_SKIP_REASON="frontend change detected, but no production deploy/live evidence required"
    local task_file ninja_name report_file
    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$task_file" ] || continue
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name")
            [ -f "$report_file" ] || continue
            if REPORT_FILE="$report_file" python3 - <<'PY' 2>/dev/null
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

with open(os.environ["REPORT_FILE"], encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

pde = data.get("post_deploy_evidence")
if not isinstance(pde, dict):
    raise SystemExit(1)

raw = pde.get("required")
required = raw if isinstance(raw, bool) else str(raw).strip().lower() in {"1", "true", "yes", "y"}
raise SystemExit(0 if required else 1)
PY
            then
                CDP_SKIP_REASON=""
                return 0
            fi
        done
    fi

    return 1
}

run_cdp_production_check() {
    echo ""
    echo "CDP production check (FE post-gate):"

    if [ "${CDP_SKIP:-}" = "1" ]; then
        echo "  SKIP (CDP_SKIP=1)"
        return 0
    fi

    if ! cmd_requires_cdp_production_check; then
        echo "  SKIP (${CDP_SKIP_REASON:-conditions not met})"
        return 0
    fi

    local cdp_script="$SCRIPT_DIR/scripts/cdp/cdp_measure.sh"
    if [ ! -x "$cdp_script" ]; then
        echo "  [CRITICAL] cdp_measure.sh not executable: $cdp_script"
        return 1
    fi

    local cdp_timeout="${CDP_MEASURE_TIMEOUT:-900}"
    local cdp_pages_raw="${CDP_MEASURE_PAGES:-home dashboard summary}"
    local cdp_cmd=(bash "$cdp_script" "$CMD_ID")
    if [ "$cdp_pages_raw" != "all" ]; then
        local cdp_pages=()
        read -r -a cdp_pages <<< "$cdp_pages_raw"
        if [ "${#cdp_pages[@]}" -gt 0 ]; then
            cdp_cmd+=(--pages "${cdp_pages[@]}")
        fi
    fi
    echo "  REQUIRED: dm-signal frontend change with production deploy/live evidence"
    echo "  timeout: ${cdp_timeout}s"
    echo "  pages: ${cdp_pages_raw}"
    if timeout "$cdp_timeout" "${cdp_cmd[@]}"; then
        echo "  CDP production check: OK"
        return 0
    fi

    echo "  [CRITICAL] CDP production check failed"
    return 1
}

# dm-signal deploy cmd専用の本番到達性チェック。CDPはFEの画面検分であり、
# APIのHTTP応答とRender live revisionの一致を代替しないため、別ゲートとして
# fail-closedにする。適用条件はtask/reportのpost_deploy_evidence.required=true
# (またはproduction_deploy.required=true)に限定し、非deploy cmdを誤BLOCKしない。
cmd_requires_dm_signal_production_smoke() {
    [ "${CMD_PROJECT:-}" = "dm-signal" ] || return 1

    DM_SIGNAL_SMOKE_REQUIREMENT_REASON=""
    local task_file report_file
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        [ -f "$task_file" ] || continue
        report_file=$(resolve_report_file "$(basename "$task_file" .yaml)" 2>/dev/null || true)
        if TASK_FILE="$task_file" REPORT_FILE="$report_file" python3 - <<'PY' 2>/dev/null
import os
import yaml

def truthy(value):
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y"}

def load(path):
    if not path or not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return data.get("task", data) if isinstance(data, dict) else {}

task = load(os.environ.get("TASK_FILE", ""))
report = load(os.environ.get("REPORT_FILE", ""))
for data in (task, report):
    for key in ("post_deploy_evidence", "production_deploy", "production_deployment"):
        value = data.get(key)
        if isinstance(value, dict) and truthy(value.get("required")):
            raise SystemExit(0)
        if key != "post_deploy_evidence" and truthy(value):
            raise SystemExit(0)
raise SystemExit(1)
PY
        then
            DM_SIGNAL_SMOKE_REQUIREMENT_REASON="task=$(basename "$task_file") report=${report_file:-missing} field=post_deploy_evidence.required_or_production_deploy.required"
            return 0
        fi
    done
    return 1
}

dm_signal_report_deploy_sha() {
    local report_file="$1" which="$2"
    [ -f "$report_file" ] || return 1
    REPORT_FILE="$report_file" WHICH_SHA="$which" python3 - <<'PY'
import os
import yaml

with open(os.environ["REPORT_FILE"], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

def lookup(mapping, keys):
    if not isinstance(mapping, dict):
        return ""
    for key in keys:
        value = mapping.get(key)
        if value:
            return str(value).strip()
    return ""

pde = data.get("post_deploy_evidence") or {}
prod = data.get("production_deploy") or data.get("production_deployment") or {}
keys = {
    "origin": ("origin_sha", "origin_commit", "origin_head", "origin_revision"),
    "live": ("live_sha", "live_commit", "live_head", "live_revision", "deployed_sha"),
}
value = lookup(pde, keys[os.environ["WHICH_SHA"]]) or lookup(prod, keys[os.environ["WHICH_SHA"]])
print(value)
PY
}

resolve_dm_signal_render_live_sha() {
    # Unit/controlled production runs may provide an independently measured
    # live revision.  Otherwise query Render's deploy list and select the newest
    # deploy whose status is live; a failed newest deploy must not be accepted.
    if [ -n "${DM_SIGNAL_SMOKE_LIVE_SHA:-}" ]; then
        printf '%s\n' "$DM_SIGNAL_SMOKE_LIVE_SHA"
        return 0
    fi
    local api_key="${RENDER_API_KEY:-}"
    local service_id="${DM_SIGNAL_RENDER_SERVICE_ID:-srv-d4ja7q15pdvs739a4q1g}"
    local api_url="${DM_SIGNAL_RENDER_API_URL:-https://api.render.com/v1/services/${service_id}/deploys?limit=20}"
    [ -n "$api_key" ] || return 1
    local curl_bin="${DM_SIGNAL_SMOKE_CURL_BIN:-curl}" response
    response=$("$curl_bin" -sS -H "Authorization: Bearer ${api_key}" -H "Accept: application/json" "$api_url" 2>/dev/null) || return 1
    RENDER_RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

try:
    payload = json.loads(os.environ["RENDER_RESPONSE"])
except Exception:
    raise SystemExit(1)
rows = payload if isinstance(payload, list) else payload.get("deploys", [])
for row in rows:
    deploy = row.get("deploy", row) if isinstance(row, dict) else {}
    status = str(deploy.get("status") or deploy.get("state") or "").lower()
    commit = deploy.get("commit") or {}
    sha = commit.get("id") if isinstance(commit, dict) else commit
    sha = sha or deploy.get("commitId")
    if status == "live" and sha:
        print(str(sha).strip())
        raise SystemExit(0)
raise SystemExit(1)
PY
}

run_dm_signal_production_smoke_check() {
    echo ""
    echo "dm-signal production smoke check:"
    if ! cmd_requires_dm_signal_production_smoke; then
        echo "  SKIP (not a dm-signal production-deploy cmd)"
        return 0
    fi
    echo "  REQUIRED (basis: ${DM_SIGNAL_SMOKE_REQUIREMENT_REASON})"

    local task_file report_file repo origin_sha live_sha report_origin report_live
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        [ -f "$task_file" ] || continue
        repo=$(resolve_task_repo_dir "$task_file" 2>/dev/null || true)
        break
    done
    repo="${repo:-${DM_SIGNAL_REPO:-}}"

    origin_sha="${DM_SIGNAL_SMOKE_ORIGIN_SHA:-}"
    if [ -z "$origin_sha" ] && [ -n "$repo" ]; then
        origin_sha=$(git -C "$repo" rev-parse refs/remotes/origin/main 2>/dev/null \
            || git -C "$repo" rev-parse refs/remotes/origin/master 2>/dev/null || true)
    fi

    live_sha="${DM_SIGNAL_SMOKE_LIVE_SHA:-}"
    if [ -z "$live_sha" ]; then
        live_sha="$(resolve_dm_signal_render_live_sha 2>/dev/null || true)"
    fi
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        [ -f "$task_file" ] || continue
        report_file=$(resolve_report_file "$(basename "$task_file" .yaml)" 2>/dev/null || true)
        report_origin="$(dm_signal_report_deploy_sha "$report_file" origin 2>/dev/null || true)"
        report_live="$(dm_signal_report_deploy_sha "$report_file" live 2>/dev/null || true)"
        [ -n "$origin_sha" ] || origin_sha="$report_origin"
        [ -n "$live_sha" ] || live_sha="$report_live"
    done

    local smoke_script="$SCRIPT_DIR/scripts/gates/gate_dm_signal_production_smoke.sh"
    local smoke_output smoke_rc=0 log_checks
    if [ ! -x "$smoke_script" ]; then
        echo "  [CRITICAL] smoke helper is not executable: $smoke_script"
        smoke_output="BLOCK: smoke_helper_missing"
        smoke_rc=1
    else
        smoke_output=$(bash "$smoke_script" "$CMD_ID" \
            --origin-sha "$origin_sha" --live-sha "$live_sha" 2>&1) || smoke_rc=$?
    fi
    printf '%s\n' "$smoke_output"
    log_checks=$(printf '%s' "$smoke_output" | tr '\n' ' ' | tr -cd '[:print:]' | sed 's/"/'"'"'/g')
    if [ "$smoke_rc" -eq 0 ]; then
        append_line_locked "$LOG_DIR/gate_fire_log.yaml" \
            "- ts: \"$(date '+%Y-%m-%dT%H:%M:%S')\", file: \"${CMD_ID}\", gate: \"dm_signal_production_smoke\", result: PASS, detector: \"dm_signal_production_smoke\", checks: \"detector_fp_rate=tracked ${log_checks}\""
        echo "  dm-signal production smoke: PASS"
        return 0
    fi

    append_line_locked "$LOG_DIR/gate_fire_log.yaml" \
        "- ts: \"$(date '+%Y-%m-%dT%H:%M:%S')\", file: \"${CMD_ID}\", gate: \"dm_signal_production_smoke\", result: FAIL, detector: \"dm_signal_production_smoke\", checks: \"detector_fp_rate=tracked ${log_checks}\""
    echo "  [CRITICAL] dm-signal production smoke: BLOCK"
    return 1
}

# ─── 必須フラグ構築 ───
ALWAYS_REQUIRED=("archive" "lesson")

# Numbered Shogun commands must bind completion to their parent SSOT, purpose,
# and complete AC coverage. Direct cmd_karo_* hotfixes retain their contract.
if ! python3 "$SCRIPT_DIR/scripts/lib/parent_cmd_contract.py" "$CMD_ID" --root "$SCRIPT_DIR"; then
    echo "GATE BLOCK: parent_cmd_contract"
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "parent_cmd_contract")"
    exit 1
fi

# The post-CLEAR workflow consumes SG7 as its single information source.
# Therefore CLEAR must never be published before that exact bundle exists and
# validates.  Otherwise archive_completed replaces the current report with an
# archive symlink and /cmd-complete receives an impossible instruction.
# karo_direct起源cmd(CMD_ID=cmd_karo_*)は通常SG7を持たないためlegacy fallbackを
# 維持する。一方、正式レビューでSG7が生成済みならcmd_karo_*でもその正本を消費し、
# worker再配備後にtask検出が0件でもcompletion generationを失わない。
_sg7_bundle="$GATES_DIR/sg7_bundle.json"
if [ -f "$SCRIPT_DIR/scripts/cmd_complete.sh" ] \
    && { [[ "$CMD_ID" != cmd_karo_* ]] || [ -f "$_sg7_bundle" ]; }; then
    if [ ! -f "$SCRIPT_DIR/scripts/review_bundle.py" ] \
        || ! _SG7_SPEC_JSON=$(python3 "$SCRIPT_DIR/scripts/review_bundle.py" consume \
            --cmd "$CMD_ID" --bundle "$_sg7_bundle" --expect-verdict APPROVE); then
        echo "GATE BLOCK: sg7_bundle_missing_or_invalid"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "sg7_bundle_missing_or_invalid")"
        exit 1
    fi
    load_validated_sg7_context "$_sg7_bundle" "$_SG7_SPEC_JSON"
    if ! resolve_sg7_completion_identity "$_sg7_bundle"; then
        echo "GATE BLOCK: sg7_completion_identity_invalid"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "sg7_completion_identity_invalid")"
        exit 1
    fi
fi

# task_type検出
read -r HAS_RECON HAS_IMPLEMENT <<< "$(detect_task_types "$CMD_ID")"

CONDITIONAL=()
if [ "$HAS_RECON" = "true" ]; then
    CONDITIONAL+=("report_merge")
fi
if [ "$HAS_IMPLEMENT" = "true" ]; then
    CONDITIONAL+=("review_gate")
fi

# A review_gate.done marker alone is insufficient: gunshi LGTM and karo ACCEPT
# must bind to the exact same report content+commit fingerprint.
if [ "$HAS_IMPLEMENT" = "true" ]; then
    source "$SCRIPT_DIR/scripts/lib/review_approval.sh"
    mapfile -t _two_phase_reports < <(PROJECT_ROOT="$SCRIPT_DIR" review_resolve_reports "$CMD_ID")
    if ! review_all_reports_ready "$CMD_ID" "${_two_phase_reports[@]}" \
        && ! review_gate_manifest_ready "$CMD_ID" "${_two_phase_reports[@]}"; then
        echo "GATE BLOCK: review_two_phase_pending (every report requires matching gunshi LGTM + karo ACCEPT)"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "review_two_phase_pending")"
        exit 1
    fi
    # karo_direct起源cmd(CMD_ID=cmd_karo_*)はSG7バンドルをスキップしたため
    # SHOGUN_COMPLETION_GENERATIONが未設定のまま。review_two_phase確認済み
    # report群のfingerprintを束ねたhashをgeneration代替として採用する
    # (cmd_karo_hotfix_karo_direct_gate_bypass_20260807)。
    if [[ "$CMD_ID" == cmd_karo_* ]] && [ -z "${SHOGUN_COMPLETION_GENERATION:-}" ]; then
        _karo_direct_generation=$(PROJECT_ROOT="$SCRIPT_DIR" review_manifest_fingerprint "${_two_phase_reports[@]}") || _karo_direct_generation=""
        if [[ ! "$_karo_direct_generation" =~ ^[0-9a-f]{64}$ ]]; then
            echo "GATE BLOCK: ${CMD_ID}:karo_direct_completion_generation_invalid"
            append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "karo_direct_completion_generation_invalid")"
            exit 1
        fi
        export SHOGUN_COMPLETION_GENERATION="$_karo_direct_generation"
    fi
    if [[ "$CMD_ID" == cmd_karo_* ]]; then
        _karo_reviewed_at=$(resolve_karo_reviewed_at "$CMD_ID" "$SCRIPT_DIR" "${_two_phase_reports[@]}" 2>&1) || {
            echo "GATE BLOCK: ${CMD_ID}:karo_reviewed_at_invalid: ${_karo_reviewed_at}"
            append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "karo_reviewed_at_invalid")"
            exit 1
        }
        export SG7_REVIEWED_AT="$_karo_reviewed_at"
    fi
fi

ALL_GATES=("${ALWAYS_REQUIRED[@]}" "${CONDITIONAL[@]}")

# cmd_407: gate_metrics拡張用のtask_type/model/bloom_level収集
IFS=$'\t' read -r GATE_TASK_TYPE GATE_MODEL GATE_BLOOM_LEVEL <<< "$(collect_gate_metrics_extra "$CMD_ID")"
GATE_INJECTED_LESSONS="$(collect_injected_lessons "$CMD_ID")"
CMD_TITLE="$(collect_cmd_title "$CMD_ID")"
CMD_CHANGED_FILES="$(get_cmd_changed_files "$CMD_ID" || true)"
if [ -z "$CMD_CHANGED_FILES" ] && [ "${SG7_DIRECT_REPORT_SPEC:-false}" = "true" ]; then
    CMD_CHANGED_FILES="$(collect_report_modified_files || true)"
fi
GATE_FIRST_MODEL_METRIC="$(build_first_gate_model_metric)"

# ─── cmd_776 B層: 報告YAML自動正規化（auto-draft前に実行） ───
NORMALIZE_LOG="$SCRIPT_DIR/logs/normalize_report.log"
echo "Normalize report candidates (B層):"
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        normalize_exit=0
        normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) || normalize_exit=$?
        if [ "$normalize_exit" -eq 0 ]; then
            echo "  [INFO] ${ninja_name}: auto-fixed: ${normalize_output}"
            append_line_locked "$NORMALIZE_LOG" "$(date '+%Y-%m-%dT%H:%M:%S') [B層] ${CMD_ID} ${ninja_name}: ${normalize_output}"
        elif [ "$normalize_exit" -eq 1 ]; then
            echo "  ${ninja_name}: OK (no normalization needed)"
        else
            echo "  ${ninja_name}: ERROR — normalize_report.sh exit=${normalize_exit}: ${normalize_output}"
        fi
    fi
done
echo ""

# Normalization must not mutate an already-approved artifact. Recheck the
# exact final bytes before any later gate can CLEAR.
if [ "$HAS_IMPLEMENT" = "true" ] \
    && ! review_all_reports_ready "$CMD_ID" "${_two_phase_reports[@]}" \
    && ! review_gate_manifest_ready "$CMD_ID" "${_two_phase_reports[@]}"; then
    echo "GATE BLOCK: review_fingerprint_changed_after_normalize"
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "review_fingerprint_changed_after_normalize")"
    exit 1
fi

# ─── context freshness doc-lane diagnostics ───
# context freshness は本体クローズの直列条件にしない。完了結果を遅らせず、
# CLEAR後の非同期doc laneで警告と安全な更新候補を将軍へ通知する。
#
# 無関係cmd誤BLOCK0の設計: (1) project定義(DM_SIGNAL_CONTEXT_PATHS/
# INFRA_CONTEXT_PATHS)を持つinfra/dm-signalのみ対象、他projectは無条件通過。
# (2) 相関判定はcommit subjectが"${CMD_ID}:"で厳密に始まる場合のみ一致とし、
# 部分文字列衝突を避ける。(3) 自分自身の変更が既存contextに未反映の場合のみ
# BLOCKし、他cmd由来の残存ALERTでは無関係cmdを止めない。
# check自体がtimeout/エラーで未確定の場合はBLOCKせずWARNに留める
# (システム全体のスループットをinfra flakinessで止めない。個別timeout緩和は
# しない=check-failedは可視化するがBLOCK判定には使わないという意図的な設計)。
check_context_freshness_own_commit() {
    local cmd_id="$1"
    local check_script="$SCRIPT_DIR/scripts/context_freshness_check.sh"
    [ -f "$check_script" ] || return 0

    # Test-only commits do not change runtime or operational knowledge.  At
    # this point every report is immutable and fingerprint-verified, so its
    # files_modified list is the narrowest trustworthy scope boundary.  Do
    # not force meaningless core/ops context edits for tests, but keep the
    # existing fail-closed behavior when even one source path is present.
    local _all_reports_test_only=1 _saw_reported_path=0
    # The reviewed report is the commit identity SSOT.  Commit subjects are a
    # useful human-readable correlation key, but they are not contractual:
    # ordinary fixes may legitimately use "fix:" instead of "${cmd_id}:".
    # Keep every reviewed commit hash so an unreflected source commit cannot
    # evade the completion gate merely because its subject is generic.
    local -A _reported_commit_hashes=()
    local _scope_tf _scope_report _scope_path
    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for _scope_tf in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$_scope_tf" ] || { _all_reports_test_only=0; break; }
            _scope_report=$(awk '
                /^  report_path:/ {
                    sub(/^  report_path:[[:space:]]*/, "")
                    gsub(/^["'"'"']|["'"'"']$/, "")
                    print
                    exit
                }
            ' "$_scope_tf" 2>/dev/null)
            [ -n "$_scope_report" ] || { _all_reports_test_only=0; break; }
            [[ "$_scope_report" = /* ]] || _scope_report="$SCRIPT_DIR/$_scope_report"
            [ -f "$_scope_report" ] || { _all_reports_test_only=0; break; }

            local _scope_commit_hash
            _scope_commit_hash=$(awk '
                /^commit_hash:/ {
                    sub(/^commit_hash:[[:space:]]*/, "")
                    gsub(/^["'"'"']|["'"'"']$/, "")
                    print
                    exit
                }
            ' "$_scope_report" 2>/dev/null)
            if [[ "$_scope_commit_hash" =~ ^[0-9a-f]{7,40}$ ]]; then
                _reported_commit_hashes["$_scope_commit_hash"]=1
            fi

            while IFS= read -r _scope_path; do
                [ -n "$_scope_path" ] || continue
                _saw_reported_path=1
                case "$_scope_path" in
                    tests/*|*/tests/*|test_*.py|*/test_*.py|*_test.py|*/*_test.py|*.bats|*/conftest.py|conftest.py)
                        ;;
                    *)
                        _all_reports_test_only=0
                        break
                        ;;
                esac
            done < <(awk '
                /^files_modified:/ { in_files = 1; next }
                in_files && /^[^[:space:]-]/ { exit }
                in_files && /^[[:space:]]*-[[:space:]]+path:/ {
                    sub(/^[[:space:]]*-[[:space:]]+path:[[:space:]]*/, "")
                    gsub(/^["'"'"']|["'"'"']$/, "")
                    print
                }
            ' "$_scope_report")
            [ "$_all_reports_test_only" -eq 1 ] || break
        done
    else
        _all_reports_test_only=0
    fi
    if [ "$_all_reports_test_only" -eq 1 ] && [ "$_saw_reported_path" -eq 1 ]; then
        echo "  CONTEXT_NON_REFLECTION_BOUNDARY project=all reason=test_only approved_files_modified=test_only"
        echo "  [INFO] context freshness own-commit check skipped: approved files_modified are test-only"
        return 0
    fi

    local -A _cfoc_projects=()
    local _tf _proj
    if declare -p MATCHING_TASK_FILES >/dev/null 2>&1; then
        for _tf in "${MATCHING_TASK_FILES[@]}"; do
            [ -f "$_tf" ] || continue
            _proj=$(awk '
                /^  [a-zA-Z_].*:$/ { next }
                /^  project:/ { sub(/^  project:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }
            ' "$_tf" 2>/dev/null)
            [ -n "$_proj" ] && _cfoc_projects["$_proj"]=1
        done
    fi

    local _any_block=0
    local _proj_id
    for _proj_id in "${!_cfoc_projects[@]}"; do
        # GA-242: project名をハードコードで絞らない。context_freshness_check.shの
        # --cmd-commit-listはconfig/projects.yamlのcontext_file/context_files定義
        # がない project では自然に0行を返す(iter_context_filesがcurrent_project一致
        # なしでスキップ)ため、infra/dm-signal以外を明示的に除外する必要はない。
        # database等split外projectも同一機構で汎用的にカバーする。

        local commit_list check_status
        commit_list=$(CFC_PROJECT_OVERRIDE="$_proj_id" timeout 20 bash "$check_script" --cmd-commit-list "$cmd_id" 2>/dev/null)
        check_status=$?

        if [ "$check_status" -ne 0 ]; then
            echo "  [WARN] context_freshness own-commit check timeout/error (project=${_proj_id}). BLOCK skipped — 一次情報で確認: CFC_PROJECT_OVERRIDE=${_proj_id} bash scripts/context_freshness_check.sh --cmd-commit-list ${cmd_id}"
            continue
        fi

        if echo "$commit_list" | grep -q '^MISSING_SOURCE_COMMIT'; then
            local missing_marker_paths
            missing_marker_paths=$(echo "$commit_list" | awk -F'\t' '/^MISSING_SOURCE_COMMIT/{print $2}' | tr '\n' ' ')
            echo "  registered context source_commit marker missing (project=${_proj_id}): ${missing_marker_paths}"
            _any_block=1
        fi

        if echo "$commit_list" | grep -q '^CHECK_FAILED'; then
            local failed_paths
            failed_paths=$(echo "$commit_list" | awk -F'\t' '/^CHECK_FAILED/{print $2}' | tr '\n' ' ')
            echo "  [WARN] context freshness check未確定(timeout/returncode): ${failed_paths}(project=${_proj_id})。BLOCK判定には使用しない"
        fi

        local own_hits subject_hits hash_hits _reported_hash
        subject_hits=$(echo "$commit_list" | awk -F'\t' -v cmd="${cmd_id}:" 'index($3, cmd) == 1 {print}')
        hash_hits=""
        for _reported_hash in "${!_reported_commit_hashes[@]}"; do
            hash_hits+=$(echo "$commit_list" | awk -F'\t' -v hash="$_reported_hash" '
                index(hash, $2) == 1 || index($2, hash) == 1 {print}
            ')
            hash_hits+=$'\n'
        done
        own_hits=$(printf '%s\n%s\n' "$subject_hits" "$hash_hits" | awk 'NF && !seen[$0]++')
        if [ -n "$own_hits" ]; then
            echo "  own commit found in unreflected split context backlog (project=${_proj_id}):"
            while IFS=$'\t' read -r _rel_path _hash _subject; do
                [ -n "$_rel_path" ] || continue
                # Level5 input: emit a stable, machine-readable update candidate before
                # blocking.  The next actor receives the exact context/hash pair instead
                # of having to rediscover it from the dashboard-wide backlog.
                printf '  CONTEXT_UPDATE_CANDIDATE project=%s context=%s source_commit=%s reason=own_reviewed_commit\n' \
                    "$_proj_id" "$_rel_path" "$_hash"
                # Level5 input: provide the complete safe setter invocation, including
                # the reason/evidence contract.  The actor must still review and commit
                # the context change, but no longer has to invent boundary metadata.
                printf "  CONTEXT_UPDATE_COMMAND bash scripts/context_source_commit_set.sh %q %q %q %q\n" \
                    "$_rel_path" "$_hash" "${cmd_id} reviewed source boundary" \
                    "cmd_complete_gate project=${_proj_id} context=${_rel_path} commit=${_hash}"
                echo "    - ${_rel_path} (${_hash}: ${_subject})"
            done <<< "$own_hits"
            _any_block=1
        fi
    done

    return "$_any_block"
}

# ─── 忍者報告からlesson_candidate自動draft登録 ───
# 循環防止: 前回BLOCKがdraft_lessons起因なら自動draft生成をスキップ
_prev_block_reason=""
if [ -f "$GATE_METRICS_LOG" ]; then
    _prev_block_reason=$(grep "^[^\t]*\t${CMD_ID}\tBLOCK\t" "$GATE_METRICS_LOG" | tail -1 | cut -f4)
fi
echo "Auto-draft lesson candidates:"
if [[ "$_prev_block_reason" == draft_lessons* ]]; then
    echo "  SKIP: 前回BLOCK理由=draft_lessons。循環防止のため自動draft生成をスキップ"
else
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        if GATE_BLOCK_REASON="$_prev_block_reason" bash "$SCRIPT_DIR/scripts/auto_draft_lesson.sh" "$report_file" 2>&1; then
            true
        else
            echo "  [INFO] auto_draft_lesson.sh failed for ${ninja_name} (non-blocking)"
        fi
    else
        echo "  ${ninja_name}: no report file"
    fi
done
fi  # draft_lessons循環防止の閉じ
echo ""

# ─── preflight: ゲートフラグ自動生成（冪等） ───
preflight_gate_flags "$CMD_ID"

# cmd_test_speed などの測定用IDはtask YAMLにもcmdキューにも存在しない。
# その場合、報告YAML/通知/アーカイブ系の全走査は意味を持たず、測定値だけを汚す。
if [ "${MATCHING_TASK_FILES_INITIAL_COUNT:-0}" -eq 0 ] && ! cmd_entry_exists "$CMD_ID" && ! has_parent_cmd_report "$CMD_ID"; then
    echo "[L1] No-task benchmark fast path:"
    echo "  no task files and no cmd entry; report-dependent gates skipped"
    echo ""
    echo "GATE CLEAR: cmd完了許可"
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tCLEAR\tno_task_benchmark_fast_path\t%s\t%s\t%s\t%s\t%s\tunknown\tunknown\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_FIRST_MODEL_METRIC")"
    print_matching_task_files_summary
    exit 0
fi

# ─── 緊急override確認 ───
if [ -f "$GATES_DIR/emergency.override" ]; then
    echo "GATE CLEAR (緊急override): ${CMD_ID}の全ゲートをバイパス"
    log_skill_execution_pass "cmd-complete" "cmd_complete_gate" "$CMD_ID"
    for gate in "${ALL_GATES[@]}"; do
        echo "  ${gate}: OVERRIDE"
    done
    send_high_notification "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  [INFO] gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID"
    send_clear_notifications_once "$CMD_ID" "GATE CLEAR - emergency override immediate"
    append_changelog "$CMD_ID"
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tOVERRIDE\temergency_override\t%s\t%s\t%s\t%s\t%s\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_FIRST_MODEL_METRIC")"
    update_karo_workaround_resolutions "$CMD_ID" || echo "  [WARN] karo workaround resolution update failed (non-blocking)"
    capture_completed_rework_event "$CMD_ID" || echo "  [WARN] rework event capture failed (non-blocking)"
    bash "$SCRIPT_DIR/scripts/rotate_gate_metrics.sh" 2>/dev/null || true
    if append_lesson_tracking "$CMD_ID" "OVERRIDE" 2>&1; then
        true
    else
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
    fi

    # ─── lesson_merge自動実行（ベストエフォート） ───
    echo ""
    echo "Lesson merge (auto):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_merge.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_merge.sh" 2>&1; then
            echo "  [GATE] lesson_merge: OK"
        else
            echo "  [GATE] lesson_merge: SKIP (non-blocking)"
        fi
    else
        echo "  [GATE] lesson_merge: SKIP (script not found)"
    fi

    run_skill_script_refs_check
    write_l6_horizontal_level5_insights "$CMD_ID"
    echo ""
    echo "Insight auto-triage (cmd-related):"
    # cmd_karo_hotfix_post_clear_fail_open_20260725 (AC1): 通常GATE CLEAR経路と同型の
    # 構造欠陥(1ステップの失敗が後続の全ステップを道連れにする)がemergency override
    # 経路にも存在したため同じくfail-openにする。
    if ! auto_resolve_cmd_related_insights "$CMD_ID"; then
        echo "  [WARN] Insight auto-triage failed (non-blocking, GATE CLEAR continues)"
    fi

    # ─── GATE CLEAR時 自動通知（ベストエフォート） ───
    echo ""
    echo "Auto-notification (GATE CLEAR - emergency override):"

    # dashboard_update removed (殿裁定2026-08-17: dashboardは誰も使っていない。
    # flock競合で最大124s遅延のボトルネックだったため除外)
    echo "  dashboard_update: SKIP (removed by lord ruling 2026-08-17)"

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    if gist_output=$(bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once 2>&1); then
        echo "  gist_sync: OK"
        if echo "$gist_output" | grep -qi "error\|fail"; then
            echo "  [ERROR] GIST_SYNC_VERIFY: success exit but output contains error: $gist_output"
        fi
    else
        echo "  [INFO] gist_sync: WARN (sync failed, non-blocking)" >&2
    fi

    # ntfy_cmd（CLEAR直後に送信済み。ここでは未送信時だけ補完）
    send_clear_notifications_once "$CMD_ID" "GATE CLEAR - emergency override"
    echo "Gunshi gate_result reflux (GATE CLEAR - emergency override):"
    if [ -f "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" "$CMD_ID" "CLEAR" 2>&1; then
            echo "  gunshi_gate_reflux: OK"
        else
            echo "  [INFO] gunshi_gate_reflux: WARN (non-blocking)"
        fi
    else
        echo "  SKIP (gunshi_gate_reflux.sh not found)"
    fi
    send_clear_notifications_once "$CMD_ID" "GATE CLEAR - emergency override shogun/karo"

    # ─── 掲示板自動投稿（GATE CLEAR時、将軍が/clear後に即把握できるよう） ───
    echo ""
    echo "Bulletin board (GATE CLEAR - emergency override):"
    _blt_title_eo=""
    _blt_title_eo=$(awk -v cmd="$CMD_ID" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        cur_id == cmd && /title:/ { sub(/.*title:[[:space:]]*"?/, ""); sub(/"?$/, ""); print; exit }
    ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)
    if BULLETIN_NOTIFY=karo,gunshi timeout 10 bash "$SCRIPT_DIR/scripts/bulletin_write.sh" "GATE CLEAR ${CMD_ID}: ${_blt_title_eo:-完了}" false 2>/dev/null; then
        echo "  bulletin: OK"
    else
        echo "  [INFO] bulletin: WARN (failed, non-blocking)" >&2
    fi

    echo ""
    echo "Lesson feedback recording (pre-impact scan - emergency override):"
    record_lesson_feedback_for_cmd
    update_lesson_impact_tsv "$CMD_ID" "CLEAR" 2>&1 || echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)"
    queue_lesson_impact_followup

    # cmd_531: AC6 — GATE CLEAR時に教訓有効率スキャン+自動退役（緊急override時も実行）
    echo ""
    echo "Lesson effectiveness scan (GATE CLEAR - emergency override):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" --project all 2>&1; then
            echo "  lesson_deprecation_scan: OK"
        else
            echo "  [INFO] lesson_deprecation_scan: WARN (scan failed, non-blocking)"
        fi
    else
        echo "  SKIP (lesson_deprecation_scan.sh not found)"
    fi

    # ─── git push（GATE CLEAR後、殿裁定2026-03-24: GATE CLEARしたcommitは家老がpush） ───
    echo ""
    echo "Git push (post-GATE CLEAR - emergency override):"
    push_task_repositories "${MATCHING_TASK_FILES[@]}"

    # ─── Gunshi gate_result reflux 2回目（GATE CLEAR後 最終ステップ, cmd_3370, emergency override） ───
    echo ""
    echo "Gunshi gate_result reflux (post-GATE CLEAR 2nd run - emergency override):"
    if [ -f "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" "$CMD_ID" "CLEAR" 2>&1; then
            echo "  gunshi_gate_reflux: OK"
        else
            echo "  [INFO] gunshi_gate_reflux: WARN (non-blocking)"
        fi
    else
        echo "  SKIP (gunshi_gate_reflux.sh not found)"
    fi

    echo ""
    echo "Async completion wait (pre-exit):"
    wait || true
    echo "  async jobs: drained"

    exit 0
fi

# ─── 各フラグの状態確認 ───
MISSING_GATES=()
BLOCK_REASONS=()
ALL_CLEAR=true

if [ "${MATCHING_TASK_FILES_INITIAL_COUNT:-0}" -eq 0 ] && ! cmd_entry_exists "$CMD_ID" && has_parent_cmd_report "$CMD_ID"; then
    level_heading "[L1]" "No-task parent report validation:"
    while IFS=$'\t' read -r report_file report_status report_detail; do
        [ -n "$report_file" ] || continue
        case "$report_status" in
            OK)
                echo "  $(basename "$report_file"): OK (${report_detail})"
                ;;
            *)
                echo "  [CRITICAL] $(basename "$report_file"): ${report_detail}"
                record_block_reason "no_task_parent_report:$(basename "$report_file"):${report_status}"
                ALL_CLEAR=false
                ;;
        esac
    done < <(REPORTS_DIR="$SCRIPT_DIR/queue/reports" CMD_ID="$CMD_ID" python3 - <<'PY'
import glob
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

reports_dir = os.environ["REPORTS_DIR"]
cmd_id = os.environ["CMD_ID"]

def iter_check_results(value):
    if isinstance(value, dict):
        for nested in value.values():
            yield from iter_check_results(nested)
        return
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                yield str(item.get("result", "") or "").strip()
            else:
                yield ""
        return
    yield ""

candidates = []
for path in sorted(glob.glob(os.path.join(reports_dir, "*.yaml"))):
    try:
        with open(path, encoding="utf-8") as f:
            report = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(report, dict):
        continue
    if str(report.get("parent_cmd") or "").strip() != cmd_id:
        continue

    # A direct training command may leave an abandoned round template beside
    # the later submitted report (for example r2 pending written before r1
    # completed).  Validate the newest filesystem state per worker, not every
    # historical round filename; lexical r1/r2 order is not submission order.
    worker = str(report.get("worker_id") or report.get("task_id") or path).strip()
    candidates.append((os.stat(path).st_mtime_ns, path, worker, report))

latest_by_worker = {}
for candidate in candidates:
    key = candidate[2]
    previous = latest_by_worker.get(key)
    if previous is None or candidate[:2] > previous[:2]:
        latest_by_worker[key] = candidate

for _, path, _, report in sorted(latest_by_worker.values(), key=lambda item: item[1]):
    verdict = str(report.get("verdict", "") or "").strip()
    binary_checks = report.get("binary_checks")
    results = list(iter_check_results(binary_checks)) if binary_checks is not None else []
    bad_results = [
        result for result in results
        if result.lower() not in ("yes", "pass", "true")
    ]
    if verdict == "FAIL":
        print(f"{path}\tFAIL_VERDICT\tverdict=FAIL")
    elif verdict not in ("PASS", "PASS_NO_IMPROVEMENT"):
        print(f"{path}\tBAD_VERDICT\tverdict={verdict or 'MISSING'}")
    elif not results:
        print(f"{path}\tBINARY_CHECKS_MISSING\tbinary_checks missing")
    elif bad_results:
        print(f"{path}\tBINARY_CHECKS_FAIL\tbinary_checks has non-PASS results")
    else:
        print(f"{path}\tOK\tparent report checks pass")
PY
)
    echo ""
fi

level_heading "[L1]" "Gate check: ${CMD_ID}"
echo "  Framework: [L1] Existence | [L2] Substantive | [L3] Integration"
echo "  Required: ${ALL_GATES[*]}"
if [ ${#CONDITIONAL[@]} -gt 0 ]; then
    echo "  Conditional: ${CONDITIONAL[*]} (task_type: recon=${HAS_RECON}, implement=${HAS_IMPLEMENT})"
fi
echo ""

for gate in "${ALL_GATES[@]}"; do
    # cmd_1314: DEFERRED_GATESに含まれるgateはcheck loopでスキップ（GATE CLEAR後に実行）
    is_deferred=false
    for dg in "${DEFERRED_GATES[@]}"; do
        if [ "$gate" = "$dg" ]; then
            is_deferred=true
            break
        fi
    done
    if [ "$is_deferred" = true ]; then
        echo "  ${gate}: DEFERRED (will run after GATE CLEAR)"
        continue
    fi

    done_file="$GATES_DIR/${gate}.done"

    if [ -f "$done_file" ]; then
        detail=$(head -1 "$done_file" 2>/dev/null)
        if [ -n "$detail" ]; then
            echo "  ${gate}: DONE (${detail})"
        else
            echo "  ${gate}: DONE"
        fi
    else
        if [ "$gate" = "lesson" ]; then
            echo "  WARN: ${gate}: MISSING ← lesson_write.sh登録待ち"
            notify_karo_lesson_registration_reminder "$CMD_ID" "gate_check"
        else
            echo "  [CRITICAL] ${gate}: MISSING ← 未完了"
            MISSING_GATES+=("$gate")
            record_block_reason "missing_gate:${gate}"
            ALL_CLEAR=false
        fi
    fi
done

# ─── 報告YAML存在チェック（cmd_1192: タスクあり報告なしをBLOCK, GP-026: 活動中忍者はWAIT） ───
level_heading "[L1]" "Report YAML existence check:"
REPORT_TASK_COUNT=0
REPORT_FOUND_COUNT=0
REPORT_MISSING_FILES=()
REPORT_WAIT_NINJAS=()
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    REPORT_TASK_COUNT=$((REPORT_TASK_COUNT + 1))
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ -f "$report_file" ]; then
        REPORT_FOUND_COUNT=$((REPORT_FOUND_COUNT + 1))
        echo "  ${ninja_name}: OK ($(basename "$report_file"))"
        notify_gunshi_for_report "$ninja_name" "$report_file" "$CMD_ID"
    else
        # GP-026 B案(cmd_1332): 活動中の3状態だけWAIT。idleは既に非稼働の
        # stale taskであり、180秒待っでも報告は生成されない。
        ninja_status=$(grep -E '^\s+status:' "$task_file" | head -1 | sed 's/.*status:[[:space:]]*//' | tr -d "'" | tr -d '"')
        missing_action=$(classify_missing_report_status "$ninja_status")
        if [ "$missing_action" = "skip" ]; then
            echo "  [SKIP] ${ninja_name}: 報告YAML未着（status=${ninja_status}、再配備/失敗済みタスクのため待機対象外）"
        elif [ "$missing_action" = "wait" ]; then
            REPORT_WAIT_NINJAS+=("$ninja_name")
            echo "  [WAIT] ${ninja_name}: 報告YAML未着（status=${ninja_status}、リトライ待ち）"
        else
            REPORT_MISSING_FILES+=("$(basename "$report_file")")
            echo "  [CRITICAL] ${ninja_name}: MISSING ← 報告YAML不在(status=${ninja_status}): $(basename "$report_file")"
        fi
    fi
done

# GP-026 B案(cmd_1332): WAIT忍者がいる場合はretry 3回×60秒=最大180秒
if [ "${#REPORT_WAIT_NINJAS[@]}" -gt 0 ]; then
    WAIT_MAX_RETRIES=3
    WAIT_INTERVAL=60
    for wait_retry in $(seq 1 $WAIT_MAX_RETRIES); do
        # 未解決WAIT忍者がいるか確認
        STILL_WAITING=()
        for ninja_name in "${REPORT_WAIT_NINJAS[@]}"; do
            report_file=$(resolve_report_file "$ninja_name")
            if [ ! -f "$report_file" ]; then
                STILL_WAITING+=("$ninja_name")
            fi
        done
        [ "${#STILL_WAITING[@]}" -eq 0 ] && break

        echo "  [WAIT] retry ${wait_retry}/${WAIT_MAX_RETRIES}: ${#STILL_WAITING[@]}名の報告待ち。${WAIT_INTERVAL}秒後に再チェック..."
        sleep "$WAIT_INTERVAL"

        for ninja_name in "${STILL_WAITING[@]}"; do
            report_file=$(resolve_report_file "$ninja_name")
            if [ -f "$report_file" ]; then
                REPORT_FOUND_COUNT=$((REPORT_FOUND_COUNT + 1))
                echo "  ${ninja_name}: OK (retry ${wait_retry}で発見: $(basename "$report_file"))"
                notify_gunshi_for_report "$ninja_name" "$report_file" "$CMD_ID"
            elif [ "$wait_retry" -eq "$WAIT_MAX_RETRIES" ]; then
                REPORT_MISSING_FILES+=("$(basename "$report_file")")
                echo "  [CRITICAL] ${ninja_name}: MISSING ← retry ${WAIT_MAX_RETRIES}回後も報告YAML不在: $(basename "$report_file")"
            fi
        done
    done
fi

if [ "$REPORT_TASK_COUNT" -ge 1 ] && [ "$REPORT_FOUND_COUNT" -eq 0 ]; then
    echo "  [CRITICAL] BLOCK: タスク${REPORT_TASK_COUNT}件に対して報告YAML 0件"
    for missing_f in "${REPORT_MISSING_FILES[@]}"; do
        record_block_reason "report_yaml_missing:${missing_f}"
    done
    ALL_CLEAR=false
elif [ "$REPORT_TASK_COUNT" -gt "$REPORT_FOUND_COUNT" ] && [ "$REPORT_FOUND_COUNT" -gt 0 ]; then
    echo "  [WARNING] タスク${REPORT_TASK_COUNT}件中、報告YAML ${REPORT_FOUND_COUNT}件のみ（一部不在、非BLOCK）"
elif [ "$REPORT_TASK_COUNT" -eq 0 ]; then
    echo "  (no tasks found for this cmd)"
else
    echo "  OK (全${REPORT_TASK_COUNT}件の報告YAML確認済み)"
fi

# ─── 報告YAMLフォーマット検証（cmd_1202: タスクYAML非依存・ディレクトリ直接スキャン） ───
# バイパス経路防止:
#   1. タスクYAMLに明示されたreport_filename（custom名含む）
#   2. 慣例名 *_report_${CMD_ID}.yaml の直接スキャン
# の両方を検証対象に含める。片側だけでは custom report_filename が素通りする。
level_heading "[L1]" "Report format validation (direct scan):"
REPORT_FORMAT_CHECKED=0
REPORT_FORMAT_FAILED=0
declare -A REPORT_FORMAT_SEEN=()
validate_report_format_file() {
    local report_file="$1"

    [ -n "$report_file" ] || return 0
    [ -f "$report_file" ] || return 0
    if [ -n "${REPORT_FORMAT_SEEN["$report_file"]+x}" ]; then
        return 0
    fi

    REPORT_FORMAT_SEEN["$report_file"]=1
    REPORT_FORMAT_CHECKED=$((REPORT_FORMAT_CHECKED + 1))
    "$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$report_file" 2>/dev/null || true
    local GATE_RC=0 GATE_STATUS
    # 遅延source: このfunctionが呼ばれた時だけ読み込み、cmd_complete_gate.shの
    # 大半のtest scaffold(cmd_gate_scaffold.bash等)が持つ最小scripts/lib契約を壊さない。
    # shellcheck source=scripts/lib/gate_report_format_classify.sh
    source "$SCRIPT_DIR/scripts/lib/gate_report_format_classify.sh"
    GATE_OUTPUT=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1) || GATE_RC=$?
    GATE_STATUS=$(gate_report_format_classify "$GATE_RC")
    # cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (AC1/AC2):
    # インフラ由来のsingle-flightタイムアウト(exit code 2)を品質FAILと機械的に区別する。
    # 1回だけ再試行し、それでも解消しなければ品質問題(report_format)とは別のreasonで
    # BLOCKし(検証未完了のまま素通りさせない)、ninjaへの誤った修正要求を防ぐ。
    # provenance: 本変更の実体はd1499a6a7で導入済み。
    if [ "$GATE_STATUS" = "INFRA_TIMEOUT" ]; then
        echo "  [INFO] $(basename "$report_file"): single-flightタイムアウト(インフラ由来)。1回再試行"
        GATE_RC=0
        GATE_OUTPUT=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1) || GATE_RC=$?
        GATE_STATUS=$(gate_report_format_classify "$GATE_RC")
    fi
    if [ "$GATE_STATUS" = "QUALITY_FAIL" ]; then
        REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
        echo "  [CRITICAL] $(basename "$report_file"): $GATE_OUTPUT"
        record_block_reason "report_format:$(basename "$report_file")"
        ALL_CLEAR=false
    elif [ "$GATE_STATUS" = "INFRA_TIMEOUT" ]; then
        REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
        echo "  [CRITICAL] $(basename "$report_file"): インフラ異常(single-flightロック競合)で2回連続timeout。品質問題ではない"
        record_block_reason "infra_timeout:$(basename "$report_file")"
        ALL_CLEAR=false
    else
        echo "  $(basename "$report_file"): PASS"
    fi
}

for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    validate_report_format_file "$report_file"
done

for report_file in "$SCRIPT_DIR/queue/reports/"*_report_${CMD_ID}.yaml; do
    [ -f "$report_file" ] || continue
    validate_report_format_file "$report_file"
done
if [ "$REPORT_FORMAT_CHECKED" -eq 0 ]; then
    echo "  (no report files found for ${CMD_ID})"
elif [ "$REPORT_FORMAT_FAILED" -eq 0 ]; then
    echo "  OK (全${REPORT_FORMAT_CHECKED}件フォーマット検証PASS)"
fi

# ─── related_lessons存在チェック（deploy_task.sh経由確認） ───
level_heading "[L1]" "Related lessons injection check:"
RL_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    RL_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)

    if grep -q '^\s*related_lessons:' "$task_file" 2>/dev/null; then
        has_rl_key="yes"
    else
        has_rl_key="no"
    fi

    if [ "$has_rl_key" = "yes" ]; then
        echo "  ${ninja_name}: OK (related_lessons present)"
    elif [ "$has_rl_key" = "no" ]; then
        echo "  [INFO] ${ninja_name}: related_lessonsキー欠落（deploy_task.sh経由でない可能性）"
    else
        echo "  [INFO] ${ninja_name}: related_lessons解析エラー"
    fi
done
if [ "$RL_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lessons_useful検証（related_lessonsあり→報告にlessons_useful必須） ───
level_heading "[L2]" "Lessons useful check:"
LESSON_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    # related_lessonsの有無をチェック（空リスト[]やnullは除外）
    # task:配下の2-space fieldだけを範囲にする。次フィールド以降のAC/standard_skillsを誤って教訓扱いしない。
    rl_count=$(awk '
        /^  related_lessons:/ { sec=1; next }
        sec && /^  [A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
        sec && /^  - id:/ { c++ }
        END { print c+0 }
    ' "$task_file" 2>/dev/null)
    has_lessons=$([ "${rl_count:-0}" -gt 0 ] && echo "yes" || echo "no")

    if [ "$has_lessons" = "yes" ]; then
        LESSON_CHECKED=true
        ninja_name=$(basename "$task_file" .yaml)
        task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
        report_file=$(resolve_report_file "$ninja_name")

        if [ -f "$report_file" ]; then
            # lessons_useful検証: null/空/FILL_THIS/形式不正/ok (cmd_536+cmd_1045+cmd_1180)
            lr_status=$(awk '
                # lessons_useful: または lesson_referenced: セクション検出
                /^lessons_useful:/ {
                    val = $0; sub(/.*lessons_useful:[[:space:]]*/, "", val)
                    if (val == "null" || val == "~") { result = "null"; exit }
                    if (val == "" || val == "[]") { sec = "lu" }
                    else { sec = "lu" }
                    lu_found = 1; next
                }
                /^lesson_referenced:/ && !lu_found {
                    sec = "lr"; next
                }
                (sec == "lu" || sec == "lr") && /^[a-zA-Z]/ { sec = "" }
                # リスト要素 (- id: ...) を検出
                (sec == "lu" || sec == "lr") && /^[[:space:]]*- / {
                    item_count++
                    # FILL_THIS検出 (useful/reason)
                    if ($0 ~ /useful:[[:space:]]*FILL_THIS/ || $0 ~ /reason:[[:space:]]*FILL_THIS/) {
                        fill_this = 1
                    }
                }
                # useful: フィールド（リスト要素の子）
                (sec == "lu" || sec == "lr") && /^[[:space:]]+useful:/ {
                    u = $0; sub(/.*useful:[[:space:]]*/, "", u); gsub(/^["'"'"']+|["'"'"']+$/, "", u)
                    if (u == "FILL_THIS") { fill_this = 1 }
                    else if (u == "true" || u == "false") { bool_count++ }
                    else if (u == "" || u == "null" || u == "~") { null_useful = 1 }
                    else { non_bool = 1 }
                }
                # reason: FILL_THIS検出
                (sec == "lu" || sec == "lr") && /^[[:space:]]+reason:[[:space:]]*FILL_THIS/ { fill_this = 1 }
                END {
                    if (result != "") { print result; exit }
                    if (item_count == 0) { print "empty"; exit }
                    if (fill_this) { print "fill_this_remaining"; exit }
                    if (null_useful || non_bool) { print "invalid_format"; exit }
                    if (bool_count > 0) { print "ok"; exit }
                    if (item_count > 0) { print "invalid_format"; exit }
                    print "empty"
                }
            ' "$report_file" 2>/dev/null)

            if [ "$lr_status" = "ok" ]; then
                if lesson_set_status=$(validate_lesson_feedback_set "$task_file" "$report_file" 2>&1); then
                    echo "  ${ninja_name}: OK (lessons_useful present and ${lesson_set_status})"
                else
                    echo "  [CRITICAL] ${ninja_name}: NG ← lessons_useful評価集合がtask契約と不一致 (${lesson_set_status})"
                    record_block_reason "${ninja_name}:lesson_feedback_set_mismatch:${lesson_set_status}"
                    ALL_CLEAR=false
                fi
            elif [ "$lr_status" = "null" ]; then
                # cmd_536 AC4: lessons_useful=null(明示的未記入)をBLOCK
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulが未記入(null)。教訓の有用性を記入せよ"
                record_block_reason "${ninja_name}:null_lessons_useful"
                ALL_CLEAR=false
            elif [ "$lr_status" = "fill_this_remaining" ]; then
                # cmd_1180: FILL_THISテンプレートが未置換
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulにFILL_THISが残っている。各教訓のusefulをtrue/falseに、reasonを理由文に書き換えよ"
                record_block_reason "${ninja_name}:fill_this_remaining"
                ALL_CLEAR=false
            elif [ "$lr_status" = "invalid_format" ]; then
                # cmd_1045: lessons_usefulの要素形式が不正（文字列/useful欠落/non-bool）
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulの形式が不正。各要素は以下の形式で記載せよ:"
                echo "    lessons_useful:"
                echo "      - id: L028"
                echo "        useful: true"
                echo "        reason: '理由を記載'"
                record_block_reason "${ninja_name}:invalid_lessons_useful_format"
                ALL_CLEAR=false
            else
                # related_lessonsからlesson IDを抽出してメッセージに表示
                rl_ids=$(awk '
                    /^  related_lessons:/ { sec=1; next }
                    sec && /^  [A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
                    sec && /id:/ {
                        val=$0
                        sub(/.*id:[[:space:]]*/, "", val)
                        gsub(/[" \t]/, "", val)
                        if (c++) printf ","
                        printf "%s", val
                    }
                ' "$task_file" 2>/dev/null)
                [ -z "$rl_ids" ] && rl_ids="(parse_error)"
                handle_empty_lessons_useful_check "$ninja_name" "$task_type" "$rl_ids"
            fi
        else
            echo "  ${ninja_name}: SKIP (report not found)"
        fi
    fi
done
if [ "$LESSON_CHECKED" = false ]; then
    echo "  (no tasks with related_lessons for this cmd)"
fi

# ─── reviewed:false残存チェック（廃止: cmd_533でpush型に移行） ───
# reviewed:falseフィールドはdeploy_task.shで付与されなくなった（detail埋込に移行）
# 旧タスクYAMLにreviewed:falseが残存していても後方互換でブロックしない
level_heading "[L1]" "Lesson reviewed check: SKIP (push型移行済み — cmd_533)"

# ─── task.ac_version再計算（deploy_task.shと同一canonical AC fingerprint） ───
# deploy時に保存したac_versionは、完了時点のtask YAMLそのものから再計算する。
# report.ac_version_readとの照合だけでは、配備後にtask.acceptance_criteriaを
# 追加・変更しても同じ保存値をreportへ返せるためstale ACを検出できない。
compute_task_ac_version() {
    local task_file="$1"
    python3 "$SCRIPT_DIR/scripts/lib/report_gate_contract.py" ac-version "$task_file"
}

check_task_ac_version_integrity() {
    local task_file="$1" ninja_name="$2"
    local saved_ac_version computed_ac_version
    saved_ac_version=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
    case "${saved_ac_version,,}" in
        ""|null|none|"~")
            echo "  [INFO] ${ninja_name}: task.ac_version未設定のため再計算照合SKIP"
            return 0
            ;;
        [0-9]*)
            if [[ "$saved_ac_version" =~ ^[0-9]+$ ]]; then
                echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${saved_ac_version}のため再計算照合SKIP"
                return 0
            fi
            ;;
    esac

    if ! computed_ac_version=$(compute_task_ac_version "$task_file"); then
        echo "  [CRITICAL] ${ninja_name}: ac_version再計算失敗"
        record_block_reason "${ninja_name}:ac_version_recompute_failed"
        return 1
    fi
    if [ "$saved_ac_version" != "$computed_ac_version" ]; then
        echo "  [CRITICAL] ${ninja_name}: NG ← task.ac_version stale (saved=${saved_ac_version}, computed=${computed_ac_version})"
        record_block_reason "${ninja_name}:ac_version_stale:task=${saved_ac_version}:computed=${computed_ac_version}"
        return 1
    fi
    echo "  ${ninja_name}: OK (task.ac_version=${saved_ac_version}, recomputed=${computed_ac_version})"
    return 0
}

# ─── ac_version照合（task.ac_version vs report.ac_version_read） ───
level_heading "[L3]" "AC version check:"
AC_VERSION_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    AC_VERSION_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)
    if ! check_task_ac_version_integrity "$task_file" "$ninja_name"; then
        ALL_CLEAR=false
    fi
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    # ac_version照合: field_getで取得→比較
    _acv_task=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
    _acv_read=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "ac_version_read" "")
    # normalize: 空/null/none → empty
    case "${_acv_task,,}" in ""|null|none|"~") _acv_task="" ;; esac
    case "${_acv_read,,}" in ""|null|none|"~") _acv_read="" ;; esac
    if [ -z "$_acv_task" ]; then
        acv_status="task_missing"
    elif [[ "$_acv_task" =~ ^[0-9]+$ ]]; then
        # legacy numeric → skip
        acv_status=$(printf 'legacy_skip\t%s\t%s' "$_acv_task" "${_acv_read:--}")
    elif [ -z "$_acv_read" ]; then
        acv_status=$(printf 'report_missing\t%s\t-' "$_acv_task")
    elif [ "$_acv_task" = "$_acv_read" ]; then
        acv_status=$(printf 'ok\t%s\t%s' "$_acv_task" "$_acv_read")
    else
        acv_status=$(printf 'mismatch\t%s\t%s' "$_acv_task" "$_acv_read")
    fi

    acv_kind=$(echo "$acv_status" | cut -f1)
    acv_task=$(echo "$acv_status" | cut -f2)
    acv_read=$(echo "$acv_status" | cut -f3)

    case "$acv_kind" in
        ok)
            echo "  ${ninja_name}: OK (ac_version task=${acv_task}, report=${acv_read})"
            ;;
        mismatch)
            echo "  [CRITICAL] ${ninja_name}: NG ← ac_version不一致 (task=${acv_task}, report=${acv_read})"
            record_block_reason "${ninja_name}:ac_version_mismatch:task=${acv_task}:report=${acv_read}"
            ALL_CLEAR=false
            ;;
        report_missing)
            echo "  [INFO] ${ninja_name}: ac_version_read未記載（task=${acv_task}）。後方互換として非BLOCK"
            ;;
        legacy_skip)
            echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${acv_task}のため照合SKIP（後方互換）"
            ;;
        task_missing)
            echo "  [INFO] ${ninja_name}: task.ac_version未設定のため照合SKIP"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: ac_version照合解析エラー（非BLOCK）"
            ;;
    esac
done
if [ "$AC_VERSION_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lesson_candidate検証（found:trueなのに未登録を防止） ───
level_heading "[L1]" "Lesson candidate check:"
LC_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    LC_CHECKED=true

    # lesson_candidateフィールドの検証 (awk: cmd_536+cmd_776+cmd_1180)
    lc_status=$(lesson_candidate_status "$report_file")

    case "$lc_status" in
        ok_false)
            echo "  ${ninja_name}: OK (lesson_candidate: found=false)"
            ;;
        ok_false_no_reason)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:false but no_lesson_reason is empty"
            record_block_reason "${ninja_name}:lesson_candidate_no_reason_empty"
            ALL_CLEAR=false
            ;;
        found_true_empty:*)
            missing_fields="${lc_status#found_true_empty:}"
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:true but empty fields: ${missing_fields}"
            record_block_reason "${ninja_name}:lesson_candidate_fields_empty:${missing_fields}"
            ALL_CLEAR=false
            ;;
        found_true)
            # lesson.doneのsource確認
            lesson_done="$GATES_DIR/lesson.done"
            if [ -f "$lesson_done" ]; then
                lsource=$(grep -E '^\s*source:' "$lesson_done" 2>/dev/null | sed 's/.*source: *//')
                [ -z "$lsource" ] && echo "[WARN] Empty source field in lesson" >&2
                if [ "$lsource" = "lesson_write" ]; then
                    echo "  ${ninja_name}: OK (lesson_candidate found:true, registered via lesson_write)"
                else
                    echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:true but lesson.done source=${lsource} (not lesson_write)"
                    record_block_reason "${ninja_name}:lesson_done_source:${lsource}"
                    ALL_CLEAR=false
                fi
            else
                echo "  WARN: ${ninja_name}: lesson_candidate found:true but lesson.done not found — lesson_write.sh登録待ち"
                notify_karo_lesson_registration_reminder "$CMD_ID" "$ninja_name"
            fi
            ;;
        missing)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidateフィールド欠落"
            record_block_reason "${ninja_name}:lesson_candidate_missing"
            ALL_CLEAR=false
            ;;
        legacy_list)
            # cmd_776 A層: BLOCK→自動修正+WARN。normalize_report.shで修正を試みる
            a_normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) && {
                echo "  [INFO] ${ninja_name}: lesson_candidate旧形式を自動修正: ${a_normalize_output}"
                append_line_locked "$SCRIPT_DIR/logs/normalize_report.log" "$(date '+%Y-%m-%dT%H:%M:%S') [A層] ${CMD_ID} ${ninja_name}: ${a_normalize_output}"
                # 修正成功 → 再検証
                if awk '/^lesson_candidate:/{p=1;next} p&&/found:/{found=1;exit} /^[^ ]/{if(p)exit 1} END{if(!found)exit 1}' "$report_file" 2>/dev/null; then
                    lc_recheck="ok"
                else
                    lc_recheck="ng"
                fi
                if [ "$lc_recheck" != "ok" ]; then
                    echo "  [CRITICAL] ${ninja_name}: NG ← 自動修正後も構造不正"
                    record_block_reason "${ninja_name}:lesson_candidate_normalize_failed"
                    ALL_CLEAR=false
                fi
            } || {
                echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate自動修正失敗"
                record_block_reason "${ninja_name}:lesson_candidate_normalize_error"
                ALL_CLEAR=false
            }
            ;;
        found_missing)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate.found が未設定。正規フォーマット: found: true/false"
            record_block_reason "${ninja_name}:lesson_candidate_found_missing"
            ALL_CLEAR=false
            ;;
        malformed)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate構造不正"
            record_block_reason "${ninja_name}:lesson_candidate_malformed"
            ALL_CLEAR=false
            ;;
        *)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate解析エラー"
            record_block_reason "${ninja_name}:lesson_candidate_parse_error"
            ALL_CLEAR=false
            ;;
    esac
done
if [ "$LC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── binary_checks検証（AC二値チェック全PASS確認） ───
# GP-221: 二重配備対応 — verdict=PASSの忍者が1名以上いれば、他忍者のbc_failはWARN止まり
level_heading "[L1]" "Binary checks validation:"
BC_CHECKED=false
# Pre-scan: verdict=PASSの忍者を収集(二重配備時の降格判定用)
_bc_pass_ninjas=""
for _bc_tf in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$_bc_tf" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $_bc_tf"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
    _bc_nn=$(basename "$_bc_tf" .yaml)
    _bc_rf=$(resolve_report_file "$_bc_nn")
    [ -f "$_bc_rf" ] || continue
    _bc_verdict=$(FIELD_GET_NO_LOG=1 field_get "$_bc_rf" "verdict" "" 2>/dev/null || true)
    [ "$_bc_verdict" = "PASS" ] && _bc_pass_ninjas="${_bc_pass_ninjas}${_bc_nn} "
done
[ -n "$_bc_pass_ninjas" ] && echo "  (verdict=PASS忍者: ${_bc_pass_ninjas% })"

for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    BC_CHECKED=true

    # assigned_acs: タスクYAMLに指定がある場合は担当AC以外をスキップ（分割配備対応）
    assigned_acs_raw=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "assigned_acs" "" 2>/dev/null || true)

    # binary_checks: リスト形式(フラット or ACグループ化)の全check→result確認
    # ネストされたdict形式(AC3:/AC4:見出し配下にcheck/result)もサポート
    # assigned_acsがある場合は担当外ACグループ(commitを除く)をスキップ
    bc_status=$(awk -v assigned="$assigned_acs_raw" '
        /^binary_checks:/ {
            val = $0; sub(/.*binary_checks:[[:space:]]*/, "", val)
            if (val == "null" || val == "~") { print "missing"; exit }
            in_bc = 1; next
        }
        # セクション終了: 行頭が英字(新キー)の場合のみ (- で始まるリスト項目は含めない)
        in_bc && /^[a-zA-Z]/ { in_bc = 0 }
        # ACグループ見出し(AC1:/AC2:/AC3:等)→assigned_acsがある場合は担当外をスキップ
        # commitグループは常にチェック対象（assigned_acsに関係なく）
        in_bc && /^[[:space:]]+[A-Za-z_][A-Za-z_0-9]*:/ && !/^[[:space:]]+check:/ && !/^[[:space:]]+result:/ {
            grp = $0; sub(/^[[:space:]]+/, "", grp); sub(/:.*/, "", grp)
            if (assigned != "" && grp != "commit") {
                skip_group = 1
                n = split(assigned, arr, /[, ]+/)
                for (i=1; i<=n; i++) { if (arr[i] == grp) { skip_group = 0; break } }
            } else { skip_group = 0 }
            next
        }
        in_bc && !skip_group && /[[:space:]]*- check:/ { item_count++; cur_check = $0; sub(/.*- check:[[:space:]]*/, "", cur_check); gsub(/^["'"'"']+|["'"'"']+$/, "", cur_check) }
        in_bc && !skip_group && /[[:space:]]+result:/ {
            r = $0; sub(/.*result:[[:space:]]*/, "", r); gsub(/^["'"'"']+|["'"'"']+$/, "", r)
            upper_r = toupper(r)
            if (upper_r != "PASS" && upper_r != "YES" && upper_r != "TRUE") {
                _name = (cur_check != "" ? cur_check : "item_" item_count)
                if (fails != "") fails = fails "|" _name
                else fails = _name
            }
        }
        END {
            if (item_count == 0) { print "missing"; exit }
            if (fails != "") print "fail:" fails
            else print "ok"
        }
    ' "$report_file" 2>/dev/null)

    case "$bc_status" in
        ok)
            echo "  ${ninja_name}: OK (binary_checks: all PASS)"
            ;;
        missing)
            echo "  [WARN] ${ninja_name}: binary_checks key missing or null"
            ;;
        fail:*)
            failed_checks="${bc_status#fail:}"
            warn_reason=$(binary_checks_warn_reason "$report_file" "$ninja_name" "$_bc_pass_ninjas" || true)
            if [ -n "$warn_reason" ]; then
                echo "  [WARN] ${ninja_name}: binary_checks non-PASS (${failed_checks}) — ${warn_reason}"
            else
                echo "  [CRITICAL] ${ninja_name}: NG ← binary_checks has non-PASS results: ${failed_checks}"
                record_block_reason "${ninja_name}:binary_checks_fail"
                _fail_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "" 2>/dev/null || true)
                if [ "$_fail_verdict" = "FAIL" ]; then
                    notify_karo_cmd_fail "$CMD_ID" "$ninja_name" "$report_file" "binary_checks_fail:${failed_checks}"
                fi
                ALL_CLEAR=false
            fi
            ;;
        malformed)
            echo "  [WARN] ${ninja_name}: binary_checks is not a list"
            ;;
        *)
            echo "  [WARN] ${ninja_name}: binary_checks parse error"
            ;;
    esac
done
if [ "$BC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── post_deploy_evidence検証（deploy後cron/外部job証跡の旧run流用防止） ───
level_heading "[L2]" "Post-deploy evidence timestamp check:"
PDE_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    if ! pde_status=$(REPORT_FILE="$report_file" python3 - 2>/dev/null <<'PY'
import os
from datetime import datetime, timezone

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

report_file = os.environ["REPORT_FILE"]
with open(report_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

pde = data.get("post_deploy_evidence")
if not isinstance(pde, dict):
    print("skip")
    raise SystemExit(0)

def as_bool(v):
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in {"1", "true", "yes", "y"}

if not as_bool(pde.get("required")):
    print("skip")
    raise SystemExit(0)

missing = []
for key in ("deploy_live_at", "evidence_run_start_at", "evidence_run_completed_at", "source"):
    if not str(pde.get(key) or "").strip():
        missing.append(key)
if "run_completed" not in pde or not as_bool(pde.get("run_completed")):
    missing.append("run_completed")
if missing:
    print("missing:" + ",".join(missing))
    raise SystemExit(0)

def parse_ts(raw):
    s = str(raw).strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        # naive timestamp is ambiguous; treat as invalid so UTC evidence is required.
        raise ValueError("timezone_missing")
    return dt.astimezone(timezone.utc)

try:
    deploy_live_at = parse_ts(pde["deploy_live_at"])
    run_start_at = parse_ts(pde["evidence_run_start_at"])
    run_completed_at = parse_ts(pde["evidence_run_completed_at"])
except Exception:
    print("invalid_timestamp")
    raise SystemExit(0)

if run_completed_at < run_start_at:
    print("order_fail:completed_before_start")
elif run_start_at <= deploy_live_at:
    print("order_fail:run_start_not_after_deploy")
else:
    print("ok")
PY
    ); then
        pde_status="parse_error"
    fi

    case "$pde_status" in
        skip)
            ;;
        ok)
            PDE_CHECKED=true
            echo "  ${ninja_name}: OK (post_deploy_evidence run_start > deploy_live_at)"
            ;;
        missing:*)
            PDE_CHECKED=true
            missing_fields="${pde_status#missing:}"
            echo "  [CRITICAL] ${ninja_name}: NG ← post_deploy_evidence required but missing/false: ${missing_fields}"
            record_block_reason "${ninja_name}:post_deploy_evidence_missing:${missing_fields}"
            ALL_CLEAR=false
            ;;
        invalid_timestamp)
            PDE_CHECKED=true
            echo "  [CRITICAL] ${ninja_name}: NG ← post_deploy_evidence timestamp invalid or timezone missing"
            record_block_reason "${ninja_name}:post_deploy_evidence_invalid_timestamp"
            ALL_CLEAR=false
            ;;
        order_fail:*)
            PDE_CHECKED=true
            pde_reason="${pde_status#order_fail:}"
            echo "  [CRITICAL] ${ninja_name}: NG ← post_deploy_evidence order check failed: ${pde_reason}"
            record_block_reason "${ninja_name}:post_deploy_evidence_${pde_reason}"
            ALL_CLEAR=false
            ;;
        *)
            PDE_CHECKED=true
            echo "  [CRITICAL] ${ninja_name}: NG ← post_deploy_evidence parse error"
            record_block_reason "${ninja_name}:post_deploy_evidence_parse_error"
            ALL_CLEAR=false
            ;;
    esac
done
if [ "$PDE_CHECKED" = false ]; then
    echo "  (no post_deploy_evidence.required=true reports)"
fi

# ─── purpose_validation検証（fit:falseでBLOCK、fit空欄はWARN） ───
level_heading "[L2]" "Purpose validation check:"
PV_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    PV_CHECKED=true
    pv_fit=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "fit" "")

    case "$pv_fit" in
        true)
            # fit=true はPASS（要件どおり無出力）
            ;;
        false)
            # GP-221: 二重配備で他忍者がverdict=PASSなら、この忍者のfit=falseはWARN止まり
            if [ -n "$_bc_pass_ninjas" ] && [[ "$_bc_pass_ninjas" != *"$ninja_name "* ]]; then
                echo "  [WARN] ${ninja_name}: fit=false — 他忍者PASS済みのためBLOCK降格"
            else
                echo "[CRITICAL] GATE BLOCK: purpose_validation.fit=false (目的未達成)"
                echo "  ${ninja_name}: fit=false"
                record_block_reason "${ninja_name}:purpose_validation_fit_false"
                ALL_CLEAR=false
            fi
            ;;
        "")
            echo "  [INFO] ${ninja_name}: fit未記入（段階導入: 非BLOCK）"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: fit値不正 '${pv_fit}'（段階導入: 非BLOCK）"
            ;;
    esac
done
if [ "$PV_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate重複チェック（resolved PDとの照合、cmd_1179） ───
level_heading "[L2]" "Decision candidate duplicate check (cmd_1179):"
if [ "$HAS_RECON" = true ] && [ "$HAS_IMPLEMENT" = false ]; then
    echo "  SKIP (recon-only cmd)"
else
    DC_DUP_CHECKED=false
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ ! -f "$report_file" ]; then
            echo "  ${ninja_name}: SKIP (report not found)"
            continue
        fi

        DC_DUP_CHECKED=true
        dc_dup_result=$(bash "$SCRIPT_DIR/scripts/gates/gate_dc_duplicate.sh" "$report_file" 2>/dev/null || echo "BLOCK: gate script error")

        case "$dc_dup_result" in
            BLOCK:*)
                echo "  [CRITICAL] ${ninja_name}: ${dc_dup_result}"
                record_block_reason "${ninja_name}:dc_duplicate_block"
                ALL_CLEAR=false
                ;;
            WARN:*)
                echo "  [INFO] ${ninja_name}: ${dc_dup_result}"
                ;;
            OK:*|SKIP:*)
                echo "  ${ninja_name}: ${dc_dup_result}"
                ;;
            *)
                echo "  [INFO] ${ninja_name}: dc_dup unexpected: ${dc_dup_result}"
                ;;
        esac
    done
    if [ "$DC_DUP_CHECKED" = false ]; then
        echo "  (no reports found for this cmd)"
    fi
fi

# ─── deviation回数チェック（WARNのみ、4回以上でWARNING） ───
level_heading "[L2]" "Deviation count check:"
DEVIATION_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    DEVIATION_CHECKED=true
    # result:セクション内のdeviation:リスト要素数を数える
    deviation_status=$(awk '
        /^result:/ { in_result=1; next }
        in_result && /^[^ ]/ { in_result=0 }
        in_result && /^[[:space:]]+deviation:/ {
            has_dev=1; in_dev=1
            match($0, /^[[:space:]]+/)
            dev_indent = RLENGTH
            if ($0 ~ /\[\]/) { has_dev=2 }
            next
        }
        in_dev && NF > 0 {
            match($0, /^[[:space:]]*/); ci = RLENGTH
            if (ci <= dev_indent) { in_dev=0; next }
        }
        in_dev && /^[[:space:]]+- / { count++ }
        END {
            if (!has_dev && count==0) { printf "skip\tresult.deviation not present"; exit }
            if (has_dev==2 || count==0) { printf "skip\tresult.deviation empty (count 0)"; exit }
            if (count >= 4) printf "warn\t%d", count
            else printf "ok\t%d", count
        }
    ' "$report_file" 2>/dev/null)

    deviation_kind=$(printf '%s\n' "$deviation_status" | cut -f1)
    deviation_detail=$(printf '%s\n' "$deviation_status" | cut -f2-)

    case "$deviation_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: deviation count ${deviation_detail} >= 4: 逸脱管理ルール(3回超過)に抵触"
            ;;
        ok)
            echo "  ${ninja_name}: OK (deviation count ${deviation_detail} <= 3)"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${deviation_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: deviation count解析エラー (${deviation_detail})"
            ;;
    esac
done
if [ "$DEVIATION_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── analysis_paralysis_triggeredチェック（WARNのみ） ───
level_heading "[L2]" "Analysis paralysis check:"
ANALYSIS_PARALYSIS_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    ANALYSIS_PARALYSIS_CHECKED=true
    if ! grep -q '^\s*result:' "$report_file" 2>/dev/null; then
        analysis_status=$'skip\tresult missing or not a mapping'
    else
        ap_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "analysis_paralysis_triggered" "")
        case "$ap_val" in
            true)  analysis_status=$'warn\tanalysis paralysis was triggered during this task' ;;
            false) analysis_status=$'ok\tanalysis_paralysis_triggered=false' ;;
            "")    analysis_status=$'skip\tanalysis_paralysis_triggered not present' ;;
            *)     analysis_status=$'skip\tanalysis_paralysis_triggered not boolean' ;;
        esac
    fi

    analysis_kind=$(printf '%s\n' "$analysis_status" | cut -f1)
    analysis_detail=$(printf '%s\n' "$analysis_status" | cut -f2-)

    case "$analysis_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: ${analysis_detail}"
            ;;
        ok)
            echo "  ${ninja_name}: OK (${analysis_detail})"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${analysis_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: analysis_paralysis_triggered解析エラー (${analysis_detail})"
            ;;
    esac
done
if [ "$ANALYSIS_PARALYSIS_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── skill_candidate検証（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Skill candidate check:"
SC_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    SC_CHECKED=true

    if ! grep -q 'skill_candidate:' "$report_file" 2>/dev/null; then
        sc_status="missing"
    elif awk '/^skill_candidate:/{p=1;next} p&&/found:/{found=1;exit} /^[^ ]/{if(p)exit 1} END{if(!found)exit 1}' "$report_file" 2>/dev/null; then
        sc_status="ok"
    else
        sc_status="no_found"
    fi

    case "$sc_status" in
        ok)
            echo "  ${ninja_name}: OK (skill_candidate.found present)"
            ;;
        missing)
            echo "  [INFO] ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        no_found)
            echo "  [INFO] ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        malformed)
            echo "  [INFO] ${ninja_name}_report.yaml skill_candidate構造不正"
            ;;
        *)
            echo "  [INFO] ${ninja_name}_report.yaml skill_candidate解析エラー"
            ;;
    esac
done
if [ "$SC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate検証（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Decision candidate check:"
DC_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    DC_CHECKED=true

    if ! grep -q 'decision_candidate:' "$report_file" 2>/dev/null; then
        dc_status="missing"
    elif awk '/^decision_candidate:/{p=1;next} p&&/found:/{found=1;exit} /^[^ ]/{if(p)exit 1} END{if(!found)exit 1}' "$report_file" 2>/dev/null; then
        dc_status="ok"
    else
        dc_status="no_found"
    fi

    case "$dc_status" in
        ok)
            echo "  ${ninja_name}: OK (decision_candidate.found present)"
            ;;
        missing)
            echo "  [INFO] ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        no_found)
            echo "  [INFO] ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        malformed)
            echo "  [INFO] ${ninja_name}_report.yaml decision_candidate構造不正"
            ;;
        *)
            echo "  [INFO] ${ninja_name}_report.yaml decision_candidate解析エラー"
            ;;
    esac
done
if [ "$DC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── how_it_works検証（implementタスクはWARN導入） ───
level_heading "[L2]" "Implementation walkthrough check:"
HOW_IT_WORKS_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    task_role=$(detect_task_role "$task_file")
    [ "$task_role" = "implement" ] || continue

    HOW_IT_WORKS_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (implement report not found)"
        continue
    fi

    walkthrough_status=$(check_how_it_works_status "$report_file")
    case "$walkthrough_status" in
        ok)
            echo "  ${ninja_name}: OK (how_it_works present)"
            ;;
        missing|empty)
            echo "  [INFO] ${ninja_name}: how_it_works missing or empty (implement report)"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: how_it_works parse error (non-blocking)"
            ;;
    esac
done
if [ "$HOW_IT_WORKS_CHECKED" = false ]; then
    echo "  (no implement tasks found for this cmd)"
fi

run_review_quality_check

# ─── draft教訓存在チェック（プロジェクト関連のdraft未査読をブロック） ───
level_heading "[L3]" "Draft lesson check:"
# cmdのprojectを取得
if [ -z "$CMD_PROJECT" ] && [ -f "$YAML_FILE" ]; then
    CMD_PROJECT=$(awk -v cmd="${CMD_ID}" '
        /^  [a-zA-Z_].*:$/ { key=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", key); found=(key==cmd) ? 1 : 0; next }
        found && /^    project:/ { sub(/^[[:space:]]*project:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }
    ' "$YAML_FILE")
else
    echo "  SKIP (cmd source YAML missing: ${YAML_FILE#"$SCRIPT_DIR"/})"
fi

if [ -n "$CMD_PROJECT" ]; then
    # projectのSSOTパスを取得
    DRAFT_SSOT_PATH=$(awk -v proj="$CMD_PROJECT" '
        /^\s*- id:/ { id=$0; sub(/.*id:\s*/, "", id); gsub(/[" \t]/, "", id); found=(id==proj) }
        found && /^\s*path:/ { sub(/^\s*path:\s*/, ""); gsub(/["'"'"' \t]/, ""); print; exit }
    ' "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null)

    if [ -n "$DRAFT_SSOT_PATH" ]; then
        DRAFT_LESSONS_FILE="$DRAFT_SSOT_PATH/tasks/lessons.md"
        if [ -f "$DRAFT_LESSONS_FILE" ]; then
            draft_count=$(grep -c '^\- \*\*status\*\*: draft' "$DRAFT_LESSONS_FILE" 2>/dev/null || true)
            draft_count=${draft_count:-0}
            # cmd固有のdraft教訓のみカウント(無関係cmdのdraftで全cmdをBLOCKしない)
            own_draft_count=0
            if [ "$draft_count" -gt 0 ]; then
                own_draft_count=$(awk -v cmd="${CMD_ID}" '
                    function close_lesson() {
                        if (in_lesson && is_draft && is_own && !is_gate_auto_draft) count++
                    }
                    /^\#\#\# L[0-9]+:/ { close_lesson(); in_lesson=1; is_draft=0; is_own=0; is_gate_auto_draft=0; next }
                    in_lesson && /^\- \*\*status\*\*: draft/ { is_draft=1 }
                    in_lesson && /^\- \*\*source\*\*:[[:space:]]*gate_auto_draft[[:space:]]*$/ { is_gate_auto_draft=1 }
                    in_lesson && /^\- \*\*出典\*\*:/ && index($0, cmd) { is_own=1 }
                    in_lesson && /^$/ { close_lesson(); in_lesson=0 }
                    END { close_lesson(); print count+0 }
                ' "$DRAFT_LESSONS_FILE" 2>/dev/null)
                own_draft_count=${own_draft_count:-0}
            fi
            if [ "$own_draft_count" -gt 0 ]; then
                echo "  [CRITICAL] NG ← ${CMD_ID}由来のdraft未査読教訓${own_draft_count}件あり"
                echo "  ★ この問題は忍者では解消できない。家老に報告して待機せよ。リトライは無駄(GP-203)"
                record_block_reason "draft_lessons:${own_draft_count}"
                ALL_CLEAR=false
            elif [ "$draft_count" -gt 0 ]; then
                echo "  WARN: ${CMD_PROJECT}に${draft_count}件のdraft未査読教訓あり(${CMD_ID}由来以外。BLOCK対象外)"
            else
                echo "  OK (no draft lessons in ${CMD_PROJECT})"
            fi
        else
            echo "  SKIP (lessons file not found: ${DRAFT_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project path not found for: ${CMD_PROJECT})"
    fi
else
    echo "  SKIP (project not found in cmd)"
fi

# ─── grep直書きYAMLアクセス検出（WARNのみ、ブロックしない） L070 ───
level_heading "[L2]" "Raw grep YAML access check (L070):"
RAW_GREP_COUNT=0
last_rel_path=""
line_count=0
RAW_GREP_TARGETS=()
while IFS= read -r changed_file; do
    [ -n "$changed_file" ] || continue
    case "$changed_file" in
        scripts/*.sh|scripts/lib/*.sh)
            case "$changed_file" in
                scripts/gates/*|scripts/lib/field_get.sh) ;;
                *) RAW_GREP_TARGETS+=("$SCRIPT_DIR/$changed_file") ;;
            esac
            ;;
    esac
done <<< "$CMD_CHANGED_FILES"

hits=""
if [ "${#RAW_GREP_TARGETS[@]}" -gt 0 ]; then
    if raw_grep_rg_cmd="$(resolve_gate_rg)"; then
        hits=$("$raw_grep_rg_cmd" -n "grep.*['\\\"]\\^(\\\\s|  ).*[a-z_]+:" "${RAW_GREP_TARGETS[@]}" 2>/dev/null | grep -v 'field_get' || true)
    else
        # rg不在時のfallback。パターンの\sはPCRE構文のためgrep -Pで同一パターンを再利用する。
        hits=$(grep -rPn "grep.*['\\\"]\\^(\\\\s|  ).*[a-z_]+:" "${RAW_GREP_TARGETS[@]}" 2>/dev/null | grep -v 'field_get' || true)
    fi
fi
if [ -n "$hits" ]; then
    while IFS=: read -r hit_file hit_line hit_rest; do
        [ -n "$hit_file" ] || continue
        rel_path="${hit_file#"$SCRIPT_DIR"/}"
        if [ "$last_rel_path" != "$rel_path" ]; then
            echo "  [INFO] ${rel_path} — raw grep YAML access detected:"
            RAW_GREP_COUNT=$((RAW_GREP_COUNT + 1))
            last_rel_path="$rel_path"
            line_count=0
        fi
        if [ "$line_count" -lt 3 ]; then
            echo "    ${hit_line}:${hit_rest}"
            line_count=$((line_count + 1))
        fi
    done <<< "$hits"
fi
if [ "$RAW_GREP_COUNT" -eq 0 ]; then
    if [ "${#RAW_GREP_TARGETS[@]}" -eq 0 ]; then
        echo "  SKIP (no scripts/*.sh changes in ${CMD_ID} commits)"
    else
        echo "  OK (no raw grep YAML access detected in changed scripts)"
    fi
else
    echo "  [INFO] ${RAW_GREP_COUNT} script(s) use raw grep for YAML field access. Migrate to field_get (scripts/lib/field_get.sh)"
fi

# ─── inbox_archive強制チェック（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Inbox archive check:"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$KARO_INBOX" ]; then
    read_count=$(grep -c 'read: true' "$KARO_INBOX" 2>/dev/null || true)
    read_count=${read_count:-0}

    if [ "$read_count" -ge 10 ]; then
        echo "[INFO] INBOX_ARCHIVE_WARN: karo has ${read_count} read messages, running inbox_archive.sh"
        if bash "$SCRIPT_DIR/scripts/inbox_archive.sh" karo; then
            echo "  karo: inbox_archive completed"
        else
            echo "  [INFO] inbox_archive.sh failed for karo"
        fi
    else
        echo "  karo: OK (read:true=${read_count}, threshold=10)"
    fi
else
    echo "  [INFO] karo inbox file not found: ${KARO_INBOX}"
fi

# ─── 未反映PD検出（WARNのみ、ブロックしない） ───
level_heading "[L3]" "Pending decision context sync check:"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$PD_FILE" ]; then
    unsynced_pds=$(awk -v cmd="${CMD_ID}" '
        /^[[:space:]]*- id:/ {
            if (did != "" && scmd == cmd && stat == "resolved" && synced == "false") print did
            did = $0; sub(/.*- id:[[:space:]]*/, "", did); gsub(/[" \t]/, "", did)
            scmd = ""; stat = ""; synced = ""
            next
        }
        /^[[:space:]]+source_cmd:/ { scmd = $0; sub(/.*source_cmd:[[:space:]]*/, "", scmd); gsub(/[" \t]/, "", scmd) }
        /^[[:space:]]+status:/ { stat = $0; sub(/.*status:[[:space:]]*/, "", stat); gsub(/[" \t]/, "", stat) }
        /^[[:space:]]+context_synced:/ { synced = $0; sub(/.*context_synced:[[:space:]]*/, "", synced); gsub(/[" \t]/, "", synced) }
        END { if (did != "" && scmd == cmd && stat == "resolved" && synced == "false") print did }
    ' "$PD_FILE" 2>/dev/null)

    if [ -n "$unsynced_pds" ]; then
        while IFS= read -r pd_id; do
            echo "  [INFO] ${pd_id} resolved but context not synced"
        done <<< "$unsynced_pds"
    else
        echo "  OK (no unsynced resolved PDs for ${CMD_ID})"
    fi
else
    echo "  SKIP (pending_decisions.yaml not found)"
fi

# ─── 穴4: 調査恒久化チェック（WARNのみ、ブロックしない） ───
level_heading "[L3]" "Recon knowledge persistence check (穴4):"
# purposeを取得（append_changelog内と同じawk）
CMD_PURPOSE=""
if [ -f "$YAML_FILE" ]; then
    CMD_PURPOSE=$(awk -v cmd="${CMD_ID}" '
        /^  [a-zA-Z_].*:$/ { key=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", key); found=(key==cmd) ? 1 : 0; next }
        found && /^    (title|purpose):/ { sub(/^[[:space:]]*(title|purpose):[[:space:]]*"?/, ""); sub(/"[[:space:]]*$/, ""); print; exit }
    ' "$YAML_FILE")
else
    echo "  SKIP (cmd source YAML missing: ${YAML_FILE#"$SCRIPT_DIR"/})"
fi

IS_RECON=false
if echo "$CMD_PURPOSE" | grep -qE '偵察|調査|棚卸し|recon|investigation'; then
    IS_RECON=true
fi

if [ "$IS_RECON" = true ]; then
    if [ -n "$CMD_PROJECT" ]; then
        CONTEXT_FILE="$SCRIPT_DIR/context/${CMD_PROJECT}.md"
        PROJECT_YAML="$SCRIPT_DIR/projects/${CMD_PROJECT}.yaml"
        HAS_CHANGE=false

        # git diffで変更有無を確認（ステージ済み+未ステージ両方）
        if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff HEAD -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff HEAD -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        # ステージ済みの変更もチェック
        if [ "$HAS_CHANGE" = false ]; then
            if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff --cached -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
            if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff --cached -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
        fi

        if [ "$HAS_CHANGE" = true ]; then
            echo "  OK (context/${CMD_PROJECT}.md or projects/${CMD_PROJECT}.yaml has changes)"
        else
            echo "  [INFO] 穴4: 調査結果が知識基盤に未反映。context/*.md or projects/*.yaml を更新せよ"
        fi
    else
        echo "  SKIP (project not found in cmd — cannot check knowledge files)"
    fi
else
    echo "  SKIP (non-recon cmd: purpose does not contain recon keywords)"
fi

# ─── 偵察報告 実装直結4要件チェック（WARNのみ、cmd_754） ───
level_heading "[L2]" "Recon implementation_readiness check (cmd_754):"

if [ "$HAS_RECON" = true ]; then
    RECON_4REQ_MISSING=0
    RECON_4REQ_CHECKED=0
    RECON_4REQ_KEYWORDS="files_to_modify affected_files related_tests edge_cases"

    for report_file in "$REPORTS_DIR"/*_report_${CMD_ID}.yaml; do
        [ -f "$report_file" ] || continue

        # task_typeがrecon/scoutの報告のみ対象
        local_task_type=""
        local_task_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "task_id" "")
        [ -z "$local_task_id" ] && local_task_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "_ac_task_id" "")
        if [ -n "$local_task_id" ]; then
            local_task_file="$TASKS_DIR/$(echo "$report_file" | sed 's|.*/\([^/]*\)_report_.*|\1|').yaml"
            if [ -f "$local_task_file" ]; then
                local_task_type=$(FIELD_GET_NO_LOG=1 field_get "$local_task_file" "task_type" "")
            fi
        fi

        # subtask_idからもrecon/scoutを判定
        if [ -z "$local_task_type" ] || { [ "$local_task_type" != "recon" ] && [ "$local_task_type" != "scout" ]; }; then
            if echo "$local_task_id" | grep -qiE 'scout|recon'; then
                local_task_type="recon"
            fi
        fi

        [ "$local_task_type" = "recon" ] || [ "$local_task_type" = "scout" ] || continue

        RECON_4REQ_CHECKED=$((RECON_4REQ_CHECKED + 1))
        for kw in $RECON_4REQ_KEYWORDS; do
            if ! grep -q "$kw" "$report_file" 2>/dev/null; then
                RECON_4REQ_MISSING=$((RECON_4REQ_MISSING + 1))
                echo "  [INFO] ${report_file##*/} に ${kw} が欠落"
            fi
        done
    done

    if [ "$RECON_4REQ_CHECKED" -eq 0 ]; then
        echo "  SKIP (recon reports not found for ${CMD_ID})"
    elif [ "$RECON_4REQ_MISSING" -eq 0 ]; then
        echo "  OK (全偵察報告に実装直結4要件あり)"
    else
        echo "  [INFO] 偵察報告に実装直結4要件(files_to_modify/affected_files/related_tests/edge_cases)が欠落。偵察品質を確認せよ"
    fi
else
    echo "  SKIP (non-recon cmd)"
fi

# ─── プロジェクトコードのスタブ検出（WARNのみ、cmd差分の追加行のみ） ───
level_heading "[L2]" "Project code stub check:"
STUB_CHECK_RC=0
STUB_CHECK_OUTPUT=$(check_project_code_stubs "$CMD_ID" "$CMD_PROJECT" 2>&1) || STUB_CHECK_RC=$?
STUB_CHECK_STATUS=$(printf '%s\n' "$STUB_CHECK_OUTPUT" | head -1 | cut -f1)
STUB_CHECK_MESSAGE=$(printf '%s\n' "$STUB_CHECK_OUTPUT" | head -1 | cut -f2-)

case "$STUB_CHECK_STATUS" in
    WARN)
        echo "  [INFO] ${STUB_CHECK_MESSAGE}"
        printf '%s\n' "$STUB_CHECK_OUTPUT" | tail -n +2 | while IFS= read -r line; do
            [ -n "$line" ] || continue
            echo "    ${line}"
        done
        ;;
    OK)
        echo "  OK (${STUB_CHECK_MESSAGE})"
        ;;
    SKIP)
        echo "  SKIP (${STUB_CHECK_MESSAGE})"
        ;;
    BLOCK)
        echo "  BLOCK (${STUB_CHECK_MESSAGE})"
        printf '%s\n' "$STUB_CHECK_OUTPUT" | tail -n +2 | while IFS= read -r line; do
            [ -n "$line" ] || continue
            echo "    ${line}"
        done
        ;;
    ERR)
        echo "  [INFO] ${STUB_CHECK_MESSAGE}"
        ;;
    *)
        if [[ $STUB_CHECK_RC -ne 0 ]]; then
            echo "  [ERROR] check_project_code_stubs failed (rc=$STUB_CHECK_RC)"
            printf '%s\n' "$STUB_CHECK_OUTPUT" | head -3 | while IFS= read -r line; do
                echo "    ${line}"
            done
        else
            echo "  [INFO] project code stub check returned no result"
        fi
        ;;
esac

# ─── 配線検証（WARNのみ、Existence != Integration） ───
level_heading "[L3]" "Wiring verification:"
if ! printf '%s\n' "$CMD_CHANGED_FILES" | grep -qE '^(scripts/|instructions/|CLAUDE\.md$)'; then
    echo "  SKIP (no scripts/instructions changes in ${CMD_ID} commits)"
else
    WIRING_OUTPUT=$(check_script_wiring "$CMD_ID" 2>/dev/null || true)
    if [ -z "$WIRING_OUTPUT" ]; then
        echo "  [INFO] wiring verification returned no result"
    else
        while IFS=$'\t' read -r row_type scope status message; do
            case "$row_type" in
                CHECK)
                    case "$status" in
                        WARN)
                            echo "  [INFO] ${scope}: WARN (${message})"
                            ;;
                        SKIP)
                            echo "  ${scope}: SKIP (${message})"
                            ;;
                        *)
                            echo "  ${scope}: OK (${message})"
                            ;;
                    esac
                    ;;
                DETAIL)
                    echo "    ${message}"
                    ;;
            esac
        done <<< "$WIRING_OUTPUT"
    fi
fi

run_todo_fixme_residual_check "$CMD_ID"

check_gs_bench_gate_warn

# ─── CoDD 退行チェック（台帳の最新エントリでAfter>Beforeを検知、WARN-only） ───
level_heading "[L3]" "CoDD regression check:"
if [ -f "$SCRIPT_DIR/scripts/gates/gate_codd_regression.sh" ]; then
    codd_reg_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_codd_regression.sh" "$SCRIPT_DIR/docs/research/codd_refactor_registry.md" 2>&1)
    while IFS= read -r line; do
        echo "  $line"
    done <<< "$codd_reg_output"
else
    echo "  [INFO] gate_codd_regression.sh not found (skip)"
fi

# ─── テストSKIP検査（skip_count > 0 で BLOCK） ───
level_heading "[L2]" "Test skip count check:"
TEST_SKIP_CHECKED=false
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    TEST_SKIP_CHECKED=true
    # test_skip_count取得 (top-level優先 → test_results.skippedフォールバック)
    skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "test_skip_count" "")
    test_skip_status=""
    if [ -z "$skip_val" ]; then
        if ! grep -q '^\s*test_results:' "$report_file" 2>/dev/null; then
            test_skip_status=$'warn\ttest_results not present'
        else
            skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "skipped" "")
            if [ -z "$skip_val" ]; then
                test_skip_status=$'warn\ttest_results.skipped not present'
            fi
        fi
    fi
    if [ -z "$test_skip_status" ] && [ -n "$skip_val" ]; then
        if [[ "$skip_val" =~ ^-?[0-9]+$ ]]; then
            if [ "$skip_val" -gt 0 ]; then
                test_skip_status=$(printf 'block\t%s' "$skip_val")
            elif [ "$skip_val" -eq 0 ]; then
                test_skip_status=$(printf 'ok\t%s' "$skip_val")
            else
                test_skip_status=$(printf 'warn\ttest_skip_count negative: %s' "$skip_val")
            fi
        else
            test_skip_status=$(printf 'warn\ttest_skip_count not a number: %s' "$skip_val")
        fi
    fi

    test_skip_kind=$(printf '%s\n' "$test_skip_status" | cut -f1)
    test_skip_detail=$(printf '%s\n' "$test_skip_status" | cut -f2-)

    case "$test_skip_kind" in
        block)
            echo "  [CRITICAL] ${ninja_name}: テスト未完了: SKIP ${test_skip_detail}件。SKIP=FAILルール"
            record_block_reason "${ninja_name}:test_skip_count_${test_skip_detail}"
            ALL_CLEAR=false
            ;;
        ok)
            echo "  ${ninja_name}: OK (test_skip_count ${test_skip_detail})"
            ;;
        warn)
            echo "  [INFO] ${ninja_name}: ${test_skip_detail}"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: test_skip_count解析エラー (${test_skip_detail})"
            ;;
    esac
done
if [ "$TEST_SKIP_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── Vercel Phaseリンク整合チェック（cmd固有context変更時のみ、BLOCK対象） ───
# Bug fix: HEAD~1がauto-commitの場合、無関係なcontext変更で偽陽性BLOCK(ci_gate_mismatch 13件WA)
# → cmd固有commitのcontext変更のみ検出。auto-commit由来のcontext変更を除外
level_heading "[L3]" "Vercel phase link check:"
# HEAD contiguous commit window only: full-history grep は /mnt/c 上で極端に遅い
_vercel_hashes=$(get_cmd_head_hashes "$CMD_ID" || true)
changed_contexts=""
for _vh in $_vercel_hashes; do
    changed_contexts="$changed_contexts $(git -C "$SCRIPT_DIR" diff-tree --no-commit-id --name-only -r "$_vh" 2>/dev/null | grep '^context/' || true)"
done
changed_contexts=$(echo "$changed_contexts" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
changed_contexts="${changed_contexts% }"
if [ -n "$changed_contexts" ]; then
    if [ -f "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh" ]; then
        # cmd変更context fileのみ走査（全context走査→偽陽性BLOCK防止, GP-137）
        # shellcheck disable=SC2086
        _vercel_output=""
        _vercel_rc=0
        _vercel_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh" $changed_contexts 2>&1) || _vercel_rc=$?
        printf '%s\n' "$_vercel_output"
        if [ "$_vercel_rc" -eq 0 ]; then
            echo "  OK (gate_vercel_phase passed for cmd-changed files)"
        else
            _vercel_reason=$(classify_vercel_phase_output "$_vercel_output")
            echo "  [CRITICAL] ALERT: gate_vercel_phase failed (reason=${_vercel_reason})"
            record_block_reason "$_vercel_reason"
            ALL_CLEAR=false
        fi
    else
        echo "  [INFO] gate_vercel_phase.sh not found (skip)"
    fi
else
    echo "  SKIP (no context/*.md changes in ${CMD_ID} commits)"
fi

# ─── CI status check（push済みcmdでCI赤を検知 — failure時WARN。CLAUDE.md準拠） ───
level_heading "[L3]" "CI status check:"
CI_PUSH_DETECTED=false
CI_PUSH_STATE_BLOCK=""
declare -A _CI_PUSH_REPO_DIRS=()
for task_file in "${MATCHING_TASK_FILES[@]}"; do
    if [ ! -f "$task_file" ]; then
        echo "  [WARN] matching task file disappeared, skipping: $task_file"
        MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
        continue
    fi
    MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        task_repo_dir=$(resolve_task_repo_dir "$task_file")
        commit_repo_result=$(resolve_report_commit_repo "$report_file" "$task_file" "$task_repo_dir")
        case "$commit_repo_result" in
            BLOCK:*) CI_PUSH_STATE_BLOCK="$commit_repo_result"; break ;;
            *) task_repo_dir="$commit_repo_result" ;;
        esac
        ci_push_state=$(report_ci_push_state "$report_file" "$task_repo_dir" "$task_file")
        case "$ci_push_state" in
            PUSHED:*) CI_PUSH_DETECTED=true; _CI_PUSH_REPO_DIRS["$task_repo_dir"]=1 ;;
            BLOCK:*) CI_PUSH_STATE_BLOCK="$ci_push_state"; break ;;
        esac
    fi
done

if [ -n "$CI_PUSH_STATE_BLOCK" ]; then
    echo "  [CRITICAL] ${CI_PUSH_STATE_BLOCK}"
    record_block_reason "ci_push_state:${CI_PUSH_STATE_BLOCK}"
    ALL_CLEAR=false
elif [ "$CI_PUSH_DETECTED" = true ]; then
    ci_result="${CMD_COMPLETE_GATE_CI_RUN_JSON:-}"
    # Fail-closed when matching tasks span multiple distinct repositories.
    if [ "${#_CI_PUSH_REPO_DIRS[@]}" -gt 1 ]; then
        echo "  [CRITICAL] BLOCK: CI status check spans ${#_CI_PUSH_REPO_DIRS[@]} distinct repos (${!_CI_PUSH_REPO_DIRS[*]})"
        record_block_reason "ci_readiness:BLOCK: mixed task repos (${#_CI_PUSH_REPO_DIRS[@]} distinct)"
        ALL_CLEAR=false
    fi
    ci_repo_dir="${!_CI_PUSH_REPO_DIRS[*]}"
    ci_repo_dir="${ci_repo_dir%% *}"
    : "${ci_repo_dir:=$SCRIPT_DIR}"
    ci_origin_slug=""
    if [ -d "$ci_repo_dir/.git" ] || git -C "$ci_repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
        ci_origin_slug=$(git -C "$ci_repo_dir" remote get-url origin 2>/dev/null \
            | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)\.git$|\1|p; s|.*github\.com[:/]\([^/]*/[^/]*\)$|\1|p' \
            | head -1)
    fi
    if [ -z "$ci_origin_slug" ]; then
        echo "  [CRITICAL] BLOCK: cannot derive GitHub origin slug from task repo ${ci_repo_dir}"
        record_block_reason "ci_readiness:BLOCK: origin slug unresolvable from ${ci_repo_dir}"
        ALL_CLEAR=false
    fi
    expected_head=$(resolve_ci_expected_head "$ci_repo_dir")
    if [ -z "$ci_result" ] && [ -n "$ci_origin_slug" ] && command -v gh >/dev/null 2>&1; then
        ci_result=$(timeout 15 gh run list --repo "$ci_origin_slug" \
            --branch main --limit 5 \
            --json status,conclusion,createdAt,startedAt,databaseId,headSha 2>/dev/null || true)
        # Pick the most recent run whose head matches expected_head; fall back
        # to the overall most recent run (index 0) when no exact match exists.
        if [ -n "$ci_result" ] && [ -n "$expected_head" ]; then
            ci_result=$(printf '%s' "$ci_result" | jq -c \
                --arg head "$expected_head" \
                '[if ([.[] | select(.headSha == $head)] | length) > 0
                  then ([.[] | select(.headSha == $head)] | sort_by(.startedAt // .createdAt) | reverse | .[0])
                  else .[0] end]' 2>/dev/null || printf '%s' "$ci_result")
        fi
    fi
    ci_run_id=$(printf '%s' "$ci_result" | jq -r 'if type == "array" and length > 0 then (.[0].databaseId // "" | tostring) else "" end' 2>/dev/null || true)
    # A非GREEN run may be "all jobs cancelled" (=評価が存在しない)。job結論は
    # run levelのconclusionからは判別できないため、非GREEN時だけ一次情報を引く。
    ci_jobs_json="${CMD_COMPLETE_GATE_CI_JOBS_JSON:-}"
    ci_run_conclusion=$(printf '%s' "$ci_result" | jq -r 'if type == "array" and length > 0 then (.[0].conclusion // "") else "" end' 2>/dev/null || true)
    if [ -z "$ci_jobs_json" ] && [ -n "$ci_run_id" ] && [ -n "$ci_origin_slug" ] \
        && [ -n "$ci_run_conclusion" ] && [ "$ci_run_conclusion" != "success" ] \
        && command -v gh >/dev/null 2>&1; then
        ci_jobs_json=$(timeout 15 gh run view "$ci_run_id" --repo "$ci_origin_slug" --json jobs 2>/dev/null || true)
    fi
    ci_jobs_conclusions=$(printf '%s' "$ci_jobs_json" | jq -c '[.jobs[]?.conclusion // ""]' 2>/dev/null || printf 'null')
    [ -n "$ci_jobs_conclusions" ] || ci_jobs_conclusions=null
    target_conclusion=success
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ "$(FIELD_GET_NO_LOG=1 field_get "$report_file" verdict "")" = "PASS" ] || target_conclusion=failure
    done
    ci_decision_json=$(printf '%s' "$ci_result" | jq -c \
        --arg expected "$expected_head" --arg target "$target_conclusion" --arg reviewed "$SG7_REVIEWED_AT" \
        --argjson jobs "$ci_jobs_conclusions" \
        'if type == "array" and length > 0 and (.[0] | type) == "object" then
           {expected_head_sha:$expected, reviewed_at:$reviewed,
            target_result:{conclusion:$target,head_sha:$expected},
            workflow_result:{status:.[0].status,conclusion:.[0].conclusion,head_sha:.[0].headSha,
                             started_at:(.[0].startedAt // .[0].createdAt),created_at:.[0].createdAt,
                             jobs_conclusions:$jobs}}
         else {expected_head_sha:$expected,reviewed_at:$reviewed,target_result:{conclusion:$target,head_sha:$expected},workflow_result:null} end' \
        2>/dev/null || printf '{}')
    if ci_decision=$(printf '%s' "$ci_decision_json" | evaluate_ci_readiness_json 2>&1); then
        case "$ci_decision" in
            WAIT:*)
                # 状態(iii): このコードに対するCI評価がまだ存在しない。BLOCKではなく
                # 後追い確認へ回す(記録カテゴリ = WAIT)。GATE CLEARは止めない。
                echo "  WAIT: ${ci_decision#WAIT: }${ci_run_id:+ run=${ci_run_id}}"
                echo "  NOTE: push通過+CI後追い方式(殿裁可 2026-07-25) — CI結果は後追いで確認せよ"
                # B20: 評価不在は台帳へもWAITとして残す(BLOCK率へ混ぜない)。
                # B25: run_id/conclusionの生値を併記し、後から実測分解できるようにする。
                append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tWAIT\tci_readiness:%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
                    "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "$ci_decision" \
                    "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" \
                    "$CMD_TITLE" "$GATE_FIRST_MODEL_METRIC" \
                    "$(format_ci_raw_columns "$ci_run_id" "$ci_run_conclusion")")"
                ;;
            *)
                echo "  OK: ${ci_decision} run=${ci_run_id}"
                # B20/B25: GREEN評価も参考情報(INFO)として生値付きで残す。
                # 「is not GREEN 24件」の対照群を台帳内で実測できるようにするため。
                append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tINFO\tci_readiness:%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
                    "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "$ci_decision" \
                    "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" \
                    "$CMD_TITLE" "$GATE_FIRST_MODEL_METRIC" \
                    "$(format_ci_raw_columns "$ci_run_id" "$ci_run_conclusion")")"
                ;;
        esac
    else
        echo "  [CRITICAL] ${ci_decision}${ci_run_id:+ run=${ci_run_id}}"
        record_block_reason "ci_readiness:${ci_decision}"
        ALL_CLEAR=false
        # 歯止め(a): 真のCI赤は「次のGATE処理より前に忍者ci_fix配備」がSLA。
        # 既存の起動gate Check 0.9と同じ機械証跡(task_type=ci_fix + ci_run_id)を
        # 使い、未配備のまま次のGATE処理へ進めないよう理由へ明示する。
        case "$ci_decision" in
            *"workflow_result is not GREEN"*)
                if [ -n "$ci_run_id" ] && ! ci_fix_task_deployed "$ci_run_id"; then
                    echo "  [CRITICAL] BLOCK: run=${ci_run_id} のci_fix忍者タスク未配備 — 次のGATE処理より前に配備せよ"
                    echo "  ACTION: /karo-directでidle忍者へ task_type=ci_fix, ci_run_id=${ci_run_id} を配備(家老D0修正禁止)"
                    record_block_reason "ci_readiness:BLOCK: ci_fix未配備 run=${ci_run_id}"
                fi
                ;;
        esac
    fi
else
    echo "  SKIP (no remote-contained report commit detected)"
fi

# ─── cmd_3207: 速度修行の安全パターン削除検出 ───
check_safety_pattern_removal() {
    # 速度修行cmdのみ対象
    local tt
    tt="$(printf '%s' "${GATE_TASK_TYPE:-}" | tr '[:upper:]' '[:lower:]')"
    case "$tt" in
        *training*|*speed*) ;;
        *) return 0 ;;
    esac

    echo ""
    echo "Safety pattern removal check (speed training):"

    # 報告YAMLからcommitハッシュを収集
    local commits=()
    local report_file
    for report_file in "${MATCHING_REPORT_FILES[@]}"; do
        local sha
        sha=$(grep -oP '(?<=commit[ _])\w{7,40}' "$report_file" 2>/dev/null | head -5)
        if [[ -n "$sha" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && commits+=("$line")
            done <<< "$sha"
        fi
    done

    if [[ ${#commits[@]} -eq 0 ]]; then
        echo "  SKIP (no commits found in reports)"
        return 0
    fi

    # 安全パターン: 削除されたら危険な行パターン
    local safety_patterns='(2>/dev/null|\|\| true|\|\| :|\|\| echo|set \+e|trap |timeout )'
    local warnings=0
    local c
    for c in "${commits[@]}"; do
        local deleted_safety
        deleted_safety=$(git diff "${c}^..${c}" -- '*.sh' 2>/dev/null | grep -E '^\-' | grep -v '^\-\-\-' | grep -cE "$safety_patterns" || true)
        if [[ "$deleted_safety" -gt 0 ]]; then
            echo "  WARN: commit $c removed $deleted_safety safety pattern line(s)"
            git diff "${c}^..${c}" -- '*.sh' 2>/dev/null | grep -E '^\-' | grep -v '^\-\-\-' | grep -E "$safety_patterns" | head -5 | while IFS= read -r line; do
                echo "    $line"
            done
            warnings=$((warnings + 1))
        fi
    done

    if [[ "$warnings" -gt 0 ]]; then
        echo "  BLOCK: $warnings commit(s) removed safety patterns. Revert safety lines or justify removal in report."
        ALL_CLEAR=false
    else
        echo "  OK: no safety patterns removed"
    fi
}
check_safety_pattern_removal

# ─── cmd_2273: 4新検証（scope drift / review staleness / partial completion / WTF） ───
check_command_files_modified_coverage

# LS086: a design handoff table is a flow contract, not documentation.  Scan
# only the approved changed-file scope; unrelated historical designs cannot
# block the current command.
echo ""
level_heading "[L4]" "Design implementation-command handoff (LS086):"
mapfile -t _ls086_changed_files < <(printf '%s\n' "$CMD_CHANGED_FILES" | awk 'NF' | sort -u)
if ! bash "$SCRIPT_DIR/scripts/gates/gate_design_cmd_handoff.sh" "${_ls086_changed_files[@]}"; then
    ALL_CLEAR=false
    record_block_reason "design_cmd_handoff_missing"
fi
check_scope_drift
check_review_staleness
check_partial_completion
check_wtf_likelihood

# ─── Loop Engineering Phase 2-2: self-grade commit/file verification（WARN only） ───
# Agent self-grade can nod along even when the actual commit does not match the report.
# Compare reported files against `git show -w --name-only` so formatting-only/no-op claims become visible.
level_heading "[L2]" "Self-grade commit/files verification:"
check_self_grade_commit_file_coverage

# dm-signalの本番deploy cmdだけ、CLEAR公開直前にAPI実測とorigin/live一致を
# 必ず通す。非deploy cmdは関数内でSKIPされ、既存の完了判定を変えない。
if [ "$ALL_CLEAR" = true ]; then
    if ! run_dm_signal_production_smoke_check; then
        record_block_reason "dm_signal_production_smoke_failed"
        ALL_CLEAR=false
    fi
fi

# ─── 軍師verdict事前チェック（cmd_3248: GATE判定前にWARN表示） ───
# GATE CLEAR後の記録処理(L6585/L6888)とは別。家老がGATE判断前に軍師指摘を把握するためのWARN。
echo ""
level_heading "[L2]" "Gunshi verdict pre-check:"
_GUNSHI_VERDICT_WARN=false
_GUNSHI_VERDICT_REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
_GUNSHI_VERDICT_ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
if [ -f "$_GUNSHI_VERDICT_REVIEW_LOG" ]; then
    _gv_precheck_result=$(
        python3 - "$CMD_ID" "$_GUNSHI_VERDICT_REVIEW_LOG" "$_GUNSHI_VERDICT_ARCHIVE_DIR" 2>/dev/null <<'END_GV_PRECHECK_PY'
import sys, re, os, glob

cmd_id = sys.argv[1]
review_log = sys.argv[2]
archive_dir = sys.argv[3]

# Newest file first.  Each file is scanned from its tail so a resolving
# LGTM/APPROVE stops all older I/O immediately.
archives = sorted(glob.glob(os.path.join(archive_dir, "gunshi_review_log*.yaml")))
sources = []
if os.path.exists(review_log):
    sources.append(review_log)
sources.extend(reversed(archives[-2:]))

def reverse_blocks(path, chunk_size=65536):
    """Yield top-level ``- cmd_id:`` blocks newest-first without full read."""
    with open(path, 'rb') as f:
        f.seek(0, os.SEEK_END)
        pos = f.tell()
        carry = b''
        lines = []
        while pos:
            size = min(chunk_size, pos)
            pos -= size
            f.seek(pos)
            data = f.read(size) + carry
            parts = data.split(b'\n')
            carry = parts.pop(0)
            for raw in reversed(parts):
                line = raw.decode('utf-8', errors='replace')
                if re.match(r'^- cmd_id:', line):
                    lines.append(line)
                    yield '\n'.join(reversed(lines))
                    lines = []
                else:
                    lines.append(line)
        if carry or lines:
            line = carry.decode('utf-8', errors='replace')
            if line:
                lines.append(line)
            if lines:
                yield '\n'.join(reversed(lines))

fail_verdicts = []
resolved = False
for src in sources:
    try:
        blocks = reverse_blocks(src)
        for entry in blocks:
            cm = re.match(r'^- cmd_id:\s*["\']?([^"\'\n]+)["\']?', entry)
            if not cm or cm.group(1).strip() != cmd_id:
                continue
            rt_m = re.search(r'review_type:\s*(\S+)', entry)
            rt = rt_m.group(1).strip('"\'') if rt_m else 'unknown'
            if rt in ('self_study', 'consultation'):
                continue
            vm = re.search(r'(?<![a-z_])verdict:\s*(\S+)', entry)
            if not vm:
                continue
            verdict = vm.group(1).strip('"\'')
            if verdict in ('LGTM', 'APPROVE'):
                resolved = True
                break
            if verdict in ('FAIL', 'REQUEST_CHANGES'):
                fs_m = re.search(r'findings_summary:\s*"([^"]*)"', entry)
                fs = fs_m.group(1) if fs_m else '(findings_summary not found)'
                fail_verdicts.append((rt, verdict, fs))
        if resolved:
            break
    except (OSError, ValueError):
        continue

if fail_verdicts:
    # Preserve the historical oldest-to-newest display order even though I/O
    # discovery runs newest-first.
    fail_verdicts.reverse()
    print("WARN")
    for rt_label, v, fs in fail_verdicts:
        print(f"  [{rt_label}] verdict={v}: {fs}")
else:
    print("OK")
END_GV_PRECHECK_PY
    ) || _gv_precheck_result="SKIP (python3 failed)"

    if [[ "$_gv_precheck_result" == WARN* ]]; then
        _GUNSHI_VERDICT_WARN=true
        echo "  [WARN] 軍師がFAIL/REQUEST_CHANGESを出しています:"
        echo "$_gv_precheck_result" | tail -n +2
        echo "  → 家老は軍師指摘を踏まえてGATE判断してください"
    elif [[ "$_gv_precheck_result" == OK* ]]; then
        echo "  OK (verdict FAIL/REQUEST_CHANGES なし)"
    else
        echo "  ${_gv_precheck_result}"
    fi
else
    echo "  SKIP (gunshi_review_log.yaml not found)"
fi

# ─── GATE CLEAR前のsource-only push ───
# GATE CLEARを先に記録してからpushすると、push失敗がWARNへ縮退して
# 「未公開のままCLEAR」という偽完了になる。remote先端へのsource-only pushと
# remote包含検証を完了してから、下のterminal CLEAR分岐へ進める。
if [ "$ALL_CLEAR" = true ] \
   && [[ "${SHOGUN_COMPLETION_GENERATION:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo ""
    echo "Git push (pre-GATE CLEAR, report source only):"
    if ! push_task_repositories "${MATCHING_TASK_FILES[@]}"; then
        record_block_reason "autopush_source_only_failed"
        ALL_CLEAR=false
    else
        echo ""
        echo "Tracked runtime publish (pre-generation checkpoint):"
        if ! publish_postclear_runtime_deltas pregate; then
            record_block_reason "pregate_runtime_publish_failed"
            ALL_CLEAR=false
        elif ! converge_shared_execution_sources "$SCRIPT_DIR" scripts/cmd_complete_gate.sh; then
            record_block_reason "shared_execution_source_convergence_failed"
            ALL_CLEAR=false
        fi
    fi
fi

# CLEAR requires both history containment and exact bytes for ordinary report
# paths.  Mutable operational records are checked by their field-aware lanes.
if [ "$ALL_CLEAR" = true ]; then
    echo ""
    level_heading "[L4]" "Report commit blob parity check:"
    if ! check_report_commit_blob_parity; then
        record_block_reason "report_commit_blob_parity"
        ALL_CLEAR=false
    fi
fi

# ─── 判定結果 ───
echo ""
if [ "$ALL_CLEAR" = true ]; then
    if [[ ! "${SHOGUN_COMPLETION_GENERATION:-}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "GATE BLOCK: ${CMD_ID}:completion_generation_missing_or_invalid"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\tcompletion_generation_missing_or_invalid' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID")"
        exit 1
    fi
    rm -f -- "$GATES_DIR/semantic_causal_audit.paths.json"
    capture_durable_writer_paths start \
        "$GATES_DIR/semantic_causal_audit.paths.before.json" \
        "$GATES_DIR/semantic_causal_audit.paths.json" \
        "$CMD_ID" "$SHOGUN_COMPLETION_GENERATION" || {
        echo "GATE BLOCK: ${CMD_ID}:postclear_generation_snapshot_failed" >&2
        exit 1
    }
    GATE_CLEAR_TS="$(date +%Y-%m-%dT%H:%M:%S)"
    GATE_DURATION_METRIC=$(build_clear_duration_metric)
    GATE_THROUGHPUT_METRIC=$(build_clear_throughput_metric "$GATE_CLEAR_TS")
    GATE_CTX_METRIC=$(build_clear_ctx_metric)
    GATE_KARO_CTX_METRIC=$(build_karo_ctx_metric)
    if ! run_cdp_production_check; then
        echo "GATE BLOCK: ${CMD_ID}:cdp_production_check_failed"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\tcdp_production_check_failed\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$GATE_CLEAR_TS" "$CMD_ID" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_DURATION_METRIC" "$GATE_THROUGHPUT_METRIC" "$GATE_CTX_METRIC" "$GATE_KARO_CTX_METRIC" "$GATE_FIRST_MODEL_METRIC")"
        exit 1
    fi
    # cmd_3862 RC: 観測イベントはCLEAR通知・完了後処理より先に同期永続化する。
    # 非同期失敗を握り潰すと観測経路バイパスが再発するため、失敗時は通知せずBLOCKする。
    if ! capture_completed_rework_event "$CMD_ID"; then
        echo "GATE BLOCK: ${CMD_ID}:rework_event_capture_failed"
        append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\trework_event_capture_failed\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$GATE_CLEAR_TS" "$CMD_ID" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_DURATION_METRIC" "$GATE_THROUGHPUT_METRIC" "$GATE_CTX_METRIC" "$GATE_KARO_CTX_METRIC" "$GATE_FIRST_MODEL_METRIC")"
        exit 1
    fi
    # The wrapper's durable worker waits for this generation-bound marker,
    # rather than for this gate process to finish. Everything above this point
    # is fail-closed; everything below remains in that same durable worker.
    if [ -n "${CMD_COMPLETE_GATE_CLEAR_MARKER:-}" ]; then
        if ! python3 - "$CMD_COMPLETE_GATE_CLEAR_MARKER" "$CMD_ID" \
            "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, os, sys, tempfile, time
path, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "state": "clear", "cmd_id": cmd_id,
        "completion_generation": generation, "persisted_at_ns": time.time_ns()}
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".gate_worker_clear.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
        then
            echo "GATE BLOCK: ${CMD_ID}:durable_clear_marker_persist_failed"
            append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tBLOCK\tdurable_clear_marker_persist_failed' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID")"
            exit 1
        fi
    fi
    echo "GATE CLEAR: cmd完了許可"
    # Post-decision and detached: telemetry failure must never reverse CLEAR.
    # shellcheck source=scripts/lib/defense_overhead_writer.sh
    source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
    self_retro_write_async shogun_gate_clear "$CMD_ID" 0 '{"gate_clear":0}' gate_clear \
      "all command gates passed" "reduce dominant gate phase without weakening checks" \
      "CLEAR remains stable and duplicate event count is 0" \
      "[[gate_clear]] -> [[self_retro]] -> [[fix_known]]"
    source "$SCRIPT_DIR/scripts/lib/retro_pane_prompt.sh"
    retro_pane_prompt_async "$SCRIPT_DIR" shogun "gate_clear:$CMD_ID" cmd_complete_gate
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\tCLEAR\tall_gates_passed\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$GATE_CLEAR_TS" "$CMD_ID" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_DURATION_METRIC" "$GATE_THROUGHPUT_METRIC" "$GATE_CTX_METRIC" "$GATE_KARO_CTX_METRIC" "$GATE_FIRST_MODEL_METRIC")"
    log_skill_execution_pass "cmd-complete" "cmd_complete_gate" "$CMD_ID"
    (bash "$SCRIPT_DIR/scripts/rotate_gate_metrics.sh" >/dev/null 2>&1 || true) &
    # gate_yaml_status: YAML status更新（WARNING only）
    (bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" >/dev/null 2>&1 || true) &
    echo "gate_yaml_status: queued (async)"
    if status_output=$(update_status "$CMD_ID" 2>&1); then
        echo "$status_output"
        if ! echo "$status_output" | grep -qE "STATUS UPDATED|STATUS ALREADY COMPLETED"; then
            echo "  [ERROR] UPDATE_STATUS_VERIFY: expected STATUS UPDATED/ALREADY COMPLETED but got: $status_output"
        fi
    else
        echo "$status_output"
        echo "  [INFO] update_status failed (non-blocking)"
    fi
    if closed_alert_count=$(close_resolved_gate_alerts "$CMD_ID" 2>>"$LOG_DIR/cmd_complete_gate_stderr.log"); then
        echo "Gate alert closure: ${closed_alert_count:-0} alert(s) closed"
    else
        echo "  [WARN] gate alert closure failed (non-blocking)"
    fi
    (update_karo_workaround_resolutions "$CMD_ID" >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 || echo "  [WARN] karo workaround resolution update failed (non-blocking)" >> "$LOG_DIR/cmd_complete_gate_async.log") &
    echo "Karo workaround resolution update: queued (async)"
    (append_changelog "$CMD_ID" >/dev/null 2>&1 || true) &
    echo "CHANGELOG: queued (async)"

    echo ""
    echo "Lesson feedback recording (pre-impact scan):"
    (record_lesson_feedback_for_cmd >/dev/null 2>&1 || true) &
    echo "  lesson feedback: queued (async)"

    (append_lesson_tracking "$CMD_ID" "CLEAR" >/dev/null 2>&1 || true) &
    echo "LESSON_TRACKING: queued (async)"
    (update_lesson_impact_tsv "$CMD_ID" "CLEAR" >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 || echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)" >> "$LOG_DIR/cmd_complete_gate_async.log") &
    echo "  lesson impact tsv: queued (async)"
    queue_lesson_impact_followup

    echo ""
    echo "Semantic index update (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/semantic_index_update.sh" ]; then
        if _semantic_payload=$(CMD_ID_ENV="$CMD_ID" CMD_TITLE_ENV="${CMD_TITLE:-}" CMD_PURPOSE_ENV="${CMD_PURPOSE:-}" CMD_CHANGED_FILES_ENV="${CMD_CHANGED_FILES:-}" CMD_YAML_FILE_ENV="$YAML_FILE" python3 - <<'PY' 2>/dev/null
import json
import os

files_raw = os.environ.get("CMD_CHANGED_FILES_ENV", "")
files = [p.strip() for p in files_raw.replace(",", "\n").splitlines() if p.strip()]

cmd_id = os.environ.get("CMD_ID_ENV", "")
cmd_data = {}
yaml_file = os.environ.get("CMD_YAML_FILE_ENV", "")
if yaml_file:
    try:
        import yaml
        with open(yaml_file, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        if isinstance(data, dict):
            raw_cmd = data.get(cmd_id)
            if raw_cmd is None and isinstance(data.get("commands"), dict):
                raw_cmd = data["commands"].get(cmd_id)
            if isinstance(raw_cmd, dict):
                cmd_data = raw_cmd
    except Exception:
        cmd_data = {}

print(json.dumps({
    "id": os.environ.get("CMD_ID_ENV", ""),
    "title": os.environ.get("CMD_TITLE_ENV", ""),
    "purpose": os.environ.get("CMD_PURPOSE_ENV", ""),
    "files": files,
    "origin": cmd_data.get("origin", ""),
    "depends_on": cmd_data.get("depends_on", ""),
}, ensure_ascii=False))
PY
        ); then
            _semantic_payload_file="$GATES_DIR/semantic_causal_payload.json"
            printf '%s\n' "$_semantic_payload" > "${_semantic_payload_file}.tmp.$$"
            mv "${_semantic_payload_file}.tmp.$$" "$_semantic_payload_file"
            echo "  payload persisted for durable worker"
        else
            echo "  [WARN] payload build failed (skip)"
        fi
    else
        echo "  [INFO] semantic_index_update.sh not found (skip)"
    fi
    echo "  semantic-map regeneration follows index update inside durable worker"
    run_report_memory_semantic_scan || echo "  [WARN] report memory semantic scan failed (non-blocking)"

    # ─── Semantic causal traverse（GATE CLEAR時 パルス伝達, cmd_3439） ───
    # Long-running affected-node tests are detached, but never best-effort:
    # the worker owns a per-cmd lock and persists PASS/WARN/FAIL evidence.
    echo ""
    echo "Semantic causal traverse (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/semantic_causal_post_clear.sh" ]; then
        _semantic_pending="$GATES_DIR/semantic_causal_audit.pending"
        _semantic_result="$GATES_DIR/semantic_causal_audit.result"
        _semantic_generation_marker="$GATES_DIR/semantic_causal_audit.generation.json"
        _semantic_path_snapshot="$GATES_DIR/semantic_causal_audit.paths.before.json"
        _semantic_path_manifest="$GATES_DIR/semantic_causal_audit.paths.json"
        rm -f -- "$_semantic_result"
        python3 - "$_semantic_generation_marker" "$_semantic_pending" "$CMD_ID" \
            "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, os, sys, tempfile
path, pending, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "cmd_id": cmd_id,
        "completion_generation": generation, "pending": pending}
fd, tmp = tempfile.mkstemp(prefix=".semantic_generation.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
        printf 'queued_at=%s\nlauncher_pid=%s\ncmd_id=%s\ncompletion_generation=%s\n' \
            "$(date -Iseconds)" "$$" "$CMD_ID" "$SHOGUN_COMPLETION_GENERATION" > "${_semantic_pending}.tmp.$$"
        mv "${_semantic_pending}.tmp.$$" "$_semantic_pending"
        # nohup alone only ignores SIGHUP; tmux respawn-pane -k terminates the
        # pane process group.  setsid detaches the durable worker from it.
        # semantic_causal_post_clear runs semantic_map_generate.sh synchronously
        # after semantic_index_update.  Suppress the update script's additional
        # background generator so no child can write semantic-map after the
        # durable path manifest has been published.
        nohup setsid env SHOGUN_HEAVY_JOB_LOCK_HELD=0 SCRIPT_DIR="$SCRIPT_DIR" \
            SEMANTIC_MAP_GENERATE=/bin/true \
            bash -c 'bash "$1/scripts/semantic_causal_post_clear.sh" "$2"' \
            _ "$SCRIPT_DIR" "$CMD_ID" "$_semantic_path_snapshot" "$_semantic_path_manifest" "$SHOGUN_COMPLETION_GENERATION" \
            >/dev/null 2>&1 </dev/null &
        echo "  queued (durable async; result=$GATES_DIR/semantic_causal_audit.result)"
    else
        echo "  [WARN] semantic_causal_post_clear.sh not found"
    fi

    echo ""
    echo "Context freshness doc-lane warning (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/context_freshness_check.sh" ]; then
        (
            warning_output=$(bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --cmd-warnings "$CMD_ID" 2>&1 || true)
            warning_file="$GATES_DIR/context_freshness_doc_lane.warning"
            warning_tmp="${warning_file}.tmp.$$"
            {
                printf 'cmd_id: %s\n' "$CMD_ID"
                printf 'timestamp: %s\n' "$(date -Iseconds)"
                if [ -n "$warning_output" ]; then
                    printf 'result: warning\n'
                    printf '%s\n' "$warning_output"
                else
                    printf 'result: clear\n'
                fi
            } > "$warning_tmp" && mv "$warning_tmp" "$warning_file"

            if [ -n "$warning_output" ] && [ -x "$SCRIPT_DIR/scripts/bulletin_write.sh" ]; then
                warning_summary=$(printf '%s\n' "$warning_output" | head -80)
                BULLETIN_NOTIFY=shogun bash "$SCRIPT_DIR/scripts/bulletin_write.sh" \
                    cmd_complete_gate \
                    "DOC_LANE_WARNING: ${CMD_ID} のcontext freshness警告。doc更新は将軍laneで処理されたし。${warning_summary}" \
                    false action_required >/dev/null 2>&1 || true
            fi
        ) &
        echo "  queued (async; warning receipt=$GATES_DIR/context_freshness_doc_lane.warning, route=shogun-doc-lane)"
    else
        echo "  [INFO] context_freshness_check.sh not found (skip)"
    fi

    # ─── lesson_merge自動実行（ベストエフォート） ───
    echo ""
    echo "Lesson merge (auto):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_merge.sh" ]; then
        (bash "$SCRIPT_DIR/scripts/lesson_merge.sh" >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 || true) &
        echo "  lesson_merge: queued (async)"
    else
        echo "  [GATE] lesson_merge: SKIP (script not found)"
    fi

    # ─── lesson score自動更新（GATE CLEAR時のみ、ベストエフォート） ───
    echo ""
    echo "Lesson score update (helpful):"
    if [ -n "$CMD_PROJECT" ]; then
        SCORE_UPDATED=0
        ALL_SCORE_ENTRIES=""
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            if [ ! -f "$task_file" ]; then
                echo "  [WARN] matching task file disappeared, skipping: $task_file"
                MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
                continue
            fi
            MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name")
            if [ -f "$report_file" ]; then
                # lessons_useful/lesson_referenced からexplicit IDs抽出
                _se_explicit=$(awk '
                    /^lessons_useful:/ || /^lesson_referenced:/ { sec=1; next }
                    sec && /^[a-zA-Z]/ { sec=0 }
                    sec && /id:/ { v=$0; sub(/.*id:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); gsub(/[[:space:]]/, "", v); if (v != "" && !seen[v]++) print v }
                ' "$report_file" 2>/dev/null)
                # related_lessons から IDs抽出
                _se_related=$(awk '
                    /^[[:space:]]+related_lessons:/ { sec=1; next }
                    sec && /^[[:space:]]+[^ -]/ && !/^[[:space:]]+- / { sec=0 }
                    sec && /id:/ { v=$0; sub(/.*id:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); gsub(/[[:space:]]/, "", v); if (v != "" && !seen[v]++) print v }
                ' "$task_file" 2>/dev/null)
                score_entries=""
                # explicit entries
                while IFS= read -r _se_lid; do
                    [ -z "$_se_lid" ] && continue
                    score_entries="${score_entries}explicit	${_se_lid}
"
                done <<< "$_se_explicit"
                # auto entries: related IDs not in explicit, found in report text
                _se_explicit_list="|${_se_explicit//$'\n'/|}|"
                while IFS= read -r _se_rlid; do
                    [ -z "$_se_rlid" ] && continue
                    # skip if already explicit
                    case "$_se_explicit_list" in *"|${_se_rlid}|"*) continue ;; esac
                    # word-boundary check in report text
                    if grep -qP "(?<![A-Za-z0-9_])$(printf '%s' "$_se_rlid" | sed 's/[.[\*^$()+?{|\\]/\\&/g')(?![A-Za-z0-9_])" "$report_file" 2>/dev/null; then
                        score_entries="${score_entries}auto	${_se_rlid}
"
                    fi
                done <<< "$_se_related"
                while IFS=$'\t' read -r score_type lid; do
                    [ -z "$score_type" ] && continue
                    [ -z "$lid" ] && continue
                    ALL_SCORE_ENTRIES="${ALL_SCORE_ENTRIES}${score_type}	${lid}
"
                    SCORE_UPDATED=$((SCORE_UPDATED + 1))
                done <<< "$score_entries"
            fi
        done
        if [ -n "$ALL_SCORE_ENTRIES" ]; then
            update_lesson_scores_batch "$CMD_PROJECT" "$ALL_SCORE_ENTRIES" || echo "  [INFO] lesson score batch update failed (non-blocking)"
        else
            echo "  Updated: 0 lesson(s)"
        fi
    elif [ -z "$CMD_PROJECT" ]; then
        echo "  SKIP (project not found in cmd)"
    fi

    append_codd_registry_entry "$CMD_ID"
    echo ""
    echo "CoDD propagate update (GATE CLEAR):"
    (run_codd_propagate_update >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 || true) &
    echo "  queued (async)"

    echo ""
    echo "SKILL.md script refs (GATE CLEAR):"
    (run_skill_script_refs_check >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 || true) &
    echo "  queued (async)"
    write_l6_horizontal_level5_insights "$CMD_ID"
    echo ""
    echo "Insight auto-triage (cmd-related):"
    # cmd_karo_hotfix_post_clear_fail_open_20260725 (AC1): このステップの失敗で
    # Auto-notification/Bulletin/Task idle transition等の後続ステップ全てを
    # 道連れにしていた(cmd_4171実証: hayateがdoneのまま取り残された)。他の後続
    # ステップと同じくfail-openにし、失敗はWARNとして明示するが後続へは進める。
    if ! auto_resolve_cmd_related_insights "$CMD_ID"; then
        echo "  [WARN] Insight auto-triage failed (non-blocking, GATE CLEAR continues)"
    fi

    # ─── GATE CLEAR時 自動通知（ベストエフォート） ───
    echo ""
    echo "Auto-notification (GATE CLEAR):"

    # dashboard_update removed (殿裁定2026-08-17: dashboardは誰も使っていない。
    # flock競合で最大124s遅延のボトルネックだったため除外)
    echo "  dashboard_update: SKIP (removed by lord ruling 2026-08-17)"

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    (bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once >/dev/null 2>&1 || true) &
    echo "  gist_sync: queued (async)"

    # GATE結果通知より先にreview_logへ同期し、/gate-sync手動依存を残さない。
    echo ""
    echo "Gunshi gate_result reflux (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" "$CMD_ID" "CLEAR" 2>&1; then
            echo "  gunshi_gate_reflux: OK"
        else
            echo "  [INFO] gunshi_gate_reflux: WARN (non-blocking)"
        fi
    else
        echo "  SKIP (gunshi_gate_reflux.sh not found)"
    fi

    # ntfy_cmd / shogun / karo は未送信時だけ補完。

    # ─── 掲示板自動投稿（GATE CLEAR時、将軍が/clear後に即把握できるよう） ───
    echo ""
    echo "Bulletin board (GATE CLEAR):"
    _blt_title=""
    _blt_title=$(awk -v cmd="$CMD_ID" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        cur_id == cmd && /title:/ { sub(/.*title:[[:space:]]*"?/, ""); sub(/"?$/, ""); print; exit }
    ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)
    (BULLETIN_NOTIFY=karo,gunshi timeout 10 bash "$SCRIPT_DIR/scripts/bulletin_write.sh" "GATE CLEAR ${CMD_ID}: ${_blt_title:-完了}" false >/dev/null 2>&1 || true) &
    echo "  bulletin: queued (async)"

    # ─── gunshi review_feedback自動送信（GATE CLEAR） ───
    # GP-209: dedup — 同一cmd+同一resultが既にinboxにあればスキップ
    echo ""
    echo "Gunshi review_feedback (GATE CLEAR):"
    if grep -q "${CMD_ID} gate_result: CLEAR" "$SCRIPT_DIR/queue/inbox/gunshi.yaml" 2>/dev/null; then
        echo "  gunshi review_feedback: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" gunshi "${CMD_ID} gate_result: CLEAR" gate_clear system 2>/dev/null; then
        echo "  gunshi review_feedback: OK (CLEAR)"
    else
        echo "  [INFO] gunshi review_feedback: WARN (non-blocking)"
    fi

    # ─── GATE CLEAR時 淘汰候補自動deprecate（ベストエフォート） ───
    echo ""
    echo "Auto-deprecate check (unused - GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/knowledge_metrics.sh" ] && [ -f "$SCRIPT_DIR/scripts/lesson_write.sh" ]; then
        (
            UNUSED_DEPRECATE_COUNT=0
            if metrics_json=$(bash "$SCRIPT_DIR/scripts/knowledge_metrics.sh" --json 2>/dev/null); then
                elimination_ids=$(echo "$metrics_json" | jq -r '.elimination_candidates[]? | select(.lesson_id != "" and .lesson_id != null and .project != "" and .project != null) | [.lesson_id, .project, (.inject_count // 0 | tostring)] | join("\t")' 2>/dev/null)
                if [ -n "$elimination_ids" ]; then
                    while IFS=$'\t' read -r lid project injected; do
                        [ -z "$lid" ] && continue
                        bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$project" --retire "$lid" >/dev/null 2>&1 || true
                        UNUSED_DEPRECATE_COUNT=$((UNUSED_DEPRECATE_COUNT + 1))
                    done <<< "$elimination_ids"
                fi
                echo "[async][deprecate] Auto-retired (unused): ${UNUSED_DEPRECATE_COUNT} lesson(s)"
            else
                echo "[async][deprecate] SKIP (knowledge_metrics.sh failed)"
            fi
        ) >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 &
        echo "  auto-retire: queued (async)"
    else
        echo "  SKIP (knowledge_metrics.sh or lesson_write.sh not found)"
    fi

    # cmd_531: AC6 — GATE CLEAR時に教訓有効率スキャン+自動退役
    echo ""
    echo "Lesson effectiveness scan (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" ]; then
        (bash "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" --project all >/dev/null 2>&1 || true) &
        echo "  lesson_deprecation_scan: queued (async)"
    else
        echo "  SKIP (lesson_deprecation_scan.sh not found)"
    fi

    # ─── cmd品質ログ記録（GATE CLEAR時、ベストエフォート） ───
    # 同期実行必須(INS-20260709-000457431-b624): gate_metrics.logへのCLEAR記録(line ~7533)は
    # 同期書込みのため即座に確定するが、本呼出しを非同期&にすると、家老セッション境界
    # (/clear respawn等)がプロセスグループごと本ジョブを道連れにした場合、
    # gate_metrics.logにはCLEARが残るのにcmd_design_quality.yamlだけ欠落する
    # (=品質記録漏れ)。GATE BLOCK側(下記)は元々同期呼出しであり、対称性のためCLEAR側も揃える。
    echo ""
    echo "Cmd quality log (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/cmd_quality_log.sh" ]; then
        _quality_karo_rework="no"
        if [ -f "$SCRIPT_DIR/queue/gates/$CMD_ID/review_approvals/karo_rework.seen" ]; then
            _quality_karo_rework="yes"
        fi
        if bash "$SCRIPT_DIR/scripts/cmd_quality_log.sh" "$CMD_ID" "CLEAR" "$_quality_karo_rework" "0" >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1; then
            echo "  cmd_quality_log: OK"
        else
            echo "  [INFO] cmd_quality_log: WARN (logging failed, non-blocking)"
        fi
    else
        echo "  SKIP (cmd_quality_log.sh not found)"
    fi

    # ─── gunshi_verdict自動更新（GATE CLEAR時、cmd_design_quality.yaml） ───
    echo ""
    echo "Gunshi verdict update to cmd_design_quality (GATE CLEAR):"
    _GV_REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
    _GV_ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
    _GV_DQ_FILE="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
    if [ -f "$_GV_DQ_FILE" ] && [ -f "$_GV_REVIEW_LOG" ]; then
        _gv_result=$(
            (
                flock -w 10 200 || exit 1
                python3 - "$CMD_ID" "$_GV_REVIEW_LOG" "$_GV_ARCHIVE_DIR" "$_GV_DQ_FILE" 2>/dev/null <<'END_GV_PY'
import sys, re, os, glob, tempfile

cmd_id = sys.argv[1]
review_log = sys.argv[2]
archive_dir = sys.argv[3]
dq_file = sys.argv[4]

# データソース: gunshi_review_log.yaml + archive直近2ファイル
sources = []
if os.path.exists(review_log):
    sources.append(review_log)
archives = sorted(glob.glob(os.path.join(archive_dir, "gunshi_review_log*.yaml")))
sources.extend(archives[-2:])

# draft verdictを取得: REQUEST_CHANGESが一度でも出た場合はそちらを優先
found_rc = False
found_approve = False
for src in sources:
    try:
        with open(src, encoding='utf-8') as f:
            content = f.read()
    except Exception:
        continue
    for m in re.finditer(r'^- cmd_id:.*?(?=^- cmd_id:|\Z)', content, re.MULTILINE | re.DOTALL):
        entry = m.group(0)
        cm = re.match(r'^- cmd_id:\s*["\']?([^"\'\n]+)["\']?', entry)
        if not cm or cm.group(1).strip() != cmd_id:
            continue
        if 'review_type: draft' not in entry:
            continue
        vm = re.search(r'(?<![a-z_])verdict:\s*(\S+)', entry)
        if vm:
            v = vm.group(1).strip('"\'')
            if v == 'REQUEST_CHANGES':
                found_rc = True
            elif v == 'APPROVE':
                found_approve = True

if found_rc:
    new_verdict = 'REQUEST_CHANGES'
elif found_approve:
    new_verdict = 'LGTM'
else:
    print(f"[INFO] {cmd_id}: no draft verdict found, keeping existing")
    sys.exit(0)

# cmd_design_quality.yaml の対象cmd_idエントリのgunshi_verdictを更新
try:
    with open(dq_file, encoding='utf-8') as f:
        lines = f.readlines()
except Exception as e:
    print(f"[ERROR] Failed to read {dq_file}: {e}")
    sys.exit(0)

updated = 0
in_entry = False
match_entry = False
new_lines = []
for line in lines:
    if re.match(r'\s*- cmd_id:', line):
        cid_m = re.search(r'cmd_id:\s*["\']?([^"\'\n]+)["\']?', line)
        match_entry = bool(cid_m and cid_m.group(1).strip() == cmd_id)
        in_entry = True
    elif line.strip() and not line.startswith(' ') and not line.startswith('\t') and not line.strip().startswith('#'):
        in_entry = False
        match_entry = False
    if match_entry and re.match(r'\s+gunshi_verdict:', line):
        new_lines.append(re.sub(r'(gunshi_verdict:\s*)["\']?[^"\'\n]*["\']?', f'\\1"{new_verdict}"', line))
        updated += 1
    else:
        new_lines.append(line)

if updated > 0:
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(dq_file), suffix='.tmp')
        os.close(tmp_fd)
        with open(tmp_path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        os.replace(tmp_path, dq_file)
        print(f"{cmd_id}: gunshi_verdict → {new_verdict} ({updated} entries updated)")
    except Exception as e:
        print(f"[ERROR] Failed to write {dq_file}: {e}")
else:
    print(f"[INFO] {cmd_id}: no matching entries found in cmd_design_quality.yaml")
END_GV_PY
            ) 200>"$(lock_path "$_GV_DQ_FILE")"
        ) || _gv_result="[INFO] gunshi_verdict update failed (non-blocking)"
        echo "  ${_gv_result}"
    else
        echo "  SKIP (cmd_design_quality.yaml or gunshi_review_log.yaml not found)"
    fi

    # ─── GATE CLEAR時 insight候補通知（cmd_1217: lesson_candidate/decision_candidate found:true検出） ───
    echo ""
    echo "Insight candidate detection (GATE CLEAR):"
    INSIGHT_TMP=$(mktemp)
    trap 'rm -f "$INSIGHT_TMP"' EXIT
    INSIGHT_COUNT=0
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue

        insight_line=$(awk '
            /lesson_candidate:/{sec="lc"; next}
            /decision_candidate:/{sec="dc"; next}
            /knowledge_candidate:/{sec="kc"; next}
            /^[^ ]/ && sec!=""{sec=""}
            sec=="lc" && /found: true/{lc_found=1}
            sec=="lc" && /title:/ && !lc_title{t=$0; sub(/.*title:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); lc_title=t}
            sec=="lc" && /summary:/ && !lc_title{t=$0; sub(/.*summary:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); lc_title=t}
            sec=="dc" && /found: true/{dc_found=1}
            sec=="dc" && /title:/ && !dc_title{t=$0; sub(/.*title:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            sec=="dc" && /summary:/ && !dc_title{t=$0; sub(/.*summary:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            sec=="dc" && /question:/ && !dc_title{t=$0; sub(/.*question:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            sec=="kc" && /found: true/{kc_found=1}
            sec=="kc" && /fact:/ && !kc_fact{t=$0; sub(/.*fact:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); kc_fact=t}
            END{
                out=""
                if(lc_found){t=substr(lc_title,1,80); out="LC: " (t?t:"(untitled)")}
                if(dc_found){t=substr(dc_title,1,80); if(out) out=out " / "; out=out "DC: " (t?t:"(untitled)")}
                if(kc_found){t=substr(kc_fact,1,80); if(out) out=out " / "; out=out "KC: " (t?t:"(new fact)")}
                if(out) print out
            }
        ' "$report_file" 2>/dev/null)

        if [ -n "$insight_line" ]; then
            INSIGHT_COUNT=$((INSIGHT_COUNT + 1))
            echo "  ${ninja_name}: ${insight_line}"
            echo "${ninja_name}: ${insight_line}" >> "$INSIGHT_TMP"
        fi
    done

    if [ "$INSIGHT_COUNT" -gt 0 ]; then
        DASHBOARD="$SCRIPT_DIR/dashboard.md"
        if [ -f "$DASHBOARD" ]; then
            # Build insert text from INSIGHT_TMP
            _insight_insert=""
            while IFS= read -r _note; do
                [ -z "$_note" ] && continue
                _insight_insert="${_insight_insert}- [INSIGHT] ${CMD_ID} ${_note}\n"
            done < "$INSIGHT_TMP"
            if [ -n "$_insight_insert" ]; then
                (
                    flock -w 10 200 || exit 1
                    awk -v ins="$_insight_insert" '
                        { print }
                        /^## 将軍宛報告[[:space:]]*$/ { printf "%s", ins }
                    ' "$DASHBOARD" > "${DASHBOARD}.tmp"
                    if [ -s "${DASHBOARD}.tmp" ]; then
                        mv "${DASHBOARD}.tmp" "$DASHBOARD"
                    else
                        rm -f "${DASHBOARD}.tmp"
                        echo "  [INFO] dashboard insight append produced empty output, keeping existing file" >&2
                    fi
                ) 200>"$(lock_path "$DASHBOARD")" 2>/dev/null \
                    || echo "  [INFO] dashboard insight append failed (non-blocking)"
            fi
            echo "  Notified: ${INSIGHT_COUNT} insight candidate(s) → dashboard 将軍宛セクション"
        fi
    else
        echo "  OK: no insight candidates (found:true=0)"
    fi
    rm -f "$INSIGHT_TMP"

    # ─── lesson_candidate未登録 WARN + register_recommended自動登録（cmd_1256, cmd_2697） ───
    echo ""
    echo "Lesson candidate registration check (GATE CLEAR):"
    LC_WARN_COUNT=0
    LC_AUTO_REG_COUNT=0
    for task_file in "${MATCHING_TASK_FILES[@]}"; do
        if [ ! -f "$task_file" ]; then
            echo "  [WARN] matching task file disappeared, skipping: $task_file"
            MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
            continue
        fi
        MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue

        # Extract lesson_candidate fields including register_recommended (1 python3 spawn)
        _lc_action=skip _lc_title="" _lc_reg=false _lc_project="" _lc_detail="" _lc_source="" _lc_author=auto_gate
        _lc_subdomain="" _lc_target_files="" _lc_origin="" _lc_when="" _lc_how=""
        if _lc_raw=$(REPORT_PATH="$report_file" python3 - 2>/dev/null <<'PYEOF'
import yaml, os, sys, shlex
report_path = os.environ["REPORT_PATH"]
try:
    with open(report_path, encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
lc = data.get("lesson_candidate", {})
if not isinstance(lc, dict) or not lc.get("found"):
    sys.exit(0)
title = str(lc.get("title", "") or "").strip()
detail = str(lc.get("detail", "") or "").strip()
project = str(lc.get("project", "") or "").strip()
reg = bool(lc.get("register_recommended"))
source_cmd = str(data.get("parent_cmd", "") or data.get("task_id", "") or "").strip()
worker_id = str(data.get("worker_id", "") or "auto_gate").strip()

def csv_value(value):
    if isinstance(value, list):
        return ",".join(str(v).strip() for v in value if str(v).strip())
    return str(value or "").strip()

def collect_target_files(report, lesson_candidate):
    raw = lesson_candidate.get("target_files") or []
    if isinstance(raw, str):
        paths = [p.strip() for p in raw.split(",")]
    elif isinstance(raw, list):
        paths = [str(p).strip() for p in raw]
    else:
        paths = []
    if not paths:
        files = report.get("files_modified") or []
        if isinstance(files, str):
            paths = [files.strip()]
        elif isinstance(files, list):
            for item in files:
                if isinstance(item, dict):
                    path = item.get("path") or item.get("file") or item.get("name")
                else:
                    path = item
                if path:
                    paths.append(str(path).strip())
    seen = set()
    result = []
    for path in paths:
        if not path or path in seen:
            continue
        seen.add(path)
        result.append(path)
        if len(result) >= 5:
            break
    return ",".join(result)

def normalize_subdomain(value):
    aliases = {
        "frontend": "fe", "front": "fe", "ui": "fe",
        "backend": "be", "back": "be", "api": "be", "ops": "be",
        "grid_search": "gs", "grid-search": "gs", "gridsearch": "gs",
        "platform": "infra",
    }
    parts = [p.strip() for p in csv_value(value).split(",") if p.strip()]
    normalized = []
    for part in parts:
        part = aliases.get(part, part)
        if part in {"fe", "be", "gs", "infra"} and part not in normalized:
            normalized.append(part)
    return ",".join(normalized)

def infer_subdomain(project_id, title_text, detail_text, tags_value, target_files_csv):
    explicit = normalize_subdomain(lc.get("subdomain") or lc.get("subdomains"))
    if explicit:
        return explicit
    if project_id == "infra":
        return "infra"
    haystack = " ".join([
        project_id,
        title_text,
        detail_text,
        csv_value(tags_value),
        target_files_csv,
    ]).lower()
    if project_id == "dm-signal":
        if any(k in haystack for k in ["scripts/gates/", "lesson_write", "cmd_complete_gate", "deploy_task", "inbox_", "ninja_monitor", "semantic"]):
            return "infra"
        if any(k in haystack for k in ["run_077", "grid_search", "grid search", "grid-search", " gs", "gs-", "gs_", "l0", "l1", "l2", "l3", "blob", "monthly", "daily_prices", "price path", "価格", "系列preflight"]):
            return "gs"
        if any(k in haystack for k in ["frontend", "next", "react", "component", "chart", "ui", "css", "app/", "components/"]):
            return "fe"
        if any(k in haystack for k in ["database", "db", "api", "recalculate", "fullrecalculate", "portfolio", "pf", "migration", "cron", "production", "prices"]):
            return "be"
    return ""

tags = lc.get("tags", "")
target_files = collect_target_files(data, lc)
subdomain = infer_subdomain(project, title, detail, tags, target_files)
origin = str(lc.get("origin", "") or "").strip()
when = str(lc.get("when", "") or "").strip()
how = str(lc.get("how", "") or "").strip()
if not title:
    sys.exit(0)
print(f"_lc_action=check")
print(f"_lc_title={shlex.quote(title[:80])}")
print(f"_lc_reg={'true' if reg else 'false'}")
print(f"_lc_project={shlex.quote(project)}")
print(f"_lc_detail={shlex.quote(detail)}")
print(f"_lc_source={shlex.quote(source_cmd)}")
print(f"_lc_author={shlex.quote(worker_id or 'auto_gate')}")
print(f"_lc_subdomain={shlex.quote(subdomain)}")
print(f"_lc_target_files={shlex.quote(target_files)}")
print(f"_lc_origin={shlex.quote(origin)}")
print(f"_lc_when={shlex.quote(when)}")
print(f"_lc_how={shlex.quote(how)}")
PYEOF
); then
            eval "$_lc_raw"
        fi

        if [ "$_lc_action" = "check" ]; then
            if lesson_done_satisfies_lesson_candidate_registration "$GATES_DIR/lesson.done"; then
                echo "  OK: lesson_candidate already registered (${ninja_name}, lesson.done)"
            elif [ "$_lc_reg" = "true" ] && [ -n "$_lc_project" ] && [ -n "$_lc_source" ]; then
                # register_recommended:true → auto lesson_write (cmd_2697)
                echo "  AUTO-REGISTER: ${ninja_name}: ${_lc_title} (register_recommended:true)"
                _lc_lesson_flags=()
                [ -n "$_lc_subdomain" ] && _lc_lesson_flags+=(--subdomain "$_lc_subdomain")
                [ -n "$_lc_target_files" ] && _lc_lesson_flags+=(--target-files "$_lc_target_files")
                [ -n "$_lc_origin" ] && _lc_lesson_flags+=(--origin "$_lc_origin")
                [ -n "$_lc_when" ] && _lc_lesson_flags+=(--when "$_lc_when")
                [ -n "$_lc_how" ] && _lc_lesson_flags+=(--how "$_lc_how")
                if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$_lc_project" "$_lc_title" "$_lc_detail" "$_lc_source" "$_lc_author" "$_lc_source" "${_lc_lesson_flags[@]}" 2>&1; then
                    echo "  [OK] lesson_write: registered (${ninja_name})"
                    LC_AUTO_REG_COUNT=$((LC_AUTO_REG_COUNT + 1))
                else
                    echo "  [WARN] lesson_write: failed for ${ninja_name} (non-blocking)"
                    LC_WARN_COUNT=$((LC_WARN_COUNT + 1))
                fi
            elif [ -n "$_lc_title" ]; then
                LC_WARN_COUNT=$((LC_WARN_COUNT + 1))
                echo "  WARN: lesson_candidate未登録 — ${ninja_name}: ${_lc_title} — lesson_write.shで登録せよ"
            fi
        fi
    done
    if [ "$LC_WARN_COUNT" -eq 0 ] && [ "$LC_AUTO_REG_COUNT" -eq 0 ]; then
        echo "  OK: no pending lesson_candidates"
    fi

    # ─── Workaround率表示（情報のみ、BLOCKしない） ───
    echo ""
    echo "Workaround rate (GATE CLEAR):"
    if [ -x "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" ]; then
        bash "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" --last 10 2>&1 || echo "  [INFO] gate_workaround_rate.sh failed (non-blocking)"
    else
        echo "  SKIP (gate_workaround_rate.sh not found)"
    fi

    # ─── 第三層loop健全性チェック（GATE CLEAR時、自動insight起票+情報表示） ───
    echo ""
    echo "Loop health (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/gates/gate_loop_health.sh" ]; then
        (
            loop_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_loop_health.sh" 2>&1) || true
            if echo "$loop_output" | grep -q "Auto-Insight"; then
                echo "$loop_output" | grep -E "CREATED:|計.*件" | head -5
            fi
            if echo "$loop_output" | grep -q "WARNING:"; then
                echo "  [WARN] $(echo "$loop_output" | grep 'WARNING:' | head -1)"
            else
                echo "  OK"
            fi
        ) >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 &
        echo "  queued (async)"
    else
        echo "  SKIP (gate_loop_health.sh not found)"
    fi

    # ─── 教訓フィードバック記録（GATE CLEAR後、archive前） ───
    # karo_idle_fix: 報告YAMLのlessons_usefulをlesson_impact.tsvに書き戻し
    echo ""
    echo "Lesson feedback recording (post-GATE CLEAR):"
    (record_lesson_feedback_for_cmd >/dev/null 2>&1 || true) &
    echo "  lesson feedback: queued (async)"

    # ─── gunshi_verdict 自動記録（GATE CLEAR時、archive前） ───
    # L895: 同一cmd_design_quality.yamlのgunshi_verdict更新は上の
    # "Gunshi verdict update to cmd_design_quality" に一本化する。
    # ここで再更新すると REQUEST_CHANGES 優先/LGTM正規化を後段ロジックが上書きする。
    echo ""
    echo "Gunshi verdict record (GATE CLEAR):"
    echo "  SKIP (handled by Gunshi verdict update to cmd_design_quality)"

    # source-only pushはGATE CLEAR記録前に完了済み。ここで再実行すると
    # 同一sourceを二重適用し得るため、post-CLEAR laneでは実行しない。
    echo ""
    echo "Git push (post-GATE CLEAR): SKIP (completed before terminal CLEAR)"

    # dashboard_update removed (殿裁定2026-08-17). auto_section も不要。

    # ─── Gunshi gate_result reflux 2回目（GATE CLEAR後 最終ステップ, cmd_3370） ───
    # 1回目（GATE CLEAR通知前）で取りこぼしたreportエントリに対応するため再実行。
    # 根因: reflux実行後にGATE CLEAR通知を受けた軍師がreport reviewを追記するため
    # gate_result: nullが残存するケース（cmd_3362/3363/3360実証）。
    echo ""
    echo "Gunshi gate_result reflux (post-GATE CLEAR 2nd run):"
    if [ -f "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" "$CMD_ID" "CLEAR" 2>&1; then
            echo "  gunshi_gate_reflux: OK"
        else
            echo "  [INFO] gunshi_gate_reflux: WARN (non-blocking)"
        fi
    else
        echo "  SKIP (gunshi_gate_reflux.sh not found)"
    fi

    echo ""
    echo "Durable post-CLEAR writer wait (terminal checkpoint):"
    if ! wait_for_postclear_durable_writers; then
        echo "GATE BLOCK: ${CMD_ID}:postclear_durable_writer_wait_failed" >&2
        exit 1
    fi

    echo ""
    echo "Tracked runtime publish (terminal checkpoint):"
    if ! publish_postclear_runtime_deltas; then
        echo "GATE BLOCK: ${CMD_ID}:postclear_runtime_publish_failed" >&2
        exit 1
    fi

    # COMPLETE is published only after every synchronous postprocessor and its
    # tracked runtime output reached origin/shared HEAD.
    echo ""
    echo "Status completed (post-runtime-publish):"
    terminal_status_target="missing"
    if cmd_entry_exists "$CMD_ID"; then
        terminal_status_target="registered"
    elif has_parent_cmd_report "$CMD_ID"; then
        terminal_status_target="direct"
    fi
    case "$terminal_status_target" in
      registered)
        if ! bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$YAML_FILE" "$CMD_ID" status completed >/dev/null 2>&1; then
            echo "GATE BLOCK: ${CMD_ID}:status_completed_publish_failed" >&2
            exit 1
        fi
        echo "  status: completed"
        ;;
      direct)
        # Direct/non-numbered commands are admitted earlier by the same
        # parent-report contract and intentionally have no command-queue row
        # to mutate.  Their durable CLEAR marker/report is the terminal status
        # publication; treating the absent row as a setter failure contradicts
        # that admission contract after all substantive gates already passed.
        echo "  status: completed (direct parent-report contract; command entry absent)"
        ;;
      *)
        echo "GATE BLOCK: ${CMD_ID}:status_completed_publish_target_missing" >&2
        exit 1
        ;;
    esac

    # Archive and task-idle are terminal side effects: a status BLOCK above
    # must leave both untouched.
    echo ""
    echo "Archive (post-GATE CLEAR):"
    if [ ! -f "$GATES_DIR/archive.done" ]; then
        _archive_worker_log="$GATES_DIR/archive_worker.log"
        _archive_tmux_bin="${CMD_COMPLETE_TMUX_BIN:-tmux}"
        if command -v "$_archive_tmux_bin" >/dev/null 2>&1 \
            && "$_archive_tmux_bin" display-message -p '#S' >/dev/null 2>&1; then
            printf -v _archive_cmd '%q ' env ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 SHOGUN_COMPLETION_GENERATION="$SHOGUN_COMPLETION_GENERATION" \
                bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$CMD_ID"
            printf -v _archive_log_q '%q' "$_archive_worker_log"
            "$_archive_tmux_bin" run-shell -b "$_archive_cmd </dev/null >>$_archive_log_q 2>&1 || echo \"[WARN] archive worker rc=\$? (run-shell)\" >>$_archive_log_q"
            echo "  archive: queued (tmux server; log=$_archive_worker_log)"
        else
            echo "  archive: tmux unavailable; synchronous fallback (log=$_archive_worker_log)"
            env ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 SHOGUN_COMPLETION_GENERATION="$SHOGUN_COMPLETION_GENERATION" \
                bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$CMD_ID" \
                </dev/null >>"$_archive_worker_log" 2>&1 \
                || echo "  [INFO] archive: WARN (sync fallback failed)" >>"$_archive_worker_log"
        fi
    else
        echo "  archive: already exists (skip)"
    fi
    (set_matching_tasks_idle >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 \
        && record_finalize_phase_event task_idle >> "$LOG_DIR/cmd_complete_gate_async.log" 2>&1 \
        || true) &
    echo "Task idle transition: queued (async)"
    echo "Git push (post-GATE CLEAR): SKIP (completed before terminal CLEAR)"
    send_clear_notifications_once "$CMD_ID" "GATE CLEAR terminal"

    echo ""
    echo "Async completion wait (pre-exit):"
    echo "  async jobs: queued"
    print_matching_task_files_summary

    exit 0
else
    missing_list=$(IFS=,; echo "${MISSING_GATES[*]}")
    if [ ${#BLOCK_REASONS[@]} -gt 0 ]; then
        block_reason=$(IFS='|'; echo "${BLOCK_REASONS[*]}")
    elif [ -n "$missing_list" ]; then
        block_reason="missing_gates:${missing_list}"
    else
        # ALL_CLEAR=false だがBLOCK_REASONS/MISSING_GATES両方空: 各gate個別結果を収集
        _gate_details=()
        for _g in "${ALL_GATES[@]}"; do
            if [ -f "$GATES_DIR/${_g}.done" ]; then
                _gate_details+=("${_g}:PASS")
            else
                _gate_details+=("${_g}:FAIL")
            fi
        done
        block_reason="fallback_gate_status:$(IFS='|'; echo "${_gate_details[*]}")"
    fi
    # B20: terminalな失敗だけをBLOCKとして台帳へ記す。評価不在(head SHA mismatch /
    # run未完了 / review前run / 全job cancelled)はWAITで記録し、BLOCK率・再発検知・
    # 軍師accuracyの分母を汚さない。理由が複合ならterminal優先(fail-closed)。
    _gate_record_category=$(classify_gate_record_reasons "$block_reason")
    append_line_locked "$GATE_METRICS_LOG" "$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$(date +%Y-%m-%dT%H:%M:%S)" "$CMD_ID" "$_gate_record_category" "$block_reason" "$GATE_TASK_TYPE" "$GATE_MODEL" "$GATE_BLOOM_LEVEL" "$GATE_INJECTED_LESSONS" "$CMD_TITLE" "$GATE_FIRST_MODEL_METRIC" "$(format_ci_raw_columns "${ci_run_id:-}" "${ci_run_conclusion:-}")")"
    bash "$SCRIPT_DIR/scripts/rotate_gate_metrics.sh" 2>/dev/null || true
    echo "GATE BLOCK: 不足フラグ=[${missing_list}] 理由=${block_reason}"
    echo ""
    echo "Karo gate_block notification (GATE BLOCK):"
    notify_karo_gate_block "$CMD_ID" "$block_reason" "$missing_list"
    if append_lesson_tracking "$CMD_ID" "BLOCK" 2>&1; then
        true
    else
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
    fi
    if update_lesson_impact_tsv "$CMD_ID" "BLOCK" 2>&1; then
        true
    else
        echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)"
    fi
    queue_lesson_impact_followup

    # ─── gunshi review_feedback自動送信（GATE BLOCK） ───
    # GP-209: dedup — 同一cmd+同一resultが既にinboxにあればスキップ
    echo ""
    echo "Gunshi review_feedback (GATE BLOCK):"
    if grep -q "${CMD_ID} gate_result: BLOCK" "$SCRIPT_DIR/queue/inbox/gunshi.yaml" 2>/dev/null; then
        echo "  gunshi review_feedback: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" gunshi "${CMD_ID} gate_result: BLOCK reason=${block_reason}" review_feedback system 2>/dev/null; then
        echo "  gunshi review_feedback: OK (BLOCK)"
    else
        echo "  [INFO] gunshi review_feedback: WARN (non-blocking)"
    fi

    # ─── GATE FAIL時 自動confirmed教訓生成（ベストエフォート） ───
    echo ""
    echo "Auto-failure lessons for GATE FAIL:"
    if [ -x "$SCRIPT_DIR/scripts/auto_failure_lesson.sh" ]; then
        _AUTO_FAILURE_COUNT=0
        for task_file in "${MATCHING_TASK_FILES[@]}"; do
            if [ ! -f "$task_file" ]; then
                echo "  [WARN] matching task file disappeared, skipping: $task_file"
                MATCHING_TASK_FILES_SKIPPED_COUNT=$((MATCHING_TASK_FILES_SKIPPED_COUNT + 1))
                continue
            fi
            MATCHING_TASK_FILES_PROCESSED_COUNT=$((MATCHING_TASK_FILES_PROCESSED_COUNT + 1))
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name")
            if [ -f "$report_file" ]; then
                if bash "$SCRIPT_DIR/scripts/auto_failure_lesson.sh" "$report_file" 2>&1; then
                    _AUTO_FAILURE_COUNT=$((_AUTO_FAILURE_COUNT + 1))
                else
                    echo "  [INFO] auto_failure_lesson.sh failed for ${ninja_name} (non-blocking)"
                fi
            else
                echo "  ${ninja_name}: no report file"
            fi
        done
        echo "  Processed: ${_AUTO_FAILURE_COUNT} report(s)"
    else
        echo "  SKIP (auto_failure_lesson.sh not found)"
    fi

    # ─── GATE BLOCK時スキル学習ループ還流（cmd_2459拡張） ───
    # executor帰属: タスクYAMLファイル名からninja名抽出(CLI非依存)
    _BLOCK_EXECUTOR="${AGENT_ID:-}"
    if [ -z "$_BLOCK_EXECUTOR" ] && [ "${#MATCHING_TASK_FILES[@]}" -gt 0 ]; then
        _BLOCK_EXECUTOR=$(basename "${MATCHING_TASK_FILES[0]}" .yaml)
    fi
    _BLOCK_EXECUTOR="${_BLOCK_EXECUTOR:-unknown}"
    _SKILL_FEEDBACK="$SCRIPT_DIR/scripts/skill_gate_feedback.sh"
    if [ "${SKILL_GATE_FEEDBACK_DISABLE:-0}" != "1" ] && [ -x "$_SKILL_FEEDBACK" ]; then
        echo ""
        echo "Skill gate feedback (GATE BLOCK):"
        # BLOCK理由から還流先スキルを特定(自動推定はgate名でcmd-completeに誤マッチする)
        _target_skill=""
        case "$block_reason" in
            *missing_gate*|*lesson_done_missing*|*draft_lessons*)
                _target_skill="cmd-complete" ;;
            *lessons_useful*|*lesson_candidate*|*report_format*|*report_yaml_missing*)
                _target_skill="report-write" ;;
            *binary_checks_fail*|*purpose_validation*)
                _target_skill="verdict-check" ;;
            *commit*|*scope*)
                _target_skill="ninja-commit" ;;
        esac
        _skill_args=()
        [ -n "$_target_skill" ] && _skill_args=(--skill "$_target_skill")
        if timeout 10 bash "$_SKILL_FEEDBACK" \
            --gate "cmd_complete_gate" \
            --result "FAIL" \
            --reason "$block_reason" \
            --executor "$_BLOCK_EXECUTOR" \
            --source "${CMD_ID}" \
            "${_skill_args[@]}" >/dev/null 2>&1; then
            echo "  skill_gate_feedback: OK (skill=${_target_skill:-auto})"
        else
            echo "  skill_gate_feedback: SKIP (non-blocking)"
        fi
    fi

    # ─── GATE BLOCK時 recall miss検出（Phase 2d: 推薦されなかったが使うべきだったスキル） ───
    if [ -n "$_target_skill" ]; then
        _recall_miss_log="${SKILL_RECOMMEND_LOG_FILE:-$SCRIPT_DIR/logs/skill_recommend_log.yaml}"
        if [ -f "$_recall_miss_log" ]; then
            if ! grep -qF "$_target_skill" "$_recall_miss_log" 2>/dev/null; then
                echo ""
                echo "Skill recall miss detected:"
                echo "  skill: $_target_skill (BLOCK理由: ${block_reason})"
                echo "  推薦ログに $_target_skill の推薦記録なし → recall miss"
                _recall_miss_entry="- ts: \"$(date '+%Y-%m-%dT%H:%M:%S%z')\""
                _recall_miss_entry="${_recall_miss_entry}\n  type: recall_miss"
                _recall_miss_entry="${_recall_miss_entry}\n  skill: \"$_target_skill\""
                _recall_miss_entry="${_recall_miss_entry}\n  block_reason: \"${block_reason//\"/\\\"}\""
                _recall_miss_entry="${_recall_miss_entry}\n  cmd_id: \"$CMD_ID\""
                printf '%b\n' "$_recall_miss_entry" >> "$_recall_miss_log" 2>/dev/null || true
            fi
        fi
    fi

    # ─── GATE BLOCK時自動draft教訓生成（ベストエフォート） ───
    echo ""
    echo "Auto-draft lessons for GATE BLOCK:"
    if [ -n "$CMD_PROJECT" ]; then
        DRAFT_GENERATED=0

        # Pattern 1: lessons_useful empty
        lr_empty_ninjas=()
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == *":empty_lessons_useful:"* || "$reason" == *":empty_lesson_referenced:"* || "$reason" == *":null_lessons_useful"* ]]; then
                ninja=$(echo "$reason" | cut -d: -f1)
                lr_empty_ninjas+=("$ninja")
            fi
        done
        if [ ${#lr_empty_ninjas[@]} -gt 0 ]; then
            lr_count=${#lr_empty_ninjas[@]}
            if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" \
                "[自動生成] 有効教訓の記録を怠った: ${CMD_ID}" \
                "lessons_usefulが空のサブタスクが${lr_count}件。役立った教訓IDを報告に記載してから完了せよ" \
                "${CMD_ID}" "gate_auto" "${CMD_ID}" --status draft --source-marker "gate_auto_draft" 2>&1; then
                echo "  draft: 有効教訓の記録を怠った (${lr_count}件)"
                DRAFT_GENERATED=$((DRAFT_GENERATED + 1))
            else
                echo "  [INFO] draft生成失敗 (lessons_useful_empty)"
            fi
        fi

        # Pattern 2: draft_remaining — 循環防止のためdraft生成をスキップ
        # draft_lessons起因のBLOCKでさらにdraftを生成すると次回GATEもBLOCKし続ける循環を招く
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == draft_lessons:* ]]; then
                d_count=$(echo "$reason" | cut -d: -f2)
                echo "  SKIP: draft_lessons:${d_count} — draft_lessons起因BLOCKでのdraft生成は循環を招くためスキップ (auto_draft_lesson.sh循環防止)"
                echo "  ヒント: ${CMD_PROJECT}の${d_count}件のdraft教訓を査読・承認してからGATEを再実行せよ"
                break
            fi
        done

        # Pattern 3: reviewed_false — 廃止 (cmd_533: push型移行)

        echo "  Generated: ${DRAFT_GENERATED} draft lesson(s)"
    else
        echo "  SKIP (project not found in cmd)"
    fi

    # ─── GATE BLOCK時 harmful判定（教訓参照しなかった忍者の注入教訓にharmful +1） ───
    echo ""
    echo "Lesson score update (harmful - GATE BLOCK):"
    # harmful判定はACE Reflector方式に移行(cmd_470)。自己申告不在での一律harmful廃止。
    echo "  SKIP (disabled)"

    # ─── cmd品質ログ記録（GATE BLOCK時、ベストエフォート） ───
    echo ""
    echo "Cmd quality log (GATE BLOCK):"
    if [ -f "$SCRIPT_DIR/scripts/cmd_quality_log.sh" ]; then
        block_notes=""
        if [ ${#BLOCK_REASONS[@]} -gt 0 ]; then
            block_notes=$(IFS='|'; echo "${BLOCK_REASONS[*]}")
        fi
        if bash "$SCRIPT_DIR/scripts/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_notes" 2>&1; then
            echo "  cmd_quality_log: OK"
        else
            echo "  [INFO] cmd_quality_log: WARN (logging failed, non-blocking)"
        fi
    else
        echo "  SKIP (cmd_quality_log.sh not found)"
    fi

    # ─── Workaround率表示（情報のみ、BLOCKしない） ───
    echo ""
    echo "Workaround rate (GATE BLOCK):"
    if [ -x "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" ]; then
        bash "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" --last 10 2>&1 || echo "  [INFO] gate_workaround_rate.sh failed (non-blocking)"
    else
        echo "  SKIP (gate_workaround_rate.sh not found)"
    fi

    # ─── GATE BLOCK時 harmful閾値による教訓自動deprecate ───
    echo ""
    echo "Auto-deprecate check (harmful threshold):"
    if [ -n "$CMD_PROJECT" ] && [ -f "$SCRIPT_DIR/scripts/lesson_write.sh" ]; then
        DEPRECATE_COUNT=0
        DEPRECATE_LESSONS_FILE="$SCRIPT_DIR/projects/${CMD_PROJECT}/lessons.yaml"
        if [ -f "$DEPRECATE_LESSONS_FILE" ]; then
            # harmful_count >= 5 かつ harmful_count > helpful_count の教訓を検出
            deprecate_targets=$(awk '
                /^[[:space:]]*- id:/ {
                    if (lid != "" && !deprecated && harmful >= 5 && harmful > helpful)
                        printf "%s\t%d\t%d\n", lid, harmful, helpful
                    lid = $0; sub(/.*- id:[[:space:]]*/, "", lid); gsub(/[" \t]/, "", lid)
                    harmful = 0; helpful = 0; deprecated = 0
                    next
                }
                /^[[:space:]]+harmful_count:/ { v=$0; sub(/.*harmful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); harmful = v + 0 }
                /^[[:space:]]+helpful_count:/ { v=$0; sub(/.*helpful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); helpful = v + 0 }
                /^[[:space:]]+deprecated: true/ { deprecated = 1 }
                /^[[:space:]]+retired: true/ { deprecated = 1 }
                /^[[:space:]]+status:[[:space:]]*deprecated/ { deprecated = 1 }
                /^[[:space:]]+status:[[:space:]]*retired/ { deprecated = 1 }
                /^[[:space:]]+deprecated_by:/ { v=$0; sub(/.*deprecated_by:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); if (v != "") deprecated = 1 }
                END {
                    if (lid != "" && !deprecated && harmful >= 5 && harmful > helpful)
                        printf "%s\t%d\t%d\n", lid, harmful, helpful
                }
            ' "$DEPRECATE_LESSONS_FILE" 2>/dev/null)

            if [ -n "$deprecate_targets" ]; then
                while IFS=$'\t' read -r lid harmful helpful; do
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" --retire "$lid" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE: ${lid} (harmful=${harmful} > helpful=${helpful})"
                        DEPRECATE_COUNT=$((DEPRECATE_COUNT + 1))
                    else
                        echo "  [INFO] ${lid}: auto-deprecate failed (non-blocking)"
                    fi
                done <<< "$deprecate_targets"
            fi
            echo "  Auto-deprecated: ${DEPRECATE_COUNT} lesson(s)"
        else
            echo "  SKIP (lessons file not found: ${DEPRECATE_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project not found or lesson_write.sh missing)"
    fi

    # ─── GATE BLOCK時 useful率低下による教訓自動deprecate ───
    echo ""
    echo "Auto-deprecate check (useful rate threshold):"
    if [ -n "$CMD_PROJECT" ] && [ -f "$SCRIPT_DIR/scripts/lesson_write.sh" ]; then
        USEFUL_DEPRECATE_COUNT=0
        USEFUL_DEPRECATE_LESSONS_FILE="$SCRIPT_DIR/projects/${CMD_PROJECT}/lessons.yaml"
        if [ -f "$USEFUL_DEPRECATE_LESSONS_FILE" ]; then
            # useful率 = helpful_count / (helpful_count + harmful_count)
            # 閾値: useful率20%以下 かつ 参照10回以上（既存deprecatedは除外）
            useful_deprecate_targets=$(awk '
                function emit_if_target() {
                    total = helpful + harmful
                    if (lid != "" && !deprecated && total >= 10 && helpful * 5 <= total)
                        printf "%s\t%d\t%d\t%d\n", lid, helpful, harmful, total
                }
                /^[[:space:]]*- id:/ {
                    emit_if_target()
                    lid = $0; sub(/.*- id:[[:space:]]*/, "", lid); gsub(/[" \t]/, "", lid)
                    harmful = 0; helpful = 0; deprecated = 0
                    next
                }
                /^[[:space:]]+harmful_count:/ { v=$0; sub(/.*harmful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); harmful = v + 0 }
                /^[[:space:]]+helpful_count:/ { v=$0; sub(/.*helpful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); helpful = v + 0 }
                /^[[:space:]]+deprecated: true/ { deprecated = 1 }
                /^[[:space:]]+retired: true/ { deprecated = 1 }
                /^[[:space:]]+status:[[:space:]]*deprecated/ { deprecated = 1 }
                /^[[:space:]]+status:[[:space:]]*retired/ { deprecated = 1 }
                /^[[:space:]]+deprecated_by:/ { v=$0; sub(/.*deprecated_by:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); if (v != "") deprecated = 1 }
                END { emit_if_target() }
            ' "$USEFUL_DEPRECATE_LESSONS_FILE" 2>/dev/null)

            if [ -n "$useful_deprecate_targets" ]; then
                while IFS=$'\t' read -r lid helpful harmful total; do
                    [ -z "$lid" ] && continue
                    useful_pct=$(( helpful * 100 / total ))
                    if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" --retire "$lid" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE(useful-rate): ${lid} (helpful=${helpful}/total=${total}, harmful=${harmful}, useful_rate=${useful_pct}%)"
                        USEFUL_DEPRECATE_COUNT=$((USEFUL_DEPRECATE_COUNT + 1))
                    else
                        echo "  [INFO] ${lid}: useful-rate auto-deprecate failed (non-blocking)"
                    fi
                done <<< "$useful_deprecate_targets"
            fi
            echo "  Useful-rate auto-deprecated: ${USEFUL_DEPRECATE_COUNT} lesson(s)"
        else
            echo "  SKIP (lessons file not found: ${USEFUL_DEPRECATE_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project not found or lesson_write.sh missing)"
    fi

    print_matching_task_files_summary
    exit 1
fi
