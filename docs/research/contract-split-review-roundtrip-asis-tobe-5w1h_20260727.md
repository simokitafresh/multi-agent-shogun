# 契約の分散が生むレビュー往復 — ASIS/TOBE 5W1H (2026-07-27)

- 版: **v1.1**(2026-07-27 16:06 将軍レビュー blt_155653 の指摘A/B/Cを全採用)
- 起案: 軍師(殿下知 2026-07-27 15:44「気づきがあれば具体的に調査をしてasis/tobe 5W1Hの形で設計書として報告せよ。覚醒して実行」)
- 一次調査: 軍師(2026-07-27 15:44-15:50、本日の自レビュー51件の全数分類+コード現物確認)
- origin: `[[軍師LGTM後のGATE BLOCK]] -> [[同一判定の複数実装]] -> [[本設計書]]`

## §1 ASIS — 否定判定の74%が成果物の中身ではない

### E0. 本日の軍師レビュー全数(母集団51件)

| 指標 | 数値 | 取得コマンド |
|---|---|---|
| 判定総数 / distinct cmd | **51件 / 25件** | `logs/gunshi_review_log.yaml` を python3 で timestamp=2026-07-27 抽出 |
| 追加往復(同一cmdの2回目以降) | **26回** | 同上。cmd_id別Counterで v>1 の (v-1) を合算 |
| 否定判定(FAIL+REQUEST_CHANGES) | 23件 | 同上 |
| うち★契約・前提・形式の不整合 | **17件(74%)** | findings_summary/fail_reasons/ambiguity_points をキーワード分類 |
| うち成果物の中身 | 6件(26%) | 同上 |

- 1件の定義 = review_log エントリ1件。網羅範囲 = 本日の軍師レビューのみ(家老レビュー・忍者内部の手戻りは未走査)
- 最多往復: `cmd_reflux_promotion_202607271152_saizo` 5回、`cmd_karo_recon2_r7_inject_byte_cap_measure_20260727` 4回

**∴レビュー工数の大半は、忍者の実装品質ではなく「発注側と検査側の齟齬」の検出に費やされている。**

### E1. 齟齬の実体は「同一の判定が複数箇所に別実装で存在する」

本日1日で同族が**7件**観測された。いずれも file:line で現物確認済み。

| # | 事象 | 判定A | 判定B | 結果 |
|---|---|---|---|---|
| 1 | no-code identity | `review_approval.sh` の `permits_no_code_identity`(queue/logs配下+evidence+明示no-commit) | `cmd_complete_gate.sh:236-262`(files_modified全てliteral `no-code-change` または `commit_hash=="no-code-change"`) | Aを満たしLGTM到達→Bで`invalid`→GATE BLOCK。軍師D0 `00c9fff99` で統一 |
| 2 | no-code identity 第3入口 | 同上 | `deploy_task.sh:3888` `rehydrate_task_commit_contract_from_report` | 3入口目。`cmd_karo_hotfix_unify_no_code_contract_dc_warn_20260727` で対処中 |
| 3 | dc duplicate の exit契約 | ヘッダ `gate_dc_duplicate.sh:14` 「Partial match → WARN (exit 0)」 | 実装 `:163` `sys.exit(1)` | 呼び手 `cmd_complete_gate.sh:7890` の `|| echo "BLOCK: gate script error"` が発火し**表示文字列へ偽BLOCK行が混入** |
| 4 | precheck 内部の二重判定 | engine `prediction: CLEAR` | shell `総合: ERRORS=1` | **同一ツールの1回の実行で結論が割れる**(実測: 半蔵 reflux 報告)。判定台帳が2つある — shell側 `ERRORS=$((ERRORS + 1))` **21箇所** / engine側 `gate_pred = 'BLOCK'\|'WARN'` **6箇所**(実測) |
| 5 | task の quality_gate | task YAML `quality_gate.fp_measurement` が契約を課す | precheck は `quality_gate` を**一切参照しない**(`grep -c` = shell 0 / engine 0) | 契約未達のまま `ERRORS=0 / CLEAR` → 軍師がLGTM→本来のAC未達。`r7` で2度目のFAIL |
| 6 | lessons_useful の集合契約 | 還流弾は対象教訓そのものを扱う | 検査は `related_lessons`(=**空配列**)の部分集合を要求 | `MISMATCH extra=LS099` でBLOCK確実。還流弾は**構造的に必ず1往復する** |
| 7 | 訂正の配送 | 軍師が訂正・追加を送信 | `inbox_write.sh:2643-2648` が report_id+fingerprint で DUPLICATE 破棄 | 本日**3回**suppressされ、都度掲示板へ迂回 |

### E2. 構造欠陥(コード現物で確定)

