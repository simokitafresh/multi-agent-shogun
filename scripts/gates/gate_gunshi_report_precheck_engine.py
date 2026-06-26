#!/usr/bin/env python3
# semantic-links: [[Silent Fallback品質]]
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
        'BC_YES_CLARITY_CONTRADICTION': '0',
        'BC_YES_CLARITY_TERMS': '',
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
    # files_modifiedが存在するのにpath抽出0件=形式違反(check/result散文形式等)。
    # silent SKIPはSG-PRE25素通り→gate command_files_modified_mismatch BLOCKに直結
    # (cmd_3274実証 2026-06-10: hayateがcheck形式で記入→precheck SKIP→軍師LGTM→BLOCK)
    result['FM_FORMAT_INVALID'] = '1' if (files_modified and not fm_paths) else '0'

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

    def _normalize_bc_result(raw: object) -> str:
        """YAML unquoted yes/no → PyYAML bool True/False を正規化."""
        if isinstance(raw, bool):
            return 'yes' if raw else 'no'
        return str(raw).strip().lower()

    if isinstance(report_bc, dict):
        for ac_key, checks in report_bc.items():
            if not isinstance(checks, list):
                continue
            for check_item in checks:
                if not isinstance(check_item, dict):
                    continue
                res = _normalize_bc_result(check_item.get('result', ''))
                if res == 'no':
                    check_name = check_item.get('check', ac_key)
                    bc_no_items.append(f'{ac_key}/{check_name}')
    result['BC_HAS_NO'] = '1' if bc_no_items else '0'
    result['BC_NO_ITEMS'] = ', '.join(bc_no_items)
    result['TEST_TRIAGE'] = str(report.get('test_triage', '') or '').strip()

    # ── 2b1. binary_checks yes × task_clarity矛盾検出 (LG043) ─────────────
    # binary_checksが全yesでも、unclear/discretion等に未達成・委譲・保留語が残れば
    # AC未達成をyesで通した虚偽yesの可能性が高い(cmd_3532実証)。
    def _flatten_text(value: object) -> str:
        if value is None:
            return ''
        if isinstance(value, dict):
            return ' '.join(_flatten_text(v) for v in value.values())
        if isinstance(value, (list, tuple, set)):
            return ' '.join(_flatten_text(v) for v in value)
        return str(value)

    bc_result_values = []
    if isinstance(report_bc, dict):
        for checks in report_bc.values():
            if not isinstance(checks, list):
                continue
            for check_item in checks:
                if isinstance(check_item, dict):
                    bc_result_values.append(_normalize_bc_result(check_item.get('result', '')))

    all_reported_checks_yes = bool(bc_result_values) and all(
        res in ('yes', 'pass', 'true', 'ok') for res in bc_result_values
    )
    _clarity_parts = []
    # assumption_checkはAC前提の明瞭性確認であり、「scope外」等の境界言及は正当。
    # 矛盾語検出対象から除外(FP防止: cmd_ga141で実証)
    for key in (
        'task_clarity',
        'unclear_points',
        'discretion_fills',
        'purpose_validation',
        'purpose_gap',
    ):
        raw = report.get(key)
        # purpose_validation内のpurpose_gapが「なし」始まりなら除外(FP防止)
        # 「CI設定無効化は未実施」等のnot_in_scope不実施報告は矛盾ではない
        if key == 'purpose_validation' and isinstance(raw, dict):
            pg = str(raw.get('purpose_gap', '') or '').strip()
            if pg.startswith('なし'):
                # purpose_gapを除外し、残りのフィールドだけフラット化
                filtered = {k: v for k, v in raw.items() if k != 'purpose_gap'}
                _clarity_parts.append(_flatten_text(filtered))
                continue
        val = _flatten_text(raw)
        if key == 'purpose_gap' and val.strip().startswith('なし'):
            continue
        _clarity_parts.append(val)
    clarity_text = ' '.join(_clarity_parts)
    contradiction_terms = (
        'デプロイ後',
        '家老実施',
        '家老が実施',
        '後で',
        '未実施',
        '未確認',
        '未達',
        '未完了',
        '保留',
        '未解決',
        'スコープ外',
        'scope外',
        'pending',
        'todo',
        'fill_this',
    )
    matched_terms = [
        term for term in contradiction_terms
        if term.lower() in clarity_text.lower()
    ]
    if all_reported_checks_yes and matched_terms:
        result['BC_YES_CLARITY_CONTRADICTION'] = '1'
        result['BC_YES_CLARITY_TERMS'] = ', '.join(matched_terms)

    # ── 2b2. waive_reason×commit_hash矛盾検出 (GP-248) ───────────────
    # commit bc:no + waive_reason付き だが commit_hash非空 → 矛盾WARN
    commit_hash = str(report.get('commit_hash', '') or '').strip()
    waive_commit_contradiction = ''
    if isinstance(report_bc, dict):
        for check_item in (report_bc.get('commit') or []):
            if not isinstance(check_item, dict):
                continue
            res = _normalize_bc_result(check_item.get('result', ''))
            waive = str(check_item.get('waive_reason', '')).strip()
            if res == 'no' and waive and commit_hash:
                waive_commit_contradiction = f'bc commit:no(waive={waive!r}) but commit_hash={commit_hash[:12]} exists'
    result['WAIVE_COMMIT_CONTRADICTION'] = waive_commit_contradiction

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
            ' → draft_lessons実件数で判定(bash側PRE12b)'
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

    # ── 3b. adversarial/blast_radius/task_type統合判定 ────────────────────
    # §3.2拡張: SG-PRE15.5/PRE16/PRE18の6回python3 -c → engine統合
    HIGH_BLAST = (
        'deploy_task.sh', 'CLAUDE.md', 'ninja_monitor.sh',
        'inbox_write.sh', 'cmd_complete_gate.sh',
    )
    target_path = ''
    if task_file and os.path.exists(task_file):
        try:
            target_path = str(task.get('target_path', ''))
        except Exception:
            pass
    # 旧条件互換: 'scripts/' in target_path で自動化系を拾う(endswith不要)
    AUTO_KEYWORDS = ('scripts/', '.sh', 'gate_', 'hook_', 'monitor', 'cron', 'cleanup')
    adv_target = any(k in target_path for k in AUTO_KEYWORDS) if target_path else False
    adv_fm_scripts = any(
        any(k in p for k in ('scripts/', '.sh', 'gate_', 'hook_', 'monitor', 'cron', 'cleanup'))
        for p in fm_paths
    )
    adv_blast = any(any(p.endswith(hb) for hb in HIGH_BLAST) for p in fm_paths)
    # 旧条件互換: task_type in (impl, fix) も条件に含める
    task_type_str = ''
    if task_file and os.path.exists(task_file):
        try:
            task_type_str = str(task.get('task_type', ''))
        except Exception:
            pass
    task_type_be = ('backend/' in target_path and task_type_str in ('impl', 'fix')) if target_path else False

    # golden/snapshot参照検出
    has_golden = False
    if task_type_be:
        import re
        texts = str((report.get('result') or {}).get('summary', '')) + str((report.get('result') or {}).get('details', ''))
        has_golden = bool(re.search(r'(golden|snapshot|ゴールデン|パリティ).{0,30}(確認|検証|比較|一致|PASS)', texts, re.IGNORECASE))

    result['ADV_TARGET_MATCH'] = '1' if adv_target else '0'
    result['ADV_FM_SCRIPTS'] = '1' if adv_fm_scripts else '0'
    result['ADV_BLAST_HIGH'] = '1' if adv_blast else '0'
    result['TASK_TYPE_BE'] = '1' if task_type_be else '0'
    result['HAS_GOLDEN_REF'] = '1' if has_golden else '0'
    result['TARGET_PATH'] = target_path

    # ── 4. GATE_PREDICTION自動計算 ───────────────────────────────────────
    # SG7 gate_predictionをエンジンが自動決定。軍師の判断を介在させない(Phase 4)
    gate_pred = 'CLEAR'
    gate_pred_reasons = []
    if result.get('BC_HAS_NO') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('bc:no検出')
    if result.get('BC_YES_CLARITY_CONTRADICTION') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('binary_checks yes×task_clarity矛盾(LG043)')
    if has_lc:
        # lesson_candidate有のみではWARNにしない(直近5/5件CLEAR=FP率高)
        # draft_lessonsの実件数によるWARN判定はbash側L977-982で実施
        gate_pred_reasons.append('lesson_candidate有(INFO:draft_lessons実件数はbash側で判定)')
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
