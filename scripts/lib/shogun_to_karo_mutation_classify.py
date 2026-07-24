#!/usr/bin/env python3
"""Argv-position-aware classifier: does a shell command MUTATE shogun_to_karo.yaml?

殿指摘2026-07-23の根治。旧Guard4は生コマンド文字列の部分一致(`sed -i`/`awk `/
`shogun_to_karo`)でBLOCK判定していたため、(1)read-onlyのgrep/awk/sed-to-stdoutを
誤BLOCKし、(2)inbox_write等の引用文字列内でこれらを言及しただけでも誤BLOCKした
(Guard5と同一の誤検出クラス)。

本モジュールはshell_command_segmentsでコマンドをquote/heredoc-awareにセグメント
分割し、TARGETが「実際に書き換えられる」場合のみmutationと判定する:

  - heredoc除去後commandにTARGETがあるが、どのargv tokenにも残らない
    => `> shogun_to_karo.yaml` 等のリダイレクトターゲットとして消費された
       (segment_tokensは実リダイレクトのみ消費し、引用文字列内の`>`は消費しない)
    => 実書込 => mutation
  - TARGETがtokenに残る => そのsegmentのargv[0]を検査:
       sed(+-i/--in-place) / tee / python|perl(open書込モード) のみmutation
       それ以外(inbox_write.sh/echo/grep/awk read等)は非mutation

cmd_2134(status迂回)保護は「実際にファイルを書き換える経路」を全て捕捉することで維持。
"""
from __future__ import annotations

import ast
import os
import re
import sys
from pathlib import PurePosixPath

from shell_command_segments import segment_tokens, strip_heredocs

TARGET = "shogun_to_karo"

# Fallback only: direct literal open('...target...','w') for python -c code that
# fails to ast.parse (won't execute, but keep an obvious literal write caught).
_PY_WRITE_RE = re.compile(
    r"""open\s*\(\s*['"][^'"]*shogun_to_karo[^'"]*['"]\s*,\s*['"][^'"]*[wax+]"""
)
_WRITE_MODE = re.compile(r"[wax+]")  # w/a/x truncate/append/create, or r+/w+/a+


def _is_inplace_sed(rest: list[str]) -> bool:
    for a in rest:
        if a == "-i" or a.startswith("-i") or a == "--in-place" or a.startswith("--in-place"):
            return True
    return False


# --- python -c dataflow analysis (家老/軍師 adversarial finding 2026-07-23) ---
# Regex/substring cannot track which variable holds TARGET nor which sink writes
# it, yielding both FP (open(other_var,'w') while TARGET merely mentioned) and FN
# (Path(TARGET).write_text / os.replace(src,TARGET) / shutil.move(src,TARGET)).
# Parse the -c code with ast and follow TARGET-bound names into write sinks.

def _str_has_target(node) -> bool:
    return (
        isinstance(node, ast.Constant)
        and isinstance(node.value, str)
        and TARGET in node.value
    )


def _is_path_ctor_target(node, target_vars) -> bool:
    if not isinstance(node, ast.Call):
        return False
    func = node.func
    name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", "")
    return name == "Path" and bool(node.args) and _arg_is_target(node.args[0], target_vars)


def _arg_is_target(node, target_vars) -> bool:
    if _str_has_target(node):
        return True
    if isinstance(node, ast.Name) and node.id in target_vars:
        return True
    return _is_path_ctor_target(node, target_vars)


def _collect_target_vars(tree) -> set:
    """Names bound (transitively) to a TARGET string / Path(TARGET)."""
    target_vars: set[str] = set()
    for _ in range(8):  # fixpoint for out-of-order aliasing (q = p; p = TARGET)
        changed = False
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assign):
                continue
            if not _arg_is_target(node.value, target_vars):
                continue
            for tgt in node.targets:
                if isinstance(tgt, ast.Name) and tgt.id not in target_vars:
                    target_vars.add(tgt.id)
                    changed = True
        if not changed:
            break
    return target_vars


def _mode_is_write(node) -> bool:
    return (
        isinstance(node, ast.Constant)
        and isinstance(node.value, str)
        and bool(_WRITE_MODE.search(node.value))
    )


