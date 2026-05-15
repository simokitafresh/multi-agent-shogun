# セマンティック辞書 網羅性監査結果
<!-- generated: 2026-05-15T14:36:00+09:00 by gunshi idle analysis (殿指示) -->

## 背景

殿指示: 「セマンティック辞書に記載されていない有用な知識がないか確認しよう」
cmd_2775偵察結果(4スクリプト277関数、context未記載238件)と連動した監査。

## 計測データ

| 指標 | 値 |
|------|-----|
| 辞書概念数 | 19 |
| contextファイル数 | 51 |
| 辞書にマッピング済み | 21(41%) |
| 未マッピング | 30(59%) |
| cmd_2775偵察: 関数総数 | 277(実測288) |
| context記載率 | 14%(39/277) |
| 高優先度暗黒物質 | 60関数 |

## 新概念候補5件

### 1. gs_ninpo_research(GS/忍法研究知見) — 優先度1

浮いているcontext 9本:
- `context/gs-speedup-knowledge.md`
- `context/gstack-knowledge.md`
- `context/gunshi-gs-landscape-analysis.md`
- `context/gunshi-gs-speed-optimization-design.md`
- `context/gunshi-flair-deepdive.md`
- `context/gunshi-opt12-analysis.md`
- `context/gunshi-metrics-engine-design.md`
- `context/gunshi-interpretation-layer-design.md`
- `context/gunshi-4metrics-design.md`

aliases候補: GS, grid_search, 忍法, ninpo, L1, wf_engine, gstack, FLAIR, メトリクスエンジン, 解釈層, opt12

### 2. silent_fallback_quality(Silent Fallback/インフラ品質) — 優先度2

浮いているcontext 4本:
- `context/gunshi-silent-fallback-analysis.md`
- `context/gunshi-infra-perf-audit.md`
- `context/gunshi-nazenaze-synthesis.md`
- `context/slop-scan-dont-fix.md`

aliases候補: silent_fallback, PI-018, エラー握りつぶし, infra_perf, slop_scan, なぜなぜ統合

### 3. skill_design_rules(スキル/UIデザインルール) — 優先度3

浮いているcontext 3本:
- `context/skill-design-rules.md`
- `context/ui-design-guide.md`
- `context/doc-style-guide.md`

aliases候補: skill_design, TRIGGER, ui_design, doc_style, 1024字制限, Adham Dannaway

### 4. dmsignal_operations(DM-Signal運用/FE全体像) — 優先度4

浮いているcontext 4本:
- `context/dm-signal.md`
- `context/dm-signal-frontend.md`
- `context/dm-signal-ops.md`
- `context/auto-ops.md`

aliases候補: dm-signal_ops, frontend, auto-ops, Render_deploy, ETL, cron

### 5. google_classroom(Google Classroom PJ) — 優先度5

浮いているcontext 1本:
- `context/google-classroom.md`

aliases候補: google-classroom, Playwright, Render_cronjob, headless

## 追加不要と判定したもの

| カテゴリ | 理由 |
|---------|------|
| cmd-chronicle, senkyoku-log, lord-conversation-index | 運用記録であり概念ではない |
| milk, neo-design-exploration, oshio-comparison | 別PJ/温め中。アクティブ化時に追加 |
| FoF/奥義(checklist-ward-fof, l2-okugi-progress) | ALMディスコン(殿裁定)。話題禁止 |
| gunshi個別分析(fof-deterioration等) | 上位概念(gs_ninpo_research等)に含まれる |

## 関数レベルの分析(cmd_2775との連携)

高優先度60関数は全て既存19概念にマッピング可能。関数レベルの新概念は不要。
辞書のギャップはトピックレベル(上記5件)にある。

## 因果鎖

```
context 30本が辞書概念に未マッピング(根因)
  → semantic_search.shでキーワード検索しても到達しない
  → cmd起票時にcmd_save.sh aliases照合で関連contextが提案されない
  → 忍者が関連知識なしで作業→assumption崩壊→workaround
  → 辞書に概念+aliases追加で到達経路確立→自動提案→崩壊減少=正の複利
```

## 複利の問い

5概念を辞書に追加し10回cmdが起票されたら？ → 毎回aliases照合で関連contextが自動提案。30本のcontextが「見えない知識」から「自動到達する知識」に変わる=正の複利。
放置したら？ → 30本のcontextが参照されず陳腐化→メンテ不要と誤判定→削除→知識消失=負の複利。
