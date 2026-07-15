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

出力: 標準出力に "heavy" または "light" の1行のみ。
"""

import os
import json
import re
import shlex
import sys

_HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def _strip_heredocs(text):
    """heredoc本文/terminator行を除去してからtokenizeする(GA-220と同一原理)。
    heredoc本文中に偶然 "bats"/"pytest" 等の単語が含まれても誤検出しないため。
    """
    lines = text.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        i += 1
        m = _HEREDOC_RE.search(line)
        if not m:
            continue
        strip_tabs = m.group(1) == "-"
        delim = m.group(3)
        while i < n:
            body_line = lines[i]
            probe = body_line.lstrip("\t") if strip_tabs else body_line
            i += 1
            if probe == delim:
                break
    return "\n".join(out)


_SEPS = {"&&", ";", "||", "|", "&", "\n"}


def _segments(command):
    try:
        # shlex.split() alone does not split shell punctuation when it is
        # adjacent to a word (for example ``one.bats; bats two.bats``).  That
        # merged the following command into the first bats argv and produced
        # a false "multiple files" heavy classification.  punctuation_chars
        # makes command boundaries structural, including &&/|| combinations.
        lexer = shlex.shlex(
            _strip_heredocs(command), posix=True, punctuation_chars=";&|\n"
        )
        # Newline is a shell command boundary, not ordinary whitespace.  If it
        # is swallowed here, arguments from a later git/commit command become
        # extra bats targets and a single-file test is falsely classified as
        # heavy.
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        # heredoc除去後も無効な引用符 → トークン化不能。呼び出し側がfail-closedで
        # 扱えるよう None を返す(=判定不能。admission wrapper側はheavyとして扱う)。
        return None
    segs = []
    cur = []
    for t in tokens:
        if t in _SEPS:
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        segs.append(cur)
    return segs


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


def _is_bats_heavy(args):
    file_args = _bats_targets(args)
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
    return False


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


_ONESHOT_HEAVY_NAME_RE = re.compile(
    r"golden|regression_check|fullrecalculate", re.IGNORECASE
)


def classify(command):
    if os.environ.get("HEAVY_JOB_JSON_ESCAPED") == "1":
        try:
            # pre-bash-combined extracts the JSON string without decoding its
            # escapes.  Wrapping it restores newlines/quotes exactly while
            # preserving a literal ``\\n`` (encoded as ``\\\\n``).
            command = json.loads(f'"{command}"')
        except (TypeError, ValueError, json.JSONDecodeError):
            return "heavy"
    segs = _segments(command)
    if segs is None:
        return "heavy"
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
    print(classify(command))


if __name__ == "__main__":
    main()
