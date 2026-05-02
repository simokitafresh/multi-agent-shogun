---
name: shogun-pd-sync
argument-hint: ""
quality_metric: "将軍系: PD反映確認cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  PD(pending_decisions)解決後のcontext反映チェック。
  殿の裁定がMCP+PDには記録されたがcontext/*.mdに
  未反映のケースを検出し、更新cmdの発令を提案する。
  TRIGGER: /shogun-pd-sync、裁定記録後のcontext反映確認、大型cmd発令前の知識鮮度チェック
  DO NOT TRIGGER: 7層横断監査（→shogun-teire）、MEMORY.md棚卸し（→/dream）、
  裁定そのものの記録（MCPへの直接write）、教訓の振り分け（→lesson-sort）
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# /shogun-pd-sync — PD→context伝播チェック

殿の裁定がcontextに反映されているか確認する軽量スキル。
裁定記録後や/shogun-clear-prepの一部として使う。

---

## When to Use

- 殿の裁定を記録した直後（MCP + PD resolve後）
- /shogun-clear-prepのStep 1cの延長として
- 「知識の流れは？」と聞かれた時の補助チェック
- フルGS等の大型cmd発令前（忍者が古い知識で動くリスク排除）

---

## 手順

### Step 1: resolved PD一覧を取得

`queue/pending_decisions.yaml` を読み、`status: resolved` のPDを抽出する。

各PDから以下を記録:
- id (PD-XXX)
- summary（裁定内容の要約）
- resolved_content（裁定の詳細）
- source_cmd（どのcmdで発生したか）
- resolved_at（いつ解決したか）

---

### Step 2: 対応contextファイルを特定

PDのsource_cmdからprojectを特定し、対応するcontextファイルを決める:

| project | context files |
|---------|--------------|
| dm-signal | context/dm-signal.md, dm-signal-core.md, dm-signal-ops.md, dm-signal-research.md, dm-signal-frontend.md |
| infra | context/infrastructure.md |
| （その他） | config/projects.yamlから逆引き |

---

### Step 3: context反映チェック

各resolved PDについて:

1. resolved_contentからキーワードを抽出（裁定の核心用語）
2. 対応するcontextファイルをGrepでキーワード検索
3. ヒットすれば反映済み、ゼロヒットなら未反映

判定基準:
- **反映済み**: キーワードがcontextに存在する
- **未反映**: キーワードがcontextに存在しない
- **要確認**: キーワードは存在するが古い記述の可能性

---

### Step 4: 結果報告

```
【PD→context同期チェック】

✅ 反映済み:
  - PD-009: 変わり身tiebreak方針 → context/dm-signal.md L166

❌ 未反映:
  - PD-011: 504日閾値Cash扱い → context/dm-signal.md にヒットなし
  - PD-012: cumulative_return方式 → context/dm-signal.md にヒットなし
  - PD-013: 全忍法同一形式統一 → context/dm-signal.md にヒットなし

⚠️ 要確認:
  - PD-XXX: 〜〜 → 古い記述が残っている可能性
```

---

### Step 5: 対応提案

未反映PDがあれば:

- **1-2件**: 殿に報告し、既存cmdのACに追加するか別cmdにするか判断を仰ぐ
- **3件以上**: context更新専用のcmdを発令することを提案

提案テンプレート:
```
殿、PD {N}件がcontextに未反映でございます。
- {PD一覧}
context更新cmdを発令してよろしいか？
```

---

## ガイドライン

1. **検索は厳密にやりすぎない** — キーワード1-2個でヒットすれば十分。文言の完全一致は不要
2. **pending PDはスキップ** — resolved のみが対象。pendingは殿裁定待ちなので反映しようがない
3. **古いresolved PDも対象** — 時間が経っていても未反映なら報告する
4. **所要時間**: 1-2分。重い処理はない
5. **将来の仕組み化**: このスキルで検出パターンが安定したら、cmd_complete_gate.shに自動チェックを追加する（B案への昇格）
