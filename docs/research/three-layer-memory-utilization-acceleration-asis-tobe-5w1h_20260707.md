# 三層記憶 有効利用加速 設計書 — AsIs/ToBe 5W1H（全ロール・全CLI・自動想起版）

origin: [[殿指示_三層記憶有効利用加速_20260707]] <- [[three-layer-memory-l0-l7-penetration-design_20260604]] + [[three_layer_memory_first_priority_design_20260606]] + [[three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707]]
created: 2026-07-07T21:30+09:00 (将軍直筆。設計書=将軍直接編集)
updated: 2026-07-16T07:54+09:00
status: **v1.3 — M1-M6実装完了に加え、普遍knowledgeの全agent検索・Claude/Codex自動prompt注入・異CLI異ロール独立一致まで本番パリティ実証済み（§9）**
baseline計測日: 2026-07-07 21:25 (gate_three_layer_health.sh + search_logs SQL一次計測)。M1初回実測(22:16): 検索→引用変換率1.9%

## §0 要求定義（殿指示 2026-07-07 21:24 の5W1H）

| 要素 | 殿の要求 |
|------|---------|
| WHY | 三層記憶の**有効利用**を加速する（書く仕組みは完成済み。使う側を伸ばす） |
| WHAT | 有効利用を自動で加速する環境一式のAsIs/ToBe設計書 |
| WHO | いつでも**誰でも**（全ロール: 将軍・家老・軍師・忍者） |
| WHERE | **どのCLIでも**（Claude/Codex/将来CLI） |
| WHEN | **いつでも**（全イベント: 起票・配備・レビュー・報告・回答・idle） |
| HOW | 自動で（環境が検索して差し出す。LLMの自発検索に依存しない） |

**位置付け**: 三層学習ループ極限化設計書(同日v2)の姉妹編。学習ループ設計書は「経験→知識」の生産側を極限化した。本設計書は「知識→行動」の**消費側**を極限化する。先行2本(L0-L7貫通 06-04=導線接続、第一優先化 06-06=将軍の使用義務)の後継であり、対象を将軍から**全ロール**、義務から**自動化**へ拡張する。

## §1 定義

### §1.1 三層記憶（殿定義 2026-05-24）
- **Layer1 記憶DB**: ローカルSQLite（events 119,709件・全文FTS5・raw_content充填率93.3%）
- **Layer2 セマンティック**: 概念辞書+aliases（検索の入口。alias自動吸収=T3で還流化済み）
- **Layer3 Obsidian**: `[[リンク]]`因果ネットワーク（道。距離×濃度）

### §1.2 有効利用のファネル（本設計書の解剖単位）
```
①検索(query発行) → ②到達(hit) → ③注入(コンテキストに載る) → ④引用(成果物が使う[MEM]) → ⑤有効(引用が判断を変えた/誤りを防いだ)
```
利用の加速 = min(①〜⑤の各スループット)を引き上げる。**現状は④⑤が計測ごと欠落**（§2.3）。

### §1.3 想起の2経路
- **pull型**: エージェントが自発的に検索する（知能・意志依存。弱LLMほど劣化）
- **push型**: 環境がイベントを起点に検索し、結果を注入する（構造依存。モデル非依存）
本設計の原理: **pull→pushへの重心移動**。学習ループ設計書P1（知能を構造に置換）の想起版。

## §2 AS-IS（2026-07-07 21:25 一次計測）

### §2.1 回っている数値（維持対象）
| 指標 | 値 | 意味 |
|------|-----|------|
| 書込み健全性 | STATUS: PASS | events 119,709件・raw充填93.3%・contradiction 0 |
| 三層連鎖失敗 | 0件 | knowledge_write 1回でLayer1-3自動貫通(cmd_3715) |
| 検索件数 | 4,475件/7日 | semantic_search経由。回ってはいる |
| 実運用NO_MATCH率 | **1.4%** (62/4,475) | 検索到達性は改善済み（startup表示の90%はstress_test由来クエリの計測窓であり実運用値ではない） |
| 検索速度 | 平均415〜1,044ms/ロール | 実用域 |

