# cmd_808: Monthly Returns Before計測

> 計測日: 2026-03-12 05:05-05:15 JST
> 計測者: tobisaru (CDP perf_measure.py + curl直接計測)
> 目的: monthly-returns APIのfallback全scan問題(cmd_805偵察)のBefore計測

## §1 計測環境

| 項目 | 値 |
|------|-----|
| FE | dm-signal-frontend.onrender.com |
| BE | dm-signal-backend.onrender.com |
| Browser | Edge 145.0.3800.97 (CDP port 9223) |
| Protocol | h3 (QUIC) |
| CDPツール | perf_measure.py (preflight-first統合フロー cmd_815) |
| 計測対象PF | 45eb0c3a-a256-48f3-b3e3-d2a9d5c3bbfa (デフォルトPF) |

## §2 CDP計測結果 (ページロード)

### Cold Cache (cookie/SW cache削除後)

| Run | page load (ms) | /api/monthly-returns (months=12) | /api/monthly-returns (months=120) | /api/signals |
|-----|---------------|----------------------------------|-----------------------------------|-------------|
| 1 | 552 | 1,387ms | 1,154ms | 206ms |
| 2 | 87 | (SW cached) | (SW cached) | 233ms |
| 3 | 74 | (SW cached) | (SW cached) | 196ms |
| **Median** | **87** | — | — | — |

- Run 1のみ/api/monthly-returnsが観測される（Run 2-3はService Worker SWRキャッシュヒット）
- Status: PASS (threshold 2500ms)

### Warm Cache (セッション維持)

| Run | page load (ms) | /api/monthly-returns (months=12) | /api/monthly-returns (months=120) | /api/signals |
|-----|---------------|----------------------------------|-----------------------------------|-------------|
| 1 | 75 | (SW cached) | (SW cached) | 212ms |
| 2 | 544 | 1,358ms | 1,222ms | 431ms |
| 3 | 116 | (SW cached) | (SW cached) | 261ms |
| **Median** | **116** | — | — | — |

- Run 2でSWRキャッシュ期限切れにより/api/monthly-returnsが再発火
- Status: PASS (threshold 2500ms)

## §3 直接API計測 (curl, キャッシュなし)

**重要**: CDPのresource timingはSWRキャッシュの恩恵を受ける。以下はcurl直接呼び出しによるキャッシュなし計測。

### /api/monthly-returns (months=12)

| Run | Response Time (s) |
|-----|------------------|
| 1 | 5.89 |
| 2 | 5.74 |
| 3 | 5.85 |
| **Median** | **5.85** |

### /api/monthly-returns (months=120)

| Run | Response Time (s) |
|-----|------------------|
| 1 | 5.86 |
| 2 | 5.71 |
| 3 | 5.71 |
| **Median** | **5.71** |

## §4 分析

### ボトルネック特定

| 指標 | 値 | 判定 |
|------|-----|------|
| /api/monthly-returns (months=12, no cache) | **5.85s** | 極端に遅い |
| /api/monthly-returns (months=120, no cache) | **5.71s** | 極端に遅い |
| /api/monthly-returns (months=12, CDP w/ SWR) | 1.39s | SWRキャッシュ効果大 |
| /api/monthly-returns (months=120, CDP w/ SWR) | 1.15s | SWRキャッシュ効果大 |
| /api/signals | 0.20-0.43s | 正常範囲 |
| ページロード (cold median) | 87ms | 良好 |
| ページロード (warm median) | 116ms | 良好 |

### 所見

1. **fallback全scan問題の確認**: cmd_805偵察で報告された7.8sに近い5.7-5.9sのレスポンスタイムを確認。キャッシュなしではMonthly Returns APIが致命的に遅い
2. **SWRキャッシュの効果**: CDPでのresource timing(1.2-1.4s)はSWRキャッシュによって大幅に短縮されている。ユーザー体験上は初回アクセス時のみ5s超の待ち時間が発生
3. **months=12とmonths=120の差が小さい**: 両方とも5.7-5.9sで月数による差がほぼない。全scanが原因でmonthsパラメータが実質的に効いていない裏付け
4. **ページロード自体は高速**: Next.js SSR + Service Worker により、ページシェルは74-116msでロード完了

## §5 JSON生データパス

- Cold: `/mnt/c/Python_app/auto-ops/results/perf_20260312_050948.json`
- Warm: `/mnt/c/Python_app/auto-ops/results/perf_20260312_051316.json`
- Markdown: `/mnt/c/Python_app/auto-ops/results/perf_20260312_050948.md`, `perf_20260312_051316.md`
- Screenshots: `/mnt/c/Python_app/auto-ops/results/screenshots/monthly-returns_*.png`
