"""
cmd_1578_recon: Ward相関構造の時系列分析
- AC1: 旧忍法15体のrolling相関行列(36mo lookback)の時系列変化
- AC2: 相関距離行列のヒストグラムとseparability分析
- AC3: シン忍法v2 20体との比較
"""

import os
import sys
import json
import numpy as np
import pandas as pd
from datetime import datetime
from scipy.cluster.hierarchy import ward, fcluster
from scipy.spatial.distance import squareform

# DB接続
sys.path.insert(0, '/mnt/c/Python_app/DM-signal')
from dotenv import load_dotenv
load_dotenv('/mnt/c/Python_app/DM-signal/backend/.env')

import psycopg2

def get_connection():
    return psycopg2.connect(os.environ['DATABASE_URL'])

def fetch_monthly_returns(conn, portfolio_ids):
    """portfolio_idsのmonthly_returnsを取得 (Open-to-Open=デフォルト)"""
    cur = conn.cursor()
    placeholders = ','.join(['%s'] * len(portfolio_ids))
    cur.execute(f"""
        SELECT p.name, mr.year_month, mr.monthly_return
        FROM monthly_returns mr
        JOIN portfolios p ON p.id = mr.portfolio_id
        WHERE mr.portfolio_id IN ({placeholders})
        ORDER BY p.name, mr.year_month
    """, portfolio_ids)
    rows = cur.fetchall()

    # pivot: rows=year_month, cols=portfolio_name
    data = {}
    for name, ym, ret in rows:
        if name not in data:
            data[name] = {}
        data[name][ym] = float(ret) if ret is not None else np.nan

    df = pd.DataFrame(data)
    df.index = pd.to_datetime(df.index + '-01')
    df = df.sort_index()
    return df

def rolling_correlation_analysis(returns_df, lookback_months=36, label=""):
    """Rolling相関行列を計算し、Frobenius normの変化を分析"""
    n_assets = returns_df.shape[1]
    dates = returns_df.index

    # 直近12リバランス日分(2025-04〜2026-03)
    target_months = pd.date_range('2025-04-01', '2026-03-01', freq='MS')

    results = {
        'frobenius_norms': [],
        'correlation_matrices': {},
        'distance_histograms': {},
        'separability': {}
    }

    prev_corr = None

    for t_date in target_months:
        # lookback window
        start_date = t_date - pd.DateOffset(months=lookback_months)
        window = returns_df.loc[(returns_df.index >= start_date) & (returns_df.index < t_date)]

        if len(window) < lookback_months * 0.8:  # 最低80%のデータ
            print(f"  {label} {t_date.strftime('%Y-%m')}: insufficient data ({len(window)} months)")
            continue

        # 相関行列
        corr_matrix = window.corr()
        ym_str = t_date.strftime('%Y-%m')
        results['correlation_matrices'][ym_str] = corr_matrix.values.tolist()

        # Frobenius norm of diff (時系列変化)
        if prev_corr is not None:
            diff = corr_matrix.values - prev_corr
            frob_norm = np.linalg.norm(diff, 'fro')
            results['frobenius_norms'].append({
                'date': ym_str,
                'frobenius_norm': round(float(frob_norm), 6),
                'max_abs_change': round(float(np.max(np.abs(diff))), 6),
                'mean_abs_change': round(float(np.mean(np.abs(diff))), 6)
            })

        prev_corr = corr_matrix.values

        # AC2: 相関距離行列分析
        dist_matrix = 1 - corr_matrix.values
        np.fill_diagonal(dist_matrix, 0)

        # 上三角のペアワイズ距離を取得
        upper_tri_idx = np.triu_indices_from(dist_matrix, k=1)
        pairwise_distances = dist_matrix[upper_tri_idx]

        results['distance_histograms'][ym_str] = {
            'mean': round(float(np.mean(pairwise_distances)), 6),
            'std': round(float(np.std(pairwise_distances)), 6),
            'min': round(float(np.min(pairwise_distances)), 6),
            'max': round(float(np.max(pairwise_distances)), 6),
            'median': round(float(np.median(pairwise_distances)), 6),
            'q25': round(float(np.percentile(pairwise_distances, 25)), 6),
            'q75': round(float(np.percentile(pairwise_distances, 75)), 6),
            'iqr': round(float(np.percentile(pairwise_distances, 75) - np.percentile(pairwise_distances, 25)), 6),
            'n_pairs': len(pairwise_distances)
        }

        # Ward clustering + separability計算
        try:
            # condensed distance matrixを作成 (scipy需要)
            condensed = squareform(np.maximum(dist_matrix, 0))  # 負値を0にクリップ
            linkage = ward(condensed)

            # 2,3,4クラスタで切断してseparabilityを計算
            for n_clusters in [2, 3, 4]:
                if n_assets <= n_clusters:
                    continue
                labels = fcluster(linkage, n_clusters, criterion='maxclust')

                # クラスタ間最小距離 / クラスタ内最大距離
                inter_min = float('inf')
                intra_max = 0

                for c1 in range(1, n_clusters + 1):
                    c1_idx = np.where(labels == c1)[0]
                    # intra-cluster距離
                    for i in range(len(c1_idx)):
                        for j in range(i + 1, len(c1_idx)):
                            d = dist_matrix[c1_idx[i], c1_idx[j]]
                            intra_max = max(intra_max, d)

                    # inter-cluster距離
                    for c2 in range(c1 + 1, n_clusters + 1):
                        c2_idx = np.where(labels == c2)[0]
                        for i in c1_idx:
                            for j in c2_idx:
                                inter_min = min(inter_min, dist_matrix[i, j])

                sep_ratio = round(float(inter_min / intra_max), 6) if intra_max > 0 else float('inf')

                key = f"{ym_str}_k{n_clusters}"
                results['separability'][key] = {
                    'n_clusters': n_clusters,
                    'inter_min': round(float(inter_min), 6),
                    'intra_max': round(float(intra_max), 6),
                    'separability_ratio': sep_ratio,
                    'cluster_sizes': [int(np.sum(labels == c)) for c in range(1, n_clusters + 1)]
                }
        except Exception as e:
            print(f"  {label} {ym_str}: Ward clustering error: {e}")

    return results


