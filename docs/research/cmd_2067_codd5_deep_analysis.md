# cmd_2067 CoDD #5深堀り + 本家リポジトリ分析

日付: 2026-04-18
担当: saizo
対象: CoDD #5記事 / `yohey-w/codd-dev` / 我が軍のGP-198/200/201

## §1 結論

CoDD #5の本質は「情報を足す」ではなく「思考の順序を強制する」にある。2026-04-14公開の#5記事は、73問のSWE-bench Verifiedで `codd fix` が `73/73 = 100%` に到達した主因を、`Diagnose (MANDATORY)` と `Session State` の組み合わせとして説明している。

本家公開リポジトリでも、同日コミット `5b15da5` で `codd/fixer.py` に診断ステップと `_SessionState` が実装された。その後も 2026-04-16〜2026-04-18 にかけて、`implement` 系で「暗黙の前提に依存した設計」を削り、「失敗タスクの文脈汚染」を止める修正が続いている。

我が軍は GP-198/200/201 により CoDD #5 の骨格は既に吸収済みである。ただし現状の Session State は **`attempt + last_block_reason + tried_approaches` に圧縮されすぎ** ており、CoDD本家が保持する「前回の診断・採ったアプローチ・その結果」までは持ち越していない。次の伸びしろはここである。

## §2 CoDD #5記事の要点

出典:
- Zenn: `https://zenn.dev/shio_shoppaize/articles/codd-swebench-diagnose`
- 公開日: 2026-04-14

### 2.1 何が問題だったか

- 73問を P1/P2/P3 の3段階で解くと、P1は高精度だが P3 が重かった
- 記事では、170回のAI呼び出しのうち100回(59%)が「同じ壁に当たるだけの無駄な再試行」と整理されている
- 根因は、各リトライがステートレスで「前回何を試し、なぜ失敗したか」をAIが知らないこと

### 2.2 Diagnose MANDATORY

記事で追加した指示は2段階である。

1. `Step 1: Diagnose (MANDATORY)`  
   根本原因、責任ファイル/行、設計書上の正しい挙動を先に書かせる
2. `Step 2: Fix`  
   その診断を踏まえて修正する

重要なのは、足しているのが「答え」ではなく「思考構造」だという点である。記事はこれを、#3で退化した外部情報注入と対比している。

### 2.3 Session State

記事中の `_SessionState` は、各リトライ後に少なくとも以下を保持する。

- `attempt`
- `diagnosis`
- `original_errors`
- `result_after_fix`
- `approach_summary`

そして次回プロンプトの先頭に `## Prior attempts (DO NOT repeat these — try a different approach)` として注入する。  
効果は「前回失敗した仮説を再発明させない」ことにある。

## §3 本家リポジトリ現物確認

出典:
- Repo: `https://github.com/yohey-w/codd-dev`
- 調査基準日: 2026-04-18

### 3.1 2026-04-14: v1.8.0 で #5 が実装された

コミット `5b15da5e0b5827a66b11c66c98e26b784c84479e`:
- `codd/fixer.py` に `diagnosis` フィールドを追加
- `run_fix()` が `_SessionState()` を生成し、失敗ごとに `record_attempt()` する形へ変更
- `_build_fix_prompt()` が `Step 1: Diagnose` → `Step 2: Fix` を強制
- `pyproject.toml` は `1.8.0` へ更新

確認できた実装上の特徴:
- 診断文は AI 出力から `## Diagnosis` / `## Root Cause` を抽出
- `format_for_prompt()` は prior attempts を自然言語の箇条書きで再注入
- 単に block reason を数えるのでなく、「診断」「アプローチ」「結果」をセットで持つ

### 3.2 2026-04-16: v1.8.1 で sprint 前提を捨てた

コミット `e56b0262b96544dc1ba3d42bcb18117ad2e09cba`:
- `implement --sprint` を廃止し、`implement` を task-based に簡素化
- `src/generated/sprint_N/...` を `src/generated/<task>/...` に変更
- 根因として「generator prompt が内部構造を規定していないのに、implementer parser が sprint 形式を暗黙前提にしていた」ことを明記

示唆:
- 暗黙フォーマット依存は、いずれ parser/prompt のズレを生む
- CoDD本家はここを「flat task-based generation」に倒している

