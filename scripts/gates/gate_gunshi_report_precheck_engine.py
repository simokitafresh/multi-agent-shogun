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
        'BC_HAS_NO': '0',
        'BC_NO_ITEMS': '',
        'TEST_TRIAGE': '',
        'HAS_LESSON_CANDIDATE': '0',
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
            # project判定: task YAMLのprojectフィールドで補完(files_modified判定の穴を塞ぐ)
            task_project = task.get('project', '')
            if task_project == 'dm-signal' and not is_dm_signal:
                is_dm_signal = True
                result['IS_DM_SIGNAL'] = '1'

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

    # ── 2b. binary_checks result:no 検出 → T1違反予防 ──────────────────
    report_bc = report.get('binary_checks') or {}
    bc_no_items = []
    if isinstance(report_bc, dict):
        for ac_key, checks in report_bc.items():
            if not isinstance(checks, list):
                continue
            for check_item in checks:
                if not isinstance(check_item, dict):
                    continue
                res = str(check_item.get('result', '')).strip().lower()
                if res == 'no':
                    check_name = check_item.get('check', ac_key)
                    bc_no_items.append(f'{ac_key}/{check_name}')
    result['BC_HAS_NO'] = '1' if bc_no_items else '0'
    result['BC_NO_ITEMS'] = ', '.join(bc_no_items)
    result['TEST_TRIAGE'] = str(report.get('test_triage', '') or '').strip()

    # ── 2c. ac_version照合 → ac_version_mismatch BLOCK予防 ─────────────
    ac_ver_msg = '  SKIP: task YAML not loaded'
    if task_file and os.path.exists(task_file):
        try:
            acv_task = str(task.get('ac_version', '')).strip()
            acv_report = str(report.get('ac_version_read', '')).strip()
            if not acv_task:
                ac_ver_msg = '  SKIP: task.ac_version未設定'
            elif not acv_report:
                ac_ver_msg = '  WARN: report.ac_version_read未記載'
            elif acv_task == acv_report:
                ac_ver_msg = f'  PASS: ac_version一致 ({acv_task[:8]})'
            else:
                ac_ver_msg = (
                    f'  ★ FAIL: ac_version不一致! '
                    f'task={acv_task[:8]} report={acv_report[:8]} '
                    '→ gate BLOCK確実。忍者がtask更新後のACで作業していない可能性'
                )
        except Exception:
            ac_ver_msg = '  SKIP: ac_version解析エラー'
    result['AC_VERSION_MSG'] = ac_ver_msg

    # ── 2d. lessons_useful format検証 → draft_lessons BLOCK予防 ──────────
    lu_msg = '  SKIP'
    lessons_useful = report.get('lessons_useful')
    lesson_candidate = report.get('lesson_candidate')
    # lesson_candidate存在判定: dict形式の場合found:trueのみ有効
    has_lc = False
    if isinstance(lesson_candidate, dict):
        has_lc = bool(lesson_candidate.get('found', False))
    elif lesson_candidate:
        has_lc = True
    result['HAS_LESSON_CANDIDATE'] = '1' if has_lc else '0'
    if isinstance(lessons_useful, list) and lessons_useful:
        bad_items = []
        for i, item in enumerate(lessons_useful):
            if not isinstance(item, dict):
                bad_items.append(f'[{i}] not dict')
            elif not item.get('id'):
                bad_items.append(f'[{i}] id missing')
            elif not isinstance(item.get('useful'), bool):
                u = item.get('useful')
                bad_items.append(f'[{i}] useful={u} (not bool)')
        if bad_items:
            lu_msg = f'  WARN: lessons_useful形式不備: {"; ".join(bad_items[:3])}'
        else:
            lu_msg = f'  PASS: lessons_useful {len(lessons_useful)}件 形式OK'
    elif has_lc:
        lu_msg = (
            '  INFO: lesson_candidate(found:true)+lessons_useful空'
            ' → draft_lessons BLOCKリスクあり(gate_prediction: WARN必須)'
        )
    else:
        lu_msg = '  PASS: lesson_candidate/lessons_useful共になし'
    result['LESSONS_USEFUL_MSG'] = lu_msg

    # ── 2e. related_lessons有り+lessons_useful空検出 → SG7盲点補完 ──────
    rl_msg = '  SKIP'
    has_rl = False
    if task_file and os.path.exists(task_file):
        try:
            related_lessons = task.get('related_lessons') or []
            if isinstance(related_lessons, list) and related_lessons:
                has_rl = True
                lu = report.get('lessons_useful')
                lu_empty = not lu or (isinstance(lu, list) and len(lu) == 0)
                if lu_empty:
                    rl_ids = ', '.join(
                        str(rl.get('id', '?')) if isinstance(rl, dict) else str(rl)
                        for rl in related_lessons[:5]
                    )
                    rl_msg = (
                        f'  ★ WARN: related_lessons注入済み[{rl_ids}]だが'
                        f'lessons_useful空 → cmd_complete_gate BLOCK確実'
                        f'(empty_lessons_useful)'
                    )
                else:
                    rl_msg = (
                        f'  PASS: related_lessons {len(related_lessons)}件,'
                        f' lessons_useful {len(lu)}件'
                    )
            else:
                rl_msg = '  PASS: related_lessonsなし(useful検証不要)'
        except Exception:
            rl_msg = '  SKIP: related_lessons解析エラー'
    result['RELATED_LESSONS_MSG'] = rl_msg
    result['HAS_RELATED_LESSONS_EMPTY_USEFUL'] = (
        '1' if (has_rl and (
            not report.get('lessons_useful')
            or (isinstance(report.get('lessons_useful'), list)
                and len(report.get('lessons_useful')) == 0)
        )) else '0'
    )

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

    # ── 4. GATE_PREDICTION自動計算 ───────────────────────────────────────
    # SG7 gate_predictionをエンジンが自動決定。軍師の判断を介在させない(Phase 4)
    gate_pred = 'CLEAR'
    gate_pred_reasons = []
    if result.get('BC_HAS_NO') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('bc:no検出')
    if has_lc:
        if gate_pred != 'BLOCK':
            gate_pred = 'WARN'
        gate_pred_reasons.append('lesson_candidate有→draft_lessons BLOCKリスク')
    if 'WARN' in lu_msg or 'FAIL' in lu_msg:
        if gate_pred != 'BLOCK':
            gate_pred = 'WARN'
        gate_pred_reasons.append('lessons_useful形式不備')
    if result.get('HAS_RELATED_LESSONS_EMPTY_USEFUL') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('related_lessons有+useful空→empty_lessons_useful BLOCK')
    result['GATE_PREDICTION'] = gate_pred
    result['GATE_PREDICTION_REASON'] = '; '.join(gate_pred_reasons) if gate_pred_reasons else 'all checks passed'

    _output(result)


def _output(result: dict) -> None:
    """bash eval-safe key=value 形式で出力 (shlex.quote)"""
    for key, value in result.items():
        print(f'{key}={shlex.quote(str(value))}')


if __name__ == '__main__':
    main()
