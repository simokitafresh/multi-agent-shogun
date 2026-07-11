#!/usr/bin/env bash
# semantic-links: [[Skill設計ルール]]
# skill_auto_improve.sh — convert skill FAIL patterns into SKILL.md prevention steps.
#
# Usage:
#   bash scripts/skill_auto_improve.sh [--top 3] [--apply] [--skill <name>]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_ROOT/scripts/lib/agent_config.sh" 2>/dev/null || true
export SKILL_IMPROVE_NINJA_NAMES="$(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"
SKILLS_DIRS="${SKILL_AUTO_IMPROVE_SKILLS_DIRS:-$REPO_ROOT/skills:$HOME/.codex/skills:$HOME/.claude/skills}"
top_n=3
apply=false
skill_filter=""
unchanged_threshold="${SKILL_AUTO_IMPROVE_UNCHANGED_THRESHOLD:-3}"
escalation_state="${SKILL_AUTO_IMPROVE_STATE_JSON:-$REPO_ROOT/logs/skill_auto_improve_state.json}"
bulletin_script="${SKILL_AUTO_IMPROVE_BULLETIN_SCRIPT:-$REPO_ROOT/scripts/bulletin_write.sh}"
bulletin_posted_by="${SKILL_AUTO_IMPROVE_POSTED_BY:-karo}"
training_task_generator="${SKILL_AUTO_IMPROVE_TRAINING_GENERATOR:-$REPO_ROOT/scripts/training_task_generator.sh}"

usage() {
    sed -n '1,7p' "$0" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log) LOG_FILE="${2:-}"; shift 2 ;;
        --skills-dirs) SKILLS_DIRS="${2:-}"; shift 2 ;;
        --top) top_n="${2:-}"; shift 2 ;;
        --skill) skill_filter="${2:-}"; shift 2 ;;
        --unchanged-threshold) unchanged_threshold="${2:-}"; shift 2 ;;
        --escalation-state) escalation_state="${2:-}"; shift 2 ;;
        --apply) apply=true; shift ;;
        --dry-run) apply=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

python3 - "$LOG_FILE" "$SKILLS_DIRS" "$top_n" "$apply" "$skill_filter" "$REPO_ROOT" "$unchanged_threshold" "$escalation_state" "$bulletin_script" "$bulletin_posted_by" "$training_task_generator" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import yaml

log_file, skills_dirs, top_n_raw, apply_raw, skill_filter, repo_root, unchanged_threshold_raw, escalation_state_raw, bulletin_script, bulletin_posted_by, training_task_generator_script = sys.argv[1:12]

# CSafeLoader: 7.7x faster than Python SafeLoader for large YAML files.
# Falls back to SafeLoader if C extension is unavailable.
_yaml_loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

# --- Gate FIX hint lookup (skill_auto_improve) ---
# Lazy import: gate_report_format_main is only needed when --apply is given.
# Avoids ~70ms NTFS .pyc read on every non-apply invocation.
_grfm = None
_gate_dir = os.path.join(repo_root, "scripts", "gates")


def _load_grfm():
    global _grfm
    if _grfm is not None:
        return _grfm
    if os.path.isdir(_gate_dir) and _gate_dir not in sys.path:
        sys.path.insert(0, _gate_dir)
    try:
        import gate_report_format_main as m  # type: ignore
        _grfm = m if hasattr(m, "lookup_fix_hints") else False
    except Exception:
        _grfm = False
    return _grfm if _grfm is not False else None

try:
    top_n = int(top_n_raw)
except ValueError:
    print("--top must be an integer", file=sys.stderr)
    raise SystemExit(2)
if top_n < 1:
    print("--top must be >= 1", file=sys.stderr)
    raise SystemExit(2)
try:
    unchanged_threshold = int(unchanged_threshold_raw)
except ValueError:
    print("--unchanged-threshold must be an integer", file=sys.stderr)
    raise SystemExit(2)
if unchanged_threshold < 1:
    print("--unchanged-threshold must be >= 1", file=sys.stderr)
    raise SystemExit(2)
