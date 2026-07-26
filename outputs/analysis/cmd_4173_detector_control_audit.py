#!/usr/bin/env python3
"""cmd_4173: 全検知器の対照fixture(陽性1+陰性1)有無を機械判定する。

設計書v3.0 §1: 既知の陽性1件を検出し、既知の陰性1件を通すことをCIで毎回証明
できない検知器は存在してはならない。本スクリプトはその「有無」だけを機械判定し、
人手監査を一切挟まない。

判定手順:
  1. 検知器を機械列挙 (scripts/gates, .claude/hooks, scripts/hooks, .git/hooks)
  2. tests/ 配下で当該検知器を「実行している」テストファイルを特定
     (basename または repo相対path の出現)
  3. そのテストファイル内で、検知器の実行に紐づく assertion が
     陽性(発火を期待) / 陰性(通過を期待) のどちらを含むかを判定
出力: TSV 1検知器1行。detector / positive / negative / evidence
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DETECTOR_DIRS = [
    "scripts/gates",
    ".claude/hooks",
    "scripts/hooks",
    ".git/hooks",
]
SKIP_NAMES = {"__pycache__", "test_hooks.sh"}
DETECTOR_EXT = (".sh", ".py")

# 陽性=検知器が発火することを期待する assertion
POSITIVE_PAT = re.compile(
    r"""(\$status"?\s*-(ne|eq)\s*[1-9])            # status非0期待
        |(\[\s*"\$status"\s*-ne\s*0\s*\])
        |(==\s*\*"?(BLOCK|FAIL|ALERT|DENY|violation|ERROR)) # 出力にBLOCK等
        |(refute|should_block|expect_block|expect_fail)""",
    re.X | re.I,
)
# 陰性=正常系が通ることを期待する assertion
NEGATIVE_PAT = re.compile(
    r"""(\[\s*"?\$status"?\s*-eq\s*0\s*\])          # status 0期待
        |(!=\s*\*"?(BLOCK|FAIL|ALERT|DENY))         # BLOCKが出ないこと
        |(==\s*\*"?(PASS|CLEAR|OK|ok))
        |(expect_pass|should_pass|allow)""",
    re.X | re.I,
)


def list_detectors():
    out = []
    for d in DETECTOR_DIRS:
        full = os.path.join(REPO, d)
        if not os.path.isdir(full):
            continue
        for name in sorted(os.listdir(full)):
            if name in SKIP_NAMES or name.endswith(".sample") or name.endswith(".old"):
                continue
            path = os.path.join(full, name)
            if not os.path.isfile(path):
                continue
            if d == ".git/hooks":
                pass  # git hooks は拡張子なし
            elif not name.endswith(DETECTOR_EXT):
                continue
            out.append((os.path.join(d, name), name))
    return out


def load_tests():
    """tests/ 配下を一度だけ読み込む。detector毎にgrepを起動すると
    WSL2の/mnt/cでは1回あたり数秒かかり全体で10分を超える。"""
    corpus = {}
    for root, _dirs, files in os.walk(os.path.join(REPO, "tests")):
        if "__pycache__" in root:
            continue
        for fn in files:
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, REPO)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    corpus[rel] = fh.read()
            except OSError:
                continue
    return corpus


def grep_tests(corpus, token):
    """tests/ 配下で token を含むファイル一覧。"""
    return [rel for rel, body in corpus.items() if token in body]


def classify(corpus, test_files):
    pos, neg = [], []
    for tf in test_files:
        body = corpus.get(tf, "")
        if POSITIVE_PAT.search(body):
            pos.append(tf)
        if NEGATIVE_PAT.search(body):
            neg.append(tf)
    return pos, neg


def main():
    detectors = list_detectors()
    corpus = load_tests()
    rows = []
    for relpath, name in detectors:
        files = set(grep_tests(corpus, name))
        files |= set(grep_tests(corpus, relpath))
        # 拡張子なしの語幹でも参照される(埋め込みtest harnessは
        # 'gate_autofix_proposal' のように .sh を落として書く)。語幹を見ないと
        # 「testは実在するのに無対照」というテキスト一致の誤判定が出る。
        stem = re.sub(r"\.(sh|py)$", "", name)
        if stem != name:
            files |= set(grep_tests(corpus, stem))
        files = sorted(files)
        if not files:
            rows.append((relpath, "no", "no", "no test file references this detector"))
            continue
        pos, neg = classify(corpus, files)
        rows.append((
            relpath,
            "yes" if pos else "no",
            "yes" if neg else "no",
            "positive={} negative={}".format(
                ",".join(pos) if pos else "-",
                ",".join(neg) if neg else "-",
            ),
        ))

    out_path = os.path.join(REPO, "outputs/analysis/cmd_4173_detector_control_fixture_audit.tsv")
    with open(out_path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write("\t".join(r) + "\n")

    both = sum(1 for r in rows if r[1] == "yes" and r[2] == "yes")
    none = sum(1 for r in rows if r[1] == "no" and r[2] == "no")
    print(f"detectors={len(rows)} both_controls={both} no_control={none} "
          f"partial={len(rows) - both - none}")
    print(f"written: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
