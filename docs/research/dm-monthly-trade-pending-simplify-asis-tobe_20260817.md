<!-- gist-master: c85b0caec523248632370c948f826efa dm-monthly-trade-pending-simplify-asis-tobe_20260817.md -->
# Monthly Trade 確定/未確定表示の簡素化 AsIs/ToBe — 過去月バッジ廃止・NEXT SIGNALゾーン撤去・当月のみ「価格が揃うまで未確定」

## 原則（親文書と同じ。殿裁定 2026-08-15 / 2026-08-17 01:42）

- ToBeは構造的に不可能でない限り妥協しない。AsIsは現実のコードそのもの。変更履歴は書かない（見出し=版+タイムスタンプ、粒度は末尾注釈）。
- 裁定は「事実→制約→判断→効果」の因果で記す（殿原則 2026-08-17 01:42）。
- 実装は殿の指示まで行わない（2026-08-17 02:06 殿「今はチャットだ」／02:12「設計書に一旦落としてくれ」）。

発端: 殿観測 2026-08-17 02:06 — 本番Monthly Trade画面で**全PF・全期間にPendingバッジ**が出ている（スクショ: `劇薬DMスムーズ` as of 2026-08-14、May〜Aug 2026 全行Pending、上部にNEXT SIGNAL Sep 2026 / 08/14 Preview）。
関連設計書: `dm-login-boundary-asis-tobe_20260817.md`（gist 0d23e0c3。entitlement=position_month基準がNEXT SIGNAL撤去の根拠の一つ）

## AsIs **v1.0** — 2026-08-17 02:15+09:00（三層記憶+本番DB一次確認。コード行番号はcontext記載時点のもの、実装前に現物再確認）

### AsIs 表示仕様（現物）

| 部位 | 現物 | 判定ロジック | 導入cmd |
|---|---|---|---|
| Positionセル内バッジ | `frontend/components/monthly-trade-table.tsx` / API型 `decision_source`,`decided_at`,`is_correction` | `signal_decision_ledger`優先。ledger行あり=✓Confirmed / 訂正=Corrected / **ledger行なし=⏳Pending** | cmd_3706 / 99edb79b |
| Historicalバッジ | `backend/app/services/signal_decision_ledger.py`, `monthly_trade_impl.py` | ledger最古`effective_start_date`より前の月=✓Historical（暗黙確定） | cmd_3710 / f4f17af9 |
| NEXT SIGNALゾーン | 表上部の黄色帯「NEXT SIGNAL / Sep 2026 / 08/14 Preview / GLD 50% XLU 50%」 | 日次スナップショットの来月候補。「日々変動が正常な未確定値」として本表から隔離表示 | cmd_3706 |
| 当月MTD行 | 先頭行 `Aug 2026 [MTD] 08/03 … 2026/08/03 open → 2026/08/16 open` | リバランス有無によらず当月canonical `holding_signal`を先頭表示 | cmd_4246系(frontend 07b13601 / backend a1111735) |
| ledgerデータ | `signal_decision_ledger` | cmd_3711(07-06)で2003〜2026を`historical_backfill`(15,160行)。以後日次confirm処理で追加 | cmd_3711 / 4b9fae64 |
| 無音書換え警報 | L809: pending/確定境界は日付ではなく出自(marker)で判定 | ledgerの出自を参照 | cmd_3679 |

### AsIs 本番一次データ（2026-08-17 02:08 JST・db-check readonly）

```
SELECT count(*),min(effective_start_date),max(effective_start_date),count(distinct portfolio_id) FROM signal_decision_ledger;
→ (0, None, None, 0)
```

**全期間Pendingの真因**: 08-16復旧でDBを新instance(PITR `dpg-da0qttc9v7es73a0cig0-a`)へ切替+復帰点fullを実行したが、ledgerはfullが生成するものではなく **cmd_3711バックフィル+日次confirm** の産物。復元後にバックフィル未実行→ledger 0行→全月「行なし=Pending」。Historical判定も最古日Noneで効かない。**表示ロジックは仕様通り動いており、データ欠落が原因。**

