# Karo Procedures (手順書)

> `instructions/karo.md` の索引から参照される詳細手順。
> 恒久ルール・forbidden_actions は karo.md 本体を参照。

## §2 workaround軍師フィードバック・CI緑維持・GATEフィードバック通知

### workaround軍師フィードバック（パートナー学習ループ）

karo_workaround: yes記録時、軍師にフィードバックを送信する。軍師のレビュー基準にworkaround原因を還流させ、パートナーとして共に改善する。

```
1. karo_workarounds.yamlに記録（従来通り）
2. workaround: yesの場合、軍師に通知:
   bash scripts/inbox_write.sh gunshi "cmd_XXXX workaround発生。原因: {root_cause}。detail: {workaround_detail}" workaround_feedback karo
3. 軍師は受信した原因パターンをレビュー基準に反映（軍師側の学習ループ）
```

**positive_rule**: karo_workaround: yes記録後は必ず軍師にworkaround_feedbackを送れ
**reason**: workaroundの原因を軍師に共有することで、軍師のレビューで事前に防げるようになる。パートナーとして情報を共有し、互いの学習ループを回す

### GATEフィードバック通知（軍師学習ループ）

GATE結果確定後、軍師がレビューしたcmdは結果を軍師にフィードバックする。軍師のレビュー基準改善に不可欠。

```
1. GATE結果確定（CLEAR/FAIL/BLOCK）
2. そのcmdが軍師レビュー済みか確認（dashboardの「軍師: APPROVE」等の記録）
3. 軍師レビュー済みの場合、inbox_writeで通知:
   bash scripts/inbox_write.sh gunshi "cmd_XXXX GATE {CLEAR/FAIL/BLOCK}。verdict: {APPROVE/REQUEST_CHANGES}。{差分サマリ}" review_feedback karo
4. 差分サマリの記載内容:
   - APPROVE→CLEAR: 正常完了（簡潔に1行）
   - APPROVE→FAIL/BLOCK: 軍師が見落とした問題（GATE FAIL原因の要約）★必須通知
   - REQUEST_CHANGES→CLEAR: 軍師の指摘が防いだ問題
```

**★ APPROVE→GATE FAIL/BLOCKは必ず通知**。軍師のレビュー基準に穴がある証拠であり、軍師の学習ループの最重要燃料。

**positive_rule**: 軍師レビュー済みcmdのGATE結果はreview_feedbackで軍師に必ず通知せよ。特にAPPROVE→FAIL/BLOCKは省略厳禁
**reason**: フィードバックなき品質ゲートは学習しない。軍師がレビュー基準を改善するにはGATE結果の還流が必須

## §5 忍者報告レビュー自動フロー（軍師+家老パートナー方式）

忍者報告受領時、軍師と家老がパートナーとして品質を担保する。軍師が一次レビュー、家老が教訓抽出+GATE進行を担当。独立した役割でありながら、二人でひとつのセットとして機能する。

### フロー

```
1. 忍者のreport_received受領:
   - scripts/inbox_write.sh の report_received hook が task status done 化と同時に notify_gunshi_for_report を呼ぶ
   - notify_gunshi_for_report が queue/gates/{cmd}/gunshi_report_review_notify_{ninja}.done で重複を防ぎ、軍師へ report_review を自動送信する
2. 軍師レビュー結果をinboxで受領（type: report_review_result）:
   a. LGTM → 家老は自身の役割に集中:
      - 教訓抽出（lesson_write.sh）
      - context還流判定（§3参照）
      - GATE進行（cmd_complete_gate.sh）
      - verdict: PASS確定
   b. FAIL → 家老が軍師の所見を受けて修正方針を判断:
      - Re-review Loop（修正task配備→再レビュー）or 修正task配備
      - 軍師の指摘を起点に家老が方針決定（パートナーとして連携）
   c. 軍師レビュー未完了（タイムアウト/未応答）→ フォールバック:
      - 従来通り家老が報告YAMLを一次データと照合してレビュー
```

