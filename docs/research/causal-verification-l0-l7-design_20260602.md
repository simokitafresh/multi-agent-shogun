# 因果確認 L0-L7 貫通設計

<!-- semantic-links: [[因果確認L0-L7]], [[三層記憶アーキテクチャ]], [[防御階層原則(Level 1-6)]], [[因果辺トラバース統合パイプライン(Obsidian×セマンティック)]], [[インフラ設計意図カタログ]] -->
<!-- origin: [[semantic_search_timeout_infra_bug]] -> [[past_design_intent_unchecked_risk]] -> [[causal_verification_l0_l7_required]] -->
<!-- created: 2026-06-02 -->

## §1 結論

実装や運用変更の前に「なぜ現在の実装がそうなっているか」を確認することを、全ロール共通の前提にする。特にインフラ、hook/gate、daemon、記憶DB、配備フロー、検索/セマンティック系は、過去の事故・殿裁定・CLI差異を受けて一見不合理な形になっていることが多い。

禁止する行動: 現象だけを見て、git履歴・教訓・設計意図・因果辺を確認せずに「簡単な修正」「削除」「置換」「無効化」をすること。

## §2 三層記憶への貫通

| 層 | 保存先 | 役割 |
|----|--------|------|
| 第1層: 全文/履歴 | `data/multi_agent_shogun_memory.db`, `queue/lord_conversation.jsonl`, reports, git log | 何が起きたか、誰が何を裁定したかを残す |
| 第2層: 因果NW | Obsidian `[[link]]`, `origin`, `event_links`, `causal_backlinks.sh` | 発端→原因→結果、設計意図、過去事故との接続を残す |
| 第3層: 概念入口 | `docs/semantic-index/index.md`, `context/semantic-map.md`, `event_concepts` | 「因果確認」「設計意図」「なぜそうなっているか」から誰でも逆引きできるようにする |

## §3 multi-CLI前提

我らはmulti-CLIであり、Claude Code CLIのhookだけ、Codex CLIのhookだけ、特定CLIのStop/SessionStart挙動だけに依存してはならない。因果確認L0-L7の正本はCLI外の共通経路に置く。

| 層 | CLI非依存の正本 | CLI固有層の扱い |
|----|----------------|----------------|
| 指示/知識 | `AGENTS.md`, `instructions/*.md`, `context/*.md`, `docs/semantic-index/index.md` | Claude/Codexどちらでも読まれる圧縮索引として使う |
| タスク入口 | `queue/tasks/*.yaml`, `scripts/deploy_task.sh`, report template | hook差ではなく配備時注入で全CLIへ同じ入力を渡す |
| ゲート | `scripts/cmd_save.sh`, `scripts/gates/gate_report_format.sh`, `scripts/gates/gate_gunshi_report_precheck.sh` | hookは早期検出の補助。最終判定は共通scriptに置く |
| 記憶 | `data/multi_agent_shogun_memory.db`, `event_concepts`, `origin`, Obsidian links | CLI差に関係なく検索・注入できる |
| daemon補完 | `ninja_monitor.sh`, `inbox_watcher.sh`, startup gates | Codex Stop hookのように危険なeventはdaemon/gateで補完する |

結論: L4 BLOCKやL5事前コンテキスト提供をhook専用に実装してはならない。hookは使えるCLIでは補助するが、同じルールは共通script/gate/template/daemonで必ず成立させる。

## §4 L0-L7 防御階層

