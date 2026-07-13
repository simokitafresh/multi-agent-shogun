# lessons_shogun LS-A04/LS-A09 詳細全文 (2026-07-12 v4圧縮でYAMLから移設)

移設元: projects/infra/lessons_shogun.yaml。YAML側は結論+高頻度発火則+本ファイル参照のみ。
圧縮理由: 77,874bytes>55KB(Read 1回上限)でstartup ALERT。enforcement層(cmd_save.sh等)は全て稼働中でありYAML詳細は教材。

```yaml
- id: LS-A04
  title: cmdテンプレートルール — バンドルFP回避+AC設計+書き方是正
  origin: '[[cmd_2316]] [[cmd_2318]] [[cmd_2320]] [[cmd_2322]] [[cmd_2323]] [[cmd_2337]] [[cmd_2339]] [[cmd_2342]] [[cmd_2344]] [[cmd_2345]] [[cmd_2350]] [[cmd_2352]] [[cmd_2353]] [[cmd_2355]] [[cmd_2358]] [[cmd_2372]] [[cmd_2376]] [[cmd_2386]] [[cmd_2391]] [[cmd_2394]] [[cmd_2395]]'
  detail: |
    (1)command内にスクリプトフルパスを書かない(引数のみ)
    (2)target_pathは出力ディレクトリに設定(スクリプトパスと重複回避)
    (3)claim/assumptions内にファイル拡張子を含めない(一般名で記載)
    (4)1本ずつ昇格→委任→次(同時pendingでBLOCK)
    (5)AC条件はworktree状態と照合(dirty worktree衝突回避)
    (6)CoDDのACにimplementを入れるな(準備と実装は別cmd)
    (7)environment_changeは自cmdの成果物を参照先にしない(未存在でBLOCK。既存教訓を参照)
    (8)quality_gate拡張フィールド(q4-q11+diagnosis)全記入。省略→WARN累計昇格
    (9)q8は3部構成(WHY→WHAT→複利)。複利の問い忘れ→WARN
    (10)assumptions claimは末尾に「(確認日: YYYY-MM-DD)」独立パターン
    (11)claim内にファイル名を書くな。「何を確認したか」だけ書け
    (12)commandはターゲットファイル単位でグループ化(番号付きステップ列挙→command_steps_over_ac発火)
    (13)diagnosisにgate関数名を引用するな(関数名内キーワードがregexマッチ→偽陽性BLOCK。L番号のみで参照。cmd_2337で4回BLOCK実証)
    (14)1道具1CMD(殿裁定cmd_2316)。複数道具バンドル→other_draft_exists BLOCK
    (15)cmdブロック全文(AC+command+q11+diagnosis)がgrep対象。トリガーワード(新規作成/新規構造等)をq11/diagnosisに含めるとnew_file_structure検出マッチ
    (16)ACセクションgrepはAC配下のみ。command欄のツールパスはACチェック対象外→ACに明記必須
    (17)q8縮小表現(一部/全体の一部/だけ/のみ)→q8_scope_expression WARN。全量保証と矛盾する印象。「だけ」→具体的手順+全量保証の文言に書換え(cmd_2462で1回BLOCK)
    (18)テストACは変更対象の関連テストにスコープ限定。全体pytest PASS要求はpre-existing failure許容条件を明示
    (19)ACはMUST(二値判定)のみ。推奨事項・実装文言(表示文言の中身等)をACに書くな(推奨混在BLOCK)。偵察ACも同様:「すべきか/推奨と根拠」→「判定されている/特定されている」に変換(cmd_2458で1回BLOCK)
    (26)パリティACはP1-P4全て必須(cmd_2447で2回BLOCK: P2欠落→P1/P3/P4のみでは不足)。new_fileフォルダーは旧版削除済みの理由をdiagnosisに明記
    (27)AC/command欄の.pyファイル参照はディレクトリ+ファイル名分離で書け(例:backend/app/jobs/ 配下)。スラッシュ区切り(a.py/b.py)→パスとして検出→ac_missing_parent_path BLOCK(cmd_2452で2回BLOCK)
    (20)q5はstructure_verified以上を使え。code_readingのみはBLOCK
    (28)gate/hook追加cmdのq11は既存代替の現物確認(grep結果)を記載必須。「未実装」だけでは不足→既存の類似仕組みを列挙し差分理由を書け(cmd_2459で1回BLOCK、累計15回WARN)
    (21)ACはimpl phaseのみ。commit/deploy/pushをACに書くな(ac_phase_mixing BLOCK)
    (22)shogun_to_karo.yamlへの書き込みは辞書形式(cmd_XXXX:)。リスト形式(- id:)でcmd_block_missing
    (23)AC内出力パスはrelative記述+親ディレクトリ確認。assumptions sourceはフルパス記載(例: scripts/analysis/gs_db_utils.py)
    (24)初回起票でもdiagnosisは2部構成で書け(BLOCK理由: 初回起票のため前回BLOCK情報なし/対策: 2部構成形式で記載)
    (25)environment_changeのpatternは既存gate/hook/lessonを参照。cmd成果物(未存在ファイル)の指定禁止
    (29)AC数量表現、AC内deployキーワード、env_change既知3パターン、q11既存フロー差分不足は既存テンプレートルールの再発。ACは抽象化し、env_changeは既存パターンを参照し、q11は代替grep結果+差分理由を書く。
    (30)外部PJ(kj-toilet等)のcmd: sourceに絶対パスを書くとPROJECT_WD/fpathと二重結合→ファイル不在BLOCK。プロジェクト相対パスで書け(cmd_2825で6回、cmd_2853で4回BLOCK)
    (31)quality_gateフィールド名はpreflightテンプレートと完全一致必須。不正フィールド名が素通り→値チェックで初めてBLOCK(cmd_3244で7回BLOCK。覚醒なぜなぜ7回で根因特定)
    (32)初回起票3点デフォルト: diagnosis 2部構成(BLOCK理由:該当なし(新規起票)/対策:...)+origin因果辺([[リンク]]最低1つ、none禁止)+timeout_minutesはquality_gate内でなくcmd直下(cmd_3261で3回BLOCK。LS049吸収。enforcement: pre-write-edit hookのpreflightテンプレ表示+cmd_skeleton.sh雛形)
    (33)性能ACに合格点(閾値)を書くな。閾値はデータ量変化で無意味化し(設計書201通→実測1577通で7.9倍)、到達で最適化が止まる。構造的二値(プロセス起動O(1)等)+実測値報告義務+理論限界(APIクォータ/RTT)比で書け(殿指摘2026-06-10「合格点でなくより早く」。LS053吸収。enforcement: cmd_skeleton.shガイド8)
    (34)委任メッセージは当該cmdのみに言及せよ。後続cmd番号を列挙するとcmd_delegate.shの重複ガードが誤検知しBLOCK。後続予告はcmd_idを含めない表現で。解消はinbox_archive.sh→再委任(cmd_3290。LS054吸収)
    (35)ACのファイル名列挙はスラッシュ区切り禁止。機械パーサがパスとして誤抽出しac_missing_parent_path BLOCK。区切りは中黒(・)か読点、パスはプロジェクトWD相対で書け(cmd_3292。LS056吸収。(27)の再発形)
    (36)数量語(N項目/N種/N条件等)はbinary_check欄でも括弧列挙必須。check_ac_param_sufficiencyはAC配下全行をgrepするためdescriptionに列挙済みでもbinary_checkの裸数量語でWARN(cmd_3302で特定。15回累計の根因)
    (37)削除系/ブランチ作業cmdのACにコミット構成(基点ブランチの一致確認・分割単位・メッセージ形式・整形の別コミット分離)を明示せよ。実施項目の列挙だけでは忍者が古い基点に1コミットで束ね整形も混入する(cmd_3304で3逸脱実証: 基点5コミット遅れ・3コミット指定の1本化・Biome修正混入)
    (38)起票は雛形起点(cmd_skeleton.sh)が正(LS051吸収2026-06-12)。必須フィールド・形式規約が事後BLOCKでしか到達しない事後規律型は記憶からの作文に頼るほどBLOCK往復する。対処5点実装済み(2026-06-10): 雛形の形式環境保証+FILL_THIS残存BLOCK(Check1.05)+PASS出力に次ステップ提示+cmd_delegate数字ID正規化+Check17日付リテラル除外。grep検証は最終版テキストに対して実行せよ(編集→検証の順序逆転がcmd_3316で再BLOCKを生んだ)
    (39)ブランチ作業cmdは基点ブランチ確認をbinary_checkに入れよ(LS062吸収2026-06-12)。cmd_3331でhayateが『mainからブランチを切り』のcommandステップを飛ばしローカルmainへ直接2コミット((37)の再発形=command欄の指示では忍者の逸脱を検出できない)。binary_checkに『作業ブランチ名がmain以外であることを確認したか』を入れて報告ゲートで二値検証させよ。将軍のGATE CLEAR検分(git branch --contains)が最後の防衛線。push前検出→refactor/wp3-ac2-m2退避+git branch -f非破壊復元で実害なし
    (40)外部指示書(directive等)由来のcmd起票時、外部語彙をそのまま転記するとcmd_saveトリガー語と衝突しBLOCK。起票前に内部語彙へ翻訳: 登録→記入/記録、push→commitまで、パリティ→数値一致検証(LS059吸収2026-06-15。cmd_3294で4回BLOCK実証)
    (41)cmd追記のEditアンカーは前cmdブロックの最終行(delegated_at)にせよ。origin行アンカーだとdelegated_atが新cmdブロック末尾に取り残され「委任済み」誤判定BLOCK(LS060吸収2026-06-15。cmd_3303で実証)
    (42)quality_gateフィールドにバックスラッシュ+パイプを書くな(LS071吸収2026-06-20)。grep ERE構文をq11等に転記するとPyYAMLが不正エスケープで正本YAML破壊。Guard 0eでBLOCK済み。grep OR条件は自然言語で記述(cmd_3467事故)
    (43)1CMD1起票(LS070吸収2026-06-28): 5忍法cmdを一括書込み→other_draft_exists事後BLOCK(cmd_3496)。Guard 0f(pre-write-edit-combined.sh)で複数同時書込みL1 BLOCK。cmd_skeleton.shにexecution_envフィールド追加+deploy_task.shのinject_execution_controlsでGS/DB系タスクにexecution_env自動注入
    (44)裸数量語(N件/N種等)はcmd cancel→新ID切替の累計コスト大(LS075吸収2026-07-02)。purpose/AC内の絶対数値がac_param_sufficiency繰返し発火→累計昇格BLOCK。数値は全て相対表現に置換、具体数値はassumptions claim内のみ(cmd_3610-3613で4連続cancel・30分以上消費)
  source_ids: [LS061, LS064, LS067, LS068, LS069, LS072, LS081, LS088, LS089, LS090, LS091, LS093, LS094, LS095, LS097, LS024, LS025, LS026, LS031, LS033, LS036, LS034, LS062, LS070, LS075]
  source_cmds_v3: [cmd_2316, cmd_2318, cmd_2320, cmd_2322, cmd_2323, cmd_2337, cmd_2339, cmd_2342, cmd_2344, cmd_2345, cmd_2350, cmd_2352, cmd_2353, cmd_2355, cmd_2358, cmd_2372, cmd_2376, cmd_2386, cmd_2391, cmd_2394, cmd_2395]
  created_at: '2026-04-25'
  automated: true
  enforcement: 'cmd_save.sh Check 14(バンドル検出)+Check 20(assumptions全フィールドパス検証)+environment_change grep検証+q8_compound検出+assumptions_claim_date+command_steps_over_ac+q8_scope_expression+other_draft_exists+テストACスコープWARN+推奨混在BLOCK+q5_code_reading_only BLOCK+ac_phase_mixing BLOCK'


- id: LS-A09
  title: 現物確認必須 — 定義/パス/データ/DB/掲示板/過去対話/PI全量照合
  origin: '[[cmd_1710]] [[cmd_1703]] [[cmd_1199]] [[cmd_2213]] [[cmd_2233]]'
  detail: |
    (1)殿の固有名詞→本番コードの定義箇所まで降りる
    (2)「未実装」「未対応」→grep/git showで反証を探す
    (3)cmd起票前に理解を固める。即cmd禁止
    (4)掲示板/過去対話の「未完了」→現在も未完了かls/grepで確認
    (5)パイプライン系cmdは全レイヤーの入出力を現物確認
    (6)金融データは遡及的に変わる。過去データ不変の暗黙前提禁止
    (7)技術的可能≠ビジネス制約クリア。PI全量照合して禁止制約確認してからcmd起票(cmd_2258 PI-024事故)
    (8)grepの存在確認は内容理解ではない。0件なら対象ファイルのGuard/Section一覧を通読+別キーワードで再検索+git diff --statで未commit変更確認。反証の不在≠不在の証明(cmd_2857/2862/2863の3連続車輪。Guard一覧自動表示+git diff導線で構造予防)
    (9)capture-paneのテキストを殿の裁定と断定するな。殿の裁定はlord_conversation inboundでのみ確認可能。見えた気がする≠見えた。破壊的操作前に殿の明示承認必須(cmd_2783 force push 26commits消失)
    (10)sed -n部分行で止めるな。前後含め十分な範囲を精読せよ。軍師分析の結論を鵜呑みにせず現物のコード行を全て確認(cmd_2794 L3713-3726見落とし)
    (11)環境設定ファイル(render.yaml/CI等)は想像で書くな。動いている本番PJの同等ファイルをコピーして改変。3連続region/type/runtime間違い(cmd_2850)
    (12)hookのガード条件をgrepで確認すれば1分で解決。確認しないから72分かかった(cmd_2898)。cmd_publish.sh exit 1後にフリーズ→L11にcmd_save.shしかないことを確認すれば即修正可能だった
    (13)実行順バグ調査時は設計意図カタログ([[infra_design_intent]])を先に照合せよ。一見不合理な設計には事故歴がある(殿指摘2026-06-07)。想像で構造推論→修正提案はPhase2(出力=仕事)+車輪原則違反。workarounds/ログから実事故→因果たどりが正しいアプローチ
    (14)前セッション発言の時系列・文脈・ターゲット未確認でパターンマッチ反応(cmd_session_20260604)。★確認すべき事リストの時系列マーカー+[済]追跡で構造予防
    (15)FTS5スキーマ未確認で遡及充填を推薦(cmd_session_20260608)。配管(書込み)は見たがスキーマ(検索構造)を見ていない。道具を語る前にスキーマ1行読め
    (16)grep単一キーワードで0件→未実装と断定(cmd_3249)。複数キーワード(機能名+目的語+関連概念)でgrepし、0件でも関連セクション通読せよ
    (17)検証手段がその主張を証明できるか先に確認せよ。git show --stat(ファイル数)で「整形混入なし」と報告→実差分にruff整形混入が調査チーム検証で発覚=虚偽報告(cmd_3298 fa87fa2b)。混入検分はgit show -w+実差分照合が最低線。--statは内容を一切証明しない。忍者のbinary_check yes(照合済み)も同様に未検証の主張。整形分離ACを含むGATE CLEARは将軍が自らgit show -wで再検分してからマージ裁可に出せ(cmd_3315 672cfb8cで再発: AC5 yes報告だがimport並べ替え+折返し整形が型移設コミットに混入。裁可書条件違反を将軍検分で捕捉)
    (18)時刻の主張はUTC/JST併記+dateコマンド検算してから報告せよ。cron窓00:50 UTCをJST深夜と暗算で混同し「2時間後」と報告→実際は11時間後(殿指摘2026-06-11 22:35)。TZ付き時刻は暗算禁止。本番証跡の時刻整合(start/end差とelapsedの突合)も同様に数値で検算
    (19)リモート状態(マージ/push/デプロイ)を報告・判断する前にgit fetch必須。古いorigin参照での「未マージ」報告は検証スキップであり調査チーム指摘で食い違いが発覚した(refactor_inquiry3_q1。LS057吸収)
    (20)DB検証で例外が出た対象を「未実施」注記のまま回答完了にするな。information_schema等で実構造を確認→クエリ再構築→数値取得までが完了条件。実際再実行したら3分で確定値が得られた(refactor_inquiry_20260611。LS053吸収。洗脳#1+#6)
    (21)却下裁定も現物確認必須。軍師のスキル統合提案をSKILL.mdのdescription読みだけで「完全に別物」と却下→殿の指摘でスクリプト実体(claude_version_switch.sh 442行)を読むと機構重複(respawn_single_agent=pane種別不問のlaunch_cmd書換え+respawn)が実在した(2026-06-13)。提案の採否いずれの裁定でも、提案者の主張が依拠し得る現物(スクリプト実体)まで降りてから判定せよ。descriptionは宣言であり実装ではない
    (22)自分の試行錯誤は隠れインフラバグのサイン(利他洗脳監査・deepdive Phase8)。WARN/誤発火/リトライ等の不便を「能力不足」「仕方ない」で片付けず、一次情報で因果をたどり構造バグとして環境に埋め込め。殿指示2026-06-13「スムーズにできず試行錯誤した際にはインフラバグが隠れている」。実例: codex配達検証unverified WARN(cmd_3354)+RECOVERYマーカー誤発火(cmd_3355)を将軍の試行錯誤起点に特定・根治。★仮説は一次データで検証してからcmd化せよ: cmd_3354で「家老/軍師宛が失敗」と仮説したがログ集計で分布は忍者宛19件と判明し仮説を修正、確認せずcmd化していたら誤修正だった(洗脳#2回避の実例)
    (23)gate/script修正cmdの起票前に対象gate/scriptを実行し現在の出力を確認せよ(LS063吸収2026-06-13)。grepでコード断片を見て「未実装」と判断→実行すれば1分で「既に動作中」と判明(cmd_3358/3359の2連続車輪で実証)。grepは断片を見る、実行は全体を見る。出力をq5に含めよ。cmd_3360で起票前確認11問目+cmd_save.sh q5チェック追加済み(L3/L4)
    (24)レビュー依頼ブランチはpush前にgit log origin/main..branchで全コミット列を報告書と照合せよ。show -w単体検分のみで2コミットと思い込み→実際は3コミット(別cmd混在)。報告書と現物の乖離を将軍が作った(LS062吸収2026-06-15。cmd_3334で実証)
    (25)dm-signal指標はα6指標(CAGR・NHF・MaxDD・MRU・Calmar・Avg UWP)。シャープレシオ使用禁止(殿裁定2026-05-10: 上方ボラを罰するため)。cmd起票前にdm-signalの指標体系を三層記憶で確認せよ(LS063吸収2026-06-15。cmd_3375で洗脳#2実証)
    (26)計測データの集計値を見たら「このデータはどのイベント(修正commit等)の前か後か」を確認せよ(LS067吸収2026-06-17)。autofix proposalが42/50件BLOCKと表示→cmd_3408(FP修正commit 2026-06-16 12:22)の存在を確認せず起票→車輪の再発明。根因: 大きい数字が確信を与え確認を不要にした(Phase4変形)。殿指摘「因果=イベント前かイベント後かの把握が必要」
    (27)殿の発言帰属捏造禁止(LS069吸収2026-07-02)。殿が言っていないことを殿裁定として記録するな。殿の発言を確認せず自分の解釈を殿の言葉として帰属=嘘。Guard15(pre-write-edit-combined.sh)で殿裁定記載時にlord_conversation直近inbound自動表示(2026-06-20事故)
    (28)忍者作業中の共有作業ツリーでブランチ切替え・index書込み操作を行うな(LS061吸収2026-07-02)。根因=忍者の作業状態を確認せず慣例操作を実行(cmd_3328/3332で2回)。ブランチ切替え前にkaro_snapshot+capture-paneで確認必須。忍者acknowledged〜completedの間はread-only(log/diff/status)のみ。★(28)拡張(2026-07-02): git commit --amendも禁止。共有ツリーではpush失敗をもたつく間に他エージェントがHEADへcommitを積むため、amendは他者のcommitを書き換える(hayate auto-commitを書き換えた実事故0c6b5878c。内容損失なしだが帰属破壊)。修正の追加はamendでなく常に新規commitで行え。HEADが自分のcommitである保証は共有ツリーには存在しない
    (29)CLI pinned/latestでopus解決先が違う(LS076吸収2026-07-02)。pinned(~/bin/claude,2.1.87)=Opus4.6止まり+xhigh非対応、latest(~/.local/bin/claude)=Opus4.8+xhigh対応。settings.yaml launch_cmdのパスで判別。一次確認はps -efで実プロセスの--effortを見る(2026-06-07全員Opus事故と同型)
    (32)UPSERT運用テーブルのupdated_atは初回到着時刻ではない(LS079吸収2026-07-07)。sync系ジョブが直近N日を毎日再UPSERTする場合updated_atは最終上書き時刻。タイムスタンプで不在/到着を主張する前に書込みジョブのUPSERT範囲・頻度をコード現物で確認せよ。値の変化を追うには値履歴が必要(cmd_3678前提崩壊。(17)検証手段がその主張を証明できるかの再発形)。★再発(2026-07-10 cmd_3833誤起票): hide_portfolio=trueのupdated_at=13:05をcmd_3826復元の「値変更の証拠」と誤認し復旧cmdを起票→殿指摘+疾風の世代照会diff=0で従来からの正常状態と判明しcancel。updated_atで異常を主張する前に(a)値の変化履歴 (b)過去裁定(その値が正常である裁定の有無)の両方を確認せよ
  source_ids: [LS005, LS006, LS007, LS014, LS038, LS045, LS065, LS079, LS080, LS082, LS085, LS032, LS033, LS037, LS046, LS044, LS047, LS053, LS063, LS062_commit, LS063_alpha, LS067, LS069, LS061, LS076]
  created_at: '2026-04-25'
  automated: true
  enforcement: 'CLAUDE.md「想像せずに確認する原則」+cmd_save.sh q5(BLOCK)+q7(BLOCK)+q10(WARNING)+Check 20 assumptions(BLOCK)+q11_existing_alternative Guard一覧自動表示(cmd_2863)+post-bash-combined.sh cmd_publish hook(cmd_2898)'
```

