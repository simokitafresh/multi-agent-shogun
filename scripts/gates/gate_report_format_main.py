#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

import yaml


def main() -> int:
    if len(sys.argv) < 2:
        print("FAIL: report path required")
        return 1

    report_path = sys.argv[1]
    errors = []
    hints = []
    assigned_acs = set()

    try:
        with open(report_path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except Exception as e:
        print(f"FAIL: YAML parse error: {e}")
        return 1

    if not data or not isinstance(data, dict):
        print("FAIL: report is empty or not a dict")
        return 1

    required = [
        "worker_id",
        "parent_cmd",
        "ac_version_read",
        "binary_checks",
        "files_modified",
        "lesson_candidate",
        "lessons_useful",
    ]
    missing_hints = {
        "worker_id": "FIX (worker_id): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\n  bash scripts/report_field_set.sh <report> worker_id <your_name>",
        "parent_cmd": "FIX (parent_cmd): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\n  bash scripts/report_field_set.sh <report> parent_cmd cmd_XXXX",
        "binary_checks": 'FIX (binary_checks): report_field_set.shで記入せよ:\n  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: "yes"',
        "files_modified": "FIX (files_modified): 変更したファイルパスを記入せよ:\n  files_modified:\n    - path/to/file.py",
        "lesson_candidate": 'FIX (lesson_candidate): report_field_set.shで記入せよ:\n  lesson_candidate:\n    found: false\n    no_lesson_reason: "理由を具体的に書け"',
        "lessons_useful": "FIX (lessons_useful): テンプレートに注入済みの教訓にuseful/reasonを記入せよ。空リストで上書きするな",
        "ac_version_read": "FIX (ac_version_read): task YAMLのac_versionハッシュ値をコピーせよ",
    }
    for field in required:
        if field not in data:
            errors.append(f"{field}: MISSING")
            if field in missing_hints:
                hints.append(missing_hints[field])

    for field_name, field_hint in [
        ("worker_id", missing_hints.get("worker_id", "")),
        ("parent_cmd", missing_hints.get("parent_cmd", "")),
    ]:
        if field_name in data and not str(data.get(field_name) or "").strip():
            errors.append(f"{field_name}: MISSING (empty value)")
            if field_hint:
                hints.append(field_hint)

    fm = data.get("files_modified")
    def files_modified_has_fill_this(items) -> bool:
        if isinstance(items, str):
            return items.strip() == "FILL_THIS"
        if isinstance(items, list):
            for item in items:
                if isinstance(item, str) and item.strip() == "FILL_THIS":
                    return True
                if isinstance(item, dict) and str(item.get("path", "")).strip() == "FILL_THIS":
                    return True
        return False

    if fm is None and "files_modified" in data:
        errors.append("files_modified: null (must be string or list of file paths)")
        hints.append("FIX (files_modified): nullではなく変更ファイルパスを記入せよ:\n  files_modified:\n    - path/to/file.py")
    elif isinstance(fm, dict):
        errors.append("files_modified: is dict (must be string or list of file paths)")
        hints.append("FIX (files_modified): 文字列またはリスト形式で記入せよ:\n  files_modified: path/to/file.py\n  または\n  files_modified:\n    - path/to/file1.py\n    - path/to/file2.py")
    elif isinstance(fm, bool):
        errors.append(f"files_modified: is bool ({fm}), must be string or list of file paths")
    elif files_modified_has_fill_this(fm):
        errors.append("files_modified: FILL_THIS placeholder remaining (must fill actual file paths)")
    elif isinstance(fm, list) and len(fm) == 0 and data.get("status") == "completed":
        hints.append('GP-127 WARN: files_modified: [] (空リスト) — 変更ファイルを記入せよ。偵察のみの場合は文字列で "偵察のみ" と記入')

    parent_cmd_value = str(data.get("parent_cmd") or "")
    if parent_cmd_value and isinstance(fm, list) and len(fm) > 0:
        fm_paths = []
        for item in fm:
            if isinstance(item, dict):
                fm_paths.append(str(item.get("path", "")))
            elif isinstance(item, str):
                fm_paths.append(item)
        if fm_paths and not any(parent_cmd_value in os.path.basename(path) for path in fm_paths if path):
            hints.append(f"GP-202 WARN: files_modified内に{parent_cmd_value}を含むファイルが0件。別cmdの成果物を上書きしていないか確認せよ")

    lc = data.get("lesson_candidate")
    if lc is None and "lesson_candidate" in data:
        errors.append("lesson_candidate: null (must be dict with found/title/detail)")
    elif lc is not None:
        if isinstance(lc, str):
            errors.append("lesson_candidate: is string (must be dict with found/title/detail)")
            hints.append('FIX (lesson_candidate): dict形式で再記入せよ:\n  lesson_candidate:\n    found: true  # or false\n    title: "教訓タイトル"\n    detail: "詳細"')
        elif isinstance(lc, dict):
            if "found" not in lc:
                errors.append('lesson_candidate: missing "found" field')
            if not lc.get("found") and not lc.get("no_lesson_reason"):
                errors.append("lesson_candidate: found=false but no no_lesson_reason")
                hints.append('FIX (lesson_candidate): found: falseの場合はno_lesson_reasonが必須:\n  lesson_candidate:\n    found: false\n    no_lesson_reason: "既知のL084と同じパターンで新規教訓なし"')
            if not lc.get("found") and lc.get("no_lesson_reason"):
                reason = str(lc.get("no_lesson_reason", "")).strip()
                if len(reason) <= 3:
                    errors.append(f"lesson_candidate: no_lesson_reason too short ({len(reason)} chars, need >3)")
                    hints.append('FIX (lesson_candidate): no_lesson_reasonに具体的な理由を記入せよ。例: "既知のL084と同じパターン"')
                placeholder_values = ["なし", "特になし", "N/A", "n/a", "none", "None", "no", "No", "FILL_THIS"]
                if reason in placeholder_values:
                    errors.append(f'lesson_candidate: no_lesson_reason="{reason}" is placeholder (write a real reason)')
                    hints.append("FIX (lesson_candidate): プレースホルダ禁止。なぜ教訓がないのか具体的に書け")
            if lc.get("found") and not lc.get("title"):
                errors.append("lesson_candidate: found=true but no title")
            if lc.get("found") and not lc.get("detail") and not lc.get("summary"):
                errors.append("lesson_candidate: found=true but no detail or summary")
        else:
            errors.append(f"lesson_candidate: unexpected type {type(lc).__name__}")

    worker_id = data.get("worker_id", "")
    task_yaml_path = os.path.join(os.path.dirname(os.path.dirname(report_path)), "tasks", f"{worker_id}.yaml")
    task_data = {}
    try:
        if worker_id and os.path.exists(task_yaml_path):
            with open(task_yaml_path, encoding="utf-8") as task_file:
                raw = yaml.safe_load(task_file)
            task_data = (raw or {}).get("task", raw or {})
    except Exception:
        pass

    def metric_filled(metric) -> bool:
        if metric is None:
            return False
        if isinstance(metric, str):
            return bool(metric.strip())
        if isinstance(metric, dict):
            return any(str(v).strip() for v in metric.values() if v is not None)
        if isinstance(metric, list):
            return len(metric) > 0
        return True

    task_title = str(task_data.get("title") or "")
    task_type = str(task_data.get("task_type") or task_data.get("type") or task_data.get("scope_mode") or "").lower().strip()
    needs_before_after = (
        parent_cmd_value.startswith("cmd_karo_gp")
        or task_type in ("gp", "improvement")
        or task_title.startswith("GP")
        or task_title.startswith("強化")
        or task_title.startswith("改善")
        or "GP/" in task_title
    )
    if needs_before_after:
        if not metric_filled(data.get("before_metrics")):
            hints.append("GP-199 WARN: before_metrics未記入 — GP/改善cmdは実装前の計測値を記録せよ")
        if not metric_filled(data.get("after_metrics")):
            hints.append("GP-199 WARN: after_metrics未記入 — GP/改善cmdは実装後の計測値を記録せよ")
        regression = data.get("regression")
        if isinstance(regression, bool):
            regression_norm = "yes" if regression else "no"
        else:
            regression_norm = str(regression or "").strip().lower()
        if regression_norm not in ("yes", "no"):
            hints.append("GP-199 WARN: regression未記入 — GP/改善cmdは退化有無を yes/no で記録せよ")

    assigned_acs_raw = task_data.get("assigned_acs", "") or ""
    if isinstance(assigned_acs_raw, str) and assigned_acs_raw.strip():
        assigned_acs = {a.strip() for a in assigned_acs_raw.replace(",", " ").split()}

    lu = data.get("lessons_useful")
    if lu is None and "lessons_useful" in data:
        errors.append("lessons_useful: null (must be list of dicts, not null)")
        hints.append('FIX (lessons_useful): nullではなくリスト形式で記入せよ。テンプレート注入済み教訓を上書きするな:\n  lessons_useful:\n    - id: L074\n      useful: true\n      reason: "具体的な理由"')
    elif lu is not None:
        if isinstance(lu, str):
            errors.append("lessons_useful: is string (must be list of dicts)")
        elif isinstance(lu, list):
            if len(lu) == 0:
                rel = task_data.get("related_lessons", [])
                has_related = bool(rel and isinstance(rel, list) and len(rel) > 0)
                if has_related:
                    errors.append("lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな)")
                    hints.append("FIX (lessons_useful): report_field_set.sh経由でuseful/reasonを各教訓に記入せよ")
            for i, item in enumerate(lu):
                if isinstance(item, dict):
                    if str(item.get("useful", "")).strip() == "FILL_THIS" or str(item.get("reason", "")).strip() == "FILL_THIS":
                        errors.append(f"lessons_useful[{i}]: value is FILL_THIS placeholder (must fill actual values)")
                    if "id" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "id" field (must have lesson ID like L074)')
                        hints.append(f'FIX (lessons_useful[{i}]): id フィールド必須。テンプレート注入済みの教訓IDを確認せよ:\n  - id: L074\n    useful: true\n    reason: "理由"')
                    elif isinstance(item["id"], str) and not re.match(r'^L\d+$', item["id"]):
                        errors.append(f'lessons_useful[{i}]: id="{item["id"]}" is invalid (must match L+number, e.g. L074)')
                        hints.append(f'FIX (lessons_useful[{i}]): idはL+数字形式のみ。テンプレート注入済みの教訓IDを確認せよ')
                    if "useful" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "useful" field')
                        hints.append(f"FIX (lessons_useful[{i}]): useful: true or false を記入せよ")
                    elif not isinstance(item["useful"], bool):
                        errors.append(f"lessons_useful[{i}]: useful={item['useful']} is {type(item['useful']).__name__} (must be true or false)")
                        hints.append(f"FIX (lessons_useful[{i}]): useful: true または useful: false を指定せよ（文字列やnullは不可）")
                    if "reason" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "reason" field')
                        hints.append(f"FIX (lessons_useful[{i}]): reason フィールド必須。教訓が有用/無用な理由を具体的に記入せよ")
                    elif isinstance(item.get("reason"), str) and not item["reason"].strip():
                        errors.append(f"lessons_useful[{i}]: reason is empty (教訓が有用/無用な理由を具体的に書け)")
                        hints.append(f'FIX (lessons_useful[{i}]): reason: "L246のreturn 1罠と一致し、set -e呼出元確認の指針として有用" / "今回の変更では未使用。対象箇所と無関係" など具体的に記述')
                else:
                    errors.append(f"lessons_useful[{i}]: is {type(item).__name__} (must be dict)")
        elif isinstance(lu, dict):
            errors.append('lessons_useful: is dict (must be list). Use "- id: L001" not "0: {id: L001}". Numbered keys are not YAML lists')
            hints.append("FIX (lessons_useful): numbered dict を YAML list へ変換して再記入せよ。report_field_set.sh でテンプレート注入済みの list 形式を維持すること")
        else:
            errors.append(f"lessons_useful: unexpected type {type(lu).__name__} (must be list of dicts)")

    bc = data.get("binary_checks")
    if bc is None and "binary_checks" in data:
        errors.append("binary_checks: null (must be dict with AC entries)")
        hints.append('FIX (binary_checks): nullではなくdict形式で記入せよ:\n  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: "yes"')
    elif isinstance(bc, str):
        errors.append("binary_checks: is string (must be dict with AC entries)")
        hints.append('FIX (binary_checks): dict形式で再記入せよ:\n  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: "yes"')
    elif isinstance(bc, dict) and not bc:
        errors.append("binary_checks: empty dict (must have at least one AC entry)")
        hints.append('FIX (binary_checks): AC完了ごとに二値チェックを記入せよ:\n  binary_checks:\n    AC1:\n      - check: "確認内容を具体的に"\n        result: "yes"')
    elif isinstance(bc, dict):
        verdict_words = {"PASS", "FAIL", "OK", "NG", "yes", "no", "YES", "NO", "true", "false", "True", "False", "pass", "fail", "ok", "ng"}
        for ac_key, ac_val in bc.items():
            if not isinstance(ac_val, list):
                errors.append(f"binary_checks.{ac_key}: is {type(ac_val).__name__} (must be list of check items)")
                hints.append(f'FIX (binary_checks.{ac_key}): list形式で記入せよ:\n  binary_checks:\n    {ac_key}:\n      - check: "確認内容"\n        result: "yes"')
            else:
                for j, check_item in enumerate(ac_val):
                    if isinstance(check_item, list):
                        errors.append(f"binary_checks.{ac_key}[{j}]: nested list detected (- - check: pattern). autofix対象")
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}]): "- - check:" を "- check:" に修正せよ(余分な"-"を削除)')
                        continue
                    if not isinstance(check_item, dict):
                        continue
                    if "check" not in check_item:
                        errors.append(f'binary_checks.{ac_key}[{j}]: missing "check" field')
                    if "result" not in check_item:
                        errors.append(f'binary_checks.{ac_key}[{j}]: missing "result" field')
                    ck = check_item.get("check", "")
                    rs = check_item.get("result", "")
                    if isinstance(ck, str) and ck.strip() in verdict_words:
                        errors.append(f'binary_checks.{ac_key}[{j}].check: "{ck}" は確認項目ではない。PASS/FAILではなく「何を確認したか」を書け')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}]): check に確認内容を書け。result に yes/no を書け。\n  例: {{check: "_pane_offset変数が除去されたか", result: "yes"}}')
                    elif isinstance(ck, str) and 0 < len(ck.strip()) < 5:
                        errors.append(f'binary_checks.{ac_key}[{j}].check: "{ck}" が短すぎる(確認内容を具体的に書け)')
                    elif isinstance(ck, str) and ("<<REPLACE" in ck or "FILL:" in ck):
                        errors.append(f"binary_checks.{ac_key}[{j}].check: プレースホルダ残存。具体的な確認内容に書き換えよ")
                    if isinstance(rs, str) and not rs.strip():
                        errors.append(f'binary_checks.{ac_key}[{j}].result: 空文字。"yes" または "no" を記入せよ')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): 確認結果を "yes" or "no" で記入せよ\n  ★引用符なし: result: yes（result: \'yes\' はNG。YAMLでは引用符付き文字列になる）')
                    elif isinstance(rs, str) and rs.strip().lower() not in ("yes", "no"):
                        errors.append(f'binary_checks.{ac_key}[{j}].result: "{rs[:40]}" は不正。"yes" または "no" のみ')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): "yes" or "no" のみ。自由記述は acceptance_criteria.detail に書け\n  ★引用符なし: result: yes（result: \'yes\' はNG。YAMLでは引用符付き文字列になる）')
    elif isinstance(bc, list) and not bc:
        errors.append("binary_checks: empty list (must have at least one entry)")

    if isinstance(bc, dict) and bc:
        rpt_bc_count = 0
        for key, value in bc.items():
            if assigned_acs and key != "commit" and key not in assigned_acs:
                continue
            if isinstance(value, list):
                rpt_bc_count += len(value)
        task_bc_count = 0
        tbc = task_data.get("binary_checks", {})
        if isinstance(tbc, dict):
            for key, value in tbc.items():
                if assigned_acs and key != "commit" and key not in assigned_acs:
                    continue
                if isinstance(value, list):
                    task_bc_count += len(value)
        if task_bc_count > 0:
            if rpt_bc_count < task_bc_count * 0.5:
                errors.append(f"binary_checks: item count {rpt_bc_count}/{task_bc_count} (<50% of task template)")
                hints.append(f"FIX (binary_checks): task YAMLに{task_bc_count}件の確認項目がある。全項目にresultを記入せよ")
            elif rpt_bc_count < task_bc_count:
                hints.append(f"GP-131 WARN: binary_checks item count {rpt_bc_count}/{task_bc_count} (task templateより少ない)")
        else:
            ac_count = 0
            ac_list = task_data.get("acceptance_criteria", [])
            if isinstance(ac_list, list):
                if assigned_acs:
                    ac_count = sum(1 for ac in ac_list if isinstance(ac, dict) and ac.get("id", "") in assigned_acs)
                else:
                    ac_count = len(ac_list)
            if ac_count > 0:
                rpt_ac_keys = [k for k in bc.keys() if k.upper().startswith("AC")]
                # Fallback: description配下にAC1/AC2等のcheckが格納されている場合もカウント
                if not rpt_ac_keys and "description" in bc and isinstance(bc["description"], list):
                    ac_in_desc = set()
                    for item in bc["description"]:
                        if isinstance(item, dict):
                            chk = item.get("check", "")
                            m = re.match(r"(AC\d+)", str(chk))
                            if m:
                                ac_in_desc.add(m.group(1))
                    rpt_ac_keys = list(ac_in_desc)
                if assigned_acs:
                    rpt_ac_keys = [k for k in rpt_ac_keys if k in assigned_acs]
                if len(rpt_ac_keys) == 0:
                    errors.append(f"binary_checks: AC self-verification missing (0/{ac_count} ACs). 全ACの二値チェックを記入せよ")
                    hints.append(f"FIX (binary_checks): task YAMLに{ac_count}件のACがある。AC1, AC2, ... のセクションを追加し各result=yes/noを記入")
                elif len(rpt_ac_keys) < ac_count:
                    hints.append(f"GP-131b WARN: binary_checks has {len(rpt_ac_keys)} AC sections but task has {ac_count} ACs")

    if "purpose_validation" not in data:
        errors.append("purpose_validation: MISSING")
        hints.append('FIX (purpose_validation): cmdの目的との適合を記入せよ:\n  purpose_validation:\n    cmd_purpose: "cmdの目的"\n    fit: true\n    purpose_gap: ""')
    elif data.get("purpose_validation") is None:
        errors.append("purpose_validation: null (must be dict with fit/reason)")

    status_val = data.get("status", "")
    if isinstance(status_val, str) and status_val.strip().lower() == "pending":
        errors.append('status: "pending" はテンプレート初期値。完了後に "completed" に更新せよ')
        hints.append("FIX (status): bash scripts/report_field_set.sh <report> status completed")

    result = data.get("result", {})
    if isinstance(result, dict):
        summary = result.get("summary")
        if not summary:
            errors.append("result.summary: MISSING or empty")
        elif isinstance(summary, str) and summary.strip() == "FILL_THIS":
            errors.append("result.summary: FILL_THIS placeholder remaining (must fill actual summary)")
    else:
        errors.append("result: not a dict")

    verdict = data.get("verdict")
    _VALID_VERDICTS = ("PASS", "FAIL", "PASS_NO_IMPROVEMENT")
    if not isinstance(verdict, str) or verdict not in _VALID_VERDICTS:
        errors.append(f'verdict: "{verdict}" is not valid (must be "PASS", "FAIL", or "PASS_NO_IMPROVEMENT")')
        hints.append("verdictはPASS/FAIL/PASS_NO_IMPROVEMENTの三値のみ。binary_checks全yes→PASS、1つでもno→FAIL、revert多数→PASS_NO_IMPROVEMENT")

    if isinstance(verdict, str) and verdict in _VALID_VERDICTS and isinstance(bc, dict) and bc:
        bc_has_no = False
        bc_has_empty = False
        bc_results_found = False
        for ac_key, ac_val in bc.items():
            if assigned_acs and ac_key != "commit" and ac_key not in assigned_acs:
                continue
            if isinstance(ac_val, list):
                for item in ac_val:
                    if isinstance(item, dict):
                        result_value = item.get("result")
                        if result_value is None or (isinstance(result_value, str) and not result_value.strip()):
                            bc_has_empty = True
                        if "result" in item:
                            bc_results_found = True
                            result_norm = str(item["result"]).strip().lower()
                            if result_norm in ("no", "false", "fail", "ng"):
                                waive = item.get("waive_reason", "")
                                if not (isinstance(waive, str) and waive.strip()):
                                    bc_has_no = True
        if verdict == "PASS" and bc_has_empty:
            errors.append('verdict: PASS but binary_checks contain empty result(s) (全result記入後にverdictを設定せよ)')
            hints.append('FIX (verdict-BC矛盾): verdict=PASSの前にbinary_checksの全result欄を"yes"/"no"で埋めよ')
        if bc_results_found:
            if verdict == "PASS" and bc_has_no:
                errors.append('verdict: PASS but binary_checks contain "no" results (verdict must be FAIL when any check fails)')
                hints.append('FIX (verdict): binary_checksにno/fail/ngがある場合はverdict: FAILにせよ')
            elif verdict == "FAIL" and not bc_has_no:
                hints.append('GP-128 WARN: verdict=FAIL but all binary_checks are "yes" — 外部制約によるFAILか確認せよ')

    # ─── binary_checks 客観裏付けチェック(a)(b)(c) [cmd_2124] ───
    # WARNのみ（段階的導入。BLOCKなし）
    if isinstance(bc, dict) and bc:
        _pc_for_check = str(data.get("parent_cmd", "") or "").strip()

        # (a) files_modifiedが空なのにbinary_checks全yes → WARN
        try:
            _fm = data.get("files_modified")
            _fm_empty = (
                _fm is None
                or (isinstance(_fm, list) and len(_fm) == 0)
                or (isinstance(_fm, str) and _fm.strip() in ("", "null", "[]"))
            )
            if _fm_empty:
                _bc_all_yes = True
                _bc_has_entries = False
                for _ac_items_a in bc.values():
                    if isinstance(_ac_items_a, list):
                        for _item_a in _ac_items_a:
                            if isinstance(_item_a, dict) and "result" in _item_a:
                                _bc_has_entries = True
                                if str(_item_a.get("result", "")).strip().lower() != "yes":
                                    _bc_all_yes = False
                if _bc_has_entries and _bc_all_yes:
                    hints.append(
                        "GP-201a WARN: files_modifiedが空なのにbinary_checks全yes — "
                        "変更ファイルを確認せよ。未コミット or files_modified未記入の可能性"
                    )
        except Exception:
            pass

        # (b) commit+pushのACがyesなのにgit logにcmd_idを含むcommitがない → WARN
        try:
            _commit_ac_yes = False
            for _ac_items_b in bc.values():
                if isinstance(_ac_items_b, list):
                    for _item_b in _ac_items_b:
                        if isinstance(_item_b, dict):
                            _chk_b = str(_item_b.get("check", "")).lower()
                            _rs_b = str(_item_b.get("result", "")).strip().lower()
                            if _rs_b == "yes" and any(kw in _chk_b for kw in ("commit", "push")):
                                _commit_ac_yes = True
            if _commit_ac_yes and _pc_for_check:
                _git_cwd = os.path.dirname(os.path.abspath(report_path))
                _log_res = subprocess.run(
                    ["git", "log", "--oneline", "-30"],
                    capture_output=True, text=True, timeout=5, cwd=_git_cwd,
                )
                if _log_res.returncode == 0 and _pc_for_check not in _log_res.stdout:
                    hints.append(
                        f"GP-201b WARN: commit+push ACがyesだが直近30コミットに{_pc_for_check}が見つからない — "
                        "pushが完了しているか確認せよ"
                    )
        except Exception:
            pass

        # (c) テスト全PASSのACがyesなのにtest_resultsが空 → WARN
        try:
            _test_ac_yes = False
            for _ac_items_c in bc.values():
                if isinstance(_ac_items_c, list):
                    for _item_c in _ac_items_c:
                        if isinstance(_item_c, dict):
                            _chk_c = str(_item_c.get("check", "")).lower()
                            _rs_c = str(_item_c.get("result", "")).strip().lower()
                            if _rs_c == "yes" and any(kw in _chk_c for kw in ("test", "テスト", "bats", "pass")):
                                _test_ac_yes = True
            if _test_ac_yes:
                _tr = data.get("test_results")
                _tr_empty = (
                    _tr is None
                    or (isinstance(_tr, dict) and not _tr)
                    or (isinstance(_tr, str) and _tr.strip() in ("", "null", "{}"))
                )
                if _tr_empty:
                    hints.append(
                        "GP-201c WARN: テスト全PASS ACがyesだがtest_resultsが空 — "
                        "テスト実行結果をtest_resultsに記録せよ"
                    )
        except Exception:
            pass

    ai = data.get("assumption_invalidation")
    if ai is None and "assumption_invalidation" in data:
        errors.append("assumption_invalidation: null (must be dict with found/affected_cmds/detail)")
    elif ai is not None:
        if not isinstance(ai, dict):
            errors.append(f"assumption_invalidation: is {type(ai).__name__} (must be dict)")
        else:
            for ai_field in ["found", "affected_cmds", "detail"]:
                if ai_field not in ai:
                    errors.append(f'assumption_invalidation: missing "{ai_field}" field')
            ai_found = ai.get("found")
            ai_cmds = ai.get("affected_cmds")
            if ai_found is True and isinstance(ai_cmds, list) and len(ai_cmds) == 0:
                errors.append("assumption_invalidation: found=true but affected_cmds is empty (影響cmdを列挙せよ)")
                hints.append("FIX (assumption_invalidation): found:trueの場合、affected_cmdsに影響を受けるcmd_IDを列挙せよ")
    elif "assumption_invalidation" not in data:
        errors.append("assumption_invalidation: MISSING")
        hints.append('FIX (assumption_invalidation): テンプレートに生成済み。上書きで消すな:\n  assumption_invalidation:\n    found: false\n    affected_cmds: []\n    detail: ""')

    kc = data.get("knowledge_candidate")
    if kc is not None:
        if not isinstance(kc, dict):
            errors.append(f"knowledge_candidate: is {type(kc).__name__} (must be dict)")
        else:
            if kc.get("found") is True:
                kc_items = kc.get("items", [])
                if not isinstance(kc_items, list) or len(kc_items) == 0:
                    errors.append("knowledge_candidate: found=true but items is empty")
                    hints.append('FIX (knowledge_candidate): found:true時はitemsに事実データを列挙せよ:\n  knowledge_candidate:\n    found: true\n    items:\n      - fact: "発見した事実"\n        source: "確認元"')
                elif isinstance(kc_items, list):
                    for i, item in enumerate(kc_items):
                        if isinstance(item, dict) and not str(item.get("fact", "")).strip():
                            errors.append(f"knowledge_candidate.items[{i}].fact: empty")

    sgc = data.get("self_gate_check")
    if sgc is not None:
        if not isinstance(sgc, dict):
            errors.append(f"self_gate_check: is {type(sgc).__name__} (must be dict)")
            hints.append('FIX (self_gate_check): dict形式で記入せよ:\n  self_gate_check:\n    lesson_ref: PASS\n    lesson_candidate: PASS\n    status_valid: PASS\n    purpose_fit: PASS\n  各項目はPASS/FAILの二値')
        else:
            required_sgc_keys = ("lesson_ref", "lesson_candidate", "status_valid", "purpose_fit")
            valid_sgc_values = {"PASS", "FAIL"}
            required_sgc_key_text = ", ".join(required_sgc_keys)
            for required_sgc_key in required_sgc_keys:
                if required_sgc_key not in sgc:
                    errors.append(
                        f'self_gate_check: missing required key "{required_sgc_key}" '
                        f"(required: {required_sgc_key_text})"
                    )
                    hints.append(
                        "FIX (self_gate_check): 必須4キーを全て記入せよ:\n"
                        "  self_gate_check:\n"
                        "    lesson_ref: PASS\n"
                        "    lesson_candidate: PASS\n"
                        "    status_valid: PASS\n"
                        "    purpose_fit: PASS"
                    )
            for sgc_key, sgc_val in sgc.items():
                sgc_str = str(sgc_val).strip() if sgc_val is not None else ""
                if sgc_str == "":
                    errors.append(f"self_gate_check.{sgc_key}: empty (must be PASS or FAIL)")
                    hints.append(f"FIX: self_gate_check.{sgc_key} に PASS or FAIL を記入せよ")
                elif sgc_str not in valid_sgc_values:
                    errors.append(f'self_gate_check.{sgc_key}: "{sgc_str}" is not valid (must be "PASS" or "FAIL")')
                    hints.append(f'FIX: Change self_gate_check.{sgc_key} from "{sgc_str}" to "PASS" or "FAIL"')

    filename = os.path.basename(report_path)
    fname_match = re.search(r"_report_(.+?)\.ya?ml", filename)
    parent_cmd = data.get("parent_cmd", "")
    if fname_match and parent_cmd:
        fname_cmd = fname_match.group(1)
        if not fname_cmd.startswith(str(parent_cmd) + "_") and fname_cmd != str(parent_cmd):
            errors.append(f"stale_report: filename has {fname_cmd} but parent_cmd={parent_cmd} (cmd_id mismatch)")

    report_text = json.dumps(data, ensure_ascii=False, default=str)
    other_cmds = set(re.findall(r"cmd_(?:[a-zA-Z_]*\d)[a-zA-Z0-9_]*", report_text)) - {str(parent_cmd)}
    if other_cmds and parent_cmd:
        stale_cmds = [cmd for cmd in other_cmds if not cmd.startswith(str(parent_cmd))]
        if stale_cmds:
            hints.append(f"GP-062 WARN: 報告内に別cmdの参照あり: {sorted(stale_cmds)} — staleコンテンツの可能性を確認せよ")

    if result and isinstance(result, dict):
        details_text = str(result.get("details", "")) + " " + str(result.get("summary", ""))
        for indicator in ["PE経由", "PE fallback", "PEフォールバック", "PE経由でフル実行", "use_pe_mode"]:
            if indicator in details_text:
                hints.append(f'PI-012 WARN: 報告にPE使用の痕跡あり("{indicator}")。GS探索でPE使用は禁止(cmd_1349)。batch pathの修正が必要')
                break

    seen_bases = set()
    deduped = []
    for hint in hints:
        base = re.sub(r"\[\d+\]", "[*]", hint)
        if base not in seen_bases:
            seen_bases.add(base)
            deduped.append(re.sub(r"\[\d+\]", "[N]", hint))
    hints = deduped

    if errors:
        print("FAIL: " + "; ".join(errors))
        for hint in hints:
            print(hint)
        return 1

    # --- PASS_NO_IMPROVEMENT detection (cmd_2072) ---
    # binary_checksでrevert含むACが全ACの50%以上の場合に発動
    _no_improvement = False
    if isinstance(bc, dict) and bc:
        _ac_keys = [k for k in bc.keys() if k.upper().startswith("AC")]
        if _ac_keys:
            _revert_acs = []
            for _ac_key in _ac_keys:
                _ac_items = bc.get(_ac_key, [])
                if isinstance(_ac_items, list):
                    for _item in _ac_items:
                        if isinstance(_item, dict):
                            if "revert" in str(_item.get("check", "")).lower():
                                _revert_acs.append(_ac_key)
                                break
            if len(_revert_acs) >= len(_ac_keys) * 0.5:
                _no_improvement = True

    if _no_improvement:
        print("PASS_NO_IMPROVEMENT")
        print(
            f"WARN: revertが検出されたAC={len(_revert_acs)}/{len(_ac_keys)}件(50%以上)。"
            "改善未達成。家老に改善未達成を通知せよ。"
        )
    else:
        print("PASS")
    for hint in hints:
        print(hint)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