### §2.2 ロール別検索分布（7日・search_logs実測）
| ロール | 検索数 | 全体比 |
|--------|--------|--------|
| 将軍 | 1,885 | 42% |
| 家老 | 1,183 | 26% |
| 軍師 | 1,018 | 23% |
| 忍者6名計 | 355 | **8%**（tobisaru 157/hayate 78/kotaro 47/hanzo 31/kagemaru 30/saizo 12） |

読み方: 実働の手を動かす忍者層の検索が全体の8%。忍者の知識到達はdeploy_task.shの静的注入(push)に依存し、**作業中の動的想起がほぼゼロ**。

### §2.3 詰まっている数値（TO-BEの標的）
| # | 指標 | 値 | 詰まっている段階(§1.2) |
|---|------|-----|----------------------|
| 1 | [MEM]引用率 | 1/20（将軍の殿向け回答のみ計測） | ④引用（検索しても成果物に乗らない/乗っても計測外） |
| 2 | 引用の有効性 | **計測自体が存在しない** | ⑤有効（useful_rate相当の欠如） |
| 3 | 忍者の動的検索 | 全体の8% | ①検索（イベント駆動想起が配備時のみ） |
| 4 | 軍師レビュー時の自動想起 | なし（startup注入のみ） | ③注入 |
| 5 | Obsidianリンクのトラバース利用 | 計測なし | ④引用（Layer3の利用が見えない） |
| 6 | Codex側の想起注入 | Stop hookなし・注入経路が薄い | ③注入（CLI依存） |

### §2.4 穴の構造（なぜなぜ）

**穴M1: ファネルの後半が計測されていない** — 検索(4,475件)と引用(1/20)の間、引用と有効の間が闇。なぜ→計測が「検索ログ」と「将軍回答の[MEM]タグ」の2点しかなく、注入→引用→有効の接続記録がないから。計測されないものは改善ループが回らない(LS-A18)。

**穴M2: 想起がpull型とhook注入型に依存** — pull型は知能・意志依存（弱LLMで劣化、/clearで習慣消失）。hook注入型（Step 1.7質問検知・MEMORY_RULING起票時）はClaude Code hookに癒着。なぜ→「イベント→scriptがクエリ生成→検索→注入」のCLI非依存push配管が、配備時(deploy_task)以外に存在しないから。

**穴M3: 忍者の作業中想起がない** — 配備時のsemantic_concepts注入は静的（タスク開始時点の1回）。作業中に遭遇した未知語・エラー・判断点での動的想起はpull任せ=8%。なぜ→忍者の作業ループ（AC進行・binary_check・報告記入）に想起イベントが定義されていないから。

**穴M4: ヒットしたが役立たない検索の放置** — NO_MATCH(1.4%)はstress testで鍛える還流があるが、「ヒットしたのに古い/無関係」の品質フィードバックがない。なぜ→検索結果に対する有効性の記入欄・突合先がないから（教訓のlessons_useful相当が検索に存在しない）。

**穴M5: Layer3（Obsidian因果）の利用が見えない** — リンクは633本生産・600本消費(loop_ledger)まで計測したが、「リンクをたどって判断が変わった」利用計測がない。なぜ→causal_expandの呼出しログと成果物引用の接続がないから。

**穴M6: 可搬性** — 記憶DB・semantic-map・想起scriptはT6 bootstrapの可搬コアに含まれたが、**想起の自動注入経路**（hook設定・イベント接続）はCLI・repo固有のまま。なぜ→注入経路の正本がhook設定ファイル(CLI依存層)にあり、script+YAML(非依存層)への分離が未設計だから。

## §3 TO-BE設計原理（学習ループ設計書P1-P6を想起軸へ継承）

