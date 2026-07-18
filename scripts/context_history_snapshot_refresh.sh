#!/usr/bin/env bash
set -euo pipefail

: "${CFC_REFRESH_REPO:?}"
: "${CFC_REFRESH_PATHS:?}"
: "${CFC_REFRESH_CONTRACT_HASH:?}"
: "${CFC_REFRESH_SOURCE_TIP:?}"
: "${CFC_REFRESH_OUTPUT:?}"
: "${CFC_REFRESH_CACHE_DIR:?}"

mkdir -p -m 700 "$CFC_REFRESH_CACHE_DIR"
exec 9>"$CFC_REFRESH_CACHE_DIR/$CFC_REFRESH_CONTRACT_HASH.lock"
flock -n 9 || exit 0

python3 - <<'PY'
import hashlib, json, os, subprocess, tempfile

repo = os.environ["CFC_REFRESH_REPO"]
revision = os.environ.get("CFC_REFRESH_REVISION") or None
since = os.environ.get("CFC_REFRESH_SINCE") or None
pathspecs = json.loads(os.environ["CFC_REFRESH_PATHS"])
output = os.environ["CFC_REFRESH_OUTPUT"]
cmd = ["git", "-C", repo, "log", "--pretty=format:__CFC_G__%x00%h%x00%s", "--name-only"]
if revision:
    cmd.append(revision)
if since:
    from datetime import date, timedelta
    cmd.append(f"--since={(date.fromisoformat(since) + timedelta(days=1)).isoformat()} 00:00:00")
if pathspecs:
    cmd.extend(["--", *pathspecs])
result = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=float(os.environ.get("CFC_GIT_RETRY_TIMEOUT", "60")))
commits, current_hash, current_subject, paths = [], "", "", []
def flush():
    if current_subject.strip():
        commits.append([current_hash, current_subject.strip(), list(paths)])
for line in result.stdout.splitlines():
    if line.startswith("__CFC_G__\x00"):
        flush()
        _, current_hash, current_subject = line.split("\x00", 2)
        paths = []
    elif line.strip():
        paths.append(line.strip())
flush()
canonical = json.dumps(commits, sort_keys=True, separators=(",", ":"))
payload = {
    "schema": "cfc-history-v2",
    "contract_hash": os.environ["CFC_REFRESH_CONTRACT_HASH"],
    "source_tip": os.environ["CFC_REFRESH_SOURCE_TIP"],
    "output_sha256": hashlib.sha256(canonical.encode()).hexdigest(),
    "commits": commits,
}
fd, temp_path = tempfile.mkstemp(prefix=os.path.basename(output) + ".", suffix=".tmp", dir=os.path.dirname(output))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(payload, stream, sort_keys=True)
        stream.flush(); os.fsync(stream.fileno())
    os.replace(temp_path, output)
finally:
    try: os.unlink(temp_path)
    except FileNotFoundError: pass
PY
