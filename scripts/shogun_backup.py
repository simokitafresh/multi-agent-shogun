#!/usr/bin/env python3
"""Encrypted off-host backup and restore for the shogun state.

The default operation is deliberately explicit: ``--backup`` uploads a
small set of typed artifacts to a dedicated Drive folder and downloads each
one again before reporting success.  The encryption key is always read from
an external file; it is never copied into an archive or sent to Drive.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DM_ROOT = Path("/mnt/c/Python_app/DM-signal")
DRIVE_FOLDER_MIME = "application/vnd.google-apps.folder"
MARKER = "# shogun-drive-backup"


class BackupError(RuntimeError):
    """A fail-closed backup/restore error."""


def fail(message: str) -> None:
    raise BackupError(message)


def utc_stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], *, capture: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=True,
            text=True,
            capture_output=capture,
        )
    except FileNotFoundError as exc:
        fail(f"required command is unavailable: {command[0]}")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        fail(f"command failed ({exc.returncode}): {command[0]} {detail[-500:]}")


def gws_path() -> str:
    path = os.environ.get("SHOGUN_GWS_BIN") or shutil.which("gws")
    if not path:
        fail("gws CLI is unavailable")
    return path


def gws_json(args: list[str]) -> dict[str, Any]:
    result = run([gws_path(), *args])
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail(f"gws returned non-JSON output: {exc}")
    if not isinstance(value, dict):
        fail("gws returned a non-object JSON response")
    return value


def drive_list(*, folder_id: str | None = None, name: str | None = None) -> list[dict[str, Any]]:
    clauses = ["trashed = false"]
    if folder_id:
        clauses.append(f"'{folder_id}' in parents")
    if name:
        escaped_name = name.replace("\\", "\\\\").replace("'", "\\'")
        clauses.append(f"name = '{escaped_name}'")
    query = " and ".join(clauses)
    files: list[dict[str, Any]] = []
    page_token: str | None = None
    while True:
        params: dict[str, Any] = {
            "q": query,
            "pageSize": 1000,
            "fields": "nextPageToken,files(id,name,mimeType,size,parents,appProperties)",
        }
        if page_token:
            params["pageToken"] = page_token
        response = gws_json(["drive", "files", "list", "--params", json.dumps(params)])
        page = response.get("files", [])
        if not isinstance(page, list):
            fail("Drive files.list returned an invalid files field")
        files.extend(item for item in page if isinstance(item, dict))
        page_token = response.get("nextPageToken")
        if not page_token:
            return files


def ensure_drive_folder(name: str) -> dict[str, Any]:
    matches = [item for item in drive_list(name=name) if item.get("mimeType") == DRIVE_FOLDER_MIME]
    if len(matches) > 1:
        fail(f"dedicated Drive folder is ambiguous: {name} ({len(matches)} matches)")
    if matches:
        return matches[0]
    return gws_json(
        [
            "drive",
            "files",
            "create",
            "--json",
            json.dumps({"name": name, "mimeType": DRIVE_FOLDER_MIME}),
            "--params",
            json.dumps({"fields": "id,name,mimeType"}),
        ]
    )


def upload(path: Path, *, folder_id: str, name: str, kind: str, backup_id: str) -> dict[str, Any]:
    metadata = {
        "name": name,
        "parents": [folder_id],
        "description": f"shogun backup {backup_id}; artifact={kind}",
        "appProperties": {"shogunBackup": "1", "backupId": backup_id, "artifactKind": kind},
    }
    return gws_json(
        [
            "drive",
            "files",
            "create",
            "--params",
            json.dumps({"fields": "id,name,mimeType,size"}),
            "--json",
            json.dumps(metadata),
            "--upload",
            str(path),
        ]
    )


def download(file_id: str, destination: Path) -> None:
    command = [
        gws_path(),
        "drive",
        "files",
        "get",
        "--params",
        json.dumps({"fileId": file_id, "alt": "media"}),
        "--output",
        str(destination),
    ]
    try:
        completed = subprocess.run(command, check=True, capture_output=True)
    except FileNotFoundError:
        fail(f"required command is unavailable: {command[0]}")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or b"").decode(errors="replace").strip()
        fail(f"command failed ({exc.returncode}): {command[0]} {detail[-500:]}")
    # gws writes binary media to --output, but application/json media is
    # rendered on stdout while leaving an empty output placeholder.  Support
    # both forms so the manifest remains verifiable and portable.
    if (not destination.exists() or destination.stat().st_size == 0) and completed.stdout:
        destination.write_bytes(completed.stdout)
    if not destination.exists() or destination.stat().st_size == 0:
        fail(f"Drive download was empty: {destination.name}")


def require_external_key(path: Path, *, root: Path, dm_root: Path) -> Path:
    try:
        resolved = path.expanduser().resolve(strict=True)
    except FileNotFoundError:
        fail(f"encryption key file does not exist: {path}")
    for protected in (root.resolve(), dm_root.resolve()):
        if resolved == protected or protected in resolved.parents:
            fail("encryption key must be outside both repositories")
    if not resolved.is_file() or not os.access(resolved, os.R_OK):
        fail("encryption key is not a readable regular file")
    return resolved


def sqlite_backup(source: Path, destination: Path) -> None:
    if not source.is_file():
        fail(f"memory DB is missing: {source}")
    # Reuse the tracked, Guard14-approved online-backup helper.  It performs
    # the read-only URI open and quick-check in one transaction-safe process.
    helper = ROOT / "scripts" / "hooks" / "memory_db_fts5_preflight.py"
    result = run(["python3", str(helper), "--backup", str(source), str(destination)])
    if "quick_check=ok" not in result.stdout:
        fail(f"memory DB backup helper did not report quick_check=ok: {result.stdout.strip()}")


def gzip_file(source: Path, destination: Path) -> None:
    with source.open("rb") as source_handle, gzip.GzipFile(
        filename="", mode="wb", fileobj=destination.open("wb"), mtime=0
    ) as destination_handle:
        shutil.copyfileobj(source_handle, destination_handle, length=1024 * 1024)


def tar_directory(source: Path, destination: Path, arcname: str) -> None:
    if not source.is_dir():
        fail(f"required directory is missing: {source}")
    with tarfile.open(destination, "w:gz") as archive:
        archive.add(source, arcname=arcname, recursive=True)


def openssl_encrypt(source: Path, destination: Path, key: Path) -> None:
    run(
        [
            "openssl",
            "enc",
            "-aes-256-cbc",
            "-pbkdf2",
            "-salt",
            "-pass",
            f"file:{key}",
            "-in",
            str(source),
            "-out",
            str(destination),
        ]
    )
    os.chmod(destination, 0o600)


def openssl_decrypt(source: Path, destination: Path, key: Path) -> None:
    run(
        [
            "openssl",
            "enc",
            "-d",
            "-aes-256-cbc",
            "-pbkdf2",
            "-pass",
            f"file:{key}",
            "-in",
            str(source),
            "-out",
            str(destination),
        ]
    )


def env_files(dm_root: Path) -> list[Path]:
    if not dm_root.is_dir():
        fail(f"DM-signal root is missing: {dm_root}")
    return sorted(path for path in dm_root.rglob(".env*") if path.is_file())


def env_tar(dm_root: Path, destination: Path) -> int:
    files = env_files(dm_root)
    if not files:
        fail(f"no DM-signal env files found below {dm_root}")
    with tarfile.open(destination, "w") as archive:
        for path in files:
            archive.add(path, arcname=path.relative_to(dm_root).as_posix(), recursive=False)
    return len(files)


def safe_extract(archive_path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    destination_resolved = destination.resolve()
    with tarfile.open(archive_path, "r:*") as archive:
        members = archive.getmembers()
        for member in members:
            relative = PurePosixPath(member.name)
            if relative.is_absolute() or ".." in relative.parts:
                fail(f"unsafe archive member: {member.name}")
            target = destination / Path(*relative.parts)
            target_absolute = target.absolute()
            if destination_resolved != target_absolute and destination_resolved not in target_absolute.parents:
                fail(f"archive member escapes destination: {member.name}")
            if member.islnk():
                fail(f"hardlink archive member is not allowed: {member.name}")
            if member.issym():
                link_name = PurePosixPath(member.linkname)
                if link_name.is_absolute():
                    # Historical worktrees used either of these two absolute
                    # repo roots.  Rewrite only those known roots to a
                    # relative link in the isolated destination.
                    known_roots = (
                        "/mnt/c/tools/multi-agent-shogun",
                        "/home/simokitafresh/multi-agent-shogun",
                    )
                    matching_root = next((root for root in known_roots if str(link_name).startswith(root + "/")), None)
                    if matching_root is None:
                        fail(f"external absolute symlink is not allowed: {member.name}")
                    mapped = destination / str(link_name)[len(matching_root) + 1 :]
                    link_value = os.path.relpath(mapped, (destination / Path(*relative.parts)).parent)
                else:
                    mapped = Path(os.path.abspath(str(destination / Path(*relative.parts).parent / Path(*link_name.parts))))
                    if destination_resolved != mapped and destination_resolved not in mapped.parents:
                        fail(f"symlink escapes destination: {member.name}")
                    link_value = member.linkname
                if not link_value:
                    fail(f"empty symlink target: {member.name}")
                continue
        for member in members:
            relative = PurePosixPath(member.name)
            target_path = destination / Path(*relative.parts)
            if member.isdir():
                if target_path.exists() and not target_path.is_dir():
                    fail(f"archive directory conflicts with file: {member.name}")
                target_path.mkdir(parents=True, exist_ok=True)
                continue
            target_path.parent.mkdir(parents=True, exist_ok=True)
            if target_path.is_symlink() or target_path.is_file():
                target_path.unlink()
            elif target_path.exists():
                fail(f"archive file conflicts with directory: {member.name}")
            if member.issym():
                link_name = PurePosixPath(member.linkname)
                if link_name.is_absolute():
                    known_roots = (
                        "/mnt/c/tools/multi-agent-shogun",
                        "/home/simokitafresh/multi-agent-shogun",
                    )
                    matching_root = next((root for root in known_roots if str(link_name).startswith(root + "/")), None)
                    if matching_root is None:
                        fail(f"external absolute symlink is not allowed: {member.name}")
                    mapped = destination / str(link_name)[len(matching_root) + 1 :]
                    link_value = os.path.relpath(mapped, target_path.parent)
                else:
                    link_value = member.linkname
                os.symlink(link_value, target_path)
                continue
            if not member.isfile():
                fail(f"unsupported archive member: {member.name}")
            source = archive.extractfile(member)
            if source is None:
                fail(f"archive member has no readable data: {member.name}")
            with source, target_path.open("wb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)


def build_artifacts(stage: Path, *, root: Path, dm_root: Path, key: Path, backup_id: str) -> tuple[list[dict[str, Any]], int]:
    raw_db = stage / "memory_db.sqlite3"
    sqlite_backup(root / "data" / "multi_agent_shogun_memory.db", raw_db)
    memory_gz = stage / f"{backup_id}__memory_db.sqlite3.gz"
    gzip_file(raw_db, memory_gz)

    projects = stage / f"{backup_id}__projects.tar.gz"
    tar_directory(root / "projects", projects, "projects")
    queue = stage / f"{backup_id}__queue.tar.gz"
    tar_directory(root / "queue", queue, "queue")

    gate_metrics = root / "logs" / "gate_metrics.log"
    if not gate_metrics.is_file():
        fail(f"gate metrics log is missing: {gate_metrics}")
    gate_gz = stage / f"{backup_id}__gate_metrics.log.gz"
    gzip_file(gate_metrics, gate_gz)

    env_raw = stage / "dm_signal_env.tar"
    env_count = env_tar(dm_root, env_raw)
    env_enc = stage / f"{backup_id}__dm_signal_env.tar.enc"
    openssl_encrypt(env_raw, env_enc, key)

    paths = [memory_gz, projects, queue, gate_gz, env_enc]
    artifacts = [
        {"name": path.name, "kind": kind, "sha256": sha256(path), "size": path.stat().st_size}
        for path, kind in zip(paths, ("memory_db", "projects", "queue", "gate_metrics", "dm_signal_env"))
    ]
    return artifacts, env_count


def verify_drive(folder_id: str, backup_id: str, stage: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    expected = manifest.get("artifacts")
    if not isinstance(expected, list) or not expected:
        fail("backup manifest has no artifacts")
    expected_by_name = {item.get("name"): item for item in expected if isinstance(item, dict)}
    names = {f.get("name") for f in drive_list(folder_id=folder_id) if f.get("name", "").startswith(f"{backup_id}__")}
    required_names = set(expected_by_name) | {f"{backup_id}__manifest.json"}
    if names != required_names:
        fail(f"Drive file list mismatch: expected {sorted(required_names)}, got {sorted(names)}")
    downloaded: dict[str, str] = {}
    for name, item in expected_by_name.items():
        matches = [f for f in drive_list(folder_id=folder_id, name=name) if f.get("name") == name]
        if len(matches) != 1:
            fail(f"Drive artifact is not unique: {name}")
        destination = stage / name
        download(str(matches[0]["id"]), destination)
        actual = sha256(destination)
        if actual != item.get("sha256"):
            fail(f"sha256 mismatch for Drive artifact {name}: {actual} != {item.get('sha256')}")
        downloaded[name] = actual
    return {"file_list_count": len(names), "sha256_verified": len(downloaded), "sha256": downloaded}


def backup(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    dm_root = Path(args.dm_root).expanduser().resolve()
    key = require_external_key(Path(args.key_file), root=root, dm_root=dm_root)
    backup_id = args.backup_id or f"shogun-{utc_stamp()}"
    folder = ensure_drive_folder(args.drive_folder)
    with tempfile.TemporaryDirectory(prefix=f"{backup_id}-", dir=args.temp_dir) as temporary:
        stage = Path(temporary)
        artifacts, env_count = build_artifacts(stage, root=root, dm_root=dm_root, key=key, backup_id=backup_id)
        manifest = {
            "schema": 1,
            "backup_id": backup_id,
            "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "source_root": str(root),
            "dm_signal_root": str(dm_root),
            "artifacts": artifacts,
            "env_file_count": env_count,
        }
        for item in artifacts:
            upload(stage / item["name"], folder_id=str(folder["id"]), name=item["name"], kind=item["kind"], backup_id=backup_id)
        manifest_path = stage / f"{backup_id}__manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        upload(manifest_path, folder_id=str(folder["id"]), name=manifest_path.name, kind="manifest", backup_id=backup_id)
        verification = verify_drive(str(folder["id"]), backup_id, stage, manifest)
    result = {
        "operation": "backup",
        "backup_id": backup_id,
        "drive_folder_id": folder["id"],
        "artifact_count": len(artifacts),
        "env_file_count": env_count,
        "verification": verification,
    }
    write_log(root, result)
    return result


def find_manifest(folder_id: str, backup_id: str) -> dict[str, Any]:
    name = f"{backup_id}__manifest.json"
    matches = drive_list(folder_id=folder_id, name=name)
    if len(matches) != 1:
        fail(f"backup manifest is not unique on Drive: {name}")
    with tempfile.TemporaryDirectory(prefix="shogun-manifest-") as temporary:
        path = Path(temporary) / name
        download(str(matches[0]["id"]), path)
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"backup manifest cannot be read: {exc}")
    if value.get("backup_id") != backup_id:
        fail("backup manifest identity mismatch")
    return value


def restore(args: argparse.Namespace) -> dict[str, Any]:
    destination = Path(args.destination).expanduser().resolve()
    dm_destination = Path(args.dm_destination).expanduser().resolve()
    root = Path(args.root).expanduser().resolve()
    dm_root = Path(args.dm_root).expanduser().resolve()
    if destination in (root, dm_root) or dm_destination in (root, dm_root):
        fail("production repository paths cannot be restore destinations")
    key = require_external_key(Path(args.key_file), root=root, dm_root=dm_root)
    folder = ensure_drive_folder(args.drive_folder)
    manifest = find_manifest(str(folder["id"]), args.backup_id)
    with tempfile.TemporaryDirectory(prefix=f"restore-{args.backup_id}-", dir=args.temp_dir) as temporary:
        stage = Path(temporary)
        verification = verify_drive(str(folder["id"]), args.backup_id, stage, manifest)
        by_kind = {item["kind"]: stage / item["name"] for item in manifest["artifacts"]}
        required = {"memory_db", "projects", "queue", "gate_metrics", "dm_signal_env"}
        if set(by_kind) != required:
            fail(f"backup artifact kinds mismatch: {sorted(by_kind)}")
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "data").mkdir(parents=True, exist_ok=True)
        (destination / "logs").mkdir(parents=True, exist_ok=True)
        with gzip.open(by_kind["memory_db"], "rb") as source, (destination / "data" / "multi_agent_shogun_memory.db").open("wb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
        safe_extract(by_kind["projects"], destination)
        safe_extract(by_kind["queue"], destination)
        with gzip.open(by_kind["gate_metrics"], "rb") as source, (destination / "logs" / "gate_metrics.log").open("wb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
        env_tar_path = stage / "dm_signal_env.tar"
        openssl_decrypt(by_kind["dm_signal_env"], env_tar_path, key)
        safe_extract(env_tar_path, dm_destination)
        restored_db = destination / "data" / "multi_agent_shogun_memory.db"
        conn = sqlite3.connect(f"{restored_db.resolve().as_uri()}?mode=ro", uri=True)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()
        conn.close()
        if not integrity or integrity[0] != "ok":
            fail(f"restored memory DB integrity_check failed: {integrity}")
        projects_count = sum(1 for path in (destination / "projects").rglob("*") if path.is_file())
        queue_count = sum(1 for path in (destination / "queue").rglob("*") if path.is_file())
    result = {
        "operation": "restore",
        "backup_id": args.backup_id,
        "destination": str(destination),
        "dm_destination": str(dm_destination),
        "verification": verification,
        "integrity_check": integrity[0],
        "restored_projects_files": projects_count,
        "restored_queue_files": queue_count,
    }
    write_log(root, result)
    return result


def install_cron(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).expanduser().resolve()
    key = Path(args.key_file).expanduser().resolve()
    require_external_key(key, root=root, dm_root=Path(args.dm_root).expanduser().resolve())
    if not shutil.which("crontab"):
        fail("crontab is unavailable")
    existing_process = subprocess.run(["crontab", "-l"], text=True, capture_output=True)
    if existing_process.returncode not in (0, 1):
        fail(f"crontab -l failed ({existing_process.returncode})")
    existing = existing_process.stdout
    lines = [line for line in existing.splitlines() if MARKER not in line]
    script = root / "scripts" / "shogun_backup.py"
    command = " ".join(
        [
            "cd",
            shlex_quote(str(root)),
            "&&",
            "/usr/bin/flock -n /tmp/shogun-drive-backup.lock",
            "python3",
            shlex_quote(str(script)),
            "--backup",
            "--root",
            shlex_quote(str(root)),
            "--dm-root",
            shlex_quote(str(args.dm_root)),
            "--drive-folder",
            shlex_quote(args.drive_folder),
            "--key-file",
            shlex_quote(str(key)),
            ">>",
            shlex_quote(str(root / "logs" / "shogun_backup.log")),
            "2>&1",
        ]
    )
    line = f"{args.cron_schedule} {command} {MARKER}"
    lines.append(line)
    installed = subprocess.run(
        ["crontab", "-"], input="\n".join(lines) + "\n", text=True, capture_output=True
    )
    if installed.returncode != 0:
        fail(f"crontab install failed ({installed.returncode})")
    result = {"operation": "install_cron", "schedule": args.cron_schedule, "marker": MARKER, "registered": True}
    write_log(root, result)
    return result


def shlex_quote(value: str) -> str:
    import shlex

    return shlex.quote(value)


def write_log(root: Path, result: dict[str, Any]) -> None:
    log = root / "logs" / "shogun_backup.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"timestamp": dt.datetime.now(dt.timezone.utc).isoformat(), **result}, sort_keys=True) + "\n")


def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--backup", action="store_true")
    mode.add_argument("--restore", metavar="BACKUP_ID")
    mode.add_argument("--install-cron", action="store_true")
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--dm-root", default=str(DEFAULT_DM_ROOT))
    parser.add_argument("--dm-destination", default="/tmp/shogun-restore-dm-signal")
    parser.add_argument("--destination", default="/tmp/shogun-restore")
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--drive-folder", default=os.environ.get("SHOGUN_DRIVE_FOLDER", "shogun-offsite-backups"))
    parser.add_argument("--backup-id")
    parser.add_argument("--cron-schedule", default="0 3 * * *")
    parser.add_argument("--temp-dir", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.backup:
            result = backup(args)
        elif args.restore:
            args.backup_id = args.restore
            result = restore(args)
        else:
            result = install_cron(args)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except BackupError as exc:
        print(f"BACKUP_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
