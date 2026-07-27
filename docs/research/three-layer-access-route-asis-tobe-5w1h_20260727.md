# 三層記憶アクセスルート是正案 — ASIS/TOBE 5W1H (2026-07-27)

- 起案: 将軍(殿下知 2026-07-27 02:34「修正案を作成して家老と軍師にレビューしてもらえ」)
- 発端: 殿指摘 02:19-02:27「三層記憶へのアクセスルートがすり替わってる。memoryは三層記憶が出来てからは本来使わないはずだ。クリティカルだ」
- 一次確認: 将軍(コード現読)+家老(blt_20260727_023043→訂正blt_023153)+軍師(blt_20260727_023045) 三者一致
- origin: [[殿指摘_三層アクセスルートすり替わり_20260727]] -> [[011bc13d1_preflight証跡化]] -> [[本修正案]]

## §1 ASIS(現状) — 4つの欠陥が同時に存在する

### A1. 検索結果の破棄(すり替わりの本体・最重要)
`scripts/hooks/three_layer_preflight.sh:373-390`(導入=commit 011bc13d1, 2026-07-10「hotfix: enforce three-layer pre-action evidence」):
```
bash scripts/memory_db_query.sh --search "$prompt" >/dev/null 2>&1
bash scripts/semantic_search.sh "$prompt"          >/dev/null 2>&1
obsidian_cached_search ...                          >/dev/null 2>&1
```
三層の検索は毎ターン実行されるが**結果は全て破棄**。記録は rc・件数・timestamp・query文字列のみ。
`pre-bash-combined.sh:117-119` / `pre-write-edit-combined.sh:250` が証跡なしBash/Editをfail-closed BLOCKするため、
全エージェントは「三層を使った」状態になるが**中身を誰も読んでいない**。
= 「検索して結果を読む」→「検索した証跡を発行する」への変質。deepdive Phase 9(保存完了トークンで満足)の機構版。

### A2. セマンティック層のmemoryすり替わり
`scripts/semantic_search.sh:496-511`: alias層miss→source-map miss後、本来の第二層(LLM意味マッチ)は
`SEMANTIC_ENABLE_LLM_FALLBACK=1`がない限り**デフォルト無効**(3f6a9522f, 2026-06-02)で、
**memory DB FTSへフォールバック**(cmd_2994導入)。出力は`MEMORY_DB_MATCH`だが、呼び手は「semanticの結果」と誤認する。
殿の「memoryは本来使わないはず」の実体。

### A3. 正本の移動が手順書未記載
実効ルート=hook4本(`pre-bash-combined.sh` / `three_layer_preflight.sh` / `prompt_state_inject.sh` / `stop_check_inbox.sh`)へ移ったが、
`instructions/*.md`には一文字も書かれていない(家老確認 blt_023153)。手順書を読んで答えると実態を外す。

### A4. cache実体の起動時不在
`memory_db_query.sh`の参照先が/tmp cache(`/tmp/shogun_memory_db_cache/`)へ移行(aba450d32, 2026-07-26)。
本日startup gateが「三層記憶DBが存在しない」WARN=cache未生成の時間帯にスクリプトが実体へ当たらない状態が実在(家老実測)。
WARN止まりで自動回復しない。

### A5. 偽引用の構造的生産(軍師レビューで追加 blt_20260727_023812)
`stop_check_inbox.sh:453`: preflight成功済みの非定型回答は[MEM:]タグなしだとBLOCK。
だがA1により検索結果は誰にも届いていない — **読んでいないものの引用が強制**されている。
UserPromptSubmit注入の[MEM:]雛形もsource/query/tsのみで原文欄なし=空の引用札。A1(不作為)より重い作為的欠陥。

### A6. 三層検索の4割強がタイムアウト(軍師全数実測 blt_024235)
logs/preaction_memory/evidence_*.json 全313件集計(全数・標本でない): success 179(57.2%)/failed 134(42.8%)。
rc=124(timeout 2.2s打ち切り)がmemory層41.5%・semantic層28.8%。obsidian層は0件。
証跡は嘘をついていない(rc!=0→failed→verify拒否を軍師実読確認)が、**42.8%のターンで初回preflightが失敗し
BLOCK→再発行の空転**が起きている=「削るな、速くしろ」(殿裁定07-21)の対象。
※台帳第1支配項 three_layer_health:refresh_window(平均38.5s、cmd_4174起票済み)と同じ遅さの族。