apply_changes = apply_raw.lower() == "true"
escalation_state_path = Path(escalation_state_raw)


def _cache_path(log_path):
    digest = hashlib.sha1(str(log_path).encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"skill_auto_improve_cache_{digest}.json"


def _parse_log_scalar(raw):
    value = str(raw or "").strip()
    if not value:
        return ""
    if value.startswith('"'):
        body = value[1:]
        if body.endswith('"'):
            body = body[:-1]
        return body.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value


def _load_entries_lenient(path):
    entries = []
    current = None
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return entries
    for line in lines:
        if line.startswith("- "):
            if isinstance(current, dict):
                entries.append(current)
            current = {}
            rest = line[2:]
            if ":" in rest:
                key, value = rest.split(":", 1)
                current[key.strip()] = _parse_log_scalar(value)
            continue
        if current is None or not line.startswith("  ") or ":" not in line:
            continue
        key, value = line.strip().split(":", 1)
        current[key.strip()] = _parse_log_scalar(value)
    if isinstance(current, dict):
        entries.append(current)
    return entries


def load_entries(path):
    try:
        stat = Path(path).stat()
        cache_key = (stat.st_mtime_ns, stat.st_size)
    except FileNotFoundError:
        return []
    cache_file = _cache_path(path)
    if cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            if tuple(cached.get("key", [])) == cache_key:
                return cached["entries"]
        except (json.JSONDecodeError, KeyError):
            pass
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.load(fh, Loader=_yaml_loader) or {}
        entries = [entry for entry in (data.get("executions") or []) if isinstance(entry, dict)]
    except yaml.YAMLError:
        entries = _load_entries_lenient(path)
    except FileNotFoundError:
        return []
    try:
        cache_file.write_text(
            json.dumps({"key": list(cache_key), "entries": entries}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass
    return entries


def iter_skill_files():
    # Name-based dedup: skills with the same name in different dirs are considered
    # duplicates (covers symlink case, e.g. ~/.codex/skills/cmd-complete -> NTFS skills/).
    # Avoids Path.resolve() per entry (~9ms/call on NTFS), saving ~470ms cold.
    seen_names = set()
    for raw_dir in skills_dirs.split(":"):
        if not raw_dir:
            continue
        root = Path(os.path.expanduser(raw_dir))
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir(), key=lambda p: p.name):
            if child.name in seen_names:
                continue
            skill_file = child / "SKILL.md"
            if not skill_file.is_file():
                continue
            seen_names.add(child.name)
            yield child.name, skill_file


_skill_index = None
GATE_SKILL_MAP = {
    "gate_report_format": "report-write",
}


def _get_skill_index():
    global _skill_index
    if _skill_index is None:
        _skill_index = {}
        for name, path in iter_skill_files():
            _skill_index.setdefault(name, path)
    return _skill_index


def skill_file_for(skill_name, logged_path):
    indexed = _get_skill_index().get(skill_name)
    if indexed:
        return indexed
    if logged_path:
        path = Path(os.path.expanduser(str(logged_path)))
        if path.is_file():
            return path
    return None


_ninja_env = os.environ.get("SKILL_IMPROVE_NINJA_NAMES", "hayate kagemaru hanzo saizo kotaro tobisaru")
NINJA_NAMES_RE = r"(?:" + "|".join(_ninja_env.split()) + ")"


def normalize_reason(value):
    normalized = " ".join(str(value or "").split())
    if not normalized:
        return ""

    # Group by root cause, not by the volatile command or worker that hit it.
    # Keep gate names such as cmd_complete_gate intact; they are causal context.
    def _cmd_repl(match):
        token = match.group(0)
        if token.endswith("_gate"):
            return token
        return "<cmd_id>"

    normalized = re.sub(r"\bcmd_[A-Za-z0-9][A-Za-z0-9_-]*\b", _cmd_repl, normalized)
    normalized = re.sub(rf"\b{NINJA_NAMES_RE}(?=:)", "<ninja>", normalized)
    normalized = re.sub(rf"\b{NINJA_NAMES_RE}(?=_report_)", "<ninja>", normalized)
    return normalized


def shorten(value, limit=180):
    if len(value) <= limit:
        return value
    return value[: limit - 3] + "..."


def marker_for(skill_name, reason):
    digest = hashlib.sha1(f"{skill_name}\0{reason}".encode("utf-8")).hexdigest()[:12]
    return f"<!-- skill-auto-improve:{digest} -->"


def escalation_key(row):
    raw = f"{row['skill']}\0{row.get('gate', '')}\0{row['reason']}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def parse_event_ts(value):
    """Parse execution timestamps for ordering; invalid values stay unresolved."""
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", raw).replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def pass_resolves_fail(pass_ts, fail_ts):
    """Fail closed: only a valid PASS strictly newer than FAIL resolves it."""
    parsed_pass = parse_event_ts(pass_ts)
    parsed_fail = parse_event_ts(fail_ts)
    return parsed_pass is not None and parsed_fail is not None and parsed_pass > parsed_fail


def load_escalation_state(path):
    if not path.is_file():
        return {"patterns": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"patterns": {}}
    if not isinstance(data, dict) or not isinstance(data.get("patterns"), dict):
        return {"patterns": {}}
    return data


def save_escalation_state(path, state):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
        os.close(fd)
        Path(tmp).write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp, path)
    except OSError as exc:
        print(f"WARN: escalation state write failed: {exc}", file=sys.stderr)


def is_code_fix_cleared(state_entry, last_fail=""):
    if not isinstance(state_entry, dict):
        return False
    cleared_at = str(
        state_entry.get("code_fix_cleared_pass_ts")
        or state_entry.get("code_fix_cleared_at")
        or ""
    )
    # A FAIL recorded after CLEAR starts a new streak.  The old CLEAR marker
    # must not suppress a genuinely unresolved recurrence forever.
    if last_fail and cleared_at and not pass_resolves_fail(cleared_at, last_fail):
        return False
    return bool(cleared_at or state_entry.get("code_fix_cleared_by"))


def reset_escalation_counters(state_entry):
    """Synchronize all streak/notified state when a pattern is cleared."""
    state_entry["unchanged_streak"] = 0
    state_entry["notified_streak"] = 0
    state_entry["training_notified_streak"] = 0


def classify_fail_cause(row, skill_changed, unchanged_streak, state_entry=None):
    if is_code_fix_cleared(state_entry):
        return "code_fix_cleared", "code fix already cleared; skip reclassification"
    reason = row["reason"].lower()
    code_markers = [
        "traceback",
        "syntax error",
        "command not found",
        "permission denied",
        "no such file",
        "exit code",
        "script",
        "exception",
    ]
    if any(marker in reason for marker in code_markers):
        return "code_fix_required", "FAIL reason indicates script/runtime failure"
    if not skill_changed and unchanged_streak >= unchanged_threshold:
        return "code_fix_required", f"SKILL.md unchanged {unchanged_streak} consecutive runs"
    return "skill_doc_improvable", "SKILL.md prevention step can still change or has not exhausted threshold"


def request_code_fix(row, unchanged_streak, state_entry):
    if is_code_fix_cleared(state_entry):
        print(f"ESCALATION_SKIPPED_CODE_FIX_CLEARED: {row['skill']} streak={unchanged_streak}")
        return False
    if state_entry.get("notified_streak", 0) >= unchanged_streak:
        print(f"ESCALATION_SKIPPED_ALREADY_NOTIFIED: {row['skill']} streak={unchanged_streak}")
        return False
    if not Path(bulletin_script).is_file():
        print(f"ESCALATION_SKIPPED_NO_BULLETIN: {bulletin_script}")
        return False
    content = (
        f"skill_auto_improve escalation: {row['skill']} のFAILがSKILL.md改善で閉じていないため、"
        f"コード修正cmd起票を要請。gate={row.get('gate') or 'unknown_gate'} "
        f"reason={shorten(row['reason'], 180)} unchanged_streak={unchanged_streak} "
        f"threshold={unchanged_threshold} last_fail={row.get('last_fail') or 'unknown'}"
    )
    env = os.environ.copy()
    env.setdefault("BULLETIN_NOTIFY", "shogun")
    try:
        proc = subprocess.run(
            ["bash", bulletin_script, bulletin_posted_by, content, "false", "action_required"],
            cwd=repo_root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    except Exception as exc:
        print(f"ESCALATION_FAILED: {row['skill']} {exc}")
        return False
    if proc.returncode != 0:
        stderr = " ".join(proc.stderr.split())
        print(f"ESCALATION_FAILED: {row['skill']} exit={proc.returncode} {shorten(stderr, 180)}")
        return False
    print(f"ESCALATED_CODE_FIX: {row['skill']} streak={unchanged_streak} gate={row.get('gate') or 'unknown_gate'}")
    state_entry["notified_streak"] = unchanged_streak
    return True


def request_training_task(row, unchanged_streak, state_entry):
    """Generate training task when escalation is detected (SKILL.md unchanged)."""
    if is_code_fix_cleared(state_entry):
        print(f"TRAINING_SKIPPED_CODE_FIX_CLEARED: {row['skill']} streak={unchanged_streak}")
        return False
    if state_entry.get("training_notified_streak", 0) >= unchanged_streak:
        print(f"TRAINING_SKIPPED_ALREADY_NOTIFIED: {row['skill']} streak={unchanged_streak}")
        return False
    if not Path(training_task_generator_script).is_file():
        print(f"TRAINING_SKIPPED_NO_GENERATOR: {training_task_generator_script}")
        return False
    try:
        proc = subprocess.run(
            [
                "bash", training_task_generator_script,
                "--skill", row["skill"],
                "--gate", row.get("gate") or "unknown_gate",
                "--reason", shorten(row["reason"], 300),
                "--streak", str(unchanged_streak),
                "--failure-at", str(row.get("last_fail") or ""),
            ],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
    except Exception as exc:
        print(f"TRAINING_FAILED: {row['skill']} {exc}")
        return False
    if proc.returncode != 0:
        stderr = " ".join(proc.stderr.split())
        print(f"TRAINING_FAILED: {row['skill']} exit={proc.returncode} {shorten(stderr, 180)}")
        return False
    for line in proc.stdout.strip().splitlines():
        print(line)
    state_entry["training_notified_streak"] = unchanged_streak
    return True


def concrete_prevention_steps(reason):
    # Phase 1: gate-specific FIX hints from gate_report_format_main.lookup_fix_hints()
    # This replaces generic keyword templates with concrete, actionable steps.
    _m = _load_grfm()
    if _m is not None:
        try:
            gate_hints = _m.lookup_fix_hints(reason)
        except Exception:
            gate_hints = []
        if gate_hints:
            first = gate_hints[0]
            field_m = re.match(r"FIX \(([^)]+)\):", first)
            check_text = (
                f"`{field_m.group(1)}` フィールドを gate FIXヒントに従って確認"
                if field_m
                else "gate_report_format FIXヒントを確認する"
            )
            fix_parts = list(dict.fromkeys(shorten(h, 150) for h in gate_hints[:3]))
            return check_text, " / ".join(fix_parts[:2])

    # Phase 2: keyword-based fallback (for non-gate-report-format gates or unmatched reasons)
    lower = reason.lower()
    checks = []
    fixes = []

    if "fill_this" in lower:
        checks.append("提出前に対象YAML/本文へ `rg -n 'FILL_THIS'` を実行する")
        fixes.append("残存箇所を実値または具体的な no_* reason に置換する")
    if "verdict" in lower:
        checks.append("verdict が空/None/不正値でないこと、かつ binary_checks 記入後に決めていることを確認する")
        fixes.append("`/verdict-check` または `report_field_set.sh ... verdict PASS|FAIL` で再導出する")
    if "binary_checks" in lower or "bc:" in lower or "bc_" in lower:
        checks.append("全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する")
        fixes.append("各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする")
    if "lesson_candidate" in lower:
        checks.append("lesson_candidate が dict で、found=false なら no_lesson_reason が具体文になっていることを確認する")
        fixes.append("found/no_lesson_reason または title/detail を report_field_set.sh 経由で記入する")
    if "lessons_useful" in lower or "draft_lessons" in lower:
        checks.append("関連教訓ごとに lessons_useful の id/useful/reason が埋まっていることを確認する")
        fixes.append("UNKNOWN/null/FILL_THISを使わず、各教訓の有用性と理由を記入する")
    if "assumption_invalidation" in lower:
        checks.append("assumption_invalidation に detail と affected_cmds があることを確認する")
        fixes.append("`report_field_set.sh <report> assumption_invalidation found false` で dict 形式を保証する")
    if "files_modified" in lower:
        checks.append("files_modified が空/欠落/FILL_THISでないことを確認する")
        fixes.append("`report_field_set.sh <report> files_modified <path>` で変更ファイルを記入する")
    if "ac_version" in lower:
        checks.append("ac_version_read がHEADの短縮ハッシュと一致するか `git rev-parse --short HEAD` で確認する")
        fixes.append("`report_field_set.sh <report> ac_version_read $(git rev-parse --short HEAD)` で記入する")
    if "purpose_validation" in lower:
        checks.append("purpose_validation.fit が true/false で、purpose_gap が記入済みか確認する")
        fixes.append("`report_field_set.sh <report> purpose_validation fit true` で記入する")
    if "worker_id" in lower or "parent_cmd" in lower:
        checks.append("worker_id と parent_cmd がテンプレート生成値と一致するか確認する")
        fixes.append("`report_field_set.sh <report> worker_id <name>` / `report_field_set.sh <report> parent_cmd <cmd_id>` で記入する")
    if "missing" in lower or "欠落" in reason:
        checks.append("FAIL理由に出たフィールド名を報告YAML上で `rg -n '<field>' <report>` で検索する")
        fixes.append("欠落フィールドを `report_field_set.sh` 経由で追加する")
    if not checks:
        checks.append("`bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する")
    if not fixes:
        fixes.append("gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する")

    # Keep generated lines readable and deterministic.
    checks = list(dict.fromkeys(checks))[:2]
    fixes = list(dict.fromkeys(fixes))[:2]
    return " / ".join(checks), " / ".join(fixes)


def prevention_line(skill_name, reason, gate, count, last_fail):
    marker = marker_for(skill_name, reason)
    compact_reason = shorten(reason)
    gate_text = gate or "unknown_gate"
    check_text, fix_text = concrete_prevention_steps(reason)
    return (
        f"- {marker} 自動防止: gate={gate_text} のTop FAIL理由「{compact_reason}」"
        f"(count={count}, last={last_fail or 'unknown'})を避ける。確認: {check_text}。"
        f"修正: {fix_text}。"
    )


def existing_auto_section_insert_index(lines):
    for idx, line in enumerate(lines):
        if line.strip() != "### 自動防止ステップ":
            continue
        insert = idx + 1
        while insert < len(lines) and not lines[insert].startswith("#"):
            insert += 1
        return insert
    return None


def procedure_insertion_index(lines):
    heading_re = re.compile(r"^##\s+.*(手順|実行フロー|Workflow|Procedure|Steps|使い方|commit手順)")
    fallback_re = re.compile(r"^##\s+注意ポイント\s*$")
    for idx, line in enumerate(lines):
        if heading_re.search(line):
            insert = idx + 1
            while insert < len(lines) and lines[insert].strip() == "":
                insert += 1
            return insert
    for idx, line in enumerate(lines):
        if fallback_re.search(line):
            return idx
    return len(lines)


def apply_prevention_steps(skill_path, rows):
    text = skill_path.read_text(encoding="utf-8", errors="ignore")
    additions = []
    added_markers = set()
    for row in rows:
        marker = marker_for(row["skill"], row["reason"])
        if marker in text:
            continue
        additions.append(prevention_line(row["skill"], row["reason"], row["gate"], row["count"], row["last_fail"]))
        added_markers.add(marker)
    if not additions:
        return set()

    lines = text.splitlines()
    auto_idx = existing_auto_section_insert_index(lines)
    if auto_idx is None:
        block = ["### 自動防止ステップ", *additions, ""]
        idx = procedure_insertion_index(lines)
    else:
        block = additions
        idx = auto_idx
    new_lines = lines[:idx] + block + lines[idx:]
    new_text = "\n".join(new_lines).rstrip() + "\n"

    fd, tmp = tempfile.mkstemp(dir=str(skill_path.parent), prefix=".SKILL.", suffix=".tmp")
    os.close(fd)
    Path(tmp).write_text(new_text, encoding="utf-8")
    os.replace(tmp, skill_path)
    return added_markers


stats = defaultdict(lambda: {"counter": Counter(), "last": {}, "gate": {}, "path": ""})
latest_pass = {}
for entry in load_entries(log_file):
    if str(entry.get("used", True)).strip().lower() == "false":
        continue
    gate_name = str(entry.get("gate") or "").strip()
    skill = GATE_SKILL_MAP.get(gate_name) or str(entry.get("skill") or "").strip()
    if not skill:
        continue
    if skill_filter and skill != skill_filter:
        continue
    result = str(entry.get("result", "")).strip().upper()
    ts = str(entry.get("ts") or "").strip()
    if result == "PASS":
        pass_key = (skill, gate_name)
        if ts >= latest_pass.get(pass_key, ""):
            latest_pass[pass_key] = ts
        continue
    if result != "FAIL":
        continue
    reason = normalize_reason(entry.get("stumbling_points"))
    if not reason:
        continue
    stats[skill]["counter"][reason] += 1
    if ts >= stats[skill]["last"].get(reason, ""):
        stats[skill]["last"][reason] = ts
        stats[skill]["gate"][reason] = gate_name
    logged_path = str(entry.get("skill_path") or "").strip()
    if GATE_SKILL_MAP.get(gate_name):
        mapped_path = skill_file_for(skill, "")
        if mapped_path:
            stats[skill]["path"] = str(mapped_path)
    elif logged_path:
        stats[skill]["path"] = logged_path

print("skill | rank | fail_count | last_fail | gate | top_fail_reason")
apply_plan = defaultdict(list)
for skill in sorted(stats):
    top_rows = sorted(stats[skill]["counter"].items(), key=lambda kv: (-kv[1], kv[0]))[:top_n]
    for rank, (reason, count) in enumerate(top_rows, start=1):
        row = {
            "skill": skill,
            "rank": rank,
            "count": count,
            "last_fail": stats[skill]["last"].get(reason, ""),
            "gate": stats[skill]["gate"].get(reason, ""),
            "reason": reason,
        }
        print(
            f"{skill} | {rank} | {count} | {row['last_fail']} | {row['gate']} | {shorten(reason, 220)}"
        )
        apply_plan[skill].append(row)

if not apply_changes:
    raise SystemExit(0)

updated = 0
escalation_state = load_escalation_state(escalation_state_path)
cleared_code_fix = 0
for key, entry in escalation_state.get("patterns", {}).items():
    if not isinstance(entry, dict) or entry.get("classification") != "code_fix_required":
        continue
    skill = str(entry.get("skill") or "").strip()
    gate = str(entry.get("gate") or "").strip()
    last_fail = str(entry.get("last_fail") or "").strip()
    pass_ts = latest_pass.get((skill, gate), "")
    if not pass_resolves_fail(pass_ts, last_fail):
        continue
    entry.pop("classification", None)
    entry.pop("classification_reason", None)
    reset_escalation_counters(entry)
    entry["code_fix_cleared_at"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    entry["code_fix_cleared_by"] = "skill_auto_improve_pass_result"
    entry["code_fix_cleared_pass_ts"] = pass_ts
    cleared_code_fix += 1
    print(f"CLEARED_CODE_FIX: {skill} gate={gate or 'unknown_gate'} pass={pass_ts} last_fail={last_fail or 'unknown'}")
for skill, rows in apply_plan.items():
    path = skill_file_for(skill, stats[skill]["path"])
    if not path:
        print(f"SKIP: {skill} SKILL.md not found")
        continue
    changed_markers = apply_prevention_steps(path, rows)
    if changed_markers:
        updated += 1
        print(f"UPDATED: {path}")
    else:
        print(f"UNCHANGED: {path}")
    for row in rows:
        key = escalation_key(row)
        entry = escalation_state["patterns"].setdefault(key, {})
        if is_code_fix_cleared(entry, row.get("last_fail") or ""):
            # Keep the current CLEAR marker for this run, but ensure stale
            # notification counters cannot leak into a future recurrence.
            entry.update({
                "skill": row["skill"],
                "gate": row.get("gate") or entry.get("gate", ""),
                "reason": row["reason"],
                "last_fail": row.get("last_fail") or entry.get("last_fail", ""),
            })
            entry.pop("classification", None)
            entry.pop("classification_reason", None)
            print(
                f"SKIPPED_CLASSIFICATION_CODE_FIX_CLEARED: {row['skill']} rank={row['rank']} "
                f"gate={row.get('gate') or entry.get('gate') or 'unknown_gate'}"
            )
            continue
        if is_code_fix_cleared(entry):
            # A newer FAIL invalidates the prior CLEAR and starts a fresh
            # unchanged streak eligible for one new training task.
            for field in (
                "code_fix_cleared_at",
                "code_fix_cleared_by",
                "code_fix_cleared_pass_ts",
                "code_fix_cleared_note",
                "code_fix_cleared_recent50_fail",
                "code_fix_cleared_recent50_total",
            ):
                entry.pop(field, None)
            reset_escalation_counters(entry)
        pass_ts = latest_pass.get((row["skill"], row.get("gate") or ""), "")
        if pass_resolves_fail(pass_ts, row.get("last_fail") or ""):
            entry.update({
                "skill": row["skill"],
                "gate": row.get("gate") or "",
                "reason": row["reason"],
                "last_fail": row.get("last_fail") or "",
                "code_fix_cleared_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
                "code_fix_cleared_by": "skill_auto_improve_pass_result",
                "code_fix_cleared_pass_ts": pass_ts,
            })
            entry.pop("classification", None)
            entry.pop("classification_reason", None)
            print(
                f"SKIPPED_CLASSIFICATION_AFTER_PASS: {row['skill']} rank={row['rank']} "
                f"gate={row.get('gate') or 'unknown_gate'} pass={pass_ts} last_fail={row.get('last_fail') or 'unknown'}"
            )
            continue
        entry.update({
            "skill": row["skill"],
            "gate": row.get("gate") or "",
            "reason": row["reason"],
            "last_fail": row.get("last_fail") or "",
        })
        row_changed = marker_for(row["skill"], row["reason"]) in changed_markers
        if row_changed:
            entry["unchanged_streak"] = 0
        else:
            entry["unchanged_streak"] = int(entry.get("unchanged_streak", 0)) + 1
        cause, cause_reason = classify_fail_cause(row, row_changed, int(entry["unchanged_streak"]), entry)
        entry["classification"] = cause
        entry["classification_reason"] = cause_reason
        print(
            f"CLASSIFIED: {row['skill']} rank={row['rank']} classification={cause} "
            f"unchanged_streak={entry['unchanged_streak']} reason={cause_reason}"
        )
        if cause == "code_fix_required":
            request_code_fix(row, int(entry["unchanged_streak"]), entry)
            # Generate training task for non-code-bug escalation (SKILL.md unchanged)
            if "script/runtime failure" not in cause_reason:
                request_training_task(row, int(entry["unchanged_streak"]), entry)

save_escalation_state(escalation_state_path, escalation_state)
print(f"updated_skills={updated} cleared_code_fix={cleared_code_fix} generated_at={datetime.now().strftime('%Y-%m-%dT%H:%M:%S')}")
PY
