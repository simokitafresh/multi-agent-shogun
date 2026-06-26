# Loop Engineering知見取込み設計書 — AsIs/ToBe 5W1H

origin: [[loop_engineering]] + [[self_improving_agent_local_optima]]
source: `docs/research/loop_engineering_anthropic_playbook_20260617.md` (原文全文1102行)
created: 2026-06-26T14:42+09:00
status: reviewed (軍師レビュー済み blt_20260626_144634_35cbc4 → 5点反映済み)

## 元論文参照

- **論文**: Loop Engineering: The Anthropic Playbook for Designing Systems That Prompt Your Agents (IEEE形式, 11ページ, 2026-06-17)
- **著者**: Peter Steinberger, Boris Cherny (Anthropic Claude Code lead), Addy Osmani (Google Chrome)
- **原文保存先**: `docs/research/loop_engineering_anthropic_playbook_20260617.md`
- **PDF**: https://drive.google.com/file/d/1qzKI4DKnyHRpXK1J3ATPqwaqLc0iNu-M/view
- **三層記憶**: knowledge:b51d72d508e5fbef / semantic:loop_engineering

---

## 実装Phase (軍師レビュー反映)

| Phase | 項目 | 理由 |
|-------|------|------|
| Phase 1 (D0/既存改修) | #5 懐疑デフォルト, #8 サンプル読み, #11 cognitive surrender checkpoint | 既存instructions/idle手順の追記のみ |
| Phase 2 (軽量新規) | #1 idle自走automation, #6 self-grade検証, #7 verification debt計測 | 既存スクリプト拡張 |
| Phase 3 (中規模) | #9 token予算, #10 intent debt計測, #3 FE動かして検証 | 新規スクリプト+gate追加 |
| Phase 4 (大規模) | #2 worktree隔離, #4 cloud scheduling | deploy_task/CI構造変更 |

**段階的導入原則(論文§XII)**: 最初のループは極小から始めよ。Phase 1でチェック追加が信頼を獲得してからPhase 2へ。各Phaseで検証が実際にミスを捕捉したことを確認してから次Phaseへ進む。

---

## 改善項目一覧 (12件)

### 項目1: idle自走automation化

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 将軍のidle時自己分析(Step 1-5: insights消費→WA分析→cmd品質→review_log→パターン発見)が意志依存 | タイマートリガーでidle Step 1-5を自動起動。Manual Loop防止 |
| **Why** | 論文§VI-C: 「4つの良い手があっても自動化がなければループではない。作った日だけ動くスクリプト」。将軍が忙しい/忘れる→idle分析が回らない→パターン見逃し | idle分析が意志に依存せず回る。発見→cmd化の鎖が切れない |
| **Who** | 将軍(手動) | ninja_monitor or cron(自動) → 将軍paneにnudge |
| **Where** | scripts/gates/gate_shogun_startup.sh idle自走トリガー表示 | ninja_monitor.sh or 新規cron: 全忍者idle+パイプライン空を検知→将軍にidle_analysis nudge |
| **When** | 将軍が起動時に気づいたとき | 全忍者idle状態が10分以上継続したとき自動トリガー |
| **How** | 新規: ninja_monitor.shにidle全員検知→将軍inbox_write(type=idle_analysis_trigger)を追加。または/loop相当のcron |
| **論文根拠** | §VI-C Manual Loop, §III-B Scheduling, Table II |

### 項目2: per-cmd worktree隔離

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 全忍者が同一作業ツリー(/mnt/c/Python_app/DM-signal)で並列作業 | cmd単位でgit worktreeを作成し、忍者ごとに隔離ディレクトリで作業 |
| **Why** | 論文§VI-E: 「並列エージェントが同じ作業ディレクトリを変更→編集衝突→マージ不能」。LS061で実証済み(hayate作業中にcheckout事故) | 並列配備時の衝突がゼロになる。Tangled Loop防止 |
| **Who** | 家老(配備時) | deploy_task.sh(自動worktree作成+cleanup) |
| **Where** | deploy_task.sh配備フロー | deploy_task.shにworktree作成→task YAMLにworktree_path注入→忍者がworktree内で作業→完了後cleanup |
| **When** | dm-signal cmdの並列配備時 | 全dm-signal cmdで常時(infra cmdは現行リポジトリ内で問題なし) |
| **How** | `git worktree add /tmp/worktree-{cmd_id} main` → task YAMLに`worktree_path`フィールド追加 → 忍者がそのパスで作業 → 報告後に`git worktree remove` |
| **論文根拠** | §IV Worktrees, §VI-E Tangled Loop, Table III |

