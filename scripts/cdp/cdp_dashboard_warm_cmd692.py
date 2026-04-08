#!/usr/bin/env python3
"""CDP Dashboard Warm Cache Measurement for cmd_692.

Methodology: Same as cmd_686 (hayate).
1. Verify viewer auth
2. Navigate to /summary (warm up prefetch)
3. SPA navigate to /dashboard via sidebar click
4. Wall-clock timing until content ready
5. Collect resource timing for API calls

Baseline: cmd_686 = 4482ms
"""

import sys
import time
import json

sys.path.insert(0, '/mnt/c/tools/multi-agent-shogun/scripts/cdp')
from cdp_helper import cdp_get, js_eval, navigate, get_tab, cdp_send

PROD_URL = "https://dm-signal-frontend.onrender.com"
PORT = 9223
WARMUP_SECONDS = 15  # Wait for prefetch to complete


def get_ws_url():
    """Get WebSocket URL for the DM-signal tab."""
    tab = get_tab("dm-signal-frontend.onrender.com", port=PORT)
    if not tab:
        # Try to find any suitable tab
        tabs = cdp_get("/json", port=PORT)
        for t in tabs:
            if t.get("type") == "page" and "dm-signal" in t.get("url", ""):
                return t["webSocketDebuggerUrl"]
        raise RuntimeError("No DM-signal tab found. Open the production URL first.")
    return tab["webSocketDebuggerUrl"]


def check_viewer_auth(ws_url):
    """Check if viewer auth is established (L211/L213)."""
    # Check if the page has portfolio selector (sign of auth)
    has_content = js_eval(ws_url, """
        (() => {
            const main = document.querySelector('main');
            if (!main) return {ok: false, reason: 'no main element'};
            const text = main.textContent || '';
            // Check for auth indicators
            const hasPortfolios = text.includes('DM2') || text.includes('DM3');
            const hasUnauth = text.includes('Unauthorized') || text.includes('Sign in');
            const hasAuthModal = !!document.querySelector('[role="dialog"]');
            return {
                ok: hasPortfolios && !hasUnauth && !hasAuthModal,
                textLen: text.length,
                hasPortfolios: hasPortfolios,
                hasUnauth: hasUnauth,
                hasAuthModal: hasAuthModal,
                snippet: text.substring(0, 200)
            };
        })()
    """)
    return has_content


def check_normal_screen(ws_url):
    """Check page is normal, not error/maintenance (L212/L214)."""
    screen = js_eval(ws_url, """
        (() => {
            const body = document.body.textContent || '';
            const isError = body.includes('城の修繕中') || body.includes('Error') || body.includes('503');
            const spinners = document.querySelectorAll('.animate-spin').length;
            const loading = document.querySelectorAll('.animate-pulse').length;
            return {
                isError: isError,
                spinners: spinners,
                loading: loading,
                bodyLen: body.length
            };
        })()
    """)
    return screen


def measure_warm_transition(ws_url, runs=3):
    """Measure warm Summary→Dashboard SPA transition."""
    results = []

    for run_idx in range(runs):
        print(f"\n--- Run {run_idx + 1}/{runs} ---")

        # Step 1: Navigate to /summary via full navigation
        print("  Navigating to /summary...")
        navigate(ws_url, f"{PROD_URL}/summary", wait=3)

        # Re-get ws_url after navigation (tab URL changed)
        time.sleep(2)
        ws_url_new = get_ws_url()

        # Step 2: Wait for summary to load
        print(f"  Warming up ({WARMUP_SECONDS}s)...")
        time.sleep(WARMUP_SECONDS)

        # Verify summary loaded
        screen = check_normal_screen(ws_url_new)
        print(f"  Summary screen: spinners={screen.get('spinners')}, loading={screen.get('loading')}, bodyLen={screen.get('bodyLen')}")

        if screen.get('isError'):
            print("  ERROR: Error screen detected! Skipping run.")
            continue

        # Step 3: Clear performance entries
        js_eval(ws_url_new, "performance.clearResourceTimings()")

        # Step 4: Record start time and click Dashboard in sidebar
        print("  Clicking Dashboard sidebar link...")
        click_result = js_eval(ws_url_new, """
            (() => {
                const startTime = performance.now();
                // Find Dashboard link in sidebar or nav
                const links = document.querySelectorAll('a[href="/dashboard"]');
                if (links.length === 0) {
                    // Try finding by text
                    const allLinks = document.querySelectorAll('a');
                    for (const a of allLinks) {
                        if (a.textContent.trim() === 'Dashboard') {
                            a.click();
                            return {clicked: true, startTime: startTime, method: 'text'};
                        }
                    }
                    return {clicked: false, reason: 'no dashboard link found'};
                }
                links[0].click();
                return {clicked: true, startTime: startTime, method: 'href'};
            })()
        """)
        print(f"  Click result: {click_result}")

        if not click_result or not click_result.get('clicked'):
            print("  ERROR: Could not click Dashboard link!")
            continue

        # Step 5: Poll until Dashboard content is ready
        print("  Waiting for Dashboard content...")
        poll_start = time.time()
        max_wait = 30  # 30s timeout
        ready = False

        while time.time() - poll_start < max_wait:
            time.sleep(0.3)
            status = js_eval(ws_url_new, """
                (() => {
                    const path = window.location.pathname;
                    if (path !== '/dashboard') return {ready: false, reason: 'not on dashboard', path: path};
                    const spinners = document.querySelectorAll('.animate-spin').length;
                    const pulses = document.querySelectorAll('.animate-pulse').length;
                    const main = document.querySelector('main');
                    const textLen = main ? main.textContent.length : 0;
                    // Dashboard should have substantial content (chart, metrics)
                    const hasContent = textLen > 100;
                    const noLoading = spinners === 0 && pulses === 0;
                    return {
                        ready: hasContent && noLoading,
                        spinners: spinners,
                        pulses: pulses,
                        textLen: textLen,
                        path: path
                    };
                })()
            """)

            if status and status.get('ready'):
                ready = True
                break

        if not ready:
            print(f"  WARNING: Dashboard not ready after {max_wait}s. Last status: {status}")
            continue

        # Step 6: Get wall-clock elapsed time
        elapsed = js_eval(ws_url_new, """
            (() => {
                const endTime = performance.now();
                return endTime;
            })()
        """)

        start_time = click_result.get('startTime', 0)
        wall_clock_ms = elapsed - start_time if elapsed else None

        # Also measure from Python side
        python_wall_ms = (time.time() - poll_start) * 1000

        # Step 7: Collect resource timing (API calls during transition)
        api_entries = js_eval(ws_url_new, """
            (() => {
                const entries = performance.getEntriesByType('resource');
                const apiCalls = entries
                    .filter(e => e.name.includes('/api/'))
                    .map(e => ({
                        name: e.name.split('/api/')[1]?.split('?')[0] || e.name,
                        duration: Math.round(e.duration),
                        startTime: Math.round(e.startTime)
                    }));
                return apiCalls;
            })()
        """)

        result = {
            'run': run_idx + 1,
            'wall_clock_ms': round(wall_clock_ms) if wall_clock_ms else None,
            'python_wall_ms': round(python_wall_ms),
            'api_calls': api_entries or [],
            'api_count': len(api_entries) if api_entries else 0,
            'dashboard_status': status
        }
        results.append(result)
        print(f"  Wall-clock: {result['wall_clock_ms']}ms (JS) / {result['python_wall_ms']}ms (Python)")
        print(f"  API calls: {result['api_count']}")
        if api_entries:
            for api in api_entries:
                print(f"    - {api['name']}: {api['duration']}ms")

        # Wait before next run
        if run_idx < runs - 1:
            time.sleep(3)

    return results