**D1. 契約の定義点と検査点が別ファイルにある**
発注は `queue/tasks/*.yaml`(AC + quality_gate)、一次検査は `gate_gunshi_report_precheck.sh`、終局検査は `cmd_complete_gate.sh`。**三者は同じ契約を別々に解釈する**。E1-5 が典型で、発注が課した契約を一次検査が読まないため、検査を全て通った成果物がAC未達のまま進む。

**D2. 同じ述語が複数実装される**
E1-1/2 の no-code identity は同一概念に3実装。共有関数 `report_commit_identity.permits_no_code_identity` は存在したが、**参照していたのは1箇所だけ**だった。

**D3. 契約の記述(ヘッダ・doc)と実装が同期しない**
E1-3。ヘッダは仕様書として読まれるが機械検査されないため、乖離しても誰も気づかない。呼び手が `||` で拾う設計と噛み合い、**正常系が異常文字列を生む**。

**D4. 弾の型ごとの契約差が表現できない**
E1-6。「対象そのものが教訓である弾」で `lessons_useful` の意味が二重化(参考として注入されたものか、作業対象か)。型を区別する語彙がないため、還流弾は毎回同じ場所で止まる。**在庫は352件あり、このまま出せば352回の往復になる。**

## §2 TOBE — 原理1行

**「契約は1箇所で定義し、検査は全てそれを参照する。参照していない検査は契約を判定していない。」**

不変更契約: fail-closed・二相承認の実質・D001-D009・三層preflight は一切緩めない(殿裁定07-21「削るな、速くしろ」)。本設計は**判定を増やさず、判定の出所を1つにする**。

### T1. 契約参照の一元化(D2是正・主軸)
- 同一概念の述語が2箇所以上にある場合、**共有関数を正本とし全入口が委譲する**。軍師D0 `00c9fff99` が採った形をそのまま横展開する
- 対象の見つけ方: 判定名(例 `no_code`, `two_phase`, `dc_duplicate`)で `grep -rn` し、**同名判定が2実装以上ある箇所を列挙**する
- 新規機構は作らない。既存の共有lib(`scripts/lib/report_commit_identity.py` 等)へ寄せるだけ

### T2. quality_gate を一次検査へ接続(D1是正・即効)
- `gate_gunshi_report_precheck.sh` が task の `quality_gate` 各キーを読み、報告側の充足を照合する(現状は参照ゼロ)
- **★照合は free-text キーワード一致にしない(将軍指摘B・採用)**。自由文照合は E1-7(SG-PRE9c が引用文へ誤反応)と同型の偽陽性源を新設し、往復を逆に増やす。報告YAMLへ**構造化フィールド**(`quality_gate_fulfillment` 等)を設け、`report_field_set.sh` 経由で書かせて**キー単位の機械照合**とする
- 未充足は ERROR。∴発注が課した契約が検査を素通りしなくなる。ERROR化は上記の構造化を前提条件とする
- 効果見込み: E1-5 型の往復(本日 r7 で1往復)が消える

### T6. precheck 内部の判定を1台帳へ(D2是正・将軍指摘A・採用)
- E1-4 は「判定の出所を1つに」の最典型でありながら初版では是正スコープから落ちていた。独立弾として起こす
- 現状: shell側 `ERRORS` 加算 **21箇所** と engine側 `gate_pred` 決定 **6箇所** が**独立に**結論を出し、`prediction: CLEAR` と `ERRORS=1` が同時に出る
- TOBE: **engine を唯一の判定源**とし、shell は engine の結論を表示・転記するだけにする。shell固有の21判定は engine へ移送する(判定内容は変えない=検査を減らさない)
- 移送しきれない判定が残る場合は、**engine が「shell判定あり」を集約して1つの結論に畳む**。∴外部から見える結論は常に1つ

### T3. ヘッダ契約の機械検証(D3是正)
- gate スクリプトのヘッダに書かれた exit契約を、**同名の回帰testで固定**する(`partial→0` / `exact→1` / `error→非0`)
- 新規gateは作らない。既存の bats へ1ケース足すだけ

### T4. 弾の型を契約へ明示(D4是正)
- 還流弾では task 側 `related_lessons` へ**対象教訓を注入**する。これで `lessons_useful` の集合照合が通り、かつ使用記録も残る
- 効果見込み: 在庫352件 × 1往復 = **352往復の除去**

### T5. 効果計測(既存計装のみ)
- before(本設計書§1に固定): 判定51件/distinct 25件・追加往復26回・否定判定に占める契約起因74%(17/23)
- after: 同一コマンド(`logs/gunshi_review_log.yaml` の python3 集計)で前後比較。目標=**契約起因の否定判定を50%未満へ、追加往復を半減**
- 記録先: 既存 `logs/defense_overhead.jsonl`。新台帳なし

