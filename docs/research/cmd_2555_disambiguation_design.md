# DM-Signal 用語曖昧性解消辞書 設計書

date: 2026-05-04
author: shogun
status: draft
inputs: cmd_2553(第1波5ファイル) + cmd_2554(第2波3ファイル) + 殿との議論(20:08-20:22)

---

## §0 As-Is / To-Be / Why / What / How

### As-Is (現状)

- DM-Signal知識基盤で同一トークン(L0-L4, signal, return, date等)が**6つの独立体系**で使い回されている
- 同一ファイル(dm-signal-core.md)内でL2が「奥義」「MonthlyReturnキャッシュ」「忍法FoF」の3意味で共存
- BE(etl_trigger.py)のL0-L3(sync体系)とFE(visibility/)のL1-L4(表示制御体系)が同じ記号で別概念
- エージェントがL*を見た時に文脈判断を「推測」で行い誤認する(本セッション実証: L2奥義をL3と報告)
- 用語の正しい意味を確認する辞書もなく、誤用を検出するgateもない

### To-Be (あるべき姿)

- 全多義トークンに対してcontext(ファイルパス)→一意な意味のマッピングが辞書として存在する
- エージェントが起動時に辞書(dm-signal-terminology.md)を自動ロードし、L*を見たら辞書を引いて一意に解決できる
- cmd文/context内で文脈なしの生L*を使うとgate(cmd_save.sh/pre-write hook)がBLOCK → 辞書参照を強制
- 辞書の上流変更(エントリ追加/修正)が下流(context/gate)に自動伝播する(CoDD propagateパターン)
- コード(BE/FE)は一切変更しない。辞書とgateで「理解を外部化」する

### Why (なぜ必要か — なぜなぜ7回の結論)

1. L2誤認 ← 照合せず推測 ← 急いだ ← 同一ファイル内3意味で認知コスト高 ← 異なる体系が同じ記号 ← 命名衝突検査の仕組み不在 ← **知識基盤がLLM特性(パターンマッチ/最近接バイアス)を未考慮**
2. LLMに生存本能はない→理解だけでは行動は変わらない→**自動化×強制**(Phase 4原理)
3. 辞書=正しい知識の外部化。gate=参照の強制。propagate=上流→下流追随の自動化。3層揃って初めて「起きなくなる」

### What (何を作るか)

1. **disambiguation.md** — 27群の文脈→意味マッピング辞書(SSOT、MD形式+CoDD frontmatter)
2. **dm-signal-terminology.md** — エージェント向け索引(辞書から導出。起動時ロード)
3. **gate追加** — cmd_save.sh(bare_layer_ref検出WARN) + pre-write hook(context更新時BLOCK)
4. **既存context注釈** — dm-signal-core.md §0/§2に canonical名を注記(後方互換維持)

### How (どう作るか)

- 段階導入: P0(4群)→P1(6群)→P2(3群)→P3(2群)の4段階
- 初期は手動propagate(辞書編集→context手動更新)。安定後にCoDD CLI自動化
- 各段階1-2cmdで完結する規模に分割
- コード無変更。辞書+gate+contextの3点セットで閉じる

---

## §1 殿の要件

- コード内は弄らない(BEが壊れるリスク回避)
- エージェントが理解できる形で知識として埋め込む
- CoDDで管理し上流変更が下流を自動的に変える
- 1語1意味(MECE)

---

## §2 アーキテクチャ

```
[上流: SSOT辞書 (MD形式)]
docs/knowledge-base/terminology/disambiguation.md
  ↓ codd scan → impact → propagate --update (MD→MD経路。cmd_2556実証済み)
[下流: エージェント向け索引]
context/dm-signal-terminology.md (起動時ロード対象)
  ↓ gate強制
[強制層]
cmd_save.sh (dm-signal cmdで生L*使用→WARN)
pre-write-edit-combined.sh (context更新時に多義語→BLOCK)
```

### CoDDでMD→MD伝播が動く条件(cmd_2556偵察で実証)

1. 上流MD(disambiguation.md)にCoDDのfrontmatter(`design: disambiguation`)を付与
2. 下流MD(dm-signal-terminology.md)のfrontmatterに`depends: [disambiguation]`を記載
3. 上流MDを変更 → `codd scan` → graphノードに解決 → `codd impact` → 下流MDが影響先 → `codd propagate --update` → 下流MDをAIで自動更新

**YAMLではなくMDにする理由**: CoDDの変更検出入口は`.md`ファイルのみ(propagator.pyの_find_changed_docsがf.endswith(".md")を条件にしている)。YAMLは入口対象外。

