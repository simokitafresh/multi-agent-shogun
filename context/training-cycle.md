# 修行サイクル設計書（殿直伝 2026-03-25）

## §1 背景と原理

軍師が消火パターン(autofix)を撤去中（90GP、消火撤去5件）。
撤去完了後、忍者はgate BLOCKされるようになる。
**BLOCKは成長機会**。BLOCKされなければ忍者は永遠に学ばない。

殿の指示: 「ダミータスクで修行をさせるのがいい。修行サイクルを回し続けるのがdeepdiveの利他と自走だ。止まらずに回し続けるのが自走」

→ deepdive Phase 8（利他: 他者を助ける）+ Phase 10（自走: 止まらないサイクル）の実装

## §2 修行タスクの設計

### 目的
idle忍者に報告書作成修行を配備し、gate BLOCKパターンを実戦前に学習させる。

### BLOCKパターン一覧（gate_report_format.sh + gate_fire_log実績）

| # | パターン | 実績FAIL数 | 消火撤去GP | 修行Level |
|---|---------|-----------|-----------|-----------|
| 1 | verdict非二値("None"/""等) | 178回 | GP-092(構造変換残留) | L1 |
| 2 | lessons_useful dict形式 | 69回 | GP-094撤去→BLOCK | L2 |
| 3 | binary_checks string形式 | 66回 | GP-103撤去→BLOCK | L1 |
| 4 | FILL_THIS残存 | 61回 | BLOCK済み | L1 |
| 5 | lesson_candidate found=false+reason欠落 | - | GP-093撤去→BLOCK | L2 |
| 6 | lesson_candidate found=true+title欠落 | - | BLOCK済み | L2 |
| 7 | ac_version_read欠落 | - | GP-106撤去→BLOCK | L1 |
| 8 | files_modified null/dict形式 | - | BLOCK済み | L1 |
| 9 | purpose_validation欠落 | - | BLOCK済み | L1 |
| 10 | result.summary空 | - | BLOCK済み | L1 |
| 11 | self_gate_check非二値(review型) | - | BLOCK済み | L3 |
| 12 | bc check内容が非具体的("ok"/"テスト") | - | BLOCK済み | L1 |

### 修行レベル設計

**Level 1 — 基礎（1AC・impl・教訓なし）**
- シナリオ: 「gate_report_format.shを読み、全FAIL条件をリスト化して報告せよ」
- 修行対象: verdict, binary_checks list形式, files_modified, ac_version_read, purpose_validation, result.summary
- 忍者の作業: ファイルを読む（簡単）→ 報告YAMLを正しく書く（本番）

**Level 2 — 教訓（2AC・impl・教訓発見あり）**
- シナリオ: 「deploy_task.shの自動注入ロジックを精査し、教訓注入の仕組みを報告せよ」
- 修行対象: lesson_candidate found=true+title+detail, lessons_useful list形式+useful=bool
- 忍者の作業: 読んで分析 → lesson_candidateを正しく書く

**Level 3 — レビュー（2AC・review型・self_gate_check）**
- シナリオ: 「直近の忍者報告YAMLをレビューし、gate準拠度を評価せよ」
- 修行対象: self_gate_check dict+各項PASS/FAIL二値, purpose_validation+purpose_gap
- 忍者の作業: 他者の報告を読んでレビュー → 自分の報告も正しく書く

**Level 4 — 総合（3AC・実戦シナリオ）**
- シナリオ: 全パターン複合。FILL_THIS罠つきテンプレート
- 修行対象: 全BLOCKパターン同時
- 忍者の作業: 実戦と同条件で一発PASS

### 配備方式

1. 既存のdeploy_task.sh + task YAMLで配備（新インフラ不要）
2. parent_cmd: `cmd_training_L{level}_{連番}` 形式
3. gate_report_format.shが本番同様に検証
4. BLOCKされたら忍者が自力修正（FIX hintsがgateから表示される）

### 自動修行サイクル（将来的な自動化）

```
ninja_monitor idle検知
  → 本番cmdなし → deploy_training.sh（未実装。初期は家老手動配備）
  → 忍者が報告作成
  → gate_report_format.sh で検証
  → BLOCK → 忍者が自力修正
  → PASS → lesson_candidateに「BLOCKされた箇所と原因」を記入
  → 家老がlesson_write → 次の本番cmdで注入
  → 修行BLOCK率を忍者別に追跡
```

## §3 計測

### 計測方法（殿指摘で修正 2026-03-25）

**計測ソース: `logs/gate_fire_log.yaml`**（gate実行のたびに自動記録。忍者paneは/clearで消失するため信頼不可）
- grep `cmd_training_L{level}` で該当レベルの全gate実行を抽出
- 忍者ごとに初回結果（PASS/FAIL）を判定 → 一発PASS率を算出

### 修行完了基準（殿裁定 2026-03-25）

1. **スムースさが本質**: 修行の目的はクリアではなく**知見を得ること**。BLOCKすら起きない＝スムースな一発PASSが指標。試行錯誤（BLOCK→修正→PASS）が起きていたらそれは**まだ修行すべき事が多い証拠**。
2. **再現性**: 同レベルを3人以上の異なる忍者が一発PASSして初めて「修行完了」。

### 計測指標

- **一発PASS率**: gate_fire_logで初回実行がPASSだった忍者の割合（Level別）
- 修行前後の本番初回CLEAR率変化
- 修行→本番のBLOCKパターン再発率

## §4 Level 1 第1回実績（2026-03-25）— gate_fire_logによる正確な計測

| 忍者 | 初回gate結果 | FAIL理由 | 一発PASS |
|------|------------|---------|---------|
| hayate | autofix依存 | files_modified string→dict変換 | **NO** |
| kagemaru | FAIL | bc result空, status pending, verdict空 | **NO** |
| kotaro | FAIL | bc result空, verdict空 | **NO** |
| hanzo | FAIL | bc result "PASS"(yes/noではない), verdict空 | **NO** |
| saizo | FAIL×2 | YAML parse + reasons空 + bc空 + verdict空 | **NO** |
| tobisaru | FAIL×2 | YAML parse + reason空 + bc空 + verdict空 | **NO** |

**一発PASS率: 0/6 = 0%**

共通弱点（全6名）:
- binary_checks result: 空文字 or "PASS"（正: "yes"/"no"のみ）
- verdict: 空文字（正: "PASS"/"FAIL"）
- status: pending（正: completed）

