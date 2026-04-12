# L2奥義GS OOM根因分析+修正設計書
<!-- gunshi consultation 2026-04-12 家老依頼: cmd_1871 OOM Kill分析 -->
<!-- v2: 殿指摘「L1は最大21体。L2構成PFも最大21体」を反映 -->

## 結論

**本質的な問題: universe CSVが42列(7忍法×6目的全列挙)になっていた。L1チャンピオンは最大21体(7忍法×3目的/モード)。universeを21列に修正すればOOMは解消する。**

| universe | 現状N | 正しいN | bunshin | kasoku_diff(peak) | OOM? |
|----------|-------|---------|---------|-------------------|------|
| okugi_shin_alm | 42 | **21** | 124,271→7,525 | 190M→1.15M | 42:Yes → **21:No** |
| okugi_alm_shin | 21 | 21 | 7,525 | 1,151,325 | **No** |
| okugi_alm_alm | 42 | **21** | 124,271→7,525 | 190M→1.15M | 42:Yes → **21:No** |

N=21で全7忍法のpeak RSS:

| 忍法 | パラメータ倍率 | パターン数 | メモリ(2x) | メモリ(1x) | 判定 |
|------|-------------|-----------|-----------|-----------|------|
| bunshin | ×1 | 7,525 | 15 MB | 8 MB | OK |
| yotsume | ×3 | 22,575 | 46 MB | 23 MB | OK |
| oikaze | ×8 | 60,200 | 123 MB | 62 MB | OK |
| kawarimi | ×36 | 270,900 | 554 MB | 277 MB | OK |
| nukimi | ×84 | 632,100 | 1,292 MB | 646 MB | OK |
| kasoku_diff | ×153 | 1,151,325 | 2,354 MB | 1,177 MB | OK |
| kasoku_ratio | ×153 | 1,151,325 | 2,354 MB | 1,177 MB | OK |

**N=21 + Phase 0廃止(1x) = peak 1,177MB。エージェント2.1GB + python 1.2GB + OS 1GB = 4.3GB。16GB余裕。**

## なぜなぜ7回

| # | なぜ | 計測事実 |
|---|------|---------|
| 1 | なぜOOM Kill? | python3 RSS=2,458MB(dmesg)。16GB中agent~2.1GB+python 2.4GB→OOM |
| 2 | なぜRSS 2.4GB? | build_grid()がC(N,2)+C(N,3)+C(N,4)生成。N=42→124,271パターン(bunshinだけ) |
| 3 | なぜN=42? | okugi_shin_alm universe CSVが7忍法×**6目的**=42列 |
| 4 | なぜ6目的? | ALM WFエンジンが6目的(cagr/nhf/maxdd/mru/calmar/uwp)全ての月次リターンを出力したため |
| 5 | なぜ6目的全て入れた? | L1→L2のデータ構造を考えずに出力をそのままuniverseに流し込んだ |
| 6 | **L1は最大何体？** | 7忍法×3目的(シン:CAGR/NHF/MaxDD or ALM:MRU/Calmar/UWP)=**最大21体** |
| 7 | **根因: L1の出力体数(21)とuniverse設計(42)の不一致** | L1チャンピオンは目的ごとに1体。6目的のメトリクス値は同一チャンピオンの評価指標であり、別PFではない。universeに入れるべきは「チャンピオンの月次リターン」(21列)であって「全目的の月次リターン」(42列)ではない |

## 修正プラン

### 修正1: universe CSV/YAMLを21列に修正（本質的修正）

okugi_shin_alm と okugi_alm_alm の統合CSVから、L1チャンピオンの3目的のみを残す:
- シン×ALM (cmd_1867): 7忍法×**3目的(cagr/nhf/maximum_drawdown)** = 21列
- ALM×ALM (cmd_1863): 7忍法×**3目的(max_run_up/calmar_ratio/underwater_period)** = 21列

okugi_alm_shin (cmd_1868)は既に21列で正しい。

### 修正2: Phase 0(baseline)廃止（推奨だが必須ではない）

N=21ならPhase 0ありでも全忍法がメモリ内に収まる(peak 2,354MB < 3GB safe limit)。
ただしPhase 0廃止で半減→peak 1,177MB→さらに安全。