**MDでの構造化**: テーブル形式で辞書を記述。YAMLほど機械的ではないが、LLMが読む辞書としてはMDテーブルの方が自然に消費できる。

### 案A採用に伴う追加穴と対策

| 穴 | リスク | 対策 |
|----|--------|------|
| 6. MD形式のgate判定 | 辞書をパースして「定義済みか」判定困難 | gateは辞書内容をパースしない。「生L*+文脈なし」のパターンマッチで検出。辞書はエージェント参照用 |
| 7. propagate --updateのAI品質 | AIが下流を正しく書換える保証なし | propagate後にdiff確認+軍師レビュー必須。「自動提案+人間承認」フロー |
| 8. CoDD graph初期構築 | multi-agent-shogunリポでCoDD初使用。設定試行が必要 | 段階0-2はCoDDなし(手動運用)。段階4でCoDD設定。失敗しても辞書+gateは独立動作 |
| 9. disambiguation.md巨大化 | 27群で80行超。起動時ロードコスト | 起動時ロード=terminology.md(索引層、80行以内)。disambiguation.md(SSOT正本)はタスク実行時にReadで参照。Vercel構造 |

### CoDDの依存グラフ設計

disambiguation.mdのfrontmatter(MD形式のYAML frontmatter部):

```markdown
---
design: disambiguation
downstream:
  - context/dm-signal-terminology.md
upstream_watch:
  - backend/app/api/etl_trigger.py  # sync体系L0-L3定義
  - frontend/app/admin/visibility/page.tsx  # visibility体系L1-L4定義
---
```

### propagateフロー

1. 辞書(disambiguation.md)を編集+commit
2. `codd scan` → MDグラフノードとして辞書変更を検知
3. `codd impact` → 下流のdm-signal-terminology.mdが影響先と判定
4. `codd propagate --update` → dm-signal-terminology.mdをAI更新提案 → diff確認+軍師レビュー後にcommit

初期はcodd CLIなしの手動propagate(辞書編集→context手動更新)で開始し、
CoDDのfrontmatter運用が安定してからCLI自動化に移行する(段階導入)。

### 依存関係グラフ

辞書エントリ間には依存がある。例:
- `signal`の定義は`FoF`の定義に依存(`fof_signal_fix_date`はFoFコンポーネント参照日)
- `L2`の定義は`FoF`の定義に依存(`pf_L2_ougi`は全てFoFタイプ)
- `weight`の定義は`component`の定義に依存(`fof_target_weight`はFoFコンポーネントの配分)

disambiguation.md内のMDテーブルで依存関係を明示:

| Token | Depends On | Impacts |
|-------|-----------|---------|
| L2 | FoF, signal | weight, component |
| signal | FoF | date, component |
| weight | component | — |

### 影響範囲(impact)の追跡

エントリ変更時に`codd impact`相当の問い:
- **上流影響**: このトークンの意味が変わると、どのcontextファイルの記述が不正確になるか？
- **下流影響**: このトークンを参照しているcmd/report/lessonはどれか？
- **横影響**: 同じcanonical名を使う他エントリとの整合性は保たれるか？

### 時系列保存(因果探索用)

辞書変更はgit履歴で追跡するだけでなく、disambiguation.md内にchangelogセクションを保持:

```markdown
### Changelog

| Date | Token | Change | Reason | Cmd |
|------|-------|--------|--------|-----|
| 2026-05-04 | L0-L4 | initial: 6体系(sync/pf/calc/vis/kb/math)を定義 | 本セッションでpf_L2をL3と誤認した事故 | cmd_2555 |
| (将来) | ... | エントリ追加/意味変更/canonical名変更時に追記 | ... | ... |
```

因果探索: 「なぜこの定義になったか」→ changelog.reason → 元cmdの偵察結果 → 殿との議論 → 事故の原点。
時系列が残っているから、将来の将軍が「この定義は本当に正しいか？」と疑った時に因果をたどれる。

---

## §3 辞書構造(disambiguation.md)

正本ファイル: `docs/knowledge-base/terminology/disambiguation.md`
形式: MDテーブル + CoDD frontmatter。CoDDのMD→MD伝播に対応。