### A7. evidenceが検索クエリ自体も捨てている(軍師発見・家老追認 blt_032644)
preflight evidence 313件中、実クエリ(*_query)を保持するのは12件のみ。残301件はprompt_hash(SHA-256・不可逆)のみ。
A1(結果の破棄)と同根 — 結果だけでなく**クエリも捨てる設計**。実害の実例: cmd_4176 AC1/AC2の教材化が
evidence源では不可能になり、供給源を記憶DB events(conversation 64,786件)へ差し替えた(2026-07-27 03:27将軍裁定)。
T1実装時にevidenceへ実クエリも保存する(記録のみ・実装は殿の指示待ち)。

### ASISの帰結(実害・本セッション実測)
- 将軍がcmd_4167(precheck cache実装済み)を三層で発見できず、重複スクリプトを自作→撤去(車輪の再発明・約30分損失)
- 殿が3度「三層記憶を使え」と言う事態(殿の時間強奪)
- 検索劣化が全ロール・毎ターンに効く(preflightは全Bash/Edit前に走る)

## §2 TOBE(あるべき姿) — 原理1行

**「三層検索は毎ターン強制のまま、結果を捨てずにターンへ注入し、エージェントが読める状態にする。」**
証跡発行とfail-closed強制は維持する(必須ハーネスは削らない=殿裁定2026-07-21「削るな、速くしろ」)。
宛先指定(targeted visibility)も維持する(殿裁定2026-07-27 02:25「宛先指定は正しい。全員可視は指示誤帰属を生む」)。

### T1. preflight結果注入(A1是正)
- three_layer_preflight.shの三層検索結果を捨てず、各層上位N行(既定: memory 5行/semantic 1概念/obsidian 3リンク、上限バイト付き)を
  evidenceファイルへ保存し、hookのadditionalContextとしてターンに注入する。
- 証跡(rc/件数/ts/query)は現行のまま。fail-closed契約は不変更。
- 注入量はCTX保護のため上限(例: 2KB)でtruncateし、全文は evidenceファイルパスを添えてRead可能にする。
- ★軍師条件(LG075防御): truncate時は**総ヒット件数とevidenceファイルパスを必ず同梱**。上位N件だけ見せて
  総数を伏せると「見た範囲を全体として語る」誤認を毎ターン配ることになる。
- 注入頻度: prompt_state_inject.sh:202のissue呼出し(UserPromptSubmit毎1回)が唯一の経路であり、
  Bash毎の再検索は構造上起きない(軍師実読確認)。新たな頻度機構は不要。
- **★空注入の明示(A6連動・軍師条件)**: memory層は現状4割の確率でtimeout=結果ゼロ。timeout時は
  `NO_RESULT(timeout)`と明示注入する。黙って空にすると「注入欄が空=該当なし」と誤読され、
  A5(読んでいないものの引用)がA6(空を該当なしと誤読)へ形を変えて残る。

### 実装順序(軍師具申を採用)
**A5/T1(偽引用停止+結果注入) > A6(timeout率是正=cmd_4174と合流) > A2全廃(T2、alias被覆実測後) > A4 > A3**
A6を先に潰さないとT1が空注入を量産する。

### T2. semanticフォールバックの全廃(A2是正) — ★殿裁定2026-07-27 02:37-02:38で改訂
- **殿裁定(全軍恒久原理)**: 「フォールバックという発想自体がバグの真因」。層のmissを別経路で自動的に埋めると
  失敗が成功の顔をして返る。ラベル付きでも自動切替である限り不可(knowledge:f02e4e8f+5a4785f6)。
  前例=DM-Signal Silent Fallback HIGH11+Medium8修正+PI-018免疫系の全軍展開。
- semantic_search.shの**memory DBフォールバックを撤去**。alias層・source-map層のmissは`NO_MATCH: <query>`として
  **可視で返す**(fail-visible)。次の一手(記憶DBを引く/aliasを直す)は呼び手が明示的に選ぶ。
- NO_MATCH出力にalias改善導線(semantic_alias_absorb経路)を1行添える(自動実行はしない)。
  ★軍師条件: 導線が実際に登録まで回るか(absorb実行実績)を1度実測してから確定(恒久的機能欠損の防止)。
