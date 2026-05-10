# 防御階層Level到達監査 — 2026-05-10

殿指摘「BLOCKされないように成長する=主軸。ゲートを通すのは枝葉」を受けた全仕組み監査。

## 防御階層原則(殿定義 2026-05-09)

| Level | 名称 | 本質 |
|-------|------|------|
| 1 | 事後検出 | 間違えた後にgateが検出 |
| 2 | 事前予防(doc) | ドキュメントに「こうせよ」と記載 |
| 3 | 事前強制(auto-gen) | テンプレート自動生成で正しい構造を強制 |
| 4 | フロー内BLOCK | 間違ったら即停止 |
| 5 | 事前コンテキスト提供 | 正しい入力を自動生成して渡す。間違える余地がない |

Level 1-4=間違えてから止める。Level 5=間違える前に正しい答えを渡す。
ゲートの成功=未熟さの証拠。発火しないシステムが完成系。

## infra全仕組みLevel到達(16件)

| 仕組み | Level | 状態 | Level5化案 |
|--------|-------|------|-----------|
| ac_physical_verify.sh | 5 | ★到達 | — |
| report_field_set.sh | 5 | ★到達 | — |
| deploy_task.sh resolve | 5 | ★到達 | — |
| cmd_2617 q11自動grep | 5 | ★到達(本セッション) | — |
| cmd_2619 ACパス自動提案 | 5 | ★到達(本セッション) | — |
| cmd_2620 semantic aliases照合 | 5 | ★到達(本セッション) | — |
| gate_vercel_phase候補提案 | 5 | ★到達(本セッションD0) | — |
| bulletin_write.sh | 4 | 自動通知+startup読込 | ほぼ到達 |
| skill_gate_feedback.sh | 4 | FAIL→SKILL.md書込み | ほぼ到達 |
| insight_write.sh | 3 | 消費が手動(idle自走) | startup自動消費 |
| gate_report_autofix.sh | 3.5 | FAIL時自動修正 | テンプレート事前埋込 |
| gate_context_freshness.sh | 1 | WARN4件。自動更新提案なし | cmd_complete時自動提案 |
| gate_lesson_health.sh | 1→4 | ALERT→startup手順で強制 | ほぼ到達 |
| gate_enforcement_audit.sh | 1 | 意志依存スクリプト検出のみ | cmd_saveにLevel自動判定 |
| gate_knowledge_freshness.sh | 1 | STALE検出のみ | deploy_task時自動鮮度注記 |
| gate_wa_data_quality.sh | 1 | WA入力品質検証のみ | karo_workaround_log.sh入力補完 |

比率: Level5=7件(44%) / Level4=2件(13%) / Level3=2件(13%) / Level1=5件(31%)
2026-05-09時点: Level5=3件(19%)。前セッションで3→7件(+4件)に改善。

## cmd_save.sh WARN Level5化(軍師D0実装 2026-05-10)

| チェック | 累積WARN | Level5内容 | テスト |
|---------|---------|-----------|--------|
| parity_ac_missing | 26回 | P1-P5 ACテンプレートコピペ提案 | 7/7 |
| new_file_structure | 21回 | 既存類似ファイルfind自動提案 | (出力のみ) |
| ac_phase_mixing | 15回 | フェーズ分割テンプレート提案 | 6/6 |
| command_steps_vs_ac | 13回 | commandステップからAC候補自動生成 | 4/4 |
| **合計** | **75回** | | |

Level5到達(cmd_save含む): 7→11件(69%)。残候補: gunshi_ref_numeric(21回)/ac_param_sufficiency(12回)=複雑度高→cmd起票必要。

## 全PJ横断監査

| PJ | 最大の穴 | Level |
|----|---------|-------|
| DM-Signal | CI/自動テストなし(3583ファイルあるがGitHub Actionsなし) | 0 |
| DM-Signal | パリティ検証が手動 | 1 |
| DM-Signal | データ異常の自動検知なし | 1 |
| 株式DB | CI/自動テストなし(2521ファイルあるがGitHub Actionsなし) | 0 |
| google-classroom | CI/テストほぼなし | 0 |

3PJでCI(Level 0)が共通の穴。

## cmd_save.sh WARN繰り返しTOP5(=成長していない箇所)

| チェック | 累積発火 | Level5化案 |
|---------|---------|-----------|
| research_tool_explicit | 62回 | cmd_2619でFP修正+パス自動提案(CLEAR) |
| q11_existing_alternative | 46回 | cmd_2617で自動grep(CLEAR) |
| parity_ac_missing | 42回 | 本番変更検出→パリティACテンプレート自動追加 |
| ac_phase_mixing | 29回 | AC記述からimpl/scout混在検出→自動分割提案 |
| command_steps_over_ac | 25回 | command行をAC単位に自動分解 |

## セマンティクスインデックスなぜなぜ7回

根因: 「引く辞書」(Level2)として設計。「必要な時に勝手に出てくる辞書」(Level5)にすべき。
接続先3箇所: (1)cmd_save.sh SEARCH_TEXT照合(cmd_2620で実装CLEAR) (2)deploy_task.sh related_concepts (3)precheck aliases照合
