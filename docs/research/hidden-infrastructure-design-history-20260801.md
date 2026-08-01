# hidden-infra修正設計書 — 履歴・監査経緯アーカイブ (2026-08-01分離)

本ファイルは正本 `hidden-infrastructure-gate-hook-remediation-design-20260730.md` (v5.0再構築)から
分離した歴史記録である。**現在の契約・現在地は正本を読め。** ここは経緯の追体験・監査証跡専用。

---

# A. 進捗更新・殿下問監査の経緯 (旧§-2.0/-2.2/-2.3/-2.1)

### §-2.0 進捗更新 2026-08-01 03:05 (将軍検分)

01:00-03:00のarchive再承認レーン(cmd_4200完遂条件の前段)が5往復のRC後に構造収束した。一次証跡は監査正本`docs/research/archive-review-reapproval-path-audit-20260801.md`と以下のcommit群。

| 成果 | commit | 設計へのfindings写像 | 実測 |
|---|---|---|---|
| canonical report identity allowlist (resolver反転) | `a71753ed7` `f24fa608f` | **R06 exact_correlation の review path 実装**。symlink/alias/traversal/nested/別cmd payloadの全族を1契約でfail-close | corpus 13/13 PASS、FP 0/13、FN 0/13、6段非対称0 |
| review/report verdict軸分離 (reviewer FAIL bundle) | `9c5a12b36` `f0019d489` `c8337adf4` | **N05 (receipt=rc中心の欠陥)** のreview層是正。8セルverdict matrix明文化 | failed/FAIL報告を書換えずFAIL bundle正規生成 |
| run_tests task Python dispatch + receipt集計 | `6c3392d74` `d9c02f170` | **R09/R13隣接** (runner inventory/receipt)。suffix dispatch+Python receipt統合 | Python receipt 21/21 rc0、contract 55/55、SKIP 0 |
| gate予測精度の計測粒度是正 | `3ee176a0c` | LS096型粒度バグ根治。cmd単位最終verdictへ統一 | final-cmd accuracy 9/9=100%、同型アラート閉鎖 |
| archive notify対称化+6段監査表 | `667f75b13` `10d349dc4` `ad03ca655` | 受付≠完了の6段identity連続性を監査表で固定 | generate/review/notify/SG7/marker/complete 全段対称 |

cmd_4200再承認の終端実勢: 軍師LGTM 6/6・家老ACCEPT 6/6・notify marker 6/6・`archive.done` 1/1。wrapper Step8相当のcompletion checkpointは `sg7_consume` から `inbox_archive` まで8/8、ntfy delivery receiptは同一completion generationで1件、重複副作用0。

### §-2.2 方向性再検証 (殿下問2026-08-01 03:02への回答・将軍判定)

**判定: 家老の方向性は実質正しい。** 初動はケース別deny増設の各論パッチ(4巡FAIL)だったが、全数監査→allowlist反転→verdict軸分離へ転換後は、本設計の根因治療(identity曖昧→typed exact identity、受付=完了→terminal receipt)を**Wave順序に先行して実運用経路へ適用した**形になっており、方向は設計と同一線上にある。ただしgovernance欠陥3点を検出:

| # | 欠陥 | 是正 |
|---|---|---|
| G1 | manifest未更新: `current_phase=WAVE_1A_IDENTITY`のまま、archive再承認レーンの成果がfindings receiptへ未写像。後日の二重実装(SUPERSEDED相当の再着手)リスク | 上表の写像をmanifestへreceipt登録し、R06 review path部分をpartial closure記録 |
| G2 | R01の非terminal中断: 飛猿がR01(lock identity, `6f4e4b77b`敵対contract済・task-scope test実行中)からallowlist taskへ先取された。旧§5.0「先行terminal receiptなしに後続を開始しない」の逸脱(当時基準)。※v3.9の§5.0改訂(実競合unitのみ直列)により先取自体は今後正規となるが、中断状態のmanifest記録義務は不変 | R01を再開しterminal化するか、中断理由と再開条件をmanifestへ明記(黙殺しない)→ 03:27 reconcileでterminal化済み |
| G3 | Wave 2A/3隣接の修正が順序外で先行(運用強制ゆえ許容)だが、記録なしでは§5.5/§5.7実装時に競合する | 該当Waveの設計節へ「先行実装済み・残作業」の差分を反映(§5.5/§5.7実装時にreceipt照合) |