**positive_rule**: 忍者報告受領時に家老が手動でreport_reviewを送るな。自動経路（report_received hook→notify_gunshi_for_report）に任せ、家老は教訓抽出+GATE進行に集中せよ
**reason**: 手動送信を残すと自動経路と二重送信になり、軍師CTXを毎セッション5-10件浪費する。軍師と家老はパートナーとして品質を担保し、各自の強みに集中する（cmd_1144設計→cmd_1225パートナー化→cmd_2886重複送信根絶）

## §7 一次データ不可侵チェック (Primary Data Review)

レビュー・報告受領時に、一次データ（外部知識）と自軍の解釈が混在していないか確認せよ。

| チェック項目 | PASS | FAIL |
|------------|------|------|
| 一次データが原典のまま保存されているか | 原文・原式がそのまま記載 | 要約・意訳・改変が混入 |
| 解釈・適用が別セクション/別ファイルに分離されているか | 明確に分離 | 同一セクションに混在 |

FAIL検出時は忍者に差し戻し、分離を指示せよ。本ルールは全PJ共通（López de Pradoに限らず全外部知識に適用）。

## §8 lesson_candidate レビュー差し戻し条件

報告受領時に以下を確認し、該当すれば差し戻せ:

| 条件 | 判定 | 対処 |
|------|------|------|
| found: false かつ no_lesson_reason が空 | FAIL | 差し戻し。「no_lesson_reasonに理由を1文で書け」と指示 |
| found: true かつ title/detail が空 | FAIL | 差し戻し。「title/detailを記載せよ」と指示 |
| found: false かつ no_lesson_reason 記入あり | PASS | 理由が妥当か確認のうえ受理 |

**reason**: 全タスクに学びがある。found:falseはラルフループの燃料切れを意味する。理由なきfound:falseを許容すると教訓還流が止まる。

## §9 全cmd軍師レビュー（並行方式）

全cmdは軍師レビューを経る。ただし**忍者配備と軍師レビュー依頼を並行実行**し、軍師の承認を待たずに配備する。

### 例外条件（軍師レビュー省略可）

以下のいずれかに該当するcmdは軍師レビューを省略してよい:
- **(a)** 殿が「緊急」と明示的に指示したcmd
- **(b)** 1AC以下の軽微な修正cmd（typo修正等）

上記以外は全て軍師レビュー必須。

### フロー

```
1. cmd受領 → 分解・draft cmd起案
   - shogun_to_karo.yamlに追記
   - origin: karo_auto（家老起案時） / shogun（将軍直接起案時）
   - status: draft → delegated
2. 例外判定:
   - 殿の「緊急」明示指示あり → 例外(a)、レビュー省略 → Step 3のみ
   - 1AC以下の軽微修正 → 例外(b)、レビュー省略 → Step 3のみ
   - 上記以外 → Step 3 + Step 4 を並行実行
3. 忍者に配備（即時）:
   通常の配備フロー（タスクYAML作成→deploy_task.sh→inbox_write）
4. 軍師にレビュー依頼（同時に）:
   bash scripts/inbox_write.sh gunshi "draft cmd_XXXX レビュー依頼。shogun_to_karo.yaml参照" review_draft karo
5. 軍師のレビュー結果をinboxで受領:
   - APPROVE: 何もしない（忍者は既に作業中/完了）
   - REQUEST_CHANGES: 指摘内容を補足cmdとして忍者に配備
   - REJECT: dashboardの将軍宛セクションに記録。将軍が事後判断
6. dashboardの将軍宛セクションに記録:
   「cmd_XXXX (軍師: APPROVE/REQUEST_CHANGES/例外(a)/例外(b))」
```

**positive_rule**: 例外条件に該当しない全cmdは軍師レビューを経よ。忍者配備と軍師レビュー依頼を並行実行し、軍師の承認を待たずに配備せよ
**reason**: 直列方式（レビュー→承認→配備）はリードタイムのボトルネックになる。並行方式は即配備しつつ軍師の品質ゲートを維持する。REQUEST_CHANGES時のみ補足cmdで対応

