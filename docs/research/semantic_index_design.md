# セマンティクスインデックス設計書
<!-- created: 2026-05-04 | author: shogun | status: draft -->
<!-- motivation: /clear後にセマンティック辞書構想を概念で引けなかった事故(2026-05-04) -->

## §1 背景・動機

### 事故

2026-05-04、将軍が/clear後に殿の「セマンティック辞書」構想を思い出せなかった。
MEMORY.mdには「双方向整合性」としか書かれておらず、lord_conversationをgrepして初めて発見。
殿が別表現を使っていたら発見不能だった。

### 殿の指摘

> 「まさにこれがセマンティクスインデックスが必要な理由だ」(2026-05-04 22:53)

### 殿の構想(2026-05-04 20:10)

> 「セマンティック辞書と単語定義辞書が完成したら勘違いは起きなくなるか？」

2本立て:
1. **単語定義辞書**(disambiguation) — 用語の1語1意味定義 → **完成済み**(cmd_2553-2561)
2. **セマンティクスインデックス** — 概念で情報を引ける逆引きマップ → **本設計書**

## §2 なぜなぜ7回

| # | 問い | 到達 |
|---|------|------|
| 1 | なぜ必要か | /clear後に概念で情報を引けない。文字列検索のみ |
| 2 | なぜgrepでは不足か | 同概念が異表現(「セマンティック辞書」「意味検索」「概念索引」)。文字列一致は1表現しか引けない |
| 3 | なぜ構造化が必要か | MEMORY.mdはファイルベース索引。「Xに関わる全情報」を1クエリで引く手段がない |
| 4 | なぜCoDDか | 手動更新は忘れる(意志依存)。上流変更→propagateで下流自動追随。用語辞書で実証済み |
| 5 | なぜ環境埋込みか | deepdive Phase 4: LLMに生存本能はない。gate/hookで更新漏れを強制検出 |
| 6 | なぜ全体スコープか | PJ限定だと殿との対話・インフラ議論が対象外。今回の事故はPJ横断 |
| 7 | なぜ既存(MEMORY/MCP)では不足か | MCPはentity/observation。MEMORY.mdはファイル索引。概念→関連リソース群マッピングではない |

## §3 設計原則（用語辞書パターン踏襲）

### 3層構造

```
用語辞書で実証済み:
  SSOT(上流)        → 索引(下流)              → gate(環境埋込み)
  disambiguation.md → dm-signal-terminology.md → check_dm_signal_bare_layer_reference

セマンティクスインデックスも同じ(全てMarkdown。CoDDはMD形式):
  SSOT(上流)                    → 索引(下流)              → gate+hook(環境埋込み)
  docs/semantic-index/index.md  → context/semantic-map.md  → gate(鮮度)+hook(更新催促)
  (全てmulti-agent-shogunリポ内。クロスリポ不要)
```

### 殿の設計原則(用語辞書から継承)

- **1語1意味(MECE)** → **1概念→1リソース群(重複なし)**
- **CoDDで上流→下流自動伝播** → 同
- **セマンティック双方向整合性** → 正方向(index変更→索引追随)+逆方向(ファイル変更→index欠落検出)
- **環境埋込み** → gate/hookで意志依存ゼロ

## §4 SSOT構造: docs/semantic-index/index.md

ファイル: `docs/semantic-index/index.md` (multi-agent-shogunリポ内)
形式: Markdown(CoDDフロントマター付き。propagate対象)
配置理由: 将軍システム全体スコープ。DM-Signal固有概念もインフラ概念も同一リポで管理。クロスリポpropagateを回避。

```markdown
---
codd:
  type: semantic-index
  propagates_to:
    - context/semantic-map.md
---

# セマンティクスインデックス SSOT

## recalculate_pipeline — 再計算パイプライン

| 属性 | 値 |
|------|---|
| aliases | fullrecalculate, recalc, 再計算 |

### リソース

| 種別 | パス/参照 |
|------|----------|
| file | backend/app/jobs/recalculate_fast.py |
| file | context/dm-signal-ops.md §6 |
| discussion | lord_conversation 2026-04-22 ETL cron 5本→4本 |
| discussion | lord_conversation 2026-04-22 過去データ不変の暗黙前提禁止 |
| lesson | PI-005, LS-A16 |

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| aliases | セマンティクス辞書, 意味検索, 概念インデックス |

### リソース

| 種別 | パス/参照 |
|------|----------|
| file | docs/research/cmd_2555_disambiguation_design.md |
| file | docs/research/semantic_index_design.md |
| discussion | lord_conversation 2026-05-04 20:10 セマンティック辞書と単語定義辞書 |
| discussion | lord_conversation 2026-05-04 20:53 セマンティック検索をしてみよう |

## gate_bypass_prevention — gate迂回防止

| 属性 | 値 |
|------|---|
| aliases | gate迂回, 滑り坂, 正規フロー |

### リソース

| 種別 | パス/参照 |
|------|----------|
| file | scripts/cmd_delegate.sh |
| file | scripts/pre-bash-combined.sh (Guard 4) |
| discussion | lord_conversation 2026-04-19 cmd_2134事故 |
| lesson | LS-A07 |
| deepdive | memory/deepdive_causal_tracing_20260415.md Phase 6 |
```

