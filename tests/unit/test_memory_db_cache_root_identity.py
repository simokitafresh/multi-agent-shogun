#!/usr/bin/env python3
"""Contract for canonical memory DB cache identity.

test_necessity: A symlinked fast-deploy import must never derive repository or
cache identity from the disposable deploy root.
"""

import importlib.util
import os
from pathlib import Path
import sqlite3


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts" / "memory_db_live_insert.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_symlink_imports_share_canonical_root_and_cache_path(tmp_path, monkeypatch):
    cache_dir = tmp_path / "cache"
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_DIR", str(cache_dir))
    monkeypatch.delenv("SHOGUN_MEMORY_DB_CACHE_PATH", raising=False)

    imported = []
    for index in (1, 2):
        deploy_scripts = tmp_path / f".deploy-report-fast-{index}" / "scripts"
        deploy_scripts.mkdir(parents=True)
        linked_module = deploy_scripts / SOURCE.name
        linked_module.symlink_to(SOURCE)
        imported.append(load_module(linked_module, f"memory_db_live_insert_deploy_{index}"))

    expected_root = str(ROOT)
    db_path = str(ROOT / "data" / "multi_agent_shogun_memory.db")
    roots = {module.REPO_ROOT for module in imported}
    cache_paths = {module.memory_db_cache_path(db_path) for module in imported}

    assert roots == {expected_root}
    assert len(cache_paths) == 1
    assert all(".deploy-report-fast" not in path for path in cache_paths)
    assert not cache_dir.exists() or list(cache_dir.iterdir()) == []


def test_normal_import_override_and_cache_read_write_contract(tmp_path, monkeypatch):
    module = load_module(SOURCE, "memory_db_live_insert_canonical")
    db_path = tmp_path / "primary.sqlite"
    with sqlite3.connect(db_path) as conn:
        conn.execute("CREATE TABLE marker(value TEXT)")
        conn.execute("INSERT INTO marker VALUES ('canonical')")

    override = tmp_path / "explicit" / "memory.sqlite"
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_PATH", str(override))
    assert module.REPO_ROOT == str(ROOT)
    assert module.memory_db_cache_path(str(db_path)) == str(override)

    published = Path(module.create_memory_db_ext4_cache(str(db_path)))
    assert published == override
    with sqlite3.connect(published) as conn:
        assert conn.execute("SELECT value FROM marker").fetchone() == ("canonical",)
