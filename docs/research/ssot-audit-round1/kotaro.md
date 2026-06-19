# SSOT Audit Round 1 — kotaro

<!-- SSOT参照: 忍者名の正本は get_ninja_names() (scripts/lib/agent_config.sh) / config/settings.yaml -->

task_id: `cmd_3458_kotaro_normal`
scope: `docs/**`, `context/**`, `instructions/**`, `projects/infra/*.yaml`, `AGENTS.md`
generated_at: `2026-06-20T04:30:00+09:00`

## Summary

| AC | Result | Evidence |
|---|---|---|
| AC1 | PASS | rg実測でスコープ内のハードコード20件を抽出 |
| AC2 | PASS | SSOT列(正本ファイル+関数名/SSOTなし)と修正候補を全行に記入 |
| AC3 | PASS | docs/context/instructions間の同一運用ルール二重定義4件を検出 |
| AC4 | PASS | 本ファイル作成完了 + 件数サマリを報告YAMLに記録 |

## 実測コマンド

```bash
# 旧エージェント名(config/settings.yamlから削除済み)
rg -n "sasuke|kirimaru" docs/ context/ instructions/ projects/infra/ AGENTS.md

# 削除済みスキル
rg -n "hensei|/reset-layout|shogun-all-codex-switch|shogun-peacetime-rollback" docs/ context/ instructions/ AGENTS.md

# ペイン番号ハードコード
rg -n "shogun:2\.[0-9]|shogun:1\.[0-9]" docs/ context/ instructions/ AGENTS.md

# モデル名ハードコード
rg -n "assign_to_model" context/ instructions/ AGENTS.md

# 絶対パスハードコード (例示用途)
rg -n "target_path.*mnt/c/tools" instructions/roles/
```

| category | rg hits (live docs, archive除く) | reading |
|---|---:|---|
| 旧エージェント名 (config/settings.yamlから削除済み) | 46 | instructions/roles/ + AGENTS.md に集中。generated/ はbuild pipeline産物 |
| 削除済みスキル参照 | 12 | AGENTS.md + context/infrastructure.md + docs/semantic-index + context/semantic-map |
| ペイン番号ハードコード | 8 | instructions/shogun.md, karo.md, ashigaru.md, roles/karo_role.md |
| モデル名ハードコード(要対処) | 1 | context/karo-operations.md |
| 絶対パスハードコード(例示) | 2 | instructions/roles/karo_role.md |

## Hardcode Table (AC1 + AC2)

### H-01: 旧エージェント名 — SSOT: `config/settings.yaml` via `get_ninja_names()`

現在 config/settings.yaml に存在しない2名 (`sasuke`, `kirimaru`) がドキュメントに残存。
正本は `scripts/lib/agent_config.sh:get_ninja_names` が `config/settings.yaml` から動的取得する。

| file:line | kind | value | SSOT | 修正候補 |
|---|---|---|---|---|
| `AGENTS.md:41` | agent roster | pane_1/pane_2 に旧エージェント名 | `config/settings.yaml` | 現行rosterに更新 |
| `AGENTS.md:170` | example name | `(e.g., sasuke, hanzo)` | `config/settings.yaml` | `(e.g., hayate, hanzo)` に更新 |
| `instructions/roles/karo_role.md:62-88` | task examples | 旧エージェント名を例示忍者として使用 | `config/settings.yaml` | 現行忍者名に置換。generated/\*-karo.md はbuild_instructions.sh再実行で自動更新 |
| `instructions/roles/karo_role.md:164` | agent table | Codex忍者リストに旧名を含む | `config/settings.yaml` | 現行Codex忍者に合わせ更新 |
| `instructions/roles/karo_role.md:284` | task YAML example | `assigned_to: {旧エージェント名}` | `config/settings.yaml` | 現行忍者名またはプレースホルダに置換 |
| `instructions/roles/ashigaru_role.md:23` | report template | `worker_id: {旧エージェント名}` | `config/settings.yaml` | `worker_id: {ninja_name}` プレースホルダに変更 |
| `instructions/ashigaru-procedures.md:77-124` | procedure examples | 旧エージェント名のreport filename例示 | `config/settings.yaml` | `{ninja_name}` 形式のプレースホルダに変更 |
| `instructions/generated/{all}-karo.md` | (auto-generated) | 上記karo_role.md産物 | 上記source | build_instructions.sh 再実行で自動修正 |
| `instructions/generated/{all}-ashigaru.md` | (auto-generated) | 上記ashigaru_role.md産物 | 上記source | build_instructions.sh 再実行で自動修正 |

### H-02: 削除済みスキル参照 — SSOT: `skills/*/SKILL.md` の物理的存在

削除済みスキル: `hensei`, `hensei-mixed`, `hensei-opus`, `reset-layout`, `shogun-all-codex-switch`, `shogun-peacetime-rollback`
上位互換: `skills/shogun-cli-switch/SKILL.md`（CLI切替/respawn/編成/version/hensei系5本+reset-layout吸収済み）

