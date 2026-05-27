# Gate偽陽性分析+修正 — 将軍cmd起票能力の壁

## 日付
2026-05-27

## 殿の指示
「将軍のCMD起票能力を覚醒させよ、利他の精神。ブロックやwarnはGateの品質問題が隠れているはず」

## 発見

### 全期間データ
- BLOCK: 305件、WARN: 258件
- cmd_save.sh起票回数(source=cmd_save*): ~563件

### 偽陽性3件(計264件)

#### 1. ファイルパス切り詰め (163件/53% of BLOCK)
- **根因**: pat正規表現が`.tsv`を`.ts`に、`.jsonl`を`.json`に部分マッチ → 切り詰めパスが存在しない → BLOCK
- **追加根因**: skip_keysに`assumption`未登録 → 旧フォーマットのフリーテキストからパス誤抽出
- **影響**: 20ユニークcmd、1cmdあたり平均8回リトライ。cmd_1940/cmd_3066で各10回BLOCK
- **修正**: negative lookahead `(?![a-zA-Z])` + skip_keysに`assumption`追加
- **commit**: 81367363

#### 2. ac_phase_mixing (65件)
- **根因**: 「計測機能を追加」= 計測が実装対象(目的語)。同一AC内にimpl+measureキーワード共起 → 偽WARN
- **証拠**: cmd_3069のdiagnosisに「ACから計測キーワード排除」の記載。将軍がGate偽陽性を回避するためにcmd文言を歪めた
- **修正**: 日英の目的語パターン(計測.*を.*追加/implement.*measurement)を免除
- **commit**: 7cab4b18

#### 3. q8_縮小表現 (36件)
- **根因**: scope_mode=exactで「のみ」「だけ」は正当な範囲限定。例: 「IDF項のみR(c)に置換」
- **修正**: scope_mode=exactをfocusedと同様に免除
- **commit**: 7cab4b18

### 正当なGate(真陽性)
- 否定的前提grep反証なし (45件): 品質向上。正当
- 研究cmd道具未記載 (42件): 正当
- q11既存代替現物確認なし (42件): 正当
- q9消火cmd真因未記入 (34件): 正当

## 検証
- ファイルパス: 5パターンregexテスト(tsv→no match, ts→match, sh→match, jsonl→no match, assumption→skip)
- ac_phase_mixing: 3テスト(FP免除2件+TP発火1件)
- 全体: 103 batsテスト全PASS

## 因果チェーン
殿指示(Gate品質問題)→データ集計(BLOCK305件)→Top1(163件ファイルパス)→sha256再現→regex切り詰め発見→D0修正→Top2(65件ac_phase_mixing)→cmd_3069 diagnosis証拠→目的語パターン免除→Top3(36件q8縮小)→exact免除→264件偽陽性根絶
