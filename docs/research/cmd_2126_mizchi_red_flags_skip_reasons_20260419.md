# cmd_2126 skip reasons

- Pattern (5) 「メトリクスが良いから質的FBは無視」: LS046 で WARN スルー事故として既知化済みで、質的FB無視は教訓・レビュー経路で既に検出対象。
- Pattern (6) 「書き直した方が早い」: Session State + DIVERGENT 警告が `cmd_save.sh` に実装済みで、同一失敗の反復逃避は既に検出対象。