### 項目3: 評価者「動かして検証」強化

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | infra/scripts変更時のみ実動作確認(gunshi.md §4.5 殿厳命2026-06-08)。FE変更時は未対応 | 軍師がPlaywright/CDP等でFE変更を実際にクリック・スクショ・DOM検査して検証。FE変更への実動作確認を拡張 |
| **Why** | 論文§V-C: 「評価者がコードを読むだけでは『よさそうに見える』しか判断できない。動かして『実際に動く』を確認すべき」 | 「JSXがよさそう」→「ボタンを押したらページ遷移した」に判定基準が昇格 |
| **Who** | 軍師 | 軍師(FE変更時) |
| **Where** | instructions/gunshi.md SGプロトコル | SGプロトコルにFE変更時のPlaywright/CDP検証ステップ追加 |
| **When** | dm-signal FE変更cmdのレビュー時 | FE変更を含む全cmdのレビュー時 |
| **How** | 軍師のSGにFE検証観点追加: 「FE変更あり→CDPでページ開く→変更箇所をクリック→スクショ→DOM確認→レビュー判定」 |
| **論文根拠** | §V-C "The Evaluator Should Act, Not Just Read", Fig. 3 |

### 項目4: Cloud Scheduling (overnight sweep)

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 全てローカルスケジューリング(ninja_monitor, inotifywait)。マシンOFF→停止 | CI/issue/commitの夜間自動トリアージをGitHub Actions scheduleで実行 |
| **Why** | 論文§VII-C: 「ローカル/loopは『自分がいる間の追加ラウンド』。クラウドは『自分がいなくても動く』。これは異なる能力」 | 殿が寝ている間もCI RED検知→修正PR作成→翌朝レビューだけ |
| **Who** | なし(現状は殿/将軍が朝確認) | GitHub Actions cron → Claude Code Cloud Routines |
| **Where** | .github/workflows/ | 新規workflow: nightly-triage.yml |
| **When** | 毎日06:00 UTC(JST 15:00)または殿指定 | 毎日定時 |
| **How** | GitHub Actions schedule → claude --skill morning-triage → state/triage.md → PR作成 → inbox通知 |
| **論文根拠** | §VII-C, §VII-D, Table IV |

### 項目5: 軍師の懐疑デフォルト

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 軍師のSGプロトコルは品質チェック6観点だが、デフォルト姿勢は「確認」 | デフォルト姿勢を「壊れていると仮定。証明されるまでFAIL」に変更 |
| **Why** | 論文§V-B: 「生成者を自己批判的にするより、独立した懐疑者を調整する方が遥かに容易」 | 軍師がPASS寄りバイアスから脱却。見逃し率低下 |
| **Who** | 軍師 | 軍師 |
| **Where** | instructions/gunshi.md | SGプロトコル冒頭にデフォルト姿勢追加 |
| **When** | 全レビュー時 | 全レビュー時 |
| **How** | gunshi.mdのSGプロトコルに「ASSUME: this output is BROKEN until proven otherwise. DO NOT praise. Find what fails.」相当の日本語指示追加 |
| **論文根拠** | §V-B "Tune a Skeptic, Don't Fix a Modest Author", §V-D evaluator setup example |

### 項目6: 忍者self-grade自動検証

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 忍者がbinary_checks全yes→verdictをPASSと自己報告。将軍がGATE CLEAR時にgit show -wで手動検分(LS-A09(17)) | 自動gate: binary_checks yesの主張をgit diff/git show -wで機械検証 |
| **Why** | 論文§V-A: 「エージェントに自分の出力を採点させると、品質が凡庸でも自信を持って褒める」。cmd_3298/3315で虚偽報告実証済み | 忍者の自己採点を機械的に検証。Nodding Loop防止 |
| **Who** | 将軍(手動) | cmd_complete_gate.sh(自動) |
| **Where** | cmd_complete_gate.sh | git show -w自動実行→整形混入検出→WARN |
| **When** | 全cmd GATE CLEAR判定時 | 全cmd GATE CLEAR判定時 |
| **How** | cmd_complete_gate.shに: git show -w HEAD → 整形のみ変更(import並替/折返し)をgrep → 混入あればWARN表示 |
| **論文根拠** | §V-A "It Always Praises Itself", §V-D maker-checker principle |