### 概念の粒度

- 機能/テーマ単位(「再計算パイプライン」「gate迂回防止」等)
- 1概念あたりリソース3-15件が目安
- 粒度が粗すぎる(>20件) → 分割
- 粒度が細かすぎる(1-2件) → grepで十分。インデックス不要

### 概念の追加ルール — 3分割(なぜなぜ7回結論)

用語辞書は「定義」(変更頻度低い→手動)。インデックスは「マッピング」(新知識のたびに更新→自動化必須)。
性質が違うのに形だけ真似るのはcausal_tracing Phase 3-4と同じ間違い。

| 機能 | 方式 | 理由 |
|------|------|------|
| 既存概念へのリソース追加 | **自動**(hookでaliases照合) | マッピングは機械的 |
| 新概念の検出 | **自動**(未マッチ→insight_write) | 検出は機械的 |
| 新概念の定義 | **人間**(ラベル+aliases設計) | 設計判断は人間の仕事 |

### 自動リソース追加(既存概念)

3つの既存自動化フローにフックを追加:

```
1. cmd_complete_gate.sh (cmd完了時)
   → report YAMLのfiles_modified + title + purpose を取得
   → index.mdの全概念のaliasesと照合
   → マッチした概念のresourcesにファイルパスを自動追記

2. lesson_write.sh / lesson_write_shogun.sh (lesson追加時)
   → lesson ID + title + enforcement を取得
   → index.mdのaliasesと照合
   → マッチした概念のlessonsに自動追記

3. lord_conversation記録時 (殿の裁定)
   → 発言summaryをindex.mdのaliasesと照合
   → マッチした概念のdiscussionsに自動追記
```

### 新概念の自動検出

上記3フローで**どの概念にもマッチしない**場合:
→ `insight_write.sh "新概念候補: {ソース}がインデックス未対応"` を自動実行
→ startup gateが「未処理insight N件」で表示
→ 将軍/軍師が概念ラベル+aliases を設計して追加

### 新概念の定義(人間の仕事)

- 概念ラベル: 機能/テーマ単位で命名
- aliases: 同概念の別表現を列挙(grepで引けるように)
- 粒度: 3-15リソースが目安
- **全量列挙不要**: 事故ドリブン+自動検出で有機的成長

## §5 索引層: context/semantic-map.md

```markdown
# セマンティクスマップ（索引）
<!-- auto-generated from docs/semantic-index/index.md -->
<!-- do not edit directly — use CoDD propagate -->

| 概念 | 別名 | 主要ファイル | 教訓 |
|------|------|------------|------|
| 再計算パイプライン | fullrecalculate, recalc | recalculate_fast.py, dm-signal-ops.md §6 | PI-005, LS-A16 |
| セマンティック辞書構想 | 意味検索, 概念索引 | cmd_2555_design.md, 本設計書 | — |
| gate迂回防止 | 滑り坂, 正規フロー | cmd_delegate.sh, Guard 4 | LS-A07 |
```

エージェント起動時: semantic-map.md を読む → 概念ラベルor別名でgrepできる → リソース群にアクセス

## §6 CoDDとの接続

### 正方向: index変更→索引追随

| 手段 | トリガー | 動作 |
|------|---------|------|
| CoDD propagate | index.md変更をgit diff検出 | semantic-map.mdを自動再生成 |
| 手動propagate | 概念追加/変更時 | `codd propagate --update` でsemantic-map.md更新 |

### 逆方向: ファイル変更→index欠落検出

| 手段 | トリガー | 動作 |
|------|---------|------|
| セマンティック欠落チェック | リソースファイル変更時(軍師idle) | 変更ファイルがindex内のどの概念にも紐づかない場合→新概念候補として報告 |

## §7 環境埋込み

### gate(startup)

