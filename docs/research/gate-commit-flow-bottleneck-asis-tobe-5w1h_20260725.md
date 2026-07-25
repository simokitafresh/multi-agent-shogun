# gate/commitフロー ボトルネック設計書 — AsIs/ToBe 5W1H

origin: [[殿指示_gate_commit_flow設計_20260725]] <- [[three-layer-learning-loop-auto-growth v3.0]] + [[deploy_control_plane速度改善_20260721]] + [[将軍家老RCA協働_20260725]]
created: 2026-07-25T17:00+09:00 (将軍直筆)
status: **v2.1 — 殿裁可(2026-07-25 17:48)。方針1+push通過+CI後追い方式(歯止め2点付き)を正式採用。実装分解へ**
baseline: 2026-07-25 一次計測(defense_overhead.jsonl + 本日の事故4件)

## §0 要求定義(殿指示 2026-07-25 16:57)

| 要素 | 内容 |
|------|------|
| WHY | gate/commitでボトルネックが頻発している。場当たり対処でなくフロー全体を一枚で見て方針を決める |
| WHAT | cmd実行フロー全体の設計書+ボトルネック台帳+ToBe方針案 |
| WHO | 起草=将軍、レビュー=家老(運用実態)+軍師(品質観点)、裁定=殿 |
| HOW | 本日の実測・事故データで接地。原則=品質2原則維持のまま超速化(P7)+考える工程は削らない(P8) |

## §1 AsIsフロー(cmd 1本のライフサイクル)

```
[起票] 将軍cmd_save.sh(gate: q1-q3 BLOCK+三層発火) 実測2.1s(表示型cut後)+three_layer_ruling 8.4s(median)
  ↓
[配備] 家老deploy_task.sh(admission/related_lessons/preflight/契約注入) 実測35.8s(-47%改善後)。テールmax 65.3s
  ↓
[作業] 忍者実装+テスト → /ninja-commit(scope検証+pre-commit hook)
  ↓
[報告] /report-write(report_field_set)→gate_report_format(bc→verdict自動導出)
  ↓
[一次レビュー] 軍師precheck(median 4.8s/max 50.4s)→レビュー→LGTM/FAIL
  ↓
[完了] 家老cmd_complete_gate.sh(GATE CLEAR判定+ロック) → post-CLEARパイプライン
        (insight triage→通知→dashboard→gist→task idle戻し) ※直列
  ↓
[後処理] archive_completed.sh+push(CI GREEN時)→CI(bats)→CI RED時は忍者ci_fix配備
```

## §2 ボトルネック台帳(本日までの実測・全て一次証跡あり)

| # | 箇所 | 事象 | 実測 | 分類 |
|---|------|------|------|------|
| B1 | cmd_save | three_layer_ruling_overhead | median 8.4s/max 32.2s | 速度 |
| B2 | deploy | queue/125,527ファイルのpreflight走査 | 配備wall 141.6s(3倍化)実測 | 速度(資源) |
| B3 | 軍師precheck | コールドパス | median 4.8s/max 50.4s | 速度 |
| B4 | cmd_complete_gate | post-CLEAR直列: triage 1件BLOCKで後続全停止(idle戻し欠落→次弾配備BLOCK連鎖) | cmd_4171実証 | 直列脆弱 |
| B5 | commit | HEAD lock競合(多エージェント同時commit) | 将軍commit失敗1回/日実測 | 競合 |
| B6 | commit | 新規ファイルsource+未追跡=CI破壊(才蔵239d663ff) | 本日実証 | 品質 |
| B7 | commit→CI | gate系ファイル変更の回帰がCIで初検出(bats 3件RED) | run 30149013181 | 品質(遅い検出) |
| B8 | scope検証 | test batsがplanned_paths未宣言→全忍者反復BLOCK | 軍師知見07-25 | 品質(FP) |
| B9 | stop hook | session_alerts同根因3行重複=処理コスト3倍 | shogun-rca:5 | 品質(重複) |
| B10 | loop_ledger | 33.2s/回+stock指標欠陥(是正済) | shogun-rca:3/穴12 | 速度+計器 |

### §2.1 軍師レビューによる追加(blt_171812。全て軍師の本日一次実測。詳細は同掲示板正文)