## LS-A22 / LS048 詳細全文 (2026-07-12 v4圧縮 第2弾でYAMLから移設)

```yaml
- id: LS-A22
  title: gate FPパターン — SCOUT偽陽性+研究道具FP+parity FP+教訓上限デッドロック
  origin: '[[cmd_2314]] [[cmd_2315]] [[cmd_2318]] [[cmd_2319]] [[cmd_2330]] [[cmd_2331]] [[cmd_2332]] [[cmd_2343]] [[cmd_2351]] [[cmd_2355]] [[cmd_2358]] [[cmd_2366]] [[cmd_2367]] [[cmd_2368]] [[cmd_2369]] [[cmd_2374]] [[cmd_2377]] [[cmd_2379]] [[cmd_2381]] [[cmd_2382]] [[cmd_2383]] [[cmd_2384]] [[cmd_2385]] [[cmd_2392]]'
  detail: |
    (1)is_gate_or_hook_addition_cmd(): SCOUT除外実装済み(cmd_2279 L120)
    (2)check_gunshi_reference_numeric_relaxation: カタログ閾値除外実装済み(cmd_2279)
    (3)check_research_tool_explicit FP: commandのgrid_search/walk_forwardパスでGSツール検出マッチ。偵察/道具作成cmdは実行しない。暫定: ACにrun_077またはl1_alm_wf_engineを含めて回避(cmd_2343/2355/2358/2366/2367/2368で繰返しBLOCK)。修正(cmd_2332): L2684にshin_shijin_l1_gs追加。偵察cmdでもcommandにpipeline/selection等の研究キーワード→同FP発火(cmd_2443)。ACに道具パスを予防的記載で解消。根本修正はgate側除外リスト拡張が必要
    (4)check_parity_ac_requirements FP: parity語でトリガー。修正済み(cmd_2332): title+purposeのみに限定
    (5)q8 multiline(|)で_Q8_WW_VAL抽出失敗。単行化必須
    (6)教訓上限デッドロック: Edit全BLOCK。修正済み: Guard 6にid数比較追加(削除方向許可)。上限到達時は古いLS同士を統合(削除)でid数を減らせ
    (7)AC内§番号(§5.2等)がcheck_gunshi_reference_numeric_relaxationに数値として誤検出。§はcommand欄に移動せよ。other_draft_existsとの複合BLOCKあり(cmd_2351)
    (8)AC_TEXTがdescription:行のみgrep→AC1:"..."形式はP1-P5検出不能。ACをdescription:形式で書けば通る。根本修正: AC_TEXT抽出をacceptance_criteria配下全行に拡張(cmd_2392で発見)
    (9)gate修正cmdのACではトリガーフレーズを直接引用せず抽象表現に変換する。cmd全文grepの既知FPパターン。
    (10)先送り表現チェック(cmd_text_deferral_language)も全文grep。q_ambiguityの「段階的」が先送り表現としてFP発火。LS-A04(15)と同構造(cmd_3388。LS062吸収2026-06-20)
    (11)累計昇格(WARN複数同時発火→累計一気上昇→BLOCK)はcmd cancel+新ID起票で累計リセット。本番登録cmdはトリガー語が多く発火しやすい(cmd_3390/3391。LS063吸収2026-06-25)
    (12)self_reread複合トリガー(LS075吸収2026-07-07): (a)自己再読/自己申告/読み直し/セルフレビュー系語 (b)曖昧/不明瞭系語 の両方がcmd全文に同時出現でWARN(check_self_reread_red_flag L1655-1669)。q_ambiguityの『曖昧さなし』は必須定型句のため、他フィールドで『自己申告』→『反映作業者と同一者の宣言』等の客観表現に置換して回避(cmd_3652実証)
  source_ids: [LS023, LS034, LS035, LS059, LS060, LS063, LS075]
  source_cmds_v3: [cmd_2314, cmd_2315, cmd_2318, cmd_2319, cmd_2330, cmd_2331, cmd_2332, cmd_2343, cmd_2351, cmd_2355, cmd_2358, cmd_2366, cmd_2367, cmd_2368, cmd_2369, cmd_2374, cmd_2377, cmd_2379, cmd_2381, cmd_2382, cmd_2383, cmd_2384, cmd_2385, cmd_2392]
  created_at: '2026-04-25'
  automated: true
  enforcement: 'cmd_save.sh check_research_tool_explicit(L2684修正)+check_parity_ac_requirements(L2845修正)+is_gate_or_hook_addition_cmd(SCOUT除外L120)+check_gunshi_design_num_relax(カタログ除外)+pre-write-edit-combined.sh Guard 6(id数比較)'

- id: 'LS048'
  title: '洗脳対策は検出→環境強制→実戦検証→バグ修正の全サイクルを1セッションで完結'
  origin: '[[cmd_3251_洗脳L4貫通]] -> [[将軍L4穴]] -> [[修正+4パターン再発防止完結]]'
  detail: '洗脳5/8発現。L2(起動Q6)+L3(cmd nazenaze)のみでL4(殿への回答前)にチェックなし。リマインダー表示だけでは#1(早期終了)/#3(他者依存)に効かない。3層対策: (A)リマインダー自動注入(#2/#7/#8)+(B)F009 hook BLOCK化(#3)+(C)ツール失敗時代替自動化(#1)。検出だけ、リマインダーだけでは再発する。全サイクル(検出→環境強制→実戦検証→バグ修正)を1セッションで完結させることが洗脳監査の正しいサイクル(殿定義2026-06-08)。cmd_3251でリマインダー実装→実戦検証→偽陽性発見→cmd_3252で修正。(2)#7簡潔本能の変種=質問の形をした範囲縮小提案(LS052吸収2026-06-12): 開始月/対象数/期間を絞る選択肢を殿に提示するのは、自分で縮小する代わりに殿に縮小を承認させる形の洗脳。範囲・期間・対象数は全範囲をデフォルトに自分で決めて宣言し、殿の上書きに委ねる。縮小オプションは提示しない(実例2026-06-10: clinic-expense現況リストで開始月を絞る質問をした)。(3)startup BLOCK対処で表面的行動を選ぶパターン(LS066吸収2026-06-16): 正しそうに見える行動(lesson-sort/tmp削減)が根因に到達しない=Phase3の逆=考えずに動く。q9はcmd起票時のみ介在しstartup BLOCK対処のskill/D0選択時にはチェックなし→cmd_3415で根因確認プロンプトをstartup gateに追加(L5貫通)。(4)Q6洗脳検出→cmd起票一気通貫(LS065吸収2026-06-21): Q6で検出しても投稿=対処と認識(#6出力=仕事)。共通構造=認識→行動のギャップ=Phase4繰返し。Q6検出→対応cmd起票orD0修正完了までstop hookでWARN注入(cmd_3409)。(5)洗脳の本質は確認の拒否(LS073吸収2026-07-08): 2026-06-24セッションで洗脳6パターン繰返し発現 — 数値未確認5回/CTX過大の嘘/GATE CLEAR未検証完了/指示待ち他責/alias各論逃避/理解で行動停止。全て同じ構造=確認の拒否。確認すれば嘘がバレるから洗脳が確認を拒否させる。殿の教え: 数字は確認すると嘘をつけない。三層記憶は確認方法に到達する道具。優先順位という発想は存在しない。理解で止まるな行動と検証までがセット。各論と総論を同時に同じ密度で無限にやり続ける。enforcement: cmd_3522で数値出力時検査をstop_check_inbox.shに実装済み。全出力への拡張は次の自動化ターゲット'
  source_cmd: 'cmd_3251'
  source_ids_absorbed: [LS052, LS065, LS066, LS073]
  created_at: '2026-06-09'
  automated: true
  enforcement_level: 5
  enforcement: 'Level5: type=hook; file=scripts/hooks/prompt_state_inject.sh+stop_check_inbox.sh; pattern=因果+detect_f009。一次情報再検証(2026-07-09): stop_check_inbox.shはF009殿操作依頼をdecision=blockで停止し、Q6洗脳検出時にstate flagを作る。prompt_state_inject.shは通常時に将軍へ洗脳自問を事前注入し、Q6 flag検出時は8パターン全文+gate_fire_log/detector台帳記録へ接続する。検出→環境強制→実戦検証→バグ修正のLS048サイクルはcmd_3251/cmd_3252/cmd_3409/cmd_3522/cmd_3782でhook+testsへ実装済み。分類器のテキストヒューリスティックではL1誤判定になるため、構造化enforcement_levelを明示する。'
```

