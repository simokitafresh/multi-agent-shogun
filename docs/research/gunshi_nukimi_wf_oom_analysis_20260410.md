# nukimi WF OOM分析

## 日付
2026-04-10

## 事象
- 半蔵: cmd_1839 nukimi WF実行中にOOM Kill (pid=1532315, RSS=12.6GB)
- 影丸: 同cmdで再配備→同じくOOM Kill (pid=1811315, RSS=13.1GB)
- 環境: 15GB total, claude群常駐~3GB → available ~12GB

## 根因

**nukimiのmmapキャッシュ(.npy)が存在しない。**

WFエンジン`load_data()`の動作:
1. キャッシュあり → `np.load(mmap_mode="r")` → メモリ消費0 → OK
2. キャッシュなし → `pd.read_csv()` → pandas DataFrame構築 → **メモリ爆発**

### なぜnukimiだけキャッシュがないか
- kasoku_diff/kasoku_ratio: cmd_1827実行時にキャッシュ生成済み(541MB .npy)
- bunshin/yotsume/oikaze/kawarimi: cmd_1839の半蔵実行で順次キャッシュ生成(これらはCSVが小さくOOMしない)
- nukimi: cmd_1827ではテスト対象外。cmd_1839で初めてWF実行 → キャッシュなし → OOM

### なぜpd.read_csvで13GBになるか
- nukimi CSV: 941MB, 481,651列×150行
- raw float32: 481K×150×4byte = 274MB
- pandas DataFrame overhead: 481K列のBlockManager構築で**47倍膨張**(274MB→13GB)
- pandasのワイドDataFrame(列数>>行数)はメモリ効率が極めて悪い
- 参照: L591教訓「大CSVは実測してから」

### kasoku_diffがOOMしなかった理由
kasoku_diff(944K列, 1.8GB CSV)はcmd_1827実行時にmmapキャッシュ(.npy)が生成済み。
load_data()でキャッシュヒット → mmap読込み(メモリ0) → peak 3.68GB(WF計算のみ)。

## CSV→DataFrame膨張比較

| CSV | ファイルサイズ | 列数 | キャッシュ | peak RSS | 膨張率 |
|-----|-------------|------|----------|----------|--------|
| bunshin | 16MB | 4,686 | 生成済み | ~100MB | 6x |
| oikaze | 468MB | 222,300 | 生成→OK | ~3GB(推定) | 6x |
| nukimi | 941MB | 481,651 | **なし** | **13GB** | **47x** |
| kasoku_diff | 1.8GB | 944,776 | 生成済み | 3.68GB(mmap) | N/A |

## 対策

### 即時(cmd_1839再開前)
nukimi CSVのmmapキャッシュを事前生成するワンショットスクリプト:

```python
import pandas as pd, numpy as np
csv = "outputs/grid_search/okugi_shin_ninpo_20body/cmd_1822_okugi_shin_ninpo_20body_nukimi_grid_monthly_20260409.csv"
# チャンク読込みでメモリ制御
chunks = pd.read_csv(csv, index_col="year_month", parse_dates=True, dtype=np.float32, chunksize=50000)
# ... chunkwise npy save
```

ただしpd.read_csv自体が481K列でOOMするため、**チャンク読込み(列方向分割)またはnumpy直接読込み**が必要。

### 恒久
1. load_data()にCSVサイズ/列数チェック追加。閾値超→チャンク読込みモード
2. GS側でCSV出力時にmmapキャッシュも同時生成(numpy savetxt + .npy保存)
3. cmd_1836(savetxt置換)完了済みなので、GS側で.npy同時出力は容易

## 因果鎖
mmapキャッシュ不在→pd.read_csv(481K列)→pandas BlockManager 47倍膨張→13GB→OOM Kill。
キャッシュ有無がOOM可否を決定。kasoku_diffは偶然キャッシュ済み。nukimiは未生成。
