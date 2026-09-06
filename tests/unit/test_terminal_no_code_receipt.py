"""test_necessity: no-code terminal reports must bind receipts to their historical tree."""
import copy
import hashlib
import json
import os
import pathlib
import re
import subprocess
import unittest
from unittest.mock import patch

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]


class NoCodeReceiptContract(unittest.TestCase):
    def setUp(self):
        text = (ROOT / 'scripts/report_field_set.sh').read_text()
        start = text.index('def _receipt_task_path(')
        end = text.index('\ntry:\n    for key, value in updates.items():', start)
        self.ns = dict(pathlib=pathlib, os=os, re=re, json=json, hashlib=hashlib,
                       subprocess=subprocess, yaml=yaml, root=ROOT)
        exec(compile(text[start:end], 'receipt helpers', 'exec'), self.ns)
        self.head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        self.tree = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD^{tree}'], text=True).strip()
        self.report = dict(worker_id='fixture', task_id='task-fixture', commit_hash='no-code-change',
                           commit_contract={'required': False},
                           files_modified=[{'path': 'queue/notes/fixture'}],
                           no_code_change_evidence=dict(tree_unchanged=True, before_tree=self.tree, after_tree=self.tree))
        self.receipt = dict(task_id='task-fixture', test_paths=[], commit_sha=self.head)
        self.ns['_receipt_task_mapping'] = lambda _: dict(task_id='task-fixture', test_receipt_path='/tmp/contract-receipt.json')
        self.ns['_receipt_is_valid'] = lambda _: self.receipt

    def run_check(self):
        self.ns['_autolink_terminal_test_receipt'](copy.deepcopy(self.report), ROOT)

    def test_matching_historical_tree_is_accepted(self):
        self.run_check()

    def test_other_tree_is_rejected(self):
        self.report['no_code_change_evidence'].update(before_tree='a' * 40, after_tree='a' * 40)
        with self.assertRaisesRegex(SystemExit, 'tree mismatch'):
            self.run_check()

    def test_source_changes_are_not_no_code(self):
        self.report['files_modified'] = [{'path': 'scripts/fixture.py'}]
        with self.assertRaisesRegex(SystemExit, 'commit identity missing'):
            self.run_check()

    def test_wrong_task_is_rejected(self):
        self.receipt['task_id'] = 'other-task'
        with self.assertRaisesRegex(SystemExit, 'task_id mismatch'):
            self.run_check()

    def test_invalid_receipt_is_rejected(self):
        self.ns['_receipt_is_valid'] = lambda _: None
        with self.assertRaisesRegex(SystemExit, 'missing or invalid'):
            self.run_check()


if __name__ == '__main__':
    unittest.main()
