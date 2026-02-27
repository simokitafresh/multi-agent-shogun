#!/usr/bin/env bash
# ============================================================
# backfill_task_type.sh — gate_metrics.logのtask_type遡及補完
#
# Usage:
#   bash scripts/backfill_task_type.sh --dry-run   # 変更予定の一覧表示のみ
#   bash scripts/backfill_task_type.sh --apply      # 実際に更新(バックアップ自動作成)
#
# Data Sources (task_type推定):
#   1. logs/deploy_task.log    — subtask ID → task_type
#   2. queue/archive/reports/  — task_id → task_type
#   3. logs/ninja_monitor.log  — TASK-CLEAR subtask ID → task_type
#   4. queue/archive/cmds/     — cmd description keywords → task_type
#
# Model resolution:
#   - config/settings.yaml     — ninja→model mapping
#   - All 6 sources from model_analysis.sh — cmd→ninja mapping
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
DEPLOY_LOG="$SCRIPT_DIR/logs/deploy_task.log"
NINJA_MONITOR="$SCRIPT_DIR/logs/ninja_monitor.log"
TRACKING="$SCRIPT_DIR/logs/lesson_tracking.tsv"
ARCHIVE_DIR="$SCRIPT_DIR/queue/archive"
BACKUP_DIR="$SCRIPT_DIR/queue/backups"

# Argument parse
MODE=""
case "${1:-}" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    *)
        echo "Usage: $0 --dry-run | --apply" >&2
        exit 1
        ;;
esac

if [[ ! -f "$GATE_LOG" ]]; then
    echo "ERROR: gate_metrics.log not found: $GATE_LOG" >&2
    exit 1
fi

export GATE_LOG SETTINGS DEPLOY_LOG NINJA_MONITOR TRACKING ARCHIVE_DIR BACKUP_DIR MODE

python3 << 'PYEOF'
import os, sys, re, shutil
from collections import defaultdict
from datetime import datetime

GATE_LOG = os.environ["GATE_LOG"]
SETTINGS = os.environ["SETTINGS"]
DEPLOY_LOG = os.environ.get("DEPLOY_LOG", "")
NINJA_MONITOR = os.environ.get("NINJA_MONITOR", "")
TRACKING = os.environ.get("TRACKING", "")
ARCHIVE_DIR = os.environ.get("ARCHIVE_DIR", "")
BACKUP_DIR = os.environ.get("BACKUP_DIR", "")
MODE = os.environ["MODE"]

ALL_NINJAS = ["sasuke", "kirimaru", "hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru"]
ALL_NINJAS_SET = set(ALL_NINJAS)

# ─── ninja→model mapping from settings.yaml ───
def parse_ninja_model_map():
    nmap = {}
    if not os.path.isfile(SETTINGS):
        return nmap
    in_agents = False
    cur_ninja = ""
    cur_type = ""
    cur_model = ""
    with open(SETTINGS, "r") as f:
        for line in f:
            stripped = line.rstrip()
            if re.match(r"^\s*agents:", stripped):
                in_agents = True
                continue
            if in_agents and re.match(r"^[^\s]", stripped):
                in_agents = False
                continue
            if not in_agents:
                continue
            m = re.match(r"^    ([a-z]+):", stripped)
            if m:
                if cur_ninja:
                    nmap[cur_ninja] = _resolve_model(cur_type, cur_model)
                cur_ninja = m.group(1)
                cur_type = ""
                cur_model = ""
                continue
            if cur_ninja:
                tm = re.match(r"^\s+type:\s*(\S+)", stripped)
                if tm:
                    cur_type = tm.group(1)
                mm = re.match(r"^\s+model_name:\s*(\S+)", stripped)
                if mm:
                    cur_model = mm.group(1)
    if cur_ninja:
        nmap[cur_ninja] = _resolve_model(cur_type, cur_model)
    return nmap

def _resolve_model(ctype, model_name):
    if ctype == "codex":
        return "Codex"
    mn = model_name.lower()
    if "sonnet" in mn:
        return "Sonnet"
    if "haiku" in mn:
        return "Haiku"
    return "Opus"

ninja_model = parse_ninja_model_map()

# ─── Infer task_type from subtask ID ───
def infer_type_from_subtask(subtask_id):
    sid = subtask_id.lower()
    # New format: subtask_NNN_type_suffix
    m = re.search(r"subtask_\d+[a-z]?_?(recon|impl|implement|review|fix)", sid)
    if m:
        t = m.group(1)
        if t in ("impl", "implement", "fix"):
            return "implement"
        return t
    # Old format: subtask_NNNa_impl, subtask_NNNa (no type)
    if "_recon" in sid:
        return "recon"
    if "_impl" in sid or "_fix" in sid or "_implement" in sid:
        return "implement"
    if "_review" in sid:
        return "review"
    return ""

