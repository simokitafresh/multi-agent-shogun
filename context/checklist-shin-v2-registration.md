# シン四神v2 + シン忍法v2 本番登録チェックリスト

> 土台から積む。GSが本番と一致することが全ての信頼の基盤。

## 用語定義（混同厳禁）

| 用語 | 意味 | 実体 |
|------|------|------|
| **狭義GS（四神作成スクリプト）** | パラメータ空間を総当たり探索しチャンピオン（シン四神12体）を選定するグリッドサーチ | `scripts/analysis/grid_search/shin_shijin_l1_gs.py` |
| **忍法スクリプト** | 四神12体をコンポーネントとして受け取り、selection block + terminal blockでFoF(忍法)を構成・計算する。1スクリプト = 1ビルディングブロック | `scripts/analysis/grid_search/run_077_*.py`（7本） |
| **GS（広義）** | 上記2種を含む `scripts/analysis/grid_search/` ディレクトリ全体 | 狭義GS + 忍法スクリプト7本 + 共通ライブラリ |

**忍法スクリプト一覧（7本 = 7ビルディングブロック）**:

| # | スクリプト | 忍法 | selection block |
|---|----------|------|----------------|
| 1 | `run_077_oikaze.py` | 追い風 | MomentumFilter |
| 2 | `run_077_nukimi.py` | 抜き身 | SingleViewMomentumFilter |
| 3 | `run_077_kawarimi.py` | 変わり身 | TrendReversalFilter |
| 4 | `run_077_kasoku_ratio.py` | 加速R | MomentumAccelerationFilter(ratio) |
| 5 | `run_077_kasoku_diff.py` | 加速D | MomentumAccelerationFilter(diff) |
| 6 | `run_077_bunshin.py` | 分身 | なし（EqualWeight単体） |
| 7 | `run_077_yotsume.py` | 四つ目 | MultiViewMomentumFilter |

**流れ**: 狭義GS → シン四神12体（コンポーネント） → 忍法スクリプト7本 → シン忍法v2 21体（7忍法×3モード）

## 0. 清掃: 汚染データの除去

本番DBに汚染シンv2(パリティFAIL状態)が33体残存。これを除去してから全てが始まる。

| # | ステップ | 確認 | 完了日時 |
|---|---------|------|---------|
| 0a | 汚染シンv2忍法(FoF)21体 DELETE — FoF参照があるため先に削除 | API DELETE×21体成功 ✅ | 2026-03-22 23:50 |
| 0b | 汚染シンv2四神(standard)12体 DELETE — FoF削除後に実行 | API DELETE×12体成功 ✅ | 2026-03-22 23:51 |
| 0c | 削除後の本番DB確認 — 「シン*」が0体であること | API GET応答で確認 ✅ (124→91, 33体削除) | 2026-03-22 23:51 |

> **🛑 必ずここで止まれ**: Step 0完了を殿に報告し、Step 2開始の承認を得よ

## 1. 土台: GSと本番のパリティ

パリティ = GSが本番と同じ結果を出せる証明。これがなければチャンピオンは信頼できず、登録しても意味がない。

**ルール2つだけ**: holding_signal完全一致 + monthly_return完全一致

#### 確認済み事実（本番DB照合 2026-03-22）

1. **分身 = FoF（type=fof）であり、standard PFではない**。selection_blocks=なし、terminal=EqualWeight。Ave-X、v1四神、劇薬DMオリジナル/スムーズと同一構造
2. **Step 1（standard PFパリティ）はFoFの計算正当性を証明しない**。FoFはEqualWeight集約+selection pipelineという独自計算パスを持つため、別途Step 2で検証必須
3. **v2忍法の全selection blockは、v1忍法にパラメータ違いで既に存在する**（本番DB確認済み）:
   - MomentumFilter → 追い風（v1）
   - SingleViewMomentumFilter → 抜き身（v1）
   - TrendReversalFilter → 変わり身（v1）
   - MomentumAccelerationFilter → 加速（v1）
   - MultiViewMomentumFilter → 四つ目（v1）, bam-2, bam-6
4. **Step 2がStep 3-4の前提となる理由**: v2忍法が使う全コードパス（selection block + terminal block）は既存FoFで既に使われている。Step 2で既存FoFのパリティを証明すれば、同じコードパスがv2でも正しく動く基盤が確立される
5. **FoF削除順序制約**: DELETE APIはFoF参照が残るstandard PFの削除を拒否する。削除順序: FoF先→standard後（Step 0a→0b）