```markdown
---
design: disambiguation
version: "1.0"
last_updated: "2026-05-04"
principle: "1 token = 1 meaning per context. Context is determined by file path pattern."
downstream:
  - context/dm-signal-terminology.md
---

MDテーブル構造(本体):

### P0: L0-L4

| Token | Scope Pattern | Meaning | Canonical |
|-------|---------------|---------|-----------|
| L0 | backend/app/api/etl_trigger* | sync stage: Price取得層(依存なし) | sync_L0_price |
| L0 | context/dm-signal-core.md §0 | PF研究階層: 四神(12体) | pf_L0_shijin |
| L0 | frontend/app/admin/page.tsx | sync stage UI: Price Syncボタン | sync_L0_price |
| L0 | projects/dm-signal.yaml naming | 命名規則: 四神名フォーマット | pf_L0_shijin |

| L1 | backend/app/api/etl_trigger* | sync stage: Ticker計算層(L0に依存) | sync_L1_ticker |
| L1 | context/dm-signal-core.md §0 | PF研究階層: 忍法(20体) | pf_L1_ninpo |
| L1 | context/dm-signal-core.md §2 | SSOT計算層: 計算ロジック(return_calculator等) | calc_L1_function |
| L1 | frontend/app/admin/visibility* | visibility: ページ表示制御 | vis_L1_page |
| L1 | docs/knowledge-base/index.md | KB複雑度: 基礎(既存パイプラインに容易に追加) | kb_L1_basic |
| L1 | 正規表現/統計文脈 | L1ノルム(LASSO正則化) | math_L1_norm |
| L2 | backend/app/api/etl_trigger* | sync stage: Standard PF再計算層(L1に依存) | sync_L2_standard |
| L2 | context/dm-signal-core.md §0 | PF研究階層: 奥義(GS済みFoF 21体) | pf_L2_ougi |
| L2 | context/dm-signal-core.md §2 | SSOT計算層: MonthlyReturnキャッシュ | calc_L2_cache |
| L2 | frontend/app/admin/visibility* | visibility: PF非表示制御(hide_portfolio) | vis_L2_hide_pf |
| L2 | docs/knowledge-base/index.md | KB複雑度: 中程度(状態モデル/レジーム判別) | kb_L2_medium |
| L3 | backend/app/api/etl_trigger* | sync stage: FoF再計算層(L2に依存) | sync_L3_fof |
| L3 | context/dm-signal-core.md §2 | SSOT計算層: UI表示層 | calc_L3_ui |
| L3 | frontend/app/admin/visibility* | visibility: シグナルマスク制御(hide_signal) | vis_L3_mask_signal |
| L3 | docs/knowledge-base/index.md | KB複雑度: 高度(深層学習/複雑アンサンブル) | kb_L3_advanced |
| L4 | frontend/app/admin/visibility* | visibility: コンポーネントマスク制御(hide_components) | vis_L4_mask_components |
| L4 | docs/knowledge-base/index.md | KB複雑度: メタ分析レベル | kb_L4_meta |

### P0: signal

| Token | Scope Pattern | Meaning | Canonical |
|-------|---------------|---------|-----------|
| signal | signals.signal (DBカラム) | パイプライン生出力(リバランス前) | raw_pipeline_signal |
| signal | signals.holding_signal (DBカラム) | リバランス適用後の保有シグナル | rebalance_holding_signal |
| signal | DM-Signal (プロダクト名) | プロダクト名称 | dm_signal_product |
| signal | frontend/ context/state | FEのAPI取得済みシグナルペイロード | portfolio_signal_state |
| signal | hide_signal (DB/API) | visibility mask flag | mask_signal_enabled |
| signal | signal_date (FoFキャッシュキー) | FoFコンポーネント参照日 | fof_signal_fix_date |

### P0: monthly_return

| Token | Scope Pattern | Meaning | Canonical |
|-------|---------------|---------|-----------|
| monthly_return | monthly_returns.monthly_return (DB) | Close-to-Close月次リターン(本番表示用) | monthly_return_close |
| monthly_return | monthly_returns.monthly_return_open (DB) | Open-to-Open月次リターン(GS/選抜用) | monthly_return_open |
| monthly_return | GS CSV列 | GS出力のOpen-to-Open月次リターン値 | gs_monthly_return_open |
| monthly_return | API response | API返却値(Open/Close選択はエンドポイント依存) | api_monthly_return |

### P0: date

| Token | Scope Pattern | Meaning | Canonical |
|-------|---------------|---------|-----------|
| date | signals.date (DBカラム) | シグナル確定日(月初営業日) | signal_fix_date |
| date | as_of (API/計算) | 計算基準日(DB最新日 or today) | calculation_as_of_date |
| date | position start/end | ポジション保有開始/終了日 | position_start_date / position_end_date |
| date | FE current/latest | UI表示上の選択状態 | ui_selected_date |

### P1-P3(段階3以降で追加)

- P1: FoF/component, weight, status, phase, method, source
- P2: universe, metrics, performance
- P3: type, mode, tier, family, block

---

## §4 既存contextの注釈追加

穴2対策: 既存の多義箇所に inline comment でスコープヒントを付与する。

```markdown
## §0 研究レイヤー構造
<!-- terminology: pf_L0/pf_L1/pf_L2 -->

