#!/usr/bin/env bash
# Extract file references from command text with the same write-vs-readonly
# heuristics used by SG-PRE25.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  extract_command_files.sh --command-text <text> --repo <repo> [--target-path <path> ...]
  extract_command_files.sh --cmd-id <cmd_id> --spec <yaml> --repo <repo> [--files-modified <paths>] [--assigned-acs <AC1,AC2>]
EOF
}

cmd_id=""
command_text=""
spec_file=""
repo=""
files_modified=""
report_file=""
assigned_acs=""
target_paths=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd-id)
            cmd_id="${2:-}"
            shift 2
            ;;
        --command-text)
            command_text="${2:-}"
            shift 2
            ;;
        --spec)
            spec_file="${2:-}"
            shift 2
            ;;
        --repo)
            repo="${2:-}"
            shift 2
            ;;
        --files-modified)
            files_modified="${2:-}"
            shift 2
            ;;
        --report)
            report_file="${2:-}"
            shift 2
            ;;
        --assigned-acs)
            assigned_acs="${2:-}"
            shift 2
            ;;
        --target-path)
            target_paths+=("${2:-}")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[[ -n "$repo" ]] || repo="$(pwd)"

COMMAND_TEXT_ENV="$command_text" \
CMD_ID_ENV="$cmd_id" \
SPEC_FILE_ENV="$spec_file" \
REPO_ENV="$repo" \
FILES_MODIFIED_ENV="$files_modified" \
REPORT_FILE_ENV="$report_file" \
ASSIGNED_ACS_ENV="$assigned_acs" \
TARGET_PATHS_ENV="$(printf '%s\n' "${target_paths[@]}")" \
python3 - <<'PY'
import glob
import os
import re
import sys
import yaml

cmd_id = os.environ.get("CMD_ID_ENV", "").strip()
cmd_text = os.environ.get("COMMAND_TEXT_ENV", "")
spec_file = os.environ.get("SPEC_FILE_ENV", "")
repo = os.environ.get("REPO_ENV", ".")
fm_raw = os.environ.get("FILES_MODIFIED_ENV", "")
report_file = os.environ.get("REPORT_FILE_ENV", "")
target_paths = [p.strip().strip("`'\"") for p in os.environ.get("TARGET_PATHS_ENV", "").splitlines() if p.strip()]
spec = {}
assigned_acs = {v.upper() for v in re.split(r"[\s,]+", os.environ.get("ASSIGNED_ACS_ENV", "")) if v.strip()}

def load_cmd_from_payload(payload, target_cmd):
    commands = payload.get("commands", {}) if isinstance(payload, dict) else {}
    if isinstance(commands, dict):
        row = commands.get(target_cmd, {})
    elif isinstance(commands, list):
        row = next((item for item in commands if isinstance(item, dict) and str(item.get("id", "")) == target_cmd), {})
    else:
        row = {}
    return row if isinstance(row, dict) else {}

if cmd_id and not cmd_text and spec_file and os.path.exists(spec_file):
    try:
        with open(spec_file, encoding="utf-8") as fh:
            spec = load_cmd_from_payload(yaml.safe_load(fh) or {}, cmd_id)
        cmd_text = str(spec.get("command", "") or "")
        criteria = spec.get("acceptance_criteria") or []
        if assigned_acs and isinstance(criteria, (list, dict)):
            if isinstance(criteria, dict):
                rows = [dict(row, id=ac_id) for ac_id, row in criteria.items() if isinstance(row, dict)]
            else:
                rows = [row for row in criteria if isinstance(row, dict)]
            all_ids = {str(row.get("id", "")).upper() for row in rows if row.get("id")}
            if assigned_acs < all_ids:
                cmd_text = "\n".join(
                    str(row.get("description", "") or "")
                    for row in rows
                    if str(row.get("id", "")).upper() in assigned_acs
                )
    except Exception as exc:
        print(f"SKIP: {exc}")
        raise SystemExit(0)

if cmd_id and not cmd_text:
    for path in sorted(glob.glob(os.path.join(repo, "queue", "archive", "cmds", f"{cmd_id}*.yaml")), reverse=True):
        try:
            with open(path, encoding="utf-8") as fh:
                spec = load_cmd_from_payload(yaml.safe_load(fh) or {}, cmd_id)
            cmd_text = str(spec.get("command", "") or "")
            if cmd_text:
                break
        except Exception:
            pass

