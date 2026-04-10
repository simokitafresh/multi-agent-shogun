# WF OOM防止設計書
<!-- gunshi 2026-04-10 殿指示: 仕組みに磨き上げよ -->
<!-- 2026-04-10 23:30 更新: cmd_1843 OOM事故記録 + 殿裁定反映 -->

## OOM事故記録 (2026-04-10 23:03:59)

### 経緯
kagemaruがcmd_1843 AC3（wf_runner.py 7本全量 workers=2）実行中にOOM Killerで死亡。

### dmesg証拠
```
oom-kill: task=python3, pid=3333866, total-vm:4447196kB, anon-rss:3092784kB (3.0GB)
oom-kill: task=python3, pid=2262909, total-vm:3972008kB, anon-rss:2732064kB (2.7GB)
oom-kill: task=python3, pid=2114099, total-vm:4200396kB, anon-rss:2996436kB (3.0GB)
```
python3子プロセスがRSS 3-4GB超 → Linux OOM Killer発動 → signal 9 → Claude CLI巻き添え死。

### 環境
- WSL2 16GB RAM + 4GB swap
- Claude CLI 6プロセス常時稼働（合計~2.1GB RSS）
- 実効的な計算用メモリ: ~12GB

### 根因
numpy直読み化(仕組み1)は実装済みだったが、kasoku系は依然3.7GB/本。
並列実行(workers=2)でGroup 1の2プロセス同時起動 + エージェント群常時消費 → 16GB突破。
MEMORY_GROUPSは静的推定値ベースで、エージェント群のメモリ消費を考慮していなかった。

### 殿裁定 (2026-04-10 23:35)
**cmd_1843クローズ。並列ランナー(wf_runner.py)は不要。直列1本ずつ実行が正解。**
理由:
- OOMリスクが激減（1プロセスのみ、最大3.7GB）
- 途中結果を都度保全できる
- 失敗時は当該忍法だけ再実行すればよい

## 3つの仕組み

| # | 仕組み | 解決する問題 | 実装規模 |
|---|--------|------------|---------|
| 1 | load_data() numpy直読み化 | pd.read_csv 48倍膨張OOM | 小(L1527-1541の15行差替え) |
| 2 | GS側.npy同時出力 | キャッシュ不在の構造的排除 | 小(各run_077に3行追加) |
| 3 | wf_runner.py並列ランナー | WF 7本直列→並列 | 中(gs_runner.pyコピー改変80行) |

## 仕組み1: load_data() numpy直読み化

### 現状(OOM箇所)
```python
# L1527-1541: キャッシュなし時
df_full = pd.read_csv(csv_path, index_col="year_month", parse_dates=True, dtype=np.float32)
# → 481K列で13GB(48倍膨張) → OOM Kill
```

### 修正後
```python
# L1527-1541 差替え: pandas不使用。numpy行単位読込み
else:
    print(f"  CSV読込（キャッシュなし・numpy直読み）: {csv_path}", flush=True)
    t0 = time.perf_counter()
    with open(csv_path) as f:
        header = f.readline().rstrip("\n").split(",")
        columns_full = header[1:]  # year_month除外
        index_strs = []
        rows = []
        for line in f:
            parts = line.rstrip("\n").split(",")
            index_strs.append(parts[0])
            row = np.empty(len(parts) - 1, dtype=np.float32)
            for i, v in enumerate(parts[1:]):
                row[i] = np.float32(v) if v and v != "nan" else np.float32("nan")
            rows.append(row)
    arr_full = np.stack(rows)
    index_full = pd.to_datetime(index_strs)
    print(f"  CSV読込完了 {time.perf_counter() - t0:.2f}s  shape={arr_full.shape}", flush=True)
    tc = time.perf_counter()
    save_memmap_cache(arr_full, columns_full, index_full, p)
    arr = np.load(arr_cache, mmap_mode="r")
    columns = np.load(columns_cache, mmap_mode="r")
    index = pd.to_datetime(np.load(index_cache, mmap_mode="r"))
    del arr_full, rows  # 即解放
    print(f"  memmapキャッシュ保存完了 {time.perf_counter() - tc:.3f}s → {arr_cache}", flush=True)
```

### メモリ比較(nukimi 481K列×150行)
| 方式 | peak RSS | 理由 |
|------|----------|------|
| pd.read_csv (現状) | **13,100MB** | BlockManager 48倍膨張 |
| numpy直読み (修正後) | **752MB** | raw float32 + 行バッファのみ |

### 検証済み
- 軍師テスト(2026-04-10): numpy直読み→キャッシュ生成→WF実行 peak 2.8GB, rc=0

## 仕組み2: GS側.npy同時出力

### 現状
GS(run_077_*.py)がCSVを出力 → WFが初回読込時にキャッシュ生成。
キャッシュ不在 = OOMリスク。

### 修正後
GS側でCSV出力と同時に.npyキャッシュも保存。WFは常にキャッシュヒット。

```python
# 各run_077_*.pyのCSV出力箇所(write_monthly_csv_numpy等)に追加:
# CSV出力直後に3行追加
np.save(csv_path.replace(".csv", ".cache.arr.npy"), arr_f32)
np.save(csv_path.replace(".csv", ".cache.columns.npy"), np.array(column_names))
np.save(csv_path.replace(".csv", ".cache.index.npy"), np.array(month_strings))
```

