# おしお殿リポジトリ対比索引
<!-- last_updated: 2026-03-25 将軍調査(深掘り2巡目) -->

> 詳細: `docs/research/oshio-repo-comparison.md`
> 対象: yohey-w/multi-agent-shogun (フォーク元)
> 確認方法: gh apiで全コード直接取得・目視確認

## 結論

両リポジトリは同一forkベース。基盤コード共通。**独自進化の方向が根本的に異なる**:
- **おしお殿**: Multi-CLI対応(4CLI) + **Bloom Taxonomy DMR**(タスク複雑度→最安モデル自動ルーティング) + OSS公開体制(README 160KB+CONTRIBUTING+SECURITY)
- **我々**: Gate(22本)/Hook(13本)品質ゲート + 教訓自動注入 + 軍師レビュー + ninja_monitor + Vercelスタイル知識管理 + 全Opus統一(品質最優先)

## 最大の設計哲学差: Bloom Taxonomy DMR (§3.4)

おしお殿にあって我々に**完全にない**システム。4CLI×4モデルのコスト最適化ルーティング:
- L1-L3→Spark(chatgpt_pro)、L4→GPT-5.3、L5→Sonnet、L6→Opus
- 4Phase TDD(56TC) + 精度テスト(bloom_task_corpus 13.8KB) + 品質比較テスト
- 我々は全Opus統一→品質最優先・コスト度外視。DMRはコスト圧迫時の選択肢として記録

## 盗むべき技術（優先度順）

| P | 技術 | 工数 | 状況 | 詳細§ |
|---|------|------|------|-------|
| P1 | Stop Hook settings.json登録 | 極小 | **完了** | §6 |
| P2 | Stop Hookにinotifywait待機追加 | 小 | **完了** | §6 |
| P3 | Batch Processing Protocol | 小 | 実質対応済み(段階的チェックリスト) | §3.9 |
| P4 | ntfy_listener corrupt_dir防御 | 小 | **完了** | §3.10 |
| P5 | Screenshot skill (mask/trim) | 中 | 未着手 | §3.2 |
| P6 | Bloom Taxonomy DMR設計知見 | 設計参考 | コスト圧迫時の選択肢 | §3.4 |
| P7 | watcher_supervisor(inbox_watcher自動再起動) | 小 | **完了** | §3.3 |

## 実施済み修正（本セッション）

- **P1+P2**: Stop Hook settings.json登録+inotifywait 55秒待機。テスト7本PASS
- **P4**: ntfy_listener corrupt_dir防御(バックアップ→リセット)。テスト7本PASS
- **P7**: ninja_monitorにcheck_inbox_watcher_health()追加(pgrep生死監視+個別再起動)。テスト3本PASS