if not target_paths and spec:
    raw_targets = spec.get("target_path", spec.get("target_paths", ""))
    if isinstance(raw_targets, str):
        target_paths = [raw_targets]
    elif isinstance(raw_targets, (list, tuple)):
        target_paths = [str(v) for v in raw_targets]
    target_paths = [p.strip().strip("`'\"") for p in target_paths if str(p).strip()]

if not cmd_text:
    print("SKIP: command欄なし")
    raise SystemExit(0)

pattern = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+"
    r"\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv))"
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
content_operation_markers = (
    "追加", "算出", "計算", "引用", "抽出", "集計", "要約", "説明", "記載", "報告",
    "add", "calculate", "quote", "extract", "summarize", "report",
)
debug_enabled = os.environ.get("EXTRACT_COMMAND_FILES_DEBUG", "").strip().lower() in {"1", "true", "yes"}

def marker_pos(text, markers):
    positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
    return min(positions) if positions else -1

def marker_pos_detail(text, markers):
    hits = [(text.find(marker), marker) for marker in markers if text.find(marker) >= 0]
    hits = [(pos, marker) for pos, marker in hits if pos >= 0]
    return min(hits, default=(-1, ""), key=lambda item: item[0])

def debug(ref, message):
    if debug_enabled:
        print(f"DEBUG: {os.path.basename(ref)} {message}")

def is_probable_product_token(ref):
    clean_ref = ref.strip().strip("`'\".,:;()[]{}")
    if "/" in clean_ref or "\\" in clean_ref:
        return False
    stem = os.path.basename(clean_ref).split(".", 1)[0]
    if not stem[:1].isupper():
        return False
    if stem.upper() == stem:
        return False
    return not os.path.isfile(os.path.join(repo, clean_ref))

def ref_matches_target(ref, target):
    ref = ref.strip().strip("./")
    target = target.strip().strip("./")
    if not ref or not target:
        return False
    return ref == target or ref.endswith("/" + target) or target.endswith("/" + ref) or ref.startswith(target.rstrip("/") + "/") or os.path.basename(ref) == os.path.basename(target)

def is_exact_target_path(target):
    clean_target = target.strip().strip("./")
    if not clean_target:
        return False
    candidate = clean_target if os.path.isabs(clean_target) else os.path.join(repo, clean_target)
    if os.path.isfile(candidate):
        return True
    # New files may not exist yet.  A known file extension is the explicit
    # file-target signal; extensionless paths remain directory targets.
    return bool(os.path.splitext(os.path.basename(clean_target))[1])

def is_design_spec_instruction_ref(ref, local_text, sentence_tail, match_start):
    clean_ref = ref.strip().strip("./")
    if not ((clean_ref.startswith("docs/spec/") or clean_ref.startswith("docs/research/")) and clean_ref.endswith(".md")):
        return False
    if target_paths and any(ref_matches_target(ref, target) for target in target_paths):
        return False
    # docs/research/ is always a readonly reference (recon reports, analysis results)
    # unless target_path points there (already excluded above)
    if clean_ref.startswith("docs/research/"):
        return True
    tail = (local_text + " " + sentence_tail)[:160]
    prefix = cmd_text[max(0, match_start - 40):match_start]
    section_ref = re.search(r"^\s*の?(?:§|第?\d+章|変更\d|変更[0-9０-９一二三四五六七八九十]+|実装順序)", local_text) is not None
    instruction_words = ("実装" in tail) or ("従い" in tail) or ("通り" in tail) or ("記載" in tail)
    explicit_design_context = ("設計書" in sentence_tail) or ("設計書" in prefix)
    return (section_ref and instruction_words) or (explicit_design_context and instruction_words)

