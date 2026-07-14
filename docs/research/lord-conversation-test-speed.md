# lord conversation Unit test speed

## 結論

[[test_lord_conversation.bats]] の21ケースで毎回起動していた `mktemp` を、Batsが各ケースへ提供する `BATS_TEST_TMPDIR` 配下の固定ディレクトリへ置換した。21/21 PASS、FAIL 0、SKIP 0を維持し、best-so-far 10.553秒に対して2 roundで6.881秒・6.675秒を記録した。

## 改善候補

1. 最高インパクト: `setup()` のcase単位`mktemp` forkを除去する。21ケースすべてで実行される固定費であり、[[test_lord_conversation.bats]] 11-12行の`BATS_TEST_TMPDIR`再利用へ変更した。
2. Python検証プロセスを集約する。JSONL assertionごとに個別`python3`を起動しており、WSL2上のprocess startup固定費が残る。
3. 500行JSONL fixtureを共有immutable baseから複製する。T-LC-008/009がほぼ同一fixtureを別々に生成している。

## 直接リンクと検証根拠

- 被テスト正本: [[lord_conversation.sh]] 15行 `append_lord_conversation() {`
- testから正本への導線: [[test_lord_conversation.bats]] 6行 `export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"`
- baseline incoming backlink: `causal_backlink_counts.sh --zero --limit 20`を実行し、対象testは候補外、zero候補1件を確認。
- baseline直接リンク: 新規文書作成前0件。変更後は上記2ファイルへの直接リンク2件。
- timing: before 7.074秒、after round 1=6.881秒、round 2=6.675秒。best-so-far 10.553秒未満。
