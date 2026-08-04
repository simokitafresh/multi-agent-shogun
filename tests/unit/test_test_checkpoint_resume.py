"""Contract tests for the fixed-HEAD checkpoint resume reducer."""

import hashlib
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("test_checkpoint_resume", ROOT / "scripts/test_checkpoint_resume.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
HEAD = "a" * 40


def _receipt(tmp_path, paths, failed=None, *, head=HEAD, complete=True, skip=0, cache=False, result=None):
    failed = list(failed or [])
    artifact = tmp_path / f"artifact-{len(list(tmp_path.iterdir()))}.txt"
    artifact.write_text("terminal output\n", encoding="utf-8")
    outcome = result or ("FAIL" if failed else "PASS")
    return {
        "source_head": head, "complete": complete, "result": outcome,
        "rc": 7 if outcome == "FAIL" else 0, "skip_count": skip,
        "artifact": str(artifact), "output_sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
        "test_paths": list(paths),
        "run_manifest": {"cache": {"enabled": cache}, "scope_identity": {
            "selected_file_count": len(paths), "complete": complete,
            "failed_files": failed, "failed_file_count": len(failed),
        }},
    }


def test_failed_shard_reuses_pass_files_and_retries_only_failure(tmp_path):
    """test_necessity: failed shard PASS files are not needlessly re-run."""
    manifest = {"source_head": HEAD, "test_paths": [f"tests/{i}.bats" for i in range(38)]}
    failed = ["tests/37.bats"]
    result = MODULE.reduce_checkpoint(manifest, [_receipt(tmp_path, manifest["test_paths"], failed)])
    assert result["status"] == "PASS"
    assert len(result["reused_files"]) == 37
    assert result["retry_files"] == failed
    assert result["missing_files"] == []


def test_all_pass_shards_reduce_to_empty_retry_and_no_duplicates(tmp_path):
    """test_necessity: disjoint PASS shards form an exact manifest union."""
    paths = [f"tests/{i}.bats" for i in range(4)]
    result = MODULE.reduce_checkpoint({"source_head": HEAD, "test_paths": paths}, [_receipt(tmp_path, paths[:2]), _receipt(tmp_path, paths[2:])])
    assert result["status"] == "PASS"
    assert result["retry_files"] == []
    assert result["reused_files"] == paths
    assert result["duplicate"] == []


def test_stale_incomplete_skip_and_tampered_receipts_never_reuse(tmp_path):
    """test_necessity: stale, incomplete, skipped, and tampered evidence fail closed."""
    paths = ["tests/a.bats", "tests/b.bats"]
    manifest = {"source_head": HEAD, "test_paths": paths}
    cases = [_receipt(tmp_path, paths, head="b" * 40), _receipt(tmp_path, paths, complete=False), _receipt(tmp_path, paths, skip=1)]
    tampered = _receipt(tmp_path, paths)
    Path(tampered["artifact"]).write_text("tampered\n", encoding="utf-8")
    cases.append(tampered)
    for receipt in cases[1:]:
        result = MODULE.reduce_checkpoint(manifest, [receipt])
        assert result["status"] == "BLOCK"
        assert result["reused_files"] == []
        assert result["retry_files"] == paths
    stale_result = MODULE.reduce_checkpoint(manifest, [cases[0]])
    assert stale_result["status"] == "PASS"
    assert stale_result["reused_files"] == []
    assert stale_result["retry_files"] == paths
