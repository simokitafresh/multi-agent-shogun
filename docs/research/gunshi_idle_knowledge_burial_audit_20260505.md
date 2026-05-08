# 知識埋没監査結果 — 将軍専用リソース→全員共有層への転記提案

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-05
- 殿指示: 「将軍だけがアクセスできるmemoryやMCPに、全員が知るべき知識が埋没していないか？」
- 手法: auto-memory 68ファイル全量スキャン + MCP索引(MEMORY.md)から間接分析

## 確定埋没7件

| # | 知識 | 埋没場所 | 致命度 | 転記先 |
|---|------|---------|--------|--------|
| 1 | DM-Signal API認証(admin=Basic Auth/viewer=Bearer Token) | auto-memory reference_dmsignal_api_auth.md | HIGH | context/dm-signal-ops.md §API認証 |
| 2 | CDP FE詳細操作(メニュー/PF選択/保有シグナル安全性) | auto-memory reference_cdp_screenshot_dmsignal.md | LOW | context/dm-signal-ops.md §CDP確認手順 拡充 |
| 3 | ETL cron 5→4本移行(各cron構造+デッドコード+移行手順) | auto-memory project_etl_cron_architecture.md | MEDIUM | context/dm-signal-ops.md §ETL追加 |
| 4 | CDPポート体系(9222/9223/9400)+daemon vs legacy版 | auto-memory cdp-browser-automation.md | LOW | context/dm-signal-ops.md §CDP ポート体系追記 |
| 5 | **簡略版コード絶対禁止**(殿厳命) | auto-memory feedback_no_simplified_code.md | **CRITICAL** | CLAUDE.md §Doing tasks 追記 |
| 6 | **忍者に記憶の連続性はない**(担当者指名禁止) | auto-memory feedback_ninja_no_memory.md | HIGH | CLAUDE.md §Deployment Rules 追記 |
| 7 | **本番が正(ground truth)**(GS不一致→GS側修正) | auto-memory feedback_production_is_ground_truth.md | HIGH | projects/dm-signal.yaml PI追加 |

## 転記原文案

### 埋没5 → CLAUDE.md追記案(§Doing tasks末尾)
```
簡略版コード禁止: 「とりあえず動く簡略版」は作るな。完璧版のみ。
一度簡略版が存在すると正しい実装の動機が消えコードベースが汚染される(殿厳命2026-03-17)。
特にアルゴリズム実装は学術論文の定義に完全準拠を要求。
```

### 埋没6 → CLAUDE.md追記案(§Deployment Rules)
```
忍者に���憶の連続性はない: 忍者は毎回/clearで全記憶消失。
「同じ忍者が最��」は誤り。知識は報告YAML+タスクYAML注入で引き継ぐ。
cmd設計で担当者を指名するな。配備は家老の判断に委ねよ。
```

### 埋没7 → projects/dm-signal.yaml PI追加案
```
- {id: PI-026, fact: "本番(PipelineEngine+DB)が正(ground truth)。GSパリティ不一致時は本番を疑わずGS側を改善。本番バグ仮説を立てるな"}
```

## 追加埋没9件（全量スキャン結果）

| # | 知識 | 埋没場所 | 対象ロール | 転記先 |
|---|------|---------|-----------|--------|
| 8 | ファイル削除は直接rmするな。集約→殿が手動削除 | feedback_deletion_procedure.md | 全員 | CLAUDE.md §Destructive Operation Safety |
| 9 | 本番DB確認が先。コード分析の前に実データ確認 | feedback_verify_production_first.md | 忍者/軍師 | context/dm-signal-ops.md |
| 10 | 設計を殿と固めてからcmd YAML作成 | feedback_design_before_cmd.md | 将軍 | instructions/shogun.md |
| 11 | cmdは小さく分割。大cmkは家老の読解コスト大 | feedback_small_cmd_split.md | 将軍 | instructions/shogun.md |
| 12 | 1cmd1スクリプト。大量起票は品質低下の元 | feedback_one_cmd_one_script.md | 将軍 | instructions/shogun.md |
| 13 | 殿はAndroid音声入力。途切れ・カタカナ揺れを補完して読め | user_voice_input_mobile.md | 全員 | CLAUDE.md (1行) |
| 14 | 冪等書込みでもmtime変化→inbox_watcher誤発火 | feedback_idempotent_write_mtime.md | 家老/軍師 | context/infrastructure.md |
| 15 | テスト=負債。3問検証(リグレッション/変更頻度/コスト) | feedback_test_is_debt.md | 全員 | CLAUDE.md §Test Rules |
| 16 | cmd中止判断は/clear後に消失。後続cmdで完了確認必須 | feedback_cmd_halt_persistence.md | 家老 | instructions/karo.md |

### 既にCLAUDE.mdに反映済み（偽陽性除外）
- feedback_read_before_write.md → "File Operation Rule" として存在
- feedback_idle_is_worst_waste.md → パラメータ空間縮小禁止§に記載
- feedback_context_reflux.md → cmd完了時手順§に戦局日誌として記載

## 全量集計

| 致命度 | 件数 | 代表例 |
|--------|------|--------|
| CRITICAL | 1 | 簡略版コード禁止 |
| HIGH | 5 | 忍者記憶なし, 本番=ground truth, API認証, 削除手順, 本番確認先 |
| MEDIUM | 7 | ETL構造, テスト負債, 音声入力, 小分割, 1cmd1script, mtime, cmd中止 |
| LOW | 3 | CDP詳細操作, CDPポート, 設計→cmd順序 |
| **合計** | **16** | |

## MCP同期漏れ疑惑

| MCP Entity | obs数 | 対応YAML | YAML件数 | 差分 |
|-----------|-------|---------|---------|------|
| shogun_lessons | 193 | lessons_shogun.yaml | 29 | **164** |
| dm_signal_decisions | 93 | dm-signal.yaml PI | 5表示(25全文) | **68?** |

MCP→YAML同期漏れは将軍にしか確認不可。軍師から将軍への依頼事項。

## 方法論

- 判定基準: 「忍者が実装時に/家老が配備時に、この知識がなければ判断を誤るか？」→YES=全員必須
- 将軍の好み/戦略/殿との対話の文脈 → 将軍専用で正当
- auto-memoryは技術的には全agent読取可能だが、MEMORY.md(索引)を忍者/家老がスキップするため事実上到達不可

## 実施結果(2026-05-06)

| アクション | 結果 |
|-----------|------|
| cmd_2580(MCP由来5件+auto-memory由来3件) | saizo LGTM→CLEAR |
| karo_direct(context/dm-signal-ops.md 4件) | hayate LGTM→CLEAR |
| 残り8件(CLAUDE.md系3件+他5件) | 将軍起票待ち(CRITICAL1+HIGH2はCLAUDE.md変更=家老権限) |

## 再実行手順(次セッションの軍師向け)

1. `ls /home/simokitafresh/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/` で全ファイル取得
2. 各ファイルのfrontmatter(type/description)で4分類: shogun-only / all-agent / reference / stale
3. all-agent分類のファイルを `grep` で CLAUDE.md/instructions/context/projects に照合
4. 照合なし=埋没。致命度判定(忍者実装/家老配備に影響→HIGH)
5. 残り8件の進捗確認: CLAUDE.md「簡略版禁止」「忍者記憶なし」、PI-026「本番=ground truth」
