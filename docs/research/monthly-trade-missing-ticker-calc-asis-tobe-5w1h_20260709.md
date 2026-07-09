# Monthly Trade検証用リターン計算 — ticker欠落時の計算続行禁止 設計書 AsIs/ToBe 5W1H

- 作成: 将軍 2026-07-09 13:45（殿指示 13:40）
- 対象: DM-Signal `backend/app/services/monthly_trade_impl.py::_calculate_return_from_price_movement()`
- version: v1.0

## §0 発端 — 殿の言葉（2026-07-09）

> マッチした3/4分だけでリターンを計算したら結果がめちゃくちゃにならないか？(13:37)
> 先にasis/tobeで設計書を作るべきだ。そもそもtickerが欠落していたら計算してはいけないはずだ。フォールバックや計算続行はサイレントな汚染データを生む。(13:40)

文脈: cmd_3786ロールバック中の本番ログ確認で `WARNING:app.services.monthly_trade_impl:Matched weight 0.7500 < 0.99, some tickers may be missing` を発見。将軍が現物確認し、コードが未正規化のまま部分加重和を返していることを確認した。

## §1 原理 — 部分データでの計算続行はサイレント汚染

**欠落を検知したら計算をやめよ。検知して続行するのは検知していないのと同じ。** ログを出すだけの「WARNING」は人間が偶然見つけない限り機能しない。既存のSilent Fallback原則(PI-018)と同型: 「不完全なデータで見た目のもっともらしい値を返す」ことが害そのもの。ログレベルの警告は防御ではない。

## §2 AsIs — 現状の実装（全てfile:line現物確認、2026-07-09）

| # | 項目 | 現状 | 現物 |
|---|------|------|------|
| A1 | 計算ロジック | `weights`(ticker→weight)と`price_movement`(ticker別騰落率)を突合し、マッチしたtickerのみ`change_pct * weight`を積算。**マッチしなかった分のweightは無視され、`total_return`は正規化されない** | `monthly_trade_impl.py:1092-1108` |
| A2 | 欠落時の挙動 | `matched_weight < 0.99`なら`logger.warning()`のみ。**計算は継続し、歪んだ`total_return`をそのまま返す** | `monthly_trade_impl.py:1112-1116` |
| A3 | 数学的帰結 | 欠落ticker分の寄与は実質「リターン0%」として扱われるのと同値。正しい部分加重平均(`total_return / matched_weight`)にすらなっていない。プラス月・マイナス月とも絶対値が真値より小さく歪む | 殿検分+将軍検算(2026-07-09 13:40) |
| A4 | 呼び出し元 | `_build_entries()`が`calculated_return_open`/`calculated_return_close`/`matched_weight`をentryへ格納 | `monthly_trade_impl.py:560-568` |
| A5 | API露出 | `MonthlyTradeEntry`スキーマの3フィールドとして返却されるのみ。バックエンド側でこの値を他の値(monthly_return等)と突合・アサートする消費者は存在しない(grep 0件) | `api/monthly_trade.py:179-181,315` |
| A6 | FE非使用 | FEは明示コメント付きで**この値を表示に使わない**。表示に使うのは`monthly_returns`テーブル由来の`monthly_return`(SSOT) | `frontend/components/monthly-trade-table.tsx:493-494` |
| A7 | 既存テスト | 部分マッチ(matched_weight=0.8)のケースで`matched_weight`値のみ検証し、**その時の`total_return`が正しい値かはアサートしていない**=現行の歪んだ挙動を「正」として固定していない | `tests/test_monthly_trade_calculator.py:1459-1466` |
| A8 | 既存防御網の欠落 | Silent Fallback監査(gunshi-silent-fallback-analysis.md, PI-018)にこの箇所は含まれていない(grep 0件)。既知のSF-001〜カタログの対象外=未発見の新規インスタンス | `context/gunshi-silent-fallback-analysis.md` |

**結論: この値は現状「検証用」として計算されているが、誰にも検証されず、誰にも表示されず、ただ歪んだ値がAPIレスポンスに乗っているだけの死んだデータ経路。** 実害は現時点でFE表示には及んでいないが、コード自体がSilent Fallbackの教科書的パターンであり、将来この値が(監視・アラート・別機能で)参照された瞬間に汚染データとして機能する。

## §3 なぜなぜ — なぜ計算続行が許されたか

1. なぜ欠落時に計算を止めないか → 「054: 照合ロジック付きのリターン計算」という追加機能が、正常系のみを想定して実装され、異常系(欠落)はログ警告で「済ませた」
2. なぜログ警告で済んだか → 呼び出し元も消費者も、この値の正しさを検証する仕組みがなく、警告が出ても誰も見ない構造だった(A5)
3. なぜ発見が遅れたか → FEが表示に使わない「検証用」の値だったため、ユーザー影響がなく、実害が顕在化しなかった
4. 根因 → 「異常時は警告して続行」という個別実装判断が、この箇所ではSilent Fallback原則(欠落=計算停止)の適用漏れとして埋め込まれた。個別のコードレビュー時にPI-018の観点が当たっていなかった

## §4 AsIs/ToBe 5W1H対比

