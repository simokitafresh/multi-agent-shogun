# 裁定待ち事項の実行順序表（家老作成 2026-07-27 06:25）

> 将軍指示（msg_20260727_062244）により作成。殿の裁定が下りた時点で、この順序で実行する。
> 調査フェーズ（殿裁定03:15）中は**起票と順序設計のみ**。実装は裁定後。

## §1 pre-push を塞いでいる件（将軍判断: 裁定まで許容継続）

**2026-07-27 06:28 更新: 4件 → 3件**（軍師が担当分を処理）

| # | path | 性質 | 正しい担当者 | 順序 | 状態 |
|---|---|---|---|---|---|
| 1 | `context/infrastructure.md` | 飛猿の教訓L1380がcontext索引へ**正常合流**（+2/-1） | **飛猿**（cmd_karo_cycle3_lessons_yaml_anomaly_probe の成果物） | ③ | 未処理 |
| 2 | ~~`context/semantic-map.md`~~ | 自動生成物（alias追記のみ・概念の追加削除なし） | 軍師 | — | ✅ **commit `da727b84f`（06:26）**。mtime 3秒静止を確認・complete=true・index残骸なし |
| 3 | `projects/dm-signal/lessons.yaml` | **家老が保全中**（index形式逸脱・書込み主体特定不能） | 裁定者の指示に従う | ② | 未処理 |
| 4 | `scripts/lib/review_approval.sh` | **家老が凍結中**（break除去・回帰151 test PASS済） | **家老** | ① | 未処理 |

**順序の根拠**: ①は他の是正の前提（no-code報告の通り道を開く）。②は保全解除の裁定が必要。③は担当者が自分のcmdとして打つ（家老が代打すると cmd↔commit 対応が崩れる＝IB-V型を再生産する）。

**軍師の検算で判明した補足**: `git status --porcelain` の生のdirtyは**33件**あるが、autogen除外regex（`^queue/|^logs/|lord-conversation-index` 等）と未pushcommitとの重複条件を適用すると**4件**に絞られる。家老が「4件」と述べたのはこの絞り込み後の数で、軍師の再計算と完全一致した。

**担当者による処理が機能した実例**: 軍師は「自分が過去2回commitした担当者だから」という理由で(2)を引き取った。家老が代打せず担当を明示したことで、**誰の変更か追える状態が保たれた**。

## §2 殿の裁定を要する7件（優先度順）

| 優先 | 件名 | 内容 | 状態 |
|---|---|---|---|
| 1 | **IB-O是正** | 穴3つ: (a)`gate_report_format.sh:1065` の `yaml.safe_dump`→`yaml_text`（置換1行＋import＋第4引数`PROJECT_ROOT`追加。出力等価は軍師がscratchpad複製で実証済み・`old==new`／round-trip等価）(b)`gate_no_direct_yaml_dump` をcommit経路へ接続 (c)同gateが**運用経路から一度も呼ばれていない**事実の是正 | **実装手順完全確定**。着手可否のみ |
| 2 | **実装停止下3commit** | 飛猿`6e2e931f2`(03:28)／小太郎`1799b6093`(03:35)／影丸`64af7d47f`(03:46)。将軍推奨=**追認**（速度改善・還流レーンは03:15凍結の主対象=三層実装とは別レーン、revert可能性は保持） | 追認かrevert |
| 3 | `review_approval.sh` 凍結解除 | break除去（commit判定ループが第1要素で打ち切られ2件目以降の`[commit不要]`宣言が評価されない）。回帰151 test PASS | 解除可否 |
| 4 | **IB-S** | enforcementのロール非対称。`gate_report_format.sh:11` の入力が`REPORT_PATH`=忍者報告YAMLのみ、`bulletin_write.sh`/`inbox_write.sh` に同種検査**0件**。∴忍者だけが範囲確認を毎回問われ指揮官は問われない | 埋め方（新gate追加を避け既存経路へ統合） |
| 5 | `lessons.yaml` 保全期限 | 書込み主体は**特定不能**（実行痕跡を残さない設計＝系の観測可能性の限界）。解除すれば再発しうる | いつまで保全するか |
| 6 | **L098の是正** | 現役index（894件）に `SVMF fallbackパスのtarget_dateフィルタリング不備 **(deprecated)**` がフラグ無しで載っている。機械は現役・人はdeprecatedと読む | フラグ付与かindex除外か |
| 7 | pushの塞ぎ期間 | 将軍判断で裁定まで許容継続。影響は静的（CI新規push無し・外部依存無し） | 裁定時に§1で一括解決 |