| # | 原理 | 内容 |
|---|------|------|
| MP1 | **環境が検索して差し出す** — 「検索せよ」と指示しない。イベント発生時にscriptがクエリを自動生成し、検索し、結果を注入する。LLMは判断せず照合する | 
| MP2 | **全イベント=想起の機会** — 起票(済:MEMORY_RULING)・配備(済:semantic_concepts)・**レビュー・報告・回答・idle**に想起を接続 |
| MP3 | **ファネル全段計測** — 検索→注入→引用→有効をloop_ledgerの新チャネル(memory)として台帳化。空転（検索多・引用ゼロ）を自動検知 |
| MP4 | **正本はCLI非依存層** — クエリ生成・検索・注入テキスト生成=script。hookは「いつ呼ぶか」だけを担う薄いトリガ。hookが無いCLIは事後gate（[MEM]なし検知）が下支え |
| MP5 | **引用に有効性の記入欄** — [MEM]引用へのフィードバック（役立った/無関係）を報告・レビューの構造化フィールドで回収 |
| MP6 | **想起もbootstrapへ** — T6可搬コアに想起経路（イベント→検索→注入のscript一式）を同梱 |

## §4 AsIs/ToBe 5W1H対比

### §4.1 WHO（誰でも）— ロール別想起
| ロール | AsIs | ToBe |
|--------|------|------|
| 将軍 | Step 1.7質問検知注入+MEMORY_RULING起票時(済) | +回答前の[MEM]なし事後検知をWARN化（全CLI共通） |
| 家老 | startup gate注入のみ。検索は自発1,183件 | +GATE CLEAR処理時・WA記録時にscriptが関連教訓/裁定を自動検索注入 |
| 軍師 | startup gate注入のみ。検索は自発1,018件 | +レビュー受領時に対象cmdのorigin因果辺+関連教訓+過去類似レビューを自動注入 |
| 忍者 | 配備時semantic_concepts静的注入のみ（動的8%） | +報告記入時にlessons_useful対象の自動想起+作業中エラー時の関連教訓検索テンプレ |

### §4.2 WHEN（いつでも）— イベント別想起
| イベント | AsIs | ToBe |
|----------|------|------|
| cmd起票 | MEMORY_RULING+semantic+chronicle検索(済・厚い) | 維持 |
| 配備 | semantic_concepts+related_lessons注入(済) | +モデル階層プロファイル連動で注入厚を切替(T5接続) |
| レビュー | なし | 自動想起（§4.1軍師） |
| 報告記入 | なし | 自動想起（§4.1忍者） |
| 殿への回答 | 質問検知hook注入(Claude Codeのみ) | +事後gate=回答に[MEM]なし→次ターンWARN（CLI非依存） |
| idle | 還流在庫の自動配備(T2で済) | +想起空転検知（検索ゼロrobot/引用ゼロの日をALERT） |

### §4.3 WHERE（どのCLIでも）
| 要素 | AsIs | ToBe |
|------|------|------|
| 検索・書込み | script+SQLite=CLI非依存(済) | 維持 |
| 想起トリガ | Claude Code hook（UserPromptSubmit/SessionStart/Stop）に癒着。CodexはPre/PostToolUseのみ | トリガ層とクエリ生成・注入層を分離。注入層=script正本。トリガ=各CLIで使える最小イベント+**事後gate**（トリガが無くても報告/回答の形式検証で想起漏れを検出） |
| 可搬 | T6 bootstrapに記憶DB/semantic含む(済)。注入経路は未同梱 | 想起script一式をbootstrap最小セットへ追加 |

### §4.4 HOW（自動で）— 計測と品質
| 要素 | AsIs | ToBe |
|------|------|------|
| 計測 | 検索ログ+将軍[MEM]率のみ | ファネル全段(検索→注入→引用→有効)をloop_ledger memoryチャネルへ |
| クエリ生成 | LLM任せ（弱LLMは検索語が不安定） | scriptがタスクYAML/イベント文脈からキーワード抽出（構造化テンプレ。判断しない） |
| 品質FB | NO_MATCH→alias還流(T3で済) | +「ヒットしたが無関係」を報告/レビューの二値フィールドで回収→検索順位・alias整理へ還流 |
| Layer3利用 | 計測なし | causal_expand呼出しログ+注入採用率の計測 |

