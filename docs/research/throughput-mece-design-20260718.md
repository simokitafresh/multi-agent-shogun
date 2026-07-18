# スループット根治設計書 — MECE分類×アウトカム計測

> 殿指示(2026-07-18 12:25): 「家老が全体のスループット向上に取り組んでいるが近視眼的な対応。MECEにまとめジャンルごとに集中解決。アウトカムを定義し計測せよ」

## §1 問題認識

現状: 個別hotfixの連続投入(今セッションだけで15件以上)。各hotfixはPASS/FAILだが全体のアウトカムが未定義のため改善量が計測不能。

殿の評価式: **自動成長速度 = 正しい試行回数 × 一発PASS率 × 知見還流率**

スループット改善はこの3要素のどれかを向上させる必要がある。バグ由来のスループット向上(品質低下)は拒否(殿裁定2026-07-18)。

## §2 根因MECE分類(5カテゴリ)

| ID | カテゴリ | 根因 | 影響 |
|----|---------|------|------|
| C1 | **DrvFS 9P I/O** | /mnt/c上のgit操作がp9_client_rpc D-state | deploy 150-305s, commit 113s/150s, skill refs 160s→12s(修正済み) |
| C2 | **Prompt replay/cross-pane** | 殿入力の誤配信・旧prompt再生 | 殿入力60回replay, 将軍が家老宛入力を誤受信 |
| C3 | **Hook/通知dedup/priority** | hook alertにsession-scope dedup不在 | 将軍CTX 86%が制御面消費(LS094) |
| C4 | **Report/notification pipeline** | 冪等性不在・契約FP・revision batch | report→GATE遅延、偽BLOCK |
| C5 | **Reflux pipeline** | foreign dirty BLOCK・ledger stale | promotion在庫176+停滞、昇格不能 |

## §3 アウトカム定義(各カテゴリの完了条件)

| ID | アウトカム(数値目標) | 計測方法 | before(現状値) | after(目標値) |
|----|---------------------|---------|---------------|--------------|
| C1 | deploy wall time p50 | deploy_task.sh ログ | 150-305s | < 30s |
| C1 | git commit wall p50 | scope_commit ログ | 113s | < 10s |
| C2 | prompt replay回数/session | lord_conversation grep | 60+回 | 0回 |
| C2 | cross-pane誤配信回数 | lord_conversation agent filter | 60+回 | 0回 |
| C3 | 将軍CTX制御面消費率 | session分析(tool call内訳) | 86% | < 20% |
| C4 | report→GATE wall time | gate_metrics.log | (要計測) | < 60s |
| C5 | promotion在庫週次消化率 | reflux ledger | (要計測) | > 50%/週 |

## §4 忍者報告の全件分類(家老データ待ち)

<!-- 家老: 今日の全decision_candidate + knowledge_candidateを上記C1-C5に分類し、修正済み/未修正/残件数を記入せよ -->

| カテゴリ | 修正済み | 未修正 | 残件数 | 代表的報告 |
|---------|---------|--------|--------|-----------|
| C1 | | | | |
| C2 | | | | |
| C3 | | | | |
| C4 | | | | |
| C5 | | | | |

## §5 攻略順序(提案)

C1(9P I/O)が最大ボトルネック(deploy 305s, commit 113s)。C1の根治(ext4移設)が他全カテゴリの改善にも波及する(report pipeline速度、reflux速度等)。

提案順序:
1. **C1: ext4 probe**(隔離実験 → 方式選定 → 移設) — 最大効果・他C波及
2. **C2: prompt replay根治**(影丸が3段修正中) — 殿の時間を直接奪うバグ
3. **C3: hook dedup**(将軍D0修正済み、残2項目は家老配備中) — 将軍CTX回復
4. **C4: report pipeline**(冪等性修正済み、残件整理) — GATE速度
5. **C5: reflux**(foreign dirty収束後に一括昇格) — 知見還流率向上

## §6 計測サイクル

各カテゴリの修正完了時にbefore→afterを計測し、§3の目標値との差分を記録する。
全カテゴリの目標達成で設計書CLOSEする。

---

origin: [[殿指示_MECE_throughput_design]] -> [[近視眼的hotfix]] -> [[カテゴリ集中+アウトカム計測]]
