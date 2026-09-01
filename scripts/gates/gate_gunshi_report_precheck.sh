#!/bin/bash
# semantic-links: [[Silent Fallback品質]]
# gate_gunshi_report_precheck.sh — 軍師レビュー前の機械的検証を自動化
# 目的: 7つの意志依存ステップを1コマンドに統合。意志依存ゼロ。
# Usage: bash scripts/gates/gate_gunshi_report_precheck.sh <report_yaml_path>
# 知性の外部化: deepdive Phase 7。自分の問題を自分で解決する。
# §3.2最適化: python3 -c 13回 → engine.py 1回呼出。390ms/report → 30ms/report

set -euo pipefail

REPORT_PATH="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "${REPO_ROOT}/scripts/lib/defense_overhead_writer.sh"
GUNSHI_PRECHECK_STARTED_US="${EPOCHREALTIME/./}"
GUNSHI_PRECHECK_STARTED_US="${GUNSHI_PRECHECK_STARTED_US:0:16}"
# No-hash reports repeat the same bounded git history lookup whenever the
# report body changes. Cache only committed-history results, keyed by the
# repository HEAD and parent command, so a new commit invalidates the entry.
GUNSHI_BATCH_GIT_CACHE_DIR="${GUNSHI_BATCH_GIT_CACHE_DIR:-${TMPDIR:-/tmp}/gate_gunshi_batch_git_cache}"
GUNSHI_BATCH_GIT_SCRIPT_HASH="$(sha256sum "${BASH_SOURCE[0]}" 2>/dev/null | awk '{print $1}')"
GUNSHI_BATCH_GIT_CACHE_HIT=0
GUNSHI_BATCH_GIT_PROJECT_LOOKUP_DONE=0
_gunshi_batch_git_cached_output() {
    local kind="$1" repo="$2" parent_cmd="$3" output_file="$4"
    local head key cache_file tmp_file rc cached_rc
    : > "$output_file"
    head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "$head" ]; then
        return 1
    fi
    key="$(printf '%s\0%s\0%s\0%s' "$kind" "$repo" "$parent_cmd$head" "$GUNSHI_BATCH_GIT_SCRIPT_HASH" | sha256sum | awk '{print $1}')"
    if ! mkdir -p "$GUNSHI_BATCH_GIT_CACHE_DIR" 2>/dev/null; then
        cache_file=""
    else
        cache_file="$GUNSHI_BATCH_GIT_CACHE_DIR/$key"
    fi
    if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
        cached_rc="$(head -1 "$cache_file" 2>/dev/null || true)"
        if [[ "$cached_rc" =~ ^[0-9]+$ ]]; then
            tail -n +2 "$cache_file" > "$output_file"
            GUNSHI_BATCH_GIT_CACHE_HIT=1
            [ -z "${GUNSHI_BATCH_GIT_CACHE_TRACE_FILE:-}" ] || printf '%s\n' "hit:$kind" >> "$GUNSHI_BATCH_GIT_CACHE_TRACE_FILE"
            return "$cached_rc"
        fi
    fi
    [ -z "${GUNSHI_BATCH_GIT_CACHE_TRACE_FILE:-}" ] || printf '%s\n' "miss:$kind" >> "$GUNSHI_BATCH_GIT_CACHE_TRACE_FILE"
    case "$kind" in
        parent_numstat)
            (cd "$repo" && timeout 2 git log -20 --no-merges --fixed-strings --grep="$parent_cmd" --format="" --numstat 2>/dev/null) > "$output_file"
            ;;
        recent_data)
            (cd "$repo" && timeout 2 git log --oneline -20 --name-only 2>/dev/null) > "$output_file"
            ;;
        *)
            return 1
            ;;
    esac
    rc=$?
    # Preserve both successful output and the existing timeout result. The
    # timeout path already treats incomplete history as empty; replaying that
    # exact result for the same HEAD/script generation avoids a repeated scan.
    if { [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; } && [ -n "$cache_file" ]; then
        tmp_file="${cache_file}.$$"
        if { printf '%s\n' "$rc"; cat "$output_file"; } > "$tmp_file" 2>/dev/null; then
            mv -f "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file"
        fi
    fi
    return "$rc"
}
gunshi_precheck_overhead_exit() {
    local rc=$? finished_us wall_ms verdict
    finished_us="${EPOCHREALTIME/./}"; finished_us="${finished_us:0:16}"
    wall_ms=$(((finished_us - GUNSHI_PRECHECK_STARTED_US + 999) / 1000))
    verdict="$([ "$rc" -eq 0 ] && echo PASS || echo FAIL)"
    defense_overhead_write_async gate_gunshi_report_precheck full_precheck "$wall_ms" "$verdict" \
        "gunshi-precheck:$$:${GUNSHI_PRECHECK_STARTED_US}" || true
}
trap gunshi_precheck_overhead_exit EXIT

# cmd_karo_hotfix_round2_full_precheck_20260728: full_precheckは恒常課税+外れ値尾の
# 混合型(§3-4 docs/research/hot-script-speedup-round2-asis-tobe-5w1h_20260728.md)と
# 判明したが、内部フェーズ別の時間・枝条件は台帳に存在しなかった(親totalのみ)。
# 最大寄与フェーズを特定するため、子check_id(full_precheck_*、親と非加算・診断専用)を
# 恒久計装する。各呼出し点は独立にasync書込みするため、_gunshi_precheck_bodyの
# command substitution(subshell)境界をまたいでも変数の受け渡しは不要。
_gunshi_phase_report() {
    local phase="$1" start_us="$2" branch="${3:-none}" now_us wall_ms
    now_us="${EPOCHREALTIME/./}"; now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - start_us + 999) / 1000 ))
    defense_overhead_write_async gate_gunshi_report_precheck "full_precheck_${phase}" "$wall_ms" PASS \
        "gunshi-precheck-${phase}-${branch}:$$:${start_us}" || true
    # _gunshi_precheck_body内から呼ばれた場合はbodyのlocal _GUNSHI_MEASURED_MSへ加算する
    # (bash動的スコープ: bodyがlocal宣言済みならここでの代入はbody側の変数を更新する)。
    # body外(engine/cache)からの呼出し時は未定義のままで無害(算術コンテキストで0扱い)。
    _GUNSHI_MEASURED_MS=$(( ${_GUNSHI_MEASURED_MS:-0} + wall_ms ))
}
# shellcheck source=scripts/lib/project_path.sh
source "${REPO_ROOT}/scripts/lib/project_path.sh"
DM_SIGNAL_PATH="$(get_project_path 'dm-signal')"
export DM_SIGNAL_PATH

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "FAIL: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

echo "=== 軍師レビュー前検証: $(basename "$REPORT_PATH") ==="

ERRORS=0

# ─── Engine: 1回のファイル読込で全Pythonチェックを実行 ───────────────────
# 出力: WORKER_ID / PARENT_CMD / IS_DM_SIGNAL / FILES_MODIFIED /
#       BINARY_CHECKS_MSG / SAME_CMD_NINJAS / TASK_FILE
_GUNSHI_PH_ENGINE_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_ENGINE_START_US="${_GUNSHI_PH_ENGINE_START_US:0:16}"
eval "$(python3 "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py" \
    --report "$REPORT_PATH" \
    --tasks-dir "${GUNSHI_PRECHECK_TASKS_DIR:-$REPO_ROOT/queue/tasks}" 2>/dev/null)"
_gunshi_phase_report engine "$_GUNSHI_PH_ENGINE_START_US" "$([ "${IS_DM_SIGNAL:-0}" = "1" ] && echo dm_signal || echo shogun)"

# ─── 結果cache: report内容hash単位 (cmd_4167: full_precheck 555回×平均5.17秒の削減) ───
# 同一reportの再precheckをcache返答にし、report(+関連task)の内容が変わった時のみ全量再検査する。
# 対象は既定の全量precheckのみ(GUNSHI_PRECHECK_ONLYの個別観点確認はcache対象外・従来通り毎回実行)。
# cache keyはreport/task本文のsha256sum(既存SG-PRE1の_PRE1_REPORT_FPと同族の素朴な内容hash。
# 新規hash機構は作らない)に加え、検出ロジック自体の変更を取りこぼさないよう本スクリプトと
# engineの内容hashも含める(GA-232と同型: 検出コード変更はledger不変でも過去判定を無効化する)。
GUNSHI_PRECHECK_CACHE_WRITE=0
GUNSHI_PRECHECK_CACHE_FILE=""
_GUNSHI_PH_CACHE_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_CACHE_START_US="${_GUNSHI_PH_CACHE_START_US:0:16}"
if [ -z "${GUNSHI_PRECHECK_ONLY:-}" ]; then
    GUNSHI_PRECHECK_CACHE_DIR="${GUNSHI_PRECHECK_CACHE_DIR:-${TMPDIR:-/tmp}/gate_gunshi_report_precheck_cache}"
    _cache_report_hash="$(sha256sum "$REPORT_PATH" 2>/dev/null | awk '{print $1}')"
    _cache_task_hash="none"
    if [ -n "${TASK_FILE:-}" ] && [ -f "$TASK_FILE" ]; then
        _cache_task_hash="$(sha256sum "$TASK_FILE" 2>/dev/null | awk '{print $1}')"
    fi
    _cache_self_hash="$(cat "$0" "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py" 2>/dev/null | sha256sum | awk '{print $1}')"
    _cache_sig="report=${_cache_report_hash}:task=${_cache_task_hash}:self=${_cache_self_hash}"
    _cache_key="$(printf '%s' "$_cache_sig" | sha256sum | awk '{print $1}')"
    GUNSHI_PRECHECK_CACHE_FILE="${GUNSHI_PRECHECK_CACHE_DIR}/${_cache_key}"
    if [ -s "$GUNSHI_PRECHECK_CACHE_FILE" ]; then
        _cache_exit="$(head -1 "$GUNSHI_PRECHECK_CACHE_FILE" 2>/dev/null)"
        if [[ "$_cache_exit" =~ ^[01]$ ]]; then
            # stdoutはfull check実行時と同一バイト列を保つ(同一reportの再precheckが
            # cache返答で全検査と同一結果になる契約)。cache応答である旨はstderrにのみ出す。
            echo "★ cache応答(full_precheck結果cache): report/task/検出ロジック内容hash一致のため全検査を省略" >&2
            tail -n +2 "$GUNSHI_PRECHECK_CACHE_FILE"
            _gunshi_phase_report cache "$_GUNSHI_PH_CACHE_START_US" hit
            exit "$_cache_exit"
        fi
    fi
    GUNSHI_PRECHECK_CACHE_WRITE=1
    _gunshi_phase_report cache "$_GUNSHI_PH_CACHE_START_US" miss
else
    _gunshi_phase_report cache "$_GUNSHI_PH_CACHE_START_US" disabled
fi

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE35" ]; then
    echo ""
    echo "■ SG-PRE35: 新規テスト必要性契約"
    DEPLOY_TASK_LIB_ONLY=1 bash -c 'source "$1/scripts/deploy_task.sh"; deploy_task_test_necessity_precheck "$2" "$3"' _ "$REPO_ROOT" "${TASK_FILE:-/nonexistent}" "$REPORT_PATH"
    exit $?
fi

# Focused contract checks may stop after the shared engine has parsed the
# report/task pair.  This avoids unrelated git-history and repository scans;
# the default remains the complete precheck.
if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE33" ]; then
    echo ""
    echo "■ SG-PRE33: enforcement層の変形検査契約"
    echo "${VARIATION_CHECKS_MSG:-  SKIP: 変形検査契約の対象外}"
    [[ "${VARIATION_CHECKS_MSG:-}" != *"ERROR:"* ]]
    exit $?
fi

# SG-PRE23 source boundary: context reference checks must consume the same
# report commit/task-worktree generation as the reviewed implementation.
resolve_review_source_context() {
    local source_helper="$REPO_ROOT/scripts/lib/review_source_context.py"
    # A report can be reviewed before the task-worktree commit is published
    # into the shared checkout.  In that window the resolver itself must come
    # from the same task worktree generation as the report source.
    if [ ! -f "$source_helper" ] && [ -f "${TASK_FILE:-}" ]; then
        local task_worktree_root
        task_worktree_root="$(python3 - "$TASK_FILE" <<'PY'
import sys
import yaml

doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = doc.get("task", doc)
print(str(task.get("task_worktree_workdir") or task.get("task_worktree_path") or "").strip())
PY
        )"
        if [ -n "$task_worktree_root" ] && [ -f "$task_worktree_root/scripts/lib/review_source_context.py" ]; then
            source_helper="$task_worktree_root/scripts/lib/review_source_context.py"
        fi
    fi
    [ -f "$source_helper" ] || {
        echo "  ERROR: review source resolver missing: $source_helper"
        return 1
    }
    local source_result
    source_result="$(python3 "$source_helper" \
        --report "$REPORT_PATH" \
        --task "${TASK_FILE:-/nonexistent}" \
        --repo-root "$REPO_ROOT" 2>/dev/null || true)"
    eval "$source_result"
    [ "${SOURCE_CONTEXT_STATUS:-BLOCK}" != "BLOCK" ] || {
        echo "  ERROR: source context generation BLOCK: ${SOURCE_CONTEXT_REASON:-unknown}"
        return 1
    }
    [ -n "${SOURCE_CONTEXT_ROOT:-}" ] || {
        echo "  ERROR: source context root missing after generation resolution"
        return 1
    }
    return 0
}

