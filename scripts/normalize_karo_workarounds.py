#!/usr/bin/env python3
"""
normalize_karo_workarounds.py — 壊れたkaro_workarounds.yamlを統一フォーマットに正規化
Usage: python3 scripts/normalize_karo_workarounds.py [--dry-run]

3つの混在フォーマットを統一:
  Format A: - cmd: cmd_XXX (手動記入, 50件)
  Format B: - timestamp: "..." (karo_workaround_log.sh出力, 9件)
  Format C: - cmd_id: cmd_XXX (新形式, 3件)

統一出力スキーマ:
  - cmd_id: cmd_XXX
    timestamp: 'YYYY-MM-DDTHH:MM:SS'
    ninja: name
    workaround: true/false
    category: report_yaml_format|commit_missing|...
    detail: '概要'
    root_cause: '原因'
    resolved_by_cmd: ''
"""
import re
import sys
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INPUT_FILE = os.path.join(REPO_ROOT, "logs", "karo_workarounds.yaml")
OUTPUT_FILE = os.path.join(REPO_ROOT, "logs", "karo_workarounds_normalized.yaml")

DRY_RUN = "--dry-run" in sys.argv


def classify_category(text):
    """Auto-classify category from detail/issue text."""
    if re.search(r'lessons_useful|binary_checks|dict.*list|list.*dict|string.*list|'
                 r'フォーマット|lesson_candidate|verdict.*CONDITIONAL|report.*ラップ|'
                 r'旧形式|FILL_THIS|fields.*欠落', text, re.IGNORECASE):
        return "report_yaml_format"
    if re.search(r'commit.*漏れ|commit.*なし|commit.*missing|uncommit', text, re.IGNORECASE):
        return "commit_missing"
    if re.search(r'消失|missing|not found|stale.*report|空テンプレート|報告YAML消失|'
                 r'報告.*欠損|テンプレート残存', text, re.IGNORECASE):
        return "report_missing"
    if re.search(r'archive.*timing|archive.*先に|GATE.*BLOCK.*archive', text, re.IGNORECASE):
        return "archive_race"
    return "uncategorized"


def parse_entries(lines):
    """Parse karo_workarounds.yaml line by line, handling broken YAML."""
    entries = []
    current = {}
    current_key = None

    for line in lines:
        stripped = line.rstrip()

        # Skip header
        if stripped in ('workarounds:', 'entries:', '') or stripped.startswith('#'):
            if current:
                entries.append(current)
                current = {}
            continue

        # New entry: starts with "- " at any indent
        m_new = re.match(r'^(\s*)- (\w[\w_]*):\s*(.*)', stripped)
        if m_new:
            indent = len(m_new.group(1))
            key = m_new.group(2)
            val = m_new.group(3).strip()

            # If it's a top-level list item (indent 0 or 2) AND starts a new entry
            if indent <= 2 and key in ('cmd', 'cmd_id', 'timestamp'):
                if current:
                    entries.append(current)
                current = {}
                current[key] = val.strip("'\"")
                current_key = key
                continue

        # Continuation key-value within entry
        m_kv = re.match(r'^\s+([\w_]+):\s*(.*)', stripped)
        if m_kv and current:
            key = m_kv.group(1)
            val = m_kv.group(2).strip()
            # Handle quoted values
            if val.startswith("'") and val.endswith("'"):
                val = val[1:-1]
            elif val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            current[key] = val
            current_key = key
            continue

        # Multi-line value continuation (indented text without key)
        if current and current_key and stripped.startswith('    '):
            prev = current.get(current_key, '')
            current[current_key] = prev + ' ' + stripped.strip()
            continue

    if current:
        entries.append(current)

    return entries


