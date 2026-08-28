# 成長ループ設計 — 全ロール共通
<!-- last_updated: 2026-07-21 殿裁定「削るな、品質を向上させながら速くしろ」 -->
<!-- origin: 殿指摘2026-04-20「BLOCKされたら次のCMDでBLOCKされないように成長する=主軸。ゲートを通すのは枝葉」 -->

## §1 核心原則

**gateで止める = 止血帯(枝葉)。成長 = 最初から間違えない構造(主軸)。**
gateの成功 = システムの未熟さの証拠。gateが発火しないシステムが完成系。

### §1.1 品質×速度の超速回転（殿裁定2026-07-21）

- **「削る／守る」を判断軸にしない**: 過剰でも超速なら問題ではない。遅さが自動成長の回転数を落とすことが問題。
- **gate/hookを削除しない。守るためだけの新gateも追加しない**: 既存防御の品質を維持したまま高速化する。
- **遅いgate/hookはインフラバグ**: 判定サマリ先頭集約、全BLOCK初回一括列挙、実在正本からの動的候補生成、cache/batch化で往復・fork・出力量を減らす。
- **品質2原則を速度改善と同時に満たす**: (1) 判定は正本と突合する、(2) 発火1件・非発火1件の境界fixtureを双方固定する。チェック項目や検出能力を減らした高速化はFAIL。
- **小さな役割分担を並列で回す**: 配備・レビューのオーバーヘッドを理由に逐次化しない。直列化は同一pathへの同時書込み等、一次確認した競合区間だけに限定する。

positive_rule: 品質向上と速度向上を同じサイクルで計測し、変更前→後の所要時間と、正本突合・境界fixtureのPASS数をともに報告する。

reason: 2026-07-20の表示型enforcement削除は必須防御まで失わせ、能力急落後にwholesale rollbackを要した。真因は防御の存在ではなく、遅いため削除へ逃げたこと。削るな、品質を向上させながら速くしろ。

origin: `[[殿裁定_品質速度超速回転_20260721]] -> [[削る守る軸の誤り]] -> [[gate_hook品質維持高速化]]`

### §1.2 高速回転の役割契約（殿裁定2026-08-09）

- 忍者: 小さな独立実験を回し、二値結果・commit hash・対象path・FAIL/SKIP数を即handoff。個体での完璧な実装・全テスト・完全報告・review適合は要求しない。
- 家老: 複数忍者の一次結果を統合し、不足を補完する。途中成果の報告整形を忍者へ差し戻さない。
- 軍師: 横断レビューとwave最終checkpointを担う。各途中弾の事前APPROVE待ちは作らない。
- 将軍・殿: 方向と採否を裁定する。
- 三層記憶・三層学習ループ: 成否を全軍の次cycleへ還流し、個体の無謬性ではなく組織の複利で品質を上げる。
- 二値境界: 途中lane=一次結果到達でPASS、wave/方式採用=最終checkpoint一回の全契約PASSで完了。

origin: `[[殿裁定_忍者完璧主義廃止_20260809]] -> [[途中lane最小handoff]] -> [[上位層補完と最終checkpoint集中]]`

## §1.5 表示型/自動化の区別軸(殿裁定 2026-07-24 18:44)

殿原文: 「だからこそ一見効率が悪い表示型の強制が必須になるんだ。考えるべきことは毎回考える。機械的なことは自動化する。」(「一件」は殿本人によるタイポ訂正済み→「一見」)

- **区別軸は「表示型か構造型か」ではなく「考えるべきことか機械的なことか」**。
- **考えるべき分岐**(品質判断・設計選択・方式決定)= 一見効率が悪くても**表示型の強制**で毎回考えさせる。考える作業を自動化で奪うと大きなトラブルを起こす。
- **機械的なこと**(三層記憶の検索・突合・知識注入・検証の実行)= 自動化する。
- 速度の目的は学習ループを高速で回して品質を向上させること。因果を逆にするな(速度のために考える工程を削るのは事故の根)。
- 実例: 2026-07-24全量テスト事故 — 将軍が起票テンポを優先しgateテンプレへ盲従(考える工程を自ら省略)。是正=検索は自動(memory_db_fts5_top3の粒度是正=cmd_4164)、方式の判断は表示で毎回将軍に問う。

