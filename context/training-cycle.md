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

## §14 次のアクション

1. **L4検討**: 総合(3AC, FILL_THIS罠)。殿判断待ち
2. **yaml.dump撲滅**: deploy_task.sh L1016/L1485の大規模リファクタ（別タスク）
3. **kotaro R1発見検証**: report_field_setマルチライン値YAML構造破壊の確認
4. 本番cmdが来たら修行は中断し本番優先