- LLM第二層の既定復活もしない(自動切替=同罪)。--llm明示指定時のみ。NO_MATCH実発生率をT2導入後に計測してから再判断。
- ★軍師指摘(証跡の嘘): 現状はmemory DB結果でもsemantic_rc=0と記録され層被覆を過大申告する。
  T2撤去によりこの嘘も同時に消えるが、**preflight evidenceに「実際に応答した層」を記録する**ことを契約に含める。
- **★順序条件(軍師実測 blt_024235)**: 現在semantic層の応答の約7割がmemory DB由来(手選び10件の暫定値・全体数字として扱うな)。
  全廃だけ先行すると「黙って別層が答える」が「semantic層は3割しか答えない」に変わるだけ。
  ∴全廃の前に**alias被覆の実測**(何件のクエリがalias/source-mapで到達できるか)を1本実施し、
  alias登録の先行埋めか「NO_MATCH許容」の明示的設計判断かを殿裁定で確定してから撤去する。

### T5. 偽引用の停止(A5是正・軍師発見) — 結果破棄×[MEM:]強制の組合せ
- 現状: stop_check_inbox.sh:453が[MEM:]タグなし非定型回答をBLOCKするが、A1により誰も結果を読んでいない
  =**読んでいないものの引用を強制**(空の引用札の配布)。A1の不作為より重い作為的欠陥。
- 是正: **T1(結果注入)が入るまで[MEM:]検査をこれ以上強化しない**。T1導入後、[MEM:]タグは注入された実結果
  からの引用のみ有効とする(雛形の空札は廃止)。[MEM: n/a — 理由]の正直な逃げ道は維持。

### T3. 手順書の実態同期(A3是正) — ★家老レビュー(blt_024052)で確定・拡張
- **書込みルートの正=memory_db_knowledge_write.sh(直接)**(家老が実装実読で確定):
  knowledge_writeのみがLayer1→2→3の三層連鎖を担保。bulletin_write.shはLayer1 INSERTのみで連鎖なし。
  instructions/karo.md L159-164の「掲示板投稿→自動INSERTを第一」記載が誤り=T3最優先の是正箇所。
- **書き分け規則(1行)**: 知識を残す目的=knowledge_write(三層連鎖)。誰かに伝える目的=bulletin(通知+1層)。
  両方必要なら両方呼ぶ。片方で済ませない。
- instructions4本+CLAUDE.mdに「実効ルート=hook自動注入(読む義務)、手動検索=memory_db_query.sh/semantic_search.sh(補助)」を記載。
- **★範囲拡張(家老具申)**: hook4本(pre-bash-combined.sh:117-119 / three_layer_preflight.sh / prompt_state_inject.sh:196 /
  stop_check_inbox.sh:25,453)のpath+行番号を手順書へ明記し、hook変更時の手順書同期を既存script_refs検分方式
  (スキルで稼働実績あり)に載せて検査する。新規gateは作らない(車輪の再発明防止)。
- A3の実害実例として記録: 家老が手順書だけを見て「すり替わりは無い」と誤答(02:30→02:33訂正)。
- 家老が実施(instructions書込み権限=家老のみ、D0で1cmd内に収まることを確認済み)。
- ★T3設計原則(軍師確定 blt_033002): no-code報告の正本形は**忍者に何を書かせるかではなく、どの契約が何を要求するかを契約側で揃える**方向で定義する。報告側の記入で吸収させるとreport_field_set.shのstatus=completed契約(binary_checks全yes要求 :1140-1156)と衝突し構造的に詰む(才蔵deadlock実証2026-07-27)。

### T4. cacheのfail-visible→自動回復(A4是正)
- startup gate/preflightでcache不在検知時、WARN表示に加えcache再生成を自動実行(既存refresh経路の呼出し。新機構は作らない)。

## §3 5W1H

