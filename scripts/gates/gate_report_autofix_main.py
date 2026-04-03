#!/usr/bin/env python3
"""gate_report_autofix_main.py - Python implementation for gate_report_autofix.sh."""

from __future__ import annotations

import os
import re
import sys

import yaml


SafeLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
SafeDumper = getattr(yaml, "CSafeDumper", yaml.SafeDumper)
DumpAll = getattr(yaml, "dump_all")


def main() -> int:
    report_path = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        with open(report_path, encoding="utf-8") as f:
            raw = f.read()
        data = yaml.load(raw, Loader=SafeLoader)
    except Exception as exc:
        print(f"UNFIXABLE: YAML parse error: {exc}")
        return 1

    if not data or not isinstance(data, dict):
        print("UNFIXABLE: report is empty or not a dict")
        return 1

    fixes: list[str] = []
    digit_key_re = re.compile(r"^\[?\d+\]?$")
    task_yaml_cache: dict[str, dict | None] = {}
    task_binary_check_map_cache: dict[str, dict[str, list]] = {}

    def get_task_data(worker_id: str) -> dict | None:
        if worker_id in task_yaml_cache:
            return task_yaml_cache[worker_id]

        result = None
        if worker_id:
            tpath = os.path.join(os.path.dirname(os.path.dirname(report_path)), "tasks", f"{worker_id}.yaml")
            if os.path.exists(tpath):
                try:
                    with open(tpath, encoding="utf-8") as tf:
                        tdata = yaml.load(tf, Loader=SafeLoader)
                    result = tdata if not isinstance(tdata, dict) or "task" not in tdata else tdata.get("task", {})
                except Exception:
                    pass

        task_yaml_cache[worker_id] = result
        return result

    def task_binary_check_map(worker_id: str) -> dict[str, list]:
        if worker_id in task_binary_check_map_cache:
            return task_binary_check_map_cache[worker_id]

        task = get_task_data(worker_id)
        mapping: dict[str, list] = {}
        if isinstance(task, dict):
            acs = task.get("acceptance_criteria", [])
            if isinstance(acs, list):
                for ac_item in acs:
                    if not isinstance(ac_item, dict):
                        continue
                    ac_id = ac_item.get("id")
                    bc_list = ac_item.get("binary_checks", [])
                    if ac_id and isinstance(bc_list, list):
                        mapping[str(ac_id)] = bc_list

        task_binary_check_map_cache[worker_id] = mapping
        return mapping

    if "report" in data and isinstance(data["report"], dict):
        inner = data.pop("report")
        data.update(inner)
        fixes.append("report:ラップ→フラット化")

    if not data.get("worker_id"):
        basename = os.path.basename(report_path)
        m20 = re.match(r"^([a-z_]+?)_report(?:_cmd_.+)?\.yaml$", basename)
        if m20:
            data["worker_id"] = m20.group(1)
            fixes.append(f"worker_id ファイル名から推定({m20.group(1)})")

    if not data.get("parent_cmd"):
        basename = os.path.basename(report_path)
        m20p = re.match(r"^[a-z_]+?_report_(cmd_.+)\.yaml$", basename)
        if m20p:
            data["parent_cmd"] = m20p.group(1)
            fixes.append(f"parent_cmd ファイル名から推定({m20p.group(1)})")
        else:
            worker20 = data.get("worker_id", "")
            task20 = get_task_data(worker20)
            if task20:
                pcmd20 = task20.get("parent_cmd", "")
                if pcmd20:
                    data["parent_cmd"] = str(pcmd20)
                    fixes.append(f"parent_cmd タスクYAMLから補完({pcmd20})")

    lu = data.get("lessons_useful")
    if isinstance(lu, dict):
        lu_keys_str = {str(k) for k in lu.keys()}
        known_fields = {"id", "useful", "reason"}
        lesson_id_re = re.compile(r"^L\d+$")

        converted = None
        fix_label = ""

        if not lu:
            converted = []
            fix_label = "lessons_useful 空dict→空list変換"
        elif lu_keys_str & known_fields:
            converted = [dict(lu)]
            fix_label = "lessons_useful 単一dict→list wrap"
            if not all(converted[0].get(k) == v for k, v in lu.items()):
                converted = None
        elif all(lesson_id_re.match(str(k)) for k in lu.keys()):
            new_list = []
            for key in sorted(lu.keys(), key=str):
                val = lu[key]
                if isinstance(val, dict):
                    entry = dict(val)
                    if "id" not in entry:
                        entry["id"] = str(key)
                    new_list.append(entry)
                else:
                    new_list.append({"id": str(key)})
            converted = new_list
            fix_label = "lessons_useful LessonIDキーdict→list変換(id注入)"
            ok = len(converted) == len(lu)
            if ok:
                for item in converted:
                    lid = item.get("id", "")
                    if lid in lu and isinstance(lu[lid], dict):
                        if not all(item.get(fk) == fv for fk, fv in lu[lid].items()):
                            ok = False
                            break
            if not ok:
                converted = None
        else:
            try:
                sorted_keys = sorted(
                    lu.keys(),
                    key=lambda key: (0, int(str(key))) if str(key).isdigit() else (1, str(key)),
                )
            except (ValueError, TypeError):
                sorted_keys = sorted(lu.keys(), key=str)
            converted = [lu[key] for key in sorted_keys]
            fix_label = "lessons_useful dict→list変換"
            if len(converted) != len(lu):
                converted = None

        if converted is not None:
            data["lessons_useful"] = converted
            fixes.append(fix_label)

    lu = data.get("lessons_useful")
    if isinstance(lu, list) and lu:
        unknown_ids: list[int] = []
        for idx, item in enumerate(lu):
            if isinstance(item, dict):
                lid = str(item.get("id", ""))
                if not lid or lid.startswith("UNKNOWN") or lid == "None":
                    unknown_ids.append(idx)
        if unknown_ids:
            task_lesson_ids: list[str] = []
            worker = data.get("worker_id", "")
            task14 = get_task_data(worker)
            if task14:
                rl = task14.get("related_lessons", [])
                if isinstance(rl, list):
                    task_lesson_ids = [str(r.get("id", "")) for r in rl if isinstance(r, dict) and r.get("id")]
            lu_fixed = False
            for pos in unknown_ids:
                lid = str(lu[pos].get("id", ""))
                num = -1
                if lid.startswith("UNKNOWN_"):
                    try:
                        num = int(lid.split("_")[1])
                    except (ValueError, IndexError):
                        pass
                if 0 <= num < len(task_lesson_ids):
                    lu[pos]["id"] = task_lesson_ids[num]
                    lu_fixed = True
                elif (not lid or lid == "None") and pos < len(task_lesson_ids):
                    lu[pos]["id"] = task_lesson_ids[pos]
                    lu_fixed = True
            if lu_fixed:
                fixes.append(f"lessons_useful id UNKNOWN→タスクYAML参照解決({len(unknown_ids)}件)")

    fm = data.get("files_modified")
    if isinstance(fm, str) and fm.strip():
        data["files_modified"] = [{"path": fm.strip(), "change": "modified"}]
        fixes.append("files_modified string→dict変換(単一ファイル)")
    elif isinstance(fm, list):
        needs_fix = False
        new_fm = []
        for item in fm:
            if isinstance(item, str):
                new_fm.append({"path": item, "change": "modified"})
                needs_fix = True
            else:
                new_fm.append(item)
        if needs_fix:
            data["files_modified"] = new_fm
            fixes.append("files_modified string→dict変換")

    lu = data.get("lessons_useful")
    if isinstance(lu, list):
        for idx, item in enumerate(lu):
            if isinstance(item, dict) and "id" not in item:
                item["id"] = f"UNKNOWN_{idx}"
                fixes.append(f"lessons_useful[{idx}]: id=UNKNOWN_{idx}仮付番")

    bc = data.get("binary_checks")
    if isinstance(bc, dict):
        bc_fixed = False
        for ac_key, ac_val in bc.items():
            if not isinstance(ac_val, str):
                continue
            converted = None
            try:
                parsed = yaml.load(ac_val, Loader=SafeLoader)
                if isinstance(parsed, list):
                    converted = parsed
                elif isinstance(parsed, dict):
                    converted = [parsed]
            except Exception:
                pass
            if converted is None:
                match = re.search(r"check:\s*(.+?)\s*,\s*result:\s*(.+)", ac_val)
                if match:
                    converted = [{"check": match.group(1).strip(), "result": match.group(2).strip()}]
            if converted is None and ac_val.strip():
                converted = [{"check": ac_val.strip(), "result": "yes"}]
            if converted is not None:
                bc[ac_key] = converted
                bc_fixed = True
        if bc_fixed:
            fixes.append("binary_checks string→list変換")

    def task_binary_checks_for(ac_key: str) -> list:
        worker = data.get("worker_id", "")
        return task_binary_check_map(worker).get(ac_key, [])

    bc = data.get("binary_checks")
    bc_pass_count = 0
    bc_fail_count = 0
    bc_result_total = 0
    bc_result_filled = 0
    if isinstance(bc, dict):
        bc_dict_fixed = False
        bc15_fixed = False
        bc_bool_fixed = False
        bc19_fixed = False
        str_fixed = False
        pass_vals = {"pass", "ok", "true", "yes", "done", "clear", "n/a", "na"}
        fail_vals = {"fail", "false", "no", "ng", "block"}

        for ac_key, ac_val in bc.items():
            if isinstance(ac_val, dict):
                ac_val = [ac_val]
                bc[ac_key] = ac_val
                bc_dict_fixed = True
            if not isinstance(ac_val, list):
                continue

            needs_numbered_convert = any(
                isinstance(chk, dict)
                and len(chk) > 1
                and sum(1 for key in chk.keys() if digit_key_re.match(str(key))) == len(chk)
                for chk in ac_val
            )
            if needs_numbered_convert:
                task_checks = task_binary_checks_for(ac_key)
                new_list = []
                for chk in ac_val:
                    if isinstance(chk, dict):
                        for idx, (key, value) in enumerate(sorted(chk.items(), key=lambda pair: str(pair[0]))):
                            result_val = value.get("result", "yes") if isinstance(value, dict) else value
                            check_name = ""
                            if idx < len(task_checks):
                                tc = task_checks[idx]
                                check_name = tc.get("check", tc) if isinstance(tc, dict) else str(tc)
                            if not check_name:
                                check_name = f"{ac_key}_check_{idx}"
                            new_list.append({"check": check_name, "result": result_val})
                    else:
                        new_list.append(chk)
                if new_list:
                    ac_val = new_list
                    bc[ac_key] = ac_val
                    bc19_fixed = True

            new_list = []
            for chk in ac_val:
                item = chk
                if isinstance(chk, dict) and len(chk) == 1:
                    key, value = next(iter(chk.items()))
                    if key not in ("check", "result"):
                        item = {"check": str(key), "result": value if isinstance(value, bool) else str(value)}
                        bc15_fixed = True
                if isinstance(item, dict):
                    result = item.get("result")
                    if isinstance(result, bool):
                        item["result"] = "yes" if result else "no"
                        bc_bool_fixed = True
                    elif isinstance(result, str):
                        lowered = result.strip().lower()
                        if lowered in pass_vals and result != "yes":
                            item["result"] = "yes"
                            str_fixed = True
                        elif lowered in fail_vals and result != "no":
                            item["result"] = "no"
                            str_fixed = True

                    norm = item.get("result")
                    if isinstance(norm, str):
                        bc_result_total += 1
                        if norm == "yes":
                            bc_pass_count += 1
                            bc_result_filled += 1
                        elif norm == "no":
                            bc_fail_count += 1
                            bc_result_filled += 1
                    elif norm is not None:
                        bc_result_total += 1
                new_list.append(item)
            bc[ac_key] = new_list

        if bc_dict_fixed:
            fixes.append("binary_checks dict→list wrap")
        if bc15_fixed:
            fixes.append("binary_checks {name:val}→{check:name,result:val}正規化")
        if bc_bool_fixed:
            fixes.append("binary_checks result boolean→string変換")
        if bc19_fixed:
            fixes.append("binary_checks [N]キー→check/result正規化")
        if str_fixed:
            fixes.append("binary_checks result文字列正規化(PASS/ok→yes, FAIL/ng→no)")

    lc = data.get("lesson_candidate")
    if isinstance(lc, list):
        if len(lc) == 0:
            data["lesson_candidate"] = {
                "found": False,
                "no_lesson_reason": "",
                "title": "",
                "detail": "",
            }
            fixes.append("lesson_candidate list→dict変換(空list→found:false)")
        elif isinstance(lc[0], dict):
            first = lc[0]
            data["lesson_candidate"] = {
                "found": first.get("found", True),
                "no_lesson_reason": first.get("no_lesson_reason", ""),
                "title": first.get("title", ""),
                "detail": first.get("detail", ""),
            }
            fixes.append(f"lesson_candidate list→dict変換({len(lc)}要素)")

    lu_missing = "lessons_useful" not in data
    lu_null = "lessons_useful" in data and data["lessons_useful"] is None
    if lu_missing or lu_null:
        skeleton = []
        worker6 = data.get("worker_id", "")
        task6 = get_task_data(worker6)
        if task6:
            rl6 = task6.get("related_lessons", [])
            if isinstance(rl6, list):
                for item6 in rl6:
                    if isinstance(item6, dict) and item6.get("id"):
                        skeleton.append({"id": str(item6["id"]), "useful": False, "reason": ""})
        data["lessons_useful"] = skeleton if skeleton else []
        label6 = "MISSING" if lu_missing else "null"
        if skeleton:
            fixes.append(f"lessons_useful {label6}→タスクYAMLからスケルトン生成({len(skeleton)}件)")
        else:
            fixes.append(f"lessons_useful {label6}→空list")

    verdict_val = data.get("verdict")
    is_valid_verdict = isinstance(verdict_val, str) and verdict_val in ("PASS", "FAIL")
    verdict_blank = verdict_val is None or (isinstance(verdict_val, str) and not verdict_val.strip())
    if verdict_blank and "verdict" in data:
        bc = data.get("binary_checks")
        if isinstance(bc, dict) and bc_result_total > 0 and bc_result_total == bc_result_filled:
            data["verdict"] = "FAIL" if bc_fail_count > 0 else "PASS"
            fixes.append(f"verdict推定({bc_pass_count}PASS/{bc_fail_count}FAIL)")
            is_valid_verdict = True
    elif not is_valid_verdict and "verdict" in data:
        bc = data.get("binary_checks")
        if isinstance(bc, dict) and (bc_pass_count + bc_fail_count > 0):
            data["verdict"] = "FAIL" if bc_fail_count > 0 else "PASS"
            fixes.append(f"verdict推定({bc_pass_count}PASS/{bc_fail_count}FAIL)")
            is_valid_verdict = True

    status_val = data.get("status")
    if is_valid_verdict and isinstance(status_val, str) and status_val.strip().lower() == "pending":
        data["status"] = "completed"
        fixes.append("status pending→completed")

    sgc = data.get("self_gate_check")
    if isinstance(sgc, dict):
        pass_map = {"ok", "yes", "true", "pass", "o", "○"}
        fail_map = {"ng", "no", "false", "fail", "x", "×"}
        changed = False
        for key, value in sgc.items():
            if not isinstance(value, str):
                continue
            lowered = value.strip().lower()
            if lowered in pass_map and value != "PASS":
                sgc[key] = "PASS"
                changed = True
            elif lowered in fail_map and value != "FAIL":
                sgc[key] = "FAIL"
                changed = True
        if changed:
            data["self_gate_check"] = sgc
            fixes.append("self_gate_check値正規化(ok/yes→PASS)")

    if fixes:
        data["autofix_applied"] = fixes
        with open(report_path, "w", encoding="utf-8") as f:
            DumpAll([data], f, Dumper=SafeDumper, allow_unicode=True, default_flow_style=False, sort_keys=False)
        print("AUTO-FIXED: " + "; ".join(fixes))
    else:
        print("NO-FIX-NEEDED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
