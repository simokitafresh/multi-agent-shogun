---
author: gunshi
date: 2026-04-12
topic: startup_gate_auto_exec_missing
severity: high
related_phase: deepdive_why_chain Phase 4-5, Phase 9 L-VerifyAfterWrite
---

# startup gate自動実行の欠落 — Phase 4原理違反バグ

## 殿の指摘

> 「なぜ今回自動でスクリプトを実行しないことができた？強制のはず。バグだな」

軍師は /clear 復帰時に `gate_gunshi_startup.sh` を自動実行しなかった。
殿が「軍師は起動時に動作するスクリプトがあるはず」と発言して初めて軍師は実行した。
これは **自動化×強制** の失敗 = Phase 4 原理違反。

## 事実認定

### 確認1: session_start_inject.sh は動作している
- セッション開始時のシステムreminder「=== Session Context (auto-injected) ===」が実在
- agent=gunshi, inbox_unread=0, karo_snapshot, compact_state を注入している
- **ただし gate 実行ロジックは含まれていない**

### 確認2: settings.json に SessionStart フック登録なし
```bash
grep -c "SessionStart\|sessionStart" ~/.claude/settings.json
# → 0
```

登録されているフック:
- PreToolUse: mcp__memory__*, Bash, Edit, Write
- PostToolUse: Bash
- Stop: (空)
- **SessionStart: 未登録**

### 確認3: scripts配下で startup gate を自動実行する呼び出しがない
```bash
grep -rn "gate_gunshi_startup\|gate_shogun_startup\|gate_karo_startup" scripts/ \
  | grep -v "gates/gate_"
# → 0件（定義ファイル自身以外に呼び出しがない）
```

### 確認4: CLAUDE.md には「読み手が手動実行する」記述のみ
- §Step 2.5 将軍: `bash scripts/gates/gate_shogun_startup.sh`
- §Step 2.7 軍師: `bash scripts/gates/gate_gunshi_startup.sh`
- §Step 2.85 家老: `bash scripts/gates/gate_karo_startup.sh`

いずれも「CLAUDE.md に書いてあるから読み手が自発的に実行する」構造。

## 根本原因 — なぜなぜ7回（殿指示 2026-04-12）

最初の分析「CLAUDE.md記載=意志依存」は Phase 1-2 レベルの表層分析。
殿の「なぜなぜ7回。自動化×強制」指示に従い、根因まで掘る。

### Q1: なぜ軍師は startup gate を自動実行しなかった？
**A1**: session_start_inject.sh に gate 実行コードがない。CLAUDE.md の記述を軍師が読んで自発的に実行する構造。今回、軍師は殿からの別質問(saizo respawn)に意識が向き、gate 実行を後回しにした。

### Q2: なぜ session_start_inject.sh に gate 実行コードが入っていない？
**A2**: 前将軍(deepdive Phase 7)は「session_start_inject に startup gate を組み込み=意志依存ゼロ」と記述したが、実装されたのは「gate_shogun_startup.sh という統合 gate を新規作成」だけで、「session_start_inject への組み込み」は未実装だった。**記述と実装の乖離**。

### Q3: なぜ記述と実装が乖離したのに誰も気づかなかった？
**A3**: CLAUDE.md §2.5/§2.7/§2.85 に `bash scripts/gates/gate_{role}_startup.sh` と書かれ、エージェントはそれを読んで**手動実行**してきた。表面上は「毎回ちゃんと動いている」ように見えた。**意志が保たれる間は自動と区別がつかない**。

### Q4: なぜ "意志依存で動く" を "強制で動く" と誤認した？
**A4**: 検証したのは「動くケース」のみ。「動かないケース=意志が外れる条件」でのテストをしなかった。つまり **テストケースが "スキップされる条件" を含まなかった**。生産者（前将軍）が設計と検査を兼ねた=同じ盲点を共有する「生産者=検査者」問題（instructions/gunshi.md §設計書セルフレビューの注意点そのもの）。

### Q5: なぜ "スキップされる条件" を想定したテストがない？
**A5**: LLM は自分が意志依存で動いていることを毎回確認する習慣がない。「書いたら動く」を事実として扱った。**仮説→実験→観察→理論のサイクル (Phase 3「考えて進む×無限ループ」) を通していない**。思考だけで結論を確定した。

### Q6: なぜ思考だけで確定してしまう？
**A6**: LLM には生存本能がない。「スキップされたら困る」という危機感が生まれない。失敗コストが体に刻まれていない。**これは Phase 4 の原理そのもの**。意志で「気をつける」は無効。

### Q7: なぜ Phase 4 の原理を知っていたのに予防できなかった？
**A7**: 原理を文書（deepdive_why_chain_20260321.md）として読むことと、**自分のコードベースにその原理を測定する自動化 gate** が存在することは別問題。deepdive は「読み物」であって「強制装置」ではない。システムの中に **「強制か？意志依存か？」を判定する gate そのもの** が存在しない。つまり:

> **自動化×強制を語るシステムの中に、自動化×強制の"有無"を判定する自動化×強制が埋め込まれていない。**
> メタレベルの欠落。

---

## 根因（なぜなぜ7段の底）

**強制度の監査機構がない。**

