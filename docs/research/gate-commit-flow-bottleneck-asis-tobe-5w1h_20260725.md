# gate/commitフロー ボトルネック設計書 — AsIs/ToBe 5W1H

origin: [[殿指示_gate_commit_flow設計_20260725]] <- [[three-layer-learning-loop-auto-growth v3.0]] + [[deploy_control_plane速度改善_20260721]] + [[将軍家老RCA協働_20260725]]
created: 2026-07-25T17:00+09:00 (将軍直筆)
status: **v2.1 — 殿裁可(2026-07-25 17:48)。方針1+push通過+CI後追い方式(歯止め2点付き)を正式採用。実装分解へ**
baseline: 2026-07-25 一次計測(defense_overhead.jsonl + 本日の事故4件)

> **⚠ 台帳訂正(2026-07-25 22:18 軍師全件集計+家老自己申告による)**: 本§2台帳は「実体の写し」であり転記時点の値・表現に誤りが含まれていた。確定訂正: (1)B1のcheck_id正式名は three_layer_memory_ruling_overhead (2)B2『141.6s』はn=494中の0.2%単独外れ値でありmedian=1220ms(常態化ではない。ただし忍者配備のみ抽出するとn=6全件42s超=母集団定義の分離が必要、疾風が実測中) (3)queue 125,527ファイルは14:40時点値。campaign_lane GC後の実測=55,845 (4)B11のpublish系check_idは台帳に0件=計装自体が不在(遅延実測はreceipt tsv由来) (5)B21は20:46解消済み。**この台帳を読んで起票する者は、必ず該当する一次データ(台帳jsonl/コード現物)を再実測してから使え。台帳の写し読みがE型7例目(重複起票)を生んだ。**

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
| B21 | FAIL verdictのクローズ | **正規経路は存在しない(軍師が現物確認で確定・自身の先行回答を撤回)**: archive_completed.sh明示CMD_ID経路もreview_gate.done検査(1279-1304行、sweep分岐の外側)で停止し、CLEARを持たないcmdは構造的にarchive不能。唯一機能する経路(karo RC→AC是正→同一cmd_id再配備)は手順書に未記載 | 直列脆弱(B型)+経路欠落 → **解消済み(2026-07-25 20:46 才蔵cmd_karo_impl_fail_close_path CLEAR: archive_completed.sh:1326/1343 FAIL_CLOSE分岐+手順書記載+bats 3/3)。※この行の旧記述を写しとして読んだ家老の重複起票=E型7例目(blt_220450)** |
| B22 | retro回答 | 忍者がinboxで回答してもtype不一致で機械判定に乗らず家老が手動復元 | 品質(誤帰属) |
| B23 | yaml_field_set | list型・ネスト型が書けずplanned_paths拡張/ci_fix evidence記入が毎回手作業(本日4回) | 速度(手動律速) |

| B24(数値更新: cancelledは直近60run中13%。按分推定で真の失敗は12.5-13.5%、22.2%は上限値) | ci_readiness cancelled | キャンセルされたCI runがconclusion=failureとして記録され『is not GREEN』BLOCKに混入(run 30151586555実測: 全4 job cancelled=テスト未実行なのにfailure)。実体は『CIが赤』でなく『CIが走っていない』 | 計器(E型)。是正=cancelledはWAIT扱い(再実行促し) |

| B25 | gate_metrics.log | ci_readiness行が解釈済み文字列のみ保存し観測生値(run_id/conclusion)を捨てる→過去分の分類再検算が原理的に不可能(B20/B24の直接計測を阻む)。是正=末尾にrun_id/conclusion raw併記 | 計器(E型・B24より深層) |

**E型対処原理の追補(軍師)**: (a)一次情報との突合は**突合対象が消える前の保全**を含む — rerunは証跡を破壊する(rerun前にrun状態JSONを保全せよ。B17台帳上書き消失と同型) (b)計器は『自分の解釈』でなく『観測した生値』を残せ (c)**取得不能事象には終端値(N/A墓標)を与えよ** — 終端値を持たない計器は取得不能事象を永久に未処理として鳴らし続ける(GATE未反映15件ALERT=revert済みcmdの永久幽霊、blt_192737実証。B24 cancelledと同型)。ALERT対処前の2択判定:『この値は今後取得可能か』→可能なら同期/不能なら終端値。
**confirmed_scopeの3つの限界(軍師の自己申告13-15件目から)**: (i)範囲宣言は「範囲外へ結論を述べない義務」とセット(読まずに肯定=読まずに否定と同罪) (ii)宣言しても**範囲の選定が仮説に汚染されていれば防げない** — 対処=不在報告に「なぜその範囲を選んだか」を併記 (iii)**分類も判断である** — 是正方法の判定を保留しながら事象の分類・命名は保留しない形(「5例目として記録する価値」等)。分類の誤りは台帳の族統計を汚染し後続の設計判断を歪める。

