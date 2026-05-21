#!/usr/bin/env python3
"""Insert concept-name Obsidian links into semantic-index resource files.

This builds file -> concept edges from docs/semantic-index/index.md. It does
not create file-to-file links; each touched resource receives only its owning
concept label as a [[concept]] link.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


ROW_RE = re.compile(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$")
MARKDOWN_EXTS = {".md", ".markdown"}
COMMENT_EXTS = {".bash", ".bats", ".py", ".sh"}
TEXT_EXTS = MARKDOWN_EXTS | COMMENT_EXTS | {".txt"}
SKIP_DIRS = {
    ".git",
    "__pycache__",
    "logs",
    "queue",
}


@dataclass(frozen=True)
class Candidate:
    concept_id: str
    label: str
    path: Path


def parse_index(index_path: Path) -> list[dict]:
    text = index_path.read_text(encoding="utf-8")
    matches = list(re.finditer(r"(?m)^##\s+(.+)$", text))
    concepts: list[dict] = []
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        block = text[match.start() : end]
        heading = match.group(1).strip()
        heading_id, _, heading_label = heading.partition(" — ")
        attrs = {"id": heading_id.strip(), "label": heading_label.strip()}
        resources: list[tuple[str, str]] = []

        for raw_line in block.splitlines():
            row = ROW_RE.match(raw_line.strip())
            if not row:
                continue
            left = row.group(1).strip()
            right = row.group(2).strip()
            if left in {"属性", "------", "種別"}:
                continue
            if left in {"id", "label", "aliases", "skills", "related_concepts", "related_lessons"}:
                attrs[left] = right
            elif right:
                resources.append((left, right))

        concepts.append(
            {
                "id": attrs.get("id", heading_id).strip("` "),
                "label": attrs.get("label", heading_label).strip("` "),
                "resources": resources,
            }
        )
    return concepts


def backtick_path(ref: str) -> str | None:
    match = re.search(r"`([^`]+)`", ref)
    return match.group(1).strip() if match else None


def resolve_path(raw: str, repo_root: Path) -> tuple[Path | None, str | None]:
    path = Path(raw)
    if path.is_absolute():
        try:
            path.relative_to(repo_root)
        except ValueError:
            return None, "outside repo"
        return path, None

    candidate = (repo_root / path).resolve()
    try:
        rel = candidate.relative_to(repo_root)
    except ValueError:
        return None, "outside repo"
    if rel.parts and rel.parts[0] in SKIP_DIRS:
        return None, f"skipped directory: {rel.parts[0]}"
    return candidate, None


def collect(index_path: Path, repo_root: Path) -> tuple[dict[Path, set[str]], list[str]]:
    by_path: dict[Path, set[str]] = {}
    skipped: list[str] = []
    for concept in parse_index(index_path):
        label = concept["label"]
        if not label:
            skipped.append(f"{concept['id']}: missing label")
            continue
        for resource_type, ref in concept["resources"]:
            if resource_type != "file":
                continue
            raw_path = backtick_path(ref)
            if not raw_path:
                skipped.append(f"{concept['id']}: unparsable file ref: {ref}")
                continue
            path, reason = resolve_path(raw_path, repo_root)
            if path is None:
                skipped.append(f"{concept['id']}: {reason}: {raw_path}")
                continue
            if path.suffix not in TEXT_EXTS:
                skipped.append(f"{concept['id']}: unsupported extension: {raw_path}")
                continue
            if not path.exists() or not path.is_file():
                skipped.append(f"{concept['id']}: missing file: {raw_path}")
                continue
            by_path.setdefault(path, set()).add(label)
    return by_path, skipped


def marker_for(path: Path, labels: set[str]) -> str:
    links = ", ".join(f"[[{label}]]" for label in sorted(labels))
    return f"# semantic-links: {links}" if path.suffix in COMMENT_EXTS else f"semantic-links: {links}"


def upsert_marker(text: str, marker: str) -> tuple[str, bool]:
    marker_re = re.compile(r"(?m)^#?\s*semantic-links:\s*\[\[.*$")
    if marker_re.search(text):
        updated = marker_re.sub(marker, text, count=1)
        return updated, updated != text

    lines = text.splitlines()
    insert_at = 0
    if lines[:1] and lines[0].startswith("#!"):
        insert_at = 1
    elif lines[:1] == ["---"]:
        for idx in range(1, len(lines)):
            if lines[idx] == "---":
                insert_at = idx + 1
                break
    lines.insert(insert_at, marker)
    updated = "\n".join(lines)
    if text.endswith("\n"):
        updated += "\n"
    return updated, True


def select_batch(paths: list[Path], batch_size: int, batch_index: int) -> list[Path]:
    if batch_size <= 0:
        return paths
    start = batch_size * batch_index
    return paths[start : start + batch_size]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", default="docs/semantic-index/index.md")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--batch-size", type=int, default=0)
    parser.add_argument("--batch-index", type=int, default=0)
    parser.add_argument("--show-skipped", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    index_path = (repo_root / args.index).resolve()
    by_path, skipped = collect(index_path, repo_root)
    all_paths = sorted(by_path)
    selected = select_batch(all_paths, args.batch_size, args.batch_index)

    changed: list[Path] = []
    for path in selected:
        original = path.read_text(encoding="utf-8", errors="replace")
        updated, did_change = upsert_marker(original, marker_for(path, by_path[path]))
        if did_change:
            changed.append(path)
            if args.apply:
                path.write_text(updated, encoding="utf-8")

    mode = "apply" if args.apply else "dry-run"
    print(f"mode: {mode}")
    print(f"resource_files: {len(all_paths)}")
    print(f"selected_files: {len(selected)}")
    print(f"changed_files: {len(changed)}")
    print(f"skipped_refs: {len(skipped)}")
    for path in changed:
        print(f"changed: {path.relative_to(repo_root)}")
    if args.show_skipped:
        for item in skipped:
            print(f"skipped: {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
