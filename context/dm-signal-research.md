# DM-signal 研究コンテキスト
<!-- last_updated: 2026-08-29 T189 outputs 整理 追補(DOC_LANE_REQUEST blt_184928) -->
<!-- source_commit:da3470694ad7 reason:T189 outputs 整理 追補(DOC_LANE_REQUEST blt_184928) evidence:git -C /mnt/c/Python_app/DM-signal show --stat da3470694ad7 -->
<!-- source_commit:dbfe34dd935b reason:T189 outputs 整理(cmd_karo_t189_outputs_cleanup_20260829、殿裁定 16:51/16:53/16:56) evidence:git -C /mnt/c/Python_app/DM-signal show --stat dbfe34dd935b -->
<!-- source_commit:d87339a4 reason:T05 shogun doc lane reviewed source boundary (2026-08-26) evidence:git -C /mnt/c/Python_app/DM-signal log <marker>..origin/main: core/ops=研究系(cmd_4372-4376)+記事のみ・core/ops知識変更なし; research=cmd_4372/4374/4376は末尾§へ反映済; frontend=frontend/配下変更は08-17 cmd_4324-4333のみで§28反映済、残りはbackend(ops§100反映済)/記事/研究。ローカルcloneはoriginと履歴分岐(同subject別hash)のためorigin/main tipを境界にする -->
<!-- source_commit:45760ecf reason:GA-490/491 research境界更新(退行復旧再適用) evidence:git -C /mnt/c/Python_app/DM-signal log b24d6b5f..45760ecf -- docs/research analysis outputs marketing-director = 14件。内容=cmd_4355/4356成果保存(07848c94)+note記事群(決定的tie-break一般論・投資家スクリーニング)+週報2026-08-18+reconcile merge revert。研究結論の変更なし、境界のみ更新。初回=877a73ef1、tree退行検出により再適用 -->
<!-- dm_signal_research_reflux: fingerprint=4383100f3b182a5113a582998b52db1451b56f7a1097ef4115797f70d3e68827; mode=non-target; evidence_b64=Y21kXzQ0MDQgbGVkZ2VyIGlzIGEgc3RhbmRhbG9uZSByZXRlbnRpb24gYXJ0aWZhY3Q7IG5vIGNvbnRleHQgb3Igc2VtYW50aWMtaW5kZXggc3luY2hyb25pemF0aW9uIGlzIGluIHNjb3Bl -->
<!-- dm_signal_research_reflux: fingerprint=02f9ba6266fc1d49d52b2011225c6b4e5bb17b305894a37e9476a891f3243beb; mode=synced; evidence_b64=Y21kXzQzNzYgbGF5ZXItc3RyYXRpZmllZCBjb25jbHVzaW9uIGlzIHJlZmxlY3RlZCBpbiBtdWx0aS1hZ2VudC1zaG9ndW4gY29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQ= -->
<!-- dm_signal_research_reflux: fingerprint=58ebae73d3c8b73bc531898a95e8a59b082592c80461598c04dacc5ed7c86c89; mode=synced; evidence_b64=Y21kXzQzNzQgUGhhc2UgMmIgcmVzdWx0IGlzIHJlZmxlY3RlZCBpbiBtdWx0aS1hZ2VudC1zaG9ndW4gY29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQ= -->
<!-- dm_signal_research_reflux: fingerprint=1be86899ba9c02cf68ed9726e4598e11603ce8bb35fb81690b79f24846d42f28; mode=synced; evidence_b64=Y21kXzQzNzMgUGhhc2UgMiByZXBvcnQgYW5kIHNoYXJlZCByZXNlYXJjaCBjb250ZXh0IG5vdyByZWZsZWN0IGV4YWN0IHJlYWRvbmx5IDc4LUZvRiBjb2hvcnQsIGNhbmRpZGF0ZSBwYXJpdHkgNzgvNzgsIGZ1dHVyZSByZWZlcmVuY2VzIDAsIFBBU1NfUEhBU0VfMg== -->
<!-- dm_signal_research_reflux: fingerprint=f9d36a7b49385ecd846cf12bb361d6654748d049bba0ee507a649f9dc1024ee3; mode=non-target; evidence_b64=U2hhcmVkIGNvbnRleHQgaW5kZXggaXMgbWFpbnRhaW5lZCBpbiBtdWx0aS1hZ2VudC1zaG9ndW47IHRoaXMgRE0tU2lnbmFsIGNvbW1pdCBvd25zIG9ubHkgdGhlIHJlc2VhcmNoIGhhcm5lc3MgYW5kIHJlcG9ydC4= -->
<!-- dm_signal_research_reflux: fingerprint=bb72f517f4cbbf1466de24c73098b7a7dd051c2ae55e753986fa431130383c2f; mode=synced; evidence_b64=Y29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQgbm93IHJlY29yZHMgY21kXzQzNzIgUEFTU19QSEFTRV8xIHdpdGggYXJ0aWZhY3QgcmVmZXJlbmNlcw== -->
<!-- dm_signal_research_reflux: fingerprint=d947f787be6c07907b51d45e4c1e3c16f645aee8c3b16355dc5a875a36a3f02d; mode=synced; evidence_b64=Y21kXzQzNjkgY29uY2x1c2lvbiBhZGRlZCB0byBzaGFyZWQgY29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQgd2l0aCBtZWFzdXJlZCA3OCBGb0YsIDEwOCBjb21tb24gUElUIG1vbnRocywgZnV0dXJlIHJlZmVyZW5jZXMgMA== -->
<!-- dm_signal_research_reflux: fingerprint=e08ee1a5e38e43ef2d162827eac8319373353dc46ebfc8b5bd8e8d194c335a35; mode=non-target; evidence_b64=VHJhY2sgQiBzdGFuZGFsb25lIHJlc2VhcmNoIGFydGlmYWN0OyBzaGFyZWQgY29udGV4dC9pbmRleCB1cGRhdGUgaXMgb3V0c2lkZSB0YXNrIHNjb3BlIGFuZCBUcmFjayBBIHJlbWFpbnMgaXNvbGF0ZWQu -->
<!-- dm_signal_research_reflux: fingerprint=4faf29b1cba9e93979eaf7230e8690d4e5ec599d0e6055f63afc85527214d2cc; mode=non-target; evidence_b64=VHJhY2sgQeaIkOaenOeJqeOCkmRvY3MvcmVzZWFyY2jjgbjkv53lrZjjgILlhbHmnIljb250ZXh044G444Gu6YKE5rWB44Gv5a626ICBcmVsZWFzZeOBvuOBp+ihjOOCj+OBquOBhOOAgg== -->
<!-- dm_signal_research_reflux: fingerprint=795aca504e998b90bfb9fcfea4e16563c679152843eeda528f089d3c3fb838b0; mode=synced; evidence_b64=Y29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQgR0EtNDc3IHNvdXJjZSBib3VuZGFyeSBwbHVzIGNtZF80MzU0IEFzSXMgdjEuMTAgc3luY2hyb25pemVk -->
<!-- dm_signal_research_reflux: fingerprint=737509502d5d41dcf9d016abf1f8a9b5958eb06228553daf93934543f8354cc2; mode=non-target; evidence_b64=Y21kXzQzNTIgQUMy44GucnVuNDA5IHJlYWRvbmx556qB5ZCI5oiQ5p6c54mp44CCdGFza+OBrmNvbnRleHRfdXBkYXRlX2NhbmRpZGF0ZXPjgYznqbrjgafjgIFjb250ZXh0L2RtLXNpZ25hbC1yZXNlYXJjaC5tZOOBuOOBruWQjOacn+OBr+acrGNtZOOCueOCs+ODvOODl+WkluOAgg== -->
<!-- dm_signal_research_reflux: fingerprint=4056ee5a07b612664a6508071fe7f5f9d0f8628543ed46fbe2fd6e0d236cdba2; mode=non-target; evidence_b64=Y21kXzQzNTAgb3V0cHV0cyBhcmUgc3RhbmRhbG9uZSByZXNlYXJjaCBhcnRpZmFjdHM7IG5vIGNvbnRleHQgb3Igc2VtYW50aWMgaW5kZXggc3luY2hyb25pemF0aW9uIGlzIGluIHNjb3Bl -->
<!-- dm_signal_research_reflux: fingerprint=60b3f3e2a0bd7895c12564084754698a650493a2d2e4e57fb34a7fcb7c60d005; mode=non-target; evidence_b64=Y21kXzQzNDIgb3ducyB0aGUgcmVwcm9kdWNpYmxlIGV4cGVjdGVkLWRpZmYgQ1NWL01hcmtkb3duIGFuZCBjb21wYXJhdG9yIHNjcmlwdDsgc2hhcmVkIHJlc2VhcmNoIGluZGV4IHN5bmNocm9uaXphdGlvbiBpcyBvdXRzaWRlIHRoaXMgdGFzayBzY29wZS4= -->
<!-- dm_signal_research_reflux: fingerprint=7b26c254b1af0d1e09ba9effee59c0f2a292c3d53d9946a2498948ad1e61896c; mode=non-target; evidence_b64=Y21kXzQzMzEgcmV2aXNpb24gYXJ0aWZhY3QgZXhwYW5kcyBBQzMgYWNyb3NzIGFsbCA3NCBGb0ZzIHdpdGggYnJhbmNoL3ZpZXcgc2VtYW50aWNzOyBubyByZXNlYXJjaCBpbmRleCBzeW5jaHJvbml6YXRpb24gd2FzIHBlcmZvcm1lZCBpbiB0YXJnZXQgcmVwbw== -->
<!-- dm_signal_research_reflux: fingerprint=57062b599ca7a88638062f79aa252acfb453d47087a796e1dd2bb61133258d38; mode=non-target; evidence_b64=Y21kXzQzMzEgYXJ0aWZhY3QgZG9jdW1lbnRzIHByb2R1Y3Rpb24gRm9GIHNjb3JlLWdhcCBhbmQgc2l4LWtleSBkcnktcnVuOyBubyByZXNlYXJjaCBpbmRleCBzeW5jaHJvbml6YXRpb24gd2FzIHBlcmZvcm1lZCBpbiB0YXJnZXQgcmVwbw== -->
<!-- dm_signal_research_reflux: fingerprint=e8231b42c346a88d961d60482fd63597f4caf27c3b9c4ee488e3e0230dec92de; mode=synced; evidence_b64=Y21kXzQzMjEgcmVzZWFyY2ggcmVzdWx0IGluZGV4ZWQgaW4gbXVsdGktYWdlbnQtc2hvZ3VuIGNvbnRleHQvZG0tc2lnbmFsLW9wcy5tZCDCpzk3 -->
<!-- source_commit:b24d6b5f reason:GA-477 reviewed source boundary evidence:context_freshness_check context=context/dm-signal-research.md commit=b24d6b5f -->
<!-- source_commit:6b3537fd reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-research.md commit=6b3537fd -->
<!-- source_commit:99199a9c reason:cmd_4301 RB8完了に伴う最新境界更新(RB8 checkpoint finalizeが最新) evidence:cmd_4301: context_freshness_check --cmd-commit-list cmd_4301の最新行=99199a9c。doc-only 8commitをmainへff-push済み(e3dccd87..99199a9c) -->

