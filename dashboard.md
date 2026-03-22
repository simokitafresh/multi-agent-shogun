# 🏯 Dashboard [dm-signal] — 2026-03-23 03:20 更新

<!-- DASHBOARD_AUTO_START -->
## 📊 リアルタイム状況 (03:28 自動更新)

### 忍者配備
| 忍者 | モデル | 状態 | cmd | 内容 |
|------|--------|------|-----|------|
| 疾風 | claude-opus-4-6 high | done | cmd_1292 | — |
| 影丸 | claude-opus-4-6 high | 稼働中 | cmd_1293 | — |
| 半蔵 | claude-opus-4-6 high | done | cmd_1294 | — |
| 才蔵 | claude-opus-4-6 high | done | cmd_1289 | — |
| 小太郎 | claude-opus-4-6 high | done | cmd_1290 | — |
| 飛猿 | claude-opus-4-6 high | done | cmd_1288 | — |

### CI Status
**CI RED: run 23403709313 — E2E Tests**

**WARN: 42件のcommit未push。`git push`を検討せよ**

### パイプライン
パイプライン空 — 次cmd待ち

### 戦況メトリクス
| 項目 | 値 |
|------|-----|
| cmd完了(GATE CLEAR) | 1053/1063 |
| 稼働忍者 | 2/8 (影丸, 半蔵) |
| 連勝(CLEAR streak) | 0 |

### モデル別スコアボード
| モデル | CLEAR率 | impl率 | 傾向 | N |
|--------|---------|--------|------|---|
| Opus 4.6 high | 100.0% | 100.0% | → | 329 |

### 知識サイクル健全度
| 項目 | 値 |
|------|-----|
| 教訓注入率 | 75.2% |
| 教訓効果率 | 56.8% |
| 効果率閾値 | OK (0.0%, 0/0, 30cmd) |
| 問題教訓 | 0件 |

#### PJ別
| PJ | 注入率 | 効果率 | N |
|----|--------|--------|---|
| infra | 77.6% | 99.6% | 312 |
| dm-signal | 62.2% | 100.0% | 267 |
| auto-ops | 82.1% | 100.0% | 56 |
| google-classroom | 66.7% | 100.0% | 3 |
| database | 0.0% | — | 1 |
| unknown | 54.7% | 95.9% | 223 |

#### タスク種別別
| task_type | 注入 | スキップ | 注入率 | N |
|-----------|------|---------|--------|---|
| implement | 964 | 0 | 100% | 964 |
| recon | 187 | 325 | 37% | 512 |
| review | 484 | 0 | 100% | 484 |
| scout | 18 | 32 | 36% | 50 |

#### モデル別
| モデル | 参照率 | 効果率 | N |
|--------|--------|--------|---|
| Opus 4.6 high | 83.3% | 100.0% | 308 |

#### 教訓ランキング
Top 5 有効教訓
| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |
|------|----|----------|----------|--------|
| L074 | infra | 385 | 549 | 70.1% |
| L063 | infra | 263 | 508 | 51.8% |
| L225 | infra | 138 | 148 | 93.2% |
| L032 | infra | 87 | 215 | 40.5% |
| L097 | infra | 79 | 113 | 69.9% |

Bottom 5 低効果教訓
| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |
|------|----|----------|----------|--------|
| L039 | dm-signal | 0 | 2 | 0.0% |
| L113 | infra | 0 | 2 | 0.0% |
| L115 | infra | 0 | 2 | 0.0% |
| L263 | infra | 0 | 2 | 0.0% |
| L027 | dm-signal | 0 | 1 | 0.0% |

### Context鮮度警告
なし

### 戦果（直近5件）
| cmd | 内容 | 結果 | 完了日時 |
|-----|------|------|----------|
| cmd_1291 | — | GATE CLEAR | 03-23 03:19 |
| cmd_1288 | — | GATE CLEAR | 03-23 03:05 |
| cmd_1286 | — | GATE CLEAR | 03-23 02:52 |
| cmd_1285 | — | GATE CLEAR | 03-23 02:37 |
| cmd_1284 | — | GATE CLEAR | 03-23 02:33 |

> 過去の戦果は archive/dashboard/ を参照
<!-- DASHBOARD_AUTO_END -->

<!-- KARO_SECTION_START -->
## 最新更新 (03:28更新)
- **cmd_1290**: 完了。小太郎PASS。Gate8にinsights自動アーカイブ追加。workaround: no
- **cmd_1291**: 完了。影丸PASS。archive_reportsにreview_gate.doneチェック追加。workaround: no
- **cmd_1292**: 完了。疾風PASS。ninja_monitor report存在チェック追加。workaround: no
- **cmd_1293**: 完了。影丸PASS(軍師APPROVE)。CLAUDE.md Step 4.5追加(GP-017)。workaround: no
- **cmd_1294**: 完了。半蔵PASS。PreToolUse DENYフック実装(GP-003完遂)。workaround: no

### パイプライン
パイプライン空 — 次cmd待ち

### idle忍者
疾風/影丸/半蔵/才蔵/小太郎/飛猿(6名idle)

### 軍師GP総点検結果
- GP-003: **完了**(cmd_1284+cmd_1294 PreToolUse DENY実装)
- GP-014: **完了**(cmd_1286)
- GP-012: **完了**(cmd_1287)
- GP-004: **完了**(cmd_1288)
- GP-011: **完了**(cmd_1289)
- GP-017: **完了**(cmd_1293 テンプレート導線修復)