## §5 L1全ラウンド実績（2026-03-25〜26）

| Round | テンプレート改善 | FP Rate | 平均エラー | 主要失敗原因 |
|-------|----------------|---------|----------|------------|
| 1 | なし | 0/6 (0%) | ~8 | bc/verdict/lu空 |
| 2 | なし | 1/6 (17%) | ~6 | bc/verdict/lu空 |
| 3 | inline hints (bc result, lu reason) | 1/6 (17%) | ~4 | bc/verdict空 |
| 4 | +header checklist (提出前チェック) | 2/6 (33%) | 1.3 | bc[last]循環依存 |
| 5 | +bc gate自己検証除去 (2→2項目) | 2/6 (33%) | 1.8 | status: pending |
| 6 | +status→completed追記 | **6/6 (100%)** | **0** | なし |

### 各ラウンドの自動化ターゲットと効果

- **R3**: `result: "" # yes or no` / `reason: '' # 有用/無用の理由を具体的に書け` → bc/lu空を部分解消
- **R4**: header checklist追加（提出前にbc/verdict/gate確認） → 構造フィールド充填率向上
- **R5**: bc[last]「gate自己検証しPASSしたか」を除去 → 循環依存排除（kagemaru 1→0エラー）
- **R6**: 手順2に `status→completed` 追記 → 3忍者のstatus忘れ解消

### L1完了判定

**条件**: 同レベルで3+忍者がFirst-Pass PASS → **Round 6で6/6達成。L1完了。**

### 核心教訓

deepdive Phase 4-5の実証: 知識をエージェントの頭（/clearで消える）ではなく環境（テンプレート）に埋め込む。
各ラウンドで「なぜFAILか」を具体的にデータ分析→1行の環境変更で解消。
0%→100%は6ラウンドの累積改善。個別の改善は小さいが複利で効く。

## §6 L2 Round 1実績（2026-03-26）

### L2設計
- **2AC構造**: AC1=スクリプト精査+報告、AC2=lesson_candidate正しい構造で記入
- L1との差: lesson_candidate found=true時にtitle+detail+project必須

### L2 Round 1結果

| 忍者 | 対象 | 初回gate | FAIL原因 | 一発PASS | lesson_candidate品質 |
|------|------|---------|---------|---------|-------------------|
| hayate | gate_report_autofix.sh | PASS | — | **YES** | yaml.dump round-trip副作用発見 |
| kagemaru | deploy_task.sh | PASS | — | **YES** | Python inline yaml.dump禁則違反発見 |
| hanzo | ninja_monitor.sh | PASS | — | **YES** | idle判定多層フォールバック解明 |
| saizo | cmd_complete_gate.sh | FAIL→PASS | bc result "PASS"(yes/noではない) ×4 | **NO** | check_project_code_stubs設計不整合発見 |
| kotaro | inbox_write.sh | FAIL→PASS | lu reason空×5, bc空×4, verdict空 | **NO** | inbox_write.sh yaml.dump問題発見 |
| tobisaru | ntfy_listener.sh | PASS | — | **YES** | grep dedupパターン不一致バグ発見 |

**一発PASS率: 4/6 = 67%**（L1 Round 6: 100%から低下）

### 分析

**L2固有要素(lesson_candidate構造): 6/6正確 = 100%** — 新スキルは問題なし
**L1基礎(bc/verdict/lu): 4/6 = 67%** — 認知負荷増大による回帰

FAIL原因はL2の新要素ではなくL1基礎の回帰。L2の深い分析に没頭→ヘッダー提出手順の記憶が薄れ→構造フィールドを埋め忘れ。

**核心**: テンプレートヒントがヘッダー（上部）のみ→分析没頭後に忘れる。提出直前に目に入る位置（末尾）にもチェックを配置する必要。

### 副産物: 実バグ発見3件

修行中に実際のバグが発見され、即時修正（殿指示: 都度直そう）:
1. **ntfy_listener.sh L286**: grep dedupパターン引用符不一致→修正済み
2. **inbox_write.sh auto-done**: yaml.dump→yaml_field_set.sh置換→修正済み
3. inbox_write.sh教訓注入 / deploy_task.sh Python inline: yaml.dump→要専用cmd

## §7 L2 Round 2に向けた環境改善

### 自動化ターゲット: テンプレート末尾フッターチェックリスト

L1ヘッダーは「作業開始時」に読まれるが「提出直前」に再確認されない。
末尾にフッターを追加し、提出動線上（verdict記入直後）で基礎チェックを強制。

## §8 L2 Round 2実績（2026-03-26）

| 忍者 | 対象 | 初回gate | 一発PASS | R1比較 |
|------|------|---------|---------|--------|
| hayate | cmd_save.sh | PASS | **YES** | YES→YES |
| kagemaru | gate_karo_startup.sh | PASS | **YES** | YES→YES |
| saizo | gate_report_format.sh | PASS | **YES** | **NO→YES** |
| kotaro | gate_report_autofix.sh | PASS | **YES** | **NO→YES** |
| tobisaru | inbox_watcher.sh | PASS | **YES** | YES→YES |

**一発PASS率: 5/5 = 100%**（R1: 4/6=67%→R2: 5/5=100%）
※ hanzoは前タスク継続中のためR2未参加

### 分析

フッターチェックリスト追加1件でR1の2名FAIL(saizo/kotaro)が完全解消。
- saizo: R1でbc result "PASS"→R2でフッター確認→"yes/no"正しく記入
- kotaro: R1で10エラー(lu/bc/verdict全空)→R2でフッター確認→全項目充填

L1と同じパターン: 環境改善1行が即効果。ヘッダー+フッターの挟撃構造で認知負荷に関わらず基礎が維持される。

### L2完了判定

**条件**: 3+忍者がFirst-Pass PASS → **Round 2で5/5達成。L2完了。**

### GP-110実装完了（軍師）

軍師がdeploy_task.shのinject_ninja_weak_points()にgate_fire_logパース機能を追加。次回配備からper-ninja gate_fail_top3が自動注入される。

## §9 L3 Round 1実績（2026-03-26）

