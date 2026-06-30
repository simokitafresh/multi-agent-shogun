# cmd_save.sh Gate設計思想カタログ化 設計書

> Status: DRAFT v2 — Phase 1a完了。検証で母集団不足判明→Phase 1b追加
> Origin: LOOPS.md比較分析(2026-06-30) → 殿教示「各論〜総論を同じ密度でレイヤーを密にせよ」
> Bulletin: blt_113804(提案) → blt_113933/114010/114133(レビュー突合) → blt_122938(家老検証) → blt_122906(軍師検証) → blt_123028(統合)
> 殿指摘(12:27): 「check_/gate名称含む関数だけで本当にいいのか？」→ 不十分と判明

---

## AS-IS（現状）

| 項目 | 現状 |
|------|------|
| ファイル | `scripts/cmd_save.sh` 6,200行・全bash関数113本 |
| 品質チェック母集団 | **3層構成**(Phase 1a検証+家老精査で判明): |
| (A) named check/gate/q funcs | 40件(check_/gate名称37 + q helper 3) — Phase 1aでカタログ済み |
| (B) inline check items | 33件(handle_cmd_save_exit内。record_reason呼出し85件中33件) — **未カタログ** |
| (C) 名称乖離+学習補助 | 9件(show_gunshi_pane_status配下6 + exit/学習系3) — **未カタログ** |
| 合計 | **約82件**(旧設計書の58件は過少。名称grepの37件はさらに過少) |
| 構造 | 全関数が1ファイルに混在。思想(なぜこのgateがあるか)と実装(how)が分離されていない |
| 中間レイヤー | 不在。教訓(lessons_shogun.yaml)と個別gate関数の間に設計思想の正本がない |
| 因果追跡 | 一部の関数にコメントでorigin記載あり。体系的なカタログは不在 |
| FP率 | LS-A22に11件のFPパターン記録。関数単位のFP率は未計測(ログに関数別FPラベルなし) |
| テスト | 25 batsファイル・212テスト。テストカバレッジ=29/37(78%、Phase 1a named funcsのみ) |
| 診断出力 | BLOCK/WARN時にtrigger summary・修正ヒント・過去同根を表示。暗黙的に多数の関数が連携 |

**問題1**: 教訓(総論)→個別gate(各論)の2層しかなく、中間レイヤー(gate設計思想)が不在。殿教示「各論〜総論すべて同じ密度でレイヤーを密にせよ」に反する。
**問題2**: 品質チェック機能の大半(42件/82件=51%)がインラインまたは名称乖離関数に埋もれており、関数名grepでは捕捉不能。殿指摘「check_/gate名称含む関数だけで本当にいいのか？」の通り、名称フィルタではなく機能フィルタが必要。

---

## TO-BE（あるべき姿）

| 項目 | あるべき姿 |
|------|----------|
| 構造 | 3層: 教訓(総論) → gate設計思想カタログ(中間) → 個別gate関数(各論) |
| カタログ | `docs/research/cmd_save_gate_catalog.md` — 全品質チェック項目(約82件)の設計思想正本 |
| 母集団3層 | (A) named funcs 40件 (B) inline checks 33件 (C) 名称乖離+学習補助 9件 |
| 各項目の記録 | 16列: origin/防御対象/L0-L7/時点/severity/副作用/正例fixture/負例fixture/対応テスト/cmd_skeleton同期/性能コスト/FP率/教訓逆引き/最終修正日/hook参照パターン/origin因果リンク |
| FP率 | 関数単位で計測済み。gate_fire_log + cmd_design_quality.yamlから算出 |
| テスト | check関数→batsテスト対応表が存在 |
| 統合判定 | failure semantics × temporal position × side effect × fixture同一性の4条件で判定 |
| 非交渉条件 | 「BLOCKされた時に、なぜ止まったか・次に何を直すか・過去同根は何かが現状以上に見える」(家老要件) |

---

## 5W1H

### Why（なぜやるか）

殿教示(2026-06-30): 「各論〜総論までバランスよくレイヤーで対策を密にするべき」。現状は教訓(総論)と個別gate(各論)の2層のみで中間が不在。gate数削減が目的ではなく、設計思想の明文化が目的。100億年スケールではgate/hookは無限に成長してよいが、なぜそのgateがあるかの因果が不明だと統合も改善もできない。

### What（何をやるか）

**5 Phase構成**（v2: Phase 1をa/bに分割）:

