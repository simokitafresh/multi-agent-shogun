<!-- gist-master: 8e47582e91257e50c95af862b1160528 three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707.md -->
# 三層学習ループ自動成長 設計書 v3.0 — 品質×速度の両輪（全面書き直し版）

origin: [[殿指示_三層学習ループ再構築_20260725]] <- [[殿指示_三層学習ループ極限化_20260707]] + [[殿裁定_削るな速くしろ_20260721]] + [[殿裁定_表示型強制必須_20260724]] + [[deepdive_why_chain_20260321]] + [[growth-loop]]
created: 2026-07-25T15:25+09:00 (将軍直筆。v1/v2からの追記ではなく全面書き直し)
status: **v3.0 — 2026-07-25一次計測baseline。旧版(v1 2026-07-07 / v2.2 2026-07-08)は`three-layer-learning-loop-auto-growth-v2-archive_20260708.md`へ全文保全**
baseline計測日: 2026-07-25 (defense_overhead.jsonl + loop_ledger.yaml + startup gate + 将軍/家老RCA一次計測)

## §0 要求定義

| 要素 | 殿の要求(07-07原点 → 07-25更新) |
|------|-------------------------------|
| WHY | 三層学習ループの自動成長を極限まで高める。**ただし成長の定義が転回した: 防御を増やす成長(v1)→品質を保ったまま超速で回す成長(v3)** |
| WHAT | 会話や作業の度に自動で成長する環境一式。v3では「ループ機構自身の速度と計器の正しさ」が主対象 |
| WHO | より性能の低いLLMでも回る（モデル知能非依存）— 不変 |
| WHERE | 他CLI・他PJへ可搬 — 不変 |
| WHEN | 自動で、会話・作業の度に — 不変 |
| HOW | 環境整備(知性の外部化)。v3では**台帳駆動**: 支配項を台帳逆引き→品質2原則維持のまま高速化→同一台帳で前後証明(殿裁定07-25) |

## §1 定義（不変の土台）

### §1.1 三層学習ループ（殿定義 2026-03-20）
- **第一層=個**: 各ロールが自分の仕事の中で回す（binary_checks, environment_change, WA記録）
- **第二層=対**: 2者の組で回す（忍者+家老の報告/WA、家老+軍師のレビュー/LGTM、将軍+殿の対話、将軍+家老のRCA協働=§6.2）
- **第三層=全**: 鎖全体で回す（gate/hook/infra、startup gate、loop_ledger、defense_overhead）

### §1.2 学習ループの解剖（1サイクル=4段階）
```
①検出(gate発火/WA/殿指摘/NO_MATCH/self_retro) → ②記録(lesson/insight/WA/掲示板/台帳)
→ ③還流(task注入/gate化/テンプレ化/alias登録/reflux自動配備) → ④検証(再発率/useful_rate/FP率/前後差分)
```
成長速度 = min(①〜④の各スループット)。**v1時点の律速=③還流の手動依存(解消済み)。v3時点の律速=ループ機構自身の速度と計器の正しさ(§3.4)**。

### §1.3 成長の定義（殿定義 2026-05-10 — 不変）
「上限は無く、下限が切り上がる」。計測形: 再発率→0漸近 + 新クラスの検出→防御化リードタイム短縮 + **(v3追加)同一品質での機構実行時間短縮**。

## §2 設計原理 P1-P10（統合版。v1のP1-P6を検証済み形で再掲）