### 3.3 2026-04-17〜2026-04-18: 実運用由来の耐障害化

コミット履歴から確認できた主要変更:

- `6be38e1` (2026-04-17): 並列 task failure 時の deadlock 防止 + agent diagnostics
- `f9e4115` (2026-04-17): failed task を握り潰さず、error 付き結果として表面化
- `b27b6c4` (2026-04-18, v1.9.3): failed task summary を downstream prompt へ混入させないよう filter 追加

特に `b27b6c4` は重要である。  
失敗タスクの要約文が後続タスクの prompt を汚染し、空出力や malformed code を誘発したため、`prior_task_outputs` から `error` を持つ要素を除外する形に修正されている。

### 3.4 DIVERGENT の扱い

記事本文では DIVERGENT が重要概念として語られるが、今回確認した公開 repo の主な実装差分は `fix` の Diagnose + Session State と、`implement` の failure surfacing / contamination guard に寄っていた。

推論:
- DIVERGENT は public repo 上で単独の大きな新機能というより、retry 文脈の運用原理として扱われている可能性が高い
- 少なくとも 2026-04-18 時点で、今回確認できた公開差分の中心は「診断」と「失敗履歴」と「失敗文脈の遮断」である

## §4 我が軍との対応

### 4.1 既に吸収済みの部分

| CoDD #5 / repo | 我が軍の対応 | 現物 |
|---|---|---|
| Diagnose MANDATORY | BLOCK時に原因言語化を要求 | `scripts/gates/gate_diagnose_check.sh` |
| DIVERGENT | 同一理由の連続BLOCKで仮説転換を要求 | `scripts/gates/gate_diagnose_check.sh`, `scripts/cmd_save.sh` |
| task-level session state | FAIL時に `session_state` を task YAMLへ記録 | `scripts/gates/gate_report_format.sh` |
| retry hint injection | 再配備時に `previous_failures` を注入 | `scripts/deploy_task.sh` |
| CoDD改善専用の failure history | registry から同一スクリプトの revert/regression を注入 | `scripts/deploy_task.sh` |

### 4.2 まだ負けている点

#### GAP 1: Session State の情報量が足りない

我が軍の `session_state` / `previous_failures` は主に以下で構成される。

- `attempt`
- `last_block_reason`
- `tried_approaches`

CoDD本家の `_SessionState` はさらに以下を持つ。

- 診断文そのもの
- 実際に採ったアプローチの要約
- 修正後に何が起きたか

差分の意味:
- 我が軍: 「どの gate 理由で落ちたか」は残る
- CoDD本家: 「どの仮説で直そうとして、どんな副作用が出たか」まで残る

前者だけだと、block_reason が同じでも診断の質が毎回浅いまま回りやすい。

#### GAP 2: DIVERGENT 判定が gate reason 依存

現状の DIVERGENT は「同じ `block_reason` が続いたか」で判定している。  
しかし CoDD #5 の本質は「前回の仮説/アプローチを繰り返すな」である。

つまり強化すべき判定は:
- 同じ `block_reason` か
ではなく
- 同じ `diagnose_reason` と同種の `approach_summary` を繰り返していないか

#### GAP 3: failure-context contamination guard が弱い

本家 `v1.9.3` は failed task summary を後続 prompt から除外した。  
我が軍でも `codd_failure_history` や `previous_failures` を再注入しているが、現在の注入は「失敗があった」という事実を渡す段階であり、後続 prompt 汚染を防ぐフィルタ設計までは持っていない。

特に CoDD改善cmdの再配備では、将来 `report summary` や `failed attempt detail` を広く注入し始めると同種の汚染が起きうる。

#### GAP 4: knowledge index が最新実装に追従していない

`context/codd.md` には以下の両方が同居している。

- `Session State ... GP-201は設計済み未実装`
- `L3 ... GP-201 CLEAR`

実装側では `gate_report_format.sh` / `deploy_task.sh` に GP-198/201 相当の処理が存在するため、索引層の記述が追従し切れていない。  
研究結果を運用判断に使うなら、この不整合は先に潰すべきである。

## §5 我が軍への拡張提案

優先順位は ROI と再利用範囲で付けた。

### P1. Session State v2: `prior_attempts[]` の構造化