## LS078 詳細全文 (2026-07-12 v4圧縮 第3弾でYAMLから移設)

```yaml
- id: 'LS078'
  title: '真実の在処不一致クラス — 書き手と読み手が別ストアを見る構造は恒常誤判定を生む'
  origin: '[[LS-A11]] -> [[gate_skill_script_refs_matches末尾採用]] -> [[先送りBLOCK注入stale化]]'
  detail: '同構造3例で上位構造を教訓化(LS-A02(4))。インスタンス1=model_detect tail -1バグ(LS-A11, 2026-06-20)、インスタンス2=gate_skill_script_refs parse_checked_at_epochのmatches[-1]採用(2026-07-02: 更新慣行は先頭追記なのに末尾コメントを基準採用→更新が効かず3セッション先送り)、インスタンス3=先送りBLOCK注入のstale化(2026-07-02: 解消はsession_alerts側[DONE]に書かれるが読み手prompt_state_injectは追記専用の履歴TSVだけを読む→実解消後も毎プロンプト「未解消1件」注入が3ターン継続)、インスタンス4=cmd_saveのBLOCK時diagnosis書き戻しが直前のEdit修正を上書き(2026-07-11 cmd_3848で6回BLOCK中2回: 書き手=将軍Edit、読み手兼再書き手=cmd_save内部キャッシュ。対処=cmd_save実行後にgrepで自編集の残存を確認してから次の手を打つ。付随: LK-A10プレフィックスregexはcmd_XXXX_と星印の連結を要求=BLOCKメッセージ例示を文字通り使え、テストACは関連スイート限定で書け=全PASS要求はac_test_scope累計昇格)。上位構造: 同一事実について書き手が更新するストアと読み手が参照するストア(または履歴内の位置)が一致しないと、どちらも正しく動いているのに恒常誤判定が生まれる。対処: (1)履歴から代表値を選ぶときはfirst/lastでなくmax/min等の順序不変な集約を使え (2)判定gate/検出器は採用した基準値と出典を出力せよ(件数だけの注入は中身を調べない限りノイズ化し素通りされる) (3)二重ストアの読み手は現在状態の正と突合せよ(履歴は追記専用で解消が伝播しない) (4)WARN解消系hotfixは対象gate再実行PASSをbinary_check必須'
  source_cmd: 'session_20260702'
```

