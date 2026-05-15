# Lord Conversation Index
<!-- last_updated: 2026-05-15 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-05-15T20:41:50+09:00 -->

## 最新やり取り（直近24h）
- 2026-05-15T20:41:50+09:00 | terminal | response | セマンティクスインデックス更新完了。 - `docs/semantic-index/index.md` に2概念追加（simple_ocr / kj_partshift） - `context/semantic-map.md` 自動再生成…
- 2026-05-15T20:40:50+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: dm-signal-core.md(15日),dm-signal-ops.md(15日),dm-signal-research.md(15日),dm-signal.md(15日),doc-style…
- 2026-05-15T20:40:40+09:00 | terminal | inbound | セマンティックインデックスも更新しよう
- 2026-05-15T20:40:18+09:00 | terminal | response | 本セッション全cmd CLEAR。 | cmd | 目的 | 状態 | |-----|------|------| | cmd_2776 | セマンティック辞書5概念追加 | **CLEAR** | | cmd_2777 | 高優先度60…
- 2026-05-15T20:40:03+09:00 | ntfy | outbound | 📊 Dashboard更新: 稼働1名 CLEAR率95% 連勝99
- 2026-05-15T20:38:30+09:00 | terminal | response | 完了。 | 成果物 | パス | |--------|------| | API取得ガイド | `/mnt/c/Python_app/Simple-OCR/docs/api-setup-guide.md` | | Gist | https…
- 2026-05-15T20:36:52+09:00 | terminal | inbound | claudeとGPTのAPI取得のステップバイステップをドキュメントにまとめて。最新情報が必須だね
- 2026-05-15T20:35:26+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: dm-signal-core.md(15日),dm-signal-ops.md(15日),dm-signal-research.md(15日),dm-signal.md(15日),doc-style…
- 2026-05-15T20:31:45+09:00 | terminal | response | バックグラウンドのCoDD extract完了。6層設計書が生成されている: ``` .codd/extract/ extract_result.yaml L1_data_models.md L2_api_endpoints.md L3_…
- 2026-05-15T20:31:27+09:00 | ntfy | outbound | 【家老】cmd_2780 初回配備開始 (title=強化 — Simple-OCRリポジトリ全体のCoDD brownfield設計書逆生成, ninja=saizo) 強化 📋 https://gist.github.com/simo…

## 未解決確認事項
- 完了。 | 成果物 | パス | |--------|------| | API取得ガイド | `/mnt/c/Python_app/Simple-OCR/docs/api-setup-guide.md` | | Gist | https://gist.github.com/s…
- https://github.com/simokitafresh/Simple-OCR、C:\Python_app\Simple-OCRを確認して。新しいプロジェクトだ
- 現物確認完了。両方動作している。 **cmd_2778**: L209-210にenvironment_changeテンプレートが注入済み。次のcmd起票時にEdit hookで自動表示される。 **cmd_2779**: L1471にBLOCK後の環境埋込み判定REMINDが…
- うまくどうさしているか確認して
- cmd_2775 GATE CLEAR（2回目通知）確認済み。殿の指示を待つ。 [meta] stop_reason=tool_use
- cmd_2775 GATE CLEAR確認。inbox処理完了。 殿、現況報告済み。cmd_2775の暗黒物質偵察がGATE CLEARした。高優先度60件のcontext可視化を進める方向で起票してよいか、殿の指示を待つ。 [meta] stop_reason=end_turn
- もう一度現況を確認せよ
- 掲示板確認7件完了。insights.yamlは存在する（257KB）。startup gateのmvエラーは一時ファイル問題。 **Step 10**: inbox処理済み（1件既読化完了）。 **Step 11**: 起動完了。禁則F001-F008確認済み。 --- 殿、…

## 殿の直近裁定・方針（直近24h）
- 2026-05-15T20:41:50+09:00 | セマンティクスインデックス更新完了。 - `docs/semantic-index/index.md` に2概念追加（simple_ocr / kj_partshift） - `context/semantic-map.md` 自動再生成済み - insights 1件自動解決…
- 2026-05-15T20:40:18+09:00 | 本セッション全cmd CLEAR。 | cmd | 目的 | 状態 | |-----|------|------| | cmd_2776 | セマンティック辞書5概念追加 | **CLEAR** | | cmd_2777 | 高優先度60関数context記載 | **CLEA…
- 2026-05-15T20:38:30+09:00 | 完了。 | 成果物 | パス | |--------|------| | API取得ガイド | `/mnt/c/Python_app/Simple-OCR/docs/api-setup-guide.md` | | Gist | https://gist.github.com/s…
- 2026-05-15T20:31:45+09:00 | バックグラウンドのCoDD extract完了。6層設計書が生成されている: ``` .codd/extract/ extract_result.yaml L1_data_models.md L2_api_endpoints.md L3_ui_pages.md L4_busin…
- 2026-05-15T20:31:24+09:00 | cmd_2780（Simple-OCR CoDD brownfield）家老に委任完了。忍者に配備される。 本セッション成果まとめ: | cmd | 目的 | 状態 | |-----|------|------| | cmd_2776 | セマンティック辞書5概念追加 | **…
- 2026-05-15T20:12:34+09:00 | はっ。Simple-OCRの現状を既に読み込んでいるので、設計書を出す。 --- ## OCRエンジン切替設計書 ### AsIs（現状） ``` スマホ撮影 → Base64送信 → Google Vision API (TEXT_DETECTION) → 生テキスト → 除…
- 2026-05-15T20:07:22+09:00 | お薬手帳のOCR精度問題、因果をたどる。 **根因**: Google Vision APIの`TEXT_DETECTION`は文字を検出するだけで**文書構造を理解しない**。段組み・表・枠線がある文書では読み取り順序が崩壊する。 **3つのアプローチ（効果順）**: ###…
- 2026-05-15T18:44:29+09:00 | プロジェクト登録完了。 | 登録先 | 内容 | |--------|------| | `config/projects.yaml` | id=kj-partshift エントリ追加 | | `projects/kj-partshift.yaml` | 核心知識(技術スタック…

## 参照cmd
- cmd_2722
- cmd_2746
- cmd_2760
- cmd_2761
- cmd_2762
- cmd_2763
- cmd_2764
- cmd_2765
- cmd_2766
- cmd_2767
- cmd_2768
- cmd_2769
- cmd_2770
- cmd_2771
- cmd_2772
- cmd_2773
- cmd_2774
- cmd_2775
- cmd_2776
- cmd_2777
- cmd_2778
- cmd_2779
- cmd_2780

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
