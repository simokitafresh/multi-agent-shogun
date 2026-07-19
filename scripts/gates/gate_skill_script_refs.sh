#!/usr/bin/env bash
# gate_skill_script_refs.sh — SKILL.md script reference freshness gate
#
# Usage:
#   bash scripts/gates/gate_skill_script_refs.sh [repo_root]
#   SKILL_REF_DIRS="skills:.claude/skills" bash scripts/gates/gate_skill_script_refs.sh
#
# Checks:
#   (A) Extract script references from all SKILL.md files.
#   (B) Verify referenced script paths exist.
#   (C) List SKILL.md files that may need updates because a referenced script is newer.
#   (D) Verify static file paths in fenced examples exist.
#   (E) Require a dated execution marker for examples declared side-effecting.
#
# Exit code: 0=PASS, 2=review required, 3=missing reference BLOCK
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

run_check() {
local attempt=0 check_code
while :; do
set +e
SKILL_REF_REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
from __future__ import annotations

import os
import re
import sys
import fcntl
import hashlib
import json
import subprocess
import atexit
import time
from datetime import datetime, timezone
from pathlib import Path

repo_root = Path(os.environ["SKILL_REF_REPO_ROOT"]).resolve()
hash_state_path = Path(os.environ.get(
    "SKILL_REF_HASH_STATE", repo_root / "logs/skill_script_refs_verified.json"
))
record_verified = os.environ.get("SKILL_REF_RECORD_VERIFIED", "0") == "1"

hash_state_path.parent.mkdir(parents=True, exist_ok=True)
state_lock = (hash_state_path.parent / (hash_state_path.name + ".lock")).open("a+")

def acquire_state_lock(timeout_seconds: float = 10.0) -> None:
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            fcntl.flock(state_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            if time.monotonic() >= deadline:
                print(f"BLOCK: contract hash state lock timeout ({timeout_seconds:g}s): {state_lock.name}")
                sys.exit(3)
            time.sleep(0.05)


def read_state_bytes() -> bytes | None:
    try:
        return hash_state_path.read_bytes()
    except FileNotFoundError:
        return None


acquire_state_lock()
state_snapshot = read_state_bytes()
state_corrupt = False
try:
    hash_state = json.loads(state_snapshot.decode("utf-8")) if state_snapshot is not None else {"references": {}}
except (UnicodeDecodeError, json.JSONDecodeError, OSError):
    hash_state = {"references": {}}
    state_corrupt = True
if not isinstance(hash_state, dict) or not isinstance(hash_state.get("references"), dict):
    hash_state = {"references": {}}
    state_corrupt = True
state_generation = hashlib.sha256(state_snapshot).hexdigest() if state_snapshot is not None else "missing"
fcntl.flock(state_lock.fileno(), fcntl.LOCK_UN)

contract_line_re = re.compile(
    r"(?:^\s*#\s*(?:usage|exit code|public (?:argument|output))\s*:|argument-hint|"
    r"getopts|argparse|add_argument|sys\.argv|\$\{?[#@*0-9]|"
    r"\b(?:exit|sys\.exit)\b|\b(?:echo|printf|print)\s*(?:\(|['\"]))",
    re.I,
)

def contract_sha256_text(text: str) -> str:
    """Hash the documented CLI arguments, exit codes and literal output format.

    Filesystem writes and implementation calls are deliberately excluded: they
    made every internal refactor look like an interface change.  Variable-only
    diagnostic changes are likewise implementation detail; literal public
    output and explicit ``# Public output:`` declarations remain contractual.
    """
    surface = []
    for raw in text.splitlines():
        line = raw.strip()
        if contract_line_re.search(line):
            surface.append(re.sub(r"\s+", " ", line))
    payload = "\n".join(surface).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def contract_sha256(path: Path) -> str:
    return contract_sha256_text(path.read_text(encoding="utf-8", errors="ignore"))

command_ref_re = re.compile(
    r"(?:^|[\s`(])(?:bash|sh|python3?|node|ruby|perl)\s+"
    r"([~./A-Za-z0-9_-][^\s`'\"|;&)]*)"
)
inline_ref_re = re.compile(
    r"`((?:scripts|skills|\.claude/skills|~/.claude/skills|~/.codex/skills)"
    r"/[^`\s]+?\.(?:sh|py|js))`"
)
script_ext_re = re.compile(r"\.(?:sh|py|js)$")
checked_at_re = re.compile(
    r"<!--\s*script_refs_checked_at\s*[:=]\s*"
    r"([0-9]{4}-[0-9]{2}-[0-9]{2}(?:[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})?)?)"
    r"\s*-->"
)
fenced_block_re = re.compile(r"```[^\n]*\n(?P<body>.*?)```", re.DOTALL)
example_path_re = re.compile(
    r"(?<![A-Za-z0-9_./-])((?:(?:/mnt/[a-zA-Z]/|/home/|/protected/|/etc/)"
    r"[A-Za-z0-9_./-]+|(?:scripts|skills|context|docs|tests|config|queue)/[A-Za-z0-9_./-]+)"
    r"\.(?:sh|py|js|md|ya?ml|json|bats|env))(?=$|[\s`'\"|;&),\]])"
)
side_effect_re = re.compile(r"<!--\s*example_side_effect\s*:\s*true\s*-->", re.I)
execution_verified_re = re.compile(
    r"<!--\s*example_execution_verified_at\s*:\s*"
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})"
    r"\s*-->",
    re.I,
)