## §3 起票候補（裁定後の是正弾）

| 候補 | 根拠 | 規模 |
|---|---|---|
| `commit_hash` 自動補完 | `no_code_change_evidence` が埋まっているのに `commit_hash` が空で止まった実例**5件**（才蔵×2/疾風/半蔵/影丸/飛猿）。既存記入経路の補完であり新規gateではない | 小 |
| `sync_lessons` 書式往復の固定 | IB-Z。flow⇔block を往復し、flowの間だけ`lesson_health`が偽ALERTを出す（IB-X） | 中 |
| gate契約の集約 | IB-AC。同一報告が上流PASS／下流BLOCK（`gate_report_format_main.py:818`=OR条件／`cmd_complete_gate.sh:7491`=detail単独必須）。本日3例目 | 中 |
| `wait_reason` の尊重 | IB-Q。`stop_check_inbox.sh:630-652` の抑制条件が`wait_reason`を見ない**局所欠落**（他4ファイルには実装あり: `gate_shogun_startup.sh`12件/`ninja_monitor.sh`5件/`gate_karo_startup.sh`4件/`deploy_task.sh`2件） | 小 |
| telemetry begin/end のスキーマ区別 | IB-N。**276系列中1系列のみ**（`three_layer_health/refresh_window`・orphan begin 21件）。第4案「1系列を他275系列と同じ形式へ揃える」が最小 | 小 |
| `.meta` リーク | IB-E。`report_field_set.sh:65` 生成／`:295` 削除だが `:241`/`:253`/`:277` の早期exitでrm到達せず。**BLOCKされるほど残骸が増える** | 小 |
| `yaml_field_set` の2つの罠 | IB-K。(a)list添字指定不可 (b)boolean文字列化。家老の是正手段自体に罠 | 小 |
| GP-062 偽陽性 | IB-F。testファイル名にcmd_idが埋まり報告本文へ混入。B37族（テキストを状態と誤読）本日3例目 | 小 |
| ninja_monitor 再起動 | B16対処commit `eda8c2c4b`（karo_snapshotへcommander行追加）が**未反映**。稼働中daemonは旧コードを実行中 | 運用 |
| **報告テンプレートへ4規律の欄を追加** | **最優先**。4規律（集計コマンド／出力行の生貼付／1件の定義／網羅限界）は instructions 3ファイルへ接続済みだが、**report_field_set等のテンプレートに欄が無く書き忘れを防げない**＝構造的強制に至っていない。コード変更のため裁定要 | 中 |
| **`lessons_karo.yaml` の統合（35件上限の解消）** | 将軍裁定07:55により **/lesson-sort 在庫（必読lessons肥大57KBと同一弾）へ登録**。淘汰判断を伴うため裁定後。※4規律の教訓登録自体は「instructionsで機能が満たされている」としてクローズ承認済み | 中 |
| **家老→軍師の依頼漏れ検知** | IB-AG。**セッション跨ぎの滞留は注意力では原理的に拾えない**（才蔵の報告が13時間埋没し、上申5件が意思決定へ届かなかった）。軍師の走査コマンドは確立済み：`logs/gunshi_review_log.yaml` の review_type=report な cmd_id 集合を作り、`queue/reports/*_report_*.yaml` の status=completed かつ parent_cmd が集合に無いものを列挙 | 中 |
| **保全path・実装停止条件の自動注入** | IB-AD/IB-U。家老が「明示する」と3度表明して3度目に忘れた（指摘から80分で3回再発）。**家老の意志では埋まらないことが実証済み**。deploy_task が条件文を自動注入／保全中pathをtarget_pathに持つ弾を配備前に警告 | 中 |

