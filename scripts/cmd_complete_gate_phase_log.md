# cmd_complete_gate phase log

`scripts/cmd_complete_gate.sh` records each completed major gate phase in
`logs/cmd_complete_gate_phases.log` by default. `CMD_COMPLETE_GATE_PHASE_LOG`
may redirect the log to another path; the explicit values `disabled` and `0`
disable recording for behavior comparisons.

Each record is one tab-separated line:

```text
timestamp<TAB>cmd_id<TAB>phase_name<TAB>elapsed_seconds
```

The timestamp is local ISO-8601 to the second, `cmd_id` identifies the gate
run, `phase_name` is the completed phase, and `elapsed_seconds` is formatted as
seconds with millisecond precision (for example `7.054`). The writer uses a
per-log lock so concurrent gate runs cannot interleave records. When the log
reaches `CMD_COMPLETE_GATE_PHASE_LOG_MAX_BYTES` (default 5 MiB), it is moved to
the single retained sidecar `<log>.1` before the next record is appended.

## gate_evaluation subphase log

The dominant `gate_evaluation` interval is also decomposed into
`logs/cmd_complete_gate_subphases.log` by default. Set
`CMD_COMPLETE_GATE_SUBPHASE_LOG` to redirect it, or to `disabled`/`0` to
disable subphase recording for an explicit behavior comparison. Records use
the same four tab-separated fields as the major-phase log:

```text
timestamp<TAB>cmd_id<TAB>subphase_name<TAB>elapsed_seconds
```

The subphase log has the same 5 MiB default bound and one retained `<log>.1`
generation (`CMD_COMPLETE_GATE_SUBPHASE_LOG_MAX_BYTES` overrides the bound).
The writer is lock-protected, and logging failures remain non-blocking so gate
判定・出力・終了コード are independent of telemetry.
