# S3 テスト・スクリプト速度改善 AsIs/ToBe 5W1H（2026-07-20起草）

殿裁定(2026-07-20 00:05「よい。開始せよ」): S3二本立て開始+**PD-132解除**(速度修行multi-round解禁)。
前提裁定: 殿指摘(00:03)「テスト実行速度の改善の大元はスクリプトや元のコードの速度改善が根源」— テスト時間は症状であり検知器、根源は被テストコードの速度。

## §1 AsIs（一次計測 2026-07-19〜20）

| 項目 | 現状 | 一次根拠 |
|------|------|---------|
| CI 1周 | 約5.5〜6分/run。7/19実測13run≈70分強の待ち税 | gh run list実測(5m40s前後) |
| テスト在庫 | unit 90 batsファイル+integration/e2e/skills。CI監査4,922件中**30日FAIL実績あり487件=9.9%** — 約4,435件(90.1%)が淘汰候補として数値特定済み | 殿裁定2026-07-19 02:09の根拠監査 |
| 作らない仕組み | **完成**: default-delete政策(契約テストのみ永続)+CLAUDE.md二値防御(5)-(7)(deletion_justification・fixture被参照0・regression_justification+race停止) | CLAUDE.md Test Rules |
| 淘汰の実走 | **未実施**(sweepゼロ)。宣言インフレ検知(宣言率>30%)は受動計測のみ | 本設計の対象 |
| スクリプト速度修行 | multi-round機構実装済み(cmd_3952、86/86 PASS)だがPD-132で停止中→**本日解除** | レーンパターン§6.5(gist f777582a v2.1) |
| ratchet基盤 | テスト時間免疫系D7規律+D3 ratchet+D4'淘汰固定(7/14 P0-P3完結)。残: P4 evidence契約+D3閾値数値固定 | gist cfd920e7 |

## §2 ToBe（二本立て）

| 系 | 内容 | 機構 | 期待効果 |
|----|------|------|---------|
| **A: スクリプト速度修行(根源)** | test_suite_timing台帳の遅suite上位→被テストスクリプトを逆引き→速度修行弾をidle忍者へ連続配備 | multi-round(baseline=best_so_far継承・悪化run自動不採用・round別commit)+D3 ratchetで下限切上げ | スクリプト・テスト・CIが同時に縮む(cmd_save 36.5s→1.66sの型) |
| **B: テスト在庫sweep(掃除)** | 統合・重複排除・不要テスト除去。候補=**二条件**(30日FAIL実績なし∧test_necessity契約宣言なし。殿裁定2026-07-20 00:22。重複被覆の三条件目は政策外の過剰安全でcmd_4092が候補0=誠実FAILとなったため撤回) | 二値防御(5)-(7)+**小batch段階遡及**(明白層→回帰事故ゼロ確認→拡大。全量一括不採用) | suite件数・実行時間・保守対象の純減 |

- **絶対条件**: 品質を落とさない。バグ由来スループット拒否(殿原則)。回帰検知力の実体=契約テスト群は全量保全
- 効果測定の計器: test_suite_timing台帳(suite別実測)+CI run時間+script_speed_training_ledger(修行before/after)

## §3 5W1H

| 問 | 答 |
|----|-----|
| **Why** | CI待ち5.5分×run数が全員の反復速度を律速。速度改善自体の速度に効く=試行回数の分母を削る(殿式: 正しい試行回数×一発PASS率×知見還流率) |
| **What** | A=遅スクリプトの根源速度改善(multi-round修行) / B=在庫4,435件級の淘汰sweep |
| **When** | 2026-07-20開始。A=idle資源で連続自走、B=段階sweep(第1弾から逐次) |
| **Where** | multi-agent-shogun全域(scripts/+tests/)。台帳=logs/test_suite_timing_ledger.tsv等 |
| **Who** | A=家老karo-direct自走(殿裁定の恒久ループ型)、B=将軍cmd起票→忍者実走→軍師必須確認、裁定=殿 |
| **How** | A=台帳逆引き→修行弾→ratchet固定 / B=候補機械抽出→justification→削除→全量FAIL0/SKIP0→CI GREEN |
| **How much** | 追加コスト0(idle資源)。効果は CI run時間とsuite件数のbefore/afterで数値報告 |

## §4 リスクと対処

| リスク | 対処 |
|--------|------|
| 回帰検知力の喪失(消しすぎ) | 契約テスト(test_necessity宣言)は淘汰対象外。境界内回帰は実装責任として受容(殿裁定の意図した受容)。事故→教訓→契約テスト昇格ループが受け皿 |
| 誤削除 | git履歴で完全可逆+削除リストdiff明示+軍師必須確認+fixture被参照0証明。他commit由来の削除競合検出で停止(二値防御(7)) |
| 速度のための品質劣化 | 修行はD3 ratchet+全量テストFAIL0/SKIP0が各roundの合格条件。悪化run自動不採用 |
| 偽改善(計測ブレ) | multi-roundのbaseline=best_so_far継承が本質防御(insight_write+17%悪化の実例より) |

## §5 工程表(Phase名参照。cmd番号は起票時にLS086照合表へ記録)

| Phase | 内容 | 起票cmd | 状態 |
|-------|------|---------|------|
| A系 修行連続配備 | 台帳逆引き→速度修行弾→ratchet(karo-direct自走、cmd起票不要=殿裁定の恒久ループ型) | 保留: karo-direct自走レーンのため個別cmd起票なし(speed_campaign_order 2026-07-20 00:05で発動済み) | **稼働開始** |
| B1 sweep初回(三条件) | 淘汰候補の機械抽出(三条件AND) | cmd_4092 | FAIL確定(削除候補0=安全条件を緩めない誠実FAIL。365 files/4,922 cases全量抽出は資産として継承) |
| B1' sweep小batch第1弾(二条件) | 三層分類(宣言55/削除資格290/昇格候補20 files)+軍師承認小batch削除 | cmd_4093 | 完了(GATE CLEAR。削除1 file・after全量1551/1551 PASS・SKIP0。実行時間はbefore318.5s→after387.8sと並行負荷ノイズで悪化計測=速度効果未確認、静穏時再計測が次弾の前提) |
| B2 sweep第2弾以降 | 削除資格層から証跡つき小batchを段階消化(静穏before/after+品質二値検証) | cmd_4094 | 起票済み(GA-304 GREEN後に直列配備) |
| B3 昇格弾 | FAIL実績あり宣言なし層へtest_necessity宣言記入(不変量1つ・契約混入0・軍師レビュー停止点) | cmd_4095 | 起票済み(同上直列) |
| C 残タスク消化 | テスト時間免疫系P4 evidence契約+D3閾値数値固定 | 保留: 静穏baseline再計測とB2実測で閾値根拠が揃ってから起票 | — |

## 因果リンク

- ← [[殿質問_速度改善どこ_20260720]] → [[テスト速度の根源はスクリプト速度]] → [[S3二本立て裁定+PD132解除]]
- → [[self-improvement-loop-candidates-20260719]] S3行(本設計で稼働化)
- → [[殿裁定_default_delete_test_20260719]] 淘汰の政策根拠
- → [[deepdive_why_chain_20260321]] Phase 5: 自動化ターゲット=検知器(台帳)から根源(スクリプト)へ降りる
