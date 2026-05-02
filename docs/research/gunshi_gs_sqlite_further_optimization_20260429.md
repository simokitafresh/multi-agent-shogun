# GS SQLite高速化 追加最適化候補分析 (2026-04-29)

## 背景
cmd_2397でSQLite書込み40x高速化完了(PRAGMA+blob圧縮+Linux-native+INDEX遅延)。
殿指示: 更なる高速化の余地を調査。

## 3候補評価

### (A) MP_WORKERS env var化 ★最推奨
- 現状: run_077_kasoku_diff.py L165 `MP_WORKERS=1` ハードコード
- SHMモード実装済み(cmd_1035)。fork overhead 92.1%削減
- 実装: `os.environ.get('GS_MP_WORKERS', '1')` の1行変更
- 期待: Phase 1(計算コア) 4-6x高速化。L1: 6.13s→~1-1.5s
- RSS: +12MB/worker(SHM)。6worker=72MB。16GBに余裕
- 注意: 50K未満patではfork overhead支配→env var制御

### (B) calc_metrics_fast 2Dベクトル化 △
- 既にnumpy vectorized(cumulative/drawdown/sharpe)
- GS全体の1.4%。10-20%改善でも全体0.1-0.3%
- ROI低。後回し

### (C) 入力データ.npyキャッシュ △不推奨
- DB読込~100-200ms。月1-2回実行
- ディスクI/O overhead ≈ DB読込時間。cost>benefit

## 追加ボトルネック
- Phase 2(SQLite書込み): zlib compress ~60-90sec(level=1=最低)
- Phase 0(DB read+前処理): ~1-2sec。global_scores AC2共有化済み

## フェーズ別時間構成(L1 kasoku_diff 119Kpat, workers=1)
| Phase | 時間 | 割合 | 状態 |
|-------|------|------|------|
| Phase 0: データロード | ~2sec | 1.6% | 最適化済み(AC2共有) |
| Phase 1: 計算コア(_run_mp) | ~16sec | 13% | ★MP_WORKERS=6で4-6x可 |
| Phase 2: SQLite書込み | ~6sec(NEW) | 5% | cmd_2397で40x改善済み |
| Phase 1(旧): 書込み | ~1168sec(OLD) | 98.6% | → 解消済み |

## 結論
(A) MP_WORKERS env var化 = 1行変更で計算フェーズ4-6x。即実装可能。圧倒的ROI。
