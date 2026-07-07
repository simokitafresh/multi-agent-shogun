# 本番PF即時復元機構 — 大規模実験の可逆性保証 設計書 AsIs/ToBe 5W1H

- 作成: 将軍 2026-07-08 02:50 (殿指示 02:43/02:47)
- 対象: DM-Signal 本番 (`/mnt/c/Python_app/DM-signal`)
- version: **v1.3** (2026-07-08 03:46 — v1.2: 殿検分5穴(H1-H5)。v1.3: 穴検分2巡目=復元パリティの原理的限界(削除後の価格改定時は完全一致しない)を計測計画に注記)

## §0 発端 — 殿の言葉（2026-07-08）

> 今の本番PFをいつでも元に戻す仕組みはあるか？(02:41)
> 本番から削除後に何時でも即時に任意や全てのPFを元通りに元に戻す仕組みだ。ローカルがなくても元に戻せる仕組みが欲しい(02:43)
> 目的は今後大規模な実験や変更をしてもユーザー希望で全て遠隔で元に戻せるようにしたい(02:47)

文脈: L0再選別(CAGR/WorstYear/AvgUWP案、`gs_3objective_correlation_analysis_20260707.md`)で旧チャンピオンPFの入替えが視野。入替え=削除が不可逆である限り、実験判断は毎回重い。**可逆性は実験速度の土台**。

## §1 原理 — 削除と退避の分離不能化

**削除操作が退避を内包し、バイパス経路が存在しないこと。** 人の注意(手動バックアップ)に依存する退避は退避ではない。バックアップファースト原則(LS040)の環境埋込み版。

## §2 AsIs — 現状の棚卸し（2026-07-08 02:45 全てfile:line現物確認）

| # | 項目 | 現状 | 現物 |
|---|------|------|------|
| A1 | 削除経路 | `DELETE /api/portfolios/{id}` → FoF参照ガード → `PortfolioRepository.delete_by_id`で**物理削除** | `backend/app/api/portfolios.py:167-197` |
| A2 | DB内退避 | `portfolio_config_snapshots`は`ondelete="CASCADE"` — **PF物理削除でスナップショットごと共倒れ** | `backend/app/db/models.py:895-905` |
| A3 | 退避の設計意図 | docstring「設定変更の履歴追跡」— 削除復元は目的外 | `models.py:896-899` |
| A4 | 最終安全策 | ローカルJSON手動バックアップ(`docs/research/pf_config_backup_*.json`) — **ローカル依存+手動** | `context/dm-signal-ops.md §39` |
| A5 | 復元経路 | **不在**。復元スクリプト/APIなし。削除スクリプトもdead code化済み(c47742d1) | ops.md §40 |
| A6 | 削除で消えるデータ | `portfolios.id`参照FKは**現在20箇所**(全て`ondelete=CASCADE`)。ops.md §39の「CASCADE 10テーブル+NO ACTION 9テーブル先行DELETE」は2026-06-01時点の記載で、**その後の追加テーブルにより現状と乖離**。実績: 58件削除で関連260,965行(cmd_3112) | `models.py` FK grep 20箇所(2026-07-08 02:53実測) |
| A6b | **再生成不能データ** | `signal_decision_ledger`(models.py:138 CASCADE)はイベント台帳 — historical_backfillは一回性バックフィル(cmd_3711)でrecalculateでは再生成**されない**。`month_start_signal_input_snapshots`(models.py:198 CASCADE)は過去の月初時点の入力状態 — 事後再現**不能**。両者は削除で永久消失する | `models.py:138,198` |
| A6c | **FoF依存連鎖** | L1=L0を構成、L2/L3=下位FoFを構成(FoF of FoF of FoF)。削除はFoF参照ガード(`portfolios.py:180-189`)により必ず逆依存順(L3→L0)。**復元は正依存順(L0→L3)が必須** — L3だけ復元しても構成PF不在で機能しない(殿指摘02:55)。依存解決ユーティリティは既存(`services/fof/dependency.py`, `get_referencing_fofs`) | `portfolios.py:167-192` |
| A7 | 論理削除 | `hide_portfolio`(default=True)/`is_active`列は存在。表示は消せるがデータ残存=「削除」ではない。recalculate系は`hide_portfolio`を参照しない(grepゼロ件)=非表示でも計算コスト残存 | `models.py:91,95` |
| A8 | 再現可能性 | `config`(JSON全量, `models.py:85`)+価格正本(prices_raw自前化済み cmd_3687-3691)があれば計算結果は決定論的に再生成可能。fullrecalculate全量≈480s | `models.py:85` |

**結論: 「ローカル非依存・即時・任意/全量・遠隔」の4要件を満たす仕組みは存在しない。**

## §3 なぜなぜ — なぜ復元機構が無いか

1. なぜ共倒れ設計か → snapshotの目的が「設定変更の履歴追跡」(A3)で、削除復元ではなかった
2. なぜ復元が目的外だったか → 削除は稀な清掃作業(58件は旧式PFの終端処分)で、戻す前提がなかった
3. なぜ今必要か → **前提が変わった**。L0再選別以降、PF入替えは「実験」になる。実験は戻せることが前提
4. 根因 → 削除=終端処分という旧前提のまま、実験サイクル(登録⇄削除⇄復元)の運用に入ろうとしている

## §4 AsIs/ToBe 5W1H対比

| 軸 | AsIs | ToBe |
|----|------|------|
| WHO | 将軍/忍者がローカルPCで手動バックアップ | **殿がユーザーとして**admin UI/APIから操作(実行主体はbackend) |
| WHAT | configのみローカルJSON退避。計算結果と紐付けは消失 | 削除PFの**全復元素材**(portfolios行+config+folder情報)をDB内退避。復元は元UUID・元フォルダで完全再現 |
| WHEN | 削除前に人が思い出したら | **削除時に自動・無条件**(コード経路に内包、バイパス不能)。復元はいつでも |
| WHERE | ローカルPCのファイル | **本番DB内**の独立退避テーブル(FK制約なし=共倒れなし) |
| WHY | 事故時の保険(暗黙) | **大規模実験の可逆性保証**=実験速度の土台(明示) |
| HOW | 手動SELECT→JSON保存 | 削除フック自動退避 + 復元API(任意1体/複数/全量) + 復元後recalculate自動起動 |

## §5 ToBe設計

### R1: 独立退避テーブル `portfolio_archive`

```
portfolio_archive
  id            (autoincrement PK)
  portfolio_id  (String, FK なし ← 共倒れ根絶の核心)
  payload       (JSON: portfolios行の全列 = id/name/type/config/folder_id/
                 hide_portfolio/hide_signal/is_active/created_at/updated_at
                 + folder名/親フォルダ階層(2-level)(SET NULLで消える文脈の保全)
                 + 再生成不能データ: signal_decision_ledger当該PF行全量
                 + month_start_signal_input_snapshots当該PF行全量)
  deleted_at    (UTCDateTime)
  delete_reason (String, nullable)
  restored_at   (UTCDateTime, nullable ← 復元済みマーク。再削除で新行)
```

- **退避基準を精密化(v1.1)**: 「決定論的に再生成可能なもののみ退避しない」。計算結果系(monthly_returns等26万行級)はconfig+価格正本から再生成可能(A8)なので退避しない。**イベント台帳(ledger)と月初入力snapshot(A6b)は再生成不能なので退避する**(行数は1PFあたり数百行程度=軽量)
- R1実装のACに「`models.py`の`portfolios.id`参照FK 20箇所の全テーブル棚卸し+再生成可能/不能の分類表」を含める(A6の乖離解消。ops.md §39も同時更新)
- 保持は無期限(容量: ledger込みでも1PF数十KB。100PF削除でも数MB未満)

### R2: 削除フック+復元API

- **削除フック**: `PortfolioRepository.delete_by_id`の直前に`portfolio_archive` INSERT(同一トランザクション)。API層ではなくRepository層に置く=どの呼出し経路でもバイパス不能
- **復元API**(admin認証):
  - `POST /api/admin/portfolios/restore/{portfolio_id}` — 任意1体
  - `POST /api/admin/portfolios/restore-all?since=...` — 全量/期間指定一括
  - 処理: archive読出し → portfolios再INSERT(**元UUID維持**) → folder再作成(不在時、親階層含む) → ledger/月初snapshot行の復元INSERT → 対象PFのrecalculate起動 → 完了通知
  - **依存グラフ自動解決(v1.1、殿指摘02:55)**: FoF復元時はconfig内の構成PF参照を再帰検証し、不在の構成PFを**archiveから正依存順(L0→L1→L2→L3)に自動復元**する(`--with-dependencies`既定on)。archiveにも現存にも無い構成PFがある場合は復元を中止し、不足依存リストを返す。全量復元はトポロジカルソートで正依存順に実行。依存解決は既存`services/fof/dependency.py`/`get_referencing_fofs`(削除ガードの逆方向)を再利用
  - 衝突ガード: 同一UUIDが現存する場合は409(上書きしない)。cron recalculate実行中は既存advisory lockに従い待機(競合エッジ)
  - **名前衝突ガード(v1.2、殿指摘03:00)**: 同名PFが現存する場合、UUIDで区別できても人間が区別できずトラブルの元 — **既定で復元を中止**し3択を返す: (1)現存PFをリネームしてから再実行 (2)復元PFに接尾辞付与(例: `name (restored 2026-07-08)`)して復元 (3)明示フラグで強制共存。同名判定はフォルダ横断の全PF名で行う(同フォルダ限定にしない)
- **所要時間**: 単体=INSERT即時+recalculate(1PF分)。全量=fullrecalculate ≈480s。いずれも人手ゼロ1コマンド

### R3: 遠隔操作口

- admin画面に「削除済みPF一覧(archive)+復元ボタン」。殿がスマホ/ブラウザから操作可能=**ローカルPC完全不要**
- 最小構成ならAPI直叩き(curl)でも要件は満たすが、「ユーザー希望で」の趣旨からUI推奨