### Step 1: Standard PFパリティ（numpy快速パス）

**原則**: シミュレーション結果 = 本番結果。この等式が成立して初めてGS探索に意味がある。

**検証対象**: `shin_shijin_l1_gs.py`のnumpy快速パス（`pipeline_config=None`、`cache.momentum_matrix`使用）が本番DBのholding_signal + monthly_returnと完全一致するか。

> ⚠️ **PI-009の適用範囲**: PI-009（本番同一エンジン必須）はパリティ検証（`run_parity_check`）に適用。GS探索（`run_family_grid`）には適用しない。GS探索にPipelineEngineを強制すると全パターンが同一シグナルになり、パラメータ探索として機能しない。

| # | 対象 | 方法 | 結果 | 完了日時 |
|---|------|------|------|---------|
| 1a | 4ファミリー代表(DM2/DM3/DM6/DM7+) numpy快速パス | holding_signal + monthly_return vs 本番DB | PASS (DM2:179mo DM3:190mo DM6:191mo DM7+:167mo 全月hs+ret完全一致) ✅ | 2026-03-23 23:20 |
| 1b | 不一致があれば快速パスのデータ処理修正(^VIX日付等) | 修正→再検証→PASS確認 | ^VIX grid汚染修正が必要だった(cmd_1353 AC1)。`_build_cache_fast`から^VIX除外+`_build_vix_native_cache`追加 ✅ | 2026-03-24 00:30 |
| 1c | 全53体 numpy快速パス hs+ret完全一致 | `verify_all_portfolios.py --numpy-fast` 53体全量突合 | PASS 53/53 (hs+ret両方完全一致。cmd_1351→1352→1353ラルフループ) ✅ | 2026-03-24 00:30 |

> 参考: PipelineEngineパスでの検証は65/65 PASS済み(cmd_1243+1245, 2026-03-22)。ただしこれはPipelineEngine同士の突合であり、numpy快速パスの正当性は未証明。
> **cmd_1351→1353経緯**: cmd_1351(52/53,L0-M_XLU FAIL) → cmd_1352(hs+ret独立突合: ret52/53,hs43/53=9 false positive) → 軍師deepdive(L186 sorted比較バグ+^VIX PI-010同一クラス特定) → cmd_1353(^VIX native cache + sorted比較 → 53/53)

#### AC1突合結果 (cmd_1276, 2026-03-23 22:37)

本番DBで `type=fof` かつ `selection_pipeline.blocks` 空のFoF = **17体**。
Phase Aチェックリスト14体は全て含まれる。差異の3体（劇薬bam/bam_guard/bam_solid）はPhase G（ネステッドFoF）に正しく分類済み。**欠落なし。完全一致。**

### Step 2: 既存FoFパリティ（ビルディングブロック種類別）

**検証方法**: 各忍法スクリプト(`run_077_*.py`)を、既存本番FoFと同じ設定で実行し、出力（holding_signal + monthly_return）が本番と完全一致するか検証する。ビルディングブロック（selection block）の種類ごとに1 Phaseずつ進め、前のPhaseの知見を次に反映する。

> **進行ルール**: 1 Phaseが完了+知見抽出されるまで次のPhaseに進むな

#### Phase A: EqualWeight単体（selection=なし） — 全FoFの土台

使用スクリプト: `run_077_bunshin.py`
証明すること: FoFのEqualWeight集約計算パスが正しい。これがFAILなら全FoFの土台が崩れる。

