#!/usr/bin/env python3
"""Shared safe-read helper for frequently-rewritten queue/ operational YAML.

cmd_karo_hotfix_queue_yaml_atomicity_202607110113 follow-up.

yaml_field_set.sh publishes new content via mktemp(same dir)+mv (an atomic
rename on POSIX-compliant filesystems). On this project's WSL2 host, the
target tree lives on /mnt/c (drvfs/9p). A bounded probe confirmed
renameat2(..., RENAME_EXCHANGE) returns EINVAL on /mnt/c while the
identical call succeeds on native tmpfs, i.e. drvfs does not implement
full POSIX rename atomicity. A concurrent reader that opens the target
path at the wrong instant can observe a transient FileNotFoundError for
a very short window around the rename (no partial/corrupt content is
ever exposed this way — only a momentary absence of the path).

Any reader of a queue/ YAML file that is written via yaml_field_set.sh
(or yaml_field_set_batch) should go through safe_load_retry() instead of
a bare open()+yaml.safe_load(), so the retry is defined once, in one
place, rather than re-implemented (or, worse, forgotten) per call site.
"""
import time

import yaml


def safe_load_retry(path, retries=5, backoff=0.02):
    """Load YAML from ``path``, retrying only on a transient FileNotFoundError.

    Any other exception (yaml.YAMLError, PermissionError, other OSError, ...)
    propagates immediately on the first attempt and is never retried --
    those represent real corruption or a real problem that must not be
    masked by blind retrying.
    """
    last_exc = None
    for attempt in range(retries + 1):
        try:
            with open(path, encoding="utf-8") as fh:
                return yaml.safe_load(fh)
        except FileNotFoundError as exc:
            last_exc = exc
            if attempt < retries:
                time.sleep(backoff)
                continue
            raise
    raise last_exc  # pragma: no cover - unreachable, loop always returns or raises