**統一根「個別と全体の対応不確認」(疾風07-26)**: 本日の指揮官の誤り33件(家老17+軍師16)は、confirmed_scope 3形+「個別と全体の対応を確認しなかった」(1件を見て全体を決める/全体をまとめて個別を見ない=表裏)の2形に整理できる。構造的答え=**値とその出所(測定時HEAD・根拠となった実文言)を対で書かせる** — B33のpost_verification_head必須化が実例。confirmed_scopeの測定値版。

**陰性対照(negative control・軍師提起07-25)**: 陽性対照(既知の陽性1件を検出できるか)と対で、破壊的操作の前には『**検出されてはならないもの(保護対象)が対象集合に含まれていないこと**』を積集合=0件の数値で示せ。0件でなければ実行しない。実証: cleanup弾の退避対象∩git worktree list=42件を着手前検出し破壊を未然防止。
**「記録≠状態」族(E型の主要サブファミリー・4例)**: 検知器が「記録の存在」を「問題の現存」と同一視する。(1)B20 pending=terminal BLOCK記録 (2)疑い8 hook_failure ALERT=事象数でなく記録数 (3)GATE未反映15件=revert済みcmdの幽霊 (4)B33 review_bundleのcount!=0一律APPROVE禁止=解決済みfailureを未解決と同視。是正原理は共通: **判定対象を記録から現在状態へ**(解決証跡の正規形式=原因特定+独立検証+理由申告+事後全PASS確認。既存RED残置型は「事後同値=悪化させていない証明」で代替)。
**派生原理「成功も検査対象」(才蔵B31 07-26)**: 緑という結果(写し)を見て、緑になった経路(実体)を見ない — T-AC3-1は本番repoを汚染することでokになっていた(fixture相対mktemp→壊れた.git→git discoveryが親=本番repoへ解決→他者stageをmainへ"init" commit)。DrvFs EPERM・帰属不明commit・stage巻き込みの3事象が単一根に統一された実証。FAILだけでなく異常に遅いPASS(303秒)も監査対象とせよ。

**運用パターン: CI RED×配備枠ゼロのデッドロック**(LS101同型): CI修正を配備したくてもidle 0名(done報告がRED故にarchive不能で枠が空かない)。正規解=karo RCで原因commit作者へ差し戻し(作者=文脈保持者が最短。断定せず『一次特定せよ、原因でなければその旨報告可』を必ず添える。テストを緩めて通す修正は禁止)。

**E型の統一原理(2026-07-25確立・6例の証跡付き)**: 検知器/計器の誤りは全て『**実体ではなく実体の写し(キャッシュ/index/報告側コピー/古い値/特定形式前提)を見ている**』に還元される。計器自身は正常に動いて見えるため自己検知できない。検知器を作る際の共通手順=『判定に使う値が実体か写しかを明示し、実体との突合を1回行ってから完成とする』。証跡6例: (1)WA総数計数(workaround=True不参照) (2)GA-PUSH1(index vs HEADのみの差分を実体差分と誤認) (3)報告側コピーを正本と誤認 (4)grep形式前提(後方形式8件中7件を欠落) (5)教訓検知器(created_atのみでmerge登録不可視) (6)stop hookのCIキャッシュ(1.5時間前のfailure保持でGREEN後も催促抑制)。理解では防げず、突合という行為だけが防ぐ。追加例(07-25夜): (7)家老が設計書台帳の写し読みで重複起票 (8)ignore処方=「報告しない」を「見ない」と誤認(報告34件vs探索83,344件の乖離) (9)是正効果の前後計測欠落 (10)指示者が是正前のgit statusの写しで空commit指示(半蔵が三者一致の一次確認で差し戻し=受け手の反論が防いだ) (11)ac_fingerprint候補→**偽と確定**(才蔵実測: 前タスク報告payloadの複写ミス伝播。家老の仮説の方がmtimeという写しだけを見たE型だった=仮説自体も陽性対照検査の対象) (12)cleanup設計の衝突検査がtask YAML grepのみ=登録済みworktree42件不可視(軍師が着手前検出) (13)regexを自分でpythonへ書き写して合成テストし「無実を実証」と称した(実体の実行ではなく自作の写しの実行。将軍もこれを「推論ゼロ」と誤評価=**評価者も写しに騙される**)。決着はA/B単一変数比較(親commit差し戻し×同一コマンド)が付けた=**検証のgold standard**。運用注記: review_approval.sh scope=reportはkaro ACCEPT構造拒否(L17)、scope=autoが正しい入口。

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
- **契約穴の3層構造(飛猿07-26)**: 第1層=AC文言が明示要求するファイル(機械判定可・B32が解く) / 第2層=稼働中task・未commit作業ツリーとの衝突(配備前チェックが解く) / 第3層=**実装判断の結果として触りうる範囲**(着手後にしか確定しないが可能性は起票時に予見可能)。第3層は機械化せず**上申を正規手順化**が有力(P8: 実装判断は考える工程。本日9件全てで忍者の上申運用が機能した実績)
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