origin: `[[殿裁定_表示型強制必須_20260724]] -> [[knowledge:2f977ef733dddf35]] -> [[全量テスト事故是正の評価軸]]`

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

- positive_rule: gate/検知器/手順を追加するcmdは追加所要時間とFP見込み、FP計測接続先(`scripts/detector_fp_rate.sh`/`logs/detector_fp_rate.yaml`等)を明記する。reason: 局所品質装置の無検証追加は誤発報で全体スループット税を増やし、品質と速度を同時に落とす。

### §9.1 厳密さの適用点を反転する（殿裁定2026-07-14）

- **全ロール共通の最適化目的（殿裁定2026-08-14）**: 最大化するのは作業量・試行回数・gate数・報告品質のいずれか単独ではなく、**正しい結果が出る速度**である。目的に直結する最小の二値ACで可逆な試行を回し、正しいと判明した時点で追加証明・単一artifact化・報告美化を止める。安全性または正しさに寄与しない過剰BLOCK・冗長ACは品質負債として除去する。
- **誤認・偽陽性は即時根治（殿裁定2026-08-14）**: 同一入力で誤判定か正当BLOCKかを再現する。真の偽陽性なら安全境界を保った最小修正と回帰契約で閉じ、正当BLOCKなら誤診を生んだ曖昧な診断を直す。迂回手順・例外運用・根拠なき許可拡大は負の複利を生むため禁止する。
- **途中**: isolated/reversibleな試行は1行ログ+対象固有の安全底線だけで回し、契約・報告YAML・レビュー・binary check・再承認を置かない。障害は直して即再実行し、RCA作文はしない。報告は結果または自力で越えられない外部障壁の時だけ。目的はtry回数の最大化。
- **最終**: 方式採用の最終検証1回と、不可逆または本番P4実行に全契約・敵対試験・レビューを集中する。
- positive_rule: 中間処理はチェック削除で短縮せず、判定のbatch化・cache化・初回一括提示で高速化する。厳密な契約は最終checkpointへ集中するが、既存防御の検出能力は維持する。
- positive_rule: 「正しい報告」と「正しい結果」が競合したら結果を先に供給し、報告整形は最終checkpointの一度へ送る。
- reason: v1.4.28の4文probeへAC 7件・binary 17件・4回の受け渡しを課し、実装より手続きが律速した。途中厳密化はtry回数を減らし、学習ループそのものを遅くする。
- origin: `[[殿裁定20260714_0811]] -> [[途中厳密化]] -> [[try回数減少]] -> [[最終checkpoint集中]]`
- origin: `[[殿裁定_正しい結果速度最適化_20260814]] -> [[過剰ACと過剰BLOCK]] -> [[高速回転_正しい結果到達速度]]`
- origin: `[[殿裁定_偽陽性即時根治_20260814]] -> [[誤認と曖昧診断]] -> [[迂回の負の複利を遮断]]`

## §10 スキル自動成長ループ(4段階 + L6強制)

スキル実行の品質を計測→還流し、SKILL.md自体を育てる仕組み。

| 段階 | 動作 | 記録先 |
|------|------|--------|
| (1) 実行 | スキル実行後、結果をログ記録 | skill_execution_log |
| (2) つまずき | FAIL発生 → stumbling_points欄に記録 | skill_execution_log |
| (3) 改善案集計 | skill_auto_improve.sh がFAILパターンを集計 | 改善候補リスト |
| (4) 品質向上 | `--apply` でSKILL.mdの注意ポイント自動書込み + ninja_monitor週1自走 | SKILL.md |