### §-2.3 超速回転・単純性監査 (殿下問2026-08-01 03:34)

**判定: 原則は書かれているが、現実装は単純ではない。設計意図PASS / 実装単純性FAIL。** §5.10は「途中はfocused test、全量testは最終固定SHAで1回」と正しく定める。一方、進捗manifest・report freshness・共有ledger・Wave終端receiptを途中laneにも重ねた結果、成果成立後の整形・同期が実作業を止めている。安全防御ではなく回転税であり、設計どおりに削減する。

| 実測 | 値 | 判定 |
|---|---:|---|
| 公開Gist / local設計(監査前) / canonical manifest | 689 / 693 / 331行 | 設計+進行台帳だけで1,024行。検索・同期面が多い |
| durable foundation本体+wrapper+contract test | 788+106+421=1,315行 | caller移行前の共通基盤として大きい |
| 関連commit | 40 | 反復の多くがreceipt・review・governance同期 |
| Gist revision(監査時) | 15 | 監査時は公開Gistが親AC 2/3・R01非terminal、localが3/3 ACCEPTED。03:37の将軍同期でrevision 16となり乖離解消。現行正本ではR01 ACCEPTEDへ同期済み。同期面の回転税は残る |
| 同一invalid continuation | 24 cycle / durable action 0 | dedupe不在で同じ防御が回転を消費 |
| blocker通知 | valid blocker 1件 / 家老通知0件 | freshness早期returnが停止理由の報告を隠した |
| 完了後shared ledger更新 | 対象commit不変 / 再gate BLOCK | 他agent後着差分を本人成果の失敗として扱った |

**最小解決原則:** 新しいgate・receipt・状態面を足して単純性を「強制」しない。既存面を統合し、途中laneを次の3操作へ縮める。

1. `event append`: `{subject, generation, state, reason_fingerprint, timestamp}`を1回追記する。
2. `focused binary check`: 変更境界だけを即時yes/no計測し、PASSなら次tryへ進む。途中report、共有tree freshness、全量receipt matrixを要求しない。
3. `final reconcile`: 外部副作用・不可逆操作・release/親cmd終端の直前だけ、固定SHAで全receipt・全量test・rollbackを1回照合する。

**採用境界:** 外部副作用、不可逆操作、最終releaseはfail-closeを維持する。可逆な隔離tryと同一成果の再提出はfail-fastではなく継続優先。新しい共通抽象は、異なるcaller 2系統以上の再現があり、旧path/field/手順の純減を同一変更で示す場合だけ採用する。追加だけで旧経路を消さない変更はNO-CHANGEとする。

**直ちに変える進め方:** Wave全体の一律直列を廃し、実際に同一file・同一side effect・同一serialization keyを共有するunitだけ直列化する。独立unitは並列可。後続Wave開始条件は先行Waveの文書終端ではなく、依存する実行不変量のfocused PASSとする。厳密な全体終端はFinal checkpointの1回に集約する。

### §-2.1 Foundation敵対検証の修正前→修正後

| 不変量 | 修正前 | 修正後 |
|---|---:|---:|
| 空artifact/ledgerの偽terminal | rc 0 | fail-close |
| subject path traversal root escape | 1 | 0 |
| symlink state-dir root escape | 1 | 0 |
| ack-loss retryのeffect count | 2 | 1（`outcome_unknown`） |
| hard process crash後のnaive retry | rc 0、effect 2 | rc 10、effect 1、provider reconcile限定 |
| test内の明示的破壊コマンド | 3 | 0 |
| focused contract | 未確定 | 17/17 PASS、SKIP 0 |


# B. 旧系が成り立っていた因果と保存優先の理由 (旧§0.0)

### §0.0 旧系が成り立っていた因果と、保存を優先する理由

新しい抽象化は、旧系の結論だけを上書きしない。まず「なぜその仕組みで長期運用が成立したか」を歴史・現物・実績から復元する。