| Level | 名称 | 因果確認での意味 | 現状/実装先 |
|-------|------|------------------|-------------|
| L0 | 原理前提 | 「現在の実装には過去の経緯がある」を全判断の初期状態にする | `AGENTS.md`, `context/growth-loop.md` |
| L1 | 事後検出 | 報告/レビュー時に「因果未確認」を検出する | `gate_report_format.sh` の報告検査、`gate_gunshi_report_precheck.sh` SG-PRE21 |
| L2 | 事前予防(doc) | 変更前にgit log/blame/教訓/semantic/causalを確認せよと明文化 | 本設計書、`context/infrastructure.md`, role instructions |
| L3 | 事前強制(auto-gen) | task/reportテンプレートへ `cause_checked` / `design_intent_checked` を自動生成 | CLI非依存: `deploy_task.sh` / report template 次実装対象 |
| L4 | フロー内BLOCK | 重大変更で因果確認欄が空なら保存/報告を止める | CLI非依存: `cmd_save.sh` q5/q8/origin、`gate_report_format.sh`。hook BLOCKだけに置かない |
| L5 | 事前コンテキスト提供 | 対象ファイルの設計意図・関連教訓・因果辺を自動表示/注入 | CLI非依存: `cmd_save.sh` target causal, `deploy_task.sh` semantic/causal注入。拡張対象: git log/blame要約 |
| L6 | 学習速度最大化 | 因果未確認による失敗をlesson/weak_points/DB概念へ即還流し、次回配備に自動注入 | `lesson_candidate`, `projects/infra/lessons_*`, `event_concepts`, `deploy_task.sh` lesson boost |
| L7 | 記憶NW常時利用 | Obsidian/semantic/DBの三層から「なぜそうなったか」を全員がいつでも検索できる | `docs/semantic-index/index.md`, `context/semantic-map.md`, `data/multi_agent_shogun_memory.db` |

## §5 実行時の標準手順

変更前に最低限この4点を確認する。

1. `git log --oneline -- <target>` と必要行の `git blame` で導入cmd/事故を確認する。
2. `rg` で `projects/infra/lessons_*.yaml` と `docs/research/` の関連教訓・設計書を確認する。
3. `bash scripts/causal_backlinks.sh "<target stem or concept>"` と `bash scripts/semantic_search.sh "<現象/変更語>"` で因果NWと概念入口を確認する。
4. 報告またはcmdに「導入理由」「守るべき設計意図」「今回壊れている因果」を3行以上で残す。

## §6 判定基準

PASS:
- 過去の設計意図を壊さない修正になっている。
- 過去の意図が古くなっている場合、古いと判断した根拠と置換後の防御が明記されている。
- `origin` または `cause_checked` に `[[発端]] -> [[原因]] -> [[結果]]` がある。

FAIL:
- 「長い」「重い」「邪魔」「不要そう」だけで削除/無効化している。
- git履歴・教訓・設計意図を見ずに、現象だけで修正している。
- 過去に入った防御を消すのに、代替防御がない。

## §7 直近適用例

`semantic_search.sh` 長時間化はインフラバグだが、memory DB FTS fallback自体は `LS-A23` のgrep脱却原則と `cmd_2994` の三層記憶到達性確保が起源。正しい修正はFTS削除ではなく、`cmd_2998` のbounded化意図を回復し、`cmd_3068/3070` のranking品質を全走査なしで保つこと。

因果: `[[LS-A23]] -> [[memory_db_fts_fallback]] -> [[semantic_search_timeout]] -> [[bounded_causal_fix_required]]`

## §8 次実装CMD候補

目的: 因果確認L0-L7をスクリプト強制へ昇格する。

AC候補:
- `deploy_task.sh` が infra/hook/gate/daemon/search/semantic対象taskへ `cause_checked` テンプレートを自動注入する。
- `gate_report_format.sh` が該当scopeで `cause_checked` 空をWARN以上にする。
- `cmd_save.sh` が hook/gate/daemon/semantic対象cmdで `quality_gate.q_causal_checked` を要求する。
- `causal_backlinks.sh` / `semantic_search.sh` の結果を `cmd_save.sh` preflight表示へ統合し、L5事前コンテキストを強化する。
- `.claude/settings.json` / `.codex/hooks.json` は補助生成物扱いにし、共通イベント層または共通gateで同じ因果確認を保証する。
