"""Contract: only real writes to shogun_to_karo.yaml are classified as mutation.

test_necessity: Guard4 (pre-bash-combined.sh) blocks status-gate bypass by
mutating shogun_to_karo.yaml, yet must not over-block read-only inspection or
quoted mentions. The invariant fixed here — verified against a substring guard
that both false-blocked reads/mentions and false-allowed variable-indirection,
keyword-file, io.open, Path.write_text, os.replace and shutil.move sinks — is:
a command is a mutation iff it actually writes shogun_to_karo.yaml (redirect,
sed -i, tee, or a python sink whose *resolved* target argument is the file),
and is NOT a mutation for reads, quoted mentions, or writes to another path.
This dataflow contract cannot be expressed by substring matching, so it is a
persistent regression boundary rather than an implementation-time throwaway.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/lib/shogun_to_karo_mutation_classify.py"
sys.path.insert(0, str(SOURCE.parent))
SPEC = importlib.util.spec_from_file_location("stk_mutation_classify", SOURCE)
assert SPEC and SPEC.loader
_MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(_MOD)
classifies_as_mutation = _MOD.classifies_as_mutation

F = "queue/shogun_to_karo.yaml"

MUTATION_CASES = [
    # shell write vectors
    ("sed-i", f"sed -i 's/on_hold/delegated/' {F}"),
    ("sed-inplace", f"sed --in-place 's/a/b/' {F}"),
    ("redirect", f"echo x > {F}"),
    ("redirect-append", f"cat y >> {F}"),
    ("redirect-attached", f"echo x >{F}"),
    ("tee", f"echo x | tee {F}"),
    ("tee-a", f"echo x | tee -a {F}"),
    # python sinks: literal / variable / alias
    ("py-open-lit", f"python3 -c \"open('{F}','w').write(s)\""),
    ("py-open-var", f"python3 -c \"p='{F}'; open(p,'w').write(s)\""),
    ("py-open-alias", f"python3 -c \"p='{F}'; q=p; open(q,'w').write(s)\""),
    ("py-open-append", f"python3 -c \"f='{F}'; open(f,'a').write(s)\""),
    ("py-open-rplus", f"python3 -c \"p='{F}'; open(p,'r+').write(s)\""),
    ("py-open-x", f"python3 -c \"open('{F}','x').write(s)\""),
    # python sinks: keyword file= / io.open / codecs.open
    ("py-open-kwfile", f"python3 -c \"p='{F}'; open(file=p, mode='w')\""),
    ("py-open-kwfile-lit", f"python3 -c \"open(file='{F}', mode='w')\""),
    ("py-io-open-var", f"python3 -c \"import io; p='{F}'; io.open(p,'w')\""),
    ("py-io-open-lit", f"python3 -c \"import io; io.open('{F}','a')\""),
    # python sinks: pathlib / os / shutil
    ("py-path-write-text-lit", f"python3 -c \"from pathlib import Path; Path('{F}').write_text(s)\""),
    ("py-path-write-text-var", f"python3 -c \"from pathlib import Path; p='{F}'; Path(p).write_text(s)\""),
    ("py-path-open", f"python3 -c \"from pathlib import Path; Path('{F}').open('w').write(s)\""),
    ("py-os-replace-dst", f"python3 -c \"import os; os.replace('/tmp/s','{F}')\""),
    ("py-os-replace-src", f"python3 -c \"import os; os.replace('{F}','/tmp/x')\""),
    ("py-shutil-move", f"python3 -c \"import shutil; shutil.move('/tmp/s','{F}')\""),
]

SAFE_CASES = [
    # read-only shell
    ("grep", f"grep cmd {F}"),
    ("awk-stdout", f"awk -F'|' '{{print $2}}' {F}"),
    ("sed-n", f"sed -n '1,5p' {F}"),
    ("cat", f"cat {F}"),
    ("awk-redirect-tmp", f"awk '{{print}}' {F} > /tmp/x"),
    # quoted mentions (not an actual op on the file)
    ("mention-inbox", f"bash scripts/inbox_write.sh karo 'fix sed -i on {F}' t f a"),
    ("mention-echo", f"echo 'sed -i {F}'"),
    ("mention-echo-redirect", f"echo 'use > {F} carefully'"),
    # python reads / writes to a DIFFERENT path while mentioning the file
    ("py-read-replace", f"python3 -c \"print(open('{F}').read().replace('a','b'))\""),
    ("py-var-read", f"python3 -c \"p='{F}'; print(open(p).read())\""),
    ("py-io-open-read", f"python3 -c \"import io; p='{F}'; io.open(p).read()\""),
    ("py-open-kwfile-read", f"python3 -c \"p='{F}'; open(file=p).read()\""),
    ("py-write-elsewhere", f"python3 -c \"p='{F}'; q='/tmp/x'; print(p); open(q,'w').write(s)\""),
    ("py-copy-src-read", f"python3 -c \"import shutil; shutil.copy('{F}','/tmp/x')\""),
]


@pytest.mark.parametrize("desc,cmd", MUTATION_CASES, ids=[c[0] for c in MUTATION_CASES])
def test_real_writes_are_mutations(desc, cmd):
    assert classifies_as_mutation(cmd) is True, desc


@pytest.mark.parametrize("desc,cmd", SAFE_CASES, ids=[c[0] for c in SAFE_CASES])
def test_reads_and_mentions_are_not_mutations(desc, cmd):
    assert classifies_as_mutation(cmd) is False, desc