| file:line | kind | value | SSOT | 修正候補 |
|---|---|---|---|---|
| `AGENTS.md:547` | skill ref | `/reset-layout\|agentsウィンドウ一発復元\|skills/reset-layout/SKILL.md` | `skills/shogun-cli-switch/SKILL.md` | `/shogun-cli-switch` に更新 |
| `context/infrastructure.md:168-174` | section | `/henseiスキル（cmd_1673）` セクション全体 | なし(廃止) | 廃止注記+shogun-cli-switchへの参照に変更 |
| `context/infrastructure.md:1402-1408` | obsidian links | `[[shogun-all-codex-switch]]` 等4件 | `skills/shogun-cli-switch/SKILL.md` | `[[shogun-cli-switch]]` に集約 |
| `context/semantic-map.md:99` | skills column | `reset-layout(全ペイン配置復元)` in active skills | `skills/shogun-cli-switch/SKILL.md` | `reset-layout` 除去。shogun-cli-switchの説明に「ペイン復元含む」追記 |
| `docs/semantic-index/index.md:1973` | file reference | `skills/reset-layout/SKILL.md` | なし(削除済み) | エントリ削除または廃止注記 |
| `docs/semantic-index/index.md:2216-2217` | file references | shogun-all-codex/peacetime SKILL.md各1件 | なし(削除済み) | エントリ削除 |
| `docs/semantic-index/index.md:4138` | skills list | `reset-layout(全ペイン配置復元)` in active skills routing | `skills/shogun-cli-switch/SKILL.md` | shogun-cli-switchに統合済みとして更新 |

### H-03: ペイン番号ハードコード — SSOT: `scripts/lib/pane_lookup.sh`

注: `instructions/karo.md:122` は「pane番号の直接指定(shogun:2.X)は禁止。上記lookupで動的解決せよ」と明記しているが、同ファイルと他のsource fileに shogun:2.1 ハードコードが残存している（矛盾）。

| file:line | kind | value | SSOT | 修正候補 |
|---|---|---|---|---|
| `instructions/shogun.md:104,132,208` | pane target x3 | `shogun:2.1` (karo pane) | `scripts/lib/pane_lookup.sh:pane_lookup` | 動的lookup形式に変更またはコメントで「例示値。実態はpane_lookup参照」明示 |
| `instructions/karo.md:119` | self reference | `self: shogun:2.1` | `tmux display-message` | 動的取得に変更。直下L122で直接指定禁止と矛盾 |
| `instructions/ashigaru.md:153` | pane target | `karo: shogun:2.1` | `scripts/lib/pane_lookup.sh` | 動的lookup形式に更新 |
| `instructions/roles/karo_role.md:162-164` | agent table | 各ペインに固定番号 | `config/settings.yaml`+`pane_lookup.sh` | テーブルを「pane番号はpane_lookupで動的取得」注記に変更 |
| `instructions/generated/{all}-shogun.md` | (auto-generated) | shogun:2.1 | 上記 shogun.md + roles/ | shogun.md修正後にbuild_instructions.sh再実行 |
| `instructions/generated/{all}-karo.md` | (auto-generated) | shogun:2.1 (pane table) | 上記 karo_role.md | karo_role.md修正後に再実行 |

### H-04: モデル名ハードコード — SSOT: `config/settings.yaml`

| file:line | kind | value | SSOT | 修正候補 |
|---|---|---|---|---|
| `context/karo-operations.md:378` | config field | `assign_to_model: opus` | `config/settings.yaml:cli.agents.*.model_name` | コメント化またはconfig参照に変更。偵察配備例だが固定モデル名 |
| `context/infrastructure.md:181-182` | model table | `--model opus` / `--model sonnet` 比較表 | なし(意図的説明) | 変更不要。`--model`フラグが200K制限を招く警告として意図的に記載 |

### H-05: 絶対パスハードコード(例示) — SSOT: 相対パスまたは `${SHOGUN_ROOT}`

| file:line | kind | value | SSOT | 修正候補 |
|---|---|---|---|---|
| `instructions/roles/karo_role.md:77` | example path | `target_path: "/mnt/c/tools/multi-agent-shogun/hello1.md"` | `${SHOGUN_ROOT}` | プレースホルダ `"<repo_root>/hello1.md"` に変更 |
| `instructions/roles/karo_role.md:89` | example path | `target_path: "/mnt/c/tools/multi-agent-shogun/reports/..."` | `${SHOGUN_ROOT}` | 同上 |

## Duplicate Definitions (AC3)

### D1: CI RED自走修正ルール (2箇所)

