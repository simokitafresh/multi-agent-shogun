# Model Comparison: GPT 5.5 vs Sonnet 4.6 vs Sonnet 5 vs Opus 4.8

## 5W1H Summary

### WHO (誰が使うか)

| Model × Effort | CLI | 主な使用者 | 編成ロール |
|----------------|-----|-----------|-----------|
| GPT 5.5 low | Codex | hayate | 定型修正, CI fix(最速・最安) |
| GPT 5.5 medium | Codex | kagemaru | 定型修正(lowより推論力あり) |
| Sonnet 4.6 high | Claude Code | hanzo, kotaro | CI fix, hotfix, 中品質定型作業 |
| Sonnet 5 xhigh | Claude Code | tobisaru | 実装, 研究, 深掘り調査 |
| Opus 4.8 xhigh | Claude Code | saizo, 将軍 | 偵察, 設計, 最高品質タスク |

### WHAT (何が違うか)

#### Model × Effort Level 個別評価（5ラウンド累積, cmd_3620-3624）

根拠データ: [[sonnet5_vs_46_ab_evaluation_20260701]] の各ラウンド記録（cmd_3620-3624）。

関連文脈: [[training-cycle]] §24-25のmixed編成修行では、テンプレート有無でGPT/Opus/SonnetのFP率差が反転しており、モデル別運用判断の補助証拠になる。

補助根拠: [[cmd_3620_sonnet5_vs_46_ab_20260701]] は初回A/B評価の出発点、[[gate_fire_log_before_20260607]] はgate計測データの扱いを確認するための参照先。

| 指標 | GPT 5.5 low | GPT 5.5 medium | Sonnet 4.6 high | Sonnet 5 xhigh | Opus 4.8 xhigh |
|------|------------|---------------|----------------|---------------|---------------|
| **速度** | ★★★★ ~3分 | ★★★★ ~4分 | ★★★ ~5分 | ★★ ~10分 | ★★ ~12分 |
| **深度** | ★ 表層のみ | ★ 表層(lowと同等) | ★★ 表層的だが正確 | ★★★ 構造的根因到達 | ★★★★ 全層統合 |
| **バグ発見** | ★ 0件(見落とし) | ★ 0件(見落とし) | ★★★ 2件発見 | ★★★★ 4件網羅 | ★★★★ 全層+予言 |
| **自発的発見** | ★ なし | ★ テスト不足1件 | ★ 計1件/5R | ★★★ 計6件+/5R | ★★★★ 計10件+/3R |
| **テスト設計** | ★ なし | ★ 最小限 | ★★ 最小限 | ★★★ 網羅的 | ★★★★ before/after実証 |
| **証拠精度** | ★ 浅い | ★ 浅い | ★★ 1件ずれ | ★★★ 完全一致 | ★★★★ 決定論的予言 |
| **教訓生成** | ★ なし | ★ テスト不足のみ | ★★ 既存参照 | ★★★ knowledge/decision自発 | ★★★★ 多段パッチ+回帰ガード |
| **コスト** | ★★★★ 最安 | ★★★ 安い | ★★★ effort=high | ★★ effort=xhigh | ★ xhigh+Opus(最高) |

#### GPT 5.5 low vs medium の差異

| 観点 | GPT 5.5 low | GPT 5.5 medium |
|------|------------|---------------|
| 推論トークン | 制限あり(fast思考) | 中程度(standard思考) |
| 速度 | ~3分（最速） | ~4分（lowより1分遅い） |
| R5残存バグ発見 | 0件 | 0件 |
| R5 lesson_candidate | テスト不足(汎用) | テスト不足+launch_cmd具体名 |
| 曖昧なタスクへの反応 | 即座に定型的に進む | 即座に定型的に進む(lowと差なし) |
| CLI | Codex(Stop hookなし) | Codex(Stop hookなし) |
| 所見 | 最速だが最も浅い。単純な期待値追従に最適 | lowとほぼ同等の深度。medium effortの追加推論がバグ発見力に寄与していない |

#### Sonnet 4.6 high vs Sonnet 5 xhigh の差異