| 軸 | AsIs | ToBe |
|----|------|------|
| WHO | `_calculate_return_from_price_movement()`が単独で判断 | 同関数だが判定基準を変更 |
| WHAT | 欠落があっても部分加重和を返す(歪んだ値) | **欠落が1件でもあれば`None`を返す(計算しない)**。欠落ticker一覧を別フィールドで返す |
| WHEN | 事後(ログ出力のみ、検知後も継続) | 事前(欠落検知した時点で即座に計算を打ち切る) |
| WHERE | ログにWARNINGとして埋没 | API応答の`calculated_return_open/close=None`として明示。欠落ticker情報を新フィールドで可視化 |
| WHY | 「参考値でも出しておけば有用」という暗黙の判断 | **不完全な計算結果は無効な結果より害が大きい**。Noneは「わからない」を正しく表現する |
| HOW | weight正規化なしの部分和+WARNINGログ | 完全一致(`matched_weight == 1.0`、浮動小数点許容誤差内)でなければ`None`+欠落ticker一覧を返す |

## §5 ToBe設計

### R1: 判定基準の変更(fail-closed化)

```python
# 現状(AsIs)
if matched_weight < 0.99:
    logger.warning(f"Matched weight {matched_weight:.4f} < 0.99, some tickers may be missing")
return round(total_return, 6), matched_weight

# ToBe
missing_tickers = [t for t in weights if t not in pm_by_ticker]
if missing_tickers or abs(matched_weight - 1.0) > 1e-6:
    logger.warning(
        f"Calculation aborted: matched_weight={matched_weight:.4f}, "
        f"missing_tickers={missing_tickers}"
    )
    return None, matched_weight, missing_tickers
return round(total_return, 6), matched_weight, missing_tickers  # missing_tickers=[]
```

- 戻り値を`(calculated_return, matched_weight, missing_tickers)`のtupleへ拡張(既存の2要素タプルから変更。呼び出し元1箇所のみ=`_build_entries()` L560-568、影響範囲は限定的)
- 完全一致でなければ`calculated_return`は必ず`None`。部分計算値は一切生成しない

### R2: API/FEへの可視化

- `MonthlyTradeEntry`スキーマに`missing_tickers: list[str] | None`を追加(`api/monthly_trade.py`)
- FEは現状これらの値を表示に使っていないため、当面はAPI応答のみで足りる。将来この値を監視・診断UIで使う際に、欠落原因が一目でわかる

### R3: 既存テストの更新

- `tests/test_monthly_trade_calculator.py:1459-1466`(部分マッチ0.8のケース)の期待値を更新: `result is None`を検証するよう修正
- `tests/test_monthly_trade_calculator.py:1636-1643`(calculated_return_open/close存在確認)は完全マッチケースのため影響なし。ただし戻り値tuple拡張に伴うシグネチャ変更で全呼び出し箇所の更新が必要

### R4: Silent Fallback監査カタログへの追加

- `context/gunshi-silent-fallback-analysis.md`へ本件を新規インスタンスとして追加記録(既存SF-001〜との重複ではなく新規発見である旨を明記)
- `scripts/gates/gate_silent_fallback.sh`の検出対象パターンに、この種の「閾値未満で警告のみ+計算続行」パターンを加えられないか、既存gate実装を確認の上検討(R4は道具改修を伴うため別cmd候補)

## §6 計測計画

| 指標 | baseline(AsIs) | target(ToBe) |
|------|----------------|---------------|
| 欠落時のcalculated_return | 歪んだ数値(部分加重和、非正規化) | `None`(欠落ticker一覧付き) |
| 欠落検知の可視性 | ログWARNINGのみ(埋没) | API応答の`missing_tickers`フィールドで構造化 |
| Silent Fallbackカタログ登録数 | 0(本箇所未収載) | 1件追加 |
| 既存テストPASS率 | 変更後に部分マッチテストが現行動作を前提にFAILする想定 | 期待値更新後に全PASS |

## §7 実装cmd分割案

| cmd | 内容 | 規模 |
|-----|------|------|
| 単一cmd | R1(fail-closed化)+R2(API/FEスキーマ追加)+R3(既存テスト更新)+R4(Silent Fallbackカタログ追記) | 小(影響1関数+1呼び出し元+1スキーマ+1テストファイル) |

R4のgate改修(検出パターン追加)は道具磨きの別cmdとし、本cmdはコード修正+テスト+カタログ記録に留める。

## §8 スコープ外(明示)

- `monthly_returns`テーブル生成パイプライン(`recalculate_fast.py`/`generators/monthly_returns.py`)の計算ロジック変更 — 本件は別系統(SSOT値は無傷)
- FEの表示変更(現状表示に使っていないため不要)
- 他のSilent Fallback既知インスタンス(SF-001〜)の修正 — 別cmdで対応済み/対応中
- cmd_3786ロールバックの本線作業 — 独立した並行課題

## 因果リンク

- ← [[殿指摘20260709_1337_matched_weight]] 「3/4分でリターン計算したら結果がめちゃくちゃにならないか」
- ← [[殿裁定20260709_1340_設計書優先]] 「フォールバックや計算続行はサイレントな汚染データを生む」
- → [[silent_fallback_quality]] PI-018原則の新規インスタンス
- → [[gunshi-silent-fallback-analysis]] カタログへの追加対象