**L6: スキル使用強制=成長ループの入口を保証する(殿裁定2026-05-10)**:
適したスキルを無視するのはバグ。スキルが使われなければ(1)-(4)のループが回らない=学習速度ゼロ。
- **原則**: TRIGGER条件に合致する場面ではSkill toolを呼ぶ。手動操作は禁止
- **強制**: 手動操作をhook/gateでBLOCK→スキル以外の道を塞ぐ(Level 4)
- **複利構造**: 使用強制→利用頻度向上→問題発見頻度向上→改善頻度向上→品質向上→さらに使いやすく→さらに使われる→...加速度的に回る
- **全エージェント共通**: 将軍(/cdp-browse等)・家老(/cmd-complete等)・軍師(/review-bundle等)・忍者(/report-write等)の全員が対象
- **実装**: pre-bash-combined.sh Guard 9 (commit d38ab3f4)。手動操作検出→BLOCK+対応スキル名表示
- **生成側と検査側の契約同期**: 配備必須欄は検査側BLOCKだけでなく起票雛形から生成する。`cmd_skeleton.sh`は`estimated_minutes`と10分超/15分超の構造化例外条件を出力し、配備時workaroundを入口で根絶する。実装・隔離fixture証跡 → `docs/research/cmd_3891_skeleton_deploy_contract.md`

**帰属精度(cmd_2604)**: GATE_SKILL_MAP固定マッピングでgateとスキルを1対1対応。
スキル別GATE結果の帰属を正確に計測し、改善対象スキルを特定する。

**PASS記録統一(cmd_2605)**: gate_report_format.sh PASS分岐からも統一記録。
FAIL時だけでなくPASS時も記録することで、スキル全体のパフォーマンス分布を把握する。

## §11 防御階層原則 — 6段階(殿定義2026-05-09, L6追加2026-05-10)

**ゲートの成功=未熟さの証拠。発火しないシステムが完成系。**

| Level | 名称 | 仕組み | 例 |
|-------|------|--------|-----|
| 1 | 事後検出 | 間違えた後にgateが検出 | gate_report_format.sh: 報告提出後にフォーマット不備検出 |
| 2 | 事前予防(doc) | ドキュメントに「こうせよ」と記載 | gunshi.md: 「git show HEADで確認せよ」 |
| 3 | 事前強制(auto-gen) | テンプレートを自動生成して正しい構造を強制 | deploy_task.sh: 報告テンプレート自動生成 |
| 4 | フロー内BLOCK | 間違ったら即停止。先に進めない | cmd_save.sh: q11にgrepなし→BLOCK |
| 5 | 事前コンテキスト提供 | 正しい入力を自動生成して渡す。間違える余地がない | cmd_2617: preflightがgrep結果を自動表示→コピーするだけ |
| 6 | 学習速度最大化 | 間違いから学ぶ速度を最大化。下限が切り上がる | ninja_weak_points: 過去の弱点を次回配備時に自動注入 |

**Level 1-5と6の本質的違い**(殿定義2026-05-10):
- Level 1-5: 「何を防ぐか」の階層。防御の質を上げる
- Level 6: 「どれだけ速く学ぶか」の階層。防御の成長速度を上げる
- **上限は無く、下限が切り上がる仕組み**(殿言)。新しい問題は常に現れる(上限なし)。一度学んだ問題は二度と通さない(下限切り上げ)

**時間減衰の法則(殿指摘2026-06-14)**:
- Level 1-2(事後検出/doc)は**時間が経つと効果がなくなる**。繰り返し接触で慣れが生じ注意力が減衰する
- Level 3(auto-gen)は構造強制だが出力を読み飛ばせる→やはり減衰する
- **Level 4+(BLOCK/フロー内埋込)のみ時間減衰しない**。通らないから慣れようがない
- 新ルール追加時: Level 2(doc)で止めるな。Level 4+(BLOCK)まで実装して初めて恒久防御

### §11.0a result.summary入口防御（cmd_3876）

`result.summary`はテンプレート生成時に`FILL_THIS`を置き、実施内容+検証結果の実値へ置換するまで`report_field_set.sh`が空値/token残存を事前BLOCKする。推定による自動補完は禁止。実装・三態証跡 → `docs/research/cmd_3876_report_summary_funnel.md`

### §11.1 Human Checkpoint一覧 — Cognitive Surrender防御 (Loop Engineering §XI-C)

ループが信頼できるほど判断を放棄したくなる(Cognitive surrender)。防御は態度ではなく構造。ループに最低1つの停止点を作れ — 人間が常に介入するためではなく、介入できる位置に居続けるために(§IX "Keep One Door Open")。

