#!/usr/bin/env bash
# semantic-links: [[セマンティック因果自動化]], [[セマンティック辞書構想]], [[因果辺トラバース統合パイプライン(Obsidian×セマンティック)]]
# semantic_map_generate.sh — Generate context/semantic-map.md from semantic index SSOT.
# Usage:
#   bash scripts/semantic_map_generate.sh
#   bash scripts/semantic_map_generate.sh --body-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$repo_root/docs/semantic-index/index.md}"
map_path="${SEMANTIC_MAP_PATH:-$repo_root/context/semantic-map.md}"
body_only=false

if [ "${1:-}" = "--body-only" ]; then
    body_only=true
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '2,6p' "$0"
    exit 0
elif [ "$#" -gt 0 ]; then
    echo "ERROR: unknown argument: $1" >&2
    exit 2
fi

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

# Share semantic_index_update.sh's lock: map generation also mutates the
# index during intake/backlink injection, so a separate writer lock permits
# a reader to persist a partially written prefix.
lock_path="${SEMANTIC_INDEX_LOCK:-${index_path}.lock}"
if [ "${SEMANTIC_INDEX_LOCK_HELD:-0}" != "1" ]; then
    exec 9>"$lock_path"
    flock -w 10 9 || { echo "ERROR: lock timeout: $lock_path" >&2; exit 1; }
fi

python3 - "$index_path" "$map_path" "$body_only" "$repo_root" <<'PY'
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

index_path = Path(sys.argv[1])
map_path = Path(sys.argv[2])
body_only = sys.argv[3] == "true"
repo_root = Path(sys.argv[4]) if len(sys.argv) > 4 else index_path.parent.parent.parent