| # | 原理 | 状態 | 根拠(一次データ) |
|---|------|------|----------------|
| P1 | **機械的判断を構造に置換**。ただし「考える工程」は毎回考えさせる — 構造で省略させない | v1から**修正** | 弱LLMテンプレ実証(GPT 0%→100%、修行§24-25)は生存。07-24全量テスト事故=考える工程の省略が事故を生むと実証(knowledge:2f977ef7) |
| P2 | 会話・作業の1単位=学習の1単位 | 生存 | retro機構E4(self_retro台帳)でターン単位RCAまで拡張済み |
| P3 | 生産と消費の均衡を計測し在庫超過を自動タスク化 | 生存 | reflux自動配備が稼働。ただし計器バグで在庫値が虚偽だった(穴12) |
| P4 | 正本はCLI非依存層(script+YAML+SQLite) | 生存 | Claude/Codex混成運用実績 |
| P5 | ループを計測するループ(メタループ) | 生存・対象拡大 | v3では**ループ機構自身**が計測対象(T11) |
| P6 | 移植=コピーでなくbootstrap | 生存(温め) | portable-learning-loop-core.md |
| P7 | **削るな、速くしろ** — LLMは必須/過剰を選別できない。成長=品質2原則(正本突合判定+境界fixture)維持のまま超速化。遅いgate/hook=インフラバグ | **v3新設** | 07-20削除sweep→必須まで削除し能力急落→rollback b3f2f56d0(LS099)→07-21裁定(knowledge:569abc55)。削除ゼロで-47%〜-99.3%実証(§3.3) |
| P8 | **考える工程は毎回考えさせ、機械的工程は自動化する** — 一見効率が悪い表示型の強制が必須な領域がある | **v3新設** | 殿裁定07-24(knowledge:2f977ef7+c4ee37b5、growth-loop§1.5)。P1の適用境界を定める |
| P9 | **計器も一次情報で検証** — 台帳・指標の定義をコード現物と突合してから結論する。台帳出力は二次情報 | **v3新設** | 穴12: 将軍がloop_ledger出力だけで「生成≧消費」と誤結論→家老がコード現物(stock=produced恒等)で訂正(blt_145051) |
| P10 | **有限資源にretentionを設計時に組み込む** — 一発限りのsentinel/flag/scratch/ログは生成時に保持期限を宣言 | **v3新設** | 穴13: queue 125,527ファイルで走査コスト比例劣化、配備wall 3倍化実測(blt_151058) |

**原理の転回史(三層因果で固定)**: v1暗黙前提「防御は増やすほど良い」→07-20「表示型=削る対象」(誤)→削除sweepで能力急落→07-21再訂正「削るな速くしろ」→07-24「表示型強制必須(考える工程)」→**v3: 品質×速度の両輪**。経緯の正本=campaign-lane v6(gist fb70493e)+growth-loop.md v2。

## §3 AS-IS（2026-07-25 一次計測）

### §3.1 資産規模（v1比較列は歴史参照）

| 資産 | v1(07-07) | **v3(07-25実測)** |
|------|-----------|------------------|
| gates | 48本 | 55本 |
| scripts | 184本 | 228本 |
| hooks | 41本 | 43本 |
| skills | 34個 | 36個 |
| 記憶DB events | 117,590件 | **225,481件**(1.92倍/18日) |
| queue/ | 未計測 | **125,527ファイル・9.4GB**(§3.4穴13) |
| logs/ | 未計測 | 276MB・6,830ファイル(ローテーション不在) |

### §3.2 回っている数値（維持対象・07-25時点）

| 指標 | 値 | 出典 |
|------|-----|------|
| 教訓効果率(直近10cmd) | 100% (24/24) | gate_lesson_health 07-25 |
| semantic在庫 | 0 (produced 74/consumed 74=完全消化) | loop_ledger 07-25 |
| lesson在庫回転 | 49 (289/250、消費継続中) | loop_ledger 07-25 |
| insight在庫回転 | 26 (最古23.3h) | loop_ledger 07-25 |
| memory useful_rate | 48.8% (494/1,013評価) | loop_ledger 07-25 |
| [MEM]引用 | citation 1,203 / search 19,542(分母計測は健全) | loop_ledger 07-25 |

### §3.3 速度実績（「削るな速くしろ」以後。台帳=defense_overhead.jsonl。削除ゼロで達成=P7実証）

| 対象 | 前→後 | 削減 |
|------|-------|------|
| deploy総 | 67.3→35.8秒 | -47% |
| admission(affected=0即return) | 248.66→1.81秒 | -99.3% (e705691df) |
| related_lessons(DB全量snapshot廃止) | 37.77→0.57秒 | -98.5% (916c0dba5) |
| cmd_save表示型9件cut | 24.2→2.12秒 | -91% |