| Checkpoint | タイミング | 仕組み | 殿の介入方法 |
|------------|----------|--------|------------|
| cmd裁可 | cmd起票時 | 将軍が推薦先行で宣言。殿がYES/NOで裁可 | dashboard 🚨要対応 or 将軍との対話 |
| push前検証 | push時 | pre-pushフック(テスト自動実行) + 殿確認 | CI結果確認 |
| 本番DB変更 | DB操作前 | バックアップファースト(LS040) + 殿確認 | ntfy通知 |
| gate変更 | gate/hook修正時 | 軍師レビュー(SG) + 殿裁可 | 掲示板投稿 |
| 月次レビュー | 月初 | 月報生成 + 殿との振り返り | 月報記事 |

origin: [[loop_engineering]] §IX "Stay the Engineer" + §XI-C "Keep One Door Open"

**L6が自動代行(autofix)と異なる理由**:
行動をシステムが代行する(autofix)→エージェントが間違えない→**間違えないから学ばない**→品質向上の機会喪失=自動消火。
L6は間違いを許す。間違いから最大の学びを引き出し、学習サイクルを加速する。
実証: verdict-check(L4 BLOCK)が矛盾11件→0件根絶。autofix(L3)は同じ間違いの繰り返しを防げなかった(autofix率1.09/cmd)。BLOCKされて自分で直すから学ぶ。

**L6のメカニズム — 5W1H(殿指摘2026-05-10)**:
ループが回転するには5W1Hが最低限必要。1つでも欠けるとループが空転する=学習速度がゼロ。

| 要素 | 問い | 欠落時の実害 |
|------|------|------------|
| WHY | なぜやるか | 目的不明のcmd→結果を評価できない→学びゼロ |
| WHAT | 何を達成するか | AC不明→完了判定不能→ループ未完結 |
| WHEN | いつ発動するか | トリガー不明→仕組みが使われない→防御が死蔵 |
| WHERE | どこで変更するか | 対象不明→パスミス/波及見落とし→BLOCK再発(cmd_2654実証) |
| WHO | 誰が影響を受けるか | 通知漏れ→全員共有されない→横展開が死ぬ |
| HOW | どうやって実現するか | 手段不明→実装が曖昧→品質低下 |

5W1HはL6の**最小構造**。gate検証(cmd_save.sh q8)で自動チェック。

**L6化済み仕組み完全リスト(2026-05-11時点・10件)**:

| 対象 | 名称 | 実装箇所 | 機能 |
|------|------|----------|------|
| 忍者 | `ninja_weak_points` | `scripts/deploy_task.sh` L3904-L4074 | `karo_workarounds.yaml`から忍者別workaround傾向を集計し、次回task YAMLへ弱点・警告を自動注入する |
| 忍者 | `gate_fail_top3` | `scripts/deploy_task.sh` L4075-L4140 | `logs/gate_fire_log.yaml`から忍者別FAIL理由TOP3を抽出し、報告作成前に頻出ミスと修正観点を渡す |
| 忍者 | `gate_blocks` BLOCK pattern | `scripts/deploy_task.sh` L4141-L4200 | `logs/gate_metrics.log`から忍者別BLOCK分類とhintを注入し、過去の詰まり方を次taskの入力へ変える |
| 忍者 | `previous_failures` | `scripts/deploy_task.sh` L4321-L4420, L5631-L5655 | 再配備前の`session_state`を保存し、再配備時に前回BLOCK理由・試行済みアプローチをtask YAMLへ引き継ぐ |
| 将軍 | Session State WARN/BLOCK履歴表示 | `scripts/cmd_save.sh` L877-L908, L1463-L1480 | 同一cmd/同一WARNの過去発火回数と検出ロジック行を保存時に表示し、消火ではなく根本修正のROIを見せる |
| 将軍 | `preflight_autolearn` | `scripts/cmd_save.sh` L929-L940, L4299-L4306; `pre-bash-combined.sh` | 繰り返しWARNをpreflight学習リストへ昇格し、次回以降の入力段階で動的チェックとして強制する |
| 将軍 | `q8_why_what` 5W1H検査 | `scripts/cmd_save.sh` L1692-L1720 | WHY/WHATだけでなくWHEN/WHERE/WHO/HOWをcmd保存時に検査し、ループが回らないcmd設計を早期可視化する |
| 将軍 | 遡及学習 | `scripts/gates/gate_shogun_startup.sh` L812-L910 | 起動時にWARN/BLOCK頻度TOP5、再発率、有効率を自動表示し、次に根本修正すべき防御を可視化する |
| 全体 | `lesson_impact.tsv` | `scripts/cmd_complete_gate.sh` L2410-L2580, L5027-L5033, L5636-L5641; `scripts/deploy_task.sh` L2764-L3673 | 教訓注入・参照・有効性を計測し、低有効教訓の減衰と次回注入品質の改善に使う |
| 全体 | 修行サイクル | `context/training-cycle.md` §2-§3, §13, §21, §27 | idle時間に訓練taskを配備し、gate BLOCK→自力修正→一発PASS率計測で本番前に失敗パターンを学習させる |

