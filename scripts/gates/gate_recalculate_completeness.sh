#!/usr/bin/env bash
# gate_recalculate_completeness.sh — GP-124: fullrecalculate後データ完全性チェック
# 用途: fullrecalculate後に全active portfolioがsignals+monthly_returns(+FoFはcomponent_weights)を持つことを検証
# 使い方: bash scripts/gates/gate_recalculate_completeness.sh
# 前提: backend/.envにDATABASE_URLが設定されていること
set -euo pipefail

DM_SIGNAL_DIR="/mnt/c/Python_app/DM-signal"
ENV_FILE="$DM_SIGNAL_DIR/backend/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "FAIL: $ENV_FILE が見つかりません"
    exit 1
fi

# DATABASE_URLを環境変数として渡す（シェル展開の問題回避）
export DATABASE_URL
DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_FILE" | head -1 | sed 's/^DATABASE_URL=//')
if [[ -z "$DATABASE_URL" ]]; then
    echo "FAIL: DATABASE_URLが空です"
    exit 1
fi

echo "=== GP-124: Recalculate Data Completeness Check ==="
echo ""

# PythonでDB接続してチェック（DATABASE_URLは環境変数経由）
python3 << 'PYEOF'
import os, sys
try:
    from sqlalchemy import create_engine, text
    db_url = os.environ["DATABASE_URL"]
    engine = create_engine(db_url)
    with engine.connect() as conn:
        # 1. 全active portfolioを取得
        pfs = conn.execute(text(
            "SELECT id, name, type FROM portfolios WHERE is_active = true ORDER BY type, name"
        )).fetchall()
        total = len(pfs)
        standard = [p for p in pfs if p[2] == "standard"]
        fofs = [p for p in pfs if p[2] == "fof"]
        print(f"Active portfolios: {total} (standard={len(standard)}, fof={len(fofs)})")
        print()

        # 2. signals件数チェック
        sig_counts = conn.execute(text("""
            SELECT p.id, p.name, p.type, COUNT(s.date) as sig_count
            FROM portfolios p
            LEFT JOIN signals s ON p.id = s.portfolio_id
            WHERE p.is_active = true
            GROUP BY p.id, p.name, p.type
            ORDER BY sig_count ASC
        """)).fetchall()

        missing_signals = [r for r in sig_counts if r[3] == 0]
        if missing_signals:
            print(f"FAIL: {len(missing_signals)} portfolios with 0 signals:")
            for r in missing_signals:
                print(f"  - {r[1]} ({r[2]}, id={r[0][:8]}...)")
        else:
            print(f"PASS: All {total} portfolios have signals")

        print()

        # 3. monthly_returns件数チェック
        mr_counts = conn.execute(text("""
            SELECT p.id, p.name, p.type, COUNT(mr.year_month) as mr_count
            FROM portfolios p
            LEFT JOIN monthly_returns mr ON p.id = mr.portfolio_id
            WHERE p.is_active = true
            GROUP BY p.id, p.name, p.type
            ORDER BY mr_count ASC
        """)).fetchall()

        missing_mr = [r for r in mr_counts if r[3] == 0]
        if missing_mr:
            print(f"FAIL: {len(missing_mr)} portfolios with 0 monthly_returns:")
            for r in missing_mr:
                print(f"  - {r[1]} ({r[2]}, id={r[0][:8]}...)")
        else:
            print(f"PASS: All {total} portfolios have monthly_returns")

        print()

        # 4. FoF component_weights チェック (FoFのみ)
        missing_cw = []
        if fofs:
            fof_ids = [f[0] for f in fofs]
            for fid in fof_ids:
                row = conn.execute(text(
                    "SELECT p.name, COUNT(cw.date) as cw_count "
                    "FROM portfolios p "
                    "LEFT JOIN fof_component_weights cw ON p.id = cw.portfolio_id "
                    "WHERE p.id = :pid GROUP BY p.name"
                ), {"pid": fid}).fetchone()
                if row and row[1] == 0:
                    missing_cw.append(row[0])

            if missing_cw:
                print(f"FAIL: {len(missing_cw)} FoFs with 0 component_weights:")
                for name in missing_cw:
                    print(f"  - {name}")
            else:
                print(f"PASS: All {len(fofs)} FoFs have component_weights")
        else:
            print("INFO: No FoF portfolios found")

        print()

        # 5. 総合判定
        fails = len(missing_signals) + len(missing_mr) + len(missing_cw)
        if fails == 0:
            print("=== VERDICT: PASS — All data complete ===")
        else:
            print(f"=== VERDICT: FAIL — {fails} gaps detected ===")
            sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYEOF
