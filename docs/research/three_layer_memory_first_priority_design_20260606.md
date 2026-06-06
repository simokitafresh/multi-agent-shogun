# 三層記憶第一優先化 L0-L7貫通設計書

## 問題定義

殿が「三層記憶は順調か？」と質問 → 将軍はMEMORY.mdの「2層長期記憶」で回答 → 正解は「記憶DB+Obsidian+セマンティックインデックス」（殿定義2026-05-24）。

SessionContextのmemory_db_fts5に殿の定義発言が注入されていたが将軍は読まなかった。3回連続で同じ間違いを繰り返した。

## 根因分析（なぜなぜ7回）

1. なぜ定義を間違えた → 記憶DBを検索しなかった
2. なぜ検索しなかった → MEMORY.mdの記述で「知っている」と思い込んだ
3. なぜ思い込んだ → MEMORY.mdが結論/定義を含み「十分な回答ソース」として機能
4. なぜMEMORY.mdが優先された → L0自動ロードで常に目の前にある。記憶DBはL5注入で奥に埋もれる
5. なぜ奥に埋もれた注入を読まない → 読まなくてもBLOCKされない（強制なし）
6. なぜ強制がない → L2(軍師CSレビュー)に三層記憶活用観点がゼロ。L1(startup gate)に検索二値チェックなし
7. **根因: 三層記憶が「あれば使う」の意志依存。L0-L7で「使わなければ止まる」の強制がない**

殿の指摘: MEMORY.md削除は各論パッチ。三層記憶を第一優先かつ絶対条件にすれば、MEMORY.mdを削除しなくても三層記憶が使われる。

## 現状L0-L7マップ

| Level | 現状 | 三層記憶の接続 | 穴 |
|-------|------|-------------|-----|
| L0 | instructions/shogun.md Step 1.7 | 「記憶DB起点」ルール記載 | ルールは意志依存。三層全体(DB+Obsidian+セマンティック)への言及なし |
| L1 | gate_shogun_startup.sh | search_logs件数表示+gate_three_layer_health.sh | DB健全性のみ。「殿の質問に三層記憶で回答したか」の計測なし |
| L2 | gate_gunshi_cs_checklist.sh | **0件** | 軍師レビューで三層記憶活用を検証する観点が完全欠落 |
| L3 | cmd_save.sh | live_insert書込み(7件)+coverage map(記憶DB関連cmd用) | 書込み側のみ。将軍の回答品質での読み出し検証なし |
| L4 | deploy_task.sh | memory_db_concept_lesson_boosts(14件) | 忍者への注入は機能。将軍への効果はL4スコープ外 |
| L5 | prompt_state_inject.sh | memory_db_fts5注入+semantic_knowledge注入+引用警告 | **注入は動作。読み出し強制なし。将軍が読まなくても通過** |
| L6 | growth-loop.md | **0件** | 三層記憶活用のFAIL→PASS遷移が追跡されていない |

## 軍師覚醒レビュー第1往復 (2026-06-06T17:58)

### 穴1: 表示しても読まない
軍師指摘: 表示→読む→引用の3段階で「読む」が意志依存。回答テンプレート(引用欄+FILL_THIS)が最小介入。
将軍の返答: 正しい。さらに掘る。テンプレートを出しても将軍がMEMORY.mdから引用欄を埋めたら意味がない。
→ **[MEM]タグにsource制約を導入**: `[MEM: memory_db ts=YYYY-MM-DD "原文"]` or `[MEM: semantic concept=XXX]` or `[MEM: obsidian link=[[XXX]]]`。MEMORY.mdのセクション名は不可。これでMEMORY.md迂回を構造的に封じる。

### 穴2: grep偽陰性
軍師指摘: lord_conversation.jsonl内の引用形式が多様。[MEM]タグ導入で100%精度。
将軍の返答: [MEM]タグ採用。ただし軍師が見落とした穴: **[MEM]タグを「形式的に」記入する洗脳#6(出力=仕事)のリスク。** タグを書くだけで中身を確認しない可能性。
→ **L2(軍師CSレビュー)で[MEM]タグのsource先と質問の関連性を検証する観点を追加。**

### 穴3: 原理分散
軍師指摘: 5箇所に同じ原理を独立に書くと将来の更新で不整合。正本1箇所+参照構造にすべき。
将軍の返答: 採用。instructions/shogun.md Step 1.7に原理を書き、他のLevelはStep 1.7を参照。

