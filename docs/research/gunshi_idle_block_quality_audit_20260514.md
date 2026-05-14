# BLOCK全量品質監査 — ゲート品質問題・インフラバグ探索

日付: 2026-05-14
分析者: 軍師(gunshi)
対象: gate_fire_log.yaml (4,231件) + cmd_design_quality.yaml (3,483件)

## 全体像

| 指標 | 値 |
|------|-----|
| gate_fire_log総数 | 4,231件 (PASS:1,902 / FAIL:907 / AUTO-FIXED:856 / UNFIXABLE:485) |
| cmd_design_quality総数 | 3,483件 (CLEAR:1,411 / BLOCK:1,365 / WARN:519 / PASS:188) |

## 発見1: FAIL率の劇的改善 — 免疫系は機能中

| 週 | 件数 | FAIL | FAIL率 |
|----|------|------|--------|
| W16 (4/13-19) | 941 | 550 | 58.4% |
| W17 (4/20-26) | 590 | 152 | 25.8% |
| W18-W19 (4/27-5/10) | 1,142 | 195 | 17.1% |
| W20 (5/11-14) | 133 | 10 | **7.5%** |

1ヶ月で58%→7.5%。7.8倍改善。FAIL→PASS遷移の93%が5分以内。免疫系正常。

## 発見2: 忍者別FAIL率格差（5月全体 → 5/10以降）

| 忍者 | 5月全体 | 5/10以降 | モデル |
|------|---------|----------|--------|
| saizo | 13.5% | **8.3%** | GPT |
| hayate | 11.1% | **9.7%** | GPT |
| hanzo | 21.2% | **10.0%** | Sonnet |
| kagemaru | 20.0% | **28.2%** | GPT |
| tobisaru | 37.1% | **27.2%** | Sonnet |
| kotaro | 27.0% | **38.0%** | Sonnet |

5/10以降でkagemaru(28.2%)とkotaro(38.0%)が悪化傾向。

## 発見3: ゲート品質問題3件

### P1: gate_report_format_combined.py Traceback (3件)

- 対象: kagemaru_report_cmd_2656.yaml (2026-05-10T15:56)
- 症状: Python Tracebackがgate_fire_logにreason="Traceback (most recent call last):"として記録
- L130-133のTraceback処理ロジックが`_LAST_ERR`を取得できず、元のTracebackテキストのみ記録
- 根因推定: YAMLのparse error（ファイルアーカイブ済みで再現不可）またはUTF-8 encoding問題
- 影響: 3件のFAILが誤った理由で記録。忍者はgateメッセージから修正内容を判断できない
- **推奨**: Traceback発生時は`$RESULT`全文をgate_fire_logに記録せよ（現在は1行目のみ）

### P2: cmd_complete_gate 外部PJのnode_modules偽陽性 (1件, WARN)

- 対象: cmd_2702 (rebalancer偵察) → 924 files uncommitted WARN
- 根因: rebalancerリポジトリの__pycache__/cacheファイル462件がuncommittedとして検出
- L1627の除外パターンにgitignore対象（node_modules/__pycache__/cache等）が含まれていない
- 影響: WARNのみでBLOCKではない。直接害なし。ただしログノイズ
- **推奨**: `git -C "$project_path" diff --name-only` の代わりに `git -C "$project_path" diff --name-only -- ':!*.pyc' ':!*__pycache__*' ':!*node_modules*' ':!*.json'` またはgitignore尊重モード

### P3: 同一ファイル連続FAIL 20回 (hayate_report_cmd_2080, 4月)

- 20回連続FAILは異常値。原因: bc result空文字+lessons_useful reason空+lesson_candidate未記入
- gateは正しく検出しているが、忍者が20回FIXヒントを見ても修正できなかった
- **FIXヒントの品質問題**: 「空文字。yesまたはnoを記入せよ」というヒントが具体性不足の可能性
- 4月の問題でW20では解消。要経過観察

## 発見4: cmd_save.sh偽陽性修正効果

| チェック | 修正前BLOCK+WARN | cmd_2703修正後(5件) |
|----------|------------------|---------------------|
| q11 | 72件 | **0件** |
| ac_param_sufficiency | 32件 | **0件** |
| command_steps | 57件 | **0件** |
| ac_phase_mixing | 59件 | **0件** |

cmd_2703修正は即効。4チェック合計220件の偽陽性が根絶。

## 発見5: FAIL reason TOP3 = テンプレート不備集中

| # | 件数 | reason |
|---|------|--------|
| 1 | 305 | lesson_candidate: found=false but no no_lesson_reason |
| 2 | 293 | binary_checks: MISSING |
| 3 | 266 | lessons_useful[n]: reason is empty |

TOP3で864件（FAIL907件の95%）。全て「テンプレートの必須フィールド未記入」。
gateの品質問題ではなく、正当なFAIL。gateが正しく機能している証拠。

## 発見6: WARN累計昇格がBLOCK最大源 (274件/1,365件=20%)

cmd_design_qualityで最大のBLOCK源はWARN累計昇格(同じWARNが繰返し→BLOCK化)。
check_ac_phase_mixing(28件)とquality_gate_q(19件)が上位。
→ cmd_2703で一部修正済みだが、残りのWARN→BLOCK昇格パターンに偽陽性が潜んでいないか要検証。

## 結論

| 分類 | 件数 | 深刻度 | ステータス |
|------|------|--------|-----------|
| **ゲート正常動作(真のFAIL)** | ~900件 | - | 免疫系正常 |
| **P1: Traceback記録不完全** | 3件 | P2-中 | 未修正。ログ品質問題 |
| **P2: 外部PJ偽陽性WARN** | 1件 | P3-低 | WARN止まり。ログノイズ |
| **P3: 連続FAIL 20回** | 1件 | P3-低 | 4月の問題。解消済み |
| **cmd_2703偽陽性修正** | 220件 | - | **修正済み。効果確認** |
| **WARN累計昇格偽陽性候補** | 未計測 | P2-中 | 要追加調査 |

**全体評価**: BLOCKにゲート品質問題は2件(P1,P2)あるが、深刻なインフラバグはなし。
免疫系(FAIL→PASS遷移)は正常機能中。FAIL率7.8倍改善は定量的に実証済み。
