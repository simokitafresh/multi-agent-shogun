# Karpathy LLMコーディング4原則 (andrej-karpathy-skills)

> Andrej Karpathyが観察したLLMコーディングの落とし穴を4原則に蒸留した CLAUDE.md ガイドライン。Forrest Changが作成・公開。我が軍ではcmd_2019でSimplicity+Think Before Codingを取込済み(LS043)。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | Forrest Chang (@forrestchang) / Andrej Karpathy (原著者) |
| Status | OSS 本番稼働中 (活発に進化) |
| Stars | **56,919** (2026-04-19取得) |
| Forks | 4,863 |
| Version | SKILL.md形式 (バージョン番号なし) |
| Last Commit | 2026-04-15 |
| Repo | https://github.com/forrestchang/andrej-karpathy-skills |
| License | MIT |
| Language | Markdown (CLAUDE.md / SKILL.md) |
| Topics | claude-code, llm-coding, best-practices, karpathy |

## Design Philosophy

- **Think Before Codingが根幹**: LLMは確認なしに誤った仮定で走る。仮定を明示し、曖昧性は複数解釈を提示し、単純なアプローチが存在するなら異議を唱える
- **Simplicity=質問**: "Would a senior engineer call this overcomplicated?" が評価基準。要求されていない機能・抽象化・エラー処理を追加しない
- **外科的精密性**: 変更は必要最小限。変更した行は全て「ユーザーのリクエストに直接起因する」まで絞る
- **宣言型ゴール**: 命令型("Add validation")を宣言型("Write tests for invalid inputs, then make them pass")に変換。LLMはゴールへのループが得意

> *"The models make wrong assumptions on your behalf and just run along with them without checking"* — Karpathy

## Architecture

### 4原則

| 原則 | フォーカス | 核心ルール |
|------|-----------|-----------|
| Think Before Coding | 仮定の明示化 | 不確実なら推測ではなく質問。曖昧性があれば複数解釈を提示。単純解があれば異議を唱える |
| Simplicity First | 最小限コード | 要求機能のみ実装。単一用途の抽象化・投機的エラー処理・要求外の柔軟性は全て禁止 |
| Surgical Changes | 変更の精密化 | 隣接コード/コメント/フォーマットの「改善」禁止。動作中のコードのリファクタ禁止。既存スタイルに合わせる |
| Goal-Driven Execution | 検証ループ | 命令型→宣言型に変換。成功基準を定義してLLMに渡す。検証まで反復 |

### インストール方法

- **Option A**: Claude Code Skillsマーケットプレイス経由 (`forrestchang/andrej-karpathy-skills`)
- **Option B**: プロジェクト内 `CLAUDE.md` に直接コピー

### 適用スコープ

- **非自明な変更に全リゴール適用**: 自明な修正(typo等)は判断で省略可
- **caution > speed**: 特に非自明タスクは速度より慎重さを優先

## Key Features

| 機能名 | 説明 |
|--------|------|
| Think Before Coding | 不確実な場合は推測せず質問。複数解釈提示。単純解への異議申し立て。混乱部分の明確化 |
| Simplicity First | 要求のみ実装。単一用途抽象化禁止。投機的エラー処理禁止。200行が50行で済むなら書き直し |
| Surgical Changes | 変更行は全てリクエストに直結。隣接コード/フォーマット改善禁止。自分の変更で生じた不要インポート/変数のみ削除 |
| Goal-Driven Execution | 命令型→宣言型変換。"Fix the bug"→"Write a test that reproduces it, then make it pass"。成功基準のLLMへの委譲 |

## Changelog

| 日付 | 変更 | 影響 |
|------|------|------|
| 2026-04-15 | READMEにプロジェクト・SNSリンク追加 | ドキュメント整備 |
| 2026-04-初旬 | Claude Code Skills形式(SKILL.md)対応 | 各種マーケットプレイスへの配布 |
| 2026年初旬 | 初公開 → 数週間でGitHub急速拡散 | Star 56,919到達(ファスト成長) |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| 仮定の明示化 | 不確実な場合は推測せず質問するプロトコル | ◎ Karpathy原則 |
| 宣言型ゴール変換 | 命令型タスク→検証可能な成功基準への変換 | ◎ Karpathy原則 |
| Caution-over-Speed | 非自明タスクは速度より慎重さを優先するポリシー | ◎ Karpathy原則 |
| 外科手術的変更 | 変更行を全てリクエストに直結させる精密性 | ◎ Karpathy原則(我が軍のSG3/LG004とも重複) |

## 我が軍への取込状況 (cmd_2019/LS043)