| FoF | component構成 | 結果 | 完了日時 |
|-----|-------------|------|---------|
| 常勝-朱雀 | L0×3 | PASS (75mo, hs=1637/1637, ret=75/75, cum=75/75) ✅ | 2026-03-23 22:38 |
| 常勝-玄武 | L0×4 | PASS (75mo, hs=1637/1637, ret=75/75, cum=75/75) ✅ | 2026-03-23 22:38 |
| 常勝-白虎 | L0×5 | PASS (75mo, hs=1637/1637, ret=75/75) ✅ | 2026-03-23 01:05 |
| 常勝-青龍 | L0×2 | PASS (75mo, hs=1637/1637, ret=75/75) ✅ | 2026-03-23 01:05 |
| 激攻-朱雀 | L0×2 | PASS (75mo, hs=1637/1637, ret=75/75) ✅ | 2026-03-23 01:03 |
| 激攻-玄武 | L0×2 | PASS (75mo, hs=1637/1637, ret=75/75) ✅ | 2026-03-23 01:03 |
| 激攻-白虎 | L0×2 | PASS (75mo, hs=1637/1637, ret=75/75) ✅ | 2026-03-23 01:03 |
| 激攻-青龍 | L0×3 | PASS (75mo, hs=1637/1637, ret=75/75, cum=75/75) ✅ | 2026-03-23 22:32 |
| 鉄壁-玄武 | L0×3 | PASS (75mo, hs=1637/1637, ret=75/75, cum=75/75) ✅ | 2026-03-23 22:32 |
| 鉄壁-白虎 | L0×2 | PASS (75mo, hs=1637/1637, ret=75/75, cum=75/75) ✅ | 2026-03-23 22:32 |
| Ave-X | DM系×6 | PASS (hs=1637/1637, mr_close=75/75, mr_open=75/75, cum=75/75) ✅ | 2026-03-23 01:04 |
| 裏Ave-X | DM系×4 | PASS (hs=1637/1637, mr_close=75/75, mr_open=75/75, cum=75/75) ✅ | 2026-03-23 01:04 |
| 劇薬DMオリジナル | DM系×3 | PASS (hs=1637/1637, mr_close=75/75, mr_open=75/75, cum=75/75) ✅ | 2026-03-23 01:05 |
| 劇薬DMスムーズ | DM系×4 | PASS (hs=1637/1637, mr_close=75/75, mr_open=75/75, cum=75/75) ✅ | 2026-03-23 01:05 |

> **🛑 必ずここで止まれ**: Phase A結果+知見を殿に報告。EqualWeight土台の正当性確認後、Phase Bへの承認を得よ

#### Phase B: MomentumFilter — 選別ブロック1種目

使用スクリプト: `run_077_oikaze.py`
証明すること: EqualWeight（Phase A済）+ MomentumFilter選別パスが正しい

| FoF | selection block | 結果 | 完了日時 |
|-----|----------------|------|---------|
| 追い風-常勝 | MomentumFilter(15mo,top1) | PASS (153mo, ret=153/153) ✅ | 2026-03-23 18:54 |
| 追い風-激攻 | MomentumFilter(18mo,top1) | PASS (150mo, ret=150/150) ✅ | 2026-03-23 18:54 |
| 追い風-鉄壁 | MomentumFilter(18mo,top2) | PASS (156mo, ret=156/156) ✅ | 2026-03-23 18:54 |

> **🛑 必ずここで止まれ**: Phase B結果+知見を殿に報告。承認後にPhase Cへ

#### Phase C: SingleViewMomentumFilter — 選別ブロック2種目

使用スクリプト: `run_077_nukimi.py`
証明すること: EqualWeight + SingleViewMomentumFilter選別パスが正しい

| FoF | selection block | 結果 | 完了日時 |
|-----|----------------|------|---------|
| 抜き身-常勝 | SVMF(18M,SK3,N1) | PASS (150mo, ret=150/150) ✅ | 2026-03-23 20:13 |
| 抜き身-激攻 | SVMF(18M,SK3,N1) | PASS (150mo, ret=150/150) ✅ | 2026-03-23 20:13 |
| 抜き身-鉄壁 | SVMF(18M,SK1,N1) | PASS (159mo, ret=159/159) ✅ | 2026-03-23 20:13 |

> **🛑 必ずここで止まれ**: Phase C結果+知見を殿に報告。承認後にPhase Dへ

#### Phase D: TrendReversalFilter — 選別ブロック3種目

使用スクリプト: `run_077_kawarimi.py`
証明すること: EqualWeight + TrendReversalFilter選別パスが正しい

| FoF | selection block | 結果 | 完了日時 |
|-----|----------------|------|---------|
| 変わり身-常勝 | TRF(24m,top2) | PASS (144mo, ret=144/144) ✅ | 2026-03-23 20:28 |
| 変わり身-激攻 | TRF(24m,top1) | PASS (150mo, ret=150/150) ✅ | 2026-03-23 20:28 |
| 変わり身-鉄壁 | TRF(24m,top1) | PASS (143mo, 初月ret除く) ✅ | 2026-03-23 20:28 |

> **🛑 必ずここで止まれ**: Phase D結果+知見を殿に報告。承認後にPhase E1へ

#### Phase E1: MomentumAccelerationFilter(ratio) — 選別ブロック4種目