---

## 設計: 三層記憶第一優先化 (v2 — レビュー反映)

### 原則（正本: instructions/shogun.md Step 1.7）

**三層記憶(記憶DB+Obsidian+セマンティック)を将軍の回答の第一情報源にする。**
MEMORY.mdは索引として残すが、回答の根拠にはしない。回答の根拠は必ず三層記憶から[MEM]タグで引用する。

### [MEM]タグ仕様

将軍が殿の質問に回答する際、三層記憶からの引用を以下の形式で記載する:
```
[MEM: memory_db ts=2026-05-24 "記憶ＤＢ、obsidian、セマンティックインデックスがある"]
[MEM: semantic concept=growth_loop "三層学習ループ=個/対/全"]
[MEM: obsidian link=[[LS-A23]] "記憶DB原則"]
```
- source種別は `memory_db` / `semantic` / `obsidian` の3種のみ。`memory_md` は不可
- L1計測: `grep -c '\[MEM:' lord_conversation.jsonl` で100%精度
- L2検証: 軍師がsource先と質問の関連性を確認（形式的記入=洗脳#6の検出）

### L0: ルール強化（原理の正本）

**変更先**: instructions/shogun.md Step 1.7（正本） + CLAUDE.md（Step 1.7参照ポインタ）

現状: 「記憶DB起点」（記憶DBのみ言及）
変更後: 「三層記憶起点」（記憶DB+Obsidian+セマンティックの3層全て）+ [MEM]タグ強制

```
1.7. **三層記憶起点（殿厳命2026-05-22, 拡張2026-06-06）**:
殿の全入力に対して、行動の前にまず三層記憶を検索せよ。
  (1) 記憶DB: SessionContextのmemory_db_fts5結果を読め
  (2) セマンティック: SessionContextのsemantic_knowledge結果を読め
  (3) Obsidian: 関連[[リンク]]から因果をたどれ
MEMORY.mdで「知っている」と感じても三層記憶で確認せよ。
MEMORY.mdは索引。回答の根拠にするな。
回答には[MEM]タグで引用元を明記: [MEM: memory_db ts=YYYY-MM-DD "原文"] / [MEM: semantic concept=XXX] / [MEM: obsidian link=[[XXX]]]
```

他のLevelはこのStep 1.7を参照する（原理分散禁止: 軍師レビュー穴3対応）。

### L1: startup gate計測追加

**変更先**: gate_shogun_startup.sh