def normalize_entry(raw):
    """Convert any format entry to unified schema."""
    norm = {}

    # cmd_id
    norm['cmd_id'] = raw.get('cmd_id', raw.get('cmd', 'unknown'))

    # timestamp
    norm['timestamp'] = raw.get('timestamp', '')

    # ninja — extract from text if not explicitly set or invalid
    VALID_NINJAS = {'hayate', 'kagemaru', 'hanzo', 'saizo', 'kotaro', 'tobisaru'}
    ninja = raw.get('ninja', '')
    # Convert bool/non-string to string
    if isinstance(ninja, bool) or not isinstance(ninja, str):
        ninja = ''
    if not ninja or ninja not in VALID_NINJAS:
        text = raw.get('detail', '') + ' ' + raw.get('root_cause', '') + ' ' + raw.get('issue', '')
        ninja_names = ['hayate', 'kagemaru', 'hanzo', 'saizo', 'kotaro', 'tobisaru',
                       '疾風', '影丸', '半蔵', '才蔵', '小太郎', '飛猿']
        name_map = {'疾風': 'hayate', '影丸': 'kagemaru', '半蔵': 'hanzo',
                    '才蔵': 'saizo', '小太郎': 'kotaro', '飛猿': 'tobisaru'}
        ninja = 'unknown'
        for name in ninja_names:
            if name in text:
                ninja = name_map.get(name, name)
                break
    norm['ninja'] = ninja

    # workaround (bool)
    wa = raw.get('workaround', raw.get('karo_workaround', ''))
    if isinstance(wa, bool):
        norm['workaround'] = wa
    elif str(wa).lower() in ('true', 'yes'):
        norm['workaround'] = True
    elif str(wa).lower() in ('false', 'no'):
        norm['workaround'] = False
    else:
        norm['workaround'] = None  # unknown

    # category
    cat = raw.get('category', '')
    if not cat or cat == 'clean':
        detail_text = raw.get('detail', '') + ' ' + raw.get('issue', '')
        cat = classify_category(detail_text)
        if not norm['workaround'] and cat == 'uncategorized':
            cat = 'clean'
    norm['category'] = cat

    # detail (merge detail/issue/workaround_detail)
    detail = raw.get('detail', raw.get('issue', raw.get('workaround_detail', '')))
    norm['detail'] = detail

    # root_cause
    norm['root_cause'] = raw.get('root_cause', '')

    # resolved_by_cmd
    norm['resolved_by_cmd'] = raw.get('resolved_by_cmd', '')

    return norm


def format_yaml_entry(entry):
    """Format a single entry as YAML text."""
    lines = []
    lines.append(f"- cmd_id: {entry['cmd_id']}")
    lines.append(f"  timestamp: '{entry['timestamp']}'")
    lines.append(f"  ninja: {entry['ninja']}")

    wa = entry['workaround']
    if wa is None:
        lines.append(f"  workaround: null")
    else:
        lines.append(f"  workaround: {'true' if wa else 'false'}")

    lines.append(f"  category: {entry['category']}")

    # detail — escape single quotes
    detail = entry['detail'].replace("'", "''") if entry['detail'] else ''
    lines.append(f"  detail: '{detail}'")

    root_cause = entry['root_cause'].replace("'", "''") if entry['root_cause'] else ''
    if root_cause:
        lines.append(f"  root_cause: '{root_cause}'")

    resolved = entry['resolved_by_cmd']
    if resolved:
        lines.append(f"  resolved_by_cmd: '{resolved}'")

    return '\n'.join(lines)


def main():
    with open(INPUT_FILE, encoding='utf-8') as f:
        lines = f.readlines()

    raw_entries = parse_entries(lines)
    print(f"Parsed {len(raw_entries)} raw entries")

    normalized = []
    for raw in raw_entries:
        norm = normalize_entry(raw)
        normalized.append(norm)

    # Stats
    wa_true = sum(1 for e in normalized if e['workaround'] is True)
    wa_false = sum(1 for e in normalized if e['workaround'] is False)
    wa_null = sum(1 for e in normalized if e['workaround'] is None)

    cats = {}
    for e in normalized:
        c = e['category']
        cats[c] = cats.get(c, 0) + 1

    print(f"\n=== 正規化結果 ===")
    print(f"Total: {len(normalized)}")
    print(f"Workaround: true={wa_true}, false={wa_false}, unknown={wa_null}")
    print(f"Categories: {dict(sorted(cats.items(), key=lambda x: -x[1]))}")

    # Output
    output_lines = ["workarounds:"]
    for entry in normalized:
        output_lines.append(format_yaml_entry(entry))

    output_text = '\n'.join(output_lines) + '\n'

    if DRY_RUN:
        print(f"\n[DRY RUN] Would write {len(normalized)} entries to {OUTPUT_FILE}")
        # Show first 3 entries
        for entry in normalized[:3]:
            print(format_yaml_entry(entry))
            print()
    else:
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write(output_text)
        print(f"\nWritten to {OUTPUT_FILE}")
        print(f"Verify, then: cp {OUTPUT_FILE} {INPUT_FILE}")


if __name__ == '__main__':
    main()
