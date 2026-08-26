# 偵察報告ゲート契約監査

- 対象: `logs/gate_fire_log.yaml` の `gate_report_format` / `FAIL`
- 分類: report path の basename/path に `recon`, `recon2`, または `scout` が独立トークンとして含まれるもの
- 集計時点: 2026-08-27T03:09:00+09:00
- 集計結果: 557発火、240報告

## 再現コマンド

```bash
python3 - <<'PY'
from pathlib import Path
from collections import Counter
import re

log = Path("logs/gate_fire_log.yaml")
events = []
for line_no, line in enumerate(log.read_text(errors="replace").splitlines(), 1):
    if 'gate: "gate_report_format"' not in line or 'result: FAIL' not in line:
        continue
    match = re.search(r'file: "([^"]+)"', line)
    if not match or not re.search(r'(?:^|[_/-])(recon2?|scout)(?:[_./-]|$)', match.group(1).lower()):
        continue
    reasons = re.search(r'reasons: "(.*)"\s*$', line)
    parts = re.split(r'; (?=[A-Za-z_][A-Za-z0-9_.\[\]-]*:)', reasons.group(1)) if reasons else []
    events.append((line_no, match.group(1), parts))

def family(reason):
    for name in (
        "binary_checks", "cross_repo_commits", "commit_contract",
        "investigation_contract", "operational_simulation", "status",
        "verdict", "lessons_useful", "LG051", "timestamp",
    ):
        if reason.startswith(name):
            return name
    return reason.split(":", 1)[0]

counts = Counter(family(reason.strip()) for _, _, parts in events for reason in parts if reason.strip())
print(f"events={len(events)} reports={len({report for _, report, _ in events})}")
for name, count in counts.most_common(5):
    print(f"{name}={count}")
PY
```

実測上位5理由（reason occurrence 数）は次のとおり。

| 理由 | 件数 | 偵察報告への適用 | 判定根拠 |
|---|---:|---|---|
| `binary_checks` | 1,436 | 適用 | 偵察でもACの二値自己検証は成果の検証可能性に必要 |
| `cross_repo_commits` | 302 | 適用外 | read-only偵察はコードcommitを成果として生成しない |
| `status` | 253 | 適用 | 完了報告の状態遷移は偵察・実装で共通 |
| `verdict` | 216 | 適用 | binary checksから導出する終端判定は偵察にも必要 |
| `investigation_contract` | 210 | 適用外（findingへ置換） | 偵察の成果を探索完遂メタデータでなく、観測対象・結果・根拠パスのfindingで直接検証する |

`commit_contract` は上位5には含まれないが135件あり、`cross_repo_commits`と同じく偵察には適用外である。偵察分類は `recon` / `scout` / `recon2` の3値を同一契約として扱う。