| 因果の段階 | immutable evidence (`commit:path:line`; blob) | 観測期間・生値 | 成り立っていた理由 | 今回保存する不変量 |
|---|---|---|---|---|
| Claude主編成の成立 | `462ea2ee31:context/infrastructure.md:177`; blob `4c8384063ab0f59d4ea10218487f2e1297bb4fd5` | 2026-03-17編成確定。将軍1+家老1+軍師1+忍者6=9/9 Opus 4.6 | 役割・復帰・hook・報告の運用がClaude lifecycle前提で蓄積した | Claudeをprimaryとし、event・prompt・reset・inbox・report・completeの使い勝手を不変とする |
| native hookが優先された因果 | `1ec43f3b9:.claude/settings.json:3-86`; blobs settings=`70dcc0f17aee6285b145cc2f238c7e255d4b6e09`, pre=`65f3b29b6d297a53b21718e6ef216e540e8839c3`, post=`8d98bf268e093301f33c882ff34c89bd49620996` | 2026-06-05 dispatcher統合。6 event typeをnative lifecycle境界で維持しつつ、複数hook entryを1 dispatcherへ集約 | 早期検出とadditional contextを正規ターン境界で与え、常時polling税と順序競合を避けた | Claude native hookを等価性未証明のdaemon/polling/wrapperで置換しない |
| CLI外共通層が必要になった因果 | `e401d29ade04bc997fc519eb52b2793b03541f39:docs/research/multi-cli-hook-event-commonization-design_20260602.md:7-15,26-33,71-77`; blob `a97cc89b2f11f2722668a6cea192f97a607ebcd4` | 2026-06-02〜06-24。Claude/Codex hook差、Stop再生成loop、settings/pane/process/watcher/coverageの5点不一致を観測 | 同event名でも意味論が異なり、Claude実装の単純移植はCodexを壊した | 共通化は「同じhook実装」ではなく「同じ軍規event」。CLIごとのcapability adapterを維持する |
| 環境強制がモデルより優先された因果 | `53d326ad5c:context/training-cycle.md:733,750,752-765`; blob `7583b27e06c73a7a10a5334c0fad455385647321` | 2026-04-02 R7→R8。Opus 2/2→2/2、GPT 0/2→2/2、Sonnet 1/2→0/2 | テンプレートでGPTは改善したがSonnetは失敗箇所が移り、モデル固有回避は他者に逆効果を持った | 安全性はモデル非依存のgate/template/stateへ置くが、CLI nativeの有利な境界は消さない |
| Codex補完が許された因果 | `cc1d6a80534fe37f0cbd15dba59e578a73297bbf:.codex/hooks.json:1-73`; blob `726b9ae4859b7f958b2b08c6ebf15cf193372592` | 2026-07-15初回追跡。Codex側はPreToolUse/SessionStart/UserPromptSubmit/PostToolUseの能力に限定し、Claude Stop blockを含めない | Claude主系を変更せず、Codex一時配置の穴だけをCLI能力に応じて埋めた | Codexの便益は補完範囲に限定し、Claude主系へ運用税・遅延・手順増を逆流させない |

したがって採否順序は次で固定する。

1. 旧Claude主系の導入理由・事故回避・成功実績を対象fileの`git log` / `git blame`、教訓、運用文書から復元する。
2. 変更がその因果辺のどれを切るかを、`old_reason -> changed_boundary -> user/runtime effect`で3行記録する。
3. 切る因果辺が0、または同一fixtureで等価性と純便益を証明した場合だけ採用する。
4. Claudeを含む任意のsupport tupleで1件でも使い勝手・latency・安全性・復帰性が悪化する、または純便益が未証明なら**NO-CHANGE CLOSE**とする。既にcanaryを入れた場合は保存したold-pathへrollbackする。
5. 「CodexでPASSした」「共通化できる」「新しい方が整っている」は単独で採用根拠にならない。旧系の成立因果を保存した上で、全対象に純便益があることを要する。

1. identityを`subject_id + generation + phase + terminal_receipt`へ統一する。
2. 複数file mutationを原子的と称さず、WALとstartup reconcilerで旧/新いずれかへ収束させる。
3. 受付・親exit・markerを完了とみなさず、artifact hashとside-effect ledgerを持つterminal receiptだけを完了とする。
4. retry可能な外部副作用をtransactional outboxとidempotency keyで収束させる。
5. 共通primitiveを一括置換せず、read-only shadowとcaller単位canaryを通す。
6. 品質だけでなくwall/lock-wait/recoveryを測定し、スループット退行を停止条件にする。


# C. As-Is 現状5W1H・監査方法・canonical findings 17件 (旧§1)

## §1 As-Is — 現状5W1H

