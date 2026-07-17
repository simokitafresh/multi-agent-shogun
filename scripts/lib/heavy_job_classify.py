#!/usr/bin/env python3
"""Heavy test-job classifier — single SSOT for admission-gating decisions.

cmd_karo_hotfix_heavy_job_admission_202607121348: 同一8コアWSL2ホスト上でbats全量/
pytest全量/DM-Signal golden regressionが無調停で並走し、host CPUオーバーサブスク
リプション(強制プリエンプション)でwall時間を増幅する構造バグを根治する。

分類はargv位置ベース(部分文字列一致ではない)。command文字列をトークン化し、
&&/;/||/| で区切ったsegmentごとに、各segmentの先頭コマンド(basename)と後続の
非オプション引数(=対象ファイル/ディレクトリ)の"数・種類"だけで重量/軽量を判定する。
segment内のどこかに偶然 "bats" や "pytest" という文字列が現れても(例: echoの引数、
commit messageの説明文)、コマンド位置(segment[0])でなければ一切マッチしない。

判定対象(重量 = admission wrapper経由を要求):
  - bats: 対象引数が0個(標準入力)、複数個、または tests/unit ディレクトリ全体、
    もしくはワイルドカードを含む場合。単一の具体的な .bats ファイル1個のみは軽量。
  - pytest / python -m pytest: 対象引数が0個(カレント全体)、複数個、または
    ディレクトリ相当のパス(::が無く拡張子.pyでもない)を含む場合。単一の
    ファイル::テスト関数、または単一の.pyファイル1個のみは軽量。
  - python/python3 <script>: script のbasenameが golden / regression_check /
    fullrecalculate のいずれかを含む場合(DM-Signal重量ワンショット系)。
  - bash run_tests.sh (basename一致): 常に重量(内部で--jobs 8をかけるため)。

出力: 標準出力に "heavy" / "light" / "malformed" の1行のみ。
引用符不整合などshellとして解析不能なcommandは "malformed"。重量jobとして
誤案内せず、呼び出し側が構文修正を要求しつつfail-closedにできるよう区別する。
"""

import os
import re
import sys
import csv
import hashlib
import json
import tempfile
import fcntl
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from shell_command_segments import segment_tokens


def _segments(command):
    return segment_tokens(command)


_BATS_OPTIONS_WITH_VALUE = {
    "-f",
    "--filter",
    "--filter-status",
    "--formatter",
    "--gather-test-outputs-in",
    "-j",
    "--jobs",
    "--line-reference-format",
    "-o",
    "--output",
    "--report-formatter",
    "--setup-suite-file",
}

_INFO_ONLY_OPTIONS = {"-h", "--help", "-v", "--version"}
_BATS_NON_EXECUTION_OPTIONS = _INFO_ONLY_OPTIONS | {"-c", "--count"}


def _bats_targets(args):
    targets = []
    skip_value = False
    for arg in args:
        if skip_value:
            skip_value = False
            continue
        option = arg.split("=", 1)[0]
        if option in _BATS_OPTIONS_WITH_VALUE:
            skip_value = "=" not in arg
            continue
        if arg.startswith("-"):
            continue
        targets.append(arg)
    return targets


_TIMED_HEAVY_SECONDS = float(os.environ.get("HEAVY_JOB_TIMED_THRESHOLD_SECONDS", "10"))
_LEDGER_MAX_AGE_SECONDS = int(os.environ.get("HEAVY_JOB_LEDGER_MAX_AGE_SECONDS", "604800"))
_INDEX_SCHEMA = 1


def _file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ledger_identity(ledger):
    stat = ledger.stat()
    return {"path": str(ledger.resolve()), "mtime_ns": stat.st_mtime_ns, "size": stat.st_size}


def _index_paths(ledger):
    cache_root = Path(
        os.environ.get(
            "HEAVY_JOB_INDEX_CACHE_DIR",
            Path(tempfile.gettempdir()) / f"shogun-heavy-timing-index-{os.getuid()}",
        )
    )
    cache_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = hashlib.sha256(str(ledger.resolve()).encode()).hexdigest()
    return cache_root / f"{key}.json", cache_root / f"{key}.lock"