```bash
# gate_shogun_startup.sh に追加
# セマンティクスインデックス鮮度チェック
semantic_index="docs/semantic-index/index.md"
if [ -f "$semantic_index" ]; then
  last_mod=$(stat -c %Y "$semantic_index")
  now=$(date +%s)
  age_days=$(( (now - last_mod) / 86400 ))
  if [ $age_days -gt 14 ]; then
    echo "ALERT: セマンティクスインデックスが${age_days}日間未更新"
  fi
fi
```

### hook — 自動リソース追加(§4 3分割の実装)

#### 共通ヘルパ: semantic_index_update.sh

3入口の照合ロジックを1スクリプトに統合(Codex所見5)。責務分離: SSOT更新とCoDD propagateを分ける(Codex所見2)。

```bash
# scripts/semantic_index_update.sh <source_type> <payload>
# source_type: cmd_complete | lesson | discussion
# payload: JSON文字列(files, title, id等)
#
# 処理フロー:
#   1. index.mdの全概念aliasesをロード
#   2. payloadのテキストとaliases照合(部分一致+正規化)
#   3. confidence判定(Codex所見6: C案閾値分岐)
#      HIGH(aliases完全一致 or 2+aliases部分一致) → 自動追記
#      LOW(1 alias部分一致のみ) → 候補キュー(insight_write)
#      NONE(マッチなし) → 新概念候補(insight_write)
#   4. 自動追記時: index.mdに追記 → commit
#   5. propagate発火は別ステップ(post-commitでcodd propagate)
```

#### フック先3箇所(全て semantic_index_update.sh を呼ぶ)

| フック先 | トリガー | payload |
|---------|---------|---------|
| cmd_complete_gate.sh | cmd完了 | `{files: files_modified, title, purpose}` |
| lesson_write.sh | lesson追加 | `{id: lesson_id, title, enforcement}` |
| log_terminal_input.sh | 殿の発言記録時 | `{summary, timestamp}` |

#### confidence閾値分岐(Codex所見6: C案)

| confidence | 条件 | 動作 |
|-----------|------|------|
| HIGH | aliases完全一致 or 2+部分一致 | index.mdに**自動追記** |
| LOW | 1 alias部分一致のみ | `insight_write` で候補キュー → 将軍/軍師が承認後追記 |
| NONE | マッチなし | `insight_write "新概念候補"` → 将軍/軍師が概念定義 |

#### 責務分離(Codex所見2)

```
semantic_index_update.sh → index.md更新(SSOT)
                                ↓
                           codd propagate → semantic-map.md再生成
                                ↓
                           git commit(index.md + semantic-map.md を一括)
```

調査結果: git post-commit hookは未設定。新設よりも、semantic_index_update.sh内で
SSOT更新→propagate→一括commitの直列実行が現実的。
CoDDのpropagateはMD形式対応済み(用語辞書cmd_2560で実証)。

### hook(pre-commit)

変更ファイルがindex内概念のresources.filesに含まれる場合:
→ 「この変更はindex概念 X に影響。index更新が必要か確認せよ」をWARN表示

### 軍師idle

既存のidle Step 7(セマンティック監査)に追加:
- `semantic_index_drift`: indexのresources.filesが存在するか確認(参照切れ検出)
- `semantic_index_gap`: 頻出ファイルがどの概念にも紐づかない場合→新概念候補
- `semantic_index_candidate`: insight_writeされた新概念候補を集約→概念定義を提案

## §8 検索インターフェース — 2層検索(なぜなぜ7回結論)

### なぜ2層か

aliases照合だけでは今回の事故(「セマンティック辞書構想」を忘失)は再発する。
aliasesに未定義の表現(殿が「意味の逆引き表」と言った場合等)はマッチしない。
**aliases照合=構造化されたgrep**であり、真のセマンティック検索ではない。

解決: 高速な第一層(aliases) + 高精度な第二層(LLM意味照合)の2層構造。

| 層 | 方式 | 速度 | 精度 | 用途 |
|---|------|------|------|------|
| 第一層 | aliases照合(grep) | 即時 | aliasesに依存 | 起動時・自動フック |
| 第二層 | LLM意味照合(claude --print) | 数秒 | 高(未知表現も引ける) | 手動検索・第一層未マッチ時 |

### スクリプト: semantic_search.sh

