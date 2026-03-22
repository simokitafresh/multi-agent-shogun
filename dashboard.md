# 🏯 Dashboard [dm-signal] — 2026-03-23 03:20 更新

<!-- DASHBOARD_AUTO_START -->
## 📊 リアルタイム状況 (04:04 自動更新)

### 忍者配備
| 忍者 | モデル | 状態 | cmd | 内容 |
|------|--------|------|-----|------|
| 疾風 | claude-opus-4-6 high | 稼働中 | cmd_1298 | — |
| 影丸 | claude-opus-4-6 high | done | cmd_1299 | — |
| 半蔵 | claude-opus-4-6 high | done | cmd_1300 | — |
| 才蔵 | claude-opus-4-6 high | done | cmd_1296 | — |
| 小太郎 | claude-opus-4-6 high | 稼働中 | cmd_1297 | — |
| 飛猿 | claude-opus-4-6 high | done | cmd_1295 | — |

### CI Status
**CI RED: run 23403709313 — E2E Tests**

**WARN: 65件のcommit未push。`git push`を検討せよ**

### パイプライン
パイプライン空 — 次cmd待ち

### 戦況メトリクス
| 項目 | 値 |
|------|-----|
| cmd完了(GATE CLEAR) | 1053/1067 |
| 稼働忍者 | 5/8 (疾風, 影丸, 半蔵, 才蔵, 小太郎) |
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
| unknown | 55.5% | 92.9% | 227 |

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
| L074 | infra | 389 | 553 | 70.3% |
| L063 | infra | 264 | 512 | 51.6% |
| L225 | infra | 142 | 152 | 93.4% |
| L032 | infra | 87 | 215 | 40.5% |
| L097 | infra | 79 | 114 | 69.3% |

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
## 最新更新 (03:54更新)
- **cmd_1295**: 完了(GATE外)。飛猿PASS。軍師gate新設+archive preflight順序修正。commit cbbc98c+66b6f1b
- **cmd_1296**: 完了(GATE外)。才蔵PASS。ninja_monitor uncommittedチェック。commit 3d244de。⚠scope問題あり(後述)
- **cmd_1297**: 完了(GATE外)。小太郎PASS。教訓退役制度(--retire)。lesson_write.sh+deploy_task.sh
- **cmd_1298**: 完了(GATE外)。疾風PASS。Bash reportリダイレクト検出hook(GP-016)。commit a6c5851
- **cmd_1299**: 完了(GATE外)。影丸PASS。lesson_candidate reason品質gate(GP-019)
- **cmd_1300**: 完了(GATE外)。半蔵PASS。lesson_harvest.sh(GP-020)。commit fd9727c

### パイプライン
パイプライン空 — 次cmd待ち

### idle忍者
全6名idle

### 軍師GP総点検結果
- GP-003: **完了**(cmd_1294)
- GP-015: **完了**(cmd_1297 教訓退役)
- GP-016: **完了**(cmd_1298 Bash report hook)
- GP-017: **完了**(cmd_1293 テンプレート導線)
- GP-018: **完了**(cmd_1296 uncommittedチェック)⚠scope問題
- GP-019: **完了**(cmd_1299 L247 gate)
- GP-020: **完了**(cmd_1300 lesson harvest)

## 🚨要対応

### GATE/archive タイミング競合（未解決）
cmd_1295でpreflight flag順序修正したが、archive_completed.shがGATE中に報告をアーカイブする根本原因は未修正。cmd_1290-1300の11cmdが全てGATE外完了。**修正案**: cmd_complete_gate.sh内でarchive_completed.sh呼出しを報告存在チェック**後**に移動

### cmd_1296 uncommittedチェックのscope問題
git status --porcelainが全repo対象→忍者固有ファイルではなくdashboard等の運用ファイルでもブロック発動。修正案: task YAMLのfiles_modified対象のみチェック or 運用ファイル除外リスト

## 🔧 将軍へのcmd起票提案（家老自己研鑽より）

### workaround率構造的根絶

| # | 内容 | 状態 | cmd |
|---|------|------|-----|
| 1 | inbox_write.sh gate発火100%化 | **完了** | cmd_1264 |
| 2 | report_field_set.sh強制hook | **完了** | cmd_1265 |
| 3 | BLOCK昇格(PreToolUse deny) | **完了** | cmd_1284+1294 |

### 軍師利他サイクル5発見(S42)
- lesson_candidate登録率17.2%。GP-019(L247強制)/GP-020(async harvesting)要起票

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