<!-- source_commit:37bc59cc reason:cmd_4296 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-research.md commit=37bc59cc -->
<!-- source_commit:00cecab1 reason:cmd_karo_recon2_cmd4284_final_evidence_202608101034 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-research.md commit=00cecab1 -->
<!-- source_commit:f22a0ca3 reason:cmd_4285 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-research.md commit=f22a0ca3 -->

<!-- retrieval: section -->
<!-- detail: docs/research/cmd_karo_hotfix_vercel_debt_reason_202608100949_dm_signal_research_full.md -->

## 結論

研究コンテキストの全892行は詳細層へ移設済み。情報項目は削除せず、以下の正本へ完全保存した。

### cmd_4300 N×E二次元ロバストネス (2026-08-13)

DM2/DM6のN=0..7×E=0..7全128セルをThird common cohortで再集計。全セルSPY CAGR超過（DM2 64/64、DM6 64/64）、欠損0、相互作用contrastはDM2 `-0.131168560..0.008238636`、DM6 `-0.007674547..0.018111132`。性能崩壊領域なし。→ `docs/research/nxe-2d-robustness-asis-tobe-5w1h_20260801.md` §6.5、成果物: `/mnt/c/Python_app/DM-Signal/docs/research/cmd_4300_nxe_robustness_20260813.md` / `cmd_4300_nxe_cells.csv`