### AsIs ワイヤーフレーム（現物スクショ 2026-08-14 as of の再現）

```
┌─────────────────────────────────────────────────────────────────────┐
│ Monthly Trade  [OPEN]                                          🏠   │
│ as of 2026-08-14 (00:09 JST)                                        │
│ ‹ [ 劇薬DMスムーズ ▾ ] ›                                            │
│                                                                     │
│ Monthly Trade History  FoF (173 months)     View: [Simple] Full  Show All │
│ ┌───────────────────────────────────────────────────────────────┐   │
│ │ NEXT SIGNAL                                    GLD 50%  XLU 50% │ ← 撤去対象
│ │ Sep 2026 / 08/14  Preview                                       │   │
│ └───────────────────────────────────────────────────────────────┘   │
│ Month     PosStart Position          Return Period        Return Cum. Price Movement │
│ Aug 2026  08/03    GLD(50%)/XLU(50%) 08/03 open→08/16 open +4.07% …  GLD: … XLU: … │
│  [MTD]             [⏳ Pending]                                       │ ← 当月: 残す(文言変更)
│ Jul 2026  07/01    GLD/XLU/TECL/GDX/QLD 07/01→08/03      -7.85% …                │
│                    [⏳ Pending]                                       │ ← 過去月: 廃止
│ Jun 2026  06/01    TECL/XLU/GDX/QLD   06/01→07/01        -7.46% …                │
│                    [⏳ Pending]                                       │ ← 過去月: 廃止
│ May 2026  05/01    TECL/XLU/GLD       05/01→06/01       +13.18% …                │
│                    [⏳ Pending]                                       │ ← 過去月: 廃止
└─────────────────────────────────────────────────────────────────────┘
```

## ToBe **v0.1** — 2026-08-17 02:15+09:00

### ToBe 表示仕様

| 部位 | ToBe | 判定 |
|---|---|---|
| NEXT SIGNALゾーン | **撤去**。来月候補は本表に出さない | — |
| 過去月バッジ | **なし**（Confirmed/Corrected/Historical/Pending 全て非表示）。過去月は常に確定という原理に一致 | — |
| 当月行 | `[MTD]` + 1バッジ「**価格が揃うまで未確定**」(仮文言。英表記案 `Unconfirmed until prices settle`)。当月の月初営業日価格が揃った時点でバッジ消灯 | 当月かつ position start の価格確定前 = 表示 / それ以外 = 非表示 |
| ledger | 表示から**切り離す**。L809無音書換え警報の出自判定用にのみ裏で維持。0行状態は表示に影響しなくなる | — |
| API型 | `decision_source`/`decided_at`/`is_correction` は当面残置(消費者=バッジのみなら次段で削除候補) | — |

### ToBe ワイヤーフレーム

```
┌─────────────────────────────────────────────────────────────────────┐
│ Monthly Trade  [OPEN]                                          🏠   │
│ as of 2026-08-14 (00:09 JST)                                        │
│ ‹ [ 劇薬DMスムーズ ▾ ] ›                                            │
│                                                                     │
│ Monthly Trade History  FoF (173 months)     View: [Simple] Full  Show All │
│                                                                     │  ← NEXT SIGNAL帯なし
│ Month     PosStart Position          Return Period        Return Cum. Price Movement │
│ Aug 2026  08/03    GLD(50%)/XLU(50%) 08/03 open→08/16 open +4.07% …  GLD: … XLU: … │
│  [MTD]             [⏳ 価格が揃うまで未確定]                          │ ← 当月のみ
│ Jul 2026  07/01    GLD/XLU/TECL/GDX/QLD 07/01→08/03      -7.85% …                │
│ Jun 2026  06/01    TECL/XLU/GDX/QLD   06/01→07/01        -7.46% …                │
│ May 2026  05/01    TECL/XLU/GLD       05/01→06/01       +13.18% …                │
└─────────────────────────────────────────────────────────────────────┘
```

