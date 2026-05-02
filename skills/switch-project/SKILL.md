---
name: switch-project
argument-hint: "[project_id]"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  プロジェクトフォーカスを切り替えるスキル。
  current_projectの更新、CLAUDE.mdのPJ固有セクション差替え、
  全エージェントへの切替通知を一括実行する。
  TRIGGER: /switch-project、PJ切替、プロジェクト変更、フォーカス切替
  DO NOT TRIGGER: PJ情報の閲覧・編集（→projects/*.yaml直接編集）、
  知識棚卸し（→shogun-teire）、新PJ作成のみ（切替を伴わない場合）
allowed-tools:
  - Read
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

# /switch-project — プロジェクトフォーカス切替

シングルフォーカスモデル。全軍が1つのPJに集中する。
殿が明示的に切替を指示した時だけ発動する。

---

## When to Use

- 殿が「PJ-Xに切り替えろ」と指示した時
- 殿が `/switch-project {project-id}` を実行した時
- 新PJを開始する時（未登録PJの場合はオンボーディングフローへ分岐）

---

## 前提条件

- 発動者: 殿のみ（将軍CLI = 殿の入力口。構造的に限定）
- 対象: config/projects.yaml に登録済みのPJ（type: platformを除く）、または新規PJ
- 制約: 骨格（指揮系統/inbox/monitor/教訓サイクル/知識回転/安全ルール/CLAUDE.md手順部）には一切触らない

---

## 手順

### Step 1: 引数パース + PJ存在確認

`/switch-project {project-id}` から project-id を取得。

```
config/projects.yaml を Read
→ projects[].id に project-id が存在するか確認
→ 存在しない場合 → Step 1b（オンボーディング）へ分岐
→ 存在するがtype: platformの場合 → 「{id}はプラットフォームです。切替対象外」で終了
→ 存在する場合 → Step 2 へ
```

### Step 1b: オンボーディング分岐（未登録PJ）

```
殿に確認: 「{project-id} は未登録です。新規登録しますか？」
→ Yes → AC4 オンボーディングフロー実行 → 完了後 Step 2 へ
→ No → 「中止しました」で終了
```

### Step 2: 切替前チェック

```
1. 現在のPJ (current_project) を取得
2. 現PJに未完了cmd/タスクがないか確認:
   - queue/shogun_to_karo.yaml で status: pending/in_progress のcmdを検索
   - queue/tasks/*.yaml で status: assigned/acknowledged/in_progress を検索
3. 未完了があれば警告表示（ブロックはしない）:
   「⚠ 現PJ({current})に未完了タスク{N}件あり。切替を続行しますか？」
4. PJパスが実在するか確認:
   projects/{new-id}.yaml から path を取得 → ls で存在確認
   → 不在なら「PJパス {path} が存在しません」でエラー終了
```

### Step 3: current_project 更新

```
config/projects.yaml の current_project を新PJ-idに Edit で更新
```

### Step 4: CLAUDE.md PJ固有セクション差替え

```
1. CLAUDE.md を Read
2. PJ固有セクション境界を特定:
   - 開始: "## Current Project" の行
   - 終了: 次の "## " 見出し行の直前
   （L032教訓: ##レベルで識別。セクション内の###は区切りではない）
3. 新PJの固有セクションを読み込み:
   - projects/{new-id}/claude_section.md を Read
4. Edit で旧セクション → 新セクションに差替え
```

**claude_section.md の位置**: `projects/{id}/claude_section.md`
各PJが自身のCLAUDE.md用セクションを保持する。
PD-027裁定: ポインタ3-4行のみ（圧縮索引ではない）。
オンボーディング時に雛形から自動生成。

### Step 5: 全エージェントへ切替通知

```bash
bash scripts/switch_project.sh {new-project-id}
```

switch_project.sh の処理:
1. inbox_write で全稼働エージェントにPJ切替通知を送信
   （karo + 全忍者。type: project_switch）
2. 通知内容: 「PJフォーカスを {old} → {new} に切替。次の/clear時に新PJ知識がロードされる」

### Step 6: ntfy通知

```bash
bash scripts/ntfy.sh "【将軍】フォーカスを{new-project-name}に切り替えた。"
```

### Step 7: 完了メッセージ

```
PJフォーカスを {old-name} → {new-name} に切り替えました。
- current_project: {new-id}
- PJパス: {path}
- CLAUDE.md: PJ固有セクション差替え済み
- 通知: 全エージェントに送信済み
- 注意: 稼働中エージェントは次の/clear時に新PJ知識を読み込みます
```

---

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| 未登録PJ | オンボーディングフロー提示（Step 1b） |
| PJパス不在 | エラー表示 + 原因（パスが正しいか確認を促す） |
| 同一PJへの切替 | 「既に{id}がフォーカスです」で終了（無操作） |
| claude_section.md 不在 | 雛形から自動生成して続行 |
| CLAUDE.md内にPJ固有セクション不在 | Skills見出しの直前に新セクションを挿入 |

---

## 差替え対象の明確な境界定義

**PJ依存層（スキルが差替える）**:
1. config/projects.yaml の current_project 値
2. CLAUDE.md の PJ固有セクション（## Current Project ～ 次の ## の直前）
3. エージェントへの通知（inbox_write）

**PJ非依存層（スキルが触らない）**:
- CLAUDE.md の Procedures / Communication Protocol / Knowledge Map / Infra / Agents / Deployment Rules / Skills / Knowledge Maintenance / Project Management / Shogun Mandatory Rules / Test Rules / Destructive Operation Safety
- instructions/*.md
- scripts/*.sh（インフラスクリプト）
- config/settings.yaml

---

## ガイドライン

1. 骨格不可侵 — PJ非依存層は絶対に変更しない
2. 即時反映はしない — 稼働中エージェントのコンテキストは次回/clear時に自然更新
3. 切替は殿のみ — 将軍CLI（殿の入力口）でのみ発動する構造的制限
4. 未完了タスク警告 — ブロックせず警告のみ（殿が判断する）
5. 所要時間: 1-2分（登録済みPJ）/ 3-5分（新規オンボーディング込み）
