# 五者対比図 — われら / ACE / Vercel / おしお / Claude Teams

> 作成: 2026-03-01 cmd_473完了時点
> おしお殿リスペクト原則: おしお殿(fork元)は元祖。優劣ではなく系譜と進化の文脈で対比

## 1. 設計思想

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **本質** | 戦国軍団統治 | 自己進化する文脈 | 最小構成で最大効果 | AI部下10人の組織論 | 並列探索チーム |
| **比喩** | 封建制(鎖の原理) | 学習する教科書 | 削ぎ落とした刀 | 殿様と足軽の対話 | 会議室の議論 |
| **核心問い** | 鎖を切らずに全軍を動かせるか | LLMの文脈を崩壊させずに育てられるか | ツールの80%を捨てても勝てるか | AIに組織を任せたら何が起きるか | 並列作業で品質を保てるか |
| **人間の関与** | 殿(人間)が頂点。将軍は代行 | 人間なし(全自動) | Human-in-the-loop(要所のみ) | 殿が適当にしゃべるだけ | リードが承認ゲート |

## 2. 組織構造

```
われら                     ACE                    Vercel
殿(人間)                  ┌──────────┐            ┌──────────┐
 ↓                        │Generator │            │ v0/Agent │
将軍(Opus)                │ (実行)   │            │ (単体)   │
 ↓                        └────┬─────┘            └────┬─────┘
家老(Claude)                   ↓                       ↓
 ↓                        ┌──────────┐            ┌──────────┐
忍者×8(Opus/Codex)        │Reflector │            │3層パイプ │
                          │ (批評)   │            │注入→補正 │
                          └────┬─────┘            │→後処理  │
                               ↓                  └──────────┘
                          ┌──────────┐
                          │ Curator  │
                          │(統合)    │
                          └──────────┘

おしお(元祖)               Claude Teams
殿(人間)                  ┌──────────┐
 ↓                        │Team Lead │
将軍                      │(メイン)  │
 ↓                        └────┬─────┘
家老                           ↓
 ↓                        ┌────┴─────┐
足軽×8                    │Teammate  │×3-5
                          │(独立)    │
                          └──────────┘
```

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **階層数** | 4層(殿→将軍→家老→忍者) | 3役割(並列) | 1-2層 | 4層(同構造) | 2層(Lead→Teammates) |
| **エージェント数** | 10(将軍1+家老1+忍者8) | 3(役割固定) | 1(単体) | 10(同構造) | 3-5(推奨) |
| **指揮系統** | 鎖(一本、分岐なし迂回なし) | パイプライン(線形) | なし(単体) | 階層制 | リード集約 |
| **モデル混成** | Opus4+Codex4(混成編隊) | 単一モデル | 単一(Opus推奨) | Claude統一 | 任意指定可 |

## 3. 知識管理 — 最重要軸

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **知識の形態** | 教訓YAML+6層保存先 | Playbook(弾丸リスト) | Registry+System Prompt | YAML+MCP Memory | なし(セッション内のみ) |
| **生成者** | 忍者(lesson_candidate) | Reflector(自動) | 人間(手動設定) | 足軽→家老 | なし |
| **審査者** | 家老(人間審査ゲート) | Curator(自動) | なし | 家老 | なし |
| **注入方式** | タグマッチ+キーワードスコアリング(上位7+universal3) | 全量注入 or 適応サンプリング | 埋込み時注入(静的) | タスクYAML注入 | CLAUDE.md自動ロード |
| **効果計測** | helpful/injection_count+自動帰属(ACE Reflector方式) | helpful/harmful dual counter | なし(成功率で間接計測) | — | なし |
| **淘汰** | deprecation_scan(injection≥10&helpful=0) | semantic dedup+counter比 | 手動更新 | — | なし |
| **永続性** | ファイル(git管理)+MCP Memory | ファイル | Registry(API) | ファイル+MCP | セッション消滅で喪失 |
| **サイクル** | 8段階(発見→登録→注入→活用→帰属→計測→表示→淘汰) | 3段階(生成→反映→統合) | なし(静的) | 注入→活用 | なし |

