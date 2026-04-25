#!/usr/bin/env python3
"""Baseline-aware wrapper around auto-ops perf_measure.py.

This script keeps CDP measurement snapshots inside the multi-agent-shogun repo,
adds regression grading against an explicitly captured baseline, and computes a
simple health score for each measurement.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PERF_SCRIPT = Path("/mnt/c/Python_app/auto-ops/workflows/perf_measure.py")
DEFAULT_OUTPUT_DIR = REPO_ROOT / "outputs" / "cdp-baselines"


@dataclass(frozen=True)
class Severity:
    name: str
    level: int


PASS = Severity("PASS", 0)
WARN = Severity("WARN", 1)
REGRESSION = Severity("REGRESSION", 2)
NO_BASELINE = Severity("NO_BASELINE", -1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run CDP perf_measure, persist snapshots to outputs/cdp-baselines, "
            "and grade regressions against a captured baseline."
        )
    )
    parser.add_argument(
        "--perf-script",
        type=Path,
        default=DEFAULT_PERF_SCRIPT,
        help="Path to auto-ops perf_measure.py",
    )
    parser.add_argument(
        "--input-json",
        type=Path,
        help="Use an existing perf_measure JSON instead of executing perf_measure.py",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for persisted CDP baseline snapshots",
    )
    parser.add_argument(
        "--branch",
        help="Override git branch label used for saved snapshot names",
    )
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="Capture the current run as the branch baseline pointer",
    )
    parser.add_argument(
        "--trend",
        action="store_true",
        help="Print recent saved snapshots for the branch after processing",
    )
    parser.add_argument(
        "--trend-limit",
        type=int,
        default=5,
        help="How many snapshots to show for --trend (default: 5)",
    )
    parser.add_argument(
        "perf_args",
        nargs=argparse.REMAINDER,
        help="Arguments forwarded to perf_measure.py. Use -- before them if needed.",
    )
    return parser.parse_args()


def sanitize_branch(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return cleaned.strip("-") or "detached-head"


def detect_branch() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return "detached-head"
    branch = result.stdout.strip() or "detached-head"
    return sanitize_branch(branch)


def iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def timestamp_slug(iso_value: str) -> str:
    dt = datetime.fromisoformat(iso_value)
    return dt.strftime("%Y%m%d_%H%M%S")


def latest_pointer_path(output_dir: Path, branch: str) -> Path:
    return output_dir / f"{branch}_latest.json"


def snapshot_path(output_dir: Path, branch: str, ts_slug: str) -> Path:
    return output_dir / f"{branch}_{ts_slug}.json"


def list_branch_snapshots(output_dir: Path, branch: str) -> list[Path]:
    pattern = f"{branch}_*.json"
    files = [
        path for path in output_dir.glob(pattern)
        if path.name != f"{branch}_latest.json"
    ]
    return sorted(files, key=lambda item: item.name, reverse=True)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return data


def median_number(values: list[float]) -> float | None:
    if not values:
        return None
    return round(float(median(values)), 2)


def bundle_bytes_from_run(run: dict[str, Any]) -> int:
    resources = run.get("resource_timings") or []
    total = 0
    for entry in resources:
        if not isinstance(entry, dict):
            continue
        decoded = entry.get("decodedBodySize")
        encoded = entry.get("encodedBodySize")
        transfer = entry.get("transferSize")
        for candidate in (decoded, encoded, transfer):
            if isinstance(candidate, (int, float)):
                total += int(candidate)
                break
    return total


def request_count_from_run(run: dict[str, Any]) -> int:
    resources = run.get("resource_timings") or []
    return sum(1 for entry in resources if isinstance(entry, dict))


def http_404_count_from_run(run: dict[str, Any]) -> int:
    resources = run.get("resource_timings") or []
    return sum(
        1
        for entry in resources
        if isinstance(entry, dict) and str(entry.get("responseStatus")) == "404"
    )


def console_error_count_from_run(run: dict[str, Any]) -> int | None:
    if "console_error_count" in run:
        value = run.get("console_error_count")
        if isinstance(value, (int, float)):
            return int(value)
    if "console_errors" in run and isinstance(run.get("console_errors"), list):
        return len(run["console_errors"])
    return None


def aggregate_measurement(measurement: dict[str, Any]) -> dict[str, Any]:
    runs = measurement.get("runs") or []
    bundle_values = [bundle_bytes_from_run(run) for run in runs if isinstance(run, dict)]
    request_values = [request_count_from_run(run) for run in runs if isinstance(run, dict)]
    status_404_values = [http_404_count_from_run(run) for run in runs if isinstance(run, dict)]
    console_values = [
        value
        for run in runs
        if isinstance(run, dict)
        for value in [console_error_count_from_run(run)]
        if value is not None
    ]
    return {
        "timing_ms": measurement.get("median_ms"),
        "bundle_bytes": median_number(bundle_values),
        "request_count": median_number(request_values),
        "http_404_count": max(status_404_values) if status_404_values else 0,
        "console_error_count": max(console_values) if console_values else None,
    }


def ratio_change(current: float | None, previous: float | None) -> float | None:
    if current is None or previous in (None, 0):
        return None
    return round(((current - previous) / previous) * 100.0, 2)


def grade_timing(current: float | None, previous: float | None) -> tuple[Severity, str]:
    if current is None or previous in (None, 0):
        return NO_BASELINE, "baseline missing"
    delta_ms = current - previous
    ratio = (current - previous) / previous
    if delta_ms > 500 or ratio > 0.5:
        return REGRESSION, f"+{delta_ms:.2f}ms / +{ratio * 100:.2f}%"
    if ratio > 0.2:
        return WARN, f"+{delta_ms:.2f}ms / +{ratio * 100:.2f}%"
    return PASS, f"{delta_ms:.2f}ms / {ratio * 100:.2f}%"


def grade_bundle(current: float | None, previous: float | None) -> tuple[Severity, str]:
    if current is None or previous in (None, 0):
        return NO_BASELINE, "baseline missing"
    ratio = (current - previous) / previous
    if ratio > 0.25:
        return REGRESSION, f"+{ratio * 100:.2f}%"
    if ratio > 0.10:
        return WARN, f"+{ratio * 100:.2f}%"
    return PASS, f"{ratio * 100:.2f}%"


def grade_request_count(current: float | None, previous: float | None) -> tuple[Severity, str]:
    if current is None or previous in (None, 0):
        return NO_BASELINE, "baseline missing"
    ratio = (current - previous) / previous
    if ratio > 0.30:
        return WARN, f"+{ratio * 100:.2f}%"
    return PASS, f"{ratio * 100:.2f}%"


def pick_overall(*severities: Severity) -> Severity:
    ranked = [sev for sev in severities if sev.level >= 0]
    if not ranked:
        return NO_BASELINE
    return max(ranked, key=lambda item: item.level)


def build_baseline_lookup(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for page in payload.get("pages", []):
        if not isinstance(page, dict):
            continue
        for measurement in page.get("measurements", []):
            if not isinstance(measurement, dict):
                continue
            key = str(measurement.get("baseline_key") or "")
            if key:
                lookup[key] = measurement
    return lookup


def score_health(
    measurement: dict[str, Any],
    timing_grade: Severity,
    bundle_grade: Severity,
    aggregated: dict[str, Any],
) -> dict[str, Any]:
    console_errors = aggregated.get("console_error_count")
    http_404_count = aggregated.get("http_404_count") or 0
    breakdown = {
        "page_load_success": 40 if measurement.get("status") == "PASS" else 0,
        "console_error_free": 20 if console_errors == 0 else 0,
        "timing_no_regression": 20 if timing_grade != REGRESSION else 0,
        "http_404_free": 10 if http_404_count == 0 else 0,
        "bundle_no_regression": 10 if bundle_grade != REGRESSION else 0,
    }
    total = sum(breakdown.values())
    return {
        "score": total,
        "breakdown": breakdown,
        "inputs": {
            "console_error_count": console_errors,
            "http_404_count": http_404_count,
        },
    }


def enrich_payload(
    payload: dict[str, Any],
    *,
    branch: str,
    source_json_path: Path,
    baseline_payload: dict[str, Any] | None,
) -> dict[str, Any]:
    baseline_lookup = build_baseline_lookup(baseline_payload or {})
    enriched = json.loads(json.dumps(payload))
    summary_rows: list[dict[str, Any]] = []

    for page in enriched.get("pages", []):
        if not isinstance(page, dict):
            continue
        for measurement in page.get("measurements", []):
            if not isinstance(measurement, dict):
                continue
            aggregated = aggregate_measurement(measurement)
            previous = baseline_lookup.get(str(measurement.get("baseline_key") or ""))
            previous_aggregated = aggregate_measurement(previous) if previous else {}

            timing_grade, timing_detail = grade_timing(
                aggregated.get("timing_ms"),
                previous_aggregated.get("timing_ms"),
            )
            bundle_grade, bundle_detail = grade_bundle(
                aggregated.get("bundle_bytes"),
                previous_aggregated.get("bundle_bytes"),
            )
            request_grade, request_detail = grade_request_count(
                aggregated.get("request_count"),
                previous_aggregated.get("request_count"),
            )
            overall = pick_overall(timing_grade, bundle_grade, request_grade)
            health = score_health(measurement, timing_grade, bundle_grade, aggregated)

            comparison = {
                "overall": overall.name,
                "timing": {
                    "grade": timing_grade.name,
                    "detail": timing_detail,
                    "current_ms": aggregated.get("timing_ms"),
                    "baseline_ms": previous_aggregated.get("timing_ms"),
                    "delta_pct": ratio_change(
                        aggregated.get("timing_ms"),
                        previous_aggregated.get("timing_ms"),
                    ),
                },
                "bundle": {
                    "grade": bundle_grade.name,
                    "detail": bundle_detail,
                    "current_bytes": aggregated.get("bundle_bytes"),
                    "baseline_bytes": previous_aggregated.get("bundle_bytes"),
                    "delta_pct": ratio_change(
                        aggregated.get("bundle_bytes"),
                        previous_aggregated.get("bundle_bytes"),
                    ),
                },
                "request_count": {
                    "grade": request_grade.name,
                    "detail": request_detail,
                    "current": aggregated.get("request_count"),
                    "baseline": previous_aggregated.get("request_count"),
                    "delta_pct": ratio_change(
                        aggregated.get("request_count"),
                        previous_aggregated.get("request_count"),
                    ),
                },
            }

            measurement["regression"] = comparison
            measurement["health_score"] = health
            measurement["aggregates"] = aggregated
            summary_rows.append(
                {
                    "page": page.get("name"),
                    "label": measurement.get("label"),
                    "overall": overall.name,
                    "health_score": health["score"],
                }
            )

    enriched["cdp_baseline_meta"] = {
        "generated_at": iso_now(),
        "branch": branch,
        "source_json_path": str(source_json_path),
        "baseline_reference_path": (
            str(baseline_payload.get("_snapshot_path"))
            if baseline_payload and baseline_payload.get("_snapshot_path")
            else None
        ),
    }
    enriched["regression_summary"] = summary_rows
    return enriched


def parse_perf_json_path(stdout: str) -> Path:
    for line in stdout.splitlines():
        if line.startswith("JSON report: "):
            return Path(line.split("JSON report: ", 1)[1].strip())
    raise RuntimeError("perf_measure.py output did not contain 'JSON report:'")


def run_perf_measure(perf_script: Path, perf_args: list[str]) -> Path:
    if not perf_script.is_file():
        raise FileNotFoundError(f"perf_measure.py not found: {perf_script}")
    forwarded = perf_args[:]
    if forwarded and forwarded[0] == "--":
        forwarded = forwarded[1:]
    cmd = [sys.executable, str(perf_script), *forwarded]
    proc = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    if proc.returncode != 0:
        raise RuntimeError(f"perf_measure.py failed with exit code {proc.returncode}")
    return parse_perf_json_path(proc.stdout)


def print_summary(payload: dict[str, Any]) -> None:
    print("Regression summary:")
    for page in payload.get("pages", []):
        if page.get("skipped_reason"):
            print(f"- {page.get('name')}: SKIP ({page.get('skipped_reason')})")
            continue
        for measurement in page.get("measurements", []):
            regression = measurement.get("regression", {})
            health = measurement.get("health_score", {})
            print(
                "- {page} [{label}] status={status} regression={regression} health={health}".format(
                    page=page.get("name"),
                    label=measurement.get("label"),
                    status=measurement.get("status"),
                    regression=regression.get("overall", "n/a"),
                    health=health.get("score", "n/a"),
                )
            )


def print_trend(output_dir: Path, branch: str, limit: int) -> None:
    snapshots = list_branch_snapshots(output_dir, branch)[:limit]
    print(f"Trend ({branch}, latest {len(snapshots)}):")
    for path in snapshots:
        data = load_json(path)
        meta = data.get("cdp_baseline_meta", {})
        summary = data.get("regression_summary", [])
        regressions = sum(1 for row in summary if row.get("overall") == "REGRESSION")
        warns = sum(1 for row in summary if row.get("overall") == "WARN")
        avg_health = median_number(
            [float(row.get("health_score")) for row in summary if row.get("health_score") is not None]
        )
        print(
            "- {name} generated_at={generated_at} regressions={regressions} warns={warns} median_health={health}".format(
                name=path.name,
                generated_at=meta.get("generated_at", "unknown"),
                regressions=regressions,
                warns=warns,
                health=avg_health if avg_health is not None else "n/a",
            )
        )


def main() -> int:
    args = parse_args()
    branch = sanitize_branch(args.branch or detect_branch())
    output_dir = args.output_dir if args.output_dir.is_absolute() else (REPO_ROOT / args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.input_json:
        source_json = args.input_json if args.input_json.is_absolute() else (REPO_ROOT / args.input_json)
    else:
        source_json = run_perf_measure(args.perf_script, args.perf_args)

    payload = load_json(source_json)
    baseline_pointer = latest_pointer_path(output_dir, branch)
    baseline_payload = None
    if baseline_pointer.is_file():
        baseline_payload = load_json(baseline_pointer)
        baseline_payload["_snapshot_path"] = str(baseline_pointer.resolve())

    enriched = enrich_payload(
        payload,
        branch=branch,
        source_json_path=source_json.resolve(),
        baseline_payload=baseline_payload,
    )
    generated_at = enriched["cdp_baseline_meta"]["generated_at"]
    ts_slug = timestamp_slug(generated_at)
    target_snapshot = snapshot_path(output_dir, branch, ts_slug)
    target_snapshot.write_text(
        json.dumps(enriched, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if args.baseline:
        shutil.copyfile(target_snapshot, baseline_pointer)
        print(f"Baseline pointer updated: {baseline_pointer}")

    print(f"Saved enriched snapshot: {target_snapshot}")
    print_summary(enriched)
    if args.trend:
        print_trend(output_dir, branch, args.trend_limit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