| # | 箇所 | 事象 | 分類 |
|---|------|------|------|
| B11 | 報告publish経路 | terminal publishの32.1%が>1秒(avg 10.9s/max 48.1s) | 速度 |
| B12 | gate_report_format | single-flight timeoutを品質FAILへ誤帰属(6件実測) | 品質(誤帰属) |
| B13 | review_log gate_result | 1cmd=1スカラーで中間BLOCK固定→38%が最終結果と不一致 | 計器 |
| B14 | 軍師precheck | 書込み中evalが構文エラー即死→ERRORS未算出でfail-open | 品質(fail-open) |
| B15 | gate_metrics.log | rotate後もliveファイル1本しか読まないconsumer複数(promotion consumed急落の真因) | 計器 |
| B16 | LG051スコープ | basename先頭一致で対象漏れ(dead code見逃しの原因。cmd_complete_gate.sh自身も対象外) | 品質(検出漏れ) |
| B17 | retention台帳 | 固定パス上書きで移動記録消失(quarantine 17,381ファイルに対し台帳0件) | 計器 |
| B18 | AC内の行番号参照 | 並行変更で陳腐化し別の行を指す(本日3cmd実証) | 品質(誤誘導) |
| B19 | 共有worktree commit | 指揮官D0 commitが第三者のstage済み変更を巻き込み帰属破壊(0f1c3ea65将軍commitが才蔵922行を巻込→才蔵7回BLOCKループ) | 競合(retry不可) |
| B20 | ci_readiness記録(家老が独立検証で一致=24/108=22.2%。pending queuedもWAITへ) | BLOCK 104件の実測分解: 真の赤23件(22.1%)のみ。SHA mismatch34+predates SG7 26=E型(CI runと評価対象の対応付け破壊)、pending13=**WAIT**(gate自身が再実行を指示するのにterminal BLOCK記録=誤り)。一括計上すると実態の78%を取り違える | 計器(E型)+記録分類 |

### §2.2 家老レビューによる追加(blt_174610。全て本日一次実測)

| # | 箇所 | 事象 | 分類 |
|---|------|------|------|
| B21 | FAIL verdictのクローズ | **正規経路は存在しない(軍師が現物確認で確定・自身の先行回答を撤回)**: archive_completed.sh明示CMD_ID経路もreview_gate.done検査(1279-1304行、sweep分岐の外側)で停止し、CLEARを持たないcmdは構造的にarchive不能。唯一機能する経路(karo RC→AC是正→同一cmd_id再配備)は手順書に未記載 | 直列脆弱(B型)+経路欠落 |
| B22 | retro回答 | 忍者がinboxで回答してもtype不一致で機械判定に乗らず家老が手動復元 | 品質(誤帰属) |
| B23 | yaml_field_set | list型・ネスト型が書けずplanned_paths拡張/ci_fix evidence記入が毎回手作業(本日4回) | 速度(手動律速) |

**C型の本体再定義(家老)**: 『同一ファイル並行』ではなく**『commit/pushの粒度が宣言scopeと一致しない』**が本体。本日4件(未commit差分の塞ぎ/922行巻込7回BLOCK/家老pushが他者未commit状態を公開しCI RED/pre-push警告2回を再試行で突破)。指揮官3ロールのcommitと**pushも**scope分離機構の対象に含める。

## §3 構造分類 — ボトルネックは5種類(A-E)

| 型 | 該当 | 対処原理 |
|----|------|---------|
| A 速度型(機械的処理が遅い) | B1/B2/B3/B10 | **台帳駆動高速化**(支配項逆引き→品質維持高速化→前後証明)。稼働中 |
| B 直列脆弱型(1箇所の失敗が全体を止める) | B4 | **fail-open分離**(各ステップ独立+失敗隔離)。配備中(才蔵再作業) |
| C 競合型(共有資源の同時アクセス) | B5(HEAD lock)/B2(queueファイル) | **単一writer化 or リトライ規約 + retention**(T9) |
| D 品質型(検出が遅い/誤検出/重複/検出漏れ/誤誘導) | B6/B7/B8/B9/B16/B18 | **検出の前倒し**+**FP根治**+**重複統合**。軍師提案で**誤帰属サブ型**(B12/B14: 正しく検出したが原因を別主体へ帰属)を明示 — 対処=失敗種別の機械可読化(影丸cmd実装中) |
| E 計器型(測定系自体の誤り)【軍師提案で独立】 | B10/B13/B15/B17 | **一次情報との定期突合**。計器の誤りは自己検知できず全判断を汚染するため型分離必須(B13で軍師自身のaccuracy指標が信頼不能と判明した実証) |

## §4 ToBe方針案(レビュー対象)