### L3設計
- **review型**: 他忍者のL2報告をレビューし、gate準拠度を5項目で評価
- L3の新要素: self_gate_check (dict形式、各項目PASS/FAIL二値)
- レビューローテーション(R1): hayate→kagemaru報告、kagemaru→hanzo報告、hanzo→saizo報告、saizo→kotaro報告、kotaro→tobisaru報告、tobisaru→hayate報告
- レビューローテーション(R2): hayate→hanzo報告、kagemaru→saizo報告、hanzo→tobisaru報告、saizo→hayate報告、kotaro→kagemaru報告、tobisaru→kotaro報告

### L3 Round 1結果

| 忍者 | レビュー対象 | 初回gate | FAIL原因 | FP |
|------|------------|---------|---------|-----|
| hayate | kagemaru L2_008 | FAIL→PASS | sgc 5項目空 | **NO** |
| kagemaru | hanzo L2_003 | PASS | — | **YES** |
| hanzo | saizo L2_009 | PASS | — | **YES** |
| saizo | kotaro L2_010 | FAIL→PASS | sgc 5項目空 | **NO** |
| kotaro | tobisaru L2_011 | PASS | — | **YES** |
| tobisaru | hayate L2_007 | PASS | — | **YES** |

**一発PASS率: 4/6 = 67%**

### 分析

FAILパターン: self_gate_checkスキャフォールドの空文字(`''`)をPASS/FAILに置換し忘れ(hayate/saizo)。
テンプレートの値にヒントがない（`''`のみ）→L1 R3のinline hint追加で解消したパターンと同一。
自動化ターゲット: `# PASS or FAIL` コメントをスキャフォールドに追加。

## §10 全ラウンド横断サマリ

| Level | Round | FP Rate | 環境改善 | 効果 |
|-------|-------|---------|---------|------|
| L1 | R1 | 0/6 (0%) | なし | — |
| L1 | R2 | 1/6 (17%) | なし | +17% |
| L1 | R3 | 1/6 (17%) | inline hints | ±0% |
| L1 | R4 | 2/6 (33%) | +header checklist | +16% |
| L1 | R5 | 2/6 (33%) | +bc循環依存除去 | ±0% |
| L1 | R6 | 6/6 (100%) | +status追記 | +67% |
| L2 | R1 | 4/6 (67%) | L1環境のまま | -33%(レベルアップ) |
| L2 | R2 | 5/5 (100%) | +footer checklist | +33% |
| L3 | R1 | 4/6 (67%) | +sgcスキャフォールド | -33%(レベルアップ) |
| L3 | R2 | 6/6 (100%) | +sgc inline hint | +33% |

### 核心教訓（L1+L2+L3統合）

1. **環境改善は複利で効く**: 各ラウンドの改善は小さい(1行変更)が累積で0%→100%
2. **ヘッダー+フッター挟撃**: 作業開始時(ヘッダー)と提出直前(フッター)の二重チェックが認知負荷に強い
3. **レベルアップで基礎が回帰する**: 新要素追加で一時的に崩れるが、環境補強で1ラウンドで回復
4. **修行は実バグを見つける**: L2で実バグ3件発見・即修正。訓練+品質改善の二重効果
5. **新フィールドには必ずinline hint**: 空文字スキャフォールドだけでは忍者は値を入れ忘れる(L1 R3, L3 R1で実証)
6. **家老も修行で成長する**: テンプレート設計+一括配備+レビューローテーション+バグ修正統合。第二層学習ループ(対: 家老+忍者)が実証
7. **レベルアップ→回帰→環境改善→100%の法則**: L2 R1(67%)→R2(100%)、L3 R1(67%)→R2(100%)で3回実証。1回の環境改善で必ず回復する

## §12 L3 Round 2実績（2026-03-26）

### 環境改善: sgc inline hint追加

R1のFAILパターン(self_gate_check空文字)に対し、スキャフォールドの各項目に`# PASS or FAIL`コメントを追加。

### L3 Round 2結果

| 忍者 | cmd_id | レビュー対象 | sgc | gate | FP |
|------|--------|------------|-----|------|-----|
| hayate | L3_018 | hanzo L2_003 | 5/5 PASS | PASS | **YES** |
| kagemaru | L3_019 | saizo L2_009 | 5/5 PASS | PASS | **YES** |
| hanzo | L3_020 | tobisaru L2_011 | 5/5 PASS | PASS | **YES** |
| saizo | L3_021 | hayate L2_007 | 5/5 PASS | PASS | **YES** |
| kotaro | L3_022 | kagemaru L2_008 | 5/5 PASS | PASS | **YES** |
| tobisaru | L3_023 | kotaro L2_010 | 5/5 PASS | PASS | **YES** |

**一発PASS率: 6/6 = 100%。L3完了。**

### L3 R2 lesson_candidate注目点

- hanzo R1: lessons_useful追加エントリはgate非検証(related_lessonsとの突合なし) → gate改善候補
- kotaro R1: report_field_setのマルチライン値書込みでYAML構造破壊 → 実バグ候補(要検証)
- hanzo R2: 全5項目PASSでも報告の実質価値はlesson_candidateの深度で決まる
- kagemaru R2: lu_structure検証はreason非空だけでなく具体性も確認すべき

### L3完了判定

**条件**: 3+忍者がFirst-Pass PASS → **Round 2で6/6達成。L3完了。**

## §13 修行サイクル全体サマリ（L1→L2→L3）

### 定量結果

| Level | テーマ | ラウンド数 | 最終FP率 | 環境改善回数 |
|-------|--------|----------|---------|------------|
| L1 | 基礎(報告構造) | 6 | 100% | 4回 |
| L2 | 教訓(lesson_candidate) | 2 | 100% | 1回 |
| L3 | レビュー(self_gate_check) | 2 | 100% | 1回 |

### 発見された実バグ（修行中に修正済み）

1. ntfy_listener.sh: grep dedup pattern引用符不一致
2. inbox_write.sh: yaml.dump禁則違反(auto-done + lesson inject)
3. gate_karo_startup.sh: set -eフォールバック欠落
4. inbox_mark_read.sh: yaml.dump禁則違反
5. inbox_watcher.sh: mark_special_read yaml.dump重複実装

### 修行設計原理（実証済み）

1. **レベルアップ→回帰→環境改善→100%**: 3回実証。新レベルで67%に回帰→1環境改善→100%
2. **環境改善は1行で十分**: inline hint/footer/header、いずれも小さな変更が大きな効果
3. **修行=訓練+品質監査の二重効果**: 忍者がスクリプトを精査するため実バグ5件発見
4. **家老の配備技術も向上**: テンプレート設計/一括配備/ローテーション/レベル間設計