run_sg_pre23() {
    local context_file source_context_root
    if ! resolve_review_source_context; then
        return 1
    fi
    source_context_root="${SOURCE_CONTEXT_ROOT:-$REPO_ROOT}"
    echo "  source_context_status=${SOURCE_CONTEXT_STATUS:-unknown} generation=${SOURCE_CONTEXT_GENERATION:-unknown} root=${source_context_root}"
    for context_file in "${_context_files[@]}"; do
        if ! bash "$source_context_root/scripts/gates/gate_vercel_phase.sh" \
            "$source_context_root/$context_file"; then
            echo "  [CRITICAL] source gate_vercel_phase FAIL — source generation has broken refs"
            return 1
        fi
    done
    echo "  PASS: source generation context references are clear"
}

# Focused execution is used by tests and diagnostics; it retains the exact
# source-generation contract without running unrelated review checks.
if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE23" ]; then
    echo ""
    echo "■ SG-PRE23: source-generation context参照検査"
    _context_files=()
    while IFS= read -r _fm_line; do
        case "$_fm_line" in context/*.md*) _context_files+=("$_fm_line");; esac
    done < <(printf '%s\n' "${FILES_MODIFIED:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep '^context/.*\.md' || true)
    if [ "${#_context_files[@]}" -eq 0 ]; then
        echo "  SKIP: context/*.md変更なし"
        exit 0
    fi
    run_sg_pre23
    exit $?
fi

# ─── SG-PRE31: N×M一致パターン意味検算BLOCK(LG048: きれいな数値一致は意味検算のサイン) ───
# focused-mode(GUNSHI_PRECHECK_ONLY=SG-PRE31)から他チェックのERRORSに引きずられず単独判定できるよう、
# SG-PRE1(gate_report_format.sh呼出し)より前に定義・早期exitする。
_sg_pre31_check() {
    local report_path="$1"
    # resultブロックから数値を抽出（整数のみ、10以上の値）
    local _result_block
    _result_block=$(awk '/^result:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    if [ -z "$_result_block" ]; then
        echo "  SKIP: resultブロックなし"
        return
    fi
    # 3以上の整数を抽出（重複排除・ソート。1,2は偽陽性が多すぎるため除外）
    # 先頭0の数字列を除外(bashが8進数として解釈しエラーになるため。commitハッシュ断片等)
    # テスト結果行(passed/failed/skipped/suites/tests)を除外(FP防止: 33 passed×3=99等)
    local _nums
    _nums=$(echo "$_result_block" | grep -viE 'passed|failed|skipped|suites|tests|PASS|FAIL' | grep -oE '[0-9]+' | grep -v '^0[0-9]' | awk '$1 >= 3' | sort -un || true)
    local _num_count
    _num_count=$(echo "$_nums" | grep -c '[0-9]' || true)
    if [ "${_num_count:-0}" -lt 3 ]; then
        echo "  PASS: 数値3個未満(N×M照合対象外)"
        return
    fi
    # N×M=Cの関係を探索
    local _found=0
    local _a _b _c
    while IFS= read -r _a; do
        [ -z "$_a" ] && continue
        while IFS= read -r _b; do
            [ -z "$_b" ] && continue
            [ "$_b" -le "$_a" ] && continue
            _c=$(( _a * _b )) || true
            if echo "$_nums" | grep -qx "$_c" 2>/dev/null; then
                echo "  INFO(LG048): N×M一致検出: ${_a}×${_b}=${_c}"
                echo "  ★ 意味検算せよ: この整数関係は仕様上の分類(PF種別/trigger別/月別等)と整合するか？"
                echo "    全件一律の数値は過剰集約や分類漏れの兆候。内訳を再計算して確認せよ"
                _found=1
            fi
        done <<< "$_nums"
    done <<< "$_nums"
    if [ "$_found" -eq 0 ]; then
        echo "  PASS: N×M一致パターンなし"
        return 0
    fi

    # 数値一致の検知だけでは意味検算にならない。分類軸・内訳再計算・結果を
    # semantic_validationとして構造化し、レビューフロー内でfail-closedに強制する。
    local _semantic_block
    _semantic_block=$(awk '/^semantic_validation:/{found=1; next} found && /^[^[:space:]#]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    if [ -z "$_semantic_block" ]; then
        echo "  BLOCK(LG048): N×M一致を検出したがsemantic_validation証跡がない"
        echo "  → classification_axis / recount / actual / result: PASSを記録せよ"
        return 2
    fi
    if ! printf '%s\n' "$_semantic_block" | grep -Eq '^  classification_axis:[[:space:]]*[^[:space:]#]'; then
        echo "  BLOCK(LG048): semantic_validation.classification_axisがない"
        return 2
    fi
    if ! printf '%s\n' "$_semantic_block" | grep -Eq '^  recount:[[:space:]]*[^[:space:]#]'; then
        echo "  BLOCK(LG048): semantic_validation.recountがない"
        return 2
    fi
    if ! printf '%s\n' "$_semantic_block" | grep -Eq '^  actual:[[:space:]]*[^[:space:]#]'; then
        echo "  BLOCK(LG048): semantic_validation.actualに分類別内訳の実測がない"
        return 2
    fi
    local _semantic_result
    _semantic_result=$(printf '%s\n' "$_semantic_block" | sed -n 's/^  result:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*#.*$//; s/^[[:space:]"]*//; s/[[:space:]"]*$//')
    if [ "$_semantic_result" != "PASS" ] && [ "$_semantic_result" != "FAIL" ]; then
        if [ -z "$_semantic_result" ]; then
            echo "  BLOCK(LG048): semantic_validation.resultが空欄"
            return 2
        fi
        echo "  BLOCK(LG048): semantic_validation.resultがPASS/FAILのいずれでもない"
        return 2
    fi
    if [ "$_semantic_result" = "FAIL" ]; then
        echo "  FAIL_DECLARED(LG048): N×M一致+分類軸別内訳の再計算証跡あり。result=FAILとして受理(ERRORSには加算しない)"
        echo "  → 意味検算の結果、分類漏れ等の問題ありと自己申告された。gate_predictionをWARNとし、軍師の判断(受理/差し戻し)をreview_logへ記録すること"
        if [ "${GATE_PREDICTION:-CLEAR}" = "CLEAR" ]; then
            GATE_PREDICTION="WARN"
        fi
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG048:FAIL_DECLARED_needs_gunshi_judgement"
        return 0
    fi
    echo "  PASS(LG048): N×M一致+分類軸別内訳の再計算証跡あり"
}
if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE31" ]; then
    echo ""
    echo "■ SG-PRE31: N×M意味検算(LG048)"
    _sg_pre31_check "$REPORT_PATH"
    _sg_pre31_rc=$?
    echo "GATE_PREDICTION=${GATE_PREDICTION:-CLEAR}"
    [ "$_sg_pre31_rc" -ne 2 ]
    exit $?
fi

# Project directory (commit検証用)
PROJECT_DIR=""
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    PROJECT_DIR="${DM_SIGNAL_PATH}"
else
    PROJECT_DIR="$REPO_ROOT"
fi

# cross_repo_commitsの妥当性はgate_report_formatと同じ共有正本で判定する。
# shell側は正本が検証済みとしたrepo/commit/pathの所有対応だけを消費し、
# PROJECT_DIR/REPO_ROOTの二択へ外部repo成果を誤って押し込まない。
_CROSS_REPO_RECORDS=""
_CROSS_REPO_ERRORS=""
eval "$(python3 - "$REPO_ROOT" "$REPORT_PATH" <<'PY'
import pathlib
import shlex
import sys
import yaml

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts" / "lib"))
from cross_repo_commit_contract import validate_cross_repo_commits

report = yaml.safe_load(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")) or {}
errors = validate_cross_repo_commits(report)
records = []
if not errors:
    for entry in report.get("cross_repo_commits") or []:
        repo = str(pathlib.Path(str(entry["repo"])).expanduser())
        commit = str(entry["commit_hash"])
        for path in entry["paths"]:
            records.append(f"{repo}\t{commit}\t{str(path).replace(chr(9), '')}")
print("_CROSS_REPO_RECORDS=" + shlex.quote("\n".join(records)))
print("_CROSS_REPO_ERRORS=" + shlex.quote("; ".join(errors)))
PY
)"

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE3X" ]; then
    echo ""
    echo "■ SG-PRE3X: cross-repo commit/path所有契約"
    if [ -n "$_CROSS_REPO_ERRORS" ]; then
        echo "  BLOCK: $_CROSS_REPO_ERRORS"
        exit 1
    fi
    if [ -z "$_CROSS_REPO_RECORDS" ]; then
        _primary_hash=$(grep -m1 -E '^[[:space:]]*commit_hash:' "$REPORT_PATH" |
            sed -E 's/^[[:space:]]*commit_hash:[[:space:]]*["'\'']?([0-9a-f]{40}).*/\1/' || true)
        if [ -n "$_primary_hash" ] &&
            { git -C "$PROJECT_DIR" cat-file -e "${_primary_hash}^{commit}" 2>/dev/null ||
              git -C "$REPO_ROOT" cat-file -e "${_primary_hash}^{commit}" 2>/dev/null; }; then
            echo "  PASS: primary repo commit resolved: $_primary_hash"
        elif [ -n "$_primary_hash" ]; then
            echo "  BLOCK: primary commit is not resolvable: $_primary_hash"
            exit 1
        else
            echo "  PASS: primary repo report (commit_hash検査対象なし)"
        fi
    else
        printf '%s\n' "$_CROSS_REPO_RECORDS" |
            awk -F '\t' '{print "  PASS: " $3 " → " $1 "@" $2}'
    fi
    exit 0
fi

print_sg_pre9() {
    echo ""
    echo "■ SG-PRE9: T1違反予防(binary_checks no検出)"
    if [ "${BC_HAS_NO:-0}" = "1" ]; then
        echo "  ★★★ WARN: binary_checks result:no検出: ${BC_NO_ITEMS}"
        if [ -n "${BC_NO_WAIVE_ITEMS:-}" ]; then
            echo "  → waive_reason付きresult:no: ${BC_NO_WAIVE_ITEMS}"
        fi
        echo "  → gate_prediction: BLOCK固定(waive_reason/test_triageがあっても免除なし)"
        echo "  → GP-128: verdict PASS + result:no → gate機械的BLOCK"
        echo "  → 見落とし実績: cmd_1897, cmd_1900, cmd_2093 (T1違反3回)"
    else
        echo "  PASS: binary_checks全result:yes (or検出対象なし)"
    fi
}

print_sg_pre10_contracts() {
    echo "■ SG-PRE10: ac_version照合"
    echo "${AC_VERSION_MSG:-  SKIP}"
    if echo "${AC_VERSION_MSG:-}" | grep -q "FAIL"; then
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }ac_version_mismatch"
    fi

    if [ -n "${TASK_FILE:-}" ] && [ -f "${TASK_FILE:-}" ]; then
        if _task_ac_result=$(python3 "$REPO_ROOT/scripts/lib/report_gate_contract.py" \
            task-ac-version "$TASK_FILE" 2>&1); then
            echo "  PASS: task ${_task_ac_result}"
        else
            echo "  ERROR: ${_task_ac_result}"
            ERRORS=$((ERRORS + 1))
            GATE_PREDICTION="BLOCK"
            GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }${_task_ac_result}"
        fi
    else
        echo "  SKIP: task file unavailable"
    fi

    echo ""
    echo "■ SG-PRE10b: parent_cmd_contract予測"
    if [[ "${PARENT_CMD:-}" =~ ^cmd_[0-9]+$ ]]; then
        if _parent_contract_result=$(python3 "$REPO_ROOT/scripts/lib/parent_cmd_contract.py" \
            "$PARENT_CMD" --root "$REPO_ROOT" 2>&1); then
            echo "  PASS: ${_parent_contract_result}"
        else
            echo "  ERROR: parent_cmd_contract: ${_parent_contract_result}"
            ERRORS=$((ERRORS + 1))
            GATE_PREDICTION="BLOCK"
            GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }parent_cmd_contract:${_parent_contract_result}"
        fi
    else
        echo "  SKIP: parent_cmd is not a numbered cmd (${PARENT_CMD:-missing})"
    fi

    echo ""
    echo "■ SG-PRE11: lesson_feedback_set照合"
    if [ -n "${TASK_FILE:-}" ] && [ -f "${TASK_FILE:-}" ] && [ -f "$REPORT_PATH" ]; then
        _set_status=$(python3 "$REPO_ROOT/scripts/lib/report_gate_contract.py" \
            lesson-feedback-set "$TASK_FILE" "$REPORT_PATH" 2>&1 || true)
        if [[ "$_set_status" == OK\ * ]]; then
            echo "  PASS: ${_set_status}"
        else
            echo "  ERROR: ${_set_status}"
            ERRORS=$((ERRORS + 1))
            GATE_PREDICTION="BLOCK"
            GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }lesson_feedback_set_mismatch:${_set_status}"
        fi
    else
        echo "  SKIP: task/report unavailable"
    fi

    echo "GATE_PREDICTION=${GATE_PREDICTION:-CLEAR}"
    echo "GATE_PREDICTION_REASON=${GATE_PREDICTION_REASON:-none}"
}