| Layer | Name | Description |
|-------|------|-------------|
| pf_L0 (旧L0) | 四神 | 個別DM戦略 |
| pf_L1 (旧L1) | 忍法 | 5忍法×3モード |
| pf_L2 (旧L2) | 奥義 | 上位構造の堅牢性検証 |
```

```markdown
## §2 SSOT階層
<!-- terminology: calc_L0/calc_L1/calc_L2/calc_L3 -->

| Level | Source | Description |
|-------|--------|-------------|
| calc_L0 (旧L0) | Price/trade-rule | 価格+ルール(SSOT最上位) |
| calc_L1 (旧L1) | return functions | 計算ロジック |
| calc_L2 (旧L2) | MonthlyReturn table | 事前計算キャッシュ |
| calc_L3 (旧L3) | UI表示層 | 派生実装 |
```

方針: 旧表記をカッコ内に残し後方互換を保つ。新規記述ではcanonical名を使用。

---

## §5 gate強制設計

### 5.1 cmd_save.sh追加チェック

```bash
check_dm_signal_bare_layer_reference() {
    # project: dm-signalのcmd内で文脈なしの生L0-L4を検出
    [[ "$PROJECT" != "dm-signal" ]] && return 0

    # purpose/AC/command内の生L*を検出(コードパス引用は除外)
    local bare_refs
    bare_refs=$(echo "$CMD_BLOCK_NC" | grep -oP '\bL[0-4]\b' | sort -u)

    # 除外: バッククォート内(コード引用)、ファイルパス内
    local filtered
    filtered=$(echo "$CMD_BLOCK_NC" | grep -P '\bL[0-4]\b' | grep -vP '`[^`]*L[0-4][^`]*`' | grep -vP '\S+\.py.*L[0-4]')

    if [[ -n "$filtered" ]]; then
        echo "WARNING: dm-signal cmdに文脈なしのL*表記あり。" >&2
        echo "  どの体系か明示せよ: sync_L2/pf_L2/calc_L2/vis_L2/kb_L2" >&2
        echo "  参照: docs/knowledge-base/terminology/disambiguation.md" >&2
        record_warn_reason "bare_layer_ref" "check=check_dm_signal_bare_layer_reference"
    fi
}
```

### 5.2 除外条件(穴5対策)

以下はWARN対象外:
- バッククォート囲み(`` `etl_trigger.py L2` ``)= コード引用
- ファイルパス+行番号付き(`backend/app/api/etl_trigger.py L512`)= 実装参照
- canonical名使用(`sync_L2`, `pf_L2_ougi`等)= 辞書準拠
- 数学/統計文脈: 同一行に正則化/ノルム/LASSO/Ridge/regularization等のキーワードがある場合(軍師レビュー追加。L1ノルム/L2正則化の偽陽性防止)

### 5.3 pre-write-edit-combined.sh追加チェック

context/dm-signal*.md更新時に同様の検出を実施。
cmd_save.shよりも先(edit段階)で止まる。cmd_2550の設計と同パターン。

---

## §6 段階導入計画(穴4対策)

| 段階 | 対象 | 成果物 | 完了条件 | 期限(タイムボックス) | 次段階移行トリガー |
|------|------|--------|----------|---------------------|-------------------|
| 0 | P0の4群(L*, signal, return, date) | disambiguation.md + dm-signal-terminology.md | MD+context配置完了+起動時ロード確認 | 2026-05-05 | 段階0 GATE CLEAR |
| 1 | 既存context注釈追加 | dm-signal-core.md §0/§2に注釈 | 注釈追加+軍師レビューPASS | 2026-05-06 | 段階1 GATE CLEAR |
| 2 | gate実装 | cmd_save.sh + pre-write hook | gate追加+偽陽性テスト3件PASS | 2026-05-07 | 偽陽性0件(直近5cmd) |
| 3 | P1の6群追加 | disambiguation.md拡張 | 6群追記+terminology.md更新 | 2026-05-10 | 段階3 GATE CLEAR |
| 4 | CoDD frontmatter運用開始 | propagate自動化 | scan/impact/propagate 1サイクル成功 | 2026-05-14 | propagate実行成功 |
| 5 | P2-P3追加 | 全27群完成 | 全群辞書化+gate全対応 | 2026-05-17 | 全27群MECE確認 |

各段階は1-2cmdで完了する規模に分割。

**放置防止メカニズム**:
- 各段階の期限を`gate_shogun_startup.sh`の気づきキューに登録
- 期限超過→startup gate ALERT「段階N期限超過。次段階に進め」
- 段階完了時に次段階の期限をinsight_write.shで自動登録(cmd完了hookで発火)

---

## §7 context配置計画

```
context/dm-signal-terminology.md (新規)
  - エージェント起動時ロード対象に追加
  - CLAUDE.md Current Project → context_filesに追記
  - 内容: disambiguation.mdから導出した14行テーブル(P0の4群)
  - 80行以下に収める(File Reading Rule準拠)