使用スクリプト: `run_077_kasoku_ratio.py`
証明すること: EqualWeight + MomentumAccelerationFilter(ratio)選別パスが正しい

| FoF | method | 本番config確認済み | 結果 | 完了日時 |
|-----|--------|-----------------|------|---------|
| 加速-激攻 | ratio | num=10d, den=84d, top_n=1 | PASS (171mo, ret=171/171) ✅ | 2026-03-23 20:44 |
| 加速-常勝 | ratio | num=378d, den=504d, top_n=1 | PASS (150mo, ret=150/150) ✅ | 2026-03-23 20:44 |

> **🛑 必ずここで止まれ**: Phase E1結果+知見を殿に報告。承認後にPhase E2へ

#### Phase E2: MomentumAccelerationFilter(diff) — 選別ブロック5種目

使用スクリプト: `run_077_kasoku_diff.py`
証明すること: EqualWeight + MomentumAccelerationFilter(diff)選別パスが正しい

| FoF | method | 本番config確認済み | 結果 | 完了日時 |
|-----|--------|-----------------|------|---------|
| 加速-鉄壁 | diff | num=189d, den=210d, top_n=1 | PASS (158mo, ret=158/158) ✅ | 2026-03-23 20:44 |

> **🛑 必ずここで止まれ**: Phase E2結果+知見を殿に報告。承認後にPhase Fへ

#### Phase F: MultiViewMomentumFilter — 選別ブロック6種目

使用スクリプト: `run_077_yotsume.py`
証明すること: EqualWeight + MultiViewMomentumFilter選別パスが正しい。同一selection blockの複数FoFをまとめて検証。

| FoF | selection block | 結果 | 完了日時 |
|-----|----------------|------|---------|
| 四つ目-常勝 | MultiViewMomentumFilter | PASS (162mo, ret=162/162) ✅ | 2026-03-23 21:12 |
| 四つ目-激攻 | MultiViewMomentumFilter | PASS (150mo, ret=150/150) ✅ | 2026-03-23 21:12 |
| 四つ目-鉄壁 | MultiViewMomentumFilter | PASS (156mo, ret=156/156) ✅ | 2026-03-23 21:12 |
| bam-2 | MultiViewMomentumFilter | PASS (162mo, ret=161/162, 初月L485) ✅ | 2026-03-23 21:12 |
| bam-6 | MultiViewMomentumFilter | PASS (178mo, ret=177/178, 初月L485) ✅ | 2026-03-23 21:12 |

> **🛑 必ずここで止まれ**: Phase F結果+知見を殿に報告。全selection block検証完了。承認後にPhase Gへ

#### Phase G: ネステッドFoF — componentにFoFを含む再帰構造

使用スクリプト: Phase A-Fで検証済みの各スクリプト（ネスト先FoFの構造に依存）
前提: Phase A-Fで全ビルディングブロック単体は検証済み。
証明すること: FoFの中にFoFを含む再帰的計算パスが正しい。

| FoF | selection block | component構成 | 結果 | 完了日時 |
|-----|----------------|-------------|------|---------|
| MIX1 | SingleViewMomentumFilter | standard+FoF混在×8 | PASS (150mo, 149/150, 初月L485) ✅ | 2026-03-23 21:39 |
| MIX2 | SingleViewMomentumFilter | standard+FoF混在×8 | PASS (150mo, 149/150, 初月L485) ✅ | 2026-03-23 21:39 |
| MIX3 | SingleViewMomentumFilter | standard+FoF混在×8 | PASS (150mo, 149/150, 初月L485) ✅ | 2026-03-23 21:39 |
| MIX4 | SingleViewMomentumFilter | standard+FoF混在×8 | PASS (150mo, 149/150, 初月L485) ✅ | 2026-03-23 21:39 |
| 劇薬bam | none | bam-2,bam-6,DM7+ | PASS (162mo, 161/162, 初月L485) ✅ | 2026-03-23 21:39 |
| 劇薬bam_guard | none | bam-2,bam-6,DM7+,DM-safe-2 | PASS (162mo, 161/162, 初月L485) ✅ | 2026-03-23 21:39 |
| 劇薬bam_solid | none | bam-2,bam-6 | PASS (162mo, 161/162, 初月L485) ✅ | 2026-03-23 21:39 |

