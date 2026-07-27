---
name: three-layer-penetrate
quality_metric: "全ロール: 貫通宣言時に3層それぞれの実測証跡が揃っている割合"
description: |
  全ロール使用可。知見・裁定・規律を三層記憶(記憶DB+セマンティック+Obsidian)へ貫通させ、
  各層から独立に検索到達可能なことを実測してから「貫通した」と宣言する手順を標準化する。
  state=PASSやOK出力だけで貫通完了と判断する事故(成功の顔をした未貫通)を構造的に防止する。
  TRIGGER: /three-layer-penetrate、三層記憶に貫通させよ、三層貫通、知見を三層に書き込む、貫通したか？
  DO NOT TRIGGER: 三層記憶の検索のみ（→semantic_search.sh / memory_db_query.sh直接）、
  MEMORY.md/MCP Memoryの整理（→/dream）、教訓登録（→lesson_write系）
argument-hint: "[知見の1行要約]"
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /three-layer-penetrate — 三層記憶貫通の標準手順

貫通の定義（殿裁定）: **3層全てに書き込み、各層から独立に検索到達可能にすること。**
掲示板投稿・contextファイル更新・知識1層書込みだけでは未貫通。

## 手順（書込み3ステップ+検証3ステップ）

### Step 1: Layer1 — 記憶DB書込み

```bash
bash scripts/memory_db_knowledge_write.sh "<知見全文。★必ず origin: [[発端]] -> [[原因]] -> [[結果]] のObsidianリンクを本文に含めよ>" "<source識別子>"
```

- **[[リンク]]を本文に含めないとLayer3候補が0件のままstate=PASSが返る**（2026-07-27軍師実測: リンクなし投入=layer3候補0件でPASS、リンクあり再投入=候補10件生成）。PASSは貫通の証明ではない
- 出力の `knowledge:<event_id>` を控える（Step 4以降で使用）

### Step 2: Layer2 — セマンティックSSOTへ概念追加

**semantic-map.mdを直接Editするな。mapは生成物である。** 正=SSOT→再生成:

```bash
# 1) docs/semantic-index/index.md へ概念セクションを追加（既存セクションの書式を踏襲:
#    id / label / aliases（殿・自分が実際に発した言い回しを含める） / related_concepts、
#    参照表に file / memory(knowledge:ID) / discussion(origin付き) を記載）
# 2) 再生成
bash scripts/semantic_map_generate.sh
```

- 既存概念への追記で足りる場合は新概念を作らない（重複概念=検索劣化）
- aliasには「探す側の言葉」（殿の発話原文の断片）を入れる

### Step 3: Layer3 — Obsidian因果ネットワーク

Step 1の本文originに`[[リンク]]`を含めていればknowledge書込みが候補生成する。
加えて関連するcontext/lessons/設計書のorigin欄に同じ`[[リンク]]`を記す（因果の道を双方向に）。

### Step 4: 3層それぞれを実測検証（宣言前必須・省略厳禁）

```bash
# L1: event_idで到達するか（★検索語は特徴的な単語1語で。複合語クエリはFTS不一致で偽陰性になる=2026-07-27スキル検証で実測）
bash scripts/memory_db_query.sh --search "<本文中の特徴的な単語1語>" | grep <event_id先頭8桁>
# L2: alias層で直接ヒットするか（MEMORY_DB_MATCHはフォールバック=Layer2未到達の証拠）
bash scripts/semantic_search.sh "<殿の言い回し>"   # 出力先頭が「## <概念id>」であること
# L3: 候補が生成されたか
grep "<[[リンク]]名>" .cache/causal_index.tsv || echo "candidate待ち(memory_candidate_pendingで確認)"
```

**検証NGパターン**: `semantic_search`の出力が`MEMORY_DB_MATCH:`で始まる=alias層miss（Layer2未貫通）。SSOT追加とmap再生成をやり直せ。

### Step 5: commit固定

```bash
bash scripts/ninja_scope_commit.sh -m "knowledge: <要約>を三層貫通 L1=knowledge:<id> L2=<概念id> L3=origin [[...]]" -- docs/semantic-index/index.md context/semantic-map.md
```

- scope_sync BLOCK（partial/foreign staged）が出たら: stagedの追加内容がworktree版に包含されるかを機械照合（特徴片grep）で実証してから `git add` で整合→再実行。包含されないなら他者のWIP=待て
- 未commitの貫通は/clearや他者のツリー操作で消える（LS-A14）

### Step 6: 宣言

3層の実測証跡（L1=event_id・L2=alias層ヒット出力・L3=候補生成/リンク）を添えて「貫通完了」と報告する。
証跡なしの「貫通した」宣言は禁止（宣言と実体の乖離=2026-07-27の支配的欠陥形）。

## 背景知見（2026-07-27確立）

- 「実装したが接続していない」が支配的欠陥形: 書いた≠読まれる、PASS≠貫通、存在確認≠呼ばれる確認
- semantic-map直接Edit事故: mapはSSOT(index.md)からsemantic_map_generate.shで生成される。逆方向の編集は次回生成で消える
- 関連: [[gist_master_three_step_rule]]（gist正本3点セット規律）、knowledge:09d1f6767ea56bee（state=PASSでは貫通を確認できない）