詳細層の完全性: `original_line_count: 892`、`original_sha256: 26f83070027334f3c348ba6f5a68a6caa0f0251cb461e6c3f969c8e4aaf06fe8`。

## 参照方法

- 通常の判断: 本索引の結論と詳細層パスだけを読む。
- 研究内容の検証: 詳細層の見出し(`^##`)または該当cmdを検索し、必要な節だけ読む。
- 全履歴・数値表・因果経緯: 詳細層を一次資料として読む。

## 情報構造

| 層 | 正本 | 役割 |
|---|---|---|
| 索引 | `context/dm-signal-research.md` | 結論・読み方・詳細参照 |
| 詳細 | `docs/research/cmd_karo_hotfix_vercel_debt_reason_202608100949_dm_signal_research_full.md` | 892行の原文、全数値・経緯・参照 |

## 完全性契約

- 詳細層は移設前原文のsha256と行数をメタデータに保持する。
- 圧縮前後の情報項目数は、詳細層の原文ハッシュ一致で証明する。
- 詳細層作成と存在確認を先に行い、その後に本索引を圧縮する。
- この索引から参照する詳細層パスは `gate_vercel_phase.sh` で存在検証する。

## 代表的な入口

- 月次研究・GS・パリティ: 詳細層の該当`§`見出しを検索。
- 運用・設計・因果: 詳細層の`cmd_`、`正本`、`source commit`を検索。
- 研究教訓・用語辞書: 詳細層の教訓索引・知識辞書節を検索。