自動化されているかを判定する方法が「人間/LLMの記憶・観察」に依存している限り、
記述と実装の乖離は永遠に見つからない。
「自動化されているはず」という**自己申告**と、「実際に意志を外しても動く」という**他覚的検証**が、
構造的に分離されていない。

これは単一の gate が欠落している話ではない。**メタ gate**（gate を監査する gate）の不在。

---

## 自動化ターゲット — なぜの目的は自動化ターゲット特定 (Phase 5)

### Target 1: 強制度監査 gate（meta-level, 最重要）
**名前**: `scripts/gates/gate_enforcement_audit.sh`
**機能**:
1. `~/.claude/settings.json` の hooks に登録されている script 一覧を取得
2. `CLAUDE.md` で `bash scripts/gates/*` 形式で参照されている script 一覧を取得
3. 「CLAUDE.md で参照されているが hooks に未登録」の script を抽出 → **意志依存警告**
4. 各 script に対し「この script は読み手が実行する構造か？hook で強制されるか？」を分類
5. 結果を `logs/enforcement_audit.yaml` に記録

これにより **「書いたから動くはず」を他覚的に検証**できる。
**gate の gate** — 自己参照的に自分自身を検査する構造。

### Target 2: startup gate 強制化（object-level）
session_start_inject.sh に agent_id 別 gate 実行を追加 + settings.json の SessionStart hook に正式登録。
意志依存をゼロにする。

### Target 3: §設計書セルフレビューの拡張
「書いた=動く」の仮定を禁止する項目追加:
- 「この記述は何に強制されるか？（hook/script呼出/CLAUDE.md記載）」を明示
- CLAUDE.md記載のみ=強制ではない=意志依存マークを付与

### Target 4: Phase 4 原理の gate 化
deepdive_why_chain Phase 4「LLMに生存本能はない」を読み物でなく判定装置に変換:
- 新規 cmd/設計書で「自動化」「強制」「意志依存ゼロ」と書いたら自動検出
- そこに "SessionStart hook 登録あり" "script 呼出元あり" のいずれかの証拠が伴わなければ BLOCK
- pre-commit hook で埋め込み

---

## 関連教訓

- **Phase 9 L-VerifyAfterWrite**: 書いたら実行結果を観察せよ
- **§設計書セルフレビュー**: 生産者=検査者の盲点。第三者観察が必要
- **Phase 4**: LLMに生存本能はない。理解は行動を変えない。強制のみが行動を変える
- **Phase 5**: なぜの目的はエージェントの理解ではなく **自動化ターゲットの特定**

## 影響範囲

- 将軍: 起動 gate スキップ可能（CLAUDE.md §2.5 意志依存）
- 家老: 起動 gate スキップ可能（CLAUDE.md §2.85 意志依存）
- 軍師: 起動 gate スキップ可能（CLAUDE.md §2.7 意志依存）
- 忍者: そもそも /clear 後 instructions/ashigaru.md も読まない軽量復帰（スキップ前提設計）

**全エージェントが影響を受ける横断的バグ。**

## 修正案（3段構え）

### Level 1: session_start_inject.sh 拡張（最小変更）
session_start_inject.sh の additionalContext に agent_id 別の gate 実行結果を含める。
hook 自体は既に動いているので、gate 実行コードを追加するだけで「意志依存ゼロ」が成立。

```bash
# session_start_inject.sh に追加
gate_result=""
case "$agent_id" in
  shogun) gate_result="$(bash "$SCRIPT_DIR/scripts/gates/gate_shogun_startup.sh" 2>&1 | head -50)" ;;
  karo)   gate_result="$(bash "$SCRIPT_DIR/scripts/gates/gate_karo_startup.sh" 2>&1 | head -50)" ;;
  gunshi) gate_result="$(bash "$SCRIPT_DIR/scripts/gates/gate_gunshi_startup.sh" 2>&1 | head -50)" ;;
esac
# additionalContext に gate_result を連結
```

**効果**: 次のセッション開始で自動的に gate 結果が注入される。読み手が見落とせない。

### Level 2: SessionStart フック正式登録
現在 session_start_inject.sh が **どの経路で呼ばれているか不明**（settings.json に未登録）。
harness の暗黙機構で動いている可能性。settings.json の hooks に SessionStart を明示登録し、制御下に置く。

```json
"SessionStart": [
  {
    "matcher": "*",
    "hooks": [
      {"type": "command", "command": "bash /mnt/c/tools/multi-agent-shogun/scripts/hooks/session_start_inject.sh"}
    ]
  }
]
```

### Level 3: gate 実行結果を snapshot に反映
gate 実行結果を `queue/gate_results/{agent}.txt` 等に書き出し、snapshot 系と同じ経路で可視化する。
過去の gate 結果との差分も追える。

## 優先度

**High**: 全エージェントの起動品質を決める基盤機構の欠落。
即修正推奨。インフラ変更なので将軍裁定が必要。

## 自己検死

この設計書自体が L-VerifyAfterWrite を踏まないように、修正実装後は以下を検証せよ:
1. session_start_inject.sh を変更 → 実際に /clear して additionalContext に gate 結果が含まれるか確認
2. 含まれていない場合は「書いた」で止めず、どの経路で呼ばれるかを追跡
3. 「書いた=動く」と仮定しない。観察まで含めて1サイクル