def iter_skill_files(root: Path):
    skip_dirs = {".git", ".mypy_cache", ".pytest_cache", "node_modules", "__pycache__"}
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        if "SKILL.md" in files:
            yield Path(current) / "SKILL.md"


def clean_ref(raw: str) -> str:
    return raw.strip().strip("'\"").rstrip(".,:;")


def resolve_ref(raw: str) -> Path:
    ref = clean_ref(raw)
    if ref.startswith("~/"):
        return Path(os.path.expanduser(ref)).resolve()
    path = Path(ref)
    if path.is_absolute():
        return path
    return (repo_root / path).resolve()


def extract_refs(text: str) -> list[str]:
    refs: list[str] = []
    for match in command_ref_re.finditer(text):
        ref = clean_ref(match.group(1))
        if script_ext_re.search(ref):
            refs.append(ref)
    for match in inline_ref_re.finditer(text):
        refs.append(clean_ref(match.group(1)))
    return sorted(set(refs))


def extract_example_paths(text: str) -> list[str]:
    paths: set[str] = set()
    for block in fenced_block_re.finditer(text):
        body = "\n".join(
            line for line in block.group("body").splitlines()
            if not line.lstrip().startswith("#")
        )
        for match in example_path_re.finditer(body):
            raw = clean_ref(match.group(1)).rstrip("]}")
            # Runtime destinations and intentionally variable/template paths cannot
            # have a repository-time existence guarantee.
            if raw.startswith(("/tmp/", "/dev/", "/proc/", "/sys/")):
                continue
            if any(token in raw for token in ("$", "<", ">", "{", "}", "*", "?")):
                continue
            if re.search(r"(?:YYYY|MM|DD|20XX|\d{8})", raw, re.I):
                continue
            if any(part in {"X.bats", "example.json", "example.yaml"} or part.startswith("my_") for part in Path(raw).parts):
                continue
            paths.add(raw)
    return sorted(paths)


def example_path_exists(raw: str) -> tuple[bool, Path]:
    resolved = resolve_ref(raw)
    if resolved.exists() or Path(raw).is_absolute():
        return resolved.exists(), resolved
    # A skill may intentionally run inside another registered project. Resolve
    # relative examples against those roots before declaring them absent.
    try:
        import yaml
        projects = yaml.safe_load((repo_root / "config/projects.yaml").read_text(encoding="utf-8")) or {}
        for item in projects.get("projects", []):
            root = Path(str(item.get("path") or "")).expanduser()
            candidate = (root / raw).resolve()
            if candidate.exists():
                return True, candidate
    except Exception:
        pass
    return False, resolved


