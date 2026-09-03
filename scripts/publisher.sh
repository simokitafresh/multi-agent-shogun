#!/usr/bin/env bash
# publisher.sh — 単一 publisher 化 U3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PUBLISHER_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}"

resolve_state_dir() {
    local real_state real_root
    mkdir -p "$STATE_DIR"
    real_state="$(cd "$STATE_DIR" && pwd)"
    real_root="$(cd "$REPO_ROOT" && pwd)"
    case "$real_state" in
        /tmp|/tmp/*) echo "publisher: STATE_DIR under /tmp is not persistent: $real_state" >&2; return 2 ;;
        "$real_root"|"$real_root"/*) echo "publisher: STATE_DIR must be outside repository root: $real_state" >&2; return 2 ;;
    esac
    STATE_DIR="$real_state"
}

resolve_state_dir
QUEUE_ROOT="$STATE_DIR/publish_queue"
RC_DIR="$QUEUE_ROOT/rc"
DONE_DIR="$QUEUE_ROOT/done"
PID_FILE="$QUEUE_ROOT/publisher.pid"
EVENT_LIB="$SCRIPT_DIR/lib/publisher_event.sh"
QUEUE_LIB="$SCRIPT_DIR/publisher_queue.sh"
ROOT_DRAIN_LIB="$SCRIPT_DIR/lib/publisher_root_drain.sh"
INBOX_WRITER="${PUBLISHER_INBOX_WRITER:-$SCRIPT_DIR/inbox_write.sh}"
source "$ROOT_DRAIN_LIB"
mkdir -p "$QUEUE_ROOT" "$RC_DIR" "$DONE_DIR"

request_field() {
    local request="$1" field="$2"
    python3 - "$request" "$field" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = data.get(sys.argv[2])
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif value is not None:
    print(str(value))
PY
}

manifest_field() {
    local manifest="$1" field="$2"
    python3 - "$manifest" "$field" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = data.get(sys.argv[2])
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif value is not None:
    print(str(value))
PY
}

request_id() { request_field "$1" task_id | head -n1; }

request_publication_identities() {
    local request="$1"
    python3 - "$request" <<'PY'
import re
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
if not isinstance(data, dict):
    raise SystemExit(0)

# A missing artifact can be safely retired only when a canonical identity from
# the request is already reachable from the fetched origin/main.  Keep the
# field name in the output so the event records which identity justified the
# idempotent decision.  Do not infer identities from prose or filenames.
for field in ("published_sha", "report_commit", "commit_hash"):
    value = str(data.get(field) or "").strip()
    if re.fullmatch(r"[0-9a-fA-F]{40}", value):
        print(f"{field}\t{value.lower()}")
PY
}

tree_blob() {
    local tree="$1" path="$2" blob
    blob="$(git -C "$REPO_ROOT" ls-tree -r "$tree" -- "$path" | awk 'NR == 1 { print $3; exit }')"
    printf '%s\n' "${blob:-ABSENT}"
}

notify_karo() {
    local message="$1" action="${2:-task_assigned}"
    if ! bash "$INBOX_WRITER" karo "$message" "$action" publisher notify_karo; then
        echo "publisher: failed to notify karo: $message" >&2
        return 1
    fi
}

event() {
    if ! bash "$EVENT_LIB" append "$1" "$2" "$3" "$4"; then
        echo "publisher: failed to append event kind=$1 request=$2" >&2
        return 1
    fi
}

move_to_rc() { mv "$1" "$RC_DIR/$(basename "$1")"; }
move_to_done() { mv "$1" "$DONE_DIR/$(basename "$1")"; }
requeue_request() { mv "$1" "$QUEUE_ROOT/$(basename "$1")"; }

increment_publish_attempts() {
    local request="$1" current next
    current="$(request_field "$request" publish_attempts)"
    current="${current:-0}"
    [[ "$current" =~ ^[0-9]+$ ]] || { echo "publisher: invalid publish_attempts=$current" >&2; return 2; }
    next=$((current + 1))
    bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$request" root publish_attempts "$next"
    printf '%s\n' "$next"
}

cleanup_isolated() {
    local isolated="${1:-}"
    [ -n "$isolated" ] && [ -d "$isolated" ] || return 0
    case "$isolated" in
        "$REPO_ROOT/.git/publisher-isolated."*) find "$isolated" -depth -delete ;;
        *) echo "publisher: refusing to clean unexpected isolated path: $isolated" >&2; return 1 ;;
    esac
}

cleanup_ledger_stage() {
    local stage="${1:-}"
    [ -n "$stage" ] && [ -d "$stage" ] || return 0
    case "$stage" in
        "$REPO_ROOT/.git/publisher-ledger-stage."*) find "$stage" -depth -delete ;;
        *) echo "publisher: refusing to clean unexpected ledger stage: $stage" >&2; return 1 ;;
    esac
}

create_isolated_clone() {
    local tip="$1" origin_url reference_repo isolated=""
    origin_url="$(git -C "$REPO_ROOT" remote get-url origin)"
    reference_repo="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)"
    case "$reference_repo" in
        /*) ;;
        *) reference_repo="$REPO_ROOT/$reference_repo" ;;
    esac
    isolated="$(mktemp -d "$REPO_ROOT/.git/publisher-isolated.XXXXXX")"
    if ! git clone --no-checkout --reference "$reference_repo" "$REPO_ROOT" "$isolated"; then
        cleanup_isolated "$isolated"
        return 1
    fi
    if ! git -C "$isolated" remote set-url origin "$origin_url"; then
        cleanup_isolated "$isolated"
        return 1
    fi
    if ! timeout 120 git -C "$isolated" fetch origin; then
        cleanup_isolated "$isolated"
        return 1
    fi
    if ! git -C "$isolated" checkout --detach "$tip"; then
        cleanup_isolated "$isolated"
        return 1
    fi
    ISOLATED_CLONE="$isolated"
}

root_has_untracked_collision() {
    local root="$1" tip="$2" status_file diff_file
    status_file="$(mktemp)"; diff_file="$(mktemp)"
    git -C "$root" status --porcelain -uall > "$status_file"
    git -C "$root" diff --name-only HEAD "$tip" > "$diff_file"
    python3 - "$status_file" "$diff_file" <<'PY'
import sys
untracked = {line[3:].rstrip("\n") for line in open(sys.argv[1], encoding="utf-8") if line.startswith("?? ")}
changed = {line.rstrip("\n") for line in open(sys.argv[2], encoding="utf-8") if line.strip()}
print("1" if untracked & changed else "0")
PY
    rm -f "$status_file" "$diff_file"
}

tracked_dirty_count() { git -C "$1" status --porcelain -uno | awk 'NF { n++ } END { print n + 0 }'; }
tracked_dirty_paths() { git -C "$1" status --porcelain -uno | sed 's/^.. //' | sort -u | paste -sd, -; }

publisher_timestamp() { TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S%:z'; }

publisher_timestamp_stream() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s %s\n' "$(publisher_timestamp)" "$line"
    done
}

root_sync_write_blob() {
    local root="$1" tree="$2" path="$3" destination="$4"
    if git -C "$root" cat-file -e "$tree:$path" 2>/dev/null; then
        git -C "$root" show "$tree:$path" > "$destination"
    else
        : > "$destination"
    fi
}

root_sync_driver_command() {
    local driver="$1" base_file="$2" ours_file="$3" theirs_file="$4"
    python3 - "$driver" "$base_file" "$ours_file" "$theirs_file" <<'PY'
import shlex
import sys

driver, base, ours, theirs = sys.argv[1:]
for marker, value in (("%O", base), ("%A", ours), ("%B", theirs)):
    driver = driver.replace(marker, shlex.quote(value))
print(driver)
PY
}

root_sync_attr_driver() {
    local root="$1" path="$2" attr driver
    attr="$(git -C "$root" check-attr merge -- "$path" 2>/dev/null | sed 's/^.*: //')"
    case "$attr" in
        ""|unspecified|unset) return 1 ;;
    esac
    driver="$(git -C "$root" config --get "merge.${attr}.driver" 2>/dev/null || true)"
    [ -n "$driver" ] || return 1
    printf '%s\n' "$attr"
}

# Merge only tracked dirty paths that overlap the incoming publication. The
# shared checkout is never merged/rebased/cherry-picked: drivers operate on
# explicit blobs, then the ref and index advance independently.
sync_root() {
    local root="$1" tip="$2" dirty collision head changed_path dirty_path overlap_path
    local -a changed_paths=() dirty_paths=() overlap_paths=() merge_results=()
    local -A dirty_set=()
    SYNC_ROOT_SKIP_REASON=""
    SYNC_ROOT_SKIP_PATHS=""
    head="$(git -C "$root" rev-parse HEAD)"
    dirty="$(tracked_dirty_count "$root")"
    collision="$(root_has_untracked_collision "$root" "$tip")"
    if [ "$collision" -ne 0 ]; then
        SYNC_ROOT_SKIP_REASON="untracked_collision"
        SYNC_ROOT_SKIP_PATHS="$(tracked_dirty_paths "$root")"
        echo "publisher: root sync BLOCK tracked_dirty=$dirty untracked_collision=$collision paths=$SYNC_ROOT_SKIP_PATHS" >&2
        return 32
    fi
    git -C "$root" merge-base --is-ancestor "$head" "$tip" || {
        SYNC_ROOT_SKIP_REASON="not_descendant"
        SYNC_ROOT_SKIP_PATHS="$(git -C "$root" diff --name-only --no-renames "$head" "$tip" | sort -u | paste -sd, -)"
        echo "publisher: root sync BLOCK not_descendant head=$head tip=$tip" >&2
        return 32
    }

    mapfile -t changed_paths < <(git -C "$root" diff --name-only --no-renames "$head" "$tip")
    while IFS= read -r dirty_path; do
        [ -n "$dirty_path" ] || continue
        dirty_paths+=("$dirty_path")
        dirty_set["$dirty_path"]=1
    done < <(git -C "$root" status --porcelain=v1 -uno | sed 's/^.. //' | sort -u)
    for changed_path in "${changed_paths[@]}"; do
        [ -n "$changed_path" ] || continue
        if [ -n "${dirty_set[$changed_path]+yes}" ]; then
            overlap_paths+=("$changed_path")
        fi
    done

    if [ "${#overlap_paths[@]}" -gt 0 ]; then
        local merge_root base_file ours_file theirs_file result_file attr driver command
        merge_root="$(mktemp -d "$root/.git/publisher-root-sync.XXXXXX")"
        for overlap_path in "${overlap_paths[@]}"; do
            attr="$(root_sync_attr_driver "$root" "$overlap_path" || true)"
            driver=""
            [ -n "$attr" ] && driver="$(git -C "$root" config --get "merge.${attr}.driver" 2>/dev/null || true)"
            if [ -z "$driver" ]; then
                SYNC_ROOT_SKIP_REASON="no_driver"
                SYNC_ROOT_SKIP_PATHS="$(IFS=,; echo "${overlap_paths[*]}")"
                rm -rf -- "$merge_root"
                echo "publisher: root sync BLOCK no_driver paths=$SYNC_ROOT_SKIP_PATHS" >&2
                return 32
            fi
            base_file="$merge_root/base.${#merge_results[@]}"
            ours_file="$merge_root/ours.${#merge_results[@]}"
            theirs_file="$merge_root/theirs.${#merge_results[@]}"
            result_file="$merge_root/result.${#merge_results[@]}"
            root_sync_write_blob "$root" "$head" "$overlap_path" "$base_file"
            if [ -e "$root/$overlap_path" ] || [ -L "$root/$overlap_path" ]; then
                cp -a -- "$root/$overlap_path" "$ours_file"
            else
                : > "$ours_file"
            fi
            root_sync_write_blob "$root" "$tip" "$overlap_path" "$theirs_file"
            command="$(root_sync_driver_command "$driver" "$base_file" "$ours_file" "$theirs_file")"
            if ! (cd "$root" && bash -c "$command"); then
                SYNC_ROOT_SKIP_REASON="driver_failed"
                SYNC_ROOT_SKIP_PATHS="$overlap_path"
                rm -rf -- "$merge_root"
                echo "publisher: root sync BLOCK driver_failed path=$overlap_path driver=$attr" >&2
                return 32
            fi
            cp -a -- "$ours_file" "$result_file"
            merge_results+=("$overlap_path|$result_file")
        done

        # update-ref's third argument is a compare-and-swap on the ref's current
        # value. A concurrent writer (another publisher pass, a direct commit in
        # the shared root) can advance HEAD between the "$head" capture above and
        # this call; the CAS then fails without touching the ref. Attempt it
        # before mutating the index/worktree below, so a lost race leaves every
        # local edit (merged results included) exactly as found instead of
        # applying an update the ref never actually advanced to. Pre-fix, this
        # 4th path fell through the reason-less final check further down and was
        # reported as reason=unknown (38/39 current-format root_sync_skipped
        # events, 2026-09-03 06:01-07:34). Classify it explicitly instead: a
        # protective skip, symmetric with no_driver/driver_failed above.
        if ! git -C "$root" update-ref HEAD "$tip" "$head"; then
            SYNC_ROOT_SKIP_REASON="head_moved"
            SYNC_ROOT_SKIP_PATHS="$(IFS=,; echo "${overlap_paths[*]}")"
            rm -rf -- "$merge_root"
            echo "publisher: root sync BLOCK head_moved head=$head tip=$tip paths=$SYNC_ROOT_SKIP_PATHS" >&2
            return 32
        fi
        # Update the index without touching the worktree.  Dirty paths are
        # intentionally left in place; clean paths changed by the tip are
        # checked out explicitly below, avoiding any operation that can erase
        # unrelated local edits.
        git -C "$root" read-tree "$tip"
        for changed_path in "${changed_paths[@]}"; do
            [ -n "${dirty_set[$changed_path]+yes}" ] && continue
            if git -C "$root" cat-file -e "$tip:$changed_path" 2>/dev/null; then
                git -C "$root" checkout-index -f -- "$changed_path"
            else
                rm -f -- "$root/$changed_path"
            fi
        done
        local result_path result_source merge_result
        for merge_result in "${merge_results[@]}"; do
            result_path="${merge_result%%|*}"
            result_source="${merge_result#*|}"
            rm -f -- "$root/$result_path"
            cp -a -- "$result_source" "$root/$result_path"
        done
        rm -rf -- "$merge_root"
    else
        if ! git -C "$root" update-ref HEAD "$tip" "$head"; then
            SYNC_ROOT_SKIP_REASON="head_moved"
            SYNC_ROOT_SKIP_PATHS="$(tracked_dirty_paths "$root")"
            echo "publisher: root sync BLOCK head_moved head=$head tip=$tip paths=$SYNC_ROOT_SKIP_PATHS" >&2
            return 32
        fi
        git -C "$root" read-tree -u -m "$tip"
    fi
    if [ "$(git -C "$root" rev-parse HEAD)" != "$tip" ]; then
        # update-ref reported success above, so HEAD must already be "$tip".
        # This is an unreachable-in-practice safety net; still name it so no
        # branch of sync_root ever depends on the caller's "unknown" fallback.
        SYNC_ROOT_SKIP_REASON="postsync_verify_mismatch"
        SYNC_ROOT_SKIP_PATHS="$(tracked_dirty_paths "$root")"
        echo "publisher: root sync BLOCK postsync_verify_mismatch head=$head tip=$tip actual=$(git -C "$root" rev-parse HEAD)" >&2
        return 32
    fi
    return 0
}

process_request() {
    local request="$1" mode="$2" task artifact manifest base source_tree tip isolated
    local artifact_missing=0 identity_field identity
    task="$(request_id "$request")"
    artifact="$STATE_DIR/publish_queue/artifacts/$task"
    manifest="$artifact/manifest.yaml"
    if [ ! -f "$manifest" ] || [ ! -f "$artifact/patch.diff" ]; then
        artifact_missing=1
    fi
    if ! timeout 120 git -C "$REPO_ROOT" fetch origin; then
        echo "publisher: fetch failed task=$task" >&2
        return 31
    fi
    if ! tip="$(git -C "$REPO_ROOT" rev-parse origin/main)"; then
        echo "publisher: origin/main unavailable after fetch task=$task" >&2
        return 31
    fi
    if [ "$artifact_missing" -eq 1 ]; then
        while IFS=$'\t' read -r identity_field identity; do
            [ -n "$identity" ] || continue
            if git -C "$REPO_ROOT" cat-file -e "$identity^{commit}" 2>/dev/null \
                && git -C "$REPO_ROOT" merge-base --is-ancestor "$identity" "$tip" 2>/dev/null; then
                event already_published "$task" 0 "identity=${identity_field}:$identity origin_tip=$tip artifact=missing"
                move_to_done "$request"
                return 0
            fi
        done < <(request_publication_identities "$request")
        echo "publisher: missing artifact task=$task" >&2
        return 31
    fi
    base="$(manifest_field "$manifest" base | head -n1)"
    [ -n "$base" ] || { echo "publisher: manifest base missing task=$task" >&2; return 31; }
    source_tree="$(manifest_field "$manifest" source_tree | head -n1)"
    [ -n "$source_tree" ] || { echo "publisher: manifest source_tree missing task=$task" >&2; return 31; }

    local path tip_blob base_blob expected_blob tip_differs=0 already_published=1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if git -C "$REPO_ROOT" cat-file -e "$tip:$path"; then
            tip_blob="$(git -C "$REPO_ROOT" rev-parse "$tip:$path")"
        else
            tip_blob=ABSENT
        fi
        if git -C "$REPO_ROOT" cat-file -e "$base:$path"; then
            base_blob="$(git -C "$REPO_ROOT" rev-parse "$base:$path")"
        else
            base_blob=ABSENT
        fi
        if [ "$tip_blob" != "$base_blob" ]; then
            tip_differs=1
            expected_blob="$(tree_blob "$source_tree" "$path")"
            if [ "$tip_blob" = "$expected_blob" ]; then
                tip_differs=1
            else
                event c2a_rc "$task" 1 "base_blob_mismatch path=$path"
                notify_karo "publisher C2a RC task=$task path=$path tip=$tip base=$base"
                move_to_rc "$request"
                return 30
            fi
        fi
    done < <(manifest_field "$manifest" paths)

    if [ "$tip_differs" -eq 1 ] && [ "$already_published" -eq 1 ]; then
        event already_published "$task" 0 "published_sha=$tip"
        move_to_done "$request"
        return 0
    fi

    create_isolated_clone "$tip"
    isolated="$ISOLATED_CLONE"
    trap 'cleanup_isolated "${isolated:-}"' RETURN
    if ! git -C "$isolated" apply --3way --binary --whitespace=nowarn "$artifact/patch.diff"; then
        event git_fail "$task" 30 "restore_threeway_conflict=1"
        notify_karo "publisher restore RC task=$task conflict=1"
        move_to_rc "$request"
        return 30
    fi
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git -C "$isolated" add -- "$path"
    done < <(manifest_field "$manifest" paths)
    local tree published_sha
    tree="$(git -C "$isolated" write-tree)"
    published_sha="$(printf 'publisher: task=%s\n\nPublished-By: publisher\n' "$task" | git -C "$isolated" -c user.name=single-publisher -c user.email=publisher@localhost commit-tree "$tree" -p "$tip")"
    if [ "$mode" = dry-run ]; then
        event dry_run_publish "$task" 0 "published_sha=$published_sha origin_update=0"
    else
        timeout 120 git -C "$isolated" push origin "$published_sha:refs/heads/main"
        event published "$task" 0 "published_sha=$published_sha"
        timeout 120 git -C "$REPO_ROOT" fetch origin || true
        # Root sync is a convenience for the shared checkout, not part of the publication. A dirty
        # root (rc=32) must not abort after the push already landed, or the request stays in
        # dequeued/ with no done receipt and no event (cmd_4465 06:47, root tracked_dirty>0).
        if ! sync_root "$REPO_ROOT" origin/main; then
            event root_sync_skipped "$task" 0 "published_sha=$published_sha reason=${SYNC_ROOT_SKIP_REASON:-unknown} paths=${SYNC_ROOT_SKIP_PATHS:-$(tracked_dirty_paths "$REPO_ROOT")}"
        fi
    fi
    cleanup_isolated "$isolated"; trap - RETURN
    move_to_done "$request"
}

ledger_source_in_isolated() {
    local operation="$1" isolated="$2"
    PUBLISHER_REPO_ROOT="$REPO_ROOT" PUBLISHER_ISOLATED="$isolated" \
        PUBLISHER_OPERATION="$operation" python3 - <<'PY'
import json, os
from pathlib import Path

data = json.load(open(os.environ["PUBLISHER_OPERATION"], encoding="utf-8"))
source = str(data.get("source_file", ""))
if not source:
    raise SystemExit("publisher: ledger operation source_file missing")
repo = Path(os.environ["PUBLISHER_REPO_ROOT"]).resolve()
source_path = Path(source)
if not source_path.is_absolute():
    source_path = repo / source_path
try:
    relative = source_path.resolve(strict=False).relative_to(repo)
except ValueError:
    raise SystemExit(f"publisher: ledger source outside publisher root: {source}")
print(Path(os.environ["PUBLISHER_ISOLATED"]) / relative)
PY
}

ledger_directory() {
    case "$1" in
        insights|lessons|lessons_yaml|review_log|bulletin|workarounds|semantic_index) printf '%s/ledger_inbox/%s\n' "$STATE_DIR" "$1" ;;
        *) return 1 ;;
    esac
}

ledger_operations() {
    local dir
    for dir in insights lessons lessons_yaml review_log bulletin workarounds semantic_index; do
        [ -d "$STATE_DIR/ledger_inbox/$dir" ] || continue
        find "$STATE_DIR/ledger_inbox/$dir" -mindepth 1 -maxdepth 1 -type f -name '*.yaml' \
            -printf '%f\t%p\n'
    done | LC_ALL=C sort -k1,1 -k2,2 | cut -f2-
}

move_ledger_to() {
    local operation="$1" destination_dir="$2" destination
    mkdir -p "$destination_dir"
    destination="$destination_dir/$(basename "$operation")"
    [ ! -e "$destination" ] || destination="$destination.$$"
    mv -- "$operation" "$destination"
}

process_ledger_batch() {
    local -a operations=() ledgers=() applied_operations=() skipped_operations=()
    local operation ledger isolated="" stage_root="" tip tree published_sha
    while IFS= read -r operation; do
        [ -n "$operation" ] || continue
        operations+=("$operation")
        ledger="$(basename "$(dirname "$operation")")"
        case " ${ledgers[*]} " in *" $ledger "*) ;; *) ledgers+=("$ledger") ;; esac
    done < <(ledger_operations)
    [ "${#operations[@]}" -gt 0 ] || return 0

    timeout 120 git -C "$REPO_ROOT" fetch origin
    tip="$(git -C "$REPO_ROOT" rev-parse origin/main)"
    create_isolated_clone "$tip"
    isolated="$ISOLATED_CLONE"
    stage_root="$(mktemp -d "$REPO_ROOT/.git/publisher-ledger-stage.XXXXXX")"
    trap 'cleanup_isolated "${isolated:-}"; cleanup_ledger_stage "${stage_root:-}"' RETURN

    local index=0 source_file staged_operation
    for operation in "${operations[@]}"; do
        index=$((index + 1))
        ledger="$(basename "$(dirname "$operation")")"
        staged_operation="$stage_root/${index}_${ledger}_$(basename "$operation")"
        cp -- "$operation" "$staged_operation"
        if ! source_file="$(ledger_source_in_isolated "$staged_operation" "$isolated")"; then
            # e.g. an op captured from a fixture path under /tmp: park it, keep the batch moving.
            move_ledger_to "$operation" "$(ledger_directory "$ledger")/rc"
            event ledger ledger_batch 1 "failed_op=$(basename "$operation") reason=source_outside_root"
            skipped_operations+=("$operation")
            continue
        fi
        local apply_rc=0
        LEDGER_SOURCE_FILE="$source_file" LEDGER_WRITER_NOTIFY=0 \
            bash "$SCRIPT_DIR/ledger_writer.sh" apply "$staged_operation" || apply_rc=$?
        if [ "$apply_rc" -eq 11 ]; then
            # duplicate_id: the entry already exists on the canonical tip (published by an earlier
            # batch whose applied/ move was lost, or re-issued). Treat as already_published and keep
            # the batch moving instead of aborting it (2026-09-03 shogun 07:14 (a)).
            move_ledger_to "$operation" "$(ledger_directory "$ledger")/applied"
            event ledger ledger_batch 0 "already_published_op=$(basename "$operation") reason=duplicate_id"
            skipped_operations+=("$operation")
            continue
        elif [ "$apply_rc" -ne 0 ]; then
            # One bad op must not hold every other ledger hostage: park it in rc/ and continue.
            move_ledger_to "$operation" "$(ledger_directory "$ledger")/rc"
            event ledger ledger_batch 1 "failed_op=$(basename "$operation") reason=apply_failed rc=$apply_rc"
            skipped_operations+=("$operation")
            continue
        fi
        applied_operations+=("$operation")
    done
    if [ "${#applied_operations[@]}" -eq 0 ]; then
        cleanup_isolated "$isolated"; isolated=""
        cleanup_ledger_stage "$stage_root"; stage_root=""
        return 0
    fi
    operations=("${applied_operations[@]}")

    git -C "$isolated" add --all -- .
    tree="$(git -C "$isolated" write-tree)"
    published_sha="$(printf 'publisher: ledger batch n=%s ledgers=%s\n\nPublished-By: publisher\n' \
        "${#operations[@]}" "$(IFS=,; echo "${ledgers[*]}")" |
        git -C "$isolated" -c user.name=single-publisher -c user.email=publisher@localhost \
        commit-tree "$tree" -p "$tip")"
    if [ "${PUBLISHER_MODE:-dry-run}" = active ]; then
        timeout 120 git -C "$isolated" push origin "$published_sha:refs/heads/main"
        # Confirm applied/ and the event as soon as the push landed; root sync is best-effort
        # (a dirty root must not leave published ops pending -> re-applied -> duplicate rc).
        for operation in "${operations[@]}"; do
            ledger="$(basename "$(dirname "$operation")")"
            move_ledger_to "$operation" "$(ledger_directory "$ledger")/applied"
        done
        event ledger ledger_batch 0 "n=${#operations[@]} ledgers=$(IFS=,; echo "${ledgers[*]}") published_sha=$published_sha"
        timeout 120 git -C "$REPO_ROOT" fetch origin || true
        if ! sync_root "$REPO_ROOT" origin/main; then
            event root_sync_skipped ledger_batch 0 "published_sha=$published_sha reason=${SYNC_ROOT_SKIP_REASON:-unknown} paths=${SYNC_ROOT_SKIP_PATHS:-$(tracked_dirty_paths "$REPO_ROOT")}"
        fi
        cleanup_isolated "$isolated"; isolated=""
        cleanup_ledger_stage "$stage_root"; stage_root=""
        return 0
    else
        event ledger ledger_batch 0 "n=${#operations[@]} origin_update=0 published_sha=$published_sha"
        cleanup_isolated "$isolated"; isolated=""
        cleanup_ledger_stage "$stage_root"; stage_root=""
        return 0
    fi
    for operation in "${operations[@]}"; do
        ledger="$(basename "$(dirname "$operation")")"
        move_ledger_to "$operation" "$(ledger_directory "$ledger")/applied"
    done
    event ledger ledger_batch 0 "n=${#operations[@]} ledgers=$(IFS=,; echo "${ledgers[*]}") published_sha=$published_sha"
    cleanup_isolated "$isolated"; isolated=""
    cleanup_ledger_stage "$stage_root"; stage_root=""
}

handle_lock_failure() {
    local request="$1" rc="$2" task next
    # C2a/restore RC already rotated the request out of dequeued; reading it again
    # raised FileNotFoundError under set -e and killed the daemon (2026-09-03 05:35).
    [ -f "$request" ] || return "$rc"
    task="$(request_id "$request")"
    if [ "$rc" -eq 210 ]; then
        notify_karo "publisher lock-run timeout rc=210 task=$task"
        next="$(increment_publish_attempts "$request")"
        if [ "$next" -gt 3 ]; then
            event retry_exhausted "$task" 210 "publish_attempts=$next"; notify_karo "publisher retry exhausted task=$task publish_attempts=$next"; move_to_rc "$request"
        else
            requeue_request "$request"
        fi
    elif [ "$rc" -ne 0 ]; then
        # C2a already rotated the request and emitted its own terminal evidence.
        # Do not manufacture a second generic failure event for the same request.
        [ -f "$request" ] || return "$rc"
        event git_fail "$task" "$rc" "publisher request failed"; notify_karo "publisher request failed task=$task rc=$rc"; [ -f "$request" ] && move_to_rc "$request"
    fi
    return "$rc"
}

run_one() {
    local request rc mode="${PUBLISHER_MODE:-dry-run}"
    case "$mode" in dry-run|active) ;; *) echo "publisher: PUBLISHER_MODE must be dry-run or active" >&2; return 2 ;; esac
    if ! request="$(bash "$QUEUE_LIB" dequeue)"; then
        rc=$?; [ "$rc" -eq 3 ] && return 0; return "$rc"
    fi
    # NOTE: `$?` after an `if` compound is 0; capture the child's rc explicitly or RC handling never runs.
    rc=0
    bash "$QUEUE_LIB" lock-run --bound 600 -- bash "$SCRIPT_DIR/publisher.sh" --process-request "$request" "$mode" || rc=$?
    [ "$rc" -eq 0 ] && return 0
    handle_lock_failure "$request" "$rc"
}

run_ledger_once() {
    local rc mode="${PUBLISHER_MODE:-dry-run}" before_events after_events
    [ -n "$(ledger_operations)" ] || return 0
    before_events=0
    [ -f "$QUEUE_ROOT/events.jsonl" ] && before_events="$(awk -F'"kind":"' 'NF > 1 {split($2, v, "\""); if (v[1] == "ledger") n++} END {print n + 0}' "$QUEUE_ROOT/events.jsonl")"
    bash "$QUEUE_LIB" lock-run --bound 600 -- bash "$SCRIPT_DIR/publisher.sh" --process-ledger "$mode" || {
        rc=$?
        after_events=0
        [ -f "$QUEUE_ROOT/events.jsonl" ] && after_events="$(awk -F'"kind":"' 'NF > 1 {split($2, v, "\""); if (v[1] == "ledger") n++} END {print n + 0}' "$QUEUE_ROOT/events.jsonl")"
        [ "$after_events" -gt "$before_events" ] || event ledger ledger_batch "$rc" "lock_run_failed=1"
        return "$rc"
    }
}

daemon_main() {
    local once="${PUBLISHER_ONCE:-0}" sleep_seconds="${PUBLISHER_SLEEP_SECONDS:-2}"
    printf '%s\n' "$$" > "$PID_FILE"; trap 'rm -f "$PID_FILE"' EXIT
    # A rejected request (RC) is terminal evidence for that request only; the daemon must keep serving the queue.
    local rc ledger_rc stop_flag="$QUEUE_ROOT/publisher.stop"
    while :; do
        # Operator reload without kill (shogun 05:55 (a)): exit cleanly at a request boundary.
        if [ -f "$stop_flag" ]; then
            rm -f "$stop_flag"
            echo "publisher: stop flag honored; exiting at request boundary pid=$$" >&2
            return 0
        fi
        rc=0; run_one || rc=$?
        ledger_rc=0; run_ledger_once || ledger_rc=$?
        [ "$rc" -eq 0 ] && rc="$ledger_rc"
        [[ "${PUBLISHER_MODE:-dry-run}" = active ]] && publisher_root_drain "$REPO_ROOT" || true
        [ "$once" = 1 ] && return "$rc"
        sleep "$sleep_seconds"
    done
}

if [ "${1:-}" = --process-request ]; then process_request "$2" "$3"
elif [ "${1:-}" = --process-ledger ]; then process_ledger_batch
elif [ "${PUBLISHER_LIB_ONLY:-0}" != 1 ]; then
    daemon_main 2>&1 | publisher_timestamp_stream
    daemon_rc="${PIPESTATUS[0]}"
    exit "$daemon_rc"
fi
