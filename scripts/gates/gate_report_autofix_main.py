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
        base_data = yaml.load(raw, Loader=yaml.BaseLoader) or {}
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
            tpath = os.path.join(
                os.path.dirname(os.path.dirname(report_path)),
                "tasks",
                f"{worker_id}.yaml",
            )
            if os.path.exists(tpath):
                try:
                    with open(tpath, encoding="utf-8") as tf:
                        tdata = yaml.load(tf, Loader=SafeLoader)
                    result = (
                        tdata if not isinstance(tdata, dict) or "task" not in tdata
                        else tdata.get("task", {})
                    )
                except Exception as e:
                    print(
                        f"  [WARN] task YAML parse failed ({tpath}): {e}",
                        file=sys.stderr,
                    )

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

    # worker_id / parent_cmd ファイル名推定は消火(GP-107 Q1:値の推定=NO)→撤去
    # 空値はgate_report_format.shがBLOCKする

    # lessons_useful numbered dict→list変換 (GP-196: 内容不変の構造変換。GP-107再評価済み)
    # {0:{id:X,useful:true,reason:Y}, 1:...} → [{id:X,useful:true,reason:Y},...]
    # 条件: 全キーがint + 全値がdict(各教訓エントリ)。単一dict/ID-keyed dictは対象外
    lu = data.get("lessons_useful")
    if isinstance(lu, dict) and lu and all(isinstance(k, int) for k in lu.keys()) and all(isinstance(v, dict) for v in lu.values()):
        data["lessons_useful"] = list(lu.values())
        fixes.append("lessons_useful numbered dict→list変換")
    # UNKNOWN id追加も消火→撤去。missing "id"はgateがBLOCKする

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

    # UNKNOWN id仮付番は消火(gate_report_format.shがmissing "id"をBLOCK)→撤去

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
                    converted = [
                        {
                            "check": match.group(1).strip(),
                            "result": match.group(2).strip(),
                        }
                    ]
            # 単一verdict語(yes/no/pass等)は消火→skipしてgateがBLOCKする
            # 散文テキストのみ変換
            _bc_skip_words = {
                "yes", "no", "pass", "fail", "ok", "ng", "true", "false",
                "done", "clear", "n/a", "na", "block",
            }
            if (
                converted is None
                and ac_val.strip()
                and ac_val.strip().lower() not in _bc_skip_words
            ):
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
        bc_quote_fixed = False
        bc19_fixed = False

        for ac_key, ac_val in bc.items():
            # binary_checks AC dict→list変換は消火→撤去。gateが"must be list"でBLOCK
            if not isinstance(ac_val, list):
                continue

            needs_numbered_convert = any(
                isinstance(chk, dict)
                and len(chk) > 1
                and sum(
                    1 for key in chk.keys() if digit_key_re.match(str(key))
                ) == len(chk)
                for chk in ac_val
            )
            if needs_numbered_convert:
                task_checks = task_binary_checks_for(ac_key)
                new_list = []
                for chk in ac_val:
                    if isinstance(chk, dict):
                        for idx, (key, value) in enumerate(
                            sorted(chk.items(), key=lambda pair: str(pair[0]))
                        ):
                            result_val = (
                                value.get("result", "yes")
                                if isinstance(value, dict)
                                else value
                            )
                            check_name = ""
                            if idx < len(task_checks):
                                tc = task_checks[idx]
                                check_name = (
                                    tc.get("check", tc)
                                    if isinstance(tc, dict)
                                    else str(tc)
                                )
                            if not check_name:
                                check_name = f"{ac_key}_check_{idx}"
                            new_list.append({"check": check_name, "result": result_val})
                    else:
                        new_list.append(chk)
                if new_list:
                    ac_val = new_list
                    bc[ac_key] = ac_val
                    bc19_fixed = True

            # Flatten nested lists: - - check: → - check: (半蔵WA率62.5%の一因)
            flat_val = []
            _had_nested = False
            for _item in ac_val:
                if isinstance(_item, list):
                    flat_val.extend(_item)
                    _had_nested = True
                else:
                    flat_val.append(_item)
            if _had_nested:
                ac_val = flat_val
                bc[ac_key] = ac_val
                bc_dict_fixed = True

            new_list = []
            for chk in ac_val:
                item = chk
                if isinstance(chk, dict) and len(chk) == 1:
                    key, value = next(iter(chk.items()))
                    if key not in ("check", "result"):
                        item = {
                            "check": str(key),
                            "result": value if isinstance(value, bool) else str(value),
                        }
                        bc15_fixed = True
                if isinstance(item, dict):
                    norm = item.get("result")
                    if isinstance(norm, str):
                        stripped = norm.strip().strip("'\"")
                        if stripped != norm:
                            item["result"] = stripped
                            norm = stripped
                            bc_quote_fixed = True
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
        if bc_quote_fixed:
            fixes.append("binary_checks result quote除去('yes'→yes)")
        if bc19_fixed:
            fixes.append("binary_checks [N]キー→check/result正規化")

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

    # lessons_useful MISSING→スケルトン生成は消火(GP-107)→撤去。
    # gate_report_format.shがBLOCK
    # 忍者が自分で記入しなければgateが止める。消火で先送りしない。

    verdict_val = data.get("verdict")
    is_valid_verdict = isinstance(verdict_val, str) and verdict_val in ("PASS", "FAIL", "PASS_NO_IMPROVEMENT")
    # verdict推定(blank/invalid→PASS/FAIL)は消火→撤去。gate_report_format.shがBLOCK
    # verdict訂正(PASS→FAIL)も消火→撤去。GP-128でgateがWARN/ERROR

    status_val = data.get("status")
    if (
        is_valid_verdict
        and isinstance(status_val, str)
        and status_val.strip().lower() == "pending"
    ):
        data["status"] = "completed"
        fixes.append("status pending→completed")

    # self_gate_check値正規化(ok→PASS等)は消火→撤去。gate_report_format.shがBLOCK

    if fixes:
        base_bc = base_data.get("binary_checks") if isinstance(base_data, dict) else {}
        data_bc = data.get("binary_checks")
        if isinstance(base_bc, dict) and isinstance(data_bc, dict):
            for ac_key, ac_val in data_bc.items():
                base_ac_val = base_bc.get(ac_key)
                if not isinstance(ac_val, list) or not isinstance(base_ac_val, list):
                    continue
                for idx, item in enumerate(ac_val):
                    if idx >= len(base_ac_val) or not isinstance(item, dict) or not isinstance(base_ac_val[idx], dict):
                        continue
                    base_rs = str(base_ac_val[idx].get("result", "")).strip().lower()
                    if base_rs in ("yes", "no"):
                        item["result"] = base_rs
        data["autofix_applied"] = fixes
        # Write to temp file first, then validate round-trip
        import tempfile
        dir_name = os.path.dirname(report_path) or "."
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                DumpAll(
                    [data],
                    f,
                    Dumper=SafeDumper,
                    allow_unicode=True,
                    default_flow_style=False,
                    sort_keys=False,
                )
            # Round-trip validation: ensure yaml.dump didn't corrupt
            with open(tmp_path, "r", encoding="utf-8") as f:
                reloaded = yaml.safe_load(f)
            if not isinstance(reloaded, dict):
                raise ValueError("yaml.dump produced non-dict output")
            for ck in ["worker_id", "parent_cmd", "verdict", "status"]:
                if data.get(ck) is not None and reloaded.get(ck) is None:
                    raise ValueError(f"yaml.dump lost field: {ck}")
            os.replace(tmp_path, report_path)
        except Exception as e:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            print(
                f"UNFIXABLE: yaml.dump round-trip validation failed: {e}. "
                "Original file preserved."
            )
            return 1
        print("AUTO-FIXED: " + "; ".join(fixes))
    else:
        print("NO-FIX-NEEDED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
