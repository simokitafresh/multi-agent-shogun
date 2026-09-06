#!/usr/bin/env bats
# test_necessity: every CLI recovery source preserves identical ninja authority boundaries after a fresh session.

@test "ninja authority is identical in recovery sources without session state" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  run env -u TMUX -u TMUX_PANE python3 - "$root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
start = '<!-- ninja-authority-20260906:start -->'
end = '<!-- ninja-authority-20260906:end -->'
blocks = []
for name in ('AGENTS.md', 'CLAUDE.md', 'instructions/ashigaru.md',
             'instructions/roles/ashigaru_role.md',
             'instructions/generated/ashigaru.md',
             'instructions/generated/codex-ashigaru.md',
             'instructions/generated/copilot-ashigaru.md',
             'instructions/generated/kimi-ashigaru.md'):
    text = (root / name).read_text()
    assert text.count(start) == text.count(end) == 1, name
    blocks.append(text.split(start)[1].split(end)[0])
    assert '他の忍者のファイルに触れるな。pushするな。commitまで。' not in text
assert len(set(blocks)) == 1
for required in ('ACは忍者の権限内', 'launcherとnonce監査', '人工的な回数制限を置かない',
                 '非main branchへのpush', 'mainへのpush・merge', '本番DB書込・DDL・deploy'):
    assert required in blocks[0], required
print('8/8 recovery sources identical; no session variables required')
PY
  [ "$status" -eq 0 ]
}