is_generated_large_artifact() {
    local path="$1"
    case "$path" in
        outputs/grid_search/*.db|outputs/grid_search/*.sqlite|outputs/grid_search/*.sqlite3|outputs/grid_search/*.duckdb|outputs/grid_search/*.db-shm|outputs/grid_search/*.db-wal|\
        */outputs/grid_search/*.db|*/outputs/grid_search/*.sqlite|*/outputs/grid_search/*.sqlite3|*/outputs/grid_search/*.duckdb|*/outputs/grid_search/*.db-shm|*/outputs/grid_search/*.db-wal)
            return 0
            ;;
    esac
    return 1
}

print_sg_pre24() {
    echo "■ SG-PRE24: generated/貫通チェック"
    local fixed_hash="${_REPORT_HASHES%%$'\n'*}"
    local _ifile _rname _gen_files _gen_first _src_hash _gen_hash
    local -a _instr_files=()
    while IFS= read -r _ifile; do
        _instr_files+=("$_ifile")
    done < <(echo "$FILES_MODIFIED" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -E '^instructions/(shogun|karo|gunshi|ashigaru)' || true)
    if [ "${#_instr_files[@]}" -eq 0 ] || [ ! -d "$REPO_ROOT/instructions/generated" ]; then
        echo "  SKIP: instructions正本変更なし or generated/不在"
        return 0
    fi
    if [ -z "$fixed_hash" ] || ! git -C "$REPO_ROOT" cat-file -e "${fixed_hash}^{commit}" 2>/dev/null; then
        echo "  ★ BLOCK: reportの固定commit SHAが不在または無効"
        return 1
    fi

    local _pre24_pass=true
    for _ifile in "${_instr_files[@]}"; do
        _rname=$(echo "$_ifile" | grep -oP '(shogun|karo|gunshi|ashigaru)' | head -1)
        [ -z "$_rname" ] && continue
        _fixed_files=$(git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$fixed_hash" 2>/dev/null || true)
        # diff-tree(変更ファイル)からgenerated/の対応ファイルを検索。ls-tree(全ファイル)だと
        # 変更されていないgenerated/ファイルが先頭に来て偽BLOCKになる(claude-gunshi.md事故)
        _gen_changed=$(printf '%s\n' "$_fixed_files" | grep -E "^instructions/generated/[^/]*${_rname}[^/]*$" || true)
        if [ -z "$_gen_changed" ]; then
            # diff-treeになければls-treeで存在自体を確認
            _gen_exists=$(git -C "$REPO_ROOT" ls-tree -r --name-only "$fixed_hash" -- instructions/generated/ 2>/dev/null | grep -E "/[^/]*${_rname}[^/]*$" || true)
            if [ -z "$_gen_exists" ]; then
                echo "  ★ BLOCK: ${_ifile}変更だが固定commit内のgenerated/に対応ファイルなし"
            else
                echo "  ★ BLOCK: ${_ifile}変更がfixed:${fixed_hash:0:12} 時点のgenerated/に未反映"
            fi
            _pre24_pass=false
            continue
        fi
        if printf '%s\n' "$_fixed_files" | grep -qxF "$_ifile"; then
            echo "  PASS: ${_ifile} → fixed:${fixed_hash:0:12} でgenerated/を同時更新済み"
        else
            echo "  ★ BLOCK: ${_ifile}変更がfixed:${fixed_hash:0:12} 時点のgenerated/に未反映"
            _pre24_pass=false
        fi
    done
    "$_pre24_pass"
}

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE9" ]; then
    print_sg_pre9
    exit 0
fi

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE10" ]; then
    print_sg_pre10_contracts
    exit "$([ "${ERRORS:-0}" -eq 0 ] && echo 0 || echo 1)"
fi

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE24" ]; then
    _REPORT_HASHES=$(grep -oiP '(?:commit|commit_hash:)\s*\K[0-9a-f]{7,40}' "$REPORT_PATH" 2>/dev/null | sort -u || true)
    print_sg_pre24
    exit $?
fi

# ─── ここから全量precheck本体をfunction化 ───────────────────────────────
# cache miss時のみ呼び出す。command substitutionのsubshellで実行するため、
# 内部のexitはこのfunction(=subshell)だけを終了し、末尾のEXIT trap(defense_overhead計測)は
# 呼出元プロセスの終了時に1回だけ発火する(subshell exitでは発火しない。動作確認済み)。
_gunshi_precheck_body() {
_GUNSHI_BODY_START_US="${EPOCHREALTIME/./}"; _GUNSHI_BODY_START_US="${_GUNSHI_BODY_START_US:0:16}"
_GUNSHI_MEASURED_MS=0

# SG-PRE2はSG-PRE1と独立だが、従来は2.5s級のworkaround台帳走査を直列実行していた。
# stdoutの節順を変えずに待ち時間だけ重ねるため、結果を既知の単一tmpfileへ先行取得し、
# SG-PRE2位置でwait→catする。失敗は従来どおり表示のみでprecheck判定へ加算しない。
_gunshi_pre2_tmpfile=""
_gunshi_pre2_pid=""
if [ -n "${WORKER_ID:-}" ]; then
    _gunshi_pre2_tmpfile=$(mktemp /tmp/gunshi_pre2_XXXXXX)
    bash "$REPO_ROOT/scripts/gates/gate_ninja_workaround_rate.sh" \
        --ninja "$WORKER_ID" > "$_gunshi_pre2_tmpfile" 2>/dev/null &
    _gunshi_pre2_pid=$!
fi

# ─── L5: GATE CLEAR≠レビュー免除リマインド (殿厳命2026-06-08) ───
echo ""
echo "★★★ レビューの目的は実装の正しさ確認。GATE CLEARはレビュー免除の理由にならない(洗脳#1防止) ★★★"
echo "★★★ infra/scripts変更: binary_checks=yesを鵜呑みにするな。実際に実行して動作確認せよ(洗脳#2防止) ★★★"

# ─── SG-PRE1: gate_report_format.sh ───
echo ""
echo "■ SG-PRE1: gate_report_format.sh"
_PRE1_REPORT_FP="$(sha256sum "$REPORT_PATH" 2>/dev/null | awk '{print $1}')"
_PRE1_VALIDATED_FP=""
if [ -n "$_PRE1_REPORT_FP" ] &&
   [ -f "${REPORT_PATH}.validated_fingerprints" ] &&
   grep -qxF "$_PRE1_REPORT_FP" "${REPORT_PATH}.validated_fingerprints"; then
    _PRE1_VALIDATED_FP="$_PRE1_REPORT_FP"
fi
_GUNSHI_PH_SGPRE1_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_SGPRE1_START_US="${_GUNSHI_PH_SGPRE1_START_US:0:16}"
if GATE_NO_LOG=1 \
   GATE_VALIDATED_FINGERPRINT="$_PRE1_VALIDATED_FP" \
   SHOGUN_DISABLE_MEMORY_DB_CACHE=1 \
   bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT_PATH" 2>/dev/null; then
    echo "  PASS"
    _gunshi_phase_report sg_pre1 "$_GUNSHI_PH_SGPRE1_START_US" pass
else
    echo "  FAIL — フォーマット不備あり。詳細は上記出力参照"
    ERRORS=$((ERRORS + 1))
    _gunshi_phase_report sg_pre1 "$_GUNSHI_PH_SGPRE1_START_US" fail
fi

# ─── SG-PRE2: ninja workaround rate ───
echo ""
echo "■ SG-PRE2: ninja workaround rate"
if [ -n "${WORKER_ID:-}" ]; then
    wait "$_gunshi_pre2_pid" || true
    cat "$_gunshi_pre2_tmpfile"
else
    echo "  SKIP: worker_id not found"
fi
[ -z "$_gunshi_pre2_tmpfile" ] || rm -f "$_gunshi_pre2_tmpfile"

# ─── Batch git data (cmd_3807: PRE3/PRE13/PRE19が独立に行っていた最大4回の全履歴--grep走査を統合) ───
# 実測(docs/research/cmd_3807_gunshi_precheck_speedup.md): 統合前は同一REPO_ROOTへの
# `git log --grep=$PARENT_CMD --numstat`系走査がPRE3(name-only)/PRE13(numstat)/PRE19(numstat)で
# 最大3回重複実行され、1回あたり約1.2s(WSL2 NTFS)。numstat 1回の出力から3列目(path)を抽出すれば
# name-onlyと等価(実データでdiff行数0を確認済み)なため、numstatへ統一し結果を共有する。
_GUNSHI_PH_BATCHGIT_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_BATCHGIT_START_US="${_GUNSHI_PH_BATCHGIT_START_US:0:16}"
_PRE_CMD_FILES=""
_PRE_RECENT_DATA=""
_PRE_PROJECT_NUMSTAT=""  # PROJECT_DIR(dm-signalならDM_SIGNAL_PATH)のnumstat。PRE3のfile一覧+PRE19のDM-Signal合計が共用
_PRE_REPO_NUMSTAT=""     # REPO_ROOTのnumstat。PRE13+PRE19のshogun側合計が共用
_REPORT_HASHES=$(grep -oiP '(?:commit|commit_hash:)\s*\K[0-9a-f]{7,40}' "$REPORT_PATH" 2>/dev/null | sort -u || true)
# 注: 報告が同一commitを短縮形+完全形の2表記で併記するケースがあり、以下のgit呼出ループが
# 該当commitについて2回走る。この重複はSG-PRE19のchanged_lines集計を通じて判定結果
# (adversarial_review要否)に影響するため(実測で確認)、本cmdのAC2(判定結果を一切変えない)
# の対象外としスコープから除外した。cat-file呼出回数のみ次のブロックで削減する。
if [ -n "${FILES_MODIFIED:-}" ] && [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        # PRE3/PRE14: report記載hashがあれば広域git logを避ける(WSL2 NTFS対策)
        while IFS= read -r _hash; do
            [ -z "$_hash" ] && continue
            # 注: hashが別repo(clinic等)のものだとgit fatal(128)→代入の終了コード=128→set -e全死亡するため || true 必須(2026-06-11 cmd_3277で発火した既存バグ)
            # cmd_karo_speed_review_notify_precheck_20260725: 旧実装はcat-file -eを`||`判定用と
            # `if`判定用で無条件に2回呼んでいた(1回目が成功しても2回目を必ず実行)。
            # 1回目の成否を変数に保持して再利用し、同一判定を1呼出へ削減する(結果は不変)。
            _hash_repo="${PROJECT_DIR:-$REPO_ROOT}"
            _hash_ok=0
            if git -C "$_hash_repo" cat-file -e "${_hash}^{commit}" 2>/dev/null; then
                _hash_ok=1
            elif [ "$_hash_repo" != "$REPO_ROOT" ]; then
                _hash_repo="$REPO_ROOT"
                if git -C "$_hash_repo" cat-file -e "${_hash}^{commit}" 2>/dev/null; then
                    _hash_ok=1
                fi
            fi
            if [ "$_hash_ok" -eq 1 ]; then
                _hash_numstat=$(git -C "$_hash_repo" diff-tree --no-commit-id --numstat -r "$_hash" 2>/dev/null || true)
                # numstatの3列目はname-onlyと等価。PRE19のchanged_lines集計に必要な
                # numstat 1回からPRE3/PRE14のpath一覧も導出し、NTFS上の同一tree走査を
                # もう1回行わない。短縮hash/full hashの重複は集計意味を保つため維持する。
                _hash_files=$(printf '%s\n' "$_hash_numstat" | awk -F'\t' 'NF>=3{print $3}')
                _PRE_CMD_FILES+="${_hash_files}"$'\n'
                _PRE_RECENT_DATA+="${_hash_files}"$'\n'
                if [ "$_hash_repo" = "$REPO_ROOT" ]; then _PRE_REPO_NUMSTAT+="${_hash_numstat}"$'\n'; else _PRE_PROJECT_NUMSTAT+="${_hash_numstat}"$'\n'; fi
            fi
        done <<< "$_REPORT_HASHES"
        # 外部repo成果は共有契約がrepo/commit/pathを全て検証済み。
        # PRE3の所有判定へ追加し、platform repoに存在しないことを理由に偽BLOCKしない。
        if [ -n "$_CROSS_REPO_RECORDS" ]; then
            while IFS=$'\t' read -r _cross_repo _cross_hash _cross_path; do
                [ -z "$_cross_path" ] && continue
                _PRE_CMD_FILES+="${_cross_path}"$'\n'
            done <<< "$_CROSS_REPO_RECORDS"
        fi
        _PRE_CMD_FILES=$(printf '%s\n' "$_PRE_CMD_FILES" | sed '/^$/d' | sort -u)
    else
        # PRE3/PRE19-DM用: cmd固有commitのnumstat (1 call)。name-only相当は3列目(path)から導出しPRE3と共用
        _gunshi_batch_git_tmpdir=$(mktemp -d /tmp/gunshi_batch_git_XXXXXX)
        _gunshi_batch_git_project_output="$_gunshi_batch_git_tmpdir/project_numstat"
        _gunshi_batch_git_recent_output="$_gunshi_batch_git_tmpdir/recent_data"
        _gunshi_batch_git_cached_output parent_numstat "${PROJECT_DIR:-$REPO_ROOT}" "$PARENT_CMD" "$_gunshi_batch_git_project_output" || true
        GUNSHI_BATCH_GIT_PROJECT_LOOKUP_DONE=1
        _PRE_PROJECT_NUMSTAT=$(cat "$_gunshi_batch_git_project_output")
        _PRE_CMD_FILES=$(printf '%s\n' "$_PRE_PROJECT_NUMSTAT" | awk -F'\t' 'NF>=3{print $3}' | sort -u)
        # PRE14用: 直近20 commitとファイル (1 call)
        _gunshi_batch_git_cached_output recent_data "$REPO_ROOT" "$PARENT_CMD" "$_gunshi_batch_git_recent_output" || true
        _PRE_RECENT_DATA=$(cat "$_gunshi_batch_git_recent_output")
        rm -f "$_gunshi_batch_git_project_output" "$_gunshi_batch_git_recent_output"
        rmdir "$_gunshi_batch_git_tmpdir" 2>/dev/null || true
    fi
fi
# PRE13/PRE19-shogun用: REPO_ROOTのnumstat。PRE13はhashの有無に関わらず全履歴grep走査が必要なため
# 上のブロックとは独立にガードする(元のPRE13ガードと同一条件=FILES_MODIFIEDのみ)。
# PROJECT_DIR==REPO_ROOT(非DM-Signal報告。実運用で最頻出)なら上のnumstatをそのまま再利用しgit呼出を省略する。
if [ -n "${FILES_MODIFIED:-}" ] && [ -z "$_REPORT_HASHES" ]; then
    if [ "${PROJECT_DIR:-$REPO_ROOT}" = "$REPO_ROOT" ] && [ "${GUNSHI_BATCH_GIT_PROJECT_LOOKUP_DONE:-0}" -eq 1 ]; then
        _PRE_REPO_NUMSTAT="$_PRE_PROJECT_NUMSTAT"
    else
        _PRE_REPO_NUMSTAT=$( { timeout 3 git -C "$REPO_ROOT" log -20 --no-merges --fixed-strings --grep="${PARENT_CMD:-}" --format="" --numstat 2>/dev/null || true; } )
    fi
fi
if [ -z "${FILES_MODIFIED:-}" ]; then
    _gunshi_phase_report batch_git "$_GUNSHI_PH_BATCHGIT_START_US" no_files_modified
elif [ -n "$_REPORT_HASHES" ]; then
    _gunshi_phase_report batch_git "$_GUNSHI_PH_BATCHGIT_START_US" has_hash
elif [ "${GUNSHI_BATCH_GIT_CACHE_HIT:-0}" -eq 1 ]; then
    _gunshi_phase_report batch_git "$_GUNSHI_PH_BATCHGIT_START_US" no_hash_cache_hit
else
    _gunshi_phase_report batch_git "$_GUNSHI_PH_BATCHGIT_START_US" no_hash_full_scan
fi

# ─── SG-PRE3: commit検証 ───
echo ""
echo "■ SG-PRE3: commit検証"

if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
    if [ -n "${FILES_MODIFIED:-}" ]; then
        COMMIT_FOUND=0
        while IFS= read -r fpath; do
            # Report-format rules represent repository-root files as
            # ./name, while Git/cross_repo_commits use name.  Compare the
            # canonical repo-relative spelling so a valid external root file
            # is not rejected as absent.
            _pre3_fpath="${fpath#./}"
            # batch dataから判定 (per-file git log不要)
            if echo "$_PRE_CMD_FILES" | grep -qFx "$_pre3_fpath" 2>/dev/null; then
                echo "  PASS: $fpath → cmd commit found"
                COMMIT_FOUND=1
            elif [ -f "$PROJECT_DIR/$_pre3_fpath" ] 2>/dev/null || [ -f "$fpath" ] 2>/dev/null; then
                echo "  WARN: $fpath → commit not found"
                echo "    → FILE EXISTS (untracked/uncommitted)"
            else
                echo "  WARN: $fpath → commit not found"
                echo "    → FILE NOT FOUND — 成果物不在の可能性"
                # no-code免除はhash不在だけでは認めない。engineがtask/report双方の
                # required:false + 許可task_type一致を検証した場合だけ適用する。
                if [ "${NO_CODE_COMMIT_EXEMPT:-0}" = "1" ] && [ -z "${_primary_hash:-}" ]; then
                    echo "    → (構造化no-code commit契約一致のためERRORS非加算)"
                else
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done <<< "${FILES_MODIFIED:-}"

        if [ "$COMMIT_FOUND" -eq 0 ]; then
            echo "  WARN: cmd_id一致のcommitなし"
        fi
    else
        echo "  SKIP: files_modified empty"
    fi

    # ─── SG-PRE3b: commit hash実在検証 (バグ2対策: 忍者手動記入hash検証) ───
    echo ""
    echo "■ SG-PRE3b: commit hash実在検証"
    REPORT_HASHES="$_REPORT_HASHES"
    if [ -n "$REPORT_HASHES" ]; then
        while IFS= read -r hash; do
            [ -z "$hash" ] && continue
            _owned_repo=""
            if [ -n "$_CROSS_REPO_RECORDS" ]; then
                _owned_repo=$(printf '%s\n' "$_CROSS_REPO_RECORDS" |
                    awk -F '\t' -v hash="$hash" '$2 == hash {print $1; exit}')
            fi
            if [ -n "$_owned_repo" ] && git -C "$_owned_repo" show --quiet "$hash" >/dev/null 2>&1; then
                echo "  PASS: $hash 実在確認(${_owned_repo})"
            elif git -C "$PROJECT_DIR" show --quiet "$hash" >/dev/null 2>&1; then
                echo "  PASS: $hash 実在確認(${PROJECT_DIR})"
            elif git -C "$REPO_ROOT" show --quiet "$hash" >/dev/null 2>&1; then
                echo "  PASS: $hash 実在確認(${REPO_ROOT})"
            else
                echo "  ★★★ WARN: $hash が両リポジトリに不在。commit hash誤記の可能性"
            fi
        done <<< "$REPORT_HASHES"
    else
        echo "  SKIP: 報告にcommit hashなし"
    fi

    # ─── SG-PRE4: backend/app/変更チェック ───
    echo ""
    echo "■ SG-PRE4: backend/app/変更チェック"
    # Find the latest commit for any modified file
    LATEST_COMMIT="${_REPORT_HASHES%%$'\n'*}"
    if [ -n "$LATEST_COMMIT" ]; then
        BACKEND_CHANGES=$(cd "$PROJECT_DIR" && git diff --name-only "${LATEST_COMMIT}^..${LATEST_COMMIT}" -- backend/app/ 2>/dev/null || echo "")
        if [ -z "$BACKEND_CHANGES" ]; then
            echo "  PASS: backend/app/変更なし"
        else
            echo "  WARN: backend/app/に変更あり:"
            while IFS= read -r _line; do echo "    $_line"; done <<< "$BACKEND_CHANGES"
        fi
    else
        echo "  SKIP: commit not resolved"
    fi
else
    echo "  SKIP: project directory not detected"
    echo ""
    echo "■ SG-PRE4: backend/app/変更チェック"
    echo "  SKIP: project directory not detected"
fi

# ─── SG-PRE5: binary_checks項目数(task YAML vs report) ───
echo ""
echo "■ SG-PRE5: binary_checks項目数整合"
if [ -f "${TASK_FILE:-}" ]; then
    echo "${BINARY_CHECKS_MSG:-  SKIP}"
else
    echo "  SKIP: task YAML not found: ${TASK_FILE:-}"
fi

# ─── SG-PRE33: enforcement層の変形検査契約 ───
echo ""
echo "■ SG-PRE33: enforcement層の変形検査契約"
echo "${VARIATION_CHECKS_MSG:-  SKIP: 変形検査契約の対象外}"
if [[ "${VARIATION_CHECKS_MSG:-}" == *"ERROR:"* ]]; then
    ERRORS=$((ERRORS + 1))
fi

# ─── SG-PRE35: new-test necessity contract ───
echo ""
echo "■ SG-PRE35: 新規テスト必要性契約"
if DEPLOY_TASK_LIB_ONLY=1 bash -c 'source "$1/scripts/deploy_task.sh"; deploy_task_test_necessity_precheck "$2" "$3"' _ "$REPO_ROOT" "${TASK_FILE:-/nonexistent}" "$REPORT_PATH"; then
    echo "  PASS: 新規testは必要性契約済み、または既存test変更/テストなし"
else
    echo "  ERROR: taskの新規test必要性契約が未解消"
    ERRORS=$((ERRORS + 1))
fi

# ─── SG-PRE6: ファイル行数確認 ───
echo ""
echo "■ SG-PRE6: files_modified行数"
if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ] && [ -n "${FILES_MODIFIED:-}" ]; then
    while IFS= read -r fpath; do
        if is_generated_large_artifact "$fpath"; then
            echo "  $fpath: SKIP generated large artifact(line-count capped)"
            continue
        fi
        FULL_PATH="$PROJECT_DIR/$fpath"
        if [ -f "$FULL_PATH" ]; then
            LINE_COUNT=$(wc -l < "$FULL_PATH")
            echo "  $fpath: ${LINE_COUNT}行"
        else
            echo "  $fpath: NOT FOUND"
        fi
    done <<< "${FILES_MODIFIED:-}"
else
    echo "  SKIP"
fi

# ─── SG-PRE7: cmd仕様パラメータ突合リマインダ ───
echo ""
echo "■ SG-PRE7: cmd仕様パラメータ突合"
if [ -n "${PARENT_CMD:-}" ]; then
    CMD_SPEC=$(grep -A60 "${PARENT_CMD}:" "$REPO_ROOT/queue/shogun_to_karo.yaml" 2>/dev/null | head -60 || true)
    if [ -n "$CMD_SPEC" ]; then
        # Extract numeric parameters from cmd spec
        PARAMS=$(echo "$CMD_SPEC" | grep -oE '(m=|window|threshold|d=|k=|alpha|span|lookback)[^,)]*[0-9][0-9.]*' || true)
        PARAMS=$(echo "$PARAMS" | head -10)
        if [ -n "$PARAMS" ]; then
            echo "  ★ cmd仕様に数値パラメータ検出。報告との突合必須:"
            echo "$PARAMS" | while IFS= read -r p; do echo "    $p"; done
        else
            echo "  PASS: cmd仕様に明示パラメータなし"
        fi
    else
        echo "  SKIP: shogun_to_karo.yamlに${PARENT_CMD}なし(アーカイブ済み?)"
    fi
else
    echo "  SKIP: parent_cmd not found"
fi

# ─── SG-PRE8: 二重配備検出 ───
echo ""
echo "■ SG-PRE8: 二重配備検出"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${WORKER_ID:-}" ]; then
    if [ -n "${SAME_CMD_NINJAS:-}" ]; then
        echo "  WARN: 二重配備検出! ${PARENT_CMD}は他の忍者にも配備済み: ${SAME_CMD_NINJAS}"
    else
        echo "  PASS: ${PARENT_CMD}は${WORKER_ID}のみ"
    fi
else
    echo "  SKIP: parent_cmd or worker_id not found"
fi

# ─── SG-PRE9: binary_checks result:no → gate_prediction BLOCK予告 (GP-193) ───
print_sg_pre9

# ─── SG-PRE9b: waive_reason×commit_hash矛盾検出 (GP-248) ───
if [ -n "${WAIVE_COMMIT_CONTRADICTION:-}" ]; then
    echo "  ★★★ WARN: ${WAIVE_COMMIT_CONTRADICTION}"
    echo "  → waive_reasonが事実と矛盾。commit存在するのにbc commit:no。FAILが正しい可能性"
fi

# ─── SG-PRE9c: binary_checks yes×task_clarity矛盾検出 (LG043) ───
echo ""
echo "■ SG-PRE9c: binary_checks yes×task_clarity矛盾検出(LG043)"
if [ "${BC_YES_CLARITY_CONTRADICTION:-0}" = "1" ]; then
    echo "  ★★★ ERROR: binary_checks全yesだがtask_clarity/assumption/purpose_gapに未達成・委譲・保留語あり: ${BC_YES_CLARITY_TERMS}"
    echo "  → cmd_3532再発防止: unclear/discretionに『デプロイ後に家老実施』等が残るなら虚偽yes。LGTMではなくFAIL/REQUEST_CHANGES"
    ERRORS=$((ERRORS + 1))
else
    echo "  PASS: binary_checks全yesとtask_clarity系の明示矛盾なし"
fi

# ─── SG-PRE10/10b/11: shared completion-gate contracts ───
echo ""
print_sg_pre10_contracts

# ─── SG-PRE11: lessons_useful形式検証 ───
echo ""
echo "■ SG-PRE11: lessons_useful形式検証"
if [ -f "$REPORT_PATH" ]; then
    _lu_has_items=$(sed -n '/^lessons_useful:/,/^[^ ]/p' "$REPORT_PATH" | grep -c '^\s*- id:' 2>/dev/null || true)
    [[ "$_lu_has_items" =~ ^[0-9]+$ ]] || _lu_has_items=0
    _lu_is_empty_list=$(grep -cE '^lessons_useful:\s*\[\s*\]' "$REPORT_PATH" 2>/dev/null || true)
    [[ "$_lu_is_empty_list" =~ ^[0-9]+$ ]] || _lu_is_empty_list=0
    _lu_field_exists=0
    grep -q '^lessons_useful:' "$REPORT_PATH" 2>/dev/null && _lu_field_exists=1
    # related_lessonsが空なら lessons_useful: [] は正当(FP防止 2026-06-20 cmd_3474で発見)
    _rl_has_items=$(sed -n '/^  related_lessons:/,/^  [a-z]/p' "${TASK_FILE:-/dev/null}" 2>/dev/null | grep -c '^\s*- id:' 2>/dev/null || true)
    [[ "$_rl_has_items" =~ ^[0-9]+$ ]] || _rl_has_items=0
    if { [ "${_lu_is_empty_list:-0}" -gt 0 ] || { [ "$_lu_field_exists" -eq 1 ] && [ "${_lu_has_items:-0}" -eq 0 ]; }; } && [ "${_rl_has_items:-0}" -gt 0 ]; then
        echo "  ERROR: lessons_useful空リスト。related_lessonsが注入済み(${_rl_has_items}件)ならフィードバック必須→GATE BLOCK確実"
        ERRORS=$((ERRORS + 1))
    elif { [ "${_lu_is_empty_list:-0}" -gt 0 ] || { [ "$_lu_field_exists" -eq 1 ] && [ "${_lu_has_items:-0}" -eq 0 ]; }; } && [ "${_rl_has_items:-0}" -eq 0 ]; then
        echo "  PASS: lessons_useful空リスト(related_lessonsも空のため正当)"
    else
        echo "  PASS: lessons_useful ${_lu_has_items}件"
    fi
else
    echo "${LESSONS_USEFUL_MSG:-  SKIP}"
fi

# ─── SG-PRE12: lesson_candidate有 → INFO通知 (GP-195改: FP率高のためWARN→INFO降格) ───
echo ""
echo "■ SG-PRE12: lesson_candidate存在チェック"
if [ "${HAS_LESSON_CANDIDATE:-0}" = "1" ]; then
    echo "  INFO: lesson_candidate有。draft_lessons実件数(PRE12b)で判定"
    echo "  → lesson_candidate有のみではWARN/BLOCKとしない(直近5/5件CLEAR=FP率高)"
    echo "  → draft_lessonsが1件以上あればbash側でWARN昇格(L977-982)"
else
    echo "  PASS: lesson_candidateなし"
fi

# ─── SG-PRE12b: draft_lessons検出 (GP-237) ───
echo ""
echo "■ SG-PRE12b: draft_lessons検出(project lessons.md)"
_draft_lessons_total=0
for _lf in "$REPO_ROOT/tasks/lessons.md" "${PROJECT_DIR:+${PROJECT_DIR}/tasks/lessons.md}"; do
    [ -z "$_lf" ] || [ ! -f "$_lf" ] && continue
    _dc=$(grep -c '^\- \*\*status\*\*: draft' "$_lf" 2>/dev/null || true)
    _dc=${_dc:-0}
    if [ "$_dc" -gt 0 ]; then
        echo "  ★★★ WARN: $_lf にdraft教訓${_dc}件。gate_prediction: WARN(draft_lessons)"
        _draft_lessons_total=$((_draft_lessons_total + _dc))
    fi
done
if [ "$_draft_lessons_total" -eq 0 ]; then
    echo "  PASS: draft教訓なし"
fi

# ─── SG-PRE13: hook/gate系ファイルの大規模削減検出 (GP-205, cmd_1975反省) ───
echo ""
echo "■ SG-PRE13: hook/gate大規模削減検出"
if [ -n "${FILES_MODIFIED:-}" ]; then
    HOOK_GATE_WARN=0
    # §speed最適化(2026-07-01 gunshi-D0→cmd_3807で再統合): git log --grep をper-fileループ外で1回だけ実行。
    # 従来はhook/gateファイルごとにgit log(全履歴grep走査~2s/回)を呼びN倍遅延(cmd_3632で2gate×2s=4s実測)。
    # さらにcmd_3807実測でPRE13単独scanがPRE19(no-hash)の同一REPO_ROOT scanと重複(1.234s+1.177s)と判明。
    # 冒頭のBatch git dataで算出済みの_PRE_REPO_NUMSTATを再利用し、git再呼出をゼロにする
    # (挙動同一・等価性検証済み: docs/research/cmd_3807_gunshi_precheck_speedup.md)。
    _pre13_numstat="$_PRE_REPO_NUMSTAT"
    while IFS= read -r fpath; do
        case "$fpath" in
            *.claude/hooks/*|*scripts/hooks/*|*scripts/gates/*)
                # ループ外取得済みのnumstatからfpath該当分を抽出(per-file git log廃止)
                read -r added deleted < <(
                    printf '%s\n' "$_pre13_numstat" | \
                    awk -v f="$fpath" '$3==f {a+=$1; d+=$2} END{print a+0, d+0}'
                )
                if [ "$deleted" -gt 0 ]; then
                    # 実ファイル行数で削減率を計算(旧: added+deleted近似→+6/-7=53%偽陽性。修正: wc -lで実態計測)
                    if [ -f "$fpath" ]; then
                        file_lines=$(wc -l < "$fpath" 2>/dev/null || echo 0)
                        total_before=$((file_lines + deleted - added))  # 変更前行数 = 現在行数 + 削除 - 追加
                    else
                        total_before=$((added + deleted))  # ファイル不在時はfallback
                    fi
                    [ "$total_before" -le 0 ] && total_before=1  # ゼロ除算防止
                    delete_ratio=$((deleted * 100 / total_before))
                    if [ "$delete_ratio" -gt 50 ]; then
                        echo "  ★★★ WARN: $fpath — 削減率${delete_ratio}%(+${added}/-${deleted}, 変更前${total_before}行)。hook/gateの大規模削減は機能破壊の可能性。git diffで現物確認せよ"
                        HOOK_GATE_WARN=1
                    fi
                fi
                ;;
        esac
    done <<< "$FILES_MODIFIED"
    if [ "$HOOK_GATE_WARN" -eq 0 ]; then
        echo "  PASS: hook/gate系の大規模削減なし"
    else
        echo "  BLOCK: hook/gate系ファイルの50%超削減を検出。テスト結果とCI状態を重点確認するまでレビューCLEAR禁止"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  SKIP: files_modified不明"
fi

# ─── SG-PRE14: revert検出 (cmd_2107事故: revert後にAC3:yesのまま報告) ───
echo ""
echo "■ SG-PRE14: revert検出(files_modified内にrevertされたファイルがないか)"
REVERT_FOUND=0
if [ -n "${FILES_MODIFIED:-}" ] && [ -n "${PARENT_CMD:-}" ]; then
    while IFS= read -r line; do
        fpath=$(echo "$line" | sed 's/.*path: *//' | tr -d "'\"")
        [ -z "$fpath" ] && continue
        [[ "$fpath" == -* ]] && continue
        # batch dataから判定 (per-file git log不要。_PRE_RECENT_DATAで事前取得済み)
        if echo "$_PRE_RECENT_DATA" | grep -B1 -F "$fpath" 2>/dev/null | grep -qi 'revert'; then
            echo "  ★★★ WARN: $fpath に直近revert commitあり。before/after数値がrevert前の可能性。再計測を確認せよ"
            REVERT_FOUND=1
        fi
    done <<< "$FILES_MODIFIED"
    if [ "$REVERT_FOUND" -eq 0 ]; then
        echo "  PASS: revertなし"
    fi