### R4: 検証(実装cmdのAC)

- E2E: PF削除→archive行存在→復元→**パリティ検証**(復元前後のmonthly_returns/holding_signal完全一致+ledger/月初snapshot行数一致)
- **依存連鎖E2E(v1.1)**: L0-L3の4層を逆依存順で全削除→L3を1体指定で復元→L0/L1/L2が自動復元され4層全てパリティ一致することをテスト(殿指摘ケースの直接検証)
- エッジ: フォルダ消失時の再作成(親階層含む)/同UUID衝突409/二重復元防止/名前衝突ガード発火(3択返却の両ケース)/cron recalculate競合時のlock待機/不足依存の中止+リスト返却

## §6 計測計画

| 指標 | baseline(AsIs) | target(ToBe) |
|------|----------------|--------------|
| 復元所要(任意1体) | 不可能(手作業数時間+ローカル必須) | 1操作+recalculate数分以内 |
| 復元所要(全量) | 不可能 | 1操作+fullrecalc ≈480s |
| 退避漏れ率 | 人依存(手動) | 構造的0(削除経路に内包) |
| 復元後パリティ | — | monthly_returns/holding_signal 100%一致。**注(v1.3): 削除〜復元の間に価格データ自体が改定された場合(EODHD再調整・corporate_events修正等)、再計算値は削除時点と原理的に一致しない。この場合は「現行価格での正しい再計算」が正であり、パリティ検証は価格改定の有無を先に確認してから解釈する** |

## §7 実装cmd分割案（1道具1CMD・殿裁可待ち）

| cmd | 内容 | 規模 |
|-----|------|------|
| R1 | `portfolio_archive`テーブル(migration+model)+Repository層削除フック+単体テスト | 小 |
| R2 | 復元API(単体/一括)+recalculate連動+衝突ガード+E2Eパリティ検証 | 中 |
| R3 | admin UI(削除済み一覧+復元ボタン) | 小 |

順序: R1→R2→R3(R1完了時点で「退避」は保証される=L0再選別の前提防御はR1+R2で成立)

## §8 スコープ外(明示)

- 価格データの復元(prices_raw正本は別系統で多重化済み cmd_3687-3691)
- 設定「変更」のundo(本設計は削除の復元。変更履歴は既存portfolio_config_snapshotsの本来目的)
- L0再選別そのもの(別cmd。本機構が前提防御)

## §9 v1.0の穴と修正（殿検分02:52-02:55 + 将軍敵対検証、全て現物確認済み）

| # | 穴 | 発見者 | v1.1修正 |
|---|-----|--------|----------|
| H1 | **FoF依存連鎖の未定義**: L3復元にはL0-L2の存在が前提だが、v1.0は「順序制約をテスト」の1行のみで復元APIの依存解決仕様が無かった | **殿(02:55)** | R2に依存グラフ自動解決(`--with-dependencies`既定on、正依存順L0→L3、不足時中止+リスト返却)を仕様化。R4に4層E2E追加 |
| H2 | **再生成不能データの見落とし**: v1.0は「計算結果は再生成可能だから退避不要」としたが、`signal_decision_ledger`(models.py:138)と`month_start_signal_input_snapshots`(models.py:198)はCASCADEで消え、recalculateでは再生成されない | 将軍検証 | payloadに両者の当該PF行を退避対象として追加。退避基準を「決定論的再生成可能なもののみ退避しない」へ精密化 |
| H3 | **削除範囲の記載乖離**: ops.md §39「CASCADE 10テーブル」は2026-06-01時点。現状は`portfolios.id`参照FK 20箇所 | 将軍検証(02:53 grep実測) | A6修正+R1のACにFK全量棚卸し(再生成可能/不能の分類表)とops.md更新を追加 |
| H4 | (小)cron recalculateとの競合の未記載 | 将軍検証 | R2衝突ガード+R4エッジに追加 |
| H5 | **同名PF共存の許容**: v1.1は同名別UUIDの共存を「表示エッジ」として許したが、UUIDで区別できても人間が区別できずトラブルの元。L0再選別では新旧チャンピオンが類似命名になる現実的シナリオ | **殿(03:00)** | R2に名前衝突ガード追加 — 既定で中止+3択(現存リネーム/接尾辞付き復元/明示強制)。判定はフォルダ横断 |

残存する既知の限界(設計上許容、明示): DB自体の喪失はスコープ外(Render管理のDBバックアップが別層でカバー)。archiveテーブル自体への誤DELETEは運用上の残リスク — R1でアプリ層にarchive削除経路を作らないことで最小化。

## 因果リンク

- [[殿要望20260708_0243_PF即時復元]] -> [[portfolio_config_snapshots_CASCADE共倒れ(models.py:905)]] -> [[本設計書]]
- [[gs_3objective_correlation_analysis_20260707]] — L0再選別(実験の第一弾)が本機構の直近ユースケース
- [[LS040_バックアップファースト]] — 原則の環境埋込み版
- [[production_parity]] — 復元検証はパリティ検証の既存手順を再利用
