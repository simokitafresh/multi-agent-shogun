# 我が軍 — 外部知見取込ログ

> 解釈層。外部システムや記事から我が軍へ取り込んだ設計・運用知見を時系列で残す。一次知識層の本文へは混ぜない。

## Timeline

| 日付 | 取込元 | 取込内容 | 我が軍での着地点 | 根拠 |
|------|--------|----------|------------------|------|
| 2026-03-13 | gstack | **8テクニック**: Suppressions, `stop_for/never_stop_for`, `scope_mode`, 推薦先行+WHY, Priority Hierarchy, Engineering Preferences, Temporal Interrogation, Two-pass Review | 偵察テンプレート、task YAML、`projects/{id}.yaml`, 家老レビュー基準へ反映 | cmd_927, `docs/research/gstack-analysis.md`, `docs/research/gyakusegawa-article-analysis.md` |
| 2026-03-13 | GSD | **4パターン**: Nyquist Validation, Requirements Traceability, Context Monitor, 4観点独立分析(Stack/Feat/Arch/Pit) | `SKIP=FAIL` 運用、AC/trace の厳格化、CTx 監視発想、GSD式4観点偵察 | `docs/research/system-comparison-2026-03-13.md`, `docs/research/systems-knowledge-base/systems/gsd.md` |
| 2026-03-13 | Vercel | 受動的知識配置、圧縮索引 + 詳細層の2層構造、agent-friendly retrieval 重視 | `AGENTS.md`/`CLAUDE.md`/`context/*.md` の圧縮索引設計、知識辞書の索引層 | `docs/research/system-comparison-2026-03-13.md`, `docs/research/systems-knowledge-base/guide.md` |
| 2026-03-13 | おしお殿 | Android App の運用面(SSH + 音声 + 8ペイン + dashboard + スクショ共有) | Android Companion App として継承・改良 | `docs/research/system-comparison-2026-03-13.md` |
| 2026-03-13〜2026-03-14 | 逆瀬川記事群 | Harness Engineering, AGENTS.md 生きたドキュメント, feedback speed hierarchy, Best-of-N 文脈整理 | AGENTS/CLAUDE 運用の再整理、記事由来概念の我が軍位置づけ確認 | `docs/research/gyakusegawa-article-analysis.md`, `sources/gyakusegawa.md` |
| 2026-03-13以降 | gstack 深掘り | wrapError, Named Invariants, Deferred Work Discipline など後続取込候補を抽出 | gate 出力の次行動化、命名された原則化、先送り理由保存の改善材料として保持 | `docs/research/gstack-deep-analysis.md` |
| 2026-04-16 | CoDD | **L3診断系**: Diagnose MANDATORY, Session State, DIVERGENT 発想, failure history 持越し | `gate_diagnose_check`, `session_state`, `previous_failures`, BLOCK 時の診断必須化 | cmd_1939-1942, `context/codd.md` |
| 2026-04-17 | Karpathy原則 | **2原則**: Think Before Coding, Simplicity First | `assumption_check`, `simplicity_check` を忍者報告・軍師レビューへ追加 | cmd_2019, `systems/karpathy-principles.md` |
| 2026-04-19 | mizchi記事群 | **3概念**: Programmer in the Loop（AIが実装・人間が設計/判断の協働モデル）, Document-First Development（docs/に仕様Markdown蓄積→AIが参照するパターン）, 漸進的権限委譲（default→auto-accept→plan mode→bypassの4段階） | task YAML の `never_stop_for` 設計・Document-First 原則・CLAUDE.md 二層運用の参照材料として保持 | cmd_2120, `sources/mizchi.md` |

## Notes

- 本ファイルは「何を採ったか」を記録する場所であり、各システムの原典説明は `systems/` または `sources/` を参照する
- 採用判断の詳細や未採用理由を増やす場合も、一次知識層の本文ではなくここへ追記する
