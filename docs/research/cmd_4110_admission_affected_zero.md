# cmd_4110 affected=0 admission先取り解消

- 修正前: 才蔵実測 248.660秒。heavy-job admission待機後にselector 0件判定。
- 修正後: 1.81秒。terminal receipt `tests=0/0 skip=0`、admission marker 0件。
- 差分: 246.85秒短縮（99.3%）。
- 実装: `scripts/run_tests.sh`のself re-exec直前でaffected selectorを先行し、0件ならreceipt wrapper内return 0。非空結果は一時manifestへ固定し、admission後に再選択しない。
- 境界fixture: affected=0、affected>0、selector errorの3系統。0件のみadmission非発火、他2系統は従来admissionを維持。

結論: selector先行によりaffected=0の248秒admission待機を回避した。