def _open_file_arg(call):
    """open()'s file arg — positional 0 or keyword file=."""
    if call.args:
        return call.args[0]
    for kw in call.keywords:
        if kw.arg == "file":
            return kw.value
    return None


def _open_mode(call):
    mode = call.args[1] if len(call.args) > 1 else None
    for kw in call.keywords:
        if kw.arg == "mode":
            mode = kw.value
    return mode


def _is_builtin_open_write(call, target_vars) -> bool:
    """open(...) / io.open(...) / codecs.open(...) with signature open(file, mode)."""
    fa = _open_file_arg(call)
    if fa is None or not _arg_is_target(fa, target_vars):
        return False
    mode = _open_mode(call)
    return mode is not None and _mode_is_write(mode)


def _call_writes_target(call, target_vars) -> bool:
    func = call.func
    # builtins open(TARGET, 'w'|'a'|...) — positional or file=/mode= keyword
    if isinstance(func, ast.Name) and func.id == "open":
        return _is_builtin_open_write(call, target_vars)
    if isinstance(func, ast.Attribute):
        attr = func.attr
        recv = func.value
        # io.open / codecs.open share open(file, mode) signature
        if attr == "open" and isinstance(recv, ast.Name) and recv.id in ("io", "codecs"):
            return _is_builtin_open_write(call, target_vars)
        recv_is_target = _is_path_ctor_target(recv, target_vars) or (
            isinstance(recv, ast.Name) and recv.id in target_vars
        )
        # Path(TARGET).write_text / write_bytes
        if attr in ("write_text", "write_bytes") and recv_is_target:
            return True
        # Path(TARGET).open('w')
        if attr == "open" and recv_is_target:
            mode = call.args[0] if call.args else None
            for kw in call.keywords:
                if kw.arg == "mode":
                    mode = kw.value
            return mode is not None and _mode_is_write(mode)
        # move/replace/rename: dst overwrites TARGET, or src removes TARGET — both mutate
        if attr in ("replace", "rename", "move"):
            if any(_arg_is_target(a, target_vars) for a in call.args[:2]):
                return True
        # copy/copyfile/copy2: only dst (arg1) writes TARGET; src is a read
        if attr in ("copy", "copyfile", "copy2"):
            if len(call.args) >= 2 and _arg_is_target(call.args[1], target_vars):
                return True
    return False


def _python_code_writes_target(code: str) -> bool:
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError):
        return bool(_PY_WRITE_RE.search(code))  # unparseable: cheap literal check
    target_vars = _collect_target_vars(tree)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _call_writes_target(node, target_vars):
            return True
    return False


def _is_python_write(seg: list[str]) -> bool:
    codes: list[str] = []
    i = 1
    while i < len(seg):
        tok = seg[i]
        if tok == "-c" and i + 1 < len(seg):
            codes.append(seg[i + 1])
            i += 2
            continue
        if tok.startswith("-c") and len(tok) > 2:  # merged -c<code>
            codes.append(tok[2:])
        i += 1
    for code in codes:
        if TARGET in code and _python_code_writes_target(code):
            return True
    return False


def classifies_as_mutation(command: str) -> bool:
    if not command:
        return False
    stripped = strip_heredocs(command)
    if TARGET not in stripped:
        # TARGET appears only inside a heredoc body (data, not a write path).
        return False
    segments = segment_tokens(command)
    if segments is None:
        # Malformed quoting: shlex could not parse. Such a command will not
        # execute cleanly, so blocking would only add false positives. Allow.
        return False

    token_has = any(TARGET in tok for seg in segments for tok in seg)
    if not token_has:
        # In the heredoc-stripped command yet absent from every surviving
        # token => consumed as a redirect target (>, >>) => real write.
        return True

    for seg in segments:
        if not seg:
            continue
        if not any(TARGET in tok for tok in seg):
            continue
        prog = PurePosixPath(seg[0].replace("\\", "/")).name
        rest = seg[1:]
        if prog == "sed" and _is_inplace_sed(rest):
            return True
        if prog == "tee":
            return True
        if prog in ("python", "python3", "perl") and _is_python_write(seg):
            return True
    return False


if __name__ == "__main__":
    cmd = os.environ.get("COMMAND", "")
    # exit 0 = mutation (hook should BLOCK); exit 1 = safe (allow)
    sys.exit(0 if classifies_as_mutation(cmd) else 1)