def parse_checked_at(text: str) -> datetime | None:
    # SKILL.mdの更新慣行は先頭への新コメント追記で、古い履歴コメントが下部に残る。
    # 最新(max)を採用しないと末尾の古いコメントで恒常WARN化する(INS-20260702-204807)。
    matches = checked_at_re.findall(text)
    if not matches:
        return None

    parsed_values: list[datetime] = []
    for raw in matches:
        normalized = raw.strip().replace("Z", "+00:00")
        if " " in normalized and "T" not in normalized:
            normalized = normalized.replace(" ", "T", 1)

        try:
            parsed = datetime.fromisoformat(normalized)
        except ValueError:
            continue

        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        parsed_values.append(parsed)

    return max(parsed_values) if parsed_values else None


def git_checkout_available() -> bool:
    try:
        subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "--git-dir"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


git_available = git_checkout_available()
git_baseline_cache: dict[tuple[str, str], str | None] = {}
git_snapshot_cache: dict[str, str | None] = {}
cat_file_process: subprocess.Popen[bytes] | None = None


def close_cat_file() -> None:
    global cat_file_process
    if cat_file_process is not None:
        try:
            if cat_file_process.stdin:
                cat_file_process.stdin.close()
            cat_file_process.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            pass


atexit.register(close_cat_file)


def git_snapshot_before(checked_iso: str) -> str | None:
    if checked_iso in git_snapshot_cache:
        return git_snapshot_cache[checked_iso]
    commit: str | None = None
    if git_available:
        try:
            commit = subprocess.run(
                ["git", "-C", str(repo_root), "rev-list", "-1", f"--before={checked_iso}", "HEAD"],
                check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            ).stdout.strip() or None
        except (OSError, subprocess.CalledProcessError):
            pass
    git_snapshot_cache[checked_iso] = commit
    return commit