## §5 TO-BE施策（M1-M6）

| # | 施策 | 塞ぐ穴 | 防御Level | 計測指標 |
|---|------|--------|-----------|---------|
| M1 | **想起ファネル台帳**: loop_ledgerにmemoryチャネル追加（検索数/注入数/引用数/有効数・ロール別）+空転検知 | 穴M1,M5 | L5 | ファネル各段の週次推移 |
| M2 | **レビュー時自動想起**: 軍師のレビュー受領イベントで対象cmdのorigin因果辺+関連教訓+類似過去レビューをscriptが検索・注入 | 穴M2 | L5 | 軍師RC指摘のうち記憶由来の割合 |
| M3 | **報告時自動想起**: 忍者の報告テンプレ生成時にlessons_useful対象教訓の要点を自動再掲+[MEM]相当の引用欄 | 穴M3 | L4 | 忍者検索比率8%→(構造二値: 報告毎に注入が走る) |
| M4 | **引用有効性の回収**: [MEM]引用・注入知識への有効/無関係の二値フィールドを報告/レビューに追加→検索品質へ還流 | 穴M4 | L4+L6 | 引用有効率(新設) |
| M5 | **[MEM]事後gate**: 質問回答・レビュー成果物で[MEM]タグなしを検出しWARN（hook非依存の事後検証。Codexでも効く） | 穴M2,M6 | L4 | [MEM]引用率 1/20→(毎計測で改善が続く構造二値) |
| M6 | **想起のbootstrap同梱**: クエリ生成+検索+注入のscript一式をT6可搬コアへ追加 | 穴M6 | — | 新PJでの想起動作証拠 |

**優先順序（推薦）**: M1（計測なくして改善なし。LS-A18）→ M3（最大の未開拓=忍者8%）→ M2（軍師レビュー品質へ直結）→ M5（CLI非依存の下支え）→ M4 → M6。

## §6 計測計画（baseline固定 2026-07-07 21:25）

| 指標 | baseline | 再計測 |
|------|----------|--------|
| 検索件数/7日 | 4,475 | loop_ledger週次 |
| 忍者検索比率 | 8% (355/4,475) | M1導入後週次 |
| 実運用NO_MATCH率 | 1.4% | 同上 |
| [MEM]引用率 | 1/20（将軍回答のみ） | M5導入後、対象イベント毎 |
| 引用有効率 | 計測不能（欄が無い） | M4導入後 |
| Layer3トラバース利用 | 計測不能 | M1導入後 |

合格点は設けない（LS-A04(33)）。**毎計測で改善が続く構造二値+実測値報告**で運用。

## §7 実装cmd分割案（殿裁可2026-07-07 21:37「やろう」→ 同日実装。v1.1で実績追記）