## §14 L4設計 — 総合（3AC・全BLOCKパターン複合）

### L4の目的

L1-L3は各スキルを個別に修行。L4は**全スキルを同時に要求する実戦シナリオ**。
本番cmdと同等の認知負荷で、報告書を一発PASSで作成できるか検証する。

### L4タスク設計

**3AC構造（impl型）**:
- AC1: 指定スクリプトの改善点を3つ特定し報告（分析系）
- AC2: 改善点の1つを実装しgit commit（実装系）
- AC3: lesson_candidate found=true + 他2ACのbinary_checks全記入 + verdict（総合系）

### L4の罠要素（FILL_THIS + 構造崩壊誘因）

1. テンプレートに`FILL_THIS`を3箇所仕込む（purpose_validation.cmd_purpose, result.details, lesson_candidate.detail）
2. AC3のbinary_checksが7項目（L1-L3最多は5項目）→ 認知負荷で記入漏れ誘発
3. related_lessonsを5件注入（理由記入5件必須）
4. files_modifiedがlist形式であることのテスト（AC2で実ファイル変更あり）

### L4 配備対象スクリプト候補

| スクリプト | 改善余地 | 難易度 |
|-----------|---------|--------|
| reset_layout.sh | エラーハンドリング弱 | 低 |
| dashboard_auto_section.sh | 可読性改善 | 中 |
| restart_watchers.sh | プロセス検出改善 | 中 |
| model_switch_preflight.sh | edge case | 中 |

### L4 完了基準

L1-L3と同一: 3+忍者がFirst-Pass PASS。

### L4 予測

L1-L3パターン「レベルアップ→回帰→環境改善→100%」に従い:
- R1: 50-67%予測（3AC+7bc+5lu+FILL_THIS罠の複合負荷）
- R2: 90-100%予測（R1のFAILパターンに応じた環境改善1-2件）

## §15 L4 Round 1実績（2026-04-01）

### L4設計
- **3AC構造**: AC1=改善点3つ特定, AC2=最高インパクト1件実装+commit, AC3=lesson_candidate found=true+完全報告
- L4の新要素: 3AC同時+FILL_THIS罠3箇所+BC7項目+実装あり
- ターゲット: archive_completed.sh/cmd_delegate.sh/daemon_watchdog.sh/context_freshness_check.sh/gate_cycle_health.sh/gate_ninja_workaround_rate.sh

### L4 Round 1結果

| 忍者 | 対象 | 初回gate | FAIL原因 | FP | 実バグ発見 |
|------|------|---------|---------|-----|----------|
| saizo | context_freshness_check.sh | PASS | — | **YES** | 14日ハードコードカットオフ |
| hanzo | daemon_watchdog.sh | PASS | — | **YES** | 再起動ストーム防止欠如 |
| hayate | archive_completed.sh | PASS | — | **YES** | yaml.dump違反+TMP散在 |
| kotaro | gate_cycle_health.sh | PASS | — | **YES** | set -u未束縛変数クラッシュ |
| kagemaru | cmd_delegate.sh | PASS* | bc空×6, verdict空 | **NO** | 二次データBLOCKゲート |
| tobisaru | gate_ninja_workaround_rate.sh | FAIL | bc空×7, verdict空 | **NO** | ALERT閾値判定欠如 |

*kagemaru: commit result='yes'のみ記入、AC1-AC3空。gate_report_format.shはcommit以外の空値を見逃した(gate coverage gap)

**一発PASS率: 4/6 = 67%**（予測50-67%の上限一致）

### 分析

**L4固有要素(3AC+FILL_THIS+実装): 6/6問題なし** — FILL_THIS全回避、実装品質良好、lesson_candidate全員found=true
**L1基礎(bc/verdict): 4/6 = 67%** — L2 R1と同パターンの認知負荷増大による回帰

FAIL原因はL4新要素ではなくL1基礎の回帰。L2 R1(67%)→R2(100%)、L3 R1(67%)→R2(100%)と同構造。
kagemaru+tobisaruは内容品質高いがbc/verdictの記入を忘れた。ヘッダー+フッター挟撃構造は3AC認知負荷下で一部の忍者に効かなかった。

**gate coverage gap発見**: kagemaru報告はcommit:yes以外のbc resultが全て空なのにgate PASS。gate_report_format.shはbc resultの「空文字」を個別チェックしていない箇所がある。tobisaruは全空でFAIL。

### 副産物: 実バグ発見5件（全修正済み）

1. context_freshness_check.sh: cutoff_14d=14日固定がSTALE_DAYSと不整合 (commit bd95daa)
2. daemon_watchdog.sh: 再起動ストーム防止機構なし (commit 65501e0)
3. archive_completed.sh: yaml.dump禁止違反+TMP外一時ファイル散在 (commit c1748d7)
4. gate_cycle_health.sh: set -u下で条件分岐内変数が未初期化 (commit 1e5caec)
5. gate_ninja_workaround_rate.sh: ALERT閾値判定なし (commit 636625c)

### §10 全ラウンド横断サマリ更新

| Level | Round | FP Rate | 環境改善 | 効果 |
|-------|-------|---------|---------|------|
| L1 | R1-R6 | 0%→100% | inline hints+header+bc除去+status | 累積100% |
| L2 | R1 | 67% | L1環境 | -33%(レベルアップ) |
| L2 | R2 | 100% | +footer checklist | +33% |
| L3 | R1 | 67% | +sgcスキャフォールド | -33%(レベルアップ) |
| L3 | R2 | 100% | +sgc inline hint | +33% |
| L4 | R1 | 67% | L3環境+3AC | -33%(レベルアップ) |

**4回連続: レベルアップ→67%回帰→環境改善→100%の法則**が成立するか、R2で検証。

## §16 L4 R2に向けた環境改善

### 自動化ターゲット

L2 R1→R2のフッター追加と同構造。bc/verdict空値の原因は「提出前チェックリストが目に入らない」。

案1: テンプレートのresultフィールドを `result: '' # yes or no` → `result: 'FILL_YES_OR_NO'` に変更。FILL_THISと同じ罠として機能させる
案2: フッターの「★提出前チェック」をより視覚的に強調（■■■ STOP ■■■等）
案3: 両方

→ 案1を採用。FILL_YES_OR_NOはgate_report_format.shでFILL_THIS同様にBLOCKされ、かつ忍者に値の種類を教示する。

