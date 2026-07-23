# cmd_4140 deterioration履歴欠落 偵察

- verified_at: 2026-07-23
- scope: read-only（本番DB書込み0件、コード変更0件）
- 結論: 欠落層はDB生成側。cronは全102 PFを正常処理するが、毎月「現在月1点」だけをUPSERTするため、PF登録前・機能導入前の履歴を生成しない。さらにAPI既定値とfrontend呼出しは6か月上限である。

## §1 データ経路と変更対象

| 層 | 現物 | 行 | 確認結果 |
|---|---|---:|---|
| cron定義 | `/mnt/c/Python_app/DM-signal/render.yaml` | 175-185 | 毎月1日03:00 UTCに`POST /admin/deterioration-batch`を1回実行 |
| endpoint | `/mnt/c/Python_app/DM-signal/backend/app/api/deterioration.py` | 322-350 | `run_deterioration_batch()`を引数なしで呼ぶ |
| batch loader | `/mnt/c/Python_app/DM-signal/backend/app/jobs/deterioration_batch.py` | 44-69 | 全PFの全期間`monthly_return_open`を年月順にロードするが年月キーを捨てて配列化 |
| 対象月 | 同上 | 72-75, 206-220 | `year_month=None`なら現在UTC月。指定月は保存キーにだけ使用 |
| 対象PF | 同上 | 224-250 | `Portfolio.id`全件を取得し、月次return 0件のみskip |
| DB保存 | 同上 | 148-174, 247-270 | PK `(portfolio_id, year_month)`へ当月1点だけ`merge`/commit |
| 計算 | `/mnt/c/Python_app/DM-signal/backend/app/services/deterioration.py` | 23-31, 118-149 | 窓6/12/24、long最低60か月、cap120。最大窓は84か月以上必要 |
| list API | `/mnt/c/Python_app/DM-signal/backend/app/api/deterioration.py` | 30-215 | 最新月の全PFを返す。対象PF漏れなし |
| history API | 同上 | 218-319 | `months`既定6、最大120。DB行を降順limit後、時系列昇順で返す |
| API client | `/mnt/c/Python_app/DM-signal/frontend/lib/api-client.ts` | 1424-1431 | `months`を指定せずhistory APIを呼ぶ |
| 詳細表示 | `/mnt/c/Python_app/DM-signal/frontend/app/deterioration/page.tsx` | 927-990 | APIのhistoryをそのままグラフへ渡す。frontend側の行欠落filterなし |

## §2 本番DB全数集計

`/db-check`の`readonly_query` capability launcherで次を実行した。

```sql
SELECT p.id,p.name,p.type,COUNT(d.year_month),MIN(d.year_month),MAX(d.year_month)
FROM portfolios p
LEFT JOIN deterioration_snapshots d ON d.portfolio_id=p.id
GROUP BY p.id,p.name,p.type;
```

| type | 履歴行数 | PF数 | DB期間 |
|---|---:|---:|---|
| fof | 1 | 74 | 2026-07のみ |
| fof | 5 | 4 | 2026-03〜2026-07 |
| standard | 1 | 12 | 2026-07のみ |
| standard | 3 | 1 | 2026-05〜2026-07 |
| standard | 5 | 11 | 2026-03〜2026-07 |

- 合計: 102 PF。0行=0件、1行=86件、3行=1件、5行=15件。
- 月次リターン素材: FoF 78件、各106〜184か月（2011-04〜2026-07）。standard 24件、各173〜276か月（2003-08〜2026-07）。
- よって表示層ではなく、`deterioration_snapshots`の履歴未生成が原因。長期計算の入力素材は全PFに存在する。

### 1行の86 PF（全数）

- fof 74: GSシン分身-常勝、GSシン分身-激攻、GSシン分身-鉄壁、GSシン加速D-常勝、GSシン加速D-激攻、GSシン加速D-鉄壁、GSシン加速R-常勝、GSシン加速R-激攻、GSシン加速R-鉄壁、GSシン四つ目-常勝、GSシン四つ目-激攻、GSシン四つ目-鉄壁、GSシン変わり身-常勝、GSシン変わり身-激攻、GSシン変わり身-鉄壁、GSシン抜き身-常勝、GSシン抜き身-激攻、GSシン抜き身-鉄壁、GSシン追い風-常勝、GSシン追い風-激攻、GSシン追い風-鉄壁、New Fund of Funds、New Fund of Funds_copy、New Fund of Funds_copy_copy、New Fund of Funds_copy_copy_copy、奥義-GS-分身-常勝、奥義-GS-分身-激攻、奥義-GS-分身-鉄壁、奥義-GS-加速D-常勝、奥義-GS-加速D-激攻、奥義-GS-加速D-鉄壁、奥義-GS-加速R-常勝、奥義-GS-加速R-激攻、奥義-GS-加速R-鉄壁、奥義-GS-四つ目-常勝、奥義-GS-四つ目-激攻、奥義-GS-四つ目-鉄壁、奥義-GS-変わり身-常勝、奥義-GS-変わり身-激攻、奥義-GS-変わり身-鉄壁、奥義-GS-抜き身-常勝、奥義-GS-抜き身-激攻、奥義-GS-抜き身-鉄壁、奥義-GS-新四つ目-常勝、奥義-GS-新四つ目-激攻、奥義-GS-新四つ目-鉄壁、奥義-GS-追い風-常勝、奥義-GS-追い風-激攻、奥義-GS-追い風-鉄壁、秘奥義-分身-常勝、秘奥義-分身-激攻、秘奥義-分身-鉄壁、秘奥義-加速D-常勝、秘奥義-加速D-激攻、秘奥義-加速D-鉄壁、秘奥義-加速R-常勝、秘奥義-加速R-激攻、秘奥義-加速R-鉄壁、秘奥義-四つ目-常勝、秘奥義-四つ目-激攻、秘奥義-四つ目-鉄壁、秘奥義-堅守、秘奥義-変わり身-常勝、秘奥義-変わり身-激攻、秘奥義-変わり身-鉄壁、秘奥義-常勝、秘奥義-抜き身-常勝、秘奥義-抜き身-激攻、秘奥義-抜き身-鉄壁、秘奥義-激攻、秘奥義-追い風-常勝、秘奥義-追い風-激攻、秘奥義-追い風-鉄壁、秘奥義-鉄壁。
- standard 12: シン朱雀-常勝、シン朱雀-激攻、シン朱雀-鉄壁、シン玄武-常勝、シン玄武-激攻、シン玄武-鉄壁、シン白虎-常勝、シン白虎-激攻、シン白虎-鉄壁、シン青龍-常勝、シン青龍-激攻、シン青龍-鉄壁。

