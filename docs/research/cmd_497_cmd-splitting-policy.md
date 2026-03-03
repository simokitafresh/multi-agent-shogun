# cmd_497 CMD分離起票ポリシー（追加/修正混在検知）
<!-- cmd_497 | 2026-03-03 -->

## §1 結論

cmd受領時に「追加系」と「修正系」が同居していたら、家老は配備前に必ず2cmdへ分離する。

## §2 判定手順（いつ/何を見るか）

タイミング: `queue/shogun_to_karo.yaml` の新規cmdを読んだ直後（分解パターン選択前）。

1. `purpose` を確認し、追加語（新規作成/導入/追加）と修正語（修正/置換/削除/fix）の混在を判定
2. `command` を確認し、追加作業と修正作業の同居を判定
3. `acceptance_criteria` を確認し、追加成果物と修正成果物が同一cmdに混在していないか判定
4. 修正を含む場合は `fixes: cmd_XXX` の有無を確認（未記載は修正系要件不足）
5. 混在時は「追加cmd」「修正cmd」に分離し、必要なら `blocked_by` で順序制御

## §3 追加系cmdサンプル（新規作成のみ）

```yaml
- id: cmd_497_add_sample
  timestamp: "2026-03-03T16:05:00+09:00"
  purpose: "家老運用手順にCMD分離チェックの新規節を追加し、受領時チェックを標準化する"
  acceptance_criteria:
    - "context/karo-operations.md に新規節『cmd受領時のCMD分離チェック』が追加されている"
    - "既存節の修正を要求しない"
  command: "context/karo-operations.md に手順節を新規追加せよ"
  project: infra
  priority: high
  status: pending
```

## §4 修正系cmdサンプル（既存成果物の是正のみ）

```yaml
- id: cmd_497_fix_sample
  timestamp: "2026-03-03T16:10:00+09:00"
  purpose: "cmd_489で作成済みのreview手順の誤記を修正し、既存運用ドキュメントの整合を回復する"
  acceptance_criteria:
    - "context/karo-operations.md の既存『レビューサイクル』節の誤記が修正されている"
    - "新規ファイルの追加を要求しない"
  command: "既存レビュー手順の誤記のみを修正せよ"
  fixes: cmd_489
  project: infra
  priority: high
  status: pending
```

## §5 運用メモ

- 追加系cmdと修正系cmdを同一IDに混在させない
- 修正系cmdには `fixes` を必須で付与する
- 分離後は各cmdごとにpurpose validationを独立実施する
