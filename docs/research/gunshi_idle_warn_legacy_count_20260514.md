# WARN累積カウント遺産問題 — 偽陽性修正後もBLOCKが残る構造的バグ

日付: 2026-05-14
分析者: 軍師(gunshi)

## 発見

Post-5/12で63件BLOCKのうち**30件(48%)がWARN遺産カウント問題に起因**。
cmd_2703等で偽陽性WARNを修正したが、修正前に蓄積されたWARNカウントが残存し、
同一パターンのWARNが(正当であっても)即BLOCK化する。

## 定量データ

| チェック | 遺産カウント | post-5/12 BLOCK | 修正後新規発火 | 性質 |
|----------|-------------|----------------|---------------|------|
| ac_file_paths | 16+ | 12件 | あり(新規作成cmd) | 偽陽性(新規作成を区別できない) |
| negative_claim | 16+ | 11件 | あり(rebalancer cmd) | 一部正当だが遺産カウントで過罰 |
| gate_hook_action | ?+ | 3件 | あり | 一部正当だが遺産カウントで過罰 |
| ac_phase_mixing | 29 | 2件 | 0件(修正有効) | 偽陽性(cmd_2703修正済み) |
| ac_param_sufficiency | 19 | 2件 | 0件(修正有効) | 偽陽性(cmd_2703修正済み) |
| **合計** | — | **30件/63件(48%)** | — | — |

残り33件(52%)は正当なBLOCK(教訓未記録19件、cmd品質7件、その他7件)。

## 因果鎖

1. 偽陽性WARN発火(cmd_2703以前) → cmd_design_quality.yaml に source=cmd_save_warn, gate_result=WARN エントリ蓄積
2. count_same_warn_pattern() が全WARNエントリをカウント → 29/19回分を返す
3. cmd_2703で偽陽性修正 → WARN発火自体は停止
4. しかし過去エントリは残存 → 将来同一パターンが正当に発火した場合、count≥1(閾値)で即BLOCK
5. 将軍は「初回なのになぜ28回目と表示されるのか」と混乱

## 根因

count_same_warn_pattern()に「偽陽性修正による解消」を反映する仕組みがない。lessons_shogun.yamlのsource_cmdによるresolved判定は存在するが、偽陽性修正cmdは通常lessonsに登録されないため該当しない。

## 提案: 3案

### 案A: resolved_warnsマーカー (推奨)
偽陽性修正cmd完了時に、cmd_design_quality.yamlの該当WARNエントリをresolved扱いにするスクリプト追加。
count_same_warn_pattern()がresolved済みエントリを除外。

```bash
# イメージ
bash scripts/lib/resolve_warn_legacy.sh ac_phase_mixing cmd_2703
# → cmd_design_quality.yaml内のac_phase_mixing WARNエントリにresolved_by: cmd_2703を付与
```

- **pros**: 偽陽性修正時に1回実行するだけ。既存ロジックへの影響が最小
- **cons**: yaml_field_set.sh相当の安全書込みが必要

### 案B: 時間窓
count_same_warn_patternに「直近N日(例: 30日)以内のWARNのみカウント」を追加。
古い偽陽性が自然減衰。

- **pros**: 運用不要で自動解消
- **cons**: 正当な繰返しWARNも30日で忘れる。学習が消える

### 案C: 即時クリーンアップ (最小コスト)
cmd_2703修正済みの2パターンについて、cmd_design_quality.yamlの該当WARNエントリのnotesに`[resolved:cmd_2703]`を追記し、count_same_warn_patternがresolved含むnotesを除外。

- **pros**: 今の問題を即座に解消。Pythonカウントロジックに1行条件追加
- **cons**: 都度手動。汎用性がない

## 推奨

案C(即時)→案A(汎用化)の段階的実装。まず案Cでcmd_2703修正済み2パターンの遺産カウントを解消し、案Aで汎用的なresolved_warnsスクリプトを追加する。

## 影響定量化

| cmd | レガシーBLOCK | 総試行 | レガシー率 |
|-----|-------------|--------|-----------|
| cmd_2713 | 5回 | 14回 | 36% |
| cmd_2714 | 5回 | 14回 | 36% |
| cmd_2715 | 7回 | 18回 | 39% |
| cmd_2719 | 4回 | 13回 | 31% |
| **合計** | **30回** | — | — |

推定時間浪費: ~30分(1回1分)。将軍体験: 「直したのにまだBLOCKされる」×7回(cmd_2715)。

## 影響範囲

- 対象ファイル: scripts/cmd_save.sh (count_same_warn_pattern関数, L1160-1217)
- 対象データ: logs/cmd_design_quality.yaml (48 WARNエントリ)
- blast radius: cmd保存時の品質判定。誤BLOCKの排除

## 関連問題: ac_file_paths 新規作成偽陽性 (12件BLOCK)

check_ac_file_paths(L2223-2292)は「ACに記載されたファイルパスの親ディレクトリが不在」でWARN。
しかしcmdが「ファイルを新規作成する」指示の場合、親ディレクトリ不在は当然であり偽陽性。

| cmd | BLOCK回数 | 内容 |
|-----|-----------|------|
| cmd_2713 | 5回 | Service Worker導入（新規ファイル作成） |
| cmd_2715 | 7回 | CI強化（新規設定ファイル作成） |

**根因**: check_ac_file_pathsが「既存ファイル参照」と「新規ファイル作成」を区別できない。
ACに「作成」「新規」「導入」等のキーワードが共起している場合、ファイル不在は期待動作。

**提案**: AC内のファイルパス周辺に「作成」「追加」「導入」「新規」キーワードがある場合、
親ディレクトリ不在WARNをINFOに降格する(L2278-2290)。

## 複利の問い

この修正を10回繰返したら正の複利か？→ YES。偽陽性修正のたびに遺産カウント問題が発生するため、一度仕組みを作れば全将来修正に適用される。ac_file_pathsの修正も同様、新規作成cmdは今後も頻出するため一度の修正で全将来cmdに適用。