matches = list(pattern.finditer(cmd_text))
seen = set()
write_refs = []
readonly_refs = []
for idx, match in enumerate(matches):
    ref = match.group(1).strip().strip("`'\".,:;()[]{}")
    if not ref or ref in seen:
        continue
    if is_probable_product_token(ref):
        continue
    seen.add(ref)
    # An execution-prefix script is a tool invocation, not a deliverable.
    # Classify it before broad directory target matching (for example
    # target_path=scripts would otherwise claim bash scripts/run_tests.sh).
    prefix_tokens = cmd_text[max(0, match.start() - 60):match.start()].split()
    is_exec_prefix = bool(prefix_tokens) and prefix_tokens[-1].lower() in {"bash", "python3", "python", "sh", "bats", "node"}
    if is_exec_prefix:
        readonly_refs.append(os.path.basename(ref))
        debug(ref, "exec_prefix readonly=True")
        continue
    # An explicit file target is a deliverable even when surrounding prose
    # contains a read marker.  Directory targets must still reach the normal
    # readonly heuristics below; otherwise every cited tool under `scripts`
    # becomes a false deliverable.
    if target_paths and any(
        is_exact_target_path(target) and ref_matches_target(ref, target)
        for target in target_paths
    ):
        write_refs.append(os.path.basename(ref))
        debug(ref, "exact_target_path readonly=False")
        continue
    sentence_end_candidates = [pos for pos in (cmd_text.find("\n", match.end()), cmd_text.find("。", match.end()), cmd_text.find("；", match.end()), cmd_text.find(";", match.end())) if pos >= 0]
    sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(cmd_text)
    next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
    local = cmd_text[match.end():next_file_start]
    sentence_tail = cmd_text[match.end():sentence_end]
    read_pos, read_marker = marker_pos_detail(local, read_markers)
    if read_pos < 0:
        read_pos, read_marker = marker_pos_detail(sentence_tail, read_markers)
    write_pos, write_marker = marker_pos_detail(sentence_tail, write_markers)
    if is_design_spec_instruction_ref(ref, local, sentence_tail, match.start()):
        debug(ref, f"design_or_research_ref readonly=True")
        readonly_refs.append(os.path.basename(ref))
        continue
    next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos)
    has_clause_boundary = False
    if read_pos >= 0 and write_pos >= 0 and read_pos < write_pos:
        clause_positions = [p for p in (sentence_tail.find("、", read_pos), sentence_tail.find(",", read_pos)) if p >= 0]
        has_clause_boundary = bool(clause_positions and min(clause_positions) < write_pos)
    # read_marker immediately after filename (within 5 chars) = strong readonly signal
    read_immediate = read_pos >= 0 and read_pos <= 5
    content_op_after_read = False
    if read_immediate and read_marker == "から" and write_pos >= 0 and read_pos < write_pos:
        between = sentence_tail[read_pos:write_pos + len(write_marker)]
        content_op_after_read = any(marker in between for marker in content_operation_markers)
    is_readonly = is_exec_prefix or has_clause_boundary or content_op_after_read or (read_pos >= 0 and (write_pos < 0 or read_pos < write_pos) and (write_pos < 0 or next_ref_before_write or read_immediate))
    base = os.path.basename(ref)
    debug(ref, f"read={read_marker or '-'}:{read_pos} write={write_marker or '-'}:{write_pos} exec={is_exec_prefix} boundary={has_clause_boundary} content_op_after_read={content_op_after_read} readonly={is_readonly}")
    (readonly_refs if is_readonly else write_refs).append(base)

fm_bases = {os.path.basename(p.strip()) for p in fm_raw.splitlines() if p.strip()}
task_readonly = set()
if cmd_id:
    for tf in glob.glob(os.path.join(repo, "queue", "tasks", "*.yaml")):
        try:
            with open(tf, encoding="utf-8") as fh:
                task = (yaml.safe_load(fh) or {}).get("task", {}) or {}
            if task.get("parent_cmd", "") != cmd_id:
                continue
            for rr in task.get("readonly_ref") or []:
                p = rr.get("path", rr) if isinstance(rr, dict) else str(rr)
                if p:
                    task_readonly.add(os.path.basename(p.strip()))
        except Exception:
            pass

ved_bases = set()
if report_file and os.path.exists(report_file):
    try:
        with open(report_file, encoding="utf-8") as fh:
            report_data = yaml.safe_load(fh) or {}
        for ved in report_data.get("verified_existing_dependency") or []:
            p = ved.get("path", ved) if isinstance(ved, dict) else str(ved)
            if p:
                ved_bases.add(os.path.basename(p.strip()))
    except Exception:
        pass

unmatched = sorted(set(write_refs) - fm_bases - task_readonly - ved_bases) if fm_raw else []

if ved_bases:
    print("VED_EXCLUDED: " + " ".join(sorted(ved_bases)))
if readonly_refs:
    print("READONLY_EXCLUDED: " + " ".join(sorted(set(readonly_refs))))
if unmatched:
    print("WARN: " + " ".join(unmatched))
elif fm_raw:
    print("PASS")
else:
    for ref in sorted(set(write_refs)):
        print(ref)
PY
