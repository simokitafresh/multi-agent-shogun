# cmd_494 Signal Pending Display Fix

- cmd: `cmd_494`
- subtask: `subtask_494_impl_pending_display_fix_r2`
- date: `2026-03-03`
- agent: `tobisaru` (hanzo途中差分を引継ぎ完了)
- target_repo: `/mnt/c/Python_app/DM-signal`

## 0. Preflight

- backend test runner: `/mnt/c/Python_app/DM-signal/.venv/Scripts/python.exe -m pytest`
- frontend test runner: `npm test -- --runInBand`
- 前提確認:
  - `.venv/Scripts/python.exe` 利用可能
  - `frontend/node_modules` 存在確認済み

## 1. 実装要約

### 1.1 Backend: `/api/signals` に monthly pending 投影を追加

対象: `/mnt/c/Python_app/DM-signal/backend/app/api/signals.py`

- `_resolve_standard_display_signal()` 追加  
  - monthly かつ `as_of` 月と当日月が不一致のとき、`signal` を pending 表示値として採用
  - 実装: L67-L97
- standardレスポンスに `signal_pending` を追加
  - 実装: L241-L247
- fof/no-dataにも `signal_pending: false` を明示
  - 実装: L196-L202, L255-L261

### 1.2 Frontend: pending表示ラベルを追加

対象: `/mnt/c/Python_app/DM-signal/frontend/components/portfolio-details.tsx`

- `signalPending` prop を `CurrentSignalCard` に追加
  - 実装: L20-L29
- `signal_pending=true` の standard PF で `"Pending Rebalance"` を表示
  - 実装: L47-L49, L109

対象: `/mnt/c/Python_app/DM-signal/frontend/lib/types/portfolio.ts`

- `PortfolioSignal.signal_pending?: boolean` を定義
  - 実装: L97-L103

## 2. テスト

### 2.1 Backend

実行コマンド:

```bash
cd /mnt/c/Python_app/DM-signal/backend
/mnt/c/Python_app/DM-signal/.venv/Scripts/python.exe -m pytest -q tests/test_signals_pending_projection_494.py
```

結果:

- `2 passed, 0 skipped`
- 対象条件:
  - 2026-03-02 pre-open 相当で monthly pending 投影
  - 2026-03-03 pre-open 相当で表示値不変（3/2=3/3）
  - non-monthly 回帰なし
- テスト定義: `/mnt/c/Python_app/DM-signal/backend/tests/test_signals_pending_projection_494.py` L84-L150

### 2.2 Frontend

実行コマンド:

```bash
cd /mnt/c/Python_app/DM-signal/frontend
npm test -- --runInBand app/__tests__/page_masking.test.tsx
```

結果:

- `1 suite passed, 5 tests passed, 0 skipped`
- 追加ケース: `shows pending marker when signal_pending is true`
- テスト定義: `/mnt/c/Python_app/DM-signal/frontend/app/__tests__/page_masking.test.tsx` L176-L188

## 3. AC対応

| AC | 判定 | 根拠 |
|---|---|---|
| AC1 | PASS | `/api/signals` に monthly pending 投影ロジック追加（signals.py L67-L97） |
| AC2 | PASS | monthly は pending表示、non-monthly は従来維持（signals.py L86-L96, test L130-L149） |
| AC3 | PASS | backend/frontend テストとも SKIP=0 で通過 |
| AC4 | PASS | 本ファイル + `context/dm-signal-frontend.md` §14 更新 |
| AC5 | PASS | `queue/reports/tobisaru_report_cmd_494.yaml` に証跡記載 |

## 4. Blind Spots

- `month_changed` 判定は `date.today()` ベースであり、サーバー時刻と運用時刻のずれがある環境では境界判定が変動しうる。
- 今回のテストは API/コンポーネント単位で、実運用DBを用いた E2E 再現は含まない。