```bash
# scripts/semantic_search.sh "再計算"
#
# 第一層: aliases照合(即時)
#   → index.mdの全概念label/aliasesをgrep照合
#   → マッチした概念のresources全量を表示
#
# 第一層マッチなし → 第二層自動フォールバック:
#   → claude --print "index.mdの概念一覧を読み、
#      '$query' に最も関連する概念を3つ選べ。
#      理由も1行ずつ付けよ。" < index.md
#   → LLMが意味理解でマッチング
#   → マッチした概念のresources表示 + aliases追加候補を提案
```

### 自動フックでの使い分け

- §7の自動リソース追加フック: **第一層のみ**(高速。cmd完了のたびにLLM呼び出しはコスト過大)
- confidence LOW/NONE → insight_write(第二層は人間の手動検索時に使う)

### エージェントの使い方

1. 起動時: semantic-map.md を一覧で読む(概念ラベル+別名+主要ファイル)
2. 特定概念の詳細: `grep -A20 "recalculate_pipeline" index.md`
3. CLI検索: `bash scripts/semantic_search.sh "再計算"` (第一層→第二層自動フォールバック)
4. 直接LLM検索: `bash scripts/semantic_search.sh --llm "殿が前に話していた辞書の設計の件"` (第二層強制)

## §9 lord_conversationとの連携

### 設計判断

lord_conversation.jsonlの構造変更は影響範囲が大きい(inbox_watcher, lord_conversation_write等)。
→ **別途マッピング**: index.md内のdiscussionsフィールドに「lord_conversation タイムスタンプ 要約」で参照。
→ lord_conversation.jsonlには手を入れない。

### 利点

- lord_conversationの既存構造を壊さない
- 概念に紐づく殿の発言をピンポイントで引ける
- 新しい議論が発生 → index.mdのdiscussionsに1行追加

## §10 段階的実装ロードマップ

| 段階 | 内容 | 依存 | トリガー |
|------|------|------|---------|
| 0 | 本設計書確定(殿承認+軍師レビュー) | — | 殿承認時 |
| 1 | index.md初期版作成(10概念)+semantic-map.md生成 | 段階0 | 段階0 GATE CLEAR |
| 2 | startup gate追加+検索スクリプト第一層(aliases照合) | 段階1 | 段階1 GATE CLEAR |
| 3 | 自動追加フック(semantic_index_update.sh)+3入口接続 | 段階2 | 段階2 GATE CLEAR |
| 4 | 検索スクリプト第二層(LLM意味照合フォールバック) | 段階3 | 段階3 GATE CLEAR |
| 5 | CoDD propagate自動化+軍師idle組込み(drift/gap/candidate) | 段階4 | 段階4 GATE CLEAR |

### 初期10概念の選出根拠

事故履歴(情報を引けなかった実績)+頻出テーマ(cmd/lesson/discussionの出現頻度)から選出:

| 概念 | 選出根拠 |
|------|---------|
| 再計算パイプライン | cmd頻出(fullrecalculate高速化cmd_955-2016) |
| セマンティック辞書構想 | 本日の事故(構想忘失) |
| gate迂回防止 | deepdive Phase 6事故(cmd_2134) |
| 用語辞書 | cmd_2553-2561(14cmd。PJ横断) |
| 本番パリティ | PI-007+チェックリスト2本。cmd頻出 |
| deepdive原理 | 毎セッション必読。全エージェント参照 |
| 学習ループ | 殿厳命。成長ループ3層。全cmdに関わる |
| ALM研究 | dm-signal-ops §31。浄化→再構築の大型テーマ |
| 四神設計 | 殿設計原理。DNA制約。shijin-design.yaml |
| 編成管理 | config/settings.yaml。/henseiスキル。モデル切替 |

## §11 既存インフラとの整合性

| 既存 | 役割 | セマンティクスインデックスとの関係 |
|------|------|-------------------------------|
| MEMORY.md | ファイルベース索引 | 補完(MEMORY=ファイル索引、SI=概念索引) |
| MCP Memory | 殿の好み・将軍教訓 | 補完(MCP=observation、SI=概念マップ) |
| context/*.md | 詳細コンテキスト | SI.resourcesの参照先 |
| lord_conversation.jsonl | 殿との対話時系列 | SI.discussionsの参照先 |
| **lord-conversation-index.md** | **直近24hの時系列索引(conversation_retention.sh自動生成)** | **重複なし。LC-index=時系列(直���24h自動生成)、SI=概念逆引き(恒久的手動+自動)。次元が異なる** |
| 用語辞書(disambiguation.md) | 1語1意味定義 | 補完(辞書=用語定義、SI=概念逆引き) |

重複なし。各層は独自の役割を持ち、SIは「概念→リソース群マッピング」という新しい次元を追加する。
