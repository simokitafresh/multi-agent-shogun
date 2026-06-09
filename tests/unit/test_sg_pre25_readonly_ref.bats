#!/usr/bin/env bats
# test_sg_pre25_readonly_ref.bats — SG-PRE25 readonly_ref除外の検証
# cmd_3247: SG-PRE25がcommand欄のreadonly_refファイルをmismatch判定から除外することを確認

setup() {
    export REPO_ROOT="/mnt/c/tools/multi-agent-shogun"
    TEST_TMP="$(mktemp -d)"
    # テスト用shogun_to_karo.yaml
    mkdir -p "$TEST_TMP/queue/archive/cmds"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ── Helper: SG-PRE25のPythonブロックだけを抽出して実行 ──
run_pre25_python() {
    local cmd_text="$1"
    local files_modified="$2"
    local cmd_id="${3:-test_cmd}"
    local spec_file="$TEST_TMP/queue/shogun_to_karo.yaml"

    # テスト用YAML生成
    cat > "$spec_file" <<YAMEOF
commands:
  ${cmd_id}:
    command: |
      ${cmd_text}
YAMEOF

    python3 - "$spec_file" "$cmd_id" "$files_modified" "$TEST_TMP" <<'PYEOF'
import yaml, re, sys, os, glob
try:
    spec_file, cmd_id, fm_raw, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    cmd_text = ''
    with open(spec_file) as f:
        d = yaml.safe_load(f) or {}
    cmds = d.get('commands', {}) or {}
    spec = cmds.get(cmd_id, {})
    if spec:
        cmd_text = spec.get('command', '')
    if not cmd_text:
        for p in sorted(glob.glob(os.path.join(repo, 'queue', 'archive', 'cmds', f'{cmd_id}*.yaml')), reverse=True):
            with open(p) as f:
                ad = yaml.safe_load(f) or {}
            acmds = ad.get('commands', {}) or {}
            aspec = acmds.get(cmd_id, {}) or {}
            cmd_text = aspec.get('command', '')
            if cmd_text:
                break
    if not cmd_text:
        print('SKIP: command欄なし')
        sys.exit(0)

    pattern = re.compile(
        r"(?<![A-Za-z0-9_./-])"
        r"((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+"
        r"\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv))"
        r"(?![A-Za-z0-9_.-])"
    )
    read_markers = (
        "読む", "読んで", "読み", "確認", "参照", "調査", "精査", "review", "read", "inspect", "refer",
        "実行", "実行のみ", "変更対象外", "走らせ", "検証", "run", "execute",
    )
    write_markers = (
        "修正", "更新", "変更", "編集", "実装", "追加", "削除", "作成", "反映",
        "modify", "update", "edit", "add", "remove", "delete", "create", "write", "implement",
    )

    def marker_pos(text, markers):
        positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
        return min(positions) if positions else -1

    matches = list(pattern.finditer(cmd_text))
    seen = set()
    write_refs = []
    readonly_refs = []
    for idx, match in enumerate(matches):
        ref = match.group(1).strip().strip("`'\".,:;()[]{}")
        if not ref or ref in seen:
            continue
        seen.add(ref)
        sentence_end_candidates = [
            pos for pos in (
                cmd_text.find("\n", match.end()),
                cmd_text.find("。", match.end()),
                cmd_text.find("；", match.end()),
                cmd_text.find(";", match.end()),
            )
            if pos >= 0
        ]
        sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(cmd_text)
        next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
        local = cmd_text[match.end():next_file_start]
        sentence_tail = cmd_text[match.end():sentence_end]
        read_pos = marker_pos(local, read_markers)
        if read_pos < 0:
            read_pos = marker_pos(sentence_tail, read_markers)
        write_pos = marker_pos(sentence_tail, write_markers)
        next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (
            write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos
        )
        is_readonly = read_pos >= 0 and (write_pos < 0 or read_pos < write_pos) and (
            write_pos < 0 or next_ref_before_write
        )
        base = os.path.basename(ref)
        if is_readonly:
            readonly_refs.append(base)
        else:
            write_refs.append(base)

    fm_bases = set(os.path.basename(p.strip()) for p in fm_raw.split('\n') if p.strip())
    unmatched = sorted(set(write_refs) - fm_bases)

    lines = []
    if readonly_refs:
        lines.append('READONLY_EXCLUDED: ' + ' '.join(sorted(set(readonly_refs))))
    if unmatched:
        lines.append('WARN: ' + ' '.join(unmatched))
    else:
        lines.append('PASS')
    print('\n'.join(lines))
except Exception as e:
    print(f'SKIP: {e}')
PYEOF
}

# ── AC1: readonly_refファイルがmismatch判定から除外される ──

@test "AC1: readonly_ref(確認)ファイルはmismatch判定から除外される" {
    # command: fileA.shを修正。fileB.mdを確認
    # files_modified: fileA.sh のみ
    # 期待: fileB.mdはreadonly_refなのでmismatch警告なし → PASS
    run run_pre25_python \
        "fileA.shを修正。fileB.mdを確認" \
        "fileA.sh"
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: fileB.md"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "AC1: readonly_ref(実行)ファイルはmismatch判定から除外される" {
    # command: main.pyを更新。test_runner.shを実行
    # files_modified: main.py のみ
    run run_pre25_python \
        "main.pyを更新。test_runner.shを実行" \
        "main.py"
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: test_runner.sh"* ]]
}

@test "AC1: readonly_ref(参照)ファイルはmismatch判定から除外される" {
    # command: config.yamlを編集。design.mdを参照
    # files_modified: config.yaml のみ
    run run_pre25_python \
        "config.yamlを編集。design.mdを参照" \
        "config.yaml"
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: design.md"* ]]
}

@test "AC1: 英語マーカーreview/inspectも除外される" {
    # マーカーはファイル参照の後方で検出(cmd_complete_gate.shと同一仕様)
    # 日本語「Xを修正」/ 英語「X review」のようにファイル後にマーカーが必要
    run run_pre25_python \
        "target.pyを修正。reference.md review for context" \
        "target.py"
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: reference.md"* ]]
}

# ── AC2: readonly_ref除外後のmismatchがWARN表示 ──

@test "AC2: readonly_ref除外後に残るwrite refのmismatchはWARN" {
    # command: fileA.shを修正。fileB.pyを追加。fileC.mdを確認
    # files_modified: fileA.sh のみ (fileB.pyが不在)
    # 期待: fileC.md=readonly除外、fileB.py=write ref不在→WARN
    run run_pre25_python \
        "fileA.shを修正。fileB.pyを追加。fileC.mdを確認" \
        "fileA.sh"
    echo "output: $output"
    [[ "$output" == *"WARN: fileB.py"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: fileC.md"* ]]
    # WARN行にfileC.mdが含まれないことを確認(readonly除外済み)
    local warn_line
    warn_line=$(echo "$output" | grep "^WARN:" || true)
    [[ "$warn_line" != *"fileC.md"* ]]
}

@test "AC2: 全write refがfiles_modifiedにあればPASS" {
    run run_pre25_python \
        "fileA.shを修正。fileB.pyを追加" \
        $'fileA.sh\nfileB.py'
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN"* ]]
}

# ── AC3: 複合ケース(readonly混在) ──

@test "AC3: 複数readonly_ref+複数write refの混在ケース" {
    # 3 write refs (a.sh, b.py, c.yaml) + 2 readonly refs (d.md確認, e.sh実行)
    # files_modified: a.sh, b.py, c.yaml → PASS (readonlyは除外)
    run run_pre25_python \
        "a.shを修正。b.pyを更新。c.yamlを編集。d.mdを確認。e.shを実行" \
        $'a.sh\nb.py\nc.yaml'
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"READONLY_EXCLUDED:"* ]]
    [[ "$output" == *"d.md"* ]]
    [[ "$output" == *"e.sh"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "AC3: readonly_refなしの場合は従来通りの挙動" {
    # 全てwrite ref、files_modifiedに全て含まれる
    run run_pre25_python \
        "a.shを修正。b.pyを追加" \
        $'a.sh\nb.py'
    echo "output: $output"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"READONLY_EXCLUDED"* ]]
}

@test "AC3: command欄なしの場合はSKIP" {
    run run_pre25_python "" "a.sh" "nonexistent_cmd"
    echo "output: $output"
    [[ "$output" == *"SKIP"* ]]
}