| 観点 | Sonnet 4.6 high | Sonnet 5 xhigh |
|------|----------------|---------------|
| 推論トークン | high(標準思考) | xhigh(拡張思考) |
| 速度 | ~5分 | ~10分（2倍） |
| 根因分析 | 表層(SIGHUP/disown漏れ等の1行修正レベル) | 構造的(dual lock race等の設計前提崩壊まで追跡) |
| 証拠精度 | 17件(1件ずれ) | 18件(完全一致) |
| 曖昧なタスクへの反応 | そのまま定型的に進む | 家老に確認質問を出す(安全だがlatency増) |
| 副作用分析 | 1件程度 | 3件程度 |
| 自発的知見 | 既存教訓参照のみ | knowledge/decision候補を自発生成 |
| 原因コミット追跡 | なし | あり(git log追跡で原因commit特定) |
| CLI | Claude Code(全hook対応) | Claude Code(全hook対応) |
| 所見 | 速度と品質のバランスが良い。定型修正の主力 | 深掘りに強い。構造的根因に到達。コストは2倍だが品質も2段階上 |

#### Opus 4.8 xhigh の固有特性

| 観点 | Opus 4.8 xhigh |
|------|---------------|
| 推論トークン | xhigh(最大思考) |
| 速度 | ~12分(最遅) |
| 根因分析 | 全層統合(他モデルの分析を包含して上回る) |
| R3実績 | kotaro説(非同期)+tobisaru説(dual lock)を統合し構造根因確定 |
| R4実績 | 次deployでのバグ発現を決定論的に予言(100%再現) |
| 修正案設計 | 4段階パッチ(核心→推奨→任意×2) |
| 副作用分析 | 6件(S1-S6, 網羅的) |
| テスト設計 | 6本(before/after定量実証含む) |
| task_clarity | 95(最高。曖昧でも高精度で意図把握) |
| CLI | Claude Code(全hook対応) |
| 所見 | 最高品質だが最高コスト。偵察・設計・バグ調査で他モデルを圧倒。定型作業には過剰 |

#### モデル別の行動パターン

| 状況 | GPT 5.5 low | GPT 5.5 medium | Sonnet 4.6 high | Sonnet 5 xhigh | Opus 4.8 xhigh |
|------|------------|---------------|----------------|---------------|---------------|
| 曖昧なタスク | 即進む | 即進む | 即進む(定型的) | 確認質問を出す | 高精度で意図把握 |
| バグ調査 | 表層で完了 | 表層で完了 | 実証付きで正確 | 原因commit追跡 | 決定論的予言 |
| 修正案 | 1行 | 1行 | 1行(正確) | 2行(構造的) | 4段階パッチ |
| 副作用考慮 | なし | なし | 1件 | 3件 | 6件(網羅) |
| gate FAIL時 | 修正が浅い | 修正が浅い | 正確に修正 | 根因まで修正 | 根因+横展開 |

### WHEN (いつ使うか)

| 状況 | 推奨 | 理由 |
|------|------|------|
| CI RED即修正(テスト期待値追従等) | GPT 5.5 low | 最速3分。表層修正で十分な場面 |
| CI RED修正(ロジック変更伴う) | Sonnet 4.6 high | 正確性が必要。GPTでは見落としリスク |
| hotfix(1-2行修正) | Sonnet 4.6 high | 定型的で正確。コスト最小(Claude系) |
| 機能実装(FE/BE) | Sonnet 5 xhigh | 構造理解。gate FAIL率低い |
| バグ根因調査 | Opus 4.8 xhigh | 決定論的予言+原因コミット追跡 |
| 設計書作成 | Opus 4.8 xhigh | 全層統合+副作用網羅+テスト設計 |
| 偵察(広範囲調査) | Sonnet 5 or Opus 4.8 | 自発的発見数が多い |
| コスト制約時 | GPT low → S4.6 → S5 | effortとモデルを段階的に上げる |

### WHERE (どこで使うか)

| プロジェクト | 推奨編成 |
|-------------|---------|
| multi-agent-shogun (infra) | Opus(偵察/設計) + S5(実装) + S4.6(CI fix) + GPT(単純修正) |
| DM-Signal (backend) | S5(計算ロジック) + S4.6(API修正/テスト追従) |
| DM-Fusion (frontend) | S5(UI実装) + S4.6(スタイル修正) |

