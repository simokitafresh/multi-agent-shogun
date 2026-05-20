# セマンティック監査 17スクリプト×2カテゴリ
<!-- generated: 2026-05-21T02:42:00+09:00 by gunshi idle analysis -->

## 対象
直近12hの変更スクリプト17件。2カテゴリ並列(silent_failure + side_effect)。

## 結果サマリ

| 分類 | 件数 | 備考 |
|------|------|------|
| P0 | 0 | 即時修正なし |
| P1 | 0 | 全件設計意図で降格 |
| P2 | 1 | knowledge_metrics regex偽陰性 |
| P3 | 3 | 非クリティカル |
| FP | 残り全件 | 設計意図通り |

## P1→降格の根拠

| スクリプト | パターン | 当初分類 | 降格理由 |
|-----------|---------|---------|---------|
| bulletin_write.sh:257 | `|| true` archive | P1 | archive=非クリティカル補助。次回再試行で自然回復 |
| causal_backlinks.sh:46 | `|| true + 2>/dev/null` | P1 | 情報表示のみ。skip許容設計 |
| prompt_state_inject.sh:332 | `set +e` timeout | P1 | hook never blocks user input。timeout→空結果→skip=正しい |
| gate_improvement_trigger.sh:195 | `send_alert || true` | P1 | 通知=非クリティカルパス |

## P2: knowledge_metrics.sh

箇所: L444-455 regex定義
```
_id_pat = re.compile(r'^- id:\s+(\S+)')
_id_inline_pat = re.compile(r'^- \{id:\s+(\S+)[,}]')
```
リスク: inline YAML辞書形式の一部フォーマットを取りこぼす可能性。
対処: 実害確認要。lessons.yamlのインデント/空白バリエーションとの突合。

## drift
semantic index file references: 0件MISSING。45概念全件実在。

## 付随作業
- gate_result重複22件清掃(414→392行)。根因=Phase2 sync重複実行(sort -u修正済み)
- CS WARN修正1件(consultation_L7_holes cs_checklist追記)
- insights: 5→3件pending(2件resolved: ノイズ+重複)