> **🛑 必ずここで止まれ**: Step 2全体PASS/FAIL集計を殿に報告。全ビルディングブロック+ネスト構造の検証完了。Step 3開始の承認を得よ

### Step 3: シン四神v2 作成（四神作成スクリプト）

**方法**: numpy快速パス（`pipeline_config=None`）で191,796パターンを全探索し、四神のDNAに一致するチャンピオンを選別する。
スクリプト: `shin_shijin_l1_gs.py`。4ファミリー(DM2/DM3/DM6/DM7+)×3モード(常勝/激攻/鉄壁) = 12スロット。
**前提**: Step 1でnumpy快速パスの本番パリティがPASS済みであること。

> ⚠️ PipelineEngineパスでGS探索を実行してはならない。全パターンが同一シグナルとなりパラメータ探索が無意味になる（cmd_1349で実証済み）。

| 対象 | 体数 | 結果 | 完了日時 |
|------|------|------|---------|
| シン四神v2 全12体一括 | 12体 | PASS (191,796パターン探索, 12体確定, 吸収なし。cmd_1363半蔵) ✅ | 2026-03-24 13:49 |

> **🛑 必ずここで止まれ**: シン四神v2 12体作成結果（吸収の有無含む）を殿に報告。承認後にStep 3.5へ

### Step 3.5: シン四神v2 パフォーマンス一覧作成

シン四神v2 12体のパフォーマンス一覧を作成し、殿に提示する。
スクリプト出力指標: CAGR, MaxDD, Calmar_Ratio, NHF, Max_Run-up, UD_Ratio, Skewness, Tail_Contribution, Underwater_Period, Left-tail_Jumps（10指標）。

| 対象 | 結果 | 完了日時 |
|------|------|---------|
| シン四神v2 12体パフォーマンス一覧 | PASS (10指標一覧作成+gist殿共有+殿承認。cmd_1363半蔵) ✅ | 2026-03-24 13:49 |

> **🛑 必ずここで止まれ**: パフォーマンス一覧を殿に報告。承認後にStep 4へ

### Step 4: シン忍法v2 作成 ✅ VALID（忍法スクリプト × シン四神v2）

シン四神v2 12体をコンポーネントとして、各忍法スクリプト(`run_077_*.py`)でシン忍法v2を作成する。
**吸収裁定(2026-03-24殿)**: 四つ目の常勝=激攻が同一pattern_id(yotsume_N4_0483_B12_N1_R1)。吸収優先順=激攻>常勝>鉄壁。激攻生存、常勝吸収。**最終体数: 21体→20体**。
正本: `outputs/analysis/shin_ninpo_v2_champions.csv`
忍法スクリプトごとに7 Phaseで進行。各スクリプトは`--universe`引数で四神構成YAMLを受け取り、3モード（常勝/激攻/鉄壁）を**1回の実行で一括生成**する。

#### Phase A: シン追い風（MomentumFilter）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン追い風（常勝/激攻/鉄壁）一括 | `run_077_oikaze.py` | 3体 | PASS (cmd_1366) ✅ | 2026-03-24 |

#### Phase B: シン抜き身（SingleViewMomentumFilter）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン抜き身（常勝/激攻/鉄壁）一括 | `run_077_nukimi.py` | 3体 | PASS (cmd_1367) ✅ | 2026-03-24 |

#### Phase C: シン変わり身（TrendReversalFilter）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン変わり身（常勝/激攻/鉄壁）一括 | `run_077_kawarimi.py` | 3体 | PASS (cmd_1368) ✅ | 2026-03-24 |

#### Phase D: シン加速R（MomentumAccelerationFilter ratio）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン加速R（常勝/激攻/鉄壁）一括 | `run_077_kasoku_ratio.py` | 3体 | PASS (cmd_1369) ✅ | 2026-03-24 |

#### Phase E: シン加速D（MomentumAccelerationFilter diff）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン加速D（常勝/激攻/鉄壁）一括 | `run_077_kasoku_diff.py` | 3体 | PASS (cmd_1370) ✅ | 2026-03-24 |

#### Phase F: シン分身（EqualWeight）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン分身（常勝/激攻/鉄壁）一括 | `run_077_bunshin.py` | 3体 | PASS (cmd_1371) ✅ | 2026-03-24 |

#### Phase G: シン四つ目（MultiViewMomentumFilter）

