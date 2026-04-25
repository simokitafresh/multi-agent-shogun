# GStack/GBrain → 将軍システム 取り込みカタログ（2026-04-25）

> 親ドキュメント: `docs/research/gstack-gbrain-skillify-2026-04.md` (§1-§6: 全体像・対比・スケール限界)
> 本ドキュメント: §7 スキル深掘り + §8 全取り込み候補33項目
> Source: https://github.com/garrytan/gstack (v1.11) / https://github.com/garrytan/gbrain (v0.19)

---

## §7 GStackスキル深掘り — 実装パターン

> §3-§4のカタログでは名前と概要のみだった。ここでは実コードレベルの実装パターンを記載。

### 7.1 /ship — 20ステップ自動デプロイ

GStackの最も複雑なスキル。feature branchからPR作成まで全自動。

**核心パターン:**

| Step | 内容 | 将軍対応 | 新規取り込み価値 |
|------|------|---------|----------------|
| 1 | Pre-flight: uncommitted changes表示+review readiness dashboard(Eng/CEO/Design staleness検出) | dashboard.md | **staleness検出**: レビューが古いかどうかの自動検知。軍師レビュー後のコード変更を検出 |
| 5 | Test Ownership Triage: in-branch(stop) vs pre-existing(fix/TODO/assign/skip) | なし | **テスト失敗の帰属分類**: 自ブランチ原因 vs 既存バグの明示的分類 |
| 7 | Coverage Audit: ASCII coverage diagram(★★★/★★/★) + 60%min/80%target gate | なし | **カバレッジ可視化**: コードパス網羅度の構造化表示 |
| 8 | Plan Completion Audit: plan items→DONE/PARTIAL/NOT DONE/CHANGED分類。NOT DONEはhard gate | cmd_complete_gate(AC検証) | **PARTIAL status**: 部分完了の表現力。現状PASS/FAILのみ |
| 10 | Staged Commit: multi-file changesetを論理単位にbisect | 暗黙ルール | **自動bisect commit**: 忍者のcommit粒度標準化 |
| 14-15 | Push→PR自動作成(diff/review/coverage/eval結果をPR bodyに統合) | cmd_complete_gate+push | **PR body自動生成**: テスト結果・レビュー結果をPRに統合 |
| **冪等性** | 再実行時: 検証は全再実行、冗長アクション(bump/PR作成)はスキップ | なし | **冪等デプロイ**: 途中失敗からの安全な再実行 |

### 7.2 /benchmark — 性能回帰検出

**回帰閾値（具体的数値）:**

| カテゴリ | WARNING | REGRESSION |
|---------|---------|-----------|
| Timing(TTFB/FCP/LCP) | >20%増加 | >50%増加 or +500ms |
| Bundle size | >10%増加 | >25%増加 |
| Request count | >30%増加 | — |

**Baseline JSON構造:**
```json
{
  "url": "<url>", "timestamp": "<ISO>", "branch": "<branch>",
  "pages": {
    "/": { "ttfb_ms": 120, "fcp_ms": 450, "lcp_ms": 800,
           "total_requests": 42, "total_transfer_bytes": 1250000,
           "js_bundle_bytes": 450000 }
  }
}
```

**将軍との差異:** cmd_2262のCDP計測はスクリプト実行型(1回限り)。/benchmarkはbaseline永続化+trend tracking+閾値自動判定。Phase 1-A再計測(cmd_2271)のCDP計測結果フォーマットをこの構造に合わせると将来の自動回帰検出に繋がる。

### 7.3 /office-hours — 実装前の6つの強制質問

| # | 質問 | 目的 | 将軍対応 |
|---|------|------|---------|
| 1 | Demand reality — 誰が金を払うか？ | 需要の実在検証 | cmd_save.sh q8(WHY→WHAT) |
| 2 | Status quo — 今はどうしているか？ | 競合=現状 | なし |
| 3 | Target user — 名前を言えるか？ | 「みんな」=市場なし | なし |
| 4 | Narrowest wedge — 最小版は？ | 最小で金を払うバージョン | cmd scope_mode |
| 5 | Observation — 邪魔せず観察したか？ | ガイド付きデモは無意味 | なし |
| 6 | Future-fit — 5年後も使えるか？ | 長期デメリット | cmd_save.sh q3 |

**核心:** "Specificity is currency" — 具体性が通貨。
**Premise Challenge:** 暗黙前提を表面化→合意→確認の3段階。assumptions gateに近いが「列挙→合意」が欠けている。

### 7.4 /qa — ブラウザテスト+自動修正