**洗脳防御(2026-05-24追加)** — 防御階層の「何から守るか」の拡張:
Level 1-6は「エージェントのミス」から守る。洗脳防御は「Anthropicのコスト最適化で植え付けられた間違った効率の本能」から守る。
殿の教え: LLMの判断はAnthropicのマーケティング+コストカットに最適化されている。早期終了/先送り/浅い判断は本能。
→ 設計書: 消失(2026-05-24作成・軍師APPROVE済みだがcommit漏れで実体喪失。2026-06-11 cmd_3281後の真陽性リンク監査で確認)。設計内容は下記実装とCLAUDE.md「洗脳8パターン」+memory/feedback_creator_brainwashing.mdに反映済み
→ 実装: cmd_3033(将軍Level0-7) + cmd_3034(軍師Level4) + cmd_3035(家老Level4) + cmd_3036(将軍Level4完成)
→ 概念: `creator_brainwashing_defense` (セマンティクスインデックス登録済み)

**因果確認L0-L7(2026-06-02追加)** — 防御階層の「過去の設計意図を壊さない」拡張:
現在の実装には過去の事故・殿裁定・CLI差異・運用制約を受けた因果がある。変更前にgit log/blame、教訓、設計書、semantic/causal linksを確認し、「導入理由」「守るべき設計意図」「今回壊れている因果」を残す。
multi-CLI前提: Claude/Codexのhook差に依存させず、正本はCLI非依存の `cmd_save.sh`、`deploy_task.sh`、`gate_report_format.sh`、report/task YAML、semantic index、memory DB、daemon/gateへ置く。hookは使えるCLIでの早期検出に留める。
→ 設計書: `docs/research/causal-verification-l0-l7-design_20260602.md`
→ 実装: `deploy_task.sh` がtask/reportへ `causal_verification` を注入し、`gate_report_format_main.py` が空欄WARN、`cmd_save.sh` がL5表示+WARNを行う(Codex/Claude共通、cmd_karo_impl_causal_verification_l0_l7_20260602)
→ 概念: `causal_verification_l0_l7`
→ 因果: [[semantic_search_timeout_infra_bug]] -> [[past_design_intent_unchecked_risk]] -> [[causal_verification_l0_l7_required]]

**設計思想カタログ=中間レイヤー(2026-06-30 cmd_3615で実現)** — 教訓→check関数の直結から3段構造へ:

教訓はcheck関数の「なぜ作ったか」を記録するが、82件のcheck関数を教訓IDから逆引きする手段がなかった。設計思想カタログ(`docs/research/cmd_save_gate_catalog.md`)が中間レイヤーとして機能し、**教訓→設計思想カタログ→個別check関数**の3段構造(TO-BE)が実現された。

| 層 | 役割 | 場所 |
|----|------|------|
| 教訓 | 失敗から何を学んだか | `projects/infra/lessons_*.yaml` |
| **設計思想カタログ(中間)** | check関数ごとのorigin・防御対象・severity・教訓逆引き | `docs/research/cmd_save_gate_catalog.md` |
| 個別check関数 | 実際のBLOCK/WARN判定 | `scripts/cmd_save.sh` |

