#!/usr/bin/env bash
# Shared retry policy for inbox_watcher and ninja_monitor.
: "${INBOX_RENUDGE_BACKOFF_SEC:=600}"
: "${INBOX_RENUDGE_MAX_ATTEMPTS:=5}"