def atomic_write_text(path, text):
    """Publish complete text only; readers must never observe a prefix."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path == index_path and path.exists():
        current = path.read_text(encoding="utf-8")
        current_ids = re.findall(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|$", current)
        candidate_ids = re.findall(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|$", text)
        if not candidate_ids or len(candidate_ids) < len(current_ids):
            raise RuntimeError(
                f"semantic index monotonicity violation: concepts {len(current_ids)} -> {len(candidate_ids)}"
            )
        if len(candidate_ids) != len(set(candidate_ids)):
            raise RuntimeError("semantic index invalid: duplicate concept ids")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass

def norm(value):
    return re.sub(r"\s+", " ", str(value).casefold()).strip()

def shell_quote_backtick(value):
    return "`" + str(value).replace("`", "'") + "`"

def split_concept_parts(text):
    return re.split(r"(?m)(?=^## )", text)

def parse_index_blocks(text):
    blocks = []
    cursor = 0
    for part in split_concept_parts(text):
        start = cursor
        cursor += len(part)
        if not part.startswith("## "):
            continue
        heading = part.splitlines()[0][3:].strip()
        concept_id = heading.split(" — ", 1)[0].strip()
        attrs = {}
        resources = []
        for raw in part.splitlines():
            row = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$", raw.strip())
            if not row:
                continue
            left, right = row.group(1).strip(), row.group(2).strip()
            if left in {"id", "label", "aliases", "related_concepts"}:
                attrs[left] = right
            elif left and right and left not in {"属性", "------", "種別"}:
                resources.append((left, right))
        blocks.append({
            "start": start,
            "end": cursor,
            "block": part,
            "id": attrs.get("id") or concept_id,
            "heading": heading,
            "label": attrs.get("label") or heading.split(" — ", 1)[-1].strip(),
            "aliases": [a.strip() for a in attrs.get("aliases", "").split(",") if a.strip()],
            "resources": resources,
        })
    return blocks

def concept_terms_from_blocks(blocks):
    terms = set()
    for block in blocks:
        for value in [block["id"], block["label"], *block["aliases"]]:
            value_n = norm(value)
            if value_n:
                terms.add(value_n)
    return terms

def resource_values_from_blocks(blocks):
    values = set()
    for block in blocks:
        for _kind, value in block["resources"]:
            stripped = value.strip()
            match = re.match(r"^`([^`]+)`", stripped)
            cleaned = match.group(1) if match else stripped.strip("`")
            if cleaned:
                values.add(cleaned)
    return values

def append_row_to_block(block, row):
    if row in block:
        return block, False
    return block.rstrip("\n") + "\n" + row + "\n\n", True

def update_blocks_by_id(text, rows_by_id):
    if not rows_by_id:
        return text, False
    blocks = parse_index_blocks(text)
    updated = text
    changed = False
    for block in sorted(blocks, key=lambda item: item["start"], reverse=True):
        rows = rows_by_id.get(block["id"])
        if not rows:
            continue
        new_block = block["block"]
        block_changed = False
        for row in rows:
            new_block, row_changed = append_row_to_block(new_block, row)
            block_changed = block_changed or row_changed
        if block_changed:
            updated = updated[: block["start"]] + new_block + updated[block["end"] :]
            changed = True
    return updated, changed

def format_related_concepts(values):
    cleaned = []
    seen = set()
    for value in values:
        item = str(value).strip().strip("`")
        if not item or item in seen:
            continue
        seen.add(item)
        cleaned.append(item)
    return ", ".join(cleaned)

def parse_related_concept_entry(value):
    item = str(value).strip().strip("`")
    if not item:
        return "", item, "related"
    relation_type = "related"
    match = re.match(r"^([A-Za-z0-9_-]+)\s*\((.*?)\)$", item)
    if match:
        for attr in match.group(2).split(";"):
            key, sep, attr_value = attr.partition("=")
            if sep and key.strip() == "relation_type" and attr_value.strip():
                relation_type = attr_value.strip()
        return match.group(1).strip(), item, relation_type
    return item, item, relation_type

def parse_related_concepts_cell(value):
    parsed = []
    for raw_item in str(value or "").split(","):
        concept_id, display, relation_type = parse_related_concept_entry(raw_item)
        if concept_id:
            parsed.append({"id": concept_id, "display": display, "relation_type": relation_type})
    return parsed

def set_related_concepts_row(block_text, related_ids):
    row = f"| related_concepts | {format_related_concepts(related_ids)} |"
    if re.search(r"(?m)^\|\s*related_concepts\s*\|", block_text):
        return re.sub(r"(?m)^\|\s*related_concepts\s*\|.*?\|$", row, block_text, count=1)
    lines = block_text.splitlines()
    insert_at = None
    for i, line in enumerate(lines):
        if re.match(r"^\|\s*(aliases|skills|related_lessons)\s*\|", line.strip()):
            insert_at = i + 1
    if insert_at is None:
        for i, line in enumerate(lines):
            if line.strip() == "|------|---|":
                insert_at = i + 1
                break
    if insert_at is None:
        return block_text.rstrip("\n") + "\n" + row + "\n"
    lines.insert(insert_at, row)
    return "\n".join(lines) + ("\n" if block_text.endswith("\n") else "")

def ensure_bidirectional_related_concepts(text):
    blocks = parse_index_blocks(text)
    by_id = {block["id"]: block for block in blocks}
    related_by_id = {}
    for block in blocks:
        rel = []
        for raw in block["block"].splitlines():
            row = re.match(r"^\|\s*related_concepts\s*\|\s*(.*?)\s*\|$", raw.strip())
            if row:
                rel = parse_related_concepts_cell(row.group(1))
                break
        related_by_id[block["id"]] = rel

    additions = {block_id: [] for block_id in by_id}
    for source_id, related_ids in related_by_id.items():
        for related in related_ids:
            if related.get("relation_type") == "混同注意":
                continue
            target_id = related["id"]
            if target_id not in by_id:
                continue
            target_related_ids = {item["id"] for item in related_by_id.get(target_id, [])}
            if source_id not in target_related_ids:
                additions[target_id].append(source_id)

    additions = {block_id: values for block_id, values in additions.items() if values}
    if not additions:
        return text, 0

    updated = text
    for block in sorted(blocks, key=lambda item: item["start"], reverse=True):
        add = additions.get(block["id"])
        if not add:
            continue
        new_related = [*[item["display"] for item in related_by_id.get(block["id"], [])], *add]
        new_block = set_related_concepts_row(block["block"], new_related)
        updated = updated[: block["start"]] + new_block + updated[block["end"] :]
    return updated, sum(len(values) for values in additions.values())

def parse_projects_config(repo_root):
    config_path = Path(os.environ.get("SEMANTIC_PROJECTS_CONFIG", str(repo_root / "config" / "projects.yaml")))
    if not config_path.exists():
        return []
    try:
        import yaml
        data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
        rows = data.get("projects") or []
        return [row for row in rows if isinstance(row, dict) and row.get("id")]
    except Exception:
        projects = []
        current = None
        for raw in config_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^\s*-\s+id:\s*", raw):
                if current:
                    projects.append(current)
                current = {"id": raw.split(":", 1)[1].strip().strip("'\"")}
            elif current and re.match(r"^\s+[a-zA-Z_][a-zA-Z0-9_]*:\s*", raw):
                key, value = raw.strip().split(":", 1)
                current[key] = value.strip().strip("'\"")
        if current:
            projects.append(current)
        return projects

def concept_id_for_project(project_id):
    return "project_" + re.sub(r"[^a-zA-Z0-9_]+", "_", project_id).strip("_").lower()

def yaml_scalar(value):
    return str(value or "").replace("|", "/").strip()

def project_concept_block(project):
    project_id = yaml_scalar(project.get("id"))
    concept_id = concept_id_for_project(project_id)
    label = yaml_scalar(project.get("name") or project_id)
    aliases = [project_id, label, f"{project_id} project", f"{label} PJ"]
    aliases = list(dict.fromkeys(a for a in aliases if a))
    rows = [
        f"## {concept_id} — {label}",
        "",
        "| 属性 | 値 |",
        "|------|---|",
        f"| id | {concept_id} |",
        f"| label | {label} |",
        f"| aliases | {', '.join(aliases)} |",
        "| related_concepts | external_project_registry |",
        "",
        "| 種別 | パス/参照 |",
        "|------|----------|",
    ]
    project_yaml = Path("projects") / f"{project_id}.yaml"
    if (repo_root / project_yaml).exists():
        rows.append(f"| file | `{project_yaml.as_posix()}` |")
    context_file = yaml_scalar(project.get("context_file"))
    if context_file:
        rows.append(f"| file | `{context_file}` |")
    repo = yaml_scalar(project.get("repo"))
    if repo:
        rows.append(f"| url | `{repo}` |")
    rows.append("| cmd | `cmd_3056` auto project registry intake |")
    return "\n".join(rows) + "\n\n"

def ensure_project_concepts(text):
    blocks = parse_index_blocks(text)
    known_terms = concept_terms_from_blocks(blocks)
    known_resources = resource_values_from_blocks(blocks)
    additions = []
    for project in parse_projects_config(repo_root):
        project_id = yaml_scalar(project.get("id"))
        label = yaml_scalar(project.get("name") or project_id)
        if not project_id:
            continue
        project_yaml = f"projects/{project_id}.yaml"
        context_file = yaml_scalar(project.get("context_file"))
        if (
            norm(project_id) in known_terms
            or norm(label) in known_terms
            or project_yaml in known_resources
            or (context_file and context_file in known_resources)
        ):
            continue
        additions.append(project_concept_block(project))
    if not additions:
        return text, 0
    text = text.rstrip() + "\n\n" + "".join(additions)
    return text, len(additions)

def run_git_lines(args, timeout_sec=3):
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout_sec,
            check=False,
        )
    except Exception:
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]

def new_file_candidates():
    env_list = os.environ.get("SEMANTIC_NEW_FILE_LIST", "").strip()
    if env_list:
        return [
            path
            for line in re.split(r"[\n,]", env_list)
            if (path := line.strip()) and not is_ignored_new_file_candidate(path)
        ]

    # TTLキャッシュ: git ls-files --othersはWSL2 NTFSで~3s。30s以内は再実行しない
    _cache_ttl = 30
    _cache_file = Path("/tmp") / f"smg_new_files_{repo_root.name}.cache"
    try:
        if time.time() - _cache_file.stat().st_mtime < _cache_ttl:
            cached = _cache_file.read_text(encoding="utf-8").splitlines()
            return [p for p in cached if p]
    except OSError:
        pass

    files = []
    files.extend(run_git_lines(["diff", "--name-only", "--diff-filter=A", "--cached"]))
    files.extend(run_git_lines(["ls-files", "--others", "--exclude-standard"], timeout_sec=2))
    seen = set()
    out = []
    for path in files:
        if path in seen:
            continue
        seen.add(path)
        if is_ignored_new_file_candidate(path):
            continue
        if path.startswith((".git/", "queue/", "logs/", "tmp/")):
            continue
        out.append(path)
    out = out[:30]

    # キャッシュ保存(失敗は非致命的)
    try:
        _cache_file.write_text("\n".join(out), encoding="utf-8")
    except OSError:
        pass

    return out

def is_ignored_new_file_candidate(path):
    name = Path(path).name
    return (
        re.match(r"^\.[^/]+_worktrees/", path) is not None
        # 2026-09-02 D0: dotfile/dot dir(.claude/.githooks/.gitattributes/.tmp-*receipt)は semantic index 対象外。
        # 14 件の INSIGHT_REPEAT 中 8 件がこれらの偽陽性で毎 run 再通知されていた(負の複利)
        or path.startswith(".")
        or path.startswith("tests/unit/_tmp_")
        or "/_tmp_" in path
        or name.startswith("_tmp_")
    )

def queue_new_file_insights(text):
    insight_script = Path(os.environ.get("SEMANTIC_INSIGHT_WRITE", str(repo_root / "scripts" / "insight_write.sh")))
    if not insight_script.exists():
        return 0
    known_resources = resource_values_from_blocks(parse_index_blocks(text))
    queued = 0
    for rel_path in new_file_candidates():
        if rel_path in known_resources:
            continue
        if not (repo_root / rel_path).exists():
            continue
        message = (
            f"semantic_map_generate新規ファイル候補: `{rel_path}` は "
            "semantic index未登録。既存概念へのfile追加または新概念定義を検討せよ"
        )
        result = subprocess.run(
            ["bash", str(insight_script), message, "low", "semantic_map_generate:new_file"],
            cwd=repo_root,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            queued += 1
    return queued

def cmd_history_candidates():
    env_paths = os.environ.get("SEMANTIC_CMD_HISTORY_FILES", "").strip()
    if env_paths:
        paths = [Path(item) for item in env_paths.split(os.pathsep) if item]
    else:
        paths = [
            repo_root / "queue" / "shogun_to_karo.yaml",
            repo_root / "context" / "senkyoku-log.md",
            repo_root / "context" / "cmd-chronicle.md",
        ]
        paths.extend(sorted((repo_root / "archive" / "cmd-chronicle").glob("*.md")) if (repo_root / "archive" / "cmd-chronicle").exists() else [])
    candidates = {}
    block = None
    for path in paths:
        if not path.exists():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception:
            continue
        for line in lines:
            ids = re.findall(r"\bcmd_[A-Za-z0-9_:-]+\b", line)
            if re.match(r"^\s*-\s+id:\s*cmd_", line) and ids:
                if block and block["id"]:
                    candidates.setdefault(block["id"], block)
                block = {"id": ids[0], "text": [line], "status": ""}
                continue
            if block is not None:
                block["text"].append(line)
                if re.match(r"^\s*status:\s*", line):
                    block["status"] = line.split(":", 1)[1].strip().strip("'\"")
                if re.match(r"^\s*-\s+id:\s*", line):
                    if block and block["id"]:
                        candidates.setdefault(block["id"], block)
                    block = None
            else:
                for cmd_id in ids:
                    candidates.setdefault(cmd_id, {"id": cmd_id, "text": [line], "status": "completed"})
        if block and block["id"]:
            candidates.setdefault(block["id"], block)
            block = None
    rows = []
    for item in candidates.values():
        status = norm(item.get("status", ""))
        text = " ".join(item.get("text") or [])
        if status and status not in {"completed", "done", "clear", "cleared"}:
            continue
        rows.append({"id": item["id"], "text": text})
    return rows

def score_cmd_for_concept(block, cmd):
    terms = [block["id"], block["label"], *block["aliases"]]
    haystack = norm(cmd["text"])
    score = 0
    for term in terms:
        term_n = norm(term)
        if not term_n:
            continue
        if term_n in haystack:
            score += 10 + min(len(term_n), 30)
        for token in re.findall(r"[a-zA-Z_][a-zA-Z0-9_]{2,}|[\u30A0-\u30FF\u4E00-\u9FFF]{2,}", term):
            if norm(token) in haystack:
                score += 2
    for _kind, value in block["resources"]:
        cleaned = value.strip("`")
        if cleaned and norm(cleaned) in haystack:
            score += 40
    return score

def backfill_zero_cmd_concepts(text):
    blocks = parse_index_blocks(text)
    zero_cmd_blocks = [
        block for block in blocks
        if not re.search(r"^\|\s*cmd\s*\|", block["block"], flags=re.M)
    ]
    if not zero_cmd_blocks:
        return text, 0
    candidates = cmd_history_candidates()
    if not candidates:
        return text, 0
    rows_by_id = {}
    fallback = next((cmd for cmd in reversed(candidates) if "semantic" in norm(cmd["text"]) or "セマンティック" in cmd["text"]), candidates[-1])
    for block in zero_cmd_blocks:
        best = None
        best_score = 0
        for cmd in candidates:
            score = score_cmd_for_concept(block, cmd)
            if score > best_score:
                best = cmd
                best_score = score
        chosen = best if best_score > 0 else fallback
        summary = re.sub(r"\s+", " ", chosen["text"]).strip()
        summary = summary[:100] if summary else "semantic cmd backfill"
        rows_by_id.setdefault(block["id"], []).append(
            f"| cmd | {shell_quote_backtick(chosen['id'])} backfill — {summary} |"
        )
    updated, changed = update_blocks_by_id(text, rows_by_id)
    return updated, sum(len(v) for v in rows_by_id.values()) if changed else 0

def auto_intake_semantic_index():
    text = index_path.read_text(encoding="utf-8")
    original_text = text
    text, project_count = ensure_project_concepts(text)
    text, backfill_count = backfill_zero_cmd_concepts(text)
    text, bidirectional_count = ensure_bidirectional_related_concepts(text)
    if text != original_text:
        atomic_write_text(index_path, text)
    insight_count = queue_new_file_insights(text)
    if project_count:
        print(f"project concepts auto-created: {project_count}")
    if backfill_count:
        print(f"cmd backfill rows added: {backfill_count}")
    if bidirectional_count:
        print(f"related_concepts bidirectional links added: {bidirectional_count}")
    if insight_count:
        print(f"new file semantic insights queued: {insight_count}")

if not body_only:
    auto_intake_semantic_index()

def parse_markdown_lesson_origins(text, scope):
    origins = {}
    current_id = None
    source_cmd = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        heading = re.match(r"^###\s+(L\w+):", line)
        if heading:
            if current_id and source_cmd:
                origins.setdefault(f"{scope}:{current_id}", f"[[{source_cmd}]]")
            current_id = heading.group(1)
            source_cmd = None
            continue
        if not current_id:
            continue
        origin = re.match(r"^-\s+\*\*origin\*\*:\s*(.+)", line)
        if origin:
            val = origin.group(1).strip().strip("'\"")
            if "[[" in val:
                origins[f"{scope}:{current_id}"] = val
            current_id = None
            source_cmd = None
            continue
        source = re.match(r"^-\s+\*\*(?:出典|source|source_cmd)\*\*:\s*(.+)", line)
        if source:
            source_cmd = source.group(1).strip().strip("'\"")
    if current_id and source_cmd:
        origins.setdefault(f"{scope}:{current_id}", f"[[{source_cmd}]]")
    return origins

def load_task_lesson_origins(repo_root):
    """Local infra and configured external project lesson SSOTs, qualified by source."""
    origins = {}
    lessons_md = repo_root / "tasks" / "lessons.md"
    try:
        origins.update(parse_markdown_lesson_origins(lessons_md.read_text(encoding="utf-8"), "infra"))
    except Exception:
        pass
    config_path = repo_root / "config" / "projects.yaml"
    try:
        config_text = config_path.read_text(encoding="utf-8")
    except Exception:
        config_text = ""
    for match in re.finditer(r"(?ms)^\s*- id:\s*([^\s#]+).*?^\s+path:\s*[\"']?([^\n\"']+)", config_text):
        scope, project_path = match.group(1).strip(), Path(match.group(2).strip())
        external_lessons = project_path / "tasks" / "lessons.md"
        try:
            origins.update(parse_markdown_lesson_origins(external_lessons.read_text(encoding="utf-8"), scope))
        except Exception:
            continue
    return origins

def git_head_text(path):
    rel = path.relative_to(repo_root).as_posix()
    try:
        result = subprocess.run(
            ["git", "show", f"HEAD:{rel}"],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout

def load_project_lesson_origins(repo_root):
    """projects/*/lessons*.yaml（archive除く）からlesson_id→originマップを作成。
    共有worktreeの未commit派生YAMLは並行忍者の一時状態で揺れるため、既定ではHEADを読む。
    """
    origins = {}
    use_worktree = os.environ.get("SEMANTIC_LESSON_ORIGIN_SOURCE") == "worktree"
    pattern = str(repo_root / "projects" / "*" / "lessons*.yaml")
    for yaml_path in sorted(glob.glob(pattern)):
        yaml_path = Path(yaml_path)
        if "archive" in yaml_path.name:
            continue
        if use_worktree:
            try:
                text = yaml_path.read_text(encoding="utf-8")
            except Exception:
                continue
        else:
            text = git_head_text(yaml_path)
            if text is None:
                try:
                    text = yaml_path.read_text(encoding="utf-8")
                except Exception:
                    continue
        current_id = None
        scope = yaml_path.parent.name
        for raw_line in text.splitlines():
            line = raw_line.strip()
            if line.startswith("- id:"):
                current_id = line[len("- id:"):].strip()
            elif line.startswith("origin:") and current_id:
                val = line[len("origin:"):].strip().strip("'\"")
                if "[[" in val:
                    origins[f"{scope}:{current_id}"] = val
                current_id = None
    return origins

def load_lesson_origins(repo_root):
    origins = load_task_lesson_origins(repo_root)
    for lid, origin in load_project_lesson_origins(repo_root).items():
        origins.setdefault(lid, origin)
    return origins

def resolve_lesson_origin(lesson_ref, origins):
    if ":" in lesson_ref:
        return origins.get(lesson_ref), False
    matches = [origin for ref, origin in origins.items() if ref.rsplit(":", 1)[-1] == lesson_ref]
    if len(matches) == 1:
        return matches[0], False
    return None, len(matches) > 1

def inject_causal_chains(index_path, origins):
    """index.mdの各概念のlesson参照からoriginを取得しcausal_chainを注入（冪等）"""
    if not origins:
        return 0
    text = index_path.read_text(encoding="utf-8")
    parts = re.split(r"(?m)(?=^## )", text)
    new_parts = []
    injected = 0
    for part in parts:
        if not part.startswith("## "):
            new_parts.append(part)
            continue
        # 既存causal_chainを削除（冪等）
        part = re.sub(r"\| causal_chain \|[^\n]*\n?", "", part)
        # lesson idを抽出（`Lxxx` 形式）
        lesson_ids = re.findall(r"\|\s*lesson\s*\|\s*`([a-z0-9._-]+:L\w+|L\w+)`", part, re.I)
        chains = []
        ambiguous = 0
        for lid in lesson_ids:
            origin, is_ambiguous = resolve_lesson_origin(lid, origins)
            if origin:
                chains.append(f"| causal_chain | `{origin}` ({lid}) |")
            elif is_ambiguous:
                ambiguous += 1
        if ambiguous:
            print(f"AMBIGUOUS lesson refs skipped: {ambiguous} ({', '.join(lesson_ids)})")
        if chains:
            lines = part.splitlines(keepends=True)
            last_pipe_idx = -1
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("|") and not stripped.startswith("|---") and stripped != "|":
                    last_pipe_idx = i
            if last_pipe_idx >= 0:
                for chain in reversed(chains):
                    lines.insert(last_pipe_idx + 1, chain + "\n")
                part = "".join(lines)
                injected += len(chains)
        new_parts.append(part)
    new_text = "".join(new_parts)
    if new_text != text:
        atomic_write_text(index_path, new_text)
    return injected

def parse_concepts(text):
    matches = list(re.finditer(r"(?m)^##\s+(.+)$", text))
    concepts = []
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        heading = match.group(1).strip()
        attrs = {}
        resources = []
        for raw in block.splitlines():
            line = raw.strip()
            row = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$", line)
            if not row:
                continue
            left, right = row.group(1).strip(), row.group(2).strip()
            if left in {"属性", "------", "種別"}:
                continue
            if left in {"id", "label", "aliases", "skills", "related_concepts", "related_lessons"}:
                attrs[left] = right
            elif left and right and left != "------":
                resources.append((left, right))
        aliases = attrs.get("aliases", "").strip()
        label = attrs.get("label") or heading.split(" — ", 1)[-1].strip()
        files = [value for kind, value in resources if kind == "file"][:3]
        urls = [value for kind, value in resources if kind == "url"][:3]
        lessons = [
            value for kind, value in resources
            if kind in {"lesson", "deepdive", "cmd", "causal"} or value.lstrip("`").startswith(("L", "LS", "PI-", "cmd_"))
        ][:3]
        related_lessons = [
            item.strip()
            for item in attrs.get("related_lessons", "").split(",")
            if item.strip()
        ]
        if related_lessons:
            lessons = (related_lessons + lessons)[:3]
        concepts.append({
            "label": label,
            "aliases": aliases,
            "skills": attrs.get("skills", "").strip(),
            "files": files,
            "urls": urls,
            "lessons": lessons,
        })
    return concepts

def cell(values, default="なし"):
    if isinstance(values, str):
        return values or default
    return ", ".join(values) if values else default

concepts = parse_concepts(index_path.read_text(encoding="utf-8"))
lines = [
    "# セマンティクスマップ",
    "",
    "<!-- auto-generated from docs/semantic-index/index.md -->",
    "<!-- do not edit directly; update docs/semantic-index/index.md and run codd propagate --update -->",
    "",
    "| 概念 | 別名 | 主要ファイル | 外部URL | 教訓 | skills |",
    "|------|------|------------|---------|------|--------|",
]
for concept in concepts:
    lines.append(
        f"| {concept['label']} | {cell(concept['aliases'])} | "
        f"{cell(concept['files'])} | {cell(concept['urls'])} | "
        f"{cell(concept['lessons'])} | {cell(concept['skills'])} |"
    )

body = "\n".join(lines) + "\n"
if body_only:
    sys.stdout.write(body)
else:
    frontmatter = """---
codd:
  node_id: design:semantic-map
  type: generated-index
  title: セマンティクスマップ
  modules:
    - semantic-index
---

"""
    map_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_text(map_path, frontmatter + body)
    print(f"generated: {map_path}")
    origins = load_lesson_origins(repo_root)
    injected = inject_causal_chains(index_path, origins)
    if injected:
        print(f"causal_chain entries injected: {injected}")
PY

auto_resolve_semantic_index_insights() {
    local insight_script="$repo_root/scripts/insight_write.sh"
    local insights_file="${SEMANTIC_INSIGHTS_PATH:-$repo_root/queue/insights.yaml}"
    local default_map="$repo_root/context/semantic-map.md"

    [ "$body_only" = false ] || return 0
    if [ "${SEMANTIC_INSIGHT_AUTO_RESOLVE:-0}" != "1" ] && [ "$map_path" != "$default_map" ]; then
        return 0
    fi
    [ -f "$insight_script" ] || return 0
    [ -s "$insights_file" ] || return 0

    local ids
    ids=$(INSIGHTS_FILE_ENV="$insights_file" SEMANTIC_INDEX_PATH_ENV="$index_path" python3 - <<'PY' 2>/dev/null || true
import json
import os
import re
from pathlib import Path

path = os.environ["INSIGHTS_FILE_ENV"]
index_path = os.environ["SEMANTIC_INDEX_PATH_ENV"]

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except Exception:
            return value.strip('"')
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

entries = []
current = None
with open(path, encoding="utf-8") as f:
    for line in f:
        if line.startswith("- id: "):
            if current:
                entries.append(current)
            current = {"id": line[len("- id: "):].strip()}
            continue
        if current is None or not line.startswith("  ") or ":" not in line:
            continue
        key, raw = line.strip().split(":", 1)
        current[key] = parse_scalar(raw)
if current:
    entries.append(current)

known_resources = set()
try:
    text = Path(index_path).read_text(encoding="utf-8")
    known_resources.update(re.findall(r"\|\s*file\s*\|\s*`([^`]+)`\s*\|", text))
except OSError:
    pass

def is_ignored_new_file_candidate(path):
    name = Path(path).name
    return (
        re.match(r"^\.[^/]+_worktrees/", path) is not None
        # 2026-09-02 D0: dotfile/dot dir(.claude/.githooks/.gitattributes/.tmp-*receipt)は semantic index 対象外。
        # 14 件の INSIGHT_REPEAT 中 8 件がこれらの偽陽性で毎 run 再通知されていた(負の複利)
        or path.startswith(".")
        or path.startswith("tests/unit/_tmp_")
        or "/_tmp_" in path
        or name.startswith("_tmp_")
    )

for entry in entries:
    if entry.get("status") != "pending":
        continue
    source = entry.get("source")
    if source == "semantic_index_update":
        print(entry["id"])
        continue
    if source == "semantic_map_generate:new_file":
        match = re.search(r"`([^`]+)`", entry.get("insight", ""))
        rel_path = match.group(1) if match else ""
        if rel_path in known_resources or is_ignored_new_file_candidate(rel_path):
            print(entry["id"])
PY
    )

    local count=0 id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if INSIGHTS_FILE="$insights_file" bash "$insight_script" --resolve "$id" \
            "semantic map generation verified the candidate is represented or intentionally ignored" \
            "semantic_map=$map_path;semantic_index=$index_path" >/dev/null 2>&1; then
            count=$((count + 1))
        else
            echo "WARN: semantic insight auto-resolve failed: $id" >&2
        fi
    done <<< "$ids"

    [ "$count" -eq 0 ] || echo "semantic insights auto-resolved: $count"
}

auto_resolve_semantic_index_insights || true