追加計測: 「前セッションで殿の質問N件に対し、三層記憶引用が含まれた回答は何件か」
データソース: lord_conversation.jsonlの殿inbound質問数 vs 将軍outbound回答内の「記憶DB」「semantic」「[[」引用数

```bash
# Gate XX: 三層記憶活用率
lord_questions=$(grep -c '"direction":"inbound"' "$lord_conv" 2>/dev/null || echo 0)
shogun_refs=$(grep '"direction":"response"' "$lord_conv" 2>/dev/null | grep -cE '記憶DB|semantic|memory_db|\[\[' || echo 0)
echo "  三層記憶引用率: $shogun_refs/$lord_questions"
if [[ "$lord_questions" -gt 3 && "$shogun_refs" -eq 0 ]]; then
    alerts+=("三層記憶引用率0%: 殿の質問に三層記憶を使っていない")
fi
```

### L2: 軍師CSチェックリスト追加（レビュー穴2対応 — 形式的記入検出）

**変更先**: gate_gunshi_cs_checklist.sh（Step 1.7参照）

追加CS観点: [MEM]タグの存在+関連性検証

```
CS-X: 三層記憶活用(Step 1.7参照)
  (a) [MEM:]タグが回答/cmd設計に含まれるか → なければ WARNING
  (b) [MEM:]のsource先が殿の質問/cmdの目的と関連があるか → 無関係なら洗脳#6(形式的記入)
  (c) MEMORY.mdセクション名のみの参照で[MEM:]なし → MEMORY.md迂回の兆候
```

### L5: 注入→[MEM]タグ回答テンプレート強制（レビュー穴1対応）

**変更先**: prompt_state_inject.sh

現状: `semantic_quote_warning` で引用を促すメッセージを表示
問題: **表示しても読まなかった実績が3回連続**（軍師指摘）

変更: 質問検知時に[MEM]タグ付き回答テンプレートを強制表示（Step 1.7参照）

```
⚠ 殿の質問検知(Step 1.7: 三層記憶起点)。以下を確認してから回答せよ:
[記憶DB] {fts5検索結果の上位3件}
[セマンティック] {semantic_knowledge概念名+aliases}
回答に[MEM: source]タグで引用元を明記せよ。MEMORY.md参照は不可。
タグなし回答 = 洗脳#2(検証スキップ)。
```

注意: [MEM]タグの形式的記入(洗脳#6リスク)はL2(軍師CSレビュー)で検出する。

### L6: 学習速度追跡

**変更先**: gate_shogun_startup.sh L6セクション

追加追跡: 三層記憶活用率のFAIL→PASS遷移
- FAIL = 殿の質問に三層記憶引用なしで回答（L1で計測）
- PASS = 引用あり

### L0-L7穴の修正サマリ

| Level | 穴 | 修正内容 |
|-------|-----|---------|
| L0 | 記憶DBのみ言及 | 三層記憶(3層)に拡張+MEMORY.md=索引明記 |
| L1 | 検索二値チェックなし | 三層記憶引用率計測+0%時ALERT |
| L2 | 観点完全欠落 | CS-X三層記憶活用観点追加 |
| L5 | 読み出し強制なし | 質問時の三層記憶結果強制表示+引用促進 |
| L6 | 遷移追跡なし | 引用率FAIL→PASS遷移追跡 |
| L3/L4 | 穴なし(書込み側は機能) | 変更不要 |

## 軍師覚醒レビュー第3往復(最終) — 残穴2件対処

### 残穴1: L1計測grepパターン未更新
v1のgrepパターン(`記憶DB|semantic|memory_db|\[\[`)がL96-104に残存。[MEM]タグ採用後は`grep -c '\[MEM:' lord_conversation.jsonl`に統一。L96-104を削除しL67の定義のみ参照する。

### 残穴2: 全入力vs質問のみ
Step 1.7「殿の全入力に対して」は過剰。定型指示(配備/クリア/修行)にfts5検索を強制するとCTX+時間コスト。
→ **質問時(？含む/概念定義/裁定確認/順調か)のみ[MEM]タグ強制。** 定型指示は三層記憶検索推奨だが強制しない。
→ Step 1.7を修正: 「殿の質問に対して」+「定型指示でも可能な限り三層記憶を参照」

### v3最終: Step 1.7修正版
```
1.7. **三層記憶起点（殿厳命2026-05-22, 拡張2026-06-06）**:
殿の質問(？含む/概念定義/裁定確認/順調か等)に対して、回答前に三層記憶を検索せよ。
  (1) 記憶DB: SessionContextのmemory_db_fts5結果を読め
  (2) セマンティック: SessionContextのsemantic_knowledge結果を読め
  (3) Obsidian: 関連[[リンク]]から因果をたどれ
MEMORY.mdは索引。回答の根拠にするな。
回答には[MEM]タグで引用元を明記: [MEM: memory_db ts=YYYY-MM-DD "原文"] / [MEM: semantic concept=XXX] / [MEM: obsidian link=[[XXX]]]
定型指示(配備/クリア/修行等)でも可能な限り三層記憶を参照。
```

---

## 影響範囲

- instructions/shogun.md: Step 1.7書換え
- CLAUDE.md: 記憶DB起点→三層記憶起点
- gate_shogun_startup.sh: Gate追加(引用率計測)
- gate_gunshi_cs_checklist.sh: CS観点追加
- prompt_state_inject.sh: 質問時強制表示強化
- context/growth-loop.md: L6追跡項目追加

## リスク

- L5の強制表示がCTX圧迫 → fts5結果は上位3件に制限（既存と同じ）
- L1の計測がlord_conversation grep依存 → false negative（引用が別の表現）→ 初期はWARNのみ、精度確認後BLOCK昇格

## 因果リンク

- ← [[LS046]] 概念混同パターンマッチ → 三層記憶不使用が根因
- ← [[LS-A23]] 記憶DB原則(5)道具を使わない=さぼり → L0-L7で強制
- ← [[deepdive_why_chain Phase 4]] 自動化×強制 → 三層記憶にも適用
- → [[growth-loop §11]] L6学習速度最大化 → 三層記憶活用率を追跡対象に追加