| 順 | cmd | 対応施策 | 状態(2026-07-07 22:21) |
|----|-----|---------|------|
| 1 | cmd_3735 | M1 loop_ledger memoryチャネル+空転検知 | **完了**。初回実測: 検索7,846/引用147=**変換率1.9%**(ファネルの闇が初めて数値化) |
| 2 | cmd_3736→cmd_3739 | M3 報告テンプレ自動想起+memory_references欄(偵察→実装) | **完了**。偵察が挿入点・欄分離設計・「gate先行は全FAIL化」の順序制約を特定 |
| 3 | cmd_3737 | M2 レビュー依頼へのpush型検索添付+fail-soft | **完了** |
| 4 | cmd_3738 | M5 引用欠落の事後検証(定型応答除外+回帰テスト) | **完了**。※起票前提の誤り(WARN判定は既存)を軍師レビューが補正し真の差分に絞って達成 |
| 5 | cmd_3740 | M4 引用有効率集計+還流リスト | **完了**(22:41 CLEAR)。初回実測: 引用有効率12.5%(evaluated=8)、還流対象2 source(semantic_search 6件が同一無関係結果を重複注入=検索品質の還流入口が初稼働) |
| 6 | cmd_3741 | M6 bootstrap想起同梱(T6の増分) | **完了**(23:14 CLEAR)。recall_inject.sh(クエリ生成+検索+注入)を可搬コアへ同梱。将軍が新PJ相当一時dirで動作実証: 境界=空出力exit 0、ヒット時=キーワード抽出→検索→注入テキスト出力 |
| 7 | cmd_3742 | 派生: Layer2連鎖自己修復(失敗理由記録+未貫通の自動再貫通) | **完了**(23:19 CLEAR、将軍検分済み: エラー要点をERROR行へ記録+ERROR後OKなしをrepair=1で自動再貫通)。発端=家老エスカレーション(三層記憶DB健全性WARN複数セッション連続)。将軍手動再貫通で当座回復(未貫通1→0)→本cmdで構造化。書込み時retryはfix 04cea95d9で別途稼働 |
| 8 | cmd_karo_hotfix_three_layer_universal_recall_202607160630 | 派生: 普遍knowledge visibility SSOT + write直後atomic prompt cache + 実異CLI独立検証 | **完了**(2026-07-16 GATE CLEAR)。全agent検索0/9→9/9、実異CLI自動入口0/2→2/2、private漏洩0/8、対象summary hash 2/2一致 |

## §8 先行設計書との対応（車輪防止）

| 本設計書 | 先行との関係 |
|---------|------------|
| ファネル計測M1 | loop_ledger(T7実装済み)の対象拡張。新台帳は作らない |
| 忍者想起M3 | deploy_task注入(済)の「配備時→報告時」への拡張 |
| [MEM]事後gate M5 | 第一優先化設計書(06-06)の将軍義務を全ロール+機械検証へ昇格 |
| クエリ自動生成 | T5モデル階層プロファイル(cmd_3727実装済み)と連動。弱LLM対応の想起版 |
| bootstrap M6 | T6(cmd_3728実装済み)の増分。新規機構なし |

## §9 v1.3追補 — 普遍knowledge自動想起の本番パリティ（2026-07-16）

### §9.1 追加で判明したAS-IS

M1-M6は「イベントで検索し、差し出し、利用を計測する」経路を実装した。しかし、2026-07-16の実CLI横断検証で、**保存済みの普遍knowledgeが全ロール・全CLIへ同じ意味と粒度で届くとは限らない**穴が判明した。

| 観点 | AS-IS（修正前） | 真因 |
|------|-----------------|------|
| target空欄の普遍knowledge | 正本events/FTS5には存在するが、agent指定検索では全9agent **0/9** | `memory_db_import.py`のtarget検索が`target=self OR document`だけを許し、target空/NULLを除外 |
| visibility意味論 | 記憶DB検索・semantic検索・prompt cacheで条件が分裂 | visibilityの共通SSOTがなかった |
| write後の再利用 | 手動DB検索では到達するが、実CLI自動入口は **0/2** | knowledge write後にprompt cacheをrefreshするproduction経路がなかった |
| テスト証明 | テスト内でcacheへ手動INSERTすれば入口contractはPASS | production write→cache→実prompt hookの連鎖を通していなかった |
| 全CLI証明 | 1つのCLIがenvで全役を模倣 | 同一processの役割模倣であり、異CLI・異役割の独立性を証明しない |
| 理解の粒度 | hit件数だけを一致判定に使用 | concept ID・殿原文timestamp・raw・origin因果・payload hashの一致を見ていなかった |

### §9.2 達成したTO-BE