### §1.1 As-Is 5W1H

| 軸 | 現状 |
|---|---|
| Why | 局所hotfixがraceを消しても、identity・owner・completion・SSOTの分裂が別callerで再発する |
| What | marker、文字列grep、独自lock、親process rc、複数file copyを各scriptが独自解釈する |
| Who | deploy/review/complete/watcher/test/semanticの各callerが状態ownerを部分的に持つ |
| When | crash、respawn、並行writer、retry、stale cache、prompt遷移の境界で破綻する |
| Where | `scripts/auto_deploy_next.sh`、`deploy_task.sh`、`cmd_complete_gate.sh`、`review_approval.sh`、`run_tests.sh`、`inbox_watcher.sh`、semantic/hook群 |
| How | denylist、部分一致、marker先行公開、非durable async tail、分裂したCI inventoryで進行する |

### §1.2 監査方法

独立6レーンは兄弟報告を参照せず、固定commitと自作probeで検証した。

| lane | 対象 | 問い |
|---|---|---|
| A | gate / hook | FP、FN、fail-open、exit code、責務重複 |
| B | inbox / watcher / lock | Lost Update、重複配送、prompt誤入力、無駄待機 |
| C | deploy / lifecycle | ghost、stale、再配備、auto-clear、状態乖離 |
| D | report / review / complete | 偽CLEAR、永久BLOCK、lock競合、非同期tail |
| E | tests / CI / metrics | focused漏れ、SKIP隠蔽、local/CI非対称、fixture汚染 |
| F | insight / lesson / memory | 未resolve、誤dedupe、三層未貫通、観測盲点 |

各findingは再現yes/no、FP/FN分子分母、fail-open、変更file/line、波及先、focused test、Level 5防御、rollback方式を記録する。

### §1.3 As-Is baseline

| 指標 | 実測 |
|---|---:|
| 直近2,000行のgate BLOCK | 166 |
| `review_two_phase_pending` | 77（46.4%） |
| `context_freshness_own_commit_unreflected` | 35（21.1%） |
| `sg7_bundle_missing_or_invalid` | 14（8.4%） |
| CI関連 | 17（10.2%） |
| その他 | 23（13.9%） |
| gate scripts | 56 |
| test files | 205 |
| gate名と直接一致testなし | 33 |
| pending insights（監査時） | 30 |

名称不一致は未テストの証明ではない。caller経由の間接coverageを追跡してから判定する。

### §1.4 Canonical findings（17件）

| ID | Sev | As-Is / evidence | To-Be primitive・invariant |
|---|---|---|---|
| R01 | CRITICAL | appendとmark-readのlock pathが別。Lost Update 1/1 | `lock_identity`; 同一inboxは1 lock identity |
| R03 | HIGH | source/target双方active 2/2 | `owner_transaction`; executable owner `<=1` |
| R04 | HIGH | deploy rc=7後もghost assigned 2/2 | `deploy_receipt`; terminalまでrollback armed |
| R05 | HIGH | `in_progress`をauto-deploy再選択 1/1 | `deploy_selector`; pending/idle allowlist |
| R06 | HIGH | `cmd_12`が`cmd_123` CLEARを誤認 1/1 | `exact_correlation`; typed完全一致 |
| R07 | HIGH | dispatch即死後もmarker公開、retry不能 | `durable_dispatch`; terminal receipt後だけmarker |
| R08 | HIGH | 親exit0後のtail失敗が不可視 | `completion_job`; queuedとcompletedを分離 |
| R09 | HIGH | 永続contract 177中97がpush CI未所属。別parserと+2差 | `contract_inventory`; canonical CI membership N/N |
| R10 | HIGH | terminal rc publicationとidentityが競合 | `immutable_rc_receipt`; 1 identity 1 rc |
| R11 | HIGH | unsigned manual aliasがpolicy前に自動昇格 | `provenance_policy`; signed curatedだけ即時昇格 |
| R13 | MEDIUM | dirty tracked sourceでも古いcache PASSを再利用可能 | `cache_identity`; worktree hashをkeyへ含める |
| R14 | MEDIUM | hook branch到達不能、Codex単体rc=1 | `hook_owner`; 1 reachable owner、BLOCK exit=2 |
| R15 | MEDIUM | artifact無変更でもinsightをresolved化 | `insight_state`; resolvedはartifact receipt必須 |
| V01 | HIGH | insight同時writeは1/2 FAIL、隔離1/1 PASS | `insight_writer`; atomic write、lost update 0 |
| V02 | HIGH | nudge表示と実体のcorrelation欠落 | `delivery_trace`; eventごとに1 durable trace |
| V03 | CRITICAL候補 | auto-deploy外lockと内lockが別domain | `lock_domain`; false success/lost update 0 |
| V04 | HIGH | idle確認後からsend直前にprompt再確認なし | `prompt_safe_send`; confirmation送信0/30、idle 30/30 |

