#!/usr/bin/env python3
# semantic-links: [[軍師precheck視点列独立性検証]]
"""detect_view_column_degeneracy.py — Markdown表内の数値列が全データ行で
完全一致する縮退パターンを検出する(cmd_3781: SG-PRE31拡張)。

cmd_3780実データで発覚: 「Expanding」「WF」の2視点列が全450行で完全一致し
(独立に算出されるべき指標が同一パイプラインに縮退)、忍者binary_checks・
軍師レビュー・家老GATEを素通りして将軍検分のみが捕捉した。
成果物表の列ペアが全データ行で一致していれば、視点/系列の独立性が
壊れている疑いとして機械的に検出する。

Usage: python3 scripts/lib/detect_view_column_degeneracy.py <markdown_file>
Output: 検出した列ペアを1行1件で標準出力(なければ無出力)。exit codeは常に0
        (呼び出し元のgate_gunshi_report_precheck.shがWARN扱いで処理する)。
"""
import re
import sys

MIN_ROWS = 3  # 2行以下は偶然一致のFP率が高いため対象外(SG-PRE31の閾値慣習に合わせる)
TOLERANCE = 1e-9

_SEP_RE = re.compile(r'^\|?[\s:|-]+\|[\s:|-]*$')


def parse_tables(lines):
    """Markdown中の全GFM表を(見出し行番号, header, rows)のリストで返す"""
    tables = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].rstrip('\n')
        if line.strip().startswith('|') and i + 1 < n:
            sep = lines[i + 1].strip()
            if _SEP_RE.match(sep) and '-' in sep:
                header = [c.strip() for c in line.strip().strip('|').split('|')]
                rows = []
                j = i + 2
                while j < n and lines[j].strip().startswith('|'):
                    cells = [c.strip() for c in lines[j].strip().strip('|').split('|')]
                    if len(cells) == len(header):
                        rows.append(cells)
                    j += 1
                tables.append((i + 1, header, rows))
                i = j
                continue
        i += 1
    return tables


def to_number(cell):
    s = cell.strip().rstrip('%').replace(',', '')
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def find_degenerate_pairs(header, rows):
    if len(rows) < MIN_ROWS:
        return []
    numeric_cols = []
    for c in range(len(header)):
        values = [to_number(r[c]) for r in rows]
        if all(v is not None for v in values):
            numeric_cols.append(c)
    pairs = []
    for a in range(len(numeric_cols)):
        for b in range(a + 1, len(numeric_cols)):
            ca, cb = numeric_cols[a], numeric_cols[b]
            vals_a = [to_number(r[ca]) for r in rows]
            vals_b = [to_number(r[cb]) for r in rows]
            if all(abs(va - vb) < TOLERANCE for va, vb in zip(vals_a, vals_b)):
                pairs.append((header[ca], header[cb], len(rows)))
    return pairs


def main():
    if len(sys.argv) < 2:
        return 0
    path = sys.argv[1]
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()
    except OSError:
        return 0
    for line_no, header, rows in parse_tables(lines):
        for col_a, col_b, n_rows in find_degenerate_pairs(header, rows):
            print(
                f"L{line_no}: 列「{col_a}」と列「{col_b}」が全{n_rows}行で完全一致"
                "(視点/系列の独立性が壊れている疑い)"
            )
    return 0


if __name__ == '__main__':
    sys.exit(main())
