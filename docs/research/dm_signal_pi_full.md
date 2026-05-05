# DM-Signal 本番不変量 (Production Invariants) 全文 PI-001〜PI-025

> 移動元: `projects/dm-signal.yaml §(PI)` (cmd_2295圧縮 2026-04-26)
> 最終更新: 2026-04-25
> 用途: 全エージェントに自動ロード。GS・偵察・impl設計の前提事実。

| ID | 事実 | 含意 |
|----|------|------|
| PI-001 | 本番シグナル計算は日次解像度。10D/15D/20D/1Mは全て異なるlookback | 月次解像度のdedupは日次パラメータ差異を破壊する |
| PI-002 | SQLiteミラー(backend/static/data/dm_signal.db)は不完全。本番PostgreSQLとデータ乖離 | 複製は原本と乖離する前提で検証せよ |
| PI-003 | standard PFのconfig JSONにはpipeline_config必須。NoneだとrecalculateでCashフォールバック | 必須フィールドのデフォルト値を暗黙に仮定するな |
| PI-004 | GSはnumpy配列操作のみで本番pydanticスキーマを通さない | 投入先のバリデーション層(Pydantic/ORM)を事前通過させよ |
| PI-005 | 新規PF登録後のrecalculateはfull(portfolio_id指定なし)一発が鉄則 | 部分操作の連続実行は暗黙の依存順序を壊す |
| PI-006 | 手順書/ランブックの記載はrecalculateコードパスとの照合なしには信頼できない | ACに「実際のコードパスとの照合検証」を含めよ |
| PI-007 | GS結果と本番計算結果は構造的に乖離しうる(月次vs日次解像度、pydanticバリデーション差異等) | 投入前に本番計算結果とのパリティ検証必須 |
| PI-008 | monthly_returnsテーブルにはmonthly_return(Close)とmonthly_return_open(Open)の2列が存在 | 比較対象のカラム/フィールドを間違えると偽の一致または偽の不一致が発生 |
| PI-009 | GSは本番と同一の結果を出さなければならない。全期間holding_signal完全一致(必須)+monthly_return 1e-6以内 | 最敏感指標(holding_signal)で完全一致要求。1期間でも不一致=全体汚染 |
| PI-010 | 本番はprice_by_symbolに非市場ティッカー(^VIX/DTB3)を含めない | 異種データは混合するな、native系列で個別処理必須 |
| PI-011 | シン忍法v2(21体)のterminal_blockは全てEqualWeight | 出力の事実(シグナル一致/リターン一致)のみで判定せよ |
| PI-012 | MomentumAccelerationFilterのnumerator_period/denominator_periodにはweight: 1.0が必須 | 書込成功≠データ有効。書込時に処理側の制約も事前検証せよ |
| PI-013 | DB INSERT前にPydanticモデル(Portfolio)の全制約を事前検証必須。top_n:1-2, months:0-36, days:≤756, weight:0-1 | ORM/Pydantic迂回禁止。1体でも違反→バックエンド全PF読込失敗→全機能停止 |
| PI-014 | 分析・研究の入力データは出自(provenance)が検証済みであること必須。outputs/配下のCSVは未検証 | 出自の検証なしにデータを信頼するな。指定ソースから直接取得せよ |
| PI-015 | ネステッドFoFはfullrecalculate(portfolio_id=None)でsignals/monthly_returnsが生成されない場合あり | バッチの成功は個別要素の成功を保証しない。個別検証で補完せよ |
| PI-016 | ループ内で同一DBクエリがN回実行される場合、ループ前に一括ロードしてdict/cacheで渡すこと | N+1パターンは桁違いの性能劣化源(実績: 53,000query除去→4627s→0.73s) |
| PI-017 | StockData API /v1/economic/{symbol} は1リクエスト最大1000レコード | 長期/大量データ取得はページネーション必須 |
| PI-018 | except ExceptionでCash/0.0/True/1.0/SPY等をfallback返却する新規コード禁止。エラー時はNone+logger.error/raise | silent fallbackはエラーを隠し下流に汚染データを伝播させる |
| PI-019 | 上流処理がデータの可視性(いつ見えるか)や生存期間(いつ消えるか)を変更すると、下流はそれを知らない | Phase境界・commit・cache・flush・session lifecycleの全てに適用 |
| PI-020 | データが信頼境界を越えるとき(GS→本番, SQL直接→ORM, 外部CSV→分析)、越えた先のルールで検証しなければ汚染が入る | 新しい境界を発見したらこのPIを参照し、検証パスが存在するか確認せよ |
| PI-021 | 本番既存の表示・計算の変更は絶対禁止。ユーザーと共有済み。変更ではなく機能追加のみ許可 | 研究=自由に実験、本番投入=厳密な設計+連携が必須 (殿厳命2026-04-03) |
| PI-022 | OOS検証はL1(FoF/忍法)レベルで実施。L0のOOSは不要。L0を有限時間指標で尖らせた設計意図=overfitを気にしない | L0でOOS検証するのは設計意図と矛盾。L1で効果を検証せよ |
| PI-023 | 本番DB変更後は即パリティ確認必須。「後でまとめて確認」禁止。新PF登録時はhide_portfolio=trueで登録 | 中間状態はリアルタイムでユーザーに影響する (殿指摘2026-04-07) |
| PI-024 | 株価データはsplit・データプロバイダ修正で過去全期間が遡及的に変わりうる。再計算は常に全期間(full history)で実行 | 差分再計算では修正を見逃して本番DBが静かに劣化する (殿厳命2026-04-22) |
| PI-025 | upfront cleanup(Phase 0先消し)後にRender worker restartすると、再生成前のMonthlyReturn 0件が永続化する | replace系precomputeはbegin_nested(savepoint)でrollback範囲を限定必須 |
| PI-026 | 本番(PipelineEngine+DB)が正(ground truth)。GSパリティ不一致時は本番を疑わずGS側を改善。本番バグ仮説を立てるな | GS不一致=GS側の再現性不足。本番は稼働中・ユーザー参照中であり正と見做す (殿裁定) |