## §18 L4 Round 2実績（2026-04-01）

### 環境改善（§16で設計）

- bcテンプレート: `result: ''` → `result: 'FILL_YES_OR_NO'`（gate BLOCKトラップ化）
- フッター強化: `■■■ STOP — 提出前に必ず確認 ■■■`（視覚的停止信号）
- FILL_YES_OR_NO残存チェックをdescriptionにも明記

### L4 Round 2結果

| 忍者 | 対象 | 初回gate | FAIL原因 | FP | R1比較 | Commit |
|------|------|---------|---------|-----|--------|--------|
| hanzo | ci_status_check.sh | PASS | — | **YES** | YES→YES | 7af662c |
| hayate | cmd_halt.sh | PASS | — | **YES** | YES→YES | 75089fe |
| kotaro | chronicle_metrics.sh | PASS | — | **YES** | YES→YES | cddf1dc |
| kagemaru | checklist_progress.sh | PASS | — | **YES** | **NO→YES** | 20d8ca8 |
| saizo | auto_deploy_next.sh | FAIL→自己修正→PASS | FILL_YES_OR_NO未置換+lu reason空 | **NO** | **YES→NO** | eb3d167 |
| tobisaru | clear_prep_check.sh | FAIL(偽陽性) | L225 reason内の"FILL_THIS"部分文字列検出 | **NO** | NO→NO* | 08c9c36 |

*tobisaru R1=bc全空(実質ミス)、R2=gate偽陽性(報告実質は完全)。スキルは向上したが計測上はNO→NO。

**一発PASS率: 4/6 = 67%**

### 分析

**初の「R2で100%未到達」**。L2/L3では1環境改善でR2=100%だったがL4 R2は67%。

原因分析:
1. **saizo(YES→NO)**: FILL_YES_OR_NOリテラルを7箇所全て未置換。R1では空文字テンプレートで正しくyes/noを記入していた。環境改善が逆効果（プレースホルダ文字列を「そのままでよい」と誤認した可能性）
2. **tobisaru(NO→NO*)**: L225 reasonに「FILL_THIS残存を防いだ」と書いたところ、gate_report_format.shのFILL_THIS部分文字列検出に引っかかった。報告の実質品質は完全。**gate偽陽性**
3. **kagemaru(NO→YES)**: R1でbc全空→R2でFILL_YES_OR_NO環境改善が効き全項目正しく記入。期待通り改善

### 環境改善の効果（忍者別）

| 忍者 | FILL_YES_OR_NO効果 | フッター効果 |
|------|-------------------|------------|
| hanzo | 不要(R1からYES) | 不要 |
| hayate | 不要(R1からYES) | 不要 |
| kotaro | 不要(R1からYES) | 不要 |
| kagemaru | **有効**(NO→YES) | 有効 |
| saizo | **逆効果**(YES→NO) | 無効 |
| tobisaru | 不明(gate偽陽性で判定不能) | 不明 |

### 副産物: 実バグ発見6件（全修正済み）

1. ci_status_check.sh: LAST_ALERT_FILE変数が書込みのみ・読取りなしのデッドコード (7af662c)
2. cmd_halt.sh: ntfy通知欠如。緊急停止で殿への通知がinboxのみ (75089fe)
3. chronicle_metrics.sh: 全期間集計のみで直近30日トレンドが不可視 (cddf1dc)
4. checklist_progress.sh: Markdownチェックボックス形式(- [ ]/- [x])未対応で実質非機能 (20d8ca8)
5. auto_deploy_next.sh: 報告YAML検証パスが命名規約と不整合でデッドコード化 (eb3d167)
6. clear_prep_check.sh: ALERT/OK判定+exit codeなしで自動化パイプライン連携不可 (08c9c36)

### §10 全ラウンド横断サマリ更新

| Level | Round | FP Rate | 環境改善 | 効果 |
|-------|-------|---------|---------|------|
| L1 | R1-R6 | 0%→100% | inline hints+header+bc除去+status | 累積100% |
| L2 | R1 | 67% | L1環境 | -33%(レベルアップ) |
| L2 | R2 | 100% | +footer checklist | +33% |
| L3 | R1 | 67% | +sgcスキャフォールド | -33%(レベルアップ) |
| L3 | R2 | 100% | +sgc inline hint | +33% |
| L4 | R1 | 67% | L3環境+3AC | -33%(レベルアップ) |
| L4 | R2 | **67%** | +FILL_YES_OR_NO+■■■STOP■■■ | **±0%(初の非回復)** |

### gate_report_format.sh偽陽性問題

tobisaruのFAILは**ゲートの検出ロジック問題**:
- 現状: `FILL_THIS`を値の**部分文字列**として検出
- 問題: 説明文中の正当な使用（「FILL_THIS残存を防いだ」）もBLOCK
- 修正案: 値が`FILL_THIS`で**始まる**場合のみ or 値**全体**が`FILL_THIS`の場合のみ検出

## §19 L4 R3に向けた環境改善

### R2→100%未達の根因

2つの独立した問題:

**問題1: FILL_YES_OR_NOが一部忍者で逆効果**
- kagemaru: 効いた（空→正しい値を記入）
- saizo: 逆効果（リテラル文字列をそのまま残した）
- 仮説: saizo は「FILL_YES_OR_NO」を「この値でOK」と誤解した可能性
- 対策: プレースホルダを `'???'` に変更。`???`は明らかに「要置換」を示し、かつgate検出容易

**問題2: gate偽陽性**
- gate_report_format.shのFILL_THIS検出が部分文字列マッチ
- 対策: gate修正（完全一致 or prefix一致に変更）。これはgate品質改善でありテンプレート変更ではない

### R3設計

1. gate_report_format.shのFILL_THIS検出を完全一致に修正 → **R3完了後に実施**（忍者稼働中はedit-guard）
2. bcテンプレート: `result: 'FILL_YES_OR_NO'` → `result: '' # yes or no`（inline hint回帰）
3. フッター維持（■■■ STOP ■■■）

## §20 L4 Round 3実績（2026-04-01）

### 環境改善（§19で設計）

- FILL_YES_OR_NO廃止→`result: '' # yes or no`（L1 R3で実証済みのinline hintに回帰）
- フッター(■■■ STOP ■■■)は維持
- gate偽陽性は未修正（忍者稼働中edit-guard）→手動修正指示で対応

### L4 Round 3結果

