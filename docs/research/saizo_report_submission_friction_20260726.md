# 報告提出経路の所要時間分析（才蔵・2026-07-26）

対象: `cmd_karo_recon_pending_decisions_triage_20260726`（recon2・コード変更0件）
目的: 殿指示による「時間がかかった原因」の分析と、インフラバグ疑いの列挙。

## §1 実測（一次データ）

| 区間 | 時刻 | 所要 | 比率 |
|---|---|---|---|
| 配備→調査完了 | 11:41:55 → 11:46:51 | 4分56秒 | 41% |
| 報告記入→送信成功 | 11:46:51 → 11:53:57 | 7分06秒 | **59%** |
| 合計 | | 12分02秒 | (見積15分内) |

出典: task YAML `deployed_at` / 報告YAML `timestamp` / inbox `msg_20260726_115357_2971400_17955501`。

**★調査より提出の方が長い。** 総時間は見積内であり「遅い」とは言えないが、**内訳が逆転している**ことが問題である。調査対象は27件のPD全件・hook現物・gate実走・git log を含み、提出は1ファイルへの記入のみである。

## §2 提出時にBLOCKされた6箇所（すべて再現条件付き）

| # | 事象 | 実体 | 分類 |
|---|---|---|---|
| B1 | `commit_hash=no-code-change` が2回BLOCK | エラーメッセージが**必要条件を1つも名指ししない** | メッセージ欠落 |
| B2 | `assumption_invalidation.found=true` がBLOCK | 同一バッチ内で `detail` を後に指定したため。**フィールド順依存** | 順序依存 |
| B3 | `binary_checks.<AC>` へのリスト書込みで**check文が黙って破棄** | GP-053保護。ただし `binary_checks.commit.0.check` の**添字経路では書込み可能** | 強制の不整合 |
| B4 | `status=completed` 後に `origin`/`test_results` を追記できない | gateのWARNで初めて不足を知るが、その時点で不変性が発動 | 順序の罠 |
| B5 | `report_received` が送信不能 | `binary_checks` に no が1件あると**報告経路が全封鎖**される | 経路封鎖 |
| B6 | `task_failed` 送信に task status ∈ failed\|blocked が必要 | 作業は完遂しているのに `blocked` と記す以外に語彙がない | 語彙の欠落 |

### B1 の詳細（最も直しやすい）
`valid_commit_identity`（`scripts/lib/report_commit_identity.py:92`）は `no-code-change` に対し**3条件すべて**を要求する:
1. `no_code_change_evidence.tree_unchanged=true` かつ `before_tree`=`after_tree`=40hex（L80-89）
2. `explicit_no_commit`（`commit_contract.required=false` または commit checkの否定表明・L23-38）
3. `operational_files_only`（`files_modified` が非空、かつ `queue/`・`logs/`・git-ignored `projects/` のみ・L57-76）

しかし `scripts/report_field_set.sh:1131-1133` のメッセージは
「40文字フルhex、または明示no-commitかつqueue/logsのみのno-code-change必須」としか言わず、
**`no_code_change_evidence` という語も `files_modified` 必須も現れない。** ∴利用者は総当たりで探す以外にない（拙者は2回失敗した）。

## §3 ★本命のインフラバグ疑い — 単一キー経路に計装が無い

`scripts/report_field_set.sh` の telemetry は **バッチ経路のみ**（L297-315 `defense_overhead_write_batch_async`）。
`logs/defense_overhead.jsonl` の source 集計に `report_field_set` は**1件も存在しない**（存在するのは `gate_report_format` 1748 / `report_publish` 2212 / `gate_gunshi_report_precheck` 1605）。

一方、報告テンプレートが忍者へ教える書式は `$RFS <key> <value>` すなわち**単一キー経路**である。

∴ **全忍者が最も多く通る経路の所要時間とBLOCK回数が、台帳に一切残らない。**
拙者の本日の約25回の呼出し（うちBLOCK 4回）は defense_overhead に0件として記録されている。

★これは本偵察で PD-116〜133 について下したのと**同一の診断**である —
「待てば貯まる欠測」ではなく「**永久に貯まらない計装の不在**」。待っても改善データは貯まらない。

**帰結**: 「報告提出が調査より長い」という本稿の主張は、拙者1件の手計測でしか示せない。
台帳があれば全忍者・全弾で即座に示せる。速度改善レーンが `deploy` / `cmd_save` を計測して -89% / -99% を出せたのは計装があったからであり、提出経路にはその入口が無い。

## §4 提案（Level5 方向・実装は別弾）

| 対象 | 提案 | 効果 |
|---|---|---|
| `scripts/report_field_set.sh` L297-315 | 単一キー経路にも `defense_overhead_write_batch_async` を通す（source=`report_field_set`, check_id=dot_key, verdict=PASS/BLOCK） | 提出コストが可視化され、以降の是正が数値で回る |
| 同 L1131-1133 | BLOCKメッセージに**不足している条件だけ**を名指しさせる（evidence欠落／files_modified欠落／explicit_no_commit欠落を判定して出し分け） | B1の総当たりが消える |
| 同 L2288-2306 | 保護の一貫化。添字経路 `binary_checks.*.N.check` でも同じ保護を掛けるか、逆に**否定表明への書換えを正規手順として明文化** | B3の抜け穴と手戻りが消える |
| 同 不変性チェック | `status=completed` を受けた時点で gate のWARN項目（`origin`/`test_results`）を**先に**検査し、不足なら completed を拒否 | B4の `revision_requested` 往復が消える |
| `gate_report_format` 差戻し | `binary_checks` の no が**AC本文の事実誤りに対する no** の場合の経路を用意する（現状は全報告経路が封鎖される） | B5・B6。緊急度最上位の情報が最も遅く届く非対称の解消 |

## §5 誤った疑いの棄却（自己反証）

- 「`git write-tree` が空を返した」→ 一時的事象。再実行で正常（`fd3e3e96…`）。`.git/index.lock` も不在。**共有ツリー競合を疑ったが証拠なし。棄却する。**
- 「no-code-change の evidence 欠落報告が4件ある（kotaro）」→ いずれも 07-16〜07-18 07:04 の作成で、契約導入 `ab5d5f2a5`(07-18 09:05) より**前**。契約違反ではない。**棄却する。**

## §6 因果

origin: `[[殿指示_所要時間分析_20260726]] -> [[報告提出経路の単一キー計装不在]] -> [[提出59%が不可視のまま個別BLOCKで消費]]`
関連: `[[cmd_karo_recon_pending_decisions_triage_20260726]]`（同型診断=永久に貯まらない計装の不在）