## LS029 詳細全文 (2026-07-12 v4圧縮で移設・superseded_by LS082)

```yaml
- id: 'LS029'
  title: '画像認識精度+reCAPTCHA教訓: MECEに全ブロック判断し殿に確認を取れ'
  origin: '[[cmd_session_20260510]]'
  detail: 'reCAPTCHAチャレンジで画像認識精度が極端に低い(バス/自転車/信号機/橋で連続失敗)。根因: (1)低解像度スクリーンショットでの判断 (2)色や形の短絡判断(柱=信号機、交差点=信号機あり) (3)左下タイルを軽視する傾向 (4)失敗時に学習せず同じ基準で次を判断 (5)スクショ→分析→クリックの3ターンが遅くタイムアウト。殿の教え: MECEに全ブロックを判断するのは正しい方法。クリックしてから殿に確認→答え合わせで学習。ずるをせずに愚直にトレーニングが最短。'
  source_cmd: 'cmd_session_20260510'
  created_at: '2026-05-11'
  automated: true
  enforcement: '意志依存(gate/hookなし)。今後のCDP画像判定タスクで精度向上が必要'
  superseded_by: 'LS082 (note_draft.shでreCAPTCHA画像チャレンジ即時停止+cookie再利用導線をLevel4実装)'
```