### §3.4 詰まっている数値（TO-BEの標的。07-25 RCA協働で接地）

| # | 指標/事象 | 実測値 | 穴 |
|---|----------|--------|-----|
| 1 | promotion在庫 | 185(消費しても減らない**計器バグ**: stock=produced恒等+literal\t 139行27.1%不可視) | 穴12 |
| 2 | queue/ファイル数 | 125,527件。find 35.6秒。campaign_lane pruneでも-4.5秒のみ=58%が保持期限なきsentinel/flag(gates 28,138+archive 26,760+ntfy 5,648最古50日+locks 4,252) | 穴13 |
| 3 | post-CLEARパイプライン | insight triage 1件BLOCKで後続全停止(通知/dashboard/idle戻し)。cmd_4171実証 | 穴14 |
| 4 | loop_ledger_update | 33.2秒/回(台帳YAML 6.8MB全parse) | 穴15 |
| 5 | cmd_save/three_layer_ruling_overhead | median 8.4秒/max 32.2秒(n=13)=cmd_save新支配項 | 穴15 |
| 6 | gunshi report precheck | median 4.8秒/max 50.4秒(コールドパス支配) | 穴15 |
| 7 | deploy_total テール | median 1.1秒だがmax 65.3秒(n=287)。ファイル数比例のpreflight走査コストが有力(家老計測: 配備wall 141.6秒=3倍化) | 穴13×15 |
| 8 | 再帰grep/du(logs+queue) | 120秒TIMEOUT実測(将軍RCA) | 穴13 |
| 9 | 教訓useful率(直近10cmd) | 12.5%(1/8)に悪化 | 是正済cmd_4152/4172、効果は次窓計測 |
| 10 | preflight証跡のターン中失効 | BLOCK→手動issue往復1回/ターン実測 | 穴15 |

**未再計測(前回値のみ。次回startup gate/週次で更新)**: NO_MATCH率(v2時90.0%※計測窓変化)、教訓活用率(v1時26%)、洗脳自己検出率(v2時38.5%)、enforcement_level分布(v2時L4+ 37.8%)。

### §3.5 穴の台帳（穴1-15統合。v1/v2発見分は現状ステータス付き）

| # | 穴 | 発見 | 07-25状態 |
|---|-----|------|----------|
| 1 | 入口が失敗偏重 | v1 | **塞込済**(T1会話単位学習+retro機構E4) |
| 2 | 還流が手動依存 | v1 | **塞込済**(T2 reflux自動配備。semantic在庫0が証拠) |
| 3 | 検索到達率が低い | v1 | 稼働中(T3自動alias。NO_MATCH率は要再計測) |
| 4 | プロトコルが知能依存 | v1 | 稼働中(T5モデル階層プロファイル配備済み) |
| 5 | 教訓が長文自然言語 | v1 | 稼働中(T4 enforcement_level+書込時付与) |
| 6 | 可搬性未設計 | v1 | 温め(T6 bootstrap実装済み・展開待ち) |
| 7 | ループ統合計測がない | v1 | **塞込済**(T7 loop_ledger)→ただし穴12で計器自体に欠陥 |
| 8 | 検出器のsilent-death | v2 | 塞込済(timeout復元+DIGEST ci常時表示+LS081) |
| 9 | 虚偽resolve | v2 | 塞込済(cmd_3729現物突合) |
| 10 | 二次記憶の鮮度 | v2 | 稼働中(compact_state+強くてニューゲーム復帰点運用) |
| 11 | 正本YAML破損の事後検出 | v2 | 稼働中(yaml_field_set+pre-bash guard) |
| 12 | **計器自体の指標欠陥** — stock=produced恒等/ledger間定義不統一/literal\t不可視 | **v3(07-25)** | hotfix2件配備済み(stock定義是正+printf根治)。contract test化=T8 |
| 13 | **保持期限なきsentinel/flag累積** — ファイル数が走査時間の支配項 | **v3(07-25)** | campaign_lane GC(9.1GB)配備中+retention実装次弾=T9 |
| 14 | **post-CLEAR直列パイプラインの連鎖BLOCK** — fail-open分離不在 | **v3(07-25)** | 是正方針承認済み・配備待ち=T10 |
| 15 | **ループ機構自身が律速** — 台帳33秒/cmd_save三層8.4秒/preflight失効往復 | **v3(07-25)** | 高速化レーン稼働中=T11 |