Wave 0結果: `selected=17`、`discovered=17`、`executed=17`、`OPEN_CONFIRMED=13`、`SUPERSEDED_WITH_EVIDENCE=4`、`NEEDS_NEW_PROBE=0`。詳細はmanifest/receiptを読め。推測するな。

### §1.5 旧設計自身の欠陥

| ID | As-Is gap | To-Be |
|---|---|---|
| N01 | 複数file変更を「1 transaction」と誤称 | WAL + generation + step receipt + reconciler |
| N02 | crash後rollback owner不在 | startup reconcilerを唯一owner化 |
| N03 | retry副作用の重複境界なし | idempotency key + side-effect ledger |
| N04 | 共通primitive一括置換が新SPOF | shadow→canary→段階移行→撤去 |
| N05 | receiptがrc中心 | artifact hash + terminal phase + side-effect IDs |
| N06 | FP/FN母集団未定義 | 正例・反例・境界例の固定corpus |
| N07 | probabilistic raceへ正常反復だけ | mutation point全数のfault matrix |
| N08 | 性能退行の停止条件なし | wall/lock wait/recovery budget |
| N09 | severity語彙が混在 | CRITICAL/HIGH/MEDIUMへ統一 |
| N10 | remote ahead/behindが共有作業依存 | fixed SHA isolated checkpoint限定 |


# D. Gap — なぜ現状の延長では直らないか (旧§2)

## §2 Gap — なぜ現状の延長では直らないか

### §2.1 4共通根因

| 根因 | As-Is | 失敗 | To-Be |
|---|---|---|---|
| identity曖昧 | 部分一致、独自lock、singleflight別identity | 誤相関・Lost Update | typed subject + generation + canonical lock |
| owner移転非原子 | source/target、review/dispatch、parent/tailを別更新 | 二重owner・ghost | WAL + fenced active pointer + reconciler |
| 受付=完了 | marker、親rc0、queuedをterminal扱い | 偽完了・retry不能 | terminal receipt + artifact + side-effect ledger |
| SSOT分裂 | contract/CI、matcher/handler、manual/promotionが別 | 未実行・到達不能・誤昇格 | generated inventory + single owner + provenance type |

### §2.2 失敗連鎖

```text
曖昧identity
  → writer/readerが別状態を見る
  → markerまたはrcだけが先にterminal化
  → retryが抑止される、または副作用が二重化
  → gate追加で局所検出
  → caller固有例外が増え、次のidentity分裂を作る
```

局所gate追加では連鎖を止めない。正しい入力・identity・ownerを事前生成するLevel 5へ移す。


# E. 軍師9反証 disposition (旧§7.1)

### §7.1 軍師9反証 disposition

| # | 決定 | 反映 | 二値検証 |
|---:|---|---|---|
| 1 | ACCEPTED | WAL/state contract | 必須field、atomicity、recovery、liveness全存在 |
| 2 | ACCEPTED | delivery contract | local/external分離、outbox 4状態、provider semantics全存在 |
| 3 | ACCEPTED | ownership contract | safety `<=1`とliveness `eventually 1`を分離 |
| 4 | ACCEPTED | shadow contract | live dual mutation禁止、canary/rollback/撤去条件全存在 |
| 5 | ACCEPTED | canonical manifest | canonical 17/17、legacy map 2/2、caller未分類0 |
| 6 | ACCEPTED | isolation contract | redirect/fake/preflight/real-state fingerprint全存在 |
| 7 | ACCEPTED | corpus contract | edge全数、selected/discovered/executedを分離 |
| 8 | ACCEPTED | performance contract | SHA/load/n/warm-cold/percentile/budget/rollback全存在 |
| 9 | ACCEPTED | dependency contract | foundation先行、2A/2B依存、serialization key全存在 |


