# 成長ループ設計 — 全ロール共通
<!-- last_updated: 2026-04-21 -->
<!-- origin: 殿指摘2026-04-20「BLOCKされたら次のCMDでBLOCKされないように成長する=主軸。ゲートを通すのは枝葉」 -->

## §1 核心原則

**gateで止める = 止血帯(枝葉)。成長 = 最初から間違えない構造(主軸)。**
gateの成功 = システムの未熟さの証拠。gateが発火しないシステムが完成系。

## §2 ロール別の成長メカニズム

| ロール | トリガー | 成長の強制方法 | enforcement |
|--------|---------|---------------|-------------|
| 将軍 | cmd_save.sh BLOCK/WARN | environment_change必須(構造化+grep検証) | cmd_save.sh Check 3.6+3.6b |
| 家老 | workaround発生 | environment_change必須(同構造) | karo_workaround_log.sh |
| 忍者 | 報告フォーマットエラー | 間違える余地がない構造(フィールド間整合性制約) | report_field_set.sh GP-072c5 |

## §3 environment_change 4層防御(将軍・家老共通)

1. **禁止値**: 初回起票/初回/該当なし/修正した/対策済み等 → BLOCK
2. **構造化必須**: 自由テキスト → BLOCK。`type=gate|lesson|hook; file=対象パス; pattern=grepパターン` 形式必須
3. **実装grep検証**: `grep -qE pattern file` で実在証明。不在 → BLOCK
4. **効果検証**: 同じWARNが再発 → 「前回のenvironment_changeが効いていない。なぜなぜ7回で深掘りせよ」

## §4 WARNもスルーしない

- BLOCK後だけでなくWARN検出時もenvironment_change要求(Check 3.6b)
- Check 3.6b は全チェック完了後に配置(WARNは後段Checkで蓄積されるため)
- WARNが出た = 問題がある。次のcmdで同じWARNが出ないように環境に埋め込め

## §5 忍者の成長 = 矛盾を作れない構造

忍者は/clearで記憶を失う。environment_changeを書かせても次のセッションで消える。
忍者の成長は「フロー上で矛盾した状態を作れないようにする」:
- bc:no + verdict:PASS → 書込み時BLOCK(GP-072c5)。事後検出ではなく事前防止
- autofix(true→yes変換等)で構文エラーは自動正規化。意味的矛盾のみBLOCK

## §6 なぜなぜ7回との関係(deepdive Phase 5)

environment_changeに書く前に「なぜ」を深掘りしないと浅い対策になる。
浅い対策 → 次も同じBLOCK → WARN累計昇格 → 「前回のenvironment_changeが効いていない」フィードバック(§3-4)。
深掘り不足が構造的に検出される。

## §7 BLOCKとWARNは同列(殿裁定2026-04-21)

**消火と学習の違い**: WARN出た→修正して通す=消火(ループするが成長しない)。WARN出た→なぜ出たか→二度と出ない仕組みを環境に埋め込む=学習。

- informational除外を廃止: q4/q6/q7/q10/Check18/Check17をWARN_COUNTに加算(6種昇格)
- 全品質WARNが学習(environment_change)を強制される
- 判定基準: 「無視するとcmd品質が下がるか？」YesならWARN(学習対象)、NoならINFO(表示のみ)

## §8 遡及学習(殿裁定2026-04-21)

**1回目のWARNで過去を見る**: record_warn_reason内で過去の同一WARN件数を即表示。
「★ このWARNは過去N回出現。消火ではなく根本修正を検討せよ。」

**起動時に自動表示**: gate_shogun_startup.sh Gate 12.5。直近50cmdのWARN/BLOCK頻度TOP 5。
- cmd数基準(日数ではない): 長期離席でも直近50cmdの傾向が見える
- 修正済みパターンは50cmd以内に再発しなければ自然に脱落
- 「直近50cmdのWARN/BLOCKなし」=学習ループ健全の指標

**遡及学習の実績(2026-04-21)**: 過去1495cmdを分析→TOP 5根本修正で164回分の消火を根絶。