def main():
    print("=== CDP Dashboard Warm Cache Measurement (cmd_692) ===")
    print(f"Baseline: cmd_686 = 4482ms")
    print()

    # Get WebSocket URL
    ws_url = get_ws_url()
    print(f"Tab found. WS URL: {ws_url[:80]}...")

    # Pre-check: Verify viewer auth (L211)
    print("\n[Pre-check 1] Viewer auth verification...")
    auth = check_viewer_auth(ws_url)
    print(f"  Auth status: {auth}")
    if not auth or not auth.get('ok'):
        print("ERROR: Viewer auth not established! Measurement would be invalid.")
        print("Please authenticate first, then re-run.")
        sys.exit(1)

    # Pre-check: Normal screen (L212/L214)
    print("\n[Pre-check 2] Normal screen check...")
    screen = check_normal_screen(ws_url)
    print(f"  Screen status: {screen}")
    if screen.get('isError'):
        print("ERROR: Error/maintenance screen detected! Measurement would be invalid.")
        sys.exit(1)

    # Run measurement
    print("\n[Measurement] Starting warm cache measurement (3 runs)...")
    results = measure_warm_transition(ws_url, runs=3)

    # Summary
    print("\n=== RESULTS SUMMARY ===")
    valid_results = [r for r in results if r.get('wall_clock_ms')]
    if not valid_results:
        print("ERROR: No valid measurement results!")
        sys.exit(1)

    js_times = [r['wall_clock_ms'] for r in valid_results]
    py_times = [r['python_wall_ms'] for r in valid_results]
    best_js = min(js_times)
    avg_js = sum(js_times) / len(js_times)
    best_py = min(py_times)

    print(f"Valid runs: {len(valid_results)}/{len(results)}")
    print(f"JS wall-clock:  best={best_js}ms, avg={round(avg_js)}ms")
    print(f"Python timing:  best={best_py}ms")
    print(f"Baseline (cmd_686): 4482ms")
    print(f"Delta (best): {best_js - 4482}ms ({round((best_js - 4482) / 4482 * 100, 1)}%)")
    print(f"Delta (avg):  {round(avg_js - 4482)}ms ({round((avg_js - 4482) / 4482 * 100, 1)}%)")

    if best_js < 4482:
        print(f"\nIMPROVED: {4482 - best_js}ms faster ({round((4482 - best_js) / 4482 * 100, 1)}% improvement)")
    elif best_js > 4482:
        print(f"\nDEGRADED: {best_js - 4482}ms slower — consider revert per AC5")

    # Output JSON for report
    output = {
        'cmd': 'cmd_692',
        'baseline_ms': 4482,
        'runs': valid_results,
        'best_js_ms': best_js,
        'avg_js_ms': round(avg_js),
        'best_py_ms': best_py,
        'delta_ms': best_js - 4482,
        'delta_pct': round((best_js - 4482) / 4482 * 100, 1),
        'improved': best_js < 4482
    }
    print(f"\n--- JSON OUTPUT ---")
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
