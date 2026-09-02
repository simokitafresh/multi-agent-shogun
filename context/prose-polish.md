# prose-polish — 文章ブラッシュアップ(natural-japanese の先)

<!-- last_updated: 2026-09-02 将軍 初版(殿指示 18:19) -->

- 結論: natural-japanese の lint は **検出器**。評価関数にすると詩的散文が均される(findings 0 の版が最悪、findings 9 の版が「とてもよい」)。判定は詩の原理で行う → `skills/prose-polish/SKILL.md`
- 5 原理: 反復=韻律 / 句点連打=打撃音 / burstiness を長文で上げない / 呼吸=段落割り+全角スペース行 / 見出しは付けず場面転換は横線 → `docs/research/prose_polish_case_apartment_interest_20260902.md` §2
- 縦画面(スマホ)の設計: 転換点を独立行、息を置く場所に空白行、時間が跳ぶ場所に `---` → 同 §1 v2/v5
- 道具: `NOTE_DRAFT_PARAGRAPHS=1 bash scripts/note_draft.sh <md>`(段落余白を残す。既定は `<br>` 結合) / `Body: inserted N == Sections` で確認 → 同 §4
- 手順: v0 無修正保存+数値検算 → lint/terms/outline → 詩の原理で振り分け → **前作完成版と style_stats で「形」を突合(Step 2.5、殿 18:38『仮定の抜けが乖離を生む』)** → 呼吸設計 → 別下書きへ版ごとアップ → 殿の 1 指示=1 版 → 同 SKILL.md Step 0-5
- スタイル基準(殿の直近完成版 v5): 段落あたり 3.9 文 / 1 文段落 29% / 横線 8=時間の跳び / 空白 4=息 / 「」の後 。40% → `skills/prose-polish/scripts/style_stats.py`
- 事例: 相続税対策アパート×金利上昇(2026-09-02、v0→v5、殿の言葉と処置の時系列) → 同 §1
- 因果: `[[殿指示_note推敲_20260902]] -> [[lint最適化でインパクト消失_v1]] -> [[詩の原理で判定_v2-v5]] -> [[prose-polish]]`
- 関連: `skills/note-writer/SKILL.md` Step 3.5(lint 実行手順の正本)、`context/semantic-map.md` natural_japanese_lint / prose_polish
