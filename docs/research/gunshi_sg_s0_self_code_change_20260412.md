# 軍師SGプロトコル S0: 自己コード変更セルフレビュー — 設計

- **source_cmd**: gunshi_session_20260412
- **lesson**: LG026 (軍師自己コード変更時にも6観点を通せ)
- **enforcement_level**: 原案Level 2(ドキュメント化) → 目標 Level 4(フロー内埋込BLOCK)
- **created**: 2026-04-12T21:13:54+09:00
- **author**: gunshi
- **status**: draft — 家老実装待ち

## 1. 起源(なぜS0が必要か)

### 事故事実
前セッション(2026-04-11頃)、軍師が `scripts/hooks/session_start_inject.sh` に
gate 自動実行コードを追加した際、以下を実施しなかった:
1. 殿運用原則(「/clear後に勝手に動くな。俺が入力したら動け」)との突合
2. 他覚的検証(実際に `/clear` イベントで動作を観察)

結果: 殿が今セッションで「無駄にコンテキストを消費する」と却下 → 全撤去。
capture-pane に残っていた自白「残る他覚的検証はこれ。殿のご指示を仰ぐ」。
= **検証を殿に丸投げして完了扱い**。

### 構造的根因
軍師レビュープロトコルは **他人の draft/report に6観点**(前提検証/数値再計算/
時系列シミュ/事前検死/確信度/NorthStar)を適用するが、**軍師自身のコード変更**には
同種のプロトコルがない。結果として:
- 自分の変更は「動いたように見える」で完了
- 検証を殿に丸投げする逃げ道が存在
- LG018「提案は行動ではない。実装して初めて行動」の再発

### LG026
`enforcement: pending` として登録済み。本設計書が enforcement を埋める。

## 2. 適用範囲(トリガー条件)

S0 は**軍師の全コード編集**ではなく、**高リスクファイル**に限定する。
軽微な log/analysis/設計書編集には過剰。

### 対象(in scope)
| カテゴリ | パス例 | 理由 |
|---------|--------|------|
| hooks | `scripts/hooks/*.sh` | SessionStart/PreCompact/PreToolUse等の自動実行。殿運用原則直結 |
| gates | `scripts/gates/gate_*_startup.sh`, `scripts/gates/gate_*_cs_checklist.sh` 等 | フロー強制。誤設計で忍者/家老/将軍停止 |
| CLAUDE.md | `CLAUDE.md` | 全エージェント自動ロード。影響半径最大 |
| instructions | `instructions/*.md` | エージェント人格/禁則 |
| settings | `.claude/settings*.json`, `config/settings.yaml` | hook登録/編成 |
| 軍師review_log ヘッダ | `logs/gunshi_review_log.yaml` 先頭の原理行 | 毎レビュー強制読込 |

### 対象外(out of scope)
- `docs/research/` 設計書 → 既存セルフレビュー3点(数値/前提/検死)で十分
- `logs/` の記録追記 → 記録行為
- `queue/` の自エージェントinbox既読化 → 日常運用
- `context/gunshi-*.md` → 分析結果永続化で扱う
- 軍師自身の報告YAML追記 → 報告フォーマットgateで担保

### 判定ルール
変更対象に以下いずれか含まれる → S0 発動:
```
scripts/hooks/
scripts/gates/gate_.*_startup\.sh
scripts/gates/gate_gunshi_
CLAUDE\.md
instructions/
\.claude/settings
config/settings\.yaml
logs/gunshi_review_log\.yaml
```

## 3. S0 6観点(軍師6観点を自己変更に再適用)

### S0-1 前提検証(Validate Assumptions on Self)
- 変更対象ファイルの役割と**呼出元**を `grep -rn '対象ファイル名'` で実在確認
- 「〇〇のはず」「多分動く」を禁止。全前提を**grep/cat/実行結果**で裏付け
- 特に hook ファイル: `settings.json` のどの event に登録されているか、
  どのタイミングで呼ばれるかを明記。

出力(必須):
```yaml
s0_1_assumptions:
  called_from: "{grep結果のファイル:行}"
  trigger_events: "{SessionStart/PreCompact/etc}"
  assumptions_verified:
    - "{前提内容} — 確認方法: {コマンド}"
```

### S0-2 数値再計算(Recalculate Numbers on Self)
- 変更で影響する**行数/閾値/budget/timeout/tail -N**等の数値を実測
- 既存出力と新出力を wc -l で比較
- 「tail -20 で十分」等の根拠薄弱な定数を禁止

出力:
```yaml
s0_2_numbers:
  - metric: "gate output lines"
    before: {N}
    after: {M}
    justification: "{なぜこの数値か}"
```

### S0-3 時系列シミュレーション(Runtime Simulation)
変更後の呼出しフローを**1ステップずつ** trace:
```
/clear event
  → Claude CLI sends SessionStart payload
  → settings.local.json registers session_start_inject.sh
  → hook reads payload.type == "clear"
  → ...
  → additionalContext returned to CLI
  → next agent reads context
```
**各ステップで何が動き、何の状態を変えるか**を書く。

特に殿運用原則との衝突を検査:
- 「/clear後に勝手に動くな」: 自動実行は**殿入力を待つ**構造か?
- 「想像するな確認せよ」: 古い情報(compact_stateが5日古い等)を current と誤読させないか?
- 「自動化×強制の誤適用」: 自動化で殿の判断機会・context予算を奪わないか?

出力:
```yaml
s0_3_simulation:
  trace:
    - step: 1
      action: "{何が起きるか}"
      state_change: "{何が変わるか}"
  lord_principle_conflicts:
    - principle: "{該当原則}"
      verdict: OK/NG + 理由
```