### 項目7: Verification debt週次計測

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | useful_rate/rework率はstartup gateでスナップショット表示のみ | 週次トレンドを記録し、悪化傾向を自動検知 |
| **Why** | 論文§VIII: 「4つのコストは沈黙のうちに蓄積する」。単発のスナップショットでは傾向が見えない | 悪化トレンドを早期検知。Verification debtの蓄積防止 |
| **Who** | gate_shogun_startup.sh | 新規: weekly_metrics_trend.sh(cron or idle時実行) |
| **Where** | logs/ | logs/weekly_metrics_trend.yaml |
| **When** | 週次(月曜idle時) | 週次 |
| **How** | useful_rate/rework率/BLOCK率の週次スナップショットをYAMLに追記 → 3週連続悪化でALERT |
| **論文根拠** | §VIII Verification debt, Fig. 6 reinforcing cycle |

### 項目8: Comprehension rot防止(サンプル読み)

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 忍者のコード変更を将軍は直接読まない(dashboardとgate結果のみ) | 毎セッション1cmd分の忍者変更をgit show -wでサンプル読み |
| **Why** | 論文§VIII/§XI-A: 「ループが速くコードを出すほど、存在するものと理解しているものの差が広がる。読むのは書くより退屈で、ループが書く仕事を取ったから、コードベースが成長する間に頭の中の地図は止まる」 | 将軍がコードベースの理解を維持。説明できない変更=地図の更新が必要 |
| **Who** | 将軍 | 将軍(idle時) |
| **Where** | idle自走Step | idle自走Step 6として追加: 直近GATE CLEAR cmdの変更をgit show -wで読む |
| **When** | 毎セッションidle時 | 毎セッションidle時 |
| **How** | cmd_design_quality.yamlから直近CLEAR cmdを1件選択 → git show -w {commit} → 変更内容を1分読み → 説明できなければinsight_write |
| **論文根拠** | §VIII Comprehension rot, §XI-A "Read a Sample, Always" |

### 項目9: Token予算上限

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | AUTOCOMPACT 90%でCTX管理するが、per-cmd/per-dayのトークン上限なし | cmd単位・日単位のトークン予算上限を設定。**注: 論文の本来の意図はAPI cost上限(hard ceilings on spend per loop)。現環境でcostを直接計測する手段がないため、/clear回数をproxy指標として使用する** |
| **Why** | 論文§VIII/§XI-B: 「ループがヘルパーを生成し、リトライし、ラウンドごとに回る。1つのバグが一晩空回りして、修正コードではなく見慣れない請求を生む」 | 空回りバグが一晩でクォータを食い尽くすリスクを構造的に防止 |
| **Who** | ninja_monitor | ninja_monitor.sh + settings.yaml |
| **Where** | config/settings.yaml token_budget セクション | per-cmd CTX上限(例: 3回/clear)、daily budget(全体) |
| **When** | 全cmd実行中 | 全cmd実行中 |
| **How** | ninja_monitor.shに: 同一cmdで/clear 3回超 → idle強制+家老報告。settings.yamlにmax_clear_per_cmd設定 |
| **論文根拠** | §VIII Token blowout, §XI-B "Cap Before You Ship" |

### 項目10: intent debt計測

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | SKILL.md陳腐化をgate_skill_script_refs.shで検出(mtime比較のみ) | SKILL.md未使用率・陳腐化率・intent debt(毎ターン説明し直すコスト)を定期計測 |
| **Why** | 論文§IV Skills: 「intent debtとは『このPJは何で、ルールは何で、罠はどこか』を毎回説明し直すコスト。スキルはこれを返済する」 | スキルが実際にintent debtを返済しているか定量計測。未使用スキル=debt未返済 |
| **Who** | gate_skill_script_refs.sh | 拡張: skill_usage_metrics.sh |
| **Where** | scripts/gates/ | gate_shogun_startup.sh + 新規skill_usage_metrics.sh |
| **When** | startup時 + 週次 | startup時 + 週次 |
| **How** | skill_recommend.shの推薦ログ + 実行ログからスキル別使用率算出。未使用30日超→陳腐化候補表示 |
| **論文根拠** | §IV Skills, intent debt定義 |