### 3〜5行の16 PF（全数）

- 3行: basicデュアルモメンタム。
- fof 5行: Ave-X、劇薬DMオリジナル、劇薬DMスムーズ、裏Ave-X。
- standard 5行: DM2、DM2-test、DM3、DM4、DM5、DM5-006、DM6、DM6-5、DM7+、DM-safe、DM-safe-2。

## §3 cron実態・順序制約

- Render resource: `crn-d6kehqlm5p6s73dov630`。
- 2026-07-23 02:57:28 UTC開始、02:57:57成功終了。
- 実レスポンス: `portfolios_processed=102`、`skipped=0`、`elapsed_sec=0.73`、benchmark 2/2、P-average 102/102。
- 対象PF選定漏れ・cron失敗ではない。月1点だけ生成する仕様が原因。
- batchは`monthly_returns`を前提とする。後続実装はETL/full recalculation完了後に実行しなければならない。
- 過去月バックフィルでは、各snapshot月より後のreturnを入力してはならない。現行`_load_monthly_returns()`は年月を捨てるため、単に`run_deterioration_batch(year_month=過去月)`をループすると未来データ混入の同値履歴になる。

## §4 波及先・テスト・エッジケース

### 波及先

1. `backend/app/jobs/deterioration_batch.py`: 年月付きreturnロード、as-of切断、全期間backfill。
2. `backend/app/api/deterioration.py`: history上限/既定値または全履歴契約。
3. `frontend/lib/api-client.ts`: `months`指定を受けるAPI client。
4. `frontend/app/deterioration/page.tsx`: 長期履歴を明示要求。
5. `render.yaml`: 定常cronは当月差分のみを維持。初回/新規PFbackfillの起動方式を追加する場合のみ変更。

### 既存テスト

- `backend/tests/test_deterioration_batch.py:150-220`: 全PF処理・欠損skip・現在月1点UPSERTを確認するが、as-of切断/backfillなし。
- `backend/tests/test_deterioration_api.py:230-297`: 時系列順、既定6、limit 1〜120を固定。
- 後続cmdでは「過去月snapshotがその月以前のreturnだけで計算される」「全PFの期待月数」「再実行冪等」「frontendが長期件数を表示」をcontract化する。

### エッジケース

- 新規登録PF: 月次return全期間を持っていても登録月1点しか生成されない。登録後backfill必須。
- 改名PF: UUIDを維持する限り履歴継続。UUID再作成なら別PFとしてbackfillが必要。
- FoF/入れ子FoF: monthly_returns生成完了後にbackfill。構成PFの登録日ではなく当該FoFの利用可能return期間を基準にする。
- 初期期間: 最大窓24+MIN_LONG 60により84か月未満は`INSUFFICIENT_DATA`。意味ある履歴の開始点は各PFの84件目以降。ただし監査目的で不足月も保存するかは後続cmdで一意に決める。
- API上限: 120ではstandardの最大276か月を全表示できない。全利用可能履歴を要件とするなら上限を少なくとも360へ上げるか、pagination/limitなし管理画面契約が必要。

## §5 修正方針と後続cmd AC案

1. 月次returnを`portfolio_id, year_month, monthly_return_open`で保持し、各対象月について`year_month <= target`だけを`_compute_for_portfolio`へ渡す。
2. 各PFの利用可能期間を削らず全候補月を計算する。少なくとも84か月目〜最新月を全数UPSERTし、初期不足月を含める/含めない基準を仕様化する。
3. 既存当月cronはO(PF)差分経路のまま維持し、新規PF検知時または明示backfill経路で過去分を冪等生成する。
4. history API/client/UIを長期表示契約へ更新し、最大276か月の本番素材を欠落なく取得・描画する。
5. 本番適用後read-only SQLで全102 PFについて、`snapshot_count = expected_count`、0件=0、未来データ混入=0、重複PK=0を検証する。
6. regression contract: as-ofリーク0、standard/FoF/新規PF/改名UUID維持/不足期間/API長期limit/再実行冪等を二値確認する。