def _shell_stat_identity(path):
    return subprocess.check_output(
        ("stat", "-c", "%y:%s", str(path)), text=True, stderr=subprocess.DEVNULL
    ).strip()


def _publish_decision_cache(command, result):
    """Publish a shell-readable fast-path only for one concrete bats file."""
    segs = _segments(command)
    if not segs or len(segs) != 1 or os.path.basename(segs[0][0]) != "bats":
        return
    targets = _bats_targets(segs[0][1:])
    if len(targets) != 1 or "*" in targets[0] or targets[0].endswith("/"):
        return
    root = Path(os.environ.get("SHOGUN_REPO_ROOT", Path(__file__).resolve().parents[2]))
    target = Path(targets[0])
    if not target.is_absolute():
        target = Path.cwd() / target
    ledger = Path(os.environ.get("TEST_TIMING_LEDGER", root / "logs/test_timing_ledger.tsv"))
    if not target.is_file() or not ledger.is_file():
        return
    cache_path, _ = _index_paths(ledger)
    checksum = subprocess.check_output(("cksum",), input=command, text=True).split()
    decision_path = cache_path.parent / f"decision-{checksum[0]}-{checksum[1]}.tsv"
    payload = "\t".join(
        (
            result,
            str(ledger.resolve()),
            _shell_stat_identity(ledger),
            str(target.resolve()),
            _shell_stat_identity(target),
            command,
        )
    ) + "\n"
    fd, tmp_name = tempfile.mkstemp(prefix=decision_path.name, dir=decision_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, decision_path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def _read_index(cache_path, identity):
    try:
        with cache_path.open(encoding="utf-8") as handle:
            data = json.load(handle)
        if (
            data.get("schema") != _INDEX_SCHEMA
            or data.get("ledger") != identity
            or not isinstance(data.get("files"), dict)
        ):
            return None
        return data["files"]
    except (OSError, ValueError, TypeError):
        return None


def _build_index(ledger, root):
    files = {}
    with ledger.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            try:
                tags = dict(
                    part.split("=", 1)
                    for part in row["resource_tags"].split(";")
                    if "=" in part
                )
                if not (
                    row["runner"] == "bats"
                    and row["status"] == "pass"
                    and row["skip_count"] == "0"
                    and row["cache_hit"] == "0"
                    and tags.get("jobs") == "1"
                ):
                    continue
                row_path = Path(row["test_file"])
                if not row_path.is_absolute():
                    row_path = root / row_path
                key = str(row_path.resolve())
                measured = datetime.fromisoformat(row["measured_at"].replace("Z", "+00:00"))
                old = files.get(key)
                # Append order is the writer's tie-breaker when two rows share
                # one-second measured_at precision; the later row is newest.
                if old is None or measured.isoformat() >= old["measured_at"]:
                    files[key] = {
                        "measured_at": measured.isoformat(),
                        "wall_sec": float(row["wall_sec"]),
                        "source_fingerprint": row["source_fingerprint"],
                    }
            except (KeyError, ValueError, OSError):
                continue
    return files


def _timing_index(ledger, root):
    """Return ext4-backed O(1) index; rebuild atomically after ledger mutation."""
    identity = _ledger_identity(ledger)
    cache_path, lock_path = _index_paths(ledger)
    cached = _read_index(cache_path, identity)
    if cached is not None:
        return cached
    with lock_path.open("a+") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        identity = _ledger_identity(ledger)
        cached = _read_index(cache_path, identity)
        if cached is not None:
            return cached
        files = _build_index(ledger, root)
        payload = {"schema": _INDEX_SCHEMA, "ledger": identity, "files": files}
        fd, tmp_name = tempfile.mkstemp(prefix=cache_path.name, dir=cache_path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp_name, cache_path)
        finally:
            try:
                os.unlink(tmp_name)
            except FileNotFoundError:
                pass
        return files


def _trusted_bats_wall_seconds(target):
    """Return latest trustworthy serial timing, or None (fail-closed boundary)."""
    root = Path(os.environ.get("SHOGUN_REPO_ROOT", Path(__file__).resolve().parents[2]))
    target_path = Path(target)
    if not target_path.is_absolute():
        target_path = Path.cwd() / target_path
    target_path = target_path.resolve()
    ledger = Path(os.environ.get("TEST_TIMING_LEDGER", root / "logs/test_timing_ledger.tsv"))
    if not target_path.is_file() or not ledger.is_file():
        return None
    try:
        row = _timing_index(ledger, root).get(str(target_path))
        if row is None or row["source_fingerprint"] != _file_sha256(target_path):
            return None
        measured = datetime.fromisoformat(row["measured_at"])
        if (datetime.now(timezone.utc) - measured).total_seconds() > _LEDGER_MAX_AGE_SECONDS:
            return None
        return float(row["wall_sec"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _is_bats_heavy(args):
    # These modes never execute a test body, even when passed a directory or
    # many files.  Admission protects host CPU from concurrent test execution;
    # making metadata/count probes take the host-wide lock is a false positive.
    if any(arg.split("=", 1)[0] in _BATS_NON_EXECUTION_OPTIONS for arg in args):
        return False
    file_args = _bats_targets(args)
    # Metadata/help queries do not execute tests.  Treating `bats --version`
    # like a stdin/full-suite invocation makes a harmless capability probe
    # require the host-wide admission lock (GA-270 false positive).
    if len(file_args) != 1:
        return True
    target = file_args[0]
    if "*" in target:
        return True
    stripped = target.rstrip("/")
    if (
        stripped.endswith("tests/unit")
        or stripped.endswith("tests/e2e")
        or stripped.endswith("tests/integration")
        or stripped == "tests"
    ):
        return True
    if target.endswith("/"):
        return True
    # A single file is light only with a current, content-identical, successful
    # serial measurement below the threshold. Missing/stale/mismatched evidence
    # fails closed so an unmeasured 29.84s file cannot bypass admission again.
    wall_seconds = _trusted_bats_wall_seconds(target)
    return wall_seconds is None or wall_seconds > _TIMED_HEAVY_SECONDS


_PYTEST_HEAVY_NAME_RE = re.compile(r"(^|/)tests?($|/)")


def _is_pytest_heavy(targets):
    if not targets:
        return True
    if len(targets) > 1:
        return True
    t = targets[0]
    if "::" in t:
        return False
    if t.endswith(".py"):
        return False
    # bare directory-looking path (no extension, no ::)
    return True


def _is_info_only(args):
    return not [a for a in args if not a.startswith("-")] and any(
        a.split("=", 1)[0] in _INFO_ONLY_OPTIONS for a in args
    )


_ONESHOT_HEAVY_NAME_RE = re.compile(
    r"golden|regression_check|fullrecalculate", re.IGNORECASE
)


def classify(command):
    segs = _segments(command)
    if segs is None:
        return "malformed"
    for seg in segs:
        if not seg:
            continue
        prog = os.path.basename(seg[0])
        args = seg[1:]

        if prog == "bats":
            if _is_bats_heavy(args):
                return "heavy"
            continue

        if prog == "pytest":
            if _is_info_only(args):
                continue
            targets = [a for a in args if not a.startswith("-")]
            if _is_pytest_heavy(targets):
                return "heavy"
            continue

        if (
            prog in ("python", "python3")
            and len(args) >= 2
            and args[0] == "-m"
            and args[1] == "pytest"
        ):
            if _is_info_only(args[2:]):
                continue
            targets = [a for a in args[2:] if not a.startswith("-")]
            if _is_pytest_heavy(targets):
                return "heavy"
            continue

        if prog in ("python", "python3"):
            positional = [a for a in args if not a.startswith("-")]
            if positional:
                script_base = os.path.basename(positional[0])
                if _ONESHOT_HEAVY_NAME_RE.search(script_base):
                    return "heavy"
            continue

        if prog == "bash" or prog.endswith(".sh"):
            script_args = args if prog == "bash" else seg
            for a in script_args:
                if os.path.basename(a) == "run_tests.sh":
                    return "heavy"
            continue

    return "light"


def main():
    command = os.environ.get("HEAVY_JOB_COMMAND")
    if command is None:
        if len(sys.argv) > 1:
            command = sys.argv[1]
        else:
            command = sys.stdin.read()
    result = classify(command)
    try:
        _publish_decision_cache(command, result)
    except OSError:
        pass
    print(result)


if __name__ == "__main__":
    main()