内容:
- `session_state` を `attempt/last_block_reason/tried_approaches` から、CoDD本家型の `prior_attempts[]` へ拡張
- 1 attempt ごとに `diagnosis`, `approach_summary`, `result_after_fix`, `new_failures` を保持

理由:
- GP-198/201 の次段階として最も素直
- 再配備・/new・retry の全てで効く
- 「前回何を試し、なぜダメだったか」を再利用できる

優先度: 最優先

### P2. DIVERGENT v2: reason一致ではなく仮説一致を検知

内容:
- `block_reason` 連続だけでなく、`diagnose_reason` / `approach_summary` の類似再提出を検知
- 「前回と実質同じ修正」を明示的にBLOCK/WARNする

理由:
- #5記事の核心に近づく
- FIX hint を読んで形だけ変える再試行を止めやすい

優先度: 高

### P3. contamination guard: 失敗要約の downstream 注入を遮断

内容:
- `prior outputs` / `failed attempts` / `report summary` を後続 prompt に使う箇所で、`error-only` な要約を除外
- 失敗履歴を渡す場合も「失敗テキスト全文」ではなく、構造化された `diagnosis + result` に限定

理由:
- `b27b6c4` が示した実戦知見をそのまま盗める
- 我が軍は YAML/報告/教訓の注入経路が多く、prompt 汚染リスクはむしろ高い

優先度: 高

### P4. partial failure surfacing を multi-script CoDD改善cmdへ持ち込む

内容:
- バッチ型改善cmdで一部対象だけ失敗した場合、成功扱いにせず `error` を表面化
- 後続の registry / report / prompt 注入でも、その失敗を明確に分離

理由:
- 2026-04-17 の本家 implement 修正群が狙っているのはここ
- 我が軍の CoDD改善バッチは3本単位が多く、部分成功の握り潰しは将来の汚染源になる

優先度: 中

### P5. `context/codd.md` の索引同期

内容:
- GP-198/200/201 の実装状況を 2026-04-18 時点へ同期
- 併せて `v1.8.0` だけでなく `v1.8.1` と `v1.9.3` の公開差分も索引に追記

理由:
- 実装は進んでいるのに索引層が古いと、次の将軍判断が stale knowledge に寄る
- 研究cmdの成果を複利化する最短手

優先度: 中

## §6 未適用知見 3件以上

未適用と判断したもの:

1. **診断文そのものの持ち越し**
   - 現在は block reason 中心
   - CoDD本家は diagnosis text を再注入

2. **approach/result の paired history**
   - 現在は tried_approaches まで
   - CoDD本家は `approach_summary + result_after_fix` の組で保持

3. **failure summary contamination filter**
   - 本家 `v1.9.3` は実装済み
   - 我が軍には同等の明示フィルタが未見当

4. **暗黙フォーマット前提の削減**
   - 本家 `v1.8.1` は sprint 概念を撤去
   - 我が軍でも spec/parser/prompt 間に暗黙前提が残る箇所は今後の監査対象になる

5. **partial failure の明示 surfacing**
   - 本家 implement 系は 2026-04-17 にここを強化
   - 我が軍の batch 改善cmdでも転用価値あり

## §7 まとめ

CoDD #5の価値は「L3っぽい言葉」を増やすことではなく、**再試行を stateful にし、同じ誤りを環境側で繰り返させない** ところにある。

我が軍は GP-198/200/201 で入口は既に作っている。次に取るべきは、public CoDD repo が実装している粒度まで Session State を濃くし、`v1.9.3` が示した failure-context contamination guard を prompt 注入系へ横展開することである。

## §8 参照

- Zenn #5: `https://zenn.dev/shio_shoppaize/articles/codd-swebench-diagnose`
- Repo: `https://github.com/yohey-w/codd-dev`
- Commit `5b15da5`: Diagnose + Session State (`2026-04-14`)
- Commit `e56b026`: sprint撤去 / flat task-based generation (`2026-04-16`)
- Commit `b27b6c4`: failed task summary contamination guard (`2026-04-18`)
- Local: `context/codd.md`
- Local: `docs/research/gunshi_codd_swebench_application_20260416.md`
- Local: `scripts/gates/gate_diagnose_check.sh`
- Local: `scripts/gates/gate_report_format.sh`
- Local: `scripts/deploy_task.sh`
- Local: `scripts/cmd_save.sh`
