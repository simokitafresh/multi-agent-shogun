# 🏯 Dashboard [dm-signal] — 2026-03-23 02:34 更新

<!-- DASHBOARD_AUTO_START -->
## 📊 リアルタイム状況 (02:33 自動更新)

### 忍者配備
| 忍者 | モデル | 状態 | cmd | 内容 |
|------|--------|------|-----|------|
| 疾風 | claude-opus-4-6 high | done | cmd_1281 | — |
| 影丸 | claude-opus-4-6 high | done | cmd_1285 | — |
| 半蔵 | claude-opus-4-6 high | done | cmd_1284 | — |
| 才蔵 | claude-opus-4-6 high | idle | cmd_1281 | — |
| 小太郎 | claude-opus-4-6 high | idle | — | — |
| 飛猿 | claude-opus-4-6 high | done | cmd_1282 | — |

### CI Status
**CI RED: run 23403709313 — E2E Tests**

**WARN: 23件のcommit未push。`git push`を検討せよ**

### パイプライン
パイプライン空 — 次cmd待ち

### 戦況メトリクス
| 項目 | 値 |
|------|-----|
| cmd完了(GATE CLEAR) | 1049/1056 |
| 稼働忍者 | 2/8 (影丸, 半蔵) |
| 連勝(CLEAR streak) | 48 (cmd_1235〜cmd_1284) |

### モデル別スコアボード
| モデル | CLEAR率 | impl率 | 傾向 | N |
|--------|---------|--------|------|---|
| Opus 4.6 high | 100.0% | 100.0% | → | 329 |

### 知識サイクル健全度
| 項目 | 値 |
|------|-----|
| 教訓注入率 | 75.2% |
| 教訓効果率 | 57.2% |
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
| unknown | 54.2% | 97.4% | 216 |

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
| L074 | infra | 380 | 544 | 69.9% |
| L063 | infra | 258 | 503 | 51.3% |
| L225 | infra | 133 | 143 | 93.0% |
| L032 | infra | 87 | 215 | 40.5% |
| L097 | infra | 78 | 112 | 69.6% |

Bottom 5 低効果教訓
| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |
|------|----|----------|----------|--------|
| L039 | dm-signal | 0 | 2 | 0.0% |
| L115 | infra | 0 | 2 | 0.0% |
| L027 | dm-signal | 0 | 1 | 0.0% |
| L062 | infra | 0 | 1 | 0.0% |
| L111 | infra | 0 | 1 | 0.0% |

### Context鮮度警告
なし

### 戦果（直近5件）
| cmd | 内容 | 結果 | 完了日時 |
|-----|------|------|----------|
| cmd_1284 | — | GATE CLEAR | 03-23 02:33 |
| cmd_1283 | — | GATE CLEAR | 03-23 02:29 |
| cmd_1281 | — | GATE CLEAR | 03-23 02:17 |
| cmd_1280 | — | GATE CLEAR | 03-23 02:04 |
| cmd_1282 | — | GATE CLEAR | 03-23 01:55 |

> 過去の戦果は archive/dashboard/ を参照
<!-- DASHBOARD_AUTO_END -->

<!-- KARO_SECTION_START -->
## 最新更新 (02:22更新)
- **cmd_1284**: 完了。 — dashboard.md🚨要対応セクション清掃+pre-write-read-tracker.shのreport YAML直接Edit BLOCK復元。半蔵完遂
- **cmd_1283**: 完了。 — lesson_update_score.shのCACHE_FILEをlessons_archive.yamlに切替え+フォールバック追加。索引(lessons.yaml)のmtime不変を検証済み。影丸完遂
- **cmd_1281**: **GATE CLEAR**。核心知識Vercel化。二重配備(小太郎+疾風)発生もファイル破損なし

### パイプライン
| cmd | 忍者 | 内容 | 状態 |
|-----|------|------|------|
| cmd_1283 | 影丸 | lesson_update_score.sh書込先修正 | 影丸PASS/**軍師RV中** |
| cmd_1284 | 未配備 | 🚨要対応清掃+BLOCK昇格 | 配備準備中 |

### idle忍者
影丸/半蔵/飛猿/才蔵/小太郎/疾風(6名idle)

### 二重配備LK009 — サイクル2完了(殿指示)
サイクル1: 3層の穴特定。サイクル2: STALL通知=信号≠事実。検証なし即再配備=「想像するな確認せよ」違反。karo.md手順改訂済み(検証→クリア→再配備)。構造的解決(deploy_task重複ガード)はcmd待ち

### 軍師分析(S27-S36)
- **GP-003**(PreToolUse DENY): workaround48.6%の根源。実装設計完了。**cmd起票推奨**
- GP-014(report前git status gate): commit/file層35%カバー。**cmd起票推奨**

## 🚨要対応
（なし）

## 🔧 将軍へのcmd起票提案（家老自己研鑽より）

### workaround率構造的根絶

| # | 内容 | 状態 | cmd |
|---|------|------|-----|
| 1 | inbox_write.sh gate発火100%化 | **GATE CLEAR** | cmd_1264 |
| 2 | report_field_set.sh強制hook | **GATE CLEAR** | cmd_1265 |
| 3 | BLOCK昇格(PreToolUse deny復元) | **cmd_1284** | cmd_1284 |

### deploy高速化 — 軍師GP-006

| # | 内容 | 状態 | cmd |
|---|------|------|-----|

## 将軍宛報告
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
