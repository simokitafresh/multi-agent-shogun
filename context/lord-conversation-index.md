# Lord Conversation Index
<!-- last_updated: 2026-05-16 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-05-16T04:22:11+09:00 -->

## 最新やり取り（直近24h）
- 2026-05-16T04:22:11+09:00 | terminal | response | cmd書き上がった。cmd_publish.shでgate検証→昇格→委任を一括実行。 [meta] stop_reason=tool_use
- 2026-05-16T04:09:11+09:00 | terminal | inbound | y
- 2026-05-16T04:08:30+09:00 | terminal | response | 家老がtraining_codd結果を書き込み中。コミットする。 [meta] stop_reason=tool_use
- 2026-05-16T04:06:00+09:00 | terminal | session_summary | 本セッション: Simple-OCR構造化JSONパイプライン完成。(1)Stage 1.5: regex schedule検出+横向き画像対応(_detect_reading_axis)+ブロックフィルタ(_filter_non_med…
- 2026-05-16T04:05:34+09:00 | terminal | inbound | 今クリアされても今より強くてニューゲーム出来るようにせよ
- 2026-05-16T03:49:22+09:00 | terminal | response | セマンティックインデックス更新完了。殿の指示通りocr-engine-switching-design.mdも更新する。 [meta] stop_reason=tool_use
- 2026-05-16T03:46:55+09:00 | terminal | inbound | セマンティックインデックスも更新しよう
- 2026-05-16T03:46:51+09:00 | terminal | response | 記録完了。projects/simple-ocr.yaml全セクション更新済み（修正履歴13件、進行状態、実装履歴、コスト、次のアクション）。 殿、次の指示を。 [meta] stop_reason=tool_use
- 2026-05-16T03:45:36+09:00 | terminal | inbound | 記録したか？
- 2026-05-16T03:44:49+09:00 | terminal | response | push完了。本セッションの成果を整理する。 **本セッション成果:** - Stage 1.5: regex schedule検出 + 横向き画像対応 + ブロックフィルタリング - Stage 2: プロンプトv3（一般名除外/薬名結…

## 未解決確認事項
- 本セッション: Simple-OCR構造化JSONパイプライン完成。(1)Stage 1.5: regex schedule検出+横向き画像対応(_detect_reading_axis)+ブロックフィルタ(_filter_non_medical_blocks 12%削減) (…
- 正常。「6時間以上あけて」も正しく出力されている。メーカー名「トーワ」も除去済み。 殿、他に修正点があるか。なければRenderデプロイ完了を待って本番確認に進める。 [meta] stop_reason=end_turn
- 再確認しよう。6時間以上あけてはメーカー名ではないな
- simple-OCRに問題を見つけた。用法が「分3」などを理解せずに「3」だけが残っている。平山トミ 令和7年1月11日 塩島内科医院 Dr.塩島俊也 アジスロマイシン錠500mg「トーワ」 1 朝食後服用 3日分 ツムラ麦門冬湯エキス顆粒(医療用) 9g 3 毎食後服用 7日…
- **Simple-OCRリポジトリ状態：クリーン。** - 未コミット変更: なし - 未push: なし（origin/mainと同期済み） - untracked: `__pycache__/`等のビルド成果物 + `docs/api-setup-guide.md`（.gi…
- １－６まで3回連続成功を確認しよう
- **5問題中4つ修正完了:** - ✅ FIX1: dosageの「42日分」混入 → 解消 - ✅ FIX2: 薬名欠落 → 「デキストロメトルファン臭化水素酸塩錠15mg「トーワ」」正しく結合 - ✅ FIX3: noteの保管指導混入 → 解消 - ✅ FIX5: dru…
- 殿、新サンプル2枚の結果。 **sample3 (20250523): 横山優羽 — 烏山耳鼻咽喉科** | group | 薬 | schedule | |-------|---|----------| | 0 | 1.ルパフィン錠10mg + 2.モンテルカスト錠10mg …

## 殿の直近裁定・方針（直近24h）
- 2026-05-16T03:49:22+09:00 | セマンティックインデックス更新完了。殿の指示通りocr-engine-switching-design.mdも更新する。 [meta] stop_reason=tool_use
- 2026-05-16T03:46:51+09:00 | 記録完了。projects/simple-ocr.yaml全セクション更新済み（修正履歴13件、進行状態、実装履歴、コスト、次のアクション）。 殿、次の指示を。 [meta] stop_reason=tool_use
- 2026-05-16T03:44:49+09:00 | push完了。本セッションの成果を整理する。 **本セッション成果:** - Stage 1.5: regex schedule検出 + 横向き画像対応 + ブロックフィルタリング - Stage 2: プロンプトv3（一般名除外/薬名結合/duration区別/categor…
- 2026-05-16T03:41:15+09:00 | push完了。殿、フィルタの除去パターンは保守的に設定している。sample5（服薬指導が薬ブロックに混在）のようなケースでは安全側に倒して除去しない。サンプルが増えればパターンを拡充できる。 殿、次の指示を。 [meta] stop_reason=tool_use
- 2026-05-16T03:38:46+09:00 | push完了。殿、フィルタの除去パターンは保守的に設定している。sample5（服薬指導が薬ブロックに混在）のようなケースでは安全側に倒して除去しない。サンプルが増えればパターンを拡充できる。 殿、次の指示を。 [meta] stop_reason=tool_use
- 2026-05-16T03:22:11+09:00 | push完了。Renderに自動デプロイされる。デフォルトがtwo_stageになったので、本番でお薬手帳を撮影すれば構造化テキストが出る。 殿、次の指示を。 [meta] stop_reason=tool_use
- 2026-05-16T03:18:45+09:00 | push完了。殿の指示を。 [meta] stop_reason=end_turn
- 2026-05-16T03:16:09+09:00 | 6サンプル全てdaily_countが「1日N回」形式に修正済み。問題なし。 殿、次の指示を。 [meta] stop_reason=tool_use

## 参照cmd
- cmd_2784
- cmd_2788
- cmd_2789
- cmd_2790
- cmd_2791
- cmd_2792

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
