#!/usr/bin/env python3
# gate_gunshi_report_precheck_engine.py
# gate_gunshi_report_precheck.sh の全Pythonチェックを1回のファイル読込で実行するエンジン
# Usage: python3 gate_gunshi_report_precheck_engine.py --report <path> --tasks-dir <dir>
# Output: bash eval-safe key=value lines (shlex.quote形式)
# 軍師監査§3.2: 13×python3 -c → 1スクリプト統合。390ms/report → 30ms/report

import os
import glob
import argparse
import shlex
import yaml


def main():
    parser = argparse.ArgumentParser(
        description='gate_gunshi_report_precheck engine: '
        '1回のYAML読込で全チェックを実行'
    )
    parser.add_argument('--report', required=True, help='Report YAML path')
    parser.add_argument('--tasks-dir', default='', help='queue/tasks directory path')
    args = parser.parse_args()

    result = {
        'WORKER_ID': '',
        'PARENT_CMD': '',
        'IS_DM_SIGNAL': '0',
        'FILES_MODIFIED': '',
        'BINARY_CHECKS_MSG': '  SKIP: task YAML not found',
        'SAME_CMD_NINJAS': '',
        'TASK_FILE': '',
    }

    # ── 1. REPORT_PATH を1回読込 ──────────────────────────────────────────
    try:
        with open(args.report) as f:
            report = yaml.safe_load(f)
    except Exception as e:
        result['ENGINE_ERROR'] = f'report load error: {e}'
        _output(result)
        return

    # worker_id / parent_cmd
    worker_id = (report.get('worker_id') or '')
    parent_cmd = (report.get('parent_cmd') or '')
    result['WORKER_ID'] = worker_id
    result['PARENT_CMD'] = parent_cmd

    # DM-Signal project detection + FILES_MODIFIED 抽出
    files_modified = report.get('files_modified') or []
    is_dm_signal = False
    fm_paths = []
    for f_entry in files_modified:
        p = f_entry.get('path', '') if isinstance(f_entry, dict) else str(f_entry)
        if not p:
            continue
        fm_paths.append(p)
        if not is_dm_signal:
            if 'backend/' in p or 'scripts/analysis/' in p or 'outputs/' in p:
                is_dm_signal = True

    result['IS_DM_SIGNAL'] = '1' if is_dm_signal else '0'
    result['FILES_MODIFIED'] = '\n'.join(fm_paths)

    # ── 2. TASK_FILE を1回読込 → binary_checks 整合性確認 ────────────────
    task_file = ''
    if worker_id and args.tasks_dir:
        task_file = os.path.join(args.tasks_dir, f'{worker_id}.yaml')
    result['TASK_FILE'] = task_file

    if task_file and os.path.exists(task_file):
        try:
            with open(task_file) as f:
                task_data = yaml.safe_load(f)
            task = (
                task_data.get('task', task_data)
                if isinstance(task_data, dict) else {}
            )
            task_bc = task.get('binary_checks') or {}
            report_bc = report.get('binary_checks') or {}

            if not isinstance(task_bc, dict) or not task_bc:
                result['BINARY_CHECKS_MSG'] = (
                    '  SKIP: task YAMLにbinary_checksテンプレートなし'
                )
            else:
                task_count = sum(
                    len(v) if isinstance(v, list) else 0
                    for v in task_bc.values()
                )
                report_count = (
                    sum(
                        len(v) if isinstance(v, list) else 0
                        for v in report_bc.values()
                    )
                    if isinstance(report_bc, dict) else 0
                )
                if report_count < task_count * 0.5:
                    result['BINARY_CHECKS_MSG'] = (
                        f'  FAIL: 報告{report_count}項目 < '
                        f'テンプレート{task_count}項目の50%。'
                        'テンプレート無視の可能性'
                    )
                elif report_count < task_count:
                    result['BINARY_CHECKS_MSG'] = (
                        f'  WARN: 報告{report_count}項目 < '
                        f'テンプレート{task_count}項目。一部欠落の可能性'
                    )
                else:
                    result['BINARY_CHECKS_MSG'] = (
                        f'  PASS: 報告{report_count}項目 >= '
                        f'テンプレート{task_count}項目'
                    )
        except Exception as e:
            result['BINARY_CHECKS_MSG'] = f'  ERROR: {e}'
    else:
        result['BINARY_CHECKS_MSG'] = f'  SKIP: task YAML not found: {task_file}'

    # ── 3. 全task YAMLを1度ずつ読込 → 二重配備検出 ────────────────────────
    same_cmd_ninjas_parts = []
    if parent_cmd and worker_id and args.tasks_dir:
        for tf in sorted(glob.glob(os.path.join(args.tasks_dir, '*.yaml'))):
            ninja_name = os.path.basename(tf).replace('.yaml', '')
            if ninja_name == worker_id:
                continue
            try:
                with open(tf) as f:
                    d = yaml.safe_load(f)
                t = d.get('task', d) if isinstance(d, dict) else {}
                tf_cmd = t.get('parent_cmd') or ''
                if tf_cmd == parent_cmd:
                    tf_status = t.get('status') or 'unknown'
                    same_cmd_ninjas_parts.append(f'{ninja_name}({tf_status})')
            except Exception:
                pass

    result['SAME_CMD_NINJAS'] = ' '.join(same_cmd_ninjas_parts)

    _output(result)


def _output(result: dict) -> None:
    """bash eval-safe key=value 形式で出力 (shlex.quote)"""
    for key, value in result.items():
        print(f'{key}={shlex.quote(str(value))}')


if __name__ == '__main__':
    main()
