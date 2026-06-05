# context ディレクトリ
<!-- last_updated: 2026-06-05 cmd_training_L4_backlinks_20260605a_kagemaru -->

プロジェクト固有のコンテキストを管理する索引層。詳細データは `docs/research/*.md` に置き、context側は結論・参照先・grep入口を保持する。詳細ルールは [[AGENTS]] のDesign for Retrieval節を正本とし、関連運用は [[infrastructure]]、概念到達は [[semantic-map]] を参照する。

## 目的
- プロジェクトごとの知識・決定事項を保存
- セッション間での情報共有
- 新規参加者（足軽）への引継ぎ
- contextファイル同士を直接 [[ファイル名]] リンクで接続し、因果探索で孤立知識を作らない

## ファイル構成
```
context/
  README.md              ← このファイル
  {project_id}.md        ← プロジェクト固有のコンテキスト
  doc-style-guide.md     ← ドキュメントスタイルガイド（Vercel実証5原則）
  infrastructure.md      ← インフラ知識ベース
  growth-loop.md         ← 成長ループ設計
  semantic-map.md        ← 概念検索・関連ファイル到達の入口
  training-cycle.md      ← 忍者修行サイクル設計
  dm-signal.md           ← DM-signalプロジェクトコンテキスト
```

## 関連コンテキスト
- [[doc-style-guide]]: context/*.mdの記述密度・索引化ルール
- [[growth-loop]]: 二値計測・知見還流・環境埋込みの共通設計
- [[infrastructure]]: inbox、gate、hook、tmux、記憶DBなどの運用正本
- [[semantic-map]]: 曖昧な語から関連context・script・skillへ到達する概念索引
- [[training-cycle]]: 修行タスクで報告品質とcontextリンク密度を育てる設計
- [[codd]]: CoDD仕様・設計・伝播の入口
- [[cmd-chronicle]]: cmd履歴の索引層
- [[lord-conversation-index]]: 殿との対話記録と記憶DBの索引

## 記述ルール
- context/*.md は [[doc-style-guide]] に従い、1-2行結論 + 参照先パス + 必要なら§番号/grep語で書く
- 調査詳細・経緯・表は `docs/research/*.md` に保存し、context側からリンクする
- 圧縮時は先にリンク先を作成し、存在確認してからcontextを索引化する
- 用語や到達先が曖昧な時は [[semantic-map]] と `bash scripts/semantic_search.sh "<query>"` を使う
- ファイル間リンクを追加する時は [[obsidian-link-principles]] に従い、孤立知識を作らない

## 使い方

### 新規プロジェクト追加時
1. `context/{project_id}.md` を作成
2. 下記テンプレートに沿って記載
3. [[semantic-map]] または [[codd]] 側の索引に新規contextの到達経路を追加

### 作業開始時
1. 自分のCLIが自動ロードする指示ファイルを基準にせよ（Codex=`AGENTS.md`, Claude=`CLAUDE.md`）
2. `context/{project_id}.md` を読む（プロジェクト固有情報）
3. 深掘りが必要な時だけ `docs/research/*.md` を参照せよ

## テンプレート

```markdown
# {project_id} プロジェクトコンテキスト
最終更新: YYYY-MM-DD

## 基本情報
- **プロジェクトID**: {project_id}
- **正式名称**: {name}
- **パス**: {path}
- **Notion URL**: {url}（あれば）

## 概要
{プロジェクトの概要を1-2文で}

## 技術スタック
- 言語:
- フレームワーク:
- データベース:

## 重要な決定事項
- {決定1}
- {決定2}

## マイルストーン
- **期限**: YYYY-MM-DD（{イベント名}）

## 進行状況
- [x] 完了タスク
- [ ] 未完了タスク

## 注意事項
{プロジェクト固有の注意点}
```

## 更新ルール
- 重要な決定があったら即座に更新
- 日付を必ず更新
- 不要になった情報は削除（シンプルに保つ）
- 削除ではなく圧縮する場合は、リンク先なき圧縮を避ける

## 因果リンク
- ← [[AGENTS]] Design for Retrieval = context/*.mdの記述ルール正本
- → [[doc-style-guide]] context記述密度と索引化ルール
- → [[obsidian-link-principles]] Obsidianリンク品質の原則
- → [[infrastructure]] インフラ運用コンテキストの入口
- → [[semantic-map]] 概念検索・関連ファイル到達の入口
- → [[training-cycle]] 修行タスクがcontextリンク密度を育てる仕組み
- → [[cmd-chronicle]] cmd履歴・完了記録の索引
- → [[lord-conversation-index]] 殿との対話記録・記憶DBの索引
