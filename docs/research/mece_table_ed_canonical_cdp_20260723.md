# MECE表体裁 E/D軸 canonical + 逸脱（本番CDP getComputedStyle実測 2026-07-23）

測定: `scripts/cdp/cdp_ed_probe.py`（本番CDP 9222・viewer認証済）。grepでなく計算済みスタイル一次。
基準確定=殿裁定「annual-returns/monthly-returnsは同じスタイルで気持ちがいい」→この2ページをcanonicalとする。

## canonical（annual-returns / monthly-returns — 2ページ完全一致）
- **E軸 padding**: `12px 8px 12px 8px`（縦12・横8、thead/tbody同一）
- **E軸 stripe**: 無し（全行 `rgba(0,0,0,0)` 透明）
- **E軸 border**: セル境界線 `0px`（thead/tbody とも）
- **D軸 card**: **無し**（表を包む枠付きcardが `null`）

## 逸脱（canonical突合・CDP実測）
| page | td_pad | card | 逸脱軸 |
|------|--------|------|--------|
| annual-returns / monthly-returns | `12px 8px` | null | **基準** |
| rolling-returns（表7個） | `8px 12px`/`8px 8px`/`12px 12px`（**ページ内で不統一**） | border 0.67px rgba(15,23,42,.1)・**radius 16px**・shadow有 | **D軸card有＋E軸padding不統一** |
| deterioration | `12px 12px` | border 0.67px rgb(229,231,235)・**radius 0px**・shadow none | **D軸card有(角丸0)＋E軸padding横12** |
| monthly-trade | `12px 16px` | null | **E軸padding横16** |

## 逸脱の構造（殿の「体裁がバラバラ」の正体）
1. **D軸 card 3種バラバラ**: canonical=card無し / rolling=角丸16px+shadow / deterioration=角丸0px。→ 表を「カードで囲む/囲まない」「角丸16/0」が統一されていない。
2. **E軸 padding 全ページ相違**: canonical=`12px 8px` / rolling=内部でも`8px12`〜`12px12`と混在 / deterioration=`12px 12px` / monthly-trade=`12px 16px`。横paddingが8/12/16と割れている。

## 統一方針（canonicalへ寄せる）
- 全表 padding → `12px 8px`（canonical）
- stripe 無し・セル境界 `0px` 維持
- **card政策は殿裁定要**: (A)canonical準拠でcard無しに統一 / (B)card有りに統一するなら角丸・border・shadowを1種へ固定（rolling系の radius16px+shadow か）。annual/monthlyがcard無しで「気持ちいい」ため既定は(A)。

## 訂正: 架空ルートの誤り（想像で作ったルート名・検証不足）
初回に `risk-management`/`model-trades`/`mtd-daily`/`up-down-market` が `[]` だったのは**これらが実在しないルート**だったため（将軍が想像でルート名を作った）。Next.js `app/*/page.tsx` の権威ある実ルートは全21件で、下の全ルートcard MECEマップで**全数CDP実測済**。

測定JSON: scratchpad/ed_rest.json + cdp_ed_probe.py 実行ログ。ツール=`scripts/cdp/cdp_ed_probe.py`（cdp_font_probe.pyのE/D版）。

## 全21ルート card MECEマップ（CDP実測 2026-07-23・全数・admin含む・cdp_card_probe.py）
「カード」= 可視border or shadow かつ 角丸>0 の最外側視覚コンテナ。

| route | card数 | radii | table内包数 |
|---|---|---|---|
| / | 1 | ['16px'] | 0 |
| /admin | 13 | ['16px', '8px'] | 0 |
| /admin/fof | 78 | ['16px'] | 78 |
| /admin/folders | 2 | ['16px'] | 0 |
| /admin/visibility | 3 | ['12px', '16px'] | 1 |
| /annual-returns | 1 | ['8px'] | 0 |
| /compare | 2 | ['8px'] | 0 |
| /compare-returns | 0 | — | 0 |
| /compare-summary | 0 | — | 0 |
| /dashboard | 1 | ['8px'] | 0 |
| /deterioration | 0 | — | 0 |
| /docs | 4 | ['16px'] | 0 |
| /drawdowns | 4 | ['16px', '8px'] | 2 |
| /faq | 10 | ['16px'] | 0 |
| /metrics | 2 | ['12px', '8px'] | 0 |
| /monthly-returns | 1 | ['8px'] | 0 |
| /monthly-trade | 1 | ['8px'] | 0 |
| /offline | 1 | ['16px'] | 0 |
| /rolling-returns | 4 | ['16px', '8px'] | 2 |
| /summary | 1 | ['8px'] | 0 |
| /trades | 1 | ['16px'] | 0 |
### card radius 逸脱の構造（D軸バラバラの正体）
- **8px**: annual-returns/monthly-returns/monthly-trade/summary/dashboard/compare
- **16px**: /(root)/docs/faq/offline/trades/admin/fof/admin/folders
- **12px**: metrics/admin/visibility
- **card無し**: compare-returns/compare-summary/deterioration
- 混在ページ(8+16): rolling-returns/drawdowns/admin
→ 同一アプリ内でcard角丸が 8/12/16/無し の4系統。統一の主対象。