## cmd_4331 FoF tie-break dry-run (2026-08-17)
- 74 FoF(選択block有57/無17)を同一as-of月で6段キー乾式適用: scalar filter 36PFで837月変化(現行同率全採用792月)、全FoF 949月変化。段別解決: ②12M 4,511/③CAGR 668/④MaxDD 0/⑤現保有 7/⑥早い方 7、②skip 264。標準PF24=near-tie 0(ε相対1e-9の根拠)。top-N/tie-breakは各filter+GS fast pathへ分散(共通helperなし)。→ `docs/research/cmd_4331_fof_tiebreak_dryrun_20260817.md`(DM-Signal repo 6b3537fd) / ops §99 / 設計書 `docs/research/dm-fof-tiebreak-determinism-asis-tobe_20260817.md`
## cmd_4369 PIT低相関FoF selection最小実験 (2026-08-23)
- 全FoF78体・monthly_returns 11,795行を同一PIT母集団で比較。36M/60Mともdecision 108月、future参照0、候補集合不整合0。→ `https://github.com/simokitafresh/DM-signal/commit/8cefd6e1b78d742897bbaa51230300fb03c55151`（`cmd_4369_low_correlation_experiment_report.md`）/ `outputs/analysis/cmd_4369_low_correlation_experiment.json`

## cmd_4372 HMM Regime Phase 1 (2026-08-23)
- SPY日次log returnを観測、3状態Gaussian HMMのexpanding-fit + filtered state（smoothing不使用）でFoF全78体を分類。decision 173月、Quiet/Transition/Stress=126/23/24、future参照0。Regime間rank correlation最小0.680709でPASS_PHASE_1、Phase 2進行可。→ `/mnt/c/Python_app/DM-Signal/docs/research/cmd_4372_hmm_regime_phase1_report.md` / `outputs/analysis/cmd_4372_hmm_regime_phase1.json`

