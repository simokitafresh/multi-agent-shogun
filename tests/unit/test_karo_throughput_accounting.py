"""test_necessity: 日次計測は重複・日境界・親子計測で値を歪めず、呼出し元計測は業務の戻り値を変えない。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AccountingContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "logs")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        (self.base / "archive").mkdir()
        self.env = dict(os.environ, KARO_THROUGHPUT_DEFENSE_LOG=str(self.base / "defense.jsonl"),
                        KARO_THROUGHPUT_DEFENSE_ARCHIVE=str(self.base / "archive"),
                        KARO_THROUGHPUT_GATE_LOG=str(self.base / "gate.log"),
                        KARO_THROUGHPUT_TIMING_LOGS=str(self.base / "timing.jsonl"),
                        KARO_THROUGHPUT_WATCHER_LOGS=str(self.base / "absent"),
                        KARO_THROUGHPUT_RETRY_ROOT=str(self.base / "absent"),
                        KARO_THROUGHPUT_OUTPUT_DIR=str(self.base / "out"))

    def rows(self, name, rows):
        (self.base / name).write_text("".join(json.dumps(r) + "\n" for r in rows))

    def report(self):
        subprocess.run(["bash", str(ROOT / "scripts/karo_throughput_report.sh"),
                        "2026-09-05", "--as-of", "2026-09-05T01:00:00+09:00"],
                       env=self.env, check=True, capture_output=True, text=True)
        return next((self.base / "out").glob("*.md")).read_text()

    def event(self, eid, ms=100, check="work"):
        return dict(timestamp="2026-09-04T15:30:00Z", source="three_layer_health",
                    check_id=check, wall_ms=ms, event_id=eid, agent="karo")

    def test_archive_overlap_and_legacy(self):
        legacy = self.event("legacy")
        del legacy["event_id"]
        self.rows("archive/defense_overhead_a.jsonl", [self.event("a"), self.event("b"), legacy])
        self.rows("defense.jsonl", [self.event("b"), legacy, self.event("c")])
        self.assertIn("| three_layer_health / work | 4 | 100 | 100 | 400 | ms |", self.report())

    def test_health_parent_not_added_to_children(self):
        self.rows("defense.jsonl", [self.event("refresh_window:begin:grp-1", 0, "refresh_window"),
                  self.event("refresh_window:end:grp-1", 100, "refresh_window"),
                  self.event("copy", 60, "refresh_copy"), self.event("verify", 30, "refresh_verify")])
        report = self.report()
        self.assertIn("| refresh_window | 1 | 100 | 100 | 100 | ms |", report)
        self.assertIn("CPU使用時間は未計測", report)

    def test_midnight_and_open_tail(self):
        (self.base / "gate.log").write_text("2026-09-04T23:30:00+09:00\tc1\tWAIT\tWAIT:ancestry\n")
        self.assertIn("| WAIT:ancestry | 60 | 100% | 1 |", self.report())

    def test_terminal_stops_wait_and_excludes_future(self):
        (self.base / "gate.log").write_text(
            "2026-09-04T23:30:00+09:00\tc1\tWAIT\tancestry\n"
            "2026-09-05T00:20:00+09:00\tc1\tCLEAR\tok duration_sec=3\n"
            "2026-09-05T02:00:00+09:00\tc1\tBLOCK\tlater\n")
        report = self.report()
        self.assertIn("| WAIT:ancestry | 20 | 100% | 1 |", report)
        self.assertNotIn("BLOCK:later", report)

    def test_naive_gate_timestamp_is_jst(self):
        (self.base / "gate.log").write_text("2026-09-04T23:30:00\tc1\tWAIT\tancestry\n"
                                            "2026-09-05T00:20:00\tc1\tCLEAR\tok\n")
        self.assertIn("| WAIT:ancestry | 20 | 100% | 1 |", self.report())

    def test_jst_timing_and_callsite_not_double_counted(self):
        common = dict(observed_at="2026-09-04T15:30:00Z", execution_id="one", script="deploy_task.sh",
                      function="run_python_logged", elapsed_us=1000)
        self.rows("timing.jsonl", [dict(common, schema="function_timing.v1"),
                                   dict(common, schema="call_site_timing.v1", call_site="inject:L8")])
        report = self.report()
        self.assertIn("| function_timing / deploy_task.sh | 1 | 1 | 1 | 1 | ms |", report)
        self.assertIn("| inject:L8 | 1 | 1 | 1 | 1 | ms |", report)

    def test_fixed_cutoff_is_deterministic(self):
        self.assertEqual(self.report(), self.report())

    def test_eight_call_sites_preserve_rc_and_parent_total(self):
        script = (ROOT / "scripts/deploy_task.sh").read_text()
        functions = script[script.index("deploy_task_function_timing_enable() {"):
                           script.index("# The later modular loader", script.index("deploy_task_function_timing_enable() {"))]
        harness = functions + '\nrun_python_logged() { local i; for ((i=0;i<20;i++)); do :; done; return "$1"; }\n'
        harness += 'deploy_task_function_timing_enable\n'
        for i in range(8):
            harness += f'f{i}() {{ run_python_logged {i}; }}\nf{i}\n[ "$?" -eq {i} ] || exit 90\n'
        harness += 'deploy_task_function_timing_finish\n'
        env = dict(os.environ, DEPLOY_TASK_FUNCTION_TIMING_LOG=str(self.base / "timing.jsonl"))
        subprocess.run(["bash", "-c", harness], env=env, check=True, capture_output=True)
        rows = [json.loads(x) for x in (self.base / "timing.jsonl").read_text().splitlines()]
        sites = [r for r in rows if r["schema"] == "call_site_timing.v1"]
        self.assertEqual(len(sites), 8)
        self.assertEqual({r["call_site"].split(":")[0] for r in sites}, {f"f{i}" for i in range(8)})
        parent = next(r for r in rows if r["schema"] == "function_timing.v1" and r["function"] == "run_python_logged")
        self.assertEqual(sum(r["elapsed_us"] for r in sites), parent["elapsed_us"])


if __name__ == "__main__":
    unittest.main()