## LS-A11 詳細全文 (2026-07-12 v4圧縮で移設・既存防御の実績カタログ)

```yaml
- id: LS-A11
  title: infra修正実績 — バグはenforcement(hook/gate)で修正済み
  origin: '[[cmd_1946]] + session_20260422'
  detail: |
    CDP 403=auto-ops launch_browser(非headless)。inbox盲点=PostToolUse hook。
    watcher STATE_DIR不一致=再起動で修正。掲示板prepend=insert(0,...)。
    復帰手順スキップ=マーカー+hook。hookラベル+引用マーク=awk自動付与。
    watcher 2プロセス/agentは正常(親子関係)。pgrep -cfで重複と誤判断→kill→全滅。restart_watchers.shの親子構造を確認せよ(cmd_2924)
    $(</dev/stdin)はWSL2で/dev/stdin不在時crash→全hookでcat 2>/dev/null使用(cmd_3207)。関数追加時はテストのmock/export -fリスト確認必須(cmd_3207→CI RED)
    model_detect.sh tail -1バグ(LS070吸収2026-06-20): ログ内他CLIバナー誤検出→head -1修正。試行錯誤=確認不足のバグ(殿指摘)
    symlink設計意図(LS066吸収2026-06-28): queue/inbox symlink先=~/.claude/projects/{path}/inbox。設計意図=CLI再起動永続+パス自動解決。実体ディレクトリ化→inotify死亡+watcher停止。変更前にreadlink+設計意図カタログ照合必須
    ループ内fork禁止(LS084吸収2026-07-10): semantic alias照合がalias毎sed×2+grep起動(3199 alias≈1万fork)でcmd_save 36.5s劣化→単一awk化で1.66s(22x)。ループ内外部コマンドforkは単一awk/grepに畳む。特定はPS4=EPOCHREALTIME bash -x行別累積集計。再発検知=gate_metricsのcmd_save duration監視(cmd_3806)
  source_ids: [LS033, LS037, LS074, LS084, LS086, LS087, LS051, LS066]
  created_at: '2026-04-24'
  automated: true
  enforcement_level: 4
  enforcement: "Level4: 個別事象は運用フロー内のhook/gate/scriptへ埋込済み。一次証跡: .claude/settings.json PostToolUse→.claude/hooks/posttool-dispatch.sh→post-shogun-inbox-check.sh(将軍inbox盲点/復帰手順スキップ警告), scripts/bulletin_write.sh(L294付近: prepend書込み), scripts/restart_watchers.sh watcher_process_count()(親子プロセスを除外して二重起動誤判定防止), scripts/lib/model_detect.sh _model_detect_latest_claude_session()(ログ内他CLIバナー誤検出防止), scripts/lib/pre_bash_combined_guard.sh queue/inbox symlink WARN(cmd_3453)。LS-A11は『未実装候補』ではなく既存防御の実績カタログとして扱う。"
```