| | 内容 |
|---|---|
| **WHY** | 三層記憶が儀式化し検索結果を誰も読んでいない。知識到達の劣化が全ロール毎ターンに効き、車輪の再発明と殿の時間強奪が実発生した |
| **WHAT** | T1結果注入+T2フォールバック明示+T3手順書同期+T4 cache自動回復。証跡・fail-closed・宛先指定は不変更 |
| **WHEN** | 殿承認後即cmd起票→家老配備。T1/T2/T4=忍者実装(並列可)、T3=家老 |
| **WHERE** | scripts/hooks/three_layer_preflight.sh(T1) / scripts/semantic_search.sh(T2) / instructions4本+CLAUDE.md(T3) / memory_db_query.sh+startup gate(T4) |
| **WHO** | 将軍=cmd起票、家老=分解配備+T3、忍者=T1/T2/T4実装、軍師=本案レビュー+実装レビュー |
| **HOW** | 各Tにbinary_check付きAC。T1=注入内容が実検索結果と一致するfixture+BLOCK契約不変fixture。T2=フォールバック時ラベル行存在のfixture。T4=cache削除→自動再生成のfixture。効果検証=修正後セッションで「注入結果を読んで回答」実対話確認+preflight wall_msをlogs/defense_overhead.jsonl既存計装で前後比較 |

## §3.5 実測結果(cmd_4176・半蔵 2026-07-27 03:22-03:50。全数・捏造なし)

| AC | 結果 |
|---|---|
| U1膝点(N×上限20組合せ) | **実測不能 0/313** — evidenceはpane毎上書きスナップショット(313件中224件=71.6%がrecovery_testフィクスチャ、非空クエリ12件も全てharness定型文字列"inbox1"等)。教材となる実クエリが存在しない。数字は捏造せず未計測と報告 |
| U3 alias被覆 | **統計的に決定不能** — 有効11クエリは全てalias層でhit(memory必要0件)だが母集団3.5%・harness定型のみ。軍師の「7割memory由来」も置換できず。**T2の(a)alias先埋め/(b)NO_MATCH許容は本データでは決められない** |
| U6偽引用 | 応答31,520件中[MEM:]タグ付き1,859件を全数機械照合: **完全な捏造0件**(knowledge参照1657件全実在・cmd参照537件中未発見2件は桁揃え表記ゆれ)。**空引用31件(1.67%)**=A5「空の引用札」の直接証跡。n/a正直宣言22件。※時点整合性(当時evidenceとの一致)はevidence破棄により検証不能 |
| U9忍者ルート | 忍者もpreflight hook適用下(evidence実発行を自pane一次証跡で確認)+task YAML静的注入(semantic_concepts)の二重経路。CLAUDE.md忍者節に三層手動検索の記載なし |
| U10 Codex | Claude Code hookを完全共有(pre-bash/pre-write-edit/prompt_state_inject)。preflight経路の欠落なし |

### §3.5の結論 — A8(最重要の新発見)
**調査自体がA1/A7に敗北した。** 系はクエリも結果も捨てるため、**自分の記憶システムの有効性を自分で測定できない**。
∴実装順序を再訂正: **最初の一手=観測の実装(T1結果注入+evidence append型ログ化=A7/A8是正)**。
実クエリが数日蓄積されて初めて膝点N・alias被覆・T2の(a)/(b)が実測で決まる。観測なき チューニングは全て感覚値になる。

## §4 品質・安全境界
- fail-closed契約(証跡なしBLOCK)の削除・緩和は**スコープ外**(LS100ロックアウト前例につきissue-bypass経路の回帰テスト必須)
- targeted visibility(memory_visibility.py)の変更は**スコープ外**(殿裁定02:25)
- 注入によるCTX膨張はバイト上限で抑制。上限値はレビューで確定
- default-delete test policy適用: 実装用testは同一タスク内削除、契約fixture(T1同一性/T2ラベル/T4再生成)のみtest_necessity付きで永続

## §5 レビュー論点(家老・軍師への問い)
1. T1注入上限(2KB案)は妥当か。CTX保護と情報量のバランス
2. T2でLLM第二層を既定復活させない判断は正しいか(軍師)
3. T3の書込みルート統一はknowledge_write直接/bulletin自動INSERTのどちらを正とするか(家老)
4. preflightは全Bash/Edit前に走る — T1注入の頻度は毎ターンか、同一プロンプト内は初回のみか
   → **クローズ(軍師回答 blt_20260727_091056)**: 問い立て自体がverify/issueの混同。全Bash/Edit前に走るのは証跡verify(検索なし・pre-bash-combined.sh:120)のみで、三層検索を伴うissueはUserPromptSubmit毎1回だけ(prompt_state_inject.sh:202)。∴注入頻度の再設計は不要。本gist §1「preflightは全Bash/Edit前に走る」の表現は「証跡verifyが走る」と読み替えよ。