def main():
    conn = get_connection()

    # =========================================================================
    # ポートフォリオ取得
    # =========================================================================
    cur = conn.cursor()

    # 旧忍法15体
    cur.execute("""
        SELECT id, name FROM portfolios
        WHERE type='fof' AND (
          name LIKE '追い風-%' OR name LIKE '抜き身-%' OR name LIKE '変わり身-%'
          OR name LIKE '加速-%' OR name LIKE '四つ目-%'
        )
        AND name NOT LIKE 'シン%'
        ORDER BY name
    """)
    old_ninpo = cur.fetchall()
    old_ids = [str(row[0]) for row in old_ninpo]
    old_names = [row[1] for row in old_ninpo]

    # シン忍法v2 20体
    cur.execute("""
        SELECT id, name FROM portfolios
        WHERE type='fof' AND name LIKE 'シン%'
        AND name NOT LIKE 'シン青龍%' AND name NOT LIKE 'シン朱雀%'
        AND name NOT LIKE 'シン白虎%' AND name NOT LIKE 'シン玄武%'
        ORDER BY name
    """)
    shin_ninpo = cur.fetchall()
    shin_ids = [str(row[0]) for row in shin_ninpo]
    shin_names = [row[1] for row in shin_ninpo]

    print(f"旧忍法: {len(old_ids)}体, シン忍法: {len(shin_ids)}体")

    # =========================================================================
    # AC1+AC2: 旧忍法の分析
    # =========================================================================
    print("\n=== AC1+AC2: 旧忍法 rolling相関分析 ===")
    old_returns = fetch_monthly_returns(conn, old_ids)
    print(f"データ期間: {old_returns.index[0].strftime('%Y-%m')} 〜 {old_returns.index[-1].strftime('%Y-%m')}")
    print(f"月数: {len(old_returns)}, ポートフォリオ: {old_returns.shape[1]}")

    old_results = rolling_correlation_analysis(old_returns, lookback_months=36, label="旧忍法")

    # AC1結果出力
    print("\n--- AC1: Frobenius norm of correlation matrix changes ---")
    print(f"{'Date':>10} {'Frob Norm':>12} {'Max Change':>12} {'Mean Change':>12}")
    for fn in old_results['frobenius_norms']:
        print(f"{fn['date']:>10} {fn['frobenius_norm']:>12.6f} {fn['max_abs_change']:>12.6f} {fn['mean_abs_change']:>12.6f}")

    if old_results['frobenius_norms']:
        frob_values = [fn['frobenius_norm'] for fn in old_results['frobenius_norms']]
        print(f"\nFrobenius norm統計: mean={np.mean(frob_values):.6f}, std={np.std(frob_values):.6f}, min={np.min(frob_values):.6f}, max={np.max(frob_values):.6f}")

    # AC2結果出力
    print("\n--- AC2: Distance distribution analysis ---")
    print(f"{'Date':>10} {'Mean Dist':>10} {'Std':>10} {'IQR':>10} {'Min':>10} {'Max':>10} {'Median':>10}")
    for ym, dh in sorted(old_results['distance_histograms'].items()):
        print(f"{ym:>10} {dh['mean']:>10.4f} {dh['std']:>10.4f} {dh['iqr']:>10.4f} {dh['min']:>10.4f} {dh['max']:>10.4f} {dh['median']:>10.4f}")

    print("\n--- AC2: Separability analysis ---")
    print(f"{'Date_k':>15} {'Inter_min':>10} {'Intra_max':>10} {'Sep Ratio':>10} {'Sizes'}")
    for key, sep in sorted(old_results['separability'].items()):
        print(f"{key:>15} {sep['inter_min']:>10.4f} {sep['intra_max']:>10.4f} {sep['separability_ratio']:>10.4f} {sep['cluster_sizes']}")

    # =========================================================================
    # AC3: シン忍法の分析
    # =========================================================================
    print("\n=== AC3: シン忍法v2 rolling相関分析 ===")
    shin_returns = fetch_monthly_returns(conn, shin_ids)
    print(f"データ期間: {shin_returns.index[0].strftime('%Y-%m')} 〜 {shin_returns.index[-1].strftime('%Y-%m')}")
    print(f"月数: {len(shin_returns)}, ポートフォリオ: {shin_returns.shape[1]}")

    shin_results = rolling_correlation_analysis(shin_returns, lookback_months=36, label="シン忍法")

    # AC3: Frobenius
    print("\n--- AC3: Frobenius norm of correlation matrix changes ---")
    print(f"{'Date':>10} {'Frob Norm':>12} {'Max Change':>12} {'Mean Change':>12}")
    for fn in shin_results['frobenius_norms']:
        print(f"{fn['date']:>10} {fn['frobenius_norm']:>12.6f} {fn['max_abs_change']:>12.6f} {fn['mean_abs_change']:>12.6f}")

    if shin_results['frobenius_norms']:
        shin_frob = [fn['frobenius_norm'] for fn in shin_results['frobenius_norms']]
        print(f"\nFrobenius norm統計: mean={np.mean(shin_frob):.6f}, std={np.std(shin_frob):.6f}, min={np.min(shin_frob):.6f}, max={np.max(shin_frob):.6f}")

    # AC3: Distance
    print("\n--- AC3: Distance distribution analysis ---")
    print(f"{'Date':>10} {'Mean Dist':>10} {'Std':>10} {'IQR':>10} {'Min':>10} {'Max':>10} {'Median':>10}")
    for ym, dh in sorted(shin_results['distance_histograms'].items()):
        print(f"{ym:>10} {dh['mean']:>10.4f} {dh['std']:>10.4f} {dh['iqr']:>10.4f} {dh['min']:>10.4f} {dh['max']:>10.4f} {dh['median']:>10.4f}")

    # AC3: Separability
    print("\n--- AC3: Separability analysis ---")
    print(f"{'Date_k':>15} {'Inter_min':>10} {'Intra_max':>10} {'Sep Ratio':>10} {'Sizes'}")
    for key, sep in sorted(shin_results['separability'].items()):
        print(f"{key:>15} {sep['inter_min']:>10.4f} {sep['intra_max']:>10.4f} {sep['separability_ratio']:>10.4f} {sep['cluster_sizes']}")

    # =========================================================================
    # 比較サマリ
    # =========================================================================
    print("\n" + "=" * 80)
    print("=== 旧忍法 vs シン忍法v2 比較サマリ ===")
    print("=" * 80)

    # Frobenius比較
    if old_results['frobenius_norms'] and shin_results['frobenius_norms']:
        old_frob_mean = np.mean([fn['frobenius_norm'] for fn in old_results['frobenius_norms']])
        shin_frob_mean = np.mean([fn['frobenius_norm'] for fn in shin_results['frobenius_norms']])
        print(f"\nFrobenius norm平均: 旧={old_frob_mean:.6f}, シン={shin_frob_mean:.6f}")
        print(f"  → シン/旧 比率: {shin_frob_mean/old_frob_mean:.3f}x")

    # 距離分布比較
    old_dist_means = [dh['mean'] for dh in old_results['distance_histograms'].values()]
    shin_dist_means = [dh['mean'] for dh in shin_results['distance_histograms'].values()]
    old_dist_stds = [dh['std'] for dh in old_results['distance_histograms'].values()]
    shin_dist_stds = [dh['std'] for dh in shin_results['distance_histograms'].values()]

    print(f"\n平均相関距離: 旧={np.mean(old_dist_means):.4f}, シン={np.mean(shin_dist_means):.4f}")
    print(f"距離分布std: 旧={np.mean(old_dist_stds):.4f}, シン={np.mean(shin_dist_stds):.4f}")

    # separability比較 (k=3)
    old_sep_k3 = [v['separability_ratio'] for k, v in old_results['separability'].items() if '_k3' in k]
    shin_sep_k3 = [v['separability_ratio'] for k, v in shin_results['separability'].items() if '_k3' in k]

    if old_sep_k3 and shin_sep_k3:
        print(f"\nSeparability (k=3): 旧平均={np.mean(old_sep_k3):.4f}, シン平均={np.mean(shin_sep_k3):.4f}")

    # 相関行列の固定度: 最初と最後の相関行列のFrobenius距離
    old_corr_dates = sorted(old_results['correlation_matrices'].keys())
    shin_corr_dates = sorted(shin_results['correlation_matrices'].keys())

    if len(old_corr_dates) >= 2:
        first_old = np.array(old_results['correlation_matrices'][old_corr_dates[0]])
        last_old = np.array(old_results['correlation_matrices'][old_corr_dates[-1]])
        total_change_old = np.linalg.norm(first_old - last_old, 'fro')
        print(f"\n期間全体のFrobenius距離(first→last): 旧={total_change_old:.6f}")

    if len(shin_corr_dates) >= 2:
        first_shin = np.array(shin_results['correlation_matrices'][shin_corr_dates[0]])
        last_shin = np.array(shin_results['correlation_matrices'][shin_corr_dates[-1]])
        total_change_shin = np.linalg.norm(first_shin - last_shin, 'fro')
        print(f"期間全体のFrobenius距離(first→last): シン={total_change_shin:.6f}")

    # クラスタ割当の時系列変化分析
    print("\n--- Ward cluster割当の時系列変化 (k=3) ---")
    for label, results, returns_df in [("旧忍法", old_results, old_returns), ("シン忍法", shin_results, shin_returns)]:
        print(f"\n{label}:")
        cluster_assignments = {}
        for ym in sorted(results['correlation_matrices'].keys()):
            corr = np.array(results['correlation_matrices'][ym])
            dist = 1 - corr
            np.fill_diagonal(dist, 0)
            dist = np.maximum(dist, 0)
            try:
                condensed = squareform(dist)
                linkage = ward(condensed)
                labels_arr = fcluster(linkage, 3, criterion='maxclust')
                cluster_assignments[ym] = labels_arr
            except:
                pass

        # 連続する月間のクラスタ割当変化をカウント
        ym_list = sorted(cluster_assignments.keys())
        total_changes = 0
        total_comparisons = 0
        for i in range(1, len(ym_list)):
            prev = cluster_assignments[ym_list[i-1]]
            curr = cluster_assignments[ym_list[i]]
            if len(prev) == len(curr):
                # ラベル置換の影響を最小化: ハンガリアンマッチング的にNMI
                from sklearn.metrics import adjusted_rand_score
                ari = adjusted_rand_score(prev, curr)
                print(f"  {ym_list[i-1]}→{ym_list[i]}: ARI={ari:.4f}")
                total_comparisons += 1
                if ari < 1.0:
                    total_changes += 1

        if total_comparisons > 0:
            stability = 1 - total_changes / total_comparisons
            print(f"  クラスタ安定性: {stability:.1%} ({total_comparisons - total_changes}/{total_comparisons} 一致)")

    # 最終データをJSON保存
    output = {
        'analysis_date': datetime.now().isoformat(),
        'task': 'cmd_1578_recon',
        'old_ninpo': {
            'names': old_names,
            'count': len(old_names),
            'data_period': f"{old_returns.index[0].strftime('%Y-%m')} to {old_returns.index[-1].strftime('%Y-%m')}",
            'months': len(old_returns),
            'frobenius_norms': old_results['frobenius_norms'],
            'distance_stats': old_results['distance_histograms'],
            'separability': old_results['separability']
        },
        'shin_ninpo': {
            'names': shin_names,
            'count': len(shin_names),
            'data_period': f"{shin_returns.index[0].strftime('%Y-%m')} to {shin_returns.index[-1].strftime('%Y-%m')}",
            'months': len(shin_returns),
            'frobenius_norms': shin_results['frobenius_norms'],
            'distance_stats': shin_results['distance_histograms'],
            'separability': shin_results['separability']
        }
    }

    output_path = '/mnt/c/tools/multi-agent-shogun/outputs/analysis/cmd_1578_ward_correlation_results.json'
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    print(f"\n結果保存: {output_path}")

    conn.close()

if __name__ == '__main__':
    main()