| Phase | 内容 | 成果物 | 状態 |
|-------|------|--------|------|
| 1a | named function catalog (check_/gate/q helper) | カタログ40件×16列 | **完了**(37件済み+helper 3件追加要。severity誤記#3修正要) |
| 1b | inline checks + 名称乖離関数の追加カタログ | カタログ追加42件×16列 | **未着手** |
| 2 | 統合候補3分類(統合可/抽象化のみ/触るな) + 候補ごとに失われる副作用列挙 | カタログに統合判定列追加。殿承認で移行 | 未着手 |
| 3 | 1候補ずつ小commitで実装。毎回before→after計測 | リファクタ済みcmd_save.sh + bats全PASS + FP率非悪化 | 未着手 |
| 4 | cmd_skeleton/semantic-map/context/infrastructureへ思想レイヤー貫通 | 中間レイヤーが全エージェントからアクセス可能 | 未着手 |

**Phase 1b の母集団**(家老精査 blt_122938):
- (B) inline checks 33件: handle_cmd_save_exit内。FILL_THIS残存/delegated再保存/other_draft_exists/environment_change 4種/quality_gate系/q4-q11系WARN・BLOCK等
- (C-1) 名称乖離6件: show_gunshi_pane_status配下。ac_structure_incomplete/未検証前提BLOCK/assumptions source path missing等
- (C-2) exit/学習補助3件: warn_q5_pair_missing_session_state/warn_missing_prev_cmd_lesson/show_three_layer_memory_ruling_info

### Who（誰がやるか）

- Phase 1a: **完了**(cmd_3608)。忍者2名(hanzo+saizo)で37件カタログ化。検証で母集団不足判明
- Phase 1b: 偵察cmd → 忍者2名並列。inline 33件+名称乖離9件のスキャン。record_reason呼出し箇所ベースで抽出(grepではなく機能フィルタ)
- Phase 2: 将軍が統合判定。殿承認で移行
- Phase 3: 修正cmd → 忍者。1候補1commit
- Phase 4: 将軍が貫通確認

### When（いつやるか）

- Phase 1: 即時起票可能(殿承認後)
- Phase 2: Phase 1完了後
- Phase 3: Phase 2の殿承認後
- Phase 4: Phase 3完了後

### Where（どこに影響するか）

| 影響先 | 内容 |
|--------|------|
| scripts/cmd_save.sh | 主対象。関数統合・リネーム・分割の可能性 |
| tests/unit/test_cmd_save_*.bats | テスト対応関係の更新 |
| .claude/hooks/pre-write-edit-combined.sh | Guard 12がcheck関数名をパターンマッチ。関数名変更時に更新必須 |
| scripts/cmd_skeleton.sh | カタログとの同期確認 |
| context/growth-loop.md | 中間レイヤーの説明追加 |
| docs/semantic-index/index.md | gate設計思想カタログ概念追加 |

### How（どうやるか）

**Phase 1 カタログ作成の具体手順**:

**Phase 1a(完了)**: `grep -n "^check_\|^function check_" scripts/cmd_save.sh` で named function 抽出 → 37件カタログ済み
**Phase 1b(次)**: `grep -n "record_block_reason\|record_warn_reason" scripts/cmd_save.sh` で全品質判定箇所を抽出 → Phase 1aカタログ外の項目を追加表に記入

Phase 1a手順(実績):
1. grep で全関数名+行番号を抽出
2. 各関数について以下12列を記入:
   - (a) origin: git logから初出commitを特定 → lessons_shogun.yamlのLS-ID逆引き
   - (b) 防御対象: 関数内のコメントと条件分岐から特定
   - (c) L0-L7レイヤー: どの防御階層に属するか
   - (d) 時点(temporal position): preflight/save/hook/session/exit
   - (e) severity: BLOCK/WARN/INFO
   - (f) 副作用: log/YAML/cache/bulletin/stdout/stderr
   - (g) 正例fixture: この関数がPASSする入力例
   - (h) 負例fixture: この関数がFAIL/WARNする入力例
   - (i) 対応テスト: batsファイル名+テスト関数名
   - (j) cmd_skeleton同期: cmd_skeleton.shに対応ガイドがあるか
   - (k) 性能コスト: 実行時間(ms)
   - (l) FP率: gate_fire_log + cmd_design_quality.yamlから算出
3. 追加列(軍師補完):
   - (m) 教訓逆引き: 対応するLG/LK/LS ID
   - (n) 最終修正日: `git log --format=%ai -1 -- scripts/cmd_save.sh:行範囲`
   - (o) hook参照パターン: pre-write-edit-combined.sh等から逆引き
   - (p) origin因果リンク: Obsidian [[リンク]]形式

**Phase 2 統合判定基準**(家老定義):
- 統合可: failure semantics同一 × temporal position同一 × side effect同一 × fixture共通
- 抽象化のみ: 防御対象同一だが時点/severity/副作用が異なる → 共通ヘルパー抽出のみ
- 触るな: 独立した因果ネットワークを持ち、統合すると因果追跡が切れる

**結果担保**(家老+軍師統合):
- bash -n scripts/cmd_save.sh (構文検証)
- cmd_save関連bats全PASS
- 実cmd --preflight N>=3 (PASS/WARN/BLOCK各1以上)
- FP/FN件数 before→after比較
- 実行時間 before→after比較
- 診断行の保持確認(BLOCK時の「なぜ・次に何を・過去同根」が現状以上)

---

## リスクと制約

| リスク | 対策 |
|--------|------|
| カタログ作成が巨大タスクになる | 58関数を2名並列で分割。1名29関数×12列 |
| 統合でFN増加(見逃し) | FP共通除外前に各件の「何を隠すか」明文化。FN増加0をfixtureで証明(家老穴3) |
| 関数名変更でhook参照が壊れる | Phase 3のACにhook参照パターン更新を含める(軍師穴2) |
| origin因果が統合で失われる | カタログに全originを保存。統合後も因果追跡可能(軍師穴1) |

---

## 因果リンク

- ← [[LOOPS.md比較分析_20260630]] 殿との対話でgate設計思想不在を特定
- ← [[殿教示_各論総論同密度_20260624]] 各論と総論を同じ濃度と粒度と密度で無限にやり続ける
- ← [[殿教示_100億年マシン成長_20260630]] 環境(gate/hook)は無限に成長してよい
- → [[growth-loop]] L1-L7防御階層の中間レイヤー追加
- → [[LS-A22]] FP 11件の根因分析をカタログで体系化