| 契約 | TO-BE（実装済み） |
|------|-------------------|
| visibility SSOT | `scripts/memory_visibility.py`へ`target空/NULL OR target=self OR document`を一元化。`memory_db_import.py`と`semantic_index.py`が共有 |
| 自動再利用経路 | `memory_db_knowledge_write.sh`成功→主DBからprompt cache再構築→Claude/Codex共通`prompt_state_inject.sh`へ自動反映 |
| atomic publish | flock→一時SQLite→`PRAGMA quick_check`→`os.replace`。更新途中のreaderへ不完全cacheを見せない |
| payload粒度 | `event_id`・`ts`・`concept`・`raw`・`origin`を構造化summaryに保持 |
| private境界 | directed knowledgeは普遍prompt cacheへ収録せず、他agentへの漏洩を防止 |
| 実CLI完了条件 | 実家老Codexと実軍師Claudeが互いの回答を参照せず同一問いを独立取得し、concept・原文timestamp・因果鎖・payload hashを突合 |
| 擬似試験の位置付け | 単一CLI env擬似8役はentrypoint contractの補助証拠へ降格 |

自動再利用経路:

```text
knowledge write
  → Layer1: memory DB（event_id / raw / timestamp）
  → Layer2: semantic concept / aliases
  → Layer3: Obsidian origin因果鎖
  → atomic prompt cache
  → prompt_state_inject.sh
  → Claude / Codexの各実CLI・各role
```

### §9.3 AS-IS / TO-BE実測

| 指標 | AS-IS | TO-BE実測 |
|------|------:|----------:|
| target空欄knowledgeの全agent検索 | 0/9 | **9/9** |
| 実異CLI自動入口 | 0/2 | **2/2** |
| 実異CLI対象summary hash一致 | 未成立 | **2/2一致** |
| 他agent宛private漏洩 | 0/8 | **0/8** |
| refresh並行reader瞬断 | 未計測 | **0/300**（refresh 30回と並行） |
| memory tests | — | **60/60 PASS、SKIP 0** |
| semantic tests | — | **33/33 PASS、SKIP 0** |

独立checkpointは`knowledge:d39dfb36cbf94766`、markerは`cross_cli_independent_checkpoint_20260716`。実家老Codexと実軍師Claudeで対象summary SHA256 `54486b88764aabc3585271b40f18fe21fa7c31ac29290a80d0fd6f1fa9cff3cc`、field 5/5一致を確認した。

実装commit:

- `8dacb9fbf`: target visibilityを`scripts/memory_visibility.py`へ統一
- `c2e7352ee`: knowledge write直後のatomic prompt cache refreshを実装

詳細: `docs/research/cmd_karo_hotfix_three_layer_universal_recall_202607160630.md`

### §9.4 完了判定の更新

三層記憶の完了は、以後「保存成功」「DB検索成功」「同一CLIのcontract test成功」では判定しない。

```text
production write
  → atomic cache refresh
  → actual prompt hook
  → 異CLI・異役割の独立取得
  → concept / raw / timestamp / origin / hash一致
```

この全経路がPASSして初めて、**全ロール・全CLIが同じレベルと粒度で自動想起できる**と判定する。

因果: `[[殿指摘20260716_単一CLI擬似全役は洗脳]] -> [[knowledge_write_to_atomic_prompt_cache]] -> [[家老Codex軍師Claude独立一致]]`

## 因果リンク

- ← [[three-layer-memory-l0-l7-penetration-design_20260604]] 導線接続(部品→貫通)=本設計の前提
- ← [[three_layer_memory_first_priority_design_20260606]] 将軍の使用義務=本設計が全ロール自動化へ昇格
- ← [[three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707]] 生産側の極限化=姉妹編。P1-P6原理を想起軸へ継承
- ← [[deepdive_why_chain_20260321]] Phase 4: 理解・意志依存の設計は原理的に壊れる→push型想起の理論的根拠
- → [[lessons_shogun]] LS-A23(道具を作っても使わなければ存在しない)+LS-A18(計測なき改善は不能)=施策M1/M5の教訓的根拠
- → [[殿指摘20260716_全ロール全CLI同一粒度]] 保存成功ではなく全入口の自動再利用成功を完了条件にする
- → [[殿指摘20260716_単一CLI擬似全役は洗脳]] 異CLI・異役割の独立取得一致を最終checkpointにする