| 忍者 | 対象 | 初回gate | FAIL原因 | FP | R1→R2→R3 | Commit |
|------|------|---------|---------|-----|----------|--------|
| hanzo | report_field_set.sh | PASS | — | **YES** | YES→YES→YES | fa3fe9e |
| hayate | cmd_save.sh | PASS | — | **YES** | YES→YES→YES | fa3fe9e |
| kagemaru | lesson_write.sh | PASS | — | **YES** | NO→YES→YES | eb438b8 |
| saizo | model_switch_preflight.sh | PASS | — | **YES** | YES→NO→**YES** | ee08488 |
| tobisaru | gate_auto_respond.sh | PASS | — | **YES** | NO→NO→**YES** | (R3 commit) |
| kotaro | health_check.sh | FAIL(gate偽陽性)→修正→PASS | L225 reason内"FILL_THIS"部分文字列 | **NO*** | YES→YES→NO* | cc9ba1d |

*kotaro: gate偽陽性。L225 reason「FILL_THIS漏れ防止」→「プレースホルダ漏れ防止」に修正でPASS。スキル上は完全。

**Raw一発PASS率: 5/6 = 83%**
**gate偽陽性除外時: 6/6 = 100%**

### 分析

**環境改善が正しければパターンは成立する。**

R2の失敗原因: FILL_YES_OR_NOという「間違った環境改善」を投入。
R3の成功原因: inline hintへの回帰（L1 R3で実証済みの正しいアプローチ）。

| ラウンド | 環境改善 | 結果 | 判定 |
|---------|---------|------|------|
| R1 | なし | 67% | ベースライン |
| R2 | FILL_YES_OR_NO(新手法) | 67% | 間違った改善→効果ゼロ |
| R3 | inline hint回帰(実証済み手法) | 83%(真100%) | 正しい改善→パターン成立 |

**新発見**: 環境改善の選択が重要。実証済み手法の再利用 > 新手法の実験。これ自体がdeepdive Phase 5（自動化ターゲット特定）の教訓: 改善候補を実験するのではなく、過去の成功パターンから選択せよ。

### gate偽陽性の再発（2回目）

R2 tobisaru、R3 kotaroで同一パターン。L225が「FILL_THIS予防」を教える教訓であるため、有用理由に「FILL_THIS」と書くのは自然かつ正当。gate修正が必要（部分文字列→完全一致）。

### 副産物: 実バグ発見6件（全修正済み、L4通算17件）

1. gate_auto_respond.sh: CI赤検知のpython3外部依存(gh --jqで代替可) (tobisaru)
2. health_check.sh: タスク停滞検知がtimestamp参照(正: deployed_at) (kotaro)
3. lesson_write.sh: PROJECT_PATH解決コード2箇所重複(DRY違反) (kagemaru)
4. model_switch_preflight.sh: agent-CLI検出パターンが2名分ハードコード (saizo)
5. cmd_save.sh: q5_val抽出がコメント含むCMD_BLOCKを使用→誤マッチ (hayate)
6. report_field_set.sh: binary_checks検証コード2箇所重複(DRY違反) (hanzo)

### §10 全ラウンド横断サマリ最終版

| Level | Round | FP Rate | 環境改善 | 効果 |
|-------|-------|---------|---------|------|
| L1 | R1-R6 | 0%→100% | inline hints+header+bc除去+status | 累積100% |
| L2 | R1 | 67% | L1環境 | -33%(レベルアップ) |
| L2 | R2 | 100% | +footer checklist | +33% |
| L3 | R1 | 67% | +sgcスキャフォールド | -33%(レベルアップ) |
| L3 | R2 | 100% | +sgc inline hint | +33% |
| L4 | R1 | 67% | L3環境+3AC | -33%(レベルアップ) |
| L4 | R2 | 67% | FILL_YES_OR_NO(間違った改善) | ±0% |
| L4 | R3 | **83%(真100%)** | inline hint回帰(正しい改善) | +16%(真+33%) |

### L4完了判定

**条件**: 3+忍者がFirst-Pass PASS → **R3で5/6達成(gate偽陽性除外6/6)。L4完了。**

## §22 L4 Round 4実績（2026-04-01）— 品質監査継続

### 目的

L4完了後の品質監査継続。R4以降はFP率ではなく実バグ発見数が主KPI。

### L4 Round 4結果

| 忍者 | 対象 | FP | 実バグ | Commit |
|------|------|-----|--------|--------|
| hayate | inbox_write.sh | YES | YAMLシリアライズ重複→lib/write_inbox_yaml.py抽出 | ✓ |
| kagemaru | inbox_watcher.sh | YES | debounce flock非統一→write_state_file()統一 | ae1fc55 |
| hanzo | ntfy_listener.sh | YES | python3起動7回→parse_all_fields()で1回に | fa614f5 |
| saizo | pending_decision_write.sh | YES | TZ欠落3箇所→%:z付加 | d2cee89 |
| kotaro | gate_improvement_trigger.sh | YES | アラートパイプライン4箇所→send_alert()集約(40行削減) | ✓ |
| tobisaru | cmd_absorb.sh | YES | python3+PyYAML依存→awk方式置換 | 2cf9ecb |

**FP: 6/6 = 100%**（疾風はstall復旧後に完了）

### 副産物: 実バグ発見6件（L4通算23件）

1. inbox_write.sh: YAMLシリアライズ_sv()+atomic write 2箇所完全重複(DRY違反) (hayate)
2. inbox_watcher.sh: refresh_debounce_file()がflock未使用(排他制御非統一) (kagemaru)
3. ntfy_listener.sh: 同一JSON行に対するpython3起動7回(性能問題) (hanzo)
4. pending_decision_write.sh: タイムスタンプ3箇所がTZ情報なし(監査困難) (saizo)
5. gate_improvement_trigger.sh: 通知パイプライン4箇所散在(修正箇所4→1集約) (kotaro)
6. cmd_absorb.sh: check_stale_lessons()がpython3+PyYAML依存(環境非統一) (tobisaru)

### lesson_candidate 6件

| 忍者 | 教訓 |
|------|------|
| hayate | テストのSCRIPT_DIR書換え時の共有ライブラリパス追従必須 |
| kagemaru | ヘルパー関数統一後は既存同種処理のgrep網羅確認 |
| hanzo | 複数python3呼出の1回バッチ抽出パターン |
| saizo | date書式ISO8601 TZ付き(%:z)標準化 |
| kotaro | DRY違反検出は「変更時修正箇所数」で評価 |
| tobisaru | python3依存awk置換は2段階fallback(PJ固有→共通config) |