else
    echo "  SKIP"
fi

# ─── SG-PRE15: 並列負荷警告 (計測値汚染リスク) ───
echo ""
echo "■ SG-PRE15: 並列負荷警告(before/after計測値の信頼性)"
source "$REPO_ROOT/scripts/lib/agent_config.sh" 2>/dev/null || true
_ninja_task_files=()
for _nn in $(get_ninja_names 2>/dev/null); do
    [ -f "$REPO_ROOT/queue/tasks/${_nn}.yaml" ] && _ninja_task_files+=("$REPO_ROOT/queue/tasks/${_nn}.yaml")
done
BUSY_NINJAS=$(awk '
    /^[[:space:]]*status:/ {
        st=$2; gsub(/["'"'"']/, "", st)
        if (st=="in_progress" || st=="acknowledged") busy++
        nextfile
    }
    END{print busy+0}
' "${_ninja_task_files[@]}" 2>/dev/null || echo 0)
if [ "$BUSY_NINJAS" -ge 3 ]; then
    echo "  ★★★ WARN: ${BUSY_NINJAS}名の忍者が稼働中。before/after計測値がWSL2 I/O負荷で汚染されている可能性。全忍者idle後の再計測を推奨"
elif [ "$BUSY_NINJAS" -ge 1 ]; then
    echo "  INFO: ${BUSY_NINJAS}名の忍者が稼働中。計測値への影響は軽微"
else
    echo "  PASS: 全忍者idle。計測値は信頼可能"
fi

# ─── SG-PRE15.5: L5 adversarial事前リマインド (§5.6自動化系cmd) ───
echo ""
echo "■ SG-PRE15.5: adversarial事前リマインド(自動化系cmd)"
# §3.2最適化: python3 -c 4回→engine変数参照(ADV_TARGET_MATCH/ADV_FM_SCRIPTS/ADV_BLAST_HIGH)
if [ "${ADV_TARGET_MATCH:-0}" = "1" ]; then
    echo "  ★ target_pathが自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6)"
elif [ "${ADV_FM_SCRIPTS:-0}" = "1" ]; then
    echo "  ★ files_modifiedに自動化系ファイル。finding_categoriesにadversarialを含めよ(§5.6/GP-263b)"
elif [ "${ADV_BLAST_HIGH:-0}" = "1" ]; then
    echo "  ★ blast_radius=highファイル検出。changed_lines<200でもadversarial推奨(GP-265)"
elif [ -z "${TASK_FILE:-}" ] || [ ! -f "${TASK_FILE:-/dev/null}" ]; then
    echo "  SKIP: task YAML不在+非自動化系files_modified"
else
    echo "  PASS: 非自動化系target"
fi

# ─── SG-PRE16: BE impl ゴールデンデータ突合チェック (L-GoldenDataFirst) ───
echo ""
echo "■ SG-PRE16: ゴールデンデータ突合チェック"
if [ "${IS_DM_SIGNAL:-0}" = "1" ]; then
    # §3.2最適化: python3 -c 2回→engine変数参照(TASK_TYPE_BE/HAS_GOLDEN_REF)
    if [ "${TASK_TYPE_BE:-0}" = "1" ]; then
        if [ "${HAS_GOLDEN_REF:-0}" = "0" ]; then
            echo "  ★★★ WARN: BE impl報告にゴールデンデータ突合の記述なし"
            echo "  → 壊れた前後比較ではないか確認せよ(L-GoldenDataFirst)"
            echo "  → docs/research/gunshi_fof_mr_nonlinear_rootcause_20260424.md §8"
        else
            echo "  PASS: ゴールデンデータ突合の記述あり"
        fi
    else
        echo "  SKIP: BE impl/fixタスクではない"
    fi
else
    echo "  SKIP: DM-Signalプロジェクトではない"
fi

# ─── SG-PRE17: AC ID照合(stale AC contamination検出 GP-235) ───
echo ""
echo "■ SG-PRE17: AC ID照合(stale AC検出)"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${CMD_SPEC:-}" ]; then
    # cmdソースからAC IDを抽出
    CMD_AC_IDS=$(echo "$CMD_SPEC" | grep -oP '(?<=id: )AC[0-9]+' | sort -u || true)
    # 報告binary_checksからAC IDを抽出(commitは除外)
    REPORT_AC_IDS=$(awk '/^binary_checks:/{bc=1;next} bc && /^[^ ]/{exit} bc && /^  [A-Z]/{gsub(/:.*$/,"",$0);gsub(/^ +/,"",$0);print}' "$REPORT_PATH" 2>/dev/null | grep -v '^commit$' | sort -u || true)
    if [ -n "$CMD_AC_IDS" ] && [ -n "$REPORT_AC_IDS" ]; then
        STALE_ACS=$(comm -23 <(echo "$REPORT_AC_IDS") <(echo "$CMD_AC_IDS"))
        if [ -n "$STALE_ACS" ]; then
            echo "  ★★★ WARN: stale AC検出! 報告にcmd原本にないAC ID: ${STALE_ACS//$'\n'/, }"
            echo "  → cmd原本AC: ${CMD_AC_IDS//$'\n'/, } / 報告AC: ${REPORT_AC_IDS//$'\n'/, }"
        else
            echo "  PASS: 報告AC IDはcmd原本と一致"
        fi
    else
        echo "  SKIP: AC ID抽出不可(cmd_spec=${#CMD_AC_IDS} report=${#REPORT_AC_IDS})"
    fi
else
    echo "  SKIP: cmd仕様取得不可"
fi

# ─── SG-PRE18: adversarial blast_radius判定 (GP-236) ───
echo ""
echo "■ SG-PRE18: adversarial blast_radius判定(GP-236)"
INFRA_DETECTED=0
INFRA_FILES=""
if [ -n "${FILES_MODIFIED:-}" ]; then
    while IFS= read -r fpath; do
        case "$fpath" in
            *scripts/hooks/*|*scripts/gates/*|*CLAUDE.md|*instructions/*|*.claude/settings*|*config/settings.yaml|*scripts/deploy_task.sh|*scripts/ninja_monitor.sh|*scripts/inbox_write.sh|*scripts/cmd_save.sh|*scripts/cmd_publish.sh|*scripts/cmd_complete_gate.sh|*scripts/report_field_set.sh|*scripts/cmd_quality_log.sh)
                INFRA_FILES="${INFRA_FILES:+$INFRA_FILES, }$fpath"
                INFRA_DETECTED=1
                ;;
        esac
    done <<< "$FILES_MODIFIED"
fi
if [ "$INFRA_DETECTED" -eq 1 ]; then
    echo "  ★★★ WARN: infra対象ファイル検出: ${INFRA_FILES}"
    echo "  → adversarial_review必須。blast_radius大(hook/gate/CLAUDE.md/instructions/settings)"
    echo "  → Red-Team第2パス: 破壊シナリオ・rollback不能性・監視穴を確認せよ"
else
    echo "  PASS: infra対象ファイルなし"
fi

# ─── SG-PRE19: total changed_lines計算 (adversarial観点冷え対策) ───
echo ""
echo "■ SG-PRE19: total changed_lines(adversarial review必要性判定)"
TOTAL_ADDED=0
TOTAL_DELETED=0
_files_modified_trimmed=$(printf '%s\n' "${FILES_MODIFIED:-}" | sed '/^[[:space:]]*$/d' | head -1)
if [ -z "$_files_modified_trimmed" ]; then
    echo "  SKIP: files_modified empty"
elif [ -n "${PARENT_CMD:-}" ]; then
    if [ -n "$_REPORT_HASHES" ]; then
        _changed_counts=$(
            REPORT_HASHES="$_REPORT_HASHES" \
            REPO_ROOT="$REPO_ROOT" \
            IS_DM_SIGNAL="${IS_DM_SIGNAL:-0}" \
            DM_SIGNAL_PATH="${DM_SIGNAL_PATH}" \
            python3 - <<'PY'
import os
import subprocess

repos = [os.environ["REPO_ROOT"]]
_dm_path = os.environ.get("DM_SIGNAL_PATH", "")
if os.environ.get("IS_DM_SIGNAL") == "1" and _dm_path and os.path.isdir(f"{_dm_path}/.git"):
    repos.append(_dm_path)

added_total = 0
deleted_total = 0
for commit_hash in os.environ.get("REPORT_HASHES", "").splitlines():
    commit_hash = commit_hash.strip()
    if not commit_hash:
        continue
    for repo in repos:
        try:
            proc = subprocess.run(
                ["git", "-C", repo, "diff-tree", "--no-commit-id", "--numstat", "-r", commit_hash],
                text=True,
                capture_output=True,
                timeout=2,
                check=False,
            )
        except subprocess.TimeoutExpired:
            continue
        for line in proc.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) < 2 or parts[0] == "-" or parts[1] == "-":
                continue
            try:
                added_total += int(parts[0])
                deleted_total += int(parts[1])
            except ValueError:
                continue
print(f"{added_total} {deleted_total}")
PY
        )
        TOTAL_ADDED="${_changed_counts%% *}"
        TOTAL_DELETED="${_changed_counts##* }"
    else
        # shogunリポジトリ (cmd_3807: 冒頭Batch git dataの_PRE_REPO_NUMSTATを再利用。git再呼出なし)
        while IFS=$'\t' read -r added deleted _; do
            [[ "$added" == "-" ]] && continue
            TOTAL_ADDED=$((TOTAL_ADDED + added))
            TOTAL_DELETED=$((TOTAL_DELETED + deleted))
        done < <(printf '%s\n' "$_PRE_REPO_NUMSTAT")
        # DM-Signalリポジトリ（プロジェクトがDM-Signalの場合。IS_DM_SIGNAL=1の時PROJECT_DIR==DM_SIGNAL_PATHが
        # 保証されるため_PRE_PROJECT_NUMSTATが該当データ。cmd_3807: 冒頭Batch git dataを再利用しgit再呼出なし）
        if [ "${IS_DM_SIGNAL:-0}" = "1" ] && [ -d "${DM_SIGNAL_PATH}/.git" ]; then
            while IFS=$'\t' read -r added deleted _; do
                [[ "$added" == "-" ]] && continue
                TOTAL_ADDED=$((TOTAL_ADDED + added))
                TOTAL_DELETED=$((TOTAL_DELETED + deleted))
            done < <(printf '%s\n' "$_PRE_PROJECT_NUMSTAT")
        fi
    fi
    TOTAL_CHANGED=$((TOTAL_ADDED + TOTAL_DELETED))
    echo "  changed_lines: +${TOTAL_ADDED}/-${TOTAL_DELETED} = ${TOTAL_CHANGED}"
    if [ "$TOTAL_CHANGED" -ge 200 ]; then
        echo "  ★★★ adversarial_review必須(changed_lines=${TOTAL_CHANGED} >= 200)"
        echo "  → review_logにchanged_lines: ${TOTAL_CHANGED}とadversarial_review:を記録せよ"
    fi
else
    echo "  SKIP: PARENT_CMD未取得"
fi

# ─── SG-PRE20: related_lessons+lessons_useful空検出 (SG7盲点補完) ───
echo ""
echo "■ SG-PRE20: related_lessons+lessons_useful整合"
if [ -f "${TASK_FILE:-}" ]; then
    _rl_count=$(awk '
        /^  related_lessons:/ { sec=1; next }
        sec && /^  [A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
        sec && /^  - id:/ { c++ }
        END { print c+0 }
    ' "$TASK_FILE" 2>/dev/null)
    _lu_count=$(awk '
        /^lessons_useful:/ { sec=1; next }
        sec && /^[A-Za-z_][A-Za-z0-9_]*:/ { sec=0 }
        sec && /^[[:space:]]*- id:/ { c++ }
        END { print c+0 }
    ' "$REPORT_PATH" 2>/dev/null)
    if [ "${_rl_count:-0}" -gt 0 ] && [ "${_lu_count:-0}" -eq 0 ]; then
        echo "  WARN: related_lessons ${_rl_count}件注入済みだがlessons_useful空リスト → BLOCK確実"
        ERRORS=$((ERRORS + 1))
    else
        # 件数一致だけではGATEのlesson_feedback_set_mismatchを予測できない(2026-07-27実証:
        # 'PASS: related_lessons=1 lessons_useful=3' を出しながらGATEがextra=L070,L230,L312でBLOCK)。
        # 判定契約の正本は cmd_complete_gate.sh:2844 validate_lesson_feedback_set。同一規則(strict=
        # assigned_lesson_ids有ならmissingも見る / 無ければsubset)でID集合を突合する。
        # Shared SSOT: this is the same strict/subset contract used by
        # cmd_complete_gate.sh's validate_lesson_feedback_set.  Keep the
        # precheck as a pure caller; do not duplicate the Python rule here.
        _set_status=$(python3 "$REPO_ROOT/scripts/lib/report_gate_contract.py" \
            lesson-feedback-set "$TASK_FILE" "$REPORT_PATH" 2>/dev/null || true)
        if [ -n "${_set_status:-}" ] && [[ "$_set_status" != OK\ * ]]; then
            # 2026-08-26訂正: subset+extra-onlyも正本gate(cmd_complete_gate.sh validate_lesson_feedback_set
            # → record_block_reason lesson_feedback_set_mismatch)はBLOCKする(report_gate_contract.py:
            # extra があれば mode に関係なく MISMATCH)。旧文言『WARN止まり』は誤り(kagemaru ghost AC1
            # 報告 extra=L241 で軍師が偽陽性と誤読)。ERRORはSG-PRE11で計上済みのため二重加算しない。
            if echo "$_set_status" | grep -qP 'mode=subset.*missing=none.*extra=[^n]'; then
                echo "  ERROR(SG-PRE11で計上済): lessons_useful集合にtask契約外あり(自発使用) → 正本gateもBLOCK。extraを lessons_useful から外し lesson_candidate/自由記述へ移せ: ${_set_status}"
            else
                echo "  ERROR: lessons_useful集合がtask契約と不一致 → GATE BLOCK確実: ${_set_status}"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "  PASS: related_lessons=${_rl_count} lessons_useful=${_lu_count} set=${_set_status:-unchecked}"
        fi
    fi
else
    echo "  SKIP: task YAML未取得"
fi

# ─── SG-PRE21: 因果辺照合(L7穴1対策: レビュー時の因果消費) ───
echo ""
echo "■ SG-PRE21: 因果辺照合(causal_backlinks)"
_GUNSHI_PH_SGPRE21_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_SGPRE21_START_US="${_GUNSHI_PH_SGPRE21_START_US:0:16}"
if [ -n "${FILES_MODIFIED:-}" ]; then
    _causal_script="$REPO_ROOT/scripts/causal_backlinks.sh"
    if [ -f "$_causal_script" ]; then
        _causal_out=""
        _causal_timeout=0
        # cmd_karo_hotfix_round2_full_precheck_20260728: files_modified 1件ごとに
        # causal_backlinks.sh(rg全木走査)を逐次起動していた(恒常課税、実測本fixtureで
        # 2件=926ms)。causal_backlinks.sh自体はscope外(planned_paths外)で変更しないため、
        # 同一コマンド・同一引数を各stemごとにbackground並列実行し、waitで合流する
        # (SG-PRE26の三層記憶検索で既に採用済みの並列パターンと同型)。判定結果
        # (ERRORS/GATE_PREDICTION)には影響しない情報echoのみのため、並列化してもAC2の
        # 「判定結果を一切変えない」制約に抵触しない。元の逐次ループと出力順序を一致させる
        # ため、SKIP行と結果行を元のfpath順のまま構築する二段構え(1: 各stem結果を並列取得
        # →一時ファイル 2: 元の順序でSKIP/結果を組み立て)にする。
        _causal_tmpdir=$(mktemp -d /tmp/gunshi_pre21_XXXXXX)
        _causal_order=()
        _causal_pids=()
        _causal_i=0
        for fpath in $FILES_MODIFIED; do
            if is_generated_large_artifact "$fpath"; then
                _causal_order+=("SKIP:${fpath}")
                continue
            fi
            _stem=$(basename "$fpath" | sed 's/\.[^.]*$//')
            _causal_i=$((_causal_i + 1))
            _causal_order+=("STEM:${_causal_i}:${_stem}")
            (
                _cb_links=$(timeout 3 bash "$_causal_script" "$_stem" 2>/dev/null)
                _cb_rc=$?
                printf '%s\n' "$_cb_rc" > "$_causal_tmpdir/${_causal_i}.rc"
                printf '%s\n' "$_cb_links" > "$_causal_tmpdir/${_causal_i}.out"
            ) &
            _causal_pids+=("$!")
        done
        for _cb_pid in "${_causal_pids[@]}"; do
            wait "$_cb_pid" || true
        done
        for _causal_entry in "${_causal_order[@]}"; do
            case "$_causal_entry" in
                SKIP:*)
                    _causal_out="${_causal_out}  ${_causal_entry#SKIP:}→ SKIP: generated large artifact"$'\n'
                    ;;
                STEM:*)
                    _stem_idx="${_causal_entry#STEM:}"; _stem_idx="${_stem_idx%%:*}"
                    _stem="${_causal_entry#STEM:*:}"
                    _rc="$(cat "$_causal_tmpdir/${_stem_idx}.rc" 2>/dev/null || echo 1)"
                    _links="$(head -3 "$_causal_tmpdir/${_stem_idx}.out" 2>/dev/null || true)"
                    if [ "$_rc" -eq 124 ]; then
                        _causal_timeout=1
                        _causal_out="${_causal_out}  ${_stem}→ WARN: causal_backlinks timeout(3s). 手動照合せよ"$'\n'
                        continue
                    fi
                    [ -n "$_links" ] && _causal_out="${_causal_out}  ${_stem}→ ${_links}"$'\n'
                    ;;
            esac
        done
        # D002遵守: project外(/tmp)パスへのrm -rf(再帰削除)は絶対禁則。
        # このディレクトリ配下は本ループ自身が作った"${i}.rc"/"${i}.out"の
        # 既知単一ファイルのみのため、個別rm -f(非再帰)で後始末しrmdir(非再帰・
        # 空でなければ失敗するfail-safe)でディレクトリを閉じる。
        for _causal_cleanup_i in $(seq 1 "${_causal_i:-0}" 2>/dev/null || true); do
            rm -f "$_causal_tmpdir/${_causal_cleanup_i}.rc" "$_causal_tmpdir/${_causal_cleanup_i}.out"
        done
        rmdir "$_causal_tmpdir" 2>/dev/null || true
        if [ -n "$_causal_out" ]; then
            if [ "$_causal_timeout" -eq 1 ]; then
                echo "  因果辺照合WARN(タイムアウトあり。PASS扱い禁止):"
            else
                echo "  因果辺あり(設計意図カタログ照合せよ):"
            fi
            echo "$_causal_out" | head -10
        else
            echo "  PASS: 因果辺なし(causal_backlinks 0件)"
        fi
    else
        echo "  SKIP: causal_backlinks.sh not found"
    fi
else
    echo "  SKIP: files_modified empty"
fi
_gunshi_phase_report sg_pre21 "$_GUNSHI_PH_SGPRE21_START_US" "n${_causal_i:-0}"

# ─── SG-PRE22: semantic概念表示(L7浸透: レビュー時に関連概念を強制表示) ───
echo ""
echo "■ SG-PRE22: semantic関連概念(L7)"
_semantic_script="$REPO_ROOT/scripts/semantic_search.sh"
_purpose=""
if [ -n "${CMD_SPEC:-}" ]; then
    _purpose=$(echo "$CMD_SPEC" | grep 'purpose:' | head -1 | sed 's/.*purpose: *//' | sed 's/"//g')
fi
[ -z "$_purpose" ] && [ -n "${PARENT_CMD:-}" ] && _purpose="$PARENT_CMD"
if [ -f "$_semantic_script" ] && [ -n "${_purpose:-}" ]; then
    set +e
    _sem_result=$(SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 timeout 1 bash "$_semantic_script" "$_purpose" 2>/dev/null)
    _sem_rc=$?
    _sem_result=$(printf '%s\n' "$_sem_result" | head -5 || true)
    set -e
    if [ "$_sem_rc" -eq 124 ]; then
        echo "  WARN: semantic_search timeout(1s). 手動で関連概念を確認せよ"
    elif [ -n "$_sem_result" ]; then
        echo "  関連概念:"
        printf '%s\n' "$_sem_result" | while IFS= read -r _line; do echo "    $_line"; done || true
    else
        echo "  NO_MATCH: 関連概念なし(aliases候補として蓄積検討)"
    fi
else
    echo "  SKIP: semantic_search.sh not found or purpose empty"
fi

# ─── SG-PRE23: context/*.md変更時のvercel_phase参照切れ検出(GP-264) ───
echo "■ SG-PRE23: vercel_phase参照切れ検出"
_context_files=()
while IFS= read -r _fm_line; do
    case "$_fm_line" in context/*.md*) _context_files+=("$_fm_line");; esac
done < <(echo "$FILES_MODIFIED" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep '^context/.*\.md' || true)
if [ "${#_context_files[@]}" -gt 0 ] && [ -f "$REPO_ROOT/scripts/gates/gate_vercel_phase.sh" ]; then
    if run_sg_pre23 2>/dev/null; then
        echo "  PASS: source generation context変更の参照先は全て実在"
    else
        echo "  [CRITICAL] source-generation gate_vercel_phase FAIL — context変更に参照切れあり"
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }vercel_phase:broken_refs"
    fi
else
    echo "  SKIP: context/*.md変更なし or gate_vercel_phase.sh不在"
fi

# ─── SG-PRE24: instructions変更時のgenerated/貫通チェック(GP-265) ───
echo "■ SG-PRE24: generated/貫通チェック"
if ! print_sg_pre24; then
    echo "  ★ generated/未貫通 BLOCK"
    ERRORS=$((ERRORS + 1))
    GATE_PREDICTION="BLOCK"
    GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }generated_not_penetrated"
fi

# ─── SG-PRE25: command×files_modified名前照合 (LG036 Step3.5自動化) ───
# readonly_ref除外ロジック: cmd_complete_gate.sh L4204-4312と同一判定
echo ""
echo "■ SG-PRE25: command×files_modified名前照合(LG036)"
if [ -n "${PARENT_CMD:-}" ] && [ -n "${FILES_MODIFIED:-}" ]; then
    _cmd_spec="$REPO_ROOT/queue/shogun_to_karo.yaml"
    if [ -f "$_cmd_spec" ]; then
        _pre25_assigned_acs=$(python3 - "$REPORT_PATH" "${TASK_FILE:-}" <<'PY'
import sys, yaml
def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError):
        return {}
report = load(sys.argv[1])
task = load(sys.argv[2]).get("task", {}) if len(sys.argv) > 2 and sys.argv[2] else {}
raw = report.get("assigned_acs") or report.get("parent_ac_coverage") or task.get("assigned_acs") or []
if isinstance(raw, str):
    raw = [raw]
print(",".join(str(v) for v in raw if str(v).strip()))
PY
)
        _pre25_result=$(bash "$REPO_ROOT/scripts/lib/extract_command_files.sh" \
            --cmd-id "${PARENT_CMD}" \
            --spec "$_cmd_spec" \
            --repo "$REPO_ROOT" \
            --files-modified "${FILES_MODIFIED}" \
            --assigned-acs "${_pre25_assigned_acs}" \
            --report "$REPORT_PATH" 2>/dev/null || true)
        # 複数行出力対応: READONLY_EXCLUDED行とWARN/PASS行を分離処理
        _has_warn=0
        _has_readonly=0
        while IFS= read -r _line; do
            case "$_line" in
                PASS*)
                    echo "  PASS: command欄ファイルとfiles_modified名前照合OK(readonly_ref除外済み)"
                    ;;
                WARN:*)
                    echo "  ★★★ ERROR: command欄ファイルがfiles_modifiedに不在(readonly_ref除外後): ${_line#WARN: }"
                    echo "  → verdict: FAILにせよ。gateのcommand_files_modified_mismatchはLG037の3分類を区別できない(殿厳命Step3.5。5件連続LGTM→BLOCK)"
                    _has_warn=1
                    ERRORS=$((ERRORS + 1))
                    ;;
                READONLY_EXCLUDED:*)
                    echo "  INFO: readonly_ref除外済み: ${_line#READONLY_EXCLUDED: }"
                    _has_readonly=1
                    ;;
                SKIP*)
                    echo "  ${_line}"
                    ;;
                *)
                    echo "  ${_line}"
                    ;;
            esac
        done <<< "$_pre25_result"
    else
        echo "  SKIP: shogun_to_karo.yaml不在"
    fi
elif [ "${FM_FORMAT_INVALID:-0}" = "1" ]; then
    # files_modifiedはあるがpath:キーが1件も抽出できない=形式違反(check/result散文等)。
    # 黙ってSKIPするとSG-PRE25素通り→gate mismatch BLOCK(cmd_3274実証 2026-06-10)
    echo "  ★★★ ERROR: files_modifiedにpath:キーが1件もない(形式違反)。gateのcommand_files_modified_mismatchでBLOCKされる"
    echo "  → verdict: FAILにせよ。忍者に path: 形式での再記入を求めよ(report_field_set.sh経由)"
    ERRORS=$((ERRORS + 1))
else
    echo "  SKIP: PARENT_CMD or FILES_MODIFIED empty"
fi

if [ "${GUNSHI_PRECHECK_ONLY:-}" = "SG-PRE25" ]; then
    [ "$ERRORS" -eq 0 ]
    exit $?
fi

# ─── GATE_PREDICTION (自動計算) ───
# PRE12b draft_lessons補正: engine.pyに未連携のためbash側で上書き
if [ "${_draft_lessons_total:-0}" -gt 0 ]; then
    if [ "${GATE_PREDICTION:-CLEAR}" = "CLEAR" ]; then
        GATE_PREDICTION="WARN"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }draft_lessons:${_draft_lessons_total}件(tasks/lessons.md)"
    fi
fi
# ─── SG-PRE26: 三層記憶検索(殿厳命2026-06-10: 使用しないのはバグ) ───
echo ""
echo "■ SG-PRE26: 三層記憶検索(L0-L7貫通)"
_GUNSHI_PH_SGPRE26_START_US="${EPOCHREALTIME/./}"; _GUNSHI_PH_SGPRE26_START_US="${_GUNSHI_PH_SGPRE26_START_US:0:16}"
_mem_branch="query_empty"
_mem_query="${_purpose:-${PARENT_CMD:-}}"
if [ -n "$_mem_query" ]; then
    _mem_db_script="$REPO_ROOT/scripts/memory_db_query.sh"
    if [ -f "$_mem_db_script" ]; then
        _mem_keywords=$(echo "$_mem_query" | tr ' 　/\n' '\n' | grep -E '.{2,}' | head -3 | tr '\n' ' ')
        _mem_result=""
        _mem_tmpdir=$(mktemp -d /tmp/gunshi_pre26_XXXXXX)
        _mem_i=0
        _mem_pids=()
        for _kw in $_mem_keywords; do
            _mem_i=$((_mem_i + 1))
            bash "$_mem_db_script" "SELECT ts, substr(summary,1,80) FROM events WHERE summary LIKE '%${_kw}%' ORDER BY ts DESC LIMIT 2" > "$_mem_tmpdir/$_mem_i" 2>/dev/null &
            _mem_pids+=("$!")
        done
        for _pid in "${_mem_pids[@]}"; do
            wait "$_pid" || true
        done
        for _f in "$_mem_tmpdir"/*; do
            [ -f "$_f" ] || continue
            _hit=$(head -4 "$_f")
            [ -n "$_hit" ] && _mem_result="${_mem_result}${_hit}"$'\n'
        done
        # D002: /tmp配下への再帰削除は禁止。作成した既知の単一ファイルだけを
        # 非再帰で除去し、空ディレクトリだけrmdirする。
        for _mem_cleanup_i in $(seq 1 "${_mem_i:-0}" 2>/dev/null || true); do
            rm -f "$_mem_tmpdir/${_mem_cleanup_i}"
        done
        rmdir "$_mem_tmpdir" 2>/dev/null || true
        if [ -n "$_mem_result" ]; then
            echo "  記憶DB関連エントリ:"
            # 注: ループ本体最後の[ -n ]がfalseだとset -e+pipefailで全体死亡するためelse分岐必須(2026-06-11発見の既存バグ)
            printf '%s\n' "$_mem_result" | head -6 | while IFS= read -r _line; do if [ -n "$_line" ]; then echo "    $_line"; fi; done
            echo "  ★ 上記を[MEM: memory_db ts=YYYY-MM-DD]で引用してレビューに反映せよ"
            _mem_branch="hit_n${#_mem_pids[@]}"
        else
            echo "  記憶DB: 関連エントリなし(検索キーワード: $_mem_keywords)"
            _mem_branch="nohit_n${#_mem_pids[@]}"
        fi
    else
        echo "  SKIP: memory_db_query.sh not found"
        _mem_branch="script_missing"
    fi
else
    echo "  SKIP: cmd purpose/id empty"
fi
_gunshi_phase_report memory_search "$_GUNSHI_PH_SGPRE26_START_US" "$_mem_branch"

# ─── SG-PRE27: verify系関数evidence検出(LG040: 検証関数は単体実行で検証せよ) ───
# cmd_3275: verify_sheets()がranges配列バグで常時Falseなのにevidence「一致確認」記載。
# 関数呼出形に限定した有界パターン(LG039: 無制限マッチの貪欲FP防止)
_sg_pre27_check() {
    local report_path="$1"
    local verify_fns simulation_block command_block actual_value fn fn_name missing=0
    verify_fns=$(grep -oE '\b(verify|validate|readback|parity)_[a-z_]{1,40}\(' "$report_path" 2>/dev/null | sort -u | head -5 || true)
    if [ -z "$verify_fns" ]; then
        echo "  PASS: verify系関数evidenceなし(対象外確認済み)"
        return 0
    fi

    echo "  INFO: 報告に検証関数の呼出evidenceあり:"
    printf '%s\n' "$verify_fns" | while IFS= read -r fn; do
        [ -n "$fn" ] && echo "    - ${fn})"
    done
    simulation_block=$(awk '/^operational_simulation:/{found=1; next} found && /^[^[:space:]#]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    command_block=$(printf '%s\n' "$simulation_block" | awk '/^  command:/{found=1; print; next} found && /^  [a-zA-Z_][a-zA-Z0-9_]*:/{exit} found{print}')

    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        fn_name=${fn%\(}
        if ! printf '%s\n' "$command_block" | grep -Fq "$fn_name"; then
            echo "  BLOCK(LG040): operational_simulation.commandに${fn_name}の単体実行証跡がない"
            missing=1
        fi
    done <<< "$verify_fns"
    actual_value=$(printf '%s\n' "$simulation_block" | sed -n 's/^  actual:[[:space:]]*//p' | head -1)
    actual_value=$(printf '%s' "$actual_value" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]"'"'']*//; s/[[:space:]"'"'']*$//')
    if [ -z "$actual_value" ]; then
        echo "  BLOCK(LG040): operational_simulation.actualに戻り値の実測がない"
        missing=1
    fi
    if ! printf '%s\n' "$simulation_block" | grep -Eq "^  result:[[:space:]]*['\"]?PASS(['\"]?[[:space:]]*(#.*)?)?$"; then
        echo "  BLOCK(LG040): operational_simulation.resultがPASSではない"
        missing=1
    fi
    if [ "$missing" -ne 0 ]; then
        echo "  ★ evidenceの『一致確認』だけでは関数が動く証明にならない(cmd_3275実証)"
        return 2
    fi
    echo "  PASS(LG040): 検証関数を単体実行したcommand・戻り値・PASS証跡あり"
}
echo ""
echo "■ SG-PRE27: verify系関数evidence検出(LG040)"
if ! _sg_pre27_check "$REPORT_PATH"; then
    ERRORS=$((ERRORS + 1))