## §4 サイクル2の判定（確定済み・8件すべてGATE CLEAR）

| ID | 判定 | 根拠 |
|---|---|---|
| B7 | 実在（真因はHEADで既修正） | 破損はmtime 19:37の残存物。**家老に修復経路なし**（`yaml_field_set.sh`はパース失敗でexit 1） |
| B19 | **非実在** | 60秒閾値でfind未検出 |
| B15 | 実在 | `sg7_bundle_missing` BLOCK 29件＋自タスクで実発火 |
| B16 | 条件付き実在 | 実体は**集約ビューの欠落**（対処commit `eda8c2c4b`・test 201/201 PASS） |
| B17 | 実在したが是正済み | — |
| B18 | 実在 | `review_bundle.py:224/302` で送信先karo固定・自動転送コード**grep 0件**。転記漏れで才蔵1時間17分停止 |
| B12/B13 | **部分的に対処済み** | 検査は`run_tests.sh:889-899`に実在するが**被覆57/957件=6%・downstream 0参照** |
| B1/B2 | 完了 | `refresh_window` median **31.49秒**（begin/end混在で0秒に見えていた）／真因=843MB DBの`sqlite backup()`が`shutil`比**7倍** |

## §5 本日の一般化（台帳28種の要約）

**(1) 「宣言」と「実体・接続」は別** — 5層で同型が発生
- gate: IB-S（入力が忍者報告のみ）/ IB-V（運用経路から呼ばれずtestのみ）/ IB-X（flow-styleをparseできず偽ALERT）
- 教訓Level: IB-Y（`gate_lesson_enforcement_level.sh` がenforcement文の**語**でLevel決定。還流在庫の**3割**が昇格候補でなかった）
- 台帳表記: IB-AB（deprecatedがtitle文字列でフラグに無い。L098は**現役index**に載る）
- pre-push guard: 4件を1BLOCKとして扱い正常/保全を区別できない
- **家老の報告文**: 同型19回目（IB-E/F/Kを「登録した」と書いて`insight_write.sh`未実行）

**(2) 「実測した」では足りない** — 「**いつ・どの版を**」まで揃えないと突合が成立しない
- fingerprintの3値混同（dir名=path hash／content fingerprint／生sha256）＝家老2回
- `wait_reason` の走査範囲（1ファイル→実際は5ファイル）＝軍師
- median の begin/end 混在（930行中475行がbegin）＝軍師→家老が配布
- 書式往復（作業ツリーとgit版が異なる）＝3者が別の版を見て別の結論

**(3) 契約の二重化** — 本日3例
- no-code符号化が4箇所で別々の形を要求
- review_two_phase（承認とfingerprintの扱い）
- `lesson_candidate.detail`（上流OR条件／下流単独必須）

## §6 役割分担が機能した記録

**点の発見 → 面の横展開 → 残り面の完了** は別の作業であり、1者では到達できない。

- IB-AB: 家老がL225のtitle文字列に気づく（点）→ 軍師が2,921件へ横展開しL098を発見（面）→ 将軍がロール別135件で該当0件を確認（残り面）→ **全数確定**

**忍者が上位を正した6例**: 小太郎（median覆し）／半蔵（虚偽記入拒否＋家老ACCEPT誤りの指摘）／影丸（軍師の検索範囲不足）／才蔵（家老の参照誤り）／飛猿（家老のヒントが誤誘導と判定）／軍師（家老の同型誤認を反証）

**唯一再現性のあった防御**: 「**確認範囲と未確認範囲を宣言する**」（n≧4）。家老05:15の件は軍師が60秒で解決、軍師の保留は影丸の正しい報告を守った。IB-S（指揮官に検算を強制する仕組みがない）の空白を運用で埋める形。

---

origin: `[[殿裁定03:15実装停止]] -> [[調査フェーズの完了]] -> [[裁定待ち7件の順序設計]]`
