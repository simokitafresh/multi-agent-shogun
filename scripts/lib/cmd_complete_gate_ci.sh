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
# 判定は3状態のみ: (i)対応する評価がGREEN=PASS (ii)対象側の評価がRED=BLOCK
# (iii)このコードに対するworkflow評価が未完了/非GREEN/不存在=WAIT
# (後追い確認。GATEを止めない)。殿裁定(cmd_4384)によりCI workflow結果の
# 確認待ちはGATE判定を止めず、既存WAIT経路へ集約する。
# 「別commitの評価」「未完了run」「全job cancelled」はいずれも同一の意味であり、
# 分岐を足さずこの1つの状態判定へ集約する。単に条件を削ると stale GREEN で
# 未検証CLEAR、stale RED で誤帰属BLOCKになるため、削除ではなく状態化する。
NO_VERDICT={"cancelled", "canceled", "skipped", "stale", "neutral", "action_required", ""}
jobs=w.get("jobs_conclusions")
external_unavailable=w.get("external_unavailable", False)
jobs_not_started=w.get("jobs_not_started", False)
if not isinstance(external_unavailable, bool) or not isinstance(jobs_not_started, bool):
    print("BLOCK: workflow_result external-unavailable evidence type invalid")
    raise SystemExit(1)
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
if external_unavailable:
    # A completed failure with no started jobs is not a code result only when
    # GitHub supplied its billing annotation and the local target evidence is
    # green.  Any missing/failed local evidence remains a repairable BLOCK.
    if not jobs_not_started:
        print("BLOCK: workflow_result is not GREEN (external-unavailable evidence is not a job-start absence)")
        raise SystemExit(1)
    if t["conclusion"] != "success":
        print("BLOCK: workflow_result is not GREEN (local test evidence is not GREEN)")
        raise SystemExit(1)
    print("READY: target_result=GREEN local_test=PASS external_unavailable=github_billing head_sha=" + expected)
    raise SystemExit(0)
if t["conclusion"] != "success":
    print("BLOCK: target_result is not GREEN")
    raise SystemExit(1)
if w["conclusion"] != "success":
    print("WAIT: ci_evaluation_external_pending=workflow_result_not_green — 後追いで確認せよ(GATEは止めない) head_sha=" + expected)
    raise SystemExit(0)
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
        *"workflow_result is not GREEN"*|*ci_evaluation_external_pending=*|\
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
    local ancestry_snapshot_file="${4:-}"
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
        # check_report_commit_main_ancestry may provide a snapshot containing
        # every commit reachable from expected_head. Reusing that one walk
        # preserves the exact ancestor predicate while avoiding one expensive
        # merge-base traversal per PASS report in the same repository.
        if [ -n "$ancestry_snapshot_file" ] && [ -f "$ancestry_snapshot_file" ]; then
            if grep -Fqx -- "$report_commit" "$ancestry_snapshot_file"; then
                echo "PUSHED: report commit $report_commit contained by $expected_head"
            else
                echo "UNPUSHED: report commit $report_commit not contained by $expected_head"
            fi
        elif git -C "$repo_dir" merge-base --is-ancestor "$report_commit" "$expected_head" 2>/dev/null; then
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
