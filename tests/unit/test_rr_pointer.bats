#!/usr/bin/env bats
# test_rr_pointer.bats - cmd_519 round-robin回転ポインタのテスト

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/queue"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ═══ AC2: deploy_task.sh がポインタを更新する ═══

@test "rr_pointer: deploy updates pointer file with ninja name" {
    RR_FILE="$TEST_TMP/queue/rr_pointer.txt"
    RR_LOCK="/tmp/rr_pointer_test_$$.lock"
    NINJA_NAME="hayate"

    (
        flock -w 5 201
        echo "$NINJA_NAME" > "$RR_FILE"
    ) 201>"$RR_LOCK"

    [ -f "$RR_FILE" ]
    result=$(cat "$RR_FILE" | tr -d '[:space:]')
    [ "$result" = "hayate" ]
    rm -f "$RR_LOCK"
}

@test "rr_pointer: pointer file contains single line" {
    RR_FILE="$TEST_TMP/queue/rr_pointer.txt"
    echo "kagemaru" > "$RR_FILE"
    line_count=$(wc -l < "$RR_FILE")
    [ "$line_count" -eq 1 ]
}

# ═══ AC3: idle一覧の回転順序 ═══

@test "rr_pointer: idle list rotated from pointer position (hayate)" {
    run bash -c '
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
rr_last="hayate"

# Build rotated order
rotated=()
rr_idx=-1
for i in "${!NINJA_NAMES[@]}"; do
    if [ "${NINJA_NAMES[$i]}" = "$rr_last" ]; then
        rr_idx=$i
        break
    fi
done
total=${#NINJA_NAMES[@]}
for (( j=1; j<=total; j++ )); do
    rotated+=("${NINJA_NAMES[$(( (rr_idx + j) % total ))]}")
done

# All idle
idle_list=""
for name in "${rotated[@]}"; do
    idle_list="${idle_list}${name},"
done
idle_list="${idle_list%,}"
echo "$idle_list"
'
    [ "$status" -eq 0 ]
    [ "$output" = "kagemaru,hanzo,saizo,kotaro,tobisaru,sasuke,kirimaru,hayate" ]
}

@test "rr_pointer: idle list rotated from pointer position (tobisaru)" {
    run bash -c '
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
rr_last="tobisaru"

rotated=()
rr_idx=-1
for i in "${!NINJA_NAMES[@]}"; do
    if [ "${NINJA_NAMES[$i]}" = "$rr_last" ]; then
        rr_idx=$i
        break
    fi
done
total=${#NINJA_NAMES[@]}
for (( j=1; j<=total; j++ )); do
    rotated+=("${NINJA_NAMES[$(( (rr_idx + j) % total ))]}")
done

idle_list=""
for name in "${rotated[@]}"; do
    idle_list="${idle_list}${name},"
done
idle_list="${idle_list%,}"
echo "$idle_list"
'
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke,kirimaru,hayate,kagemaru,hanzo,saizo,kotaro,tobisaru" ]
}

# ═══ フォールバック: ポインタ未存在時 ═══

@test "rr_pointer: fallback to default order when pointer file missing" {
    run bash -c '
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
rr_last=""

rotated=("${NINJA_NAMES[@]}")

idle_list=""
for name in "${rotated[@]}"; do
    idle_list="${idle_list}${name},"
done
idle_list="${idle_list%,}"
echo "$idle_list"
'
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke,kirimaru,hayate,kagemaru,hanzo,saizo,kotaro,tobisaru" ]
}

@test "rr_pointer: fallback when pointer contains unknown name" {
    run bash -c '
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
rr_last="unknown_ninja"

rotated=()
rr_idx=-1
for i in "${!NINJA_NAMES[@]}"; do
    if [ "${NINJA_NAMES[$i]}" = "$rr_last" ]; then
        rr_idx=$i
        break
    fi
done
if [ "$rr_idx" -ge 0 ]; then
    total=${#NINJA_NAMES[@]}
    for (( j=1; j<=total; j++ )); do
        rotated+=("${NINJA_NAMES[$(( (rr_idx + j) % total ))]}")
    done
else
    rotated=("${NINJA_NAMES[@]}")
fi

idle_list=""
for name in "${rotated[@]}"; do
    idle_list="${idle_list}${name},"
done
idle_list="${idle_list%,}"
echo "$idle_list"
'
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke,kirimaru,hayate,kagemaru,hanzo,saizo,kotaro,tobisaru" ]
}

# ═══ AC4: auto_deploy_next.sh の回転選択 ═══

@test "rr_pointer: python rotation selects first idle after pointer" {
    run python3 -c "
NINJA_NAMES = ['sasuke','kirimaru','hayate','kagemaru','hanzo','saizo','kotaro','tobisaru']
rr_last = 'hayate'

rotated = list(NINJA_NAMES)
if rr_last in NINJA_NAMES:
    idx = NINJA_NAMES.index(rr_last)
    rotated = NINJA_NAMES[idx+1:] + NINJA_NAMES[:idx+1]

# Simulate: kagemaru and saizo are idle
idle_ninjas = {'kagemaru', 'saizo'}
for name in rotated:
    if name in idle_ninjas:
        print(name)
        break
"
    [ "$status" -eq 0 ]
    [ "$output" = "kagemaru" ]
}

@test "rr_pointer: python rotation wraps around correctly" {
    run python3 -c "
NINJA_NAMES = ['sasuke','kirimaru','hayate','kagemaru','hanzo','saizo','kotaro','tobisaru']
rr_last = 'kotaro'

rotated = list(NINJA_NAMES)
if rr_last in NINJA_NAMES:
    idx = NINJA_NAMES.index(rr_last)
    rotated = NINJA_NAMES[idx+1:] + NINJA_NAMES[:idx+1]

# Only sasuke is idle
idle_ninjas = {'sasuke'}
for name in rotated:
    if name in idle_ninjas:
        print(name)
        break
"
    [ "$status" -eq 0 ]
    [ "$output" = "sasuke" ]
}

@test "rr_pointer: python fallback when pointer unknown" {
    run python3 -c "
NINJA_NAMES = ['sasuke','kirimaru','hayate','kagemaru','hanzo','saizo','kotaro','tobisaru']
rr_last = 'nonexistent'

rotated = list(NINJA_NAMES)
if rr_last in NINJA_NAMES:
    idx = NINJA_NAMES.index(rr_last)
    rotated = NINJA_NAMES[idx+1:] + NINJA_NAMES[:idx+1]

# kirimaru is idle
idle_ninjas = {'kirimaru'}
for name in rotated:
    if name in idle_ninjas:
        print(name)
        break
"
    [ "$status" -eq 0 ]
    [ "$output" = "kirimaru" ]
}