## cmd_4373 HMM Regime Phase 2 (2026-08-23)
- Phase 1 filtered regime系列を再利用し、正本DBのreadonly export（FoF 78体・monthly_return_open 11,795行）でPIT prior 36M/60M eligibility + prior 12M Momentum top-4内の全horizon Regime×forward・sample対称化・Stress leave-one-month-outを再計測した。候補母集団一致(78/78)、future参照0、判定は `PASS_PHASE_2`（最小rank correlation=-0.563190511663018）。→ `https://github.com/simokitafresh/DM-signal/commit/919e7aeb005d19d79fb418260e544e0ce0dce2db`（`cmd_4373_hmm_regime_phase2_report.md`）/ `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_4373_hmm_regime_phase2.json`

## cmd_4374 HMM Regime Phase 2b (2026-08-23)
- 既存JSONの固定seed equal-n randomization 40件とStress LOO 72件を統計要約。h=6 Quiet-Stress=-0.563191は帰無min=-0.533082より外側だが、保守的両側p値相当=0.166667、h=6以外のhorizon方向も不一致のため `STOP_PHASE_2B`。selection変更・本番書込み・新規run起動なし。→ `/mnt/c/Python_app/DM-signal/docs/research/cmd_4374_hmm_regime_phase2b_report.md`

## cmd_4376 FoF層別再分析 (2026-08-23)
- FoF78体を`fof_component_weights`の参照先型再帰でnested depth 0/1/2/3=25/25/21/7、selection block有/無=57/21、構成PF数2/3/4/6=9/14/54/1へ分類。低相関E1−C1差はdepth 0/1でSharpe悪化傾向、depth 2は混在、depth 3はE1支持月0で判定不能。→ `https://github.com/simokitafresh/DM-signal/commit/39b2827fcc71eb309694c7117c6556e733f5de8c`（`cmd_4376_layer_stratified_reanalysis.md`）
- HMM Stress時pairwise相関(h=6)はnested depth 0/1/2/3=0.856/0.893/0.912/0.961、selection block有/無=0.868/0.915。高相関は単一層に限定されず、depth 3はN=7の記述統計に留める。standard PF24体は両実験母集団外。→ `/mnt/c/Python_app/DM-Signal/outputs/analysis/cmd_4376_layer_stratified_reanalysis.json`

## T189 outputs 整理 — 本番 PF 作成根拠の保持と 30.8GB 除去 (2026-08-29)
- 殿裁定 16:51/16:53/16:56『outputs は本番使用中以外不要。ただし本番 PF を作成するために使ったものは残す。消せ』。本番コード(backend/app)は outputs/ を読まない(recalculate_fast.py の source-identity 除外のみ)。
- 保持集合(本番 33 体=シン四神 12+シン忍法 v2 21 の GS 根拠): `outputs/grid_search/shin_shijin_l1`(cmd_1018, 872M)・`shin_ninpo_v2_12body`(cmd_1080, 2.7G)・`cmd_3495〜3505`(秘奥義, 1.4G)・`cmd_3774/3779`(full, 4.4G)・`cmd_3798_phase_b_l1`・`ema_experiment_phase0_v2_l1`・git tracked 24M・cmd_3871 KEEP 10 件。要確認 2 件(okugi_shin_ninpo_20body 2.0G/20260427 52M)は据置。
- 除去: 138 対象 30,841,072,791B を realpath guard 付き直列除去、残存 0、`grid_search` 43G→14G、保持集合差分 0・tracked 削除 0・本番 DB 件数差 0。manifest=DM-signal `outputs/t189_cleanup_manifest_20260829.tsv`(commit dbfe34dd)。判定表の正本 → `docs/research/grid-search-outputs-cleanup-inventory-20260807.md` §最終判定。
- 効果: T106 ext4 cutover の複製対象が 62G→約 31G。origin: `[[殿裁定_作成に使ったものは残す_20260829_1653]] -> [[T189_outputs整理]] -> [[T106_DM-signal_ext4移設]]`
