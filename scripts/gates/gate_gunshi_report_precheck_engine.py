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
import json
import pathlib
import re
import shlex
import sys
import yaml

LIB_DIR = pathlib.Path(__file__).resolve().parents[1] / 'lib'
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))
from report_gate_contract import parent_contract_ac_version  # noqa: E402

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
        'HONEST_REPORT_FLAG': '0',
        'AC_EVIDENCE_MAPPING_MISSING': '0',
        'AC_EVIDENCE_MAPPING_MISSING_KEYS': '',
        'TEST_TRIAGE': '',
        'HAS_LESSON_CANDIDATE': '0',
        'NO_CODE_COMMIT_EXEMPT': '0',
        'VARIATION_CHECKS_REQUIRED': '0',
        'VARIATION_CHECKS_MSG': '  SKIP: 変形検査契約の対象外',
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
            # no-code免除はcommit_hash不在だけでは成立しない。task/report双方が
            # 構造化commit_contractでrequired:falseを宣言し、許可task_typeも
            # 一致する場合だけSG-PRE3の成果物不在ERRORを免除する。
            no_code_task_types = {
                'no_code', 'no-code', 'nocode', 'decision',
                'decision_candidate', 'data_readonly', 'data-readonly',
                'readonly', 'read_only', 'recon', 'recon2', 'scout',
            }
            report_contract = report.get('commit_contract') or {}
            if isinstance(report_contract, str):
                try:
                    report_contract = json.loads(report_contract)
                except (json.JSONDecodeError, TypeError):
                    report_contract = {}
            task_contract = task.get('commit_contract') or {}
            if isinstance(task_contract, str):
                try:
                    task_contract = json.loads(task_contract)
                except (json.JSONDecodeError, TypeError):
                    task_contract = {}
            report_task_type = str(
                report_contract.get('task_type') or report.get('task_type') or ''
            ).strip()
            task_task_type = str(
                task_contract.get('task_type') or task.get('task_type') or ''
            ).strip()
            no_code_contract_match = (
                isinstance(report_contract, dict)
                and isinstance(task_contract, dict)
                and report_contract.get('required') is False
                and task_contract.get('required') is False
                and report_task_type in no_code_task_types
                and task_task_type == report_task_type
            )
            result['NO_CODE_COMMIT_EXEMPT'] = (
                '1' if no_code_contract_match else '0'
            )
            # project判定: task YAMLのprojectフィールドで補完(files_modified判定の穴を塞ぐ)
            task_project = task.get('project', '')
            if task_project == 'dm-signal' and not is_dm_signal:
                is_dm_signal = True
                result['IS_DM_SIGNAL'] = '1'

            task_bc = task.get('binary_checks') or {}
            report_bc = report.get('binary_checks') or {}

            variation_required_raw = task.get('variation_checks_required', False)
            variation_required = str(variation_required_raw).strip().lower() in (
                '1', 'true', 'yes', 'on'
            )
            if variation_required:
                result['VARIATION_CHECKS_REQUIRED'] = '1'
                expected_variations = (
                    'normal_pass',
                    'quoted_or_heredoc',
                    'linked_worktree',
                    'parallel_or_respawn',
                    'abnormal_exit',
                )
                variations = report.get('variation_checks') or {}
                missing_variations = []
                if not isinstance(variations, dict):
                    missing_variations = list(expected_variations)
                else:
                    for name in expected_variations:
                        item = variations.get(name)
                        raw_result = item.get('result', '') if isinstance(item, dict) else ''
                        if isinstance(raw_result, bool):
                            normalized_result = 'yes' if raw_result else 'no'
                        else:
                            normalized_result = str(raw_result).strip().lower()
                        if normalized_result not in ('yes', 'no'):
                            missing_variations.append(name)
                if len(missing_variations) == len(expected_variations):
                    result['VARIATION_CHECKS_MSG'] = (
                        '  ERROR: 変形検査が全セル未実施。'
                        '正常系PASS・引用符/heredoc・linked worktree・併走/respawn・異常exitを記入せよ'
                    )
                elif missing_variations:
                    result['VARIATION_CHECKS_MSG'] = (
                        '  ERROR: 変形検査欄の未記入: ' + ', '.join(missing_variations)
                    )
                else:
                    result['VARIATION_CHECKS_MSG'] = (
                        '  PASS: 変形検査5セルがyes/noで記入済み'
                    )

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
    bc_no_waive_items = []

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
                    waive = str(check_item.get('waive_reason', '') or '').strip()
                    if waive:
                        bc_no_waive_items.append(f'{ac_key}/{check_name}')
    result['BC_HAS_NO'] = '1' if bc_no_items else '0'
    result['BC_NO_ITEMS'] = ', '.join(bc_no_items)
    result['BC_NO_WAIVE_ITEMS'] = ', '.join(bc_no_waive_items)
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

    # ── 2b2. 正直報告 × AC evidence 1:1 mapping (LG044) ────────────────
    # assumption/decision/WITH_CONCERNS は懸念を正直に残すための良い信号だが、
    # それ自体はAC充足の証拠ではない。全ACをyesとする場合だけ、各ACの本旨を
    # 独立した evidence mapping で説明させる。binary no は既存SG-PRE9がBLOCKする。
    assumption_invalidation = report.get('assumption_invalidation')
    decision_candidate = report.get('decision_candidate')

    def _structured_found(value: object) -> bool:
        if not isinstance(value, dict):
            return False
        raw = value.get('found', False)
        return raw is True or str(raw).strip().lower() in ('true', 'yes', '1', 'on')

    status_detail = str(report.get('status_detail', '') or '').strip().upper()
    honest_report_flag = (
        _structured_found(assumption_invalidation)
        or _structured_found(decision_candidate)
        or status_detail in ('WITH_CONCERNS', 'PARTIAL', 'INCOMPLETE')
    )
    result['HONEST_REPORT_FLAG'] = '1' if honest_report_flag else '0'

    evidence_mapping = report.get('ac_evidence_mapping')
    if honest_report_flag and all_reported_checks_yes:
        expected_ac_keys = [
            str(key) for key, checks in report_bc.items()
            if str(key).lower() != 'commit' and isinstance(checks, list) and checks
        ] if isinstance(report_bc, dict) else []
        missing_mapping = []
        for ac_key in expected_ac_keys:
            value = evidence_mapping.get(ac_key) if isinstance(evidence_mapping, dict) else None
            if not _flatten_text(value).strip():
                missing_mapping.append(ac_key)
        if missing_mapping:
            result['AC_EVIDENCE_MAPPING_MISSING'] = '1'
            result['AC_EVIDENCE_MAPPING_MISSING_KEYS'] = ','.join(missing_mapping)
    # SG-PRE9c is a structured completion-clarity check. Do not flatten the
    # whole report or purpose_validation: cmd_purpose, not_in_scope and causal
    # history legitimately describe conditional rollback and past failures.
    purpose_validation = report.get('purpose_validation')
    purpose_fit = (
        purpose_validation.get('fit')
        if isinstance(purpose_validation, dict)
        else None
    )
    purpose_fit_is_true = (
        purpose_fit is True
        or (
            isinstance(purpose_fit, str)
            and purpose_fit.strip().lower() in ('true', 'yes', '1', 'on')
        )
    )
    nested_purpose_gap = (
        purpose_validation.get('purpose_gap')
        if isinstance(purpose_validation, dict) and not purpose_fit_is_true
        else ''
    )
    clarity_fields = (
        report.get('task_clarity'),
        report.get('unclear_points'),       # legacy top-level field
        report.get('discretion_fills'),     # legacy top-level field
        report.get('assumption_check'),
        nested_purpose_gap,
        report.get('purpose_gap'),          # legacy top-level field
    )
    _clarity_parts = []
    for raw in clarity_fields:
        val = _flatten_text(raw)
        if val.strip().startswith('なし'):
            continue
        _clarity_parts.append(val)
    clarity_text = ' '.join(_clarity_parts)
    completion_evidence_text = ' '.join(
        _flatten_text(report.get(field))
        for field in ('result', 'ac_evidence_mapping', 'operational_simulation')
    ).lower()
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
        'スコープ外で家老',
        'scope外で家老',
        # 'scope外'単体はnot_in_scopeとの整合的記述(GA-154 FP実証)。委譲語(家老実施等)と結合時のみ検出
        # 'pending' removed: task/ACの状態記述(pending件数等)で偽陽性。委譲は「保留」「未完了」でカバー
        'todo',
        'fill_this',
    )
    def _term_is_contextual_fp(term: str, text: str) -> bool:
        lower_text = text.lower()
        lower_term = term.lower()
        if lower_term not in lower_text:
            return True
        if term == '未達':
            # 「5分目標は未達(スコープ外)」「補完済み」「次改善」等は
            # AC未達ではなく境界/補足説明。委譲・保留語が同居する場合は検出を維持する。
            benign_markers = ('スコープ外', 'scope外', 'not_in_scope', '補完', '補完済み', '次改善', '次の改善', '対象外')
            delegation_markers = ('家老実施', '家老が実施', '後で', '未実施', '未完了', '保留')
            if any(marker.lower() in lower_text for marker in benign_markers) and not any(
                marker.lower() in lower_text for marker in delegation_markers
            ):
                return True
        if term in ('未確認', '未解決'):
            # 「未確認前提なし」「未解決事項なし」は、対象が存在しないことを
            # 明示した完了表現であり、実作業の未完了ではない。語の直後だけを
            # 局所判定し、「未確認の前提あり」「未解決事項を保留」は維持する。
            occurrences = list(re.finditer(re.escape(lower_term), lower_text))
            benign_occurrence_count = 0
            delegation_markers = (
                '家老実施', '家老が実施', '後で', '未実施', '未完了', '保留',
                'todo', 'fill_this',
            )
            for occurrence in occurrences:
                _, end = occurrence.span()
                after = lower_text[end:min(len(lower_text), end + 32)]
                past_state = bool(re.match(r'(?:だった|であった)(?:が|ものの|[\s。、，,.]|$)', after))
                completion_markers = (
                    ('status=resolved', 'status: resolved', 'resolvedへ遷移', '解決済み', '解決済')
                    if term == '未解決'
                    else ('確認済み', '確認済', 'mismatch=0', '未確認0')
                )
                # 「未解決前提を現行実装で照合し、対象status=resolved」のように、
                # 未解決だった対象を現行実装で照合して解消した履歴は、別欄の
                # 証跡に頼らず同一局所文脈の完了証跡と組み合わせて免除する。
                # 「未解決事項を確認したが残存」には完了証跡がなく、
                # 「未解決だったがresolve可能」には resolved 状態がないため維持する。
                local_after = lower_text[end:min(len(lower_text), end + 96)]
                local_resolved_history = (
                    term == '未解決'
                    and re.search(
                        r'(?:前提|事項|項目|問題|課題)?(?:を|は)?'
                        r'(?:(?:現行)?(?:実装|コード)で)?'
                        r'(?:照合|確認|検証)'
                        r'[^。！？]{0,48}'
                        r'(?:対象|当該|該当)?\s*'
                        r'(?:status\s*[:=]\s*resolved|resolvedへ(?:遷移|更新)|解決済み|解決済)',
                        local_after,
                    )
                )
                past_state_with_evidence = (
                    past_state
                    and any(marker in completion_evidence_text for marker in completion_markers)
                    and not any(marker.lower() in lower_text for marker in delegation_markers)
                )
                completed_or_quoted = (
                    # 完了肯定: 「未確認0」「未確認0を確認」。裸の0は
                    # 末尾・空白・句読点境界だけを許可し、「0だが…」を除外する。
                    re.match(
                        r'0(?:'
                        r'(?:件)?(?:を)?確認(?:済み|済)?(?=$|[\s。、，,.!?！？])'
                        r'|(?=$|[\s。、，,.!?！？])'
                        r')',
                        after,
                    )
                    # 対象なし: 「未確認前提なし」「未確認routeなし」
                    or re.match(
                        r'(?:の)?(?:前提|事項|項目|問題|課題|[a-z_][a-z0-9_-]*)?'
                        r'(?:は)?(?:なし|無し|ない)(?:\b|。|、|$)',
                        after,
                    )
                    # 対象を解決済みとした完了表現:
                    # 「未解決前提は残していない」「未解決事項は残っていない」。
                    or re.match(
                        r'(?:の)?(?:前提|事項|項目|問題|課題|[a-z_][a-z0-9_-]*)?'
                        r'(?:は)?(?:残していない|残っていない)(?:\b|。|、|$)',
                        after,
                    )
                    # AC要件引用: 「未確認が1件でもあればBLOCK」
                    or re.match(r'が?(?:1件|一件|1つ|ひとつ)でもあれば', after)
                    # 過去状態は、別の完了証拠が報告内にある場合だけ免除する。
                    # 「未解決だったがresolve可能」のような可能性記述だけでは通さない。
                    or past_state_with_evidence
                    # 未解決の対象を現行実装で照合し、同じ説明内で解消済みと
                    # 記録した場合だけ免除する(歴史説明の局所判定)。
                    or local_resolved_history
                )
                if completed_or_quoted:
                    benign_occurrence_count += 1
            if occurrences and benign_occurrence_count == len(occurrences):
                return True
            # 偵察報告やdetector設計説明では「未確認/未解決」は調査状態・分類語であり、
            # AC未達や委譲を意味しない。委譲・未完了語が同居する場合は検出を維持する。
            investigation_markers = (
                '偵察',
                '調査',
                '切り分け',
                '原因',
                '分類',
                '分類ロジック',
                'detector',
                '設計用語',
                '状態記述',
                '本番パスワード',
                'パスワード',
                '認証',
                '401',
            )
            if any(marker.lower() in lower_text for marker in investigation_markers) and not any(
                marker.lower() in lower_text for marker in delegation_markers
            ):
                return True
        if term == '未完了':
            # 「未完了マーカー」「未完了検出」等は検出器設計のメタ言語。
            # 「未完了当年」「未完了年度」は時間窓の分類名でありAC未達ではない。
            # 「AC未完了」「作業未完了」「検証未完了」は実際の未完了なので除外しない。
            occurrences = list(re.finditer(re.escape(lower_term), lower_text))
            metalinguistic = 0
            for occurrence in occurrences:
                start, end = occurrence.span()
                before = lower_text[max(0, start - 8):start]
                after = lower_text[end:min(len(lower_text), end + 8)]
                if (
                    after.startswith(('マーカー', '語', '文字列', '検出', '判定', 'チェック', '当年', '年度'))
                    and not before.endswith(('ac', '作業', '実装', '検証', 'タスク'))
                ):
                    metalinguistic += 1
            if occurrences and metalinguistic == len(occurrences):
                return True
            # 分布・母集団の定義では、未完了の現行taskを計測対象から
            # 除外することがあり、これは業務未完了の申告ではない。
            # ただし「作業未完了」「実装未完了」等の実作業語が同じ局所文脈に
            # あれば、分類語を含んでいてもBLOCKを維持する。
            population_markers = ('分布', '母集団', '集計', '分類')
            exclusion_markers = ('除外', '対象外', '別集計', '分離')
            work_markers = ('作業', '実装', '検証', '実施', '対応', 'ac')
            delegation_markers = ('後で', '未実施', '保留', '家老実施', '家老が実施')
            population_context = lower_text[max(0, occurrence.start() - 16):min(len(lower_text), occurrence.end() + 96)] if occurrences else ''
            if (
                any(marker in population_context for marker in population_markers)
                and any(marker in population_context for marker in exclusion_markers)
                and not any(marker in population_context for marker in work_markers)
                and not any(marker in population_context for marker in delegation_markers)
            ):
                return True
        if term == '後で':
            # 「実行後であり」「確認後であり」「判明後であり」等の時間副詞用法は
            # 委譲語(「後で対応する」)ではない。偽陽性実例: kagemaru gist_reorder
            # assumption_check「判明したのは実行後であり」(2026-08-08)
            occurrences = list(re.finditer(re.escape(lower_term), lower_text))
            temporal_count = 0
            for occurrence in occurrences:
                start, end = occurrence.span()
                after = lower_text[end:min(len(lower_text), end + 8)]
                if after.startswith(('であり', 'である', 'だった', 'あり', 'ある', 'に', 'の')):
                    temporal_count += 1
            if occurrences and temporal_count == len(occurrences):
                return True
        if term in ('todo', 'fill_this'):
            # 機能名/識別子、引用、検出器の説明に現れる予約語は未完了作業ではない。
            # 各出現の局所文脈を判定し、1件でも実作業の用法なら検出を維持する。
            detector_markers = (
                '機能名', '識別子', '検出器', '検出', 'チェック', '引用', '文字列',
                '語句', '予約語', 'detector', 'checker', 'check',
            )
            occurrences = list(re.finditer(re.escape(lower_term), lower_text))
            benign_count = 0
            for occurrence in occurrences:
                start, end = occurrence.span()
                before = lower_text[start - 1:start]
                after = lower_text[end:end + 1]
                in_identifier = bool(
                    (before and (before.isalnum() or before == '_'))
                    or (after and (after.isalnum() or after == '_'))
                )
                window = lower_text[max(0, start - 32):min(len(lower_text), end + 32)]
                quoted = (
                    (before in ('"', "'", '`', '「', '『') and after in ('"', "'", '`', '」', '』'))
                )
                explanatory = any(marker.lower() in window for marker in detector_markers)
                actionable = bool(re.search(
                    re.escape(lower_term) + r'(?:は|:|：)?[^。\n]{0,8}(?:後で|未実施|未完了|保留|家老実施|家老が実施)',
                    window,
                ))
                if (in_identifier or quoted or explanatory) and not actionable:
                    benign_count += 1
            if occurrences and benign_count == len(occurrences):
                return True
        return False

    matched_terms = [
        term for term in contradiction_terms
        if not _term_is_contextual_fp(term, clarity_text)
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
    # queue/tasks/{worker}.yaml is a mutable lease and may already describe a
    # later assignment.  Resolve the expected value from report.parent_cmd's
    # immutable snapshot (or the saved parent command for legacy reports).
    ac_ver_msg = '  SKIP: parent contract unavailable'
    try:
        expected_ac, contract_source = parent_contract_ac_version(args.report, args.tasks_dir)
        acv_report = str(report.get('ac_version_read', '') or '').strip()
        if not expected_ac:
            ac_ver_msg = f'  SKIP: {contract_source}'
        elif not acv_report:
            ac_ver_msg = '  WARN: report.ac_version_read未記載'
        elif expected_ac == acv_report:
            ac_ver_msg = f'  PASS: ac_version一致 ({expected_ac[:8]}) source={contract_source}'
        else:
            ac_ver_msg = (
                f'  ★ FAIL: ac_version不一致! '
                f'parent={expected_ac[:8]} report={acv_report[:8]} '
                f'source={contract_source}'
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
        if result.get('BC_NO_WAIVE_ITEMS'):
            gate_pred_reasons.append('bc:no検出(waive_reason有でもBLOCK)')
        else:
            gate_pred_reasons.append('bc:no検出')
    if result.get('BC_YES_CLARITY_CONTRADICTION') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('binary_checks yes×task_clarity矛盾(LG043)')
    if result.get('AC_EVIDENCE_MAPPING_MISSING') == '1':
        gate_pred = 'BLOCK'
        gate_pred_reasons.append(
            '正直報告あり×AC evidence mapping欠落(LG044):'
            + result.get('AC_EVIDENCE_MAPPING_MISSING_KEYS', '')
        )
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
    if result.get('VARIATION_CHECKS_REQUIRED') == '1' and 'ERROR:' in result.get('VARIATION_CHECKS_MSG', ''):
        gate_pred = 'BLOCK'
        gate_pred_reasons.append('変形検査契約の未記入')
    result['GATE_PREDICTION'] = gate_pred
    result['GATE_PREDICTION_REASON'] = '; '.join(gate_pred_reasons) if gate_pred_reasons else 'all checks passed'
    result['GATE_PREDICTION_WITH_SHELL_FINDINGS'] = 'BLOCK'

    _output(result)


def _output(result: dict) -> None:
    """bash eval-safe key=value 形式で出力 (shlex.quote)"""
    for key, value in result.items():
        print(f'{key}={shlex.quote(str(value))}')


if __name__ == '__main__':
    main()
