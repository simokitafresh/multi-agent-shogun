# 本番再計算の非決定性根治 — AS-IS / TO-BE 5W1H

作成: 2026-07-11 将軍 | 源流: cmd_3827 FAIL → cmd_3840偵察設計(GATE CLEAR 2026-07-10 23:03)
正本設計書: DM-signal `docs/research/cmd_3840_nondeterminism_redesign.md`

---

## 0. 一言でいうと

**「同じデータで再計算したのに、シグナルが前回と違う」問題**の根治計画。
調べた結果、**計算コード自体は決定的**（同一入力なら5,000行×2回で差分ゼロ）だった。
真の問題は2つ:
1. **計算経路が2本ある**こと（PipelineEngineと、高速化用の手書きvectorized経路）。2本は独立実装なので、修正のたびに乖離し得る
2. **「同じ入力」を保証する仕組みがない**こと。run中に価格・config・ledgerが動くと、そもそも前回と入力が違うのに「非決定だ」と見えてしまう

おまけに、調査を妨げていた「基準生成が30秒でも終わらない」問題は計算ではなく、**日次ループ内でgit rev-parseを238回subprocess起動していた**のが主因（35.2秒中21.2秒=60%）。

---

## 1. AS-IS（現状）

| 項目 | 現状 |
|---|---|
| 計算経路 | **2本並存**。日次のPipelineEngine（正、決定的と実証済み）と、fullrecalculate高速化用の`_compute_pipeline_signals()`（recalculate_fast.py内の独立vectorized実装） |
| 非決定性の実態 | 単一プロセス・同一入力の反復では**差分ゼロ**（semantic hash完全一致）。set順序もDTB3 bisectも決定的と個別に検証済み |
| 残る発生条件 | run間で入力が動く: 価格/DTB3の更新、PF config変更、commit差、ledger生成時点差。**入力を固定・記録する仕組み（manifest）がないため、差が出ても「計算が悪いのか入力が違うのか」を区別できない** |
| 調査を阻んだバグ | 日次ループが月初snapshotごとに`_get_git_commit_hash()`→`git rev-parse` subprocessを238回起動。Stage A 35.21秒中21.17秒(60.1%)。vectorized計算本体は0.20秒(0.6%) |
| 防御 | ledger guard（DRIFT BLOCK）は正常動作。DRIFT 8,729件検知時もsignals実書込みゼロ=本番データは守られている |
| 被害 | cmd_3827（ledger再構築検証）がこの構造のせいで原因特定できずFAIL。再計算のたびに「本当に同じか」を人手で疑う運用コスト |

## 2. TO-BE（あるべき姿）

| 項目 | あるべき姿 |
|---|---|
| 計算経路 | **意味論は1本**。PipelineEngineのblock意味論を純粋関数の共通executorに抽出し、日次Engineもvectorized batchも**同じ実装を呼ぶ**。独立`_compute_pipeline_signals()`は廃止 |
| 入力の固定 | run開始時に**入力manifest**（commit hash・PF config hash・price/DTB3のwatermark+件数・ledger時点）を1つ固定して記録。以後の比較はmanifest一致が前提。並行更新を検知したらfail-closed |
| 速度 | 現行の高速性を維持（git hash定数化込みでStage A 35.2s→warm約3.9s）。全日付Engine逐日呼び出し（約2,000秒）へは退行させない |
| 検証 | 全PF×全日付でEngine対vectorizedの**signal+weights完全一致のdifferential test**を常設。Stage A 30秒のperformance regression testも常設 |
| 防御 | ledger guardは維持・緩めない。drift検知時はmanifest差分を必ず添付（「入力が違った」のか「計算が違った」のかが即座に分かる） |

## 3. 5W1H

| | 内容 |
|---|---|
| **Why（なぜ）** | 再計算の信頼性はDM-Signal全機能の土台。二重実装は「修正のたびに乖離リスク」を永久に抱え、入力固定がないと検証のたびに原因切り分けから始まる。cmd_3827 FAILで実害が顕在化した |
| **What（何を）** | 二段構え。**hotfix（案2）**: git hash呼び出しのrun固定値化+入力manifest固定=30秒timeout即解消+比較可能性の確保。**本体（案1）**: block意味論の共通executor化+vectorized adapter接続=二重実装の廃止 |
| **When（いつ）** | hotfixは裁可後すぐ（最小変更）。本体はhotfix+differential testのRED化を先行させてから着手（依存順: manifest/計測修正→differential test先にRED→共通executor→全PF parity→fullrecalculate実測） |
| **Where（どこを）** | `recalculate_fast.py`（git hash箇所+vectorized経路）、`services/pipeline/engine.py`（意味論抽出元）、`backend/tests/`（differential+regression）。ledger guard（signal_flush.py）は不変。**本番DB変更はゼロ** |
| **Who（誰が）** | 忍者1名ずつ（hotfix→本体の直列cmd）。設計は確定済み（cmd_3840設計書）なので実装に専念できる |
| **How（どう）** | 案1採用（採用順位1位）。案2はhotfixとして先行併用。案3（全日付Engine逐日委譲、約2,000秒へ退行）は速度SLO違反のため本番不採用、正しさのoracle（回帰比較の基準）としてのみ使用 |

## 4. 案の比較（cmd_3840設計書 §4より）

| 順位 | 案 | 速度 | リスク | 判定 |
|---|---|---|---|---|
| 1 | 共通executor+vectorized adapter | 現行維持（warm約3.9s） | 中（共通契約の設計が必要） | **採用** |
| 2 | 独立経路のまま決定化+manifest固定 | 現行維持 | 高（二重実装が残り将来再乖離） | hotfixとして先行のみ |
| 3 | 全日付Engine逐日委譲 | 約2,000秒へ退行 | 低〜中 | oracle限定 |

## 5. これで何が変わるか（殿の体験）

- fullrecalculateやledger検証で「前回と違う」が出たら、**manifest差分を見るだけで「入力が動いた」か「バグ」かが即断できる**
- シグナル計算のロジック修正は1箇所直せば日次もbatchも揃う。「片方だけ直って片方が古い」事故が構造的に消える
- 再計算検証系のcmd（cmd_3827のような）が、入力固定の上で再現可能な実験になる

## 6. 因果

`[[cmd_3827_FAIL]] -> [[Stage_A計測汚染=git_hash_subprocess238回]] + [[入力manifest不在で比較不能]] + [[二重実装の乖離リスク]] -> [[hotfix先行+共通executor単一意味論化]]`