## §4 TO-BE施策（T1-T11統合。T1-T7はv1設計→全実装済み、T8-T11がv3新設）

| # | 施策 | 塞ぐ穴 | 状態(07-25) | 計測指標 |
|---|------|--------|------------|---------|
| T1 | 会話単位学習ループ | 穴1 | **稼働中**(cmd_3722+retro E4拡張) | 殿指摘→教訓登録リードタイム |
| T2 | 還流在庫の自動消化 | 穴2 | **稼働中**(cmd_3721。semantic在庫0実証) | 在庫件数・滞留時間 |
| T3 | 検索到達率の自動改善 | 穴3 | 稼働中(cmd_3718) | NO_MATCH率(要再計測) |
| T4 | 教訓→構造変換率の計測と昇格 | 穴5 | 稼働中(cmd_3724/3731書込時付与) | enforcement_level分布 |
| T5 | 弱LLM構造化プロトコル | 穴4 | 稼働中(cmd_3727 model-aware injection) | モデル別初回PASS率 |
| T6 | ポータブルコア | 穴6 | 実装済み・展開待ち(cmd_3728) | 新PJ導入時間 |
| T7 | ループ台帳(メタループ) | 穴7 | 稼働中(cmd_3719-3720+aging軸) | ループ別サイクルタイム |
| T8 | **計器契約検証**: 台帳指標定義(stock=produced-consumed等)のcontract test化+ledger間定義統一 | 穴12 | hotfix配備済み(cmd_karo_hotfix_loop_ledger_stock/gate_metrics_literal_tab)。contract test=次弾 | 指標定義とコード現物の突合PASS |
| T9 | **retention/GC**: campaign scratch GC+sentinel/lock/flag保持期限(完了+archive済みcmdのみ・稼働中保護・削除ルール準拠) | 穴13 | 飛猿GC配備中+retention次弾 | queue/ファイル数・find秒数前後差分 |
| T10 | **post-CLEAR fail-open分離**: 各ステップ独立実行+失敗隔離+triage BLOCK根治 | 穴14 | 方針承認済み・忍者空き次第配備 | post-CLEAR完走率・idle戻し欠落0 |
| T11 | **ループ機構の速度台帳化**: 機構自身をdefense_overhead.jsonl単一台帳で計測→支配項逆引き→高速化→同一台帳で前後証明 | 穴15 | **稼働中**(§3.3実績。次弾=cmd_save三層8.4s/loop_ledger 33s/q11_semantic 19.5s/completion_pipeline/review_notify配備中) | 同一台帳source別median/max |

## §5 運用形（v3で確立した型）

### §5.1 台帳駆動高速化の3手順（殿裁定 2026-07-25）
```
①支配項を台帳(defense_overhead.jsonl)から逆引き
→ ②品質2原則(正本突合判定+境界fixture両方)を維持したまま高速化
→ ③同一台帳で前後差分を証明
```
新台帳を作らない(車輪の再発明防止=提案前grep。knowledge:fbb5716c)。

### §5.2 RCA協働の型（2026-07-25 に1日で3周実証）
```
殿「覚醒して調査せよ」→ 将軍: 台帳集計+実測で仮説 → 家老: 一次計測で検証
→ 誤りは同日訂正して台帳CORRECTED記録 → 正しい真因に忍者配備 → 前後差分を同一台帳で証明
```
実証: 将軍仮説2件が家老の一次計測で訂正(campaign_lane≠走査律速/promotion≠投入不足)、軍師の一次確認が家老の二重実装を1件阻止(idle戻し機構は既存だった)。**誤り訂正コストが同日内・台帳1行に圧縮された** = 「求めるのは正しい報告ではなく正しい結果」の実装。

