# Completion pipeline gap analysis

Generated: 2026-08-24T09:03:00+09:00
Source records: 7 complete / 10 total

| Gap | N | Median (s) | Mean (s) | Max (s) |
|---|---:|---:|---:|---:|
| report_done_to_review_request_sec | 7 | 82.000 | 611.143 | 3097.000 |
| review_request_to_review_start_sec | 7 | 102.000 | 129.143 | 233.000 |
| review_start_to_lgtm_sent_sec | 7 | 2.000 | 2.143 | 3.000 |
| lgtm_sent_to_karo_accept_sec | 7 | 93.000 | 707.714 | 1812.000 |
| karo_accept_to_gate_start_sec | 7 | 180.000 | 263.571 | 818.000 |

Next individual shortening target: `karo_accept_to_gate_start_sec` (highest median contribution).
Total pipeline gap median: `1887.000s`.