### WHY (なぜこの使い分けか)

1. **コスト vs 品質のトレードオフ**: Opus 4.8 xhighはGPT 5.5 lowの10倍以上のコスト。全タスクにOpusを使うと消費が爆発する。品質が必要な場面だけOpusを投入し、定型作業はGPT/S4.6で回す
2. **effort levelの効果はモデル依存**: GPT 5.5ではlow→mediumでほぼ差なし(バグ発見0件→0件)。Sonnet系ではhigh→xhighで深度が劇的に向上(表層→構造的根因)。effort投資はClaude系に集中すべき
3. **深度の差は再発リスクに直結**: S4.6は「何を直すか」、S5は「なぜ壊れたか」、Opusは「次にどこで再発するか」まで到達。深度が浅い=表層修正→再発
4. **GPT 5.5のCLI制約**: Codex CLIはStop hookなし。brainwash_checkやinbox確認の自動強制が効かない。深度が必要なタスクでは構造的に不利
5. **速度の差は殿の待ち時間**: GPT 3分 vs Opus 12分。CI REDの緊急修正では9分の差が直結

### Claude effort level別の特性（既知情報+推定）

| Model | low | high | xhigh |
|-------|-----|------|-------|
| **Sonnet 4.6** | 未計測 | **今回計測**: 表層的だが正確、速度~5分 | 未計測（Sonnet 4.6はhighが標準運用） |
| **Sonnet 5** | 未計測 | 未計測 | **今回計測**: 構造的根因到達、速度~10分 |
| **Opus 4.8** | 未計測 | 未計測 | **今回計測**: 全層統合+予言、速度~12分 |

**注**: 今回のA/B/Cは各モデルを固定effortで比較した。effort別の比較（例: Sonnet 5 high vs xhigh）は未実施。

**effort levelの効果に関する仮説**:
- **GPT 5.5**: low→mediumでバグ発見力に差なし（R5実証）。effort投資の限界収益が低い
- **Sonnet 4.6**: highで十分な品質。xhighにすると深度が上がる可能性があるが未検証
- **Sonnet 5**: xhighで構造的根因に到達。highに下げると深度が落ちてS4.6 highと差が縮まる可能性
- **Opus 4.8**: xhighで全層統合。highに下げた場合の影響は未検証だが、Opusの思考深度がeffort依存である可能性が高い

**次の検証候補**: Sonnet 5 high vs Sonnet 5 xhigh の同一cmd比較で、effort投資の限界収益を定量化する

### HOW (どう運用するか)

1. **settings.yamlで忍者別にmodel+effortを設定**: cli_profilesの各エントリでmodel/effortを個別指定
2. **家老がタスク種別×必要深度で配備先を選定**: 単純修正→GPT、定型修正→S4.6、実装→S5、偵察/設計→Opus
3. **軍師がレビュー時にモデル差を考慮**: GPT報告は表層でも正確なら許容。S5/Opus報告は深度を期待
4. **コスト監視**: 週次メトリクスでモデル別トークン消費を追跡
5. **effort昇格ルール**: GPTでFAIL→S4.6に再配備。S4.6でFAIL→S5に再配備。段階的にeffort/モデルを上げる

## 評価方法

- 5ラウンド(cmd_3620-3624)で同一タスクを並列配備
- カテゴリ: 偵察(R1) → 根因調査(R2) → infra改善設計(R3) → バグ調査(R4) → 四者横断(R5)
- 参加: R1-2=S4.6+S5, R3-4=S4.6+S5+Opus 4.8, R5=GPT low+GPT med+S4.6+S5
- 計測: 既存インフラ(gate_fire_log, karo_workarounds, review_log, タイムスタンプ)
- 詳細データ: [[sonnet5_vs_46_ab_evaluation_20260701]]

## 裁定

- 殿承認(2026-07-01): 多層編成(偵察/設計=Opus, 実装/研究=S5, CI fix=S4.6, 定型速度優先=GPT 5.5)
- 殿指摘(2026-07-01): model×effort levelで分離して記載。low/mediumをまとめるな