## A案（canonical準拠=card撤去）で直すべき逸脱リスト（全表ページCDP実測 2026-07-23）
canonical = padding `12px 8px` / stripe無 / セル境界`0px` / **card無し**。以下❌が要修正。
| route | 表 | 逸脱内容 | 修正 |
|---|---|---|---|
| annual-returns / monthly-returns | t0 | ✅canonical | 不要（基準） |
| rolling-returns | t0-t5(6表) | padding不統一(8px12/8px8/12px12)+**card r16px** | padding→12px8px + card撤去 |
| deterioration | t0 | padding 12px12 + **card r0px(border)** | padding→12px8px + card枠撤去 |
| monthly-trade | t0 | padding 12px16(横16) | padding→12px8px |
| drawdowns | t0,t1 | padding 8px12 + **card r16px** | padding→12px8px + card撤去 |
| metrics | t0 | padding 8px **1px**(右1px異常) | padding→12px8px |
| metrics | t1 | padding 8px12 + **card r0px** | padding→12px8px + card枠撤去 |
| compare-returns | t0(104行) | padding 12px12 + **stripe有** | padding→12px8px + stripe撤去 |
| compare-summary | t0(104行) | padding 12px12 + **stripe有** | padding→12px8px + stripe撤去 |
| summary | t0 | padding 8px **1px** | padding→12px8px |
| dashboard | t0 | padding 8px12 + **stripe有** | padding→12px8px + stripe撤去 |

### 修正軸の集計
- **padding→12px8px**: 全11表(annual/monthly以外の全逸脱表)
- **card撤去**: rolling-returns(6)/drawdowns(2)/deterioration/metrics t1 = 計10表
- **stripe撤去**: compare-returns/compare-summary/dashboard = 3表
- 特異: metrics t0 / summary t0 の右padding=1px(コード上の異常値、要現物確認)
- 未含(admin系): /admin/fof(78表)・/admin/visibility(1表)は管理画面。統一対象に含めるか殿裁定要

---

# 【最終確定仕様】MECE表体裁統一（殿裁定2026-07-23・本番CDP実測・二層モデル）

## 設計原則: 一律でなく二層（狭tier/広tier）
表示最大化・横スクロール最小化を主題とし、列数に応じ機構を分ける（縦スクロールは許容）。

## 狭tier（列少・画面に収まる） canonical
- **max-width cap = 1100px**（狭tierの列間の間延びを抑えつつ横スクロールを発生させない）
- **中央寄せ**（左右均等マージン。dashboard式。左寄せは不可）
- padding = **12px 8px**（縦12/横8）
- **card無し**（枠で囲まない）
- **stripe無し**（行の交互背景色なし）
- col1/ヘッダ sticky = **不要**（横スクロールしないので効かない）

## 広tier（列多・画面幅で伸びる/full展開で横スクロール） canonical
- 幅 = 画面に応じ可変（cap無し）
- **ヘッダ行 sticky**（`position:sticky; top:0`）= 縦スクロールで見出し固定
- **1列目 sticky**（`position:sticky; left:0`）= 横スクロールで行ラベル固定
- 左上角セル = 両方向固定
- 基準完備 = compare-summary

## Tier確定＆修正リスト（本番CDP実測）
### 広tier
| 表 | 現状 | 修正 |
|---|---|---|
| compare-summary(18列,伸びる) | sticky完備✓ | stripe撤去 |
| deterioration(14列,伸びる) | sticky無✗ | **ヘッダ+col1 sticky追加** |
| monthly-trade **full表示**(1088→1352,横スクロール) | sticky無✗ | **ヘッダ+col1 sticky追加**（normalは狭tier） |

### 狭tier（cap→1100・padding12/8・card無・stripe無・中央寄せ）
| 表 | 修正 |
|---|---|
| annual-returns/monthly-returns | cap 1088→1100のみ（他は基準・中央✓） |
| rolling-returns | card撤去＋padding統一(ページ内8/12・8/8・12/12混在)＋cap→1100 |
| drawdowns | card撤去＋padding統一＋cap→1100 |
| monthly-trade(normal) | padding(12/16)統一＋cap→1100 |
| metrics | padding異常(右1px)修正＋t1 card撤去＋cap→1100 |
| summary | padding異常(右1px)修正＋cap→1100 |
| dashboard | stripe撤去＋padding統一＋col1 sticky撤去(狭tier不要) |
| **compare-returns** | **中央寄せ化**(現240/1208左寄せ)＋stripe撤去＋padding統一＋cap→1100＋col1 sticky撤去＋内側縦スクロール廃止＋全行展開 |

## 実装前確認
- trades: 表未検出(`[]`)→route/描画確認
- 「All/Show All」= 行展開(縦・幅不変・実測確認済)→ tier対象外

## 測定ツール(全て本番CDP getComputedStyle・grep不使用)
- scripts/cdp/cdp_ed_probe.py(E軸境界/stripe/padding + D軸card)
- scripts/cdp/cdp_card_probe.py(全カード列挙)
- scripts/cdp/cdp_maxdisplay_probe.py(幅利用/横スクロール)
- ★測定は必ず**実表示幅(2560×1600)＋全モード(normal/full)**で。1036px狭窓・normalのみは誤り(将軍反省)