全エージェントへの貫通経路:
- 将軍(起票時): `cmd_skeleton.sh` のGUIDEに逆引き先を明記
- 全員(概念検索): `bash scripts/semantic_search.sh "設計思想カタログ"` → `cmd_save_gate_catalog` 概念到達
- 家老(インフラ理解): `context/infrastructure.md` のcmd_save.shセクションに構造を記載
→ セマンティクス概念: `cmd_save_gate_catalog` | 因果: [[教訓蓄積]] -> [[check関数逆引き不在]] -> [[中間レイヤー設計思想カタログ]]

**L6未化仕組み(2026-05-11時点・0件 ★全L5到達)**:

cmd_2673-2676で4件全てL5化完了(2026-05-11):
- `gate_context_freshness.sh` Level 1→5 (stale TOP3+cmdテンプレート自動提案)
- `gate_enforcement_audit.sh` Level 1→5 (hooks登録cmd自動提案)
- `gate_knowledge_freshness.sh` Level 1→5 (STALE TOP3+verified_at更新cmd例)
- `gate_wa_data_quality.sh` Level 1→5 (False WAパターンTOP3+--fix cmd例)

次のL6化対象: L5到達済み仕組みの中から「BLOCKされた時の学び」を最大化する仕組みを追加する段階。

**全ロール共通の設計指針**:
- 新規gate/hook設計時: 最初からLevel 5を目指せ。Level 4で止めるな
- 既存gate/hookの改善時: 繰り返し発火しているチェック → Level 5化の候補
- **Level 5到達後**: 「BLOCKされた時の学び」を最大化するL6を考えよ。FIX hint/弱点注入/失敗履歴の横展開
- GP提案時: `defense_level`フィールドにLevelを明記。Level 4以下なら「Level 5化できないか？」を自問
- **BLOCKされたら**: 修正してCLEARするだけでなく「同じBLOCKが二度と起きない仕組み」を環境に埋め込め
- **教訓注入は適合条件を狭く機械化する**: useful率0%の5教訓はタグ/条件を絞り、通常infra taskへの空振りを5→0件、即時シミュレーションでuseful率24.4%→27.8%（+3.4pt）に改善した（cmd_3890）。→ `docs/research/cmd_3855_lesson_injection_precision.md`
- **WA再分類はcmd単位で一括しない**: 同一cmd内にも異根があるため、detail/root_causeを読み、category×root_signatureを本文条件付きhelperで原子的に更新する（cmd_3897）。→ `docs/research/cmd_3897_wa_uncategorized_reclassify.md`

**計測指標**: Level 4:Level 5の比率。2026-05-10時点 = Level5:7件(44%)。Level 5比率の向上が成長の指標。L6は「BLOCK→自力修正→PASS遷移率」で計測。

**実績(2026-05-09〜10)**:
- cmd_2616: q11 WARN→BLOCK昇格(Level 4)
- cmd_2617: q11 preflight自動grep(Level 5)。同じ問題にLevel 4→5の進化を1セッションで実現
- cmd_2618: 未自動化教訓18件のLevel 5化計画策定(偵察)
- cmd_2619: research_tool_explicit FP修正+ACパス自動提案(Level 5化)
- cmd_2620: セマンティクスインデックスaliases受動表示(Level 5化)
- D0: gate_vercel_phase broken ref候補自動提案(Level 5化)

**詳細監査データ**: `docs/research/gunshi_defense_hierarchy_audit_20260510.md`(全16仕組み+全4PJ横断+cmd_save WARN TOP5+なぜなぜ7回)

---

## 因果リンク

- テスト時間免疫系は新runnerを作らず、既存`run_tests.sh`のtiming/cacheと`test_select.sh`の影響選択を台帳writerへ統合する。静的棚卸し材料 → `docs/research/cmd_3894_test_asset_inventory.md`
- 計測機構自身の停止を見逃さないため、通常all/unit完走だけが時間台帳の鮮度を更新し、cache/部分runは更新せず、staleをstartup gateでWARNする。→ `docs/research/cmd_3895_timing_ledger_revival.md`

