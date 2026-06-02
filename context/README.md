# context ディレクトリ
<!-- last_updated: 2026-06-03 cmd_karo_training_backlinks_readme_20260603 -->

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
  dm-signal.md           ← DM-signalプロジェクトコンテキスト
```

## 記述ルール
- context/*.md は [[doc-style-guide]] に従い、1-2行結論 + 参照先パス + 必要なら§番号/grep語で書く
- 調査詳細・経緯・表は `docs/research/*.md` に保存し、context側からリンクする
- 圧縮時は先にリンク先を作成し、存在確認してからcontextを索引化する
- 用語や到達先が曖昧な時は [[semantic-map]] と `bash scripts/semantic_search.sh "<query>"` を使う

## 使い方

### 新規プロジェクト追加時
1. `context/{project_id}.md` を作成
2. 下記テンプレートに沿って記載

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
- → [[infrastructure]] インフラ運用コンテキストの入口
- → [[semantic-map]] 概念検索・関連ファイル到達の入口
- → [[training-cycle]] 修行タスクがcontextリンク密度を育てる仕組み