### §5.3 弱LLM・可搬（v1 §6の運用規則。内容不変のため要点のみ）
- Tier 0(記録層)→1(+gate)→2(+記憶DB/semantic/台帳)の段階導入
- 正本=script+YAML+SQLite。hookは早期検出のみ(無くてもgateが守る二重化)
- モデル階層プロファイル: 弱LLM=フルテンプレ+実例+bcヒント、強LLM=標準(判断はスクリプト)

## §6 計測計画（baseline固定 2026-07-25）

| 指標 | v3 baseline | 再計測 |
|------|------------|--------|
| deploy総/admission/related_lessons | 35.8s/1.81s/0.57s | 変更の度(同一台帳) |
| cmd_save three_layer overhead | median 8.4s | T11次弾後 |
| loop_ledger_update | 33.2s | T11次弾後 |
| queue/ファイル数 | 125,527 | T9前後 |
| promotion在庫(是正後定義) | 計器修正後に初計測 | T8後、startup毎 |
| post-CLEAR完走率 | 計測なし(穴14) | T10後 |
| 教訓useful率(10cmd窓) | 12.5% | cmd_4152/4172効果を次窓 |
| NO_MATCH率/活用率/洗脳検出率/enforcement分布 | 前回値(§3.4末尾) | 次回startup/週次 |

合格点は設けない(LS-A04(33))。「毎計測で改善が続く」構造二値+実測値報告で運用。

## §7 履歴（時系列ナビゲーション）

| 版 | 日付 | 内容 | 所在 |
|----|------|------|------|
| v1 | 2026-07-07 | 極限化設計(§0-§9): 穴1-7+T1-T7+原理P1-P6。当日全実装 | `three-layer-learning-loop-auto-growth-v2-archive_20260708.md` §0-§9 |
| v2-v2.2 | 2026-07-07〜08 | 実装実証+穴8-11+免疫サイクル5周+待機許可根絶W1-W6 | 同アーカイブ §10 |
| (転回期) | 2026-07-20〜24 | 削除軸の誤り→rollback→削るな速くしろ→表示型強制必須 | campaign-lane v6(gist fb70493e)+growth-loop.md v2+LS099 |
| **v3.0** | **2026-07-25** | **本書。品質×速度の両輪へ全面書き直し。P7-P10+穴12-15+T8-T11+運用形** | 本ファイル |

## 因果リンク

- ← [[deepdive_why_chain_20260321]] Phase 4-5知性の外部化+Phase 9生産消費分離=P1-P3の理論的根拠
- ← [[growth-loop]] v2: 防御階層+転回の経緯=P7-P8の土台
- ← [[殿裁定_削るな速くしろ_20260721]] P7正本(knowledge:569abc55)
- ← [[殿裁定_表示型強制必須_20260724]] P8正本(knowledge:2f977ef7)
- ← [[campaign-lane_v6]] 両輪エンジン(gist fb70493e)=P7-P8のレーン実装
- ← [[training-cycle]] §24-25モデル別FP率=P1(修正版)の定量実証
- ← [[three-layer-learning-loop-auto-growth-v2-archive_20260708]] v1/v2全文保全(baseline歴史)
- → [[defense_overhead.jsonl]] T11単一台帳(source:shogun_rca :1-:13=07-25 RCA全証跡)
- → [[cmd_karo_hotfix_loop_ledger_stock_metric_20260725]] 穴12是正 / [[cmd_karo_speed_completion_pipeline_20260725]] 穴14起点
- → [[LS099]][[LS081]] 削除軸の誤り+検出器silent-deathの教訓化
- → [[portable-learning-loop-core]] T6可搬コア / [[three-layer-memory-utilization-acceleration-asis-tobe-5w1h_20260707]] 想起側姉妹編