fi

# ─── SG-PRE28: 正直報告×AC本旨1:1 evidence BLOCK(LG044) ───
echo ""
echo "■ SG-PRE28: 正直報告×AC本旨照合(LG044)"
if [ "${AC_EVIDENCE_MAPPING_MISSING:-0}" = "1" ]; then
    echo "  WARN: 正直報告フラグあり・binary_checks全yesだがac_evidence_mapping欠落: ${AC_EVIDENCE_MAPPING_MISSING_KEYS}"
    echo "  → LG044: レビュー観点として確認せよ(gateにac_evidence_mappingチェックなし=BLOCK予測しない)"
elif [ "${HONEST_REPORT_FLAG:-0}" = "1" ]; then
    echo "  PASS: 正直報告フラグあり、全非commit ACのac_evidence_mappingを確認"
else
    echo "  PASS: 正直報告フラグなし(通常レビュー)"
fi

# ─── SG-PRE29: FE変更時Next build確認BLOCK(LG045: pytest/JestだけではApp Router制約を検出できない) ───
_sg_pre29_check() {
    local report_path="$1" fm_block fe_files evidence
    fm_block=$(awk '/^files_modified:/{found=1; next} found && /^[^[:space:]#]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    fe_files=$(printf '%s\n' "$fm_block" | grep -Ei '(^|/)(frontend)/|\.tsx([^[:alnum:]_]|$)|\.ts([^[:alnum:]_]|$)' | grep -v '^[[:space:]]*#' | grep -v 'backend/' || true)
    if [ -z "$fe_files" ]; then
        echo "  PASS: frontend変更なし(対象外)"
        return 0
    fi

    evidence=$(awk '/^(result|test_results|operational_simulation):/{found=1} found && /^[^[:space:]#]/ && $0 !~ /^(result|test_results|operational_simulation):/{found=0} found{print}' "$report_path" 2>/dev/null | tr '\n' ' ' || true)
    if ! printf '%s\n' "$evidence" | grep -qiE 'npm[[:space:]]+run[[:space:]]+build|next[[:space:]]+build'; then
        echo "  BLOCK(LG045): frontend変更あり。npm run build/next buildの実行証跡がない"
        return 2
    fi
    if printf '%s\n' "$evidence" | grep -qiE 'build.{0,80}(FAIL|failed|error)|(FAIL|failed|error).{0,80}build'; then
        echo "  BLOCK(LG045): Next build失敗証跡あり。LGTM不可"
        return 2
    fi
    if ! printf '%s\n' "$evidence" | grep -qiE 'build.{0,80}(PASS|passed|succeeded|success)|(PASS|passed|succeeded|success).{0,80}build'; then
        echo "  BLOCK(LG045): Next build言及はあるがPASS実測がない"
        return 2
    fi
    echo "  PASS(LG045): frontend変更あり+Next build PASS実測あり"
}
echo ""
echo "■ SG-PRE29: FE変更×Next build確認(LG045)"
if ! _sg_pre29_check "$REPORT_PATH"; then
    ERRORS=$((ERRORS + 1))
    GATE_PREDICTION="BLOCK"
    GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG045:next_build_pass_missing"
fi

# ─── SG-PRE30: daemon lib-only再利用時グローバル変数列挙BLOCK(LG046) ───
# 関数化: テストから呼出し可能にする
_sg_pre30_check() {
    local report_path="$1"
    # files_modifiedブロックのみ抽出(次のトップレベルキーで停止)
    local _fm_block
    _fm_block=$(awk '/^files_modified:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$report_path" 2>/dev/null || true)
    local _daemon_files
    _daemon_files=$(echo "$_fm_block" | grep -iE 'ninja_monitor|ntfy_listener|inbox_watcher|dashboard_auto' | grep -v '#' || true)
    local _lib_only_contract
    # A source path in prose/evidence is not a lib-only execution contract.
    # Restrict the non-daemon trigger to an explicit *_LIB_ONLY=1 assignment
    # within the files_modified block only (not the full report text).
    # Fix: evidence内の "NINJA_MONITOR_LIB_ONLY=1 source ..." 等が偽陽性発火していた (INS-20260807-113145934-921f)
    _lib_only_contract=$(echo "$_fm_block" | grep -ciE '(^|[^[:alnum:]_])[A-Z][A-Z0-9_]*_LIB_ONLY[[:space:]]*=[[:space:]]*1([^[:digit:]]|$)' 2>/dev/null || true)
    if [ -n "$_daemon_files" ] || [ "${_lib_only_contract:-0}" -gt 0 ]; then
        local _simulation _command _actual
        _simulation=$(awk '/^operational_simulation:/{found=1; next} found && /^[^[:space:]#]/{exit} found{print}' "$report_path" 2>/dev/null || true)
        _command=$(printf '%s\n' "$_simulation" | sed -n 's/^  command:[[:space:]]*//p' | head -1)
        _actual=$(printf '%s\n' "$_simulation" | sed -n 's/^  actual:[[:space:]]*//p' | head -1)
        if ! printf '%s\n' "$_command" | grep -qE "grep.*(-oE|-Eo).*[A-Z_]"; then
            echo "  BLOCK(LG046): daemon/lib-only変更あり。operational_simulation.commandに参照グローバルの機械列挙コマンドがない"
            return 2
        fi
        if ! printf '%s' "$_actual" | grep -q '[^[:space:]"'"'"']'; then
            echo "  BLOCK(LG046): operational_simulation.actualに列挙したグローバル変数の実測がない"
            return 2
        fi
        if ! printf '%s\n' "$_simulation" | grep -Eq "^  result:[[:space:]]*['\"]?PASS(['\"]?[[:space:]]*(#.*)?)?$"; then
            echo "  BLOCK(LG046): 初期化場所/lib-only時の値を突合したPASS証拠がない"
            return 2
        fi
        echo "  PASS(LG046): 参照グローバルの機械列挙・実測・初期化突合PASSあり"
    else
        echo "  PASS: daemon/lib-only変更なし(対象外)"
    fi
}
echo ""
echo "■ SG-PRE30: daemon lib-only再利用(LG046)"
if ! _sg_pre30_check "$REPORT_PATH"; then
    ERRORS=$((ERRORS + 1))
    GATE_PREDICTION="BLOCK"
    GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG046:global_enumeration_evidence_missing"
fi

# ─── SG-PRE31: N×M一致パターン意味検算BLOCK(LG048) ─── 関数定義・focused-exitは冒頭(SG-PRE33直後)へ移動済み
echo ""
echo "■ SG-PRE31: N×M意味検算(LG048)"
if ! _sg_pre31_check "$REPORT_PATH"; then
    ERRORS=$((ERRORS + 1))
    GATE_PREDICTION="BLOCK"
    GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG048:semantic_validation_missing"
fi

# ─── SG-PRE32: 視点列間の全行一致検出(LG049: 独立視点の縮退検出) ───
# 関数化: テストから呼出し可能にする
_sg_pre32_check() {
    local files_modified_text="${1:-}"
    local project_dir="${2:-$PROJECT_DIR}"
    local repo_root="${3:-$REPO_ROOT}"
    local detector="$repo_root/scripts/lib/detect_view_column_degeneracy.py"

    if [ -z "$files_modified_text" ]; then
        echo "  PASS: files_modified空(対象外)"
        return
    fi
    if [ ! -f "$detector" ]; then
        echo "  WARN(LG049): detector missing: $detector"
        return
    fi

    local _found_md=0
    local _found_warn=0
    local _path _full_path _detected
    while IFS= read -r _path; do
        _path="$(echo "$_path" | sed 's/.*path: *//' | tr -d "'\"" | sed 's/^[[:space:]-]*//;s/[[:space:]]*$//')"
        [ -z "$_path" ] && continue
        case "$_path" in
            *.md|*.markdown) ;;
            *) continue ;;
        esac
        _found_md=1
        _full_path="$project_dir/$_path"
        if [ ! -f "$_full_path" ]; then
            _full_path="$repo_root/$_path"
        fi
        if [ ! -f "$_full_path" ]; then
            continue
        fi
        _detected="$(python3 "$detector" "$_full_path" 2>/dev/null || true)"
        if [ -n "$_detected" ]; then
            echo "  WARN(LG049): $_path"
            echo "$_detected" | sed 's/^/    /'
            echo "    → 視点列が全データ行で一致。Expanding/WF等の独立算出が同一系列へ縮退していないか確認せよ"
            _found_warn=1
        fi
    done <<< "$files_modified_text"

    if [ "$_found_warn" -eq 0 ]; then
        if [ "$_found_md" -eq 0 ]; then
            echo "  PASS: Markdown成果物なし(対象外)"
        else
            echo "  PASS: 視点列間の全行一致なし"
        fi
    fi
}
echo ""
echo "■ SG-PRE32: 視点列間一致検出(LG049)"
_sg_pre32_check "${FILES_MODIFIED:-}" "$PROJECT_DIR" "$REPO_ROOT"