### decision_candidate 1件

- 才蔵: pending_decision_write.sh(L217,L351)のpython YAML書出しがCLAUDE.md安全規則違反。大規模改修要。優先度決定必要

### 備考

- 軍師がGP-134(scout_gate AWKバグ根絶: 77fabd7)とGP-133(BCスタブ自動生成: 706663a)を並行実装完了
- report_merge.doneワークアラウンドはGP-134により不要に

## §23 L4 Round 5実績（2026-04-02）— 品質監査継続

### L4 Round 5結果

| 忍者 | 対象 | FP | 実バグ | Commit |
|------|------|-----|--------|--------|
| hayate | gate_report_format.sh | YES | PASS cache flock未使用(race condition) | ✓ |
| kagemaru | dashboard_auto_section.sh | YES | TMP_METRICS二重ループ(I/O 1回削減+4行削減) | ✓ |
| hanzo | review_gate.sh | YES | フィールド参照バグ(title/description→command/purpose, **ゲート完全無効化**) | ✓ |
| saizo | workaround_pattern_check.sh | YES | regex値抽出が空クォート/複数語非対応(silent skip) | f40d445 |
| kotaro | lesson_effectiveness.sh | YES | reportファイル二重ループ(114×2→1回に削減) | ✓ |
| tobisaru | insight_write.sh | YES | yaml.dump禁止違反(L54,L121, Critical) | ✓ |

**FP: 6/6 = 100%**（5ラウンド連続100%）

### 副産物: 実バグ発見6件（L4通算29件）

1. gate_report_format.sh: PASS cache更新にflock未使用、並列実行でsed -i競合リスク (hayate)
2. dashboard_auto_section.sh: TMP_METRICSを2つのwhileループで読取、single-pass統合可 (kagemaru)
3. review_gate.sh: title/description参照だが実YAMLはcommand/purpose。**ゲートが常にSKIPし完全無効化** (hanzo)
4. workaround_pattern_check.sh: regex値抽出が空クォート値をsilent skip+複数語値を切り詰め (saizo)
5. lesson_effectiveness.sh: 同一glob 2回ループ、114ファイル×2→1回に統合 (kotaro)
6. insight_write.sh: writeモード+resolveモード両方でyaml.dump使用、CLAUDE.md安全規則違反 (tobisaru)

### 特筆: 半蔵のreview_gate.sh発見

review_gate.shがtitle/descriptionフィールドを検索していたが、タスクYAMLスキーマはcommand/purposeに変更済み。フィールド名不一致でゲートが常にSKIPを返し**完全に無効化**されていた。スキーマ変更時の参照箇所追従漏れ。

### lesson_candidate 6件

| 忍者 | 教訓 |
|------|------|
| hayate | PASS cacheとgate fire logで保護レベル不統一 — 排他制御は統一パターンで |
| kagemaru | single-pass最適化: 同一データソースの複数whileループは統合せよ |
| hanzo | ゲートの検索フィールドはスキーマ変更時に追従が必要 |
| saizo | YAML値抽出regexは空クォート/複数語/unquotedの3パターン全対応必須 |
| kotaro | reportループ統合パターン: 同一globの複数パーサーは単一ループ内で逐次実行 |
| tobisaru | YAML全書き戻しはコメント文字列でもhookにブロックされる |

### 備考

- deploy_task.shのscout_gateが修行→本番cmd切替時にBLOCK。手動配備workaround使用(cmd_1671/cmd_1672)
- 旧修行報告84件をarchive/reports/stale/にアーカイブ(ninja_monitor偽陽性防止)
- cmd_1672(deploy_task.sh direct mode)が本構造問題の根治策

## §21 修行サイクル全体サマリ（L1→L2→L3→L4）

### 定量結果

| Level | テーマ | ラウンド数 | 最終FP率 | 環境改善回数 | 実バグ発見数 |
|-------|--------|----------|---------|------------|------------|
| L1 | 基礎(報告構造) | 6 | 100% | 4回 | 0 |
| L2 | 教訓(lesson_candidate) | 2 | 100% | 1回 | 3 |
| L3 | レビュー(self_gate_check) | 2 | 100% | 1回 | 0 |
| L4 | 総合(3AC+実装) | 5 | 100% | 2回(1回失敗) | **29** |

### 累積実績

- **総ラウンド数**: 15
- **総実バグ発見**: 32件（全修正済み）
- **環境改善**: 8回（うち1回失敗=FILL_YES_OR_NO）
- **核心パターン**: レベルアップ→67%回帰→正しい環境改善→100%回復

### 核心教訓（全レベル統合）

1. **環境改善は複利で効く**: L1の6回の改善(header/footer/inline hint/etc)はL4まで持続
2. **レベルアップ→回帰→回復パターン**: 5回実証。新スキル追加で67%に回帰するが1環境改善で回復
3. **正しい改善の選択が重要**: L4 R2で間違った改善(FILL_YES_OR_NO)→効果ゼロ。実証済み手法の再利用が安全
4. **修行=訓練+品質監査の二重効果**: 26実バグ発見は予想外の副産物。idle時間を有効活用
5. **gate偽陽性は計測を歪める**: FILL_THIS部分文字列検出が正当な使用をBLOCK。ゲート自体の品質管理も必要（R3後に修正済み）
6. **deepdive Phase 4-5の実証**: 知識を環境に埋め込む(自動化×強制)ことでLLMの/clear→知識喪失問題を克服
7. **品質監査継続の価値**: R4でFP100%維持+実バグ6件。環境安定後もラウンドごとに新バグを発見し続ける

## §24 L4 R7実績（2026-04-02）— mixed編成初修行

### 編成
| 忍者 | CLI | モデル |
|------|-----|--------|
| hayate | Codex | GPT-5.4 |
| saizo | Codex | GPT-5.4 |
| kagemaru | Claude | Sonnet 4.6 |
| kotaro | Claude | Sonnet 4.6 |
| hanzo | Claude | Opus 4.6 |
| tobisaru | Claude | Opus 4.6 |

### 配備方式: 手動(cat > task YAML)。deploy_task.sh非使用→報告テンプレートなし

### R7結果（モデル別）