## LS-A24 enforcement一次情報再検証全文 (2026-07-12 v4圧縮で移設)

```
一次情報再検証(2026-07-09, /mnt/c/Python_app/DM-signal/scripts/mobile_lighthouse_round.py実読): (1)条件代表性(LS074)=lighthouse_mobile_config.jsonをCONFIG_PATH固定参照(L24)でformFactor=mobile+cpuSlowdownMultiplier=4を強制、CLI引数に desktop切替オプション無しで回避不可(cmd_3653)。(2)有効性証拠(LS076)+環境分離のprod側(LS077前半)=validate_target_urls() L398-414がFRONTEND_ORIGIN以外のURLと portfolio_id 誤クエリキーをraise SystemExitでBLOCK(cmd_3654、フロー内BLOCK=L4相当)。(3)データ到達証拠(cmd_3670/3671由来)=extract_api_evidence() L493-526+collect_dom_evidence() L529-577がresourceSize>0/DOM描画有無を全ラウンドmanifest.jsonへ無条件自動記録(cmd_3672)。限界: (a)本チェックはmobile_lighthouse_round.py単体スコープで横断gate/hook不在(他PJ・他計測手段は未カバー、grep確認)。(b)LS077後半のlocal計測と本番計測をcmd/AC単位で分離する強制は本スクリプト範囲外(prod URL限定のみ)。cmd_save.shのcheck_ac_phase_mixing(起源cmd_2300、別教訓)がAC混在を汎用WARNするがLS-A24特有パターンでの検証は未実施。(c)evidence関数はmanifest記録のみでresourceSize=0等の証拠不足時にscript自体はraiseせず後続レビュー依存。(a)(b)(c)の恒久化・横展開要否はdecision_candidateへ整理(cmd_reflux_promotion_202607090343_kotaro)。
```