| 対象 | スクリプト | 体数 | 結果 | 完了日時 |
|------|----------|------|------|---------|
| シン四つ目（常勝/激攻/鉄壁）一括 | `run_077_yotsume.py` | 3体→2体 | PASS (cmd_1374 bugfix + cmd_1375 フルGS)。常勝=激攻同一pattern → **常勝吸収**(殿裁定: 激攻>常勝>鉄壁) ✅ | 2026-03-24 |

> 四つ目吸収結果: 激攻(yotsume_N4_0483_B12_N1_R1, CAGR=72.88%) + 鉄壁(yotsume_N4_0736_B6_N2_R1, CAGR=53.21%) = **2体**。常勝は激攻に吸収。

> **🛑 必ずここで止まれ**: シン忍法v2 **20体**作成結果を殿に報告。承認後にStep 4.5へ

### Step 4.5: シン忍法v2 パフォーマンス一覧作成 ❌ INVALID

シン忍法v2 20体（四つ目常勝吸収後）のパフォーマンス一覧を作成し、殿に提示する。
スクリプト出力指標: cagr, maxdd, calmar, sharpe, worst_year, worst_year_return, new_high_ratio, n_months（8指標）。

| 対象 | 結果 | 完了日時 |
|------|------|---------|
| シン忍法v2 20体パフォーマンス一覧（四つ目常勝吸収後） | PASS (cmd_1381疾風。gist: e7e3286a。20体×8指標CSV) ✅ | 2026-03-25 00:28 |

> **🛑 必ずここで止まれ**: ~~パフォーマンス一覧を殿に報告。承認後にStep 5へ~~ → INVALID。Step 4.5Rへ進め

---

## ⚠️ 事故記録: パフォーマンスCSV無効化 (2026-03-25)

### 経緯

cmd_1381のパフォーマンスCSVが本番と大きく乖離 → M-1オフセット欠如を疑い →
殿の指示でチャンピオン選定スクリプト(run_077_*.py)の直接確認を実施。

### 調査結果

**Step 4（チャンピオン選定）のrun_077_*.py 7本を将軍が直接コード確認。**
全スクリプトが`open_matrix[i+1]`構造でM-1オフセットを正しく実装していた。
→ **チャンピオン選定は有効。無効なのはStep 4.5のパフォーマンスCSVのみ。**

検証詳細: [deleted — `docs/research/fof_gs_m1_offset_verification.md` は削除済み。上記コード確認結果が証拠]

### Step 4.5 無効の根本原因

cmd_1381パフォーマンスCSVの問題（run_077スクリプトの出力ではなく別の計算パスで生成）:

1. **コンポーネント不整合**: 旧component PF(DM3_STMV_T2_Be_L0003等)を参照。本番FoFはシン四神v2を使用
2. **計算パスの乖離**: run_077スクリプトのGS探索パスとは異なる方法でCAGR等を算出

### 理論的根拠（3文書で土台確立）

| 文書 | 内容 |
|------|------|
| `docs/research/fof_parity_decision_tree.md` | [deleted] FoF本番vsGS月次の決定木比較(9ステップ同値性証明)。Step 2完了時の証拠として使用済み |
| `docs/research/standard_pf_parity_decision_tree.md` | [deleted] Standard PF本番vsGS numpy快速パスの決定木比較(10ステップ同値性証明)。Step 1完了時の証拠として使用済み |
| `docs/research/fof_gs_m1_offset_verification.md` | [deleted] run_077_*.py 7本のM-1オフセット直接確認記録。Step 4有効性確認時に使用済み |

### Step 4有効性の根拠（3重証拠）

1. **コード確認**: 全7本が`open_matrix[i+1]`でM-1オフセットを正しく実装（将軍直接確認 2026-03-25）
2. **Step 2パリティ**: 同じrun_077スクリプトで既存本番FoF 42体のhs+ret完全一致(Phase A-G全PASS)
3. **実データ突合**: シン加速R-常勝 140/141月一致(99.3%)、シン加速D-激攻 175/176月一致(99.4%)、不一致は全て初月L485パターン

---

### Step 4.5R: シン忍法v2 パフォーマンス一覧再作成

run_077スクリプトの出力から直接パフォーマンスCSVを生成する。cmd_1381の別計算パスは使用しない。