# F. Review history全rounds (旧§9.1)

### §9.1 Review history

| round | reviewer | verdict | 主指摘・反映 |
|---:|---|---|---|
| 0 | 軍師 | LGTM | R10 wave、V03 scope、R02→V03、R12→V04 |
| 1 | 将軍 | REQUEST_CHANGES | Gate 0、WAL/reconciler、idempotency、shadow、fault、性能を追加 |
| 2 | 軍師 | REQUEST_CHANGES | 9反証をGate 0 contract/manifestへ9/9反映 |
| 3-8 | 軍師 | REQUEST_CHANGES | receipt hash、caller全数、phase、Gist自己参照を順次是正 |
| 9 | 軍師 | LGTM | Gate 0A contract確定 `9e5f8a382` |
| Wave0 RC1 | 軍師 | LGTM | 完全再実行command、正時刻、16/16 byte一致 `ce54074be` |
| Gate0B AC1 | 軍師 | LGTM | receipt 17/17、SHA/未来/未分類0 `f37a4365a` |
| Gate0B map | 軍師/家老 | ACCEPTED | OPEN 13/13、未割当/owner重複/循環/serialization欠落すべて0 `2e1090bb7` |
| Foundation RC1-5 | 軍師/家老 | REQUEST_CHANGES→LGTM | 空terminal、path traversal、symlink escape、ack-loss、hard-crash、test安全性を順次是正 |
| Foundation final | 家老 | ACCEPTED | 17/17 PASS、SKIP 0、hard-crash retry rc 10/effect 1 `4c89d38ca` |
| Wave1A R01 | 飛猿 | ACCEPTED | 敵対contract `6f4e4b77b`。post-commit 10反復もlost/duplicate/parse各0、task selector 287/287・SKIP 0、軍師LGTM・家老ACCEPT |
| Multi-runtime RC1 | 軍師 | REQUEST_CHANGES | Gist/local一致のみPASS。active-only Claude欠落、3 matrix未分離、resolver/manifest欠落、type/binary矛盾2、Codex Stop代替receipt欠落、OS runner証跡0、valid constraint欠落の6 finding |
| Multi-runtime RC1 response | 家老 | UPDATED v3.3 | support/configured/active分離、artifact/resolver、event代替receipt、OS support境界、valid constraint、AC16-20へ反映 |
| 殿訂正 | 殿/家老 | UPDATED v3.3 | 主編成=Claudeを明記。active Codexを主編成へ誤昇格しない。Claude primary 6-event非退行、配備変更0、AC21-22を追加 |
| 因果保存訂正 | 殿/家老 | UPDATED v3.4 | 旧Claude主系の成立因果、native hook優先理由、CLI adapterが必要になった事故、全tuple純便益未証明時NO-CHANGEを追加 |
| Multi-runtime RC2 | 軍師 | REQUEST_CHANGES | 前回6 findingは6/6解消。新規3件: Claude実manifestの6 cell縮小、rollback pointer不存在、post-commit pane birth 1/9のowner/cause未証明 |
| Multi-runtime RC2 response | 家老 | UPDATED v3.4 | 6 event type/12 top handler/dispatcher leaf N全数、baseline hash+restore script、mutation journal、AC21-25へ反映 |
| Multi-runtime RC3 | 軍師 | REQUEST_CHANGES | RC2契約3/3はPASS。新規3件: DrvFsのGit mode 100644/stat 0777二重性、settings writeと未journal mutation不可視、因果5 rowがmutable path参照でfixed commit/line 0/5 |
| Multi-runtime RC3 response | 家老 | UPDATED v3.5 | git_mode/fs_mode/fs_capability/mount分離、before/after state delta×journal N/N、因果5/5をcommit/path/line/blob/期間/生値で固定 |
| Claude Fable RC1 | 将軍 (Claude Fable 5) | REQUEST_CHANGES | Claude primary/NO-CHANGEはPASS。新規3件: resolved mismatch実数3を固定2が過少計数、Wave 4A合成がClaude Stop 5-chainへ逆流可能、Fable 5 row例欠落 |
| Claude Fable RC1 response | 家老 | UPDATED v3.5 | mismatchをresolved全agent N/N・終端0/Nへ変更、Claude native multi-handlerを合成対象外+NO-CHANGE優先、Fable configured例追加 |