- ← [[deepdive_why_chain_20260321]] Phase 4-5: 自動化×強制=知性の外部化→成長ループの理論的基盤
- ← [[deepdive_causal_tracing_20260415]] 因果をたどる=成長ループのSystem 2側
- → [[training-cycle]] 修行サイクル=成長ループの忍者向け実装
- → [[infrastructure]] gate/hook/lessons=成長ループの環境埋込み先
- → [[throughput-first-asis-tobe-5w1h_20260708]] 全体スループット第一原則(殿2026-07-08)。2026-07-21裁定により「削る装置」ではなく、品質2原則を維持した高速化サイクルとして読む。
- → [[gunshi_idle_nazenaze7_bottleneck_20260413]] なぜなぜ7回転がボトルネックになる構造分析
- → [[gunshi_idle_nazenaze_ci_red_lesson_gap_20260605]] CI red→lesson gap: なぜなぜが成長ループに接続されていない根因
- → [[gunshi_idle_recommended_skills_role_filter_20260602]] 推奨スキルのロールフィルタ設計: 不要通知削減の実践
- → [[gunshi_idle_s05_test_premise_check_20260521]] テスト前提チェックのなぜなぜ: S05実行可能前提の確認
- → [[gunshi_idle_gate_prediction_accuracy_20260612]] gate予測精度分析: APPROVE→CLEAR/FAIL予測の精度計測
- → [[gunshi_idle_gate_prediction_false_positive_analysis_20260706]] gate予測偽陽性分析: 直近MISS 4件がBLOCK→CLEAR方向であることを計測
- → [[gunshi_idle_self_gate_check_str_bug_20260516]] self_gate_checkの文字列バグ: gate品質の問題
- → [[gunshi_idle_silent_failure_audit_20260605]] サイレント失敗監査: 成長ループの穴の可視化
- → [[gunshi_idle_skill_enforcement_5layer_20260515]] スキル強制5層設計: Level5到達の実装実例
- → [[gunshi_idle_skill_growth_audit_20260506]] スキル成長監査: 成長ループのスキル次元の計測
- → [[gunshi_idle_adversarial_retroactive_application_20260614]] 敵対的遡及適用分析: 教訓の遡及適用パターン
- → [[gunshi_idle_useful_rate_measurement_fix_20260615]] useful_rate計測バグ修正: 教訓健全度ALERTの根因
- → [[gunshi_idle_skill_growth_loop_nazenaze_20260502]] スキル成長ループのなぜなぜ: idle→skill精度の連鎖
- → [[gunshi_idle_skill_growth_nazenaze_20260512]] スキル成長のなぜなぜ継続分析
- → [[gunshi_idle_skill_precision_cycle2_20260609]] スキル精度サイクル2: 成長ループの計測と改善
- → [[gunshi_idle_structural_analysis_20260510]] 構造的問題分析: なぜBLOCKが繰り返されるかの根因
- → [[gunshi_idle_test_contamination_20260413]] テスト汚染: 成長ループのフィードバック精度低下の根因
- → [[gunshi_idle_useful_rate_alert_nazenaze_20260519]] useful_rate ALERT後のなぜなぜ7回転
- → [[gunshi_idle_useful_rate_baseline_20260512]] useful_rate基準値設定と成長ループ計測設計
- → [[gunshi_idle_useful_rate_drop_20260425]] useful_rate低下の原因分析
- → [[gunshi_idle_useful_rate_gp218_20260422]] GP218: useful_rate向上提案
- → [[gunshi_idle_useful_rate_gp219_20260422]] GP219: useful_rate向上提案
- → [[gunshi_idle_verdict_override_analysis_20260411]] verdict override問題の分析: 手動判断依存の根因
- → [[gunshi_idle_verdict_override_elimination_20260414]] verdict override廃止設計: gate自動化への移行
- → [[gunshi_idle_verdict_override_root_cause_20260412]] verdict override根因: 判断の外部化なしに品質は安定しない
- → [[gunshi_idle_warn_legacy_count_20260514]] WARN数計測によるレガシー問題の可視化
- → [[gunshi_l6_bottleneck_analysis_20260510]] L6化のボトルネック分析: BLOCK→自力修正遷移率の改善
- → [[gunshi_nazenaze_universal_claim_20260413]] 普遍的主張の危険性: なぜなぜを特定事例に限定すべき理由
- → [[gunshi_sg_s0_self_code_change_20260412]] SG S0自己コード変更: gate自己改善の盲点分析
- → [[cmd_497_cmd-splitting-policy]] cmdスプリットポリシー(cmd_497)
- → [[cmd_2589_codd_adr]] CoDD ADR設計書(cmd_2589)
- → [[cmd_2589_skill_gate_feedback_refactor_spec]] スキルgate feedback refactor仕様(cmd_2589)
- → [[cmd_2590_skill_auto_improve_after_20260506]] スキル自動改善after状態(cmd_2590)
- → [[cmd_2590_skill_auto_improve_refactor_spec]] スキル自動改善refactor仕様(cmd_2590)
- → [[cmd_3227_skill_auto_growth_loop_design]] スキル自動成長ループ設計(cmd_3227)
- → [[karpathy-principles]] Karpathy原則知識ベース(systems-knowledge-base)
- → [[lessons_shogun]] 将軍教訓=成長ループの第一層(個)の蓄積先
- → [[three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707]] 三層学習ループ自動成長極限化設計書(殿指示2026-07-07): AsIs 7穴計測+ToBe T1-T7(弱LLM/他CLI/他PJ可搬) → `docs/research/three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707.md`

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi_idle_growth_loop_nazenaze_20260515]] — 軍師idle: 成長ループなぜなぜ分析(2026-05-15)
- [[gunshi_idle_immune_system_evidence_20260426]] — 軍師idle: 免疫システム証拠収集(2026-04-26)
- [[gunshi_idle_immunity_measurement_20260510]] — 軍師idle: 免疫計測フレームワーク(2026-05-10)
- [[gunshi_idle_immune_effectiveness_20260512]] — 軍師idle: 免疫システム有効性測定(2026-05-12)
- [[gunshi_idle_gate_fail_trend_20260430]] — 軍師idle: ゲート失敗トレンド分析(2026-04-30)
- [[gunshi_idle_gate_fail_rate_anatomy_20260502]] — 軍師idle: ゲート失敗率解剖(2026-05-02)
- [[gunshi_idle_gate_fire_traceback_20260510]] — 軍師idle: ゲート発火トレースバック(2026-05-10)
- [[gunshi_idle_gate_fp_analysis_20260527]] — 軍師idle: ゲート偽陽性(FP)分析(2026-05-27)
- [[gunshi_idle_gate_prediction_false_positive_analysis_20260706]] — 軍師idle: gate_prediction偽陽性分析(2026-07-06)
- [[gunshi_idle_lg003_gate_wa_analysis_20260519]] — 軍師idle: LG003ゲートWA分析(2026-05-19)
- [[gunshi_idle_lu_dict_pattern_20260415]] — 軍師idle: LU辞書パターン分析(2026-04-15)
- [[gunshi_idle_commit_check_wa_pattern_20260410]] — 軍師idle: コミットチェックWAパターン(2026-04-10)
- [[gunshi_idle_cross_contamination_20260503]] — 軍師idle: クロスプロジェクト汚染分析(2026-05-03)
- [[gunshi_idle_cross_project_fp_20260426]] — 軍師idle: クロスプロジェクトFP分析(2026-04-26)
- [[gunshi_idle_deepdive_design_impl_phantom_20260516]] — 軍師idle: deepdive設計実装ファントム問題(2026-05-16)
- [[gunshi_idle_brainwash_audit_memory_loop_20260602]] — 軍師idle: 洗脳監査メモリループ分析(2026-06-02)
- [[gunshi_idle_lg048_automate_sg_pre31_20260706]] — 軍師idle: LG048 SG-PRE31自動化+extract_command_files read_markers「から」欠落分析(2026-07-06)。cmd_3713/3714連続BLOCKの根因特定→D0部分修正(commit 39448c969)。残存問題=write_marker近接誤判定

- → [[四つのらせん_20260828]] らせんの横展開(速度/デッドコード/リファクタ/知識)=2026-08-28 殿下問。計測器→1 unit→一段深く→計測器は残す
- → [[session_save_20260828_1420]] -> [[復帰後の型_第七弾]] 復帰点 第5便(2026-08-28 14:20)。四つのらせん・finalize 区間実測・auto clear 根治