# ─── Source 1: deploy_task.log → cmd→task_types + cmd→ninjas ───
def parse_deploy_log():
    cmd_types = defaultdict(set)
    cmd_ninjas = defaultdict(set)
    if not DEPLOY_LOG or not os.path.isfile(DEPLOY_LOG):
        return cmd_types, cmd_ninjas
    with open(DEPLOY_LOG, "r") as f:
        for line in f:
            # subtask deployment: task=subtask_NNN_type_suffix
            m = re.search(r"task=(subtask_(\d+)\S*)", line)
            if m:
                subtask_id = m.group(1)
                cmd_num = m.group(2)
                cmd_id = "cmd_" + cmd_num
                tt = infer_type_from_subtask(subtask_id)
                if tt:
                    cmd_types[cmd_id].add(tt)
            # ninja deployment: [DEPLOY] {ninja}: deployment complete
            m = re.search(r"\[DEPLOY\] (\w+): deployment complete", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                # Find associated cmd from the line or nearby context
                cmd_m = re.search(r"type=(cmd_\d+|task_assigned)", line)
                ninja = m.group(1)
                # Also extract cmd from nearby subtask refs
                cmd_ref = re.search(r"cmd_(\d+)", line)
                if cmd_ref:
                    cmd_ninjas["cmd_" + cmd_ref.group(1)].add(ninja)

            # scout_gate lines: task_type=...
            m = re.search(r"scout_gate: PASS: task_type=(\w+)", line)
            if m:
                # These don't have cmd refs directly, skip
                pass
    return cmd_types, cmd_ninjas

# ─── Source 2: archive/reports → cmd→task_types + cmd→ninjas ───
def parse_archive_reports():
    cmd_types = defaultdict(set)
    cmd_ninjas = defaultdict(set)
    reports_dir = os.path.join(ARCHIVE_DIR, "reports")
    if not os.path.isdir(reports_dir):
        return cmd_types, cmd_ninjas
    for fname in os.listdir(reports_dir):
        if not fname.endswith(".yaml"):
            continue
        # Extract ninja name and cmd from filename
        nm = re.match(r"^([a-z]+)_report.*?(cmd_?(\d+))", fname)
        if nm and nm.group(1) in ALL_NINJAS_SET:
            ninja = nm.group(1)
            cmd_id = "cmd_" + nm.group(3)
            cmd_ninjas[cmd_id].add(ninja)
        # Parse task_id from file content
        fpath = os.path.join(reports_dir, fname)
        try:
            with open(fpath, "r") as f:
                for line in f:
                    m = re.match(r"task_id:\s*(subtask_\S+)", line.strip())
                    if m:
                        subtask_id = m.group(1)
                        cmd_m = re.search(r"subtask_(\d+)", subtask_id)
                        if cmd_m:
                            c_id = "cmd_" + cmd_m.group(1)
                            tt = infer_type_from_subtask(subtask_id)
                            if tt:
                                cmd_types[c_id].add(tt)
                            cmd_ninjas[c_id].add(ninja) if nm else None
        except Exception:
            continue
    # Also parse current reports
    current_reports = os.path.join(os.path.dirname(ARCHIVE_DIR), "reports")
    if os.path.isdir(current_reports):
        for fname in os.listdir(current_reports):
            if not fname.endswith(".yaml"):
                continue
            nm = re.match(r"^([a-z]+)_report.*?(cmd_?(\d+))", fname)
            if nm and nm.group(1) in ALL_NINJAS_SET:
                ninja = nm.group(1)
                cmd_id = "cmd_" + nm.group(3)
                cmd_ninjas[cmd_id].add(ninja)
            fpath = os.path.join(current_reports, fname)
            try:
                with open(fpath, "r") as f:
                    for line in f:
                        m = re.match(r"task_id:\s*(subtask_\S+)", line.strip())
                        if m:
                            subtask_id = m.group(1)
                            cmd_m = re.search(r"subtask_(\d+)", subtask_id)
                            if cmd_m:
                                c_id = "cmd_" + cmd_m.group(1)
                                tt = infer_type_from_subtask(subtask_id)
                                if tt:
                                    cmd_types[c_id].add(tt)
            except Exception:
                pass
    return cmd_types, cmd_ninjas

# ─── Source 3: ninja_monitor.log → cmd→task_types + cmd→ninjas ───
def parse_ninja_monitor():
    cmd_types = defaultdict(set)
    cmd_ninjas = defaultdict(set)
    if not NINJA_MONITOR or not os.path.isfile(NINJA_MONITOR):
        return cmd_types, cmd_ninjas
    with open(NINJA_MONITOR, "r") as f:
        for line in f:
            # AUTO-DONE: {ninja} ... parent_cmd=cmd_XXX
            m = re.search(r"AUTO-DONE: (\w+) .*parent_cmd=(cmd_\d+)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas[m.group(2)].add(m.group(1))
                continue
            # TASK-CLEAR: {ninja} ... was: subtask_XXX or cmd_XXX
            m = re.search(r"TASK-CLEAR: (\w+) .*was: (subtask_(\d+)\S*)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_id = "cmd_" + m.group(3)
                cmd_ninjas[cmd_id].add(m.group(1))
                tt = infer_type_from_subtask(m.group(2))
                if tt:
                    cmd_types[cmd_id].add(tt)
                continue
            m = re.search(r"TASK-CLEAR: (\w+) .*was: (cmd_(\d+))", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas[m.group(2)].add(m.group(1))
    return cmd_types, cmd_ninjas

# ─── Source 4: archive/cmds → cmd→task_types (keyword inference) ───
def parse_archive_cmds():
    cmd_types = defaultdict(set)
    cmd_ninjas = defaultdict(set)
    cmds_dir = os.path.join(ARCHIVE_DIR, "cmds")
    if not os.path.isdir(cmds_dir):
        return cmd_types, cmd_ninjas
    for fname in os.listdir(cmds_dir):
        if not fname.endswith(".yaml"):
            continue
        m = re.match(r"(cmd_(\d+))_", fname)
        if not m:
            continue
        cmd_id = m.group(1)
        fpath = os.path.join(cmds_dir, fname)
        try:
            with open(fpath, "r") as f:
                content = f.read()
        except Exception:
            continue
        # Extract ninja names mentioned in cmd
        for n in ALL_NINJAS:
            if n in content:
                cmd_ninjas[cmd_id].add(n)
        # Extract subtask IDs from content
        for sub_m in re.finditer(r"subtask_(\d+)\w*", content):
            sub_id = sub_m.group(0)
            tt = infer_type_from_subtask(sub_id)
            if tt:
                cmd_types[cmd_id].add(tt)
        # Keyword-based type inference from purpose/description
        content_lower = content.lower()
        # Only infer from keywords if no subtask-based type found yet
        if cmd_id not in cmd_types or not cmd_types[cmd_id]:
            types_found = set()
            # Recon keywords
            if re.search(r"偵察|調査|recon|分析|比較|検証|スパイク|spike|確認|evaluate|assess", content_lower):
                types_found.add("recon")
            # Review keywords
            if re.search(r"レビュー|review|コードレビュー|code.?review|品質チェック|監査", content_lower):
                types_found.add("review")
            # Implement keywords
            if re.search(r"実装|修正|追加|impl|fix|新規作成|create|build|develop|改修|リファクタ", content_lower):
                types_found.add("implement")
            if types_found:
                cmd_types[cmd_id] = types_found
    return cmd_types, cmd_ninjas

# ─── Source 5: lesson_tracking.tsv → cmd→ninjas ───
def parse_tracking():
    cmd_ninjas = defaultdict(set)
    if not TRACKING or not os.path.isfile(TRACKING):
        return cmd_ninjas
    with open(TRACKING, "r") as f:
        for i, line in enumerate(f):
            if i == 0:
                continue
            parts = line.strip().split("\t")
            if len(parts) < 3:
                continue
            cmd_id = parts[1]
            ninjas = [n.strip() for n in parts[2].split(",") if n.strip()]
            for n in ninjas:
                if n in ALL_NINJAS_SET:
                    cmd_ninjas[cmd_id].add(n)
    return cmd_ninjas

# ─── Source 6: archive inbox (karo) → cmd→ninjas ───
def parse_archive_inbox():
    cmd_ninjas = defaultdict(set)
    if not ARCHIVE_DIR or not os.path.isdir(ARCHIVE_DIR):
        return cmd_ninjas
    try:
        import yaml
    except ImportError:
        return cmd_ninjas
    for fname in os.listdir(ARCHIVE_DIR):
        if not fname.startswith("inbox_karo") or not fname.endswith(".yaml"):
            continue
        fpath = os.path.join(ARCHIVE_DIR, fname)
        try:
            with open(fpath, "r") as f:
                data = yaml.safe_load(f)
            if not data or "messages" not in data:
                continue
            for msg in data["messages"]:
                frm = msg.get("from", "")
                content = msg.get("content", "")
                if frm not in ALL_NINJAS_SET:
                    continue
                for c in re.findall(r"cmd_?(\d+)", content):
                    cmd_ninjas["cmd_" + c].add(frm)
        except Exception:
            # L098: YAML parse fallback for mixed format
            try:
                with open(fpath, "r") as f:
                    raw = f.read()
                # Try parsing messages: block
                msg_block = re.search(r"messages:\s*\n(.*)", raw, re.DOTALL)
                if msg_block:
                    for m in re.finditer(r"from:\s*(\w+).*?content:\s*['\"]?(.*?)['\"]?\s*\n", raw, re.DOTALL):
                        frm = m.group(1)
                        content = m.group(2)
                        if frm in ALL_NINJAS_SET:
                            for c in re.findall(r"cmd_?(\d+)", content):
                                cmd_ninjas["cmd_" + c].add(frm)
            except Exception:
                continue
    # Also parse ninja-specific inbox archives
    for fname in os.listdir(ARCHIVE_DIR):
        if not fname.startswith("inbox_") or fname.startswith("inbox_karo") or fname.startswith("inbox_shogun"):
            continue
        if not fname.endswith(".yaml"):
            continue
        nm = re.match(r"inbox_(\w+)_\d+\.yaml", fname)
        if not nm:
            continue
        ninja = nm.group(1)
        if ninja not in ALL_NINJAS_SET:
            continue
        fpath = os.path.join(ARCHIVE_DIR, fname)
        try:
            with open(fpath, "r") as f:
                data = yaml.safe_load(f)
            if not data or "messages" not in data:
                continue
            for msg in data["messages"]:
                content = msg.get("content", "")
                for c in re.findall(r"cmd_?(\d+)", content):
                    cmd_ninjas["cmd_" + c].add(ninja)
        except Exception:
            continue
    return cmd_ninjas

# ─── Collect ninja names from BLOCK detail ───
def extract_ninjas_from_detail(detail):
    ninjas = set()
    if not detail or detail == "all_gates_passed":
        return ninjas
    tokens = detail.split("|")
    for tok in tokens:
        m = re.match(r"^([a-z]+):", tok)
        if m and m.group(1) in ALL_NINJAS_SET:
            ninjas.add(m.group(1))
    return ninjas

# ─── Main ───
print("=" * 60)
print("  backfill_task_type — gate_metrics.log task_type遡及補完")
print("=" * 60)
print()

# Collect all sources
print("Collecting data from sources...")
deploy_types, deploy_ninjas = parse_deploy_log()
print(f"  deploy_task.log: {len(deploy_types)} cmds with type info")

report_types, report_ninjas = parse_archive_reports()
print(f"  archive/reports: {len(report_types)} cmds with type info")

monitor_types, monitor_ninjas = parse_ninja_monitor()
print(f"  ninja_monitor.log: {len(monitor_types)} cmds with type info")

archive_types, archive_cmd_ninjas = parse_archive_cmds()
print(f"  archive/cmds: {len(archive_types)} cmds with type info")

tracking_ninjas = parse_tracking()
print(f"  lesson_tracking.tsv: {len(tracking_ninjas)} cmds with ninja info")

inbox_ninjas = parse_archive_inbox()
print(f"  archive/inbox: {len(inbox_ninjas)} cmds with ninja info")

# Merge all type sources (priority: deploy > report > monitor > archive_cmd)
cmd_all_types = defaultdict(set)
for src in (deploy_types, report_types, monitor_types, archive_types):
    for cmd_id, types in src.items():
        cmd_all_types[cmd_id].update(types)

# Merge all ninja sources
cmd_all_ninjas = defaultdict(set)
for src in (deploy_ninjas, report_ninjas, monitor_ninjas, archive_cmd_ninjas, tracking_ninjas, inbox_ninjas):
    for cmd_id, ninjas in src.items():
        cmd_all_ninjas[cmd_id].update(ninjas)

print(f"\nTotal: {len(cmd_all_types)} cmds with type info, {len(cmd_all_ninjas)} cmds with ninja info")
print()

# Read gate_metrics.log
with open(GATE_LOG, "r") as f:
    lines = f.readlines()

# Process each line
changes = []
unchanged = 0
already_has = 0
total = 0
for i, line in enumerate(lines):
    raw = line.rstrip("\n\r")
    if not raw:
        continue
    total += 1
    parts = raw.split("\t")
    if len(parts) < 4:
        continue

    cmd_id = parts[1]
    detail = parts[3]

    # Skip test entries
    if cmd_id.lower().startswith("cmd_test"):
        unchanged += 1
        continue

    # Already has 6 fields (task_type + models)
    if len(parts) >= 6 and parts[4].strip():
        already_has += 1
        continue

    # Need backfill
    # Resolve task_type
    types = cmd_all_types.get(cmd_id, set())
    if types:
        task_type_csv = ",".join(sorted(types))
    else:
        task_type_csv = "unknown"

    # Resolve models from ninjas
    # First from detail column
    detail_ninjas = extract_ninjas_from_detail(detail)
    all_ninjas = cmd_all_ninjas.get(cmd_id, set())
    all_ninjas.update(detail_ninjas)

    models = set()
    for n in all_ninjas:
        if n in ninja_model:
            models.add(ninja_model[n])

    if models:
        models_csv = ",".join(sorted(models))
    else:
        models_csv = "unknown"

    new_line = "\t".join(parts[:4]) + "\t" + task_type_csv + "\t" + models_csv

    if new_line != raw:
        changes.append({
            "line_num": i,
            "cmd_id": cmd_id,
            "old_type": parts[4] if len(parts) > 4 else "(none)",
            "new_type": task_type_csv,
            "old_model": parts[5] if len(parts) > 5 else "(none)",
            "new_model": models_csv,
            "new_line": new_line,
        })
    else:
        unchanged += 1

# Summary
backfilled_known = sum(1 for c in changes if c["new_type"] != "unknown")
backfilled_unknown = sum(1 for c in changes if c["new_type"] == "unknown")

print("─" * 60)
print(f"Total entries: {total}")
print(f"Already has type: {already_has}")
print(f"Backfilled (type found): {backfilled_known}")
print(f"Backfilled (still unknown): {backfilled_unknown}")
print(f"Unchanged: {unchanged}")
print("─" * 60)

# Show changes
if changes:
    print()
    print("Changes:")
    type_resolved = 0
    model_resolved = 0
    for c in changes:
        marker = "+" if c["new_type"] != "unknown" else " "
        print(f"  {marker} {c['cmd_id']:12s} type={c['new_type']:<25s} model={c['new_model']}")
        if c["new_type"] != "unknown":
            type_resolved += 1
        if c["new_model"] != "unknown":
            model_resolved += 1
    print()
    print(f"Type resolved: {type_resolved}/{len(changes)} ({type_resolved/len(changes)*100:.1f}%)")
    print(f"Model resolved: {model_resolved}/{len(changes)} ({model_resolved/len(changes)*100:.1f}%)")

    # Post-backfill stats (deduped)
    # Simulate dedup to calculate unknown rate
    all_lines = []
    change_map = {c["line_num"]: c["new_line"] for c in changes}
    for i, line in enumerate(lines):
        raw = line.rstrip("\n\r")
        if not raw:
            continue
        if i in change_map:
            all_lines.append(change_map[i])
        else:
            all_lines.append(raw)

    # Dedup: last result per cmd
    cmd_latest = {}
    for l in all_lines:
        parts = l.split("\t")
        if len(parts) < 4:
            continue
        cmd_id = parts[1]
        if cmd_id.lower().startswith("cmd_test"):
            continue
        cmd_latest[cmd_id] = parts

    total_deduped = len(cmd_latest)
    unknown_deduped = 0
    for cmd_id, parts in cmd_latest.items():
        task_type = parts[4] if len(parts) > 4 else ""
        if not task_type or task_type == "unknown":
            unknown_deduped += 1

    unknown_pct = (unknown_deduped / total_deduped * 100) if total_deduped > 0 else 0.0
    print()
    print(f"Post-backfill unknown rate (deduped): {unknown_deduped}/{total_deduped} ({unknown_pct:.1f}%)")
else:
    print("\nNo changes needed.")

# Apply
if MODE == "apply" and changes:
    # Create backup
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, f"gate_metrics_{timestamp}.log.bak")
    shutil.copy2(GATE_LOG, backup_path)
    print(f"\nBackup created: {backup_path}")

    # Apply changes
    change_map = {c["line_num"]: c["new_line"] for c in changes}
    new_lines = []
    for i, line in enumerate(lines):
        if i in change_map:
            new_lines.append(change_map[i] + "\n")
        else:
            new_lines.append(line)

    with open(GATE_LOG, "w") as f:
        f.writelines(new_lines)

    print(f"Applied {len(changes)} changes to {GATE_LOG}")
elif MODE == "dry-run":
    print("\n[DRY-RUN] No changes applied.")
PYEOF