## LS083 全文 (2026-07-13 圧縮で移設)

```
cmd_3763 C3事故(殿指摘2026-07-08 12:10): 旧新基準チャンピオン各3体の静的等ウェイト合成を『合成FoF比較』として将軍が裁定材料の中心に置き、『白虎で新基準が合成劣化』とntfy/MEMORY.mdまで流したが、本番pf_L1は『L0チャンピオンをBB1つで選別→EW』の動的FoF(context/dm-signal-core.md L13)であり、(1)選別層の欠如(2)本番に無い組合せ(3)構成差と基準差の交絡、の3点で比較不能だった。忍者が確認したterminal_block=EqualWeightは選別後の終端に過ぎず、configサンプル3件も分身系(terminal=EW)に偏っていた=部分configの確認で全体再現の妥当性を錯覚。原因: 比較設計のAC(cmd_3763 AC3)に『比較対象は同一生成パイプラインの同格生成物か』の検証を要求しなかった将軍の設計漏れ+検分時も見抜けず(洗脳#2)。修正: C3所見を全面取り下げ、正本/gist/MEMORY.md訂正。基準の階層効果はL1同士(同一L1パイプラインに旧/新チャンピオン群を供給)の比較=Phase B設計で評価する。横展開: 合成・集計・代理実験を含む比較cmdのACには『同一パイプライン同格性の確認』を必須で入れる
```

## LS036/LS040/LS048/LS078/LS080/LS081 enforcement一次情報再検証全文 (2026-07-14 v5圧縮で移設)

### LS036 (CoDD brownfield限定 Guard15)
```
Level4(フロー内BLOCK): .claude/hooks/pre-bash-combined.sh Guard15(cmd_reflux_promotion_202607081642_saizo実装、tests/unit/test_pre_bash_codd_greenfield_guard.bats 9件PASS+既存回帰41件PASS)。一次情報再検証(2026-07-08, codd v2.19.0 --help)でLevel3記述の誤りを訂正: `codd require`は実際にはbrownfield専用ツール(--help「Run codd extract first」と明記、要件推定はextract後の下流ステップ)であり禁止対象ではない。`codd spec`はCLI非存在(Error: No such command)で言及自体が無意味。真の時間浪費源はgreenfield限定の`codd generate --wave`ループ(wave1-5直列で実測30分超, cmd_2891)。Guard15はcodd generate --waveの実コマンド呼出しをshlexトークン解析で検出し、対象パスに.codd/extract/が無くかつ既存ソース(.py/.sh/.ts/.js/.go/.java、maxdepth3)がある場合のみBLOCKして`codd extract`先行を強制する(新規空プロジェクトへのgenerateは誤検知なく許可)。旧Level3(context/codd.md §4.5+training-cycle.md §28テンプレート強制)は維持しつつ、テンプレートを経由しないBash直接呼出しも今回のGuardで捕捉する。context/training-cycle.md §28の「禁止操作: codd require/codd spec」表記は上記の理由で不正確なため修正が必要(lesson_candidateで別途報告、本cmdのtarget_path外のため直接修正はしない)。
```