## §9 偽陽性監視(Gate 13.8)

gate_shogun_startup.sh Gate 13.8: WARN typeごとの偽陽性率を30日窓で計測。
FP率60%以上 → ALERT。gate精度劣化の早期発見 → gate改善も成長の一部。

## §10 スキル自動成長ループ(4段階)

スキル実行の品質を計測→還流し、SKILL.md自体を育てる仕組み。

| 段階 | 動作 | 記録先 |
|------|------|--------|
| (1) 実行 | スキル実行後、結果をログ記録 | skill_execution_log |
| (2) つまずき | FAIL発生 → stumbling_points欄に記録 | skill_execution_log |
| (3) 改善案集計 | skill_auto_improve.sh がFAILパターンを集計 | 改善候補リスト |
| (4) 品質向上 | `--apply` でSKILL.mdの注意ポイント自動書込み + ninja_monitor週1自走 | SKILL.md |

**帰属精度(cmd_2604)**: GATE_SKILL_MAP固定マッピングでgateとスキルを1対1対応。
スキル別GATE結果の帰属を正確に計測し、改善対象スキルを特定する。

**PASS記録統一(cmd_2605)**: gate_report_format.sh PASS分岐からも統一記録。
FAIL時だけでなくPASS時も記録することで、スキル全体のパフォーマンス分布を把握する。

## §11 防御階層原則 — 5段階(殿定義2026-05-09)

**ゲートの成功=未熟さの証拠。発火しないシステムが完成系。**

| Level | 名称 | 仕組み | 例 |
|-------|------|--------|-----|
| 1 | 事後検出 | 間違えた後にgateが検出 | gate_report_format.sh: 報告提出後にフォーマット不備検出 |
| 2 | 事前予防(doc) | ドキュメントに「こうせよ」と記載 | gunshi.md: 「git show HEADで確認せよ」 |
| 3 | 事前強制(auto-gen) | テンプレートを自動生成して正しい構造を強制 | deploy_task.sh: 報告テンプレート自動生成 |
| 4 | フロー内BLOCK | 間違ったら即停止。先に進めない | cmd_save.sh: q11にgrepなし→BLOCK |
| 5 | 事前コンテキスト提供 | 正しい入力を自動生成して渡す。間違える余地がない | cmd_2617: preflightがgrep結果を自動表示→コピーするだけ |

**Level 1-4と5の本質的違い**:
- Level 1-4: 「間違えてから止める」。止め方の強さが違うだけ。ゲートは発火し続ける
- Level 5: 「間違える前に正しい答えを渡す」。ゲートが発火する必要がなくなる

**全ロール共通の設計指針**:
- 新規gate/hook設計時: 最初からLevel 5を目指せ。Level 4で止めるな
- 既存gate/hookの改善時: 繰り返し発火しているチェック → Level 5化の候補
- GP提案時: `defense_level`フィールドにLevelを明記。Level 4以下なら「Level 5化できないか？」を自問
- **BLOCKされたら**: 修正してCLEARするだけでなく「同じBLOCKが二度と起きない仕組み」を環境に埋め込め

**計測指標**: Level 4:Level 5の比率。2026-05-10時点 = Level5:7件(44%)。Level 5比率の向上が成長の指標。

**実績(2026-05-09〜10)**:
- cmd_2616: q11 WARN→BLOCK昇格(Level 4)
- cmd_2617: q11 preflight自動grep(Level 5)。同じ問題にLevel 4→5の進化を1セッションで実現
- cmd_2618: 未自動化教訓18件のLevel 5化計画策定(偵察)
- cmd_2619: research_tool_explicit FP修正+ACパス自動提案(Level 5化)
- cmd_2620: セマンティクスインデックスaliases受動表示(Level 5化)
- D0: gate_vercel_phase broken ref候補自動提案(Level 5化)

**詳細監査データ**: `docs/research/gunshi_defense_hierarchy_audit_20260510.md`(全16仕組み+全4PJ横断+cmd_save WARN TOP5+なぜなぜ7回)
