# heavy-job-admission test speed

- 対象: [[test_heavy_job_admission.bats]]
- 変更前: 25 PASS / 0 FAIL / 0 SKIP、9.272秒（`run_timed_bats.sh`）。
- 支配項: admission直列化の固定2秒待機と、修正前並走再現の固定1秒待機で計3.10秒。
- 改善: 固定時間待ちを開始・解放マーカーによる因果同期へ置換。期待値・対象件数は不変で、解放前の第2ジョブ未開始を直接検証する。
- 次候補: 分類器source反復の共有fixture化、hook payload/環境fixtureの共有cache化。
