# 表フォント14px統一 — CDP計算済みスタイル実測による逸脱全数カバレッジ

殿裁定2026-07-23 10:15「一回14pxに統一しよう」。canonical確定 → 逸脱を本番CDP `getComputedStyle` で全数実測。

## canonical（正・殿裁定）

| 役割 | font-size | font-family | weight |
|---|---|---|---|
| 本体・数値 | **14px** | **ui-monospace** (tabular-nums) | 400 |
| 本体・文字(ラベル) | **14px** | Inter | 400-500 |
| ヘッダ | **14px** | Inter | 600-700 |

- 数値と文字は本体で同一14px（殿確認済み: サイズ差は数値/文字ではなくヘッダ由来だった）
- サイズは全役割14pxへ統一（ヘッダの12px列見出しも14pxへ）

## 逸脱全数（本番CDP実測 2026-07-23、全21ページ走査、データ表を持つ13表対象）

計測基盤: powershell Start-Process + `--remote-allow-origins=*` + 隔離profile + viewer premium token(localStorage `dm_viewer_token`注入) + `getComputedStyle`。ソースgrepは描画と不一致(text-base→14px上書き実証)のため使用不可。

| # | route | table | 逸脱内容 | canonical化 |
|---|---|---|---|---|
| 1 | /rolling-returns | t0(65c) | データ数値48セルが等幅漏れ(`text-right text-foreground`にfont-mono無し、実値"+3.63%"等) | font-mono tabular-nums付与 |
| 2 | /monthly-trade | t0 | データ数値26セルが等幅漏れ | font-mono tabular-nums付与 |
| 3 | /metrics | t1(40c) | データ数値28セルが等幅漏れ | font-mono tabular-nums付与 |
| 4 | /annual-returns | t0 | ①データ数値11セル等幅漏れ ②ヘッダ列見出し9セルが12px(`text-xs`) | ①mono付与 ②text-xs→text-sm(14px) |
| 5 | /monthly-returns | t0 | ①データ数値12セル等幅漏れ ②ヘッダ列見出し9セルが12px | ①mono付与 ②text-xs→text-sm |
| 6 | /deterioration | t0 | ①カテゴリ小ラベル8セルが12px(`text-xs text-muted`, "standard/fof/benchmark") ②方向矢印8セルが18px(`text-lg`, "↘↓→"色付き) | ①text-xs→text-sm ②【要判断】矢印はアイコン役割 |

## 判断が必要な1点: deterioration の方向矢印

- 18px `text-lg text-orange/red/gray` の "↘ ↓ →" はトレンド方向を示す**色付きアイコン**。数値でも通常文字でもない。
- 機械的に14px化するとトレンド表示の視認性が落ちる。
- 選択肢: (A)殿裁定「14px統一」を字義適用し矢印も14px化 (B)矢印はicon役割として統一対象外(cmd_4119のmuted caption除外と同型)。
- 実装cmdでは(B)を既定とし、殿/家老が(A)を選べるようフラグ化。

## 逸脱していない表（canonical準拠・変更不要）

/summary, /metrics t0, /drawdowns(2表), /compare-returns, /compare-summary, /risk-management, /dashboard, /trades — いずれも本体14px・数値mono・文字Inter。

## 検証（完了条件）

修正push→本番デプロイ後、将軍が同一CDP実測を再実行し、上記6表の逸脱が0件になることを `getComputedStyle` で証明する。ソースgrepでの確認は不可(描画と不一致のため)。

origin: `[[殿指摘_表によってフォント違う_20260723]] -> [[将軍CDP getComputedStyle全数実測]] -> [[逸脱6表確定]] -> [[殿裁定_14px統一_20260723]]`