# ─── SG-PRE34: integration contract未テスト検出(LG055: テスト存在≠実行経路) ───
echo ""
echo "■ SG-PRE34: integration contract検出(LG055)"
_pre34_has_integration=false
_pre34_search="${CMD_SPEC:-}"
# CMD_SPECがなければ報告YAML自体からACとcommandを検索
if [ -z "$_pre34_search" ] && [ -f "$REPORT_PATH" ]; then
    _pre34_search=$(grep -E 'description:|command:|summary:|acceptance_criteria' "$REPORT_PATH" 2>/dev/null | head -20 || true)
fi
if [ -n "$_pre34_search" ]; then
    if echo "$_pre34_search" | grep -qiE '実装|経路|連携|統合|integrate|consume|generate.*notify|焼き込む|配備経路|round.*task|multi.?round'; then
        _pre34_has_integration=true
    fi
fi
if [ "$_pre34_has_integration" = true ]; then
    # integration ACには実走証跡(operational_simulation with実行command/expected/actual/result)が必須
    _pre34_has_opsim=false
    if [ -f "$REPORT_PATH" ]; then
        if grep -qE 'operational_simulation:|実走証跡:|liveproof:' "$REPORT_PATH" 2>/dev/null; then
            # 実走証跡に実行command+result/actual等の具体的証跡があるか
            if grep -A10 -E 'operational_simulation:|実走証跡:|liveproof:' "$REPORT_PATH" 2>/dev/null | grep -qiE 'command.*:|actual.*:|result.*PASS|expected.*:|entrypoint' 2>/dev/null; then
                _pre34_has_opsim=true
            fi
        fi
    fi
    if [ "$_pre34_has_opsim" = true ]; then
        echo "  PASS: integration AC+operational_simulation実走証跡あり"
    else
        echo "  ★★★ ERROR(LG055): integration ACだがoperational_simulation実走証跡なし"
        echo "  → reportにoperational_simulation(実行command/expected/actual/result PASS)を記録せよ"
        echo "  → production entrypointを実走し、文書grepでなく挙動を確認せよ"
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG055:integration_opsim_missing"
    fi