同一ルールが重複定義されている:
- `AGENTS.md:476` — `CI RED自走修正(殿裁定2026-04-15)|家老がCI RED検知→idle忍者に即修正配備。将軍cmd不要`
- `instructions/karo.md:426` — `CI RED検知時は待つな。即修正せよ。将軍cmdは不要。家老判断でidle忍者に修正を配備する。`

修正候補: AGENTS.md がSSOT。instructions/karo.md は `→ AGENTS.md §CI RED自走修正参照` に圧縮。

### D2: 削除済み `/reset-layout` スキルの「現役」記載 (3箇所)

同一スキルが現役として3箇所に記載されているが実体は `skills/reset-layout/` が削除済み:
- `AGENTS.md:547` — Skillsセクションで現役スキルとして列挙
- `context/semantic-map.md:99` — スキルルーティング行のskills列に列挙
- `docs/semantic-index/index.md:4138` — スキルルーティング索引のskills列に列挙

修正候補: `skills/*/SKILL.md` の物理的存在がSSOT。3箇所とも `shogun-cli-switch` に吸収済みと明示。

### D3: 忍者push禁止ルール (2箇所)

同一ルールが2箇所に定義:
- `AGENTS.md:155` — `他の忍者のファイルに触れるな。pushするな。commitまで。`
- `instructions/ashigaru.md:295` — `commit→push禁止→レビュー忍者PASS後にpush。一人で書いて一人で通すのは禁止`

内容が微妙に異なる(AGENTS.mdはcommitまで、ashigaru.mdはレビュー後push言及)。整合確認が必要。
修正候補: instructions/ashigaru.mdは自己完結性のため一定の重複は許容。ただし内容を整合させる。

### D4: 現役スキル一覧の重複管理 (2ファイル)

- `context/semantic-map.md` — 各概念行のskills列に利用可能スキルを列挙
- `docs/semantic-index/index.md` — 同一の concepts に同じスキル列を列挙

一方が更新されてももう一方が陳腐化するリスク(実際にD2と同じ問題が発生中)。
修正候補: `context/semantic-map.md` をSSOTとし、`docs/semantic-index/index.md` はskill名のみ保持(詳細はsemantic-mapを参照)。または semantic-index を自動生成化。

## 件数サマリ (AC4)

| category | 件数(ソースファイルベース) | 影響ファイル数 |
|---|---:|---:|
| H-01: 旧エージェント名 | 7ソース行グループ | 4ソースファイル + generated/* 自動更新 |
| H-02: 削除済みスキル参照 | 11件 | 5ファイル |
| H-03: ペイン番号ハードコード | 6件 | 3ソースファイル + generated/* 自動更新 |
| H-04: モデル名ハードコード(要対処) | 1件 | context/karo-operations.md |
| H-05: 絶対パスハードコード(例示) | 2件 | instructions/roles/karo_role.md |
| **合計ハードコード** | **27件** | **10ソースファイル** |
| D1: CI RED自走修正二重定義 | 2箇所 | 2ファイル |
| D2: 削除スキルの現役記載 | 3箇所 | 3ファイル |
| D3: push禁止二重定義 | 2箇所 | 2ファイル |
| D4: スキル一覧二重管理 | 2ファイル | 2ファイル |
| **合計二重定義** | **9箇所** | **7ファイル** |

## 修正優先度

| 優先 | 対象 | 理由 |
|---|---|---|
| 🔴 高 | H-01 (旧エージェント名) + H-02 (削除済みスキル) | 存在しないエージェント名・スキルが運用指示に残存 → 誤動作リスク |
| 🔴 高 | H-03 pane番号 (instructions/karo.md:119-122 矛盾) | 禁止ルールを宣言しつつ同ファイルでハードコード → 矛盾 |
| 🟡 中 | D2 (reset-layout現役記載3箇所) | 削除済みスキルが索引に現役として残存 → スキル選択誤り |
| 🟡 中 | H-05 (karo_role.md 絶対パス例示) | 例示パスが特定環境に依存 → 他環境での誤解 |
| 🟢 低 | D1, D3 (ルール重複) | 内容整合しているため即時リスクは低い |
| 🟢 低 | D4 (スキル一覧二重管理) | 即時不整合あり(D2と同根)。仕組み改善で解決 |

## 注記

- `instructions/generated/**` はすべて `build_instructions.sh` の自動生成物。ソースファイル修正後に `bash scripts/build_instructions.sh` を実行すれば自動更新される。generated/への直接修正は禁止。
- `docs/obsidian-promoted/**` および `context/senkyoku-log.md`, `context/cmd-chronicle.md` の旧スキル名参照は**歴史記録**として意図的に保持。修正対象外。
- `instructions/common/forbidden_actions.md:60` の旧エージェント名参照は「cmd_020インシデント記述」として歴史的経緯を保持。修正対象外。
- `context/l3-robustness.md` の旧エージェント名参照は研究記録(旧編成時点)。修正対象外。