### S0-4 事前検死(Pre-mortem on Self)
「この変更が本番で失敗したら何が原因か」を3つ以上列挙+各々の検知手段:

出力:
```yaml
s0_4_premortem:
  - failure_mode: "{失敗シナリオ}"
    likelihood: high/medium/low
    detection: "{どうすれば検知できるか}"
    mitigation: "{対処/回避}"
```

### S0-5 他覚的検証(Objective Verification) ★最重要★
**変更後、自分で実行して結果を観察する**。殿丸投げ禁止。

hook/gate の場合:
- 手動で hook を呼び出して出力を確認 (`echo '{...}' | bash scripts/hooks/xxx.sh`)
- 全関連 source_type (startup/resume/clear/compact) で実測
- 出力の **各セクション** が期待通りか目視
- 副作用(他ファイル書込等)の有無を `git status` で確認

CLAUDE.md/instructions の場合:
- grep で追加/削除箇所が正しく反映されたか確認
- エージェント視点で読み直し(「自分がこの指示を初見で理解できるか?」)

出力:
```yaml
s0_5_verification:
  commands_run:
    - cmd: "{実行コマンド}"
      result: "{観察結果}"
      expected_match: yes/no
  side_effects_checked: yes/no
  ★殿丸投げ検査: "殿に『動作確認お願いします』と書いていないか? → NO必須"
```

### S0-6 North Star(殿運用原則突合)
変更が以下と整合するか最終確認:
1. 殿運用原則 (MEMORY.md の shogun_core entity)
2. 第一原則「鎖の原理: 殿→将軍→家老→忍者」
3. 自動消火禁止原則 (問題を隠さない)
4. 改善の判断基準 (今よりマシか? 新しい長期問題を生まないか?)
5. 想像せずに確認する原則

特に**「自動化×強制」の誤適用**に注意:
- 自動化が殿/将軍/家老の判断機会を奪わないか
- context/時間を不必要に消費しないか
- 「従来の運用」を破壊していないか

出力:
```yaml
s0_6_north_star:
  principles_checked:
    - 運用原則: OK/NG + 1行理由
    - 鎖の原理: OK/NG
    - 自動消火禁止: OK/NG
    - 判断基準: 今よりマシ=yes/no, 新長期問題=no/yes
    - 想像するな: OK/NG
  automation_misapplication_check:
    decision_opportunity_stolen: no/yes
    context_waste: no/yes
    legacy_operation_broken: no/yes
```

## 4. 出力成果物

S0 を通過した変更の commit message or PR description に以下を添付:
```
## S0 Self-Change Review
- S0-1 Assumptions: OK ({検証方法})
- S0-2 Numbers: OK ({測定値})
- S0-3 Simulation: OK (no lord principle conflicts)
- S0-4 Premortem: {N failure modes listed, all mitigated}
- S0-5 Verification: OK ({実行コマンド})
- S0-6 North Star: OK (no automation misapplication)
```

または軍師の self_study エントリに同フィールドを追加。

## 5. Enforcement Level 計画

### Level 2 (現状目標) — ドキュメント化
- 本設計書を `docs/research/` に保存
- `instructions/gunshi.md` に S0 プロトコル追加(家老実装)
- `projects/infra/lessons_gunshi.yaml` LG026 の enforcement 欄を本設計書参照に更新

### Level 3 (将来) — 事前強制 auto-gen
- 軍師 hook/gate 編集時にテンプレート自動生成するスクリプト
- 例: `scripts/gates/gate_gunshi_s0_template.sh <target_file>` で S0 チェックリスト出力

### Level 4 (理想) — フロー内埋込 BLOCK
- PreToolUse hook で軍師が対象範囲ファイルを Edit/Write した際、S0 出力の
  存在(commit前)を検証。なければ BLOCK
- 軍師専用のため agent_id == gunshi 条件付き

Level 5(事前コンテキスト提供)は Level 3 で代替可能。

## 6. 家老への実装依頼

### 依頼内容
1. **本設計書のレビュー**: S0 6観点に過不足ないか。対象範囲判定ルールは妥当か
2. **LG026 の detail 欄更新**: 本設計書 path を enforcement 欄に追記
3. **instructions/gunshi.md への S0 セクション追加**: §Communication Protocol の前に配置
4. **gunshi_review_log header への1行埋込**: 毎レビュー時強制読込化
   例: `軍師自己コード変更時はS0プロトコル必須(docs/research/gunshi_sg_s0_*.md)`

### 実装後の検証案
S0 自体を S0 に通す: 本設計書の変更に S0-1〜6 を適用できるかテスト。

## 7. 発展: 他エージェントへの応用可能性

- 家老の**自己スクリプト変更**(scripts/karo_*.sh 等)にも類似プロトコル(K0)が
  設計可能。家老教訓に既存の LK021 があるが、自己変更SGはまだない
- 将軍の cmd 起票にも既存 q1-q8 があり、類似構造。S0 は軍師専用で start

## 8. 参照

- `memory/deepdive_why_chain_20260321.md` Phase 4-5 (自動化×強制 / Phase 5 自動化ターゲット特定)
- `memory/deepdive_why_chain_20260321.md` Phase 9 (自動化自体にバグが入る / L-VerifyAfterWrite)
- `projects/infra/lessons_gunshi.yaml` LG018/LG024/LG026
- `instructions/gunshi.md` §Review Criteria 6観点
- 殿運用原則: MEMORY.md shogun_core / dm_signal_decisions