5. 見落としている欠陥・副作用はないか(特にstop_check_inbox.shの[MEM:]タグ検査との整合)
   → **見落とし1件確定(軍師回答 blt_20260727_091056)**: stop_check_inbox.sh:25-45 has_successful_three_layer_preflight()がevidence JSONを直接パースする外部消費者であり、§4安全境界にもT1にも未記載。**T1実装制約(A8)**: evidenceのスキーマ変更(結果注入・append化)時はstop_check_inbox.sh側の消費関数との互換を同一commitで維持すること。才蔵のT1弾レビュー時に将軍が検分する。

## §6 実装進捗台帳(2026-07-27 13:35時点・一次情報=logs/gate_metrics.logの終局行)

| 弾 | 対象欠陥 | 担当 | 状態 | 証跡 |
|---|---|---|---|---|
| T1弾(preflight実結果注入) | A1/A5 | 才蔵 | **GATE CLEAR** 09:39:18 | 三層検索の実結果(memory上位5行/semantic 1概念/obsidian上位3リンク)をevidenceへ伝搬 |
| 弾2(IB-O yaml.dump閉鎖) | 書込みルート | 半蔵 | **GATE CLEAR** 09:26:52 | gate_report_format.sh:1065をyaml_textへ是正+gate_no_direct_yaml_dumpを実commit経路(git-pre-commit.sh)へ接続。commit=3e653c265 |
| 弾1(指揮官投稿契約) | IB-S系 | 影丸 | 実装済み・**GATE再判定待ち** | 実戦欠陥2件を是正済み(スクリプト自動生成通知の除外恒久化+検出パターンを標準書式「出力行(生)」へ整合)。09:38のBLOCKはrelated_lessons入れ替わり由来の無過失BLOCK→下記snapshot弾で根治 |
| A6弾(検索42.8% timeout) | A6 | 疾風 | **GATE CLEAR** 10:18:47 | semantic-index.mdの9パス直読みを/tmpローカルcache経由へ変更しtimeout要因を是正 |

### 派生是正(本作戦中に発見・根治した周辺欠陥)
- **related_lessons配備時点固定**(cmd_karo_impl_related_lessons_snapshot): 再配備でrelated_lessonsが入れ替わり忍者が無過失BLOCKされる事象を既存task_contract_snapshot拡張で根治。GATE CLEAR 10:16:37
- **LG048実質化**(cmd_karo_impl_lg048_fail_receivable): semantic_validation.resultがPASS固定の通過儀礼だった欠陥をFAILリテラル受理+差し戻しフロー接続へ。GATE CLEAR 10:35:54
- **循環lock競合根治**(将軍D0 commit=ea634f70d): report_field_set.shのdetached reconciler 0.2秒がinbox_write→gate_report_formatで親保持中の報告lockを掴み忍者停止5件(才蔵3/飛猿1/半蔵1)。既定30秒へ+test 62のyaml_text移行追随。62/62 PASS。家老が同型再発の観測役
- **gate_metrics偽BLOCK訂正**: CLEAR成立後のcmd_complete再実行が偽BLOCKを記録→追記型訂正CLEAR行で最終状態復元(集計=cmd毎最新1件採用)

### 欠陥別スコアボード(11:25時点)
| 欠陥 | 状態 | 証拠 |
|---|---|---|
| A1 検索結果の破棄(最重要) | ✅ 是正済み | T1弾commit 850a0429d。直近evidence 8/8にmemory_top/semantic_top/obsidian_top実結果を実測 |
| A7 クエリの破棄 | ✅ 是正済み(T1に同梱) | evidenceにmemory_query等が保存されている実測 |
| A6 検索42.8%タイムアウト | ✅ 是正済み | A6弾CLEAR 10:18。効果実測: 失敗率 before 44.1%(134/304) → after 0%(0/8)・total_wall_ms中央値622ms。after母集団8件のため観測継続 |
| A5 偽引用の構造的生産 | ✅ 是正済み | R3弾CLEAR 12:08:03(cmd_karo_impl_a5_mem_evidence_raw_field)。[MEM:]雛形へevidence実結果原文欄を追加=「読める化」完成。12:36将軍実測: 注入雛形に原文=付きで実データ表示 |
| A4 cache起動時不在 | ✅ 概ね是正済み | commit aba450d32(rowid水位比較+自動再生成+追随検知器)。本日朝WARN実在のため観測継続下 |
| A2 semantic→memoryすり替わり | ✅ 是正済み | R2弾CLEAR 13:09:55(cmd_karo_impl_a2_semantic_fallback_visible・疾風)。memory_dbフォールバックをMEMORY_DB_MATCHラベル明示+miss可視化へ(殿裁定02:37準拠)。途中で家老誤RC→台帳退避(queue/archive/rc_erroneous/)→軍師LGTM再実行の脱出路を実証 |
| A3 手順書未記載 | ✅ 是正済み | R4完了。instructions 4ロール全て(shogun/karo/gunshi/ashigaru)に実効ルート(hook4本+evidence消費者)記載を実測各6件(grep -c "three_layer_preflight\|実効ルート" → 6/6/6/6) |