### 効果
- WFの初回CSV読込みが完全に不要になる
- OOMリスクがゼロになる(pd.read_csvを通らない)
- GS側のメモリコストは0(arr_f32は既にメモリ上にある)

### 注意
cmd_1836でCSV出力をnumpy savetxt化済み。arrはfloat32 numpy arrayとして存在する。
.npy保存は3行追加のみ。

## ~~仕組み3: wf_runner.py並列ランナー~~ → **廃止（殿裁定 2026-04-10）**

> **クローズ理由**: 直列実行で十分。並列化はOOMリスクを高め、途中保全を困難にする。cmd_1843でOOM事故発生（上記記録参照）。

### 設計（参考。実装済みだが使用しない）
gs_runner.py(cmd_1831実装済み)のWF版。7忍法のWFを並列実行。

```python
# wf_runner.py 骨格(gs_runner.pyコピー改変)
WF_SCRIPT = "outputs/scripts/l1_alm_wf_engine.py"

NINJUTSU = ["bunshin", "yotsume", "oikaze", "kawarimi",
            "nukimi", "kasoku_diff", "kasoku_ratio"]

# peak RSSによるメモリ制約グループ
MEMORY_GROUPS = [
    ["bunshin", "yotsume", "oikaze", "kawarimi"],  # 合計~2.8GB
    ["nukimi"],                                       # 2.9GB
    ["kasoku_diff"],                                   # 3.7GB
    ["kasoku_ratio"],                                  # 3.7GB
]

def run_single(ninjutsu, csv_dir, out_dir, cmd_id):
    csv_name = f"{cmd_id}_okugi_shin_ninpo_20body_{ninjutsu}_grid_monthly_*.csv"
    csv_path = glob.glob(f"{csv_dir}/{csv_name}")[0]
    child_cmd = [
        sys.executable, WF_SCRIPT,
        "--csv", csv_path,
        "--multi-is", "--cmd-id", cmd_id,
        "--progress", "--out-dir", out_dir,
    ]
    return subprocess.run(child_cmd, capture_output=True, text=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv-dir", required=True)
    parser.add_argument("--cmd-id", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--workers", type=int, default=2)
    args = parser.parse_args()

    # メモリグループ内は並列、グループ間は直列
    for group in MEMORY_GROUPS:
        with ThreadPoolExecutor(max_workers=min(args.workers, len(group))) as ex:
            futures = {ex.submit(run_single, n, ...): n for n in group}
            for f in as_completed(futures):
                r = f.result()
                print(f"[wf_runner] {futures[f]}: rc={r.returncode}")
```

### 速度見込み
| 方式 | 所要時間 | 理由 |
|------|---------|------|
| 直列7本(現状) | ~70min | kasoku_diff律速 |
| 並列(メモリグループ) | ~40min | Wave1(4本同時3min)+nukimi(6min)+kasoku×2直列(60min) |
| 2忍者分割 | ~35min | 忍者A: bunshin〜nukimi / 忍者B: kasoku×2 |

### 実装規模
gs_runner.py(147行)をコピーし、CSVパス→WFコマンドに差替え+メモリグループ追加。~80行。

## cmd提案(3本、依存順)

### cmd-A: load_data() numpy直読み化(最優先・OOM根絶)
- AC1: l1_alm_wf_engine.py L1527-1541をnumpy直読みに差替え
- AC2: nukimi CSV(481K列)でキャッシュなし状態からWF実行。peak RSS < 2GB, rc=0
- AC3: bunshin回帰テスト(キャッシュ削除→再生成→WF実行→allclose rtol=1e-4)
- 実装規模: 15行差替え

### cmd-B: GS .npy同時出力(キャッシュ不在の構造的排除)
- AC1: 7忍法のrun_077_*.pyのCSV出力箇所に.npy保存3行追加
- AC2: bunshin GS実行→.cache.arr.npy生成確認→WFがキャッシュヒット確認
- 実装規模: 各ファイル3行×7=21行

### ~~cmd-C: wf_runner.py並列ランナー~~ → **廃止（殿裁定 cmd_1843クローズ）**

### 依存順（更新後）
cmd-A(OOM根絶) → cmd-B(キャッシュ保証)。
cmd-Aだけで今後のOOMは防げる。cmd-Bで二重防御。
WF実行は直列1本ずつ（cmd_1825方式: `--csv`で1本ずつ、1本≈30-45秒、7本で≈5分）。

### 運用方針（殿裁定 2026-04-10）
```bash
# WF実行は直列。並列ランナー使用禁止。
cd /mnt/c/Python_app/DM-signal
for ninjutsu in bunshin yotsume oikaze kawarimi nukimi kasoku_diff kasoku_ratio; do
  python3 outputs/scripts/l1_alm_wf_engine.py \
    --csv outputs/grid_search/okugi_shin_ninpo_20body/cmd_XXXX_*_${ninjutsu}_grid_monthly_*.csv \
    --multi-is --cmd-id cmd_XXXX --progress \
    --out-dir outputs/analysis/alm_research/okugi_shin_ninpo
done
```