| # | ステップ | 結果 | 完了日時 |
|---|---------|------|---------|
| 4.5R-a | run_077スクリプト出力のper-ninja結果ファイルからパフォーマンス一覧生成(CAGR/MaxDD/Calmar等8指標×20体) | PASS ✅ `outputs/analysis/shin_ninpo_v2_20body_performance.csv` 上書き | 2026-03-25 23:40 |
| 4.5R-b | 代表3体(四つ目-激攻/加速R-激攻/追い風-激攻)のCAGRをraw grid結果と突合 → 3/3完全一致(誤差<1e-10) | PASS ✅ | 2026-03-25 23:45 |

> **🛑 必ずここで止まれ**: パフォーマンス一覧を殿に報告。承認後にStep 5へ

---

### Step 5: フォルダー確認/作成

本番DBにシン四神・シン忍法のフォルダーが存在するか確認。なければ作成。
フォルダーAPI: `api/folders.py`。
参考: cmd_269時点では全88PFが`folder_id=NULL`。現在のフォルダー状態は要確認。

| 対象 | フォルダー名 | 確認 | 結果 | 完了日時 |
|------|------------|------|------|---------|
| シン四神フォルダー | シン四神 | API GET確認→なければPOST作成 | 存在確認 ✅ (id=4917a3e8, PF数=0, cmd_1082時に作成済み) | 2026-03-24 19:20 |
| シン忍法フォルダー | シン忍法 | API GET確認→なければPOST作成 | 存在確認 ✅ (id=d41626a4, PF数=0, cmd_1082時に作成済み) | 2026-03-24 19:20 |

> **🛑 必ずここで止まれ**: フォルダー準備完了を殿に報告。承認後にStep 6へ

### Step 6: 本番DB登録（シン四神12体 + シン忍法20体）

L1(standard)を先に登録し、L2(FoF)はL1のUUIDをcomponent_portfoliosに使うため後。

> **⚠ 注記(cmd_1397教訓)**: ninpo CSV(shin_ninpo_v2_champions.csv)のsubset列は旧v1 pattern_idを参照する（12体中7体が不一致）。register時にshijin CSVのold_pattern_id列→v2 nameマッピングが必須。PI-012: MomentumAccelerationFilterのnumerator/denominator_periodにはweight: 1.0必須。

> **🛑 PI-013(Pydantic制約事前検証)**: DB INSERT前に全configを本番Pydanticモデル(`backend/app/schemas/models.py:Portfolio`)でバリデーションせよ。制約: `top_n: 1-2`, `months: 0-36`, `days: ≤756`, `weight: 0-1`, `rebalance_trigger: 有効値セット`, `benchmark_ticker: 非空/非DTB3/非CASH`, FoF: `component_portfolios ≥2 + pipeline_config + terminal_block`。**分身のtop_n=4事故(2026-03-26)**: selection_blocks空のFoFでもPydanticはtop_nを検証する。top_n=component数は誤り、top_n=1が正。

| 対象 | 体数 | 確認 | 結果 | 完了日時 |
|------|------|------|------|---------|
| L1 シン四神12体 登録 | 12体 | cmd_1397で登録済み。将軍が直接DB検証→Step 3 GSチャンピオン全12体完全一致 | PASS ✅ (本物確認済み) | 2026-03-25 |
| L1 登録確認 | — | DB直接確認: 12体存在+シン四神フォルダー(4917a3e8)内 | PASS ✅ | 2026-03-26 |
| L2 シン忍法20体 登録 | 20体 | cmd_1397の登録は偽物(旧チャンピオン)→将軍がDELETE(88,622件)+正しいStep 4データで再登録 | PASS ✅ (再登録完了) | 2026-03-26 |
| L2 登録確認 | — | DB直接確認: 20体存在+component_portfolios/selection_pipeline全件正+フォルダー内 | PASS ✅ | 2026-03-26 |
| フォルダー所属確認 | 32体 | DB直接確認: シン四神12体(4917a3e8)+シン忍法20体(d41626a4) = 32体 | PASS ✅ | 2026-03-26 |

> **🛑 必ずここで止まれ**: 32体登録結果を殿に報告。Step 7は殿が実行する

### Step 7: full recalculate（殿が実行）

殿が本番環境でfull recalculate(PI-005: portfolio_id指定なし一発)を実行する。**将軍・家老・忍者は手を出すな。殿の完了報告を待て。**

| 対象 | 実行者 | 結果 | 完了日時 |
|------|--------|------|---------|
| full recalculate (1回目) | 殿 | Pydanticエラー(シン分身top_n=4, PI-013違反)で20体データ生成失敗 ❌ | 2026-03-26 00:35 |
| PI-013修正 | 将軍 | シン分身3体 top_n=4→1 修正 + PI-013本番不変量登録 ✅ | 2026-03-26 01:15 |
| full recalculate (2回目) | 殿 | 全20体MR生成完了 ✅ | 2026-03-26 01:20 |