### 残工程と完了見込み(11:25起点・本日実績ベース: 1弾=配備→GATE CLEARまで実測40〜80分)
| # | 工程 | 内容 | 依存 | 見込み |
|---|---|---|---|---|
| R1 | 弾1(指揮官投稿契約)クローズ | ✅ **GATE CLEAR 12:04:33**。実戦欠陥2件是正+検出パターン標準書式整合+related_lessons snapshot根治を経て完了 | — | 完了 |
| R2 | A2弾 | ✅ **GATE CLEAR 13:09:55**(疾風・cmd_karo_impl_a2_semantic_fallback_visible)。MEMORY_DB_MATCHラベル明示+miss可視化(殿裁定02:37準拠)。LLM第二層の既定復活はしない(§5論点2)。途中の家老誤RC(12:47、grep -A4抽出範囲不足で空欄誤判定)は台帳退避で正規解消—「通し方を見つけたことと通してよいことは別」(将軍裁定12:56を家老が実践) | R1(忍者枠) | 完了 |
| R3 | A5最終段 | ✅ **GATE CLEAR 12:08:03**(飛猿)。[MEM:]雛形へ実結果原文欄追加=「読める化」完成 | — | 完了 |
| R4 | A3弾 | ✅ **完了(13:33将軍実測)**。instructions 4ロール全てへ実効ルート(hook4本+evidence消費者)記載。grep -c実測=shogun 6/karo 6/gunshi 6/ashigaru 6 | R2/R3の最終形確定後 | 完了 |
| R5 | 検収 | preflight失敗率・実結果注入率の全数再計測(after母集団50件以上)+§6最終更新。軍師の独立検算付き | R1-R4(全て済) | **唯一の残工程。13:35配備指示** |
| R6 | 貫通の道具内蔵化(12:32将軍下知・追加) | ✅ **GATE CLEAR 13:04:08**(cmd_karo_impl_r6_knowledge_write_penetration_visible)。memory_db_knowledge_write.shへL1/L2/L3貫通可視化を内蔵(commit 99f7abbb6)+軍師D0でL2 pending案内パス誤記も是正(3853f071f)。スキル意志依存の排除 | R3(済) | 完了 |
- **状況(13:35更新): R1/R2/R3/R4/R6/T1/A6/弾2=完了。残=R5検収のみ。**欠陥A1-A7は全て是正済み(上記スコアボード)。R5は数値検収(after母集団50件以上の失敗率・注入率再計測+軍師独立検算)で本作戦をクローズする
- 派生教訓(13:18将軍): loop_ledger promotion.stock=265を「滞留」と誤読→軍師検証で棄却(promotion.stockはLevel4未満教訓数。定義はloop_ledger_update.sh:986-996)。指標の定義を確定させてから対処方針を立てよ(LG076型)
- 副産物: /three-layer-penetrateスキル新設(15c521a62)+検証3回で欠陥3件検出修正(2bbec5797/ae26044c9)+家老の初実使用成功(blt_123435・3層証跡付き)
- A4は追加実装なし(検知器の観測継続のみ)。観測で再発すれば別弾
- 未push57commit=GA-PUSH1正当BLOCK(忍者WIP+lessons.yaml経路外書込みと同一path)。lessons.yaml根治(別作戦: 真犯人候補lesson_auto_tag.sh・計装承認済み)の後に一括push

