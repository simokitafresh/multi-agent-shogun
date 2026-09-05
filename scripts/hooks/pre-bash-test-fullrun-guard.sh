#!/usr/bin/env bash
# PreToolUse[Bash]: 重量bats直接実行をBLOCK（run_tests.sh経由は許可）
# 単一の具体的な.batsと--countは軽量照会/実行としてcombined Guard 17へ渡す。
payload="$(cat)"
# JSONをregexで切り出すと、escaped quote/newlineを含むcommandを壊す。
# payloadはPreToolUseの正規JSONなので、標準ライブラリで一度だけ復元する。
command="$(printf '%s' "$payload" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    raise SystemExit(0)

tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
command = tool_input.get("command") or tool_input.get("cmd") or ""
if isinstance(command, str):
    sys.stdout.write(command)
' 2>/dev/null)"
[[ -z "$command" ]] && exit 0

# 実際のコマンド位置だけを判定する。単純な文字列包含では、echo/rgの
# 説明文までBLOCKし、run_tests.shを引数に含めただけの偽許可も起きる。
# env prefix、timeout wrapper、bash -cを再帰的にほどき、直接batsだけを検出する。
classification="$(printf '%s' "$command" | python3 -c '
import os
import re
import shlex
import sys

text = sys.stdin.read()

def strip_heredocs(source):
    # 2026-09-05 将軍根治: heredoc 本文(python の三重引用符や日本語の引用符)は shell 文法ではなく
    # shlex を ValueError にする。本文は bats を「実行」できないので、判定前に本文を落とす。
    out, lines, i = [], source.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        m = re.search(r"<<-?\s*[\x27\x22]?([A-Za-z_][A-Za-z0-9_]*)[\x27\x22]?", line)
        out.append(line)
        i += 1
        if m:
            tag = m.group(1)
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1  # skip the terminator line itself
    return "\n".join(out)

def split_segments(source):
    # heredoc 本文を落とし、残った <<TAG 演算子も除き、改行を文区切りとして扱う。
    # (改行区切りの 2 文目の bats は旧実装では 1 文目の head に隠れて判定されなかった)
    source = strip_heredocs(source)
    source = re.sub(r"<<-?\s*[\x27\x22]?[A-Za-z_][A-Za-z0-9_]*[\x27\x22]?", " ", source)
    source = source.replace("\n", " ; ")
    try:
        lexer = shlex.shlex(source, posix=True, punctuation_chars=";&|()<>")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        # 解析不能=BLOCK は「bats を実行していない command」まで止める偽陽性だった
        # (2026-09-05 将軍: python heredoc patch + run_tests.sh の 1 command が 3 回 BLOCK、
        # 変数連結で '.bats' を隠す迂回を誘発)。heredoc を落として再解析し、それでも不能なら
        # 文字列上の実行位置に bats があるかだけを見る(run_tests.sh 経由は許可)。
        pattern = r"(^|[;&|(]\s*|\b(?:env|command|exec|time|nice|timeout\s+\S+|bash\s+-c\s+[\x22\x27]?)\s*)(?:\S*/)?bats(\s|$)"
        return "block-text" if re.search(pattern, source) else None
    segments, current = [], []
    operators = {";", "&&", "||", "|", "&", "(", ")"}
    for token in tokens:
        if token in operators:
            if current:
                segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    return segments

def assignment(token):
    return bool(re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token))

def bats_is_lightweight(args):
    # --count/-c only reports metadata and never executes test bodies.
    if any(arg.split("=", 1)[0] in {"--count", "-c"} for arg in args):
        return True
    targets = []
    options_with_value = {
        "-f", "--filter", "--filter-status", "--formatter", "-j", "--jobs",
        "-o", "--output", "--report-formatter", "--setup-suite-file",
    }
    skip_value = False
    for arg in args:
        if skip_value:
            skip_value = False
            continue
        option = arg.split("=", 1)[0]
        if option in options_with_value:
            skip_value = "=" not in arg
            continue
        if arg.startswith("-"):
            continue
        targets.append(arg)
    return len(targets) == 1 and targets[0].endswith(".bats") and "*" not in targets[0]

def nested(tokens, depth=0):
    if depth > 8:
        return "none"
    tokens = list(tokens)
    while tokens and assignment(tokens[0]):
        tokens.pop(0)
    if not tokens:
        return "none"
    head = os.path.basename(tokens[0])
    if head == "run_tests.sh":
        return "allow"
    if head == "bats":
        # --count/-c only reports metadata and never executes test bodies.
        # Every executing bats invocation, including one concrete file, must
        # use run_tests file mode so receipts and admission remain uniform.
        return "allow" if any(token in {"--count", "-c"} for token in tokens[1:]) else "block"
    if head in {"env", "command", "exec", "time", "nice"}:
        rest = tokens[1:]
        while rest and rest[0].startswith("-") and rest[0] != "--":
            option = rest.pop(0)
            if head == "env" and option in {"-u", "--unset", "-S"} and rest:
                rest.pop(0)
            elif head == "nice" and option in {"-n", "--adjustment"} and rest:
                rest.pop(0)
        if rest and rest[0] == "--":
            rest.pop(0)
        if head == "env":
            while rest and assignment(rest[0]):
                rest.pop(0)
        return nested(rest, depth + 1)
    if head == "timeout":
        rest = tokens[1:]
        while rest and rest[0].startswith("-") and rest[0] != "--":
            option = rest.pop(0)
            if option in {"-k", "--kill-after"} and rest:
                rest.pop(0)
        if rest:
            rest.pop(0)  # duration
        if rest and rest[0] == "--":
            rest.pop(0)
        return nested(rest, depth + 1)
    if head in {"bash", "sh", "dash", "zsh", "ksh"}:
        rest = tokens[1:]
        while rest and rest[0].startswith("-"):
            option = rest.pop(0)
            if option in {"-c", "--command"} and rest:
                inner = rest.pop(0)
                result = classify(inner, depth + 1)
                if result != "none":
                    return result
                break
        if rest:
            return nested(rest, depth + 1)
    return "none"

def classify(source, depth=0):
    segments = split_segments(source)
    if segments == "block-text":
        return "block"
    if segments is None:
        return "none"
    saw_allow = False
    for segment in segments:
        result = nested(segment, depth)
        if result == "block":
            return "block"
        if result == "allow":
            saw_allow = True
    return "allow" if saw_allow else "none"

print(classify(text))
' 2>/dev/null)"

if [[ "$classification" == "block" ]]; then
    echo "BLOCK: batsの直接実行は禁止。bash scripts/run_tests.sh file <対象の.bats> を使え。"
    echo "BLOCK(heavy-job-admission): 実行batsはhost-wide排他制御とreceipt会計のため、'bash scripts/run_tests.sh file <対象の.bats>' へ一本化せよ。"
    echo "正規代替: bash scripts/run_tests.sh file <対象の.bats>"
    echo "全量代替: bash scripts/run_tests.sh unit"
    exit 2
fi

exit 0