def cat_file_blob(object_name: str) -> str | None:
    global cat_file_process
    try:
        if cat_file_process is None:
            cat_file_process = subprocess.Popen(
                ["git", "-C", str(repo_root), "cat-file", "--batch"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
        assert cat_file_process.stdin is not None and cat_file_process.stdout is not None
        cat_file_process.stdin.write(object_name.encode("utf-8") + b"\n")
        cat_file_process.stdin.flush()
        header = cat_file_process.stdout.readline().decode("utf-8", errors="replace").strip()
        if header.endswith(" missing"):
            return None
        parts = header.rsplit(" ", 2)
        if len(parts) != 3 or parts[1] != "blob":
            return None
        size = int(parts[2])
        payload = cat_file_process.stdout.read(size)
        cat_file_process.stdout.read(1)
        return payload.decode("utf-8", errors="ignore")
    except (OSError, ValueError, BrokenPipeError):
        return None


def git_contract_baseline(path: Path, checked_at: datetime) -> str | None:
    """Return the contract hash from the last blob committed before checked_at."""
    try:
        rel = str(path.resolve().relative_to(repo_root))
    except ValueError:
        return None
    checked_iso = checked_at.astimezone(timezone.utc).isoformat()
    key = (rel, checked_iso)
    if key in git_baseline_cache:
        return git_baseline_cache[key]
    result: str | None = None
    if git_available:
        try:
            commit = git_snapshot_before(checked_iso)
            if commit:
                blob = cat_file_blob(f"{commit}:{rel}")
                result = contract_sha256_text(blob) if blob is not None else None
        except (OSError, subprocess.CalledProcessError):
            result = None
    git_baseline_cache[key] = result
    return result


raw_roots = os.environ.get("SKILL_REF_DIRS", "skills:.claude/skills:.codex/skills")
scan_roots: list[Path] = []
for raw in raw_roots.split(":"):
    raw = raw.strip()
    if not raw:
        continue
    candidate = Path(os.path.expanduser(raw))
    if not candidate.is_absolute():
        candidate = repo_root / candidate
    if candidate.exists():
        scan_roots.append(candidate.resolve())

skill_files = sorted(
    {skill_file for root in scan_roots for skill_file in iter_skill_files(root)}
)
missing: list[tuple[str, str, str]] = []
stale: list[tuple[str, str, str]] = []
missing_example_paths: list[tuple[str, str, str]] = []
unverified_side_effect_examples: list[str] = []
total_refs = 0
skills_with_refs = 0
state_dirty = False
actions_required = 0

for skill_file in skill_files:
    try:
        text = skill_file.read_text(encoding="utf-8", errors="ignore")
    except OSError as exc:
        missing.append((str(skill_file.relative_to(repo_root)), "(read error)", str(exc)))
        continue

    refs = extract_refs(text)
    if refs:
        skills_with_refs += 1
    total_refs += len(refs)
    checked_at = parse_checked_at(text)
    checked_at_epoch = checked_at.timestamp() if checked_at is not None else None
    skill_freshness_time = checked_at_epoch if checked_at_epoch is not None else skill_file.stat().st_mtime

    display_skill = str(skill_file.relative_to(repo_root))
    for example_path in extract_example_paths(text):
        exists, resolved_example = example_path_exists(example_path)
        if not exists:
            missing_example_paths.append((display_skill, example_path, str(resolved_example)))
    if side_effect_re.search(text) and not execution_verified_re.search(text):
        unverified_side_effect_examples.append(display_skill)

    for ref in refs:
        resolved = resolve_ref(ref)
        if not resolved.exists():
            missing.append((display_skill, ref, str(resolved)))
            continue
        state_key = f"{display_skill}::{ref}"
        current_hash = contract_sha256(resolved) if resolved.is_file() else ""
        entry = hash_state["references"].get(state_key, {})
        verified_hash = str(entry.get("contract_sha256", entry.get("sha256", "")))
        if record_verified and current_hash:
            hash_state["references"][state_key] = {
                "contract_sha256": current_hash,
                "verified_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
            }
            verified_hash = current_hash
            state_dirty = True
        git_baseline = git_contract_baseline(resolved, checked_at) if checked_at is not None else None
        baseline_hashes = {value for value in (verified_hash, git_baseline) if value}
        contract_changed = bool(baseline_hashes) and current_hash not in baseline_hashes
        mtime_fallback_changed = (
            not baseline_hashes and resolved.stat().st_mtime > skill_freshness_time + 1
        )
        if resolved.is_file() and (contract_changed or mtime_fallback_changed):
            # 判定根拠を明示: 採用基準(checked_atコメント最新値かmtimeか)が見えないと
            # 「更新したのに直らない」の原因調査が毎回ゼロからになる(2026-07-02 3セッション先送りの教訓)
            baseline_src = (
                "verified contract hash" if verified_hash else
                "checked_at Git contract hash" if git_baseline else
                "checked_at mtime fallback" if checked_at_epoch is not None else
                "SKILL.md mtime fallback"
            )
            baseline_iso = datetime.fromtimestamp(skill_freshness_time, tz=timezone.utc).astimezone().isoformat(timespec="seconds")
            script_iso = datetime.fromtimestamp(resolved.stat().st_mtime, tz=timezone.utc).astimezone().isoformat(timespec="seconds")
            stale.append((display_skill, ref, str(resolved.relative_to(repo_root)) if resolved.is_relative_to(repo_root) else str(resolved), baseline_src, baseline_iso, script_iso))
            if str(entry.get("last_action_contract_sha256", "")) != current_hash:
                entry = dict(entry)
                entry["last_action_contract_sha256"] = current_hash
                hash_state["references"][state_key] = entry
                actions_required += 1
                state_dirty = True

if state_dirty:
    acquire_state_lock()
    publish_snapshot = read_state_bytes()
    publish_generation = hashlib.sha256(publish_snapshot).hexdigest() if publish_snapshot is not None else "missing"
    if publish_generation != state_generation:
        fcntl.flock(state_lock.fileno(), fcntl.LOCK_UN)
        # Re-run the complete scan once; stale decisions are never published.
        sys.exit(75)
    tmp = hash_state_path.with_suffix(hash_state_path.suffix + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(hash_state, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, hash_state_path)
    fcntl.flock(state_lock.fileno(), fcntl.LOCK_UN)

print("=== SKILL.md script reference check ===")
print(
    f"走査: {len(skill_files)} SKILL.md / script参照 {total_refs}件 / "
    f"参照あり {skills_with_refs}件 / roots={','.join(str(p.relative_to(repo_root)) if p.is_relative_to(repo_root) else str(p) for p in scan_roots)}"
)
print(f"契約hash action: required={actions_required}, deduped={max(0, len(stale) - actions_required)}")

if state_corrupt:
    print(f"BLOCK: contract hash state is corrupt: {hash_state_path}")
    sys.exit(3)

if missing:
    print("=== 参照先不在 ===")
    for skill, ref, resolved in missing[:30]:
        print(f"  WARN: {skill} -> {ref} (resolved: {resolved})")
    if len(missing) > 30:
        print(f"  ... {len(missing) - 30} more")
else:
    print("OK: 全script参照先が実在")

if stale:
    print("=== 要更新スキル一覧 (script newer than SKILL.md) ===")
    for skill, ref, resolved, baseline_src, baseline_iso, script_iso in stale[:30]:
        print(f"  WARN: {skill} <- {ref} (newer: {resolved})")
        print(f"        基準={baseline_src} {baseline_iso} < script {script_iso}")
    if len(stale) > 30:
        print(f"  ... {len(stale) - 30} more")
else:
    print("OK: SKILL.md更新日がscript参照先以上に新しい")

if missing_example_paths:
    print("=== 例示コードブロック内パス不在 ===")
    for skill, ref, resolved in missing_example_paths[:30]:
        print(f"  WARN: {skill} -> {ref} (resolved: {resolved})")
    if len(missing_example_paths) > 30:
        print(f"  ... {len(missing_example_paths) - 30} more")
else:
    print("OK: 例示コードブロック内の静的ファイルパスが実在")

if unverified_side_effect_examples:
    print("=== 副作用例示の実走検証マーカー不在 ===")
    for skill in unverified_side_effect_examples[:30]:
        print(f"  WARN: {skill} requires example_execution_verified_at (ISO 8601)")
else:
    print("OK: 宣言済み副作用例示に日時つき実走検証マーカーあり")

if missing or stale or missing_example_paths or unverified_side_effect_examples:
    fire_log = Path(os.environ.get("GATE_FIRE_LOG_FILE", repo_root / "logs/gate_fire_log.yaml"))
    fire_log.parent.mkdir(parents=True, exist_ok=True)
    reasons = (
        f"missing={len(missing)},stale={len(stale)},"
        f"example_path_missing={len(missing_example_paths)},"
        f"side_effect_marker_missing={len(unverified_side_effect_examples)}"
    )
    with fire_log.open("a", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        ts = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
        handle.write(
            f'- ts: "{ts}", file: "SKILL.md", gate: "skill_script_refs", '
            f'result: WARN, reasons: "{reasons}"\n'
        )
        handle.flush()
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    if missing:
        print("--- 総合判定: BLOCK ---")
        sys.exit(3)
    print("--- 総合判定: REVIEW_REQUIRED ---")
    sys.exit(2)

print("--- 総合判定: PASS ---")
PY
check_code=$?
if [ "$check_code" -ne 75 ]; then
    # The caller owns errexit.  Re-enabling it here makes a legitimate
    # REVIEW_REQUIRED/BLOCK return terminate the cache wrapper before it can
    # publish the captured diagnostics.
    return "$check_code"
fi
if [ "$attempt" -ge 1 ]; then
    printf '%s\n' 'BLOCK: contract hash state generation changed twice; refusing stale publish'
    return 3
fi
attempt=$((attempt + 1))
done
}

CACHE_TTL_SECONDS="${SKILL_REF_CACHE_TTL_SECONDS:-30}"
RAW_ROOTS="${SKILL_REF_DIRS:-skills:.claude/skills:.codex/skills}"

# Cache identity is the complete result-determining input, not a maximum mtime.
# This intentionally invalidates within TTL for verified-state changes, changes
# to any (including non-max-mtime) SKILL.md, and every referenced script.
INPUT_SIGNATURE="$({
    printf 'gate\0'; sha256sum "$0" 2>/dev/null || true
    printf 'roots\0%s\0' "$RAW_ROOTS"
    printf 'record_verified\0%s\0' "${SKILL_REF_RECORD_VERIFIED:-0}"
    state_file="${SKILL_REF_HASH_STATE:-$REPO_ROOT/logs/skill_script_refs_verified.json}"
    printf 'state\0'; sha256sum "$state_file" 2>/dev/null || printf 'missing\n'
    IFS=':' read -r -a signature_roots <<< "$RAW_ROOTS"
    for raw_root in "${signature_roots[@]}"; do
        [ -n "$raw_root" ] || continue
        expanded_root="${raw_root/#\~/$HOME}"
        case "$expanded_root" in /*) skill_root="$expanded_root" ;; *) skill_root="$REPO_ROOT/$expanded_root" ;; esac
        [ -d "$skill_root" ] || continue
        while IFS= read -r -d '' skill_file; do
            printf 'skill\0%s\0' "$skill_file"; sha256sum "$skill_file"
            while IFS= read -r ref; do
                [ -n "$ref" ] || continue
                case "$ref" in /*) ref_path="$ref" ;; ~/*) ref_path="${ref/#\~/$HOME}" ;; *) ref_path="$REPO_ROOT/$ref" ;; esac
                printf 'ref\0%s\0' "$ref"; sha256sum "$ref_path" 2>/dev/null || printf 'missing\n'
            done < <(grep -Eo '(bash|sh|python3?|node|ruby|perl)[[:space:]]+[^[:space:]`'"'"'"|;&)]*\.(sh|py|js)' "$skill_file" 2>/dev/null | awk '{print $2}' | sort -u)
        done < <(find "$skill_root" -name SKILL.md -type f -print0 | sort -z)
    done
} | sha256sum | awk '{print $1}')"

if [ "${SKILL_REF_DISABLE_CACHE:-0}" != "1" ] && [ "$CACHE_TTL_SECONDS" -gt 0 ] 2>/dev/null; then
    CACHE_KEY="${REPO_ROOT//[^A-Za-z0-9._-]/_}_${INPUT_SIGNATURE}"
    CACHE_BASE="/tmp/shogun_gate_skill_script_refs_${CACHE_KEY}"
    # Single cache file: first line = exit code, remaining lines = output.
    # Eliminates the race window between writing CACHE_OUT and CACHE_CODE separately.
    CACHE_FILE="${CACHE_BASE}.cache"
    printf -v NOW '%(%s)T' -1

    if [ -f "$CACHE_FILE" ]; then
        CACHE_MTIME="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || printf '0')"
        CACHE_AGE=$((NOW - CACHE_MTIME))
        if [ "$CACHE_AGE" -ge 0 ] && [ "$CACHE_AGE" -le "$CACHE_TTL_SECONDS" ]; then
            {
                IFS= read -r CACHED_CODE
                while IFS= read -r CACHE_LINE || [ -n "$CACHE_LINE" ]; do
                    printf '%s\n' "$CACHE_LINE"
                done
            } < "$CACHE_FILE"
            exit "$CACHED_CODE"
        fi
    fi

    TMP_OUT="$(mktemp "${CACHE_BASE}.XXXXXX")"
    set +e
    run_check >"$TMP_OUT"
    CHECK_CODE=$?
    set -e
    TMP_CACHE="$(mktemp "${CACHE_BASE}.XXXXXX")"
    { printf '%s\n' "$CHECK_CODE"; cat "$TMP_OUT"; } >"$TMP_CACHE"
    mv "$TMP_CACHE" "$CACHE_FILE"
    cat "$TMP_OUT"
    rm -f "$TMP_OUT"
    exit "$CHECK_CODE"
fi

run_check