Phase 0はPhase 1(fast)と同一結果を検証するための二重計算。L2はL1検証済みの道具を使うため、Phase 0は省略してもリスクは低い。

### 修正3: run_077の既存ファイル上書き防止をリセット

```python
# L595-597: 既存ファイルがあるとERROR
for p in [csv_path_fast, csv_path_monthly_fast]:
    if p.exists():
        print(f"ERROR: {p} already exists. Rename or move it first.", file=sys.stderr)
        return 1
```

cmd_1871再実行時、前回のOOM前に部分出力されたファイルが残っている可能性。忍者はこれを削除またはリネームしてから再実行する必要がある。

## OOM計算の実測根拠

- dmesg: `Out of memory: Killed process 3610835 (python3) total-vm:4094944kB, anon-rss:2458364kB`
- N=42 bunshin: C(42,2)+C(42,3)+C(42,4)=124,271パターン × 134月 × 8bytes × 2(baseline+fast) = 254MB
- 加えてPhase 1のPipelineEngine import + rows_baseline/rows_fast dict + 各パターンのmetrics dict → 合計~2.4GB
- **bunshin(最軽量スクリプト)ですら2.4GBでOOM** → 他スクリプトはさらに重い

## 因果鎖

```
L1 ALM WFエンジンが6目的の月次リターンを出力
  → 6目的全てをuniverse CSV列に投入(42列)
  → L1チャンピオン=21体なのにuniverseは42コンポーネント
  → run_077のbuild_grid()がC(42,k)を生成 → 124K〜190Mパターン → OOM
  → 根因: L1の体数(21)とuniverse設計(42)の不一致
  → 修正: universe CSVを21列(L1チャンピオン対応3目的)に修正
  → N=21なら全7忍法がメモリ内(peak 2.4GB)。run_077変更不要
```

## 実行ランブック（忍者向け）

### Step 0: universe CSV修正（本質修正）

1. okugi_shin_alm: 42列→21列に修正（cagr/nhf/maximum_drawdown の3目的のみ残す）
2. okugi_alm_alm: 同上（max_run_up/calmar_ratio/underwater_period の3目的のみ残す）
3. universe YAMLのcomponents/familiesを21体に修正
4. **検証**: `head -1 <csv>` で列数確認。year_month + 21列 = 22列

### Step 1: 前回OOMの残骸削除

```bash
# OOM前に部分出力されたファイルを確認・削除
ls outputs/grid_search/okugi_*/metrics_*  # 部分ファイルがあれば削除
```

### Step 2: GS実行（3パターン×7忍法=21 GS、直列）

```bash
# 各忍法のrun_077を各universeで実行
for universe in okugi_shin_alm okugi_alm_shin okugi_alm_alm; do
  for script in run_077_*.py; do
    python3 scripts/analysis/grid_search/$script \
      --universe config/portfolio_universes/${universe}.yaml \
      --out-dir outputs/grid_search/${universe}/
  done
done
```

**LG025準拠: 直列1本ずつ。** N=21ならpeak 2.4GB(2x) or 1.2GB(1x)で安全。

### Step 3: ②WFエンジン実行

既存okugi_shin_ninpo_20body → WFエンジン直接実行（cmdのStep 3）。GS不要。

## 既存L2実績（リファレンス）

**okugi_shin_ninpo_20body** (cmd_1822): シン忍法20体のL2 GSが全7忍法で完走済み。

```
universe: config/portfolio_universes/okugi_shin_ninpo_20.yaml
source_type: db
components: 20 (7忍法×3モード - 吸収)
GS output: outputs/grid_search/okugi_shin_ninpo_20body/
kasoku_diff: 944,775パターン (N=20, peak ~1.9GB) → 正常完走
```

**新L2 universeもN≤21にすれば同じ構造で動作する。** run_077変更不要。universe CSV/YAMLの列数修正のみ。

## 設計書作成日
- v1: 2026-04-12T15:55:00+09:00 — 初版(N=42問題発見+run_077廃止提案)
- v2: 2026-04-12T16:15:00+09:00 — 殿指摘反映。L1最大21体→universe 21列修正が本質的解。run_077はN=21で使用可能
- v3: 2026-04-12T16:25:00+09:00 — 殿指摘反映。既存L2(okugi_shin_ninpo_20body, N=20)が実績リファレンス。考えずに確認。現物→結論の順
