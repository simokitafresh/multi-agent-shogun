# DM-Signal APIエンドポイント詳細
<!-- cmd_286 | 2026-02-23 | core.md §8から移動。全エンドポイント・レスポンス構造・フロントエンド連携 -->

## アーキテクチャ

- Backend: FastAPI (22ルーター, 84-88エンドポイント)
- Frontend: Next.js (`frontend/lib/api-client.ts`)
- 共通ラッパー: `ApiResponse{success,data,error,message}` (`backend/app/schemas/response.py:7-12`)
- ルーター登録: `backend/app/main.py:313-337 (+debug:341-343)`

## 主要エンドポイント

| パス | 用途 | Backend | Frontend |
|------|------|---------|----------|
| GET /api/signals | シグナル取得 | signals.py:67 | api-client.ts:751 |
| GET /api/portfolios/get | PF一覧 | portfolios.py:147 | api-client.ts:578 |
| POST /api/portfolios/save | PF保存 | portfolios.py:215 | api-client.ts:587 |
| POST /admin/recalculate-sync | 再計算トリガー | etl_trigger.py:235 | api-client.ts:641 |
| GET /api/history/{id} | 履歴 | history.py:27 | api-client.ts:754 |
| GET /api/performance/{id} | パフォーマンス | performance.py:27 | api-client.ts:757 |
| GET /api/metrics/summary | メトリクスサマリー | metrics.py | api-client.ts:777 |
| GET /healthz | ヘルスチェック | main.py | — |

## レスポンス構造（/api/signals）

```
{
  as_of: date,
  calculated_at: datetime,
  portfolios: [
    {
      id, name, type, signal, momentum, hide_symbols, hide_signal, hide_components, benchmark_ticker
      // momentum: { relative: [], absolute, risk_free, safe_haven }
      // _sanitize_momentum_data() (signals.py:28-64) で正規化
    }
  ]
}
```

Frontend型: `SignalsLightResponse` (frontend/lib/types/api.ts:45-49)
状態管理: `SignalsContext` (frontend/contexts/signals-context.tsx)

## momentum_data

- sanitize: `_sanitize_momentum_data()` → `relative[]/absolute/risk_free/safe_haven`
- backend実装: `backend/app/api/signals.py:28-64`
- frontend型: `PortfolioMomentum` (`frontend/lib/types/market.ts:8-13`)
