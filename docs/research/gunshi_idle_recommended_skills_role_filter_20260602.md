# recommended_skills注入のロールフィルタ不在問題
<!-- generated: 2026-06-02T09:07:01+09:00 by gunshi idle analysis -->

## 現象

CS checklist(gate_gunshi_cs_checklist.sh)がcmd_3114でrecommended_skills未使用WARNを出力:
```
missing_skills=db-check,gate-sync,idle-persist,pf-registration,report-write,review-bundle,verdict-check
```

このうち `review-bundle`, `gate-sync`, `idle-persist` は軍師専用スキル。忍者(saizo)が使用不能。偽陽性。

## 根因分析

### 注入経路

```
deploy_task.sh L2837-2863
  → SEMANTIC_DISABLE_LLM=1 semantic_search.sh "$purpose"
  → awk '/^- skills:/' で skills: 行を抽出
  → recommended_skills として task YAML に注入
```

### マッチした概念

cmd_3114 purpose = 「将軍がcmd_idなしのtype=cmd_newをinbox_writeで送信すると...」

マッチ概念と付随スキル:
| 概念 | skills | 忍者で使用可能? |
|------|--------|----------------|
| report_quality_protocol | report-write, verdict-check | YES |
| shin_shijin_design | pf-registration, db-check | NO (タスク無関係) |
| gunshi_review_lifecycle | review-bundle, gate-sync, idle-persist | NO (軍師専用) |

### 根本原因

**semantic index概念にrole属性がない。** deploy_task.shはマッチした概念のskillsを全て注入し、ロールフィルタリングを行わない。

## 影響

- CS checklist偽陽性WARN → レビュアーの注意力消費(ノイズ)
- 忍者が使用不能スキルを推薦される → 混乱・不要なFAIL判定リスク
- recommended_skills精度低下 → スキル推薦機能の信頼性毀損

## 対処案

### 案A: deploy_task.shにロールフィルタ追加(推奨)

deploy_task.shのrecommended_skills注入時に、各スキルのSKILL.mdを読み、
TRIGGER/description内の「軍師専用」「家老専用」等のロール制限を検出→除外。

- 変更: deploy_task.sh 1ファイル
- 既存スキルのSKILL.mdは既にロール制限を記述済み
- 実装量: ~15行(grep -l "軍師専用\|家老専用\|将軍専用" skills/*/SKILL.md)

### 案B: semantic index概念にrole属性追加

`docs/semantic-index/index.md`のskills行にrole情報を付与:
```
| skills | review-bundle (gunshi), gate-sync (gunshi), idle-persist (gunshi) |
```
deploy_task.shがrole部分を解析してフィルタ。

- 変更: index.md全体 + deploy_task.sh
- 運用負荷: 新スキル追加時にrole記入が必要

### 推奨: 案A

既存SKILL.mdのロール制限表記を活用するため、追加の運用負荷がない。

## 因果鎖

semantic_search.shがロール無関係にスキルマッチ → deploy_task.shが全スキルを注入 → CS checklistが偽陽性WARN → レビュアー注意力消費 = 負の複利(毎cmd発生)