else
    # report gateと同じ境界: docs/data-only以外は4項目+result二値を必須化。
    _pre34_contract=$(python3 - "$REPORT_PATH" 2>/dev/null <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
fm = data.get('files_modified') or []
paths = [str(x.get('path') or '') for x in fm if isinstance(x, dict)] if isinstance(fm, list) else []
prefixes = ('docs/', 'context/', 'logs/', 'queue/', 'projects/')
exempt = bool(paths) and all(p.startswith(prefixes) for p in paths)
ops = data.get('operational_simulation')
valid = isinstance(ops, dict) and all(str(ops.get(k) or '').strip() for k in ('command','expected','actual','result')) and str(ops.get('result')).strip() in ('PASS','FAIL')
print(('exempt' if exempt else 'required') + ' ' + ('valid' if valid else 'invalid'))
PY
    ) || _pre34_contract="required invalid"
    if [ "$_pre34_contract" = "exempt invalid" ] || [ "$_pre34_contract" = "exempt valid" ]; then
        echo "  PASS: docs/data-only operational_simulation免除"
    elif [ "$_pre34_contract" = "required valid" ]; then
        echo "  PASS: operational_simulation四要素+result二値"
    else
        echo "  ★★★ ERROR(LG055): operational_simulation四要素欠落またはresult不正"
        ERRORS=$((ERRORS + 1))
        GATE_PREDICTION="BLOCK"
        GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:+${GATE_PREDICTION_REASON}; }LG055:opsim_contract_invalid"
    fi