## 🚨要対応

### GATE/archive preflightタイミング競合
deploy_task.shがdeploy時にreview_gate.doneを事前生成→cmd_1291のarchive_reportsがreview_gate.done存在=レビュー完了と判定→preflightで報告YAMLをアーカイブ→直後のGATEが報告不在でBLOCK。cmd_1290/1292/1293で発生。家老検証+軍師LGTMで完了処理済みだがGATE経由ではない。**修正案**: (A) review_gate.doneのdeploy時事前生成を廃止しレビュー完了時にのみ作成 or (B) cmd_complete_gate.sh内のarchive preflightを報告存在チェック後に移動

## 🔧 将軍へのcmd起票提案（家老自己研鑽より）

### workaround率構造的根絶

| # | 内容 | 状態 | cmd |
|---|------|------|-----|
| 1 | inbox_write.sh gate発火100%化 | **完了** | cmd_1264 |
| 2 | report_field_set.sh強制hook | **完了** | cmd_1265 |
| 3 | BLOCK昇格(PreToolUse deny) | **完了** | cmd_1284+1294 |
| 4 | テンプレート導線修復(GP-017) | **完了** | cmd_1293 |
| 5 | GATE/archive timing修正 | **要起票** | — |

### deploy高速化 — 軍師GP-006

| # | 内容 | 状態 | cmd |
|---|------|------|-----|

## 将軍宛報告
- [INSIGHT] cmd_1286 hayate: LC: target_path/filesなしタスクではgit uncommittedチェックがスキップされる
- [INSIGHT] cmd_1285 kagemaru: LC: 運用YAMLファイルはYAML構造破損を前提にfallback parser設計必須
- [INSIGHT] cmd_1281 hayate: LC: Vercel化は分割先ファイルの既存内容と前任作業状況を先に確認せよ
- [INSIGHT] cmd_1281 saizo: LC: Vercel分割後のcontext参照先更新
- [INSIGHT] cmd_1280 hanzo: LC: Vercel化後の消費者スクリプトarchive参照切替が必要 / DC: 消費者スクリプトのarchive参照切替cmd
- [INSIGHT] cmd_1280 kagemaru: LC: lesson_update_score.shの書込先がindex(lessons.yaml)のままでblock-style書き戻しが発生する
- [INSIGHT] cmd_1277 kagemaru: LC: PostToolUse hook SKIPカウントの誤検知
- [INSIGHT] cmd_1275 kagemaru: DC: 削除済みスクリプトを参照する27ファイルの整理要否
- [INSIGHT] cmd_1274 hanzo: LC: タスクYAMLの認証情報を盲信せず.envで確認すべき
- [INSIGHT] cmd_1272 tobisaru: LC: standard PF登録時のmomentum_methodデフォルト
- [INSIGHT] cmd_1271 kotaro: LC: selection-based FoF初月のmonthly_returns.holding_signal=NULL問題
- [INSIGHT] cmd_1270 saizo: LC: selection付きFoFのinit月はholding_signal=Noneで独立検証不可
- [INSIGHT] cmd_1269 kagemaru: LC: selection-block FoFは本番holding_signalベースで検証可。Cash月はスキップ / DC: selection_blocks付き18体のFoFパリティ検証方針
- [INSIGHT] cmd_1269 kagemaru: LC: selection-block FoFは本番holding_signalベースで検証可。Cash月はスキップ / DC: selection_blocks付き18体のFoFパリティ検証方針
- [INSIGHT] cmd_1272 tobisaru: LC: standard PF登録時のmomentum_methodデフォルト
- [INSIGHT] cmd_1271 kotaro: LC: selection-based FoF初月のmonthly_returns.holding_signal=NULL問題
- [INSIGHT] cmd_1270 saizo: LC: selection付きFoFのinit月はholding_signal=Noneで独立検証不可
- **[CRITICAL] cmd_1272 飛猿PASS**: L1シン四神12体登録スクリプト完成。33体登録クリティカルパスのL1部分完了
- **[CRITICAL] cmd_1273 疾風PASS**: ランブックv2全6参照一致+PF枠76空き+admin認証OK。登録環境Ready
- [INSIGHT] FoFパリティ総合(cmd_1269+1270+1271): **21体中12PASS/9FAIL**。全FAILはinit月hs=NULLのみ。非init月100%一致。selection-block FoFも本番hs経由で検証成功
- [INSIGHT] cmd_1269 影丸(再検証): LC: selection-block FoFは本番holding_signalベースで検証可。Cash月はスキップ
- [INSIGHT] cmd_1269 影丸: DC: selection_blocks付き18体のFoFパリティ検証方針→将軍裁定要
- [INSIGHT] cmd_1272 飛猿: LC: standard PFのmomentum_methodはデフォルト依存せず明示指定推奨
- [INSIGHT] cmd_1265 半蔵: LC: PostToolUse hookはdeny不可。WARN/BLOCK切替はPreToolUse deny有無で制御
- **[CRITICAL] 6cmd全完了(1265/1269-1273)**: 5cmd GATE CLEAR + 1cmd(1269)軍師RV中
- cmd_1234〜1261のINSIGHT 17件: 全件教訓登録済み(L461-L478)
- lesson健全性: OK(未振り分け0件)
