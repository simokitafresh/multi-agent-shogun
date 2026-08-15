<!-- gist-master: 70e96c6901a18a0a8211184a00037907 dm-speed-line-timeline_20260815.md -->
# DM-Signal 速度レーン 時系列（08-10 〜 08-15）

**用途: 現在地を再導出しないための正本。判断の前にここを読む。**

| 日時(JST) | 出来事 | 一次根拠 |
|---|---|---|
| 08-10 11:01 | **cmd_4287 γ5 cutover + ledger再基線**（殿裁可） | memory_db `cmd_save:cmd_4287` |
| 08-10 02:22Z | この時点で ledger=15212行（不変manifest） | 家老 blt_20260815_105849 |
| 08-12 11:12 | cache一本化 T0/T1/T2/T3/T3.5/T4.5/T7.5/B4 完了。run296順序違反でSTOP、「fullはT6完了まで禁止」 | knowledge:89be3636 |
| 08-12 12:52-12:55 | **殿裁定: 旧値比較・signal_change_log・ALERT・ntfyの撤去GO** | §0-7 |
| 08-12 18:07 | **殿下知: 優先=fullで全量バグ露出→完全正常化→正常化後のみ速度改善**（前項の「full禁止」を上書き） | §0-1 |
| 08-12 19:58 | **殿裁定: バグを含む現本番値とのparityを完了基準にするな** | §0-6b |
| 08-12 23:20 | run316(full) → L2 102/102・L3 78/78 成功、**L5のみ failed**。修正730f3632 Live、L5終端検証は未実行 | 追補v2.35 |
| 08-13 01:52 | **rollback `233c2303`（tree=21e80e30復元、185ファイル/-34589行）** → 08-12に撤去したALERTが**復活**（現mainに生存） | git log / rg |
| 08-13 | RB6独立oracle構築。保存値が無く一から再実装が必要 → **provenanceを実装する動機が発生** | provenance設計書§1 Why |
| 08-14 03:53 | **RB6 完全CLEAR = 正常化完了。月次33748/33748 + metrics30240/30240 exact・本番バグゼロ** | knowledge:cb56743d / 8bc2da6a |
| 08-14 11:21 | **SIGNAL CHANGE ALERT 8626件/40PF の RCA確定・GATE CLEAR**。writer=L3 sync-fof cronの**正規**月次再展開。mismatch0・raw_eq_new=8626・**実害なし**。残論点=sync_fofはrecalculation_status行を残さず、確定月がcron経路でledger凍結を素通りする構造 | knowledge:02d2736d |
| 08-14 14:29 | RB8 = cmd_4301 GATE CLEAR。復帰点=rollback計画書v1.8 §-1 | knowledge:3bfce02b |
| 08-14 15:40 | **殿P0裁定 → provenance実装開始**（§0-1の「正常化後」条件はRB6で成立済み） | 同上 |
| 08-14 中 | P0/P0.4/P0.5/P0.6/P0.7/P1a/P1b/P2a/P2b/P3a/P3b 完了 | 同上 |
| 08-15 01:22 | P0.9 GATE CLEAR・本番live | 掲示板 |
| 08-15 01:43 | **P4 CLEAR**（run401、月次16874/metrics102がrun364と完全一致） | 進捗台帳 |
| 08-15 05:11 | **cmd_4312 live**（§4.5-2 expanded_weights再利用）— fingerprintによる入力不変の証明**なし**で保存値を計算入力へ昇格 | commit d452000f/c90e97b1 |
| 08-15 08:13 | cmd_4314/4316/4317 deploy 後、false側 full run403 | 家老報告 |
| 08-15 08:24 | **確定月38120件/50PF変化を検知。monthly 14718行・metrics102件が基準から乖離** | signal_change_log |
| 08-15 08:27-08:29 | 家老が4314/16/17→4312の順にrevert。main=`5da7f107`（cmd_4312導入前treeと完全同一） | git |
| 08-15 09:20 | **run404で復旧CLEAR**。基準run364と cmp_rc=0（所要475秒） | 家老報告 |
| 08-15 10:44 | 日次 sync-fof cron が確定月8761件/38PFを再展開 → **08-14 11:21のRCAと同一現象** | signal_change_log |
| 08-15 11:23 | cmd_4320: 保存値と再展開値の突合 15768組中 **不一致813**（ticker集合731/weight64/legacy空18） | cmd_4320成果物 |
| 08-15 12:28 | cmd_4321: 分岐段=nested FoFの子選択層。795件は再展開が規則に沿い、**18件は保存値が正**（規則1違反） | cmd_4321成果物 |

## 未着手・未完（進捗の正=補填設計書§10.1）

- **T3.6 / T4（L5 builder cache供給＝L1〜L5貫通の本体）/ T5 / T6** = 🔶部分完了
- **T7** = 🔶 run314の28 WARNINGで停止
- **T8** = ⬜未着手
- **P7（fingerprint skip＝速度の本体）** = 未達（実装はcmd_4314/4316にあったがrevert済み）
- run316のL5終端検証（canary→全件）= 未実行

## 確定している前提（再導出禁止）

1. **正常化は 08-14 03:53 のRB6完全CLEARで完了している。本番バグゼロ。**
2. **∴速度改善は解禁済み。** provenance実装（08-14 15:40 P0裁定）は §0-1 に適合する。
3. **日次cronによる確定月再展開は 08-14 11:21 にRCA確定・実害なし。** 新規事象ではない。
4. **ALERTは08-12に撤去裁定済みだが、08-13のrollbackで復活し現存する。** これは未処理。