fi

echo ""
echo "■ GATE_PREDICTION (自動計算 — SG7 gate_predictionに転記せよ)"
echo "  prediction: ${GATE_PREDICTION:-UNKNOWN}"
echo "  reason: ${GATE_PREDICTION_REASON:-engine未実行}"
if [ "${GATE_PREDICTION:-}" = "WARN" ] || [ "${GATE_PREDICTION:-}" = "BLOCK" ]; then
    echo "  ★★★ gate_prediction: ${GATE_PREDICTION} をSG7バンドルに転記必須"
fi

# ─── 出力フォールバックERRORカウント(cmd定義消失時のSG-PRE25 ERROR見逃し防止) ───
# SG-PRE25等がERROR行を出力したがERROR変数が加算されなかったケースを捕捉
_output_errors=$(echo "${_pre25_result:-}" | grep -c '^WARN:' || true)
if [ "${_output_errors:-0}" -gt 0 ] && [ "$ERRORS" -eq 0 ]; then
    ERRORS=$((_output_errors))
    echo "★ フォールバックERROR検出: SG-PRE25出力にWARN ${_output_errors}件だがERRORS未加算だった"
fi

# ─── 総合判定 ───
# ERRORS is an observation count, not a verdict. Select the conclusion that
# the engine precomputed for shell findings. This adds no Python startup or I/O.
if [ "$ERRORS" -gt 0 ]; then
    GATE_PREDICTION="${GATE_PREDICTION_WITH_SHELL_FINDINGS:?engine conclusion missing}"
fi
# full_precheck_body_rest: 個別計装した子(sg_pre1/batch_git/memory_search)を除く
# body内の残り約30チェック合計(SG-PRE2/SG-PRE19等の未計装区間)。子と非加算・診断専用。
# _gunshi_phase_reportは開始時刻からの単純経過時間しか出せない(子の減算不可)ため、
# ここだけ body_total - _GUNSHI_MEASURED_MS を直接計算して書き込む。
_gunshi_body_now_us="${EPOCHREALTIME/./}"; _gunshi_body_now_us="${_gunshi_body_now_us:0:16}"
_gunshi_body_total_ms=$(( (_gunshi_body_now_us - _GUNSHI_BODY_START_US + 999) / 1000 ))
_gunshi_body_rest_ms=$(( _gunshi_body_total_ms - _GUNSHI_MEASURED_MS ))
if [ "$_gunshi_body_rest_ms" -lt 0 ]; then
    _gunshi_body_rest_ms=0
fi
defense_overhead_write_async gate_gunshi_report_precheck full_precheck_body_rest "$_gunshi_body_rest_ms" PASS \
    "gunshi-precheck-body_rest-measured${_GUNSHI_MEASURED_MS}ms:$$:${_GUNSHI_BODY_START_US}" || true
echo ""
echo "=== 総合: ERRORS=$ERRORS ==="
if [ "$GATE_PREDICTION" = "BLOCK" ]; then
    echo "★ FAIL項目あり。レビュー前に確認せよ"
    exit 1
else
    echo "★ 機械的検証PASS。6観点レビューに進め"
    exit 0
fi
}
# ─── ここまでfunction化 ───────────────────────────────────────────────

set +e
_gunshi_precheck_output="$(_gunshi_precheck_body)"
_gunshi_precheck_rc=$?
set -e
printf '%s\n' "$_gunshi_precheck_output"

if [ "$GUNSHI_PRECHECK_CACHE_WRITE" -eq 1 ] && [ -n "$GUNSHI_PRECHECK_CACHE_FILE" ]; then
    mkdir -p "$(dirname "$GUNSHI_PRECHECK_CACHE_FILE")" 2>/dev/null || true
    if {
        printf '%s\n' "$_gunshi_precheck_rc"
        printf '%s\n' "$_gunshi_precheck_output"
    } > "${GUNSHI_PRECHECK_CACHE_FILE}.$$" 2>/dev/null; then
        mv "${GUNSHI_PRECHECK_CACHE_FILE}.$$" "$GUNSHI_PRECHECK_CACHE_FILE" 2>/dev/null || true
    fi
fi

exit "$_gunshi_precheck_rc"