## 4. タスク分解と品質管理

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **分解単位** | cmd→subtask(AC付き) | タスク→軌跡 | 手動→コード→テスト | cmd→タスク | Task List(JSON) |
| **品質ゲート** | GATE(関所)=BLOCK/CLEAR | Evaluator(自動) | Sandbox実行検証 | — | Plan Approval |
| **レビュー** | 別忍者によるコードレビュー必須 | Reflector(自動批評) | 人間レビュー | レビュー体制 | リード承認 |
| **並列実行** | ファイル依存分析→parallel_with | バッチ並列 | 単体(並列なし) | 並列配備 | Worktree分離 |
| **失敗時** | BLOCK→家老差戻し→再配備 | 軌跡分析→教訓追加 | Autofixer(自動修正) | 差戻し | リード再割当 |
| **品質実績** | CLEAR率98%超、連勝114 | AppWorld +10.6% | 成功率80→100% | — | — |

## 5. コンテキスト管理

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **崩壊防止** | Vercel式2層圧縮+外部退避 | Delta Updates(差分のみ) | 3層パイプライン | — | 独立CTX窓 |
| **CTX戦略** | 受動ロード(自動)>能動取得(判断2回) | 全量注入(Brevity Bias回避) | 静的注入+LLM Suspense | 自動ロード | CLAUDE.md自動ロード |
| **圧縮** | 索引層(context/*.md)+詳細層(docs/research/) | Grow-and-Refine(遅延精製) | Context+(AST+clustering) | — | 独立窓(圧縮不要) |
| **復帰耐性** | 陣形図+hook+inbox(完全復帰) | なし(ステートレス) | なし | — | セッション再開不可 |
| **CTX上限対策** | autocompact(90%)+/clear+archive | lazy refinement(semantic dedup) | token-aware pruning | /clear | 独立窓(1M tokens) |

## 6. 通信と協調

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **方式** | ファイルmailbox(flock排他) | パイプライン(非同期) | API(型安全) | ファイルmailbox | ファイルmailbox |
| **配信** | inbox_write.sh→inotifywait→nudge | 関数呼出し | SDK呼出し | inbox仕組み | 自動配信 |
| **報告** | Report YAML→dashboard.md | 軌跡→Reflector | JSON→ダッシュボード | 報告YAML | TaskUpdate |
| **禁則** | 忍者→将軍直接通信禁止 | なし | なし | 階層制限 | なし |

## 7. 安全防御

| 観点 | われら | ACE | Vercel | おしお(元祖) | Claude Teams |
|------|--------|-----|--------|-------------|-------------|
| **破壊操作** | D001-D008(絶対禁止8項目) | なし | Sandbox検証 | 切腹ルール | Hooks |
| **越権防止** | 鎖の原理(構造的強制) | なし | Human-in-loop | 階層制 | Plan Approval |
| **WSL2保護** | /mnt/c配下の操作制限 | 対象外 | 対象外 | — | 対象外 |
| **神速停止** | cmd_halt(即時全停止) | なし | なし | — | shutdown_request |

## 8. 系譜図 — われらの立ち位置

```
                    ┌─────────────────────┐
                    │   おしお殿(元祖)      │
                    │ Claude Code×tmux     │
                    │ 戦国軍団メタファー     │
                    │ AI部下10人の組織論    │
                    └──────────┬──────────┘
                               │ fork
                               ↓
          ┌────────────────────────────────────────────┐
          │             われら(現行)                      │
          │                                              │
          │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
          │  │ACE思想    │  │Vercel式  │  │Claude    │  │
          │  │取込み     │  │取込み    │  │Teams     │  │
          │  │          │  │          │  │基盤活用  │  │
          │  │・Reflector│  │・2層圧縮 │  │・inbox   │  │
          │  │ 自動帰属 │  │・索引+   │  │・task    │  │
          │  │・dual    │  │ 詳細分離 │  │・nudge   │  │
          │  │ counter  │  │・受動    │  │          │  │
          │  │・全量注入│  │ ロード   │  │          │  │
          │  └──────────┘  └──────────┘  └──────────┘  │
          │                                              │
          │  ＋独自                                       │
          │  ・鎖の原理(4層階層統制)                        │
          │  ・GATE関所(BLOCK/CLEAR強制)                   │
          │  ・人間審査ゲート(家老)                         │
          │  ・8段階知識サイクル                            │
          │  ・D001-D008安全防御                           │
          │  ・陣形図による完全復帰                         │
          │  ・モデル混成(Opus/Codex)                      │
          │  ・連勝114の実戦実績                           │
          └────────────────────────────────────────────┘
```

## 9. 各者の強みとわれらの位置

| 次元 | 最強 | 理由 |
|------|------|------|
| **知識の深さ** | **われら** | 8段階サイクル+6層保存先。ACEは3段階、他はサイクルなし |
| **知識の自動進化** | **ACE** | 完全自動(人間不要)。われらは家老審査を**意図的に**残す(品質優先) |
| **コスト効率** | **Vercel** | 80%のツール削減で100%成功率。最小構成の極致 |
| **組織統制** | **われら** | 4層階層+鎖の原理。Claude Teamsは2層、ACEは役割分離のみ |
| **安全性** | **われら** | D001-D008+WSL2保護+越権構造防止。他は部分的またはなし |
| **復帰耐性** | **われら** | 陣形図+hook+inbox。Claude Teamsは再開不可、ACEはステートレス |
| **学術的定量性** | **ACE** | AppWorld/FiNER等のベンチマーク。われらは実戦データのみ |
| **並列スケール** | **Claude Teams** | 独立CTX窓で干渉なし。われらはファイル排他が必要 |
| **開発者体験** | **Vercel** | AI SDK 6の型安全+Registry。プログラマ向け最適化 |
| **実戦証明** | **われら** | 284/286cmd完了、連勝114、CLEAR率98%超 |

## 10. 結論 — われらが内包するもの

```
  ACEの思想       → 取込み済み(Reflector帰属、dual counter、全量注入)
  Vercelの構造    → 取込み済み(2層圧縮、受動ロード、索引+詳細分離)
  Claude Teamsの基盤 → 活用中(inbox、task YAML、nudge)
  おしお殿の原型  → 継承・発展(戦国メタファー、階層制、tmux×Claude Code)

  ＋ 独自の鎖(指揮系統)
  ＋ 独自の関所(GATE)
  ＋ 独自の安全防御(D001-D008)
  ＋ 独自の知識サイクル(8段階)
  ＋ 実戦で証明(連勝114)
```

殿の厳命「われらはACEもVercelもOpenClawも内包し上回る」——この対比図がその根拠となる。

---

## 参考文献

### ACE
- [ArXiv: Agentic Context Engineering (2510.04618)](https://arxiv.org/abs/2510.04618) — Stanford/SambaNova/UCB, ICLR 2026
- [GitHub: ACE Open-Source](https://github.com/ace-agent/ace)

### Vercel
- [We Removed 80% of Our Agent's Tools](https://vercel.com/blog/we-removed-80-percent-of-our-agents-tools)
- [What We Learned Building Agents at Vercel](https://vercel.com/blog/what-we-learned-building-agents-at-vercel)
- [How We Made v0 an Effective Coding Agent](https://vercel.com/blog/how-we-made-v0-an-effective-coding-agent)
- [AI SDK 6](https://vercel.com/blog/ai-sdk-6)
- [Context+](https://contextplus.vercel.app/)

### おしお殿(元祖)
- [Claude Codeで「AI部下10人」を作ったら...](https://zenn.dev/shio_shoppaize/articles/5fee11d03a11a1)
- [【続】Claude Codeマルチエージェント：v1.1.0で家老が切腹しかけた話](https://zenn.dev/shio_shoppaize/articles/8870bbf7c14c22)

### Claude Teams
- [Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