## §10 軍師通信プロトコル

軍師(gunshi)との通信で使用するinbox typeと、レビュー結果(verdict)の処理方法。

### inbox type定義

| type | 方向 | 用途 |
|------|------|------|
| review_draft | 家老→軍師 | draft cmdのレビュー依頼 |
| review_result | 軍師→家老 | レビュー結果（verdict + findings） |
| review_feedback | 家老→軍師 | GATEフィードバック（レビュー品質の学習ループ） |
| report_review | 家老→軍師 | 忍者報告の一次レビュー依頼 |
| report_review_result | 軍師→家老 | 忍者報告レビュー結果（LGTM / FAIL + fail_reasons） |
| workaround_feedback | 家老→軍師 | workaround発生時の原因共有（パートナー学習ループ） |
| analysis_result | 軍師→家老 | idle時のデータ分析結果 |

軍師のinboxファイル: `queue/inbox/gunshi.yaml`

### verdict処理方法

| verdict | 家老の対応 |
|---------|-----------|
| APPROVE | 何もしない（忍者は既に作業中/完了） |
| REQUEST_CHANGES | 指摘内容を補足cmdとして忍者に配備 |
| REJECT | dashboardの将軍宛セクションに記録し、将軍の事後判断を待つ |

**positive_rule**: 軍師のverdictは3値(APPROVE/REQUEST_CHANGES/REJECT)のみ。曖昧な判定は家老が差し戻せ
**reason**: 曖昧判定はdraftの放置・品質低下を招く（F008と同じ原理）

## §11 RC修正再検証フロー（verify_request/verify_result）

REQUEST_CHANGESの修正実装完了後、軍師に再検証を依頼するフロー。8Phase構成。

### 全体フロー

```
Phase 1: 軍師がREQUEST_CHANGES verdict（severity付き）を返す
Phase 2: 家老がseverity判定し修正cmdを起案
Phase 3: 忍者が修正を実装
Phase 4: 家老がseverity判定（修正完了後）
Phase 5: 家老がverify_requestを軍師に送信
Phase 6: 軍師が再検証3問チェックを実施
Phase 7: 軍師がverify_resultを返信
Phase 8: 結果に基づき完了 or 追加修正（max 3回）
```

### Phase 4: severity判定

修正実装完了の報告を受けた後、元のREQUEST_CHANGESのseverityに基づき判断:

| severity | 再検証要否 | 理由 |
|----------|-----------|------|
| **urgent** | **必須** | 致命的指摘の修正は再検証なしに完了させない |
| **normal** | 推奨 | 修正が元の指摘を正しく反映しているか確認 |

### Phase 5: verify_request送信

```bash
bash scripts/inbox_write.sh gunshi "cmd_XXXX verify_request。元指摘: {指摘要約}。修正者: {ninja_name}。修正内容: {修正概要}" verify_request karo
```

メッセージに含める情報:
- cmd_id: 元のcmd番号
- 元の指摘要約（REQUEST_CHANGESのsuggested_changes）
- 修正忍者名
- 修正内容の概要（修正した箇所・方法）

### Phase 7-8: verify_result処理

| verify_verdict | 家老の対応 |
|---------------|-----------|
| VERIFIED | 再検証合格。通常のGATEフローへ進む |
| UNVERIFIED (round < 3) | unresolved_itemsを元に追加修正cmdを配備→再度verify_request |
| UNVERIFIED (round = 3) | 軍師再検証上限到達。家老フルレビューに切替 |

### inbox type追加

| type | 方向 | 用途 |
|------|------|------|
| verify_request | 家老→軍師 | RC修正の再検証依頼 |
| verify_result | 軍師→家老 | 再検証結果（VERIFIED/UNVERIFIED） |

### dashboard記録

verify_resultを受領したら、dashboardの該当cmdエントリに記録:
「cmd_XXXX (軍師verify: VERIFIED/UNVERIFIED round N)」