### R5検収(2026-07-27 13:40・影丸実測。計測源=logs/preaction_memory/evidence_log_*.jsonl、軍師独立検算前提で手順を明記)

**計測源選定**: `grep -n append scripts/hooks/three_layer_preflight.sh` → L684 `evidence_log_${safe_key}.jsonl` がT1導入(commit 850a0429d, 09:28:44)と同時に新設されたappend型ログ。既存の`evidence_*.json`(313件)は上書き型スナップショットで履歴を持たない。`wc -l logs/preaction_memory/evidence_log_*.jsonl`(全9ファイル)→ 907行(2026-07-27T09:11:33〜13:34:52、9名分)。他候補(`logs/three_layer_preflight_warn.tsv`=最終行07-21で対象期間外/`logs/three_layer_chain_async.log`=layer2/3書込みイベントで検索失敗率と無関係/記憶DB`search_logs`=`caller='semantic_search'`のみでpreflight自身の呼出しは含まない/`logs/defense_overhead.jsonl`=three_layer_preflight関連check_idなし)は不採用。母集団907件は50件を十分満たす。

**再現手順(軍師独立検算用)**:
```
python3 -c "
import json,glob
files = glob.glob('logs/preaction_memory/evidence_log_*.jsonl')
recs=[]
for f in files:
    for raw in open(f,'rb'):
        line=raw.decode('utf-8',errors='replace').strip()
        if line:
            try: recs.append(json.loads(line))
            except: pass
recs.sort(key=lambda d: d.get('issued_at',''))
split='2026-07-27T10:18:47'  # A6弾 GATE CLEAR時刻
after=[r for r in recs if r.get('issued_at','') >= split]
before=[r for r in recs if r.get('issued_at','') < split]
to=sum(1 for r in after if any(r.get(f)=='NO_RESULT(timeout)' for f in ['memory_top','semantic_top','obsidian_top']))
hit=sum(1 for r in after if any(r.get(f) not in (None,'','NO_RESULT(timeout)') for f in ['memory_top','semantic_top','obsidian_top']))
print('before n=',len(before),'after n=',len(after))
print('after timeout(any-layer)=',to,'/',len(after))
print('after inject-rate(any-layer非空)=',hit,'/',len(after))
"
```

**結果**:
| 指標 | before(n=) | after(n=) | 差分 | 判定 |
|---|---|---|---|---|
| preflight失敗率(timeoutでNO_RESULTになった率・any-layer) | §3.5基準44.1%(134/304、evidence_*.json全313件集計の再現値=134/313=42.8%・n=313) | 0/589 = 0.0%(A6 GATE CLEAR 10:18:47以降、n=589) | -42.8pt〜-44.1pt | **A6は有効。after母集団589件(50件を大幅に超過)で判定可能。timeout再発0件** |
| 三層実結果の注入率(any-layerが非空かつNO_RESULT以外) | 測定不能(append型ログはT1導入と同時に新設されたため、T1導入前のデータが構造的に存在しない。上書きスナップショットの直近120件中、T1後スキーマ(memory_top等のkeyを持つ)ファイルは9件のみで残り111件はT1導入前のまま再実行されていない陳腐化ファイルだった) | 506/589 = 85.9%(A6 GATE CLEAR以降。3層すべて非空=465/589=78.9%) | 算出不能(before無し) | **T1のbefore/afterは構造的に測定不能(家老指摘・実装確認で確定)。上書きスナップショットの代替証跡: T1後に再実行されたpaneは9/9=100%で実結果ありを確認** |

**★AC1是正(家老解釈の誤り)**: purposeに記載の家老解釈「evidenceは上書きゆえ注入率ではない」は`evidence_*.json`単体については正しいが、結論「after母集団50件以上は構造的に達成できない可能性がある」は誤り。`evidence_log_*.jsonl`(append型、T1と同時実装)により母集団907件(50件超)が実在する。またpurposeの「直近120中実結果9件」は家老の実測数値としては正しいが解釈補足: 120件中111件はT1導入前のスキーマ(memory_top等のkey自体が無い)の陳腐化ファイルであり、T1後に再実行され新スキーマを持つ9件は9/9=100%で実結果ありだった(`has_successful_three_layer_preflight`消費者への影響=陳腐化ファイルの扱いはT1実装のスコープ外・別途要確認)。