| 原則 | 取込状況 | 我が軍での実装箇所 |
|------|---------|-----------------|
| Think Before Coding | ✅ 取込済み (cmd_2019) | task YAMLの `assumption_check` 欄 |
| Simplicity First | ✅ 取込済み (cmd_2019) | task YAMLの `simplicity_check` 欄 + CLAUDE.md「複雑さ追加が必要なら理由を1文で記せ」 |
| Surgical Changes | ✅ カバー済み | SG3 (AC外変更検出ゲート) + LG004 (コードレビュー観点) — LS043で重複確認済み |
| Goal-Driven Execution | ✅ 取込済み | AC+binary_checks方式 (各ACに検証ループを設定し完了基準を明示) |

**LS043教訓**: Surgical Changesを最優先と判断したが軍師がSG3+LG004で既カバーを確認(車輪の再発明回避)。真の穴はSimplicity(over-engineering検出)だった。外部知見取込前に既存仕組みの現物確認が必須。

## Ecosystem

| カテゴリ | 名前 | 説明 |
|----------|------|------|
| Skills Marketplace | Claude Code Plugin Hub | https://www.claudepluginhub.com/plugins/forrestchang-andrej-karpathy-skills |
| Skills Marketplace | Skillkit.io | https://skillkit.io/skills/claude-code/karpathy-guidelines |
| Skills Marketplace | LobeHub | https://lobehub.com/skills/forrestchang-andrej-karpathy-skills-karpathy-guidelines |
| Skills Marketplace | Playbooks | https://playbooks.com/skills/forrestchang/andrej-karpathy-skills/karpathy-guidelines |
| Skills Marketplace | Agent Skills Directory | https://www.skillsdirectory.org |
| 解説記事 | PyShine | https://pyshine.com/Andrej-Karpathy-Skills-LLM-Coding-Guidelines/ |
| 解説記事 | AIBit | https://aibit.im/blog/post/karpathy-s-llm-coding-rules-think-simplify-iterate |
| 解説記事 | Antigravity | https://antigravity.codes/blog/karpathy-claude-code-skills-guide |
| DeepWiki | forrestchang/andrej-karpathy-skills | https://deepwiki.com/forrestchang/andrej-karpathy-skills |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| 全ルール適用タイミングの誤判断 | 自明な修正（typo等）にも全4原則を適用しようとすると実行速度が落ちる。「非自明な変更にのみ全リゴール適用」という原文の例外条件を見落としやすい | 修正タスクの粒度判断時、CI自動修正、小規模バグ修正 |
| Goal-Driven変換における成功基準の曖昧化 | 「Fix the bug」を宣言型に変換せずに残すと、LLMが成功を判定できずに反復ループを脱出できないか、誤った完了判定をする | 反復タスク設計時、テスト駆動開発の成功基準定義 |
| Surgical Changesの過剰解釈による放置 | 「隣接コードを改善するな」を誤解し、明らかな誤りや不整合も修正禁止と判断する。原則は不要な改善を禁止するのであり、タスク起因の変更は対象外 | コードレビュー統合、大規模リファクタリングとの組合せ運用 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [逆瀬川 (Harness Engineering)](../sources/gyakusegawa.md) | 個別LLM指示ルールに対し、フィードバック速度ヒエラルキー・Skill設計・AGENTS.md等のハーネス全体設計視点を補完する |
| 補完 | [mizchi](../sources/mizchi.md) | KarpathyのThink Before Coding原則に対し、mizchiのDocument-First Development（仕様をdocsに先行蓄積）が実践的な前準備パターンとして補完する |
| 競合 | [gsd](gsd.md) | Karpathyはシンプルさ優先でLLM指示を最小化する一方、GSDは役割分担・QA・shipまでの明示的なロール設計を優先する点で最適化方向が異なる |
| 前提 | [our-army](our-army.md) | 原則をCLAUDE.mdへ埋め込み実際に稼働させるには、our-armyのようなYAML配備フロー・gate・binary check方式の実運用基盤が前提となる |

## Sources

| 種別 | URL |
|------|-----|
| Repository | https://github.com/forrestchang/andrej-karpathy-skills |
| Skills Marketplace (Skillkit) | https://skillkit.io/skills/claude-code/karpathy-guidelines |
| 解説記事 (PyShine) | https://pyshine.com/Andrej-Karpathy-Skills-LLM-Coding-Guidelines/ |
| 解説記事 (AIBit) | https://aibit.im/blog/post/karpathy-s-llm-coding-rules-think-simplify-iterate |
| DeepWiki | https://deepwiki.com/forrestchang/andrej-karpathy-skills |

## Verification

| 項目 | 値 |
|------|-----|
| verified_at | 2026-04-19T00:40:00+09:00 |
| method | GitHub API (gh api repos/forrestchang/andrej-karpathy-skills) + WebFetch README + WebSearch |
| source | github.com/forrestchang/andrej-karpathy-skills 公式リポジトリ直接取得 |
| stars_verified | 56,919 (API取得) |
| last_commit_verified | 2026-04-15T17:47:20Z (API取得) |
| principle_names | Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution (README直接確認) |
| note | cmd_2097の事前情報では第4原則を「コード品質」と記載していたが、正式名称はGoal-Driven Execution |