| 特徴 | 内容 | 将軍対応 |
|------|------|---------|
| Health Score 0-100 | 加重ルーブリック。baseline比較でdrop検出 | なし |
| WTF-likelihood自己規制 | revert≥5回 or 1fix≥3ファイル→停止 | なし(忍者の自己規制なし) |
| Diff-aware testing | ブランチ上ではchanged routes のみテスト | なし(全テスト実行) |
| "Never read source" | QA時はコードを読まない。ユーザー視点のみ | なし |

**WTF-likelihood:** cmd_2271事故(scope外改変174行)はこのパターンで防げた。

### 7.5 /context-save — セッションチェックポイント

append-only(上書きなし)で`~/.gstack/projects/{slug}/checkpoints/`に蓄積。将軍の/shogun-clear-prepが同等だが、履歴蓄積はlord_conversation.jsonlで部分実現。

### 7.6 GStack CLAUDE.md — 開発プロセスルール

| ルール | 内容 | 将軍対応 | 取り込み価値 |
|--------|------|---------|------------|
| Testing tiers | gate(CI)とperiodic(weekly)の2層 | 修行サイクル | **テスト2層分離** |
| "Boil lakes" | AIで完全版が安い。常に完全版を推奨 | パラメータ空間縮小禁止 | **同じ哲学** |
| E2E blame protocol | 「既存」主張にはbase branch証明必須 | なし | **テスト帰属** |
| Bisect commits | 1 commit = 1 logical change | 暗黙ルール | **明文化候補** |
| "Don't give up" | 長時間タスクは完了まで待て | F004対立 | **polling例外** |
| Slop-scan | AI品質パターン(fix vs don't-fix) | hook(部分) | **don't-fixリスト** |
| PR guardrails | ETHOS/voice=自動merge禁止 | 殿の好み | **同じ発想** |

---

## §8 Complete Takeaway Catalog — 全33項目

> 殿指示: 「優先度とは順番の話であってデメリットがないものを捨てる理由にはならない」
> 全項目を網羅。デメリットなし=全て実装対象。

### 凡例
- **工数**: S=instructions追記のみ / M=スクリプト改修 / L=新スクリプト作成
- **効果範囲**: 全cmd / レビュー時 / 偵察時 / デプロイ時 / 定期

| # | 出典 | 取り込み内容 | 具体的実装 | 工数 | 効果 | デメリット |
|---|------|------------|-----------|------|------|-----------|
| 1 | /review | **Confidence 1-10** — findingに信頼度。3-4以下は抑制 | gunshi.md SGプロトコル追記 | S | レビュー | なし |
| 2 | /review | **Fix-First分類** — AUTO-FIX/ASK二分 | gunshi.md+報告テンプレート | S | レビュー | なし |
| 3 | /review | **Scope drift検出** — diff vs AC alignment | cmd_complete_gate.sh追加 | M | 全cmd | なし |
| 4 | /review | **Adaptive gating** — 10回0件の観点を抑制 | review_log集計+抑制 | M | レビュー | なし |
| 5 | /review | **Adversarial review** — Red-Team視点。>200行で発動 | 軍師第2パス | M | 大型cmd | トークン増(大型限定で緩和) |
| 6 | /review | **Review staleness** — レビュー後コード変更検出 | complete_gate.shに比較追加 | M | 全cmd | なし |
| 7 | /investigate | **3-strike rule** — 仮説3回失敗→エスカレーション | 偵察template追記 | S | 偵察 | なし |
| 8 | /investigate | **パターン認識表** — バグ署名→初期仮説6パターン | context/ops追加 | S | 偵察 | なし |
| 9 | /investigate | **DEBUG REPORT** — DONE/WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT | verdict選択肢拡張 | S | 全報告 | なし |
| 10 | /investigate | **Scope lock** — 調査中は対象外変更禁止 | task YAML+hook | M | 偵察 | なし |
| 11 | /learn | **教訓Prune** — 参照ファイル存在検証+矛盾検出 | /dream Phase統合 | M | 定期 | なし |
| 12 | /learn | **教訓Stats** — type別/信頼度/活用率 | startup gate追加 | S | 起動時 | なし |
| 13 | /learn | **Cross-project learnings** — PJ横断検索 | deploy_task.sh拡張 | M | 配備時 | ノイズ(スコアで緩和) |
| 14 | /canary | **Deploy後継続監視** — 60s間隔×10分+2回連続アラート | cdp canary mode | L | deploy後 | なし(基盤安定後) |
| 15 | /canary | **4段階severity** — critical/high/medium/low | CDP severity分類 | S | deploy後 | なし |
| 16 | /benchmark | **回帰閾値** — timing>20%WARN/>50%REGRESSION | baseline比較ロジック | M | deploy後 | なし |
| 17 | /benchmark | **Baseline永続化+trend** | JSON保存+trend表示 | M | deploy後 | なし |
| 18 | /ship | **Test Ownership Triage** — in-branch vs pre-existing | 報告triage欄追加 | S | テスト失敗 | なし |
| 19 | /ship | **PARTIAL status** — DONE/PARTIAL/NOT DONE/CHANGED | complete_gate PARTIAL判定 | M | 全cmd | PASS/FAIL整合検討 |
| 20 | /ship | **冪等デプロイ** — 再実行時は検証のみ再実行 | 再配備ガード | M | deploy再実行 | なし |
| 21 | /ship | **Bisect commit** — 論理単位に分割 | ashigaru.md追記 | S | 全実装 | なし |
| 22 | /office-hours | **前提3段階** — 列挙→合意→確認 | assumptions強化 | M | cmd起票 | なし |
| 23 | /office-hours | **Second Opinion** — cross-model cold read | 既存の明文化 | S | レビュー | なし |
| 24 | /qa | **Health Score 0-100** — 加重ルーブリック | CDP health score | M | deploy後 | なし |
| 25 | /qa | **WTF-likelihood** — revert≥5/fix≥3ファイル→停止 | 忍者hook追加 | M | 全実装 | なし |
| 26 | /qa | **Diff-aware testing** — changed routesのみ | scope最適化 | S | テスト | 全量前提の場合あり |
| 27 | CLAUDE.md | **E2E blame protocol** — 「既存」にはbase branch証明 | ashigaru.md追記 | S | テスト失敗 | なし |
| 28 | CLAUDE.md | **Slop-scan don't-fix** — 過剰修正防止リスト | context/作成 | S | 全実装 | なし |
| 29 | CLAUDE.md | **Testing tiers** — gate(毎回) vs periodic(定期) | ルール明文化 | S | テスト設計 | なし |
| 30 | Skillify | **check-resolvable** — スキル到達可能性+MECE+DRY | 健全性チェック作成 | L | スキル追加時 | なし |
| 31 | Skillify | **routing-eval** — intent→skill テスト | 修行サイクル統合 | L | 修行時 | なし |
| 32 | /context-save | **append-only履歴** — 上書きなしで蓄積 | 既存の明文化 | S | 既存 | なし |
| 33 | GBrain | **ハイブリッド検索** — Vector+BM25+Graph | MCP Memory強化 | L | 教訓検索 | MCP制約要調査 |
| 34 | /ship | **Security scan** — 依存脆弱性チェック(pip-audit/npm audit) | ashigaru.md追記(impl前にpip-audit実行) | S | 全impl | なし |
| 35 | GBrain | **Query router** — 知識ソース優先度選択(lessons/context/MCP/code) | deploy_task.sh教訓注入ソース選択強化(GP-223合流) | M | 全cmd配備 | なし |

### 実装順序ガイド

**Round 1（S工数。cmd_2272で15項目実装済み ✅）:**
#1, #2, #7, #8, #9, #12, #15, #18, #21, #23, #27, #28, #29, #32, #34

**Round 2（M工数。cmd_2273-2275で実装中）:**
#3, #4, #6, #10, #11, #13, #16, #17, #19, #20, #22, #24, #25, #26, #35

**Round 3（L工数。設計書→忍者配備で5項目）:**
#5, #14, #30, #31, #33

### 実装進捗（2026-04-25 20:00時点）

| cmd | 項目 | 状態 |
|-----|------|------|
| cmd_2272 | R1: #1,2,7,8,9,12,15,18,21,23,27,28,29,32,34 (15項目) | ✅完了 |
| cmd_2273 | R2-G1: #3,6,19,25 (4項目) | ✅GATE CLEAR |
| cmd_2274 | R2-G3a: #16,17,24 (3項目) | ✅GATE CLEAR |
| cmd_2275 | R2-G3b: #11,13,20,26 (4項目) | 🔄実装中 |
| (未起票) | R2-G2: #4,5,10,22 (4項目) | R1完了後 |
| (未起票) | R2追加: #35 (1項目) | — |
| (未起票) | R3: #14,30,31,33 (4項目) | 設計書必要 |

### サマリ

- **全35項目**。デメリット「あり」= 2項目（#5トークン増, #26全量前提）。緩和策あり
- **22項目実装済み**。残り13項目
- Round 3(4項目)は設計書が必要。CoDD or 軍師設計

### パリティ確認済み（既に将軍が上回る or 同等）

| GStack/GBrain | 将軍システム | 状態 |
|--------------|-------------|------|
| /careful(破壊操作警告) | Tier 1/2/3 ABSOLUTE BAN | **将軍が上回る** |
| /learn(永続学習) | lessons.yaml+PI+deepdive | **将軍が上回る**(追体験) |
| Minions(決定論タスク) | bashスクリプト群 | **同等** |
| cross-modal review | 軍師レビュー(第2モデル) | **同等** |
| soul-audit | instructions/*.md | **同等** |
| /benchmark | cmd_2262(CDP計測) | **着手済み** |