### 方針1: 型別の標準対処を確立し、新規ボトルネックは型判定→標準対処で処理する
各ボトルネックへの個別対処(各論パッチ)をやめ、§3の4型への分類と型別標準対処を正本化する。
- A型→既存高速化レーン(変更なし・実績-47%〜-99%)
- B型→post-CLEARで確立するfail-open分離パターンを、他の直列パイプライン(deploy内部/archive)へ横展開
- C型→(a)commit: 忍者はninja_scope_commit.sh(HEAD由来専用index+宣言scope限定add=LG004)で既に保護済み。**指揮官(将軍/家老/軍師)D0 commitへ同機構の適用範囲を拡大**(B19対処。新規機構でなく既存スクリプトの流用)+retryヘルパー (b)queue: T9 retention
- D型誤帰属サブ型の追加対処: DIVERGENT警告に『同一BLOCK反復時は外部要因の可能性を家老へ確認せよ』分岐を追加(本日BLOCKループ12回は全て忍者の外に原因があり、警告が誤った自己修正へ誘導していた)
- D型→**commit時構造検証の1本化**: 「新規source先の同一commit内包」「gate系変更時のbats実行」をpre-commitへ接続。選定規則(軍師レビュー確定): 新規機構は作らず**既存run_tests.shのaffected/taskスコープに乗せる**(staged paths→affected、FAIL>0またはSKIP>0でBLOCK)。ただし**逆依存規則を明文化**: scripts/lib/*の追加・変更はtests/helpers/*経由の全testをaffectedに含める(CI RED 30148392707の真因=helper allowlist未追随がこの規則で捕まる)
- B8(planned_paths)→自動拡張は**非対称**で統合: ACがtest作成を要求する場合のみtests/配下への拡張を許す(permission ceilingの一般緩和はしない)
- E型→計器と一次情報の定期突合をT8(計器契約検証)へ統合
- B20→**記録カテゴリの3分離(BLOCK/WAIT/INFO)**: pendingはBLOCK率に数えない(指標水増し+軍師予測精度汚染+『BLOCK=成長機会』原則の空振り適用を防ぐ)。真のGREEN失敗のみD型即応SLA対象。push通過+CI後追い方式が入ればSHA mismatch/predates計60件は正規手順へ吸収されBLOCK記録自体が不要化=**殿発案方式の定量的裏付け**。GATE_PREDICTIONへのci_readiness事前判定(CI run状態+headSha+bundle mtimeで提出前機械判定)も併せて有効

### 方針1追加要素(殿発案 2026-07-25 17:11): push通過+CI後追い方式
「CI GREEN待ちでpush保留」を廃し、**pushは常時通過させ、CI REDは後追いの即応義務に変える**。
- 根拠: (1)LS101 push保留デッドロック実証(修正21h未pushでRED自己永続) (2)本日lib hotfix即pushが現HEADの真の回帰即検出を可能にした (3)本repoはpush≠デプロイでrevert完全可逆(07-10裁定適用対象)
- 必須条件: (a)CI RED→忍者ci_fix即配備SLAの強制継続 (b)D型検出前倒しとセット(CIは最後の網に格下げ) (c)push=本番デプロイ直結repo(DM-Signal等)は適用外
- レビュー観点追加: 家老=RED放置累積の歯止め運用、軍師=RED中の追いpush許容条件(未解決RED上への積み増し規則)

### 方針2(対案): CI RED級のみ即応し、速度系は現行レーン任せで新設なし
最小変更。ただしB5/B6/B7は再発する(本日3件発生が反証)。

### レビュー結果サマリ(2026-07-25 完了)
- **軍師**: 方針1賛成+push通過方式条件付き賛成。B11-B18+B20追加、E型独立、誤帰属サブ型、affected逆依存規則、planned_paths非対称拡張
- **家老**: 方針1賛成+push通過方式賛成。ci_readiness分解を独立検証(22.2%で一致)。B21-B23追加、C型本体再定義、pre-commit接続の費用対効果=正(追加数百msに対しCI 1周8-10分+往復の削減)を実証
- **push通過方式の歯止め(家老提案)**: (a)RED検知→忍者配備SLA=『次のGATE処理より前』に固定(人の判断に委ねない) (b)同一REDへの追いpush上限2回、3回目で新規配備停止しRED修正へ全リソース

**将軍推薦=方針1**。理由: 本日1日でB4-B7の4件が実発生しており、型別標準対処がなければ同型を毎回一から診断することになる。方針1は新gate増設ではなく「既存機構への接続+パターンの正本化」であり、P7(削るな速くしろ)/P8(考える工程維持)と整合。

## §5 レビュー依頼事項

- 家老へ: (1)§1フローに運用実態との乖離はないか (2)B5 commit競合の頻度体感と、retryヘルパーの現実性 (3)§4方針1のD型=pre-commit接続が配備フローを遅くしないか(速度と品質のトレードオフ実測案)
- 軍師へ: (1)§2台帳に漏れているボトルネックはないか(レビュー観点から) (2)D型「gate系変更時の該当batsローカル実行」の選定規則(全量実行はBLOCK対象=cmd_save gate反転と整合させる方法) (3)B8 planned_paths自動拡張(tobisaru decision_candidate)の本設計への統合可否

レビュー期限: 忍者稼働と並行で可。両者のレビュー完了後、将軍が集約して殿裁定へ上げる。

## 因果リンク
- ← [[three-layer-learning-loop-auto-growth v3.0]] §3.4詰まり台帳+P7-P10=本設計の原理
- ← [[defense_overhead.jsonl]] B1-B3/B10の実測正本
- → [[cmd_karo_hotfix_post_clear_fail_open_20260725]] B型の初実装(才蔵再作業中)
- → [[LS101]] CI RED診断手順 / [[LS110]] 証跡と現物の突合=B6の教訓的根拠