| 忍者 | モデル | 対象 | 初回gate | FP | FAIL原因 |
|------|--------|------|---------|-----|---------|
| hayate | GPT-5.4 | auto_draft_lesson.sh | FAIL→PASS | **NO** | assumption_invalidation detail欠落 |
| saizo | GPT-5.4 | build_instructions.sh | FAIL→PASS | **NO** | assumption_invalidation MISSING |
| kagemaru | Sonnet 4.6 | cmd_quality_log.sh | FAIL→PASS | **NO** | files_modified/purpose_validation/assumption_invalidation欠落 |
| kotaro | Sonnet 4.6 | ac_physical_verify.sh | PASS | **YES** | — |
| hanzo | Opus 4.6 | lesson_confirm.sh | PASS | **YES** | — |
| tobisaru | Opus 4.6 | checklist_update.sh | PASS | **YES** | — |

**モデル別FP率: Opus 2/2(100%), Sonnet 1/2(50%), GPT 0/2(0%)**

## §25 L4 R8実績（2026-04-02）— テンプレート付き検証

### 配備方式: deploy_task.sh --direct。報告テンプレートあり（18フィールド+assumption_invalidation scaffold）

### R8結果（モデル別）

| 忍者 | モデル | 対象 | 初回gate | FP | FAIL原因 |
|------|--------|------|---------|-----|---------|
| hayate | GPT-5.4 | agent_status.sh | PASS | **YES** | — |
| saizo | GPT-5.4 | api_usage.sh | PASS | **YES** | — |
| kagemaru | Sonnet 4.6 | auto_failure_lesson.sh | FAIL→PASS | **NO** | bc AC self-verification missing(0/3) |
| kotaro | Sonnet 4.6 | cmd_friction_log.sh | FAIL→PASS | **NO** | bc AC self-verification missing(0/3) |
| hanzo | Opus 4.6 | cli_lookup.sh | PASS | **YES** | — |
| tobisaru | Opus 4.6 | conversation_retention.sh | PASS | **YES** | — |

**モデル別FP率: Opus 2/2(100%), Sonnet 0/2(0%), GPT 2/2(100%)**

### R7→R8比較分析

| モデル | R7(テンプレートなし) | R8(テンプレートあり) | 変化 |
|--------|---------------------|---------------------|------|
| Opus 4.6 | 100% | 100% | 安定 |
| Sonnet 4.6 | 50% | 0% | 悪化(FAILパターン移動) |
| GPT-5.4 | 0% | 100% | テンプレートで改善 |

**核心発見**:
1. テンプレート追加でGPTが劇的改善(0%→100%)。GPTはテンプレート構造依存度が高い
2. Opusは両条件で100%安定。テンプレート有無に関わらず自力でフィールドを構造化できる
3. Sonnetはテンプレートがあってもbc AC構造を書き換えてしまう（50%→0%）。FAILパターンがassumption_invalidation→bc ACに移動しただけ
4. **テンプレートは共通FAILパターンを潰すが、モデル固有の弱点は別フィールドに移動する**
5. R9ではcommandにbc構造維持ヒントを追加して検証

### 環境改善履歴（mixed編成）

| Round | 環境改善 | Opus FP | Sonnet FP | GPT FP |
|-------|---------|---------|-----------|--------|
| R7 | なし(手動配備) | 100% | 50% | 0% |
| R8 | +テンプレート | 100% | 0% | 100% |
| R9 | +bc構造維持ヒント | — | — | GPT 1/2(50%) |
| R10 | bc構造ヒント継続 | — | 1/2(50%) | 2/2(100%) |

※R9: Sonnet/Opus全員STALL。GPTのみ完了(才蔵FP=YES、疾風FP=NO verdict:None)
※R10: 殿指示でSonnet+Codex 4名のみ。Opus訓練停止

## §26 R11-R12 テスト速度最適化（2026-04-02）— 殿指示ネタ変更

### 殿指示
修行ネタをテスト速度最適化に変更。docs/research/test-optimization-journal.md参照。
確立済みパターン: 巨大スクリプトフル実行→関数抽出→source→単体テスト化(48倍/16倍/21倍実証)。

### R11結果（Sonnet+Codex 4名）

| 忍者 | モデル | 対象 | Before→After | 倍率 | テスト数 |
|------|--------|------|-------------|------|---------|
| 疾風 | GPT-5.4 | review_quality | 28.2s→2.1s | **13.6x** | 5/5 PASS |
| 才蔵 | GPT-5.4 | warning_levels | 120s→1.7s | **68.9x** | 12/12 PASS |
| 影丸 | Sonnet 4.6 | ac_verify | 13.9s→1.3s | **11x** | 8/8 PASS |
| 小太郎 | Sonnet 4.6 | cmd_save | 6.3s→0.9s | **7x** | 21/21 PASS |

**全4名成功。累計高速化: 168.4s→6.0s**

### R12結果（Sonnet+Codex 4名）

| 忍者 | モデル | 対象 | Before→After | 倍率 | 状態 |
|------|--------|------|-------------|------|------|
| 才蔵 | GPT-5.4 | stale_field_reset(29t) | 14.1s→1.3s | **10.8x** | ✅ |
| 影丸 | Sonnet 4.6 | pending_decision(19t) | 8.1s→4.8s | 1.7x | ❌固定コスト制約 |
| 小太郎 | Sonnet 4.6 | lesson_write(20t) | 6.5s→1.5s | 4.4x | ❌固定コスト制約 |
| 疾風 | GPT-5.4 | ac_version(31t) | 32.8s | STALL | ❌Codex処理不能 |

### 新知見: bats固定コスト制約

**10倍目標は30秒超のテストでのみ有効。** 5-10秒帯はbats起動コスト(0.5-0.7s)が支配的で物理的に10倍不可能。影丸・小太郎が独立に同一結論に到達。次回から目標を「30秒超→10倍、10秒未満→3倍」に分離すべき。

### Codex(GPT-5.4) STALL傾向 — **N=1で結論を出すな（殿指摘で修正）**

R12で疾風がdeploy_task.sh(2000行)テスト最適化でSTALL。当初「大型ファイル不向き」と結論したが、R13で才蔵がcmd_complete_gate.sh(3985行)を24倍高速化で成功。**ファイルサイズが原因ではない**ことが反証された。STALLの真因は未特定（Codexプロンプト待ち/nudge未到達/個体差の可能性）。N=1の事象で配備ルールを作るな。