## §3 5W1H

| | 内容 |
|---|---|
| **WHY** | 軍師の否定判定23件中17件(74%)が成果物の中身ではなく契約・前提・形式の不整合であり、本日26回の追加往復を生んだ |
| **WHAT** | T1契約参照の一元化 + T2 quality_gateの一次検査接続(構造化フィールド前提) + T3ヘッダ契約の回帰固定 + T4弾型の契約明示 + T5前後計測 + **T6 precheck内部の判定を1台帳へ** |
| **WHEN** | 家老・将軍レビュー→殿裁可→cmd起票。1道具1CMD: **T6を第1弾**(将軍指摘A、最典型)、T2第2弾(構造化フィールド込み)、T4第3弾。★T1族(1)(2)とT3のdc_duplicateは `cmd_karo_hotfix_unify_no_code_contract_dc_warn_20260727` で**着地済み**(軍師LGTM 16:04)のため T1/T3 の残スコープは「未走査の族」の列挙のみへ縮小 |
| **WHERE** | `gate_gunshi_report_precheck.sh` + `_engine.py`(T2/T3/T6) / 各入口の述語(T1) / `deploy_task.sh` の還流弾生成(T4) |
| **WHO** | 軍師=本設計、将軍=起票、家老=分解配備、忍者=実装、軍師=実装レビュー |
| **HOW** | 境界fixture(§4) + §1数値の前後比較 |

## §4 境界fixture(実装ACへ転記)

1. task に `quality_gate.X` があり報告に充足記述なし → precheck ERROR(現状はCLEAR)
2. task に `quality_gate` なし → 従来どおり(過剰検知しない)
3. 同一概念の述語が2実装 → 同一入力で両者の結論が一致することを差分testで固定
4. `gate_dc_duplicate` partial → exit 0 / exact → exit 1 / 内部エラー → 非0(3方向)
5. 還流弾 task に対象教訓が `related_lessons` として注入される → `lessons_useful` 照合が通る
6. 通常弾では `related_lessons` の意味は不変(還流弾の変更が他弾を壊さない)

## §5 不変更契約

| 対象 | 契約 |
|---|---|
| fail-closed(証跡なしにCLEARしない) | **不変更**。T2は検査を増やす方向であり緩めない |
| 二相承認の実質(LGTM+ACCEPT+fingerprint) | **不変更** |
| D001-D009 / 三層preflight | **不変更** |
| 表示型を増やさない(殿裁定07-20) | T1-T4はいずれも**既存判定の出所を揃える**変更であり、人に作文を強要する新BLOCKを作らない |

## §6 決定事項(未決定を残さない)

| 論点 | 決定 | 根拠 |
|---|---|---|
| 新規gate/hook/状態ファイル | **作らない** | 既存の共有lib・既存precheck・既存batsへ寄せる |
| T2で未充足を WARN か ERROR か | **ERROR** | WARNだと本日の r7 と同じく素通りする。契約は発注側が課したものであり任意ではない |
| 弾の分割 | **T6 → T2 → T4** の3弾(T1/T3は縮小) | 将軍指摘A採用でT6を新設し先頭へ。T1族(1)(2)とT3 dc_duplicateは小太郎弾で着地済み |
| 実装順序 | **T6先行** | 「判定の出所を1つに」の最典型であり、shell21/engine6という実測スコープが確定している |
| T2の照合方式 | **構造化フィールド + report_field_set.sh 経由**(free-text照合は不採用) | 将軍指摘B採用。自由文照合はE1-7と同型のFP源を新設し往復を増やす |
| 将軍レビュー(blt_155653)の反映 | 指摘A/B/C を**全採用** | A=T6新設、B=T2の照合方式を構造化へ、C=T1/T3のスコープ縮小 |

## §7 軍師が確認済みで「不能」と確定した事項

- 本日の家老レビュー・忍者内部の手戻り回数は**未走査**。∴「往復26回」は軍師視点の下限であり、系全体の往復はこれより多い
- E1の7件は本日1日の観測であり、過去日を遡った族の全数は未計測。T1の対象列挙(判定名grep)を実装弾のAC1で取得する

## §8 因果リンク

- → [[commander-inbox-flood-asis-tobe-5w1h_20260727]] 同族(結果の分かっている仕事の反復)。あちらは起床の反復、こちらは判定の反復
- → [[finalize-pipeline-event-driven-asis-tobe-5w1h_20260727]] E1-4/5と同じ層(gate内部の二重判定)
- → [[LG006]] LGTM=GATE通過保証。契約が分散する限りこの保証は成立しない
- → [[LG023]] 原理1行 > 各論パッチ。本設計は新規判定を1つも足さない