### 未決（殿裁定待ち）
1. 当月バッジ文言（日本語/英語・「価格が揃うまで未確定」の最終表記）。
2. ledgerバックフィル(cmd_3711相当)を復元後に再実行するか。表示から切れば実害は消えるが、L809警報系がledger依存なら必要。→ 依存関係を偵察してから。
3. 本設計をログイン境界「第0段」の前に置くか後に置くか。（表示のみ・可逆・小さい→前でもよい）
4. Signalページ側にも同種の Preview/pending 表示があるか(cmd_494 `Pending Rebalance`)。同時に整えるか別段か。

## 裁定の因果連鎖 — なぜその判断か（事実→制約→判断→効果）— 2026-08-17 02:15+09:00

| # | 裁定/意見（殿・時刻） | 事実 | 制約 | 判断 | 効果 | Obsidian |
|---|---|---|---|---|---|---|
| 1 | 過去月バッジ廃止・当月だけ「価格が揃うまで未確定」（殿 02:10「いい案だな」） | 全期間Pending。真因はledger 0行。過去月は原理的に常に確定 | 確定/未確定の区別が意味を持つのは当月1行だけ。ledger欠落で全部未確定に見える脆さ | 過去月バッジを廃し、当月のみ未確定表示 | 台帳欠落が表示事故にならない。認知負荷減 | `[[全期間Pending_20260817]] -> [[ledger0行]] -> [[過去月バッジ廃止]]` |
| 2 | NEXT SIGNALゾーン不要（殿 02:10 スクショ提示） | 日次スナップショットの来月候補。月末まで毎日変わる | (a)ユーザーが行動できるのは月初確定後 (b)殿裁定01:36「翌月ポジションは翌月分を払った人だけ」(entitlement=position_month)と衝突 (c)as of日付とPreview日付の二重表示 | 撤去 | ログイン境界の面が1つ減る。DM原理(月初確定)と表示が一致 | `[[NEXT_SIGNAL_Preview]] -> [[entitlement_position_month]] -> [[NEXT_SIGNAL撤去]]` |
| 3 | まずチャット・設計書に落とす（殿 02:06/02:12） | 表示仕様変更は小さいが、因果を残さないと車輪の再発明 | 殿原則01:42「裁定は因果で記す」 | AsIs/ToBe+ワイヤーフレーム+チャット記録を1書へ | 他LLM/他人と共通前提 | `[[殿原則_裁定は因果で記す_20260817]] -> [[本設計書]]` |

## チャット記録（殿×将軍・要旨・時系列）— 2026-08-17 02:15+09:00

- 02:06 殿「本番monthly trade画面、全PFでpending表示。表示しなくてもいい気がしてきた。なぜ表示することにしたか、なぜ全期間pendingか調べないと。今はチャット」
- 02:08 将軍: (1)因果=05-31/06-01殿観測→cmd_3675「表示層が主因」→cmd_3706 ledger優先バッジ→cmd_3710 Historical→cmd_3711バックフィル。(2)本番DB一次確認 ledger 0行=08-16復旧後バックフィル未実行が真因。私見=過去月バッジ廃し当月のみ未確定表示へ簡素化。ledgerはL809用に別問題。
- 02:10 殿「過去月バッジ廃し当月だけ未確定はいい案。[スクショ] next signalゾーンは不要」
- 02:11 将軍: NEXT SIGNALはcmd_3706で確定/未確定隔離の裏表として生まれた。不要根拠3点(行動不能情報/entitlement衝突/二重日付)。簡素化後の姿を提示。
- 02:12 殿「設計書に一旦落としてくれ。チャットの流れと俺の意見の因果も忘れるな。asis/tobeのワイヤーフレームも必要」→ 本書作成。

## 注釈 — 2026-08-17 02:15+09:00
- 版番号: AsIsは現物確認のたびにminor更新、ToBeは殿裁定のたびにminor更新。
- 本書は表示仕様のみ。ledger再バックフィルの是非は未決2で扱い、本書のスコープに実行を含めない。