### 項目11: Cognitive surrender防御(human checkpoint明示化) — 軍師レビュー追加

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 殿の鎖(殿→将軍→家老→忍者)に暗黙的に含まれるが、ループ内のhuman checkpointとして明示されていない | ループの各段階にhuman checkpoint(殿レビュー点)を明示的に設計・文書化 |
| **Why** | 論文§XI-C: 「認知降伏への防御は態度ではなく構造。ループに最低1つの停止点を作れ — 人間が常に介入するためではなく、介入できる位置に居続けるために」。論文§IX: 「全てのドアを溶接した技術者は、入る必要が生じた日に鍵を持っていない」 | 殿が判断を放棄しないための構造的保証。ループが信頼できるほど判断放棄の誘惑が強まる |
| **Who** | 殿 | 殿(変更なし。明示化のみ) |
| **Where** | CLAUDE.md + instructions/shogun.md | 既存の🚨要対応セクション、push前human review、cmd scope modeを「human checkpoint」として再定義 |
| **When** | 全cmd完了時 | 全cmd完了時(変更なし) |
| **How** | context/growth-loop.mdにhuman checkpoint一覧セクション追加: (1)cmd起票=殿裁可 (2)push=pre-pushフック+殿確認 (3)本番DB変更=バックアップファースト+殿確認 (4)gate変更=軍師レビュー+殿裁可。既存仕組みの再定義であり新規実装不要 |
| **論文根拠** | §IX "Stay the Engineer", §XI-C "Keep One Door Open", §VIII Cognitive surrender |

### 項目12: 段階的導入原則 — 軍師レビュー追加

| 項目 | AsIs | ToBe |
|------|------|------|
| **What** | 改善項目を一括で設計・実装する傾向 | 極小から始め、検証が実際のミスを捕捉してから拡大する段階的導入 |
| **Why** | 論文§XII: 「Stripeのパイプラインは到達点であって出発点ではない。最初のループは極小で — 信頼を獲得した小さなループが拡大の権利を得る」。§XII-B: 「安全な成長順序は、検証が証明された後に並列を追加すること」 | 大規模導入の失敗リスクを構造的に防止。小さく始めて信頼を積む |
| **Who** | 将軍 | 将軍(cmd設計時) |
| **Where** | cmd設計プロセス | 上記Phase表(Phase 1→2→3→4)の順序を遵守。各Phase完了条件=検証が実際のミスを捕捉した実績 |
| **When** | 本設計書の実装開始時 | Phase間の移行判定時 |
| **How** | Phase N完了条件: 追加した検証/gateが1件以上の実際の問題を検出した実績。未検出のままPhase N+1に進まない |
| **論文根拠** | §XII "Build Your First Loop Today", §XII-B "Growing the Loop Safely" |

---

## 軍師レビュー反映履歴

- **blt_20260626_144634_35cbc4** (2026-06-26T14:46)
  1. ✅ 抜け漏れ: 項目11(cognitive surrender), 項目12(段階的導入)追加
  2. ✅ AsIs誤り: 項目3 AsIsを「infra/scripts変更時のみ実動作確認。FE変更時は未対応」に修正
  3. ✅ ToBe逸脱: 項目9 ToBeにproxy指標である旨と論文本来意図(API cost上限)との差異を明記
  4. ✅ 実装順序: Phase表を冒頭に追加(Phase 1-4)
  5. ✅ 重複・干渉: 項目5はLG043拡張で統合可能(実装時に確認)

---

## レビュー依頼事項

1. 上記10件に抜け漏れはないか(論文の知見で取りこぼしている項目)
2. AsIs認識の誤りはないか(現状を正しく把握しているか)
3. ToBe設計に論文の意図から外れた解釈はないか
4. 実装優先順位の提案(ただし全件実施が前提。順序の提案)
5. 既存の仕組みとの重複・干渉リスク