> **🛑 殿の完了報告があるまで絶対に次に進むな**

### Step 8: 最終パリティ検証（33体 × スクリプト突合）

Step 1・Step 2と同じ方法で、recalculate後の本番DB計算結果とスクリプト出力を突合する。

#### 8a: シン四神12体（standard PF）パリティ

Step 1と同一手法。holding_signal完全一致 + monthly_return完全一致。

| 対象 | 体数 | 結果 | 完了日時 |
|------|------|------|---------|
| シン四神v2 12体 | 12体 | PASS ✅ 12/12 hs+ret完全一致 (65/65全体PASSの一部) | 2026-03-26 |

#### 8b: シン忍法20体（FoF）パリティ

Step 4R-cと同一手法: スクリプト出力 vs 本番DB直接突合(hs+ret完全一致)。
**注意**: `verify_fof_parity_batch.py`は内部整合性チェックのみ(GS-vs-本番パリティではない)。必ずスクリプト出力と本番DBの月次直接比較で検証せよ。

| 対象 | 体数 | 結果 | 完了日時 |
|------|------|------|---------|
| シン忍法v2 20体 | 20体 | PASS ✅ 17/20完全一致 + 3/20(分身)L485パターン(初月NULL=既知許容。hs=174/175,ret差3e-6) | 2026-03-26 |

> **🛑 必ずここで止まれ**: 最終パリティ結果（33体PASS/FAIL）を殿に報告。承認後にStep 9へ

### Step 9: 劣化指標バッチ再計算

`POST /admin/deterioration-batch`（1回のAPIコール）で全active PFのG1/G2/P(det)/p̄を一括再計算する。
実態: `run_deterioration_batch()`（P(det)+G1+G2→`deterioration_snapshots`テーブル）+ `run_p_average_batch()`（p̄→`p_average_results`テーブル）が順次実行される。
Render cron（毎月1日 03:00 UTC）でも自動実行されるが、登録直後は手動トリガーが必要。

| 対象 | 方法 | 結果 | 完了日時 |
|------|------|------|---------|
| 全active PF（新規32体含む）劣化指標一括計算 | `POST /admin/deterioration-batch` | PASS ✅ 123PF処理(skip=0)。PK修正(portfolio_id→portfolio_id+n_splits)後に成功 | 2026-03-26T01:35 |
| 結果確認: 32体全てにP(det)/G1/G2/p̄が算出されていること | DB直接確認 | PASS ✅ 32/32全てにP(det)3窓+G1+G2+p̄算出済み。label分布: GOOD6/MIXED14/EARLY_WARNING3/DETERIORATING9 | 2026-03-26T01:36 |

> **🛑 必ずここで止まれ**: 新規32体のG1/G2/P(det)/p̄結果を殿に報告。全工程完了

## ルール

1. **上から順に進む。飛ばさない**
2. **各ステップのPASS/FAILと完了日時を記録してから次へ**
3. **FAILしたら止まる。原因を特定してから再開**
4. **並列化は同一ステップ内のみ**
5. **清掃(0)が完了する前に土台(1-)に進むな**
6. **土台(1-5)が完了する前に登録(6-)に進むな**
7. **新しい種類に進む前に、同じ種類の既存本番で検証せよ**（恐怖の代替: 「本当に動くのか？」を既存で証明してから新規に進む）
8. **本番DBがground truth。ドキュメントは二次情報**
9. **🛑マークで必ず止まれ。殿の承認なしに次へ進むな**
10. **Standard PFパリティの理論根拠**: [deleted — `docs/research/standard_pf_parity_decision_tree.md`]。GS numpy快速パス = 本番PipelineEngine(MomentumFilter+EqualWeight条件下、10ステップ同値性証明)。Step 1で実証済み
11. **FoFパリティの理論根拠**: [deleted — `docs/research/fof_parity_decision_tree.md`]。GS月次計算はM-1オフセット適用で本番同値(monthly+EqualWeight条件下)。Step 2で実証済み
12. **verify_fof_parity_batch.pyは内部整合性チェックのみ**。GS-vs-本番パリティの証明にはスクリプト出力と本番DBの直接月次突合が必須