```

CLAUDE.md変更箇所:
```yaml
context_files:
  - file: "context/dm-signal-terminology.md"
    tags: [terminology, disambiguation, all]
```

`tags: [all]`により全dm-signal cmdで自動ロード対象。

---

## §8 辞書未参照の検知(穴1対策)

cmd文中でL*を使う時の強制フロー:

1. pre-write hookが生L*を検出 → BLOCK「canonical名を使え」
2. 忍者が辞書を参照 → scope_patternから該当canonical名を特定
3. canonical名(sync_L2等)で記述 → gate PASS

忍者が辞書を参照しない限りBLOCKが解除されない = 参照の強制。

---

## §9 上流コード変更時の追随(穴3補完)

BEのetl_trigger.pyに新しいLayer(例: L4)が追加された場合:

1. 忍者の報告にknowledge_candidate.found=trueで「sync_L4追加」を報告
2. 家老がdisambiguation.mdにエントリ追加
3. 手動propagateでcontext/dm-signal-terminology.mdを更新

CoDD CLI自動化(段階4)までは手動。手動でも辞書→context→gateの3層は機能する。
自動化は「手動propagateの忘れ」をゼロにするための改善であり、機能自体は手動で動く。

---

## §10 双方向整合性保証(中核設計)

### 正方向: 辞書変更→context追随

| 手段 | トリガー | 動作 |
|------|---------|------|
| CoDD propagate (MD→MD) | disambiguation.md変更をgit diff検出 | dm-signal-terminology.mdをAI更新提案 |
| 手動propagate (段階0-3) | 辞書編集者が手動でcontext更新 | gate(mtime比較)で未更新を検出 |

### 逆方向: context変更→辞書との矛盾検出

| 手段 | トリガー | 動作 |
|------|---------|------|
| セマンティック整合性チェック | context/dm-signal*.md変更時(pre-commit or 軍師idle) | 変更されたcontextと辞書を突合し、辞書定義と矛盾する多義使用を検出 |

### なぜ双方向が必要か(なぜなぜ7回結論)

- 正方向だけ: 辞書は最新だがcontextが別理由で変更され辞書と矛盾→検出不能
- 逆方向だけ: contextは正しいが辞書が古い→canonical名が陳腐化→検出不能
- **両方揃って初めて整合性崩壊を構造的に防止**

### セマンティック整合性チェックの実装

```
実行タイミング:
  (a) context/dm-signal*.md に変更があった時(pre-commit hook or 軍師idle)
  (b) 辞書変更後のpropagate完了時(正方向完了の確認)
  (c) 定期(週1の/dreamタイミング)

入力:
  - disambiguation.md (正本辞書)
  - 変更されたcontext/*.md (diff or 全文)

処理:
  LLMに以下を問う:
  「このcontext内で、disambiguation.mdの定義と矛盾する用語使用はないか？
   特に: 生L*の文脈なし使用、canonical名と異なる意味での使用、
   辞書に未定義の新しい多義パターンの導入」

出力:
  - 矛盾0件: PASS
  - 矛盾N件: 各箇所+辞書定義+矛盾内容をリスト化→家老に報告
```

### 軍師idleへの組込み

軍師のidle Step 7(セマンティック監査)に「辞書整合性チェック」を追加:
- 既存: 5カテゴリ探索(silent_failure/state_transition/race_condition/implicit_assumption/side_effect)
- 追加: terminology_drift(辞書定義からの逸脱検出)

これにより定期的にセマンティック整合性が自動監視される。