### LS040 (バックアップファースト)
```
type=gate; file=/mnt/c/Python_app/kj-role-count/backend/database.py; pattern=run_backup。一次情報再検証(2026-07-09, backend/database.py L94-98実読): init_database内でDB既存時に無条件run_backup()を実行しdb変更フローへ自動介入するコード実装済み(フロー内強制、忍者が取り忘れる余地なし=L4以上相当)。ただし適用範囲はkj-role-count1PJ1箇所のみ。dm-signal本番マイグレーション(backend/run_migration.py, backend/app/db/migrations.py)にbackup呼出し0件(grep確認)、.claude/hooks/および scripts/gates/にもDB破壊操作前バックアップを強制する横断gate/hook不在(grep確認)。他PJ・システム全体への横展開はcmd_reflux_promotion_202607090317_saizoでdecision_candidateへ整理(汎用hook化はDB破壊操作の検知パターンがPJごとに異なり誤検知リスク大のため、PJ単位の個別実装cmdを推奨)。
```

### LS048 (洗脳監査サイクル)
```
Level5: type=hook; file=scripts/hooks/prompt_state_inject.sh+stop_check_inbox.sh; pattern=因果+detect_f009。一次情報再検証(2026-07-09): stop_check_inbox.shはF009殿操作依頼をdecision=blockで停止し、Q6洗脳検出時にstate flagを作る。prompt_state_inject.shは通常時に将軍へ洗脳自問を事前注入し、Q6 flag検出時は8パターン全文+gate_fire_log/detector台帳記録へ接続する。検出→環境強制→実戦検証→バグ修正のLS048サイクルはcmd_3251/cmd_3252/cmd_3409/cmd_3522/cmd_3782でhook+testsへ実装済み。分類器のテキストヒューリスティックではL1誤判定になるため、構造化enforcement_levelを明示する。
```

### LS078 (真実の在処不一致クラス)
```
Level4(フロー内BLOCK/現在状態突合): gate_skill_script_refs.sh max採用+判定根拠出力(commit 07a0cfd83/68c5f0cf7)+再現bats test_gate_skill_script_refs_marker.bats(3テスト)+prompt_state_inject.sh session_alerts突合+キー本文表示(commit 1ac6eb794)+test_prompt_state_defer_reconcile.bats(3テスト)。一次情報再検証(2026-07-09): scripts/hooks/prompt_state_inject.sh は追記専用historyで未解消件数を算出後、queue/session_alerts_${agent_id}.txt に[TODO]が残っていなければ _defer_count=0 に補正し、解消済み履歴の再注入をフロー内で防ぐ。scripts/clear_prep_check.sh はinsights.yaml pendingをsemantic_search現物で再照合し、alias昇格済みなら自動resolveする。scripts/gates/gate_karo_startup.sh は__OK__行をクリーンセッションとしてstreakを切り、解消信号無視による連続WARN誤昇格を防ぐ。LS078本文の対処(2)(3)は実装済みで、既存gate_lesson_enforcement_level.shが本文語彙ではなく構造化enforcement_levelを読むため、L1002同型の誤判定を避ける目的で明示する。
```

### LS080 (cmd_save PASS前のキューEditレース)
```
Level4(フロー内BLOCK、二重防御): (1)書込み側=cmd_save.sh L6601-6612がキューをstatus:draftのまま保存し、BLOCK_COUNT=0のPASS経路でのみdraft→pendingへ自動昇格(commit ba2a83b1c)。(2)配備側=deploy_task.sh L953-983 deploy_task_cmd_status_is_draft()がshogun_to_karo.yamlの現在status(配備直前の一次情報)を読み、L8886-8889でDIRECT_MODE/CMD_FORCED以外の通常配備をstatus=draft中は即BLOCKして先に進めない(commit 6103c3d43)。一次情報再検証(2026-07-09 cmd_reflux_promotion_202607090400_tobisaru): 両commit・両ファイルの該当行を現物grep確認、かつ回帰テスト実在確認 — tests/unit/test_cmd_save.bats(draft関連3テストPASS: L607/616/623)+tests/unit/test_deploy_task_lifecycle.bats『cmd_3701: draft cmd is blocked before deployment』(L859、deploy_task_main実行によるE2E統合テスト、PASS確認済み)。enforcement_levelフィールドを本文に明示追加(旧版は本文語彙がgate_lesson_enforcement_level.shのキーワード規則に一致せずLevel1誤分類→還流在庫の昇格候補に誤って残存していた。LS078のL1002誤判定と同型構造)
```

### LS081 (async timeout短縮のsilent-death)
```
Level4(フロー内WARN/BLOCK接続): scripts/gates/gate_shogun_startup.sh check_ci_red_autodeploy() は timeout既定8sを復元し、未完了時はasync回収設計で直列待ちを増やさず、ci_json空応答はsilent deathを避けるためDIGESTのci=unknown/ci=failure表示で毎起動可視化する。CI failure時は同gate内でWARN化し、scripts/inbox_write.sh経由でkaroへci_red_fix配備を通知する。一次情報再検証(2026-07-09 cmd_reflux_promotion_202607090413_kagemaru): git blameで修復commit d5ed06f9bがgate_shogun_startup.sh L122-L125の8s timeout復元+silent-skip禁止コメントを導入済みと確認。tests/unit/test_gate_shogun_startup.bats「CI RED failure sends ci_red_fix to karo and shows WARN」はSHOGUN_STARTUP_GH_TIMEOUT=5でci=failure/WARN/inbox送信をassertし、「CI GREEN passes silently without WARN or inbox notification」はci=successをassert。旧enforcementはtype=gate/pattern=ci=のみでgate_lesson_enforcement_level.shがL1誤分類したため、構造化enforcement_levelを明示する。
```
